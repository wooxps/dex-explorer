--!strict

local Apps

local function InitDeps(deps)
	Apps = deps.Apps
end

local function Main()
	local Types = {}
	local precedence = {
		["or"] = 1,
		["and"] = 2,
		["=="] = 3,
		["~="] = 3,
		["<"] = 3,
		[">"] = 3,
		["<="] = 3,
		[">="] = 3,
		[".."] = 4,
		["+"] = 5,
		["-"] = 5,
		["*"] = 6,
		["/"] = 6,
		["//"] = 6,
		["%"] = 6,
		["^"] = 8,
	}
	local blocked = {
		["end"] = true,
		["else"] = true,
		["elseif"] = true,
		["until"] = true,
		["then"] = true,
		["do"] = true,
		["local"] = true,
		["return"] = true,
		["in"] = true,
		["break"] = true,
		["continue"] = true,
		["for"] = true,
		["while"] = true,
		["repeat"] = true,
	}
	local ends = { ["end"] = true }
	local branches = { ["elseif"] = true, ["else"] = true, ["end"] = true }
	local missing = { Value = "" }
	local typeNames = { int = "number", int64 = "number", float = "number", double = "number", bool = "boolean" }
	local tableTransforms = { ["table.freeze"] = "readonly", ["table.clone"] = "copy" }
	local comparisons = { ["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }
	local function loadImport(value)
		if value.Load then
			local load = value.Load
			value.Load = nil
			value.Value, value.Types = load()
		end
	end
	local function resolve(value)
		for _ = 1, 8 do
			if type(value) ~= "table" or value.Kind ~= "import" then
				return value
			end
			loadImport(value)
			value = value.Value
		end
	end

	local function describe(value, depth, nested, budget)
		if type(value) == "table" and value.Kind == "import" then
			value = value.Value
		end
		budget[1] -= 1
		if budget[1] < 0 then
			return "…"
		end
		if type(value) ~= "table" then
			return value or "unknown"
		end
		if depth >= 6 then
			return "…"
		end
		local parts = {}
		if value.Kind == "singleton" then
			return value.Literal == "string" and string.format("%q", value.Value) or value.Value
		elseif value.Kind == "pack" then
			for _, variant in ipairs(value.Values) do
				parts[#parts + 1] = describe(variant, depth + 1, nested, budget)
			end
			return "(" .. table.concat(parts, ", ") .. ")"
		elseif value.Kind == "variadic" then
			return "..." .. describe(value.Type, depth + 1, nested, budget)
		elseif value.Kind == "union" or value.Kind == "intersection" then
			local seen = {}
			for _, variant in ipairs(value.Values) do
				local label = describe(variant, depth + 1, nested, budget)
				if not seen[label] then
					seen[label] = true
					parts[#parts + 1] = label
				end
			end
			return table.concat(parts, value.Kind == "union" and " | " or " & ")
		elseif value.Kind == "function" then
			for index, param in ipairs(value.Params) do
				if index > 16 then
					parts[index] = "…"
					break
				end
				local label = describe(param.Type, depth + 1, true, budget)
				parts[index] = if param.Name then param.Name .. ": " .. label else label
			end
			return (nested and "" or "function")
				.. (value.Generics or "")
				.. "("
				.. table.concat(parts, ", ")
				.. ")"
				.. (nested and " -> " or ": ")
				.. describe(value.Return, depth + 1, true, budget)
		end
		local names = {}
		for name in pairs(value.Fields) do
			names[#names + 1] = name
		end
		table.sort(names)
		for index, name in ipairs(names) do
			if index > 16 then
				parts[#parts + 1] = "…"
				break
			end
			local key = name:match("^[%a_][%w_]*$") and name or ("[" .. string.format("%q", name) .. "]")
			parts[#parts + 1] = key .. ": " .. describe(value.Fields[name], depth + 1, true, budget)
		end
		if value.Element then
			local item = describe(value.Element, depth + 1, true, budget)
			if #parts == 0 then
				return "{" .. item .. "}"
			end
			parts[#parts + 1] = "[number]: " .. item
		end
		if value.Indexer then
			parts[#parts + 1] = "[string]: " .. describe(value.Indexer, depth + 1, true, budget)
		end
		return if #parts > 0 then "{ " .. table.concat(parts, ", ") .. " }" else "{}"
	end

	local function combine(values)
		if #values == 0 then
			return nil
		elseif #values == 1 then
			return values[1]
		end
		local variants, seen = {}, {}
		for _, value in ipairs(values) do
			local candidates = type(value) == "table" and value.Kind == "union" and value.Values or { value }
			for _, candidate in ipairs(candidates) do
				local key = if type(candidate) == "table" and candidate.Kind == "import"
					then candidate
					else describe(candidate, 0, true, { 64 })
				if not seen[key] then
					seen[key] = true
					variants[#variants + 1] = candidate
					if #variants == 8 then
						return { Kind = "union", Values = variants }
					end
				end
			end
		end
		return if #variants == 1 then variants[1] else { Kind = "union", Values = variants }
	end

	local function skippable(value)
		return value == "nil" or value == "never"
	end

	local function fieldType(owner, field, depth)
		owner = resolve(owner)
		depth = depth or 0
		if depth >= 8 then
			return nil
		end
		if type(owner) ~= "table" then
			return nil
		elseif owner.Kind == "record" then
			return if field == nil
				then owner.Element
				else owner.Fields[field] or owner.Indexer or fieldType(owner.Prototype, field, depth + 1)
		elseif owner.Kind == "union" or owner.Kind == "intersection" then
			local fields = {}
			for _, variant in ipairs(owner.Values) do
				if skippable(variant) then
					continue
				end
				local value = fieldType(variant, field, depth + 1)
				if value then
					fields[#fields + 1] = value
				elseif owner.Kind == "union" then
					return nil
				end
			end
			return combine(fields)
		end
	end

	local function copyRecord(value, readonly)
		if type(value) == "table" and value.Kind == "record" then
			return {
				Kind = "record",
				Fields = table.clone(value.Fields),
				Element = value.Element,
				Indexer = value.Indexer,
				Readonly = readonly,
				Prototype = value.Prototype,
				Sealed = value.Sealed,
			}
		end
		return value
	end

	local function typeAt(occurrence)
		if occurrence then
			return occurrence.Type or occurrence.Slot and occurrence.Slot.Type
		end
	end
	local function constrain(occurrence, inferred)
		local slot = occurrence and occurrence.Slot
		if
			slot
			and slot.Parameter
			and not slot.Type
			and type(inferred) == "string"
			and inferred ~= "nil"
			and inferred ~= "any"
		then
			slot.Type = inferred
		end
	end

	local function firstType(value)
		return if type(value) == "table" and value.Kind == "pack" then value.Values[1] else value
	end

	local function bindGenerics(parameter, argument, generics, bindings, depth)
		if not argument or depth > 6 then
			return
		end
		if type(parameter) == "string" and generics[parameter] then
			local prior = bindings[parameter]
			bindings[parameter] = prior and combine({ prior, argument }) or argument
		elseif type(parameter) == "table" and parameter.Kind == "record" then
			bindGenerics(parameter.Element, fieldType(argument), generics, bindings, depth + 1)
			for field, value in pairs(parameter.Fields) do
				bindGenerics(value, fieldType(argument, field), generics, bindings, depth + 1)
			end
		elseif type(parameter) == "table" and parameter.Kind == "union" and argument ~= "nil" then
			for _, alternative in ipairs(parameter.Values) do
				if type(alternative) == "string" and generics[alternative] then
					bindGenerics(alternative, argument, generics, bindings, depth + 1)
				end
			end
		end
	end
	local function substituteGenerics(value, bindings, depth)
		if type(value) == "string" then
			return bindings[value] or value
		end
		if type(value) ~= "table" or depth > 6 then
			return value
		end
		if value.Kind == "union" or value.Kind == "intersection" or value.Kind == "pack" then
			local items = table.create(#value.Values)
			for index, item in ipairs(value.Values) do
				items[index] = substituteGenerics(item, bindings, depth + 1)
			end
			return if value.Kind == "union" then combine(items) else { Kind = value.Kind, Values = items }
		elseif value.Kind == "record" then
			local result = copyRecord(value, value.Readonly)
			for field, item in pairs(value.Fields) do
				result.Fields[field] = substituteGenerics(item, bindings, depth + 1)
			end
			result.Element = substituteGenerics(value.Element, bindings, depth + 1)
			result.Indexer = substituteGenerics(value.Indexer, bindings, depth + 1)
			return result
		elseif value.Kind == "function" then
			local result = table.clone(value)
			result.Params = table.create(#value.Params)
			for index, parameter in ipairs(value.Params) do
				result.Params[index] =
					{ Name = parameter.Name, Type = substituteGenerics(parameter.Type, bindings, depth + 1) }
			end
			result.Return = substituteGenerics(value.Return, bindings, depth + 1)
			return result
		end
		return value
	end

	local function callableType(value)
		if type(value) ~= "table" then
			return nil
		elseif value.Kind == "function" then
			return value
		elseif value.Kind == "union" then
			local result
			for _, alternative in ipairs(value.Values) do
				if not skippable(alternative) then
					if result or type(alternative) ~= "table" or alternative.Kind ~= "function" then
						return nil
					end
					result = alternative
				end
			end
			return result
		end
	end

	local function parseType(tokens, aliases, substitutions, loading, resolveAlias)
		local index = 1
		local function token()
			return tokens[index] or missing
		end
		local function take(value)
			local current = token()
			if current.Value == value and (current.Kind == "symbol" or current.Kind == "name") then
				index += 1
				return current
			end
		end
		local read
		local function atom(depth)
			if depth > 20 then
				return nil
			end
			if take("{") then
				local fields, element, indexer = {}, nil, nil
				while token().First and token().Value ~= "}" do
					local name = token()
					local nextToken = tokens[index + 1]
					local accessModifier = name.Value == "read" or name.Value == "write"
					if accessModifier and nextToken and (nextToken.Kind == "name" or nextToken.Value == "[") then
						index += 1
						name, nextToken = token(), tokens[index + 1]
					end
					if name.Kind == "name" and nextToken and (nextToken.Value == ":" or nextToken.Value == "?") then
						index += 1
						local optional = take("?")
						take(":")
						local value = read(1, depth + 1) or "unknown"
						fields[name.Value] = if optional then combine({ value, "nil" }) else value
					elseif take("[") then
						local key = read(1, depth + 1)
						take("]")
						take(":")
						local value = read(1, depth + 1) or "unknown"
						if key == "number" then
							element = value
						elseif key == "string" then
							indexer = value
						elseif type(key) == "table" and key.Kind == "singleton" and key.Literal == "string" then
							fields[key.Value] = value
						end
					else
						element = read(1, depth + 1)
						if not element then
							break
						end
					end
					if not take(",") and not take(";") then
						break
					end
				end
				take("}")
				return { Kind = "record", Fields = fields, Element = element, Indexer = indexer, Sealed = true }
			elseif take("(") then
				local params, values = {}, {}
				while token().First and token().Value ~= ")" do
					local name
					local after = tokens[index + 1]
					if token().Kind == "name" and after and after.Value == ":" then
						name = token().Value
						index += 2
					end
					local value = read(1, depth + 1)
					if not value then
						break
					end
					values[#values + 1] = value
					params[#params + 1] = { Name = name, Type = value }
					if not take(",") then
						break
					end
				end
				take(")")
				if take("->") then
					return { Kind = "function", Params = params, Return = read(1, depth + 1) or "unknown" }
				end
				return if #values == 1
					then values[1]
					elseif #values == 0 then "()"
					else { Kind = "pack", Values = values }
			elseif take("...") then
				local value = read(3, depth + 1) or "unknown"
				return { Kind = "variadic", Type = value }
			end
			local name = token()
			if name.Kind == "string" or name.Value == "true" or name.Value == "false" then
				index += 1
				return {
					Kind = "singleton",
					Literal = name.Kind == "string" and "string" or "boolean",
					Value = name.Value,
				}
			end
			if name.Kind ~= "name" then
				return nil
			end
			index += 1
			local nameValue = name.Value
			local alias = aliases[nameValue]
			if take(".") and token().Kind == "name" then
				local qualified = token().Value
				index += 1
				alias = resolveAlias and resolveAlias(nameValue, qualified)
				nameValue ..= "." .. qualified
			end
			local genericArguments
			if take("<") then
				genericArguments = {}
				repeat
					local argument = read(1, depth + 1)
					if not argument then
						break
					end
					genericArguments[#genericArguments + 1] = argument
				until not take(",")
				take(">")
			end
			if substitutions and substitutions[nameValue] then
				return substitutions[nameValue]
			end
			if alias and not loading[alias] and loading.Depth < 12 and alias.Annotation then
				local aliasTokens = Apps.EditorDefinitions.Tokenize(alias.Annotation)
				if not aliasTokens then
					return nameValue
				end
				local bindings
				if alias.Generics and genericArguments then
					bindings = {}
					local argument = 0
					for generic in alias.Generics:gmatch("[%a_][%w_]*") do
						argument += 1
						bindings[generic] = genericArguments[argument]
					end
				end
				loading[alias] = true
				loading.Depth += 1
				local result = parseType(aliasTokens, alias.Aliases or aliases, bindings, loading, resolveAlias)
				loading.Depth -= 1
				loading[alias] = nil
				return result or nameValue
			end
			return nameValue
		end
		function read(minimum, depth)
			local value = atom(depth)
			if not value then
				return nil
			end
			while take("?") do
				value = combine({ value, "nil" })
			end
			while true do
				local operator = token().Value
				local priority = if operator == "&" then 2 elseif operator == "|" then 1 else 0
				if priority < minimum then
					break
				end
				index += 1
				local rhs = read(priority + 1, depth + 1)
				if not rhs then
					break
				end
				value = if operator == "|"
					then combine({ value, rhs })
					else { Kind = "intersection", Values = { value, rhs } }
			end
			return value
		end
		return read(1, 0)
	end

	local function semanticType(node, aliases, resolveAlias, substitutions, loading, depth)
		if not node or depth > 24 then return nil end
		local function read(child)
			return semanticType(child, aliases, resolveAlias, substitutions, loading, depth + 1)
		end
		local kind = node.kind
		if kind == "TypeReference" then
			local name = node.name
			local alias = aliases[name]
			if node.prefix then
				alias = resolveAlias and resolveAlias(node.prefix, name)
				name = node.prefix .. "." .. name
			end
			if substitutions and substitutions[name] then return substitutions[name] end
			if alias and alias.Ast and not loading[alias] then
				local bound = {}
				local i = 0
				loading[alias] = true
				for _, parameters in {alias.TypeParameters or {}, alias.TypePacks or {}} do
					for _, param in parameters do
						i += 1
						local arg = node.parameters[i]
						if arg then
							bound[param.name] = read(arg.type or arg.typePack)
						elseif param.defaultValue then
							bound[param.name] = semanticType(param.defaultValue, alias.Aliases or aliases, resolveAlias, bound, loading, depth + 1)
						end
					end
				end
				local value = semanticType(alias.Ast, alias.Aliases or aliases, resolveAlias, bound, loading, depth + 1)
				loading[alias] = nil
				return value or name
			end
			return name
		elseif kind == "TypeTable" then
			local fields = {}
			for _, prop in node.props do fields[prop.name.value] = read(prop.type) or "unknown" end
			local result = {Kind = "record", Fields = fields, Sealed = true}
			if node.indexer then
				local key = read(node.indexer.indexType)
				local value = read(node.indexer.resultType)
				if key == "number" then result.Element = value
				elseif key == "string" then result.Indexer = value
				elseif type(key) == "table" and key.Literal == "string" then fields[key.Value] = value end
			end
			return result
		elseif kind == "TypeUnion" or kind == "TypeIntersection" or kind == "TypePackExplicit" then
			local values = {}
			for _, member in node.types do table.insert(values, read(member) or "unknown") end
			if node.tailType then table.insert(values, read(node.tailType) or "unknown") end
			if kind == "TypeUnion" then return combine(values) end
			if kind == "TypeIntersection" then return {Kind = "intersection", Values = values} end
			return if #values == 1 then values[1] elseif #values == 0 then "()" else {Kind = "pack", Values = values}
		elseif kind == "TypeFunction" then
			local params = {}
			for i, param in node.argTypes.types do
				local named = node.argNames[i]
				params[i] = {Name = named and named.name or nil, Type = read(param) or "unknown"}
			end
			if node.argTypes.tailType then table.insert(params, {Type = read(node.argTypes.tailType)}) end
			return {Kind = "function", Params = params, Return = read(node.returnTypes) or "unknown"}
		elseif kind == "TypeOptional" then return "nil"
		elseif kind == "TypeGroup" then return read(node.type)
		elseif kind == "TypePackGeneric" then return substitutions and substitutions[node.genericName] or node.genericName
		elseif kind == "TypePackVariadic" then return {Kind = "variadic", Type = read(node.variadicType) or "unknown"}
		elseif kind == "TypeSingletonBool" or kind == "TypeSingletonString" then
			return {Kind = "singleton", Literal = if kind == "TypeSingletonString" then "string" else "boolean", Value = tostring(node.value)}
		elseif kind == "TypeTypeof" then return "typeof" end
		return nil
	end

	function Types.ParseAnnotation(annotation, symbols, resolveAlias)
		if type(annotation) ~= "string" or #annotation > 8192 then
			return annotation
		end
		local aliases = symbols and (symbols.Types or symbols) or {}
		if Apps.EditorParser then
			local node = symbols and symbols.AnnotationNodes and symbols.AnnotationNodes[annotation]
			if not node then
				local parsed = Apps.EditorParser.Parse("type __Annotation = " .. annotation)
				local declaration = parsed and parsed.Root and parsed.Root.body[1]
				if parsed and parsed.Diagnostics.Passed and declaration then node = declaration.type end
			end
			if node then
				local value = semanticType(node, aliases, resolveAlias, nil, {}, 0)
				if value then return value end
			end
		end
		local tokens = Apps.EditorDefinitions.Tokenize(annotation)
		return tokens
			and parseType(tokens, symbols and (symbols.Types or symbols) or {}, nil, { Depth = 0 }, resolveAlias)
	end

	function Types.Analyze(source, symbols, resolveMember, checkpoint, options)
		if #source > 65536 then
			return nil
		end
		local record = symbols.Record
		if not record or record.Source ~= source then
			record = Apps.EditorParser and Apps.EditorParser.Parse(source, checkpoint)
			if Apps.EditorParser and not record then return nil end
		end
		local aliases = symbols.Types
		local tokens = options and options.Tokens or Apps.EditorDefinitions.Tokenize(source, checkpoint, false, record)
		if not tokens or #tokens > 12000 then
			return nil
		end
		local trackOccurrences = not (options and options.ExportOnly)
		local index, operations, nextCheck = 1, 0, 512
		local cancelled = false
		local scopes = { {} }
		local expectedPosition = options and options.ExpectedPosition
		local expectation
		local visible
		local parsedTypes, signatures = {}, {}
		local entries, calls, receivers, returns, importedTypes = {}, {}, {}, {}, {}
		local declarations = {}
		for _, item in ipairs(symbols.Declarations) do
			declarations[item.Position] = item
		end
		local syntax
		local ranges
		if record and record.Diagnostics.Passed then
			syntax = Apps.EditorParser.ExpressionIndex(record, checkpoint)
			if not syntax then return nil end
		else
			ranges = table.clone(symbols.TypeRanges)
			table.sort(ranges, function(a, b)
				return if a.First == b.First then a.Last > b.Last else a.First < b.First
			end)
		end
		local nextRange = 1
		local expr, block, readFunction
		local function findSlot(name)
			for level = #scopes, 1, -1 do
				local slot = scopes[level][name]
				if slot then
					return slot
				end
			end
		end
		local function captureScope()
			visible = {}
			for level = #scopes, 1, -1 do
				for name, slot in pairs(scopes[level]) do
					if not visible[name] then
						visible[name] = table.clone(slot)
					end
				end
			end
		end
		local function current(offset)
			if cancelled then
				return missing
			end
			if checkpoint and index >= nextCheck then
				nextCheck = index + 512
				if not checkpoint() then
					cancelled = true
					return missing
				end
			end
			local token = tokens[index + (offset or 0)] or missing
			if
				not offset
				and expectedPosition
				and not visible
				and token.First
				and (token.First >= expectedPosition or token.Last > expectedPosition)
			then
				captureScope()
			end
			if not offset and options and options.TypeQualifier and token.First == options.TypeQualifier then
				local slot = findSlot(token.Value)
				receivers.TypeNamespace = slot and slot.Type
			end
			return token
		end
		local function expect(value, kind, first, last)
			if value and expectedPosition and expectedPosition >= first and expectedPosition <= last then
				if not expectation or first >= expectation.First and last <= expectation.Last then
					expectation = { Type = value, Kind = kind, First = first, Last = last }
				end
			end
		end
		local function take(value)
			local token = current()
			if token.Value == value and (token.Kind == "symbol" or token.Kind == "name") then
				index += 1
				return token
			end
			return nil
		end
		local function bind(token, value, parameter, declared)
			local slot = { Type = value, Parameter = parameter, Declared = declared, First = token.First }
			scopes[#scopes][token.Value] = slot
			if trackOccurrences then
				entries[token.First] = { Slot = slot }
			end
			return slot
		end
		local function readTypeTokens(last)
			while current().First and current().First < last do
				local token = current()
				if trackOccurrences and token.Kind == "name" and current(1).Value == "." and current(2).Kind == "name" then
					local slot = findSlot(token.Value)
					if slot and type(slot.Type) == "table" and slot.Type.Kind == "import" then
						importedTypes[current(2).First] = slot.Type
					end
				end
				index += 1
			end
		end
		local function annotation()
			local start = current().First
			if not start then
				return nil
			end
			if syntax then
				local last = syntax.TypeEnds[start]
				if last then
					readTypeTokens(last)
					return source:sub(start, last - 1)
				end
			else
				while ranges[nextRange] and ranges[nextRange].Last <= start do
					nextRange += 1
				end
				for rangeIndex = nextRange, #ranges do
					local range = ranges[rangeIndex]
					if range.First > start then
						break
					end
					if start >= range.First and start < range.Last then
						readTypeTokens(range.Last)
						return source:sub(start, range.Last - 1):match("^(.-)%s*$")
					end
				end
			end
			local token = current()
			if token.Kind == "name" then
				index += 1
				return token.Value
			end
		end
		local function parseAnnotation(raw)
			if not raw then
				return nil
			end
			if parsedTypes[raw] then
				return parsedTypes[raw]
			end
			local value = Types.ParseAnnotation(raw, symbols, function(module, name)
				local slot = findSlot(module)
				local imported = slot and Types.ExportedTypes(slot.Type)
				return imported and imported[name]
			end) or raw
			if not raw:find("[%w_]%s*%.%s*[%w_]") then
				parsedTypes[raw] = value
			end
			return value
		end
		local function signatureType(occurrence)
			local signature = occurrence.Signature
				or (occurrence.Path and Apps.EditorApiDocumentation.Signature(occurrence.Path))
			if not signature then
				return nil
			end
			if not signatures[signature] then
				local params, result = signature:match("^[^(]*(%b()):%s*(.+)$")
				signatures[signature] = params and callableType(parseAnnotation(params .. " -> " .. result)) or false
			end
			return signatures[signature] or nil
		end
		local function lookup(token)
			local slot = findSlot(token.Value)
			if slot then
				return { Slot = slot, First = token.First }
			end
			local name = token.Value
			return {
				First = token.First,
				Path = name,
				Type = ({ game = "DataModel", workspace = "Workspace", script = "LuaSourceContainer" })[name],
			}
		end
		local function refineSlot(condition, truthy)
			if not condition then
				return
			end
			if condition.Negated then
				return refineSlot(condition.Negated, not truthy)
			end
			local slot, name, equality, test = condition.Slot, condition.Name, false, nil
			if condition.Guard then
				slot, name, test = condition.Guard.Slot, condition.Guard.Name, condition.Guard.Type
				equality = truthy ~= condition.Guard.Invert
			end
			if not slot or not name or slot.Type == nil then
				return
			end
			local value = slot.Type
			local variants = type(value) == "table" and value.Kind == "union" and value.Values or { value }
			local narrowed = {}
			for _, variant in ipairs(variants) do
				if test then
					local variantType = type(variant) == "table" and variant.Kind == "singleton" and variant.Literal
						or variant
					if (variantType == test) == equality then
						narrowed[#narrowed + 1] = variant
					end
				else
					local falsy = variant == "nil"
						or type(variant) == "table"
							and variant.Kind == "singleton"
							and variant.Literal == "boolean"
							and variant.Value == "false"
					if variant == "boolean" then
						narrowed[#narrowed + 1] = { Kind = "singleton", Literal = "boolean", Value = tostring(truthy) }
					elseif falsy ~= truthy then
						narrowed[#narrowed + 1] = variant
					end
				end
			end
			local refined = combine(narrowed) or (test and equality and test)
			if refined and refined ~= value then
				local narrowedSlot = table.clone(slot)
				narrowedSlot.Type = refined
				narrowedSlot.Refined = true
				scopes[#scopes][name] = narrowedSlot
			end
		end
		local function parseTable(depth, expectedType, opening)
			local fields, values = {}, {}
			while true do
				expect(expectedType, "TableKey", opening, current().Last or #source + 1)
				if not current().First or current().Kind == "symbol" and current().Value == "}" then
					break
				end
				local key
				local separator
				if current().Kind == "name" and current(1).Value == "=" then
					key = current()
					separator = current(1)
					index += 2
				elseif take("[") then
					key = current().Kind == "string" and current() or nil
					expr(0, depth + 1)
					take("]")
					separator = take("=")
				end
				local expectedField = fieldType(expectedType, key and key.Value)
				local value = expr(0, depth + 1, expectedField)
				if separator then
					expect(expectedField, "Value", separator.Last, current().First or #source + 1)
				end
				if not value then
					break
				end
				if key then
					fields[key.Value] = firstType(typeAt(value)) or "unknown"
					if key.Kind == "name" then
						if trackOccurrences then
							entries[key.First] = value
						end
					end
				else
					values[#values + 1] = firstType(typeAt(value)) or "unknown"
				end
				local delimiter = take(",") or take(";")
				if not delimiter then
					break
				end
				opening = delimiter.Last
			end
			take("}")
			return { Kind = "record", Fields = fields, Element = combine(values) }
		end
		local function parseCall(value, depth)
			local args = {}
			local callable = callableType(resolve(typeAt(value))) or signatureType(value)
			local parameterOffset = 0
			if callable then
				if callable.Method and not value.MethodCall then
					parameterOffset = -1
				elseif not callable.Method and value.MethodCall and not value.Path and not value.Signature then
					parameterOffset = 1
				end
			end
			local bindings
			if callable and callable.Generics then
				bindings = {}
			end
			local function expectedParameter(position)
				local param = callable and callable.Params[position + parameterOffset]
				if not param then
					return nil
				end
				return bindings and substituteGenerics(param.Type, bindings, 0) or param.Type
			end
			local opening = take("(")
			if opening then
				while true do
					local position = #args + 1
					local expectedArg = expectedParameter(position)
					local arg
					if current().First and not (current().Kind == "symbol" and current().Value == ")") then
						arg = expr(0, depth + 1, expectedArg)
					end
					expect(expectedArg, "Value", opening.Last, current().First or #source + 1)
					if not arg then
						break
					end
					args[#args + 1] = arg
					if bindings and expectedArg then
						bindGenerics(
							callable.Params[position + parameterOffset].Type,
							firstType(typeAt(arg)),
							callable.GenericNames,
							bindings,
							0
						)
					end
					opening = take(",")
					if not opening then
						break
					end
				end
				take(")")
			elseif current().Kind == "symbol" and current().Value == "{" then
				local brace = take("{")
				args[1] = { Type = parseTable(depth + 1, expectedParameter(1), brace.Last) }
			else
				index += 1
				args[1] = { Type = "string" }
			end
			local result
			if value.Path == "require" and options and options.Require then
				local position = value.First
				local requireType = options.Require
				result = {
					Kind = "import",
					Load = function()
						return requireType(position)
					end,
				}
			elseif value.Path == "setmetatable" then
				local base = resolve(typeAt(args[1]))
				local prototype = fieldType(typeAt(args[2]), "__index")
				if type(base) == "table" and base.Kind == "record" then
					result = copyRecord(base, base.Readonly)
					result.Prototype = prototype
				end
			elseif value.Path and tableTransforms[value.Path] then
				local input = resolve(typeAt(args[1]))
				result = copyRecord(input, tableTransforms[value.Path] == "readonly")
				if trackOccurrences and input and input ~= "unknown" and value.First then
					calls[value.First] = input
				end
			elseif callable then
				if bindings and not opening and #args == 1 then
					local param = callable.Params[1 + parameterOffset]
					if param and not next(bindings) then
						bindGenerics(param.Type, firstType(typeAt(args[1])), callable.GenericNames, bindings, 0)
					end
				end
				result = bindings and substituteGenerics(callable.Return, bindings, 0) or callable.Return
				for index, argument in ipairs(args) do
					constrain(argument, expectedParameter(index))
				end
			elseif value.Path then
				local signature = value.Signature or value.Path and Apps.EditorApiDocumentation.Signature(value.Path)
				result = signature and signature:match("^[^(]*%b():%s*(.+)$")
				local parameters = signature and signature:match("^[^(]*%(([^()]*)%)")
				if parameters then
					local paramIndex = 0
					for param in (parameters .. ","):gmatch("([^,]*),") do
						paramIndex += 1
						local expected = param:match(":%s*([%w_]+)%??%s*$") or param:match("^%s*([%w_]+)%??%s*$")
						if expected == "number" or expected == "string" or expected == "boolean" then
							constrain(args[paramIndex], expected)
						end
					end
				end
			end
			if value.Path == "Instance.new" or value.Path == "game:GetService" then
				result = value.ClassArgument or result
			end
			return {
				Type = result or value.Return,
				Guarded = if value.Path == "type" or value.Path == "typeof" then args[1] else nil,
			}
		end
		local function binaryResult(operator, result, rhs)
			if comparisons[operator] then
				constrain(result, typeAt(rhs))
				constrain(rhs, typeAt(result))
				local guard
				if rhs and (operator == "==" or operator == "~=") then
					local checked, check = result, rhs
					if result.Type == "nil" or rhs.Guarded then
						checked, check = rhs, result
					end
					local test = if checked.Guarded
						then check.String
						elseif check.Type == "nil" then "nil"
						else nil
					checked = checked.Guarded or checked
					if test and checked.Slot then
						guard =
							{ Slot = checked.Slot, Name = checked.Name, Type = test, Invert = operator == "~=" }
					end
				end
				result = { Type = "boolean", Guard = guard }
			elseif operator == "or" or operator == "and" then
				result = { Type = combine({ typeAt(result) or "unknown", typeAt(rhs) or "unknown" }) }
			else
				local inferred = if operator == ".." then "string" else "number"
				constrain(result, inferred)
				constrain(rhs, inferred)
				result = { Type = inferred }
			end
			return result
		end
		function expr(minimum, depth, expectedType, node)
			operations += 1
			local token = current()
			if depth > 32 or operations > 18000 or not token.First or token.Kind == "name" and blocked[token.Value] then
				return nil
			end
			node = node or (minimum == 0 and syntax and syntax.Expressions[token.First]) or nil
			local finish = node and record.Starts[node.location.end_.x + 1] + node.location.end_.y
			if node and node.kind == "ExprBinary" then
				local chain = {}
				while node.kind == "ExprBinary" do
					chain[#chain + 1] = node
					node = node.left
				end
				local result = expr(0, depth + 1, nil, node)
				if not result then return nil end
				for i = #chain, 1, -1 do
					local operator = current()
					if not precedence[operator.Value] then break end
					index += 1
					local rhs = expr(0, depth + 1, nil, chain[i].right)
					result = binaryResult(operator.Value, result, rhs)
				end
				return result
			end
			index += 1
			local value = token.Value
			local result
			if token.Kind == "number" then
				result = { Type = "number" }
			elseif token.Kind == "string" or token.Kind == "opaque" then
				result = { Type = "string", String = if token.Kind == "string" then token.Value else nil }
			elseif value == "true" or value == "false" then
				result = { Type = "boolean" }
			elseif value == "nil" then
				result = { Type = "nil" }
			elseif value == "function" then
				result = { Type = readFunction(depth + 1) }
				if trackOccurrences then
					entries[token.First] = result
				end
			elseif value == "if" then
				expr(0, depth + 1)
				take("then")
				local values = { typeAt(expr(0, depth + 1)) or "unknown" }
				while take("elseif") do
					expr(0, depth + 1)
					take("then")
					values[#values + 1] = typeAt(expr(0, depth + 1)) or "unknown"
				end
				if take("else") then
					values[#values + 1] = typeAt(expr(0, depth + 1)) or "unknown"
				end
				result = { Type = combine(values) }
			elseif value == "{" then
				result = { Type = parseTable(depth + 1, expectedType, token.Last) }
			elseif value == "(" then
				result = expr(0, depth + 1, expectedType)
				take(")")
			elseif value == "not" or value == "-" or value == "#" then
				local operand = expr(7, depth + 1, nil, node and node.kind == "ExprUnary" and node.expr or nil)
				if value == "-" then
					constrain(operand, "number")
				end
				result = {
					Type = if value == "not" then "boolean" else "number",
					Negated = if value == "not" then operand else nil,
				}
			elseif token.Kind == "name" then
				result = lookup(token)
				result.Name = value
				if trackOccurrences then
					entries[token.First] = result
				end
			else
				index -= 1
				return nil
			end
			while result and current().First and (not finish or current().First < finish) do
				local nextToken = current()
				local operator = if nextToken.Kind == "symbol" or nextToken.Kind == "name" then nextToken.Value else ""
				if operator == "." or operator == ":" then
					local member = current(1)
					local receiver = firstType(typeAt(result))
					if options and nextToken.First == options.Separator then
						receivers.Type = receiver
						receivers.Reached = true
					end
					if
						operator == ":"
						and nextToken.First ~= (options and options.Separator)
						and current(2).Value ~= "("
						and current(2).Value ~= "{"
						and current(2).Kind ~= "string"
					then
						break
					end
					if member.Kind ~= "name" then
						break
					end
					index += 2
					local path = result.Path and result.Path .. operator .. member.Value
					local reflected, returns, signature = resolveMember(receiver, member.Value, operator == ":")
					result = {
						Type = fieldType(receiver, member.Value) or reflected,
						Return = returns,
						Path = path,
						First = member.First,
						Signature = signature,
						Owner = receiver,
						Member = member.Value,
						MethodCall = operator == ":",
					}
					if trackOccurrences then
						entries[member.First] = result
					end
				elseif take("[") then
					local key = current().Kind == "string" and current().Value
					expr(0, depth + 1)
					take("]")
					local owner = firstType(typeAt(result))
					result = { Type = fieldType(owner, key or nil), Owner = key and owner, Member = key }
				elseif operator == "(" or operator == "{" or current().Kind == "string" then
					result.ClassArgument = operator == "(" and current(1).Kind == "string" and current(1).Value or nil
					result = parseCall(result, depth)
				elseif take("::") then
					result = { Type = parseAnnotation(annotation()) or typeAt(result) }
				else
					local priority = precedence[operator]
					if not priority or priority < minimum then
						break
					end
					index += 1
					local rhs = expr(priority + ((operator == "^" or operator == "..") and 0 or 1), depth + 1)
					result = binaryResult(operator, result, rhs)
				end
			end
			return result
		end

		function readFunction(depth, target, methodOwner)
			local params, returned = {}, {}
			local fn = { Kind = "function", Params = params, Return = "()" }
			if target then
				target.Type = fn
			end
			local generic = take("<")
			if generic then
				while current().First and current().Value ~= ">" and current().Value ~= "(" do
					index += 1
				end
				local closing = take(">")
				fn.Generics = closing and source:sub(generic.First, closing.Last - 1)
				if fn.Generics then
					fn.GenericNames = {}
					for name in fn.Generics:gmatch("[%a_][%w_]*") do
						fn.GenericNames[name] = true
					end
				end
			end
			if depth > 32 or not take("(") then
				return fn
			end
			scopes[#scopes + 1] = {}
			if methodOwner then
				scopes[#scopes].self = { Type = methodOwner }
				fn.Method = true
			end
			while current().Kind == "name" or current().Value == "..." do
				local name = current()
				index += 1
				local declared = take(":") and annotation()
				local slot = bind(name, parseAnnotation(declared), true, declared ~= nil)
				slot.Name = name.Value
				params[#params + 1] = slot
				if not take(",") then
					break
				end
			end
			take(")")
			local explicit = take(":") and annotation()
			block(ends, returned, depth + 1)
			take("end")
			scopes[#scopes] = nil
			fn.Return = parseAnnotation(explicit) or combine(returned) or "()"
			return fn
		end

		local function nested(stops, returned, depth, condition, truthy)
			scopes[#scopes + 1] = {}
			refineSlot(condition, truthy)
			block(stops, returned, depth + 1)
			scopes[#scopes] = nil
		end

		function block(stops, returned, depth)
			while
				current().First
				and not (current().Kind == "name" and stops[current().Value])
				and depth <= 32
				and operations <= 18000
			do
				local start = index
				local keyword = current()
				if take("local") or take("const") then
					local name = current()
					if take("function") then
						name = current()
						if name.Kind == "name" then
							index += 1
							readFunction(depth + 1, bind(name))
						end
					else
						local names, declared = {}, {}
						while current().Kind == "name" do
							names[#names + 1] = current()
							index += 1
							declared[#names] = take(":") and annotation()
							if not take(",") then
								break
							end
						end
						local values = {}
						local separator = take("=")
						if separator then
							repeat
								local expectedType = parseAnnotation(declared[#values + 1])
								local value = typeAt(expr(0, depth + 1, expectedType)) or "unknown"
								expect(expectedType, "Value", separator.Last, current().First or #source + 1)
								separator = take(",")
								if not separator and type(value) == "table" and value.Kind == "pack" then
									for _, item in ipairs(value.Values) do
										values[#values + 1] = item
									end
								else
									values[#values + 1] = firstType(value)
								end
							until not separator
						end
						for slot, token in ipairs(names) do
							bind(token, parseAnnotation(declared[slot]) or values[slot], false, not not declared[slot])
						end
					end
				elseif take("function") then
					local name = current()
					if name.Kind == "name" then
						index += 1
						local owner, separator, qualified
						local declaration = declarations[name.First]
						local value = typeAt(lookup(name))
						while true do
							separator = take(".") or take(":")
							if not separator or current().Kind ~= "name" then
								break
							end
							qualified = true
							owner = value
							name = current()
							index += 1
							value = fieldType(owner, name.Value)
						end
						if type(owner) == "table" and owner.Kind == "record" and not owner.Readonly then
							local isMethod = tokens[index - 2].Value == ":"
							local slot = {}
							if trackOccurrences then
								entries[name.First] = { Slot = slot }
							end
							local fn = readFunction(depth + 1, slot, isMethod and owner or nil)
							owner.Fields[name.Value] = fn
							fn.Documentation = declaration and declaration.Documentation
						elseif not qualified then
							readFunction(depth + 1, bind(name))
						else
							readFunction(depth + 1)
						end
					end
				elseif take("return") then
					local values = {}
					repeat
						local value = expr(0, depth + 1)
						if not value then
							break
						end
						values[#values + 1] = typeAt(value) or "unknown"
					until not take(",")
					if #values == 1 then
						returned[#returned + 1] = values[1]
					elseif #values > 1 then
						returned[#returned + 1] = { Kind = "pack", Values = values }
					end
				elseif take("if") then
					local condition = expr(0, depth + 1)
					take("then")
					nested(branches, returned, depth, condition, true)
					while take("elseif") do
						condition = expr(0, depth + 1)
						take("then")
						nested(branches, returned, depth, condition, true)
					end
					if take("else") then
						nested(ends, returned, depth, condition, false)
					end
					take("end")
				elseif take("for") then
					local names = {}
					while current().Kind == "name" do
						names[#names + 1] = current()
						index += 1
						if not take(",") then
							break
						end
					end
					local numeric = take("=")
					local iterable
					if numeric or take("in") then
						if
							not numeric
							and (current().Value == "ipairs" or current().Value == "pairs")
							and current(1).Value == "("
						then
							index += 2
							iterable = typeAt(expr(0, depth + 1))
							take(")")
						else
							iterable = typeAt(expr(0, depth + 1))
							while take(",") do
								expr(0, depth + 1)
							end
						end
					end
					take("do")
					scopes[#scopes + 1] = {}
					for slot, name in ipairs(names) do
						local element = fieldType(iterable)
						bind(
							name,
							if numeric
								then "number"
								elseif #names == 1 or slot > 1 then element
								elseif element then "number"
								else nil
						)
					end
					block(ends, returned, depth + 1)
					take("end")
					scopes[#scopes] = nil
				elseif take("while") or take("do") then
					if keyword.Value == "while" then
						expr(0, depth + 1)
						take("do")
					end
					nested(ends, returned, depth)
					take("end")
				elseif take("repeat") then
					nested({ ["until"] = true }, returned, depth)
					take("until")
					expr(0, depth + 1)
				elseif keyword.Value == "type" or keyword.Value == "export" and current(1).Value == "type" then
					index += keyword.Value == "export" and 2 or 1
					local alias = aliases[current().Value]
					if alias then
						readTypeTokens(alias.Last)
					end
				elseif take("break") or take("continue") then
				else
					local target = expr(0, depth + 1)
					local separator = take("=")
					if separator then
						local expectedType = target
							and ((target.Slot and target.Slot.Declared) or target.Owner)
							and typeAt(target)
						local value = firstType(typeAt(expr(0, depth + 1, expectedType)))
						expect(expectedType, "Value", separator.Last, current().First or #source + 1)
						if target and target.Slot and not target.Slot.Declared and value then
							local previous = target.Slot.Type
							target.Slot.Type = previous and combine({ previous, value }) or value
						elseif
							target
							and type(target.Owner) == "table"
							and target.Owner.Kind == "record"
							and not target.Owner.Readonly
							and not target.Owner.Sealed
							and value
						then
							target.Owner.Fields[target.Member] = value
							target.Type = value
						elseif target and target.Path and target.Path:match("^[%a_][%w_]*$") and value then
							scopes[1][target.Path] = { Type = value, First = target.First }
						end
					end
				end
				if index == start then
					index += 1
				end
				if receivers.Reached then
					break
				end
			end
		end

		block({}, returns, 0)
		if cancelled then
			return nil
		end
		if expectedPosition and not visible then
			captureScope()
		end
		return {
			Entries = entries,
			Calls = calls,
			ImportedTypes = importedTypes,
			Receiver = resolve(receivers.Type),
			TypeNamespace = receivers.TypeNamespace,
			Export = combine(returns),
			Expected = expectation and expectation.Type,
			ExpectedKind = expectation and expectation.Kind,
			Visible = visible,
		}
	end

	function Types.Describe(value)
		return describe(value, 0, false, { 96 })
	end
	function Types.Members(value)
		local seen = {}
		local function visit(record, depth)
			record = resolve(record)
			if type(record) ~= "table" or seen[record] or depth >= 8 then
				return {}
			end
			seen[record] = true
			local names = {}
			if record.Kind == "record" then
				names = visit(record.Prototype, depth + 1)
				for name in pairs(record.Fields) do
					names[name] = true
				end
			elseif record.Kind == "intersection" then
				for _, item in ipairs(record.Values) do
					for name in pairs(visit(item, depth + 1)) do
						names[name] = true
					end
				end
			elseif record.Kind == "union" then
				local found = false
				for _, item in ipairs(record.Values) do
					if skippable(item) then
						continue
					end
					local branch = visit(item, depth + 1)
					if found then
						for name in pairs(names) do
							if not branch[name] then
								names[name] = nil
							end
						end
					else
						names = branch
						found = true
					end
					if not next(names) then
						break
					end
				end
			end
			seen[record] = nil
			return names
		end
		return visit(value, 0)
	end

	Types.TypeAt = typeAt
	Types.Resolve = resolve
	Types.FieldType = fieldType
	function Types.ExportedTypes(value)
		if type(value) == "table" and value.Kind == "import" then
			loadImport(value)
			return value.Types
		end
	end
	function Types.FromApi(value)
		return typeNames[value] or value
	end
	return Types
end

return { InitDeps = InitDeps, Main = Main }
