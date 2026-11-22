--!strict

local Main, Lib, Apps, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, service = d.Main, d.Lib, d.Apps, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Tools = {
		Enabled = true,
		Tool = "Select",
		Space = "Local",
		MoveSnap = 1,
		RotateSnap = 15,
		ScaleSnap = 1,
		Snapping = false,
		Dragging = false,
	}
	local hotspotFolder, hotspotBox, hotspotSize
	local gui, bar, options, readout, gizmo, frameConnection
	local roots = {}
	local selectionConnections = {}
	local drag, hover
	local buttons, buttonHovers = {}, {}
	local destroyed = false
	local toolbarDrag
	local lastCamera, lastViewport, lastPointer, lastPivot, lastSize, lastFOV, lastCameraObject, lastTickDegrees
	local boundsDirty = true
	local cachedBox, cachedSize, cachedPivot
	local refreshQueued = false
	local restoringSelection = false
	local refresh, render, finish, updateButtons, updateFrameBinding
	local actionName = "DexPlusTransform_" .. tostring(math.floor(os.clock() * 1000000))
	local axes = { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }
	local input = service.UserInputService
	local function guiActive()
		return Apps.GuiTransformTools and Apps.GuiTransformTools.IsActive()
	end
	local function gestureActive()
		return drag ~= nil or Tools.GuiDragging
	end
	local function altDown()
		return input:IsKeyDown(Enum.KeyCode.LeftAlt) or input:IsKeyDown(Enum.KeyCode.RightAlt)
	end
	local function checked(ok, problem)
		if not ok then
			error(problem or "Transform failed", 0)
		end
	end
	local function node(class, props)
		local object = Instance.new(class)
		for key, value in pairs(props) do
			object[key] = value
		end
		return object
	end
	local function report(problem)
		Tools.LastError = tostring(problem)
		if readout then
			readout.Text = Tools.LastError
			readout.Visible = true
		end
		warn("[Dex Explorer] Transform: " .. Tools.LastError)
	end
	local function point(position)
		return Vector2.new(position.X, position.Y)
	end
	local function inset()
		local ok, value = pcall(function()
			return service.GuiService:GetGuiInset()
		end)
		return ok and value or Vector2.new(0, 0)
	end
	local function mousePoint()
		local value = input:GetMouseLocation()
		local offset = inset()
		return Vector2.new(value.X - offset.X, value.Y - offset.Y)
	end
	local function worldAxis(cf, index)
		return cf:VectorToWorldSpace(axes[index])
	end
	local function overUI(position)
		if bar and bar.Visible then
			local offset = inset()
			local x, y = position.X + offset.X, position.Y + offset.Y
			for _, object in ipairs({ bar, options }) do
				if object and object.Visible then
					local p, s = object.AbsolutePosition, object.AbsoluteSize
					if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
						return true
					end
				end
			end
		end
		return Main.IsPointInDexUI and Main.IsPointInDexUI(position.X, position.Y)
	end
	function Tools.IsToolbarPoint(position)
		if not bar or not bar.Visible then
			return false
		end
		local offset = inset()
		local x, y = position.X + offset.X, position.Y + offset.Y
		for _, object in ipairs({ bar, options }) do
			if object and object.Visible then
				local p, s = object.AbsolutePosition, object.AbsoluteSize
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
					return true
				end
			end
		end
		return false
	end
	local function ray(camera, position)
		local r = camera:ScreenPointToRay(position.X, position.Y)
		return r.Origin, r.Direction.Unit
	end
	local function snapped(value, step)
		local enabled = Tools.Snapping and not Lib.IsShiftDown() and (not Tools.EditingPivot or Tools.Tool == "Rotate")
		return enabled and Apps.TransformSession.Snap(value, step) or value
	end
	local function releaseConnections()
		for _, connection in ipairs(selectionConnections) do
			connection:Disconnect()
		end
		table.clear(selectionConnections)
	end
	local function bounds()
		if boundsDirty then
			cachedBox, cachedSize, cachedPivot =
				Apps.TransformSession.Bounds(roots, Tools.Tool == "Scale" and "Scale" or Tools.Space)
			if Tools.EditingPivot and #roots == 1 then
				local pivot = roots[1]:GetPivot()
				cachedPivot = if Tools.Space == "World" then CFrame.new(pivot.Position) else pivot
				cachedBox = cachedPivot
			end
			boundsDirty = false
		end
		return cachedBox, cachedSize, cachedPivot
	end
	local function setReadout(text)
		readout.Text = text or ""
		readout.Visible = text ~= nil
	end
	local measuredText, measuredFont, measuredWidth
	local function positionReadout(camera, box)
		if not drag or not readout.Visible then
			return
		end
		local h = drag.Handle
		local anchor = box.Position
		if h.Kind == "Axis" then
			anchor = h.Start + (h.Finish - h.Start) * (drag.GrabFraction or 0.65)
		elseif h.Kind == "Rotate" and h.DragStart then
			local radial = CFrame.fromAxisAngle(drag.Axis, (h.DragAngle or 0) * 0.5):VectorToWorldSpace(h.DragStart)
			anchor = drag.Center + radial * (h.Radius * 1.2)
		end
		local projected = camera:WorldToScreenPoint(anchor)
		if projected.Z <= 0 then
			readout.Visible = false
			return
		end
		if measuredText ~= readout.Text or measuredFont ~= Lib.StudioFont then
			measuredText, measuredFont = readout.Text, Lib.StudioFont
			measuredWidth = service.TextService:GetTextSize(measuredText, 13, measuredFont, Vector2.new(1000, 30)).X
				+ 10
		end
		local width = measuredWidth
		local nextSize = UDim2.fromOffset(math.max(28, width), 20)
		if readout.Size ~= nextSize then
			readout.Size = nextSize
		end
		local offset = inset()
		local nextPosition = UDim2.fromOffset(
			math.floor(projected.X + offset.X + 0.5),
			math.floor(projected.Y + offset.Y + (h.Kind == "Axis" and 24 or 0) + 0.5)
		)
		if readout.Position ~= nextPosition then
			readout.Position = nextPosition
		end
	end
	finish = function(cancel)
		if not drag then
			return
		end
		local current = drag
		drag = nil
		Tools.Dragging = false
		local ok, problem = pcall(function()
			if cancel then
				current.Session:Cancel()
			else
				checked(current.Session:Commit())
			end
		end)
		if not ok then
			pcall(function()
				current.Session:Cancel()
			end)
			report(problem)
		end
		if Main.SetGameInputLocked then
			Main.SetGameInputLocked(current.PreviousLock)
		end
		Apps.History.Focused = true
		if ok then
			setReadout(nil)
		end
		hover = nil
		lastPivot = nil
		if not destroyed then
			refresh()
		end
	end
	local function beginDrag(handle, position)
		if gestureActive() or guiActive() or toolbarDrag or not handle or #roots == 0 then
			return false
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return false
		end
		local box, size, pivot = bounds()
		if not box then
			return false
		end
		local ok, session, problem
		if Tools.EditingPivot then
			ok, session, problem = pcall(Apps.TransformSession.BeginPivot, roots, function()
				return Tools.Snapping and not Lib.IsShiftDown()
			end)
		else
			ok, session, problem = pcall(Apps.TransformSession.Begin, roots, Tools.Tool, pivot or box, size)
		end
		if not ok or not session then
			report(problem or session)
			return false
		end
		local origin, direction = ray(camera, position)
		local axis = handle.AxisVector or handle.Axis and worldAxis(box, handle.Axis)
		local center = (pivot or box).Position
		local planeNormal = handle.Kind == "Plane" and worldAxis(box, handle.Axis) or camera.CFrame.LookVector
		local start
		if handle.Kind == "Rotate" then
			start = Apps.TransformSession.RayPlane(origin, direction, center, axis)
			if start and (start - center).Magnitude < 1e-5 then
				start = nil
			end
			if math.abs(direction:Dot(axis)) < 0.15 and handle.HitVector then
				start = center + handle.HitVector
			end
		elseif handle.Kind == "Axis" or handle.Kind == "Scale" then
			start = Apps.TransformSession.RayAxis(origin, direction, center, axis)
		else
			start = Apps.TransformSession.RayPlane(origin, direction, center, planeNormal)
		end
		if start == nil then
			session:Cancel()
			return false
		end
		drag = {
			Session = session,
			Handle = handle,
			Box = box,
			Size = size,
			Pivot = pivot or box,
			Axis = axis,
			Center = center,
			Normal = planeNormal,
			Start = start,
			Pointer = position,
			PreviousLock = Main.GameInputLocked,
			Angle = 0,
			PreviousAngle = 0,
			Camera = camera,
		}
		drag.Selection = table.clone(Apps.Explorer.Selection.List)
		if handle.Kind == "Rotate" then
			handle.DragStart = (start - center).Unit
			handle.DragAngle = 0
		end
		if handle.Kind == "Rotate" and math.abs(direction:Dot(axis)) < 0.15 then
			local radial = (start - center).Unit
			local radius = handle.Radius
			local a = camera:WorldToScreenPoint(center + radial * radius)
			local b =
				camera:WorldToScreenPoint(center + CFrame.fromAxisAngle(axis, 0.01):VectorToWorldSpace(radial) * radius)
			local x, y = (b.X - a.X) / 0.01, (b.Y - a.Y) / 0.01
			local magnitude = math.sqrt(x * x + y * y)
			if magnitude < 5 then
				x, y, magnitude = 1, 0, math.max(30, radius * 20)
			else
				x, y = x / magnitude, y / magnitude
			end
			drag.Tangent = { X = x, Y = y, PixelsPerRadian = magnitude, Start = position }
		end
		if handle.Kind == "Axis" then
			local a = camera:WorldToScreenPoint(handle.Start)
			local b = camera:WorldToScreenPoint(handle.Finish)
			local x, y = b.X - a.X, b.Y - a.Y
			local length = x * x + y * y
			drag.GrabFraction = length > 1e-6
					and math.clamp(((position.X - a.X) * x + (position.Y - a.Y) * y) / length, 0.4, 1)
				or 0.65
		end
		Tools.Dragging = true
		Apps.History.Focused = true
		if Main.SetGameInputLocked then
			Main.SetGameInputLocked(true)
		end
		setReadout(nil)
		return true
	end
	local function applyDrag(position)
		local current = drag
		if not current then
			return
		end
		local camera = workspace.CurrentCamera
		if camera ~= current.Camera then
			finish(true)
			return
		end
		local modifiers = tostring(Lib.IsShiftDown()) .. tostring(Lib.IsCtrlDown()) .. tostring(altDown())
		if
			current.Applied
			and current.Applied.X == position.X
			and current.Applied.Y == position.Y
			and current.Modifiers == modifiers
		then
			return
		end
		current.Applied = position
		current.Modifiers = modifiers
		local origin, direction = ray(camera, position)
		local h = current.Handle
		local value
		if h.Kind == "Rotate" then
			local a = (current.Start - current.Center).Unit
			if current.Tangent then
				local t = current.Tangent
				current.Angle = ((position.X - t.Start.X) * t.X + (position.Y - t.Start.Y) * t.Y) / t.PixelsPerRadian
			else
				local hit = Apps.TransformSession.RayPlane(origin, direction, current.Center, current.Axis)
				if not hit or (hit - current.Center).Magnitude < 1e-5 then
					return
				end
				local b = (hit - current.Center).Unit
				local angle = math.atan2(current.Axis:Dot(a:Cross(b)), a:Dot(b))
				local difference = angle - current.PreviousAngle
				if difference > math.pi then
					difference -= 2 * math.pi
				elseif difference < -math.pi then
					difference += 2 * math.pi
				end
				current.PreviousAngle = angle
				current.Angle += difference
			end
			value = math.rad(snapped(math.deg(current.Angle), Tools.RotateSnap))
			checked(current.Session:Rotate(current.Axis, value))
			local degrees = (math.floor((math.abs(math.deg(value)) % 360) * 1000 + 0.5) % 360000) / 1000
			h.DragStart = a
			h.DragAngle = math.rad(degrees) * (value < 0 and -1 or 1)
			setReadout(string.format("%.3f", degrees))
		elseif h.Kind == "Axis" or h.Kind == "Scale" then
			local hit = Apps.TransformSession.RayAxis(origin, direction, current.Center, current.Axis)
			if hit == nil then
				return
			end
			value = hit - current.Start
			if h.Kind == "Axis" then
				value = snapped(value, Tools.MoveSnap)
				checked(current.Session:Move(current.Axis * value))
			else
				value = snapped(value * (h.Sign or 1), Tools.ScaleSnap)
				checked(current.Session:Scale(h.Axis, value, Lib.IsCtrlDown(), altDown(), h.Sign or 1))
			end
			if h.Kind == "Scale" then
				local _, updatedSize = Apps.TransformSession.Bounds(roots, "Scale")
				setReadout(string.format("%.3f", ({ updatedSize.X, updatedSize.Y, updatedSize.Z })[h.Axis]))
			else
				setReadout(string.format("%.3f", value))
			end
		else
			local hit = Apps.TransformSession.RayPlane(origin, direction, current.Center, current.Normal)
			if not hit then
				return
			end
			local delta = current.Box:VectorToObjectSpace(hit - current.Start)
			if h.Kind == "Plane" then
				local values = {
					snapped(delta.X, Tools.MoveSnap),
					snapped(delta.Y, Tools.MoveSnap),
					snapped(delta.Z, Tools.MoveSnap),
				}
				values[h.Axis] = 0
				delta = current.Box:VectorToWorldSpace(Vector3.new(values[1], values[2], values[3]))
			else
				local cf = current.Camera.CFrame
				local right = snapped((hit - current.Start):Dot(cf.RightVector), Tools.MoveSnap)
				local up = snapped((hit - current.Start):Dot(cf.UpVector), Tools.MoveSnap)
				delta = cf.RightVector * right + cf.UpVector * up
			end
			checked(current.Session:Move(delta))
			setReadout(string.format("%.3f", delta.Magnitude))
		end
		boundsDirty = true
	end
	local function pickWorld(position)
		if overUI(position) then
			return false
		end
		return Apps.Explorer.PickWorld(position)
	end
	function Tools.CapturesPointer(x, y)
		if Apps.GuiTransformTools and Apps.GuiTransformTools.CapturesPointer(x, y) then
			return true
		end
		if guiActive() then
			return toolbarDrag ~= nil
		end
		return Tools.Dragging
			or toolbarDrag ~= nil
			or (Tools.Enabled and (Tools.Tool ~= "Select" or Tools.WorldSelection) and not overUI(Vector2.new(x, y)))
	end
	local function clearHotspots()
		if hotspotFolder then hotspotFolder:Destroy() end
		hotspotFolder, hotspotBox, hotspotSize = nil, nil, nil
	end
	local function drawHotspots()
		if not Tools.EditingPivot or not Tools.Snapping or Lib.IsShiftDown() then
			if hotspotFolder then clearHotspots() end
			return
		end
		local box, size = Apps.TransformSession.PivotBox(roots[1])
		if box == hotspotBox and size == hotspotSize then return end
		if not hotspotFolder then hotspotFolder = node("Folder", {Name="PivotHotspots",Parent=gui}) end
		local parts = hotspotFolder:GetChildren()
		local localBox = workspace.Terrain.CFrame:ToObjectSpace(box)
		local i = 0
		for x=-1,1 do
			for y=-1,1 do
				for z=-1,1 do
					i += 1
					local dot = parts[i] or node("SphereHandleAdornment",{Parent=hotspotFolder,Adornee=workspace.Terrain,
						Color3=Color3.fromRGB(230,52,175),AlwaysOnTop=true,ZIndex=2})
					dot.CFrame = localBox * CFrame.new(Vector3.new(x,y,z)*size*0.5)
					dot.Radius = math.clamp(size.Magnitude*0.013,0.03,0.16)
				end
			end
		end
		hotspotBox, hotspotSize = box, size
	end
	render = function()
		if destroyed or not Tools.Enabled or guiActive() or #roots == 0 or Tools.Tool == "Select" then
			if gizmo then
				gizmo:Hide()
			end
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			gizmo:Hide()
			return
		end
		drawHotspots()
		local position = drag and drag.Pointer or mousePoint()
		if drag then
			local ok, problem = pcall(applyDrag, position)
			if not ok then
				finish(true)
				report(problem)
				return
			end
		end
		local box, size, pivot = bounds()
		if not box then
			gizmo:Hide()
			return
		end
		local pose = Tools.Tool == "Scale" and box or pivot or box
		local tickDegrees = Tools.Snapping and not Lib.IsShiftDown() and Tools.RotateSnap or nil
		local changed = pose ~= lastPivot
			or size ~= lastSize
			or camera.CFrame ~= lastCamera
			or camera.ViewportSize ~= lastViewport
			or camera.FieldOfView ~= lastFOV
			or camera ~= lastCameraObject
			or tickDegrees ~= lastTickDegrees
		local pointerChanged = not lastPointer or position.X ~= lastPointer.X or position.Y ~= lastPointer.Y
		if changed or pointerChanged or drag or gizmo.Animating then
			gizmo:Update(
				camera,
				pose,
				size,
				Tools.Tool,
				hover,
				drag and drag.Handle,
				Tools.Snapping and not Lib.IsShiftDown() and Tools.RotateSnap or nil
			)
			if not drag and (changed or pointerChanged) then
				local nextHover = not overUI(position) and gizmo:HitTest(camera, position) or nil
				if nextHover ~= hover then
					hover = nextHover
					gizmo:Update(
						camera,
						pose,
						size,
						Tools.Tool,
						hover,
						nil,
						Tools.Snapping and not Lib.IsShiftDown() and Tools.RotateSnap or nil
					)
				end
			end
			lastPivot, lastSize, lastCamera, lastViewport, lastPointer =
				pose, size, camera.CFrame, camera.ViewportSize, position
			lastFOV, lastCameraObject = camera.FieldOfView, camera
			lastTickDegrees = tickDegrees
		end
		positionReadout(camera, box)
	end
	updateFrameBinding = function()
		local needed = Tools.Enabled and not guiActive() and #roots > 0 and Tools.Tool ~= "Select"
		if needed and not frameConnection then
			frameConnection = Main.TrackSignal(service.RunService.RenderStepped, render)
		elseif not needed and frameConnection then
			frameConnection:Disconnect()
			frameConnection = nil
		end
		if not needed and hotspotFolder then clearHotspots() end
		if not needed and gizmo then
			gizmo:Hide()
		end
	end
	refresh = function()
		if destroyed then
			return
		end
		if drag then
			if not restoringSelection then
				restoringSelection = true
				Apps.Explorer.Selection:SetTable(drag.Selection)
				restoringSelection = false
			end
			return
		end
		releaseConnections()
		if not Tools.Enabled then
			Tools.EditingPivot = false
			roots = {}
			Tools.Roots = roots
			bar.Visible = false
			options.Visible = false
			toolbarDrag = nil
			table.clear(buttonHovers)
			lastPivot, hover = nil, nil
			updateButtons()
			updateFrameBinding()
			return
		end
		local objects = {}
		for _, entry in ipairs(Apps.Explorer.Selection.List) do
			objects[#objects + 1] = entry.Obj
		end
		local modelParts = {}
		roots = Apps.TransformSession.Collect(objects, modelParts)
		Tools.Roots = roots
		if #roots ~= 1 or guiActive() then Tools.EditingPivot = false end
		boundsDirty = true
		bar.Visible = #roots > 0 or guiActive()
		if not bar.Visible then
			options.Visible = false
			toolbarDrag = nil
			table.clear(buttonHovers)
		end
		local watchBounds = Tools.Tool ~= "Select"
		local function selectionChanged()
			if drag then finish(true) else refresh() end
		end
		local function dirty()
			boundsDirty = true
		end
		local bulk = #objects >= 32
		for _, parts in pairs(modelParts) do
			if #parts >= 32 then bulk = true break end
		end
		local watched
		if bulk then
			local members = {}
			local ok, connection = pcall(function()
				local properties = if watchBounds then { Locked = true, CFrame = true, Size = true, PivotOffset = true,
					Orientation = true, Position = true, Rotation = true } else { Locked = true }
				return Apps.PropertyChanges.For(properties, members):Connect(function(_, key)
					if key == "Locked" then
						selectionChanged()
					else
						dirty()
					end
				end)
			end)
			if ok then
				watched = members
				selectionConnections[#selectionConnections + 1] = connection
			end
		end
		for _, object in ipairs(objects) do
			if not (object:IsA("BasePart") or object:IsA("Model")) or not object:IsDescendantOf(workspace) then
				continue
			end
			selectionConnections[#selectionConnections + 1] = object.AncestryChanged:Connect(selectionChanged)
			local function watch(part)
				if part:IsA("BasePart") then
					if watched then
						watched[part] = true
						return
					end
					if watchBounds then
						for _, key in ipairs({ "CFrame", "Size", "PivotOffset" }) do
							selectionConnections[#selectionConnections + 1] = part:GetPropertyChangedSignal(key)
								:Connect(dirty)
						end
					end
					selectionConnections[#selectionConnections + 1] = part:GetPropertyChangedSignal("Locked")
						:Connect(selectionChanged)
				end
			end
			watch(object)
			if object:IsA("Model") then
				for _, part in ipairs(modelParts[object] or object:GetDescendants()) do
					watch(part)
				end
				if watchBounds then
					selectionConnections[#selectionConnections + 1] =
						object:GetPropertyChangedSignal("WorldPivot"):Connect(dirty)
					selectionConnections[#selectionConnections + 1] =
						object:GetPropertyChangedSignal("PrimaryPart"):Connect(dirty)
				end
				local function topology()
					if drag then
						finish(true)
					end
					boundsDirty = true
					if refreshQueued then
						return
					end
					refreshQueued = true
					task.defer(function()
						refreshQueued = false
						if Main.Alive and not destroyed then
							refresh()
						end
					end)
				end
				selectionConnections[#selectionConnections + 1] = object.DescendantAdded:Connect(topology)
				selectionConnections[#selectionConnections + 1] = object.DescendantRemoving:Connect(topology)
			end
		end
		lastPivot = nil
		hover = nil
		updateButtons()
		updateFrameBinding()
	end
	function Tools.SetWorldSelection(enabled)
		Tools.WorldSelection = enabled == true
		local control = Main.MenuApps and Main.MenuApps["Click part to select"]
		if control then
			if Tools.WorldSelection then
				control.Enable()
			else
				control.Disable()
			end
		end
		if bar then
			updateButtons()
		end
	end
	function Tools.SetTool(tool)
		if gestureActive() then
			return
		end
		if tool ~= "Select" and tool ~= "Move" and tool ~= "Rotate" and tool ~= "Scale" then
			return
		end
		finish(true)
		if tool == "Scale" or tool == "Select" then Tools.EditingPivot = false end
		Tools.Tool = tool
		Tools.Enabled = true
		hover = nil
		lastPivot = nil
		boundsDirty = true
		if not guiActive() then
			Tools.SetWorldSelection(true)
		end
		if Apps.GuiTransformTools then
			Apps.GuiTransformTools.SetEnabled(true)
		end
		if Apps.GuiTransformTools then
			Apps.GuiTransformTools.SetTool(tool)
		end
		local control = Main.MenuApps and Main.MenuApps["Transform Tools"]
		if control then
			control.Enable(true)
		end
		if bar then
			refresh()
		end
	end
	function Tools.SetEnabled(enabled)
		if gestureActive() then
			return
		end
		finish(true)
		Tools.Enabled = enabled == true
		if Apps.GuiTransformTools then
			Apps.GuiTransformTools.SetEnabled(Tools.Enabled)
		end
		local control = Main.MenuApps and Main.MenuApps["Transform Tools"]
		if control then
			if Tools.Enabled then
				control.Enable(true)
			else
				control.Disable(true)
			end
		end
		if bar then
			refresh()
		end
	end
	function Tools.SetSpace(space)
		if gestureActive() or guiActive() then
			return
		end
		finish(true)
		Tools.Space = space == "World" and "World" or "Local"
		lastPivot = nil
		boundsDirty = true
		updateButtons()
	end
	function Tools.Cancel()
		if Apps.GuiTransformTools then
			Apps.GuiTransformTools.Cancel()
		end
		finish(true)
	end
	local function makeButton(parent, key, text, x, width, callback)
		local b = node("TextButton", {
			Name = key,
			Parent = parent,
			Position = UDim2.fromOffset(x + 20, 4),
			Size = UDim2.fromOffset(width, 28),
			Text = text,
			Font = Lib.StudioFont,
			TextSize = 12,
			TextColor3 = Settings.Theme.Text,
			BackgroundColor3 = Settings.Theme.ButtonHover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		})
		node("UICorner", { Parent = b, CornerRadius = UDim.new(0, 3) })
		b.MouseButton1Click:Connect(callback)
		b.MouseEnter:Connect(function()
			buttonHovers[b] = true
			updateButtons()
		end)
		b.MouseLeave:Connect(function()
			buttonHovers[b] = nil
			updateButtons()
		end)
		return b
	end
	local function positionOptions()
		if options then
			options.Position = UDim2.fromOffset(132, bar.AbsolutePosition.Y < options.Size.Y.Offset + 8 and bar.AbsoluteSize.Y + 8 or -options.Size.Y.Offset-8)
		end
	end
	updateButtons = function()
		for key, b in pairs(buttons) do
			local selected = (key == "Pivot" and Tools.EditingPivot) or (Tools.Tool == key and (key ~= "Select" or Tools.WorldSelection or guiActive()))
				or (
					key == "Snap"
					and (guiActive() and Apps.GuiTransformTools.Snapping or not guiActive() and Tools.Snapping)
				)
			b.BackgroundTransparency = (selected or buttonHovers[b]) and 0 or 1
		end
		for _, key in {"Pivot","ResetPivot","Align"} do
			local b = buttons[key]
			if b then
				local available = not guiActive() and (if key == "Align" then #roots >= 2 else #roots == 1)
				b.Interactable = available
				b.TextTransparency = if available then 0 else 0.6
			end
		end
		if buttons.Space then
			buttons.Space.Text = guiActive() and "UI" or Tools.Tool == "Scale" and "Local" or Tools.Space
		end
		if options then
			local isGui = guiActive()
			for _, key in ipairs({ "MoveSnap", "ScaleSnap", "RotateSnap" }) do
				options[key].Text = tostring(isGui and Apps.GuiTransformTools[key] or Tools[key])
				if key ~= "RotateSnap" then
					options[key .. "Unit"].Text = isGui and "px" or "studs"
				end
			end
		end
	end
	function Tools.OpenAlign()
		local d = Apps.StudioPopup.Open("Align Tool", 284)
		local config = { Mode = "Center", Space = "World", Relative = "Selection Bounds" }
		local axesOn = { X=true, Y=false, Z=false }
		local colors, planes = {}, {}
		local activeBox = node("SelectionBox",{ Parent=d.gui, Color3=Color3.fromRGB(255,165,38), LineThickness=0.035 })
		local update
		local function choices(key, caption, y, values)
			d.label(d.panel,caption,20,y,120,28,14,true)
			local x = 152
			for _, value in values do
				local width = if key == "Relative" then 150 else 88
				local _, paint = d.button(d.panel,value,x,y,width,28,Settings.Theme.Main2,function()
					if key == "Axes" then axesOn[value] = not axesOn[value] else config[key] = value end
					update()
				end)
				colors[#colors+1] = function()
					paint(if config[key] == value or (key == "Axes" and axesOn[value]) then Color3.fromRGB(52,90,202) else Settings.Theme.Main2)
				end
				x += width + 4
			end
		end
		choices("Mode","Mode",48,{"Min","Center","Max"})
		choices("Space","Align In",89,{"World","Local"})
		choices("Axes","Axes",130,{"X","Y","Z"})
		choices("Relative","Relative To",171,{"Selection Bounds","Active Object"})
		for _, axis in {"X","Y","Z"} do
			planes[axis] = node("BoxHandleAdornment",{Parent=d.gui, Adornee=workspace.Terrain,
				Color3=Color3.fromRGB(255,153,48),Transparency=0.68,AlwaysOnTop=true,ZIndex=1,Visible=false})
		end
		local function preview()
			local _, basis, dest, low, high = Apps.TransformSession.AlignPlan(roots,config.Mode,config.Space,config.Relative,axesOn)
			activeBox.Adornee = if basis and config.Relative == "Active Object" then roots[#roots] else nil
			for axis, plane in planes do
				plane.Visible = basis ~= nil and axesOn[axis]
				if not plane.Visible then continue end
				local mid,size = (low+high)*0.5,high-low
				local center = Vector3.new(if axis=="X" then dest.X else mid.X,if axis=="Y" then dest.Y else mid.Y,if axis=="Z" then dest.Z else mid.Z)
				plane.Size = Vector3.new(if axis=="X" then 0.035 else math.max(0.1,size.X),if axis=="Y" then 0.035 else math.max(0.1,size.Y),if axis=="Z" then 0.035 else math.max(0.1,size.Z))
				plane.CFrame = workspace.Terrain.CFrame:ToObjectSpace(basis*CFrame.new(center))
			end
		end
		update = function()
			for _, paint in colors do paint() end
			preview()
			d.setPrimary("Align",if #roots >= 2 and (axesOn.X or axesOn.Y or axesOn.Z) then function()
				Apps.TransformSession.ApplyAlign(roots,config.Mode,config.Space,config.Relative,axesOn)
				boundsDirty = true
				preview()
			end else nil)
		end
		update()
		local selected = Apps.Explorer.Selection.Changed:Connect(function() task.defer(function() if d.isOpen() then update() end end) end)
		local clock = 0
		local connection = service.RunService.Heartbeat:Connect(function(dt)
			clock += dt
			if clock >= 0.12 then
				clock = 0
				preview()
			end
		end)
		d.onClose = function() connection:Disconnect() selected:Disconnect() end
	end
	function Tools.Init()
		if gui then
			return
		end
		gui = node("ScreenGui", {
			Name = "DexTransformTools",
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = Main.DisplayOrders.Core + 1,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		Lib.ShowGui(gui)
		bar = node("Frame", {
			Name = "Toolbar",
			Parent = gui,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -24),
			Size = UDim2.fromOffset(340, 36),
			BackgroundColor3 = Settings.Theme.Main2,
			BorderSizePixel = 0,
			Active = true,
			Visible = false,
		})
		node("UICorner", { Parent = bar, CornerRadius = UDim.new(0, 4) })
		node("UIStroke", { Parent = bar, Color = Settings.Theme.Outline2, Thickness = 1 })
		local grip = node("Frame", {
			Name = "DragHandle",
			Parent = bar,
			Position = UDim2.fromOffset(2, 4),
			Size = UDim2.fromOffset(20, 28),
			BackgroundTransparency = 1,
			Active = true,
		})
		for x = 0, 1 do
			for y = 0, 2 do
				node("Frame", {
					Parent = grip,
					Position = UDim2.fromOffset(6 + x * 5, 7 + y * 5),
					Size = UDim2.fromOffset(2, 2),
					BackgroundColor3 = Settings.Theme.PlaceholderText or Settings.Theme.Text,
					BorderSizePixel = 0,
				})
			end
		end
		Lib.StudioTooltip(grip, "Drag to move toolbar")
		Main.TrackSignal(grip.InputBegan, function(event)
			if gestureActive() or toolbarDrag or not bar.Visible then
				return
			end
			if
				event.UserInputType == Enum.UserInputType.MouseButton1
				or event.UserInputType == Enum.UserInputType.Touch
			then
				toolbarDrag = {
					Start = point(event.Position),
					Position = bar.Position,
					Touch = event.UserInputType == Enum.UserInputType.Touch and event or nil,
				}
				table.clear(buttonHovers)
				updateButtons()
			end
		end)
		for index, tool in ipairs({ "Select", "Move", "Scale", "Rotate" }) do
			local selected = tool
			local b = makeButton(bar, tool, "", 4 + (index - 1) * 32, 28, function()
				Tools.SetTool(selected)
			end)
			buttons[tool] = b
			node("ImageLabel", {
				Parent = b,
				Name = "Icon",
				BackgroundTransparency = 1,
				Image = Main.GetStudioAsset("native/transform/ribbon/" .. tool:lower()) or "",
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.fromOffset(24, 24),
			})
			Lib.StudioTooltip(b, tool .. " (" .. index .. ")")
		end
		node("Frame", {
			Parent = bar,
			Position = UDim2.fromOffset(156, 8),
			Size = UDim2.fromOffset(1, 20),
			BorderSizePixel = 0,
			BackgroundColor3 = Settings.Theme.Outline2,
		})
		buttons.Space = makeButton(bar, "Space", "Local", 144, 52, function()
			if Tools.Tool ~= "Scale" then
				Tools.SetSpace(Tools.Space == "Local" and "World" or "Local")
			end
		end)
		Lib.StudioTooltip(buttons.Space, function()
			if guiActive() then
				local caps = Apps.GuiTransformTools.Capabilities
				return (caps and (caps.MoveReason or caps.ScaleReason))
					or "Screen UI coordinates. Shift locks movement or aspect ratio. Ctrl resizes from the center; Ctrl+Shift does both."
			end
			return "Local / World (Ctrl+L)"
		end)
		buttons.Snap = makeButton(bar, "Snap", "Snap", 202, 44, function()
			if guiActive() then
				Apps.GuiTransformTools.Snapping = not Apps.GuiTransformTools.Snapping
			else
				Tools.Snapping = not Tools.Snapping
			end
			updateButtons()
		end)
		Lib.StudioTooltip(buttons.Snap, function()
			return guiActive() and "Snap to UI edges, centers and pixel increments"
				or "Snap to increments; hold Shift to temporarily disable snapping"
		end)
		buttons.Options = makeButton(bar, "Options", "…", 250, 30, function()
			if not gestureActive() then
				options.Visible = not options.Visible
				positionOptions()
			end
		end)
		buttons.Close = makeButton(bar, "Hide", "×", 284, 30, function()
			Tools.SetEnabled(false)
		end)
		buttons.Options.TextSize = 24
		buttons.Close.TextSize = 24
		options = node("Frame", {
			Name = "Snapping",
			Parent = bar,
			Position = UDim2.fromOffset(132, -120),
			Size = UDim2.fromOffset(224, 148),
			BackgroundColor3 = Settings.Theme.Main2,
			BorderSizePixel = 0,
			Active = true,
			Visible = false,
		})
		node("UICorner", { Parent = options, CornerRadius = UDim.new(0, 4) })
		node("UIStroke", { Parent = options, Color = Settings.Theme.Outline2, Thickness = 1 })
		for index, setting in ipairs({
			{ "MoveSnap", "Move", "studs" },
			{ "RotateSnap", "Rotate", "°" },
			{ "ScaleSnap", "Scale", "studs" },
		}) do
			local key = setting[1]
			node("TextLabel", {
				Parent = options,
				Position = UDim2.fromOffset(12, 8 + (index - 1) * 32),
				Size = UDim2.fromOffset(62, 28),
				BackgroundTransparency = 1,
				Text = setting[2],
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = Settings.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local box = node("TextBox", {
				Name = key,
				Parent = options,
				Position = UDim2.fromOffset(76, 8 + (index - 1) * 32),
				Size = UDim2.fromOffset(60, 26),
				BackgroundColor3 = Settings.Theme.TextBox,
				BorderSizePixel = 0,
				Text = tostring(Tools[key]),
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = Settings.Theme.Text,
				ClearTextOnFocus = false,
				MultiLine = false,
			})
			box.FocusLost:Connect(function()
				local target = guiActive() and Apps.GuiTransformTools or Tools
				local value = tonumber(box.Text)
				if value and value == value and value > 0 and value < 1e6 then
					target[key] = value
				end
				box.Text = tostring(target[key])
			end)
			node("TextLabel", {
				Name = key .. "Unit",
				Parent = options,
				Position = UDim2.fromOffset(142, 8 + (index - 1) * 32),
				Size = UDim2.fromOffset(42, 26),
				BackgroundTransparency = 1,
				Text = setting[3],
				Font = Lib.StudioFont,
				TextSize = key == "RotateSnap" and 18 or 12,
				TextColor3 = Settings.Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function optionButton(name, text, x, width, callback)
			local b = makeButton(options, name, text, x, width, callback)
			b.Position = UDim2.fromOffset(x,112)
			buttons[name] = b
		end
		optionButton("Pivot","Edit Pivot",4,76,function()
			if gestureActive() or #roots ~= 1 or guiActive() then return end
			Tools.EditingPivot = not Tools.EditingPivot
			Tools.SetTool(if Tools.Tool == "Rotate" then "Rotate" else "Move")
			options.Visible = false
		end)
		optionButton("ResetPivot","Reset Pivot",82,80,function()
			if not gestureActive() and #roots == 1 and not guiActive() then
				Apps.TransformSession.ResetPivot(roots[1])
				boundsDirty = true
			end
		end)
		optionButton("Align","Align",164,56,function()
			if not gestureActive() and #roots >= 2 and not guiActive() then
				options.Visible = false
				Tools.OpenAlign()
			end
		end)
		readout = node("TextLabel", {
			Name = "Delta",
			Parent = gui,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(48, 20),
			BackgroundColor3 = Color3.fromRGB(35, 35, 35),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Text = "",
			Font = Lib.StudioFont,
			TextSize = 13,
			TextColor3 = Color3.new(1, 1, 1),
			Active = false,
			Visible = false,
		})
		gizmo = Apps.TransformGizmo.Create(gui)
		Tools.Gui = gui
		Tools.Toolbar = bar
		Tools.Gizmo = gizmo
		Tools.Readout = readout
		Main.TrackSignal(Apps.Explorer.Selection.Changed, refresh)
		Main.TrackSignal(input.InputChanged, function(event)
			if
				toolbarDrag
				and (
					(not toolbarDrag.Touch and event.UserInputType == Enum.UserInputType.MouseMovement)
					or event == toolbarDrag.Touch
				)
			then
				local p, origin = point(event.Position), toolbarDrag.Position
				local dx, dy = p.X - toolbarDrag.Start.X, p.Y - toolbarDrag.Start.Y
				local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or gui.AbsoluteSize
				local size = bar.AbsoluteSize
				local anchor = bar.AnchorPoint
				bar.Position = UDim2.fromOffset(
					math.clamp(
						origin.X.Scale * viewport.X + origin.X.Offset + dx,
						size.X * anchor.X,
						math.max(size.X * anchor.X, viewport.X - size.X * (1 - anchor.X))
					),
					math.clamp(
						origin.Y.Scale * viewport.Y + origin.Y.Offset + dy,
						size.Y * anchor.Y,
						math.max(size.Y * anchor.Y, viewport.Y - size.Y * (1 - anchor.Y))
					)
				)
				if options.Visible then
					positionOptions()
				end
				return
			end
			if
				drag
				and (
					(not drag.Touch and event.UserInputType == Enum.UserInputType.MouseMovement)
					or event == drag.Touch
				)
			then
				drag.Pointer = point(event.Position)
			end
		end)
		Main.TrackSignal(input.InputEnded, function(event)
			if
				toolbarDrag
				and (
					(not toolbarDrag.Touch and event.UserInputType == Enum.UserInputType.MouseButton1)
					or event == toolbarDrag.Touch
				)
			then
				toolbarDrag = nil
				return
			end
			if
				drag
				and ((not drag.Touch and event.UserInputType == Enum.UserInputType.MouseButton1) or event == drag.Touch)
			then
				if event.Position then
					drag.Pointer = point(event.Position)
				end
				local ok, problem = pcall(applyDrag, drag.Pointer)
				if not ok then
					finish(true)
					report(problem)
				else
					finish(false)
				end
			end
		end)
		Main.TrackSignal(input.InputBegan, function(event, processed)
			if not Tools.Enabled or input:GetFocusedTextBox() then
				return
			end
			if toolbarDrag then
				return
			end
			local key = event.KeyCode
			if gestureActive() then
				if Tools.GuiDragging then
					return
				end
				if key == Enum.KeyCode.Escape or (Lib.IsCtrlDown() and key == Enum.KeyCode.Z) then
					finish(true)
				end
				return
			end
			if
				event.UserInputType == Enum.UserInputType.Keyboard
				and (#roots > 0 or guiActive())
				and (Main.GameInputLocked or Tools.WorldSelection or guiActive())
			then
				local shortcuts = {
					[Enum.KeyCode.One] = "Select",
					[Enum.KeyCode.Two] = "Move",
					[Enum.KeyCode.Three] = "Scale",
					[Enum.KeyCode.Four] = "Rotate",
				}
				if shortcuts[key] and not Lib.IsCtrlDown() then
					Tools.SetTool(shortcuts[key])
				elseif key == Enum.KeyCode.L and Lib.IsCtrlDown() then
					Tools.SetSpace(Tools.Space == "Local" and "World" or "Local")
				end
			elseif
				not guiActive()
				and (event.UserInputType == Enum.UserInputType.MouseButton1 or event.UserInputType == Enum.UserInputType.Touch)
				and not processed
			then
				local position = point(event.Position)
				if not overUI(position) and (Tools.Tool ~= "Select" or Tools.WorldSelection) then
					local handle = gizmo:HitTest(workspace.CurrentCamera, position)
					if not beginDrag(handle, position) and Tools.WorldSelection then
						local picked = pickWorld(position)
						if picked and Tools.Tool == "Move" and not Lib.IsShiftDown() then
							beginDrag({ Id = "CursorMove", Kind = "Free" }, position)
						end
					end
					if drag and event.UserInputType == Enum.UserInputType.Touch then
						drag.Touch = event
					end
				end
			end
		end)
		local ok = pcall(function()
			service.ContextActionService:BindActionAtPriority(actionName, function(_, state, event)
				if Tools.Dragging or Tools.GuiDragging or toolbarDrag then
					return Enum.ContextActionResult.Sink
				end
				if guiActive() then
					return Enum.ContextActionResult.Pass
				end
				if
					state == Enum.UserInputState.Begin
					and Tools.Enabled
					and Tools.Tool ~= "Select"
					and not input:GetFocusedTextBox()
				then
					local position = point(event.Position)
					if not overUI(position) then
						local handle = gizmo:HitTest(workspace.CurrentCamera, position)
						if beginDrag(handle, position) then
							return Enum.ContextActionResult.Sink
						end
					end
				elseif Tools.Dragging then
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			end, false, (Main.InputLockPriority or 10000000) + 1, Enum.UserInputType.MouseButton1)
		end)
		Tools.NativeInputBound = ok
		pcall(function()
			service.ContextActionService:BindActionAtPriority(
				actionName .. "Keys",
				function(_, _, event)
					if
						not Tools.Enabled
						or (not Tools.WorldSelection and not guiActive())
						or (#roots == 0 and not guiActive())
						or input:GetFocusedTextBox()
					then
						return Enum.ContextActionResult.Pass
					end
					local key = event.KeyCode
					if key == Enum.KeyCode.L and not Lib.IsCtrlDown() then
						return Enum.ContextActionResult.Pass
					end
					if key ~= Enum.KeyCode.L and Lib.IsCtrlDown() then
						return Enum.ContextActionResult.Pass
					end
					return Enum.ContextActionResult.Sink
				end,
				false,
				(Main.InputLockPriority or 10000000) + 1,
				Enum.KeyCode.One,
				Enum.KeyCode.Two,
				Enum.KeyCode.Three,
				Enum.KeyCode.Four,
				Enum.KeyCode.L
			)
		end)
		if input.WindowFocusReleased then
			Main.TrackSignal(input.WindowFocusReleased, function()
				toolbarDrag = nil
				table.clear(buttonHovers)
				updateButtons()
				finish(true)
			end)
		end
		Main.AddCleanup(function()
			destroyed = true
			toolbarDrag = nil
			finish(true)
			releaseConnections()
			if frameConnection then
				frameConnection:Disconnect()
				frameConnection = nil
			end
			pcall(function()
				service.ContextActionService:UnbindAction(actionName)
			end)
			pcall(function()
				service.ContextActionService:UnbindAction(actionName .. "Keys")
			end)
			gizmo:Destroy()
			gui:Destroy()
		end)
		refresh()
	end
	return Tools
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
