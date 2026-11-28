--!strict

local API, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	API, Apps = d.API, d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local Language = {}
	local keywords = {
		"and",
		"break",
		"continue",
		"do",
		"else",
		"elseif",
		"end",
		"export",
		"false",
		"for",
		"function",
		"if",
		"in",
		"local",
		"nil",
		"not",
		"or",
		"repeat",
		"return",
		"then",
		"true",
		"type",
		"until",
		"while",
	}
	local globals = {
		"assert",
		"error",
		"ipairs",
		"next",
		"pairs",
		"pcall",
		"print",
		"require",
		"select",
		"tonumber",
		"tostring",
		"type",
		"typeof",
		"unpack",
		"warn",
		"xpcall",
		"game",
		"workspace",
		"script",
		"shared",
		"Enum",
		"Instance",
		"Color3",
		"Vector2",
		"Vector3",
		"CFrame",
		"UDim",
		"UDim2",
		"task",
		"math",
		"string",
		"table",
		"utf8",
		"coroutine",
		"buffer",
		"bit32",
		"os",
	}
	local globalFunctions = {
		assert = true,
		error = true,
		ipairs = true,
		next = true,
		pairs = true,
		pcall = true,
		print = true,
		require = true,
		select = true,
		tonumber = true,
		tostring = true,
		type = true,
		typeof = true,
		unpack = true,
		warn = true,
		xpcall = true,
	}
	local libraries = {
		Instance = Instance,
		math = math,
		string = string,
		table = table,
		utf8 = utf8,
		coroutine = coroutine,
		bit32 = bit32,
		buffer = buffer,
		os = os,
		task = task,
		CFrame = CFrame,
		Color3 = Color3,
		Vector2 = Vector2,
		Vector3 = Vector3,
		UDim = UDim,
		UDim2 = UDim2,
	}
	local function isPublic(member, includeDeprecated)
		local tags = member.Tags or {}
		local access = type(member.Security) == "table" and member.Security.Read or member.Security
		return not (
			tags.Hidden
			or tags.NotScriptable
			or (tags.Deprecated and not includeDeprecated)
			or type(access) == "string" and access ~= "None"
		)
	end
	local function childNames(object, add, literals)
		local ok, children = pcall(function()
			return object:GetChildren()
		end)
		if ok then
			for _, child in ipairs(children) do
				if literals or child.Name:match("^[%a_][%w_]*$") then
					add(child.Name, "Instance", child.ClassName, { ClassName = child.ClassName, TypeOnly = true })
				end
			end
		end
	end
	local function literalContext(before, masked)
		local quote, prefix = before:match('(")([^"\\\r\n]*)$')
		local singleQuote, singlePrefix = before:match("(')([^'\\\r\n]*)$")
		if singleQuote and (not quote or #singlePrefix < #prefix) then
			quote, prefix = singleQuote, singlePrefix
		end
		if not quote then
			return nil
		end
		local first = #before - #prefix + 1
		if masked:sub(first - 1, first - 1) ~= " " then
			return nil
		end
		local left = before:sub(1, first - 2)
		local bracket = left:match("()%[%s*$")
		if bracket and masked:sub(bracket, bracket) == "[" then
			return { First = first, MethodStart = bracket, Method = "[", Prefix = prefix, Quote = quote }
		end
		local methodStart, method = left:match("()([%a_][%w_]*)%s*%(%s*$")
		if not method and left:match("%f[%w_]require%s*$") then
			methodStart, method = left:match("()(require)%s*$")
		end
		if not method or masked:sub(methodStart, methodStart + #method - 1) ~= method then
			return { First = first, Prefix = prefix, Quote = quote }
		end
		return { First = first, MethodStart = methodStart, Method = method, Prefix = prefix, Quote = quote }
	end
	local function isNameStart(byte)
		return byte == 95 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122
	end
	local function nameStart(text, last, members)
		local first = last
		while first > 0 do
			local byte = text:byte(first)
			if not (isNameStart(byte) or byte >= 48 and byte <= 57 or members and (byte == 46 or byte == 58)) then
				break
			end
			first -= 1
		end
		first += 1
		while first <= last and not isNameStart(text:byte(first)) do
			first += 1
		end
		return first
	end
	local function skipSpace(text, last)
		while last > 0 do
			local byte = text:byte(last)
			if byte ~= 32 and (byte < 9 or byte > 13) then
				break
			end
			last -= 1
		end
		return last
	end
	local classNameMethods = {
		IsA = true,
		FindFirstChildOfClass = true,
		FindFirstChildWhichIsA = true,
		FindFirstAncestorOfClass = true,
		FindFirstAncestorWhichIsA = true,
	}
	local childNameMethods = {
		["["] = true,
		WaitForChild = true,
		FindFirstChild = true,
		FindFirstAncestor = true,
	}
	local function matchScore(name, query, subsequence, substring)
		local length = #query
		if length == 0 then
			return 0
		end
		local common = 0
		while common < length and name:byte(common + 1) == query:byte(common + 1) do
			common += 1
		end
		if common == 0 and length < 3 then
			return nil
		end
		local score = common > 0 and common * 10 or -30
		local longest = length
		if common < length and not name:find(query, 1, true) then
			if length > 32 or #name > 128 or #name + 1 < length then
				return nil
			end
			local found = 0
			for i = 1, length do
				if name:find(query:sub(i, i), 1, true) then
					found += 1
				end
			end
			if found < length - 1 then
				return nil
			end
			table.clear(subsequence)
			table.clear(substring)
			longest = 0
			for i = 1, #name do
				local byte = name:byte(i)
				local diagonalSequence, diagonalString = 0, 0
				for j = 1, length do
					local previousSequence, previousString = subsequence[j] or 0, substring[j] or 0
					if byte == query:byte(j) then
						subsequence[j] = diagonalSequence + 1
						substring[j] = diagonalString + 1
						longest = math.max(longest, substring[j])
					else
						subsequence[j] = math.max(previousSequence, subsequence[j - 1] or 0)
						substring[j] = 0
					end
					diagonalSequence, diagonalString = previousSequence, previousString
				end
			end
			local missing = length - (subsequence[length] or 0)
			if missing > 1 then
				return nil
			end
			score -= missing * 40
		end
		score += math.max(0, longest - 1) * 5
		if longest == length and length >= 3 then
			score += length * 16
		end
		return if score > -10 then score else nil
	end
	local function typeName(value)
		if type(value) == "table" then
			value = value.Name or value.name or value.Type
		end
		local name = tostring(value or "unknown")
		return Apps.EditorHoverTypes.FromApi(name)
	end
	local builtinTypes = {
		"any",
		"boolean",
		"buffer",
		"never",
		"nil",
		"number",
		"string",
		"thread",
		"unknown",
		"vector",
		"Axes",
		"BrickColor",
		"CFrame",
		"Color3",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"Content",
		"DateTime",
		"Enum",
		"EnumItem",
		"Faces",
		"FloatCurveKey",
		"Font",
		"NumberRange",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"OverlapParams",
		"PathWaypoint",
		"PhysicalProperties",
		"Random",
		"Ray",
		"RaycastParams",
		"RaycastResult",
		"RBXScriptConnection",
		"RBXScriptSignal",
		"Rect",
		"Region3",
		"Region3int16",
		"SharedTable",
		"TweenInfo",
		"UDim",
		"UDim2",
		"Vector2",
		"Vector2int16",
		"Vector3",
		"Vector3int16",
	}
	local datatypeMembers = Apps.EditorBuiltinSignatures.DatatypeMembers
	local libraryMembers = {}
	local builtinGlobals = {}
	for key, signature in Apps.EditorBuiltinSignatures.Signatures do
		local owner, member = key:match("^([%w_]+)%.([%w_]+)$")
		if owner then
			local members = libraryMembers[owner]
			if not members then
				members = {}
				libraryMembers[owner] = members
			end
			members[member] = signature
		elseif not key:find("[.:]") then
			builtinGlobals[key] = signature
		end
	end
	local function datatypeMember(className, name, methodOnly)
		local members = datatypeMembers[className]
		local member = members and members[name]
		if member and (member[1] == "Method" or (not methodOnly and member[1] == "Property")) then
			return member[1], member[2]
		end
		if className == "string" then
			local signature = libraryMembers.string[name]
			local remaining = signature and signature:match("^[^(]*%(%s*[%w_]+:%s*string%s*,?%s*(.*)$")
			if remaining then
				return "Method", name .. "(" .. remaining
			end
		end
	end
	local function namedType(value)
		value = Apps.EditorHoverTypes.Resolve(value)
		if type(value) == "string" then
			return value
		end
		if type(value) ~= "table" then
			return nil
		end
		if value.Kind == "singleton" then
			return value.Literal
		elseif value.Kind == "union" then
			local className
			for _, item in value.Values do
				if item == "nil" or item == "never" then
					continue
				end
				local candidate = if type(item) == "string"
					then item
					elseif type(item) == "table" and item.Kind == "singleton" then item.Literal
					else nil
				if not candidate or className and className ~= candidate then
					return nil
				end
				className = candidate
			end
			return className
		end
	end
	local function datatypeItem(className, name, kind, detail)
		return {
			Name = name,
			Kind = kind,
			Detail = detail,
			DocKey = "@roblox/globaltype/" .. className .. "." .. name,
			DocGlobal = className == "string" and "string." .. name or nil,
			TypeOnly = kind ~= "Method",
			Url = if className == "string"
				then "https://create.roblox.com/docs/reference/engine/libraries/string#" .. name
				else "https://create.roblox.com/docs/reference/engine/datatypes/" .. className .. "#" .. name,
		}
	end
	local function memberItem(className, group, member)
		local kind = if group == "Functions" then "Method" elseif group == "Events" then "Event" else "Property"
		local detail = member.Name
		if kind == "Property" then
			detail = typeName(member.ValueType or member.Type)
		elseif kind == "Event" then
			detail = "RBXScriptSignal"
		else
			local args = {}
			for _, param in ipairs(member.Parameters or {}) do
				args[#args + 1] = param.Name .. ": " .. typeName(param.Type)
			end
			detail ..= "(" .. table.concat(args, ", ") .. ")"
			if member.ReturnType then
				detail ..= ": " .. typeName(member.ReturnType)
			end
		end
		local metadata = Apps.ReflectionService.GetMetadata(className, member.Name)
		return {
			Name = member.Name,
			Kind = kind,
			Detail = detail,
			ClassName = className,
			DocKey = "@roblox/globaltype/" .. className .. "." .. member.Name,
			Deprecated = member.Tags and member.Tags.Deprecated,
			HasParameters = group == "Functions" and #(member.Parameters or {}) > 0,
			Documentation = metadata and (metadata.Summary or metadata.Description),
			CodeExample = metadata and (metadata.CodeExample or metadata.Example),
			Url = "https://create.roblox.com/docs/reference/engine/classes/" .. className .. "#" .. member.Name,
		}
	end
	local function baseType(annotation)
		return annotation
			and (annotation:match("^%s*([%a_][%w_]*)%s*%??%s*$") or annotation:match("^%s*([%a_][%w_]*)%s*<"))
	end
	local function reflectedMember(className, name, methodOnly)
		local visited = {}
		while type(className) == "string" and not visited[className] do
			visited[className] = true
			local class = API.Classes[className]
			if not class then
				return nil
			end
			for _, group in ipairs(methodOnly and { "Functions" } or { "Properties", "Functions", "Events" }) do
				for _, member in ipairs(class[group] or {}) do
					if member.Name == name and isPublic(member, true) then
						return className, group, member
					end
				end
			end
			className = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
		end
	end
	local function memberType(className, name, methodOnly)
		className = namedType(className)
		local kind, detail = datatypeMember(className, name, methodOnly)
		if kind == "Property" then
			return detail
		elseif kind == "Method" then
			return nil, detail:match("^[^(]*%b():%s*(.*)$"), detail
		end
		local _, group, member = reflectedMember(className, name, methodOnly)
		if group == "Properties" then
			return Apps.EditorHoverTypes.FromApi(typeName(member.ValueType or member.Type))
		elseif group == "Functions" then
			local returns = member.ReturnType and typeName(member.ReturnType) or "()"
			local args = {}
			for _, parameter in member.Parameters or {} do
				args[#args + 1] = parameter.Name .. ": " .. typeName(parameter.Type)
			end
			return nil, returns, name .. "(" .. table.concat(args, ", ") .. "): " .. returns
		elseif group == "Events" then
			return "RBXScriptSignal"
		end
	end
	local function typeMatches(value, expected, depth)
		local types = Apps.EditorHoverTypes
		value, expected = types.Resolve(value), types.Resolve(expected)
		if
			depth >= 8
			or not value
			or not expected
			or value == "unknown"
			or value == "any"
			or expected == "any"
			or expected == "unknown"
		then
			return false
		end
		if value == expected then
			return true
		end
		local valueKind = type(value) == "table" and value.Kind
		local expectedKind = type(expected) == "table" and expected.Kind
		if valueKind == "union" or expectedKind == "intersection" then
			local values = if valueKind == "union" then value.Values else expected.Values
			for _, variant in values do
				if
					not (
						if valueKind == "union"
							then typeMatches(variant, expected, depth + 1)
							else typeMatches(value, variant, depth + 1)
					)
				then
					return false
				end
			end
			return true
		elseif expectedKind == "union" or valueKind == "intersection" then
			local values = if expectedKind == "union" then expected.Values else value.Values
			for _, variant in values do
				if
					if expectedKind == "union"
						then typeMatches(value, variant, depth + 1)
						else typeMatches(variant, expected, depth + 1)
				then
					return true
				end
			end
			return false
		elseif valueKind == "singleton" then
			return if expectedKind == "singleton"
				then value.Literal == expected.Literal and value.Value == expected.Value
				else value.Literal == expected
		elseif valueKind == "record" and expectedKind == "record" then
			for name, field in expected.Fields do
				if not typeMatches(types.FieldType(value, name) or "nil", field, depth + 1) then
					return false
				end
			end
			return not expected.Element or typeMatches(value.Element, expected.Element, depth + 1)
		elseif valueKind == "function" and expectedKind == "function" then
			if #value.Params ~= #expected.Params or not typeMatches(value.Return, expected.Return, depth + 1) then
				return false
			end
			for index, parameter in expected.Params do
				if not typeMatches(parameter.Type, value.Params[index].Type, depth + 1) then
					return false
				end
			end
			return true
		end
		for _ = 1, 32 do
			local class = API.Classes[value]
			if not class then
				return false
			end
			value = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
			if value == expected then
				return true
			end
		end
		return false
	end
	local function singletonStrings(value, add, depth)
		value = Apps.EditorHoverTypes.Resolve(value)
		if type(value) ~= "table" or depth >= 8 then
			return
		end
		if value.Kind == "singleton" and value.Literal == "string" then
			add(value.Value, Apps.EditorHoverTypes.Describe(value))
		elseif value.Kind == "union" then
			for _, item in value.Values do
				singletonStrings(item, add, depth + 1)
			end
		end
	end
	local function signatureType(signature, symbols)
		if not signature then
			return nil
		end
		local arguments, returns = signature:match("^[^(]*(%b())%s*:%s*(.*)$")
		if arguments then
			return Apps.EditorHoverTypes.ParseAnnotation(arguments .. " -> " .. returns, symbols)
		end
	end
	function Language.New()
		local self = {
			source = nil,
			masked = "",
			identifiers = {},
			declarations = {},
			Symbols = Apps.EditorSymbols.New(),
			HoverRevision = 0,
		}
		local receiverDefinitions = Apps.EditorDefinitions and Apps.EditorDefinitions.New()
		local hoverCache
		function self:Index(text, checkpoint)
			if self.source == text then
				return true
			end
			local symbols = Apps.EditorSymbols.New()
			local identifiers, declarations = {}, {}
			local cancelled = {}
			local function check()
				if not checkpoint() then
					error(cancelled, 0)
				end
			end
			if checkpoint then
				local ok, problem = pcall(symbols.Index, symbols, text, check)
				if not ok then
					if problem ~= cancelled then
						error(problem, 0)
					end
					return false
				end
			else
				symbols:Index(text)
			end
			for index, declaration in ipairs(symbols.Declarations) do
				if checkpoint and index % 128 == 0 and not checkpoint() then
					return false
				end
				local name = declaration.Name
				local entries = declarations[name]
				if not entries then
					entries = {}
					declarations[name] = entries
				end
				entries[#entries + 1] = declaration
			end
			local record = symbols.Record
			if record then
				local tokenAt = Apps.EditorParser.TokenAt
				for i = 1, record.TokenCount do
					if checkpoint and i % 256 == 1 and not checkpoint() then return false end
					local kind, first, last = tokenAt(record, i)
					if kind == 281 or kind >= 291 then
						local before = if first > 1 then text:byte(first - 1) else nil
						if before ~= 46 and before ~= 58 then identifiers[text:sub(first, last - 1)] = true end
					end
				end
			else
				local nextCheck = 0
				for first, name in symbols.Masked:gmatch("()([%a_][%w_]*)") do
					if checkpoint and first >= nextCheck then
						nextCheck = first + 4096
						if not checkpoint() then
							return false
						end
					end
					local before = first > 1 and symbols.Masked:sub(first - 1, first - 1)
					if before ~= "." and before ~= ":" then
						identifiers[name] = true
					end
				end
			end
			self.Symbols, self.masked = symbols, symbols.Masked
			self.identifiers, self.declarations = identifiers, declarations
			self.source = text
			self.HoverAnalysis = nil
			hoverCache = nil
			self.HoverRevision += 1
			return true
		end
		local function declarationAt(name, position, declarations, symbols)
			local declaration
			for _, entry in ipairs((declarations or self.declarations)[name] or {}) do
				if entry.Position > position then
					break
				end
				if not entry.ScopeEnd or position < entry.ScopeEnd then declaration = entry end
			end
			local parameter = (symbols or self.Symbols):Parameter(name, position)
			if parameter and (not declaration or declaration.Position < parameter.Position) then
				return parameter
			end
			return declaration
		end
		local function variableType(declaration, context, position, symbols)
			if declaration.Annotation and declaration.Annotation ~= "" then
				return declaration.Annotation
			end
			local name = declaration.Name
			symbols = symbols or self.Symbols
			local _, class = symbols:Resolve(name, context, position)
			if class then
				return class
			end
			local expression
			for _, binding in ipairs(symbols.Bindings[name] or {}) do
				if binding.Position < position then
					if not binding.ScopeEnd or position < binding.ScopeEnd then expression = binding.Expression end
				else
					break
				end
			end
			if expression then
				local value = expression:match("^%s*(.-)%s*$")
				if tonumber(value) then
					return "number"
				elseif value == "true" or value == "false" then
					return "boolean"
				elseif value:match("^[\"'`]") then
					return "string"
				elseif value:match("^%{") then
					return "table"
				end
			end
		end
		local function aliasFor(annotation, symbols)
			local name = baseType(annotation)
			local visited = {}
			while name and not visited[name] do
				visited[name] = true
				local alias = (symbols or self.Symbols).Types[name]
				if not alias or next(alias.Fields) then
					return alias, name
				end
				local following = baseType(alias.Annotation)
				if not following then
					return alias, name
				end
				name = following
			end
		end
		local function hover(text, position, context, checkpoint, work)
			if not self:Index(text, checkpoint) then
				return nil
			end
			context = context or {}
			local symbols, masked, declarations = self.Symbols, self.masked, self.declarations
			if not masked:sub(position, position):match("[%w_]") then
				return nil
			end
			local first, last = position, position + 1
			while first > 1 and masked:sub(first - 1, first - 1):match("[%w_]") do
				first -= 1
			end
			while masked:sub(last, last):match("[%w_]") do
				last += 1
			end
			local name = masked:sub(first, last - 1)
			if not name:match("^[%a_]") then
				return nil
			end
			local left = masked:sub(math.max(1, first - 512), first - 1)
			local receiver, separator = left:match("([%a_][%w_%.:]*)%s*([.:])%s*$")
			if receiver and (receiver:sub(-1) == "." or receiver:sub(-1) == ":") then
				receiver = nil
			end
			local qualified = receiver and receiver .. separator .. name or name
			local types = Apps.EditorHoverTypes
			local modules = Apps.EditorModuleTypes
			local moduleRevision = Apps.ReferenceSource.Revision and Apps.ReferenceSource.Revision()
			local cache = hoverCache
			if
				not cache
				or cache.Busy
				or cache.Script ~= context.Script
				or cache.ModuleRevision ~= moduleRevision
				or cache.SourceRevision ~= context.ModuleRevision
			then
				cache = {
					Revision = self.HoverRevision,
					Script = context.Script,
					ModuleRevision = moduleRevision,
					SourceRevision = context.ModuleRevision,
				}
			end
			cache.Busy, cache.Checkpoint = true, checkpoint
			work.Cache = cache
			if cache.Result == nil then
				local resolveModule = modules.Resolver(text, context, memberType, function()
					return not cache.Checkpoint or cache.Checkpoint()
				end)
				cache.Result = types.Analyze(text, symbols, memberType, checkpoint, { Require = resolveModule })
					or false
			end
			local analysis = cache.Result
			local occurrence = analysis and analysis.Entries[first]
			local inferred = types.Resolve(types.TypeAt(occurrence))
			if (checkpoint and not checkpoint()) or self.source ~= text then
				return nil
			end
			if occurrence and occurrence.Path then
				qualified = occurrence.Path
			end
			local function display(item)
				item = Apps.EditorApiDocumentation.Apply(item)
				item.First, item.Last = first, last
				return item
			end
			local declaration = declarationAt(qualified, first, declarations, symbols)
			if occurrence and occurrence.Path and not receiver then
				declaration = nil
			elseif declaration and occurrence and occurrence.Slot and occurrence.Slot.First ~= declaration.Position then
				declaration = nil
			end
			local alias = symbols.Types[name]
			local isType = symbols:InType(first) or alias and alias.Position == first
			local imported = isType and analysis and analysis.ImportedTypes[first]
			if imported then
				local exported = types.ExportedTypes(imported)
				alias = exported and exported[name]
			elseif isType and receiver then
				alias = nil
			end
			if isType and alias then
				return display({
					Name = name,
					Kind = "Type",
					Detail = alias.Signature,
					Documentation = alias.Documentation,
				})
			elseif not isType and declaration then
				local refined = occurrence and occurrence.Slot and occurrence.Slot.Refined
				local annotation = (refined and inferred and types.Describe(inferred))
					or declaration.Annotation
					or (inferred and types.Describe(inferred))
					or variableType(declaration, context, first, symbols)
				local detail = declaration.Signature
				if annotation then
					if declaration.Kind == "Function" and type(inferred) == "table" and inferred.Kind == "function" then
						detail = name .. annotation:sub(#"function" + 1)
					elseif declaration.Kind ~= "Function" then
						detail = name .. ": " .. annotation
					end
				end
				if detail or declaration.Documentation then
					return display({
						Name = name,
						Kind = declaration.Kind,
						Detail = detail or name,
						Documentation = declaration.Documentation,
					})
				end
				return nil
			end
			if not receiver and inferred and name == "function" then
				return display({ Name = name, Kind = "Function", Detail = types.Describe(inferred) })
			end
			local member = (receiver or occurrence and occurrence.Owner) and name
			if member then
				local localReceiver = receiver and declarationAt(receiver, first, declarations, symbols)
				local typed, base =
					aliasFor(localReceiver and variableType(localReceiver, context, first, symbols), symbols)
				local field = typed and typed.Fields[member]
				if field then
					return display({
						Name = member,
						Kind = field.Kind,
						Detail = field.Signature,
						Documentation = field.Documentation,
					})
				end
				local className
				if receiver then
					local _, resolved = symbols:Resolve(receiver, context, first)
					className = resolved
				end
				local ownerType = occurrence and namedType(occurrence.Owner)
				className = className
					or base
					or ownerType
					or ({ game = "DataModel", workspace = "Workspace", script = "LuaSourceContainer" })[receiver]
				local kind, detail = datatypeMember(className, member, separator == ":")
				if kind then
					return display(
						datatypeItem(
							className,
							member,
							kind,
							if kind == "Property" then member .. ": " .. detail else detail
						)
					)
				end
				local owner, group, candidate = reflectedMember(className, member, separator == ":")
				if owner then
					local item = memberItem(owner, group, candidate)
					if group == "Properties" then
						item.Detail = member .. ": " .. types.FromApi(item.Detail)
					end
					return display(item)
				end
				if inferred then
					local callable = type(inferred) == "table" and inferred.Kind == "function"
					local typeText = types.Describe(inferred)
					return display({
						Name = member,
						Kind = if callable then "Function" else "Property",
						Detail = if callable
							then member .. typeText:sub(#"function" + 1)
							else member .. ": " .. typeText,
						Documentation = if callable then inferred.Documentation else nil,
					})
				end
				if localReceiver then
					return nil
				end
				local enumType = receiver and receiver:match("^Enum%.([%w_]+)$")
				if enumType then
					return display({
						Name = member,
						Kind = "Enum",
						Detail = qualified,
						DocKey = "@roblox/enum/" .. enumType .. "." .. member,
					})
				end
			end
			if isType and (table.find(builtinTypes, name) or API.Classes[name]) then
				return display({ Name = name, Kind = "Type", Detail = name, DocKey = "@roblox/globaltype/" .. name })
			end
			if inferred then
				local detail = types.Describe(inferred)
				if occurrence.Slot then
					return display({ Name = name, Kind = "Variable", Detail = name .. ": " .. detail })
				end
				return display({ Name = name, Kind = "Global", Detail = detail, DocGlobal = name })
			end
			if occurrence and occurrence.Slot then
				return nil
			end
			local callable = globalFunctions[qualified] or Apps.EditorApiDocumentation.Signature(qualified) ~= nil
			local library = not member and libraries[name]
			local candidate = {
				Name = member or name,
				Kind = callable and "Function" or "Global",
				Detail = library and (name .. ": table") or qualified,
				DocGlobal = qualified,
				DocCallable = callable or member ~= nil,
			}
			local call = analysis and analysis.Calls[first]
			if call then
				local shape = types.Describe(call)
				local signature = Apps.EditorApiDocumentation.Signature(qualified)
				local parameter = signature and signature:match("%(([%a_][%w_]*):") or "value"
				candidate.HoverDetail = name .. "(" .. parameter .. ": " .. shape .. "): " .. shape
			end
			local enriched = display(candidate)
			if
				library
				or enriched.Detail ~= qualified
				or enriched.Documentation
				or enriched.Url
				or enriched.HoverDetail
			then
				return enriched
			end
		end
		function self:Hover(text, position, context, checkpoint)
			local work = {}
			local cancelled = false
			if checkpoint then
				local check = checkpoint
				checkpoint = function()
					cancelled = cancelled or not check()
					return not cancelled
				end
			end
			local ok, item = pcall(function()
				local result = hover(text, position, context, checkpoint, work)
				if work.Cache and checkpoint and not checkpoint() then
					return nil
				end
				return result
			end)
			local cache = work.Cache
			if cache then
				cache.Busy, cache.Checkpoint = false, nil
				if ok and not cancelled and cache.Revision == self.HoverRevision then
					hoverCache, self.HoverAnalysis = cache, cache.Result
				else
					item = if ok then nil else item
					if hoverCache == cache then
						hoverCache, self.HoverAnalysis = nil, nil
					end
				end
			end
			if not ok then
				error(item, 0)
			end
			return item
		end
		local function complete(text, caret, context, checkpoint, work)
			caret = math.clamp(caret, 1, #text + 1)
			local first = nameStart(text, caret - 1)
			local prefix = text:sub(first, caret - 1)
			local previous = skipSpace(text, first - 1)
			local previousChar = if previous > 0 then text:sub(previous, previous) else ""
			local separatorAt = if previousChar == "." or previousChar == ":" then previous else nil
			local separator = separatorAt and previousChar
			local receiver, receiverAt, receiverLast
			if separatorAt then
				receiverLast = skipSpace(text, separatorAt - 1)
				receiverAt = nameStart(text, receiverLast, true)
				if receiverAt <= receiverLast then
					receiver = text:sub(receiverAt, receiverLast)
				end
			end
			local before
			if prefix == "" and not previousChar:match("[%.:=<|&>(,{]") then
				before = text:sub(1, caret - 1)
				if not before:match("[\"'][^\"'\r\n]*$") then
					return nil
				end
			end
			local tail = text:match("^[%w_]*", caret) or ""
			local indexSource = text
			if separator and prefix ~= "" then
				indexSource = text:sub(1, first - 1) .. "_" .. text:sub(caret + #tail)
			end
			if not self:Index(indexSource, checkpoint) then
				return nil
			end
			local symbols, masked = self.Symbols, self.masked
			local identifiers, declarations = self.identifiers, self.declarations
			context = context or {}
			local function declarationBefore(name)
				return declarationAt(name, first - 1, declarations, symbols)
			end
			local function expectsFunction()
				local prefixText = masked:sub(math.max(1, first - 512), first - 1)
				prefixText = prefixText:gsub("[%a_][%w_]*[%.:]$", "")
				if prefixText:match("%f[%w_]typeof%s*%(%s*$") or prefixText:match("%f[%w_]function%s+[%w_%.:]*$") then
					return true
				end
				local target = prefixText:match("%f[%w_]local%s+([%a_][%w_]*)%s*:[^\n=]+=%s*$")
					or prefixText:match("([%a_][%w_]*)%s*=%s*$")
				local declaration = target and declarationBefore(target)
				local annotation = declaration and declaration.Annotation
				if not annotation then
					return false
				end
				local alias = symbols.Types[annotation]
				annotation = alias and alias.Annotation or annotation
				return annotation:match("^%s*%b()%s*%-%>") ~= nil
			end
			local receiverSource
			local function resolveObject(at)
				if not receiverDefinitions or #text > 65536 then
					return nil
				end
				local closing = masked:sub(at, at)
				if closing == ")" or closing == "]" then
					local opening = closing == ")" and "(" or "["
					local depth = 1
					for cursor = at - 1, math.max(1, at - 512), -1 do
						local char = masked:sub(cursor, cursor)
						if char == closing then
							depth += 1
						elseif char == opening then
							depth -= 1
							if depth == 0 then
								at = text:find("%S", cursor + 1) or at
								local char = text:sub(at, at)
								if char == '"' or char == "'" then
									at += 1
								end
								break
							end
						end
					end
				end
				receiverSource = receiverSource or indexSource
				if checkpoint and not receiverDefinitions.Prime(receiverSource, checkpoint) then
					return nil
				end
				local result =
					receiverDefinitions.Resolve(receiverSource, at, context.Script, context.Game, context.Workspace)
				local object = result and result.Object
				return object, object and object.ClassName
			end
			local function receiverObject(receiver, at)
				local object, className
				if receiver then
					object, className = symbols:Resolve(receiver, context, first - 1)
				end
				if not object and not className then
					object, className = resolveObject(at)
				end
				local declaration = receiver and declarationBefore(receiver)
				local _, annotation =
					aliasFor(declaration and variableType(declaration, context, first - 1, symbols), symbols)
				if
					not className
					and annotation
					and (API.Classes[annotation] or datatypeMembers[annotation] or annotation == "string")
				then
					className = annotation
				end
				return object, className
			end
			local literal
			local indexedPrefix = if indexSource == text then prefix else "_"
			local prefixIsCode = masked:sub(first, first + #indexedPrefix - 1) == indexedPrefix
			if not prefixIsCode or prefix == "" then
				before = before or text:sub(1, caret - 1)
				literal = literalContext(before, masked)
				if not literal and not prefixIsCode then
					return nil
				end
			end
			local all, seen, scores = {}, {}, {}
			local missingModules
			local function analyzeCompletion(typeQualifier, expectedAt)
				local modules = Apps.EditorModuleTypes
				local source = text:sub(1, if expectedAt then expectedAt - 1 else separatorAt)
				local analysis = self.MemberAnalysis
				local revision = Apps.ReferenceSource.Revision and Apps.ReferenceSource.Revision()
				if
					not analysis
					or analysis.Busy
					or analysis.Source ~= source
					or analysis.Script ~= context.Script
					or analysis.ModuleRevision ~= context.ModuleRevision
					or analysis.Revision ~= revision
					or analysis.Qualifier ~= typeQualifier
					or analysis.ExpectedAt ~= expectedAt
					or os.clock() - analysis.Time > 3
				then
					local budget = { Checkpoint = checkpoint }
					local resolveModule, missing = modules.Resolver(source, context, memberType, function()
						return not budget.Checkpoint or budget.Checkpoint()
					end)
					local result = Apps.EditorHoverTypes.Analyze(source, symbols, memberType, checkpoint, {
						Separator = if typeQualifier or expectedAt then nil else separatorAt,
						TypeQualifier = typeQualifier,
						ExpectedPosition = expectedAt,
						Require = resolveModule,
					})
					analysis = {
						Source = source,
						Script = context.Script,
						Revision = revision,
						Qualifier = typeQualifier,
						ModuleRevision = context.ModuleRevision,
						ExpectedAt = expectedAt,
						Time = os.clock(),
						Result = result,
						Missing = missing,
						Budget = budget,
					}
					if checkpoint and not checkpoint() then
						return nil
					end
					if typeQualifier and result then
						result.ExportedTypes = Apps.EditorHoverTypes.ExportedTypes(result.TypeNamespace)
					end
					if checkpoint and not checkpoint() then
						return nil
					end
					self.MemberAnalysis = analysis
				end
				analysis.Busy = true
				analysis.Budget.Checkpoint = checkpoint
				work.Analysis = analysis
				missingModules = analysis.Missing
				return analysis.Result
			end
			local function inferReceiver(typeQualifier)
				local result = analyzeCompletion(typeQualifier)
				return result and if typeQualifier then result.ExportedTypes else result.Receiver
			end
			local typeContext = not literal and (symbols:InType(first) or separatorAt and symbols:InType(separatorAt))
			local expectedAnalysis
			if not typeContext and (literal or not separator) and caret <= 65537 then
				expectedAnalysis = analyzeCompletion(nil, literal and literal.First or first)
			end
			local expected = expectedAnalysis and expectedAnalysis.Expected
			local expectedKind = expectedAnalysis and expectedAnalysis.ExpectedKind
			local referenceOnly
			local subsequence, substring = {}, {}
			local lastPrefix, lowerPrefix
			local checked = 0
			local cancelled = false
			local function eligible(name, deprecated)
				checked += 1
				if checked % 64 == 0 and checkpoint and not checkpoint() then
					cancelled = true
				end
				if cancelled then
					return false
				end
				if seen[name] then
					return false
				end
				if lastPrefix ~= prefix then
					lastPrefix, lowerPrefix = prefix, prefix:lower()
					table.clear(scores)
				end
				if scores[name] == nil then
					scores[name] = matchScore(name:lower(), lowerPrefix, subsequence, substring) or false
				end
				local score = scores[name]
				return score ~= false and (not deprecated or score > 0)
			end
			local function add(name, kind, detail, metadata, insertion)
				local deprecated = metadata and metadata.Deprecated
				if not eligible(name, deprecated) then
					return
				end
				seen[name] = true
				local item = metadata or {}
				item.Name = name
				item.Kind = kind
				item.Detail = detail or kind
				item.InsertText = insertion
				if kind == "Method" and separator == "." and not item.PreserveSeparator then
					item.MethodSeparator = separatorAt
				end
				local exactType = expected and item.Type and typeMatches(item.Type, expected, 0)
				local returnType = type(item.Type) == "table" and item.Type.Kind == "function" and item.Type.Return
					or item.ReturnType
				if type(returnType) == "table" and returnType.Kind == "pack" then
					returnType = returnType.Values[1]
				end
				item.TypeScore = if item.Expected or exactType
					then 2
					elseif expected and returnType and typeMatches(returnType, expected, 0) then 1
					else 0
				if kind == "Function" or kind == "Method" then
					if referenceOnly == nil then
						referenceOnly = expectsFunction()
					end
					item.InsertCall = not (referenceOnly or exactType or expectedKind == "TableKey")
					if item.InsertCall and item.HasParameters == nil then
						if item.DocGlobal then
							item.HasParameters = Apps.EditorApiDocumentation.TakesArguments(item.DocGlobal)
						else
							item.HasParameters = not item.Detail:match("^[^(]*%(%s*%)")
						end
					end
				end
				item.Score = scores[name] - (deprecated and 10 or 0)
				all[#all + 1] = item
			end
			local last
			if typeContext then
				local function addType(name, detail, docKey, documentation)
					add(
						name,
						"Type",
						detail or name,
						{ TypeOnly = not documentation, Documentation = documentation, DocKey = docKey }
					)
				end
				if separator == "." and receiver == "Enum" then
					for name, enum in pairs(API.Enums or {}) do
						if isPublic(enum) then
							addType(name, "Enum." .. name, "@roblox/global/Enum." .. name)
						end
					end
				elseif separator == "." and receiver and receiver:match("^[%a_][%w_]*$") and separatorAt <= 65536 then
					for name, alias in pairs(inferReceiver(receiverAt) or {}) do
						addType(name, alias.Signature, nil, alias.Documentation)
					end
				else
					for name, alias in pairs(symbols.Types) do
						addType(name, alias.Signature, nil, alias.Documentation)
					end
					local generics = symbols:GenericsAt(caret)
					if generics then
						for name in (generics .. ","):gmatch("([%a_][%w_]*)%s*%.?%.?%.?%s*[,=]") do
							addType(name)
						end
					end
					for _, name in ipairs(builtinTypes) do
						addType(name, name, "@roblox/globaltype/" .. name)
					end
					for name, class in pairs(API.Classes) do
						if isPublic(class) then
							addType(name, name, "@roblox/globaltype/" .. name)
						end
					end
				end
				last = caret + #(text:match("^[%w_]*", caret) or "")
			elseif literal then
				first, prefix = literal.First, literal.Prefix
				local method = literal.Method
				local receiver = literal.MethodStart and before:sub(1, literal.MethodStart - 1) or ""
				local function addLiteral(name, kind, detail, metadata, insertion)
					local insert = (insertion or name)
						:gsub("\\", "\\\\")
						:gsub(literal.Quote, "\\" .. literal.Quote)
						:gsub("[\r\n\t]", { ["\r"] = "\\r", ["\n"] = "\\n", ["\t"] = "\\t" })
					add(name, kind, detail, metadata, insert)
				end
				singletonStrings(expected, function(value, label)
					addLiteral(value, "Value", label, { TypeOnly = true, Expected = true })
				end, 0)
				if
					method == "new"
					and receiver:match("%f[%w_]Instance%s*%.%s*$")
					and not declarationBefore("Instance")
				then
					for name, class in pairs(API.Classes) do
						local tags = class.Tags or {}
						if not (tags.NotCreatable or tags.Service) and isPublic(class) then
							addLiteral(name, "Instance", name, { ClassName = name, TypeOnly = true })
						end
					end
				elseif
					(method == "GetService" or method == "FindService")
					and receiver:match("%f[%w_]game%s*:%s*$")
					and not declarationBefore("game")
				then
					for name, class in pairs(API.Classes) do
						if class.Tags and class.Tags.Service and isPublic(class) then
							addLiteral(name, "Instance", name, { ClassName = name, TypeOnly = true })
						end
					end
				elseif
					classNameMethods[method]
					or childNameMethods[method]
					or method == "GetPropertyChangedSignal"
					or method == "GetAttribute"
					or method == "SetAttribute"
					or method == "GetAttributeChangedSignal"
				then
					local lastReceiver = method == "[" and #receiver or receiver:match("():%s*$")
					if not lastReceiver then
						return nil
					end
					local ending = method == "[" and lastReceiver or lastReceiver - 1
					while ending > 0 and receiver:sub(ending, ending):match("%s") do
						ending -= 1
					end
					local expression = receiver:sub(1, ending):match("([%a_][%w_%.:]*)$")
					local object, className = receiverObject(expression, ending)
					if classNameMethods[method] and (object or API.Classes[className]) then
						for name, class in API.Classes do
							if isPublic(class) then
								addLiteral(name, "Type", name, { TypeOnly = true })
							end
						end
					elseif method == "GetPropertyChangedSignal" and className then
						local visited = {}
						while API.Classes[className] and not visited[className] do
							visited[className] = true
							local class = API.Classes[className]
							for _, member in class.Properties or {} do
								if eligible(member.Name) and isPublic(member) then
									local item = memberItem(className, "Properties", member)
									addLiteral(member.Name, item.Kind, item.Detail, item)
								end
							end
							className = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
						end
					elseif object and childNameMethods[method] then
						if method == "FindFirstAncestor" then
							object = object.Parent
							for _ = 1, 64 do
								if not object then
									break
								end
								addLiteral(
									object.Name,
									"Instance",
									object.ClassName,
									{ ClassName = object.ClassName, TypeOnly = true }
								)
								object = object.Parent
							end
						else
							childNames(object, addLiteral, true)
						end
					elseif object and object.GetAttributes then
						local ok, attributes = pcall(object.GetAttributes, object)
						for name, value in ok and attributes or {} do
							addLiteral(name, "Property", typeof(value), { TypeOnly = true })
						end
					end
				elseif
					method == "require"
					and not receiver:match("[%.:%w_]$")
					and not declarationBefore("require")
					and Apps.EditorDefinitions
				then
					local folder, partial = prefix:match("^(.*[/])([^/]*)$")
					if folder then
						local root = Apps.EditorDefinitions.ResolvePath(folder, context.Script, context.Game or game)
						if root then
							prefix = partial
							first += #folder
							childNames(root, function(name, kind, detail, metadata)
								if name:find("/", 1, true) then
									return
								end
								if detail == "ModuleScript" then
									addLiteral(name, kind, detail, metadata)
								elseif root == (context.Game or game) or detail == "Folder" or detail == "Model" then
									addLiteral(name, kind, detail, metadata, name .. "/")
								end
							end, true)
						end
					else
						for _, root in ipairs({ "./", "../", "@self/", "@game/", "@/" }) do
							if Apps.EditorDefinitions.ResolvePath(root, context.Script, context.Game or game) then
								addLiteral(root, "Instance", root, { TypeOnly = true })
							end
						end
					end
				end
				local cursor = caret
				while cursor <= #text do
					local char = text:sub(cursor, cursor)
					if char == literal.Quote or char == "\n" or char == "\r" then
						break
					elseif char == "\\" and cursor < #text then
						cursor += 1
					end
					cursor += 1
				end
				last = cursor
			else
				if not receiver and receiverLast and receiverLast > 0 and text:byte(receiverLast) == 41 then
					receiver = text:sub(1, first - 1):match([=[(Instance%.new%s*%(%s*["'][%w_]+["']%s*%))%s*[%.:]%s*$]=])
				end
				if separator and masked:sub(separatorAt, separatorAt) ~= separator then
					return nil
				end
				if prefix == "" and not separator and not expected then
					return nil
				end
				if separator then
					local declaration = receiver and declarationBefore(receiver)
					local typed =
						aliasFor(declaration and variableType(declaration, context, first - 1, symbols), symbols)
					local library = receiver and not declaration and libraries[receiver]
					local builtins = receiver and not declaration and libraryMembers[receiver]
					local enumType = receiver and receiver:match("^Enum%.([%w_]+)$")
					local inferred
					local globalObject = not declaration
						and (receiver == "game" or receiver == "workspace" or receiver == "script")
					if
						not library
						and not builtins
						and not globalObject
						and receiver ~= "Enum"
						and not enumType
						and separatorAt <= 65536
					then
						local types = Apps.EditorHoverTypes
						inferred = inferReceiver()
						for name in pairs(types.Members(inferred)) do
							if not name:match("^[%a_][%w_]*$") or table.find(keywords, name) or not eligible(name) then
								continue
							end
							local field = types.Resolve(types.FieldType(inferred, name))
							local declaredField = typed and typed.Fields[name]
							if declaredField and declaredField.Documentation then
								add(
									name,
									declaredField.Kind,
									declaredField.Signature,
									{ Documentation = declaredField.Documentation }
								)
								continue
							end
							local callable = type(field) == "table" and field.Kind == "function"
							if callable then
								local detail = types.Describe(field):sub(#"function" + 1)
								add(name, field.Method and "Method" or "Function", name .. detail, {
									Documentation = field.Documentation,
									PreserveSeparator = not field.Method,
								})
							elseif separator == "." then
								add(name, "Property", types.Describe(field), { TypeOnly = true })
							end
						end
					end
					if typed and next(typed.Fields) then
						for name, field in pairs(typed.Fields) do
							if separator == "." or field.Kind == "Function" then
								add(name, field.Kind, field.Signature, { Documentation = field.Documentation })
							end
						end
					elseif receiver == "Enum" then
						for name, enum in pairs(API.Enums or {}) do
							if isPublic(enum) then
								add(name, "Enum", "Enum." .. name, {
									TypeOnly = true,
									DocKey = "@roblox/global/Enum." .. name,
								})
							end
						end
					elseif enumType then
						local enum = (API.Enums or {})[enumType]
						for _, item in ipairs(enum and enum.Items or {}) do
							add(item.Name, "Enum", "Enum." .. enumType .. "." .. item.Name, {
								TypeOnly = true,
								DocKey = "@roblox/enum/" .. enumType .. "." .. item.Name,
							})
						end
					elseif library or builtins then
						for name, signature in builtins or {} do
							add(
								name,
								"Function",
								signature,
								{ DocGlobal = receiver .. "." .. name, DocCallable = true }
							)
						end
						for name, member in datatypeMembers[receiver] or {} do
							if member[1] == "Value" then
								add(name, "Value", member[2], { DocGlobal = receiver .. "." .. name, TypeOnly = true })
							end
						end
						for name, value in library or {} do
							if type(name) == "string" then
								add(
									name,
									type(value) == "function" and "Function" or "Value",
									receiver .. "." .. name,
									{
										DocGlobal = receiver .. "." .. name,
										DocCallable = type(value) == "function",
									}
								)
							end
						end
					elseif type(inferred) ~= "table" or namedType(inferred) then
						local endOfReceiver = separatorAt - 1
						while masked:sub(endOfReceiver, endOfReceiver):match("%s") do
							endOfReceiver -= 1
						end
						local object, className = receiverObject(receiver, endOfReceiver)
						className = className
							or namedType(inferred)
							or ({ game = "DataModel", workspace = "Workspace", script = "LuaSourceContainer" })[receiver]
						local members = if className == "string"
							then libraryMembers.string
							else datatypeMembers[className]
						for name in members or {} do
							local kind, detail = datatypeMember(className, name, separator == ":")
							if kind and eligible(name) then
								add(name, kind, detail, datatypeItem(className, name, kind, detail))
							end
						end
						local visited = {}
						while className and not visited[className] do
							visited[className] = true
							local class = API.Classes[className]
							if not class then
								break
							end
							for _, group in
								ipairs(separator == ":" and { "Functions" } or { "Properties", "Functions", "Events" })
							do
								for _, member in ipairs(class[group] or {}) do
									local deprecated = member.Tags and member.Tags.Deprecated
									if not eligible(member.Name, deprecated) or not isPublic(member, true) then
										continue
									end
									local item = memberItem(className, group, member)
									add(item.Name, item.Kind, item.Detail, item)
								end
							end
							className = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
						end
						if object and separator == "." then
							childNames(object, add)
						end
					end
				else
					local types = Apps.EditorHoverTypes
					if expectedKind == "TableKey" then
						for name in types.Members(expected) do
							if name:match("^[%a_][%w_]*$") and not table.find(keywords, name) then
								local assignment = text:match("^[%w_]*%s*=", caret)
								add(
									name,
									"Property",
									types.Describe(types.FieldType(expected, name)),
									{ TypeOnly = true, Expected = true },
									if assignment then nil else name .. " = "
								)
							end
						end
					end
					singletonStrings(expected, function(value, label)
						add(value, "Value", label, { TypeOnly = true, Expected = true }, string.format("%q", value))
					end, 0)
					local visible = expectedAnalysis and expectedAnalysis.Visible
					for name in visible or identifiers do
						if not eligible(name) then
							continue
						end
						local slot = visible and visible[name]
						local declaration = declarationBefore(name)
						if slot and declaration and declaration.Position ~= slot.First then
							declaration = nil
							for _, candidate in declarations[name] or {} do
								if candidate.Position == slot.First then
									declaration = candidate
									break
								end
							end
						end
						if not declaration and not slot then
							continue
						end
						local inferred = slot and types.Resolve(slot.Type)
						local callable = type(inferred) == "table" and inferred.Kind == "function"
						local kind = if callable then "Function" else declaration and declaration.Kind or "Variable"
						local detail = declaration and declaration.Signature
						local metadata =
							{ Documentation = declaration and declaration.Documentation, Local = true, Type = inferred }
						if callable then
							detail = name .. types.Describe(inferred):sub(#"function" + 1)
						elseif kind == "Variable" or kind == "Parameter" then
							local annotation = declaration and not (slot and slot.Refined) and declaration.Annotation
							if annotation and not inferred and expected then
								metadata.Type = types.ParseAnnotation(annotation, symbols)
							end
							local description = annotation
								or (inferred and types.Describe(inferred))
								or declaration and variableType(declaration, context, first - 1, symbols)
							if description then
								detail = description
								metadata.TypeOnly = not metadata.Documentation
							end
						elseif expected and kind == "Function" then
							metadata.Type = signatureType(detail, symbols)
						end
						add(name, kind == "Parameter" and "Variable" or kind, detail, metadata)
					end
					for _, name in ipairs(keywords) do
						add(name, "Keyword")
					end
					for _, name in ipairs(globals) do
						local callable = globalFunctions[name]
						if eligible(name) then
							add(name, callable and "Function" or "Global", builtinGlobals[name] or name, {
								DocGlobal = name,
								DocCallable = callable,
								Type = expected and signatureType(builtinGlobals[name], symbols),
							})
						end
					end
					for name, signature in builtinGlobals do
						if name ~= "PluginManager" and name ~= "DebuggerManager" and eligible(name) then
							add(name, "Function", signature, {
								DocGlobal = name,
								DocCallable = true,
								Type = expected and signatureType(signature, symbols),
							})
						end
					end
					for name in libraryMembers do
						add(name, "Global", name .. ": table", { DocGlobal = name })
					end
					if not visible then
						local lowerPrefix = prefix:lower()
						for name in pairs(identifiers) do
							if name ~= prefix and name:lower():sub(1, #prefix) == lowerPrefix then
								add(name, "Identifier")
							end
						end
					end
				end
				last = caret + #tail
			end
			if cancelled or checkpoint and not checkpoint() then
				return nil
			end
			if missingModules and context.OnModuleReady then
				Apps.EditorModuleTypes.RequestMissing(missingModules, context)
			end
			table.sort(all, function(a, b)
				local aExact, bExact = a.Name == prefix, b.Name == prefix
				if aExact ~= bExact then
					return aExact
				end
				if a.TypeScore ~= b.TypeScore then
					return a.TypeScore > b.TypeScore
				end
				if a.Score ~= b.Score then
					return a.Score > b.Score
				end
				if (a.Local == true) ~= (b.Local == true) then
					return a.Local == true
				end
				local aKeyword, bKeyword = a.Kind == "Keyword", b.Kind == "Keyword"
				if aKeyword ~= bKeyword then
					return not aKeyword
				end
				if #a.Name ~= #b.Name then
					return #a.Name < #b.Name
				end
				return a.Name < b.Name
			end)
			while #all > 100 do
				all[#all] = nil
			end
			if #all == 0 or (#all == 1 and not all[1].InsertCall and (all[1].InsertText or all[1].Name) == prefix) then
				return nil
			end
			return { First = first, Last = last, Items = all }
		end
		function self:Complete(text, caret, context, checkpoint)
			local work = {}
			if checkpoint then
				local check = checkpoint
				checkpoint = function()
					local valid = not work.Cancelled and check()
					work.Cancelled = not valid
					return valid
				end
			end
			local ok, result = pcall(complete, text, caret, context, checkpoint, work)
			local analysis = work.Analysis
			if analysis then
				analysis.Busy = false
				analysis.Budget.Checkpoint = nil
				if self.MemberAnalysis == analysis and (work.Cancelled or not ok) then
					self.MemberAnalysis = nil
				end
			end
			if not ok then
				error(result, 0)
			end
			return result
		end
		return self
	end
	function Language.MemberSignature(className, name, includeReceiver)
		local kind, detail = datatypeMember(className, name, true)
		if kind then
			if includeReceiver then
				local separator = detail:sub(#name + 2, #name + 2) == ")" and "" or ", "
				detail = name .. "(self: " .. className .. separator .. detail:sub(#name + 2)
			end
			return detail, className
		end
		local seen = {}
		while className and not seen[className] do
			seen[className] = true
			local class = API.Classes[className]
			if not class then
				break
			end
			for _, member in ipairs(class.Functions or {}) do
				if member.Name == name then
					local args = {}
					if includeReceiver then
						args[1] = "self: " .. className
					end
					for _, param in ipairs(member.Parameters or {}) do
						args[#args + 1] = param.Name .. ": " .. typeName(param.Type)
					end
					return name .. "(" .. table.concat(args, ", ") .. ")" .. (member.ReturnType and ": " .. typeName(
						member.ReturnType
					) or ""),
						className
				end
			end
			className = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
		end
	end
	return Language
end
return { InitDeps = InitDeps, Main = Main }
