--!strict

------------------------------ Module ------------------------------

local function Main()
	local Comparison = {}
	local MAX_BYTES = 48 * 1024
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
	local function failure(value)
		return prefix(tostring(value), 160)
	end
	local function integer(value, default, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum,
			"INVALID_ARGUMENT: bounded positive integer required"
		)
		return value
	end
	function Comparison.Create(c)
		local registry, codec = c.Registry, c.Codec
		local dead = false
		local result = { Commands = {} }
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		local function alive(check)
			assert(not dead and (not check or check()), "CANCELLED: structural inspection ended")
		end
		local function identity(object)
			local name = object.Name
			return {
				id = registry:Id(object),
				name = prefix(name, 256),
				nameTruncated = #name > 256,
				className = object.ClassName,
			}
		end
		local function output(kind)
			return {
				scope = "client",
				kind = kind,
				coverage = {
					truncated = false,
					resultByteLimit = MAX_BYTES,
					nonAtomic = true,
				},
			}
		end
		local function append(out, key, row)
			if size(out) + size(row) > MAX_BYTES - 1024 then
				out.coverage.truncated = true
				out.coverage.reason = "result_byte_limit"
				return false
			end
			out[key][#out[key] + 1] = row
			return true
		end
		local function read(callback)
			local ok, value = pcall(function()
				local raw = callback()
				assert(type(raw) ~= "string" or #raw <= 2048, "VALUE_LIMIT: string exceeds comparison field budget")
				local encoded = codec:Encode(raw)
				assert(
					not (
							type(encoded) == "table"
							and (encoded.type == "Unsupported" or encoded.type == "TruncatedString")
						),
					"UNSUPPORTED_VALUE: field cannot be compared"
				)
				assert(size(encoded) <= 4096, "VALUE_LIMIT: field exceeds comparison budget")
				return encoded
			end)
			return ok, value
		end
		local function compared(name, leftGetter, rightGetter)
			local a, left = read(leftGetter)
			local b, right = read(rightGetter)
			local row = { name = name, status = "unavailable", errors = {} }
			if a then
				row.left = left
			else
				row.errors.left = failure(left)
			end
			if b then
				row.right = right
			else
				row.errors.right = failure(right)
			end
			if a and b then
				row.status = equal(left, right) and "equal" or "different"
			end
			return row
		end
		local function canonical(className)
			local found, seen = {}, {}
			while className and not seen[className] do
				seen[className] = true
				local class = c.Apps.ReflectionService.GetClass(className)
				if not class then
					break
				end
				for _, member in pairs(class.Properties or {}) do
					local name, tags = member.Name, member.Tags or {}
					local security = member.Security
					local readSecurity = type(security) == "table" and security.Read
						or type(security) == "string" and security
						or nil
					if
						type(name) == "string"
						and name:match("^%u")
						and name ~= "Source"
						and not tags.Deprecated
						and not tags.Hidden
						and not tags.NotScriptable
						and (not readSecurity or readSecurity == "None")
					then
						found[name] = true
					end
				end
				className = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
			end
			return found
		end
		add("compare_instances", function(args)
			alive()
			local left, right = registry:Resolve(args.leftId), registry:Resolve(args.rightId)
			for _, key in ipairs({ "includeAttributes", "includeTags" }) do
				assert(args[key] == nil or type(args[key]) == "boolean", "INVALID_ARGUMENT: boolean required")
			end
			local wanted = args.properties
			local omitted = 0
			if wanted == nil then
				wanted = {}
				local first, second = canonical(left.ClassName), canonical(right.ClassName)
				for name in pairs(first) do
					if second[name] then
						wanted[#wanted + 1] = name
					end
				end
				table.sort(wanted)
				omitted = math.max(0, #wanted - 32)
				while #wanted > 32 do
					table.remove(wanted)
				end
			else
				assert(
					type(wanted) == "table" and #wanted >= 1 and #wanted <= 32,
					"INVALID_ARGUMENT: choose 1 to 32 properties"
				)
				for _, key in ipairs(wanted) do
					assert(
						type(key) == "string" and #key > 0 and #key <= 128,
						"INVALID_ARGUMENT: bounded property name required"
					)
					assert(key ~= "Source", "UNSUPPORTED: use explicit script-source tools for Source")
				end
			end
			local out = output("instance_comparison")
			out.left = identity(left)
			out.right = identity(right)
			out.properties = {}
			out.attributes = {}
			out.counts = { equal = 0, different = 0, unavailable = 0 }
			out.coverage.defaultPropertiesOmitted = omitted
			if omitted > 0 then
				out.coverage.truncated = true
			end
			out.note =
				"Native GetAttributes/GetTags materialize their immediate results before Lua field/name caps. No script source is read."
			local function keep(key, row)
				if not append(out, key, row) then
					return false
				end
				out.counts[row.status] += 1
				return true
			end
			for _, key in ipairs(wanted) do
				local row = compared(key, function()
					assert(
						c.Apps.ReflectionService.GetProperty(left.ClassName, key),
						"INVALID_PROPERTY: property not declared on left class"
					)
					return left[key]
				end, function()
					assert(
						c.Apps.ReflectionService.GetProperty(right.ClassName, key),
						"INVALID_PROPERTY: property not declared on right class"
					)
					return right[key]
				end)
				if not keep("properties", row) then
					break
				end
			end
			if args.includeAttributes ~= false and out.coverage.reason ~= "result_byte_limit" then
				local leftOk, leftValues = pcall(left.GetAttributes, left)
				local rightOk, rightValues = pcall(right.GetAttributes, right)
				out.attributeErrors = {}
				if not leftOk then
					out.attributeErrors.left = failure(leftValues)
				end
				if not rightOk then
					out.attributeErrors.right = failure(rightValues)
				end
				local names, seen = {}, {}
				out.coverage.attributeEntryScanLimitPerSide = 128
				out.coverage.attributeEntriesExamined = 0
				local function collect(values)
					local count = 0
					for key in pairs(values) do
						count += 1
						out.coverage.attributeEntriesExamined += 1
						if count > 128 then
							out.coverage.truncated = true
							out.coverage.attributeScanLimitReached = true
							break
						end
						if not seen[key] then
							seen[key] = true
							names[#names + 1] = key
						end
					end
				end
				if leftOk then
					collect(leftValues)
				end
				if rightOk then
					collect(rightValues)
				end
				table.sort(names)
				if #names > 128 then
					out.coverage.truncated = true
				end
				if out.coverage.attributeScanLimitReached then
					out.coverage.attributeNamesOmittedAtLeast = math.max(1, #names - 128)
				elseif #names > 128 then
					out.coverage.attributeNamesOmitted = #names - 128
				end
				for index = 1, math.min(#names, 128) do
					local key = names[index]
					local row = compared(key, function()
						assert(leftOk, failure(leftValues))
						return leftValues[key]
					end, function()
						assert(rightOk, failure(rightValues))
						return rightValues[key]
					end)
					if not keep("attributes", row) then
						break
					end
				end
			end
			if args.includeTags ~= false and out.coverage.reason ~= "result_byte_limit" then
				local function tags(object)
					local values = c.service.CollectionService:GetTags(object)
					assert(
						type(values) == "table" and #values <= 128,
						"VALUE_LIMIT: tags exceed comparison field count"
					)
					table.sort(values)
					return values
				end
				local row = compared("tags", function()
					return tags(left)
				end, function()
					return tags(right)
				end)
				if size(out) + size(row) <= MAX_BYTES - 1024 then
					out.tags = row
					out.counts[row.status] += 1
				else
					out.coverage.truncated = true
					out.coverage.reason = "result_byte_limit"
				end
			end
			out.coverage.estimatedBytes = size(out)
			return out
		end)
		local function walk(root, maximum, check, out, visit)
			local queue = { { Object = root, Depth = 0 } }
			local first, last = 1, 1
			local visited = {}
			local function inScope(object)
				return registry:Allowed(object) and (object == root or object:IsDescendantOf(root))
			end
			while first <= last do
				alive(check)
				local item = queue[first]
				queue[first] = nil
				first += 1
				local object = item.Object
				if inScope(object) and not visited[object] then
					if item.Parent and object.Parent ~= item.Parent then
						out.coverage.truncated = true
						out.coverage.reparentedObjectsSkipped = (out.coverage.reparentedObjectsSkipped or 0) + 1
						continue
					end
					visited[object] = true
					out.coverage.nodesVisited += 1
					if visit(object, item.Depth, item.Parent) == false then
						return
					end
					if not inScope(object) then
						continue
					end
					local ok, children = pcall(object.GetChildren, object)
					if not ok then
						if
							not append(
								out,
								"errors",
								{ instance = identity(object), operation = "GetChildren", error = failure(children) }
							)
						then
							return
						end
					else
						local room = maximum - out.coverage.nodesVisited - (last - first + 1)
						for index = 1, math.min(#children, math.max(0, room)) do
							alive(check)
							local child = children[index]
							if inScope(child) and child.Parent == object and not visited[child] then
								last += 1
								queue[last] = { Object = child, Depth = item.Depth + 1, Parent = object }
							elseif not inScope(child) or child.Parent ~= object then
								out.coverage.truncated = true
								out.coverage.reparentedObjectsSkipped = (out.coverage.reparentedObjectsSkipped or 0) + 1
							end
						end
						if #children > math.max(0, room) then
							out.coverage.truncated = true
							out.coverage.nodeLimitReached = true
						end
					end
				elseif not inScope(object) then
					out.coverage.truncated = true
					out.coverage.outsideRootSkipped = (out.coverage.outsideRootSkipped or 0) + 1
				end
			end
		end
		local function job(run)
			assert(type(c.StartJob) == "function", "UNSUPPORTED: analysis jobs unavailable")
			return c.StartJob(function(check)
				alive(check)
				return run(check)
			end)
		end
		add("summarize_hierarchy", function(args)
			local root = registry:Resolve(args.rootId)
			local maximum = integer(args.maxNodes, 3000, 10000)
			local top = integer(args.topClasses, 20, 50)
			return job(function(check)
				local out = output("hierarchy_summary")
				out.root = identity(root)
				out.classes = {}
				out.duplicateNames = {}
				out.errors = {}
				out.totals = {
					instances = 0,
					parts = 0,
					models = 0,
					folders = 0,
					scripts = 0,
					localScripts = 0,
					moduleScripts = 0,
					maxDepth = 0,
				}
				out.coverage.nodesVisited = 0
				out.coverage.nodeLimit = maximum
				out.coverage.duplicateGroupLimit = 50
				out.coverage.duplicateEvidence = "visited_siblings_only"
				out.note =
					"Native GetChildren materializes each immediate child array before Lua caps queued/visited work. Duplicate groups describe only visited siblings."
				local counts, parents, duplicates = {}, {}, {}
				walk(root, maximum, check, out, function(object, depth, parent)
					local class = object.ClassName
					counts[class] = (counts[class] or 0) + 1
					local totals = out.totals
					totals.instances += 1
					totals.maxDepth = math.max(totals.maxDepth, depth)
					if object:IsA("BasePart") then
						totals.parts += 1
					end
					local counter = ({
						Model = "models",
						Folder = "folders",
						Script = "scripts",
						LocalScript = "localScripts",
						ModuleScript = "moduleScripts",
					})[class]
					if counter then
						totals[counter] += 1
					end
					if parent and registry:Allowed(parent) then
						local byName = parents[parent]
						if not byName then
							byName = {}
							parents[parent] = byName
						end
						local name = object.Name
						local group = byName[name]
						if not group then
							group = {
								parent = identity(parent),
								name = prefix(name, 256),
								nameTruncated = #name > 256,
								count = 0,
								sampleIds = {},
							}
							byName[name] = group
						end
						group.count += 1
						if #group.sampleIds < 4 then
							group.sampleIds[#group.sampleIds + 1] = registry:Id(object)
						end
						if group.count == 2 then
							duplicates[#duplicates + 1] = group
						end
					end
				end)
				local classes = {}
				for name, count in pairs(counts) do
					classes[#classes + 1] = { className = name, count = count }
				end
				table.sort(classes, function(a, b)
					return a.count == b.count and a.className < b.className or a.count > b.count
				end)
				out.distinctClasses = #classes
				out.classCountsOmitted = math.max(0, #classes - top)
				for index = 1, math.min(#classes, top) do
					if not append(out, "classes", classes[index]) then
						break
					end
				end
				table.sort(duplicates, function(a, b)
					return a.parent.id == b.parent.id and a.name < b.name or a.parent.id < b.parent.id
				end)
				out.duplicateGroupCount = #duplicates
				for index = 1, math.min(#duplicates, 50) do
					if not append(out, "duplicateNames", duplicates[index]) then
						break
					end
				end
				if #duplicates > 50 then
					out.coverage.truncated = true
					out.coverage.duplicateGroupsOmitted = #duplicates - 50
				end
				out.coverage.includesRoot = true
				out.coverage.estimatedBytes = size(out)
				return out
			end)
		end)
		local function linkKeys(object)
			local keys = {}
			local seen = {}
			local function addKey(key)
				if not seen[key] then
					seen[key] = true
					keys[#keys + 1] = key
				end
			end
			if object:IsA("ObjectValue") then
				addKey("Value")
			end
			if object:IsA("Model") then
				addKey("PrimaryPart")
			end
			if object:IsA("JointInstance") or object:IsA("WeldConstraint") then
				addKey("Part0")
				addKey("Part1")
			end
			if object:IsA("Constraint") or object:IsA("Beam") or object:IsA("Trail") then
				addKey("Attachment0")
				addKey("Attachment1")
			end
			if c.Apps.ReflectionService.GetProperty(object.ClassName, "Adornee") then
				addKey("Adornee")
			end
			return keys
		end
		add("validate_references", function(args)
			local root = registry:Resolve(args.rootId)
			local maximum = integer(args.maxNodes, 2000, 5000)
			local limit = integer(args.limit, 50, 100)
			return job(function(check)
				local out = output("structural_reference_candidates")
				out.root = identity(root)
				out.links = {}
				out.errors = {}
				out.coverage.nodesVisited = 0
				out.coverage.nodeLimit = maximum
				out.coverage.candidateLimit = limit
				out.coverage.linksChecked = 0
				out.coverage.insideRoot = 0
				out.note =
					"Known structural links only, not script references. Nil/outside-root links can be intentional, not proof of broken behavior. Native GetChildren creates immediate child arrays before Lua caps queued work."
				walk(root, maximum, check, out, function(object)
					local source = identity(object)
					for _, key in ipairs(linkKeys(object)) do
						alive(check)
						local row = { source = source, property = key, severity = "informational", candidate = true }
						if not registry:Allowed(object) or object ~= root and not object:IsDescendantOf(root) then
							row.status = "read_unavailable"
							row.severity = "unavailable"
							row.error = "STALE_INSTANCE: source left the inspected scope during inspection"
						else
							out.coverage.linksChecked += 1
							local ok, target = pcall(function()
								return object[key]
							end)
							if not ok then
								row.status = "read_unavailable"
								row.severity = "unavailable"
								row.error = failure(target)
							elseif target == nil then
								row.status = "nil"
								row.value = { type = "nil" }
							elseif typeof(target) ~= "Instance" then
								row.status = "unexpected_value"
								row.severity = "unavailable"
								row.error = "UNSUPPORTED_VALUE: structural link is not an Instance"
							elseif not registry:Allowed(target) then
								row.status = "target_unavailable"
								row.severity = "unavailable"
								local good, value = pcall(function()
									return {
										name = prefix(target.Name, 256),
										className = target.ClassName,
										available = false,
									}
								end)
								if good then
									row.target = value
								end
							elseif target ~= root and not target:IsDescendantOf(root) then
								row.status = "outside_root"
								row.target = identity(target)
							else
								out.coverage.insideRoot += 1
							end
						end
						if row.status then
							if #out.links >= limit then
								out.coverage.truncated = true
								out.coverage.reason = "candidate_limit"
								return false
							end
							if not append(out, "links", row) then
								return false
							end
						end
						if not registry:Allowed(object) or object ~= root and not object:IsDescendantOf(root) then
							return
						end
					end
				end)
				out.coverage.includesRoot = true
				out.coverage.estimatedBytes = size(out)
				return out
			end)
		end)
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Comparison
end
return { Main = Main }
