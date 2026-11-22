--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Find = { SupportsRegex = Apps and Apps.EditorRegex ~= nil }
	local cachedSource, cachedLower
	local function folded(source)
		if source == cachedSource then
			return cachedLower
		end
		local lower = source:lower()
		if #source <= 2 * 1024 * 1024 then
			cachedSource, cachedLower = source, lower
		end
		return lower
	end
	local function boundary(source, position)
		if position < 1 or position > #source then
			return true
		end
		local byte = source:byte(position)
		return byte < 128 or byte >= 192
	end
	local function wordAt(source, position)
		if position < 1 or position > #source then
			return false
		end
		local byte = source:byte(position)
		return byte >= 128 or byte == 95 or (byte >= 48 and byte <= 57)
			or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
	end
	local function previous(source, position)
		position -= 1
		while position > 1 and not boundary(source, position) do
			position -= 1
		end
		return position
	end
	local function scope(source, options)
		local bounds = options.Scope
		local first = bounds and (bounds.Start or bounds[1]) or 1
		local last = bounds and (bounds.Finish or bounds[2]) or #source + 1
		first = math.clamp(math.floor(first), 1, #source + 1)
		last = math.clamp(math.floor(last), 1, #source + 1)
		if first > last then
			first, last = last, first
		end
		while first <= #source and not boundary(source, first) do
			first += 1
		end
		while last > first and not boundary(source, last) do
			last -= 1
		end
		return first, last
	end
	function Find.Search(source, query, options)
		options = options or {}
		local first, last = scope(source, options)
		local result = { Matches = {}, ScopeStart = first, ScopeFinish = last, Truncated = false }
		local limit = options.MaxMatches and math.max(0, math.floor(options.MaxMatches)) or math.huge
		local work = 0
		local function append(match)
			if #result.Matches >= limit then
				result.Truncated = true
				return false
			end
			result.Matches[#result.Matches + 1] = match
			return true
		end
		local function checkpoint()
			work += 1
			if work % 256 == 0 and options.Checkpoint and not options.Checkpoint() then
				result.Cancelled = true
				return false
			end
			return true
		end
		if query == "" then
			return result
		end
		if options.Regex then
			if not Find.SupportsRegex then
				result.Error = "Regular expression engine is unavailable."
				return result
			end
			local ok, matches = pcall(
				Apps.EditorRegex.Search,
				query,
				options.MatchCase and "m" or "mi",
				source,
				first,
				last,
				options.WorkLimit
			)
			if not ok then
				result.Error = tostring(matches)
				return result
			end
			for _, match in ipairs(matches) do
				if
					not options.WholeWord
					or not wordAt(source, previous(source, match.Start)) and not wordAt(source, match.Finish)
				then
					if not append(match) then
						break
					end
				end
				if not checkpoint() then
					break
				end
			end
			return result
		end
		if query == "" or first >= last then
			return result
		end
		local base = 0
		local haystack = source
		local length = last - first
		if length < #source / 4 and (#source + 1 - last > length or (not options.MatchCase and cachedSource ~= source)) then
			base = first - 1
			haystack = source:sub(first, last - 1)
			if not options.MatchCase then haystack = haystack:lower() end
		elseif not options.MatchCase then
			haystack = folded(source)
		end
		local needle = options.MatchCase and query or query:lower()
		local offset = first
		while offset < last do
			local start, finish = haystack:find(needle, offset - base, true)
			if not start then break end
			start, finish = start + base, finish + base
			if finish >= last then break end
			local valid = boundary(source, start) and boundary(source, finish + 1)
			if valid and options.WholeWord then
				valid = not wordAt(source, previous(source, start)) and not wordAt(source, finish + 1)
			end
			if valid then
				if not append({ Start = start, Finish = finish + 1 }) then
					break
				end
				offset = finish + 1
			else
				offset = start + 1
			end
			if not checkpoint() then
				break
			end
		end
		return result
	end
	function Find.Step(matches, caret, backward, currentIndex)
		local count = #matches
		if count == 0 then
			return nil, false
		end
		if currentIndex and currentIndex >= 1 and currentIndex <= count then
			local index = currentIndex + (backward and -1 or 1)
			if index < 1 then
				return count, true
			end
			if index > count then
				return 1, true
			end
			return index, false
		end
		local first, last = 1, count + 1
		while first < last do
			local middle = math.floor((first + last) / 2)
			if matches[middle].Start < caret then
				first = middle + 1
			else
				last = middle
			end
		end
		if backward then
			return if first > 1 then first - 1 else count, first == 1
		end
		return if first <= count then first else 1, first > count
	end
	local function validMatch(source, match, after)
		return match
			and type(match.Start) == "number"
			and type(match.Finish) == "number"
			and match.Start % 1 == 0
			and match.Finish % 1 == 0
			and match.Start >= (after or 1)
			and match.Finish >= match.Start
			and match.Finish <= #source + 1
			and boundary(source, match.Start)
			and boundary(source, match.Finish)
	end
	local function replacementText(match, replacement)
		if not match.Regex then
			return replacement
		end
		local function group(name)
			if tonumber(name) then
				return match.Groups[tonumber(name)] or ""
			end
			return match.NamedGroups[name] or ""
		end
		local chunks, index = {}, 1
		while index <= #replacement do
			local char = replacement:sub(index, index)
			local following = replacement:sub(index + 1, index + 1)
			if char == "$" and following == "$" then
				chunks[#chunks + 1] = "$"
				index += 2
			elseif char == "$" and following == "&" then
				chunks[#chunks + 1] = group("0")
				index += 2
			elseif char == "$" and following == "{" then
				local ending = replacement:find("}", index + 2, true)
				if ending then
					chunks[#chunks + 1] = group(replacement:sub(index + 2, ending - 1))
					index = ending + 1
				else
					chunks[#chunks + 1] = char
					index += 1
				end
			elseif char == "$" and following:match("%d") then
				local name = replacement:match("^(%d%d?)", index + 1)
				chunks[#chunks + 1] = group(name)
				index += 1 + #name
			else
				chunks[#chunks + 1] = char
				index += 1
			end
		end
		return table.concat(chunks)
	end
	function Find.Replace(source, match, replacement)
		if not validMatch(source, match) then
			return { Text = source, Caret = 1, Count = 0, Error = "Invalid or stale search match." }
		end
		replacement = replacementText(match, replacement)
		return {
			Text = source:sub(1, match.Start - 1) .. replacement .. source:sub(match.Finish),
			Caret = match.Start + #replacement,
			Count = 1,
		}
	end
	function Find.ReplaceAll(source, matches, replacement)
		local chunks, offset, count, caret, shift = {}, 1, 0, 1, 0
		for _, match in ipairs(matches) do
			if not validMatch(source, match, offset) then
				return { Text = source, Caret = 1, Count = 0, Error = "Invalid or overlapping search matches." }
			end
			chunks[#chunks + 1] = source:sub(offset, match.Start - 1)
			local value = replacementText(match, replacement)
			chunks[#chunks + 1] = value
			caret = match.Start + shift + #value
			shift += #value - (match.Finish - match.Start)
			offset = match.Finish
			count += 1
		end
		chunks[#chunks + 1] = source:sub(offset)
		return { Text = table.concat(chunks), Caret = caret, Count = count }
	end
	return Find
end
return {
	InitDeps = function(deps)
		Apps = deps.Apps
	end,
	InitAfterMain = function() end,
	Main = Main,
}
