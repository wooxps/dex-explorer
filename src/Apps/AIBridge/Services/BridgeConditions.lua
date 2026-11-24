--!strict

------------------------------ Module ------------------------------

local function Main()
	local Conditions = {}
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local bytes = 2
		for key, item in pairs(value) do
			bytes += size(key) + size(item) + 2
		end
		return bytes
	end
	local function prefix(value, maximum)
		local length = math.min(#value, maximum)
		if length < #value then
			while length > 0 do
				local byte = value:byte(length + 1)
				if byte < 128 or byte >= 192 then
					break
				end
				length -= 1
			end
		end
		return value:sub(1, length)
	end
	local function equal(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for key, value in pairs(a) do
			if not equal(value, b[key]) then
				return false
			end
		end
		for key in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	local function only(value, keys)
		assert(type(value) == "table", "INVALID_ARGUMENT: object required")
		for key in pairs(value) do
			assert(keys[key], "INVALID_ARGUMENT: unsupported condition field")
		end
	end
	local function text(value, maximum)
		assert(type(value) == "string" and #value > 0 and #value <= maximum, "INVALID_ARGUMENT: bounded text required")
		return value
	end
	function Conditions.Create(c)
		local registry, codec = c.Registry, c.Codec
		local api = {}
		local function encode(value)
			local encoded = codec:Encode(value)
			assert(
				not (type(encoded) == "table" and (encoded.type == "Unsupported" or encoded.type == "TruncatedString")),
				"UNAVAILABLE_VALUE: value cannot be compared"
			)
			assert(size(encoded) <= 4096, "VALUE_LIMIT: condition value exceeds 4 KiB")
			return encoded
		end
		function api:Prepare(value)
			only(value, {
				kind = true,
				target = true,
				name = true,
				expected = true,
				op = true,
				tolerance = true,
				className = true,
			})
			local kind = value.kind
			assert(
				kind == "exists"
					or kind == "property"
					or kind == "attribute"
					or kind == "tag"
					or kind == "class"
					or kind == "child_count",
				"INVALID_ARGUMENT: unsupported condition kind"
			)
			local selector = value.target
			only(selector, { instanceId = true, rootId = true, path = true })
			local prepared = {
				kind = kind,
				op = value.op == nil and "eq" or value.op,
				name = value.name,
				className = value.className,
				tolerance = value.tolerance,
			}
			if selector.instanceId ~= nil then
				assert(
					selector.rootId == nil and selector.path == nil,
					"INVALID_ARGUMENT: choose an instanceId or rootId/path"
				)
				text(selector.instanceId, 32)
				prepared.target = { instanceId = selector.instanceId }
				local ok, object = pcall(registry.Resolve, registry, selector.instanceId)
				if ok then
					prepared.object = object
				else
					prepared.targetError = prefix(tostring(object), 200)
				end
			else
				text(selector.rootId, 32)
				assert(
					type(selector.path) == "table" and #selector.path <= 16,
					"INVALID_ARGUMENT: path requires at most 16 exact child names"
				)
				prepared.path = {}
				for _, segment in ipairs(selector.path) do
					prepared.path[#prepared.path + 1] = text(segment, 128)
				end
				prepared.target = { rootId = selector.rootId, path = prepared.path }
				local ok, root = pcall(registry.Resolve, registry, selector.rootId)
				if ok then
					prepared.root = root
				else
					prepared.targetError = prefix(tostring(root), 200)
				end
			end
			if kind == "exists" or kind == "tag" then
				assert(
					value.expected == nil or type(value.expected) == "boolean",
					"INVALID_ARGUMENT: expected must be boolean"
				)
				prepared.expected = value.expected ~= false
				assert(
					value.op == nil and value.tolerance == nil and value.className == nil,
					"INVALID_ARGUMENT: fields do not apply to this condition"
				)
				if kind == "tag" then
					prepared.name = text(value.name, 128)
				else
					assert(value.name == nil, "INVALID_ARGUMENT: name does not apply to exists")
				end
			elseif kind == "class" then
				prepared.className = text(value.className, 128)
				prepared.expected = prepared.className
				assert(
					value.expected == nil and value.name == nil and value.op == nil and value.tolerance == nil,
					"INVALID_ARGUMENT: fields do not apply to class condition"
				)
			else
				assert(value.expected ~= nil, "INVALID_ARGUMENT: expected is required; use typed nil for nil")
				assert(
					prepared.op == "eq"
						or prepared.op == "ne"
						or prepared.op == "lt"
						or prepared.op == "lte"
						or prepared.op == "gt"
						or prepared.op == "gte"
						or prepared.op == "contains",
					"INVALID_ARGUMENT: unsupported comparison operator"
				)
				prepared.expectedValue = codec:Decode(value.expected)
				prepared.expected = encode(prepared.expectedValue)
				if kind == "property" or kind == "attribute" then
					prepared.name = text(value.name, 128)
				else
					assert(
						type(prepared.expectedValue) == "number"
							and prepared.expectedValue % 1 == 0
							and prepared.expectedValue >= 0
							and prepared.expectedValue <= 10000
							and value.name == nil,
						"INVALID_ARGUMENT: child_count requires a count from 0 to 10000"
					)
				end
				assert(value.className == nil, "INVALID_ARGUMENT: className only applies to class conditions")
				if prepared.tolerance ~= nil then
					assert(
						type(prepared.tolerance) == "number"
							and prepared.tolerance >= 0
							and prepared.tolerance <= 1000000
							and (prepared.op == "eq" or prepared.op == "ne")
							and type(prepared.expectedValue) == "number",
						"INVALID_ARGUMENT: numeric equality tolerance required"
					)
				end
				if prepared.op == "contains" then
					assert(
						type(prepared.expectedValue) == "string" and kind ~= "child_count",
						"INVALID_ARGUMENT: contains requires string expected"
					)
				elseif prepared.op ~= "eq" and prepared.op ~= "ne" then
					assert(
						type(prepared.expectedValue) == "number",
						"INVALID_ARGUMENT: ordered comparisons require numeric expected"
					)
				end
			end
			assert(size(prepared.expected) <= 4096, "VALUE_LIMIT: expected value exceeds condition budget")
			return prepared
		end
		local function consume(budget, count)
			assert(count <= budget.remaining, "WORK_LIMIT: condition candidate budget exhausted; use an exact handle")
			budget.remaining -= count
		end
		local function locate(condition, budget)
			if condition.targetError then
				return nil, "unavailable", condition.targetError
			end
			local object = condition.object or condition.root
			if not registry:Allowed(object) then
				return nil, "missing", "Known target left the inspectable client session"
			end
			if condition.path then
				for _, segment in ipairs(condition.path) do
					local children = object:GetChildren()
					assert(#children <= 512, "WORK_LIMIT: path parent exceeds 512 children; use an exact handle")
					consume(budget, #children)
					local found
					for _, child in ipairs(children) do
						if registry:Allowed(child) and child.Name == segment then
							assert(not found, "AMBIGUOUS_TARGET: duplicate child names; use an exact handle")
							found = child
						end
					end
					if not found then
						return nil, "missing", "Exact child path is absent"
					end
					object = found
				end
			end
			return object, "present"
		end
		function api:Evaluate(condition, budget)
			budget = budget or { remaining = 4096 }
			local before = budget.remaining
			local observation = {
				kind = condition.kind,
				target = condition.target,
				name = condition.name,
				op = condition.op,
				tolerance = condition.tolerance,
				className = condition.className,
				expected = condition.expected,
				outcome = "unavailable",
				passed = false,
			}
			local ok, problem = pcall(function()
				local object, state, why = locate(condition, budget)
				observation.targetState = state
				if state == "unavailable" then
					observation.error = why
					return
				end
				local actual
				if condition.kind == "exists" then
					actual = state == "present"
				elseif state ~= "present" then
					observation.error = why
					return
				elseif condition.kind == "property" then
					assert(
						c.Apps.ReflectionService.GetProperty(object.ClassName, condition.name),
						"INVALID_PROPERTY: property is not declared"
					)
					actual = object[condition.name]
				elseif condition.kind == "attribute" then
					actual = object:GetAttribute(condition.name)
				elseif condition.kind == "tag" then
					actual = c.service.CollectionService:HasTag(object, condition.name)
				elseif condition.kind == "class" then
					actual = object:IsA(condition.className)
				else
					local children = object:GetChildren()
					assert(#children <= 1024, "WORK_LIMIT: child count exceeds 1024 native candidates")
					consume(budget, #children)
					actual = 0
					for _, child in ipairs(children) do
						if registry:Allowed(child) then
							actual += 1
						end
					end
				end
				observation.actual = encode(actual)
				if object then
					observation.instanceId = registry:Id(object)
				end
				local passed
				if condition.kind == "class" then
					passed = actual
				elseif condition.kind == "tag" or condition.kind == "exists" then
					passed = actual == condition.expected
				elseif condition.op == "eq" or condition.op == "ne" then
					if condition.tolerance ~= nil then
						assert(type(actual) == "number", "TYPE_MISMATCH: observed value is not numeric")
						passed = math.abs(actual - condition.expectedValue) <= condition.tolerance
					else
						passed = equal(observation.actual, condition.expected)
					end
					if condition.op == "ne" then
						passed = not passed
					end
				elseif condition.op == "contains" then
					assert(type(actual) == "string", "TYPE_MISMATCH: observed value is not text")
					passed = actual:find(condition.expectedValue, 1, true) ~= nil
				else
					assert(type(actual) == "number", "TYPE_MISMATCH: observed value is not numeric")
					if condition.op == "lt" then
						passed = actual < condition.expectedValue
					elseif condition.op == "lte" then
						passed = actual <= condition.expectedValue
					elseif condition.op == "gt" then
						passed = actual > condition.expectedValue
					else
						passed = actual >= condition.expectedValue
					end
				end
				observation.passed = passed
				observation.outcome = passed and "passed" or "failed"
				if condition.name then
					observation.name = condition.name
				end
				if condition.op then
					observation.op = condition.op
				end
			end)
			if not ok then
				observation.error = prefix(tostring(problem), 240)
			end
			observation.candidatesExamined = before - budget.remaining
			return observation
		end
		return api
	end
	Conditions.Size = size
	return Conditions
end
return { Main = Main }
