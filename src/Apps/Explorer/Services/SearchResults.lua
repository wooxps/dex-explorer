--!strict

local Apps

local function Main()
	local Bits = Apps.SearchBits
	local Results = {}

	local createView
	local function snapshotChildren(node, read, checkpoint)
		local children = read(node, checkpoint)
		if children == node then
			return table.move(children, 1, #children, 1, table.create(#children))
		end
		return children
	end
	function Results.MatchesVisibility(layout, visible)
		if not layout then
			return false
		end
		for node, shown in pairs(layout.RootVisibility or {}) do
			if visible(node) ~= shown then
				return false
			end
		end
		return true
	end

	function Results.CreateLayout(roots, context, checkpoint)
		local estimate = math.clamp(context.Estimate or 0, 0, 250000)
		local nodes, names = table.create(estimate), table.create(estimate)
		local ends, depths, parents = table.create(estimate), table.create(estimate), table.create(estimate)
		local positions, top = {}, {}
		local rootVisibility = context.VisibleOnly and {} or nil
		local readName, readChildren = context.Name, context.Children
		local count = 0
		local function visit(node, parent, depth)
			if node.Del then
				return
			end
			count += 1
			if count % 128 == 0 then
				checkpoint()
			end
			local position = count
			nodes[position], names[position] = node, readName(node)
			parents[position], depths[position] = parent, depth
			positions[node] = position
			if parent == 0 then
				top[#top + 1] = position
			end
			if #node > 0 then
				for _, child in ipairs(snapshotChildren(node, readChildren, checkpoint)) do
					if child.Parent == node then
						visit(child, position, depth + 1)
					end
				end
			end
			ends[position] = count
		end
		for _, node in ipairs(snapshotChildren(roots[1], readChildren, checkpoint)) do
			local shown = not rootVisibility or context.Visible(node)
			if rootVisibility then
				rootVisibility[node] = shown
			end
			if shown and node.Parent == roots[1] then
				visit(node, 0, 1)
			end
		end
		if roots[2] then
			visit(roots[2], 0, 1)
		end
		return {
			Nodes = nodes,
			Names = names,
			Ends = ends,
			Depths = depths,
			Parents = parents,
			Widths = {},
			Positions = positions,
			Top = top,
			NilRoot = roots[2],
			RootVisibility = rootVisibility,
		}
	end

	local charLanes, lowBits, highBits = {}, {}, {}
	for lane = 1, 36 do
		local bit = bit32.lshift(1, (lane - 1) % 32)
		if lane <= 26 then
			charLanes[96 + lane] = lane
			charLanes[64 + lane] = lane
		else
			charLanes[21 + lane] = lane
		end
		if lane <= 32 then
			lowBits[bit] = lane
		else
			highBits[bit] = lane
		end
	end

	function Results.PrepareCharacters(layout, checkpoint)
		local nodes, names = layout.Nodes, layout.Names
		local parents, depths = layout.Parents, layout.Depths
		local positions = not layout.Positions and {} or nil
		local top = not layout.Top and {} or nil
		local columns, matchWords, ancestorWords = table.create(36), table.create(36, 0), table.create(36, 0)
		for lane = 1, 36 do
			columns[lane] = { Match = Bits.Dense(#nodes), Context = Bits.Dense(#nodes), Width = 0, Depth = 1 }
		end
		local pendingLow, pendingHigh, nameMasks = {}, {}, {}
		local cacheCount = 0
		local bor, band, bnot, lshift = bit32.bor, bit32.band, bit32.bnot, bit32.lshift
		local highUnit = 4294967296
		local function nameMask(name)
			local cached = nameMasks[name]
			if cached then
				return cached % highUnit, cached // highUnit
			end
			local lo, hi = 0, 0
			for index = 1, #name do
				local lane = charLanes[string.byte(name, index)]
				if lane then
					if lane <= 32 then
						lo = bor(lo, lshift(1, lane - 1))
					else
						hi = bor(hi, lshift(1, lane - 33))
					end
				end
			end
			if cacheCount < 4096 then
				nameMasks[name] = lo + hi * highUnit
				cacheCount += 1
			end
			return lo, hi
		end
		for position = #nodes, 1, -1 do
			local node, name = nodes[position], names[position]
			if positions then positions[node] = position end
			if top and parents[position] == 0 then top[#top + 1] = position end
			local ownLow, ownHigh = 0, 0
			if node ~= layout.NilRoot then
				ownLow, ownHigh = nameMask(name)
			end
			local childLow, childHigh = pendingLow[position], pendingHigh[position]
			local lo, hi = ownLow, ownHigh
			if childLow then
				pendingLow[position] = nil
				lo = bor(lo, childLow)
				childLow = band(childLow, bnot(ownLow))
			end
			if childHigh then
				pendingHigh[position] = nil
				hi = bor(hi, childHigh)
				childHigh = band(childHigh, bnot(ownHigh))
			end
			local parent = parents[position]
			if parent > 0 then
				if lo ~= 0 then
					pendingLow[parent] = bor(pendingLow[parent] or 0, lo)
				end
				if hi ~= 0 then
					pendingHigh[parent] = bor(pendingHigh[parent] or 0, hi)
				end
			end
			local index = (position - 1) % 32
			local rowBit = lshift(1, index)
			local width, depth = node.NameWidth or math.min(100, #name) * 14, depths[position]
			while ownLow ~= 0 do
				local lowBit = band(ownLow, -ownLow)
				local lane = lowBits[lowBit]
				local column = columns[lane]
				matchWords[lane] = bor(matchWords[lane], rowBit)
				if width > column.Width then
					column.Width = width
				end
				if depth > column.Depth then
					column.Depth = depth
				end
				ownLow = band(ownLow, ownLow - 1)
			end
			while ownHigh ~= 0 do
				local lowBit = band(ownHigh, -ownHigh)
				local lane = highBits[lowBit]
				local column = columns[lane]
				matchWords[lane] = bor(matchWords[lane], rowBit)
				if width > column.Width then
					column.Width = width
				end
				if depth > column.Depth then
					column.Depth = depth
				end
				ownHigh = band(ownHigh, ownHigh - 1)
			end
			while childLow and childLow ~= 0 do
				local lowBit = band(childLow, -childLow)
				local lane = lowBits[lowBit]
				local column = columns[lane]
				ancestorWords[lane] = bor(ancestorWords[lane], rowBit)
				if width > column.Width then
					column.Width = width
				end
				if depth > column.Depth then
					column.Depth = depth
				end
				childLow = band(childLow, childLow - 1)
			end
			while childHigh and childHigh ~= 0 do
				local lowBit = band(childHigh, -childHigh)
				local lane = highBits[lowBit]
				local column = columns[lane]
				ancestorWords[lane] = bor(ancestorWords[lane], rowBit)
				if width > column.Width then
					column.Width = width
				end
				if depth > column.Depth then
					column.Depth = depth
				end
				childHigh = band(childHigh, childHigh - 1)
			end
			if index == 0 then
				local offset = (position - 1) // 32 * 4
				for lane, column in ipairs(columns) do
					local matchWord = matchWords[lane]
					local ancestorWord = ancestorWords[lane]
					if matchWord ~= 0 or ancestorWord ~= 0 then
						buffer.writeu32(column.Match.Data, offset, matchWord)
						buffer.writeu32(column.Context.Data, offset, bor(matchWord, ancestorWord))
						column.Match.Count += Bits.Pop(matchWord)
						matchWords[lane], ancestorWords[lane] = 0, 0
					end
				end
				checkpoint()
			end
		end
		layout.Positions = layout.Positions or positions
		layout.Top = layout.Top or top
		layout.Characters = columns
	end

	function Results.CreateIndexed(layout, term, context, checkpoint)
		local lane = #term == 1 and charLanes[string.byte(term)]
		local column = lane and layout.Characters and layout.Characters[lane]
		if not column then
			return nil
		end
		if not column.Match.Prefix then
			column.Match:Prepare(checkpoint)
		end
		if not column.Context.Prefix then
			column.Context:Prepare(checkpoint)
		end
		local top = {}
		for index, at in ipairs(layout.Top) do
			if column.Context:Has(at) then
				top[#top + 1] = at
			end
			if index % 128 == 0 then
				checkpoint()
			end
		end
		return createView(
			layout,
			context,
			checkpoint,
			layout.Positions,
			top,
			column.Match,
			column.Context,
			column.Width,
			column.Depth
		)
	end

	function Results.CreatePredicate(layout, predicate, context, checkpoint, roots, matchNode, className)
		layout = layout or Results.CreateLayout(roots, context, checkpoint)
		if not layout.Positions then
			local positions = {}
			for i, node in ipairs(layout.Nodes) do
				positions[node] = i
				if i % 256 == 0 then
					checkpoint()
				end
			end
			layout.Positions = positions
		end
		local cache = layout.ClassResults
		local result = className and cache and cache[className]
		if not result then
			local nodes, names, ends, depths, parents = layout.Nodes, layout.Names, layout.Ends, layout.Depths, layout.Parents
			local allMatches, allContext = Bits.Dense(#nodes), Bits.Dense(#nodes)
			local top, width, depth = {}, 0, 1
			local object = context.Object
			local bor, band, lshift = bit32.bor, bit32.band, bit32.lshift
			local queryable = layout.NilRoot
			for first = 1, #nodes, 32 do
				local matchWord = 0
				for i = first, math.min(first + 31, #nodes) do
					local node = nodes[i]
					if node ~= queryable then
						local hit
						if matchNode then
							hit = matchNode(node)
						else
							local ok, value = pcall(predicate, if object then object(node) else node.Obj)
							hit = ok and value
						end
						if hit then
							matchWord = bor(matchWord, lshift(1, i - first))
						end
					end
				end
				buffer.writeu32(allMatches.Data, (first - 1) // 8, matchWord)
				if first % 128 == 1 then
					checkpoint()
				end
			end

			allMatches:Prepare(checkpoint)
			if allMatches.Count <= #nodes // 64 then
				allMatches:Each(function(i)
					while i > 0 and allContext:Set(i) do
						width = math.max(width, nodes[i].NameWidth or math.min(100, #names[i]) * 14)
						depth = math.max(depth, depths[i])
						local parent = parents[i]
						if parent == 0 then top[#top + 1] = i end
						if depths[i] % 128 == 0 then checkpoint() end
						i = parent
					end
				end, checkpoint)
			else
				local nextMatch = math.huge
				for word = (#nodes + 31) // 32 - 1, 0, -1 do
					local offset = word * 4
					local matchWord = buffer.readu32(allMatches.Data, offset)
					local contextWord = 0
					local first = word * 32 + 1
					for i = math.min(first + 31, #nodes), first, -1 do
						local bit = lshift(1, i - first)
						if band(matchWord, bit) ~= 0 then
							nextMatch = i
						end
						if nextMatch <= ends[i] then
							contextWord = bor(contextWord, bit)
							width = math.max(width, nodes[i].NameWidth or math.min(100, #names[i]) * 14)
							depth = math.max(depth, depths[i])
							if parents[i] == 0 then
								top[#top + 1] = i
							end
						end
					end
					buffer.writeu32(allContext.Data, offset, contextWord)
					if word % 4 == 0 then
						checkpoint()
					end
				end
			end
			allContext:Prepare(checkpoint)
			result = { Match = allMatches, Context = allContext, Top = top, Width = width, Depth = depth }
			if className then
				cache = layout.ClassResults or {}
				local order = layout.ClassOrder or {}
				if #order >= 4 then
					cache[table.remove(order, 1)] = nil
				end
				order[#order + 1] = className
				cache[className] = result
				layout.ClassResults, layout.ClassOrder = cache, order
			end
		end
		return createView(layout, context, checkpoint, layout.Positions, result.Top, result.Match, result.Context, result.Width, result.Depth)
	end

	-- Keep immutable membership on the hierarchy snapshot. Each visit gets its own
	-- expansion, removals and visibility, even when a user backspaces to an earlier query.
	local function literalView(layout, terms, context, checkpoint, positions, top, matches, included, width, depth)
		if #layout.Nodes >= 1024 and #terms == 1 and #terms[1] <= 256 then
			local recent = layout.LiteralResults or {}
			local largeMap = positions ~= layout.Positions and included.Count > #layout.Nodes // 16
			for i = #recent, 1, -1 do
				if recent[i].Term == terms[1] or (largeMap and recent[i].LargeMap) then
					table.remove(recent, i)
				end
			end
			if #recent == 6 then table.remove(recent, 1) end
			recent[#recent + 1] = { Term = terms[1], Positions = positions, Top = top,
				Match = matches, Context = included, Depth = depth, LargeMap = largeMap }
			layout.LiteralResults = recent
		end
		return createView(layout, context, checkpoint, positions, top, matches, included, width, depth)
	end

	local function scanNameBlocks(layout, terms, checkpoint, matchesName)
		local names, nodes = layout.Names, layout.Nodes
		-- Common queries are cheaper to scan directly. Sample across the tree so a
		-- single folder full of matches doesn't determine the path for every folder.
		local sampledHits = 0
		local stride = #nodes // 16
		for i = stride, stride * 16, stride do
			if matchesName(names[i]) then
				sampledHits += 1
				if sampledHits == 4 then return nil end
			end
		end
		local needle = terms[1]
		for i = 2, #terms do
			if #terms[i] > #needle then needle = terms[i] end
		end
		local blocks = layout.NameBlocks or {}
		layout.NameBlocks = blocks
		if #needle == 0 then return nil end
		local candidates = {}
		local limit = math.max(32, #nodes // 32)
		for first = 1, #nodes, 128 do
			local last = math.min(first + 127, #nodes)
			local block = (first - 1) // 128 + 1
			local text = blocks[block]
			if not text then
				text = string.lower(table.concat(names, "\0", first, last))
				blocks[block] = text
			end
			local at = string.find(text, needle, 1, true)
			if at then
				local row, start = first, 1
				while at do
					local finish = start + #names[row] - 1
					while at > finish and row < last do
						start = finish + 2
						row += 1
						finish = start + #names[row] - 1
					end
					if at >= start and at + #needle - 1 <= finish then
						if nodes[row] ~= layout.NilRoot and (#terms == 1 or matchesName(names[row])) then
							candidates[#candidates + 1] = row
							if #candidates > limit then return nil end
						end
					end
					-- A hit on the separator can be followed by a valid hit in this row.
					at = string.find(text, needle, if at < start then start else finish + 2, true)
				end
			end
			if block % 4 == 0 then checkpoint() end
		end
		return candidates
	end

	local function sparseNameView(layout, terms, context, checkpoint, matchesName)
		local nodes, names = layout.Nodes, layout.Names
		if #nodes < 1024 then return nil end
		local subset
		for _, entry in ipairs(layout.LiteralResults or {}) do
			if #terms == 1 and terms[1] == entry.Term then
				-- Widths may have been measured since this search last ran.
				local width = 0
				entry.Context:Each(function(i)
					width = math.max(width, nodes[i].NameWidth or math.min(100, #names[i]) * 14)
				end, checkpoint)
				return createView(layout, context, checkpoint, layout.Positions or entry.Positions, entry.Top,
					entry.Match, entry.Context, width, entry.Depth)
			end
			if entry.Match.Count <= #nodes // 32 and (not subset or entry.Match.Count < subset.Count) then
				for _, term in ipairs(terms) do
					if string.find(term, entry.Term, 1, true) then
						subset = entry.Match
						break
					end
				end
			end
		end
		-- Every literal match must also contain each of its ASCII letters and digits.
		-- A rare character can narrow a new query before any prefix has been searched.
		if layout.Characters then
			for _, term in ipairs(terms) do
				for i = 1, math.min(#term, 128) do
					local column = layout.Characters[charLanes[string.byte(term, i)]]
					if column and column.Match.Count <= #nodes // 32 and (not subset or column.Match.Count < subset.Count) then
						subset = column.Match
					end
				end
			end
		end
		local candidates
		if subset then
			if subset.Count == 0 then
				return createView(layout, context, checkpoint, layout.Positions or {}, {}, subset, subset, 0, 1)
			end
			candidates = {}
			subset:Each(function(i)
				if matchesName(names[i]) then candidates[#candidates + 1] = i end
			end, checkpoint)
		else
			candidates = scanNameBlocks(layout, terms, checkpoint, matchesName)
			if not candidates then return nil end
		end
		local matches, included = Bits.Dense(#nodes), Bits.Dense(#nodes)
		local fullPositions = layout.Positions
		local positions, parents = fullPositions or {}, layout.Parents
		local top, width, depth = {}, 0, 1
		for i, position in candidates do
			matches:Set(position)
			local at = position
			while at > 0 and included:Set(at) do
				if not fullPositions then positions[nodes[at]] = at end
				width = math.max(width, nodes[at].NameWidth or math.min(100, #names[at]) * 14)
				depth = math.max(depth, layout.Depths[at])
				local parent = parents[at]
				if parent == 0 then top[#top + 1] = at end
				if layout.Depths[at] % 128 == 0 then checkpoint() end
				at = parent
			end
			if i % 128 == 0 then checkpoint() end
		end
		return literalView(layout, terms, context, checkpoint, positions, top, matches:Prepare(checkpoint), included:Prepare(checkpoint), width, depth)
	end

	function Results.CreateCold(roots, terms, context, checkpoint, layout)
		if context.VisibleOnly and (not layout or not layout.RootVisibility or not Results.MatchesVisibility(layout, context.Visible)) then
			layout = nil
		end
		local estimate = math.clamp(context.Estimate or 0, 0, 250000)
		local nodes = layout and layout.Nodes or table.create(estimate)
		local names = layout and layout.Names or table.create(estimate)
		local ends = layout and layout.Ends or table.create(estimate)
		local depths = layout and layout.Depths or table.create(estimate)
		local parents = layout and layout.Parents or table.create(estimate)
		local widths = layout and layout.Widths or {}
		local fullPositions = layout and layout.Positions
		local positions, top = fullPositions or {}, {}
		local matchWords, contextWords = {}, {}
		local rootVisibility = context.VisibleOnly and {} or nil
		local width, maxDepth = 0, 1
		local firstTerm, termCount = terms[1], #terms
		local nameResults, cachedNames = {}, 0
		local function matchesName(name)
			local cached = nameResults[name]
			if cached ~= nil then
				return cached
			end
			local lower = string.lower(name)
			local hit = string.find(lower, firstTerm, 1, true) ~= nil
			if hit then
				for index = 2, termCount do
					if not string.find(lower, terms[index], 1, true) then
						hit = false
						break
					end
				end
			end
			if cachedNames < 8192 then
				nameResults[name] = hit
				cachedNames += 1
			end
			return hit
		end
		local readName, readChildren = context.Name, context.Children
		local nodeCount = #nodes
		local function visitChildren(owner, children, parent, depth)
			local hasMatches = false
			for _, node in ipairs(children) do
				if owner == roots[1] and rootVisibility then
					local shown = context.Visible(node)
					rootVisibility[node] = shown
					if not shown then continue end
				end
				if node.Del or (owner and node.Parent ~= owner) then continue end
				nodeCount += 1
				if nodeCount % 128 == 0 then checkpoint() end
				local position = nodeCount
				local name = readName(node)
				nodes[position], names[position] = node, name
				depths[position], parents[position] = depth, parent
				local hit = owner ~= nil and nameResults[name]
				if hit == nil then hit = matchesName(name) end
				local childMatch = #node > 0 and visitChildren(node, snapshotChildren(node, readChildren, checkpoint), position, depth + 1)
				ends[position] = nodeCount
				if hit or childMatch then
					hasMatches = true
					positions[node] = position
					local word = (position - 1) // 32
					local rowBit = bit32.lshift(1, (position - 1) % 32)
					local words = if hit then matchWords else contextWords
					words[word] = bit32.bor(words[word] or 0, rowBit)
					if parent == 0 then top[#top + 1] = position end
					if depth > maxDepth then maxDepth = depth end
					local nameWidth = node.NameWidth or math.min(100, #name) * 14
					if nameWidth > width then width = nameWidth end
				end
			end
			return hasMatches
		end
		if layout then
			local sparse = sparseNameView(layout, terms, context, checkpoint, matchesName)
			if sparse then return sparse end
			local nextMatch = math.huge
			local matchWord, contextWord = 0, 0
			local matchedBits, contextBits = Bits.Dense(#nodes), Bits.Dense(#nodes)
			for position = #nodes, 1, -1 do
				local node, name = nodes[position], names[position]
				local hit = node ~= roots[2] and matchesName(name)
				local rowBit = bit32.lshift(1, (position - 1) % 32)
				if hit then
					matchWord = bit32.bor(matchWord, rowBit)
					nextMatch = position
				end
				if nextMatch <= ends[position] then
					local parent = parents[position]
					if not fullPositions then
						positions[node] = position
					end
					contextWord = bit32.bor(contextWord, rowBit)
					if parent == 0 then
						top[#top + 1] = position
					end
					local depth = depths[position]
					if depth > maxDepth then maxDepth = depth end
					local nameWidth = node.NameWidth or math.min(100, #name) * 14
					if nameWidth > width then width = nameWidth end
				end
				if (position - 1) % 32 == 0 then
					local offset = (position - 1) // 32 * 4
					buffer.writeu32(matchedBits.Data, offset, matchWord)
					buffer.writeu32(contextBits.Data, offset, contextWord)
					matchWord, contextWord = 0, 0
				end
				if position % 128 == 0 then
					checkpoint()
				end
			end
			return literalView(layout, terms, context, checkpoint, positions, top, matchedBits:Prepare(checkpoint), contextBits:Prepare(checkpoint), width, maxDepth)
		else
			visitChildren(roots[1], snapshotChildren(roots[1], readChildren, checkpoint), 0, 1)
			if roots[2] then visitChildren(nil, { roots[2] }, 0, 1) end
		end
		local allMatches, allContext = Bits.Dense(#nodes), Bits.Dense(#nodes)
		for word = 0, (#nodes + 31) // 32 - 1 do
			local matched = matchWords[word] or 0
			local included = bit32.bor(matched, contextWords[word] or 0)
			buffer.writeu32(allMatches.Data, word * 4, matched)
			buffer.writeu32(allContext.Data, word * 4, included)
			if word % 128 == 0 then checkpoint() end
		end
		allMatches:Prepare(checkpoint)
		allContext:Prepare(checkpoint)
		layout = layout or {
			Nodes = nodes,
			Names = names,
			Ends = ends,
			Depths = depths,
			Parents = parents,
			Widths = widths,
			NilRoot = roots[2],
			RootVisibility = rootVisibility,
		}
		return literalView(layout, terms, context, checkpoint, positions, top, allMatches, allContext, width, maxDepth)
	end

	createView = function(layout, context, checkpoint, positions, top, allMatches, allContext, width, maxDepth)
		local nodes, names, ends, depths, parents, widths =
			layout.Nodes, layout.Names, layout.Ends, layout.Depths, layout.Parents, layout.Widths
		local result = {
			Width = width,
			Depth = maxDepth,
			ExactWidth = false,
			WidthRevision = 0,
			Overrides = {},
			Removed = {},
			ExpansionVersion = 0,
			OverrideRevision = 0,
			Resolved = 0,
			Pages = {},
			PageOrder = {},
			Cold = true,
			ColdLayout = layout,
		}
		local matches, contextRows, visible = allMatches, allContext, allContext
		local allowed = {}
		function result:Contains(node)
			return allContext:Has(positions[node])
		end
		function result:HasChildren(node)
			local at = positions[node]
			return at ~= nil and ends[at] > at and contextRows:Has(at) and contextRows:Rank(ends[at]) > contextRows:Rank(at)
		end
		function result:Remove(node)
			if self:Contains(node) and not self.Removed[node] then
				self.Removed[node] = true
				self.ExpansionVersion += 1
			end
		end
		function result:NameOf(node)
			local at = positions[node]
			return (not layout.Positions or allContext:Has(at)) and names[at] or nil
		end
		function result:DepthOf(node)
			local at = positions[node]
			return (not layout.Positions or allContext:Has(at)) and depths[at] or nil
		end
		function result:IndexOf(node)
			local at = positions[node]
			return at and visible:Has(at) and visible:Rank(at) or nil
		end
		function result:PositionOfMatch(node)
			local at = positions[node]
			return at and matches:Has(at) and matches:Rank(at) or nil
		end
		function result:MaterializeMatches(include)
			local output = table.create(matches.Count)
			matches:Each(function(at)
				local node = nodes[at]
				if not include or include(node) then
					output[#output + 1] = node
				end
			end)
			return output
		end
		function result:MeasureWidths(measure, check)
			local masks, maxima = layout.WidthMasks, layout.WidthMaxima
			if not masks then
				masks, maxima = {}, {}
				layout.WidthMasks, layout.WidthMaxima = masks, maxima
			end
			local maximum = 0
			local data = visible.Data
			for word = 0, buffer.len(data) // 4 - 1 do
				local mask = buffer.readu32(data, word * 4)
				if mask ~= 0 then
					local index = word + 1
					local widest = maxima[index]
					if masks[index] ~= mask then
						local bits, exact = mask, true
						widest = 0
						while bits ~= 0 do
							local at = word * 32 + bit32.countrz(bits) + 1
							local value = widths[at]
							if not value then
								local reusable
								value, reusable = measure({ Node = nodes[at], Name = names[at] })
								if reusable ~= false then widths[at] = value else exact = false end
							end
							widest = math.max(widest, value)
							bits = bit32.band(bits, bits - 1)
						end
						if exact then masks[index], maxima[index] = mask, widest end
					end
					maximum = math.max(maximum, widest)
				end
				if word % 4 == 0 then check() end
			end
			return maximum
		end
		function result:RememberStats() end
		function result:Reflow(check)
			local changed = self.AppliedExpansion ~= self.ExpansionVersion
			local hasHidden = false
			for _, at in ipairs(top) do
				local shown = context.Visible(nodes[at])
				hasHidden = hasHidden or not shown
				changed = changed or allowed[at] ~= shown
				allowed[at] = shown
			end
			if not changed then
				return
			end
			matches, contextRows = allMatches, allContext
			if hasHidden or next(self.Removed) then
				matches, contextRows = allMatches:Clone(), allContext:Clone()
				local function hide(at)
					matches:ClearRange(at, ends[at])
					contextRows:ClearRange(at, ends[at])
				end
				for _, at in ipairs(top) do
					if not allowed[at] then
						hide(at)
					end
				end
				for node in pairs(self.Removed) do
					hide(positions[node])
				end
				matches:Prepare(check)
				for node in pairs(self.Removed) do
					local ancestor = parents[positions[node]]
					while ancestor > 0 and matches:Rank(ends[ancestor]) == matches:Rank(ancestor - 1) do
						contextRows:Set(ancestor, false)
						ancestor = parents[ancestor]
					end
				end
				contextRows:Prepare(check)
			end
			visible = contextRows
			for node, value in pairs(self.Overrides) do
				local at = positions[node]
				if value == false and at then
					if visible == contextRows then
						visible = contextRows:Clone()
					end
					visible:ClearRange(at + 1, ends[at])
				end
			end
			if visible ~= contextRows then
				visible:Prepare(check)
			end
			self.MatchBits, self.VisibleBits = matches, visible
			self.WidthRevision += 1
			self.ExactWidth = false
			self.AppliedExpansion = self.ExpansionVersion
		end
		result.Rows = setmetatable({
			IndexOf = function(node)
				return result:IndexOf(node)
			end,
			DepthOf = function(node)
				return result:DepthOf(node)
			end,
		}, {
			__len = function()
				return visible.Count
			end,
			__index = function(_, i)
				local at = type(i) == "number" and visible:Select(i)
				return at and nodes[at] or nil
			end,
		})
		result.Indices = setmetatable({}, {
			__index = function(_, node)
				return result:IndexOf(node)
			end,
		})
		result.Matches = setmetatable({}, {
			__index = function(_, node)
				return matches:Has(positions[node]) or nil
			end,
		})
		result.MatchList = setmetatable({
			IndexOf = function(node)
				return result:PositionOfMatch(node)
			end,
		}, {
			__len = function()
				return matches.Count
			end,
			__index = function(_, i)
				local at = type(i) == "number" and matches:Select(i)
				return at and nodes[at] or nil
			end,
		})
		result.Expanded = setmetatable({}, {
			__newindex = function(_, node, value)
				if result.Expanded[node] ~= value then
					result.Overrides[node] = value
					result.OverrideRevision += 1
					result.ExpansionVersion += 1
				end
			end,
			__index = function(_, node)
				local override = result.Overrides[node]
				if override ~= nil then
					return override
				end
				local at = positions[node]
				if at and contextRows:Has(at) then
					return ends[at] > at and contextRows:Rank(ends[at]) > contextRows:Rank(at) and true or 0
				end
			end,
		})
		result:Reflow(checkpoint)
		return result
	end
	return Results
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,
	InitAfterMain = function() end,
	Main = Main,
}
