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
local trackedRoots, fullScans = nil, 0
local manager = Renderer.Create({
	Parent = holder,
	Workspace = workspace,
	PivotSpace = function() return "World" end,
	CreateSelectionPivot = function(roots, records, groups)
		trackedRoots = roots
		return Transform.CreateSelectionPivot(roots, records, groups)
	end,
	SelectionPivot = function(roots)
		fullScans += 1
		local _, _, pivot = Transform.Bounds(roots, "World")
		return pivot
	end,
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
for i = 1, 120 do
	parts[200].CFrame = CFrame.new(200 + i, 0, 0)
	game.ItemChanged:Fire(parts[200], "CFrame")
	service.RunService.RenderStepped:Fire()
end
assert(writes == 0 and wire.Scale == vec(1025, 2, 2), "interior movement rewrote the same outline")
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
assert(transformed > 0 and transformed <= 8, "one moving part recomputed unrelated bounds")
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
do
	local selected = { host }
	for i = 1, 48 do
		local part = newPart(workspace, vec(-i, 0, 0))
		part.Anchored = true
		selected[#selected + 1] = part
	end
	local projected, camera = nil, workspace.CurrentCamera
	workspace.CurrentCamera = { WorldToScreenPoint = function(_, point)
		projected = point
		return vec(100, 100, 10), true
	end }
	manager:Update(selected)
	assert(#trackedRoots == 49)
	transformed = 0
	for _ = 1, 120 do service.RunService.RenderStepped:Fire() end
	assert(transformed == 0 and fullScans == 0, "a large group disabled caching for unrelated roots")
	local function verify()
		service.RunService.RenderStepped:Fire()
		local _, _, expected = Transform.Bounds(trackedRoots, "World")
		assert((projected - expected.Position).Magnitude < 0.000001)
	end
	parts[1024].CFrame = CFrame.new(2000, 0, 0)
	game.ItemChanged:Fire(parts[1024], "CFrame")
	verify()
	local children = host:GetChildren()
	for _, child in ipairs(children) do child.Parent = workspace end
	verify()
	assert(#trackedRoots == 48)
	for _, child in ipairs(children) do child.Parent = host end
	verify()
	assert(#trackedRoots == 49 and fullScans == 0)
	manager:Update({host})
	for i = 2, #selected do selected[i]:Destroy() end
	workspace.CurrentCamera = camera
end
-- Shrink across several tree levels between frames, then regrow the same selection.
for _, part in ipairs(host:GetChildren()) do part.Parent = workspace end
record.Group:Step()
assert(record.Group.Count == 0 and not wire.Visible)
for i = 1, 513 do
	parts[i].CFrame = CFrame.new(-2 * i, i, 0)
	parts[i].Parent = host
	if i == 1 or i == 8 or i == 9 or i == 64 or i == 65 or i == 512 or i == 513 then
		record.Group:Step()
		assert(wire.Visible and wire.Scale == vec(2 * i, i + 1, 2))
	end
end
for i = 1, 513 do
	local part = parts[i]
	part.Anchored = false
	game.ItemChanged:Fire(part, "Anchored")
	part._props.CFrame = CFrame.new(i * 3, -i, 0)
end
record.Group:Step()
assert(wire.Scale == vec(1538, 514, 2), "dense movement must update every extent")
parts[2]._props.CFrame = CFrame.new(-100, 10, 0)
record.Group:Step()
assert(wire.Scale == vec(1641, 525, 2), "a sparse frame after dense motion must see all prior movement")
for i = 1, 511 do parts[i].Parent = workspace end
record.Group:Step()
assert(wire.Scale == vec(5, 3, 2), "swapping tail parts invalidates both former and new bounds")
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
		local walks = 0
		local getDescendants = methods.GetDescendants
		methods.GetDescendants = function(self)
			if self == container then walks += 1 end
			return getDescendants(self)
		end
		for _ = 1, 100 do manager:Update({ workspace, container }) end
		assert(walks == 0 and manager.Records[container] == detailed and detailed.Highlight.Adornee == container)
		methods.GetDescendants = getDescendants
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
instMT.__newindex = oldNewIndex
host:Destroy()
for _, part in ipairs(parts) do if part.Parent then part:Destroy() end end
rotated:Destroy()
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
	assert(calls > 0 and calls <= 4, "one moving root only recomputes its leaf")
	checkPivot()
	for i = 2, #order do
		local part = order[i]
		part.Anchored = false
		game.ItemChanged:Fire(part, "Anchored")
		part._props.CFrame = CFrame.new(i, -i, 2*i)
	end
	service.RunService.RenderStepped:Fire()
	checkPivot()
	order[3]._props.CFrame = CFrame.new(-9100, 35, 0)
	service.RunService.RenderStepped:Fire()
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
