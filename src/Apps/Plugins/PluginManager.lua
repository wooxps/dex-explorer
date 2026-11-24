--!strict

local Apps, Main, Lib, Settings, env

local function InitDeps(deps)
	Apps, Main, Lib, Settings, env = deps.Apps, deps.Main, deps.Lib, deps.Settings, deps.env
end

local function CreateModule()
	local Manager = {}
	local runtime = Apps.PluginRuntime
	local theme = Settings.Theme
	local skin = Apps.StudioEditorSkin
	local window, ui, body, footer, current, sourceMenu
	local render, review, showDetails
	local pad = 14
	local footerHeight = 46
	local fileBarHeight = 48
	local fileHeadingHeight = 23
	local accent = Color3.fromRGB(128, 162, 249)
	local warning = Color3.fromRGB(226, 187, 108)
	local errorColor = Color3.fromRGB(231, 151, 146)

	local function section(parent, name, gap)
		local group = ui:Node("Frame", {
			Parent = parent,
			Name = name,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = #parent:GetChildren(),
		})
		ui:Node("UIListLayout", {
			Parent = group,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap or 6),
		})
		return group
	end

	local function label(parent, name, text, size, color)
		local item = ui:Text(parent, name, text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), false, size)
		item.AutomaticSize = Enum.AutomaticSize.Y
		item.TextWrapped = true
		item.TextTruncate = Enum.TextTruncate.None
		item.TextYAlignment = Enum.TextYAlignment.Top
		item.TextColor3 = color or theme.Text
		item.LayoutOrder = #parent:GetChildren()
		return item
	end

	local function divider(parent)
		ui:Node("Frame", {
			Parent = parent,
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = theme.Outline2,
			BorderSizePixel = 0,
			LayoutOrder = #parent:GetChildren(),
		})
	end

	local function pluginHeader(parent, plugin)
		local row = ui:Node("Frame", {
			Parent = parent,
			Name = "PluginHeader",
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundTransparency = 1,
			LayoutOrder = #parent:GetChildren(),
		})
		local icon = ui:Round(
			ui:Node("ImageLabel", {
				Parent = row,
				Name = "Icon",
				Size = UDim2.fromOffset(40, 40),
				BackgroundColor3 = theme.Main1,
				BorderSizePixel = 0,
				Image = plugin.Icon or "",
				ScaleType = Enum.ScaleType.Fit,
			}),
			4
		)
		if icon.Image == "" then
			local fallback = Main.GetStudioAsset and Main.GetStudioAsset("native/plugins/manage")
			if fallback then
				ui:Node("ImageLabel", {
					Parent = icon,
					Position = UDim2.fromOffset(8, 8),
					Size = UDim2.fromOffset(24, 24),
					BackgroundTransparency = 1,
					Image = fallback,
					ScaleType = Enum.ScaleType.Fit,
				})
			else
				local initial = ui:Text(
					icon,
					"Initial",
					utf8.char(utf8.codepoint(plugin.Name, 1)),
					UDim2.fromOffset(0, 0),
					UDim2.fromScale(1, 1),
					false,
					21
				)
				initial.TextXAlignment = Enum.TextXAlignment.Center
			end
		end
		ui:Text(row, "Name", plugin.Name, UDim2.fromOffset(50, 0), UDim2.new(1, -50, 0, 22), false, 16)
		local byline = if plugin.Author and plugin.Author ~= ""
			then plugin.Author .. "  ·  " .. plugin.Version
			else plugin.Version
		local author = ui:Text(row, "Author", byline, UDim2.fromOffset(50, 23), UDim2.new(1, -50, 0, 16), false, 12)
		author.TextColor3 = accent
	end

	local function makeWindow()
		ui = Apps.BridgeUI.Create()
		window = Lib.Window.new()
		window.MinX = 340
		window.MinY = 250
		window:Resize(436, 322)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		local content = window.GuiElems.Content
		content.BackgroundColor3 = theme.Menu
		body = ui:Node("Frame", {
			Parent = content,
			Name = "Body",
			Size = UDim2.new(1, 0, 1, -footerHeight),
			BackgroundTransparency = 1,
		})
		footer = ui:Node("Frame", {
			Parent = content,
			Name = "Actions",
			Position = UDim2.new(0, 0, 1, -footerHeight),
			Size = UDim2.new(1, 0, 0, footerHeight),
			BackgroundColor3 = skin.Chrome,
			BorderSizePixel = 0,
		})
		Manager.Window = window
		window.OnDeactivate:Connect(function()
			if window.Closed then
				current = nil
			end
			if sourceMenu then
				sourceMenu:Hide()
			end
		end)
		Main.AddCleanup(function()
			current = nil
			if sourceMenu then
				sourceMenu:Destroy()
			end
			ui:Destroy()
			window:Destroy()
		end)
	end

	render = function(title, filePicker)
		if not window then
			makeWindow()
		end
		if sourceMenu then
			sourceMenu:Hide()
		end
		body:ClearAllChildren()
		footer:ClearAllChildren()
		window:SetTitle(title)
		local pageBody = ui:Node(filePicker and "Frame" or "ScrollingFrame", {
			Parent = body,
			Name = "PluginPage",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = not filePicker and UDim2.fromOffset(0, 0) or nil,
			AutomaticCanvasSize = not filePicker and Enum.AutomaticSize.Y or nil,
			ScrollingDirection = not filePicker and Enum.ScrollingDirection.Y or nil,
			ScrollBarThickness = not filePicker and 5 or nil,
			ScrollBarImageColor3 = not filePicker and theme.Guide or nil,
		})
		if not filePicker then
			ui:Node("UIPadding", {
				Parent = pageBody,
				PaddingTop = UDim.new(0, pad),
				PaddingBottom = UDim.new(0, pad),
				PaddingLeft = UDim.new(0, pad),
				PaddingRight = UDim.new(0, pad + 5),
			})
			ui:Node(
				"UIListLayout",
				{ Parent = pageBody, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 11) }
			)
		end
		ui:Node("Frame", {
			Parent = body,
			Position = UDim2.new(0, 0, 1, -1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = skin.Border,
			BorderSizePixel = 0,
		})
		local target = footer
		if filePicker then
			target = ui:Node("Frame", {
				Name = "Buttons",
				Parent = footer,
				Position = UDim2.new(1, -175, 0, 0),
				Size = UDim2.new(0, 175, 1, 0),
				BackgroundTransparency = 1,
			})
		end
		ui:Node("UIListLayout", {
			Parent = target,
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		})
		ui:Node("UIPadding", { Parent = target, PaddingRight = UDim.new(0, pad) })
		window:Show()
		local page = { Body = pageBody, Footer = footer }
		current = page
		function page:Action(name, text, width, callback, kind)
			local control = ui:Button(
				target,
				name,
				text,
				UDim2.fromOffset(0, 0),
				UDim2.fromOffset(width, 28),
				function()
					if current == self then
						callback()
					end
				end,
				kind
			)
			Lib.StudioCorner(control.Gui, 4)
			control.Gui.LayoutOrder = #target:GetChildren()
			return control
		end
		function page:Report(message, color)
			if self.Message then
				self.Message.Text = message or ""
				self.Message.TextColor3 = color or errorColor
				self.Message.Visible = message ~= nil
			elseif message then
				self.Message = label(self.MessageParent or self.Body, "Message", message, 13, color or errorColor)
			end
		end
		return page
	end

	local function close()
		current = nil
		window:Close()
	end

	local function clipboard()
		if type(env.getclipboard) == "function" then
			local ok, value = pcall(env.getclipboard)
			if ok and type(value) == "string" then
				return value
			end
		end
		return ""
	end

	local function addPluginDetails(parent, plugin)
		pluginHeader(parent, plugin)
		if plugin.Description and plugin.Description ~= "" then
			label(parent, "Description", plugin.Description, 14)
		end
		local buttons = {}
		for _, button in ipairs(plugin.Buttons or {}) do
			buttons[#buttons + 1] = button.Name
		end
		if #buttons > 0 then
			local toolbar = section(parent, "Toolbar", 4)
			label(toolbar, "Heading", "Toolbar buttons", 14)
			label(toolbar, "Buttons", table.concat(buttons, ", "), 13, theme.PlaceholderText)
		end
	end

	local function addSourceAction(page, id, source)
		if type(env.setclipboard) == "function" then
			page:Action("CopySource", "Copy Source", 104, function()
				local value = source or runtime.GetSource(id)
				local copied = value and pcall(env.setclipboard, value)
				if copied then
					page:Report("Source copied.", theme.PlaceholderText)
				else
					page:Report("Couldn’t copy the source.")
				end
			end)
		end
	end

	local function formatStatus(plugin)
		if plugin.Error then
			return "Plugin error", errorColor
		elseif plugin.Loading then
			return "Starting…", theme.PlaceholderText
		elseif plugin.Running then
			return "Running", Color3.fromRGB(111, 190, 135)
		elseif plugin.Enabled then
			return "Enabled", Color3.fromRGB(111, 190, 135)
		end
		return "Disabled", theme.PlaceholderText
	end

	showDetails = function(id, message)
		local plugin = runtime.Get(id)
		if not plugin then
			return
		end
		local page = render("Plugin Details")
		page.DetailID = id
		addPluginDetails(page.Body, plugin)
		divider(page.Body)
		local meta = section(page.Body, "Properties", 4)
		local status, color = formatStatus(plugin)
		label(meta, "Status", status, 13, color)
		if plugin.Path then
			label(meta, "Path", plugin.Path, 13, theme.PlaceholderText)
		elseif plugin.Link then
			label(meta, "Link", plugin.Link, 13, theme.PlaceholderText)
		end
		if plugin.Startup then
			label(meta, "Startup", "Starts with Dex", 13, theme.PlaceholderText)
		end
		page:Report(message or plugin.Error)
		addSourceAction(page, id)
		page:Action("Close", "Close", 80, close)
	end

	function Manager.Open(id)
		showDetails(id)
	end

	function Manager.ShowError(id, message)
		showDetails(id, message)
	end

	function Manager.RequestEnable(id)
		local plugin = runtime.Get(id)
		if not plugin then
			return
		end
		local page = render("Enable Plugin")
		pluginHeader(page.Body, plugin)
		divider(page.Body)
		local access = section(page.Body, "Access", 5)
		label(access, "Heading", "Plugin access", 14, warning)
		label(
			access,
			"Description",
			"This plugin can run code with the same access as Dex. Enable it only if you trust the author.",
			13
		)
		addSourceAction(page, id)
		page:Action("Cancel", "Keep Disabled", 102, close)
		local button
		button = page:Action("Enable", "Enable", 90, function()
			button:SetEnabled(false)
			local ok, reason = runtime.SetEnabled(id, true)
			if current ~= page then
				return
			end
			if ok then
				close()
			else
				page:Report(reason or "Couldn’t enable the plugin.")
				button:SetEnabled(true)
			end
		end, "primary")
	end

	function Manager.RequestRemove(id)
		local plugin = runtime.Get(id)
		if not plugin then
			return
		end
		local page = render("Uninstall Plugin")
		pluginHeader(page.Body, plugin)
		label(page.Body, "Description", "Uninstall this plugin and remove its buttons from Dex?", 14)
		page:Action("Cancel", "Cancel", 80, close)
		local button
		button = page:Action("Uninstall", "Uninstall", 90, function()
			button:SetEnabled(false)
			local ok, reason = runtime.Remove(id)
			if current ~= page then
				return
			end
			if ok then
				close()
			else
				page:Report(reason or "Couldn’t uninstall the plugin.")
				button:SetEnabled(true)
			end
		end)
		button.TextColor = errorColor
		button:Paint()
	end

	review = function(plugin, back)
		local previous = runtime.Get(plugin.ID)
		local page = render(previous and "Update Plugin" or "Review Plugin")
		addPluginDetails(page.Body, plugin)
		divider(page.Body)
		if previous then
			label(
				page.Body,
				"UpdateNotice",
				"Replaces version " .. previous.Version .. ". You’ll be asked to enable the update.",
				13,
				theme.PlaceholderText
			)
		else
			label(
				page.Body,
				"InstallNotice",
				"After installing, choose whether to enable this plugin.",
				13,
				theme.PlaceholderText
			)
		end
		addSourceAction(page, plugin.ID, plugin.Source)
		page:Action("Back", "Back", 70, back or close)
		local button
		button = page:Action("Install", previous and "Update" or "Install", 86, function()
			button:SetEnabled(false)
			local ok, reason = runtime.Install(plugin, previous ~= nil)
			if current ~= page then
				return
			end
			if ok then
				Manager.RequestEnable(plugin.ID)
			else
				page:Report(reason or "Couldn’t install the plugin.")
				button:SetEnabled(true)
			end
		end, "primary")
	end

	function Manager.ReviewUpdate(id)
		local plugin = runtime.Get(id)
		if not plugin or not (plugin.Path or plugin.Link) then
			return
		end
		local page = render("Check for Update")
		pluginHeader(page.Body, plugin)
		page:Report("Reading package…", theme.PlaceholderText)
		page:Action("Cancel", "Cancel", 72, close)
		local package, issue
		if plugin.Path then
			package, issue = runtime.ReadImport(plugin.Path)
		else
			package, issue = runtime.ReadLink(plugin.Link)
		end
		if current ~= page or not window:IsVisible() then
			return
		end
		if not package or package.ID ~= id then
			showDetails(id, issue or "The file has a different plugin ID.")
			return
		end
		if runtime.IsInstalledPackage(package) then
			showDetails(id, nil)
			current:Report("This package is already installed.", theme.PlaceholderText)
			return
		end
		review(package, function()
			showDetails(id)
		end)
	end

	local maxPackageBytes = 2 * 1024 * 1024

	local function addPackageList(page, packages, selectFile)
		local heading = ui:Node("Frame", {
			Name = "FileHeading",
			Parent = page.Body,
			Position = UDim2.fromOffset(0, fileBarHeight),
			Size = UDim2.new(1, 0, 0, fileHeadingHeight),
			BackgroundColor3 = skin.Chrome,
			BorderSizePixel = 0,
		})
		ui:Text(heading, "NameLabel", "Name", UDim2.fromOffset(pad, 0), UDim2.new(1, -2 * pad, 1, 0), true, 12)
		local listTop = fileBarHeight + fileHeadingHeight
		local list = ui:Node("ScrollingFrame", {
			Name = "LocalPackages",
			Parent = page.Body,
			Position = UDim2.fromOffset(0, listTop),
			Size = UDim2.new(1, 0, 1, -listTop),
			BackgroundColor3 = skin.Inactive,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = theme.Guide,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		})
		local entries = section(list, "Entries", 0)
		page.MessageParent = section(list, "Messages", 4)
		ui:Node("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })
		ui:Node(
			"UIPadding",
			{ Parent = page.MessageParent, PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad) }
		)
		local rows, active = {}, nil
		local previous
		local function selectRow(name)
			if active then
				active:SetKind("quiet")
			end
			active = rows[name]
			if active then
				active:SetKind("primary")
			end
		end
		local function refresh(nextPackages, name)
			if previous and #previous == #nextPackages then
				local changed = false
				for index, file in ipairs(nextPackages) do
					if previous[index] ~= file then
						changed = true
						break
					end
				end
				if not changed then
					return
				end
			end
			previous = nextPackages
			entries:ClearAllChildren()
			ui:Node("UIListLayout", { Parent = entries, SortOrder = Enum.SortOrder.LayoutOrder })
			table.clear(rows)
			active = nil
			if #nextPackages == 0 then
				local empty = ui:Text(
					entries,
					"Empty",
					"No .dexplugin files in this folder.",
					UDim2.fromOffset(0, 0),
					UDim2.new(1, 0, 0, 32),
					true,
					13
				)
				empty.TextTruncate = Enum.TextTruncate.AtEnd
				ui:Node("UIPadding", {
					Parent = empty,
					PaddingLeft = UDim.new(0, pad),
					PaddingRight = UDim.new(0, pad),
				})
				entries.Size = UDim2.new(1, 0, 0, 32)
				return
			end
			entries.Size = UDim2.new(1, 0, 0, 0)
			local icon = Main.GetStudioAsset("native/plugins/manage")
			for index, name in ipairs(nextPackages) do
				local row = ui:Node("Frame", {
					Name = "File" .. index,
					Parent = entries,
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundTransparency = 1,
					LayoutOrder = index + 2,
				})
				local item = ui:Button(row, "Package", name, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), function()
					selectFile(name)
				end, "quiet")
				rows[name] = item
				Lib.StudioCorner(item.Gui, 0)
				item.Gui.TextXAlignment = Enum.TextXAlignment.Left
				item.Gui.TextTruncate = Enum.TextTruncate.AtEnd
				ui:Node("UIPadding", {
					Parent = item.Gui,
					PaddingLeft = UDim.new(0, icon and pad + 20 or pad),
					PaddingRight = UDim.new(0, pad),
				})
				if icon then
					ui:Node("ImageLabel", {
						Parent = row,
						BackgroundTransparency = 1,
						Position = UDim2.new(0, pad, 0.5, -7),
						Size = UDim2.fromOffset(14, 14),
						Image = icon,
						Active = false,
					})
				end
			end
			selectRow(name)
		end
		refresh(packages)
		return selectRow, refresh
	end

	local function showImport(source, drafts)
		local isFile = source == "Files"
		local isLink = source == "Link"
		local title = if isFile then "Add Plugin" elseif isLink then "Add Plugin from Link" else "Paste Plugin"
		local page = render(title, isFile)
		local form = if isFile then page.Footer else section(page.Body, "ImportForm", 6)
		local fieldName = if isLink then "Plugin link" else "Plugin file contents"
		local placeholder = if isFile
			then "File name (.dexplugin)"
			elseif isLink then "https://example.com/plugin.dexplugin"
			else "Paste a .dexplugin file here"
		if not isFile then
			label(form, "FieldLabel", fieldName, 13)
		end
		local input = ui:Field(
			form,
			source .. "Input",
			placeholder,
			isFile and UDim2.new(0, pad, 0.5, -14) or UDim2.fromOffset(0, 0),
			UDim2.new(1, isFile and -190 or 0, 0, if isFile then 28 elseif source == "Paste" then 112 else 30)
		)
		input.LayoutOrder = #form:GetChildren()
		input.BackgroundColor3 = skin.Inactive
		input.TextSize = 14
		input:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 2)
		if source == "Paste" then
			input.MultiLine = true
			input.TextWrapped = true
			input.TextTruncate = Enum.TextTruncate.None
			input.TextYAlignment = Enum.TextYAlignment.Top
			local padding = input:FindFirstChildOfClass("UIPadding")
			padding.PaddingTop = UDim.new(0, 8)
			padding.PaddingBottom = UDim.new(0, 8)
		end
		input.Text = drafts[source] or ""
		local function switch(nextSource)
			drafts[source] = input.Text
			if drafts[nextSource] == nil and nextSource ~= "Files" then
				local value = clipboard()
				if nextSource == "Link" then
					drafts.Link = #value <= 2048 and value:match("^%s*(https://%S+)%s*$") or ""
				else
					drafts.Paste = #value <= maxPackageBytes and value:match("^%s*{") and value or ""
				end
			end
			showImport(nextSource, drafts)
		end
		if isFile then
			local header = ui:Node("Frame", {
				Name = "FileToolbar",
				Parent = page.Body,
				Size = UDim2.new(1, 0, 0, fileBarHeight),
				BackgroundTransparency = 1,
			})
			local folder = Main.GetStudioAsset("class/Folder")
			if folder then
				ui:Node("ImageLabel", {
					Parent = header,
					Position = UDim2.new(0, pad, 0.5, -8),
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = folder,
				})
			end
			local locationX = folder and pad + 24 or pad
			ui:Text(
				header,
				"Location",
				"dex-explorer/plugins",
				UDim2.fromOffset(locationX, 0),
				UDim2.new(1, -locationX - 130, 1, 0),
				false,
				13
			)
			local sourceButton
			sourceButton = ui:Button(
				header,
				"ImportFrom",
				"Import From",
				UDim2.new(1, -108 - pad, 0.5, -14),
				UDim2.fromOffset(108, 28),
				function()
					sourceMenu = sourceMenu or Apps.ContextMenu.new()
					if sourceMenu.Shown then
						sourceMenu:Hide()
						return
					end
					sourceMenu:Clear()
					sourceMenu.Iconless = true
					sourceMenu.PreferredWidth = 152
					sourceMenu:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
					sourceMenu:Add({
						Text = "From Link…",
						OnClick = function()
							switch("Link")
						end,
					})
					sourceMenu:Add({
						Text = "Paste Plugin…",
						OnClick = function()
							switch("Paste")
						end,
					})
					local anchor = sourceButton.Gui.AbsolutePosition
					sourceMenu:Show(anchor.X + sourceButton.Gui.AbsoluteSize.X - 152, anchor.Y + 28)
				end
			)
			sourceButton.Gui.TextXAlignment = Enum.TextXAlignment.Left
			ui:Node("UIPadding", { Parent = sourceButton.Gui, PaddingLeft = UDim.new(0, 8) })
			local chevron = Lib.PanelAsset("dropdown")
			if chevron then
				ui:Node("ImageLabel", {
					Parent = sourceButton.Gui,
					Position = UDim2.new(1, -21, 0.5, -7),
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Image = chevron,
				})
			end
			local selection, refreshFiles = addPackageList(page, runtime.LocalPackages(), function(name)
				input.Text = name
			end)
			if not runtime.SupportsPersistence() then
				label(
					page.MessageParent,
					"Persistence",
					"Installed plugins are kept for this session.",
					12,
					theme.PlaceholderText
				)
			end
			selection(input.Text)
			input:GetPropertyChangedSignal("Text"):Connect(function()
				selection(input.Text)
			end)
			if type(env.listfiles) == "function" then
				local function pollFiles()
					if current ~= page or not Main.Alive or window.Closed then
						return
					end
					if not window.Minimized and window:IsVisible() then
						refreshFiles(runtime.LocalPackages(), input.Text)
					end
					task.delay(1, pollFiles)
				end
				task.delay(1, pollFiles)
			end
			page:Action("Cancel", "Cancel", 65, close)
		else
			page:Action("Back", "Back", 65, function()
				switch("Files")
			end, "quiet")
		end
		local button
		local busy = false
		local function open(file)
			if busy then
				return
			end
			if file then
				input.Text = file
			end
			local value = input.Text
			if not value:find("%S") then
				return
			end
			drafts[source] = value
			busy = true
			button:SetEnabled(false)
			local package, issue
			if isFile then
				package, issue = runtime.ReadImport(value)
			elseif isLink then
				page:Report("Opening link…", theme.PlaceholderText)
				package, issue = runtime.ReadLink(value)
			else
				package, issue = runtime.Parse(value)
			end
			busy = false
			if current ~= page or not window:IsVisible() then
				return
			end
			if package then
				review(package, function()
					showImport(source, drafts)
				end)
			else
				page:Report(issue or "Couldn’t read this plugin file.")
				button:SetEnabled(input.Text:find("%S") ~= nil)
			end
		end
		button = page:Action("Review", "Review", 84, function()
			open()
		end, "primary")
		button:SetEnabled(input.Text:find("%S") ~= nil)
		input:GetPropertyChangedSignal("Text"):Connect(function()
			if not busy then
				button:SetEnabled(input.Text:find("%S") ~= nil)
				page:Report(nil)
			end
		end)
		if source ~= "Paste" then
			input.FocusLost:Connect(function(enter)
				if enter and current == page then
					open()
				end
			end)
		end
		if not isFile and not runtime.SupportsPersistence() then
			label(page.Body, "Persistence", "Installed plugins are kept for this session.", 12, theme.PlaceholderText)
		end
	end

	function Manager.OpenImport()
		showImport("Files", {})
	end

	return Manager
end

return { InitDeps = InitDeps, Main = CreateModule }
