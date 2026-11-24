--!strict

local Main, Lib, Apps, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, service = d.Main, d.Lib, d.Apps, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Dialog = {}
	local window, renderer, searchRef, listRef
	local names, filtered = {}, {}
	local query, selected = "", nil
	local rendering = false
	local function rebuild()
		filtered = {}
		for _, name in ipairs(names) do
			if name:lower():find(query:lower(), 1, true) then
				filtered[#filtered + 1] = name
			end
		end
		if not table.find(filtered, selected) then
			selected = filtered[1]
		end
		Dialog.Entries = filtered
	end
	local render
	function Dialog.Insert()
		if not selected then
			return
		end
		local object, problem = Apps.ServiceVisibility.Show(selected)
		if not object then
			Dialog.Error = problem
			render()
			return
		end
		local explorer = Apps.Explorer
		explorer.SyncHistoryObject(object)
		explorer.ForceUpdate()
		explorer.ViewObj(object)
		explorer.SelectService(object)
		explorer.Refresh()
		names = Apps.ServiceVisibility.GetHiddenServices()
		Dialog.Error = nil
		rebuild()
		render()
	end
	local function close()
		searchRef.current:ReleaseFocus()
		window:Close()
	end
	render = function()
		if rendering then
			return
		end
		rendering = true
		local React = Apps.React.React
		local e = React.createElement
		local theme = Settings.Theme
		local list = listRef.current
		local offset = list and list.CanvasPosition.Y or 0
		local visible = list and list.AbsoluteSize.Y or 300
		local first = math.min(math.max(1, #filtered), math.max(1, math.floor(offset / 24) + 1))
		local last = math.min(#filtered, first + math.ceil(visible / 24) + 1)
		local children = {}
		Dialog.MountedRows = 0
		for index = first, last do
			local name = filtered[index]
			Dialog.MountedRows += 1
			children[name] = e("TextButton", {
				Name = "Service_" .. name,
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				BackgroundColor3 = theme.ListSelection,
				BackgroundTransparency = name == selected and 0 or 1,
				Position = UDim2.fromOffset(0, (index - 1) * 24),
				Size = UDim2.new(1, -2, 0, 24),
				[React.Event.Activated] = function()
					selected = name
					render()
				end,
			}, {
				Icon = e("ImageLabel", {
					BackgroundTransparency = 1,
					Image = Main.GetStudioAsset("class/" .. name) or Main.GetStudioAsset("class/Service") or "",
					Position = UDim2.fromOffset(6, 4),
					Size = UDim2.fromOffset(16, 16),
				}),
				Label = e("TextLabel", {
					BackgroundTransparency = 1,
					Text = name,
					Font = Enum.Font.BuilderSans,
					TextSize = 14,
					TextColor3 = theme.Text,
					Position = UDim2.fromOffset(28, 0),
					Size = UDim2.new(1, -32, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			})
		end
		local function button(name, position, callback)
			return e("TextButton", {
				Name = name,
				Text = name,
				Font = Enum.Font.BuilderSans,
				TextSize = 14,
				TextColor3 = theme.Text,
				BorderSizePixel = 0,
				BackgroundColor3 = theme.Button,
				Position = position,
				Size = UDim2.fromOffset(76, 24),
				Active = name ~= "Insert" or selected ~= nil,
				TextTransparency = name == "Insert" and not selected and 0.6 or 0,
				[React.Event.Activated] = callback,
			})
		end
		renderer:Portal(
			"ServiceVisibilityDialog",
			e("Frame", { Name = "InsertService", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, {
				Search = e("TextBox", {
					Name = "SearchServices",
					ref = searchRef,
					ClearTextOnFocus = false,
					Text = query,
					PlaceholderText = "Search",
					Font = Enum.Font.BuilderSans,
					TextSize = 14,
					TextColor3 = theme.Text,
					PlaceholderColor3 = theme.PlaceholderText,
					BackgroundColor3 = theme.TextBox,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(10, 10),
					Size = UDim2.new(1, -20, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				List = e("ScrollingFrame", {
					Name = "Services",
					ref = listRef,
					BackgroundColor3 = theme.Main2,
					BorderSizePixel = 0,
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = theme.PlaceholderText,
					CanvasSize = UDim2.fromOffset(0, #filtered * 24),
					Position = UDim2.fromOffset(10, 42),
					Size = UDim2.new(1, -20, 1, -104),
					ClipsDescendants = true,
				}, children),
				Message = e("TextLabel", {
					Name = "Message",
					Text = Dialog.Error or (#filtered == 0 and "No services to show" or ""),
					Font = Enum.Font.BuilderSans,
					TextSize = 12,
					TextColor3 = theme.Text,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 10, 1, -60),
					Size = UDim2.new(1, -20, 0, 20),
				}),
				Insert = button("Insert", UDim2.new(1, -174, 1, -34), Dialog.Insert),
				Done = button("Done", UDim2.new(1, -88, 1, -34), close),
			}),
			window.GuiElems.Content
		)
		Dialog.Commits = (Dialog.Commits or 0) + 1
		rendering = false
	end
	function Dialog.Open()
		if not window then
			renderer = Apps.Explorer.TreeRenderer
			local React = Apps.React.React
			searchRef, listRef = React.createRef(), React.createRef()
			window = Lib.Window.new()
			window:SetTitle("Insert Service")
			window:SetSize(360, 430)
			window.Alignable = false
			window.Resizable = false
			if window.GuiElems.Minimize then
				window.GuiElems.Minimize.Visible = false
			end
			window.GuiElems.Content.BackgroundColor3 = Settings.Theme.Main1
			names = Apps.ServiceVisibility.GetHiddenServices()
			rebuild()
			render()
			searchRef.current:GetPropertyChangedSignal("Text"):Connect(function()
				if rendering then
					return
				end
				query = searchRef.current.Text:gsub("[\r\n]", ""):sub(1, 32767)
				Dialog.Error = nil
				rebuild()
				listRef.current.CanvasPosition = Vector2.new(0, 0)
				render()
			end)
			listRef.current:GetPropertyChangedSignal("CanvasPosition"):Connect(render)
			Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if
					window.Closed
					or (
						service.UserInputService:GetFocusedTextBox() ~= searchRef.current
						and Main.ActiveFocusOwner ~= window
					)
				then
					return
				end
				if input.KeyCode == Enum.KeyCode.Escape then
					close()
				elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
					Dialog.Insert()
				elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.Up then
					local index = table.find(filtered, selected) or 0
					selected = filtered[math.clamp(
						index + (input.KeyCode == Enum.KeyCode.Down and 1 or -1),
						1,
						math.max(1, #filtered)
					)]
					local list = listRef.current
					local top = ((table.find(filtered, selected) or 1) - 1) * 24
					if top < list.CanvasPosition.Y then
						list.CanvasPosition = Vector2.new(0, top)
					elseif top + 24 > list.CanvasPosition.Y + list.AbsoluteSize.Y then
						list.CanvasPosition = Vector2.new(0, math.max(0, top + 24 - list.AbsoluteSize.Y))
					end
					render()
				end
			end)
			Dialog.Window = window
		end
		names = Apps.ServiceVisibility.GetHiddenServices()
		query = ""
		Dialog.Error = nil
		rebuild()
		listRef.current.CanvasPosition = Vector2.new(0, 0)
		render()
		window:Show()
		searchRef.current:CaptureFocus()
	end
	return Dialog
end
return { InitDeps = InitDeps, Main = CreateModule }
