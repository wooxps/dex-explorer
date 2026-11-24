--!strict

------------------------------ Module ------------------------------

local function Main()
	local Symbols = {}
	function Symbols.Mask(text, checkpoint)
		local chunks, i = {}, 1
		local nextCheck = 4096
		while i <= #text do
			if checkpoint and i >= nextCheck then
				nextCheck = i + 4096
				checkpoint()
			end
			local start = i
			local ch = text:sub(i, i)
			local comment = text:sub(i, i + 1) == "--"
			local open = i + (comment and 2 or 0)
			local eq = text:sub(open, open) == "[" and text:match("^%[(=*)%[", open)
			if eq then
				local _, last = text:find("]" .. eq .. "]", open + #eq + 2, true)
				i = last and last + 1 or #text + 1
			elseif comment then
				i = text:find("\n", i + 2, true) or #text + 1
			elseif ch == '"' or ch == "'" or ch == "`" then
				i += 1
				while i <= #text do
					local c = text:sub(i, i)
					if c == "\\" then
						i += 2
					elseif c == ch then
						i += 1
						break
					else
						i += 1
					end
				end
			else
				i = text:find([=[["'`%[%-]]=], i + 1) or #text + 1
				chunks[#chunks + 1] = text:sub(start, i - 1)
				continue
			end
			chunks[#chunks + 1] = text:sub(start, i - 1):gsub("[^\n]", " ")
		end
		return table.concat(chunks)
	end
	local closing = { ["("] = ")", ["{"] = "}", ["["] = "]", ["<"] = ">" }
	local function balanced(masked, first)
		local expected = closing[masked:sub(first, first)]
		if not expected then
			return nil
		end
		local stack = { expected }
		for at = first + 1, math.min(#masked, first + 16384) do
			local char = masked:sub(at, at)
			if char == stack[#stack] and (char ~= ">" or masked:sub(at - 1, at - 1) ~= "-") then
				stack[#stack] = nil
				if #stack == 0 then
					return at + 1
				end
			elseif closing[char] and (char ~= "<" or stack[#stack] == ">") then
				stack[#stack + 1] = closing[char]
			end
		end
	end
	local function readType(source, masked, first, onTypeof)
		local at = first
		for _ = 1, 64 do
			local _, leading = masked:find("^%s*", at)
			local atom = leading + 1
			local quoted = source:match([=[^%s*(["'])]=], at)
			if quoted then
				atom = source:find(quoted, at, true)
				local cursor = atom + 1
				while cursor <= #source do
					local char = source:sub(cursor, cursor)
					if char == quoted then
						at = cursor + 1
						break
					elseif char == "\\" then
						cursor += 1
					elseif char == "\n" then
						break
					end
					cursor += 1
				end
			elseif closing[masked:sub(atom, atom)] then
				at = balanced(masked, atom) or #source + 1
				if masked:sub(atom, atom) == "<" then
					continue
				end
			else
				local name, nextAt = masked:match("^([%a_][%w_]*)()", atom)
				if name and name ~= "end" and name ~= "return" and name ~= "local" and name ~= "function" then
					at = nextAt
					local qualifier = masked:match("^%s*%.%s*[%a_][%w_]*()", at)
					at = qualifier or at
					local generics = masked:match("^%s*()<", at)
					if generics then
						at = balanced(masked, generics) or #source + 1
					elseif name == "typeof" then
						local group = masked:match("^%s*()%(", at)
						if group then
							at = balanced(masked, group) or #source + 1
							if onTypeof then
								onTypeof(group + 1, at - 1)
							end
						end
					end
				end
			end
			if at <= atom then
				return at
			end
			at = masked:match("^%s*%?()", at) or masked:match("^%.%.%.()", at) or at
			local afterOperator = masked:match("^%s*[|&]()", at) or masked:match("^%s*%-%>()", at)
			if not afterOperator then
				return at
			end
			at = afterOperator
		end
		return at
	end
	local function trim(text)
		return text:match("^%s*(.-)%s*$")
	end
	function Symbols.New()
		local self = { Source = nil, Masked = "", Functions = {}, Declarations = {}, Bindings = {} }
		function self:Index(source, checkpoint)
			if self.Source == source then
				return
			end
			self.Source = source
			self.Masked = Symbols.Mask(source, checkpoint)
			self.Functions = {}
			self.Declarations = {}
			self.Bindings = {}
			self.Types = {}
			self.TypeRanges = {}
			self.TypeValues = {}
			self.Parameters = {}
			self.FunctionScopes = {}
			self.DocumentedFields = {}
			local masked = self.Masked
			local function annotation(first)
				local last = readType(source, masked, first, function(valueStart, valueEnd)
					self.TypeValues[#self.TypeValues + 1] = { First = valueStart, Last = valueEnd }
				end)
				self.TypeRanges[#self.TypeRanges + 1] = { First = first, Last = last }
				return trim(source:sub(first, last - 1)), last
			end
			local function precedingComment(at)
				local lastByte = at - 1
				while lastByte > 0 and source:sub(lastByte, lastByte):match("%s") do
					lastByte -= 1
				end
				if source:byte(lastByte) ~= 93 then
					return nil
				end
				local prefix = source:sub(math.max(1, lastByte - 3999), lastByte)
				local ending, equals = prefix:match("()%](=*)%]%s*$")
				if not ending then
					return nil
				end
				local start, body = nil, 1
				while body < ending do
					local first, last = prefix:find("--[" .. equals .. "[", body, true)
					if not first or first >= ending then
						break
					end
					start, body = first, last + 1
				end
				local close = start and prefix:find("]" .. equals .. "]", body, true)
				return close == ending and prefix:sub(body, ending - 1):match("^%s*(.-)%s*$") or nil
			end
			local function declare(name, position, kind, signature)
				if checkpoint and #self.Declarations % 128 == 0 then
					checkpoint()
				end
				local item = { Name = name, Position = position, Kind = kind, Signature = signature or name }
				self.Declarations[#self.Declarations + 1] = item
				return item
			end
			local occupied = {}
			local functionDeclarations = {}
			local function fn(name, at, opening, declarationStart, header)
				if occupied[opening] then
					return
				end
				occupied[opening] = true
				local depth, last = 1, opening + 1
				while last <= #source and depth > 0 do
					local c = self.Masked:sub(last, last)
					if c == "(" then
						depth += 1
					elseif c == ")" then
						depth -= 1
					end
					last += 1
				end
				if depth ~= 0 then
					return
				end
				local item = name and declare(name, at, "Function", name .. source:sub(opening, last - 1))
					or { Position = at }
				if name then
					functionDeclarations[at] = item
				end
				local params = source:sub(opening + 1, last - 2)
				item.Parameters = params
				if name then
					item.Documentation = precedingComment(declarationStart)
				end
				local returnStart = masked:match("^%s*:()", last)
				if returnStart then
					local returnType, typeEnd = annotation(returnStart)
					item.ReturnType = returnType
					if name then
						item.Signature ..= ": " .. returnType
					end
					last = typeEnd
				end
				if header then
					if name then
						item.Signature = name .. source:sub(header, opening - 1) .. item.Signature:sub(#name + 1)
					end
					local genericEnd = balanced(masked, header)
					item.Generics = genericEnd and source:sub(header + 1, genericEnd - 2)
				end
				item.BodyStart = last
				self.FunctionScopes[#self.FunctionScopes + 1] = item
				local paramEnd = opening + #params + 1
				local paramStart = opening + 1
				while paramStart < paramEnd do
					local position, parameter, afterName = masked:match("^%s*()([%a_][%w_]*)()", paramStart)
					if not parameter then
						break
					end
					local typeStart = masked:match("^%s*:()", afterName)
					local parameterType, afterType
					if typeStart then
						parameterType, afterType = annotation(typeStart)
					end
					local params = self.Parameters[parameter] or {}
					self.Parameters[parameter] = params
					params[#params + 1] = {
						Name = parameter,
						Kind = "Parameter",
						Position = position,
						NameEnd = afterName,
						Annotation = parameterType,
						BodyStart = last,
						Owner = item,
					}
					paramStart = masked:match("^%s*,()", afterType or afterName) or paramEnd
				end
				if name then
					self.Functions[#self.Functions + 1] = item
				end
			end
			for at, name, opening in self.Masked:gmatch("()function%s+([%a_][%w_%.:]*)%s*()%(") do
				local prefixStart = math.max(1, at - 32)
				local localStart = self.Masked:sub(prefixStart, at - 1):match("%f[%w_]()local%s+$")
				local start = localStart and prefixStart + localStart - 1 or at
				fn(name, self.Masked:find(name, at + 8, true), opening, start)
			end
			for at, name, generic in masked:gmatch("()function%s+([%a_][%w_%.:]*)%s*()<") do
				local genericEnd = balanced(masked, generic)
				local opening = genericEnd and masked:match("^%s*()%(", genericEnd)
				if opening then
					local prefixStart = math.max(1, at - 32)
					local localStart = masked:sub(prefixStart, at - 1):match("%f[%w_]()local%s+$")
					fn(
						name,
						masked:find(name, at + 8, true),
						opening,
						localStart and prefixStart + localStart - 1 or at,
						generic
					)
				end
			end
			for at, name, opening in self.Masked:gmatch("()([%a_][%w_%.:]*)%s*=%s*function%s*()%(") do
				local prefixStart = math.max(1, at - 32)
				local localStart = self.Masked:sub(prefixStart, at - 1):match("%f[%w_]()local%s+$")
				fn(name, at, opening, localStart and prefixStart + localStart - 1 or at)
			end
			for at, opening in masked:gmatch("%f[%w_]()function%s*()%(") do
				fn(nil, at, opening, at)
			end
			for at, name, afterName in self.Masked:gmatch("()local%s+([%a_][%w_]*)()") do
				if name ~= "function" then
					local tail = source:match("^[^\n]*", at) or ""
					local expression = tail:match("^local%s+[%a_][%w_]*%s*=%s*(.-)%s*$")
					local position = afterName - #name
					local declaration = functionDeclarations[position] or declare(name, position, "Variable")
					declaration.Documentation = precedingComment(at)
					local typeStart = masked:match("^[ \t]*:()", afterName)
					if typeStart then
						local typeEnd
						declaration.Annotation, typeEnd = annotation(typeStart)
						local rhs = masked:match("^%s*=()", typeEnd)
						expression = rhs and trim(source:match("^[^\r\n]*", rhs) or "")
					end
					if expression then
						self.Bindings[name] = self.Bindings[name] or {}
						table.insert(self.Bindings[name], { Position = at, Expression = expression })
					end
				end
			end
			for position, name, afterName in masked:gmatch("%f[%w_]()type[ \t]+([%a_][%w_]*)()") do
				local generic = masked:match("^[ \t]*()<", afterName)
				local genericEnd = generic and balanced(masked, generic)
				local first = masked:match("^%s*=()", genericEnd or afterName)
				if not first then
					continue
				end
				local declarationStart = position
				local exportStart = math.max(1, position - 24)
				local export = masked:sub(exportStart, position - 1):match("%f[%w_]()export%s+$")
				if export then
					declarationStart = exportStart + export - 1
				end
				local annotationText, last = annotation(first)
				local item = {
					Name = name,
					Kind = "Type",
					Position = position + #"type ",
					First = first,
					Last = last,
					Annotation = annotationText,
					Signature = trim(source:sub(position, last - 1)),
					Documentation = precedingComment(declarationStart),
					Fields = {},
					Generics = genericEnd and source:sub(generic + 1, genericEnd - 2),
					Exported = export ~= nil,
				}
				self.Types[name] = item
			end
			for colon in masked:gmatch("()::") do
				annotation(colon + 2)
			end
			for _, alias in pairs(self.Types) do
				for offset in masked:sub(alias.First, alias.Last - 1):gmatch("%f[%w_]typeof%s*%(()") do
					local first = alias.First + offset - 1
					local last = balanced(masked, first - 1)
					self.TypeValues[#self.TypeValues + 1] = { First = first, Last = last and last - 1 or #source + 1 }
				end
				local start = masked:match("^%s*(){", alias.First)
				if not start then
					continue
				end
				local cursor = start + 1
				while cursor < alias.Last do
					local position, field, first = masked:match("^%s*()([%a_][%w_]*)%s*:()", cursor)
					if not field then
						break
					end
					local fieldType, last = annotation(first)
					local signature = field .. ": " .. fieldType
					local functionAt, parameters, returnStart =
						masked:match("^%s*typeof%s*%(%s*()function%s*(%b())%s*:()", first)
					local comment = precedingComment(position) or (functionAt and precedingComment(functionAt))
					local item = {
						Name = field,
						Position = position,
						Kind = "Property",
						Signature = signature,
						Annotation = fieldType,
						Documentation = comment,
					}
					if functionAt then
						local returnType = readType(source, masked, returnStart)
						item.Signature = field .. parameters .. ": " .. trim(source:sub(returnStart, returnType - 1))
						item.Kind = "Function"
					end
					alias.Fields[field] = item
					if comment then
						self.DocumentedFields[field] = if self.DocumentedFields[field] == nil then item else false
					end
					cursor = masked:match("^%s*[,;]()", last) or alias.Last
				end
			end
			table.sort(self.Functions, function(a, b)
				return a.Position < b.Position
			end)
			table.sort(self.Declarations, function(a, b)
				return a.Position < b.Position
			end)
			for _, params in pairs(self.Parameters) do
				table.sort(params, function(a, b)
					return a.Position < b.Position
				end)
			end
		end
		function self:InType(position)
			for _, range in ipairs(self.TypeRanges or {}) do
				if position >= range.First and position <= range.Last then
					for _, value in ipairs(self.TypeValues) do
						if position >= value.First and position < value.Last and value.First >= range.First then
							return false
						end
					end
					return true
				end
			end
			return false
		end
		local function inFunction(self, item, position)
			if position < item.BodyStart or position - item.BodyStart > 8192 then
				return false
			end
			local depth = 1
			for _, word in self.Masked:sub(item.BodyStart, position - 1):gmatch("()([%a_][%w_]*)") do
				if word == "function" or word == "then" or word == "do" or word == "repeat" then
					depth += 1
				elseif word == "end" or word == "until" then
					depth -= 1
					if depth == 0 then
						return false
					end
				elseif word == "elseif" then
					depth -= 1
				end
			end
			return true
		end
		function self:GenericsAt(position)
			local nearest, generics
			for _, func in ipairs(self.FunctionScopes) do
				if
					func.Generics
					and func.Position < position
					and (not nearest or func.Position > nearest)
					and (position < func.BodyStart or inFunction(self, func, position))
				then
					nearest, generics = func.Position, func.Generics
				end
			end
			for _, alias in pairs(self.Types) do
				if
					alias.Generics
					and position >= alias.First
					and position <= alias.Last
					and (not nearest or alias.Position > nearest)
				then
					nearest, generics = alias.Position, alias.Generics
				end
			end
			return generics
		end
		function self:Parameter(name, position)
			for index = #(self.Parameters[name] or {}), 1, -1 do
				local item = self.Parameters[name][index]
				if
					(position >= item.Position and position < item.NameEnd) or inFunction(self, item.Owner, position)
				then
					return item
				end
			end
		end
		function self:Find(name, position)
			local result
			for _, item in ipairs(self.Declarations) do
				if item.Name == name and (not result or item.Position <= (position or math.huge)) then
					result = item
					if item.Position > (position or math.huge) then
						break
					end
				end
			end
			return result
		end
		function self:Token(position)
			position = math.clamp(position, 1, #self.Masked + 1)
			if not self.Masked:sub(position, position):match("[%w_]") and position > 1 then
				position -= 1
			end
			local a, b = position, position
			while a > 1 and self.Masked:sub(a - 1, a - 1):match("[%w_%.:]") do
				a -= 1
			end
			while b <= #self.Masked and self.Masked:sub(b, b):match("[%w_%.:]") do
				b += 1
			end
			local token = self.Masked:sub(a, b - 1)
			if token:match("^[%a_]") then
				return token, a, b
			end
		end
		function self:Resolve(expression, context, position, visited)
			context = context or {}
			visited = visited or {}
			if #expression > 512 or visited[expression] then
				return nil
			end
			visited[expression] = true
			local root, rest = expression:match("^%s*([%a_][%w_]*)(.*)$")
			if not root then
				return nil
			end
			local object, className
			if root == "game" then
				object = context.Game or game
			elseif root == "workspace" then
				object = context.Workspace or workspace
			elseif root == "script" then
				object = context.Script
			elseif root == "Instance" then
				return nil, rest:match([=[^%.new%s*%(%s*["']([%w_]+)["']%s*%)%s*$]=])
			else
				local bindings = self.Bindings[root]
				local binding
				for _, item in ipairs(bindings or {}) do
					if item.Position < (position or math.huge) then
						binding = item
					else
						break
					end
				end
				if binding then
					object, className = self:Resolve(binding.Expression, context, binding.Position, visited)
				end
			end
			if not object and not className then
				return nil
			end
			local serviceName, after = rest:match([=[^:GetService%s*%(%s*["']([%w_]+)["']%s*%)(.*)$]=])
			if serviceName and root == "game" then
				local ok, value = pcall(function()
					return object:FindFirstChild(serviceName)
				end)
				object = ok and value or nil
				className = serviceName
				rest = after
			end
			local count = 0
			while rest ~= "" do
				local child, tail = rest:match("^%.([%a_][%w_]*)(.*)$")
				if not child then
					return nil
				end
				count += 1
				if count > 20 or not object then
					return nil
				end
				local ok, value = pcall(function()
					if child == "Parent" then
						return object.Parent
					end
					return object:FindFirstChild(child)
				end)
				object = ok and value or nil
				rest = tail
				className = nil
			end
			if object then
				local ok, value = pcall(function()
					return object.ClassName
				end)
				if ok then
					className = value
				end
			end
			return object, className
		end
		return self
	end
	return Symbols
end
return { Main = Main }
