--!strict

local Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps = d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local EditorDocument = {}
	local Document = {}
	Document.__index = Document
	local pairsByOpen = { ["("] = ")", ["["] = "]", ["{"] = "}", ['"'] = '"', ["'"] = "'", ["`"] = "`" }
	local closes = { ["("] = ")", ["["] = "]", ["{"] = "}" }
	local function clampPosition(text, position)
		position = math.clamp(math.floor(position or 1), 1, #text + 1)
		while position > 1 and position <= #text do
			local byte = string.byte(text, position)
			if byte < 128 or byte >= 192 then
				break
			end
			position -= 1
		end
		return position
	end
	local function previousPosition(text, position)
		return clampPosition(text, position - 1)
	end
	local function nextPosition(text, position)
		if position > #text then
			return #text + 1
		end
		local nextByte = position + 1
		while nextByte <= #text do
			local byte = string.byte(text, nextByte)
			if byte < 128 or byte >= 192 then
				break
			end
			nextByte += 1
		end
		return nextByte
	end
	function Document:SetText(text, changedLine)
		assert(type(text) == "string", "Editor document text must be a string")
		if self.Text == text then
			return false
		end
		local previous = self.Text
		self.Text = text
		if Apps and Apps.EditorBuffer then
			if not self.Buffer then
				self.Buffer = Apps.EditorBuffer.Create(text)
			else
				self.Buffer:SetText(text)
			end
		end
		if changedLine and previous then
			local ends = self.Ends
			local delta = #text - #previous
			if self.Separators[changedLine] ~= "\n" or text:byte(ends[changedLine] + delta) ~= 13 then
				ends[changedLine] += delta
				if delta ~= 0 then
					local starts = self.Starts
					for line = changedLine + 1, #starts do
						starts[line] += delta
						ends[line] += delta
					end
				end
				return true
			end
		end
		self.Starts, self.Ends, self.Separators = { 1 }, {}, {}
		self.Newline = "\n"
		local index = 1
		while true do
			local at = text:find("\n", index, true)
			if not at then
				break
			end
			local ending = if text:sub(at - 1, at - 1) == "\r" then "\r\n" else "\n"
			if #self.Starts == 1 then
				self.Newline = ending
			end
			self.Ends[#self.Starts] = at - #ending
			self.Separators[#self.Starts] = ending
			self.Starts[#self.Starts + 1] = at + 1
			index = at + 1
		end
		self.Ends[#self.Starts], self.Separators[#self.Starts] = #text, ""
		return true
	end
	function EditorDocument.ClampSelectionPosition(text, position)
		local clamped = clampPosition(text, position)
		if clamped > 1 and text:byte(clamped) == 10 and text:byte(clamped - 1) == 13 then
			return clamped - 1
		end
		return clamped
	end
	function Document:GetText()
		return self.Text
	end
	local function category(text, position)
		local c = text:sub(position, position)
		if c:match("%s") then
			return "space"
		end
		if c:match("[%w_]") or (text:byte(position) or 0) >= 128 then
			return "word"
		end
		return "symbol"
	end
	function Document:WordBoundary(position, direction)
		local text = self.Text
		position = clampPosition(text, position)
		if direction < 0 then
			while position > 1 and category(text, previousPosition(text, position)) == "space" do
				position = previousPosition(text, position)
			end
			local kind = position > 1 and category(text, previousPosition(text, position))
			while position > 1 and category(text, previousPosition(text, position)) == kind do
				position = previousPosition(text, position)
			end
		else
			local kind = category(text, position)
			while position <= #text and category(text, position) == kind do
				position = nextPosition(text, position)
			end
			while position <= #text and category(text, position) == "space" do
				position = nextPosition(text, position)
			end
		end
		return position
	end
	function Document:PointerRange(position, clicks)
		local text = self.Text
		position = clampPosition(text, position)
		local line = self:PositionToLineColumn(position)
		local lineFirst, lineEnd = self.Starts[line], self.Ends[line] + 1
		if clicks == 3 then
			return lineFirst, self.Starts[line + 1] or lineEnd
		end
		if lineFirst == lineEnd then
			return position, position
		end
		if position >= lineEnd then
			position = previousPosition(text, lineEnd)
		end
		local kind = category(text, position)
		local first, last = position, nextPosition(text, position)
		while first > lineFirst and category(text, previousPosition(text, first)) == kind do
			first = previousPosition(text, first)
		end
		while last < lineEnd and category(text, last) == kind do
			last = nextPosition(text, last)
		end
		return first, last
	end
	function Document:GetLineCount()
		return #self.Starts
	end
	function Document:GetLine(line)
		line = math.clamp(math.floor(line), 1, #self.Starts)
		return self.Text:sub(self.Starts[line], self.Ends[line])
	end
	function Document:PositionToLineColumn(position)
		position = clampPosition(self.Text, position)
		local low, high = 1, #self.Starts
		while low <= high do
			local middle = math.floor((low + high) / 2)
			if self.Starts[middle] <= position then
				low = middle + 1
			else
				high = middle - 1
			end
		end
		local line = math.max(high, 1)
		return line, math.min(position, self.Ends[line] + 1) - self.Starts[line] + 1
	end
	function Document:LineColumnToPosition(line, column)
		line = math.clamp(math.floor(line or 1), 1, #self.Starts)
		return clampPosition(
			self.Text,
			math.clamp(
				self.Starts[line] + math.max(0, math.floor((column or 1) - 1)),
				self.Starts[line],
				self.Ends[line] + 1
			)
		)
	end
	function Document:AdjacentPosition(position, direction)
		local line = self:PositionToLineColumn(position)
		local first, last = self.Starts[line], self.Ends[line] + 1
		if direction < 0 then
			if position <= first then
				return line > 1 and self.Ends[line - 1] + 1 or 1
			end
			return previousPosition(self.Text, math.min(position, last))
		end
		if position >= last then
			return self.Starts[line + 1] or last
		end
		return nextPosition(self.Text, position)
	end
	function Document:SelectedLines(anchor, caret)
		anchor, caret = clampPosition(self.Text, anchor), clampPosition(self.Text, caret)
		local first, last = math.min(anchor, caret), math.max(anchor, caret)
		local firstLine, lastLine = self:PositionToLineColumn(first), self:PositionToLineColumn(last)
		if last > first and lastLine > firstLine and last == self.Starts[lastLine] then
			lastLine -= 1
		end
		return firstLine, lastLine
	end
	local function longOpen(text, position)
		local equals = text:match("^%[(=*)%[", position)
		return if equals then "]" .. equals .. "]" else nil, if equals then #equals + 2 else 0
	end
	local function visitCode(text, first, finish, visit, checkpoint)
		local at = first
		local nextCheck = first
		while at < finish do
			if checkpoint and at >= nextCheck then
				if not checkpoint() then
					return false
				end
				nextCheck = at + 4096
			end
			local char = text:sub(at, at)
			local comment = char == "-" and text:sub(at + 1, at + 1) == "-"
			local literalStart = comment and at + 2 or at
			local delimiter, size
			if text:sub(literalStart, literalStart) == "[" then
				delimiter, size = longOpen(text, literalStart)
			end
			if delimiter then
				local _, ending = text:find(delimiter, literalStart + size, true)
				if ending and ending < finish and not comment and visit("literal", at, ending) == false then
					return
				end
				at = ending and ending + 1 or finish
			elseif comment then
				at = text:find("\n", at + 2, true) or finish
			elseif char == '"' or char == "'" or char == "`" then
				at += 1
				while at < finish do
					local nextChar = text:sub(at, at)
					if nextChar == "\\" then
						at += 2
					elseif nextChar == char or nextChar == "\n" and char ~= "`" then
						at += 1
						if nextChar == char and visit("literal", literalStart, at - 1) == false then
							return
						end
						break
					else
						at += 1
					end
				end
			else
				local token = text:match("^[%a_][%w_]*", at) or char
				if not token:match("^%s$") and visit(token, at, at + #token - 1) == false then
					return
				end
				at += #token
			end
		end
	end

	local expressionBefore = {
		["="] = true,
		["("] = true,
		["{"] = true,
		["["] = true,
		[","] = true,
		["return"] = true,
		["and"] = true,
		["or"] = true,
		["not"] = true,
	}
	local function blockTokens(text, first, finish, visit, checkpoint)
		local prior, depth, pending, conditional = nil, 0, {}, {}
		local headers = {}
		local tokenEnd
		local completed = visitCode(text, first, finish, function(token, at, ending)
			local kind
			if token == "if" or token == "elseif" then
				pending[depth] = if token == "elseif"
					then (conditional[depth] == "expression" and "expression" or "branch")
					else (expressionBefore[prior] and "expression" or "end")
				headers[depth] = { Start = at, Name = token, Keyword = "then", Kind = pending[depth] }
			elseif token == "while" or token == "for" then
				headers[depth] = { Start = at, Name = token, Keyword = "do", Kind = "end" }
			elseif token == "then" then
				kind, pending[depth] = pending[depth], nil
				conditional[depth] = kind
				headers[depth] = nil
			elseif token == "else" then
				kind = conditional[depth] == "expression" and "expression" or "branch"
			elseif token == "function" or token == "do" then
				kind = "end"
				headers[depth] = nil
			elseif token == "in" or token == "=" or token == "," then
				local header = headers[depth]
				if header and header.Name == "for" then
					if token == "," and header.Separator == "=" then
						header.HasLimit = true
					elseif not header.Separator and token ~= "," then
						header.Separator = token
					end
				end
			elseif token == "repeat" then
				kind = "until"
			elseif closes[token] then
				depth += 1
			elseif token == ")" or token == "}" or token == "]" then
				pending[depth] = nil
				conditional[depth] = nil
				headers[depth] = nil
				depth = math.max(0, depth - 1)
			end
			prior = token
			tokenEnd = ending
			return visit(token, at, kind)
		end, checkpoint)
		return headers[depth], prior, tokenEnd, completed ~= false
	end

	local function lineStructure(text, first, finish, lineStart, checkpoint)
		local blocks, token, tokenAt, branch = {}, nil, nil, false
		local header, lastToken, lastByte, completed = blockTokens(text, first, finish, function(nextToken, at, kind)
			if kind == "end" or kind == "until" then
				blocks[#blocks + 1] = { Close = kind, Start = at, Function = nextToken == "function" }
			elseif nextToken == "end" or nextToken == "until" then
				if blocks[#blocks] and blocks[#blocks].Close == nextToken then
					blocks[#blocks] = nil
				end
			end
			if at >= lineStart then
				token, tokenAt = nextToken, at
				branch = kind == "branch"
			end
		end, checkpoint)
		return blocks, token, tokenAt, branch, header, lastToken, lastByte, completed
	end

	local function missingHeaderKeyword(header, lastToken, lineStart, after)
		if not header or header.Start < lineStart or header.Kind == "expression" or lastToken == header.Name then
			return nil
		end
		if header.Name == "for" and (not header.Separator or (header.Separator == "=" and not header.HasLimit)) then
			return nil
		end
		if
			lastToken == "and"
			or lastToken == "or"
			or lastToken == "not"
			or lastToken == "in"
			or lastToken == "local"
			or lastToken == "const"
			or not lastToken:match("^[%w_%)}%]]+$")
		then
			return nil
		end
		local nextWord = after:match("^([%a_][%w_]*)")
		if after ~= "" and nextWord ~= "end" then
			return nil
		end
		return header.Keyword
	end

	local function findBlockCloser(text, first, finish, closing)
		local nested, matched = {}, false
		blockTokens(text, first, finish, function(token, at, kind)
			if kind == "end" or kind == "until" then
				nested[#nested + 1] = kind
			elseif token == "end" or token == "until" then
				if #nested == 0 then
					matched = token == closing and at
					return false
				elseif nested[#nested] == token then
					nested[#nested] = nil
				end
			end
		end)
		return matched
	end

	local function newlineEdit(self, first, last, indent)
		local source = self.Text
		local line = self:PositionToLineColumn(first)
		local lineStart, lineEnd = self.Starts[line], self.Ends[line]
		local prefix = source:sub(lineStart, first - 1)
		local whitespace = prefix:match("^[ \t]*")
		local base = self.Newline .. whitespace
		local context = self:ContextAt(first)
		if context ~= "Code" and context ~= "LineComment" then
			return base, last, #base
		end
		local before = prefix:match("(.-)%s*$")
		local opening = before:sub(-1)
		local trailing = source:sub(last, lineEnd)
		local leading = trailing:match("^[ \t]*")
		local after = trailing:sub(#leading + 1)
		if context == "Code" and closes[opening] then
			if after:sub(1, 1) == closes[opening] then
				return base .. indent .. base, last + #leading, #base + #indent
			end
			return base .. indent, last, #base + #indent
		end
		local possible = before:find("%f[%w_]then%f[^%w_]")
			or before:find("%f[%w_]do%f[^%w_]")
			or before:find("%f[%w_]else%f[^%w_]")
			or before:find("%f[%w_]repeat%f[^%w_]")
			or before:find("%f[%w_]function%f[^%w_]")
			or before:find("%f[%w_]if%f[^%w_]")
			or before:find("%f[%w_]elseif%f[^%w_]")
			or before:find("%f[%w_]while%f[^%w_]")
			or before:find("%f[%w_]for%f[^%w_]")
		if not possible then
			return base, last, #base
		end
		local scanStart = 1
		if lineStart > 65536 then
			scanStart = self.Starts[math.max(1, line - 2)]
		end
		local blocks, token, tokenAt, branch, header, lastToken, lastByte =
			lineStructure(source, scanStart, first, lineStart)
		local keyword = first == last and missingHeaderKeyword(header, lastToken, lineStart, after)
		if keyword and after == "" then
			local following = source:match("^%s*([%a_][%w_]*)", last)
			if following == keyword then
				keyword = nil
			end
		end
		if keyword then
			token, tokenAt, branch = keyword, lastByte, header.Kind == "branch"
			if not branch then
				blocks[#blocks + 1] = { Close = "end", Start = header.Start }
			end
		end
		local active, count = blocks[#blocks], 0
		if active and active.Start >= lineStart then
			local blockHeader = token == "then"
				or token == "do"
				or token == "repeat"
				or active.Function
					and (token == ")" or source:sub(active.Start, first - 1):match("^function[^\n]*%b()[ \t]*:[^\n=]+$"))
			if blockHeader then
				for index = #blocks, 1, -1 do
					if blocks[index].Start < lineStart then
						break
					end
					count += 1
				end
			end
		end
		if branch and (token == "else" or token == "then") then
			if keyword and after:match("^end%f[^%w_]") then
				return base .. indent .. base, last + #leading, #base + #indent, keyword, lastByte
			end
			return base .. indent, last, #base + #indent, keyword, lastByte
		end
		if count == 0 then
			return base, last, #base
		end
		local inner = base .. indent:rep(count)
		local afterWord = after:match("^([%a_][%w_]*)")
		if afterWord == active.Close then
			return inner .. base .. indent:rep(count - 1), last + #leading, #inner, keyword, lastByte
		end
		local hasTrailingComment = tokenAt and context == "LineComment"
		local callbackEnd = active.Function and after:match("^%)")
		if first ~= last or (after ~= "" and not callbackEnd) then
			return inner, last, #inner, keyword, lastByte
		end
		if #source - last > 65536 then
			return inner, last, #inner, keyword, lastByte
		end
		local searchFrom, missing = last, {}
		for index = #blocks, #blocks - count + 1, -1 do
			local block = blocks[index]
			local closer = findBlockCloser(source, searchFrom, #source + 1, block.Close)
			if closer then
				local closerLine = self:PositionToLineColumn(closer)
				local closerIndent = self:GetLine(closerLine):match("^[ \t]*")
				if #closerIndent >= #whitespace then
					searchFrom = closer + #block.Close
					continue
				end
			end
			missing[#missing + 1] = base
				.. indent:rep(index - (#blocks - count) - 1)
				.. (block.Close == "until" and "until " or "end")
		end
		if #missing > 0 and (context == "Code" or hasTrailingComment) then
			return inner .. table.concat(missing), last + #leading, #inner, keyword, lastByte
		end
		return inner, last, #inner, keyword, lastByte
	end
	function Document:CompletesHeaderOnEnter(position)
		local line = self:PositionToLineColumn(position)
		local start = self:GetLine(line):match("^%s*([%a_][%w_]*)")
		if start ~= "if" and start ~= "elseif" and start ~= "while" and start ~= "for" then
			return false
		end
		local _, _, _, keyword = newlineEdit(self, position, position, "\t")
		return keyword ~= nil
	end
	function Document:ContextAt(position)
		position = clampPosition(self.Text, position)
		local text, index, context, quote, closing = self.Text, 1, "Code", nil, nil
		while index < position do
			local char = text:sub(index, index)
			if context == "LineComment" then
				if char == "\n" then
					context = "Code"
				end
				index += 1
			elseif context == "LongString" or context == "LongComment" then
				if text:sub(index, index + #closing - 1) == closing and index + #closing <= position then
					index += #closing
					context, closing = "Code", nil
				else
					index += 1
				end
			elseif context == "String" or context == "InterpolatedString" then
				if char == "\\" then
					index += 2
				elseif char == quote then
					context, quote = "Code", nil
					index += 1
				elseif char == "\n" and context == "String" then
					context, quote = "Code", nil
					index += 1
				else
					index += 1
				end
			else
				if text:sub(index, index + 1) == "--" and index + 2 <= position then
					local delimiter, size = longOpen(text, index + 2)
					if delimiter and index + 2 + size <= position then
						context, closing, index = "LongComment", delimiter, index + 2 + size
					else
						context, index = "LineComment", index + 2
					end
				elseif char == '"' or char == "'" or char == "`" then
					context, quote, index = if char == "`" then "InterpolatedString" else "String", char, index + 1
				elseif char == "[" then
					local delimiter, size = longOpen(text, index)
					if delimiter and index + size <= position then
						context, closing, index = "LongString", delimiter, index + size
					else
						index += 1
					end
				else
					index += 1
				end
			end
		end
		return context, index > position, quote
	end
	local function mapPosition(position, edits)
		local delta = 0
		for _, edit in ipairs(edits) do
			if position < edit.Start then
				break
			end
			if position < edit.Finish then
				return edit.Start + delta + math.min(position - edit.Start, #edit.Text)
			end
			delta += #edit.Text - (edit.Finish - edit.Start)
		end
		return position + delta
	end
	function Document:Apply(command, anchor, caret, options)
		options = options or {}
		anchor, caret = clampPosition(self.Text, anchor), clampPosition(self.Text, caret)
		local original, edits = self.Text, {}
		local first, last = math.min(anchor, caret), math.max(anchor, caret)
		local firstLine, lastLine = self:SelectedLines(anchor, caret)
		local indent = options.Indent or "\t"
		assert(
			type(indent) == "string" and #indent > 0 and not indent:find("[^ \t]"),
			"Indent must contain spaces or tabs"
		)
		local resultAnchor, resultCaret
		local function replace(start, finish, text)
			edits[#edits + 1] = { Start = start, Finish = finish, Text = text }
		end
		local function insertSelection(text)
			replace(first, last, text)
			resultAnchor, resultCaret = first + #text, first + #text
		end
		if command == "InsertText" then
			if options.Overwrite and first == last then
				local at = first
				for _ in utf8.codes(options.Text or "") do
					if at > #original or original:sub(at, at):match("[\r\n]") then
						break
					end
					at = nextPosition(original, at)
				end
				last = at
			end
			insertSelection(options.Text or "")
		elseif command == "Indent" or command == "Outdent" then
			if command == "Indent" and first == last and not options.WholeLines then
				insertSelection(indent)
			else
				for line = firstLine, lastLine do
					local start, content = self.Starts[line], self:GetLine(line)
					if command == "Indent" then
						replace(start, start, indent)
					elseif content:sub(1, 1) == "\t" then
						replace(start, start + 1, "")
					else
						local spaces = content:match("^ *")
						local width = if indent == "\t" then (options.TabWidth or 4) else #indent
						replace(start, start + math.min(#spaces, width), "")
					end
				end
			end
		elseif command == "ToggleComment" then
			local uncomment = true
			for line = firstLine, lastLine do
				local content = self:GetLine(line)
				if content:find("%S") and not content:match("^[ \t]*%-%-") then
					uncomment = false
					break
				end
			end
			for line = firstLine, lastLine do
				local content = self:GetLine(line)
				if content:find("%S") then
					local whitespace = content:match("^[ \t]*")
					local at = self.Starts[line] + #whitespace
					if uncomment then
						local count = if content:sub(#whitespace + 3, #whitespace + 3) == " " then 3 else 2
						replace(at, at + count, "")
					else
						replace(at, at, "-- ")
					end
				end
			end
		elseif command == "DeleteLines" then
			local start = self.Starts[firstLine]
			local finish = self.Starts[lastLine + 1] or (#original + 1)
			if lastLine == #self.Starts and firstLine > 1 then
				start -= #self.Separators[firstLine - 1]
			end
			replace(start, finish, "")
			resultAnchor, resultCaret = start, start
		elseif command == "DuplicateLines" then
			local start, finish = self.Starts[firstLine], self.Ends[lastLine] + 1
			local block = original:sub(start, finish - 1)
			local added = self.Newline .. block
			replace(finish, finish, added)
			resultAnchor, resultCaret = anchor + #added, caret + #added
		elseif command == "MoveLinesUp" or command == "MoveLinesDown" then
			local up = command == "MoveLinesUp"
			if (up and firstLine > 1) or (not up and lastLine < #self.Starts) then
				local neighbor = if up then firstLine - 1 else lastLine + 1
				local startLine, finishLine = math.min(firstLine, neighbor), math.max(lastLine, neighbor)
				local moved = original:sub(self.Starts[firstLine], self.Ends[lastLine])
				local other = self:GetLine(neighbor)
				local gap = if up then self.Separators[neighbor] else self.Separators[lastLine]
				local text = if up then moved .. gap .. other else other .. gap .. moved
				replace(self.Starts[startLine], self.Ends[finishLine] + 1, text)
				local delta = if up then -(#other + #gap) else #other + #gap
				resultAnchor, resultCaret = anchor + delta, caret + delta
			end
		elseif command == "Newline" then
			local text, finish, cursor, keyword, headerEnd = newlineEdit(self, first, last, indent)
			if keyword then
				local suffix = original:sub(headerEnd + 1, first - 1)
				local preserved = suffix:match("^%s*$") and "" or suffix
				replace(headerEnd + 1, finish, " " .. keyword .. preserved .. text)
				cursor += headerEnd + 1 - first + 1 + #keyword + #preserved
			else
				replace(first, finish, text)
			end
			resultAnchor, resultCaret = first + cursor, first + cursor
		elseif command == "PairCharacter" then
			local char = options.Text or ""
			assert(#char == 1, "PairCharacter expects one ASCII character")
			local closing = pairsByOpen[char]
			local context, escaped, quote = self:ContextAt(first)
			local nextChar = original:sub(last, last)
			local isClosingBracket = context == "Code" and (char == ")" or char == "]" or char == "}")
			local isClosingQuote = not escaped
				and quote == char
				and closing == char
				and (context == "String" or context == "InterpolatedString")
			if first == last and original:sub(first, first) == char and (isClosingBracket or isClosingQuote) then
				resultAnchor, resultCaret = first + 1, first + 1
			elseif
				closing
				and context == "Code"
				and (first ~= last or nextChar == "" or nextChar:match("[%s%)%]%},;]"))
			then
				replace(first, last, char .. original:sub(first, last - 1) .. closing)
				if first == last then
					resultAnchor, resultCaret = first + 1, first + 1
				else
					resultAnchor, resultCaret = anchor + 1, caret + 1
				end
			else
				insertSelection(char)
			end
		elseif command == "DeletePreviousWord" or command == "DeleteNextWord" or command == "DeleteToLineStart" then
			if first == last then
				if command == "DeletePreviousWord" then
					first = self:WordBoundary(first, -1)
				elseif command == "DeleteNextWord" then
					last = self:WordBoundary(last, 1)
				else
					first = self:LineColumnToPosition(firstLine, 1)
				end
			end
			replace(first, last, "")
			resultAnchor, resultCaret = first, first
		elseif command == "Backspace" then
			if first ~= last then
				insertSelection("")
			elseif first > 1 then
				local previous = previousPosition(original, first)
				if original:sub(previous - 1, first - 1) == "\r\n" then
					previous -= 1
				end
				local opening = original:sub(previous, first - 1)
				local closing = pairsByOpen[opening]
				local finish = if closing
						and original:sub(first, first) == closing
						and self:ContextAt(previous) == "Code"
					then first + 1
					else first
				replace(previous, finish, "")
				resultAnchor, resultCaret = previous, previous
			end
		elseif command == "Delete" then
			if first ~= last then
				insertSelection("")
			elseif first <= #original then
				local finish = if original:sub(first, first + 1) == "\r\n"
					then first + 2
					else nextPosition(original, first)
				replace(first, finish, "")
				resultAnchor, resultCaret = first, first
			end
		else
			error("Unknown editor command: " .. tostring(command))
		end
		local text, pieces, at = original, {}, 1
		if #edits > 0 and self.Buffer then
			for i = #edits, 1, -1 do
				local edit = edits[i]
				self.Buffer:Replace(edit.Start, edit.Finish, edit.Text)
			end
			text = self.Buffer:GetText()
		elseif #edits > 0 then
			for _, edit in ipairs(edits) do
				pieces[#pieces + 1], pieces[#pieces + 2] = original:sub(at, edit.Start - 1), edit.Text
				at = edit.Finish
			end
			pieces[#pieces + 1] = original:sub(at)
			text = table.concat(pieces)
		end
		resultAnchor = clampPosition(text, resultAnchor or mapPosition(anchor, edits))
		resultCaret = clampPosition(text, resultCaret or mapPosition(caret, edits))
		local changedLine
		if #edits == 1 then
			local edit = edits[1]
			local line = self:PositionToLineColumn(edit.Start)
			if edit.Finish <= self.Ends[line] + 1 and not edit.Text:find("\n", 1, true) then
				changedLine = line
			end
		end
		self:SetText(text, changedLine)
		return { Text = text, Anchor = resultAnchor, Caret = resultCaret, Changed = text ~= original, Edits = edits }
	end
	function EditorDocument.Create(text)
		local document = setmetatable({}, Document)
		document:SetText(text or "")
		return document
	end
	function EditorDocument.Apply(text, anchor, caret, command, options)
		return EditorDocument.Create(text):Apply(command, anchor, caret, options)
	end
	function EditorDocument.OpenFunctionAt(source, position, checkpoint)
		local blocks, _, _, _, _, _, _, completed = lineStructure(source, 1, position, position, checkpoint)
		if not completed then
			return nil
		end
		for index = #blocks, 1, -1 do
			if blocks[index].Function then
				return blocks[index].Start
			end
		end
		return 0
	end
	return EditorDocument
end

return { InitDeps = InitDeps, Main = Main }
