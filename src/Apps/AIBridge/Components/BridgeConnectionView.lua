--!strict

local Apps, Lib, Main

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Lib, Main = d.Apps, d.Lib, d.Main
end
------------------------------ Module ------------------------------

local function CreateModule()
	local View = {}
	function View.Create(parent, ui, actions)
		local theme, palette = ui.Theme, ui.Palette
		local muted = theme.PlaceholderText
		local view = {}
		local expanded = false
		local lastModel
		local green, red, amber =
			Color3.fromRGB(94, 193, 129), Color3.fromRGB(230, 99, 105), Color3.fromRGB(225, 180, 82)
		local inset = 16
		local pairingY, pairingHeight, pairingGap = 88, 32, 14
		local permissionSplit, rowHeight = 0.525, 36
		local statusStrip = ui:Node("Frame", {
			Name = "StatusStrip",
			Parent = parent,
			Position = UDim2.fromOffset(inset, 14),
			Size = UDim2.new(1, -2 * inset, 0, 32),
			BackgroundColor3 = palette.Raised,
			BorderSizePixel = 0,
		})
		ui:Round(statusStrip, 3)
		local toggle = ui:Button(
			statusStrip,
			"SessionStatus",
			"",
			UDim2.fromOffset(0, 2),
			UDim2.fromOffset(140, 28),
			function()
				expanded = not expanded
				view:Update(lastModel)
			end,
			"quiet"
		)
		local help = ui:Button(
			statusStrip,
			"ConnectionHelp",
			"",
			UDim2.new(1, -125, 0, 2),
			UDim2.fromOffset(121, 28),
			actions.Help,
			"quiet"
		)
		ui:Round(help.Gui, 3)
		local helpText =
			ui:Text(help.Gui, "Label", "Connection Help", UDim2.fromOffset(3, 0), UDim2.new(1, -28, 1, 0), false, 13)
		helpText.TextXAlignment = Enum.TextXAlignment.Right
		ui:Icon(help.Gui, "HelpIcon", "external-v2", UDim2.new(1, -20, 0.5, -7), 14)
		local dot = ui:Node("Frame", {
			Name = "StatusDot",
			Parent = toggle.Gui,
			Position = UDim2.fromOffset(8, 9),
			Size = UDim2.fromOffset(10, 10),
			BorderSizePixel = 0,
		})
		ui:Node("UICorner", { Parent = dot, CornerRadius = UDim.new(1, 0) })
		local status =
			ui:Text(toggle.Gui, "State", "Disconnected", UDim2.fromOffset(30, 0), UDim2.fromOffset(120, 28), false, 13)
		local chevron = ui:Node("ImageLabel", {
			Name = "Chevron",
			Parent = toggle.Gui,
			Image = Main.GetStudioAsset("native/editor/submenu") or "",
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Visible = false,
		})
		local function fitStatus()
			local textEnd = status.Position.X.Offset + math.ceil(status.TextBounds.X)
			chevron.Position = UDim2.fromOffset(textEnd + 5, 8)
			toggle.Gui.Size = UDim2.fromOffset(textEnd + (chevron.Visible and 22 or 6), 28)
		end
		status:GetPropertyChangedSignal("TextBounds"):Connect(fitStatus)
		local summary =
			ui:Text(parent, "Summary", "", UDim2.fromOffset(inset, 49), UDim2.new(1, -2 * inset, 0, 18), true, 11)
		local title = ui:Text(
			parent,
			"PairingLabel",
			"Pairing code",
			UDim2.fromOffset(inset, 62),
			UDim2.new(1, -2 * inset, 0, 20),
			false,
			14
		)
		title.Font = Lib.StudioBold or Lib.StudioFont
		local code = ui:Field(
			parent,
			"PairingCode",
			"Paste pairing code",
			UDim2.fromOffset(inset, pairingY),
			UDim2.new(1, -(2 * inset + pairingGap + 100), 0, pairingHeight)
		)
		code.BackgroundColor3 = palette.Input
		code.TextSize = 13
		ui:Round(code, 3)
		local connect = ui:Button(
			parent,
			"Connect",
			"Connect",
			UDim2.new(1, -116, 0, pairingY),
			UDim2.fromOffset(100, pairingHeight),
			actions.Connect,
			"primary"
		)
		ui:Round(connect.Gui, 3)
		connect.Gui.TextSize = 14
		local pause =
			ui:Button(parent, "Pause", "Pause", UDim2.fromOffset(inset, 74), UDim2.fromOffset(78, 28), actions.Pause)
		local details =
			ui:Text(parent, "Session", "", UDim2.fromOffset(inset, 123), UDim2.new(1, -2 * inset, 0, 18), true, 11)
		local error = ui:Node("Frame", {
			Name = "ConnectionError",
			Parent = parent,
			Position = UDim2.fromOffset(inset, 125),
			Size = UDim2.new(1, -2 * inset, 0, 44),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
		})
		ui:Node("Frame", { Parent = error, Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = red, BorderSizePixel = 0 })
		local errorText = ui:Text(error, "Error", "", UDim2.fromOffset(10, 0), UDim2.new(1, -10, 1, 0), false, 11)
		errorText.TextColor3 = red
		errorText.TextWrapped = true
		errorText.TextTruncate = Enum.TextTruncate.None
		errorText.TextYAlignment = Enum.TextYAlignment.Top
		local rule = ui:Rule(parent, "ConnectionDivider", 144)
		rule.Size = UDim2.new(1, -2 * inset, 0, 1)
		rule.BackgroundColor3 = palette.Border
		rule.BackgroundTransparency = 0
		local access = ui:Node("Frame", {
			Name = "Permissions",
			Parent = parent,
			Position = UDim2.fromOffset(inset, 165),
			Size = UDim2.new(1, -2 * inset, 0, 3 * rowHeight),
			BackgroundColor3 = palette.Raised,
			BackgroundTransparency = 0.64,
			BorderSizePixel = 0,
		})
		ui:Round(access, 2)
		ui:Outline(access)
		ui:Node("Frame", {
			Name = "ValueDivider",
			Parent = access,
			Position = UDim2.new(permissionSplit, 0, 0, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = palette.Border,
			BorderSizePixel = 0,
		})
		local buttons = {}
		local rows = {
			{ "Inspect", "Read objects, scripts, and captures.", nil },
			{ "Edit objects", "Change properties, selection, and transforms.", "edit" },
			{ "Run code", "Run Luau and call remotes or bindables.", "execute" },
		}
		for index, data in ipairs(rows) do
			local row = ui:Node("Frame", {
				Parent = access,
				Name = data[1],
				Position = UDim2.fromOffset(0, (index - 1) * rowHeight),
				Size = UDim2.new(1, 0, 0, rowHeight),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			})
			if index > 1 then
				ui:Node("Frame", {
					Parent = row,
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = palette.Border,
					BorderSizePixel = 0,
				})
			end
			local label = ui:Text(
				row,
				"Title",
				data[1],
				UDim2.fromOffset(16, 0),
				UDim2.new(permissionSplit, -24, 1, 0),
				false,
				14
			)
			ui:Tip(label, data[2])
			if data[3] then
				local key = data[3]
				local control = ui:Switch(row, key, UDim2.new(permissionSplit, 16, 0.5, -10), function()
					actions.Grant(key)
				end)
				ui:Tip(
					control.Gui,
					key == "execute" and "Run Luau and call remotes. These actions may be permanent."
						or "Edit objects through Dex."
				)
				buttons[key] = control
			else
				ui:Text(
					row,
					"Access",
					"Always on",
					UDim2.new(permissionSplit, 16, 0, 0),
					UDim2.new(1 - permissionSplit, -24, 1, 0),
					true,
					13
				)
			end
		end
		local note =
			ui:Text(parent, "AccessNote", "", UDim2.fromOffset(inset, 0), UDim2.new(1, -2 * inset, 0, 20), true, 11)
		function view:Update(model)
			lastModel = model
			local client = model.Client
			local state = client.State
			local paired = client.SessionId ~= nil
			local connected = state == "Connected"
			local paused = client.Paused
			local info = client:GetSummary()
			if not paired then
				expanded = false
			end
			local busy = connected and not paused and info.ActiveCommand ~= nil
			local collapsed = connected and paired and not expanded
			toggle:SetEnabled(connected and paired)
			chevron.Visible = connected and paired
			chevron.Rotation = expanded and 90 or 0
			status.Text = paused and "Paused" or busy and "Busy" or state
			help.Gui.Visible = not paired
			fitStatus()
			dot.BackgroundColor3 = paused and amber
				or busy and theme.Focus
				or connected and green
				or (state == "Connecting" or state == "Reconnecting") and amber
				or red
			local port = info.Port and "Local server on port " .. info.Port or "Local server"
			summary.Text = busy and "Running " .. info.ActiveCommand:gsub("^dex_", ""):gsub("_", " ") .. "…"
				or paired and port
				or ""
			title.Visible = not paired
			code.Visible = not paired
			code.TextEditable = not model.Busy
			pause.Gui.Visible = connected and not collapsed
			pause.Gui.Text = paused and "Resume" or "Pause"
			pause:SetEnabled(connected and not model.Busy)
			local paste = model.CanPaste and code.Text == ""
			connect.Gui.Text = state == "Connecting" and "Cancel"
				or paired and "Disconnect"
				or paste and "Paste & Connect"
				or "Connect"
			connect:SetKind((paired or state == "Connecting") and "secondary" or "primary")
			connect.Gui.Visible = not collapsed
			local buttonWidth = paste and not paired and 126 or 100
			connect.Gui.Position = paired and UDim2.fromOffset(connected and inset + 86 or inset, 74)
				or UDim2.new(1, -inset - buttonWidth, 0, pairingY)
			connect.Gui.Size = UDim2.fromOffset(buttonWidth, paired and 28 or pairingHeight)
			code.Size = UDim2.new(1, -(2 * inset + pairingGap + buttonWidth), 0, pairingHeight)
			connect:SetEnabled(
				paired
					or state == "Connecting"
					or not model.Busy
						and client:Supported()
						and (paste or Apps.BridgeClient.ParseCode(code.Text) ~= nil)
			)
			details.TextColor3 = muted
			if state == "Connecting" then
				details.Text = ""
			elseif code.Text ~= "" then
				local valid = Apps.BridgeClient.ParseCode(code.Text) ~= nil
				details.Text = valid and "Ready to connect" or "Include the port and full code."
				details.TextColor3 = valid and green or amber
			else
				details.Text = ""
			end
			for key, control in pairs(buttons) do
				control:SetOn(model.Grants[key] == true)
				control:SetEnabled(not model.Busy)
			end
			local problem = model.PairingError or client.Error
			local dividerY = paired and (collapsed and 76 or 114) or 144
			local errorY = paired and (collapsed and 72 or 108) or 125
			if problem then
				dividerY = errorY + 50
			end
			error.Position = UDim2.fromOffset(inset, errorY)
			error.Visible = problem ~= nil
			errorText.Text = problem or ""
			details.Visible = not paired and problem == nil
			rule.Position = UDim2.fromOffset(inset, dividerY)
			local accessY = dividerY + 21
			local noteY = accessY + 3 * rowHeight + 8
			access.Position = UDim2.fromOffset(inset, accessY)
			note.Position = UDim2.fromOffset(inset, noteY)
			note.Text = model.Notice or (model.Busy and "Updating…" or "")
			note.TextColor3 = model.Notice and (model.NoticeError and red or green) or muted
			note.Visible = note.Text ~= ""
			parent.CanvasSize = UDim2.fromOffset(0, noteY + (note.Visible and 25 or 12))
		end
		view.Code = code
		view.Connect = connect
		view.Pause = pause
		view.State = status
		view.StatusControl = toggle.Gui
		view.StatusDot = dot
		view.Permissions = buttons
		return view
	end
	return View
end
return { InitDeps = InitDeps, Main = CreateModule }
