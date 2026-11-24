--!strict

local Apps

------------------------------ Constants ------------------------------

local Closer = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local ExpressionPrefix = {
	["="] = true,
	["return"] = true,
	[","] = true,
	["("] = true,
	["{"] = true,
	["["] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["//"] = true,
	["%"] = true,
	["^"] = true,
	[".."] = true,
	["=="] = true,
	["~="] = true,
	["<"] = true,
	[">"] = true,
	["<="] = true,
	[">="] = true,
	["#"] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
	["//="] = true,
	["%="] = true,
	["^="] = true,
	["..="] = true,
}

------------------------------ Initialization ------------------------------

local function InitDeps(deps)
	Apps = deps.Apps
end

------------------------------ Module ------------------------------

local function Main()
	local Formatter = {}
	function Formatter.Edit(text, ranges, selectionOnly, indent, insertions)
		local document = Apps.EditorDocument.Create(text)
		local selected = {}
		local lastLine = #document.Starts
		if insertions then
			lastLine = 0
			for _, insertion in ipairs(insertions) do
				local first, last = document:SelectedLines(insertion.First, insertion.Last)
				local start = document.Starts[first]
				local bodyStart = text:match("^[ \t]*()", start)
				if insertion.First > bodyStart then
					first += 1
				end
				if first <= last then
					lastLine = math.max(lastLine, last)
					for line = first, last do
						selected[line] = true
					end
				end
			end
		elseif selectionOnly then
			for _, range in ipairs(ranges) do
				if range.Anchor ~= range.Caret then
					local first, last = document:SelectedLines(range.Anchor, range.Caret)
					for line = first, last do
						selected[line] = true
					end
				end
			end
		end
		local sourceToFormat = if insertions then text:sub(1, document.Ends[lastLine] or 0) else text
		local tokens = Apps.EditorDefinitions.Tokenize(sourceToFormat, nil, true)

		local stack, edits = {}, {}
		local level, tokenIndex = 0, 1
		local expectsExpression = false
		local function push(close, line, conditional)
			local above = stack[#stack]
			local weight = if line == 0
					or (close == ")" or close == "]" or close == "}") and above and above.Line == line
				then 0
				else 1
			stack[#stack + 1] = { Close = close, Line = line, Weight = weight, Conditional = conditional }
			level += weight
		end
		local function pop()
			local frame = stack[#stack]
			stack[#stack] = nil
			level -= frame.Weight
			return frame
		end
		for line = 1, lastLine do
			local start = document.Starts[line]
			local finish = document.Ends[line]
			local token = tokens[tokenIndex]
			local continuation = token and token.First < start and token.Last > start
			local lineLevel, leading = level, not continuation
			while token and token.First <= finish do
				if token.First >= start and (token.Kind == "name" or token.Kind == "symbol") then
					local value = token.Value
					local top = stack[#stack]
					local expression = ExpressionPrefix[value] == true
					if top and top.Close == value then
						local closing = pop()
						if value == "then" then
							if closing.Conditional == "expression" then
								push("else", 0, "expression")
								expression = true
							else
								push("end", line, "statement")
							end
						elseif value == "else" then
							expression = true
						elseif leading then
							lineLevel = math.min(lineLevel, level)
						end
					elseif top and top.Conditional and (value == "elseif" or value == "else") then
						local branch = pop()
						if leading and branch.Conditional == "statement" then
							lineLevel = math.min(lineLevel, level)
						end
						if value == "elseif" then
							push("then", 0, branch.Conditional)
						elseif branch.Conditional == "statement" then
							push("end", line)
						end
						leading = false
					elseif value == "if" then
						push("then", 0, if expectsExpression then "expression" else "statement")
						leading = false
					elseif Closer[value] then
						push(Closer[value], line)
						leading = false
					elseif value == "function" or value == "do" or value == "repeat" then
						push(if value == "repeat" then "until" else "end", line)
						leading = false
					else
						leading = false
					end
					expectsExpression = expression
				elseif token.First >= start and token.Kind ~= "comment" then
					expectsExpression = false
					leading = false
				end
				if token.Last > finish + 1 then
					break
				end
				tokenIndex += 1
				token = tokens[tokenIndex]
			end
			if not continuation and lineLevel <= 64 and (not selectionOnly and not insertions or selected[line]) then
				local bodyStart = text:match("^[ \t]*()", start)
				if bodyStart <= finish then
					local replacement = string.rep(indent, lineLevel)
					if replacement ~= text:sub(start, bodyStart - 1) then
						edits[#edits + 1] = { Start = start, Finish = bodyStart, Text = replacement }
					end
				end
			end
		end

		local chunks, start = {}, 1
		for _, edit in ipairs(edits) do
			chunks[#chunks + 1] = text:sub(start, edit.Start - 1)
			chunks[#chunks + 1] = edit.Text
			start = edit.Finish
		end
		chunks[#chunks + 1] = text:sub(start)
		local source = table.concat(chunks)
		local positions, mapped = {}, {}
		for i, range in ipairs(ranges) do
			local result = { Id = range.Id }
			mapped[i] = result
			positions[#positions + 1] = { Value = range.Anchor, Key = "Anchor", Range = result }
			positions[#positions + 1] = { Value = range.Caret, Key = "Caret", Range = result }
		end
		table.sort(positions, function(a, b)
			return a.Value < b.Value
		end)
		local index, shift = 1, 0
		for _, point in ipairs(positions) do
			local value = point.Value
			local edit = edits[index]
			while edit and value >= edit.Finish do
				shift += #edit.Text - (edit.Finish - edit.Start)
				index += 1
				edit = edits[index]
			end
			if edit and value >= edit.Start then
				value = edit.Start + math.min(value - edit.Start, #edit.Text)
			end
			point.Range[point.Key] = value + shift
		end
		table.sort(mapped, function(a, b)
			return a.Id < b.Id
		end)
		local primary = mapped[1]
		return { Text = source, Anchor = primary.Anchor, Caret = primary.Caret, Ranges = mapped, Changed = #edits > 0 }
	end
	return Formatter
end

return { InitDeps = InitDeps, Main = Main }
