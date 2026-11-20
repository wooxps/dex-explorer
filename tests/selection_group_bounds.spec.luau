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
manager:Destroy()
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
