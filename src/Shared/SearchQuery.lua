--!strict

local API, service, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(data)
	API, service, Apps = data.API, data.service, data.Apps
end

------------------------------ Module ------------------------------

local function Main()
	local Search = {}
	local function searchObject(node)
		local virtual = { Name = node.Obj.Name, ClassName = node.InferredClass or "Unknown" }
		virtual.Parent = node.Parent and node.Parent.Obj
		function virtual:IsA(className)
			if className == "Instance" then
				return true
			end
			local class = API.Classes[self.ClassName]
			while class do
				if class.Name == className then
					return true
				end
				class = class.Superclass
				if type(class) == "string" then
					class = API.Classes[class]
				end
			end
			return false
		end
		return virtual
	end
	Search.Object = function(node)
		return (node.Inferred and not node.Materialized) and searchObject(node) or node.Obj
	end
	local literalTerms = setmetatable({}, { __mode = "k" })
	local classTerms = setmetatable({}, { __mode = "k" })
	local requiredClassTerms = setmetatable({}, { __mode = "k" })
	local nameIndex = Apps and Apps.SearchNameIndex and Apps.SearchNameIndex.Create()
	Search.NameIndex = nameIndex
	Search.LiteralTerms = function(predicate)
		local value = literalTerms[predicate]
		return type(value) == "string" and { value } or value
	end
	Search.ClassFilter = function(predicate)
		return classTerms[predicate]
	end
	Search.RequiredClassTerm = function(predicate)
		return requiredClassTerms[predicate]
	end
	Search.ClassNodeMatcher = function(predicate)
		local target = classTerms[predicate]
		if not target then
			return nil
		end
		local classes = {}
		return function(node)
			local object = node.Obj
			if typeof(object) == "Instance" and (not node.Inferred or node.Materialized) then
				local class = node.Class or object.ClassName
				local matches = classes[class]
				if matches ~= nil then
					return matches
				end
				local ok, value = pcall(predicate, object)
				if ok then
					classes[class] = value
					return value
				end
				return false
			end
			local ok, value = pcall(predicate, Search.Object(node))
			return ok and value
		end
	end
	local candidateCache = {}
	local candidateLower = {}
	local valueTypesByProperty
	local components = {
		x = "X",
		y = "Y",
		z = "Z",
		r = "R",
		g = "G",
		b = "B",
		position = "Position",
		orientation = "Orientation",
		magnitude = "Magnitude",
		scale = "Scale",
		offset = "Offset",
		min = "Min",
		max = "Max",
	}
	local unitComponents = { Vector2 = { "X", "Y" }, Vector3 = { "X", "Y", "Z" }, Color3 = { "R", "G", "B" } }
	local function compareNumber(actual, expected, op)
		if not expected then
			return false
		end
		if op == ">" then
			return actual > expected
		end
		if op == "<" then
			return actual < expected
		end
		if op == ">=" then
			return actual >= expected
		end
		if op == "<=" then
			return actual <= expected
		end
		if op == "~=" or op == "!=" then
			return actual ~= expected
		end
		return actual == expected
	end
	local function tokenize(query)
		local tokens, i = {}, 1
		while i <= #query do
			local c = query:sub(i, i)
			if c:match("%s") then
				i += 1
			elseif c == '"' then
				local chars, closed = {}, false
				i += 1
				while i <= #query do
					c = query:sub(i, i)
					if c == '"' then
						closed = true
						i += 1
						break
					end
					if c == "\\" and i < #query then
						i += 1
						c = query:sub(i, i)
					end
					chars[#chars + 1] = c
					i += 1
				end
				if not closed then
					error("Close the quotation mark", 0)
				end
				tokens[#tokens + 1] = { value = table.concat(chars), quoted = true }
			elseif c:match("[():=<>!]") or query:sub(i, i + 1) == "~=" then
				local op = c
				if query:sub(i + 1, i + 1) == "=" and c ~= "(" and c ~= ")" and c ~= ":" then
					op ..= "="
					i += 1
				end
				tokens[#tokens + 1] = { value = op }
				i += 1
			else
				local start = i
				while i <= #query and not query:sub(i, i):match('[%s():=<>!"]') and query:sub(i, i + 1) ~= "~=" do
					i += 1
				end
				tokens[#tokens + 1] = { value = query:sub(start, i - 1) }
			end
		end
		return tokens
	end

	local function contains(value, lowerQuery)
		return string.find(string.lower(tostring(value)), lowerQuery, 1, true) ~= nil
	end

	Search.Suggest = function(query, cursor)
		cursor = math.clamp(cursor or (#query + 1), 1, #query + 1)
		local before = query:sub(1, cursor - 1)
		local quoteStart, escaped = nil, false
		for index = 1, #before do
			local char = before:sub(index, index)
			if quoteStart and escaped then
				escaped = false
			elseif quoteStart and char == "\\" then
				escaped = true
			elseif char == '"' then
				quoteStart = if quoteStart then nil else index
			end
		end
		local key, op, prefix
		local quoted = quoteStart ~= nil
		if quoted then
			key, op = before:sub(1, quoteStart - 1):match("([%w_]+)%s*([:=]+)%s*$")
			if not key or key:lower() ~= "tag" then
				return nil
			end
			prefix = before:sub(quoteStart + 1):gsub("\\(.)", "%1")
		else
			key, op, prefix = before:match("([%w_]+)%s*([:=]+)%s*([%w_%.%-]*)$")
		end
		local cacheKey = key and (key:lower() .. op)
		local cached = cacheKey and candidateCache[cacheKey]
		local candidates, seen = {}, {}
		local function add(value)
			if not seen[value] then
				seen[value] = true
				candidates[#candidates + 1] = value
			end
		end
		if cached then
			candidates = cached
		elseif key and (key:lower() == "is" or key:lower() == "classname") and op == ":" then
			for name in pairs(API.Classes) do
				add(name)
			end
		elseif key and (op == "=" or op == "==") then
			if not valueTypesByProperty then
				valueTypesByProperty = {}
				for _, class in pairs(API.Classes) do
					for _, prop in pairs(class.Properties or {}) do
						if prop.ValueType then
							local name = prop.Name:lower()
							local types = valueTypesByProperty[name] or {}
							valueTypesByProperty[name] = types
							types[prop.ValueType.Category == "Enum" and prop.ValueType.Name or (prop.ValueType.Name == "bool" and "bool" or "")] =
								true
						end
					end
				end
			end
			for valueType in pairs(valueTypesByProperty[key:lower()] or {}) do
				if valueType == "bool" then
					add("false")
					add("true")
				elseif valueType ~= "" then
					local ok, items = pcall(function()
						return Enum[valueType]:GetEnumItems()
					end)
					if ok then
						for _, item in ipairs(items) do
							add(item.Name)
						end
					end
				end
			end
		elseif key and key:lower() == "tag" and op == ":" then
			local readable, tags = pcall(function()
				return service.CollectionService:GetAllTags()
			end)
			if readable and type(tags) == "table" then
				for _, tag in ipairs(tags) do
					if type(tag) == "string" then
						add(tag)
					end
				end
			end
		else
			return nil
		end
		if not cached then
			table.sort(candidates, function(a, b)
				return a:lower() < b:lower()
			end)
		end
		if cacheKey and key:lower() ~= "tag" and not cached then
			candidateCache[cacheKey] = candidates
		end
		local lowerCandidates = cached and candidateLower[cacheKey] or {}
		if not cached then
			for i, value in ipairs(candidates) do
				lowerCandidates[i] = value:lower()
			end
			if cacheKey and key:lower() ~= "tag" then
				candidateLower[cacheKey] = lowerCandidates
			end
		end
		local choices = {}
		local prefixLower = prefix:lower()
		for i, value in ipairs(candidates) do
			if lowerCandidates[i]:sub(1, #prefix) == prefixLower then
				if key:lower() == "tag" and (quoted or value:find("[^%w_%.%-]")) then
					value = '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
				end
				choices[#choices + 1] = value
			end
		end
		if #choices == 0 then
			return nil
		end
		local last
		if quoted then
			last = #query
			local tailEscaped = escaped
			for index = cursor, #query do
				local char = query:sub(index, index)
				if tailEscaped then
					tailEscaped = false
				elseif char == "\\" then
					tailEscaped = true
				elseif char == '"' then
					last = index
					break
				end
			end
		else
			local tail = query:sub(cursor):match("^[%w_%.%-]*") or ""
			last = cursor + #tail - 1
		end
		return { Choices = choices, First = if quoted then quoteStart else cursor - #prefix, Last = last }
	end

	Search.Scan = function(roots, predicate, results, matches, expand, checkpoint, options)
		local started = os.clock()
		local literal = literalTerms[predicate]
		if nameIndex and literal and options and options.Revision ~= nil then
			local complete = nameIndex.Scan(
				roots,
				type(literal) == "table" and literal[1] or literal,
				options.Revision,
				results,
				matches,
				expand,
				checkpoint,
				options.Incremental,
				type(literal) == "table" and literal or nil
			)
			Search.LastScanStats = {
				Mode = "NameIndex",
				Seconds = os.clock() - started,
				Candidates = nameIndex.Stats.Candidates,
				Builds = nameIndex.Stats.Builds,
				Updates = nameIndex.Stats.Updates,
				Complete = complete,
			}
			return complete
		end
		local visited = 0
		local stack, indices = {}, {}
		for _, root in ipairs(roots) do
			local depth = 1
			stack[1], indices[1] = root, 1
			while depth > 0 do
				local parent, index = stack[depth], indices[depth]
				local node = parent[index]
				if not node then
					stack[depth], indices[depth] = nil, nil
					depth -= 1
				else
					indices[depth] = index + 1
					local ok, matched =
						pcall(predicate, (node.Inferred and not node.Materialized) and searchObject(node) or node.Obj)
					if ok and matched then
						expand[node], results[node], matches[node] = 0, true, true
						local ancestor = node.Parent
						while ancestor and (not results[ancestor] or expand[ancestor] == 0) do
							expand[ancestor], results[ancestor] = true, true
							ancestor = ancestor.Parent
						end
					end
					if #node > 0 then
						depth += 1
						stack[depth], indices[depth] = node, 1
					end
					visited += 1
					if checkpoint and visited % 256 == 0 and not checkpoint() then
						return false
					end
				end
			end
		end
		Search.LastScanStats =
			{ Mode = "Predicate", Seconds = os.clock() - started, Candidates = visited, Complete = true }
		return true
	end

	Search.Compile = function(query)
		local indexedLiteral
		local ok, result = pcall(function()
			local tokens, pos = tokenize(query), 1
			if #tokens == 1 and (tokens[1].quoted or not tokens[1].value:find(".", 1, true)) then
				indexedLiteral = tokens[1].value:lower()
			elseif
				#tokens == 3
				and not tokens[1].quoted
				and tokens[1].value:lower() == "name"
				and tokens[2].value == ":"
			then
				indexedLiteral = tokens[3].value:lower()
			end
			local function peek(value)
				local token = tokens[pos]
				return token and not token.quoted and token.value:lower() == value
			end
			local function take()
				local token = tokens[pos]
				if not token then
					error("Add a search value", 0)
				end
				pos += 1
				return token
			end
			local parseOr, parseAnd, parseAtom
			local nameLengths, conjunctions = {}, {}
			parseAtom = function()
				if peek("(") then
					pos += 1
					local expr = parseOr()
					if not peek(")") then
						error("Close the parenthesis", 0)
					end
					pos += 1
					return expr
				end
				local first = take()
				if
					not first.quoted
					and (
						first.value == ")"
						or first.value == "("
						or first.value:lower() == "or"
						or first.value:lower() == "and"
					)
				then
					error("Add a search term", 0)
				end
				local op = tokens[pos] and tokens[pos].value
				if
					not first.quoted
					and (
						op == ":"
						or op == "="
						or op == "=="
						or op == "!="
						or op == "~="
						or op == ">"
						or op == "<"
						or op == ">="
						or op == "<="
					)
				then
					pos += 1
					local value = take().value
					local lowerValue, expected = value:lower(), tonumber(value)
					local expectedUnit
					if value:find(",", 1, true) then
						expectedUnit = {}
						for _, part in ipairs(string.split(value, ",")) do
							local number = tonumber(part)
							if not number then
								expectedUnit = nil
								break
							end
							expectedUnit[#expectedUnit + 1] = number
						end
					end
					local key = first.value:lower()
					local fields = string.split(key, ".")
					local rootKey = fields[1]
					if op == ":" and key == "is" then
						local className
						for name in pairs(API.Classes) do
							if name:lower() == lowerValue then
								className = name
								break
							end
						end
						if not className then
							error("Unknown class: " .. value, 0)
						end
						local predicate = function(obj)
							return obj:IsA(className)
						end
						classTerms[predicate] = className
						return predicate
					elseif op == ":" and key == "tag" then
						return function(obj)
							return service.CollectionService:HasTag(obj, value)
						end
					elseif op == ":" and key ~= "name" and key ~= "classname" then
						error("Use name:, classname:, is:, or tag:", 0)
					end
					local propertyCache, propertyTypes = {}, {}
					local function property(obj)
						if key == "name" then
							return obj.Name
						end
						if key == "classname" then
							return obj.ClassName
						end
						local name = propertyCache[obj.ClassName]
						if name == nil then
							local class = API.Classes[obj.ClassName]
							while class do
								for _, prop in pairs(class.Properties or {}) do
									if prop.Name:lower() == rootKey then
										name = prop.Name
										propertyTypes[obj.ClassName] = prop.ValueType and prop.ValueType.Name or false
										break
									end
								end
								if name then
									break
								end
								class = type(class.Superclass) == "table" and class.Superclass
									or API.Classes[class.Superclass]
							end
							propertyCache[obj.ClassName] = name or false
						end
						if name then
							local actual = obj[name]
							local valueType = propertyTypes[obj.ClassName] or typeof(actual)
							for i = 2, #fields do
								local component = components[fields[i]]
								if not component or actual == nil then
									return nil
								end
								if
									valueType == "Color3" and (component == "R" or component == "G" or component == "B")
								then
									actual = math.round(actual[component] * 255)
								else
									actual = actual[component]
								end
								valueType = typeof(actual)
							end
							return actual, valueType
						end
						return nil
					end
					local function matchesProperty(obj)
						local success, actual, valueType = pcall(property, obj)
						if not success or actual == nil then
							return false
						end
						if op == ":" and type(actual) == "string" then
							return string.find(string.lower(actual), lowerValue, 1, true) ~= nil
						end
						local fields = unitComponents[valueType]
						if fields then
							if not expectedUnit or #expectedUnit ~= #fields then
								return false
							end
							local unequal = op == "~=" or op == "!="
							for index, field in ipairs(fields) do
								local component = actual[field]
								if valueType == "Color3" then
									component = math.round(component * 255)
								end
								if unequal then
									if component ~= expectedUnit[index] then
										return true
									end
								elseif not compareNumber(component, expectedUnit[index], op) then
									return false
								end
							end
							return not unequal
						end
						if op == ">" or op == "<" or op == ">=" or op == "<=" then
							if type(actual) ~= "number" or not expected then
								return false
							end
							return compareNumber(actual, expected, op)
						end
						local equal
						if type(actual) == "number" then
							equal = actual == expected
						elseif type(actual) == "boolean" then
							equal = tostring(actual) == lowerValue
						else
							equal = contains(actual, lowerValue)
						end
						if op == "!=" or op == "~=" then
							return not equal
						end
						return equal
					end
					if key == "name" and op == ":" then nameLengths[matchesProperty] = #lowerValue end
					return matchesProperty
				end
				if not first.quoted and first.value:find(".", 1, true) then
					local path = string.split(first.value:lower(), ".")
					for _, part in ipairs(path) do
						if part == "" then
							error("Add a name between ancestry separators", 0)
						end
					end
					local function matches(node, index)
						if not node or index < 1 then
							return false
						end
						local part = path[index]
						if part ~= "*" and node.Name:lower() ~= part then
							return false
						end
						return index == 1 or matches(node.Parent, index - 1)
					end
					if path[#path] == "**" then
						return function(obj)
							local ancestor = obj.Parent
							while ancestor do
								if matches(ancestor, #path - 1) then
									return true
								end
								ancestor = ancestor.Parent
							end
							return false
						end
					end
					return function(obj)
						return matches(obj, #path)
					end
				end
				local lowerValue = first.value:lower()
				local function byName(obj)
					return contains(obj.Name, lowerValue)
				end
				nameLengths[byName] = #lowerValue
				return byName
			end
			parseAnd = function()
				local terms = { parseAtom() }
				while tokens[pos] and not peek(")") and not peek("or") do
					if peek("and") then
						pos += 1
					end
					terms[#terms + 1] = parseAtom()
				end
				if #terms == 1 then
					return terms[1]
				end
				local function conjunction(obj)
					for _, term in ipairs(terms) do
						if not term(obj) then
							return false
						end
					end
					return true
				end
				for _, term in ipairs(terms) do
					local required = classTerms[term] and term or requiredClassTerms[term]
					if required then
						requiredClassTerms[conjunction] = required
						break
					end
				end
				conjunctions[conjunction] = terms
				return conjunction
			end
			parseOr = function()
				local terms = { parseAnd() }
				while peek("or") do
					pos += 1
					terms[#terms + 1] = parseAnd()
				end
				if #terms == 1 then
					return terms[1]
				end
				return function(obj)
					for _, term in ipairs(terms) do
						if term(obj) then
							return true
						end
					end
					return false
				end
			end
			if #tokens == 0 then
				return function()
					return true
				end
			end
			local predicate = parseOr()
			if not indexedLiteral and #tokens > 1 then
				local terms = {}
				local valid = true
				for _, token in ipairs(tokens) do
					local value = token.value:lower()
					if not token.quoted and value == "and" then
						continue
					end
					if not token.quoted and (not value:match("^[%w_%-]+$") or value == "or") then
						valid = false
						break
					end
					terms[#terms + 1] = value
				end
				if valid and #terms > 0 then
					table.sort(terms, function(a, b)
						return #a > #b
					end)
					indexedLiteral = terms
				end
			end
			if tokens[pos] then
				error("Unexpected " .. tokens[pos].value, 0)
			end
			-- A mandatory name can reject a row before expensive class or property reads.
			-- Leave evaluation inside OR branches in its original order.
			local terms = conjunctions[predicate]
			if terms and not indexedLiteral then
				local best, length = 1, 0
				for i, term in ipairs(terms) do
					local size = nameLengths[term] or 0
					if size > length then best, length = i, size end
				end
				if best > 1 then table.insert(terms, 1, table.remove(terms, best)) end
			end
			return predicate
		end)
		if ok then
			if indexedLiteral ~= nil then
				literalTerms[result] = indexedLiteral
			elseif query:match("^[%w_%-]+$") then
				literalTerms[result] = query:lower()
			end
			return result
		end
		return nil, tostring(result)
	end
	return Search
end

return { InitDeps = InitDeps, InitAfterMain = function() end, Main = Main }
