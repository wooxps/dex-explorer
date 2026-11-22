--!strict

local usedWindow, popup, callback, engine
local saves, plays = 0, 0
local failSave
local chosen
local focusLock
local cleanup
local store = {
	MaxMacros = 32,
	Available = function()
		return true
	end,
	Load = function()
		return {}
	end,
	Save = function(macros)
		saves += 1
		chosen = macros
		if failSave then
			return false, "Could not save macros"
		end
		return true
	end,
}

for n = 1, 12 do
	local name = "F" .. n
	Enum.KeyCode[name] = { Name = name }
end
Vector2.zero = Vector2.new(0, 0)
function methods:IsFocused()
	return service.UserInputService.Focus == self
end
function Lib.StudioText() end
function Lib.StudioTooltip() end
Main.Alive = true
local heartbeat = signal()
service.RunService = { Heartbeat = heartbeat }
Main.DisplayOrders = { Core = 10 }
Main.GetStudioAsset = function()
	return nil
end
Main.SetGameInputLocked = function(locked)
	focusLock = locked
end
Main.AddCleanup = function(fn)
	cleanup = fn
end
Main.IsPointInDexUI = function(x)
	return x == 1
end
local defaultWindow = Lib.Window.new
Lib.Window.new = function()
	local window = defaultWindow()
	window.Hidden = true
	function window:Show()
		self.Hidden = false
		self.OnActivate:Fire()
	end
	function window:Hide(instant)
		assert(instant == true and focusLock == false, "macro capture and playback remove the window and input lock immediately")
		self.Hidden = true
		self.OnDeactivate:Fire()
	end
	function window:IsVisible()
		return not self.Hidden
	end
	window.IsContentVisible = window.IsVisible
	function window:Focus() end
	function window:SetTitle(title)
		self.Title = title
	end
	function window:SetResizeHandleStyle(style)
		self.ResizeHandleStyle = style
	end
	function window:Resize(x, y)
		window.GuiElems.Main.Size = UDim2.fromOffset(x, y)
	end
	function window:Destroy()
		self.Destroyed = true
	end
	usedWindow = window
	return window
end
Apps.ContextMenu = {
	new = function()
		popup = Lib.ContextMenu.new()
		function popup:Destroy()
			self.Destroyed = true
		end
		return popup
	end,
}
Apps.MacroStore = store
Apps.MacroEngine = {
	MaxDuration = 600,
	Create = function(config)
		callback = config
		engine = { State = "Idle" }
		function engine:CanPlay(events)
			return #events > 0
		end
		function engine:StartRecording()
			self.State = "Recording"
			callback.OnState(self.State)
			return true
		end
		function engine:Play(events, options)
			plays += 1
			self.State = "Playing"
			self.Options = options
			callback.OnState(self.State)
			return true
		end
		function engine:Stop(events)
			self.State = "Idle"
			callback.OnState("Idle", "Stopped", events)
		end
		function engine:Destroy()
			self.Destroyed = true
		end
		return engine
	end,
}
local function createSimple(class, props)
	local object = Instance.new(class)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Visible = props.Visible ~= false
	object.ZIndex = props.ZIndex or 1
	if class == "ScrollingFrame" then
		object.CanvasPosition = Vector2.zero
	end
	return object
end
local deps =
	{ Main = Main, Apps = Apps, Settings = Settings, Lib = Lib, service = service, createSimple = createSimple }
local BridgeUI = (function()
	-- BRIDGE_UI
end)()
BridgeUI.InitDeps(deps)
Apps.BridgeUI = BridgeUI.Main()
local InputMacros = (function()
	-- INPUT_MACROS
end)()
InputMacros.InitDeps(deps)
local app = InputMacros.Main()
app.Init()
assert(
	usedWindow == nil and #service.UserInputService.InputBegan.handlers == 0,
	"empty startup remains idle with no window or key listener"
)
app.Open()
local body = usedWindow.GuiElems.Content
local pane = body.Sequence
local transport = pane.Transport
local sidebar, toolbar, header, events, edit =
	body.MacroLibrary, pane.Toolbar, pane.EventHeader, pane.Events, pane.EditBar
local function bounds(node)
	local position, size = node.AbsolutePosition, node.AbsoluteSize
	return { Left = position.X, Top = position.Y, Right = position.X + size.X, Bottom = position.Y + size.Y }
end
local function within(container, nodes, width)
	local outer = bounds(container)
	for _, node in ipairs(nodes) do
		local inner = bounds(node)
		assert(
			inner.Left >= outer.Left
				and inner.Right <= outer.Right + 0.01
				and inner.Top >= outer.Top
				and inner.Bottom <= outer.Bottom + 0.01,
			("%s spills outside %s at width %d"):format(node.Name, container.Name, width)
		)
	end
end
local function noOverlap(nodes, width)
	for index, node in ipairs(nodes) do
		local a = bounds(node)
		for otherIndex = index + 1, #nodes do
			local other = nodes[otherIndex]
			local b = bounds(other)
			assert(
				a.Right <= b.Left + 0.01
					or b.Right <= a.Left + 0.01
					or a.Bottom <= b.Top + 0.01
					or b.Bottom <= a.Top + 0.01,
				("%s overlaps %s at width %d"):format(node.Name, other.Name, width)
			)
		end
	end
end
local nativeTitle, nativeResizeStyle = usedWindow.Title, usedWindow.ResizeHandleStyle
assert(nativeTitle == "Input Macros" and nativeResizeStyle == "Dock", "uses native title and resize handles")
assert(app.Window == usedWindow and body.Parent == usedWindow.GuiElems.Main, "reuses native content container")
assert(sidebar.MacroActions.Parent == sidebar, "library actions stay beside the New button")
assert(toolbar.EventCount.Parent == toolbar and not pane.Status.Visible, "empty status stays hidden")
local function verifyLayout(width, height)
	usedWindow:Resize(width, height + 28)
	body:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	flushTasks()

	within(body, { sidebar, pane }, width)
	noOverlap({ sidebar, pane }, width)
	within(sidebar, { sidebar.LibraryTitle, sidebar.New, sidebar.MacroActions, sidebar.Macros }, width)
	noOverlap({ sidebar.LibraryTitle, sidebar.New, sidebar.MacroActions, sidebar.Macros }, width)
	within(toolbar, { toolbar:FindFirstChild("Name"), toolbar.EventCount }, width)
	noOverlap({ toolbar:FindFirstChild("Name"), toolbar.EventCount }, width)

	local transportControls =
		{ transport.Record, transport.Play, transport.Speed, transport.Loop, transport.LoopCaption, transport.Hotkey }
	within(transport, transportControls, width)
	noOverlap(transportControls, width)
	within(transport.Speed, { transport.SpeedOptions }, width)
	local editControls = { edit.DelayCaption, edit.Delay, edit.Trim, edit.DeleteEvent }
	within(edit, editControls, width)
	noOverlap(editControls, width)

	local headings = { header.Time, header.Input, header.Action }
	within(header, headings, width)
	noOverlap(headings, width)
	assert(header.Time.AbsoluteSize.X >= 40, "time column fits timestamps")
	assert(
		header.Input.AbsoluteSize.X >= (if width < 365 then 42 else 45),
		"input column stays readable at width " .. width
	)
	assert(
		header.Action.AbsoluteSize.X >= (if width < 365 then 62 else 65),
		"action column stays readable at width " .. width
	)

	within(pane, { toolbar, transport, header, events, edit }, width)
	noOverlap({ toolbar, transport, header, events, edit }, width)
	assert(bounds(header).Top >= bounds(transport).Bottom - 0.01, "event header starts below the transport")
	assert(bounds(events).Top >= bounds(header).Bottom - 0.01, "list starts below the header")
	assert(bounds(events).Bottom <= bounds(edit).Top + 0.01, "list stops above the inspector")
	assert(events.AbsoluteSize.Y >= 48, "even a short window keeps at least two event rows visible")
end
verifyLayout(624, 390)
local wideSidebar = sidebar.AbsoluteSize.X
local wideTransport = transport.AbsoluteSize.Y
verifyLayout(420, 260)
verifyLayout(365, 260)
assert(sidebar.AbsoluteSize.X < wideSidebar, "sidebar contracts with the window")
assert(transport.AbsoluteSize.Y > wideTransport, "narrow transport reflows to two rows")
verifyLayout(302, 260)
assert(edit.Trim.AbsolutePosition.Y > edit.Delay.AbsolutePosition.Y, "footer also reflows at the minimum width")
verifyLayout(624, 390)
assert(
	sidebar.AbsoluteSize.X == wideSidebar and transport.AbsoluteSize.Y == wideTransport,
	"controls reflow back to reference size"
)

body.MacroLibrary.New.Activated:Fire()
assert(#chosen == 1 and chosen[1].Name == "Macro 1")
transport.Record.Activated:Fire()
assert(engine.State == "Recording" and usedWindow.Hidden and focusLock == false)
local hud = game:FindFirstChild("InputMacroStatus")
local statusStrip = hud.Status
assert(hud.Enabled and not Main.FocusIgnoredGuis[hud] and statusStrip.Stop.Visible)
assert(
	statusStrip.Mode.Text == "Recording" and statusStrip.Stop.Keycap.Text == "F8" and not statusStrip.Progress.Visible
)
assert(statusStrip.Metric.Text == "00:00")
assert(statusStrip.Stop.BackgroundTransparency == 1)
statusStrip.Stop.MouseEnter:Fire()
assert(statusStrip.Stop.BackgroundTransparency == 0)
statusStrip.Stop.MouseLeave:Fire()
assert(statusStrip.Stop.BackgroundTransparency == 1)
heartbeat:Fire(12.2)
assert(statusStrip.Metric.Text == "00:12")
local stopInput = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F8 }
assert(callback.IsStopInput(stopInput), "F8 is reserved for stopping")
local mousePosition = Vector2.new(1, 0)
service.UserInputService.GetMouseLocation = function()
	return mousePosition
end
local staleClick = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(2, 0) }
assert(callback.ShouldRecord(staleClick), "an actual press outside Dex stays accepted after the pointer moves over Dex")
assert(not callback.ShouldRecord(staleClick, false, mousePosition), "held-button sampling explicitly uses the current pointer")
mousePosition = Vector2.new(2, 0)
assert(not callback.ShouldRecord({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(1, 0) }, true),
	"a press inside Dex stays excluded after the pointer moves outside")
assert(callback.ShouldRecord(staleClick, true), "game-processed clicks outside Dex remain recordable")
engine:Stop({
	{ Kind = "KeyDown", Time = 0, Key = "W" },
	{ Kind = "RelativeMove", Time = 0.25, DeltaX = 3, DeltaY = -4 },
	{ Kind = "KeyUp", Time = 1, Key = "W" },
})
assert(#chosen[1].Events == 3 and not usedWindow.Hidden, "stopping saves and restores the tool")
heartbeat:Fire(3)
assert(not hud.Enabled and statusStrip.Metric.Text == "00:12", "the recording timer disconnects on stop")
pane.Events:GetPropertyChangedSignal("CanvasPosition"):Fire()
pane.Events:GetPropertyChangedSignal("AbsoluteSize"):Fire()
flushTasks()
local rows = {}
for _, child in ipairs(pane.Events:GetChildren()) do
	if child.Name == "Event" then
		table.insert(rows, child)
	end
end
assert(#rows == 3 and rows[2].Action.Text == "+3, -4 px")
for _, width in ipairs({ 365, 624 }) do
	verifyLayout(width, 260)
	for _, column in ipairs({ "Time", "Input", "Action" }) do
		assert(
			rows[2][column].AbsolutePosition.X == header[column].AbsolutePosition.X,
			column .. " aligns with its heading after resizing"
		)
		assert(
			rows[2][column].AbsoluteSize.X == header[column].AbsoluteSize.X,
			column .. " width matches its heading after resizing"
		)
	end
end
rows[2].Activated:Fire()
pane.EditBar.Delay.Text = "0.5"
pane.EditBar.Delay.FocusLost:Fire()
assert(chosen[1].Events[2].Time == 0.5 and chosen[1].Events[3].Time == 1.25, "editing a delay shifts later timestamps")
pane.EditBar.Trim.Activated:Fire()
popup.Items[1].OnClick()
assert(#chosen[1].Events == 2 and chosen[1].Events[1].Time == 0, "trimming before selection rebases timestamps")
popup:Hide()
local loopTrack = transport.Loop.Track
assert(loopTrack.Size.X.Offset == 28 and loopTrack.Size.Y.Offset == 14)
assert(loopTrack.Thumb.Position.X.Offset == 2 and loopTrack.Thumb.Size.X.Offset == 10)
transport.Record.MouseEnter:Fire()
assert(transport.Record.BackgroundTransparency == 0 and transport.Record.BackgroundColor3 ~= Settings.Theme.ButtonHover)
transport.Record.MouseLeave:Fire()
assert(transport.Record.BackgroundTransparency == 1)
transport.Loop.Activated:Fire()
assert(loopTrack.Thumb.Position.X.Offset == 16 and transport.Loop.BackgroundTransparency == 1)
transport.Speed.Text = "2x"
transport.Speed.FocusLost:Fire()
assert(chosen[1].Loop and chosen[1].Speed == 2)
transport.SpeedOptions.Activated:Fire()
popup.Items[3].OnClick()
assert(chosen[1].Speed == 1, "speed presets update the same value as direct entry")
popup.Items[5].OnClick()
popup:Hide()
transport.Hotkey.Activated:Fire()
popup.Items[2].OnClick()
assert(chosen[1].Hotkey == "F1" and #service.UserInputService.InputBegan.handlers == 1)
popup:Hide()
local pressed = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F1 }
local input = service.UserInputService
input.Focus = toolbar:FindFirstChild("Name")
input.InputBegan:Fire(pressed, false)
input.Focus = nil
input.InputBegan:Fire(pressed, true)
assert(plays == 0, "hotkeys ignore text entry and processed input")
input.InputBegan:Fire(pressed, false)
input.InputBegan:Fire(pressed, false)
assert(plays == 1 and engine.Options.Loop and engine.Options.Speed == 2, "replaying cannot nest through a hotkey")
assert(hud.Enabled and Main.FocusIgnoredGuis[hud], "passive playback indicator never claims game input")
assert(statusStrip.Mode.Text == "Playing" and statusStrip.Keycap.Text == "F8" and not statusStrip.Stop.Visible)
assert(statusStrip.Progress.Visible and statusStrip.Metric.Text == "0 / 2")
callback.OnProgress(1, 2)
assert(statusStrip.Metric.Text == "1 / 2" and statusStrip.Progress.Fill.Size.X.Scale == 0.5)
engine:Stop()
assert(not hud.Enabled and not Main.FocusIgnoredGuis[hud])
failSave = true
transport.Loop.Activated:Fire()
assert(
	not chosen[1].Loop and pane.Status.Text == "Could not save macros",
	"a save failure is visible with edits retained in memory"
)
failSave = false
transport.Loop.Activated:Fire()
assert(chosen[1].Loop and pane.Status.Text ~= "Could not save macros")
local normalHide = usedWindow.Hide
usedWindow.Hide = function(self)
	self.Hidden = true
	engine:Stop()
end
transport.Record.Activated:Fire()
assert(engine.State == "Idle" and not hud.Enabled and not usedWindow.Hidden,
	"stopping during window hiding does not reopen the recording HUD")
usedWindow.Hide = normalHide
do
	local funcs = {}
	local leftSide, rightSide, visibleWindows = { Windows = {} }, { Windows = {} }, {}
	local waits, tweens, layouts, cancelled = 0, 0, 0, 0
	local Lib = {
		FindAndRemove = function(list, item)
			local index = table.find(list, item)
			if index then
				table.remove(list, index)
			end
		end,
		FastWait = function()
			waits += 1
		end,
	}
	local Enum = { EasingStyle = { Quad = "Quad" }, EasingDirection = { Out = "Out" } }
	local TweenInfo = { new = function() return {} end }
	local tick = function() return 1 end
	local updateWindows = function() layouts += 1 end
	local sample = {
		Gui = { Parent = game },
		GuiElems = { Main = {}, Title = {}, Minimize = { ImageLabel = {} }, Close = { ImageLabel = {} }, TopBar = {}, Outlines = {} },
		SizeX = 400,
		SetResizableInternal = function() end,
		MinimizeAnim = { Disable = function() end },
		CloseAnim = { Disable = function() end },
		OnDeactivate = { Fire = function() end },
		StopTweens = function() cancelled += 1 end,
		DoTween = function() tweens += 1 end,
	}
	table.insert(visibleWindows, sample)
	funcs.Close(sample, true)
	assert(sample.Closed and sample.Gui.Parent == nil and #visibleWindows == 0 and layouts == 1)
	assert(waits == 0 and tweens == 0 and cancelled == 1, "instant macro hiding executes the actual close path without a yield")
	funcs.Close(sample)
	assert(waits == 2 and tweens == 6 and cancelled == 2, "normal window closing retains its animation")
end
cleanup()
input.InputBegan:Fire(pressed, false)
assert(plays == 1 and engine.Destroyed and usedWindow.Destroyed, "cleanup removes hotkey and window")
print(
	"PASS: macro UI native chrome, responsive geometry, record/restore, event editing, hotkeys, save failure, cleanup"
)
