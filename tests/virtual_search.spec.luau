--!strict

do
	Explorer.ClearSearch()
	local host = Instance.new("Folder", workspace)
	host.Name = "VirtualSearchScope"
	local items = {}
	for i = 1, 80 do
		local child = Instance.new("Folder", host)
		child.Name = "VirtualHit" .. i
		items[i] = child
	end
	Explorer.SyncHistoryObject(host)
	assert(
		Explorer.DoSearch("VirtualSearchScope.**") and #Explorer.MatchList == 80,
		"ancestry query was incorrectly treated as a name literal"
	)
	assert(Explorer.SearchView and rawget(Explorer.SearchView.Rows, 1) == nil)
	Explorer.SelectMatches(false)
	assert(#Explorer.Selection.List == 80, "bulk select silently loses virtual results")
	Explorer.SelectMatches(true)
	assert(#Explorer.Selection.List == 0, "bulk toggle cannot clear virtual selection")
	Explorer.StepMatch(1, false)
	local selected = Explorer.Selection.List[1]
	assert(selected and Explorer.Matches[selected], "forward stepping cannot select virtual matches")
	Explorer.StepMatch(-1, false)
	assert(Explorer.Selection.List[1] ~= selected, "reverse stepping cannot select virtual matches")
	local view = Explorer.SearchView
	local a, b = view.MatchList[3], view.MatchList[8]
	local range = Apps.ExplorerPolicy.Range(view.Rows, a, b, view.Matches)
	assert(#range == 6, "Shift range loses virtual rows")
	local page = Apps.ExplorerPolicy.PageStep(view.Rows, { a }, 5, view.Matches, view.Indices)
	assert(page and view:IndexOf(page) > view:IndexOf(a), "PageDown does not resolve virtual row indices")
	local last = Apps.ExplorerPolicy.Endpoint(view.Rows, true, view.Matches)
	assert(last == view.MatchList[#view.MatchList], "End does not resolve last result")
	local index = view:IndexOf(view.MatchList[80])
	Explorer.Index = math.max(0, index - 2)
	Explorer.Refresh()
	assert(view.Resolved < 160 and #view.PageOrder <= 4, "scrolling materializes the entire search tree")
	local reads = Explorer.SearchEngine.Snapshots.Stats.NativeReads
	assert(Explorer.DoSearch("VirtualHit7") and #Explorer.MatchList == 11)
	assert(Explorer.DoSearch("VirtualHit") and #Explorer.MatchList == 80)
	assert(Explorer.SearchEngine.Snapshots.Stats.NativeReads == reads, "typing/backspacing rereads unchanged objects")
	local hostNode = nodes[host]
	Explorer.SetExpanded(hostNode, false)
	Explorer.Update()
	local hovered, within = Explorer.ResolveHoveredNode(items[1])
	assert(hovered == hostNode and within, "hover on a collapsed hit must highlight its visible nonmatching ancestor")
	local searchBox = Explorer.GuiElems.SearchBar
	searchBox.Text = "VirtualHit"
	local previous = Explorer.SearchView
	searchBox.FocusLost:Fire(false)
	assert(Explorer.SearchView == previous, "clicking out of search reruns the displayed query")
	items[1].Name = "VirtualHitRenamed"
	game.ItemChanged:Fire(items[1], "Name")
	flushTasks()
	assert(
		Explorer.SearchView ~= previous and Explorer.SearchExpanded[hostNode] == false and #Explorer.MatchList == 80,
		"live refresh must retain the collapsed branch and all matching objects"
	)
	local search = Explorer.DoSearch
	local requested = {}
	Explorer.DoSearch = function(query)
		requested[#requested + 1] = query
		return search(query)
	end
	items[1].Name = "VirtualHitChangedAgain"
	game.ItemChanged:Fire(items[1], "Name")
	searchBox.Text = "VirtualHit7"
	searchBox:GetPropertyChangedSignal("Text"):Fire()
	Explorer.ForceUpdate()
	assert(#requested == 0 and Explorer.Query == "VirtualHit", "a tree update runs the old query during debounce")
	flushTasks()
	assert(#requested == 1 and requested[1] == "VirtualHit7", "replacement executes the obsolete query")
	assert(Explorer.Query == "VirtualHit7" and #Explorer.MatchList == 11)
	Explorer.DoSearch = search
	searchBox.Text = "VirtualHit"
	assert(Explorer.DoSearch("VirtualHit") and #Explorer.MatchList == 80)
	local destination = Instance.new("Folder", host)
	destination.Name = "Nonmatching destination"
	Explorer.SyncHistoryObject(destination)
	local snapshot = Explorer.SearchView
	items[1].Parent = destination
	Explorer.SyncHistoryObject(items[1])
	assert(not snapshot.Matches[nodes[destination]], "moving a match must not modify the published match map")
	flushTasks()
	assert(
		not Explorer.Matches[nodes[destination]] and #Explorer.MatchList == 80,
		"move refresh keeps ancestors separate from matches"
	)
	Explorer.ClearSearch()
	local size = Explorer.InitialObjectCount
	local fallbacks = Explorer.SearchFallbacks or 0
	Explorer.InitialObjectCount = 9000
	Explorer.SearchEngine.Snapshots.State = nil
	assert(Explorer.DoSearch("VirtualHit") and #Explorer.MatchList == 80, "cold bitmap loses results")
	local cold = Explorer.SearchView
	assert(cold and cold.Cold and not Explorer.SearchEngine:Ready())
	assert((Explorer.SearchFallbacks or 0) == fallbacks, "cold query materializes a temporary result")
	Explorer.SearchExpanded[hostNode] = false
	Explorer.Update()
	assert(#cold.MatchList == 80 and not cold:IndexOf(nodes[items[2]]), "cold collapse changes the match set")
	flushTasks()
	assert(Explorer.SearchView == cold, "cold results are rebuilt without a change")
	assert(Explorer.DoSearch("VirtualHit7") and #Explorer.MatchList == 11, "querying the cold layout loses matches")
	assert(Explorer.SearchView.ColdLayout == cold.ColdLayout, "replacement rereads cold hierarchy metadata")
	assert(Explorer.DoSearch("VirtualHit") and #Explorer.MatchList == 80)
	Explorer.SearchExpanded[hostNode] = false
	local during = Instance.new("Folder", host)
	during.Name = "VirtualHitDuringPreparation"
	Explorer.SyncHistoryObject(during)
	flushTasks()
	assert(Explorer.SearchView and #Explorer.MatchList == 81, "cold results miss a live insertion")
	assert(Explorer.SearchExpanded[hostNode] == false, "live refresh expands a user-collapsed branch")
	Explorer.ClearSearch()
	local medium = Instance.new("Folder", host)
	medium.Name = "Medium sibling sort"
	local mediumRows = {}
	for i = 1, 64 do
		local object = Instance.new("Part", medium)
		object.Name = "MediumSort" .. (i % 7)
		mediumRows[i] = object
	end
	Explorer.SyncHistoryObject(medium)
	local ordered = {}
	for i, object in ipairs(mediumRows) do
		local node = nodes[object]
		node.Id = 65 - i
		ordered[i] = node
	end
	local function checkMediumOrder()
		table.sort(ordered, Explorer.NodeSorter)
		Explorer.SearchEngine.Snapshots.State = nil
		assert(Explorer.DoSearch("MediumSort") and #Explorer.MatchList == #ordered)
		for i, node in ipairs(ordered) do
			assert(Explorer.MatchList[i] == node, "medium sibling sort changed tie or manual order")
		end
		Explorer.ClearSearch()
	end
	checkMediumOrder()
	Explorer.SetHistoryOrder(mediumRows[32], -1)
	checkMediumOrder()
	for i, object in ipairs(mediumRows) do nodes[object].Id = i end
	Explorer.SetHistoryOrder(mediumRows[32], nil)
	checkMediumOrder()
	local expected = {}
	for i = 1200, 1, -1 do
		local object = Instance.new("Folder", host)
		object.Name = string.format("SortProbe%04d", i)
		expected[i] = object
		Explorer.SyncHistoryObject(object)
	end
	Explorer.SearchEngine.Snapshots.State = nil
	assert(Explorer.DoSearch("SortProbe") and #Explorer.MatchList == #expected)
	assert(Explorer.SearchView and Explorer.SearchView.Cold, "large sibling sorting did not exercise the cold bitmap")
	for index, object in ipairs(expected) do
		assert(Explorer.MatchList[index].Obj == object, "broad sibling sorting changed search order")
	end
	flushTasks()
	assert(Explorer.SearchView and #Explorer.MatchList == #expected)
	for index, object in ipairs(expected) do
		assert(Explorer.MatchList[index].Obj == object, "prepared results changed fallback order")
	end
	Explorer.ClearSearch()
	local classes = { "MeshPart", "Folder", "Part" }
	local mixed = {}
	for i = 1, 1800 do
		local object = Instance.new(classes[i % 3 + 1], host)
		object.Name = i % 2 == 0 and "MixedSortCommon" or "MixedSort" .. (i % 17)
		Explorer.SyncHistoryObject(object)
		local node = nodes[object]
		node.Id = 1801 - i
		mixed[i] = node
	end
	table.sort(mixed, Explorer.NodeSorter)
	Explorer.SearchEngine.Snapshots.State = nil
	assert(Explorer.DoSearch("MixedSort") and #Explorer.MatchList == #mixed and Explorer.SearchView.Cold)
	for i, node in ipairs(mixed) do
		assert(Explorer.MatchList[i] == node, "cold search reordered mixed classes or duplicate names")
	end
	Explorer.InitialObjectCount = size
	Explorer.ClearSearch()
	Explorer.Selection:Clear()
	host.Parent = nil
	Explorer.SyncHistoryObject(host)
	host:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	flushTasks()
	assert(
		not Explorer.SearchView and Explorer.VisibleProjection.Valid,
		"clearing search does not restore incremental normal rows"
	)
	print(
		"PASS: production virtual ancestry, all-match select/toggle, stepping, Shift range, PageDown/End, scroll-to-last, retained pages, prefix/backspace reuse and normal hierarchy restoration"
	)
end

do
	Explorer.ClearSearch()
	local host = Instance.new("Folder", workspace)
	host.Name = "BroadRefreshScope"
	Explorer.SyncHistoryObject(host)
	local branches = {}
	for i = 1, 100 do
		local branch = Instance.new("Folder", host)
		branch.Name = string.format("Branch%03d", i)
		branches[i] = branch
		Explorer.SyncHistoryObject(branch)
	end
	local items = {}
	for i = 1, 8300 do
		local branch = branches[math.ceil(i / 83)]
		local child = Instance.new("Folder", branch)
		child.Name = string.format("WideRefresh%04d", i)
		items[i] = child
		Explorer.SyncHistoryObject(child)
	end

	local query = "WideRefresh"
	Explorer.GuiElems.SearchBar.Text = query
	local engine = Explorer.SearchEngine
	engine:Warm()
	assert(engine:Ready(), "test must exercise an already indexed tree")
	assert(Explorer.DoSearch(query))
	for _ = 1, 4 do
		flushTasks()
	end
	local original = assert(Explorer.SearchView)
	assert(#original.MatchList == #items, "wide search lost matches")

	local branch = nodes[branches[1]]
	local selected = nodes[items[2]]
	Explorer.Selection:Set(selected)
	Explorer.SetExpanded(branch, false)
	Explorer.Update()
	assert(not original:IndexOf(selected), "test branch must be collapsed")
	local fallbacks = Explorer.SearchFallbacks or 0

	items[1].Name = "WideRefreshRenamed"
	game.ItemChanged:Fire(items[1], "Name")
	for _ = 1, 4 do
		flushTasks()
	end
	local updated = assert(Explorer.SearchView)
	assert(updated ~= original and (Explorer.SearchFallbacks or 0) == fallbacks, "wide live refresh used the fallback")
	assert(rawget(updated.Rows, 1) == nil and updated.Resolved < 100, "live refresh materialized the visible tree")
	assert(
		#updated.MatchList == #items and updated.MatchList[83] == nodes[items[1]],
		"wide refresh lost sorted matches"
	)
	assert(
		Explorer.SearchExpanded[branch] == false and not updated:IndexOf(selected),
		"live refresh expanded the branch"
	)
	assert(Explorer.Selection.List[1] == selected and #Explorer.Selection.List == 1, "live refresh changed selection")

	items[1].Name = "Unrelated"
	game.ItemChanged:Fire(items[1], "Name")
	Explorer.ForceUpdate()
	for _ = 1, 4 do
		flushTasks()
	end
	assert(
		#Explorer.MatchList == #items - 1 and not Explorer.Matches[nodes[items[1]]],
		"an explicit refresh did not remove a renamed match"
	)
	assert((Explorer.SearchFallbacks or 0) == fallbacks and Explorer.SearchExpanded[branch] == false)
	assert(Explorer.Selection.List[1] == selected)

	Explorer.ClearSearch()
	Explorer.Selection:Clear()
	host.Parent = nil
	Explorer.SyncHistoryObject(host)
	host:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	flushTasks()
	print("PASS: indexed wide live refresh preserves virtual rows, order, collapsed ancestors and current selection")
end

do
	Explorer.ClearSearch()
	local previousActive, previousSize, previousWait = Explorer.Active, Explorer.InitialObjectCount, task.wait
	Explorer.Active, Explorer.InitialObjectCount = true, 9000
	task.wait = function()
		return 0
	end

	local indexedCalls = 0
	local createIndexed = Apps.SearchResults.CreateIndexed
	Apps.SearchResults.CreateIndexed = function(...)
		local view = createIndexed(...)
		if view then
			indexedCalls += 1
		end
		return view
	end

	local host = Instance.new("Folder", workspace)
	host.Name = "BitmapScope"
	local source = Instance.new("Folder", host)
	source.Name = "Source"
	local destination = Instance.new("Folder", host)
	destination.Name = "Destination"
	local match = Instance.new("Folder", source)
	match.Name = "Query"
	local replacement = Instance.new("Folder", source)
	replacement.Name = "Moth"
	Explorer.SyncHistoryObject(host)

	assert(Explorer.DoSearch("q") and Explorer.Matches[nodes[match]], "first search before preparation must remain exact")
	assert(indexedCalls == 0, "incomplete index must not be published")
	Explorer.ClearSearch()
	for _ = 1, 6 do
		flushTasks()
	end
	assert(Explorer.DoSearch("q") and Explorer.Matches[nodes[match]] and indexedCalls == 1, "a ready index must serve a new character query")
	assert(Explorer.SearchView:IndexOf(nodes[source]) and not Explorer.Matches[nodes[source]])
	Explorer.SetExpanded(nodes[source], false)
	Explorer.Update()
	assert(Explorer.Matches[nodes[match]] and not Explorer.SearchView:IndexOf(nodes[match]), "indexed collapse hides rows but keeps matches")

	match.Name = "Renamed"
	game.ItemChanged:Fire(match, "Name")
	replacement.Name = "Query2"
	game.ItemChanged:Fire(replacement, "Name")
	replacement.Parent = destination
	Explorer.SyncHistoryObject(replacement)
	assert(Explorer.DoSearch("q"), "a hierarchy change must keep character search usable")
	assert(indexedCalls == 1, "a changed tree must not use stale character bitmaps")
	assert(
		not Explorer.Matches[nodes[match]]
			and Explorer.Matches[nodes[replacement]]
			and Explorer.SearchView:IndexOf(nodes[destination])
			and not Explorer.SearchView:IndexOf(nodes[source]),
		"rename and reparent invalidate the match and ancestor columns"
	)
	Explorer.ClearSearch()
	for _ = 1, 6 do
		flushTasks()
	end
	assert(Explorer.DoSearch("q") and Explorer.Matches[nodes[replacement]] and indexedCalls == 2, "background preparation must index the changed hierarchy")

	Explorer.ClearSearch()
	Apps.SearchResults.CreateIndexed = createIndexed
	Explorer.Active, Explorer.InitialObjectCount, task.wait = previousActive, previousSize, previousWait
	host.Parent = nil
	Explorer.SyncHistoryObject(host)
	host:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	flushTasks()
	print("PASS: exact character search index readiness, fallback, collapse, rename and reparent integration")
end

do
	Explorer.ClearSearch()
	local previousSize, previousWait = Explorer.InitialObjectCount, task.wait
	Explorer.InitialObjectCount = 9000
	task.wait = function()
		return 0
	end
	local engine = Explorer.SearchEngine
	engine.Snapshots.State = nil
	local basePart = API.Classes.BasePart
	API.Classes.BasePart = { Name = "BasePart", Properties = {} }
	local host = Instance.new("Folder", workspace)
	host.Name = "PackedSearchScope"
	local first = Instance.new("Part", host)
	first.Name, first.Anchored = "First", true
	local second = Instance.new("Part", host)
	second.Name, second.Anchored = "Second", false
	local unrelated = Instance.new("Folder", host)
	unrelated.Name = "Other"
	Explorer.SyncHistoryObject(host)
	local scope = "PackedSearchScope.** AND Anchored=true"
	local fallbacks = Explorer.SearchFallbacks or 0
	assert(Explorer.DoSearch(scope))
	local initial = Explorer.SearchView
	assert(initial and initial.PackedPredicate and not engine:Ready() and (Explorer.SearchFallbacks or 0) == fallbacks)
	assert(#Explorer.MatchList == 1 and Explorer.MatchList[1] == nodes[first] and initial:IndexOf(nodes[host]))
	Explorer.SetExpanded(nodes[host], false)
	Explorer.Update()
	assert(Explorer.Matches[nodes[first]] and not initial:IndexOf(nodes[first]))
	first.Anchored, second.Anchored = false, true
	assert(Explorer.DoSearch(scope))
	assert(Explorer.SearchView.ColdLayout == initial.ColdLayout and Explorer.SearchView ~= initial)
	assert(#Explorer.MatchList == 1 and Explorer.MatchList[1] == nodes[second] and not Explorer.Matches[nodes[first]])
	assert(Explorer.SearchExpanded[nodes[host]] == false and not Explorer.SearchView:IndexOf(nodes[second]))
	assert(Apps.SearchQuery.ClassFilter(assert(Apps.SearchQuery.Compile("(is:basepart)"))) == "BasePart")
	assert(not Apps.SearchQuery.ClassFilter(assert(Apps.SearchQuery.Compile("is:BasePart OR is:Folder"))))
	assert(Explorer.DoSearch("is:BasePart"))
	local classView = Explorer.SearchView
	assert(classView.ColdLayout.ClassResults.BasePart and classView.ColdLayout == initial.ColdLayout)
	assert(Explorer.Matches[nodes[first]] and Explorer.Matches[nodes[second]] and not Explorer.Matches[nodes[unrelated]])
	local function requiredClass(query)
		local term = Apps.SearchQuery.RequiredClassTerm(assert(Apps.SearchQuery.Compile(query)))
		return term and Apps.SearchQuery.ClassFilter(term)
	end
	assert(requiredClass("(is:BasePart AND Anchored=true) name:Second") == "BasePart")
	assert(not requiredClass("(is:BasePart OR is:Folder) name:Other"))
	assert(not requiredClass("(is:BasePart AND name:First) OR is:Folder"))
	assert(Explorer.DoSearch("is:BasePart AND (Anchored=true OR name:First)"))
	assert(Explorer.Matches[nodes[first]] and Explorer.Matches[nodes[second]] and not Explorer.Matches[nodes[unrelated]])
	assert(Explorer.DoSearch("name:Other AND (is:BasePart OR is:Folder)") and Explorer.Matches[nodes[unrelated]])
	local classReads = 0
	local probe = { Name = "Other", IsA = function()
		classReads += 1
		return true
	end }
	local namedPart = assert(Apps.SearchQuery.Compile("is:BasePart AND name:First"))
	assert(not namedPart(probe) and classReads == 0)
	probe.Name = "FIRST"
	assert(namedPart(probe) and classReads == 1, "mandatory names read the current value")
	local unreadable = setmetatable({ IsA = probe.IsA }, { __index = function() error("unreadable name") end })
	assert(assert(Apps.SearchQuery.Compile("name:First OR is:BasePart"))(unreadable))
	assert(Explorer.DoSearch("is:BasePart OR is:Folder") and Explorer.Matches[nodes[unrelated]])
	host.Parent = nil
	Explorer.SyncHistoryObject(host)
	assert(Explorer.DoSearch("is:BasePart") and not Explorer.Matches[nodes[first]] and not Explorer.Matches[nodes[second]])
	Explorer.ClearSearch()
	Explorer.InitialObjectCount, task.wait = previousSize, previousWait
	API.Classes.BasePart = basePart
	host:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	flushTasks()
	print("PASS: packed cold property/class search, live values, class cache, OR, collapse and subtree removal")
end

do
	Explorer.ClearSearch()
	local previousSize, previousWait = Explorer.InitialObjectCount, task.wait
	Explorer.InitialObjectCount = 38000
	task.wait = function()
		return 0
	end
	local host = Instance.new("Folder", workspace)
	host.Name = "BroadColdScope"
	local children = {}
	for index = 1, 1200 do
		local part = Instance.new("Part", host)
		part.Name = "RepeatedPiece" .. index % 8
		children[index] = part
	end
	Explorer.SyncHistoryObject(host)
	local engine = Explorer.SearchEngine
	local originalSearch = engine.Search
	engine.Search = function()
		error("broad cold search rebuilt the general index")
	end
	assert(Explorer.DoSearch("repeatedpiece") and #Explorer.MatchList == 1200)
	local layout = Explorer.SearchView.ColdLayout
	assert(layout and Explorer.SearchView.Resolved < 100, "wide matches remain virtual")
	local previous
	for index = 1, #Explorer.MatchList do
		local node = Explorer.MatchList[index]
		assert(not previous or not Explorer.NodeSorter(node, previous), "duplicate names preserve the Explorer comparator")
		previous = node
	end
	assert(Explorer.DoSearch("piece0") and #Explorer.MatchList == 150)
	assert(Explorer.SearchView.ColdLayout == layout, "all literal queries reuse a valid layout")
	children[1].Name = "UpdatedPiece0"
	game.ItemChanged:Fire(children[1], "Name")
	assert(Explorer.DoSearch("piece0") and #Explorer.MatchList == 151)
	assert(Explorer.Matches[nodes[children[1]]], "renames invalidate cached sibling order and names")
	local nestedMatch = Instance.new("Part", children[2])
	nestedMatch.Name = "RepeatedPieceNested"
	Explorer.SyncHistoryObject(nestedMatch)
	local nestedNode = nodes[nestedMatch]
	Explorer.ClearSearch()
	local createCold = Apps.SearchResults.CreateCold
	local scans, removed = 0, false
	Apps.SearchResults.CreateCold = function(roots, terms, context, checkpoint, previousLayout)
		scans += 1
		local name = context.Name
		local first = true
		context.Name = function(node)
			if first then
				first = false
				local deadline = os.clock() + 0.008
				repeat until os.clock() >= deadline
			end
			return name(node)
		end
		return createCold(roots, terms, context, checkpoint, previousLayout)
	end
	local deletedNode = nodes[children[2]]
	task.wait = function()
		if not removed then
			removed = true
			children[2].Parent = nil
			Explorer.SyncHistoryObject(children[2])
		end
		return 0
	end
	assert(Explorer.DoSearch("repeatedpiece") and removed and scans == 1, "a deletion restarted the foreground scan")
	assert(#Explorer.MatchList == 1198 and not Explorer.Matches[deletedNode], "deleted matches survived publication")
	assert(not Explorer.Matches[nestedNode], "a descendant of a deleted subtree survived publication")
	Apps.SearchResults.CreateCold = createCold
	engine.Search = originalSearch
	Explorer.ClearSearch()
	host.Parent = nil
	Explorer.SyncHistoryObject(host)
	host:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.InitialObjectCount, task.wait = previousSize, previousWait
	Explorer.ForceUpdate()
	flushTasks()
	print("PASS: stale broad cold searches skip index rebuilding, retain duplicate order, reuse layouts and invalidate renamed siblings")
end

do
	Explorer.ClearSearch()
	local previousSize, previousWait = Explorer.InitialObjectCount, task.wait
	Explorer.InitialObjectCount = 38000
	local host = Instance.new("Folder", workspace)
	host.Name = "FallbackNeedleParent"
	local children = {}
	for index = 1, 100 do
		local child = Instance.new("Folder", host)
		child.Name = string.format("FallbackNeedle%03d", index)
		children[index] = child
	end
	local outside = Instance.new("Folder", workspace)
	outside.Name = "OutsideMarker"
	Explorer.SyncHistoryObject(host)
	Explorer.SyncHistoryObject(outside)
	local original = Apps.SearchResults.CreateCold
	local scans, changed = 0, false
	Apps.SearchResults.CreateCold = function(roots, terms, context, checkpoint, layout)
		scans += 1
		local name, first = context.Name, true
		context.Name = function(node)
			if first then
				first = false
				local deadline = os.clock() + .008
				repeat until os.clock() >= deadline
			end
			return name(node)
		end
		return original(roots, terms, context, checkpoint, layout)
	end
	task.wait = function()
		if not changed then
			changed = true
			children[1].Name = "FallbackNeedleRenamed"
			game.ItemChanged:Fire(children[1], "Name")
		end
		return 0
	end
	assert(Explorer.DoSearch("fallbackneedle") and changed and scans == 1, "a changing game does not repeat the failed cold scan")
	assert(#Explorer.MatchList == 101, "fallback retains every matching object")
	assert(Explorer.HasChildren(nodes[host]), "fallback parent arrows remain available")
	Explorer.SetExpanded(nodes[host], false)
	Explorer.Update()
	assert(not Explorer.IsNodeVisible(nodes[children[2]]) and #Explorer.MatchList == 101, "fallback collapse preserves all matches")
	assert(Explorer.DoSearch("fallbackneedle00") and #Explorer.MatchList == 8 and scans == 1, "the next query skips another doomed scan without losing matches")
	assert(Explorer.DoSearch("outsidemarker") and Explorer.Matches[nodes[outside]], "query replacement keeps complete game coverage")
	assert(Explorer.DoSearch("no such marker anywhere") and #Explorer.MatchList == 0, "empty fallback is valid")
	Apps.SearchResults.CreateCold = original
	task.wait = previousWait
	Explorer.InitialObjectCount = previousSize
	Explorer.ClearSearch()
	host.Parent, outside.Parent = nil, nil
	Explorer.SyncHistoryObject(host)
	Explorer.SyncHistoryObject(outside)
	host:Destroy()
	outside:Destroy()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	flushTasks()
	print("PASS: changing-game fallback skips repeated work, keeps full results, arrows, collapse and cross-query coverage")
end
