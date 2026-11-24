--!strict

------------------------------ Module ------------------------------

local function Main()
	local SearchNameIndex = {}
	local function readName(node)
		return node.Obj.Name
	end

	local function sameRoots(left, right)
		if not left or #left ~= #right then
			return false
		end
		for index, root in ipairs(left) do
			if right[index] ~= root then
				return false
			end
		end
		return true
	end

	function SearchNameIndex.Create()
		local revision, indexedRoots
		local nodes, names, positionsByNode = {}, {}, {}
		local rawNames = {}
		local pending = {}
		local activeChanges
		local groups, groupCount = {}, 0
		local function addName(name, position)
			local bucket = groups[name]
			if not bucket then
				groups[name] = position
				groupCount += 1
			elseif type(bucket) == "number" then
				if bucket ~= position then
					groups[name] = { [bucket] = true, [position] = true }
				end
			else
				bucket[position] = true
			end
		end
		local function removeName(name, position)
			local bucket = groups[name]
			if not bucket then
				return
			end
			if type(bucket) == "number" then
				if bucket == position then
					groups[name] = nil
					groupCount -= 1
				end
			else
				bucket[position] = nil
				local first = next(bucket)
				if not first then
					groups[name] = nil
					groupCount -= 1
				elseif next(bucket, first) == nil then
					groups[name] = first
				end
			end
		end
		local previousTerm, previousMatches
		local queryCache, queryOrder = {}, {}
		local queryPositions = {}
		local function clearQueries()
			table.clear(queryCache)
			table.clear(queryOrder)
			table.clear(queryPositions)
		end
		local function dropQuery(term)
			queryCache[term] = nil
			queryPositions[term] = nil
			local at = table.find(queryOrder, term)
			if at then
				table.remove(queryOrder, at)
			end
		end
		local function cacheQuery(term, items)
			dropQuery(term)
			if #queryOrder >= 8 then
				dropQuery(queryOrder[1])
			end
			queryOrder[#queryOrder + 1] = term
			queryCache[term] = items
			if #items <= 8192 then
				local map = {}
				for i, position in ipairs(items) do
					map[position] = i
				end
				queryPositions[term] = map
			end
		end
		local function updateQuery(term, position, matched)
			local map = queryPositions[term]
			if not map then
				return
			end
			local items = queryCache[term]
			local at = map[position]
			if matched and not at then
				if #items >= 8192 then
					dropQuery(term)
					return
				end
				items[#items + 1] = position
				map[position] = #items
			elseif not matched and at then
				local last = items[#items]
				items[at] = last
				map[last] = at
				items[#items] = nil
				map[position] = nil
			end
		end
		local index = { Stats = { Builds = 0, NameReads = 0, Candidates = 0, Updates = 0 } }

		local function build(roots, nextRevision, checkpoint, term)
			local nextNodes, nextNames, nextPositions, found = {}, {}, {}, {}
			local nextRaw = {}
			local normalized, termMatches = {}, {}
			local nextGroups, nextGroupCount = {}, 0
			local stack, positions = {}, {}
			local visited = 0
			for _, root in ipairs(roots) do
				local depth = 1
				stack[1], positions[1] = root, 1
				while depth > 0 do
					local parent, position = stack[depth], positions[depth]
					local node = parent[position]
					if not node then
						stack[depth], positions[depth] = nil, nil
						depth -= 1
					else
						positions[depth] = position + 1
						local ok, name = pcall(readName, node)
						index.Stats.NameReads += 1
						if ok and type(name) == "string" then
							local position = #nextNodes + 1
							local lower = normalized[name]
							nextRaw[position] = name
							if not lower then
								lower = string.lower(name)
								normalized[name] = lower
							end
							nextNodes[position], nextNames[position], nextPositions[node] = node, lower, position
							local bucket = nextGroups[lower]
							if not bucket then
								nextGroups[lower] = position
								nextGroupCount += 1
							elseif type(bucket) == "number" then
								nextGroups[lower] = { [bucket] = true, [position] = true }
							else
								bucket[position] = true
							end
							local matched = termMatches[lower]
							if matched == nil then
								matched = string.find(lower, term, 1, true) ~= nil
								termMatches[lower] = matched
							end
							if matched then
								found[#found + 1] = position
							end
						end
						if #node > 0 then
							depth += 1
							stack[depth], positions[depth] = node, 1
						end
						visited += 1
						if checkpoint and visited % 256 == 0 and not checkpoint() then
							return false
						end
					end
				end
			end
			nodes, names = nextNodes, nextNames
			rawNames = nextRaw
			groups, groupCount = nextGroups, nextGroupCount
			positionsByNode = nextPositions
			indexedRoots, revision = table.clone(roots), nextRevision
			previousTerm, previousMatches = nil, nil
			clearQueries()
			index.Stats.Builds += 1
			return true, found
		end

		function index.MarkDirty(node, subtree)
			if indexedRoots then
				pending[node] = pending[node] or subtree or false
			end
		end
		function index.CachedName(node)
			local position = positionsByNode[node]
			if not position then return nil end
			if not activeChanges and next(pending) == nil then
				return rawNames[position]
			end
			local ancestor = node
			while ancestor do
				if
					pending[ancestor] ~= nil and (ancestor == node or pending[ancestor])
					or activeChanges
						and activeChanges[ancestor] ~= nil
						and (ancestor == node or activeChanges[ancestor])
				then
					return nil
				end
				ancestor = ancestor.Parent
			end
			return rawNames[position]
		end

		local function included(node, rootSet)
			local ancestor = node
			while ancestor do
				if ancestor.Del then
					return false
				end
				if rootSet[ancestor] then
					return ancestor ~= node
				end
				ancestor = ancestor.Parent
			end
			return false
		end

		local function updateNode(node, rootSet)
			local position = positionsByNode[node]
			if position then
				removeName(names[position], position)
			end
			local ok, name = false, nil
			if included(node, rootSet) then
				ok, name = pcall(readName, node)
				index.Stats.NameReads += 1
			end
			if ok and type(name) == "string" then
				if not position then
					position = #nodes + 1
					nodes[position], positionsByNode[node] = node, position
				end
				names[position] = string.lower(name)
				rawNames[position] = name
				addName(names[position], position)
				for term in pairs(queryCache) do
					updateQuery(term, position, string.find(names[position], term, 1, true) ~= nil)
				end
			elseif position then
				local last = #nodes
				local replacement = nodes[last]
				if last ~= position then
					removeName(names[last], last)
					addName(names[last], position)
				end
				for term, items in pairs(queryCache) do
					updateQuery(term, position, false)
					local map = queryPositions[term]
					local at = map and map[last]
					if at and last ~= position then
						items[at] = position
						map[position] = at
						map[last] = nil
					end
				end
				nodes[position], names[position] = replacement, names[last]
				rawNames[position] = rawNames[last]
				positionsByNode[replacement] = position
				nodes[last], names[last], positionsByNode[node] = nil, nil, nil
				rawNames[last] = nil
			end
			index.Stats.Updates += 1
		end

		local function applyChanges(roots, checkpoint)
			if next(pending) == nil then
				return true
			end
			previousTerm, previousMatches = nil, nil
			for i = #queryOrder, 1, -1 do
				local term = queryOrder[i]
				if not queryPositions[term] then
					dropQuery(term)
				end
			end
			local changes = pending
			activeChanges = changes
			pending = {}
			local rootSet = {}
			for _, root in ipairs(roots) do
				rootSet[root] = true
			end
			local work = 0
			local considered = 0
			local function requeue()
				for node, descendants in pairs(changes) do
					pending[node] = pending[node] or descendants
				end
				activeChanges = nil
			end
			for changed, subtree in pairs(changes) do
				considered += 1
				if checkpoint and considered % 256 == 0 and not checkpoint() then
					requeue()
					return false
				end
				local ancestor = changed.Parent
				local covered = false
				while ancestor do
					if changes[ancestor] then
						covered = true
						break
					end
					ancestor = ancestor.Parent
				end
				if covered then
					continue
				end
				local stack = { changed }
				while #stack > 0 do
					local node = table.remove(stack)
					updateNode(node, rootSet)
					if subtree then
						for _, child in ipairs(node) do
							stack[#stack + 1] = child
						end
					end
					work += 1
					if checkpoint and work % 256 == 0 and not checkpoint() then
						requeue()
						return false
					end
				end
			end
			activeChanges = nil
			return true
		end

		function index.Scan(roots, term, nextRevision, results, matches, expanded, checkpoint, incremental, terms)
			local builtMatches
			if not sameRoots(indexedRoots, roots) or (revision ~= nextRevision and not incremental) then
				local complete
				complete, builtMatches = build(roots, nextRevision, checkpoint, term)
				if not complete then
					return false
				end
				table.clear(pending)
			elseif not applyChanges(roots, checkpoint) then
				return false
			end
			revision = nextRevision
			local candidates = previousTerm and term:sub(1, #previousTerm) == previousTerm and previousMatches or nil
			local exact = builtMatches ~= nil or queryCache[term] ~= nil
			if builtMatches then
				candidates = builtMatches
			elseif exact then
				candidates = queryCache[term]
			else
				local length = candidates and #previousTerm or -1
				for cached, items in pairs(queryCache) do
					if #cached > length and term:sub(1, #cached) == cached then
						length = #cached
						candidates = items
					end
				end
			end
			local grouped = false
			if not exact and (not candidates or #candidates > groupCount) then
				candidates = {}
				local checked = 0
				for name, bucket in pairs(groups) do
					if string.find(name, term, 1, true) then
						if type(bucket) == "number" then
							candidates[#candidates + 1] = bucket
						else
							for position in pairs(bucket) do
								candidates[#candidates + 1] = position
								checked += 1
								if checkpoint and checked % 256 == 0 and not checkpoint() then
									return false
								end
							end
						end
					end
					checked += 1
					if checkpoint and checked % 256 == 0 and not checkpoint() then
						return false
					end
				end
				exact = true
				grouped = true
			end
			local count = if candidates then #candidates else #nodes
			local nextMatches = exact and candidates or {}
			local nameMatches = if exact then nil else {}
			local secondaryMatches = if terms and #terms > 1 then {} else nil
			local memoCount = 0
			index.Stats.Candidates = builtMatches and #nodes or count

			for position = 1, count do
				local item = if candidates then candidates[position] else position
				local name = names[item]
				local matched = if nameMatches then nameMatches[name] else true
				if nameMatches and matched == nil then
					matched = string.find(name, term, 1, true) ~= nil
					if memoCount < 32768 then
						nameMatches[name] = matched
						memoCount += 1
					end
				end
				if matched then
					local node = nodes[item]
					if not exact then
						nextMatches[#nextMatches + 1] = item
					end
					if secondaryMatches then
						local allTerms = secondaryMatches[name]
						if allTerms == nil then
							allTerms = true
							for i = 2, #terms do
								if not string.find(name, terms[i], 1, true) then
									allTerms = false
									break
								end
							end
							if memoCount < 32768 then
								secondaryMatches[name] = allTerms
								memoCount += 1
							end
						end
						if not allTerms then
							if checkpoint and position % 256 == 0 and not checkpoint() then
								return false
							end
							continue
						end
					end

					if expanded[node] == nil then
						expanded[node] = 0
					end
					results[node], matches[node] = true, true
					local ancestor = node.Parent
					while ancestor and (not results[ancestor] or expanded[ancestor] == 0) do
						expanded[ancestor], results[ancestor] = true, true
						ancestor = ancestor.Parent
					end
				end
				if checkpoint and position % 256 == 0 and not checkpoint() then
					return false
				end
			end
			previousTerm, previousMatches = term, nextMatches
			if not exact or builtMatches or grouped then
				cacheQuery(term, nextMatches)
			end
			return true
		end

		function index.Clear()
			revision, indexedRoots, previousTerm, previousMatches = nil, nil, nil, nil
			table.clear(groups)
			groupCount = 0
			table.clear(nodes)
			table.clear(names)
			table.clear(rawNames)
			table.clear(positionsByNode)
			table.clear(pending)
			clearQueries()
		end

		return index
	end

	return SearchNameIndex
end

return { Main = Main }
