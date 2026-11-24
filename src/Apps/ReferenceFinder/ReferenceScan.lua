--!strict

local API

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	API = d.API
end
------------------------------ Module ------------------------------

local function Main()
	local Scan = {}
	local reflectedClasses = {}
	local literalCache = setmetatable({}, { __mode = "k" })
	function Scan.FindName(text, name)
		local offset = 1
		while offset <= #text do
			local first, last = text:find(name, offset, true)
			if not first then
				return
			end
			local before = first > 1 and text:sub(first - 1, first - 1) or ""
			local after = text:sub(last + 1, last + 1)
			if
				(not name:sub(1, 1):match("[%w_]") or not before:match("[%w_]"))
				and (not name:sub(-1):match("[%w_]") or not after:match("[%w_]"))
			then
				return first
			end
			offset = last + 1
		end
	end
	function Scan.Run(options)
		local target = assert(options.Target)
		local checkpoint = options.Checkpoint or function()
			return true
		end
		local results = {
			Direct = {},
			Scripts = {},
			Stats = {
				Objects = 0,
				Properties = 0,
				UnreadableProperties = 0,
				UnknownClasses = 0,
				Scripts = 0,
				ReadableScripts = 0,
				BytecodeScripts = 0,
				UnavailableScripts = 0,
				LargeScripts = 0,
				Bytes = 0,
				Cancelled = false,
				Truncated = false,
			},
		}
		local stats = results.Stats
		local classes = reflectedClasses
		local scripts = {}
		local seen = {}
		local objects = {}
		local scriptClasses = {}
		local limit = options.MaxResults or 5000
		local count = 0
		local function check()
			if not checkpoint(results) then
				stats.Cancelled = true
				return false
			end
			return true
		end
		local function path(object)
			local ok, value = pcall(function()
				return object:GetFullName()
			end)
			return ok and value or object.Name
		end
		local function add(section, item)
			if count >= limit then
				stats.Truncated = true
				return false
			end
			count += 1
			results[section][#results[section] + 1] = item
			return true
		end
		local function properties(name)
			if classes[name] then
				return classes[name]
			end
			if not API.Classes[name] then
				stats.UnknownClasses += 1
			end
			local list = {}
			local canonical = {}
			local visited = {}
			local current = name
			while current and not visited[current] do
				visited[current] = true
				local class = API.Classes[current]
				if not class then
					break
				end
				for _, property in pairs(class.Properties or {}) do
					local valueType = property.ValueType or {}
					local key = property.Name
					if
						key
						and key:lower() ~= "parent"
						and (
							valueType.Category == "Class"
							or valueType.Name == "Instance"
							or API.Classes[valueType.Name]
						)
					then
						local lower = key:lower()
						local previous = canonical[lower]
						if not previous or key:match("^%u") and not previous:match("^%u") then
							canonical[lower] = key
						end
					end
				end
				current = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
			end
			for _, key in pairs(canonical) do
				list[#list + 1] = key
			end
			table.sort(list)
			classes[name] = list
			return list
		end
		local snapshot = table.clone(options.Objects or {})
		for object in pairs(snapshot) do
			if not check() then
				return results
			end
			if typeof(object) ~= "Instance" then
				continue
			end
			seen[object] = true
			stats.Objects += 1
			local class = object.ClassName
			local group = objects[class]
			if not group then
				group = {}
				objects[class] = group
			end
			group[#group + 1] = object
			if scriptClasses[class] == nil then
				scriptClasses[class] = object:IsA("LuaSourceContainer")
			end
			if scriptClasses[class] then
				scripts[#scripts + 1] = object
			end
		end
		local function direct()
			for class, group in pairs(objects) do
				local members = properties(class)
				if #members == 0 then
					continue
				end
				for _, object in ipairs(group) do
					for _, property in ipairs(members) do
						if not check() then
							return false
						end
						stats.Properties += 1
						local ok, value = pcall(function()
							return object[property]
						end)
						if not ok then
							stats.UnreadableProperties += 1
						elseif
							value == target
							and not add(
								"Direct",
								{ Object = object, Property = property, Path = path(object), Kind = "Direct" }
							)
						then
							return false
						end
					end
				end
			end
			return true
		end
		for object in pairs(options.Sources or {}) do
			if not seen[object] then
				scripts[#scripts + 1] = object
				seen[object] = true
			end
		end
		local name = target.Name
		if name == "" then
			direct()
			return results
		end
		for _, object in ipairs(scripts) do
			if not check() then
				return results
			end
			stats.Scripts += 1
			local source = options.Sources and options.Sources[object]
			local sourceKind = source and "Editor buffer" or "Readable source"
			if source == nil and options.ReadScript then
				local record = options.ReadScript(object, function()
					return check()
				end)
				if record.Cancelled then
					stats.Cancelled = true
					return results
				end
				if record.Literals then
					stats.BytecodeScripts += 1
					local cached = literalCache[record.Literals]
					if not cached then
						cached = { Queries = {}, Count = 0 }
						literalCache[record.Literals] = cached
					end
					local found = cached.Queries[name]
					if found == nil then
						found = false
						for _, literal in ipairs(record.Literals) do
							if not check() then
								return results
							end
							local at = Scan.FindName(literal, name)
							if at then
								found = { Literal = literal, At = at }
								break
							end
						end
						if cached.Count >= 64 then
							table.clear(cached.Queries)
							cached.Count = 0
						end
						cached.Queries[name] = found
						cached.Count += 1
					end
					if found then
						local literal, at = found.Literal, found.At
						if
							not add("Scripts", {
								Object = object,
								Path = path(object),
								Snippet = "Constant: " .. literal:sub(math.max(1, at - 40), at + #name + 120),
								Literal = literal,
								SourceKind = record.SourceKind,
								TargetName = name,
								Kind = "Bytecode",
							})
						then
							return results
						end
					end
					continue
				end
				source = record.Source
				sourceKind = record.SourceKind or "Readable source"
			elseif source == nil then
				local ok, value = pcall(function()
					return object.Source
				end)
				if ok and type(value) == "string" then
					source = value
				end
			end
			if type(source) ~= "string" then
				stats.UnavailableScripts += 1
				continue
			end
			if
				#source > (options.MaxScriptBytes or 2 * 1024 * 1024)
				or stats.Bytes + #source > (options.MaxTotalBytes or 32 * 1024 * 1024)
			then
				stats.LargeScripts += 1
				continue
			end
			stats.Bytes += #source
			stats.ReadableScripts += 1
			if name:find("\n", 1, true) then
				continue
			end
			local cursor, lineNumber, lineStart, countedThrough = 1, 1, 1, 1
			local documentId = {}
			local objectPath
			local window, windowStart, windowEnd
			local leftWord = name:sub(1, 1):match("[%w_]") ~= nil
			local rightWord = name:sub(-1):match("[%w_]") ~= nil
			while cursor <= #source do
				if not check() then
					return results
				end
				if not window or cursor > windowEnd then
					windowStart = cursor
					windowEnd = math.min(#source, cursor + 65535)
					window = source:sub(cursor, math.min(#source, windowEnd + #name - 1))
				end
				local first, last = window:find(name, cursor - windowStart + 1, true)
				if not first then
					cursor = windowEnd + 1
					continue
				end
				first, last = windowStart + first - 1, windowStart + last - 1
				local before = first > 1 and source:sub(first - 1, first - 1) or ""
				local after = source:sub(last + 1, last + 1)
				if (leftWord and before:match("[%w_]")) or (rightWord and after:match("[%w_]")) then
					cursor = last + 1
					continue
				end
				local counted = 0
				while countedThrough < first do
					local newline = source:find("\n", countedThrough, true)
					if not newline or newline >= first then
						break
					end
					lineNumber += 1
					lineStart = newline + 1
					countedThrough = lineStart
					counted += 1
					if counted % 256 == 0 and not check() then
						return results
					end
				end
				local lineEnd = source:find("\n", last + 1, true) or (#source + 1)
				local column = first - lineStart + 1
				local start = math.max(lineStart, first - 50)
				local snippet = (start > lineStart and "..." or "")
					.. source:sub(start, math.min(lineEnd - 1, first + #name + 150)):gsub("\r$", ""):gsub("^%s+", "")
				local prefix = source:sub(lineStart, first - 1):gsub("\t", "    ")
				objectPath = objectPath or path(object)
				if
					not add("Scripts", {
						Object = object,
						Path = objectPath,
						Line = lineNumber,
						Column = column,
						EditorColumn = #prefix + 1,
						Snippet = snippet,
						Source = source,
						SourceKind = sourceKind,
						DocumentId = documentId,
						TargetName = name,
						Kind = "Text",
					})
				then
					return results
				end
				cursor = lineEnd + 1
				countedThrough = cursor
				lineStart = cursor
				lineNumber += 1
			end
		end
		direct()
		return results
	end
	return Scan
end
return { InitDeps = InitDeps, Main = Main }
