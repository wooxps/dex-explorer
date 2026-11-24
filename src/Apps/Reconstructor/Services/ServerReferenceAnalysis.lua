--!strict

------------------------------ Module ------------------------------

local function Main()
	local Analysis = {}
	local roots = { ServerStorage = true, ServerScriptService = true }
	local properties = {
		Name = true,
		ClassName = true,
		Parent = true,
		Source = true,
		Value = true,
		Disabled = true,
		Enabled = true,
		Archivable = true,
	}
	local escapes = { n = "\n", r = "\r", t = "\t", a = "\a", b = "\b", f = "\f", v = "\v" }
	local function tokenize(source, checkpoint, maximumTokens)
		local tokens, i, line, steps = {}, 1, 1, 0
		local function advance(last)
			if last == i then
				if source:byte(i) == 10 then
					line += 1
				end
			else
				local _, count = source:sub(i, last):gsub("\n", "")
				line += count
			end
			i = last + 1
		end
		local function longEnd(start)
			local equals = source:match("^%[(=*)%[", start)
			if not equals then
				return
			end
			local opening = start + #equals + 2
			local first, last = source:find("]" .. equals .. "]", opening, true)
			return first or (#source + 1), last or #source, opening
		end
		while i <= #source do
			if #tokens > (maximumTokens or 50000) then
				return
			end
			steps += 1
			if steps % 128 == 1 and checkpoint and checkpoint() == false then
				return
			end
			local byte = source:byte(i)
			local char = source:sub(i, i)
			if byte == 45 and source:sub(i, i + 1) == "--" then
				local _, last = longEnd(i + 2)
				advance(last or ((source:find("\n", i + 2, true) or (#source + 1)) - 1))
			elseif byte == 32 or byte == 9 or byte == 10 or byte == 13 or byte == 11 or byte == 12 then
				if byte == 10 then
					line += 1
				end
				i += 1
			elseif char == '"' or char == "'" then
				local startLine, cursor, value, valid, closed = line, i + 1, {}, true, false
				while cursor <= #source do
					if cursor % 256 == 0 and checkpoint and checkpoint() == false then
						return
					end
					local c = source:sub(cursor, cursor)
					if c == char then
						closed = true
						break
					end
					if c == "\\" then
						cursor += 1
						local escape = source:sub(cursor, cursor)
						if escape:match("%d") then
							local digits = source:match("^%d%d?%d?", cursor)
							local byte = tonumber(digits)
							if byte > 255 then
								valid = false
							else
								value[#value + 1] = string.char(byte)
							end
							cursor += #digits - 1
						elseif escape == "x" then
							local hex = source:sub(cursor + 1, cursor + 2)
							local byte = #hex == 2 and tonumber(hex, 16)
							if not byte then
								valid = false
							else
								value[#value + 1] = string.char(byte)
							end
							cursor += 2
						elseif escapes[escape] then
							value[#value + 1] = escapes[escape]
						elseif escape == "\\" or escape == '"' or escape == "'" then
							value[#value + 1] = escape
						else
							valid = false
						end
					else
						value[#value + 1] = c
					end
					cursor += 1
				end
				tokens[#tokens + 1] =
					{ Kind = "string", Value = valid and closed and table.concat(value) or false, Line = startLine }
				advance(math.min(cursor, #source))
			elseif char == "[" and longEnd(i) then
				local first, last, opening = longEnd(i)
				tokens[#tokens + 1] =
					{ Kind = "string", Value = source:sub(opening, first - 1):gsub("^\r?\n", ""), Line = line }
				advance(last)
			elseif byte >= 48 and byte <= 57 then
				local number = source:match("^%d+%.?%d*", i)
				tokens[#tokens + 1] = { Kind = "number", Value = number, Line = line }
				i += #number
			elseif byte == 95 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122 then
				local word = source:match("^[%w_]+", i)
				tokens[#tokens + 1] = { Kind = "name", Value = word, Line = line }
				i += #word
			else
				local nextTwo = source:sub(i, i + 1)
				local symbol = (
					nextTwo == "=="
					or nextTwo == "~="
					or nextTwo == "+="
					or nextTwo == "-="
					or nextTwo == ".."
				)
						and nextTwo
					or char
				tokens[#tokens + 1] = { Kind = "symbol", Value = symbol, Line = line }
				i += #symbol
			end
		end
		return tokens
	end
	function Analysis.Source(source, label, emit, checkpoint, maximumTokens)
		if type(source) ~= "string" or #source > 2 * 1024 * 1024 then
			return false
		end
		local t = tokenize(source, checkpoint, maximumTokens)
		if not t then
			return false
		end
		local writes, aliases, constants, scopeAt, scopeParents = {}, {}, {}, {}, { [1] = 0 }
		local function value(i)
			return t[i] and t[i].Value
		end
		local stack, nextScope = { 1 }, 1
		for i, token in ipairs(t) do
			if i % 256 == 0 and checkpoint and checkpoint() == false then
				return false
			end
			local word = token.Kind == "name" and token.Value
			if word == "end" or word == "until" or word == "else" or word == "elseif" then
				if #stack > 1 then
					table.remove(stack)
				end
			end
			scopeAt[i] = stack[#stack]
			if word == "function" or word == "do" or word == "then" or word == "repeat" or word == "else" then
				nextScope += 1
				scopeParents[nextScope] = stack[#stack]
				stack[#stack + 1] = nextScope
			end
		end
		local function inScope(current, owner)
			while current and current ~= 0 do
				if current == owner then
					return true
				end
				current = scopeParents[current]
			end
			return false
		end
		for i, token in ipairs(t) do
			if i % 256 == 0 and checkpoint and checkpoint() == false then
				return false
			end
			if token.Value == "function" then
				local cursor = i + 1
				while cursor <= #t and value(cursor) ~= "(" and cursor < i + 8 do
					cursor += 1
				end
				if value(cursor) == "(" then
					cursor += 1
					while cursor <= #t and value(cursor) ~= ")" do
						if t[cursor].Kind == "name" then
							writes[value(cursor)] = (writes[value(cursor)] or 0) + 1
						end
						cursor += 1
					end
				end
			end
			if token.Kind == "name" then
				local nextValue = value(i + 1)
				local assignmentList = false
				if nextValue == "," then
					local cursor = i + 1
					while value(cursor) == "," and t[cursor + 1] and t[cursor + 1].Kind == "name" do
						cursor += 2
					end
					assignmentList = value(cursor) == "=" or value(cursor) == "in"
				end
				if
					assignmentList
					or nextValue == "in"
					or nextValue == "="
					or nextValue == "+="
					or nextValue == "-="
					or value(i - 1) == "local"
					or (value(i - 1) == "function" and nextValue ~= "." and nextValue ~= ":")
					or value(i - 1) == "for"
				then
					writes[token.Value] = (writes[token.Value] or 0) + 1
				end
			end
		end
		local stringExpression
		stringExpression = function(start, depth)
			depth = (depth or 0) + 1
			if depth > 16 then
				return
			end
			local text, cursor
			local token = t[start]
			if token and token.Kind == "string" and type(token.Value) == "string" then
				text, cursor = token.Value, start + 1
			elseif value(start) == "(" then
				text, cursor = stringExpression(start + 1, depth)
				if not cursor or value(cursor) ~= ")" then
					return
				end
				cursor += 1
			elseif
				constants[value(start)]
				and writes[value(start)] == 1
				and inScope(scopeAt[start], constants[value(start)].Scope)
			then
				text, cursor = constants[value(start)].Text, start + 1
			end
			if not text then
				return
			end
			if value(cursor) == ".." then
				local tail, following = stringExpression(cursor + 1, depth)
				if not tail then
					return
				end
				text, cursor = text .. tail, following
			end
			if #text > 512 then
				return
			end
			return text, cursor
		end
		local expression
		expression = function(start)
			local name = value(start)
			local path, cursor
			if name == "game" and not writes.game then
				cursor = start + 1
				if value(cursor) == ":" and value(cursor + 1) == "GetService" and value(cursor + 2) == "(" then
					local service, close = stringExpression(cursor + 3)
					if service and roots[service] and value(close) == ")" then
						path = { service }
						cursor = close + 1
					end
				elseif value(cursor) == "." and roots[value(cursor + 1)] then
					path = { value(cursor + 1) }
					cursor += 2
				elseif value(cursor) == "[" then
					local service, close = stringExpression(cursor + 1)
					if service and roots[service] and value(close) == "]" then
						path = { service }
						cursor = close + 1
					end
				end
			elseif aliases[name] and writes[name] == 1 and inScope(scopeAt[start], aliases[name].Scope) then
				path = table.clone(aliases[name].Path)
				cursor = start + 1
			end
			if not path then
				return
			end
			while #path < 64 do
				if value(cursor) == "." and t[cursor + 1] and t[cursor + 1].Kind == "name" then
					local child = value(cursor + 1)
					if child == "Parent" then
						if #path <= 1 then
							break
						end
						table.remove(path)
					elseif properties[child] then
						break
					else
						path[#path + 1] = child
					end
					cursor += 2
				elseif value(cursor) == "[" then
					local child, close = stringExpression(cursor + 1)
					if not child or value(close) ~= "]" then
						break
					end
					path[#path + 1] = child
					cursor = close + 1
				elseif
					value(cursor) == ":"
					and (value(cursor + 1) == "WaitForChild" or value(cursor + 1) == "FindFirstChild")
					and value(cursor + 2) == "("
				then
					local child, close = stringExpression(cursor + 3)
					if not child then
						break
					end
					if value(close) ~= ")" then
						if value(cursor + 1) == "FindFirstChild" then
							break
						end
						while close <= #t and value(close) ~= ")" and close < cursor + 8 do
							close += 1
						end
						if value(close) ~= ")" then
							break
						end
					end
					path[#path + 1] = child
					cursor = close + 1
				else
					break
				end
			end
			return path, cursor
		end
		local moduleAliases, variableTypes = {}, {}
		local function inputType(first, last)
			if first == last then
				local token = t[first]
				if not token then
					return "unknown"
				end
				if token.Kind == "string" then
					return "string"
				end
				if token.Kind == "number" then
					return "number"
				end
				if token.Value == "true" or token.Value == "false" then
					return "boolean"
				end
				if token.Value == "nil" then
					return "nil"
				end
				local binding = variableTypes[token.Value]
				if binding and writes[token.Value] == 1 and inScope(scopeAt[first], binding.Scope) then
					return binding.Type
				end
			end
			if value(first) == "-" and first + 1 == last and t[last] and t[last].Kind == "number" then
				return "number"
			end
			if value(first) == "{" and value(last) == "}" then
				return "table"
			end
			local path, following = expression(first)
			if path and following == last + 1 then
				return "Instance"
			end
			return "unknown"
		end
		local function moduleUsage(index, token)
			local binding = moduleAliases[token.Value]
			if not binding or writes[token.Value] ~= 1 or not inScope(scopeAt[index], binding.Scope) then
				return
			end
			if value(index - 1) == "." or value(index - 1) == ":" then
				return
			end
			local cursor = index + 1
			local members = table.clone(binding.Members or {})
			local method = false
			while #members < 16 do
				if
					(value(cursor) == "." or value(cursor) == ":")
					and t[cursor + 1]
					and t[cursor + 1].Kind == "name"
				then
					method = value(cursor) == ":"
					members[#members + 1] = value(cursor + 1)
					cursor += 2
					if method then
						break
					end
				elseif
					value(cursor) == "["
					and t[cursor + 1]
					and (t[cursor + 1].Kind == "string" or t[cursor + 1].Kind == "number")
					and value(cursor + 2) == "]"
				then
					local key = t[cursor + 1].Kind == "number" and tonumber(value(cursor + 1)) or value(cursor + 1)
					if key == nil then
						break
					end
					members[#members + 1] = key
					cursor += 3
				else
					break
				end
			end
			if #members == 0 and value(cursor) ~= "(" then
				return
			end
			local member = {
				Name = members[#members] or "__call",
				Root = #members == 0,
				Path = members,
				Kind = "field",
				Type = "unknown",
			}
			local declaration = value(index - 1) == "function"
				or (value(cursor) == "=" and value(cursor + 1) == "function")
			if declaration then
				local opening = value(index - 1) == "function" and cursor or cursor + 2
				if value(opening) ~= "(" then
					return
				end
				local names, kinds, count = {}, {}, 0
				if method then
					count = 1
					names[1] = "self"
					kinds[1] = "unknown"
				end
				local at = opening + 1
				local done = false
				local vararg = false
				while at <= math.min(#t, opening + 512) do
					if checkpoint and at % 128 == 0 and checkpoint() == false then
						return
					end
					if value(at) == ")" then
						done = true
						break
					end
					if value(at) == ".." and value(at + 1) == "." then
						vararg = true
						at += 2
					elseif t[at] and t[at].Kind == "name" then
						count += 1
						if count > 32 then
							return
						end
						names[count] = value(at)
						kinds[count] = "unknown"
						at += 1
					else
						return
					end
					if value(at) == ":" then
						at += 1
						local start = at
						local depth = 0
						while at <= #t and at < opening + 512 do
							local v = value(at)
							if depth == 0 and (v == "," or v == ")") then
								break
							end
							if v == "{" or v == "(" or v == "[" then
								depth += 1
							elseif v == "}" or v == ")" or v == "]" then
								depth -= 1
							end
							at += 1
						end
						local kind = value(start)
						local primitive = {
							string = true,
							number = true,
							boolean = true,
							thread = true,
							buffer = true,
							Instance = true,
							unknown = true,
							any = true,
						}
						local annotation = primitive[kind] and (kind == "any" and "unknown" or kind)
							or kind == "{" and "table"
							or "unknown"
						if value(start + 1) == "?" then
							annotation ..= "?"
						end
						if not vararg then
							kinds[count] = annotation
						end
					end
					if value(at) == "," then
						at += 1
					elseif value(at) ~= ")" then
						return
					end
				end
				if not done then
					return
				end
				member.Kind = nil
				member.Definition = true
				member.Count = count
				member.DeclaredNames = names
				member.DeclaredArguments = kinds
				member.Vararg = vararg
			elseif value(cursor) == "(" then
				local start, depth, count, arguments = cursor + 1, 1, 0, {}
				local finish
				for at = cursor + 1, math.min(#t, cursor + 512) do
					if at % 128 == 0 and checkpoint and checkpoint() == false then
						return
					end
					local v = value(at)
					if v == "function" then
						return
					end
					if v == "(" or v == "{" or v == "[" then
						depth += 1
					elseif v == ")" or v == "}" or v == "]" then
						depth -= 1
					end
					if depth == 0 or (depth == 1 and v == ",") then
						if at > start then
							count += 1
							arguments[count] = inputType(start, at - 1)
						end
						start = at + 1
						if count > 32 then
							return
						end
					end
					if depth == 0 then
						finish = at
						break
					end
				end
				if not finish then
					return
				end
				member.Kind = nil
				member.Method = method
				member.Count = count
				member.Arguments = arguments
			elseif value(cursor) == "=" then
				member.Type = inputType(cursor + 1, cursor + 1)
			elseif value(index - 1) == "=" and value(index - 3) == "local" and writes[value(index - 2)] == 1 then
				moduleAliases[value(index - 2)] = { Path = binding.Path, Members = members, Scope = scopeAt[index] }
			end
			emit(
				binding.Path,
				{ Source = label, Line = token.Line, Kind = "module usage", Class = "ModuleScript", Member = member }
			)
		end
		for i, token in ipairs(t) do
			if i % 256 == 0 and checkpoint and checkpoint() == false then
				return false
			end
			moduleUsage(i, token)
			if token.Value == "local" and t[i + 1] and value(i + 2) == "=" and writes[value(i + 1)] == 1 then
				variableTypes[value(i + 1)] = { Type = inputType(i + 3, i + 3), Scope = scopeAt[i] }
			end
			if
				token.Value == "local"
				and t[i + 1]
				and t[i + 1].Kind == "name"
				and value(i + 2) == "="
				and writes[value(i + 1)] == 1
			then
				local text, following = stringExpression(i + 3)
				local nextToken = following and t[following]
				if
					text
					and (
						not nextToken
						or nextToken.Value == ";"
						or (
							nextToken.Line > token.Line
							and nextToken.Value ~= "or"
							and nextToken.Value ~= "and"
							and nextToken.Value ~= ".."
						)
					)
				then
					constants[value(i + 1)] = { Text = text, Scope = scopeAt[i] }
				end
			end
			if value(i - 1) ~= "." and value(i - 1) ~= ":" then
				local path, cursor = expression(i)
				if path then
					local class, kind = nil, "source reference"
					if
						value(i - 1) == "("
						and value(i - 2) == "require"
						and not writes.require
						and value(cursor) == ")"
					then
						class = "ModuleScript"
						kind = "require target"
					elseif
						value(cursor) == ":"
						and value(cursor + 1) == "IsA"
						and value(cursor + 2) == "("
						and t[cursor + 3]
						and t[cursor + 3].Kind == "string"
					then
						class = value(cursor + 3)
						kind = "conditional IsA constraint"
					elseif
						value(cursor) == "."
						and value(cursor + 1) == "ClassName"
						and value(cursor + 2) == "=="
						and t[cursor + 3]
						and t[cursor + 3].Kind == "string"
					then
						class = value(cursor + 3)
						kind = "conditional ClassName constraint"
					end
					emit(path, { Source = label, Line = token.Line, Kind = kind, Class = class })
					if
						kind == "require target"
						and value(i - 3) == "="
						and value(i - 5) == "local"
						and writes[value(i - 4)] == 1
					then
						local following = value(cursor + 1)
						if
							not following
							or following == ";"
							or (
								t[cursor + 1].Line > t[cursor].Line
								and following ~= "."
								and following ~= "["
								and following ~= "or"
								and following ~= "and"
							)
						then
							moduleAliases[value(i - 4)] = { Path = path, Scope = scopeAt[i] }
						end
					end
					if value(i - 1) == "=" and t[i - 2] and value(i - 3) == "local" and writes[value(i - 2)] == 1 then
						local following = value(cursor)
						if
							not following
							or following == ";"
							or (
								t[cursor].Line > token.Line
								and following ~= "."
								and following ~= ":"
								and following ~= "["
								and following ~= "or"
								and following ~= "and"
							)
						then
							aliases[value(i - 2)] = { Path = path, Scope = scopeAt[i] }
						end
					end
				end
			end
		end
		return true
	end
	function Analysis.Log(message, label, emit)
		if type(message) ~= "string" or #message > 65536 then
			return
		end
		for class, path in message:gmatch("is not a valid member of (%w+) [\"']([^\"']+)[\"']") do
			local segments = string.split(path, ".")
			if segments[1] == "game" then
				table.remove(segments, 1)
			end
			if roots[segments[1]] then
				emit(segments, { Source = label, Kind = "error-reported container class", Class = class })
			end
		end
		for path in message:gmatch("[Ss]cript ['\"]([^'\"]+)['\"]") do
			local segments = string.split(path, ".")
			if segments[1] == "game" then
				table.remove(segments, 1)
			end
			if roots[segments[1]] then
				emit(segments, { Source = label, Kind = "traceback path (script class unknown)" })
			end
		end
		for root, tail in message:gmatch("(Server%a+)%.([%w_%.]+)") do
			if roots[root] then
				local segments = { root }
				for part in tail:gmatch("[%w_]+") do
					segments[#segments + 1] = part
				end
				emit(segments, { Source = label, Kind = "error path text" })
			end
		end
	end
	return Analysis
end
return { Main = Main }
