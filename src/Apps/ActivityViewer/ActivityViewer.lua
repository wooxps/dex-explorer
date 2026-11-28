--!strict

local Main, Lib, Apps, service, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, service, env = d.Main, d.Lib, d.Apps, d.service, d.env or {}
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Viewer = {}
	local window, session, list, filter, status, empty, pause
	local rows = {}
	local filtered = {}
	local revision = -1
	local query = ""
	local elapsed = 0
	local selected
	local kindFilter = "All events"
	local typeButton, details, objectValue, beforeValue, afterValue
	local notice = ""
	local colors = {
		Surface = Color3.fromRGB(25, 26, 31),
		Chrome = Color3.fromRGB(33, 34, 39),
		Text = Color3.fromRGB(204, 204, 204),
		Muted = Color3.fromRGB(155, 157, 165),
		Selected = Color3.fromRGB(9, 71, 113),
	}
	local function node(class, props)
		local object = Instance.new(class)
		for key, value in pairs(props) do
			object[key] = value
		end
		return object
	end
	local function escaped(text)
		return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	end
	local function tip(widget, text)
		if Lib.StudioTooltip then
			Lib.StudioTooltip(widget, text)
		end
	end
	local function label(parent, name, size)
		return node("TextLabel", {
			Name = name,
			Parent = parent,
			Text = "",
			Font = Lib.StudioFont,
			TextSize = size or 12,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
	end
	local function detail(event)
		if event.Before == "" and event.After == "" then
			return event.Name
		end
		if (event.Kind == "Child added" or event.Kind == "Descendant added") and event.BeforeKnown == false then
			return event.Name .. " added to " .. event.After
		end
		return event.Name
			.. ": "
			.. event.Before
			.. " → "
			.. event.After
			.. (event.Changes > 1 and " (" .. event.Changes .. " changes)" or "")
	end
	local paint, refresh
	local function eventText(event)
		return string.format(
			"%.3fs | %s | %s\nObject: %s\nBefore: %s\nAfter: %s\nChanges combined: %d",
			event.Time,
			event.Kind,
			event.Name,
			event.ObjectPath or event.Name,
			event.BeforeKnown == false and "Not observed" or event.Before,
			event.After,
			event.Changes
		)
	end
	local function copy(text)
		local ok = type(env.setclipboard) == "function" and pcall(env.setclipboard, text)
		notice = ok and "Copied to clipboard" or "Clipboard is unavailable"
		refresh(true)
	end
	local function menu(event, point)
		local context = Apps.ContextMenu.new()
		context.Iconless = true
		context.Width = 220
		if event then
			context:Add({
				Name = "Watch this object",
				OnClick = function()
					local object = event.Object and event.Object[1]
					if object then
						Viewer.Open(object)
					end
				end,
			})
			context:Add({
				Name = "Filter by this name",
				OnClick = function()
					filter.Text = event.Name
					refresh(true)
				end,
			})
			context:Add({
				Name = "Copy event",
				Disabled = type(env.setclipboard) ~= "function",
				OnClick = function()
					copy(eventText(event))
				end,
			})
			context:Add({
				Name = "Copy previous value",
				Disabled = type(env.setclipboard) ~= "function" or event.BeforeKnown == false,
				OnClick = function()
					copy(event.Before)
				end,
			})
			context:Add({
				Name = "Copy new value",
				Disabled = type(env.setclipboard) ~= "function",
				OnClick = function()
					copy(event.After)
				end,
			})
			if event.Kind == "Property" or event.Kind == "Attribute" then
				context:AddDivider()
				context:Add({
					Name = "Restore previous value",
					Disabled = event.BeforeKnown == false,
					OnClick = function()
						local _, message = Apps.ActivitySession.Restore(event)
						notice = message
						session:Flush()
						refresh(true)
					end,
				})
			end
		else
			context:Add({
				Name = "Watch Explorer selection",
				OnClick = function()
					local chosen = Apps.Explorer.Selection.List[1]
					if chosen then
						Viewer.Open(chosen.Obj)
					end
				end,
			})
			context:Add({
				Name = "Clear events",
				OnClick = function()
					session:Clear()
					selected = nil
					notice = ""
					refresh(true)
				end,
			})
			context:AddDivider()
			context:Add({
				Name = "Copy filtered events",
				Disabled = type(env.setclipboard) ~= "function",
				OnClick = function()
					local lines = {}
					for _, entry in ipairs(filtered) do
						lines[#lines + 1] = eventText(entry)
					end
					copy(table.concat(lines, "\n\n"))
				end,
			})
			context:Add({
				Name = "Follow latest events",
				OnClick = function()
					list.CanvasPosition = Vector2.new(0, math.max(0, list.CanvasSize.Y.Offset - list.AbsoluteSize.Y))
				end,
			})
		end
		local mouse = point or service.UserInputService:GetMouseLocation()
		context:Show(mouse.X, mouse.Y)
	end
	paint = function()
		if not list then
			return
		end
		details.Visible = selected ~= nil
		local reserved = selected and 170 or 76
		local size = UDim2.new(1, 0, 1, -reserved)
		if list.Size ~= size then
			list.Size = size
		end
		local first = math.floor(list.CanvasPosition.Y / 24) + 1
		local count = math.max(1, math.ceil(list.AbsoluteSize.Y / 24) + 1)
		empty.Visible = #filtered == 0
		empty.Text = (filter.Text ~= "" or kindFilter ~= "All events") and "No matching events"
			or not session.Running and "Recording stopped"
			or session.Paused and "Recording paused"
			or "Waiting for changes..."
		for slot = 1, count do
			local record = rows[slot]
			if not record then
				local gui = node("TextButton", {
					Name = "ActivityRow",
					Parent = list,
					Text = "",
					BackgroundColor3 = colors.Selected,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					Size = UDim2.new(1, -6, 0, 24),
				})
				local time = label(gui, "Time", 11)
				time.TextColor3 = colors.Muted
				time.Position = UDim2.fromOffset(8, 0)
				time.Size = UDim2.new(0, 60, 1, 0)
				local kind = label(gui, "Kind", 11)
				kind.TextColor3 = colors.Muted
				kind.Position = UDim2.fromOffset(74, 0)
				kind.Size = UDim2.new(0, 108, 1, 0)
				local object = label(gui, "Object", 12)
				object.Position = UDim2.fromOffset(186, 0)
				object.Size = UDim2.new(0.28, 0, 1, 0)
				local text = label(gui, "Detail", 12)
				text.Position = UDim2.new(0.28, 194, 0, 0)
				text.Size = UDim2.new(0.72, -202, 1, 0)
				record = { Gui = gui, Time = time, Kind = kind, Text = text, Object = object }
				rows[slot] = record
				local pressed, held
				gui.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.Touch then
						pressed, held = record.Event, false
					elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
						held = false
					end
				end)
				gui.TouchLongPress:Connect(function(points, state)
					if state ~= Enum.UserInputState.Begin or #points ~= 1 or not pressed or pressed ~= record.Event then return end
					held, selected, notice = true, pressed, ""
					paint()
					menu(selected, points[1])
				end)
				gui.MouseButton1Click:Connect(function()
					if held then held = false return end
					selected = record.Event
					notice = ""
					paint()
					local object = selected and selected.Object and selected.Object[1]
					if object and Apps.Explorer.GetNodes()[object] then
						Apps.Explorer.SelectService(object)
						Apps.Explorer.ViewObj(object)
					end
				end)
				gui.MouseButton2Click:Connect(function()
					selected = record.Event
					notice = ""
					paint()
					menu(selected)
				end)
				gui.MouseEnter:Connect(function()
					gui.BackgroundTransparency = 0
				end)
				gui.MouseLeave:Connect(function()
					gui.BackgroundTransparency = record.Event == selected and 0 or 1
				end)
				tip(gui, function()
					local event = record.Event
					if not event then
						return ""
					end
					local before = event.BeforeKnown == false and "Previous parent was not observed."
						or "Before: " .. event.Before
					return escaped(
						event.Kind
							.. " • "
							.. event.Name
							.. "\nObject: "
							.. (event.ObjectPath or event.Name)
							.. "\n"
							.. before
							.. "\nAfter: "
							.. event.After
							.. (event.Changes > 1 and "\n" .. event.Changes .. " changes combined" or "")
					)
				end)
			end
			local event = filtered[first + slot - 1]
			record.Event = event
			record.Gui.Visible = event ~= nil
			if event then
				record.Gui.Position = UDim2.fromOffset(0, (first + slot - 2) * 24)
				record.Gui.BackgroundTransparency = event == selected and 0 or 1
				record.Time.Text = string.format("%02d:%05.2f", math.floor(event.Time / 60), event.Time % 60)
				record.Kind.Text = event.Kind
				record.Object.Text = event.ObjectName or event.Name
				record.Text.Text = detail(event)
			end
		end
		for slot = count + 1, #rows do
			rows[slot].Gui.Visible = false
			rows[slot].Event = nil
		end
		if selected then
			objectValue.Text = (selected.ObjectPath or selected.Name) .. "  ·  " .. selected.Name
			beforeValue.Text = selected.BeforeKnown == false and "Not observed" or selected.Before
			afterValue.Text = selected.After
		end
	end
	refresh = function(force)
		if not list then
			return
		end
		local current = filter.Text:lower()
		if force or revision ~= session.Revision or query ~= current then
			local endY = math.max(0, list.CanvasSize.Y.Offset - list.AbsoluteSize.Y)
			local follow = list.CanvasPosition.Y >= endY - 24
			filtered = {}
			for _, event in ipairs(session:Events()) do
				if
					(kindFilter == "All events" or event.Kind == kindFilter)
					and (
						current == ""
						or (event.Kind .. " " .. (event.ObjectPath or "") .. " " .. detail(event))
							:lower()
							:find(current, 1, true)
					)
				then
					filtered[#filtered + 1] = event
				end
			end
			list.CanvasSize = UDim2.fromOffset(0, #filtered * 24)
			if follow then
				list.CanvasPosition = Vector2.new(0, math.max(0, #filtered * 24 - list.AbsoluteSize.Y))
			end
			revision = session.Revision
			query = current
			paint()
		end
		pause.Text = session.Paused and "Resume" or "Pause"
		pause.Interactable = session.Running
		local coverage = session.Running and not session.Paused and "  ·  " .. session.WatchedObjects .. " objects"
			or ""
		status.Text = notice ~= "" and notice
			or (not session.Running and "Stopped" or session.Paused and "Paused" or "Recording")
				.. coverage
				.. "  ·  "
				.. #filtered
				.. " events"
				.. (session.PendingObjects > 0 and "  ·  Setting up " .. session.PendingObjects .. " more" or "")
				.. (session.Dropped > 0 and "  ·  Older/excess events discarded" or "")
	end
	function Viewer.Open(object)
		if not object then
			return
		end
		if not window then
			Viewer.Init()
		end
		session:Start(object)
		selected = nil
		notice = ""
		kindFilter = "All events"
		typeButton.Text = kindFilter
		filter.Text = ""
		list.CanvasPosition = Vector2.new(0, 0)
		window:SetTitle("Activity - " .. object.Name)
		window:Show()
		refresh(true)
	end
	function Viewer.Init()
		if window then
			return
		end
		window = Lib.Window.new()
		Viewer.Window = window
		window:SetTitle("Object Activity")
		window.MinX = 640
		window.MinY = 260
		window:Resize(820, 440)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		session = Apps.ActivitySession.Create()
		Viewer.Session = session
		local content = window.GuiElems.Content
		content.BackgroundColor3 = colors.Surface
		local bar = node("Frame", {
			Name = "Toolbar",
			Parent = content,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		local function button(name, text, x, width, callback)
			local object = node("TextButton", {
				Name = name,
				Parent = bar,
				Text = text,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = colors.Text,
				Position = UDim2.new(1, x, 0, 3),
				Size = UDim2.fromOffset(width, 24),
				BackgroundColor3 = colors.Selected,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				BorderSizePixel = 0,
			})
			object.MouseButton1Click:Connect(callback)
			object.MouseEnter:Connect(function()
				object.BackgroundTransparency = 0
			end)
			object.MouseLeave:Connect(function()
				object.BackgroundTransparency = 1
			end)
			return object
		end
		pause = button("Pause", "Pause", -96, 60, function()
			session:Pause(not session.Paused)
			notice = ""
			refresh(true)
		end)
		button("More", "⋯", -32, 28, function()
			menu()
		end)
		typeButton = button("EventTypes", "All events", -204, 104, function()
			local context = Apps.ContextMenu.new()
			context.Iconless = true
			context.Width = 160
			for _, kind in ipairs({
				"All events",
				"Property",
				"Attribute",
				"Parent",
				"Child added",
				"Child moved",
				"Child removed",
				"Descendant added",
				"Descendant moved",
				"Descendant removed",
				"Paused",
				"Resumed",
				"Stopped",
			}) do
				context:Add({
					Name = kind,
					OnClick = function()
						kindFilter = kind
						typeButton.Text = kind
						refresh(true)
					end,
				})
			end
			context:Show(typeButton.AbsolutePosition.X, typeButton.AbsolutePosition.Y + 24)
		end)
		filter = node("TextBox", {
			Name = "Filter",
			Parent = bar,
			Text = "",
			PlaceholderText = "Filter events",
			ClearTextOnFocus = false,
			MultiLine = false,
			Font = Lib.StudioFont,
			TextSize = 13,
			TextColor3 = colors.Text,
			PlaceholderColor3 = colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = colors.Surface,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(5, 4),
			Size = UDim2.new(1, -249, 0, 22),
		})
		filter.Size = UDim2.new(1, -214, 0, 22)
		node("UIPadding", { Parent = filter, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
		local headings = node("Frame", {
			Name = "Columns",
			Parent = content,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = colors.Surface,
			BorderSizePixel = 0,
		})
		for _, column in ipairs({
			{ "Time", UDim2.fromOffset(8, 0), UDim2.new(0, 60, 1, 0) },
			{ "Event", UDim2.fromOffset(74, 0), UDim2.new(0, 108, 1, 0) },
			{ "Object", UDim2.fromOffset(186, 0), UDim2.new(0.28, 0, 1, 0) },
			{ "Change", UDim2.new(0.28, 194, 0, 0), UDim2.new(0.72, -202, 1, 0) },
		}) do
			local heading = label(headings, column[1], 11)
			heading.Text = column[1]
			heading.TextColor3 = colors.Muted
			heading.Position = column[2]
			heading.Size = column[3]
		end
		list = node("ScrollingFrame", {
			Name = "Timeline",
			Parent = content,
			Position = UDim2.fromOffset(0, 54),
			Size = UDim2.new(1, 0, 1, -76),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.fromOffset(0, 0),
			CanvasPosition = Vector2.new(0, 0),
			ClipsDescendants = true,
		})
		empty = label(list, "Empty", 13)
		empty.Position = UDim2.fromOffset(12, 10)
		empty.Size = UDim2.new(1, -24, 0, 24)
		empty.TextColor3 = colors.Muted
		details = node("Frame", {
			Name = "EventDetails",
			Parent = content,
			Position = UDim2.new(0, 0, 1, -116),
			Size = UDim2.new(1, 0, 0, 94),
			Visible = false,
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		local function valueRow(name, y)
			local caption = label(details, name .. "Label", 11)
			caption.Text = name
			caption.TextColor3 = colors.Muted
			caption.Position = UDim2.fromOffset(8, y)
			caption.Size = UDim2.fromOffset(52, 24)
			local value = label(details, name, 12)
			value.Position = UDim2.fromOffset(66, y)
			value.Size = UDim2.new(1, -76, 0, 24)
			tip(value, function()
				return escaped(value.Text)
			end)
			return value
		end
		objectValue = valueRow("Object", 6)
		beforeValue = valueRow("Before", 34)
		afterValue = valueRow("After", 62)
		tip(
			details,
			"Right-click an event to copy values, watch its object, or restore a property or attribute. Restoring refuses to overwrite a value that changed again."
		)
		local footer = node("Frame", {
			Name = "Footer",
			Parent = content,
			Position = UDim2.new(0, 0, 1, -22),
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		status = label(footer, "Status", 12)
		status.Position = UDim2.fromOffset(8, 0)
		status.Size = UDim2.new(1, -16, 1, 0)
		tip(status, function()
			return session.ReadableProperties
				.. " readable properties across "
				.. session.WatchedObjects
				.. " objects.\nThe selected object and its descendants are monitored, including new descendants. Dex's own UI is excluded.\nRapid changes are combined; the most recent 500 events are kept."
		end)
		Viewer.Filter = filter
		Viewer.Rows = rows
		Viewer.List = list
		Viewer.Status = status
		filter:GetPropertyChangedSignal("Text"):Connect(function()
			refresh(true)
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		Main.TrackSignal(list:GetPropertyChangedSignal("AbsoluteSize"), paint)
		Main.TrackSignal(window.OnDeactivate, function()
			if window.Closed then
				session:Stop()
				refresh(true)
			end
		end)
		Main.TrackSignal(service.RunService.Heartbeat, function(dt)
			if window.Closed then
				return
			end
			elapsed += dt
			if elapsed < 0.1 then
				session:Step()
				return
			end
			elapsed = 0
			session:Flush()
			if not window.Minimized then
				refresh()
			end
		end)
		Main.AddCleanup(function()
			session:Destroy()
			for _, record in ipairs(rows) do
				record.Event = nil
			end
			table.clear(rows)
			table.clear(filtered)
			selected = nil
		end)
	end
	return Viewer
end
return { InitDeps = InitDeps, Main = CreateModule }
