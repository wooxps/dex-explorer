--!strict

local transformed = 0
local getComponents = baseFrameIndex.GetComponents
baseFrameIndex.GetComponents = function(cf)
	transformed += 1
	return getComponents(cf)
end
local oldClear, oldLines = methods.Clear, methods.AddLines
methods.Clear = function(self)
	self._props.Lines = {}
end
methods.AddLines = function(self, points)
	self._props.Lines = table.clone(points)
end
local oldTerrain, oldCamera = workspace.Terrain, workspace.CurrentCamera
workspace.Terrain = Instance.new("Terrain", workspace)
workspace.Terrain.CFrame = CFrame.new(500, 0, 0)
workspace.CurrentCamera = {
	WorldToScreenPoint = function()
		return { X = 100, Y = 100, Z = 10 }, true
	end,
}
local host = Instance.new("Folder", workspace)
local parts = {}
for index = 1, 1024 do
	local part = Instance.new("Part", host)
	part.Anchored = true
	part.CFrame = CFrame.new(index, 0, 0)
	part.Size = vec(2, 2, 2)
	parts[index] = part
end
local baseline = activeSignals()
local manager = Renderer.Create({
	Parent = holder,
	Workspace = workspace,
	GeometryMask = {
		Create = function()
			error("large selections must not duplicate geometry")
		end,
	},
})
manager:Update({ host })
local record = manager.Records[host]
assert(record.Group and record.Group.Count == 1024 and not record.Mask)
assert(manager.Counts.Roots == 1 and manager.Counts.Bounds == 1 and manager.Counts.Highlights == 0)
assert(activeSignals() - baseline < 10, "large selection installs per-part listeners")
local wire = holder:FindFirstChild("SelectionGroupBounds")
assert(wire and #wire.Lines == 24 and wire.Scale == vec(1025, 2, 2))
assert(wire.CFrame.Position == vec(12.5, 0, 0), "wireframe must account for Terrain's coordinate frame")
local writes = 0
local oldNewIndex = instMT.__newindex
instMT.__newindex = function(object, property, value)
	if object == wire and (property == "CFrame" or property == "Scale") then
		writes += 1
	end
	oldNewIndex(object, property, value)
end
for _ = 1, 120 do
	service.RunService.RenderStepped:Fire()
end
assert(writes == 0, "static selections redraw unchanged bounds every frame")
parts[1].CFrame = CFrame.new(-20, 0, 0)
game.ItemChanged:Fire(parts[1], "CFrame")
service.RunService.RenderStepped:Fire()
assert(wire.Scale == vec(1046, 2, 2) and writes == 2, "anchored edits update the bounds once")
parts[1].Anchored = false
game.ItemChanged:Fire(parts[1], "Anchored")
parts[1]._props.CFrame = CFrame.new(-30, 0, 0)
transformed = 0
service.RunService.RenderStepped:Fire()
assert(wire.Scale == vec(1056, 2, 2), "physics movement is observed without property events")
assert(transformed > 0 and transformed <= 32, "one moving part recomputed the whole folder")
parts[1].Parent = workspace
service.RunService.RenderStepped:Fire()
assert(record.Group.Count == 1023 and wire.Scale == vec(1024, 2, 2), "removed parts leave the bounds")
local rotated = Instance.new("Part")
rotated.Size = vec(10, 2, 2)
rotated.Anchored = true
rotated.CFrame = CFrame.new(-50, 0, 0) * CFrame.fromAxisAngle(vec(0, 0, 1), math.pi * 0.5)
rotated.Parent = host
service.RunService.RenderStepped:Fire()
assert(wire.Scale == vec(1076, 10, 2), "rotated geometry uses all three world-space extents")
manager:Update({ host, parts[2] })
assert(manager.Counts.Roots == 1, "selected ancestors deduplicate descendant adornments")
manager:Update({}, {})
drain()
assert(not wire.Parent and manager.Counts.Roots == 0 and manager.Counts.Bounds == 0)
assert(service.RunService.RenderStepped.Active == 0, "clearing a large selection leaves render work running")
for _, class in { "Folder", "Model" } do
	local container = Instance.new(class, workspace)
	local visible = Instance.new("Part", container)
	for _ = 1, 520 do Instance.new("StringValue", container) end
	manager:Update({ container })
	local detailed = manager.Records[class == "Folder" and visible or container]
	assert(detailed and detailed.Highlight and not detailed.Group, "metadata hid the detailed outline")
	if class == "Model" then
		for i = 1, 511 do
			local part = Instance.new("Part")
			part.CFrame, part.Size = CFrame.new(i, 0, 0), vec(1, 1, 1)
			part.Parent = container
		end
		visible.CFrame, visible.Size = CFrame.new(), vec(1, 1, 1)
		manager:Update({ container })
		assert(manager.Records[container].Group.Count == 512 and detailed.Destroyed)
	end
	manager:Update({})
	container:Destroy()
	drain()
end
manager:Destroy()
do
	local blocks = {}
	local dirtyDraws = 0
	methods.AddLines = function(self, points)
		dirtyDraws += 1
		self._props.Lines = table.clone(points)
	end
	local many = Renderer.Create({ Parent = holder, Workspace = workspace })
	for i = 1, 768 do
		local part = newPart(workspace, vec(i, 0, 0))
		part.Shape, part.Anchored = Enum.PartType.Block, true
		blocks[i] = part
	end
	many:Update(blocks)
	assert(many.Counts.WireBatches == 12 and many.Counts.Highlights == 0 and many.Counts.Bounds == 0)
	for _ = 1, 120 do service.RunService.RenderStepped:Fire() end
	assert(dirtyDraws == 12, "idle outlines were uploaded again")
	local box = many.Records[blocks[2]].Batch.Wire
	assert(#box.Lines == 64 * 24)
	blocks[2].CFrame = CFrame.new(300, 0, 0) * CFrame.fromAxisAngle(vec(0, 0, 1), math.pi / 2)
	blocks[2].Size = vec(2, 4, 8)
	game.ItemChanged:Fire(blocks[2], "CFrame")
	game.ItemChanged:Fire(blocks[2], "Size")
	service.RunService.RenderStepped:Fire()
	assert(dirtyDraws == 13 and box.Lines[25] == vec(302, -1, -4) and box.Lines[26] == vec(302, 1, -4))
	assert((workspace.Terrain.CFrame * box.CFrame) * box.Lines[25] == box.Lines[25])
	blocks[2].Anchored = false
	game.ItemChanged:Fire(blocks[2], "Anchored")
	drain()
	assert(many.Records[blocks[2]].Highlight and not many.Records[blocks[2]].Batch)
	local mesh = Instance.new("SpecialMesh", blocks[1])
	drain()
	assert(many.Records[blocks[1]].Highlight, "adding geometry must restore the native silhouette")
	many:Update({blocks[1], blocks[3]})
	assert(many.Counts.WireBatches == 0 and many.Counts.Highlights == 2 and not box.Parent)
	local folder = Instance.new("Folder", workspace)
	local mixed = {folder}
	for i = 1, 64 do blocks[i].Parent = folder end
	for i = 65, 79 do mixed[#mixed + 1] = blocks[i] end
	many:Update(mixed)
	assert(many.Records[folder].Group.Count == 64 and not many.Records[blocks[1]])
	many:Update({folder})
	assert(not many.Records[folder] and many.Records[blocks[1]].Highlight, "isolated folder restores child outlines")
	many:Destroy()
	for _, part in blocks do part:Destroy() end
	folder:Destroy()
	drain()
	print("PASS: 768 block outlines in 12 adornments, idle reuse, rotated resize, physics and mesh handoff")
end
instMT.__newindex = oldNewIndex
host:Destroy()
parts[1]:Destroy()
workspace.Terrain:Destroy()
workspace.Terrain, workspace.CurrentCamera = oldTerrain, oldCamera
methods.Clear, methods.AddLines = oldClear, oldLines
baseFrameIndex.GetComponents = getComponents
drain()
assert(activeSignals() == baseline, "group selection leaks source or frame subscriptions")
print("PASS: large selections use one wireframe, bounded listeners, static idle reuse, live transforms, rotated bounds and cleanup")

do
	local space = "Local"
	local observed, order
	local before = activeSignals()
	local camera = workspace.CurrentCamera
	workspace.CurrentCamera = { WorldToScreenPoint = function(_, point)
		observed = point
		return vec(100, 100, 1), true
	end }
	local multi = Renderer.Create({
		Parent = holder, Workspace = workspace,
		PivotSpace = function() return space end,
		CreateSelectionPivot = function(roots, records)
			order = roots
			return Transform.CreateSelectionPivot(roots, records)
		end,
		SelectionPivot = function(roots)
			local _, _, pivot = Transform.Bounds(roots, space)
			return pivot
		end,
	})
	local selected = {}
	for i = 1, 768 do
		local part = newPart(workspace, vec(i, i % 5, -i), vec(2, 3, 4))
		part.GetPivot = methods.GetPivot
		part.Anchored = true
		selected[i] = part
	end
	multi:Update(selected)
	local calls = 0
	baseFrameIndex.GetComponents = function(cf)
		calls += 1
		return getComponents(cf)
	end
	for _ = 1, 120 do service.RunService.RenderStepped:Fire() end
	assert(calls == 0, "stationary selection recomputed bounds while projecting its dot")
	local function checkPivot()
		local _, _, expected = Transform.Bounds(order, space)
		assert((observed - expected.Position).Magnitude < 0.000001)
	end
	checkPivot()
	local moving = order[50]
	moving.Anchored = false
	game.ItemChanged:Fire(moving, "Anchored")
	moving._props.CFrame = CFrame.new(5000, 0, 100)
	calls = 0
	service.RunService.RenderStepped:Fire()
	assert(calls == 32)
	checkPivot()
	moving.Size = vec(200, 200, 200)
	game.ItemChanged:Fire(moving, "Size")
	service.RunService.RenderStepped:Fire()
	checkPivot()
	order[1].PivotOffset = CFrame.fromAxisAngle(vec(0, 0, 1), 0.37)
	game.ItemChanged:Fire(order[1], "PivotOffset")
	for _, mode in { "Local", "World", "Scale" } do
		space = mode
		service.RunService.RenderStepped:Fire()
		checkPivot()
	end
	selected[1].LocalTransparencyModifier = 1
	game.ItemChanged:Fire(selected[1], "LocalTransparencyModifier")
	assert(multi.Records[selected[1]].Parts[selected[1]].Invisible)
	selected[1].LocalTransparencyModifier = 0
	game.ItemChanged:Fire(selected[1], "LocalTransparencyModifier")
	assert(not multi.Records[selected[1]].Parts[selected[1]].Invisible)
	local model = Instance.new("Model", workspace)
	model.GetPivot = methods.GetPivot
	newPart(model, vec(-8000, 0, 0)).Anchored = true
	selected[#selected + 1] = model
	multi:Update(selected)
	checkPivot()
	local extra = newPart(nil, vec(-16000, 100, 0))
	extra.Anchored = true
	extra.Parent = model
	service.RunService.RenderStepped:Fire()
	checkPivot()
	extra.Parent = nil
	service.RunService.RenderStepped:Fire()
	checkPivot()
	extra:Destroy()
	baseFrameIndex.GetComponents = getComponents
	multi:Destroy()
	drain()
	for _, part in ipairs(selected) do part:Destroy() end
	workspace.CurrentCamera = camera
	assert(activeSignals() == before, "bulk selection leaked a listener")
	print("PASS: bulk selection idle projection, physics movement, resize, pivot edits, transform modes and cleanup")
end
