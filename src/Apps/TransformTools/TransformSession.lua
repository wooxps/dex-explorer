--!strict

local Apps, Main

------------------------------ Initialization ------------------------------

local function InitDeps(deps)
	Apps, Main = deps.Apps, deps.Main
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Transform = { MinimumSize = 0.001 }
	local axisNames = { "X", "Y", "Z" }
	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	local function vectorFinite(value)
		return value and finite(value.X) and finite(value.Y) and finite(value.Z)
	end
	local function excluded(object)
		local explorer = Apps.Explorer
		return Main and Main.IsDexGuiObject and Main.IsDexGuiObject(object)
			or explorer and explorer.IsReadOnlyInferenceObject and explorer.IsReadOnlyInferenceObject(object)
	end
	local function geometry(object)
		if object:IsA("BasePart") then
			return { object }
		end
		local result = {}
		for _, child in ipairs(object:GetDescendants()) do
			if child:IsA("BasePart") and not child:IsA("Terrain") then
				result[#result + 1] = child
			end
		end
		return result
	end
	local function eligible(object, modelParts)
		if
			typeof(object) ~= "Instance"
			or not (object:IsA("BasePart") or object:IsA("Model"))
			or object:IsA("Terrain")
			or not object:IsDescendantOf(workspace)
			or excluded(object)
		then
			return false
		end
		if object:IsA("BasePart") then return not object.Locked end
		local parts = geometry(object)
		if modelParts then modelParts[object] = parts end
		if #parts == 0 then
			return false
		end
		for _, part in ipairs(parts) do
			if part.Locked or excluded(part) then
				return false
			end
		end
		return true
	end
	function Transform.Collect(objects, modelParts)
		local candidates, seen = {}, {}
		for _, value in ipairs(objects or {}) do
			local object = typeof(value) == "Instance" and value or type(value) == "table" and value.Obj
			if object and not seen[object] and eligible(object, modelParts) then
				seen[object] = true
				candidates[#candidates + 1] = object
			end
		end
		local roots = {}
		for _, object in ipairs(candidates) do
			local parent = object.Parent
			while parent and not seen[parent] do
				parent = parent.Parent
			end
			if not parent then
				roots[#roots + 1] = object
			end
		end
		return roots
	end
	local function selectionOrientation(roots, space)
		if space ~= "World" then
			local reference = space == "Scale" and roots[1]:IsA("BasePart") and roots[1].CFrame or roots[1]:GetPivot()
			return reference - reference.Position
		end
		return nil
	end
	local function extents(roots, first, last, toLocal)
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		for i = first, last do
			local root = roots[i]
			local cf, size
			if root:IsA("Model") then
				cf, size = root:GetBoundingBox()
			else
				cf, size = root.CFrame, root.Size
			end
			if toLocal then
				cf = toLocal * cf
			end
			local x, y, z, xx, xy, xz, yx, yy, yz, zx, zy, zz = cf:GetComponents()
			local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
			local ex = math.abs(xx) * hx + math.abs(xy) * hy + math.abs(xz) * hz
			local ey = math.abs(yx) * hx + math.abs(yy) * hy + math.abs(yz) * hz
			local ez = math.abs(zx) * hx + math.abs(zy) * hy + math.abs(zz) * hz
			minX, minY, minZ = math.min(minX, x - ex), math.min(minY, y - ey), math.min(minZ, z - ez)
			maxX, maxY, maxZ = math.max(maxX, x + ex), math.max(maxY, y + ey), math.max(maxZ, z + ez)
		end
		return minX, minY, minZ, maxX, maxY, maxZ
	end
	function Transform.Bounds(roots, space)
		if not roots or #roots == 0 then
			return nil
		end
		local orientation = selectionOrientation(roots, space)
		local minX, minY, minZ, maxX, maxY, maxZ = extents(roots, 1, #roots, orientation and orientation:Inverse())
		local center = CFrame.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
		if orientation then
			center = orientation * center
		end
		local pivot = #roots == 1 and roots[1]:GetPivot() or center
		if space == "Scale" then
			pivot = CFrame.new(pivot.Position) * orientation
		end
		if space == "World" then
			pivot = CFrame.new(pivot.Position)
		end
		return center, Vector3.new(maxX - minX, maxY - minY, maxZ - minZ), pivot
	end
	function Transform.CreateSelectionPivot(roots, records, groups)
		local membership, modelOf = {}, {}
		local moving, movingSlots = {}, {}
		local changed = true
		local tracker = {}
		local function build(first, last, parent)
			local block = { First = first, Last = last, Parent = parent, Dirty = true }
			if last - first < 4 then
				for i = first, last do membership[roots[i]] = block end
			else
				local step = math.ceil((last - first + 1) / 8)
				for i = first, last, step do
					block[#block + 1] = build(i, math.min(i + step - 1, last), block)
				end
			end
			return block
		end
		local top = build(1, #roots)
		local function dirty(block)
			changed = true
			while block and not block.Dirty do
				block.Dirty = true
				block = block.Parent
			end
		end
		function tracker:InvalidateRoot(root)
			local block = membership[root]
			if block then dirty(block) end
		end
		local function trackMotion(part, enabled)
			local slot = movingSlots[part]
			if enabled and not slot then
				moving[#moving + 1] = { Part = part, Pose = part.CFrame, Block = membership[part] }
				movingSlots[part] = #moving
			elseif slot and not enabled then
				local last = #moving
				local tail = moving[last]
				moving[slot] = tail
				movingSlots[tail.Part] = slot
				moving[last], movingSlots[part] = nil, nil
			end
		end
		function tracker:AddPart(root, part)
			local block = membership[root]
			if not block then return end
			membership[part] = block
			if root ~= part then modelOf[part] = root end
			trackMotion(part, not part.Anchored)
			dirty(block)
		end
		function tracker:RemovePart(root, part)
			local block = membership[part]
			if not block or modelOf[part] ~= root then return end
			dirty(block)
			trackMotion(part, false)
			membership[part], modelOf[part] = nil, nil
		end
		for _, root in ipairs(roots) do
			-- The renderer tracks each group as a single bounding box.
			if groups and groups[root] then continue end
			if root:IsA("Model") then
				for part in pairs(records[root].Parts) do tracker:AddPart(root, part) end
			else
				tracker:AddPart(root, root)
			end
		end
		local ok, connection = pcall(function()
			return game.ItemChanged:Connect(function(part, property)
				local block = membership[part]
				if not block then return end
				if property == "Anchored" then
					trackMotion(part, not part.Anchored)
				elseif property ~= "CFrame" and property ~= "Size" and property ~= "PivotOffset"
					and property ~= "WorldPivot" and property ~= "PrimaryPart"
					and property ~= "Position" and property ~= "Orientation" and property ~= "Rotation" then
					return
				end
				dirty(block)
			end)
		end)
		if not ok then return nil end
		local previousSpace, previousOrientation, pivot
		local rebuildTree = false
		local function measure(block, toLocal, rotated)
			if not rotated and not block.Dirty then return end
			if #block == 0 then
				block.X, block.Y, block.Z, block.MaxX, block.MaxY, block.MaxZ =
					extents(roots, block.First, block.Last, toLocal)
			else
				local x, y, z = math.huge, math.huge, math.huge
				local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
				for _, child in ipairs(block) do
					measure(child, toLocal, rotated)
					x, y, z = math.min(x, child.X), math.min(y, child.Y), math.min(z, child.Z)
					maxX, maxY, maxZ = math.max(maxX, child.MaxX), math.max(maxY, child.MaxY), math.max(maxZ, child.MaxZ)
				end
				block.X, block.Y, block.Z = x, y, z
				block.MaxX, block.MaxY, block.MaxZ = maxX, maxY, maxZ
			end
			block.Dirty = false
		end
		function tracker:Get(space)
			local moved = 0
			for _, entry in ipairs(moving) do
				local pose = entry.Part.CFrame
				if pose ~= entry.Pose then
					entry.Pose = pose
					moved += 1
					changed = true
					if not rebuildTree and moved < #roots / 4 then dirty(entry.Block) end
				end
			end
			if not changed and space == previousSpace then return pivot end
			local orientation = selectionOrientation(roots, space)
			local toLocal = orientation and orientation:Inverse()
			if moved >= #roots / 4 then
				top.X, top.Y, top.Z, top.MaxX, top.MaxY, top.MaxZ = extents(roots, 1, #roots, toLocal)
			else
				measure(top, toLocal, orientation ~= previousOrientation or rebuildTree)
			end
			-- A full scan bypasses the child bounds. Refresh them on the next sparse update.
			rebuildTree = moved >= #roots / 4
			pivot = CFrame.new((top.X + top.MaxX) * 0.5, (top.Y + top.MaxY) * 0.5, (top.Z + top.MaxZ) * 0.5)
			if orientation then pivot = orientation * pivot end
			previousSpace, previousOrientation, changed = space, orientation, false
			return pivot
		end
		function tracker:Destroy()
			connection:Disconnect()
		end
		return tracker
	end
	function Transform.Snap(value, increment)
		if not finite(value) then
			return 0
		end
		if not finite(increment) or increment <= 0 then
			return value
		end
		return math.floor(value / increment + 0.5) * increment
	end
	function Transform.RayPlane(origin, direction, point, normal)
		local denominator = direction:Dot(normal)
		if math.abs(denominator) < 1e-7 then
			return nil
		end
		local distance = (point - origin):Dot(normal) / denominator
		if distance < 0 then
			return nil
		end
		return origin + direction * distance
	end
	function Transform.RayAxis(origin, direction, point, axis)
		local rayLength = direction.Magnitude
		local axisLength = axis.Magnitude
		if rayLength < 1e-7 or axisLength < 1e-7 then
			return nil
		end
		local ray = direction / rayLength
		local unit = axis / axisLength
		local separation = origin - point
		local alignment = ray:Dot(unit)
		local denominator = 1 - alignment * alignment
		if denominator < 1e-6 then
			return nil
		end
		return (separation:Dot(unit) - separation:Dot(ray) * alignment) / denominator
	end
	local function snapshot(object)
		if object:IsA("Model") then
			return { Pivot = object:GetPivot(), Scale = object:GetScale() }
		end
		return { CFrame = object.CFrame, Size = object.Size, PivotOffset = object.PivotOffset }
	end
	local function apply(object, state)
		if object:IsA("Model") then
			if object:GetScale() ~= state.Scale then
				object:ScaleTo(state.Scale)
			end
			object:PivotTo(state.Pivot)
		else
			if object.Size ~= state.Size then
				object.Size = state.Size
			end
			if object.PivotOffset ~= state.PivotOffset then
				object.PivotOffset = state.PivotOffset
			end
			object.CFrame = state.CFrame
		end
	end
	local function same(a, b)
		return a.CFrame == b.CFrame
			and a.Size == b.Size
			and a.PivotOffset == b.PivotOffset
			and a.Pivot == b.Pivot
			and a.Scale == b.Scale
	end
	function Transform.Begin(objects, tool, pivot, boundsSize)
		local roots = Transform.Collect(objects)
		if #roots == 0 then
			return nil, "Select an unlocked part or model in Workspace."
		end
		local bounds, measuredSize, measuredPivot = Transform.Bounds(roots, tool == "Scale" and "Scale" or "Local")
		pivot = pivot or measuredPivot
		boundsSize = boundsSize or measuredSize
		local records = {}
		local minimumFactor = 0
		local maximumFactor = math.huge
		local hasModel = false
		for _, object in ipairs(roots) do
			local parts = geometry(object)
			for _, part in ipairs(parts) do
				minimumFactor =
					math.max(minimumFactor, Transform.MinimumSize / math.min(part.Size.X, part.Size.Y, part.Size.Z))
				maximumFactor = math.min(maximumFactor, 2048 / math.max(part.Size.X, part.Size.Y, part.Size.Z))
			end
			hasModel = hasModel or object:IsA("Model")
			records[#records + 1] = { Object = object, Before = snapshot(object) }
		end
		local session = {
			Roots = roots,
			Pivot = pivot,
			Bounds = bounds,
			Size = boundsSize,
			Tool = tool,
			Active = true,
			Uniform = hasModel or #roots > 1,
		}
		local function restore()
			local errors = {}
			for index = #records, 1, -1 do
				local record = records[index]
				local ok, problem = pcall(apply, record.Object, record.Before)
				if not ok then
					errors[#errors + 1] = tostring(problem)
				end
			end
			return #errors == 0, table.concat(errors, "; ")
		end
		local function preview(callback)
			if not session.Active then
				return false, "Gesture has ended."
			end
			local ok, problem = pcall(function()
				for _, record in ipairs(records) do
					if not record.Object:IsDescendantOf(workspace) then
						error("A selected object left Workspace.", 0)
					end
					callback(record.Object, record.Before)
				end
			end)
			if not ok then
				session.Active = false
				restore()
				return false, tostring(problem)
			end
			return true
		end
		function session:Move(delta)
			if not vectorFinite(delta) then
				return false, "Invalid movement."
			end
			return preview(function(object, before)
				if before.Pivot then
					object:PivotTo(before.Pivot + delta)
				else
					object.CFrame = before.CFrame + delta
				end
			end)
		end
		function session:Rotate(axis, angle)
			if not vectorFinite(axis) or axis.Magnitude < 1e-7 or not finite(angle) then
				return false, "Invalid rotation."
			end
			local delta = CFrame.new(pivot.Position)
				* CFrame.fromAxisAngle(axis.Unit, angle)
				* CFrame.new(-pivot.Position)
			return preview(function(object, before)
				if before.Pivot then
					object:PivotTo(delta * before.Pivot)
				else
					object.CFrame = delta * before.CFrame
				end
			end)
		end
		function session:Scale(axisIndex, distance, centered, uniform, faceSign)
			if not finite(distance) then
				return false, "Invalid scale."
			end
			axisIndex = axisIndex or 1
			if not axisNames[axisIndex] then
				return false, "Invalid scale axis."
			end
			faceSign = faceSign == -1 and -1 or 1
			local axis = axisNames[axisIndex]
			local unit = Vector3.new(axisIndex == 1 and 1 or 0, axisIndex == 2 and 1 or 0, axisIndex == 3 and 1 or 0)
			local span = math.max(boundsSize[axis], Transform.MinimumSize)
			local multiplier = centered and 2 or 1
			local factor = math.clamp(1 + distance * multiplier / span, minimumFactor, maximumFactor)
			local isUniform = uniform or self.Uniform
			if isUniform then
				local anchor = centered and pivot.Position
					or bounds.Position - pivot:VectorToWorldSpace(unit) * (span * 0.5 * faceSign)
				return preview(function(object, before)
					local cf = before.Pivot or before.CFrame
					local target = cf + (anchor + (cf.Position - anchor) * factor - cf.Position)
					if before.Pivot then
						object:ScaleTo(before.Scale * factor)
						object:PivotTo(target)
					else
						object.Size = before.Size * factor
						if before.PivotOffset then
							object.PivotOffset = before.PivotOffset + (before.PivotOffset.Position * (factor - 1))
						end
						object.CFrame = target
					end
				end)
			end
			local before = records[1].Before
			local worldAxis = pivot:VectorToWorldSpace(unit)
			local localAxis = before.CFrame:VectorToObjectSpace(worldAxis)
			local absolute = { math.abs(localAxis.X), math.abs(localAxis.Y), math.abs(localAxis.Z) }
			local partAxis = 1
			for i = 2, 3 do
				if absolute[i] > absolute[partAxis] then
					partAxis = i
				end
			end
			local property = axisNames[partAxis]
			local component = localAxis[property] >= 0 and 1 or -1
			local newLength = math.clamp(before.Size[property] + distance * multiplier, Transform.MinimumSize, 2048)
			local change = newLength - before.Size[property]
			local ratio = newLength / before.Size[property]
			local dimensions = { before.Size.X, before.Size.Y, before.Size.Z }
			dimensions[partAxis] = newLength
			local partUnit = Vector3.new(partAxis == 1 and 1 or 0, partAxis == 2 and 1 or 0, partAxis == 3 and 1 or 0)
			local customPivot = before.CFrame:PointToObjectSpace(pivot.Position)
			local displacement = centered and customPivot[property] * (1 - ratio) or change * 0.5 * faceSign * component
			local offset = partUnit * displacement
			return preview(function(object)
				object.Size = Vector3.new(dimensions[1], dimensions[2], dimensions[3])
				if before.PivotOffset then
					object.PivotOffset = before.PivotOffset
						+ partUnit * (before.PivotOffset.Position[property] * (ratio - 1))
				end
				object.CFrame = before.CFrame * CFrame.new(offset)
			end)
		end
		function session:Cancel()
			if not self.Active then
				return false
			end
			self.Active = false
			return restore()
		end
		function session:Commit()
			if not self.Active then
				return false, "Gesture has ended."
			end
			local changes = {}
			local ok, problem = pcall(function()
				for _, record in ipairs(records) do
					if not record.Object:IsDescendantOf(workspace) then
						error("A selected object left Workspace.", 0)
					end
					local after = snapshot(record.Object)
					if not same(record.Before, after) then
						changes[#changes + 1] = { Object = record.Object, Before = record.Before, After = after }
					end
				end
			end)
			if not ok then
				self.Active = false
				restore()
				return false, tostring(problem)
			end
			self.Active = false
			if #changes == 0 then
				return true, false
			end
			ok, problem = pcall(Apps.History.Run, tool or "Transform", function()
				for _, change in ipairs(changes) do
					local object = change.Object
					Apps.History.Record(function()
						return snapshot(object)
					end, function(value)
						apply(object, value)
					end, change.Before, change.After)
				end
			end)
			if not ok then
				restore()
				return false, tostring(problem)
			end
			Apps.History.Focused = true
			return true, true
		end
		return session
	end
	return Transform
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
