--!strict

------------------------------ Module ------------------------------

local function Main()
	local Reconstruction = {}
	local sources = setmetatable({}, { __mode = "k" })
	local allowed = {
		string = true,
		number = true,
		boolean = true,
		["nil"] = true,
		Instance = true,
		thread = true,
		buffer = true,
		unknown = true,
		["table"] = true,
		["function"] = true,
	}
	local function pathKey(path)
		local parts = {}
		for _, name in ipairs(path) do
			local text = tostring(name)
			parts[#parts + 1] = type(name) .. ":" .. #text .. ":" .. text
		end
		return table.concat(parts)
	end
	function Reconstruction.Merge(node, member, budget)
		if type(member) ~= "table" or (type(member.Name) ~= "string" and type(member.Name) ~= "number") then
			return false
		end
		local path = member.Path or { member.Name }
		if (#path == 0 and not member.Root) or #path > 16 then
			return false
		end
		for _, name in ipairs(path) do
			if type(name) == "number" then
				if name ~= math.floor(name) or math.abs(name) > 1000000 then
					return false
				end
			elseif type(name) ~= "string" or #name == 0 or #name > 128 then
				return false
			end
		end
		node.ModuleMembers = node.ModuleMembers or {}
		local key = pathKey(path)
		local record = node.ModuleMembers[key]
		if not record then
			if (node.ModuleMemberCount or 0) >= 2048 or (budget and budget.Count >= budget.Limit) then
				if budget then
					budget.Dropped += 1
				end
				node.ModuleDropped = (node.ModuleDropped or 0) + 1
				return false, "Module member budget reached"
			end
			record = { Name = member.Name, Path = table.clone(path), Arguments = {}, Count = 0, Types = {} }
			node.ModuleMembers[key] = record
			node.ModuleMemberCount = (node.ModuleMemberCount or 0) + 1
			if budget then
				budget.Count += 1
			end
		end
		local changed = not record.Seen
		record.Seen = true
		if member.Kind == "field" then
			local kind = allowed[member.Type] and member.Type or "unknown"
			if not record.Types[kind] then
				record.Types[kind] = true
				changed = true
			end
			return changed
		end
		if not record.Callable then
			record.Callable = true
			record.Method = member.Method
			changed = true
		elseif record.Method ~= member.Method and not record.Mixed then
			record.Mixed = true
			changed = true
		end
		if member.Definition then
			if record.Method or record.DefinitionCount ~= member.Count then
				changed = true
			end
			record.Method = false
			record.DefinitionCount = math.min(member.Count or 0, 32)
			record.DeclaredNames = record.DeclaredNames or {}
			record.DeclaredArguments = record.DeclaredArguments or {}
			for index = 1, math.min(member.Count or 0, 32) do
				local name = (member.DeclaredNames or {})[index]
				local kind = (member.DeclaredArguments or {})[index]
				if type(name) == "string" and #name <= 64 and record.DeclaredNames[index] ~= name then
					record.DeclaredNames[index] = name
					changed = true
				end
				if type(kind) == "string" and record.DeclaredArguments[index] ~= kind then
					record.DeclaredArguments[index] = kind
					changed = true
				end
			end
			if not record.Definition then
				record.Definition = true
				changed = true
			end
		end
		local count = math.min(member.Count or 0, 32)
		if member.Vararg and not record.Vararg then
			record.Vararg = true
			changed = true
		end
		if count > record.Count then
			record.Count = count
			changed = true
		end
		for index = 1, count do
			local kind = (member.Arguments or {})[index] or "unknown"
			if not allowed[kind] then
				kind = "unknown"
			end
			record.Arguments[index] = record.Arguments[index] or {}
			if not record.Arguments[index][kind] then
				record.Arguments[index][kind] = true
				changed = true
			end
		end
		if record.MinCount == nil or count < record.MinCount then
			record.MinCount = count
			changed = true
		end
		return changed
	end
	local reserved = {}
	for word in
		("and break do else elseif end false for function if in local nil not or repeat return then true until while continue type export"):gmatch(
			"%S+"
		)
	do
		reserved[word] = true
	end
	local function annotation(kind)
		if kind == "table" then
			return "{[any]: any}"
		end
		if kind == "function" then
			return "((...any) -> ...any)"
		end
		return kind
	end
	local function declaredType(kind)
		if type(kind) ~= "string" then
			return
		end
		local base = kind:gsub("%?$", "")
		if not allowed[base] then
			return
		end
		return annotation(base) .. (kind:sub(-1) == "?" and base ~= "nil" and "?" or "")
	end
	local function types(seen, optional)
		if seen.unknown then
			return "unknown"
		end
		local names = {}
		for kind in pairs(seen) do
			names[#names + 1] = annotation(kind)
		end
		if optional and not seen["nil"] then
			names[#names + 1] = "nil"
		end
		table.sort(names)
		return #names > 0 and table.concat(names, " | ") or "unknown"
	end
	function Reconstruction.Generate(node)
		local lines = { "-- Reconstructed by Dex", "local module = {}", "" }
		local root = { Children = {}, Expression = "module" }
		for _, member in pairs(node.ModuleMembers or {}) do
			local current = root
			for _, name in ipairs(member.Path) do
				current.Children[name] = current.Children[name]
					or {
						Children = {},
						Expression = current.Expression
							.. "["
							.. (type(name) == "number" and tostring(name) or string.format("%q", name))
							.. "]",
					}
				current = current.Children[name]
			end
			current.Member = member
		end
		local function signature(member, receiver)
			local args = receiver and { "_receiver: unknown" } or member.Method and { "self: unknown" } or {}
			if receiver and member.Method then
				args[#args + 1] = "self: unknown"
			end
			local used = { self = member.Method or nil, _receiver = receiver or nil }
			for index = 1, (member.DefinitionCount or member.Count) do
				local name = member.DeclaredNames and member.DeclaredNames[index]
				if not name or not name:match("^[%a_][%w_]*$") or reserved[name] or used[name] then
					name = "arg" .. index
				end
				while used[name] do
					name = "_" .. name
				end
				used[name] = true
				args[#args + 1] = name
					.. ": "
					.. (
						declaredType(member.DeclaredArguments and member.DeclaredArguments[index])
						or types(member.Arguments[index] or {}, index > (member.MinCount or 0))
					)
			end
			if member.Vararg then
				args[#args + 1] = "...: unknown"
			end
			if member.Mixed and not member.Definition then
				args = receiver and { "_receiver: unknown", "...: unknown" } or { "...: unknown" }
			end
			return table.concat(args, ", ")
		end
		local function callableTable(item)
			if not item.Member or not item.Member.Callable then
				return
			end
			lines[#lines + 1] = "setmetatable("
				.. item.Expression
				.. ", {__call = function("
				.. signature(item.Member, true)
				.. ")"
			lines[#lines + 1] = ' error("Reconstructed stub: implementation unavailable", 2)'
			lines[#lines + 1] = "end})"
		end
		local function output(parent)
			local names = {}
			for name in pairs(parent.Children) do
				names[#names + 1] = name
			end
			table.sort(names, function(a, b)
				if type(a) == type(b) then
					return a < b
				end
				return type(a) == "number"
			end)
			for _, name in ipairs(names) do
				local item = parent.Children[name]
				local member = item.Member
				if next(item.Children) or (member and not member.Callable and member.Types.table) then
					lines[#lines + 1] = item.Expression .. " = {}"
					output(item)
					callableTable(item)
				elseif member and member.Callable then
					lines[#lines + 1] = item.Expression .. " = function(" .. signature(member, false) .. ")"
					lines[#lines + 1] = ' error("Reconstructed stub: implementation unavailable", 2)'
					lines[#lines + 1] = "end"
				else
					lines[#lines + 1] = item.Expression .. " = nil :: (" .. types(member and member.Types or {}) .. ")"
				end
			end
		end
		output(root)
		callableTable(root)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "return module"
		return table.concat(lines, "\n")
	end
	function Reconstruction.Bind(object, node)
		local source = Reconstruction.Generate(node)
		if sources[object] ~= source then
			sources[object] = source
			pcall(function()
				object.Source = source
			end)
		end
		return source
	end
	function Reconstruction.GetSource(object)
		return sources[object]
	end
	return Reconstruction
end
return { Main = Main }
