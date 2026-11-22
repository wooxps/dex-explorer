--!strict

local Apps = {}
for _, pair in ipairs({
	{ "SearchBits", require("../src/Apps/Explorer/Services/SearchBits") },
	{ "SearchPostings", require("../src/Apps/Explorer/Services/SearchPostings") },
	{ "SearchSnapshot", require("../src/Apps/Explorer/Services/SearchSnapshot") },
	{ "SearchResults", require("../src/Apps/Explorer/Services/SearchResults") },
	{ "SearchTreeResults", require("../src/Apps/Explorer/Services/SearchTreeResults") },
	{ "ExplorerSearch", require("../src/Apps/Explorer/Services/ExplorerSearch") },
}) do
	pair[2].InitDeps({ Apps = Apps })
	Apps[pair[1]] = pair[2].Main()
end
local Bits = Apps.SearchBits
for _, size in ipairs({ 0, 1, 31, 32, 33, 63, 64, 65, 1001 }) do
	local dense, sparse = Bits.Dense(size), Bits.Sparse()
	local values = {}
	for i = 1, size do
		if i % 3 ~= 0 then
			dense:Set(i)
			sparse:Set(i)
			values[#values + 1] = i
		end
	end
	dense:Prepare()
	assert(dense.Count == #values and sparse.Count == #values)
	for i, value in ipairs(values) do
		assert(dense:Select(i) == value and dense:Rank(value) == i and sparse:Has(value))
	end
	assert(dense:Select(0) == nil and dense:Select(#values + 1) == nil)
	local clone = dense:Clone()
	clone:ClearRange(20, 74)
	clone:Prepare()
	local count = 0
	for i = 1, size do
		local expected = i % 3 ~= 0 and not (i >= 20 and i <= 74)
		assert(clone:Has(i) == expected)
		if expected then
			count += 1
			assert(clone:Rank(i) == count)
		end
	end
	assert(clone.Count == count and dense.Count == #values and dense:Rank(0) == 0)
end
do
	local bitmap = Bits.Dense(137)
	for i = 1, 137 do bitmap:Set(i) end
	for i = 137, 1, -1 do assert(bitmap:Select(i) == i and bitmap:Rank(i) == i) end
	bitmap:ClearRange(30, 65)
	bitmap:Set(128, false)
	local ids = {}
	for i = 1, 137 do if bitmap:Has(i) then ids[#ids + 1] = i end end
	for i = #ids, 1, -1 do
		assert(bitmap:Select(i) == ids[i] and bitmap:Select(#ids + 1 - i) == ids[#ids + 1 - i])
	end
	bitmap:Set(64)
	assert(bitmap:Select(30) == 64 and bitmap:Rank(64) == 30)
end
local posts = Apps.SearchPostings.Create()
for _, name in ipairs({
	"Car",
	"Cart",
	"Race Car",
	"Vehicle",
	"a",
	"ab",
	"ABC",
	"",
	string.rep("x", 130) .. "car",
	"日本語car",
}) do
	posts:Intern(name)
end
for _, term in ipairs({ "a", "ab", "car", "cart", "vehicle", "cle", "xx", "日本", "不存在", "" }) do
	local actual = posts:Lookup(term)
	for id, name in ipairs(posts.Names) do
		assert(actual:Has(id) == (name:find(term, 1, true) ~= nil), "substring postings missed a match")
	end
end
local before = posts.Stats.Comparisons
posts:Lookup("car")
assert(posts.Stats.Comparisons == before, "exact/backspace cache rescans")
local new = posts:Intern("Cargo")
assert(posts:Lookup("car"):Has(new), "new names do not update broad caches")
local shared = posts:Intern("Car Blue")
posts:AddMember(shared, 1)
posts:AddMember(shared, 33)
posts:AddMember(shared, 65)
posts:AddMember(new, 66)
local declined = posts:NodeCandidates({ "car" }, nil, 2)
assert(not declined and not posts.NodeCache.car, "cutoff must not cache partial instance postings")
assert(posts:ExceedsLimit("ca", 2) and not posts:ExceedsLimit("cart", 2))
local both = posts:NodeCandidates({ "car", "blue" }, nil, 3)
assert(both and both.Count == 3 and both:Has(65) and not both:Has(66))
posts:RemoveMember(shared, 65)
assert(not posts:ExceedsLimit("ca", 2), "removed instances invalidate a cached lower bound")
local checked = posts:NodeCandidates({ "car" }, nil, 3)
assert(checked and checked.Count == 3 and checked:Has(66) and not checked:Has(65))
local disjoint = posts:NodeCandidates({ "blue", "cargo" })
assert(disjoint and disjoint.Count == 0)
local root = { Obj = { Name = "game", ClassName = "DataModel" } }
local serial = 0
local function add(parent, name)
	serial += 1
	local node = { Obj = { Name = name, ClassName = "Folder" }, Parent = parent, Key = serial }
	parent[#parent + 1] = node
	return node
end
do
	local testRoot = {}
	local parent = add(testRoot, "NeedleParent")
	local child = add(parent, "NeedleChild")
	local context = {
		Name = function(node) return node.Obj.Name end,
		Children = function(node) return node end,
		Visible = function() return true end,
		Roots = function() return { testRoot } end,
		Sorting = function() return false end,
		Scope = function() return 1 end,
		Alive = function() return true end,
		Wait = function() end,
		Read = function(node) return node.Obj.Name, "Folder", 0, node.Key end,
	}
	local engine = Apps.ExplorerSearch.Create(context)
	local views = {
		Apps.SearchResults.CreateCold({ testRoot }, { "needle" }, context, function() end),
		engine:Search(nil, { "needle" }, function() return true end),
	}
	parent[1] = nil
	for _, view in views do
		assert(view:HasChildren(parent) and not view:HasChildren(child), "arrows use the displayed snapshot during live hierarchy changes")
		view.Expanded[parent] = false
		view:Reflow(function() end)
		assert(view:HasChildren(parent) and not view:IndexOf(child), "collapsed snapshots retain their expand arrows")
		view.Expanded[parent] = true
		view:Reflow(function() end)
		assert(view:IndexOf(child), "snapshot descendants can expand while live children are changing")
		view:Remove(child)
		view:Reflow(function() end)
		assert(not view:HasChildren(parent) and not view:IndexOf(child), "removing the final search child removes the arrow")
	end
	parent[1] = child
	print("PASS: snapshot-stable arrows, collapse/expand and last-child removal")
end
do
	local testRoot = {}
	local visible = add(testRoot, "Visible")
	local hidden = add(testRoot, "Hidden")
	add(visible, "Piece")
	for _ = 1, 100 do
		add(hidden, "Piece")
	end
	local shown, hiddenReads = false, 0
	local context = {
		Name = function(node)
			if node.Parent == hidden then
				hiddenReads += 1
			end
			return node.Obj.Name
		end,
		Children = function(node)
			return node
		end,
		Visible = function(node)
			return node ~= hidden or shown
		end,
		VisibleOnly = true,
	}
	local function checkpoint() end
	local roots = { testRoot }
	local firstLayout = Apps.SearchResults.CreateLayout(roots, context, checkpoint)
	assert(#firstLayout.Nodes == 2 and hiddenReads == 0, "filtered searches and character preparation skip hidden service trees")
	local first = Apps.SearchResults.CreateCold(roots, { "piece" }, context, checkpoint)
	assert(#first.MatchList == 1 and #first.ColdLayout.Nodes == 2 and hiddenReads == 0)
	shown = true
	assert(not Apps.SearchResults.MatchesVisibility(firstLayout, context.Visible), "showing a service invalidates the pruned layout")
	local nextLayout = Apps.SearchResults.CreateLayout(roots, context, checkpoint)
	assert(#nextLayout.Nodes == 103 and hiddenReads == 100, "showing services restores their full searchable hierarchy")
	hiddenReads = 0
	assert(not Apps.SearchResults.MatchesVisibility(first.ColdLayout, context.Visible))
	local second = Apps.SearchResults.CreateCold(roots, { "piece" }, context, checkpoint, first.ColdLayout)
	assert(#second.MatchList == 101 and hiddenReads == 100, "showing services must restore every hidden match")
	shown = false
	local third = Apps.SearchResults.CreateCold(roots, { "piece" }, context, checkpoint, second.ColdLayout)
	assert(#third.MatchList == 1 and #first.MatchList == 1 and #second.MatchList == 101)
end
do
	for _, size in ipairs({ 1, 31, 32, 33, 63, 64, 65, 257 }) do
		local testRoot = {}
		local group = add(testRoot, "Container")
		for index = 1, size do
			add(group, index % 3 == 0 and "Repeated É日本 Car Blue" or "Repeated Tree")
		end
		local context = {
			Name = function(node)
				return node.Obj.Name
			end,
			Children = function(node)
				return node
			end,
			Visible = function()
				return true
			end,
		}
		local function checkpoint() end
		local roots = { testRoot }
		local layout = Apps.SearchResults.CreateLayout(roots, context, checkpoint)
		local positions = table.clone(layout.Positions)
		local retained
		for _, terms in ipairs({ { "e" }, { "car", "blue" }, { "日本" }, { "absent" } }) do
			local recursive = Apps.SearchResults.CreateCold(roots, terms, context, checkpoint)
			local packed = Apps.SearchResults.CreateCold(roots, terms, context, checkpoint, layout)
			assert(#recursive.Rows == #packed.Rows and #recursive.MatchList == #packed.MatchList)
			for index = 1, #packed.Rows do
				assert(packed.Rows[index] == recursive.Rows[index] and packed:IndexOf(packed.Rows[index]) == index)
			end
			for index = 1, #packed.MatchList do
				assert(packed.MatchList[index] == recursive.MatchList[index])
			end
			retained = retained or { View = packed, Count = #packed.MatchList }
			assert(#retained.View.MatchList == retained.Count, "later queries mutated an earlier result")
		end
		for node, position in pairs(positions) do
			assert(layout.Positions[node] == position, "query mutated shared hierarchy positions")
		end
	end
end
do
	local testRoot = {}
	local group = add(testRoot, "Group")
	local recurring = add(group, "Part1")
	add(group, "Part2")
	local context = {
		Name = function(node)
			return node.Obj.Name
		end,
		Children = function(node)
			return node
		end,
		Visible = function()
			return true
		end,
	}
	local function checkpoint() end
	local first = Apps.SearchResults.CreateCold({ testRoot }, { "part" }, context, checkpoint)
	first:MeasureWidths(function(entry)
		return if entry.Node == recurring then 90 else 10, entry.Node ~= recurring
	end, checkpoint)
	local nextView = Apps.SearchResults.CreateCold({ testRoot }, { "part1" }, context, checkpoint, first.ColdLayout)
	local calls = 0
	local maximum = nextView:MeasureWidths(function(entry)
		calls += 1
		assert(entry.Node == recurring, "exact widths must be reused by later queries with the same layout")
		return 30
	end, checkpoint)
	assert(maximum == 30 and calls == 1, "estimated widths must be retried instead of retained across queries")
end
do
	local testRoot = {}
	local group = add(testRoot, "Container")
	local hidden = add(testRoot, "Hidden")
	local nested = add(group, "Branch")
	local nilRoot = { Obj = { Name = "Nil Instances" } }
	local roots = { testRoot, nilRoot }
	local keep = add(nested, "QqQ")
	local removable = add(nested, "q")
	local nilMatch = add(nilRoot, "q")
	add(hidden, "Hidden q")
	add(hidden, "Not a match for the explicit fixture")

	local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	for index = 1, #alphabet do
		local name = string.sub(alphabet, index, index)
		add(group, name:upper())
		add(nested, "é" .. name .. name)
	end
	add(nested, "日本語")
	add(nested, "")
	add(nested, "punctuation !")

	local nameReads, childReads = 0, 0
	local hideService = true
	local context = {
		Name = function(node)
			nameReads += 1
			return node.Obj.Name
		end,
		Children = function(node)
			childReads += 1
			return node
		end,
		Visible = function(node)
			return node ~= hidden or not hideService
		end,
	}
	local function checkpoint() end
	local layout = Apps.SearchResults.CreateLayout(roots, context, checkpoint)
	assert(not Apps.SearchResults.CreateIndexed(layout, "q", context, checkpoint), "unprepared layout must use the exact fallback")
	Apps.SearchResults.PrepareCharacters(layout, checkpoint)
	for _, term in ipairs({ "", "qq", "é", "日本", "!" }) do
		assert(not Apps.SearchResults.CreateIndexed(layout, term, context, checkpoint), "unsupported terms must use the exact fallback")
	end

	local function compare(a, b)
		assert(#a.MatchList == #b.MatchList and #a.Rows == #b.Rows, "indexed match or context count differs")
		for index = 1, #a.MatchList do
			local node = a.MatchList[index]
			assert(
				b.MatchList[index] == node and b:PositionOfMatch(node) == index and b.Matches[node],
				"indexed match order or reverse lookup differs"
			)
		end
		for index = 1, #a.Rows do
			local node = a.Rows[index]
			assert(
				b.Rows[index] == node and b:IndexOf(node) == index and b:DepthOf(node) == a:DepthOf(node)
					and b:NameOf(node) == a:NameOf(node),
				"indexed row order, name or depth differs"
			)
		end
		for _, node in ipairs(layout.Nodes) do
			assert(
				a:Contains(node) == b:Contains(node) and a.Expanded[node] == b.Expanded[node],
				"indexed ancestor context or expansion differs"
			)
		end
		local old, new = a:MaterializeMatches(), b:MaterializeMatches()
		assert(#old == #new)
		for index, node in ipairs(old) do
			assert(new[index] == node, "indexed bulk-match enumeration reordered results")
		end
	end

	for index = 1, #alphabet do
		local term = string.sub(alphabet, index, index)
		local baseline = Apps.SearchResults.CreateCold(roots, { term }, context, checkpoint)
		local names, children = nameReads, childReads
		local indexed = assert(Apps.SearchResults.CreateIndexed(layout, term, context, checkpoint))
		compare(baseline, indexed)
		assert(nameReads == names and childReads == children, "indexed queries reread hierarchy names or children")
	end

	local baseline = Apps.SearchResults.CreateCold(roots, { "q" }, context, checkpoint)
	local indexed = assert(Apps.SearchResults.CreateIndexed(layout, "Q", context, checkpoint))
	compare(baseline, indexed)
	assert(indexed.Matches[keep] and indexed.Matches[nilMatch] and not indexed.Matches[nilRoot])
	hideService = false
	baseline:Reflow(checkpoint)
	indexed:Reflow(checkpoint)
	compare(baseline, indexed)
	baseline.Expanded[group], indexed.Expanded[group] = false, false
	baseline:Remove(removable)
	indexed:Remove(removable)
	baseline:Reflow(checkpoint)
	indexed:Reflow(checkpoint)
	compare(baseline, indexed)
	assert(indexed.Matches[keep] and not indexed.Matches[removable] and not indexed:IndexOf(keep))
	local fresh = assert(Apps.SearchResults.CreateIndexed(layout, "q", context, checkpoint))
	assert(fresh.Matches[removable] and fresh:IndexOf(keep), "one result mutates the shared index or another result")
end
local service = add(root, "Workspace")
do
	local tree, context = {}, {
		Name = function(node) return node.Obj.Name end,
		Children = function(node) return node end,
		Visible = function() return true end,
	}
	local outer = add(tree, "Container")
	local nested = add(outer, "Branch")
	for i = 1, 2048 do add(nested, "Part" .. i) end
	nested[129].Obj.Name = "Upper_NEEDLE_日本"
	nested[130].Obj.Name = "Tail"
	nested[131].Obj.Name = "Head"
	nested[132].Obj.Name = ""
	nested[133].Obj.Name = "\0Head"
	nested[134].Obj.Name = "DoubleNeedleNeedle"
	nested[2048].Obj.Name = "keep\0byte"
	local function check() end
	local roots = { tree }
	local first = Apps.SearchResults.CreateCold(roots, { "absent" }, context, check)
	local layout = first.ColdLayout
	local broad = Apps.SearchResults.CreateCold(roots, { "part" }, context, check, layout)
	for i, node in ipairs(layout.Nodes) do
		assert(layout.Positions[node] == i, "a broad name search must fill every missing position")
	end
	assert(not broad:Contains(nested[129]) and not broad:NameOf(nested[129]) and not broad:DepthOf(nested[129]))
	local broadCount = #broad.MatchList
	broad.Expanded[nested] = false
	broad:Remove(nested[5])
	broad:Reflow(check)
	nested[17].NameWidth = 1901
	local revisit = Apps.SearchResults.CreateCold(roots, { "part" }, context, check, layout)
	assert(#revisit.MatchList == broadCount and revisit:IndexOf(nested[5]) and revisit.Width == 1901)
	assert(#broad.MatchList == broadCount - 1 and not broad:IndexOf(nested[5]))
	local version, passes = 1, 0
	context.WidthRevision = function() return version end
	local entry = layout.LiteralResults[#layout.LiteralResults]
	local each = entry.Context.Each
	entry.Context.Each = function(...)
		passes += 1
		return each(...)
	end
	assert(Apps.SearchResults.CreateCold(roots, { "part" }, context, check, layout).Width == 1901)
	assert(Apps.SearchResults.CreateCold(roots, { "part" }, context, check, layout).Width == 1901)
	assert(passes == 1, "reopening the same name search should reuse its width")
	nested[17].NameWidth = 70
	version += 1
	local narrower = Apps.SearchResults.CreateCold(roots, { "part" }, context, check, layout)
	assert(passes == 2 and narrower.Width < 1901 and #narrower.MatchList == broadCount)
	entry.Context.Each = nil
	local absent = Apps.SearchResults.CreateCold(roots, { "absent", "needle" }, context, check, layout)
	assert(#absent.Rows == 0 and absent.Depth == 1 and absent.Width == 0)
	for _, terms in {{ "日本", "needle" }, { "tail\0head" }, { "keep\0byte" }, { "\0head" }, { "\0" }, { "needle" }, { "part" }} do
		local actual = Apps.SearchResults.CreateCold(roots, terms, context, check, layout)
		local full = Apps.SearchResults.CreateCold(roots, terms, context, check)
		assert(#actual.Rows == #full.Rows and #actual.MatchList == #full.MatchList)
		for i = 1, #full.Rows do assert(actual.Rows[i] == full.Rows[i]) end
		for i = 1, #full.MatchList do assert(actual.MatchList[i] == full.MatchList[i]) end
	end
	local filtered = Apps.SearchResults.CreatePredicate(layout, function(obj)
		return obj.Name == "\0Head" or obj.Name == "keep\0byte"
	end, context, check, roots)
	assert(#filtered.MatchList == 2 and filtered.MatchList[1] == nested[133] and filtered.MatchList[2] == nested[2048])
	assert(#filtered.Rows == 4 and filtered.Rows[1] == outer and filtered.Rows[2] == nested)
	filtered.Expanded[nested] = false
	filtered:Reflow(check)
	assert(#filtered.Rows == 2 and #filtered.MatchList == 2)
	Apps.SearchResults.CreateCold(roots, { "needle" }, context, check, layout)
	local nameReads = 0
	local function enabledNeedle(obj)
		nameReads += 1
		return obj.Enabled and string.find(string.lower(obj.Name), "upper_needle", 1, true)
	end
	nested[129].Obj.Enabled = true
	local named = Apps.SearchResults.CreatePredicate(layout, enabledNeedle, context, check, roots, nil, nil, false, "upper_needle")
	assert(nameReads == 2 and #named.MatchList == 1 and named.MatchList[1] == nested[129])
	nested[129].Obj.Enabled = false
	assert(#Apps.SearchResults.CreatePredicate(layout, enabledNeedle, context, check, roots, nil, nil, false, "upper_needle").MatchList == 0)
	local regular, inferred = nested[130], nested[140]
	regular.Obj.ClassName, regular.Obj.Enabled = "Part", true
	inferred.Inferred = true
	local function isPart(node) return node.Obj.ClassName == "Part" end
	local calls = 0
	local function enabledPart(obj)
		calls += 1
		return obj.ClassName == "Part" and obj.Enabled
	end
	local only = Apps.SearchResults.CreatePredicate(layout, enabledPart, context, check, roots, isPart, "Part", true)
	assert(#only.MatchList == 1 and only.MatchList[1] == regular and calls == 2)
	regular.Obj.Enabled = false
	inferred.Obj.ClassName, inferred.Obj.Enabled = "Part", true
	calls = 0
	local changed = Apps.SearchResults.CreatePredicate(layout, enabledPart, context, check, roots, isPart, "Part", true)
	assert(#changed.MatchList == 1 and changed.MatchList[1] == inferred and calls == 2)
	local function isFolder(node) return node.Obj.ClassName == "Folder" end
	local function folders(obj) return obj.ClassName == "Folder" end
	local dense = Apps.SearchResults.CreatePredicate(layout, folders, context, check, roots, isFolder, "Folder")
	assert(#dense.MatchList == #layout.Nodes - 2 and not layout.FilterRows)
	local denseLive = Apps.SearchResults.CreatePredicate(layout, function(obj)
		return folders(obj) and obj.Name == "Upper_NEEDLE_日本"
	end, context, check, roots, isFolder, "Folder", true)
	assert(#denseLive.MatchList == 1 and denseLive.MatchList[1] == nested[129])
	Apps.SearchResults.PrepareCharacters(layout, check)
	for _, terms in { { "pa" }, { "art" }, { "a", "t" }, { "p", "2" } } do
		local indexed = Apps.SearchResults.CreateCold(roots, terms, context, check, layout)
		local fresh = Apps.SearchResults.CreateCold(roots, terms, context, check)
		assert(#indexed.MatchList == #fresh.MatchList and #indexed.Rows == #fresh.Rows)
		assert(indexed.Width == fresh.Width and indexed.Depth == fresh.Depth)
		for i = 1, #fresh.Rows do assert(indexed.Rows[i] == fresh.Rows[i]) end
		for i = 1, #fresh.MatchList do assert(indexed.MatchList[i] == fresh.MatchList[i]) end
	end
	local evaluated = 0
	local function sparseCondition(obj)
		evaluated += 1
		return string.find(obj.Name, "keep", 1, true) and obj.Enabled
	end
	for _, value in { true, false } do
		nested[2048].Obj.Enabled = value
		local filtered = Apps.SearchResults.CreatePredicate(layout, sparseCondition, context, check, roots, nil, nil, true, "keep")
		assert(#filtered.MatchList == (if value then 1 else 0))
	end
	assert(evaluated < #layout.Nodes)
	local rare = Apps.SearchResults.CreateCold(roots, { "upper_", "日本" }, context, check, layout)
	assert(#rare.Rows == 3 and rare.MatchList[1] == nested[129] and #rare.MatchList == 1)
	assert(#Apps.SearchResults.CreateCold(roots, { "xylophone" }, context, check, layout).MatchList == 0)
	assert(#Apps.SearchResults.CreateCold(roots, { "upper_zz", "日本" }, context, check, layout).Rows == 0)
	local single = assert(Apps.SearchResults.CreateIndexed(layout, "u", context, check))
	assert(single:IndexOf(nested[129]) and single:HasChildren(outer) and not single:IndexOf(nested[130]))
	assert(not first:Contains(nested[129]), "promoting a cold layout changed the original view")
end
local a = add(service, "Alpha")
local b = add(service, "Beta")
for i = 1, 70000 do
	add(i % 2 == 0 and a or b, "Part" .. i)
end
local checks = 0
local context = {
	Roots = function()
		return { root }
	end,
	Sorting = function()
		return true
	end,
	Scope = function()
		return 1
	end,
	Alive = function()
		return true
	end,
	Wait = function()
		checks += 1
	end,
	Visible = function()
		return true
	end,
	Read = function(node)
		return node.Obj.Name, node.Obj.ClassName, 0, node.Key or 0
	end,
}
local engine = Apps.ExplorerSearch.Create(context)
local coldStarted = os.clock()
local view = assert(engine:Search(nil, { "part" }, function()
	return true
end))
local coldSeconds = os.clock() - coldStarted
local warmStarted = os.clock()
view = assert(engine:Search(nil, { "part" }, function()
	return true
end))
print(
	string.format(
		"70000 matches: cold CPU %.1f ms, repeated CPU %.1f ms; compact bytes %d",
		coldSeconds * 1000,
		(os.clock() - warmStarted) * 1000,
		buffer.len(view.MatchBits.Data)
	)
)
assert(
	#view.MatchList == 70000 and #view.Rows == 70003 and rawget(view.Rows, 1) == nil,
	"broad results must not allocate 70000 row objects"
)
assert(view.Resolved == 0)
local first, last = view.Rows[1], view.Rows[#view.Rows]
assert(
	first == service and view:IndexOf(last) == #view.Rows and view.Resolved <= 64,
	"rank/select or lazy page resolution is incorrect"
)
local full = {}
for i = 1, #view.Rows do
	local node = view.Rows[i]
	assert(view:IndexOf(node) == i)
	full[#full + 1] = node
end
assert(#view.PageOrder <= 4, "scrolling leaks virtual pages")
view.Expanded[a] = false
view:Reflow(function() end)
assert(#view.Rows == 35003 and #view.MatchList == 70000, "collapse must not lose bulk-selection matches")
view.Expanded[a] = true
view:Reflow(function() end)
assert(#view.Rows == #full)
local queries = engine.Stats.Queries
local declined, broad = engine:Search(nil, { "par" }, function()
	return true
end, false, 8192)
assert(not declined and broad and engine.Stats.Queries == queries and engine.LastResult == view)
local bounded = assert(engine:Search(nil, { "part69999" }, function()
	return true
end, false, 8192))
assert(#bounded.MatchList == 1, "a narrow match must not fall back after a broad query")
local beforeBuilds = engine.Snapshots.Stats.Builds
local beforeReads = engine.Snapshots.Stats.NativeReads
local selective = assert(engine:Search(nil, { "part69999" }, function()
	return true
end))
assert(
	#selective.MatchList == 1 and engine.Snapshots.Stats.NativeReads == beforeReads,
	"typing rereads all object names"
)
local chosen = selective.MatchList[1]
chosen.Obj.Name = "RenamedCar"
engine:Mark(chosen, false)
local changed = assert(engine:Search(nil, { "renamedcar" }, function()
	return true
end))
assert(#changed.MatchList == 1 and changed.MatchList[1] == chosen)
assert(
	engine.Snapshots.Stats.Builds == beforeBuilds and engine.Snapshots.Stats.NativeReads - beforeReads < 5,
	"one rename rebuilds the name index"
)
assert(
	#selective.MatchList == 1 and selective.MatchList[1] == chosen,
	"old snapshot results change after a new snapshot is published"
)
local oldParent = chosen.Parent
table.remove(oldParent, table.find(oldParent, chosen))
chosen.Parent = oldParent == a and b or a
chosen.Parent[#chosen.Parent + 1] = chosen
engine:Mark(chosen, true)
local moved = assert(engine:Search(nil, { "renamedcar" }, function()
	return true
end))
assert(#moved.MatchList == 1 and moved:IndexOf(chosen))
chosen.Del = true
table.remove(chosen.Parent, table.find(chosen.Parent, chosen))
engine:Mark(chosen, true)
local removed = assert(engine:Search(nil, { "renamedcar" }, function()
	return true
end))
assert(#removed.MatchList == 0)
-- Property predicates remain fully supported through the snapshot evaluator.
local general = assert(engine:Search(
	function(obj)
		return obj.Name == "Part7"
	end,
	nil,
	function()
		return true
	end
))
assert(#general.MatchList == 1)
-- Pending mutations do not cancel a query; only a newer request or teardown does.
local alive = true
local calls = 0
local cancelled = engine:Search(nil, { "part" }, function()
	calls += 1
	return calls < 2
end)
assert(cancelled == nil and not engine.Busy, "cancelled query retains the engine lock")
assert(
	engine:Search(nil, { "part7" }, function()
		return true
	end),
	"cancelled engine cannot resume"
)
-- Cached broad terms survive unrelated updates; memberships are expanded from
-- the new state rather than retaining stale object positions in the cache.
local stable = assert(engine:Search(nil, { "part" }, function()
	return true
end))
local measured = 0
local function measure(entry)
	measured += 1
	return #entry.Name * 7
end
stable:MeasureWidths(measure, function() end)
measured = 0
stable:MeasureWidths(measure, function() end)
assert(measured == 0, "unchanged immutable result branches repeat native text measurements")
local dictionary = engine.Snapshots.State.Postings
local comparisons = dictionary.Stats.Comparisons
local extra = add(service, "CompletelyUnrelated")
engine:Mark(extra, true)
local again = assert(engine:Search(nil, { "part" }, function()
	return true
end))
assert(
	#again.MatchList == #stable.MatchList and dictionary.Stats.Comparisons == comparisons,
	"unrelated insertion invalidates broad caches"
)
assert(again.Seed.Rebuilt < 10, "one insertion rebuilds every cached result branch")
again:MeasureWidths(measure, function() end)
assert(measured < 10, "an unrelated insertion remeasures every matching row")
assert(engine.Snapshots.Stats.OrderBuilds == 0, "search deltas renumber the entire hierarchy")
-- Visibility and collapse are independent, and showing a service restores the
-- complete result set without another object scan.
local shown = true
context.Visible = function()
	return shown
end
local hidden = assert(engine:Search(nil, { "part7" }, function()
	return true
end))
local count = #hidden.MatchList
shown = false
hidden:Reflow(function() end)
assert(#hidden.Rows == 0 and #hidden.MatchList == 0)
shown = true
hidden:Reflow(function() end)
assert(#hidden.MatchList == count)
local revision = hidden.WidthRevision
hidden:Reflow(function()
	error("unchanged view rebuilds its rank tables")
end)
assert(hidden.WidthRevision == revision, "unchanged view is not retained")
-- Deleting an old parent must not delete a child that moved out of it in the
-- same coalesced batch, regardless of event delivery order.
local moving = add(a, "MovedOutBeforeDelete")
engine:Mark(moving, true)
engine:Search(nil, { "movedout" }, function()
	return true
end)
table.remove(a, table.find(a, moving))
moving.Parent = b
b[#b + 1] = moving
a.Del = true
engine:Mark(a, true)
engine:Mark(moving, true)
local survived = assert(engine:Search(nil, { "movedout" }, function()
	return true
end))
assert(
	#survived.MatchList == 1 and survived.MatchList[1] == moving,
	"coalesced parent deletion loses moved-out children"
)
-- A changed session root starts a new index rather than reusing stale nodes.
root = {}
local nextNode = add(root, "FreshSession")
local fresh = assert(engine:Search(nil, { "freshsession" }, function()
	return true
end))
assert(#fresh.MatchList == 1 and fresh.MatchList[1] == nextNode and #fresh.Rows == 1)
local rootChild = nextNode
for round = 1, 100 do
	rootChild.Del = true
	table.remove(root, table.find(root, rootChild))
	engine:Mark(rootChild, true)
	rootChild = add(root, "Transient" .. round)
	engine:Mark(rootChild, true)
	local query = assert(engine:Search(nil, { "transient" }, function()
		return true
	end))
	assert(#query.MatchList == 1 and query.MatchList[1] == rootChild)
end
assert(engine.Snapshots.State.MaxId < 10, "spawn/despawn churn grows the stable-ID universe forever")
assert(fresh.MatchList[1] == nextNode and not fresh:IndexOf(rootChild), "reusing a deleted ID corrupts old snapshots")
-- Compare mixed, coalesced structural/name edits against an independent walk.
root = {}
serial = 0
local groups = {}
for i = 1, 6 do
	groups[i] = add(root, "Group" .. i)
end
local objects = {}
for i = 1, 240 do
	objects[i] = add(groups[i % 6 + 1], i % 3 == 0 and "Hit" .. i or "Other" .. i)
end
-- Deterministic integer stream, independent of Roblox's Random implementation.
local randomState = 739
local function pick(max)
	randomState = (randomState * 48271) % 2147483647
	return randomState % max + 1
end
local function oracle(term)
	local rows, matches = {}, {}
	local function visit(node)
		local children = table.clone(node)
		table.sort(children, function(x, y)
			if x.Obj.Name ~= y.Obj.Name then
				return x.Obj.Name < y.Obj.Name
			end
			return x.Key < y.Key
		end)
		local below = {}
		local hits = {}
		for _, child in ipairs(children) do
			if not child.Del then
				local r, m = visit(child)
				for _, v in ipairs(r) do
					below[#below + 1] = v
				end
				for _, v in ipairs(m) do
					hits[#hits + 1] = v
				end
			end
		end
		local hit = node ~= root and node.Obj.Name:lower():find(term, 1, true) ~= nil
		if node ~= root and (hit or #below > 0) then
			table.insert(below, 1, node)
		end
		if hit then
			table.insert(hits, 1, node)
		end
		return below, hits
	end
	return visit(root)
end
for round = 1, 100 do
	for _ = 1, 3 do
		local node = objects[pick(#objects)]
		if round % 3 == 0 then
			node.Obj.Name = (pick(2) == 1 and "Hit" or "Other") .. pick(1000)
			engine:Mark(node, false)
		else
			table.remove(node.Parent, table.find(node.Parent, node))
			node.Parent = groups[pick(#groups)]
			node.Parent[#node.Parent + 1] = node
			engine:Mark(node, true, "move")
		end
	end
	local term = round % 2 == 0 and "hit" or "other"
	local actual = assert(engine:Search(nil, { term }, function()
		return true
	end))
	local rows, matches = oracle(term)
	assert(
		#actual.Rows == #rows and #actual.MatchList == #matches,
		"incremental cached result count differs from independent walk"
	)
	for i, node in ipairs(rows) do
		assert(
			actual.Rows[i] == node and actual:IndexOf(node) == i,
			"incremental cached row ordering differs from independent walk"
		)
	end
	for i, node in ipairs(matches) do
		assert(
			actual.MatchList[i] == node and actual:PositionOfMatch(node) == i,
			"incremental cached match ordering differs from independent walk"
		)
	end
end
-- Warm-up stores compact columns, and class metadata is read only for the
-- included paths. Deferred entries still retain the original snapshot values.
root = {}
local untouched = add(root, "Needle")
untouched.ManualOrder = 7
for i = 1, 1000 do
	add(root, "Unrelated" .. i)
end
local metadataReads = 0
local deferredContext = table.clone(context)
deferredContext.Read = function(node)
	return node.Obj and node.Obj.Name or "", nil, nil, node.Key or 0
end
deferredContext.Metadata = function(entry)
	metadataReads += 1
	entry.Class, entry.Order = "Folder", 0
end
local deferred = Apps.ExplorerSearch.Create(deferredContext)
deferred:Warm()
local frozen = deferred.Snapshots.State
local id = frozen.Ids[untouched]
assert(rawget(frozen.Entries, id) == nil and metadataReads == 0, "warm-up eagerly builds every metadata record")
untouched.Obj.Name = "ChangedLater"
untouched.ManualOrder = 99
assert(
	frozen.Entries[id].Name == "Needle" and frozen.Entries[id].Manual == 7,
	"lazy metadata observes later name/manual-order edits"
)
local one = deferred:Search(nil, { "needle" }, function()
	return true
end)
assert(#one.MatchList == 1 and metadataReads <= 2, "selective search reads class metadata for unrelated objects")
deferred:Mark(untouched, false)
assert(#deferred:Search(nil, { "changedlater" }, function()
	return true
end).MatchList == 1)
print(
	"PASS: bitset boundaries/rank/select, substring/short/Unicode/overflow coverage, live broad-cache updates, 70000 virtual matches, bounded scrolling, snapshot isolation, delta rename/move/delete, predicate fallback and cancellation"
)
