--!strict

local initialConnections = activeSignals()
local globalCount = #Main.GlobalConnections
local cleanups = #Main.CleanupCallbacks
local holder = Instance.new("ScreenGui")
local manager = Renderer.Create({ Parent = holder, Workspace = workspace })
assert(#Main.CleanupCallbacks == cleanups + 1, "one shutdown owner per manager")
local root = Instance.new("Model", workspace)
local a = Instance.new("Part", root)
local b = Instance.new("Part", root)
manager:Update({ root, a })
local record = manager.Records[root]
assert(
	record and not manager.Records[a] and record.Highlight.Adornee == root,
	"selected ancestor merges descendant geometry once"
)
assert(
	record.Highlight.FillTransparency == 1 and record.Highlight.OutlineTransparency == 0,
	"outline has no selection fill"
)
assert(
	record.Highlight.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop,
	"foreground objects cannot cut new outline boundaries into the selected silhouette"
)
assert(
	record.Highlight.ReservedId == nil and record.Highlight.LineThickness == nil,
	"private Studio rendering path stays unused"
)
assert(
	manager.PivotDot.Visible and manager.PivotDot.Position == UDim2.fromOffset(120, 81),
	"pivot dot projects to integer screen pixels"
)
local highlight, dot = record.Highlight, manager.PivotDot
local other = Instance.new("Part", workspace)
local combined = { Position = { Marker = true } }
local pivotRoots
local multi = Renderer.Create({
	Parent = holder,
	Workspace = workspace,
	SelectionPivot = function(roots)
		pivotRoots = roots
		return combined
	end,
})
multi:Update({ root, a, other })
assert(#pivotRoots == 2 and multi.PivotDot.Visible, "multi-selection uses shared bounds after descendant deduplication")
local dots = 0
for _, visual in ipairs(holder:GetChildren()) do
	if visual.Name == "SelectionDot" then
		dots += 1
	end
end
assert(dots == 2, "each selection manager owns exactly one marker, not one per object")
assert(not multi.Records[root].Dot and not multi.Records[other].Dot, "individual objects own no pivot markers")
multi:Update({})
assert(not multi.PivotDot, "clearing selection removes shared marker")
multi:Destroy()
other:Destroy()
local connections = activeSignals()
for _ = 1, 40 do
	manager:Update({ root, a })
end
assert(
	manager.Records[root] == record and record.Highlight == highlight and manager.PivotDot == dot,
	"unchanged selection retains visuals"
)
assert(
	activeSignals() == connections and #Main.GlobalConnections == globalCount,
	"reconciliation creates no duplicate or globally retained listeners"
)
assert(service.RunService.RenderStepped.Active == 1, "one render callback for all pivot dots")
projection = { X = 222, Y = 152, Z = 10 }
service.RunService.RenderStepped:Fire()
assert(dot.Position == UDim2.fromOffset(222, 152), "dot follows live projection")
onScreen = false
service.RunService.RenderStepped:Fire()
assert(not dot.Visible, "offscreen dot is hidden")
onScreen = true

local previousWrite = instMT.__newindex
local alphaWrites = 0
instMT.__newindex = function(object, key, value)
	if object == record.Highlight then
		alphaWrites += 1
	end
	return previousWrite(object, key, value)
end
for i = 1, 1000 do
	a.Transparency = (i % 99) / 100
end
instMT.__newindex = previousWrite
assert(alphaWrites == 0, "partial-opacity animations cause no redundant highlight writes")
a.Transparency = 1
assert(
	record.Parts[a].Bounds and record.Parts[a].Bounds.Adornee == a and record.Highlight == highlight,
	"invisible child adds its own bounds without rebuilding visible silhouette"
)
b.LocalTransparencyModifier = 1
assert(
	not record.Highlight and record.Parts[b].Bounds and manager.Counts.Highlights == 0,
	"effective local invisibility releases empty model highlight"
)
a.Transparency = 0.5
a.LocalTransparencyModifier = 0.5
assert(record.Highlight and not record.Parts[a].Bounds, "partial effective transparency remains visible")
local incoming = Instance.new("Part", root)
assert(record.Parts[incoming] and record.VisibleParts == 2, "new descendant becomes part of retained model")
incoming.Parent = workspace
assert(not record.Parts[incoming] and record.VisibleParts == 1, "removed descendant releases its state")
assert(
	incoming.Transparency == 0 and a.Transparency == 0.5 and a.LocalTransparencyModifier == 0.5,
	"rendering does not alter game opacity"
)

manager:Update({ a })
record = manager.Records[a]
assert(record and record.Kind == "Part" and record.Highlight, "direct part gets its own selection")
a.LocalTransparencyModifier = 1
assert(record.Parts[a].Bounds and not record.Highlight, "direct part LTM change updates automatically")
a.LocalTransparencyModifier = 0
a.Transparency = 0
assert(record.Highlight and not record.Parts[a].Bounds, "direct part opacity restores silhouette automatically")
local storage = Instance.new("Folder", game)
a.Parent = storage
drain()
assert(
	not manager.Records[a] and manager.Counts.Roots == 0,
	"off-Workspace geometry has neither outline nor floating pivot"
)
a.Parent = workspace
drain()
assert(manager.Records[a], "selected part reparented back into Workspace regains visuals")

local folder = Instance.new("Folder", workspace)
local nested = Instance.new("Folder", folder)
local shape = Instance.new("Part", nested)
manager:Update({ folder, nested })
assert(manager.Records[shape] and manager.Counts.Roots == 1, "nested selected folders deduplicate geometry")
local dynamic = Instance.new("Part", nested)
drain()
assert(manager.Records[dynamic] and manager.Counts.Roots == 2, "selected folder reacts to added descendants")
shape.Parent = storage
drain()
assert(not manager.Records[shape] and manager.Records[dynamic], "selected folder drops moved-out geometry")
local later = Instance.new("Folder", nested)
drain()
local grandchild = Instance.new("Part", later)
drain()
assert(manager.Records[grandchild], "new nested folder is watched after reconciliation")
manager:Update({}, {})
drain()
assert(
	manager.Counts.Roots == 0
		and manager.Counts.Highlights == 0
		and manager.Counts.Bounds == 0
		and #holder:GetChildren() == 0,
	"clear releases every visual"
)
assert(service.RunService.RenderStepped.Active == 0, "empty selection does not run frame work")

local gui = Instance.new("Frame", Instance.new("ScreenGui"))
local attached, detached = 0, 0
local guiManager = Renderer.Create({
	Parent = holder,
	Workspace = workspace,
	AttachGui = function(_, parent)
		attached += 1
		return Instance.new("Frame", parent), function()
			detached += 1
		end
	end,
})
guiManager:Update({ gui }, { PartEnabled = false })
guiManager:Update({ gui }, { PartEnabled = false })
assert(attached == 1, "GUI selection attachment is retained")
guiManager:Destroy()
guiManager:Destroy()
assert(detached == 1, "GUI cleanup runs once")

local small = Renderer.Create({ Parent = holder, Workspace = workspace, MaxHighlights = 1, MaxBounds = 1 })
local first, second, third =
	Instance.new("Part", workspace), Instance.new("Part", workspace), Instance.new("Part", workspace)
small:Update({ first, second, third })
drain()
assert(
	small.Counts.Highlights == 1 and small.Counts.Bounds == 1 and small.Counts.OmittedBounds == 1,
	"outline and fallback budgets are bounded"
)
local winner
for object, state in pairs(small.Records) do
	if state.Highlight then
		winner = object
		break
	end
end
local remaining = {}
for _, object in ipairs({ first, second, third }) do
	if object ~= winner then
		remaining[#remaining + 1] = object
	end
end
small:Update(remaining)
drain()
assert(
	small.Counts.Highlights == 1 and small.Counts.Bounds == 1 and small.Counts.OmittedBounds == 0,
	"freed highlight capacity promotes a waiting root"
)
remaining[1].Transparency = 1
remaining[2].Transparency = 1
drain()
assert(
	small.Counts.Highlights == 0 and small.Counts.Bounds == 1 and small.Counts.OmittedBounds == 1,
	"hidden descendant bounds also obey budget"
)
small:Update({ remaining[2] })
drain()
assert(
	small.Counts.Bounds == 1 and small.Counts.OmittedBounds == 0,
	"released bounds capacity promotes pending hidden geometry"
)
small:Destroy()
manager:Destroy()
manager:Destroy()
drain()
assert(activeSignals() == initialConnections, "destroy disconnects selection, geometry, folder and frame listeners")
assert(#Main.GlobalConnections == globalCount, "transient visuals never enter global connection storage")
assert(#holder:GetChildren() == 0, "destroy removes all render objects")
a.Transparency = 1
grandchild.Parent = workspace
drain()
assert(#holder:GetChildren() == 0, "late game events cannot resurrect destroyed selection visuals")
do
	local previous = game.ItemChanged
	local event = signal()
	game._events.ItemChanged = event
	local members = { [a] = true }
	local selected = Apps.PropertyChanges.For({ Size = true }, members)
	local all, hits, lateHits = 0, 0, 0
	local replace, follower = false, nil
	local first = Apps.PropertyChanges.For({ Size = true, Name = true }):Connect(function()
		all += 1
		if replace then
			replace = false
			follower:Disconnect()
			follower = selected:Connect(function() lateHits += 1 end)
		end
	end)
	follower = selected:Connect(function() hits += 1 end)
	assert(event.Active == 1, "overlapping subscribers must share one engine connection")
	event:Fire(a, "Size")
	event:Fire(b, "Size")
	event:Fire(a, "CFrame")
	event:Fire(a, "Name")
	assert(all == 3 and hits == 1)
	members[a], members[b] = nil, true
	event:Fire(a, "Size")
	event:Fire(b, "Size")
	assert(all == 5 and hits == 2, "membership changes apply to the next event")
	replace = true
	event:Fire(b, "Size")
	assert(hits == 2 and lateHits == 0, "a replacement subscriber starts on the next event")
	event:Fire(b, "Size")
	assert(all == 7 and lateHits == 1)
	first:Disconnect()
	first:Disconnect()
	assert(event.Active == 1)
	follower:Disconnect()
	assert(event.Active == 0)
	game._events.ItemChanged = previous
end
print(
	"PASS: selection renderer retention, live opacity and hierarchy, direct/folder selection, budgets, GUI cleanup and listener ownership"
)
