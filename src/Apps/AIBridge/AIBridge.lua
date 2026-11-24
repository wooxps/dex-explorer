--!strict

local Apps, Main, Lib, Settings, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Lib, Settings, env = d.Apps, d.Main, d.Lib, d.Settings, d.env or {}
end
------------------------------ Module ------------------------------

local function CreateModule()
	local app = {}
	local window, client, ui, connection, activity, commands
	local pages, tabs = {}, {}
	local tabNames = { "Connection", "Commands", "Activity", "Setup" }
	local sidebarWidth = 138
	local tabHeight, tabTop = 35, 7
	local minimumSidebarWindowWidth = 460
	local requested = { inspect = true, edit = false, execute = false }
	local busy, closed = false, false
	local tab = "Connection"
	local notice, noticeError, noticeVersion = nil, false, 0
	local pairingError
	local render
	local function flash(control, value)
		control.IdleText = control.IdleText or control.Gui.Text
		local previous = control.IdleText
		control.FlashVersion = (control.FlashVersion or 0) + 1
		local version = control.FlashVersion
		control.Gui.Text = value
		task.delay(2, function()
			if not closed and version == control.FlashVersion then
				control.Gui.Text = previous
			end
		end)
	end
	local function feedback(message, failed)
		noticeVersion += 1
		local version = noticeVersion
		notice, noticeError = message, failed == true
		render()
		task.delay(3, function()
			if not closed and version == noticeVersion then
				notice = nil
				render()
			end
		end)
	end
	local function attempt(callback)
		if busy or closed then
			return
		end
		busy = true
		render()
		task.spawn(function()
			local ok, problem = pcall(callback)
			if closed then
				return
			end
			if not ok then
				client.Error = tostring(problem):sub(1, 180)
			end
			busy = false
			render()
		end)
	end
	local function closeMenus()
		if activity then
			activity:CloseMenu()
		end
		if commands then
			commands:CloseMenu()
		end
	end
	local function switch(value)
		closeMenus()
		tab = value
		app.ActiveTab = value
		for name, page in pairs(pages) do
			page.Visible = name == value
		end
		for name, item in pairs(tabs) do
			local selected = name == value
			item:SetKind(selected and "primary" or "quiet")
			if item.PaneIcon then
				item.PaneIcon.ImageColor3 = selected and (Settings.Theme.SelectedText or Settings.Theme.Text)
					or Settings.Theme.Text
			end
		end
		if value == "Activity" and activity and client then
			activity:Update(client.Recent, client.ActivityVersion)
		elseif value == "Commands" and commands and client then
			commands:Update(client.CommandCatalog, client.PolicyPending, client.State, client.ToolControls)
		end
	end
	local function disconnect()
		client.Error = nil
		pairingError = nil
		client:Disconnect()
	end
	local function pause()
		if client and client.State == "Connected" then
			client:SetPaused(not client.Paused)
		end
	end
	local function connect(useClipboard)
		if client.SessionId or client.State == "Connecting" then
			disconnect()
			return
		end
		if busy or not client:Supported() then
			return
		end
		local code = connection.Code.Text
		if useClipboard and code == "" and type(env.getclipboard) == "function" then
			local ok, value = pcall(env.getclipboard)
			if not ok or type(value) ~= "string" or not Apps.BridgeClient.ParseCode(value) then
				pairingError = "No pairing code on the clipboard."
				render()
				return
			end
			code = value:match("^%s*(.-)%s*$")
			connection.Code.Text = code
		end
		if not Apps.BridgeClient.ParseCode(code) then
			pairingError = "Enter the full pairing code."
			render()
			return
		end
		pairingError = nil
		attempt(function()
			client:Connect(code, requested)
		end)
	end
	local function grant(key)
		if busy then
			return
		end
		requested[key] = not requested[key]
		local target = requested[key]
		attempt(function()
			local ok = client:SetGrants(requested)
			requested = table.clone(client.Grants)
			if ok and client.State ~= "Reconnecting" then
				client.Error = nil
			end
			feedback(
				ok
						and (key == "edit" and "Object editing " or "Code and remote calls ") .. (target and "enabled" or "disabled")
					or "Could not update access",
				not ok
			)
		end)
	end
	render = function()
		if closed then
			return
		end
		if not window then
			return
		end
		if client.State == "Connected" and connection.Code.Text ~= "" then
			connection.Code.Text = ""
		end
		connection:Update({
			Client = client,
			Busy = busy,
			Grants = requested,
			Notice = notice,
			NoticeError = noticeError,
			PairingError = pairingError,
			CanPaste = type(env.getclipboard) == "function",
		})
		if tab == "Activity" and window:IsContentVisible() then
			activity:Update(client.Recent, client.ActivityVersion)
		elseif tab == "Commands" and window:IsContentVisible() then
			commands:Update(client.CommandCatalog, client.PolicyPending, client.State, client.ToolControls)
		end
	end
	function app.Open()
		if window then
			render()
			window:Show()
			return
		end
		ui = Apps.BridgeUI.Create(true)
		window = Lib.Window.new()
		window:SetTitle("Dex MCP")
		window.MinX = 440
		window.MinY = 360
		window:Resize(580, 420)
		window:SetResizeHandleStyle("Dock")
		app.Window = window
		local content = window.GuiElems.Content
		content.BackgroundColor3 = ui.Palette.Pane
		local bar = ui:Node("Frame", {
			Name = "Tabs",
			Parent = content,
			Size = UDim2.new(0, sidebarWidth, 1, 0),
			BackgroundColor3 = ui.Palette.Sidebar,
			BorderSizePixel = 0,
		})
		ui:Node("Frame", {
			Name = "Divider",
			Parent = bar,
			Position = UDim2.new(1, -1, 0, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = ui.Palette.Border,
			BorderSizePixel = 0,
		})
		for index, name in ipairs(tabNames) do
			local control = ui:Button(
				bar,
				name,
				name,
				UDim2.fromOffset(1, tabTop + (index - 1) * tabHeight),
				UDim2.new(1, -2, 0, tabHeight),
				function()
					switch(name)
				end,
				"quiet"
			)
			control.Gui.TextSize = 14
			control.Gui.TextTruncate = Enum.TextTruncate.AtEnd
			ui:Round(control.Gui, 0)
			control.Gui.TextXAlignment = Enum.TextXAlignment.Left
			control.PanePadding = ui:Node("UIPadding", { Parent = control.Gui, PaddingLeft = UDim.new(0, 42) })
			control.PaneIcon = ui:Icon(
				control.Gui,
				"Icon",
				name == "Connection" and "connection-v2" or name:lower(),
				UDim2.new(0, -28, 0.5, -9),
				18
			)
			if control.PaneIcon.Image == "" then
				control.PaneIcon:Destroy()
				control.PaneIcon = nil
				control.PanePadding.PaddingLeft = UDim.new(0, 12)
			end
			tabs[name] = control
		end
		for _, name in ipairs(tabNames) do
			local scroll = name == "Connection" or name == "Setup"
			pages[name] = ui:Node(scroll and "ScrollingFrame" or "Frame", {
				Name = name,
				Parent = content,
				Position = UDim2.fromOffset(sidebarWidth, 0),
				Size = UDim2.new(1, -sidebarWidth, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Visible = false,
				ClipsDescendants = true,
				CanvasSize = scroll and UDim2.fromOffset(0, 365) or nil,
				CanvasPosition = scroll and Vector2.new(0, 0) or nil,
				ScrollBarThickness = scroll and 4 or nil,
				ScrollBarImageColor3 = scroll and Settings.Theme.PlaceholderText or nil,
				ScrollingDirection = scroll and Enum.ScrollingDirection.Y or nil,
			})
		end
		local divider = bar:FindFirstChild("Divider")
		local compactNavigation
		local function fitNavigation()
			local compact = content.AbsoluteSize.X < minimumSidebarWindowWidth
			if compactNavigation == compact then
				return
			end
			compactNavigation = compact
			bar.Size = compact and UDim2.new(1, 0, 0, 38) or UDim2.new(0, sidebarWidth, 1, 0)
			divider.Position = compact and UDim2.new(0, 0, 1, -1) or UDim2.new(1, -1, 0, 0)
			divider.Size = compact and UDim2.new(1, 0, 0, 1) or UDim2.new(0, 1, 1, 0)
			for index, name in ipairs(tabNames) do
				local control = tabs[name]
				control.Gui.Position = compact and UDim2.new((index - 1) / #tabNames, 4, 0, 4)
					or UDim2.fromOffset(1, tabTop + (index - 1) * tabHeight)
				control.Gui.Size = compact and UDim2.new(1 / #tabNames, -8, 0, 30) or UDim2.new(1, -2, 0, tabHeight)
				control.Gui.TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
				control.PanePadding.PaddingLeft = UDim.new(0, compact and 0 or control.PaneIcon and 42 or 12)
				if control.PaneIcon then
					control.PaneIcon.Visible = not compact
				end
				pages[name].Position = compact and UDim2.fromOffset(0, 38) or UDim2.fromOffset(sidebarWidth, 0)
				pages[name].Size = compact and UDim2.new(1, 0, 1, -38) or UDim2.new(1, -sidebarWidth, 1, 0)
			end
		end
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitNavigation)
		fitNavigation()
		connection = Apps.BridgeConnectionView.Create(pages.Connection, ui, {
			Connect = function()
				connect(true)
			end,
			Pause = pause,
			Grant = grant,
			Help = function()
				switch("Setup")
			end,
		})
		activity = Apps.BridgeActivityView.Create(pages.Activity, ui, function()
			client:ClearRecent()
		end)
		app.Activity = activity
		if type(Settings.BridgeDisabledCommands) ~= "table" then
			Settings.BridgeDisabledCommands = {}
		end
		local disabled = Settings.BridgeDisabledCommands
		commands = Apps.BridgeCommandsView.Create(pages.Commands, ui, disabled, function()
			client:SyncToolPolicy()
			if Main.SaveSettings then
				Main.SaveSettings()
			end
		end)
		app.Commands = commands
		Apps.BridgeSetupView.Create(pages.Setup, ui, {
			Flash = flash,
			Connect = function()
				switch("Connection")
			end,
		})
		client = Apps.BridgeClient.Create({
			DisabledTools = disabled,
			CommandCatalog = Apps.BridgeCommandCatalog,
			OnChanged = function()
				if not closed and window then
					render()
				end
			end,
		})
		window.OnActivate:Connect(render)
		window.OnRestore:Connect(render)
		window.OnDeactivate:Connect(closeMenus)
		window.OnMinimize:Connect(closeMenus)
		app.Client = client
		app.PairingCode = connection.Code
		app.ConnectControl = connection.Connect
		app.PauseControl = connection.Pause
		app.Pages = pages
		app.StateLabel = connection.State
		connection.Code:GetPropertyChangedSignal("Text"):Connect(function()
			if client.State == "Disconnected" and client:Supported() then
				pairingError, client.Error = nil, nil
			end
			render()
		end)
		connection.Code.FocusLost:Connect(function(enter)
			if enter and not busy and client.State == "Disconnected" then
				connect(false)
			end
		end)
		if not client:Supported() then
			client.Error = "Executor lacks HTTP or WebSocket support."
		end
		switch(tab)
		render()
		window:Show()
	end
	function app.Hide()
		if window then
			closeMenus()
			window:Hide()
		end
	end
	function app.ConnectWithCode(code, grants)
		assert(type(code) == "string", "A pairing code is required")
		grants = grants or {}
		assert(type(grants) == "table", "Access grants must be a table")
		app.Open()
		assert(not client.SessionId and not busy, "Dex MCP is already connected or connecting")
		requested = { inspect = true, edit = grants.edit == true, execute = grants.execute == true }
		connection.Code.Text = code
		connect()
	end
	function app.SetTab(value)
		if pages[value] then
			switch(value)
		end
	end
	Main.AddCleanup(function()
		closed = true
		if client then
			client:Destroy()
		end
		if activity then
			activity:Destroy()
		end
		if commands then
			commands:Destroy()
		end
		if ui then
			ui:Destroy()
		end
	end)
	return app
end
return { InitDeps = InitDeps, Main = CreateModule }
