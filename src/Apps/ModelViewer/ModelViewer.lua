--!strict

local Main, Lib, Apps, Settings, env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, env, service = d.Main, d.Lib, d.Apps, d.Settings, d.env, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Viewer = {
		EnableInputCamera = true,
		IsViewing = false,
		AutoRefresh = false,
		AutoRotate = false,
		RotationSpeed = 0.25,
		RefreshRate = 1,
		GridVisible = true,
		Lighting = "Neutral",
		Background = "Dark",
		TouchPan = false,
	}
	local window, viewport, camera, state, scene, original, selected, menu, pathLabel, status, empty, toolbar, footer, help, helpButton
	local buttons = {}
	local gesture
	local touches = {}
	local hovering = false
	local dirty = false
	local elapsed = 0
	local renderConnection, syncRendering, refreshPending
	local layoutToolbar
	local lights = {
		Neutral = { Color3.fromRGB(140, 140, 140), Color3.fromRGB(255, 255, 255), Vector3.new(-1, -1, -1) },
		Soft = { Color3.fromRGB(185, 185, 195), Color3.fromRGB(190, 190, 210), Vector3.new(-0.4, -1, -0.2) },
		Flat = { Color3.new(1, 1, 1), Color3.new(0, 0, 0), Vector3.new(0, -1, 0) },
	}
	local function node(class, props)
		local value = Instance.new(class)
		for key, item in pairs(props) do
			value[key] = item
		end
		return value
	end
	local function visible()
		return window and window:IsVisible() and not window.Minimized and viewport.Visible
	end
	local function vector(value)
		return Vector3.new(value.X, value.Y, value.Z)
	end
	local function path(object)
		if not object then
			return ""
		end
		local ok, value = pcall(function()
			return Apps.Explorer.GetInstancePath(object)
		end)
		return ok and value or object.Name
	end
	local function info(message)
		if not status then
			return
		end
		status.Text = message
			or (scene and tostring(scene.PartCount) .. (scene.PartCount == 1 and " part" or " parts") or "No model")
		status.Size = message and UDim2.new(1, -36, 1, 0) or UDim2.new(0, 68, 1, 0)
		pathLabel.Visible = message == nil and original ~= nil
		pathLabel.Text = selected and selected.Name or original and original.Name or ""
	end
	local function tooltip(widget, text)
		if Lib.StudioTooltip then
			Lib.StudioTooltip(widget, text)
		end
	end
	local function escaped(value)
		return value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	end
	local function applyCamera()
		if not state or not scene then
			return
		end
		local position, target = state:Pose()
		camera.CFrame = CFrame.lookAt(vector(position), vector(target))
		camera.Focus = CFrame.new(vector(target))
		dirty = false
	end
	local function updateButtons()
		if not buttons.Light then
			return
		end
		buttons.Light.Caption.Text = Viewer.Lighting
		buttons.Background.Caption.Text = Viewer.Background
		buttons.Pan.Text = Viewer.TouchPan and "Pan" or "Orbit"
		for _, key in ipairs({ "Grid", "Spin", "Pan" }) do
			local active = key == "Grid" and Viewer.GridVisible
				or key == "Spin" and Viewer.AutoRotate
				or key == "Pan" and Viewer.TouchPan
			buttons[key].BackgroundColor3 = active and Color3.fromRGB(9, 71, 113) or Color3.fromRGB(43, 44, 48)
			buttons[key]:SetAttribute("Checked", active == true)
			buttons[key].BackgroundTransparency = active and 0 or 1
		end
		if layoutToolbar then
			layoutToolbar()
		end
	end
	local function dispose()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		gesture = nil
		table.clear(touches)
		if scene then
			scene:Destroy()
			scene = nil
		end
		Viewer.Scene = nil
		Viewer.IsViewing = false
	end
	function Viewer.SetLighting(name)
		local preset = assert(lights[name], "Unknown preview lighting preset")
		Viewer.Lighting = name
		if viewport then
			viewport.Ambient = preset[1]
			viewport.LightColor = preset[2]
			viewport.LightDirection = preset[3]
			updateButtons()
		end
	end
	function Viewer.SetBackground(name)
		assert(name == "Dark" or name == "Light" or name == "Transparent", "Unknown preview background")
		Viewer.Background = name
		if viewport then
			viewport.BackgroundColor3 = name == "Light" and Color3.fromRGB(222, 224, 228) or Color3.fromRGB(24, 25, 29)
			viewport.BackgroundTransparency = name == "Transparent" and 1 or 0
			window.GuiElems.Content.BackgroundTransparency = 1
			updateButtons()
		end
	end
	function Viewer.SetGrid(enabled)
		Viewer.GridVisible = enabled == true
		if scene then
			scene:SetGrid(Viewer.GridVisible)
		end
		updateButtons()
	end
	function Viewer.Fit(reset)
		if not scene then
			return
		end
		state:Fit(scene.Radius, viewport.AbsoluteSize.X / math.max(1, viewport.AbsoluteSize.Y), reset)
		dirty = true
		applyCamera()
	end
	function Viewer.ResetCamera()
		Viewer.AutoRotate = false
		updateButtons()
		Viewer.Fit(true)
	end
	function Viewer.Zoom(steps)
		if scene then
			state:Zoom(steps)
			dirty = true
		end
	end
	function Viewer.StopViewModel()
		dispose()
		original = nil
		selected = nil
		if window then
			window:SetTitle("3D Preview")
			pathLabel.Text = ""
			empty.Visible = true
			info()
		end
	end
	function Viewer.ViewModel(item, updating)
		if not item or not viewport then
			return false
		end
		local started = os.clock()
		local ok, nextScene = pcall(Apps.PreviewScene.Build, item)
		if not ok then
			info("Preview failed: " .. tostring(nextScene))
			return false
		end
		dispose()
		scene = nextScene
		Viewer.Scene = scene
		original = item
		Viewer.IsViewing = true
		scene.World.Parent = viewport
		scene:SetGrid(Viewer.GridVisible)
		if updating then
			state.Radius = scene.Radius
			state.Minimum = math.max(0.05, scene.Radius * 0.03)
			state.Maximum = math.max(state.Distance, scene.Radius * 1000)
		else
			selected = nil
			Viewer.Fit(true)
		end
		scene:Select(selected)
		empty.Visible = false
		window:SetTitle(item.Name .. " - 3D Preview")
		if not updating then
			window:Show()
		end
		dirty = true
		applyCamera()
		info()
		if syncRendering then
			syncRendering()
		end
		if Viewer.AutoRefresh and os.clock() - started > 0.05 then
			Viewer.AutoRefresh = false
			info("Auto update paused. Use Refresh for this model.")
		end
		return true
	end
	function Viewer.Refresh()
		if original then
			return Viewer.ViewModel(original, true)
		end
		return false
	end
	function Viewer.SelectAt(x, y)
		if not scene then
			return
		end
		local origin, direction = state:Ray(x, y, viewport.AbsoluteSize.X, viewport.AbsoluteSize.Y)
		local object = scene:Pick(origin, direction, math.max(1000, state.Distance + scene.Radius * 4))
		selected = object
		scene:Select(object)
		if object then
			local explorer = Apps.Explorer
			if explorer.GetNodes()[object] then
				explorer.SelectService(object)
				explorer.ViewObj(object)
			end
			info()
		else
			info()
		end
		return object
	end
	local function showMenu(x, y)
		if help then
			help.Visible = false
		end
		menu = menu or Apps.ContextMenu.new()
		Viewer.ContextMenu = menu
		menu:Clear()
		menu.Iconless = true
		menu.Width = 270
		menu:ApplyTheme({
			RowHeight = 24,
			TextSize = 13,
			CornerRadius = 4,
			SubmenuImage = Main.GetStudioAsset("native/editor/submenu") or "",
		})
		local function add(name, callback, disabled, shortcut)
			menu:Add({ Name = name, OnClick = callback, Disabled = disabled, Shortcut = shortcut })
		end
		add("Frame Model", function()
			Viewer.Fit()
		end, not scene, "F")
		add("Reset Camera", Viewer.ResetCamera, not scene, "R")
		add("Zoom In", function()
			Viewer.Zoom(1)
		end, not scene)
		add("Zoom Out", function()
			Viewer.Zoom(-1)
		end, not scene)
		add("Refresh", Viewer.Refresh, not original)
		menu:AddDivider()
		local function presets(values, choose)
			local result = {}
			for _, value in ipairs(values) do
				result[#result + 1] = {
					Name = value,
					OnClick = function()
						choose(value)
					end,
				}
			end
			return result
		end
		menu:Add({ Name = "Lighting", Submenu = presets({ "Neutral", "Soft", "Flat" }, Viewer.SetLighting) })
		menu:Add({ Name = "Background", Submenu = presets({ "Dark", "Light", "Transparent" }, Viewer.SetBackground) })
		menu:AddDivider()
		add(Viewer.GridVisible and "Hide Grid" or "Show Grid", function()
			Viewer.SetGrid(not Viewer.GridVisible)
		end)
		add(Viewer.AutoRotate and "Stop Rotation" or "Start Rotation", function()
			Viewer.AutoRotate = not Viewer.AutoRotate
			updateButtons()
		end)
		add(Viewer.AutoRefresh and "Disable Auto Update" or "Enable Auto Update", function()
			Viewer.AutoRefresh = not Viewer.AutoRefresh
			elapsed = 0
		end, not original)
		add(Viewer.TouchPan and "Switch to Orbit" or "Switch to Pan", function()
			Viewer.TouchPan = not Viewer.TouchPan
			updateButtons()
		end)
		add(Viewer.EnableInputCamera and "Lock Camera" or "Unlock Camera", function()
			Viewer.EnableInputCamera = not Viewer.EnableInputCamera
			gesture = nil
			table.clear(touches)
		end)
		if type(env.setclipboard) == "function" then
			add("Copy Path", function()
				if original then
					env.setclipboard(path(original))
				end
			end, not original)
		end
		if type(env.saveinstance) == "function" then
			add("Save Model...", function()
				local source = original
				if not source then
					return
				end
				Lib.SaveAsPrompt(source.Name, function(filename)
					local ok, problem =
						pcall(env.saveinstance, source, filename, { Decompile = true, RemovePlayerCharacters = false })
					info(ok and "Model saved." or "Save failed: " .. tostring(problem))
				end)
			end, not original)
		end
		menu:AddDivider()
		add("Clear Preview", Viewer.StopViewModel, not original)
		menu:Show(x, y)
	end
	local function showChoices(button, values, current, choose)
		if help then
			help.Visible = false
		end
		menu = menu or Apps.ContextMenu.new()
		Viewer.ContextMenu = menu
		menu:Clear()
		menu.Iconless = true
		menu.Width = 190
		menu:ApplyTheme({ RowHeight = 24, TextSize = 13, CornerRadius = 2 })
		for _, value in ipairs(values) do
			menu:Add({
				Name = value,
				Shortcut = value == current and "Current" or "",
				OnClick = function()
					choose(value)
				end,
			})
		end
		menu:Show(button.AbsolutePosition.X, button.AbsolutePosition.Y + button.AbsoluteSize.Y + 2)
	end
	local function point(input)
		return { X = input.Position.X, Y = input.Position.Y }
	end
	local function inside(pos)
		local origin, size = viewport.AbsolutePosition, viewport.AbsoluteSize
		return pos.X >= origin.X and pos.Y >= origin.Y and pos.X < origin.X + size.X and pos.Y < origin.Y + size.Y
	end
	local function blocked()
		return Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown()
	end
	local function shift()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or service.UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end
	local function touchPair()
		local pair = {}
		for input, pos in pairs(touches) do
			pair[#pair + 1] = { Input = input, Position = pos }
			if #pair == 2 then
				break
			end
		end
		if #pair < 2 then
			return
		end
		local a, b = pair[1].Position, pair[2].Position
		return { X = (a.X + b.X) / 2, Y = (a.Y + b.Y) / 2 }, math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
	end
	function Viewer.Init()
		window = Lib.Window.new()
		window:SetTitle("3D Preview")
		window.MinX = 320
		window.MinY = 240
		window:Resize(600, 430)
		Viewer.Window = window
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		state = Apps.PreviewCamera.Create()
		Viewer.CameraState = state
		local content = window.GuiElems.Content
		local chrome = Color3.fromRGB(33, 34, 39)
		toolbar = node("ScrollingFrame", {
			Name = "PreviewToolbar",
			Parent = content,
			Size = UDim2.new(1, -36, 0, 30),
			BackgroundColor3 = chrome,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(544, 0),
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.X,
		})
		local offset = 5
		local function button(key, text, width, callback, description)
			local value = node("TextButton", {
				Name = key,
				Parent = toolbar,
				Text = text,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = Color3.fromRGB(204, 204, 204),
				BackgroundColor3 = Color3.fromRGB(43, 44, 48),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Position = UDim2.fromOffset(offset, 3),
				Size = UDim2.fromOffset(width, 24),
			})
			node("UICorner", { Parent = value, CornerRadius = UDim.new(0, 2) })
			value.MouseButton1Click:Connect(function()
				if help then
					help.Visible = false
				end
				callback()
			end)
			offset += width + 4
			buttons[key] = value
			value.MouseEnter:Connect(function()
				value.BackgroundTransparency = 0
			end)
			value.MouseLeave:Connect(function()
				value.BackgroundTransparency = value:GetAttribute("Checked") and 0 or 1
			end)
			tooltip(value, description)
			return value
		end
		button("Fit", "Fit", 32, function()
			Viewer.Fit()
		end, "Frame the entire model (F)")
		button("Reset", "Reset", 42, Viewer.ResetCamera, "Reset camera position and rotation (R)")
		button("Pan", "Orbit", 48, function()
			Viewer.TouchPan = not Viewer.TouchPan
			updateButtons()
			info()
		end, "Switch between orbit and pan dragging")
		button("Light", "Neutral", 76, function()
			showChoices(buttons.Light, { "Neutral", "Soft", "Flat" }, Viewer.Lighting, Viewer.SetLighting)
		end, "Lighting preset")
		button("Background", "Dark", 98, function()
			showChoices(buttons.Background, { "Dark", "Light", "Transparent" }, Viewer.Background, Viewer.SetBackground)
		end, "Preview background")
		for _, key in ipairs({ "Light", "Background" }) do
			local button = buttons[key]
			node("TextLabel", {
				Name = "Caption",
				Parent = button,
				Text = button.Text,
				Font = button.Font,
				TextSize = button.TextSize,
				TextColor3 = button.TextColor3,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -32, 1, 0),
			})
			button.Text = ""
			node("ImageLabel", {
				Parent = button,
				Name = "DropdownArrow",
				Image = Main.GetStudioAsset("native/editor/submenu") or "",
				Rotation = 90,
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -20, 0.5, -8),
				Size = UDim2.fromOffset(16, 16),
			})
		end
		button("Grid", "Grid", 38, function()
			Viewer.SetGrid(not Viewer.GridVisible)
		end, "Show or hide the floor grid")
		button("Spin", "Rotate", 50, function()
			Viewer.AutoRotate = not Viewer.AutoRotate
			updateButtons()
		end, "Automatically rotate the preview")
		local more = button("More", "...", 28, function()
			local p = buttons.More.AbsolutePosition
			showMenu(p.X, p.Y + 26)
		end, "More preview options")
		local actions = node("Frame", {
			Name = "PreviewActions",
			Parent = content,
			Position = UDim2.new(1, -36, 0, 0),
			Size = UDim2.fromOffset(36, 30),
			BackgroundColor3 = chrome,
			BorderSizePixel = 0,
		})
		more.Parent = actions
		more.Position = UDim2.fromOffset(4, 3)
		layoutToolbar = function()
			local x = 6
			for _, key in ipairs({ "Fit", "Reset", "Pan", "Light", "Background", "Grid", "Spin" }) do
				if key == "Light" or key == "Grid" then
					x += 4
				end
				local button = buttons[key]
				local caption = button:FindFirstChild("Caption")
				local measured = service.TextService:GetTextSize(
					caption and caption.Text or button.Text,
					button.TextSize,
					button.Font,
					Vector2.new(10000, 24)
				)
				local width = math.max(28, math.ceil(measured.X) + (caption and 32 or 16))
				button.Position = UDim2.fromOffset(x, 3)
				button.Size = UDim2.fromOffset(width, 24)
				x += width + 4
			end
			toolbar.CanvasSize = UDim2.fromOffset(x + 2, 0)
		end
		viewport = node("ViewportFrame", {
			Name = "PreviewViewport",
			Parent = content,
			Active = true,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 1, -52),
			BorderSizePixel = 0,
		})
		Viewer.Viewport = viewport
		camera = Instance.new("Camera")
		camera.Name = "PreviewCamera"
		camera.FieldOfView = state.FieldOfView
		camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		empty = node("TextLabel", {
			Name = "Empty",
			Parent = viewport,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = "3D Preview\n\nRight-click a Model or Part in Explorer to preview it",
			TextColor3 = Color3.fromRGB(145, 149, 159),
			Font = Lib.StudioFont,
			TextSize = 14,
			TextWrapped = true,
		})
		footer = node("Frame", {
			Name = "PreviewFooter",
			Parent = content,
			Position = UDim2.new(0, 0, 1, -22),
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = chrome,
			BorderSizePixel = 0,
		})
		status = node("TextLabel", {
			Name = "Status",
			Parent = footer,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(0, 68, 1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Color3.fromRGB(155, 157, 165),
			Font = Lib.StudioFont,
			TextSize = 12,
			BackgroundTransparency = 1,
		})
		pathLabel = node("TextButton", {
			Name = "SourcePath",
			Parent = footer,
			Position = UDim2.fromOffset(80, 0),
			Size = UDim2.new(1, -112, 1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = Color3.fromRGB(204, 204, 204),
			Font = Lib.StudioFont,
			TextSize = 12,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		})
		pathLabel.MouseButton1Click:Connect(function()
			local object = selected or original
			if object and Apps.Explorer.GetNodes()[object] then
				Apps.Explorer.SelectService(object)
				Apps.Explorer.ViewObj(object)
			end
		end)
		tooltip(pathLabel, function()
			return escaped(path(selected or original)) .. "\nReveal in Explorer"
		end)
		tooltip(status, function()
			return escaped(status.Text)
		end)
		helpButton = node("TextButton", {
			Name = "Help",
			Parent = footer,
			Position = UDim2.new(1, -28, 0, 0),
			Size = UDim2.new(0, 24, 1, 0),
			Text = "?",
			TextColor3 = Color3.fromRGB(180, 182, 190),
			Font = Lib.StudioFont,
			TextSize = 13,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
		tooltip(helpButton, "Preview navigation controls")
		help = node("Frame", {
			Name = "NavigationHelp",
			Parent = viewport,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -8),
			Size = UDim2.fromOffset(276, 164),
			BackgroundColor3 = chrome,
			BorderColor3 = Color3.fromRGB(55, 57, 64),
			BorderSizePixel = 1,
			Visible = false,
			Active = true,
			ZIndex = 5,
		})
		node("TextLabel", {
			Parent = help,
			Text = "Navigation",
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 22),
			Font = Lib.StudioFont,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			ZIndex = 6,
		})
		for index, row in ipairs({
			{ "Orbit", "Drag" },
			{ "Pan", "Shift-drag / middle mouse" },
			{ "Zoom", "Scroll / pinch" },
			{ "Select part", "Click" },
			{ "Frame / reset", "F / R" },
			{ "Touch pan", "Two-finger drag" },
		}) do
			for column, value in ipairs(row) do
				node("TextLabel", {
					Parent = help,
					Text = value,
					Position = UDim2.fromOffset(column == 1 and 12 or 100, 32 + (index - 1) * 20),
					Size = UDim2.fromOffset(column == 1 and 84 or 168, 20),
					Font = Lib.StudioFont,
					TextSize = 12,
					TextColor3 = column == 1 and Color3.fromRGB(204, 204, 204) or Color3.fromRGB(155, 157, 165),
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					ZIndex = 6,
				})
			end
		end
		helpButton.MouseButton1Click:Connect(function()
			help.Visible = not help.Visible
		end)
		Viewer.Help = help
		Viewer.Footer = footer
		Viewer.SetLighting(Viewer.Lighting)
		Viewer.SetBackground(Viewer.Background)
		updateButtons()
		info()
		viewport.MouseEnter:Connect(function()
			hovering = true
		end)
		viewport.MouseLeave:Connect(function()
			hovering = false
		end)
		viewport.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if help.Visible then
				help.Visible = false
				return
			end
			if blocked() then
				return
			end
			if kind == Enum.UserInputType.MouseButton2 and (not scene or not Viewer.EnableInputCamera) then
				gesture = {
					Input = input,
					Kind = kind,
					Start = point(input),
					Last = point(input),
					Mode = "Menu",
					Moved = false,
				}
				return
			end
			if not scene or not Viewer.EnableInputCamera then
				return
			end
			if
				kind ~= Enum.UserInputType.MouseButton1
				and kind ~= Enum.UserInputType.MouseButton2
				and kind ~= Enum.UserInputType.MouseButton3
				and kind ~= Enum.UserInputType.Touch
			then
				return
			end
			local pos = point(input)
			Viewer.AutoRotate = false
			updateButtons()
			if kind == Enum.UserInputType.Touch then
				touches[input] = pos
				local center, length = touchPair()
				if center then
					gesture = { Mode = "Pinch", Center = center, Length = length, Moved = true }
					return
				end
			elseif gesture then
				return
			end
			gesture = {
				Input = input,
				Kind = kind,
				Start = pos,
				Last = pos,
				Mode = (kind == Enum.UserInputType.MouseButton3 or Viewer.TouchPan or shift()) and "Pan" or "Orbit",
				Moved = false,
			}
		end)
		viewport.InputChanged:Connect(function(input)
			if
				visible()
				and scene
				and Viewer.EnableInputCamera
				and not blocked()
				and input.UserInputType == Enum.UserInputType.MouseWheel
			then
				Viewer.Zoom(input.Position.Z)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if not gesture or not visible() or not Viewer.EnableInputCamera or gesture.Mode == "Menu" then
				return
			end
			local pos = point(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				if not touches[input] then
					return
				end
				touches[input] = pos
				if gesture.Mode == "Pinch" then
					local center, length = touchPair()
					if not center then
						return
					end
					state:Pan(center.X - gesture.Center.X, center.Y - gesture.Center.Y, viewport.AbsoluteSize.Y)
					if length > 1 and gesture.Length > 1 then
						state:Zoom(math.log(length / gesture.Length) / 0.15)
					end
					gesture.Center = center
					gesture.Length = length
					dirty = true
					return
				elseif input ~= gesture.Input then
					return
				end
			elseif
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				or gesture.Kind == Enum.UserInputType.Touch
				or gesture.Mode == "Pinch"
			then
				return
			end
			local dx, dy = pos.X - gesture.Last.X, pos.Y - gesture.Last.Y
			gesture.Last = pos
			if (pos.X - gesture.Start.X) ^ 2 + (pos.Y - gesture.Start.Y) ^ 2 >= 16 then
				gesture.Moved = true
			end
			if not gesture.Moved then
				return
			end
			if gesture.Mode == "Pan" then
				state:Pan(dx, dy, viewport.AbsoluteSize.Y)
			else
				state:Orbit(dx, dy)
			end
			dirty = true
		end)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				if not touches[input] then
					return
				end
				touches[input] = nil
				if gesture and gesture.Mode == "Pinch" then
					gesture = nil
					table.clear(touches)
					return
				end
			end
			if not gesture or (input ~= gesture.Input and input.UserInputType ~= gesture.Kind) then
				return
			end
			local ended = gesture
			gesture = nil
			if ended.Moved or not visible() then
				return
			end
			local pos = point(input)
			if not inside(pos) then
				return
			end
			if ended.Kind == Enum.UserInputType.MouseButton2 then
				showMenu(pos.X, pos.Y)
			elseif
				ended.Mode ~= "Pan"
				and (ended.Kind == Enum.UserInputType.MouseButton1 or ended.Kind == Enum.UserInputType.Touch)
			then
				local origin = viewport.AbsolutePosition
				Viewer.SelectAt(pos.X - origin.X, pos.Y - origin.Y)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				help.Visible = false
			end
			if
				not hovering
				or not visible()
				or not Viewer.EnableInputCamera
				or service.UserInputService:GetFocusedTextBox()
				or blocked()
			then
				return
			end
			if input.KeyCode == Enum.KeyCode.F then
				Viewer.Fit()
			elseif input.KeyCode == Enum.KeyCode.R then
				Viewer.ResetCamera()
			end
		end)
		Main.TrackSignal(service.UserInputService.WindowFocusReleased, function()
			gesture = nil
			table.clear(touches)
		end)
		Main.TrackSignal(viewport:GetPropertyChangedSignal("AbsoluteSize"), function()
			if scene and viewport.AbsoluteSize.Y > 0 then
				state:Resize(viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y)
				dirty = true
			end
		end)
		local function renderPreview(dt)
			if not visible() or not scene then
				return
			end
			if Viewer.AutoRotate and not gesture then
				state.Yaw += Viewer.RotationSpeed * math.min(dt, 0.1)
				dirty = true
			end
			if dirty then
				applyCamera()
			end
			if Viewer.AutoRefresh then
				elapsed += dt
				if elapsed >= 1 / math.clamp(Viewer.RefreshRate, 0.1, 1) and not gesture and not refreshPending then
					elapsed = 0
					local current = scene
					refreshPending = true
					task.defer(function()
						refreshPending = false
						if
							Main.Alive ~= false
							and scene == current
							and visible()
							and Viewer.AutoRefresh
							and not gesture
						then
							Viewer.Refresh()
						end
					end)
				end
			else
				elapsed = 0
			end
		end
		syncRendering = function()
			if visible() and scene then
				if not renderConnection then
					renderConnection = service.RunService.RenderStepped:Connect(renderPreview)
				end
			elseif renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end
		end
		local function suspend()
			help.Visible = false
			gesture = nil
			table.clear(touches)
			if menu then
				menu:Hide()
			end
			if window.Closed or window.Minimized then
				dispose()
			end
			syncRendering()
		end
		local function resume()
			if original and not scene and visible() then
				Viewer.Refresh()
			end
			syncRendering()
		end
		Main.TrackSignal(window.OnDeactivate, suspend)
		Main.TrackSignal(window.OnMinimize, suspend)
		Main.TrackSignal(window.OnActivate, resume)
		Main.TrackSignal(window.OnRestore, resume)
		Main.TrackSignal(Apps.Explorer.Selection.Changed, function()
			if scene then
				local first = Apps.Explorer.Selection.List[1]
				selected = first and scene.Reverse[first.Obj] and first.Obj or nil
				scene:Select(selected)
				info()
			end
		end)
		Main.AddCleanup(function()
			dispose()
			if menu then
				menu:Destroy()
			end
			camera:Destroy()
		end)
	end
	return Viewer
end
return { InitDeps = InitDeps, Main = CreateModule }
