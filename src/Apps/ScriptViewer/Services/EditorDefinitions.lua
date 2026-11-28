--!strict

------------------------------ Types ------------------------------

type Token = {
	Kind: string,
	Value: string,
	First: number,
	Last: number,
}

type Reference = {
	Object: Instance,
	First: number,
	Last: number,
}

type Binding = { Name: number, Value: number }
type Checkpoint = () -> boolean

------------------------------ Constants ------------------------------

local Escapes = {
	a = "\a",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
	v = "\v",
}

local Assignments = {
	["="] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
	["//="] = true,
	["%="] = true,
	["^="] = true,
	["..="] = true,
}

local MultiSymbols = {
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
	["%="] = true,
	["^="] = true,
	["=="] = true,
	["~="] = true,
	["<="] = true,
	[">="] = true,
	[".."] = true,
	["->"] = true,
	["//"] = true,
	["::"] = true,
}

local ChildMethods = {
	WaitForChild = true,
	FindFirstChild = true,
	FindFirstChildOfClass = true,
	FindFirstChildWhichIsA = true,
	GetService = true,
	FindService = true,
}

------------------------------ Module ------------------------------

local function LongString(source: string, first: number, _skipContent: boolean?): (number?, string?)
	local equals = source:match("^%[(=*)%[", first)
	if not equals then
		return nil, nil
	end
	local start = first + #equals + 2
	local close, last = source:find("]" .. equals .. "]", start, true)
	if not close or not last then
		return #source + 1, nil
	end
	return last + 1, if _skipContent then nil else (source:sub(start, close - 1):gsub("^\r?\n", ""))
end

local function QuotedString(source: string, first: number): (number, string?)
	local quote = source:sub(first, first)
	local interpolated = quote == "`"
	local special = source:find("[\\\r\n" .. quote .. (if interpolated then "{" else "") .. "]", first + 1)
	if not special then
		return #source + 1, nil
	end
	local firstSpecial = source:sub(special, special)
	if firstSpecial == quote then
		return special + 1, source:sub(first + 1, special - 1)
	elseif firstSpecial ~= "\\" then
		return special, nil
	end

	local parts = {}
	local position = first + 1
	local valid = true
	while position <= #source do
		local char = source:sub(position, position)
		if char == quote then
			return position + 1, if valid then table.concat(parts) else nil
		elseif char == "\n" or char == "\r" or interpolated and char == "{" then
			return position, nil
		elseif char ~= "\\" then
			parts[#parts + 1] = char
			position += 1
			continue
		end

		position += 1
		local escape = source:sub(position, position)
		local value = Escapes[escape]
		if escape == quote or escape == "\\" or escape == "'" or escape == '"' or interpolated and escape == "{" then
			value = escape
		elseif escape == "z" then
			local _, last = source:find("^%s*", position + 1)
			position = last or position
			value = ""
		elseif escape == "x" then
			local hex = source:sub(position + 1, position + 2)
			if #hex == 2 and hex:match("^%x%x$") then
				value = string.char(tonumber(hex, 16) :: number)
				position += 2
			end
		elseif escape == "u" then
			local hex, nextPosition = source:match("^{(%x+)}()", position + 1)
			local codepoint = hex and tonumber(hex, 16)
			if codepoint and nextPosition and codepoint <= 0x10FFFF then
				value = utf8.char(codepoint)
				position = nextPosition - 1
			end
		elseif escape:match("%d") then
			local digits = source:match("^%d%d?%d?", position) :: string
			local byte = tonumber(digits) :: number
			if byte <= 255 then
				value = string.char(byte)
			end
			position += #digits - 1
		elseif escape == "\r" or escape == "\n" then
			if source:sub(position, position + 1) == "\r\n" then
				position += 1
			end
			value = "\n"
		end
		if value then
			parts[#parts + 1] = value
		else
			valid = false
		end
		position += 1
	end
	return #source + 1, nil
end

local function SkipComment(source: string, first: number): number
	local last = LongString(source, first + 2, true)
	return last or source:find("[\r\n]", first + 2) or #source + 1
end

local function SkipInterpolated(source: string, first: number, depth: number): number
	if depth > 32 then
		return #source + 1
	end
	local braces = 0
	local position = first + 1
	while position <= #source do
		local char = source:sub(position, position)
		if braces == 0 then
			if char == "`" then
				return position + 1
			elseif char == "\\" then
				position += 1
			elseif char == "{" then
				braces = 1
			end
		elseif char == "{" then
			braces += 1
		elseif char == "}" then
			braces -= 1
		elseif char == "`" then
			position = SkipInterpolated(source, position, depth + 1)
			continue
		elseif char == '"' or char == "'" then
			position = QuotedString(source, position)
			continue
		elseif char == "-" and source:sub(position + 1, position + 1) == "-" then
			position = SkipComment(source, position)
			continue
		elseif char == "[" then
			local last = LongString(source, position, true)
			if last then
				position = last
				continue
			end
		end
		position += 1
	end
	return #source + 1
end

local function Tokenize(source: string, _checkpoint: Checkpoint?, includeComments: boolean?): { Token }?
	local tokens = {}
	local position, nextCheck = 1, 4096
	while position <= #source do
		if _checkpoint and position >= nextCheck then
			if not _checkpoint() then
				return nil
			end
			nextCheck = position + 4096
		end
		local byte = source:byte(position)
		local first = position
		local kind, value
		if byte == 32 or byte >= 9 and byte <= 13 then
			local _, last = source:find("^%s+", position)
			position = (last or position) + 1
			continue
		elseif byte == 45 and source:sub(position + 1, position + 1) == "-" then
			position = SkipComment(source, position)
			if not includeComments then
				continue
			end
			kind = "comment"
		elseif byte == 34 or byte == 39 then
			position, value = QuotedString(source, position)
			kind = if value then "string" else "opaque"
		elseif byte == 96 then
			position, value = QuotedString(source, position)
			if not value then
				position = SkipInterpolated(source, first, 0)
			end
			kind = if value then "string" else "opaque"
		elseif byte == 95 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122 then
			value = source:match("^[%w_]+", position) :: string
			kind = "name"
			position += #value
		elseif byte >= 48 and byte <= 57 then
			value = source:match("^%d[%w_]*", position) :: string
			if not value:match("^0[xXbB]") then
				value = source:match("^%d[%d_]*%.%d[%d_]*[eE][%+%-]?[%d_]+", position)
					or source:match("^%d[%d_]*[eE][%+%-]?[%d_]+", position)
					or source:match("^%d[%d_]*%.%d[%d_]*", position)
					or value
			end
			kind = "number"
			position += #value
		else
			if byte == 91 then
				local last, content = LongString(source, position)
				if last then
					tokens[#tokens + 1] = {
						Kind = if content then "string" else "opaque",
						Value = content or "",
						First = first,
						Last = last,
					}
					position = last
					continue
				end
			end
			kind = "symbol"
			local triple = source:sub(position, position + 2)
			local pair = source:sub(position, position + 1)
			value = if triple == "//="
					or triple == "..="
					or triple == "..."
				then triple
				elseif MultiSymbols[pair] then pair
				else source:sub(position, position)
			position += #value
		end
		tokens[#tokens + 1] = { Kind = kind, Value = value or "", First = first, Last = position }
	end
	return tokens
end

local function IndexBindings(
	tokens: { Token },
	_checkpoint: Checkpoint?
): ({ [string]: Binding }?, { [string]: boolean }?)
	local declarations: { [string]: Binding } = {}
	local blocked: { [string]: boolean } = {}
	local depth = 0
	local function blockNames(index: number): ()
		while tokens[index] and tokens[index].Kind == "name" do
			blocked[tokens[index].Value] = true
			if not tokens[index + 1] or tokens[index + 1].Value ~= "," then
				break
			end
			index += 2
		end
	end

	for i, token in tokens do
		if _checkpoint and i % 1024 == 0 and not _checkpoint() then
			return nil, nil
		end
		if token.Kind == "name" then
			if token.Value == "local" or token.Value == "const" then
				local name = tokens[i + 1]
				local assignment = i + 2
				local following, annotation = tokens[assignment], tokens[assignment + 1]
				if following and following.Value == ":" and annotation and annotation.Kind == "name" then
					assignment += 2
				end
				local equals = tokens[assignment]
				if name and name.Value == "function" then
					blockNames(i + 2)
				elseif name and name.Kind == "name" then
					if depth == 0 and equals and equals.Value == "=" and not declarations[name.Value] then
						declarations[name.Value] = { Name = i + 1, Value = assignment + 1 }
						if
							name.Value == "script"
							or name.Value == "game"
							or name.Value == "workspace"
							or name.Value == "require"
						then
							blocked[name.Value] = true
						end
					else
						blockNames(i + 1)
					end
				end
			elseif token.Value == "function" then
				depth += 1
				local functionName, afterName = tokens[i + 1], tokens[i + 2]
				if
					functionName
					and functionName.Kind == "name"
					and afterName
					and (afterName.Value == "(" or afterName.Value == "<")
				then
					blocked[functionName.Value] = true
				end
				local cursor = i + 1
				while cursor < i + 64 and tokens[cursor] and tokens[cursor].Value ~= "(" do
					cursor += 1
				end
				if not tokens[cursor] or tokens[cursor].Value ~= "(" then
					continue
				end
				local parens = 1
				cursor += 1
				while tokens[cursor] and parens > 0 do
					local parameter = tokens[cursor]
					if parameter.Kind == "name" then
						blocked[parameter.Value] = true
					elseif parameter.Value == "(" then
						parens += 1
					elseif parameter.Value == ")" then
						parens -= 1
					end
					cursor += 1
				end
			elseif token.Value == "for" then
				blockNames(i + 1)
			elseif token.Value == "do" or token.Value == "if" or token.Value == "repeat" then
				depth += 1
			elseif token.Value == "end" or token.Value == "until" then
				depth = math.max(0, depth - 1)
			end
		elseif token.Kind == "symbol" and Assignments[token.Value] then
			local cursor = i - 1
			while tokens[cursor] and tokens[cursor].Kind == "name" do
				local name = tokens[cursor].Value
				local binding = declarations[name]
				local previous = tokens[cursor - 1] and tokens[cursor - 1].Value
				if previous == "." or previous == ":" then
					break
				end
				if not binding or binding.Name ~= cursor then
					blocked[name] = true
				end
				if previous ~= "," then
					break
				end
				cursor -= 2
			end
		end
	end
	return declarations, blocked
end

local function FindToken(tokens: { Token }, position: number): number?
	local left, right = 1, #tokens
	while left <= right do
		local center = (left + right) // 2
		local token = tokens[center]
		if position < token.First then
			right = center - 1
		elseif position >= token.Last then
			left = center + 1
		else
			return center
		end
	end
	return nil
end

local function ReadMember(object: Instance, name: string): Instance?
	local ok, value = pcall(function()
		return (object :: any)[name]
	end)
	return if ok and typeof(value) == "Instance" then value else nil
end

local function GetChild(object: Instance, name: string, method: string, recursive: boolean?): Instance?
	local ok, child = pcall(function()
		if method == "GetService" or method == "FindService" then
			return (object :: DataModel):FindService(name)
		elseif method == "FindFirstChildOfClass" then
			return object:FindFirstChildOfClass(name)
		elseif method == "FindFirstChildWhichIsA" then
			return object:FindFirstChildWhichIsA(name, recursive)
		end
		return object:FindFirstChild(name, recursive)
	end)
	return if ok then child else nil
end

local function ResolvePath(path: string, scriptObject: Instance?, gameObject: DataModel): Instance?
	if path:find("//", 1, true) then
		return nil
	end

	local object: Instance? = nil
	local tail
	local rootService = false
	if path:sub(1, 6) == "@self/" then
		object, tail = scriptObject, path:sub(7)
	elseif path:sub(1, 6) == "@game/" then
		object, tail, rootService = gameObject, path:sub(7), true
	elseif path:sub(1, 2) == "@/" then
		object, tail, rootService = gameObject, path:sub(3), true
	elseif path:sub(1, 2) == "./" or path:sub(1, 3) == "../" then
		object = scriptObject and ReadMember(scriptObject, "Parent")
		tail = if path:sub(1, 2) == "./" then path:sub(3) else path
	else
		return nil
	end
	if not object then
		return nil
	end

	for part in tail:gmatch("[^/]+") do
		if part == ".." then
			object = ReadMember(object, "Parent")
		elseif part ~= "." then
			local existingService = if rootService then GetChild(gameObject, part, "FindService") else nil
			object = existingService or GetChild(object, part, "FindFirstChild")
		end
		if not object then
			return nil
		end
		rootService = false
	end
	return object
end

local function Main(apps)
	local function tokensFor(source, checkpoint, includeComments, preparedRecord)
		local record = if preparedRecord and preparedRecord.Source == source then preparedRecord else apps and apps.EditorParser and apps.EditorParser.Parse(source, checkpoint)
		if not record then
			if apps and apps.EditorParser then return nil end
			return Tokenize(source, checkpoint, includeComments)
		end
		if not record.Root then return Tokenize(source, checkpoint, includeComments) end
		local key = if includeComments then "WithComments" else "Tokens"
		if record[key] then return record[key] end
		local tokens = {}
		local tokenAt = apps.EditorParser.TokenAt
		local depth, interpolation = 0, nil
		for i = 1, record.TokenCount do
			if checkpoint and i % 256 == 1 and checkpoint() == false then return nil end
			local id, first, last = tokenAt(record, i)
			local kind, value
			if id == 266 then
				if depth == 0 then interpolation = first end
				depth += 1
				continue
			elseif depth > 0 then
				if id == 268 then depth -= 1 end
				if depth ~= 0 then continue end
				first, kind = interpolation, "opaque"
			elseif id == 278 or id == 279 or id == 269 then
				local finish
				if id == 278 then finish, value = LongString(source, first) else finish, value = QuotedString(source, first) end
				kind = if value then "string" else "opaque"
			elseif id == 282 or id == 283 or id == 287 then
				if not includeComments then continue end
				kind = "comment"
			elseif id == 286 or id == 289 then
				kind = "opaque"
			else
				kind = if id == 280 then "number" elseif id == 281 or id >= 291 then "name" else "symbol"
				value = source:sub(first, last - 1)
			end
			tokens[#tokens + 1] = {Kind = kind, Value = value or "", First = first, Last = last}
		end
		if depth > 0 then
			tokens[#tokens + 1] = {Kind = "opaque", Value = "", First = interpolation, Last = #source + 1}
		end
		record[key] = tokens
		return tokens
	end
	local function astBindings(record, tokens, checkpoint)
		if record.BindingIndex then return record.BindingIndex[1], record.BindingIndex[2] end
		local declarations, blocked = {}, {}
		local function tokenAt(node)
			local at = node.location.begin
			return FindToken(tokens, record.Starts[at.x+1] + at.y)
		end
		for i, node, _, scope in apps.EditorParser.Nodes(record, checkpoint) do
			if checkpoint and i % 256 == 0 and checkpoint() == false then return nil, nil end
			if node.kind == "StatLocal" then
				for index, var in node.vars do
					local name = var.name
					local expr = node.values[index]
					if scope == record.Root and expr and not declarations[name] then
						local lhs, rhs = tokenAt(var), tokenAt(expr)
						if lhs and rhs then declarations[name] = {Name = lhs, Value = rhs} end
						if name == "script" or name == "game" or name == "workspace" or name == "require" then blocked[name] = true end
					else blocked[name] = true end
				end
			elseif node.kind == "StatLocalFunction" and node.name then blocked[node.name.name] = true
			elseif node.kind == "ExprFunction" then
				for _, arg in node.args do blocked[arg.name] = true end
			elseif node.kind == "StatFor" then blocked[node.var.name] = true
			elseif node.kind == "StatForIn" then
				for _, var in node.vars do blocked[var.name] = true end
			elseif node.kind == "StatAssign" or node.kind == "StatCompoundAssign" or node.kind == "StatFunction" then
				for _, var in node.vars or {node.var or node.name} do
					if var.kind == "ExprGlobal" then blocked[var.name] = true
					elseif var.kind == "ExprLocal" then blocked[var["local"].name] = true end
				end
			end
		end
		if not record.Nodes then return nil, nil end
		record.BindingIndex = {declarations, blocked}
		return declarations, blocked
	end
	local Definitions = { New = function() return Main(apps) end, Tokenize = tokensFor }
	function Definitions.ResolvePath(path: string, _scriptObject: Instance?, _gameObject: DataModel?): Instance?
		return ResolvePath(path, _scriptObject, _gameObject or game)
	end

	local indexedSource
	local tokens: { Token } = {}
	local declarations: { [string]: Binding } = {}
	local blocked: { [string]: boolean } = {}

	function Definitions.IsPrimed(source: string): boolean
		return source == indexedSource
	end

	function Definitions.Prime(source: string, _checkpoint: Checkpoint?, preparedTokens: { Token }?, preparedRecord): boolean
		if Definitions.IsPrimed(source) then
			return true
		end
		local nextTokens = preparedTokens or tokensFor(source, _checkpoint, false, preparedRecord)
		if not nextTokens then
			return false
		end
		local nextDeclarations, nextBlocked
		local record = if preparedRecord and preparedRecord.Source == source then preparedRecord else apps and apps.EditorParser and apps.EditorParser.Parse(source, _checkpoint)
		if record and record.Root then
			nextDeclarations, nextBlocked = astBindings(record, nextTokens, _checkpoint)
		else
			nextDeclarations, nextBlocked = IndexBindings(nextTokens, _checkpoint)
		end
		if not nextDeclarations or not nextBlocked or _checkpoint and not _checkpoint() then
			return false
		end
		tokens, declarations, blocked = nextTokens, nextDeclarations, nextBlocked
		indexedSource = source
		return true
	end

	function Definitions.Resolve(
		source: string,
		position: number,
		_scriptObject: Instance?,
		_gameObject: DataModel?,
		_workspaceObject: Workspace?,
		_cachedOnly: boolean?
	): Reference?
		if not Definitions.IsPrimed(source) and (_cachedOnly or not Definitions.Prime(source)) then
			return nil
		end
		local wanted = FindToken(tokens, position)
		if not wanted or (tokens[wanted].Kind ~= "name" and tokens[wanted].Kind ~= "string") then
			return nil
		end
		local scriptObject = _scriptObject
		local dataModel = _gameObject or game
		local world = _workspaceObject or workspace
		local function value(index: number): string?
			local token = tokens[index]
			return if token and token.Kind ~= "string" and token.Kind ~= "opaque" then token.Value else nil
		end
		local function literal(index: number): string?
			local token = tokens[index]
			return if token and token.Kind == "string" then token.Value else nil
		end
		local function hit(index: number, object: Instance?): Reference?
			if index == wanted and object then
				local token = tokens[index]
				local first, last = token.First, token.Last
				if token.Kind == "string" then
					local equals = source:match("^%[(=*)%[", first)
					if equals then
						local delimiter = #equals + 2
						first += delimiter
						last -= delimiter
						if source:sub(first, first + 1) == "\r\n" then
							first += 2
						elseif source:sub(first, first) == "\n" then
							first += 1
						end
					else
						first += 1
						last -= 1
					end
				end
				if position >= first and position < last then
					return { Object = object, First = first, Last = last }
				end
			end
			return nil
		end
		local function endsBinding(cursor: number): boolean
			local following = value(cursor)
			if not tokens[cursor] or following == ";" or following == "end" or following == "until" then
				return true
			end
			if not source:sub(tokens[cursor - 1].Last, tokens[cursor].First - 1):find("[\r\n]") then
				return false
			end
			return tokens[cursor].Kind == "name" or following == "}"
		end
		local function staticPath(start: number, depth: number): (string?, number, number?)
			if depth > 32 then
				return nil, start, nil
			end
			local path = literal(start)
			if path then
				return path, start + 1, start
			end
			local name = value(start)
			if name == "(" then
				local inner, after, link = staticPath(start + 1, depth + 1)
				if inner and value(after) == ")" then
					return inner, after + 1, link
				end
			elseif name and not blocked[name] then
				local binding = declarations[name]
				if binding and binding.Name < start then
					local bound, after = staticPath(binding.Value, depth + 1)
					if bound and endsBinding(after) then
						return bound, start + 1, start
					end
				end
			end
			return nil, start, nil
		end

		local parse
		local function parseRequire(start: number, depth: number): (Instance?, number, Reference?)
			if value(start) ~= "require" or blocked.require then
				return nil, start, nil
			end
			local opening = value(start + 1) == "("
			local first = start + (if opening then 2 else 1)
			local path, cursor, link = nil, first, nil
			if opening then
				path, cursor, link = staticPath(first, depth + 1)
			else
				local argument = tokens[first]
				if argument and source:sub(argument.First, argument.First) ~= "`" then
					path = literal(first)
					cursor, link = first + 1, first
				end
			end
			local object, reference
			if path then
				if path:sub(-1) ~= "/" then
					object = ResolvePath(path, scriptObject, dataModel)
				end
			elseif opening then
				local required
				object, cursor, reference, required = parse(first, depth + 1)
				if required then
					return nil, start, reference
				end
			else
				return nil, start, nil
			end
			if opening and value(cursor) ~= ")" then
				return nil, start, reference
			end
			if not object or object.ClassName ~= "ModuleScript" then
				return nil, start, reference
			end
			return object,
				cursor + (if opening then 1 else 0),
				hit(start, object) or (if link then hit(link, object) else nil) or reference
		end

		function parse(start: number, depth: number): (Instance?, number, Reference?, boolean?)
			if depth > 32 then
				return nil, start, nil
			end
			local token = tokens[start]
			if not token then
				return nil, start, nil
			end
			local object, reference, required
			local cursor = start + 1
			if token.Kind == "symbol" and token.Value == "(" then
				object, cursor, reference, required = parse(cursor, depth + 1)
				if value(cursor) ~= ")" then
					return nil, start, reference
				end
				cursor += 1
			elseif token.Kind == "name" and not blocked[token.Value] then
				if token.Value == "script" then
					object = scriptObject
				elseif token.Value == "game" then
					object = dataModel
				elseif token.Value == "workspace" then
					object = world
				elseif token.Value == "require" then
					object, cursor, reference = parseRequire(start, depth)
					return object, cursor, reference, object ~= nil
				else
					local binding = declarations[token.Value]
					if binding and binding.Name < start then
						local after
						object, after, _, required = parse(binding.Value, depth + 1)
						if object and not endsBinding(after) then
							object = nil
						end
					end
				end
				reference = hit(start, object)
			end

			while object and not required do
				local punctuation = value(cursor)
				if punctuation == "." and tokens[cursor + 1] and tokens[cursor + 1].Kind == "name" then
					object = ReadMember(object, tokens[cursor + 1].Value)
					reference = reference or hit(cursor + 1, object)
					cursor += 2
				elseif punctuation == "[" and literal(cursor + 1) and value(cursor + 2) == "]" then
					object = ReadMember(object, tokens[cursor + 1].Value)
					reference = reference or hit(cursor + 1, object)
					cursor += 3
				elseif punctuation == ":" and ChildMethods[value(cursor + 1) or ""] and value(cursor + 2) == "(" then
					local method, name = value(cursor + 1) :: string, literal(cursor + 3)
					if not name or (method == "GetService" or method == "FindService") and object ~= dataModel then
						break
					end
					local close, recursive = cursor + 4, false
					if value(close) == "," and (method == "FindFirstChild" or method == "FindFirstChildWhichIsA") then
						local argument = value(close + 1)
						if argument ~= "true" and argument ~= "false" then
							break
						end
						recursive, close = argument == "true", close + 2
					elseif value(close) == "," and method == "WaitForChild" then
						local argument = tokens[close + 1]
						if not argument or argument.Kind ~= "number" then
							break
						end
						close += 2
						if value(close) == "." and tokens[close + 1] and tokens[close + 1].Kind == "number" then
							close += 2
						end
					end
					if value(close) ~= ")" then
						break
					end
					object = GetChild(object, name, method, recursive)
					reference = reference or hit(cursor + 1, object) or hit(cursor + 3, object)
					cursor = close + 1
				else
					break
				end
			end
			return object, cursor, reference, required
		end

		for candidate = wanted, math.max(1, wanted - 96), -1 do
			local token = tokens[candidate]
			local previous = value(candidate - 1)
			local before = tokens[candidate - 1]
			local grouping = value(candidate) == "("
				and (
					not before
					or before.Kind == "symbol" and previous ~= ")" and previous ~= "]" and previous ~= "}"
					or previous == "return"
					or previous == "if"
					or previous == "elseif"
					or previous == "while"
					or previous == "until"
					or previous == "and"
					or previous == "or"
					or previous == "not"
				)
			if token.Kind == "name" and previous ~= "." and previous ~= ":" or grouping then
				local _, _, reference = parse(candidate, 0)
				if reference then
					return reference
				end
			end
		end
		return nil
	end

	return table.freeze(Definitions)
end

return table.freeze({ Main = Main })
