--!strict

-- Indexed text results must match the general predicate scanner exactly.
do
	local index = Apps.SearchNameIndex.Create()
	local root = {}
	for i = 1, 160 do
		local parent = { Obj = { Name = "NeedleParent" .. i }, Parent = root }
		parent[1] = { Obj = { Name = "NeedleChild" .. i }, Parent = parent }
		root[i] = parent
	end
	assert(index.Scan({ root }, "absent", 1, {}, {}, {}, nil, true))
	for _, query in { "needle", "needlep", "needle" } do
		local results, matches, expanded = {}, {}, {}
		assert(index.Scan({ root }, query, 1, results, matches, expanded, nil, true))
		for _, parent in root do
			assert(matches[parent], "matching parents stay in the result set")
			if query == "needle" then
				assert(expanded[parent] == true and matches[parent[1]], "child-first matches must retain the parent's expand arrow")
			else
				assert(expanded[parent] == 0, "filtered leaves do not get an empty expand arrow")
			end
		end
	end
	print("PASS: grouped and cached search preserves parent arrows regardless of match order")
end

do
	local root, secondRoot = {}, {}
	local parent = { Obj = { Name = "Nested" }, Parent = root }
	root[1] = parent
	for i = 1, 1300 do
		parent[i] = { Obj = { Name = "Part" .. i }, Parent = parent }
	end
	secondRoot[1] = { Obj = { Name = "OtherPart" }, Parent = secondRoot }
	local roots = { root, secondRoot }
	local revision = 1
	local function check(query)
		local predicate = assert(Apps.SearchQuery.Compile(query))
		local expectedResults, expectedMatches, expectedExpanded = {}, {}, {}
		local results, matches, expanded = {}, {}, {}
		assert(Apps.SearchQuery.Scan(roots, predicate, expectedResults, expectedMatches, expectedExpanded))
		assert(Apps.SearchQuery.Scan(roots, predicate, results, matches, expanded, nil, { Revision = revision }))
		for node, value in pairs(expectedResults) do
			assert(results[node] == value)
		end
		for node, value in pairs(results) do
			assert(expectedResults[node] == value)
		end
		for node, value in pairs(expectedMatches) do
			assert(matches[node] == value)
		end
		for node, value in pairs(matches) do
			assert(expectedMatches[node] == value)
		end
		for node, value in pairs(expectedExpanded) do
			assert(expanded[node] == value)
		end
		return matches
	end
	local first = assert(Apps.SearchQuery.Compile("name:PART12"))
	local opts = { Revision = revision, Incremental = true, Provisional = true }
	assert(not Apps.SearchQuery.Scan(roots, first, {}, {}, {}, function() return false end, opts))
	local provisional, directMatches, open = {}, {}, {}
	assert(Apps.SearchQuery.Scan(roots, first, provisional, directMatches, open, nil, opts))
	assert(Apps.SearchQuery.LastScanStats.Mode == "Literal" and open[parent] == true)
	local expected = check("name:PART12")
	for node in directMatches do assert(expected[node]) end
	for node in expected do assert(directMatches[node]) end
	check("part")
	check('"Part123"')
	assert(Apps.SearchQuery.LastScanStats.Mode == "NameIndex", "quoted literal searches use the index")
	check("name:Part123")
	assert(Apps.SearchQuery.LastScanStats.Mode == "NameIndex", "name-filter searches use the index")
	local builds = Apps.SearchQuery.NameIndex.Stats.Builds
	check("part1")
	assert(Apps.SearchQuery.NameIndex.Stats.Builds == builds, "typing reuses normalized names")
	check("part123")
	assert(Apps.SearchQuery.NameIndex.Stats.Candidates < 1300, "prefix refinement scans prior matches only")
	check("part") -- Backspace must widen again.
	for _, query in ipairs({
		"part 12",
		"part and 12",
		'"Part" "12"',
		"part 1",
		"part 99999",
		"part",
		"part or nested",
		"Nested.Part1",
	}) do
		check(query)
	end
	check("part and 12")
	assert(Apps.SearchQuery.LastScanStats.Mode == "NameIndex", "name conjunctions reuse normalized names")
	parent[2].Obj.Name = "Renamed"
	revision += 1
	assert(check("renamed")[parent[2]], "rename invalidates normalized names")
	local removed = table.remove(parent, 3)
	revision += 1
	assert(not check("part")[removed], "removal invalidates membership")
	local moved = table.remove(parent, 4)
	moved.Parent = secondRoot
	secondRoot[2] = moved
	revision += 1
	assert(check("part")[moved], "reparented match keeps current ancestry")
	local predicate = assert(Apps.SearchQuery.Compile("part"))
	revision += 1
	local checkpoints = 0
	assert(not Apps.SearchQuery.Scan(roots, predicate, {}, {}, {}, function()
		checkpoints += 1
		return false
	end, { Revision = revision }), "cancelled index construction never publishes its cache")
	assert(checkpoints == 1)
	check("part")
	Apps.SearchQuery.NameIndex.Clear()
	print(
		"PASS: indexed/predicate equivalence, prefix narrowing, backspace, rename, removal, reparenting and cancellation"
	)
end

do
	local index = Apps.SearchNameIndex.Create()
	local root = {}
	for i = 1, 4000 do
		root[i] = { Obj = { Name = "Part" .. i }, Parent = root }
	end
	local revision = 1
	local function scan(term, checkpoint)
		local matches = {}
		local ok = index.Scan({ root }, term, revision, {}, matches, {}, checkpoint, true)
		return ok, matches
	end
	assert(scan("part123"))
	assert(scan("part234"))
	local ok, matches = scan("part123")
	local count = 0
	for _ in pairs(matches) do
		count += 1
	end
	assert(ok and count == 11 and index.Stats.Candidates == 11, "revisited queries reuse complete matching indices")
	root[123].Obj.Name = "Renamed"
	index.MarkDirty(root[123], false)
	revision += 1
	ok, matches = scan("part123")
	count = 0
	for _ in pairs(matches) do
		count += 1
	end
	assert(ok and count == 10 and not matches[root[123]], "renames update retained query membership")
	assert(index.Stats.Candidates == 10, "a rename no longer discards a selective cached query")
	root[1].Obj.Name = "Unrelated"
	index.MarkDirty(root[1], false)
	revision += 1
	assert(scan("part123") and index.Stats.Candidates == 10, "unrelated live mutations preserve selective candidates")
	assert(scan("part"))
	assert(scan("part234"))
	assert(not scan("part", function()
		return false
	end), "cached scans retain cancellation checkpoints")
	ok, matches = scan("part")
	count = 0
	for _ in pairs(matches) do
		count += 1
	end
	assert(ok and count == 3998, "a cancelled cached scan cannot corrupt retained matches")
	for i = 1, 20 do
		assert(scan("part" .. i))
	end
	assert(scan("part123"), "query eviction never prevents recomputation")
end

do
	local index = Apps.SearchNameIndex.Create()
	local root = {}
	local parent = { Obj = { Name = "Original" }, Parent = root }
	local child = { Obj = { Name = "OriginalChild" }, Parent = parent }
	root[1], parent[1] = parent, child
	local revision = 1
	local function scan(term, checkpoint)
		local matches = {}
		local complete = index.Scan({ root }, term, revision, {}, matches, {}, checkpoint, true)
		return complete, matches
	end
	assert(scan("orig"))
	assert(index.CachedName(child) == "OriginalChild", "cached raw names must preserve capitalization")
	local reads = index.Stats.NameReads
	child.Obj.Name = "NewChild"
	index.MarkDirty(child, false)
	revision += 1
	assert(index.CachedName(child) == nil, "dirty names are exposed as fresh cached values")
	local complete, matches = scan("new")
	assert(complete and matches[child] and index.Stats.Builds == 1)
	assert(index.CachedName(child) == "NewChild", "patched names are not shared with the accelerator")
	assert(index.Stats.NameReads == reads + 1, "rename reads only the changed name")
	index.MarkDirty(parent, true)
	assert(index.CachedName(child) == nil, "subtree refresh exposes stale child names")
	assert(scan("new"))
	local added = { Obj = { Name = "NewLeaf" }, Parent = root }
	root[2] = added
	index.MarkDirty(added, true)
	revision += 1
	complete, matches = scan("new")
	assert(matches[added] and matches[child] and index.Stats.Builds == 1, "insertion patches the index")
	table.remove(root, 1)
	parent.Del = true
	index.MarkDirty(parent, true)
	revision += 1
	complete, matches = scan("new")
	assert(matches[added] and not matches[child], "subtree deletion removes cached descendants")
	table.remove(root, 1)
	added.Parent = {}
	index.MarkDirty(added, true)
	revision += 1
	complete, matches = scan("new")
	assert(next(matches) == nil, "moving outside indexed roots removes membership")
	revision += 1
	assert(scan("new") and index.Stats.Builds == 1, "ordering-only revisions do not rebuild names")

	local large = { Obj = { Name = "Folder" }, Parent = root }
	root[1] = large
	for i = 1, 900 do
		large[i] = { Obj = { Name = "Needle" .. i }, Parent = large }
	end
	index.MarkDirty(large, true)
	revision += 1
	assert(not scan("needle", function()
		return false
	end), "incremental updates honor cancellation")
	complete, matches = scan("needle")
	local count = 0
	for _ in pairs(matches) do
		count += 1
	end
	assert(
		complete and count == 900 and index.Stats.Builds == 1,
		"cancelled deltas replay without duplicates or full rebuilds"
	)
	local priorReads = index.Stats.NameReads
	for _, node in ipairs(large) do
		node.Obj.Name = "Changed" .. node.Obj.Name
		index.MarkDirty(node, false)
	end
	index.MarkDirty(large, true)
	revision += 1
	complete, matches = scan("changed")
	count = 0
	for _ in pairs(matches) do
		count += 1
	end
	assert(
		complete and count == 900 and index.Stats.NameReads - priorReads == 901,
		"overlapping parent/child deltas read every changed name exactly once"
	)
	local nested = { Obj = { Name = "NestedDelta" }, Parent = large[1] }
	large[1][1] = nested
	local last = { Obj = { Name = "ChangedGrandchild" }, Parent = nested }
	nested[1] = last
	index.MarkDirty(large[1], false)
	index.MarkDirty(nested, true)
	revision += 1
	complete, matches = scan("changed")
	assert(complete and matches[last], "shallow parent deltas cannot swallow deeper subtree updates")
	print(
		"PASS: incremental name updates, subtree insertion/removal, root membership, sort reuse and cancelled-delta replay"
	)
end
