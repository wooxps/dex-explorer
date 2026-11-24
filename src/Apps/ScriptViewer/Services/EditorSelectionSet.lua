--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Set = {}
	local function copy(range)
		return { Anchor = range.Anchor, Caret = range.Caret, Id = range.Id }
	end
	function Set.Normalize(text, ranges)
		local ordered = {}
		local clamp = Apps.EditorDocument.ClampSelectionPosition
		for index, range in ipairs(ranges) do
			local a, c = clamp(text, range.Anchor), clamp(text, range.Caret)
			ordered[#ordered + 1] =
				{ Anchor = a, Caret = c, Id = range.Id or index, First = math.min(a, c), Last = math.max(a, c) }
		end
		table.sort(ordered, function(a, b)
			return a.First < b.First or a.First == b.First and a.Last < b.Last
		end)
		local result = {}
		for _, range in ipairs(ordered) do
			local previous = result[#result]
			if previous and (range.First < previous.Last or range.First == previous.First) then
				local survivor = range.Id < previous.Id and range or previous
				local reversed = survivor.Anchor > survivor.Caret
				previous.Last = math.max(previous.Last, range.Last)
				previous.Anchor = reversed and previous.Last or previous.First
				previous.Caret = reversed and previous.First or previous.Last
				previous.Id = math.min(previous.Id, range.Id)
			else
				result[#result + 1] = range
			end
		end
		return result
	end
	local function lineCommand(command, options, ordered)
		if command == "Indent" then
			if options and options.WholeLines then
				return true
			end
			for _, range in ipairs(ordered) do
				if range.Anchor ~= range.Caret then
					return true
				end
			end
		end
		return command == "Outdent"
			or command == "ToggleComment"
			or command == "DeleteLines"
			or command == "DuplicateLines"
			or command == "MoveLinesUp"
			or command == "MoveLinesDown"
	end
	local function applyLines(text, ordered, command, options)
		local original = Apps.EditorDocument.Create(text)
		local blocks, points = {}, {}
		for _, range in ipairs(ordered) do
			local first, last = original:SelectedLines(range.Anchor, range.Caret)
			if command == "Indent" and not (options and options.WholeLines) and range.Anchor == range.Caret then
				points[#points + 1] = { First = first, Last = last, Members = { range.Id }, Point = range.Anchor }
			else
				blocks[#blocks + 1] = { First = first, Last = last, Members = { range.Id } }
			end
		end
		table.sort(blocks, function(a, b)
			return a.First < b.First or a.First == b.First and a.Last < b.Last
		end)
		local merged = {}
		local moving = command == "MoveLinesUp" or command == "MoveLinesDown"
		for _, block in ipairs(blocks) do
			local previous = merged[#merged]
			if previous and block.First <= previous.Last + (moving and 1 or 0) then
				previous.Last = math.max(previous.Last, block.Last)
				for _, id in ipairs(block.Members) do
					previous.Members[#previous.Members + 1] = id
				end
			else
				merged[#merged + 1] = block
			end
		end
		for _, point in ipairs(points) do
			local covering
			for _, block in ipairs(merged) do
				if not block.Point and point.First >= block.First and point.First <= block.Last then
					covering = block
					break
				end
			end
			if covering then
				covering.Members[#covering.Members + 1] = point.Members[1]
			else
				merged[#merged + 1] = point
			end
		end
		table.sort(merged, function(a, b)
			local first = a.Point or original:LineColumnToPosition(a.First, 1)
			local second = b.Point or original:LineColumnToPosition(b.First, 1)
			return first < second
		end)
		local result = {}
		for _, range in ipairs(ordered) do
			result[#result + 1] = copy(range)
		end
		local current = text
		for index = #merged, 1, -1 do
			local block = merged[index]
			local first = block.Point or original:LineColumnToPosition(block.First, 1)
			local last = block.Point or original:LineColumnToPosition(block.Last, #original:GetLine(block.Last) + 1)
			local transaction = Apps.EditorDocument.Apply(current, first, last, command, options or { Indent = "    " })
			local members = {}
			for _, id in ipairs(block.Members) do
				members[id] = true
			end
			local translate = command == "DuplicateLines" or moving
			local delta = transaction.Anchor - first
			local function mapped(position)
				local shift = 0
				for _, edit in ipairs(transaction.Edits) do
					if position < edit.Start then
						break
					end
					if position < edit.Finish then
						return edit.Start + shift + #edit.Text
					end
					shift += #edit.Text - (edit.Finish - edit.Start)
				end
				return position + shift
			end
			for _, range in ipairs(result) do
				if translate and members[range.Id] then
					range.Anchor += delta
					range.Caret += delta
				else
					range.Anchor = mapped(range.Anchor)
					range.Caret = mapped(range.Caret)
				end
			end
			current = transaction.Text
		end
		local normalized = Set.Normalize(current, result)
		table.sort(normalized, function(a, b)
			return a.Id < b.Id
		end)
		local primary = normalized[1] or { Anchor = 1, Caret = 1 }
		return {
			Text = current,
			Anchor = primary.Anchor,
			Caret = primary.Caret,
			Ranges = normalized,
			Changed = current ~= text,
		}
	end
	local function insertText(text, ordered, options, trackInsertions)
		local chunks, at, shift, result = {}, 1, 0, {}
		local insertions = if trackInsertions then {} else nil
		for index, range in ipairs(ordered) do
			local value = range.PasteText
				or (options and (options.Entries and options.Entries[index] or options.Text))
				or ""
			chunks[#chunks + 1] = text:sub(at, range.First - 1)
			chunks[#chunks + 1] = value
			at = range.Last
			local first = range.First + shift
			local caret = first + #value
			if insertions and caret > first then
				insertions[#insertions + 1] = { First = first, Last = caret }
			end
			result[#result + 1] = { Anchor = caret, Caret = caret, Id = range.Id }
			shift += #value - (range.Last - range.First)
		end
		chunks[#chunks + 1] = text:sub(at)
		local source = table.concat(chunks)
		table.sort(result, function(a, b)
			return a.Id < b.Id
		end)
		local primary = result[1] or { Anchor = 1, Caret = 1 }
		return {
			Text = source,
			Anchor = primary.Anchor,
			Caret = primary.Caret,
			Ranges = result,
			Insertions = insertions,
			Changed = source ~= text,
		}
	end
	function Set.Apply(text, ranges, command, options, doc)
		local ordered = Set.Normalize(text, ranges)
		if lineCommand(command, options, ordered) then
			return applyLines(text, ordered, command, options)
		end
		if command == "InsertText" and not (options and options.Overwrite) then
			return insertText(text, ordered, options)
		end
		if doc and #ordered == 1 then
			local range = ordered[1]
			local per = options or { Indent = "    " }
			if per.Entries then
				per = table.clone(per)
				per.Text = per.Entries[1]
			end
			local result = doc:Apply(command, range.Anchor, range.Caret, per)
			local clamp = Apps.EditorDocument.ClampSelectionPosition
			result.Anchor, result.Caret = clamp(result.Text, result.Anchor), clamp(result.Text, result.Caret)
			result.Ranges = { { Anchor = result.Anchor, Caret = result.Caret, Id = range.Id } }
			return result
		end
		local completed = {}
		local current = text
		for index = #ordered, 1, -1 do
			local range = ordered[index]
			local per = options or { Indent = "    " }
			if per.Entries then
				per = table.clone(per)
				per.Text = options.Entries[index]
				per.Entries = nil
			end
			local r = Apps.EditorDocument.Apply(current, range.Anchor, range.Caret, command, per)
			current = r.Text
			if r.Changed then
				local function mapped(p)
					local shift = 0
					for _, edit in ipairs(r.Edits) do
						if p < edit.Start then
							break
						end
						if p < edit.Finish then
							return edit.Start + shift + #edit.Text
						end
						shift += #edit.Text - (edit.Finish - edit.Start)
					end
					return p + shift
				end
				for _, done in ipairs(completed) do
					done.Anchor = mapped(done.Anchor)
					done.Caret = mapped(done.Caret)
				end
				for prior = 1, index - 1 do
					local pending = ordered[prior]
					pending.Anchor = mapped(pending.Anchor)
					pending.Caret = mapped(pending.Caret)
				end
			end
			completed[#completed + 1] = { Anchor = r.Anchor, Caret = r.Caret, Id = range.Id }
		end
		local normalized = Set.Normalize(current, completed)
		table.sort(normalized, function(a, b)
			return a.Id < b.Id
		end)
		local primary = normalized[1] or { Anchor = 1, Caret = 1 }
		return {
			Text = current,
			Anchor = primary.Anchor,
			Caret = primary.Caret,
			Ranges = normalized,
			Changed = current ~= text,
		}
	end
	function Set.Copy(text, ranges, doc)
		doc = doc or Apps.EditorDocument.Create(text)
		local ordered = Set.Normalize(text, ranges)
		local entries, whole = {}, {}
		for _, range in ipairs(ordered) do
			if range.First == range.Last then
				local line = doc:PositionToLineColumn(range.Caret)
				entries[#entries + 1] = doc:GetLine(line)
				whole[#whole + 1] = true
			else
				entries[#entries + 1] = text:sub(range.First, range.Last - 1)
				whole[#whole + 1] = false
			end
		end
		return {
			Entries = entries,
			WholeLines = whole,
			Text = table.concat(entries, "\n") .. (whole[#whole] and doc.Newline or ""),
		}
	end
	function Set.Paste(text, ranges, plain, packet, doc)
		doc = doc or Apps.EditorDocument.Create(text)
		local ordered = Set.Normalize(text, ranges)
		if not packet or packet.Text ~= plain or #packet.Entries ~= #ordered then
			return insertText(text, ordered, { Text = plain }, true)
		end
		local edits, candidate = {}, 1
		for index, range in ipairs(ordered) do
			local first, last = range.First, range.Last
			local wholeLine = packet.WholeLines[index]
			if wholeLine and first == last then
				local line = doc:PositionToLineColumn(first)
				local lineStart = doc:LineColumnToPosition(line, 1)
				while ordered[candidate] and ordered[candidate].Last <= lineStart do
					candidate += 1
				end
				local existing = ordered[candidate]
				if not existing or existing.First >= lineStart then
					first, last = lineStart, lineStart
				end
			end
			edits[index] = {
				First = first,
				Last = last,
				Id = range.Id,
				Order = index,
				PasteText = packet.Entries[index] .. (wholeLine and doc.Newline or ""),
			}
		end
		table.sort(edits, function(a, b)
			if a.First ~= b.First then
				return a.First < b.First
			elseif a.Last ~= b.Last then
				return a.Last < b.Last
			end
			return a.Order < b.Order
		end)
		return insertText(text, edits, nil, true)
	end
	return Set
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,

	Main = Main,
}
