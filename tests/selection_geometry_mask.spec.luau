--!strict

-- Structural/runtime ownership checks. These do not simulate Highlight GPU output.
do
	local baseline = activeSignals()
	local oldDestroy = methods.Destroy
	methods.Destroy = function(self)
		for _, child in ipairs(self:GetChildren()) do
			child:Destroy()
		end
		oldDestroy(self)
	end
	local oldTags, oldRemoveTag, oldAttrs = methods.GetTags, methods.RemoveTag, methods.GetAttributes
	methods.GetTags = function(self)
		return table.clone(self._props.TestTags or {})
	end
	methods.RemoveTag = function(self, tag)
		local tags = self._props.TestTags or {}
		local at = table.find(tags, tag)
		if at then
			table.remove(tags, at)
		end
	end
	methods.GetAttributes = function(self)
		local result = {}
		for key, value in pairs(self._props) do
			if key:sub(1, 5) == "attr_" then
				result[key:sub(6)] = value
			end
		end
		return result
	end
	local poseWrites = 0
	local originalIndex, originalNewIndex = instMT.__index, instMT.__newindex
	instMT.__index = function(object, key)
		if key == "Changed" then
			object._events[key] = object._events[key] or signal()
			return object._events[key]
		end
		return originalIndex(object, key)
	end
	instMT.__newindex = function(object, key, value)
		if key == "CFrame" or key == "Transform" then
			poseWrites += 1
		end
		local old = object._props[key]
		originalNewIndex(object, key, value)
		if old ~= value and object._events.Changed then
			object.Changed:Fire(key)
		end
	end
	local oldIsA = methods.IsA
	methods.IsA = function(self, class)
		return oldIsA(self, class)
			or class == "DataModelMesh" and self.ClassName == "SpecialMesh"
			or class == "BasePart" and (self.ClassName == "MeshPart" or self.ClassName == "UnionOperation")
	end
	local oldFromExisting = Instance.fromExisting
	Instance.fromExisting = function(source)
		assert(not source:GetAttribute("RejectCopy"), "copy denied")
		local copy = Instance.new(source.ClassName)
		for key, value in pairs(source._props) do
			if key ~= "Parent" and key ~= "Destroyed" then
				copy[key] = type(value) == "table" and key == "TestTags" and table.clone(value) or value
			end
		end
		return copy
	end
	local Geometry = MaskModule.Main()
	local updates = 0
	local sourceRoot = Instance.new("Model", workspace)
	local visible = Instance.new("Part", sourceRoot)
	visible.Size = Vector3.new(4, 6, 2)
	visible.CFrame = { Id = 1 }
	visible.Shape = "Cylinder"
	visible.Anchored = true
	visible.Archivable = false
	visible.TestTags = { "GameTag" }
	visible:SetAttribute("GameplayId", 12)
	local hidden = Instance.new("MeshPart", sourceRoot)
	hidden.Size = Vector3.new(8, 6, 2)
	hidden.CFrame = { Id = 2 }
	hidden.Transparency = 1
	hidden.LocalTransparencyModifier = 0.6
	hidden.Anchored = false
	hidden.MeshId = "rbxassetid://native-mesh"
	hidden.Archivable = false
	local foreground = Instance.new("Part", workspace)
	foreground.CFrame = visible.CFrame
	foreground.Size = visible.Size
	local mesh = Instance.new("SpecialMesh", visible)
	mesh.Scale = Vector3.new(2, 1, 1)
	local scriptChild = Instance.new("Script", visible)
	local emitter = Instance.new("ParticleEmitter", hidden)
	local bone = Instance.new("Bone", hidden)
	bone.CFrame = { Id = 3 }
	bone.Transform = { Id = 4 }
	local mask = assert(Geometry.Create({ [visible] = true, [hidden] = true }, function()
		updates += 1
	end))
	assert(not mask.Ready and not mask.Model.Parent, "geometry builds off-scene before publishing")
	drain()
	assert(mask.Ready and not mask.Failed and mask.Count == 2 and updates == 1, "complete mask publishes once")
	assert(
		mask.Model.Parent.Parent == workspace and Main.SelectionGeometryRoots[mask.Model.Parent],
		"root is registered before entering Workspace"
	)
	assert(
		Geometry.IsInternal(mask.Model) and Geometry.IsInternal(mask.Entries[hidden].Copy),
		"render copies can be excluded from Explorer"
	)
	local a, b = mask.Entries[visible].Copy, mask.Entries[hidden].Copy
	assert(Main.SelectionGeometryObjects[a] and Main.SelectionGeometryObjects[b], "render copies bypass Explorer reconciliation")
	assert(
		not mask.Entries[foreground] and mask.Count == 2,
		"overlapping foreign objects do not enter the selected geometry set"
	)
	assert(
		a.ClassName == "Part" and b.ClassName == "MeshPart" and b.MeshId == hidden.MeshId and a.Shape == visible.Shape,
		"native render geometry is preserved instead of bounding-box substitution"
	)
	for _, copy in ipairs({ a, b }) do
		assert(
			copy.Anchored and not copy.CanCollide and not copy.CanTouch and not copy.CanQuery and not copy.CastShadow,
			"copies do not participate in interaction or physics"
		)
		assert(
			copy.Transparency > 0.999999 and copy.Transparency < 1 and copy.LocalTransparencyModifier == 0,
			"copies remain mask-eligible without a visible material surface"
		)
		assert(
			not copy.Archivable and #copy:GetTags() == 0 and next(copy:GetAttributes()) == nil,
			"no copied gameplay metadata is activated"
		)
	end
	assert(
		a:FindFirstChildOfClass("SpecialMesh") and b:FindFirstChildOfClass("Bone"),
		"shape meshes and deformation bones survive shallow reconstruction"
	)
	assert(
		not a:FindFirstChildOfClass("Script") and not b:FindFirstChildOfClass("ParticleEmitter"),
		"scripts and effects are never copied"
	)
	assert(
		visible.Parent == sourceRoot
			and hidden.Parent == sourceRoot
			and hidden.Transparency == 1
			and hidden.LocalTransparencyModifier == 0.6
			and not visible.Archivable,
		"original hierarchy/opacity/Archivable remain untouched"
	)
	assert(visible:GetAttribute("GameplayId") == 12 and #visible:GetTags() == 1, "source metadata is unchanged")
	visible.CFrame = { Id = 5 }
	visible.Size = Vector3.new(9, 9, 9)
	assert(a.CFrame == visible.CFrame and a.Size == visible.Size, "anchored geometry follows live transform edits")
	hidden._props.CFrame = { Id = 6 }
	bone._props.Transform = { Id = 7 }
	mask:Step()
	assert(
		b.CFrame == hidden.CFrame and mask.Bones[bone].Copy.Transform == bone.Transform,
		"physics and animation poses follow native updates without Changed"
	)
	local settledWrites = poseWrites
	for _ = 1, 120 do
		mask:Step()
	end
	assert(poseWrites == settledWrites, "unchanged native poses cause no copy writes across 120 frames")
	hidden._props.CFrame = { Id = 61 }
	mask:Step()
	assert(b.CFrame == hidden.CFrame, "pose polling resumes immediately on movement")
	mesh.Scale = Vector3.new(3, 2, 1)
	assert(a:FindFirstChildOfClass("SpecialMesh").Scale == mesh.Scale, "SpecialMesh geometry edits are mirrored")
	local extra = Instance.new("SpecialMesh", hidden)
	drain()
	assert(
		mask.Entries[hidden].Copy:FindFirstChildOfClass("SpecialMesh"),
		"new geometry helper triggers a safe shallow rebuild"
	)
	mask:Remove(hidden)
	assert(
		mask.Count == 1 and not mask.Entries[hidden] and not mask.Bones[bone],
		"removed source removes geometry and animation ownership"
	)
	local late = Instance.new("Part", sourceRoot)
	mask:Add(late)
	mask:Destroy()
	drain()
	assert(
		not Geometry.IsInternal(mask.Model) and not next(Main.SelectionGeometryRoots),
		"destroy removes root registration and queued copies"
	)
	assert(activeSignals() == baseline, "all source/helper observers are released")

	local moving = {}
	local oldBulkMove = methods.BulkMoveTo
	local bulkCalls, denyBulk = 0, false
	methods.BulkMoveTo = function(_, parts, poses, mode)
		assert(#parts == 64 and #poses == #parts and mode == Enum.BulkMoveMode.FireCFrameChanged)
		bulkCalls += 1
		assert(not denyBulk, "bulk move denied")
		for index, part in ipairs(parts) do
			part._props.CFrame = poses[index]
		end
	end
	for index = 1, 64 do
		local part = Instance.new("Part", workspace)
		part.Anchored = false
		part.CFrame = { Id = index }
		moving[part] = true
	end
	local movingMask = assert(Geometry.Create(moving))
	drain()
	movingMask:Step()
	assert(bulkCalls == 0, "initial copies already match source poses")
	for part in pairs(moving) do
		part._props.CFrame = { Id = 100 }
	end
	movingMask:Step()
	movingMask:Step()
	assert(bulkCalls == 1, "64 changed copies use one native movement call, with no idle repeat")
	for part, entry in pairs(movingMask.Entries) do
		assert(entry.Copy.CFrame == part.CFrame)
		part._props.CFrame = { Id = 101 }
	end
	denyBulk = true
	movingMask:Step()
	assert(bulkCalls == 2, "failed batch falls back to individual moves")
	for part, entry in pairs(movingMask.Entries) do
		assert(entry.Copy.CFrame == part.CFrame)
	end
	movingMask:Destroy()
	for part in pairs(moving) do
		part:Destroy()
	end
	methods.BulkMoveTo = oldBulkMove

	-- Exercise the real renderer switching one retained Highlight to a combined
	-- model, rather than keeping the old Highlight-plus-wireframe rendering.
	local manager = Renderer.Create({ Parent = holder, Workspace = workspace, GeometryMask = Geometry })
	manager:Update({ sourceRoot })
	local record = manager.Records[sourceRoot]
	assert(
		record.PreparingMask and not record.Highlight and manager.Counts.Bounds == 0,
		"initial selection never shows visible-only outlines or per-part bounds before the combined mask"
	)
	drain()
	assert(
		record.MaskActive and record.Highlight.Enabled and record.Highlight.Adornee == record.Mask.Model,
		"first published outline uses the completed combined geometry"
	)
	local originalHighlight = record.Highlight
	local helper = Instance.new("SpecialMesh", visible)
	flushTasks()
	assert(
		record.PreparingMask and not originalHighlight.Enabled and manager.Counts.Bounds == 0,
		"geometry rebuild suppresses all temporary fallback outlines"
	)
	drain()
	assert(
		record.Highlight == originalHighlight
			and originalHighlight.Enabled
			and originalHighlight.Adornee == record.Mask.Model,
		"completed rebuild reuses and atomically restores the highlight"
	)
	assert(
		record.Highlight.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop and not record.Mask.Entries[foreground],
		"combined outlines retain only selected geometry without tracing foreground depth holes"
	)
	assert(
		not record.Parts[hidden].Bounds and record.RenderingMode == "CombinedGeometryMask",
		"individual hidden-part wireframes are replaced after the combined mask is ready"
	)
	local added = Instance.new("Part", sourceRoot)
	assert(
		record.PreparingMask and not record.Highlight.Enabled,
		"adding geometry hides an incomplete mask until its new entry is ready"
	)
	drain()
	assert(
		record.Mask.Entries[added] and record.Highlight.Enabled,
		"incremental mask addition publishes the completed geometry"
	)
	local oldStep = record.Mask.Step
	record.Mask.Step = function()
		error("removed native geometry")
	end
	service.RunService.RenderStepped:Fire()
	assert(
		not record.Mask and record.MaskUnavailable and record.Highlight.Adornee == sourceRoot,
		"native pose failure cleanly falls back instead of breaking every render frame"
	)
	hidden.Transparency = 0
	hidden.LocalTransparencyModifier = 0
	assert(
		not record.Mask and record.Highlight.Adornee == sourceRoot,
		"ordinary visible-only selection uses its original geometry"
	)
	manager:Destroy()
	drain()
	assert(
		activeSignals() == baseline and not next(Main.SelectionGeometryRoots),
		"renderer shutdown releases combined geometry resources"
	)
	local rejected = Instance.new("Part", sourceRoot)
	rejected:SetAttribute("RejectCopy", true)
	manager = Renderer.Create({ Parent = holder, Workspace = workspace, GeometryMask = Geometry })
	rejected.Transparency = 1
	manager:Update({ rejected })
	drain()
	record = manager.Records[rejected]
	assert(
		record.MaskUnavailable and not record.Mask and record.Parts[rejected].Bounds,
		"copy failure preserves a working fallback and does not retry forever"
	)
	manager:Destroy()
	drain()
	assert(
		activeSignals() == baseline and not next(Main.SelectionGeometryRoots),
		"failed mask leaves no geometry/listeners"
	)
	local bulk = {}
	for _ = 1, 300 do
		local part = Instance.new("Part", sourceRoot)
		part.Anchored = true
		bulk[part] = true
	end
	mask = assert(Geometry.Create(bulk))
	flushTasks()
	assert(not mask.Ready and mask.Count <= 256, "large masks yield instead of allocating every part in one frame")
	mask:Destroy()
	drain()
	assert(
		activeSignals() == baseline and not next(Main.SelectionGeometryRoots),
		"cancelling a large pending build leaves no copies or observers"
	)
	local folderBaseline = activeSignals()
	local folder = Instance.new("Folder", workspace)
	local nested = Instance.new("Folder", folder)
	local nestedModel = Instance.new("Model", nested)
	local folderPart = Instance.new("Part", folder)
	local nestedPart = Instance.new("Part", nestedModel)
	nestedPart.Transparency = 1
	manager = Renderer.Create({ Parent = holder, Workspace = workspace, GeometryMask = Geometry })
	manager:Update({ folder, nested, nestedModel, nestedPart })
	assert(manager.Counts.Roots == 2 and not manager.Records[folder], "folders resolve to native spatial targets")
	assert(manager.Records[folderPart].Highlight.Adornee == folderPart)
	assert(not manager.Records[nestedModel].Mask and manager.Records[nestedModel].Parts[nestedPart].Bounds,
		"invisible folder descendants use bounds without duplicating geometry")
	local extraFolder = Instance.new("Folder", nested)
	local extraPart = Instance.new("Part", extraFolder)
	drain()
	assert(manager.Records[extraPart].Highlight.Adornee == extraPart, "nested additions use original geometry")
	manager:Destroy()
	folder:Destroy()
	drain()
	assert(activeSignals() == folderBaseline and not next(Main.SelectionGeometryRoots), "folder observers are released")
	Instance.fromExisting = nil
	assert(
		Geometry.Create({ [visible] = true }) == nil,
		"unsupported shallow copying is detected without touching originals"
	)
	Instance.fromExisting = oldFromExisting
	instMT.__index, instMT.__newindex = originalIndex, originalNewIndex
	methods.Destroy, methods.IsA = oldDestroy, oldIsA
	methods.GetTags, methods.RemoveTag, methods.GetAttributes = oldTags, oldRemoveTag, oldAttrs
	print(
		"PASS: combined selection geometry, source immutability, shallow mesh/bone copying, live transforms, renderer handoff and failure cleanup (GPU appearance unverified)"
	)
end
