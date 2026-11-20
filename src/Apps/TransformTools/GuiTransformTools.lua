--!strict

local Main, Apps, Lib, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, Lib, service = d.Main, d.Apps, d.Lib, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local T = {
		Enabled = true,
		Dragging = false,
		Roots = {},
		Tool = "Select",
		Snapping = true,
		MoveSnap = 1,
		ScaleSnap = 1,
		RotateSnap = 1,
	}
	local gui, view, connection, gesture, hover, cursor, previousIcon, previousEnabled
	local refreshing = false
	local destroyed = false
	local editCapabilities
	local selectionConnections = {}
	local refreshQueued = false
	local lastHit
	local input = service.UserInputService
	local function point(p)
		return Vector2.new(p.X, p.Y)
	end
	local function objects()
		local r = {}
		for _, n in ipairs(Apps.Explorer.Selection.List) do
			r[#r + 1] = n.Obj
		end
		return r
	end
	local function toolbar()
		return Apps.TransformTools
	end
	local function setDragging(value)
		T.Dragging = value
		local tools = toolbar()
		if tools then
			tools.GuiDragging = value
		end
	end
	local function blocked(p)
		if toolbar() and toolbar().IsToolbarPoint and toolbar().IsToolbarPoint(p) then
			return true
		end
		return Main.IsPointInDexUI and Main.IsPointInDexUI(p.X, p.Y)
	end
	local function clearCursor()
		if previousEnabled ~= nil then
			pcall(function()
				input.MouseIconEnabled = previousEnabled
			end)
			previousEnabled = nil
		end
		if previousIcon ~= nil then
			pcall(function()
				Main.Mouse.Icon = previousIcon
			end)
			previousIcon = nil
		end
		if cursor then
			cursor.Visible = false
		end
	end
	local function showCursor(h, p)
		if not h or h.Kind == "Move" then
			clearCursor()
			return
		end
		local rotation = (view.Geometry and view.Geometry.Rotation or 0)
		local angle = (math.deg(math.atan2(h.Y, h.X)) + rotation) % 360
		local index = (math.floor(angle / 45 + 0.5) % 8) + 1
		local key
		if h.Kind == "Rotate" then
			key = "icon_rotate" .. index
		else
			key = "icon_resize" .. ({ 2, 3, 4, 1, 2, 3, 4, 1 })[index]
		end
		local asset = Main.GetStudioAsset("native/gui-editor/" .. key)
		if not asset then
			clearCursor()
			return
		end
		if previousEnabled == nil then
			pcall(function()
				previousEnabled = input.MouseIconEnabled
			end)
			pcall(function()
				previousIcon = Main.Mouse.Icon
			end)
		end
		pcall(function()
			input.MouseIconEnabled = false
		end)
		cursor.Image = asset
		cursor.Position = UDim2.fromOffset(p.X, p.Y)
		cursor.Visible = true
	end
	local function report(problem)
		T.LastError = tostring(problem)
		warn("[Dex Explorer] UI transform: " .. T.LastError)
		local tools = toolbar()
		if tools then
			tools.LastError = T.LastError
		end
	end
	local transformModes = { "Move", "Scale", "Rotate" }
	local function capabilities()
		local r = { Move = true, Scale = true, Rotate = #T.Roots == 1 }
		local layouts = {}
		for _, o in ipairs(T.Roots) do
			for _, tool in ipairs(transformModes) do
				local ok, reason = Apps.GuiTransformSession.CanEdit(o, tool, layouts)
				if not ok then
					r[tool] = false
					r[tool .. "Reason"] = reason
				end
			end
		end
		return r
	end
	local function geometry()
		return Apps.GuiTransformSession.Bounds(T.Roots, true)
	end
	local finish, refresh, render, begin
	local function apply(p)
		local g = gesture
		if not g then
			return
		end
		local shift, ctrl = Lib.IsShiftDown(), Lib.IsCtrlDown()
		if g.Last and g.Last.X == p.X and g.Last.Y == p.Y and shift == g.Shift and ctrl == g.Ctrl then
			return
		end
		g.Last = p
		g.Shift = shift
		g.Ctrl = ctrl
		local dx, dy = p.X - g.Start.X, p.Y - g.Start.Y
		if not g.Started and math.abs(dx) + math.abs(dy) <= 3 then
			return
		end
		g.Started = true
		local h = g.Handle
		local ok, problem
		local alignment = Apps.GuiAlignment
		local xMatches, yMatches = {}, {}
		if h.Kind == "Rotate" then
			local angle = math.atan2(p.Y - g.Bounds.Center.Y, p.X - g.Bounds.Center.X)
			local delta = angle - g.PreviousAngle
			if delta > math.pi then
				delta -= 2 * math.pi
			elseif delta < -math.pi then
				delta += 2 * math.pi
			end
			g.Angle += delta
			g.PreviousAngle = angle
			local degrees = math.floor(math.deg(g.Angle) + 0.5)
			if T.Snapping then
				degrees = math.floor(degrees / T.RotateSnap + 0.5) * T.RotateSnap
			end
			ok, problem = g.Session:Rotate(degrees)
			view:SetReadout(tostring((g.InitialRotation + degrees) % 360) .. "°", p)
		elseif h.Kind == "Resize" then
			if T.Snapping then
				dx = math.floor(dx / T.ScaleSnap + 0.5) * T.ScaleSnap
				dy = math.floor(dy / T.ScaleSnap + 0.5) * T.ScaleSnap
			end
			if T.Snapping and not shift and not ctrl and math.abs(g.Bounds.Rotation % 360) < 0.001 then
				local c, s = g.Bounds.Center, g.Bounds.Size
				if h.X ~= 0 then
					local d, m = alignment.Snap(g.Targets.X, { { Value = c.X + h.X * s.X * 0.5 + dx, Kind = "Edge" } })
					dx += d
					xMatches = m
				end
				if h.Y ~= 0 then
					local d, m = alignment.Snap(g.Targets.Y, { { Value = c.Y + h.Y * s.Y * 0.5 + dy, Kind = "Edge" } })
					dy += d
					yMatches = m
				end
			end
			ok, problem = g.Session:Resize(h.X, h.Y, dx, dy, ctrl, shift)
		else
			if shift then
				if math.abs(dx) > math.abs(dy) then
					dy = 0
				else
					dx = 0
				end
			end
			if T.Snapping then
				dx = math.floor(dx / T.MoveSnap + 0.5) * T.MoveSnap
				dy = math.floor(dy / T.MoveSnap + 0.5) * T.MoveSnap
			end
			if T.Snapping then
				local xLocked, yLocked = shift and dx == 0, shift and dy == 0
				local d, m = alignment.Snap(g.Targets.X, alignment.Features(g.Bounds, "X", dx))
				if not xLocked then
					dx += d
					xMatches = m
				elseif math.abs(d) < 1e-6 then
					xMatches = m
				end
				d, m = alignment.Snap(g.Targets.Y, alignment.Features(g.Bounds, "Y", dy))
				if not yLocked then
					dy += d
					yMatches = m
				elseif math.abs(d) < 1e-6 then
					yMatches = m
				end
			end
			ok, problem = g.Session:Move(dx, dy)
			view:SetReadout(math.floor(dx + 0.5) .. ", " .. math.floor(dy + 0.5), p)
		end
		if not ok then
			finish(true)
			report(problem)
			return
		end
		local b = geometry()
		if b and h.Kind == "Resize" then
			view:SetReadout(math.floor(b.Size.X + 0.5) .. " × " .. math.floor(b.Size.Y + 0.5), p)
		end
		if T.Snapping and b and h.Kind == "Resize" then
			local d, m = alignment.Snap(g.Targets.X, alignment.Features(b, "X"))
			xMatches = math.abs(d) < 0.001 and m or {}
			d, m = alignment.Snap(g.Targets.Y, alignment.Features(b, "Y"))
			yMatches = math.abs(d) < 0.001 and m or {}
		end
		view:SetGuides(T.Snapping and b and alignment.Guides(xMatches, yMatches, b) or nil)
		return b, true
	end
	finish = function(cancel)
		if not gesture then
			return
		end
		local g = gesture
		gesture = nil
		setDragging(false)
		local ok, problem = pcall(function()
			if cancel or not g.Started then
				return g.Session:Cancel()
			end
			local done, err = g.Session:Commit()
			if not done then
				error(err, 0)
			end
			return true
		end)
		if not ok then
			pcall(function()
				g.Session:Cancel()
			end)
			report(problem)
		end
		if Main.SetGameInputLocked then
			Main.SetGameInputLocked(g.PreviousLock)
		end
		view:SetReadout(nil)
		view:SetGuides(nil)
		clearCursor()
		hover = nil
		refresh()
	end
	begin = function(h, event)
		if not T.Enabled or gesture or not h then
			return false
		end
		if
			event.UserInputType ~= Enum.UserInputType.MouseButton1
			and event.UserInputType ~= Enum.UserInputType.Touch
		then
			return false
		end
		local tools = toolbar()
		if tools and tools.Dragging or blocked(point(event.Position)) then
			return false
		end
		local action = h.Kind == "Resize" and "Scale" or h.Kind == "Rotate" and "Rotate" or "Move"
		local session, problem = Apps.GuiTransformSession.Begin(T.Roots, action)
		if not session then
			report(problem)
			return false
		end
		local p = point(event.Position)
		local b = session.Bounds
		local targets = Apps.GuiAlignment.Collect(T.Roots)
		gesture = {
			Session = session,
			Bounds = b,
			Start = p,
			Pointer = p,
			Handle = h,
			Selection = table.clone(Apps.Explorer.Selection.List),
			PreviousLock = Main.GameInputLocked,
			Touch = event.UserInputType == Enum.UserInputType.Touch and event or nil,
			Targets = targets,
			Angle = 0,
			PreviousAngle = math.atan2(p.Y - b.Center.Y, p.X - b.Center.X),
			InitialRotation = T.Roots[1].Rotation,
		}
		setDragging(true)
		Apps.History.Focused = true
		if Main.SetGameInputLocked then
			Main.SetGameInputLocked(true)
		end
		return true
	end
	render = function()
		if not T.Enabled or #T.Roots == 0 then
			view:Hide()
			clearCursor()
			return
		end
		local p, g, measured
		if gesture then
			p = gesture.Pointer
			local ok, geometryOrError, didMeasure = pcall(apply, p)
			if not ok then
				finish(true)
				report(geometryOrError)
				return
			end
			g, measured = geometryOrError, didMeasure
		else
			local raw = input:GetMouseLocation()
			local ok, inset = pcall(function()
				return service.GuiService:GetGuiInset()
			end)
			p = Vector2.new(raw.X - (ok and inset.X or 0), raw.Y - (ok and inset.Y or 0))
		end
		if not measured then g = geometry() end
		if
			not gesture
			and g
			and lastHit
			and lastHit.X == p.X
			and lastHit.Y == p.Y
			and lastHit.CX == g.Center.X
			and lastHit.CY == g.Center.Y
			and lastHit.W == g.Size.X
			and lastHit.H == g.Size.Y
			and lastHit.R == g.Rotation
			and lastHit.Tool == T.Tool
		then
			return
		end
		lastHit = g
				and {
					X = p.X,
					Y = p.Y,
					CX = g.Center.X,
					CY = g.Center.Y,
					W = g.Size.X,
					H = g.Size.Y,
					R = g.Rotation,
					Tool = T.Tool,
				}
			or nil
		view:Update(g, T.Tool, hover, gesture and gesture.Handle, editCapabilities)
		if not g then
			clearCursor()
			return
		end
		if not gesture then
			hover = not blocked(p) and view:HitTest(p) or nil
			view:Update(g, T.Tool, hover, nil, editCapabilities)
		end
		showCursor(gesture and gesture.Handle or hover, p)
	end
	refresh = function()
		if destroyed then
			return
		end
		if gesture then
			if not refreshing then
				refreshing = true
				Apps.Explorer.Selection:SetTable(gesture.Selection)
				refreshing = false
			end
			return
		end
		for _, con in ipairs(selectionConnections) do
			con:Disconnect()
		end
		table.clear(selectionConnections)
		lastHit = nil
		if not T.Enabled then
			T.Roots = {}
			T.Active = false
			if connection then
				connection:Disconnect()
				connection = nil
				view:Hide()
				clearCursor()
			end
			return
		end
		T.Roots = Apps.GuiTransformSession.Collect(objects())
		T.Active = #T.Roots > 0
		editCapabilities = capabilities()
		T.Capabilities = editCapabilities
		local function schedule(cancel)
			if gesture and cancel then
				finish(true)
			end
			if refreshQueued then
				return
			end
			refreshQueued = true
			task.defer(function()
				refreshQueued = false
				if not destroyed then
					refresh()
				end
			end)
		end
		local function structure(child)
			local class = child.ClassName
			schedule(
				class == "UIScale"
					or class == "UIPadding"
					or class == "UIAspectRatioConstraint"
					or class == "UISizeConstraint"
					or class == "UIListLayout"
					or class == "UIGridLayout"
					or class == "UIPageLayout"
					or class == "UITableLayout"
			)
		end
		local watched = {}
		for _, o in ipairs(T.Roots) do
			selectionConnections[#selectionConnections + 1] = o.AncestryChanged:Connect(function()
				schedule(true)
			end)
			selectionConnections[#selectionConnections + 1] = o:GetPropertyChangedSignal("AutomaticSize")
				:Connect(function()
					schedule(true)
				end)
			for _, parent in ipairs({ o, o.Parent }) do
				if parent and not watched[parent] then
					watched[parent] = true
					selectionConnections[#selectionConnections + 1] = parent.ChildAdded:Connect(structure)
					selectionConnections[#selectionConnections + 1] = parent.ChildRemoved:Connect(structure)
				end
			end
		end
		if T.Enabled and T.Active and not connection then
			connection = Main.TrackSignal(service.RunService.RenderStepped, render)
		elseif (not T.Enabled or not T.Active) and connection then
			connection:Disconnect()
			connection = nil
			view:Hide()
			clearCursor()
		end
		if T.Enabled and T.Active then
			render()
		end
	end
	function T.Cancel()
		finish(true)
	end
	function T.SetEnabled(enabled)
		if gesture then
			return
		end
		T.Enabled = enabled
		refresh()
		if Apps.Explorer.UpdateSelectionVisuals then
			Apps.Explorer.UpdateSelectionVisuals()
		end
	end
	function T.SetTool(tool)
		if gesture then
			return
		end
		T.Tool = tool
		refresh()
	end
	function T.IsActive()
		return T.Enabled and T.Active
	end
	function T.HandlesObject(object)
		return gui ~= nil
			and T.Enabled
			and #Apps.GuiTransformSession.Collect({ object }) > 0
			and Apps.GuiTransformSession.Visible(object)
	end
	function T.CapturesPointer(x, y)
		return gesture ~= nil
			or (T.Enabled and view and not blocked(Vector2.new(x, y)) and view:HitTest(Vector2.new(x, y)) ~= nil)
	end
	function T.Init()
		if gui then
			return
		end
		gui = Instance.new("ScreenGui")
		gui.Name = "DexGuiTransform"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = false
		gui.DisplayOrder = (Main.DisplayOrders.SideWindow or 8) - 2
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
		pcall(function()
			gui.ClipToDeviceSafeArea = false
			gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		end)
		Lib.ShowGui(gui)
		Main.FocusIgnoredGuis = Main.FocusIgnoredGuis or setmetatable({}, { __mode = "k" })
		Main.FocusIgnoredGuis[gui] = true
		view = Apps.GuiTransformView.Create(gui, begin)
		T.View = view
		T.Gui = gui
		cursor = Instance.new("ImageLabel")
		cursor.Name = "Cursor"
		cursor.BackgroundTransparency = 1
		cursor.Size = UDim2.fromOffset(64, 64)
		cursor.AnchorPoint = Vector2.new(0.5, 0.5)
		cursor.Active = false
		cursor.ZIndex = 20
		cursor.Visible = false
		cursor.Parent = gui
		Main.TrackSignal(Apps.Explorer.Selection.Changed, refresh)
		Main.TrackSignal(input.InputChanged, function(e)
			if
				gesture
				and ((not gesture.Touch and e.UserInputType == Enum.UserInputType.MouseMovement) or gesture.Touch == e)
			then
				gesture.Pointer = point(e.Position)
			end
		end)
		Main.TrackSignal(input.InputEnded, function(e)
			if
				gesture
				and ((not gesture.Touch and e.UserInputType == Enum.UserInputType.MouseButton1) or gesture.Touch == e)
			then
				if e.Position then
					gesture.Pointer = point(e.Position)
				end
				local ok, err = pcall(apply, gesture.Pointer)
				if not ok then
					finish(true)
					report(err)
				else
					finish(false)
				end
			end
		end)
		Main.TrackSignal(input.InputBegan, function(e)
			if gesture and e.KeyCode == Enum.KeyCode.Escape then
				finish(true)
			end
		end)
		local name = "DexGuiTransform_" .. tostring(math.floor(os.clock() * 1e6))
		pcall(function()
			service.ContextActionService:BindActionAtPriority(
				name,
				function(_, state, e)
					if gesture then
						return Enum.ContextActionResult.Sink
					end
					if
						state == Enum.UserInputState.Begin
						and T.Enabled
						and view.Visible
						and not input:GetFocusedTextBox()
					then
						local p = point(e.Position)
						if not blocked(p) and begin(view:HitTest(p), e) then
							return Enum.ContextActionResult.Sink
						end
					end
					return Enum.ContextActionResult.Pass
				end,
				false,
				(Main.InputLockPriority or 10000000) + 2,
				Enum.UserInputType.MouseButton1,
				Enum.UserInputType.Touch
			)
		end)
		if input.WindowFocusReleased then
			Main.TrackSignal(input.WindowFocusReleased, function()
				finish(true)
				clearCursor()
			end)
		end
		Main.AddCleanup(function()
			destroyed = true
			finish(true)
			clearCursor()
			for _, con in ipairs(selectionConnections) do
				con:Disconnect()
			end
			table.clear(selectionConnections)
			if connection then
				connection:Disconnect()
				connection = nil
			end
			pcall(function()
				service.ContextActionService:UnbindAction(name)
			end)
			view:Destroy()
			gui:Destroy()
		end)
		refresh()
	end
	return T
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
