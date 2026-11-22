--!strict

local Factory = require("../src/Apps/Explorer/Services/ExplorerProjection").Main()
local root = {}
local service = { Parent = root, NameWidth = 5 }
root[1] = service
local expanded = { [service] = true }
local rows, indices = {}, {}
local p = Factory.Create(rows, indices)
local function oracle()
	local result = {}
	local function visit(parent)
		for _, node in ipairs(parent) do
			if not node.Del then
				result[#result + 1] = node
				if expanded[node] then
					visit(node)
				end
			end
		end
	end
	visit(root)
	return result
end
local function full()
	table.clear(rows)
	table.clear(indices)
	for i, node in ipairs(oracle()) do
		rows[i] = node
		indices[node] = i
	end
	p:Rebuild(root)
end
local function check()
	local expected = oracle()
	assert(#rows == #expected, "count mismatch")
	local width, depth = 0, 1
	for i, node in ipairs(expected) do
		assert(rows[i] == node and indices[node] == i, "order/position mismatch")
		local d = 0
		local parent = node
		while parent ~= root do
			d += 1
			parent = parent.Parent
		end
		assert(p.Depths[node] == d, "depth mismatch")
		width = math.max(width, node.NameWidth)
		depth = math.max(depth, d)
	end
	assert(p.Width == width and p.Depth == depth, "extent mismatch")
end
local context = { Root = root, Expanded = expanded, Sort = function() end, Measure = function() end }
for i = 1, 17500 do
	local group = { Parent = service, NameWidth = i % 79 + 1 }
	service[i] = group
	expanded[group] = true
	for j = 1, 3 do
		group[j] = { Parent = group, NameWidth = j * 3 }
	end
end
full()
assert(#rows == 70001)
local firstGroup, secondGroup = service[1], service[2]
local reindexed = p.Stats.Reindexed
firstGroup[1], firstGroup[3] = firstGroup[3], firstGroup[1]
p:Mark(firstGroup)
assert(p:Try(context))
assert(p.Stats.Reindexed - reindexed == 3, "equal-length edits leave the unchanged tail indexed")
check()
reindexed = p.Stats.Reindexed
local child = table.remove(firstGroup, 1)
child.Parent = secondGroup
secondGroup[#secondGroup + 1] = child
p:Mark(firstGroup)
p:Mark(secondGroup)
assert(p:Try(context))
assert(p.Stats.Reindexed - reindexed == 7, "a paired move only reindexes its affected range")
check()
local projectedBeforeInsertion = p.Stats.Projected
local group = service[8700]
local added = { Parent = group, NameWidth = 120 }
group[#group + 1] = added
p:Mark(group)
assert(p:Try(context))
check()
assert(p.Stats.Projected - projectedBeforeInsertion == 4, "small branch change traverses unrelated branches")
local gone = table.remove(group, 4)
gone.Del = true
p:Mark(group)
assert(p:Try(context) and indices[gone] == nil)
check()
do
	local at = 320
	local left = { Parent = service, NameWidth = 203 }
	local right = { Parent = service, NameWidth = 204 }
	table.insert(service, at, right)
	p:MarkChild(right, at)
	table.insert(service, at, left)
	p:MarkChild(left, at)
	local before = p.Stats.Projected
	assert(p:Try(context) and p.Stats.Projected == before + 2)
	check()
	left.Del = true
	p:MarkChild(left)
	right.Del = true
	p:MarkChild(right)
	assert(p:Try(context) and not indices[left] and not indices[right])
	check()
	table.remove(service, at)
	table.remove(service, at)

	local last = { Parent = service, NameWidth = 200 }
	table.insert(service, last)
	p:MarkChild(last, #service)
	expanded[firstGroup] = false
	p:Mark(firstGroup)
	assert(not p:Try(context), "an expansion change invalidates the leaf-only patch")
	full()
	check()
	table.remove(service)
	expanded[firstGroup] = true
	full()
end
-- Large changes bypass the splice before touching published rows or measuring.
local snapshot = table.clone(rows)
p:Mark(service)
local calls = 0
context.Measure = function()
	calls += 1
end
assert(not p:Try(context) and calls == 0, "large fallback performs duplicate expensive preparation")
for i, node in ipairs(snapshot) do
	assert(rows[i] == node, "fallback modifies published rows")
end
full()
math.randomseed(7342)
for iteration = 1, 300 do
	local a, b = service[math.random(1, 17500)], service[math.random(1, 17500)]
	if #a > 0 then
		local node = table.remove(a, math.random(1, #a))
		node.Parent = b
		b[#b + 1] = node
		p:Mark(a)
		p:Mark(b)
		p:Mark(node)
	end
	if iteration % 3 == 0 then
		expanded[a] = not expanded[a]
		p:Mark(a)
	end
	assert(p:Try(context))
	check()
end
-- Hidden churn must not retain an ever-growing dirty-node map.
for i = 1, 10000 do
	p:Mark({ Parent = service })
end
assert(next(p.Dirty) == nil, "hidden churn accumulates dirty references")
print(
	"PASS: 70001 rows, four-row local projection, fallback isolation, width shrink, 300 bidirectional moves/collapses against an independent oracle, and bounded hidden churn"
)
