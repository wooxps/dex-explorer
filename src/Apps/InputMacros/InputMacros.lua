--!strict

local Apps, Main, Lib, service

local function InitDeps(deps)
	Apps, Main, Lib, service = deps.Apps, deps.Main, deps.Lib, deps.service
end

local hotkeys = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F9", "F10", "F11", "F12" }
local stopKey = Enum.KeyCode.F8
local rowHeight = 24
local libraryRowHeight = 26
local empty = table.freeze({})
local mouseNames = { "Left Mouse", "Right Mouse", "Middle Mouse" }

local function eventText(event)
	if event.Kind == "KeyDown" or event.Kind == "KeyUp" then
		return event.Key, if event.Kind == "KeyDown" then "Press" else "Release"
	elseif event.Kind == "ButtonDown" or event.Kind == "ButtonUp" then
		return mouseNames[event.Button] or "Mouse", if event.Kind == "ButtonDown" then "Press" else "Release"
	elseif event.Kind == "Move" then
		if event.X and event.Y then
			return "Mouse", ("%d%%, %d%%"):format(math.round(event.X * 100), math.round(event.Y * 100))
		end
		return "Mouse", "Move"
	elseif event.Kind == "RelativeMove" then
		return "Mouse", ("%+g, %+g px"):format(event.DeltaX, event.DeltaY)
	end
	return "Mouse Wheel", ("%+g"):format(event.Delta or 0)
end

local function CreateModule()
	local app = {}
	local input = service.UserInputService
	local macros, active, engine
	local initialized, controls, picker, window, hud
	local selectedEvent
	local bindings = {}
	local hotkeyConnection
	local shownDuringAction, recordingTarget
	local notice, storageError, playbackProgress
	local playbackCheckMacro, canPlay, playbackIssue
	local repaint, showHud, hideHud, updateHudProgress, startPlayback
	local playbackCount = 0

	local function persist()
		playbackCheckMacro = nil
		if Apps.MacroStore.Available() then
			local ok, reason = Apps.MacroStore.Save(macros)
			storageError = if ok then nil else reason or "Could not save macros."
		end
	end

	local function playingKey(event)
		return event.UserInputType == Enum.UserInputType.Keyboard and event.KeyCode.Name
	end

	local function updateBindings()
		table.clear(bindings)
		for _, macro in ipairs(macros) do
			if macro.Hotkey and macro.Hotkey ~= stopKey.Name and not bindings[macro.Hotkey] then
				bindings[macro.Hotkey] = macro
			end
		end
		if next(bindings) and not hotkeyConnection then
			hotkeyConnection = input.InputBegan:Connect(function(event, processed)
				if processed or engine.State ~= "Idle" or input:GetFocusedTextBox() then
					return
				end
				local macro = bindings[playingKey(event)]
				if macro and #macro.Events > 0 then
					startPlayback(macro)
				end
			end)
		elseif not next(bindings) and hotkeyConnection then
			hotkeyConnection:Disconnect()
			hotkeyConnection = nil
		end
	end

	local function setNotice(value)
		notice = value
		if repaint then
			repaint()
		end
	end

	local function activate(macro)
		active = macro
		selectedEvent = nil
		if controls then
			controls.List.CanvasPosition = Vector2.zero
		end
		setNotice(nil)
	end

	local function createMacro()
		if #macros >= (Apps.MacroStore.MaxMacros or 32) then
			setNotice("Macro limit reached.")
			return
		end
		local names = {}
		for _, macro in ipairs(macros) do
			names[macro.Name] = true
		end
		local number = 1
		while names["Macro " .. number] do
			number += 1
		end
		local macro = { Name = "Macro " .. number, Events = {}, Loop = false, Speed = 1 }
		macros[#macros + 1] = macro
		activate(macro)
		persist()
		repaint()
	end

	local function createHud()
		local ui = Apps.BridgeUI.Create()
		local theme = ui.Theme
		local dark = theme.IconTheme ~= "Light"
		local surface = if dark then Color3.fromRGB(27, 28, 32) else theme.Menu
		local border = if dark then Color3.fromRGB(64, 67, 74) else theme.Outline2
		local text = if dark then Color3.fromRGB(240, 241, 243) else theme.Text
		local muted = if dark then Color3.fromRGB(147, 151, 159) else theme.PlaceholderText
		local blue = if dark then Color3.fromRGB(49, 125, 247) else theme.Focus
		local width, height = 330, 38
		local gui = ui:Node("ScreenGui", {
			Name = "InputMacroStatus",
			DisplayOrder = Main.DisplayOrders.Core,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Enabled = false,
		})
		Main.FocusIgnoredGuis = Main.FocusIgnoredGuis or setmetatable({}, { __mode = "k" })
		local panel = ui:Node("Frame", {
			Parent = gui,
			Name = "Status",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -12),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = surface,
			BorderSizePixel = 0,
		})
		ui:Round(panel, 4)
		ui:Outline(panel, border)
		local scale = ui:Node("UIScale", { Parent = panel, Scale = 1 })
		local function fitHud()
			local available = gui.AbsoluteSize.X
			scale.Scale = if available > 0 then math.clamp((available - 24) / width, 0.5, 1) else 1
		end
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHud)

		local function textLabel(parent, name, value, x, y, w, h, color, fontSize)
			local label = ui:Text(parent, name, value, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), false, fontSize)
			label.TextColor3 = color
			label.Interactable = false
			return label
		end
		local dot = ui:Node("Frame", {
			Parent = panel,
			Name = "RecordDot",
			Position = UDim2.fromOffset(11, 15),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.fromRGB(224, 82, 77),
			BorderSizePixel = 0,
			Interactable = false,
		})
		ui:Round(dot, 4)
		local playImage = Main.GetStudioAsset("macro/play")
		local playIcon = if playImage
			then ui:Node("ImageLabel", {
				Parent = panel,
				Name = "PlayIcon",
				Position = UDim2.fromOffset(8, 12),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				ImageColor3 = blue,
				Image = playImage,
				Interactable = false,
			})
			else textLabel(panel, "PlayIcon", "▶", 10, 0, 14, height, blue, 11)
		local caption = textLabel(panel, "Mode", "", 29, 0, 79, height, text, 13)
		caption.Font = Enum.Font.BuilderSansMedium
		local metric = textLabel(panel, "Metric", "", 160, 0, 53, height, muted, 12)
		metric.TextXAlignment = Enum.TextXAlignment.Right
		local rail = ui:Node("Frame", {
			Parent = panel,
			Name = "Progress",
			Position = UDim2.fromOffset(85, 16),
			Size = UDim2.fromOffset(85, 6),
			BackgroundColor3 = if dark then Color3.fromRGB(61, 64, 70) else theme.Outline2,
			BorderSizePixel = 0,
			Interactable = false,
		})
		ui:Round(rail, 3)
		local fill = ui:Node("Frame", {
			Parent = rail,
			Name = "Fill",
			BackgroundColor3 = blue,
			Size = UDim2.fromScale(0, 1),
			BorderSizePixel = 0,
			Interactable = false,
		})
		ui:Round(fill, 3)
		local separator = ui:Node("Frame", {
			Parent = panel,
			Name = "Separator",
			Size = UDim2.fromOffset(1, 18),
			BackgroundColor3 = border,
			BorderSizePixel = 0,
			Interactable = false,
		})
		local stop = ui:Button(panel, "Stop", "", UDim2.fromOffset(243, 7), UDim2.fromOffset(77, 24), function()
			engine:Stop()
		end, "quiet")
		ui:Round(stop.Gui, 3)
		textLabel(stop.Gui, "Caption", "Stop", 12, 0, 31, 24, text, 12)
		local playbackHint = textLabel(panel, "StopHint", "Stop", 259, 0, 32, height, muted, 12)
		local keycap = textLabel(panel, "Keycap", "F8", 295, 10, 24, 18, text, 11)
		keycap.TextXAlignment = Enum.TextXAlignment.Center
		keycap.ZIndex = 2
		ui:Round(keycap, 3)
		local keyOutline = ui:Outline(keycap, muted)
		local ticker
		Lib.ShowGui(gui)
		fitHud()
		hud = gui

		updateHudProgress = function(index, count)
			local value = ("%d / %d"):format(index, count)
			metric.Text = value
			metric.TextSize = if #value > 9 then 10 else 12
			fill.Size = UDim2.fromScale(if count > 0 then math.clamp(index / count, 0, 1) else 0, 1)
		end
		hideHud = function()
			if ticker then
				ticker:Disconnect()
				ticker = nil
			end
			Main.FocusIgnoredGuis[gui] = nil
			gui.Enabled = false
		end
		showHud = function(mode)
			local recording = mode == "Recording"
			Main.FocusIgnoredGuis[gui] = if recording then nil else true
			caption.Text = if recording then "Recording" else "Playing"
			caption.Size = UDim2.fromOffset(if recording then 100 else 55, height)
			dot.Visible = recording
			playIcon.Visible = not recording
			rail.Visible = not recording
			metric.Position = UDim2.fromOffset(if recording then 159 else 178, 0)
			metric.Size = UDim2.fromOffset(if recording then 53 else 50, height)
			separator.Position = UDim2.fromOffset(if recording then 228 else 241, 10)
			stop.Gui.Visible = recording
			keycap.Parent = if recording then stop.Gui else panel
			keycap.Position = if recording then UDim2.fromOffset(52, 3) else UDim2.fromOffset(295, 10)
			playbackHint.Visible = not recording
			keyOutline.Transparency = if recording then 0 else 0.24
			if recording then
				metric.Text = "00:00"
				metric.TextSize = 12
				local elapsed, lastSecond = 0, 0
				ticker = service.RunService.Heartbeat:Connect(function(dt)
					elapsed += dt
					local seconds = math.floor(elapsed)
					if seconds ~= lastSecond then
						lastSecond = seconds
						metric.Text = ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
					end
				end)
			else
				updateHudProgress(0, playbackCount)
			end
			gui.Enabled = true
		end
	end

	local function suspendWindow()
		if Main.SetGameInputLocked then
			Main.SetGameInputLocked(false)
		end
		if window and window:IsVisible() then
			shownDuringAction = true
			window:Hide(true)
		end
	end

	local function onState(state, reason, events)
		playbackProgress = nil
		if state ~= "Idle" then
			suspendWindow()
			if engine.State ~= state then
				return
			end
			if not hud then
				createHud()
			end
			showHud(state)
		else
			if hideHud then
				hideHud()
			end
			local target = recordingTarget
			recordingTarget = nil
			notice = if reason == "Stopped" or reason == "Finished" then nil else reason
			if target and events and #events > 0 then
				target.Events = events
				selectedEvent = nil
				persist()
			end
			if shownDuringAction and window and Main.Alive ~= false then
				window:Show()
				window:Focus()
			end
			shownDuringAction = false
		end
		if repaint then
			repaint()
		end
	end

	startPlayback = function(macro)
		if engine.State ~= "Idle" or #macro.Events == 0 then
			return
		end
		notice = nil
		playbackCount = #macro.Events
		local ok, reason = engine:Play(macro.Events, { Loop = macro.Loop, Speed = macro.Speed })
		if not ok then
			setNotice(reason)
		end
	end

	local function shouldRecord(event, _, _position)
		local key = playingKey(event)
		if key then
			local focused = input:GetFocusedTextBox()
			return not bindings[key] and not (focused and Main.IsDexGuiObject and Main.IsDexGuiObject(focused))
		end
		local kind = event.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			return true
		end
		local position = _position or event.Position or input:GetMouseLocation()
		return not Main.IsPointInDexUI or not Main.IsPointInDexUI(position.X, position.Y)
	end

	function app.Init()
		if initialized then
			return
		end
		initialized = true
		macros, storageError = Apps.MacroStore.Load()
		macros = macros or {}
		active = macros[1]
		engine = Apps.MacroEngine.Create({
			ShouldRecord = shouldRecord,
			IsStopInput = function(event)
				return event.UserInputType == Enum.UserInputType.Keyboard and event.KeyCode == stopKey
			end,
			OnState = onState,
			OnProgress = function(index, count)
				playbackProgress = ("%d / %d"):format(index, count)
				if updateHudProgress then
					updateHudProgress(index, count)
				end
				if controls and window:IsContentVisible() then
					controls.Status.Text = "Playing  " .. playbackProgress
				end
			end,
		})
		updateBindings()
		Main.AddCleanup(function()
			shownDuringAction = false
			if hotkeyConnection then
				hotkeyConnection:Disconnect()
				hotkeyConnection = nil
			end
			engine:Destroy()
			if picker then
				picker:Destroy()
			end
			if hud then
				hideHud()
				hud:Destroy()
			end
			if window then
				window:Destroy()
			end
		end)
	end

	local function showMenu(anchor, populate)
		picker = picker or Apps.ContextMenu.new()
		if picker.Shown and picker.Anchor == anchor then
			picker:Hide()
			return
		end
		picker.Anchor = anchor
		picker.Iconless = true
		picker.PreferredWidth = math.max(132, anchor.AbsoluteSize.X)
		picker.MaxHeight = 245
		picker:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
		picker:Clear()
		populate(picker)
		picker:Show(anchor.AbsolutePosition.X, anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 3)
	end

	local function buildWindow()
		local ui = Apps.BridgeUI.Create(true)
		local theme = ui.Theme
		local dark = theme.IconTheme ~= "Light"
		local bodyColor = dark and Color3.fromRGB(25, 26, 31) or theme.Menu
		local toolbarColor = dark and Color3.fromRGB(30, 31, 36) or theme.Main2
		local tableHeaderColor = dark and Color3.fromRGB(42, 44, 50) or theme.Button
		local dividerColor = dark and Color3.fromRGB(60, 63, 70) or theme.Outline2
		local selectionColor = dark and Color3.fromRGB(20, 49, 128) or theme.ListSelection
		window = Lib.Window.new()
		window.MinX = 310
		window.MinY = 292
		window:Resize(624, 417)
		window:SetTitle("Input Macros")
		window:SetResizeHandleStyle("Dock")
		app.Window = window

		local hoverColor = if dark then Color3.fromRGB(47, 49, 55) else theme.ButtonHover
		local pressedColor = if dark then Color3.fromRGB(56, 59, 66) else theme.ButtonPress or theme.ButtonHover
		local function button(parent, name, caption, position, size, callback, kind)
			local control = ui:Button(parent, name, caption, position, size, callback, kind)
			local paint = control.Paint
			function control:Paint()
				paint(self)
				if self.Kind == "quiet" then
					self.Gui.BackgroundColor3 = if self.Pressed then pressedColor else hoverColor
					self.Gui.BackgroundTransparency = if self.Enabled and (self.Hovered or self.Pressed) then 0 else 1
				end
			end
			ui:Round(control.Gui, 3)
			control:Paint()
			return control
		end

		local content = window.GuiElems.Content
		content.BackgroundColor3 = bodyColor
		local sidebar = ui:Node("Frame", {
			Parent = content,
			Name = "MacroLibrary",
			Size = UDim2.new(0, 151, 1, 0),
			BackgroundColor3 = bodyColor,
			BorderSizePixel = 0,
		})
		local pane = ui:Node("Frame", {
			Parent = content,
			Name = "Sequence",
			Position = UDim2.fromOffset(152, 0),
			Size = UDim2.new(1, -152, 1, 0),
			BackgroundColor3 = bodyColor,
			BorderSizePixel = 0,
		})
		local function rule(parent, position, size, color)
			return ui:Node("Frame", {
				Parent = parent,
				Position = position,
				Size = size,
				BackgroundColor3 = color or dividerColor,
				BorderSizePixel = 0,
			})
		end
		local paneDivider = rule(content, UDim2.fromOffset(151, 0), UDim2.new(0, 1, 1, 0), ui.Palette.Border)
		ui:Node("Frame", {
			Parent = sidebar,
			Name = "LibraryHeader",
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = toolbarColor,
			BorderSizePixel = 0,
		})
		rule(sidebar, UDim2.fromOffset(0, 35), UDim2.new(1, 0, 0, 1))
		local libraryTitle =
			ui:Text(sidebar, "LibraryTitle", "Macros", UDim2.fromOffset(11, 0), UDim2.new(1, -68, 0, 35), false, 13)
		libraryTitle.Font = Enum.Font.BuilderSansBold
		local macroList = ui:Node("ScrollingFrame", {
			Parent = sidebar,
			Name = "Macros",
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 1, -36),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = theme.PlaceholderText,
		})
		local add = button(sidebar, "New", "+", UDim2.new(1, -27, 0, 4), UDim2.fromOffset(24, 24), createMacro, "quiet")
		local addIcon
		local addImage = Main.GetStudioAsset("native/plugins/add")
		if addImage then
			add.Gui.Text = ""
			addIcon = ui:Node("ImageLabel", {
				Parent = add.Gui,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(5, 5),
				Size = UDim2.fromOffset(14, 14),
				Image = addImage,
				ImageColor3 = theme.Text,
			})
		end
		add.Gui.TextSize = 20
		ui:Round(add.Gui, 2)
		ui:Tip(add.Gui, "New Macro")
		local toolbar = ui:Node("Frame", {
			Parent = pane,
			Name = "Toolbar",
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = toolbarColor,
			BorderSizePixel = 0,
		})
		rule(toolbar, UDim2.fromOffset(0, 35), UDim2.new(1, 0, 0, 1))
		local name = ui:Field(toolbar, "Name", "Macro name", UDim2.fromOffset(8, 7), UDim2.new(0.615, 0, 0, 23))
		ui:Round(name, 3)
		name.TextSize = 13
		local count = ui:Text(toolbar, "EventCount", "", UDim2.new(1, -88, 0, 0), UDim2.fromOffset(79, 36), false)
		count.TextXAlignment = Enum.TextXAlignment.Right
		local menuButton = button(
			sidebar,
			"MacroActions",
			"…",
			UDim2.new(1, -54, 0, 4),
			UDim2.fromOffset(24, 24),
			function()
				showMenu(controls.Actions.Gui, function(menu)
					menu:Add({
						Text = "Delete Macro",
						OnClick = function()
							local index = table.find(macros, active)
							if index then
								table.remove(macros, index)
								activate(macros[index] or macros[index - 1])
								updateBindings()
								persist()
								repaint()
							end
						end,
					})
				end)
			end,
			"quiet"
		)
		local moreIcon
		local moreImage = Main.GetStudioAsset("native/plugins/more")
		if moreImage then
			menuButton.Gui.Text = ""
			moreIcon = ui:Node("ImageLabel", {
				Parent = menuButton.Gui,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(5, 5),
				Size = UDim2.fromOffset(14, 14),
				Image = moreImage,
				ImageColor3 = theme.Text,
			})
		end
		ui:Round(menuButton.Gui, 2)
		ui:Tip(menuButton.Gui, "Macro Actions")

		local transport = ui:Node("Frame", {
			Parent = pane,
			Name = "Transport",
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 35),
			BackgroundColor3 = toolbarColor,
			BorderSizePixel = 0,
		})
		local record = button(
			transport,
			"Record",
			"Record",
			UDim2.fromOffset(8, 5),
			UDim2.fromOffset(73, 24),
			function()
				if #active.Events > 0 and notice ~= "Click Record again to replace this recording." then
					setNotice("Click Record again to replace this recording.")
					return
				end
				notice = nil
				recordingTarget = active
				local ok, reason = engine:StartRecording()
				if not ok then
					recordingTarget = nil
					setNotice(reason)
				end
			end,
			"quiet"
		)
		record.Gui.TextXAlignment = Enum.TextXAlignment.Right
		ui:Node("UIPadding", { Parent = record.Gui, PaddingRight = UDim.new(0, 8) })
		local recordDot = ui:Node("Frame", {
			Parent = record.Gui,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Color3.fromRGB(240, 87, 89),
			BorderSizePixel = 0,
		})
		ui:Round(recordDot, 6)
		ui:Tip(record.Gui, "Record a new sequence for this macro")
		local recordDivider = rule(transport, UDim2.fromOffset(84, 7), UDim2.fromOffset(1, 20))
		local play = button(transport, "Play", "Play", UDim2.fromOffset(90, 5), UDim2.fromOffset(50, 24), function()
			startPlayback(active)
		end, "quiet")
		local playImage = Main.GetStudioAsset("macro/play")
		if playImage then
			play.Gui.TextXAlignment = Enum.TextXAlignment.Right
			ui:Node("UIPadding", { Parent = play.Gui, PaddingRight = UDim.new(0, 7) })
			ui:Node("ImageLabel", {
				Parent = play.Gui,
				Position = UDim2.fromOffset(4, 5),
				Size = UDim2.fromOffset(14, 14),
				Image = playImage,
				ImageColor3 = theme.Text,
				BackgroundTransparency = 1,
			})
		else
			play.Gui.Text = "▶  Play"
		end
		local shortcut = button(
			transport,
			"Hotkey",
			"Hotkey",
			UDim2.new(0.28, 208, 0, 5),
			UDim2.fromOffset(67, 24),
			function()
				showMenu(controls.Hotkey.Gui, function(menu)
					local function choose(key)
						if key and bindings[key] and bindings[key] ~= active then
							setNotice(key .. " is assigned to " .. bindings[key].Name .. ".")
							return
						end
						active.Hotkey = key
						updateBindings()
						setNotice(nil)
						persist()
						repaint()
					end
					menu:Add({
						Text = "No Hotkey",
						OnClick = function()
							choose(nil)
						end,
					})
					for _, key in ipairs(hotkeys) do
						menu:Add({
							Text = key,
							OnClick = function()
								choose(key)
							end,
						})
					end
				end)
			end,
			"quiet"
		)
		shortcut.Gui.TextXAlignment = Enum.TextXAlignment.Left
		ui:Node("UIPadding", { Parent = shortcut.Gui, PaddingLeft = UDim.new(0, 7) })
		ui:Icon(shortcut.Gui, "Chevron", "chevron-down", UDim2.fromOffset(48, 7), 10)
		ui:Tip(shortcut.Gui, "Assign a playback hotkey")
		local speed = ui:Field(transport, "Speed", "1×", UDim2.fromOffset(149, 5), UDim2.new(0.15, 0, 0, 24))
		ui:Round(speed, 3)
		speed:FindFirstChildOfClass("UIPadding").PaddingRight = UDim.new(0, 19)
		local speedButton
		speedButton = button(
			transport,
			"SpeedOptions",
			"",
			UDim2.new(0.15, 129, 0, 6),
			UDim2.fromOffset(17, 22),
			function()
				showMenu(speedButton.Gui, function(menu)
					for _, value in ipairs({ 0.25, 0.5, 1, 1.5, 2, 3, 4 }) do
						menu:Add({
							Text = ("%g×"):format(value),
							OnClick = function()
								active.Speed = value
								setNotice(nil)
								persist()
								repaint()
							end,
						})
					end
				end)
			end,
			"quiet"
		)
		ui:Icon(speedButton.Gui, "Chevron", "chevron-down", UDim2.fromOffset(3, 6), 10)
		ui:Tip(speed, "Playback speed (0.25×–4×)")
		local speedDivider = rule(transport, UDim2.fromOffset(231, 7), UDim2.fromOffset(1, 20))
		local loopDivider = rule(transport, UDim2.fromOffset(324, 7), UDim2.fromOffset(1, 20))
		local loop = button(transport, "Loop", "", UDim2.fromOffset(245, 5), UDim2.fromOffset(30, 24), function()
			active.Loop = not active.Loop
			persist()
			repaint()
		end, "quiet")
		local track = ui:Node("Frame", {
			Parent = loop.Gui,
			Name = "Track",
			Position = UDim2.fromOffset(1, 5),
			Size = UDim2.fromOffset(28, 14),
			BorderSizePixel = 0,
		})
		ui:Round(track, 7)
		local trackOutline = ui:Outline(track)
		local thumb = ui:Node("Frame", {
			Parent = track,
			Name = "Thumb",
			Size = UDim2.fromOffset(10, 10),
			BorderSizePixel = 0,
		})
		ui:Round(thumb, 5)
		function loop:Paint()
			self.Gui.BackgroundTransparency = 1
			local engaged = self.Enabled and (self.Hovered or self.Pressed)
			track.BackgroundColor3 = if self.On then selectionColor elseif engaged then hoverColor else bodyColor
			trackOutline.Color = if self.On
				then theme.Focus
				elseif engaged then theme.PlaceholderText
				else ui.Palette.Border
			thumb.BackgroundColor3 = if dark then Color3.fromRGB(211, 213, 218) else theme.PlaceholderText
			thumb.Position = UDim2.fromOffset(self.On and 16 or 2, 2)
			track.BackgroundTransparency = if self.Enabled then 0 else 0.45
			trackOutline.Transparency = if self.Enabled then 0 else 0.45
			thumb.BackgroundTransparency = if self.Enabled then 0 else 0.45
		end
		function loop:SetOn(enabled)
			self.On = enabled == true
			self:Paint()
		end
		loop:SetOn(false)
		local loopCaption =
			ui:Text(transport, "LoopCaption", "Loop", UDim2.fromOffset(274, 5), UDim2.fromOffset(23, 24), false, 11)

		ui:Tip(loop.Gui, "Loop playback")

		local header = ui:Node("Frame", {
			Parent = pane,
			Name = "EventHeader",
			Position = UDim2.fromOffset(0, 71),
			Size = UDim2.new(1, -12, 0, 25),
			BackgroundColor3 = tableHeaderColor,
			BorderSizePixel = 0,
		})
		local function columns(parent, height, labels)
			local captions = if labels then { "Time (s)", "Input", "Action" } else { "", "", "" }
			local result = {}
			for index, caption in ipairs(captions) do
				local column = ui:Text(
					parent,
					({ "Time", "Input", "Action" })[index],
					caption,
					UDim2.fromOffset(0, 0),
					UDim2.fromOffset(0, height),
					false,
					13
				)
				if labels then
					column.Font = Enum.Font.BuilderSansMedium
				end
				result[index] = column
			end
			return result[1], result[2], result[3]
		end
		local headerTime, headerInput, headerAction = columns(header, 25, true)
		local timeDivider = rule(header, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0))
		local inputDivider = rule(header, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0))
		rule(header, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1))
		rule(header, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1))
		local scrollTrack = ui:Node("Frame", {
			Parent = pane,
			Name = "ScrollTrack",
			BackgroundColor3 = dark and Color3.fromRGB(39, 40, 46) or theme.Main2,
			BorderSizePixel = 0,
		})
		ui:Round(scrollTrack, 4)
		local list = ui:Node("ScrollingFrame", {
			Parent = pane,
			Name = "Events",
			Position = UDim2.fromOffset(0, 96),
			Size = UDim2.new(1, 0, 1, -138),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = dark and Color3.fromRGB(85, 88, 95) or theme.PlaceholderText,
			ClipsDescendants = true,
		})
		local emptyLabel = ui:Text(list, "Empty", "", UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 24), true)
		local edit = ui:Node("Frame", {
			Parent = pane,
			Name = "EditBar",
			Position = UDim2.new(0, 0, 1, -42),
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = toolbarColor,
			BorderSizePixel = 0,
		})
		ui:Node("Frame", {
			Parent = edit,
			Name = "Divider",
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = dividerColor,
			BorderSizePixel = 0,
		})
		local delayCaption =
			ui:Text(edit, "DelayCaption", "Delay (s)", UDim2.fromOffset(11, 8), UDim2.fromOffset(55, 26))
		local delay = ui:Field(edit, "Delay", "0.000", UDim2.fromOffset(67, 10), UDim2.fromOffset(73, 22))
		ui:Round(delay, 3)
		local remove = button(
			edit,
			"DeleteEvent",
			"Delete",
			UDim2.new(1, -59, 0, 8),
			UDim2.fromOffset(54, 26),
			function()
				table.remove(active.Events, selectedEvent)
				selectedEvent = math.min(selectedEvent, #active.Events)
				if selectedEvent == 0 then
					selectedEvent = nil
				end
				persist()
				repaint()
			end,
			"quiet"
		)
		local trim = button(edit, "Trim", "Trim", UDim2.new(1, -126, 0, 8), UDim2.fromOffset(57, 26), function()
			showMenu(controls.Trim.Gui, function(menu)
				menu:Add({
					Text = "Trim Before Selection",
					OnClick = function()
						local events = active.Events
						local offset = events[selectedEvent].Time
						local trimmed = table.create(#events - selectedEvent + 1)
						for index = selectedEvent, #events do
							local event = events[index]
							event.Time -= offset
							trimmed[#trimmed + 1] = event
						end
						active.Events = trimmed
						selectedEvent = 1
						list.CanvasPosition = Vector2.zero
						persist()
						repaint()
					end,
				})
				menu:Add({
					Text = "Trim After Selection",
					OnClick = function()
						for index = #active.Events, selectedEvent + 1, -1 do
							active.Events[index] = nil
						end
						persist()
						repaint()
					end,
				})
			end)
		end, "quiet")
		trim.Gui.TextXAlignment = Enum.TextXAlignment.Left
		ui:Node("UIPadding", { Parent = trim.Gui, PaddingLeft = UDim.new(0, 8) })
		ui:Icon(trim.Gui, "Chevron", "chevron-down", UDim2.fromOffset(38, 8), 10)
		local editDivider = rule(edit, UDim2.new(1, -62, 0, 9), UDim2.fromOffset(1, 24))
		local status = ui:Text(pane, "Status", "", UDim2.new(0, 8, 1, -66), UDim2.new(1, -16, 0, 24), true)
		status.BackgroundColor3 = toolbarColor
		status.BackgroundTransparency = 0
		status.ZIndex = list.ZIndex + 1
		controls = { List = list, Actions = menuButton, Hotkey = shortcut, Trim = trim }
		local tableWidth, timeWidth, inputWidth = 0, 0, 0
		local tableTop, footerHeight = 96, 42
		local function applyColumns(time, inputLabel, action)
			time.Position = UDim2.fromOffset(11, 0)
			time.Size = UDim2.new(0, timeWidth - 18, 1, 0)
			inputLabel.Position = UDim2.fromOffset(timeWidth + 8, 0)
			inputLabel.Size = UDim2.new(0, inputWidth - 15, 1, 0)
			action.Position = UDim2.fromOffset(timeWidth + inputWidth + 8, 0)
			action.Size = UDim2.new(0, math.max(0, tableWidth - timeWidth - inputWidth - 15), 1, 0)
		end

		local function sizeTimeline()
			local statusHeight = if status.Visible then 24 else 0
			local bottom = tableTop + footerHeight + statusHeight
			list.Position = UDim2.fromOffset(0, tableTop)
			list.Size = UDim2.new(1, -2, 1, -bottom)
			scrollTrack.Position = UDim2.new(1, -10, 0, tableTop + 2)
			scrollTrack.Size = UDim2.new(0, 8, 1, -bottom - 4)
			status.Position = UDim2.new(0, 8, 1, -footerHeight - 24)
		end

		local layoutWidth
		local function fitLayout()
			local width = content.AbsoluteSize.X
			if width == layoutWidth then
				return
			end
			layoutWidth = width
			local libraryWidth = math.clamp(math.round(width * 0.245), 82, 151)
			local paneWidth = math.max(0, width - libraryWidth - 1)
			sidebar.Size = UDim2.new(0, libraryWidth, 1, 0)
			paneDivider.Position = UDim2.fromOffset(libraryWidth, 0)
			pane.Position = UDim2.fromOffset(libraryWidth + 1, 0)
			pane.Size = UDim2.new(1, -libraryWidth - 1, 1, 0)

			local smallLibrary = libraryWidth < 116
			local libraryButtonSize = if smallLibrary then 18 else 24
			local libraryButtonY = math.floor((36 - libraryButtonSize) / 2)
			add.Gui.Position = UDim2.new(1, -libraryButtonSize - 4, 0, libraryButtonY)
			menuButton.Gui.Position = UDim2.new(1, -libraryButtonSize * 2 - 7, 0, libraryButtonY)
			add.Gui.Size = UDim2.fromOffset(libraryButtonSize, libraryButtonSize)
			menuButton.Gui.Size = add.Gui.Size
			libraryTitle.Position = UDim2.fromOffset(if smallLibrary then 7 else 11, 0)
			libraryTitle.Size = UDim2.new(1, -libraryButtonSize * 2 - 21, 0, 36)
			libraryTitle.TextSize = if smallLibrary then 11 else 13
			if addIcon then
				addIcon.Position = UDim2.fromOffset((libraryButtonSize - 14) / 2, (libraryButtonSize - 14) / 2)
			end
			if moreIcon then
				moreIcon.Position = UDim2.fromOffset((libraryButtonSize - 14) / 2, (libraryButtonSize - 14) / 2)
			end

			local countWidth = if paneWidth < 300 then 66 else 82
			name.Size =
				UDim2.fromOffset(math.max(0, math.min(math.floor(paneWidth * 0.615), paneWidth - countWidth - 24)), 23)
			count.Position = UDim2.new(1, -countWidth - 8, 0, 0)
			count.Size = UDim2.fromOffset(countWidth, 36)

			local stacked = paneWidth < 342
			local transportHeight = if stacked then 62 else 35
			transport.Size = UDim2.new(1, 0, 0, transportHeight)
			local spacing = math.clamp((paneWidth - 342) / 128, 0, 1)
			local speedX = 146 + math.round(3 * spacing)
			local speedWidth = if stacked
				then math.clamp(paneWidth - speedX - 7, 53, 70)
				else 54 + math.round(16 * spacing)
			local loopX = if stacked then 9 else 211 + math.round(34 * spacing)
			local hotkeyX = if stacked then 83 else 266 + math.round(72 * spacing)
			local secondY = if stacked then 32 else 5
			speed.Position = UDim2.fromOffset(speedX, 5)
			speed.Size = UDim2.fromOffset(speedWidth, 24)
			speedButton.Gui.Position = UDim2.fromOffset(speedX + speedWidth - 18, 6)
			loop.Gui.Position = UDim2.fromOffset(loopX, secondY)
			loopCaption.Position = UDim2.fromOffset(loopX + 35, secondY)
			shortcut.Gui.Position = UDim2.fromOffset(hotkeyX, secondY)
			recordDivider.Visible = not stacked
			speedDivider.Visible = not stacked
			speedDivider.Position = UDim2.fromOffset(loopX - 7, 7)
			loopDivider.Visible = not stacked
			loopDivider.Position = UDim2.fromOffset(hotkeyX - 8, 7)

			local headerY = 36 + transportHeight
			tableTop = headerY + 25
			header.Position = UDim2.fromOffset(0, headerY)
			tableWidth = math.max(0, paneWidth - 12)
			timeWidth = math.clamp(math.round(tableWidth * 0.21), 60, 98)
			inputWidth = math.clamp(math.round(tableWidth * 0.39), 68, 181)
			local overflow = math.max(0, timeWidth + inputWidth + 80 - tableWidth)
			inputWidth = math.max(42, inputWidth - overflow)
			timeDivider.Position = UDim2.fromOffset(timeWidth, 0)
			inputDivider.Position = UDim2.fromOffset(timeWidth + inputWidth, 0)
			applyColumns(headerTime, headerInput, headerAction)

			local splitFooter = paneWidth < 236
			footerHeight = if splitFooter then 65 else 42
			edit.Position = UDim2.new(0, 0, 1, -footerHeight)
			edit.Size = UDim2.new(1, 0, 0, footerHeight)
			local delayWidth = if splitFooter then 73 else math.clamp(paneWidth - 195, 40, 73)
			delay.Size = UDim2.fromOffset(delayWidth, 22)
			delayCaption.Position = UDim2.fromOffset(11, if splitFooter then 4 else 8)
			delay.Position = UDim2.fromOffset(67, if splitFooter then 6 else 10)
			local editY = if splitFooter then 34 else 8
			trim.Gui.Position = UDim2.new(1, -126, 0, editY)
			remove.Gui.Position = UDim2.new(1, -59, 0, editY)
			editDivider.Position = UDim2.new(1, -62, 0, editY + 1)

			sizeTimeline()
		end

		local macroRows = {}
		local function paintMacros(idle)
			macroList.CanvasSize = UDim2.fromOffset(0, #macros * libraryRowHeight)
			for index, macro in ipairs(macros) do
				local row = macroRows[index]
				if not row then
					row = button(
						macroList,
						"Macro",
						"",
						UDim2.fromOffset(0, (index - 1) * libraryRowHeight),
						UDim2.new(1, -4, 0, libraryRowHeight),
						function()
							activate(macros[index])
						end,
						"quiet"
					)
					ui:Round(row.Gui, 0)
					local paint = row.Paint
					function row:Paint()
						paint(self)
						if self.Kind == "primary" and self.Enabled then
							self.Gui.BackgroundColor3 = selectionColor
						end
					end
					row.Gui.TextXAlignment = Enum.TextXAlignment.Left
					row.Gui.TextTruncate = Enum.TextTruncate.AtEnd
					ui:Node(
						"UIPadding",
						{ Parent = row.Gui, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 4) }
					)
					macroRows[index] = row
				end
				row.Gui.Visible = true
				row.Gui.Text = macro.Name
				row:SetEnabled(idle)
				row:SetKind(if macro == active then "primary" else "quiet")
			end
			for index = #macros + 1, #macroRows do
				macroRows[index].Gui.Visible = false
				macroRows[index]:SetEnabled(false)
			end
		end
		local rows = {}
		local repaintQueued = false
		local function paintRows()
			local events = active and active.Events or empty
			local maxFirst = math.max(1, #events - math.floor(list.AbsoluteSize.Y / rowHeight) + 1)
			local first = math.clamp(math.floor(list.CanvasPosition.Y / rowHeight) + 1, 1, maxFirst)
			local visible = math.min(#events, math.ceil(list.AbsoluteSize.Y / rowHeight) + 1)
			for slot = 1, visible do
				local row = rows[slot]
				if not row then
					local gui = ui:Node("TextButton", {
						Parent = list,
						Name = "Event",
						Text = "",
						AutoButtonColor = false,
						BorderSizePixel = 0,
						Size = UDim2.new(1, -10, 0, rowHeight),
					})
					local time, inputLabel, action = columns(gui, rowHeight, false)
					row = { Gui = gui, Time = time, Input = inputLabel, Action = action }
					rule(gui, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1))
					local function style(hover)
						local selected = selectedEvent == row.Index
						gui.BackgroundColor3 = if selected then selectionColor else hoverColor
						gui.BackgroundTransparency = if selected or hover then 0 else 1
					end
					row.Paint = style
					gui.MouseEnter:Connect(function()
						style(true)
					end)
					gui.MouseLeave:Connect(function()
						style(false)
					end)
					gui.Activated:Connect(function()
						if row.Index and engine.State == "Idle" then
							if delay:IsFocused() then
								delay:ReleaseFocus()
							end
							selectedEvent = row.Index
							setNotice(nil)
						end
					end)
					rows[slot] = row
				end
				local index = first + slot - 1
				local event = events[index]
				row.Index = if event then index else nil
				row.Gui.Visible = event ~= nil
				if event then
					if row.TableWidth ~= tableWidth then
						row.TableWidth = tableWidth
						applyColumns(row.Time, row.Input, row.Action)
					end
					row.Gui.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
					row.Time.Text = ("%.3f"):format(event.Time)
					row.Input.Text, row.Action.Text = eventText(event)
					row.Paint(false)
				end
			end
			for slot, row in pairs(rows) do
				if slot > visible then
					row.Gui.Visible = false
					row.Index = nil
				end
			end
		end
		local function queuePaintRows()
			if repaintQueued then
				return
			end
			repaintQueued = true
			task.defer(function()
				repaintQueued = false
				if Main.Alive ~= false then
					paintRows()
				end
			end)
		end

		local function saveName()
			if not active or engine.State ~= "Idle" then
				return
			end
			local value = name.Text:match("^%s*(.-)%s*$") or ""
			if value == "" then
				name.Text = active.Name
			elseif #value > 96 or not utf8.len(value) then
				name.Text = active.Name
				setNotice("Use a shorter macro name.")
			elseif value ~= active.Name then
				active.Name = value
				notice = nil
				persist()
				repaint()
			end
		end
		name.FocusLost:Connect(saveName)
		speed.FocusLost:Connect(function()
			if active and engine.State == "Idle" then
				local value = tonumber((speed.Text:gsub("×", ""):gsub("[xX]", "")))
				if not value or value ~= value or value < 0.25 or value > 4 then
					setNotice("Speed must be between 0.25× and 4×.")
					return
				end
				notice = nil
				if active.Speed ~= value then
					active.Speed = value
					persist()
				end
				repaint()
			end
		end)
		delay.FocusLost:Connect(function()
			local events = active and active.Events
			if not events or not selectedEvent or not events[selectedEvent] or engine.State ~= "Idle" then
				return
			end
			local value = tonumber(delay.Text)
			local before = events[selectedEvent - 1] and events[selectedEvent - 1].Time or 0
			local offset = value and before + value - events[selectedEvent].Time
			local limit = Apps.MacroEngine.MaxDuration or 600
			if not value or value ~= value or value < 0 or events[#events].Time + offset > limit then
				setNotice("Enter a delay within the recording limit.")
				return
			end
			for index = selectedEvent, #events do
				events[index].Time = math.max(before, events[index].Time + offset)
			end
			notice = nil
			persist()
			repaint()
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(queuePaintRows)
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(queuePaintRows)
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitLayout()
			queuePaintRows()
		end)
		fitLayout()
		window.OnDeactivate:Connect(function()
			if picker then
				picker:Hide()
			end
		end)

		repaint = function()
			local events = active and active.Events or empty
			local entry = events[selectedEvent]
			local idle = engine.State == "Idle"
			local enabled = idle and active ~= nil
			local editable = enabled and entry ~= nil
			name.TextEditable = enabled
			speed.TextEditable = enabled
			speedButton:SetEnabled(enabled)
			delay.TextEditable = editable
			if not name:IsFocused() then
				name.Text = active and active.Name or ""
			end
			if not speed:IsFocused() then
				speed.Text = active and ("%g×"):format(active.Speed) or ""
			end
			if not delay:IsFocused() then
				local previous = selectedEvent and events[selectedEvent - 1]
				delay.Text = entry and ("%.3f"):format(entry.Time - (previous and previous.Time or 0)) or ""
			end
			paintMacros(idle)
			add:SetEnabled(idle and #macros < (Apps.MacroStore.MaxMacros or 32))
			menuButton:SetEnabled(enabled)
			record:SetEnabled(enabled)
			if enabled and #events > 0 and playbackCheckMacro ~= active then
				playbackCheckMacro = active
				canPlay, playbackIssue = engine:CanPlay(events)
			end
			play:SetEnabled(enabled and #events > 0 and canPlay == true)
			shortcut:SetEnabled(enabled)
			shortcut.Gui.Text = active and active.Hotkey or "Hotkey"
			loop:SetEnabled(enabled)
			loop:SetOn(active and active.Loop == true)
			remove:SetEnabled(editable)
			trim:SetEnabled(editable and #events > 1)
			emptyLabel.Text = if active then "No recorded input" else "Select New to create a macro."
			emptyLabel.Visible = #events == 0
			list.CanvasSize = UDim2.fromOffset(0, #events * rowHeight)
			status.Text = if not idle
				then engine.State .. (playbackProgress and "  " .. playbackProgress or "  ·  F8 to stop")
				else storageError
					or notice
					or (enabled and #events > 0 and playbackIssue or nil)
					or (not Apps.MacroStore.Available() and "Macros are kept for this session.")
					or ""
			status.Visible = status.Text ~= ""
			sizeTimeline()
			count.Text = ("%d %s"):format(#events, if #events == 1 then "event" else "events")
			paintRows()
		end
	end

	function app.Open()
		app.Init()
		if not window then
			buildWindow()
		end
		window:Show()
		window:Focus()
		repaint()
	end

	function app.Hide()
		if window then
			window:Hide()
		end
	end

	return app
end

return { InitDeps = InitDeps, Main = CreateModule }
