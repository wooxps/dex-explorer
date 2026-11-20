--!strict

local Main, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, service = d.Main, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Renderer = {}
	local function disconnect(list)
		for _, connection in ipairs(list) do
			connection:Disconnect()
		end
		table.clear(list)
	end
	local function destroy(object)
		if object then
			object:Destroy()
		end
	end
	local function invisible(part)
		local t = part.Transparency or 0
		local localT = part.LocalTransparencyModifier or 0
		return 1 - (1 - t) * (1 - localT) >= 1
	end
	local function needsGroupBounds(object, descendants)
		if #descendants < 512 then return false end
		local folder = object:IsA("Folder")
		local count = 0
		for _, child in ipairs(descendants) do
			-- Folder expansion also installs watches on nested folders and models.
			if child:IsA("BasePart") or (folder and (child:IsA("Folder") or child:IsA("Model"))) then
				count += 1
				if count >= 512 then return true end
			end
		end
		return false
	end
	local function createGroupBounds(object, parent, color, workspace, excluded, descendants, owners)
		local group = { Parts = {}, Dynamic = {}, Connections = {}, Dirty = true, Count = 0 }
		local entries, moving, levels = {}, {}, { {} }
		local fanout = 8
		-- Each leaf covers eight consecutive parts. A changed leaf invalidates
		-- just its ancestors, including the root when the tree grows or shrinks.
		local function dirtySlot(slot, resized)
			group.Dirty = true
			local index = (slot - 1) // fanout + 1
			local count = (#entries + fanout - 1) // fanout
			local depth = 1
			while true do
				local level = levels[depth]
				if not level then
					level = {}
					levels[depth] = level
				end
				local block = level[index]
				if index > count then
					level[index] = nil
				elseif not block then
					level[index] = { Dirty = true }
				elseif block.Dirty and not resized then
					return
				else
					block.Dirty = true
				end
				if count <= 1 then
					if resized then levels[depth + 1] = nil end
					return
				end
				index = (index - 1) // fanout + 1
				count = (count + fanout - 1) // fanout
				depth += 1
			end
		end
		local wire = Instance.new("WireframeHandleAdornment")
		wire.Name = "SelectionGroupBounds"
		wire.Adornee = workspace.Terrain
		wire.AlwaysOnTop = true
		wire.ZIndex = 1
		wire.Thickness = 1
		wire.Transparency = 0
		local vertices = {}
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			for _, a in ipairs({ -0.5, 0.5 }) do
				for _, b in ipairs({ -0.5, 0.5 }) do
					if axis == "X" then
						vertices[#vertices + 1], vertices[#vertices + 2] = Vector3.new(-0.5, a, b), Vector3.new(0.5, a, b)
					elseif axis == "Y" then
						vertices[#vertices + 1], vertices[#vertices + 2] = Vector3.new(a, -0.5, b), Vector3.new(a, 0.5, b)
					else
						vertices[#vertices + 1], vertices[#vertices + 2] = Vector3.new(a, b, -0.5), Vector3.new(a, b, 0.5)
					end
				end
			end
		end
		function group:SetColor(value)
			if self.Color ~= value then
				self.Color = value
				wire.Color3 = value
				wire:Clear()
				wire:AddLines(vertices)
			end
		end
		local function setMoving(part, entry, enabled)
			local slot = entry.MovingSlot
			if enabled and not slot then
				entry.MovingSlot = #moving + 1
				moving[entry.MovingSlot] = entry
				group.Dynamic[part] = entry
			elseif not enabled and slot then
				local last = #moving
				local tail = moving[last]
				moving[slot] = tail
				tail.MovingSlot = slot
				moving[last] = nil
				entry.MovingSlot = nil
				group.Dynamic[part] = nil
			end
		end
		local function add(part)
			if not part:IsA("BasePart") or part:IsA("Terrain") or excluded(part) or group.Parts[part] then
				return
			end
			local slot = #entries + 1
			local entry = { Part = part, Pose = part.CFrame, Size = part.Size, Slot = slot }
			entries[slot] = entry
			dirtySlot(slot, (slot - 1) % fanout == 0)
			group.Parts[part] = entry
			owners[part] = group
			setMoving(part, entry, not part.Anchored)
			group.Count += 1
		end
		for _, part in ipairs(descendants or object:GetDescendants()) do
			add(part)
		end
		group.Connections[#group.Connections + 1] = object.DescendantAdded:Connect(add)
		group.Connections[#group.Connections + 1] = object.DescendantRemoving:Connect(function(part)
			local entry = group.Parts[part]
			if entry then
				local last = #entries
				local tail = entries[last]
				entries[entry.Slot] = tail
				tail.Slot = entry.Slot
				entries[last] = nil
				dirtySlot(last, (last - 1) % fanout == 0)
				if entry.Slot < last then dirtySlot(entry.Slot) end
				setMoving(part, entry, false)
				group.Parts[part] = nil
				if owners[part] == group then owners[part] = nil end
				group.Count -= 1
			end
		end)
		function group:PropertyChanged(part, property)
			local entry = group.Parts[part]
			if not entry then
				return
			end
			if property == "CFrame" or property == "Size" then
				entry.Pose, entry.Size = part.CFrame, part.Size
				dirtySlot(entry.Slot)
			elseif property == "Anchored" then
				setMoving(part, entry, not part.Anchored)
			end
		end
		local function partBounds(first, last)
			local ax, ay, az = math.huge, math.huge, math.huge
			local bx, by, bz = -math.huge, -math.huge, -math.huge
			for slot = first, last do
				local entry = entries[slot]
				local x, y, z, xx, xy, xz, yx, yy, yz, zx, zy, zz = entry.Pose:GetComponents()
				local size = entry.Size
				local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
				local ex, ey, ez = hx, hy, hz
				if xx ~= 1 or xy ~= 0 or xz ~= 0 or yx ~= 0 or yy ~= 1 or yz ~= 0 or zx ~= 0 or zy ~= 0 or zz ~= 1 then
					ex = math.abs(xx) * hx + math.abs(xy) * hy + math.abs(xz) * hz
					ey = math.abs(yx) * hx + math.abs(yy) * hy + math.abs(yz) * hz
					ez = math.abs(zx) * hx + math.abs(zy) * hy + math.abs(zz) * hz
				end
				ax, ay, az = math.min(ax, x - ex), math.min(ay, y - ey), math.min(az, z - ez)
				bx, by, bz = math.max(bx, x + ex), math.max(by, y + ey), math.max(bz, z + ez)
			end
			return ax, ay, az, bx, by, bz
		end
		local function boundsAt(depth, index)
			local block = levels[depth][index]
			if not block.Dirty then return block end
			local first = (index - 1) * fanout + 1
			if depth == 1 then
				block.MinX, block.MinY, block.MinZ, block.MaxX, block.MaxY, block.MaxZ =
					partBounds(first, math.min(index * fanout, #entries))
			else
				local ax, ay, az = math.huge, math.huge, math.huge
				local bx, by, bz = -math.huge, -math.huge, -math.huge
				for i = first, math.min(index * fanout, #levels[depth - 1]) do
					local child = boundsAt(depth - 1, i)
					ax, ay, az = math.min(ax, child.MinX), math.min(ay, child.MinY), math.min(az, child.MinZ)
					bx, by, bz = math.max(bx, child.MaxX), math.max(by, child.MaxY), math.max(bz, child.MaxZ)
				end
				block.MinX, block.MinY, block.MinZ = ax, ay, az
				block.MaxX, block.MaxY, block.MaxZ = bx, by, bz
			end
			block.Dirty = false
			return block
		end
		local treeStale = false
		function group:Step()
			local moved, scanAt = 0, math.max(8, self.Count // 8)
			for _, entry in ipairs(moving) do
				local pose = entry.Part.CFrame
				if pose ~= entry.Pose then
					entry.Pose = pose
					moved += 1
					if moved < scanAt and not treeStale then dirtySlot(entry.Slot) end
				end
			end
			if not self.Dirty and moved == 0 then
				return
			end
			self.Dirty = false
			local visible = self.Count > 0
			if self.Visible ~= visible then
				self.Visible = visible
				wire.Visible = visible
			end
			if self.Count > 0 then
				local minX, minY, minZ, maxX, maxY, maxZ
				if moved >= scanAt then
					minX, minY, minZ, maxX, maxY, maxZ = partBounds(1, self.Count)
					treeStale = true
				else
					if treeStale then
						for _, level in ipairs(levels) do
							for _, block in ipairs(level) do block.Dirty = true end
						end
						treeStale = false
					end
					local root = boundsAt(#levels, 1)
					minX, minY, minZ = root.MinX, root.MinY, root.MinZ
					maxX, maxY, maxZ = root.MaxX, root.MaxY, root.MaxZ
				end
				local terrainPose = workspace.Terrain.CFrame
				if minX == self.MinX and minY == self.MinY and minZ == self.MinZ
					and maxX == self.MaxX and maxY == self.MaxY and maxZ == self.MaxZ
					and terrainPose == self.TerrainPose then return end
				self.MinX, self.MinY, self.MinZ = minX, minY, minZ
				self.MaxX, self.MaxY, self.MaxZ = maxX, maxY, maxZ
				self.TerrainPose = terrainPose
				self.Pivot = CFrame.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
				self.Size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
				wire.CFrame = terrainPose:ToObjectSpace(self.Pivot)
				wire.Scale = self.Size
			end
		end
		function group:IsA(class)
			return class == "Model"
		end
		function group:GetPivot()
			return self.Pivot
		end
		function group:GetBoundingBox()
			return self.Pivot, self.Size
		end
		function group:SetEnabled(enabled)
			wire.Parent = enabled and parent or nil
		end
		function group:Destroy()
			disconnect(self.Connections)
			wire:Destroy()
			for part in self.Parts do
				if owners[part] == self then owners[part] = nil end
			end
			table.clear(self.Parts)
			table.clear(self.Dynamic)
			table.clear(entries)
			table.clear(moving)
			table.clear(levels)
		end
		group:SetColor(color)
		group:Step()
		wire.Parent = parent
		return group
	end
	function Renderer.Create(config)
		local parent = config.Parent
		local workspace = config.Workspace or service.Workspace
		local maxHighlights = config.MaxHighlights or 255
		local maxBounds = config.MaxBounds or 1000
		local manager = {
			Records = {},
			Folders = {},
			Counts = { Roots = 0, Highlights = 0, Bounds = 0, OmittedBounds = 0 },
			Destroyed = false,
		}
		manager.InspectorRecords = manager.Records
		local selection, selectionWatches = {}, {}
		local largeGroups = {}
		local groupOwners, groupCount, groupConnection = {}, 0, nil
		local options = { PartEnabled = true, GuiEnabled = true, Color = Color3.fromRGB(0, 170, 255) }
		local pendingBounds, pendingHighlights, pendingGroups = {}, {}, {}
		local masks = {}
		local selectionPivot
		local sharedOpacity = {}
		local opacityConnection
		local frameConnection, reconcileQueued, balanceQueued
		local reconcile, balance, updateRoot, removeRecord
		local function excluded(object)
			return config.IsExcluded and config.IsExcluded(object)
		end
		local function spatial(object)
			return (object:IsA("BasePart") or object:IsA("Model") or largeGroups[object])
				and not object:IsA("Terrain")
				and object ~= workspace
				and not excluded(object)
				and object:IsDescendantOf(workspace)
		end
		local function bind(list, event, callback)
			list[#list + 1] = event:Connect(callback)
		end
		local function queueBalance()
			if balanceQueued or manager.Destroyed then
				return
			end
			balanceQueued = true
			task.defer(function()
				balanceQueued = false
				if not manager.Destroyed then
					balance()
				end
			end)
		end
		local function clearPending(state)
			if pendingBounds[state] then
				pendingBounds[state] = nil
				manager.Counts.OmittedBounds -= 1
			end
		end
		local function releaseBounds(state)
			clearPending(state)
			if state.Bounds then
				state.Bounds:Destroy()
				state.Bounds = nil
				manager.Counts.Bounds -= 1
				queueBalance()
			end
		end
		local function requestBounds(state, target)
			if state.Bounds then
				return
			end
			if manager.Counts.Bounds >= maxBounds then
				if not pendingBounds[state] then
					pendingBounds[state] = target
					manager.Counts.OmittedBounds += 1
				end
				return
			end
			clearPending(state)
			local box = Instance.new("SelectionBox")
			box.Name = "SelectionBounds"
			box.Color3 = options.Color
			box.LineThickness = config.BoundsThickness or 0.02
			box.SurfaceTransparency = 1
			box.Transparency = 0
			box.Adornee = target
			box.Parent = parent
			state.Bounds = box
			manager.Counts.Bounds += 1
		end
		local function releaseHighlight(record)
			pendingHighlights[record] = nil
			if record.Highlight then
				record.Highlight:Destroy()
				record.Highlight = nil
				manager.Counts.Highlights -= 1
				queueBalance()
			end
		end
		local function requestHighlight(record, target)
			if record.Highlight then
				return
			end
			if manager.Counts.Highlights >= maxHighlights then
				pendingHighlights[record] = true
				return
			end
			pendingHighlights[record] = nil
			local highlight = Instance.new("Highlight")
			highlight.Name = "SelectionOutline"
			highlight.FillTransparency = 1
			highlight.OutlineTransparency = 0
			highlight.OutlineColor = options.Color
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = target or record.Object
			highlight.Parent = parent
			record.Highlight = highlight
			manager.Counts.Highlights += 1
		end
		local function queueReconcile()
			if reconcileQueued or manager.Destroyed then
				return
			end
			reconcileQueued = true
			task.defer(function()
				reconcileQueued = false
				if not manager.Destroyed then
					reconcile()
				end
			end)
		end
		local function updatePart(record, state)
			if manager.Destroyed or record.Destroyed or state.Destroyed then
				return
			end
			local hidden = invisible(state.Object)
			if hidden == state.Invisible then
				return
			end
			if hidden ~= state.Invisible then
				record.VisibleParts += (hidden and -1 or 1)
				record.HiddenParts += (hidden and 1 or -1)
				state.Invisible = hidden
			end
			updateRoot(record)
			if
				hidden
				and not record.PreparingMask
				and not (record.MaskActive and record.Mask and record.Mask.Entries[state.Object])
			then
				requestBounds(state, state.Object)
			else
				releaseBounds(state)
			end
		end
		local function removePart(record, part)
			local state = record.Parts[part]
			if not state then
				return
			end
			state.Destroyed = true
			if sharedOpacity[part] == record then sharedOpacity[part] = nil end
			if selectionPivot and record.Kind == "Model" then selectionPivot:RemovePart(record.Object, part) end
			record.Parts[part] = nil
			disconnect(state.Connections)
			if state.Invisible then
				record.HiddenParts -= 1
			else
				record.VisibleParts -= 1
			end
			if record.Mask then
				record.Mask:Remove(part)
			end
			releaseBounds(state)
			updateRoot(record)
		end
		local function watchPart(record, part)
			if not part:IsA("BasePart") or part:IsA("Terrain") or excluded(part) or record.Parts[part] then
				return
			end
			local state = { Object = part, Connections = {}, Invisible = invisible(part) }
			record.Parts[part] = state
			if selectionPivot and record.Kind == "Model" then selectionPivot:AddPart(record.Object, part) end
			if state.Invisible then
				record.HiddenParts += 1
			else
				record.VisibleParts += 1
			end
			if record.Mask then
				record.Mask:Add(part)
			end
			if opacityConnection and part == record.Object then
				sharedOpacity[part] = record
			else
				local function opacityChanged()
					updatePart(record, state)
				end
				bind(state.Connections, part:GetPropertyChangedSignal("Transparency"), opacityChanged)
				bind(state.Connections, part:GetPropertyChangedSignal("LocalTransparencyModifier"), opacityChanged)
			end
			if not record.Collecting then
				updateRoot(record)
				if state.Invisible and not record.PreparingMask and not record.MaskActive then
					requestBounds(state, part)
				end
			end
		end
		updateRoot = function(record)
			if manager.Destroyed or record.Destroyed or record.Kind == "Gui" or record.Group then
				return
			end
			local previousProblem = record.MaskUnavailable
			if record.Mask and record.Mask.Failed then
				record.MaskUnavailable = record.Mask.Problem
				record.Mask:Destroy()
				record.Mask = nil
			end
			if record.HiddenParts > 0 and not record.NativeOnly and config.GeometryMask and not record.Mask and not record.MaskUnavailable then
				local mask, problem = config.GeometryMask.Create(record.Parts, function()
					if not record.Destroyed then
						updateRoot(record)
					end
				end)
				record.Mask = mask
				record.MaskUnavailable = problem
			elseif (record.HiddenParts == 0 or record.NativeOnly) and record.Mask then
				record.Mask:Destroy()
				record.Mask = nil
			end
			if record.MaskUnavailable and record.MaskUnavailable ~= previousProblem then
				manager.LastGeometryProblem = record.MaskUnavailable
				if config.ReportFailure then
					config.ReportFailure(record.Object, record.MaskUnavailable)
				end
			end
			local maskReady = record.Mask and record.Mask.Ready and not record.Mask.Failed
			masks[record] = record.Mask
			local wasPreparing = record.PreparingMask
			record.PreparingMask = record.Mask ~= nil and not maskReady
			if record.PreparingMask then
				record.WantsHighlight = false
				record.RenderingMode = "PreparingGeometryMask"
				pendingHighlights[record] = nil
				if record.Highlight then
					record.Highlight.Enabled = false
				end
				releaseBounds(record)
				if not wasPreparing then
					for _, state in pairs(record.Parts) do
						releaseBounds(state)
					end
				end
				record.MaskActive = false
				record.MaskVersion = -1
				return
			end
			local want = record.VisibleParts > 0 or maskReady
			record.WantsHighlight = want
			if want then
				requestHighlight(record, maskReady and record.Mask.Model or record.Object)
			else
				releaseHighlight(record)
			end
			if record.Highlight then
				record.Highlight.Adornee = maskReady and record.Mask.Model or record.Object
				record.Highlight.Enabled = true
				record.RenderingMode = maskReady and "CombinedGeometryMask" or "PublicFallback"
				releaseBounds(record)
			else
				if record.VisibleParts > 0 then
					requestBounds(record, record.Object)
				else
					releaseBounds(record)
				end
			end
			local maskActive = not not (maskReady and record.Highlight)
			local maskVersion = record.Mask and record.Mask.Version or 0
			if record.MaskActive ~= maskActive or record.MaskVersion ~= maskVersion then
				record.MaskActive = maskActive
				record.MaskVersion = maskVersion
				for _, state in pairs(record.Parts) do
					if state.Invisible and not (maskActive and record.Mask.Entries[state.Object]) then
						requestBounds(state, state.Object)
					else
						releaseBounds(state)
					end
				end
			end
		end
		balance = function()
			for record in pairs(pendingGroups) do
				if manager.Counts.Bounds < maxBounds then
					pendingGroups[record] = nil
					manager.Counts.OmittedBounds -= 1
					manager.Counts.Bounds += 1
					record.Group:SetEnabled(true)
				end
			end
			for record in pairs(pendingHighlights) do
				if record.Destroyed or not record.WantsHighlight then
					pendingHighlights[record] = nil
				elseif manager.Counts.Highlights < maxHighlights then
					updateRoot(record)
				end
			end
			for state, target in pairs(pendingBounds) do
				if state.Destroyed then
					clearPending(state)
				elseif manager.Counts.Bounds < maxBounds then
					requestBounds(state, target)
				end
			end
		end
		local function style(record)
			if record.Group then
				record.Group:SetColor(options.Color)
			end
			if record.Highlight then
				record.Highlight.OutlineColor = options.Color
			end
			if record.Bounds then
				record.Bounds.Color3 = options.Color
			end
			if record.Parts then
				for _, state in pairs(record.Parts) do
					if state.Bounds then
						state.Bounds.Color3 = options.Color
					end
				end
			end
		end
		local dotRoots = {}
		local function stepMask(mask)
			local ok, problem = pcall(mask.Step, mask)
			if not ok then mask:Fail(problem) end
		end
		local function updateDots()
			local roots = dotRoots
			for _, mask in pairs(masks) do stepMask(mask) end
			if not selectionPivot then
				table.clear(roots)
				for _, record in pairs(manager.Records) do
					if record.Group then
						record.Group:Step()
						if record.Object.Parent and record.Group.Count > 0 then roots[#roots + 1] = record.Group end
					elseif record.Kind ~= "Gui" and record.Object.Parent then
						roots[#roots + 1] = record.Object
					end
				end
			end
			local dot = manager.PivotDot
			if not dot then
				return
			end
			local camera = workspace.CurrentCamera
			local ok, position, onScreen = pcall(function()
				if not camera or #roots == 0 then
					return nil, false
				end
				local pivot
				if selectionPivot then
					pivot = selectionPivot:Get(config.PivotSpace())
				elseif #roots == 1 then
					pivot = roots[1]:GetPivot()
				elseif config.SelectionPivot then
					pivot = config.SelectionPivot(roots)
				end
				if not pivot then
					return nil, false
				end
				return camera:WorldToScreenPoint(pivot.Position)
			end)
			local visible = ok and position ~= nil and onScreen and position.Z > 0
			if dot.Visible ~= visible then
				dot.Visible = visible
			end
			if visible then
				local nextPosition = UDim2.fromOffset(math.floor(position.X + 0.5), math.floor(position.Y + 0.5))
				if dot.Position ~= nextPosition then
					dot.Position = nextPosition
				end
			end
		end
		local function updateFrame()
			if selectionPivot then
				selectionPivot:Destroy()
				selectionPivot = nil
			end
			if config.CreateSelectionPivot and manager.Counts.Roots >= 32 then
				table.clear(dotRoots)
				for _, record in pairs(manager.Records) do
					if record.Group then
						table.clear(dotRoots)
						break
					elseif record.Kind ~= "Gui" and record.Object.Parent then
						dotRoots[#dotRoots + 1] = record.Object
					end
				end
				if #dotRoots >= 32 then
					selectionPivot = config.CreateSelectionPivot(dotRoots, manager.Records)
				end
			end
			local needed = false
			for _, record in pairs(manager.Records) do
				if record.Kind ~= "Gui" then
					needed = true
					break
				end
			end
			if needed and not manager.PivotDot then
				local dot = Instance.new("Frame")
				dot.Name = "SelectionDot"
				dot.Size = UDim2.fromOffset(3, 3)
				dot.BackgroundColor3 = Color3.new(1, 1, 1)
				dot.BorderColor3 = Color3.new(0, 0, 0)
				dot.BorderSizePixel = 1
				dot.Selectable = false
				dot.Active = false
				dot.Visible = false
				dot.Parent = parent
				manager.PivotDot = dot
			elseif not needed then
				destroy(manager.PivotDot)
				manager.PivotDot = nil
				table.clear(dotRoots)
			end
			if needed and not frameConnection then
				frameConnection = service.RunService.RenderStepped:Connect(updateDots)
			elseif not needed and frameConnection then
				frameConnection:Disconnect()
				frameConnection = nil
			end
			if needed then
				updateDots()
			end
		end
		local function addRecord(object, nativeOnly, descendants)
			local record = {
				Object = object,
				NativeOnly = nativeOnly,
				Connections = {},
				Kind = object:IsA("GuiObject") and "Gui" or object:IsA("Model") and "Model" or "Part",
			}
			manager.Records[object] = record
			manager.Counts.Roots += 1
			if largeGroups[object] then
				record.Group = createGroupBounds(object, parent, options.Color, workspace, excluded, descendants, groupOwners)
				groupCount += 1
				if not groupConnection then
					groupConnection = game.ItemChanged:Connect(function(part, property)
						local group = groupOwners[part]
						if group then group:PropertyChanged(part, property) end
					end)
				end
				if manager.Counts.Bounds < maxBounds then
					manager.Counts.Bounds += 1
				else
					record.Group:SetEnabled(false)
					pendingGroups[record] = true
					manager.Counts.OmittedBounds += 1
				end
				record.RenderingMode = "GroupBounds"
			elseif record.Kind == "Gui" then
				if config.AttachGui then
					record.Gui, record.GuiCleanup = config.AttachGui(object, parent)
				end
			else
				record.Parts = {}
				record.VisibleParts = 0
				record.HiddenParts = 0
				record.Collecting = true
				if record.Kind == "Part" then
					watchPart(record, object)
				end
				for _, part in ipairs(descendants or object:GetDescendants()) do
					watchPart(record, part)
				end
				record.Collecting = false
				record.BelowGroupLimit = descendants ~= nil and record.Kind == "Model"
				bind(record.Connections, object.DescendantAdded, function(part)
					if record.BelowGroupLimit and part:IsA("BasePart") then record.BelowGroupLimit = false end
					watchPart(record, part)
				end)
				bind(record.Connections, object.DescendantRemoving, function(part)
					removePart(record, part)
				end)
				updateRoot(record)
			end
			return record
		end
		removeRecord = function(record)
			if record.Destroyed then
				return
			end
			record.Destroyed = true
			masks[record] = nil
			sharedOpacity[record.Object] = nil
			manager.Records[record.Object] = nil
			manager.Counts.Roots -= 1
			disconnect(record.Connections)
			if record.Group then
				record.Group:Destroy()
				groupCount -= 1
				if groupCount == 0 then
					groupConnection:Disconnect()
					groupConnection = nil
				end
				if pendingGroups[record] then
					pendingGroups[record] = nil
					manager.Counts.OmittedBounds -= 1
				else
					manager.Counts.Bounds -= 1
				end
				queueBalance()
			end
			if record.Parts then
				for _, state in pairs(record.Parts) do
					state.Destroyed = true
					disconnect(state.Connections)
					releaseBounds(state)
				end
				table.clear(record.Parts)
			end
			releaseHighlight(record)
			releaseBounds(record)
			if record.Mask then
				record.Mask:Destroy()
				record.Mask = nil
			end
			if type(record.GuiCleanup) == "function" then
				record.GuiCleanup()
			elseif record.GuiCleanup and record.GuiCleanup.Destroy then
				record.GuiCleanup.Destroy()
			end
			destroy(record.Gui)
		end
		reconcile = function()
			if manager.Destroyed then
				return
			end
			local expanded, folders, seen, folderMembers = {}, {}, {}, {}
			local descendants = {}
			local function append(object, fromFolder)
				if fromFolder then
					folderMembers[object] = true
				end
				if not seen[object] then
					seen[object] = true
					expanded[#expanded + 1] = object
				end
			end
			for _, object in ipairs(selection) do
				if object == workspace then continue end
				local existing = manager.Records[object]
				if options.PartEnabled and not largeGroups[object] and not (existing and existing.BelowGroupLimit)
					and (object:IsA("Folder") or object:IsA("Model")) then
					local children = object:GetDescendants()
					if needsGroupBounds(object, children) then largeGroups[object] = true end
					if existing and existing.Kind == "Model" and not largeGroups[object] then existing.BelowGroupLimit = true end
					if not manager.Records[object] and (largeGroups[object] or object:IsA("Model")) then
						descendants[object] = children
					end
				end
				if options.PartEnabled and largeGroups[object] then
					append(object)
				elseif object:IsA("Folder") then
					if options.PartEnabled then
						folders[object] = true
					end
				else
					append(object)
				end
			end
			local folderQueue = {}
			for folder in pairs(folders) do
				folderQueue[#folderQueue + 1] = folder
			end
			local index = 1
			while index <= #folderQueue do
				local folder = folderQueue[index]
				index += 1
				for _, object in ipairs(folder:GetChildren()) do
					if object:IsA("Folder") then
						if not folders[object] then
							folders[object] = true
							folderQueue[#folderQueue + 1] = object
						end
					elseif object:IsA("BasePart") or object:IsA("Model") then
						append(object, true)
					end
				end
			end
			for folder, record in pairs(manager.Folders) do
				if not folders[folder] then
					disconnect(record.Connections)
					manager.Folders[folder] = nil
				end
			end
			for folder in pairs(folders) do
				if not manager.Folders[folder] then
					local record = { Connections = {} }
					manager.Folders[folder] = record
					bind(record.Connections, folder.ChildAdded, queueReconcile)
					bind(record.Connections, folder.ChildRemoved, queueReconcile)
					bind(record.Connections, folder.AncestryChanged, queueReconcile)
				end
			end
			local wanted, spatialCandidates = {}, {}
			for _, object in ipairs(expanded) do
				if options.PartEnabled and spatial(object) then
					spatialCandidates[object] = true
				end
			end
			for _, object in ipairs(expanded) do
				if spatialCandidates[object] then
					local ancestor = object.Parent
					while ancestor and not spatialCandidates[ancestor] do
						ancestor = ancestor.Parent
					end
					if not ancestor then
						wanted[object] = true
					end
				elseif
					options.GuiEnabled
					and object.Parent
					and object:IsA("GuiObject")
					and not excluded(object)
					and not (config.HandlesGui and config.HandlesGui(object))
				then
					wanted[object] = true
				end
			end
			for object, record in pairs(manager.Records) do
				if not wanted[object] or (largeGroups[object] and not record.Group) then
					removeRecord(record)
				end
			end
			if #expanded >= 32 and not opacityConnection then
				local ok, connection = pcall(function()
					return game.ItemChanged:Connect(function(object, key)
						if key == "Transparency" or key == "LocalTransparencyModifier" then
							local record = sharedOpacity[object]
							if record then updatePart(record, record.Parts[object]) end
						end
					end)
				end)
				if ok then opacityConnection = connection end
			end
			for _, object in ipairs(expanded) do
				if wanted[object] then
					local nativeOnly = folderMembers[object] == true
					local record = manager.Records[object]
					if not record then
						record = addRecord(object, nativeOnly, descendants[object])
					elseif record.NativeOnly ~= nativeOnly then
						record.NativeOnly = nativeOnly
						updateRoot(record)
					end
					if record.Color ~= options.Color then
						style(record)
						record.Color = options.Color
					end
				end
			end
			if opacityConnection and not next(sharedOpacity) then
				opacityConnection:Disconnect()
				opacityConnection = nil
			end
			balance()
			updateFrame()
		end
		function manager:Update(objects, settings)
			if self.Destroyed then
				return
			end
			selection = table.clone(objects or {})
			local selected = {}
			for _, object in ipairs(selection) do
				selected[object] = true
				if not selectionWatches[object] then
					selectionWatches[object] = object.AncestryChanged:Connect(queueReconcile)
				end
			end
			for object, connection in pairs(selectionWatches) do
				if not selected[object] then
					largeGroups[object] = nil
					connection:Disconnect()
					selectionWatches[object] = nil
				end
			end
			settings = settings or {}
			options.PartEnabled = settings.PartEnabled ~= false
			options.GuiEnabled = settings.GuiEnabled ~= false
			options.Color = settings.Color or Color3.fromRGB(0, 170, 255)
			reconcile()
		end
		function manager:Destroy()
			if opacityConnection then
				opacityConnection:Disconnect()
				opacityConnection = nil
			end
			if selectionPivot then
				selectionPivot:Destroy()
				selectionPivot = nil
			end
			table.clear(dotRoots)
			if self.Destroyed then
				return
			end
			self.Destroyed = true
			if frameConnection then
				frameConnection:Disconnect()
				frameConnection = nil
			end
			destroy(self.PivotDot)
			self.PivotDot = nil
			for _, record in pairs(self.Records) do
				removeRecord(record)
			end
			for _, record in pairs(self.Folders) do
				disconnect(record.Connections)
			end
			for _, connection in pairs(selectionWatches) do
				connection:Disconnect()
			end
			table.clear(selectionWatches)
			table.clear(largeGroups)
			table.clear(self.Folders)
			table.clear(pendingBounds)
			table.clear(pendingHighlights)
			table.clear(pendingGroups)
			table.clear(selection)
			self.Counts.OmittedBounds = 0
		end
		if Main and Main.AddCleanup then
			Main.AddCleanup(function()
				manager:Destroy()
			end)
		end
		return manager
	end
	return Renderer
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
