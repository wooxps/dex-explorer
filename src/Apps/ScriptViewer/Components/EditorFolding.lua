--!strict

------------------------------ Module ------------------------------

local function Main(apps)
	local Folding = {}
	local structural = {
		["function"] = true,
		["if"] = true,
		["elseif"] = true,
		["then"] = true,
		["for"] = true,
		["while"] = true,
		["do"] = true,
		["repeat"] = true,
		["until"] = true,
		["end"] = true,
	}
	local function neutral(line)
		if line:find("[{}%[%]%'%\"`\\%-]") then
			return false
		end
		for token in line:gmatch("[%w_]+") do
			if structural[token] then
				return false
			end
		end
		return true
	end
	local function structure(line)
		return (line:gsub("[%w_]+", function(token)
			return structural[token] and token or "_"
		end))
	end
	function Folding.SameStructure(previous, current)
		if previous == current or neutral(previous) and neutral(current) then
			return true
		end
		return not previous:find("\\", 1, true)
			and not current:find("\\", 1, true)
			and structure(previous) == structure(current)
	end
	function Folding.Ranges(source)
		local record = apps and apps.EditorParser and apps.EditorParser.Peek(source)
		if record and record.Diagnostics.Passed then
			local ranges = {}
			for _, node, parent in apps.EditorParser.Nodes(record) do
				local kind = node.kind
				local location = node.location
				if kind == "StatFor" or kind == "StatForIn" or kind == "StatWhile" or kind == "StatRepeat"
					or kind == "ExprFunction" or kind == "ExprTable" or kind == "TypeTable"
					or kind == "StatBlock" and parent and parent.kind == "StatBlock"
					or kind == "StatIf" and not (parent and parent.kind == "StatIf" and parent.elsebody == node) then
					local first, last = location.begin.x + 1, location.end_.x + 1
					if last > first then ranges[first] = math.max(ranges[first] or 0, last) end
				end
			end
			return ranges
		end
		local stack, ranges = {}, {}
		local i, line, lineStart = 1, 1, 1
		local pendingIf, pendingLoop
		local find, match, sub = string.find, string.match, string.sub
		local function advance(to)
			local skipped = source:sub(i, to - 1)
			local _, n = skipped:gsub("\n", "")
			local last = skipped:match(".*()\n")
			if last then
				lineStart = i + last
			end
			line += n
			i = to
		end
		local function push(kind, start)
			stack[#stack + 1] = { kind = kind, line = start or line }
		end
		local function close(kind)
			local top = stack[#stack]
			if not top or (kind and top.kind ~= kind) then
				return
			end
			stack[#stack] = nil
			if line > top.line then
				ranges[top.line] = math.max(ranges[top.line] or 0, line)
			end
		end
		while i <= #source do
			local start = find(source, "[%w_{}%[\n'\"`%-]", i)
			if not start then
				break
			end
			i = start
			local ch = sub(source, i, i)
			local comment = ch == "-" and sub(source, i + 1, i + 1) == "-"
			local open = i + (comment and 2 or 0)
			local equals = (comment or ch == "[") and match(source, "^%[(=*)%[", open) or nil
			if equals then
				local a, b = source:find("]" .. equals .. "]", open + 2 + #equals, true)
				advance(b and b + 1 or #source + 1)
			elseif comment then
				advance(source:find("\n", i + 2, true) or #source + 1)
			elseif ch == '"' or ch == "'" or ch == "`" then
				local quote = ch
				local j = i + 1
				while j <= #source do
					local c = sub(source, j, j)
					if c == "\\" then
						if sub(source, j + 1, j + 1) == "z" then
							j = find(source, "%S", j + 2) or #source + 1
						else
							j += 2
						end
					elseif c == quote then
						j += 1
						break
					elseif c == "\n" and quote ~= "`" then
						break
					else
						j += 1
					end
				end
				advance(j)
			elseif match(ch, "[%w_]") then
				local token = match(source, "^[%w_]+", i)
				i += #token
				if token == "function" then
					push("end")
				elseif token == "if" then
					pendingIf = source:sub(lineStart, start - 1):match("^%s*$") and line or nil
				elseif token == "elseif" then
					pendingIf = nil
				elseif token == "then" then
					if pendingIf then
						push("end", pendingIf)
						pendingIf = nil
					end
				elseif token == "for" or token == "while" then
					pendingLoop = line
				elseif token == "do" then
					push("end", pendingLoop)
					pendingLoop = nil
				elseif token == "repeat" then
					push("repeat")
				elseif token == "until" then
					close("repeat")
				elseif token == "end" then
					close("end")
				end
			else
				if ch == "{" then
					push("table")
				elseif ch == "}" then
					close("table")
				end
				if ch == "\n" then
					line += 1
					lineStart = i + 1
				end
				i += 1
			end
		end
		return ranges
	end
	function Folding.Build(lines, ranges, collapsed)
		local display, reverse = {}, {}
		local line = 1
		while line <= #lines do
			display[#display + 1] = line
			reverse[line] = #display
			if collapsed[line] and ranges[line] then
				line = ranges[line] + 1
			else
				line += 1
			end
		end
		return {
			display = display,
			reverse = reverse,
			ranges = ranges,
			collapsed = collapsed,
			sourceLines = next(collapsed) and table.clone(lines) or nil,
		}
	end
	function Folding.Create(lines, source, previous)
		local ranges = Folding.Ranges(source or table.concat(lines, "\n"))
		local collapsed = {}
		local oldLines = previous and previous.sourceLines
		if oldLines then
			local prefix, suffix = 0, 0
			local count = math.min(#oldLines, #lines)
			while prefix < count and oldLines[prefix + 1] == lines[prefix + 1] do
				prefix += 1
			end
			while suffix < count - prefix and oldLines[#oldLines - suffix] == lines[#lines - suffix] do
				suffix += 1
			end
			local delta = #lines - #oldLines
			local function remap(line)
				if line <= prefix then
					return line
				end
				if line > #oldLines - suffix then
					return line + delta
				end
				return nil
			end
			for first in pairs(previous.collapsed) do
				local start, finish = remap(first), remap(previous.ranges[first])
				if start and finish and ranges[start] == finish then
					collapsed[start] = true
				end
			end
		end
		return Folding.Build(lines, ranges, collapsed)
	end
	function Folding.Rebuild(model, lines)
		return Folding.Build(lines, model.ranges, model.collapsed)
	end
	return Folding
end
return { Main = Main }
