--!strict

local Apps, Lib, Main, Settings, createSimple, userInput

local function InitDeps(deps)
	Apps, Lib, Main, Settings, createSimple = deps.Apps, deps.Lib, deps.Main, deps.Settings, deps.createSimple
	userInput = deps.service.UserInputService
end

local function CreateModule()
	local toolbar = {}
	local menu

	function toolbar.HideMenu()
		if menu then
			menu:Hide()
		end
	end

	function toolbar.MenuContainsPointer()
		return menu ~= nil and menu.Shown and Lib.CheckMouseInGui(menu.GuiElems.Main)
	end

	function toolbar.IsMenuOpen()
		return menu ~= nil and menu.Shown
	end

	function toolbar.Create(parent)
		local runtime = Apps.PluginRuntime
		local theme = Settings.Theme
		local section = createSimple("Frame", {
			Name = "Plugins",
			Parent = parent,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -16, 0, 34),
		})
		createSimple("Frame", {
			Name = "Divider",
			Parent = section,
			BackgroundColor3 = theme.Outline2,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
		})
		local title = createSimple("TextLabel", {
			Name = "Title",
			Parent = section,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(3, 6),
			Size = UDim2.new(1, -34, 0, 24),
			Text = "Plugins",
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Lib.StudioText(title)
		title.TextSize = 13
		local add = Lib.StudioButton(section, "AddPlugin", "+", UDim2.new(1, -24, 0, 6), UDim2.fromOffset(24, 24))
		if Lib.SetNativeIcon(add, "native/plugins/add", 16) then
			add.Text = ""
		end
		add.MouseButton1Click:Connect(function()
			Main.SetMainGuiOpen(false)
			Apps.PluginManager.OpenImport()
		end)
		local unbindAdd = Lib.StudioTooltip(add, "Add Plugin")

		local grid = createSimple("Frame", {
			Name = "Buttons",
			Parent = section,
			Position = UDim2.fromOffset(0, 34),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
		})
		local layout = createSimple("UIGridLayout", {
			Parent = grid,
			CellSize = UDim2.fromOffset(56, 56),
			CellPadding = UDim2.fromOffset(6, 4),
			FillDirectionMaxCells = 5,
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local function fit()
			local height = layout.AbsoluteContentSize.Y
			grid.Size = UDim2.new(1, 0, 0, height)
			section.Size = UDim2.new(1, -16, 0, 34 + height)
		end
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)

		local function showDetails(id, action, message)
			Main.SetMainGuiOpen(false)
			Apps.PluginManager[action](id, message)
		end
		local function showError(id, problem)
			if Main.Alive and runtime.Get(id) then
				showDetails(id, "ShowError", problem)
			end
		end
		local function openMenu(id, x, y)
			local plugin = runtime.Get(id)
			if not plugin then
				return
			end
			menu = menu or Apps.ContextMenu.new()
			menu.Iconless = true
			menu:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
			menu:Clear()
			menu:Add({
				Text = "Plugin Details",
				OnClick = function()
					showDetails(id, "Open")
				end,
			})
			menu:Add({
				Text = "Plugin Output",
				OnClick = function()
					Main.SetMainGuiOpen(false)
					Apps.PluginOutput.Open(id)
				end,
			})
			menu:Add({
				Text = plugin.Enabled and "Disable" or "Enable",
				OnClick = function()
					if not plugin.Enabled then
						showDetails(id, "RequestEnable")
						return
					end
					local ok, problem = runtime.SetEnabled(id, false)
					if not ok then
						showError(id, problem)
					end
				end,
			})
			if plugin.Enabled then
				menu:Add({
					Text = "Reload",
					OnClick = function()
						local ok, problem = runtime.Reload(id)
						if not ok then
							showError(id, problem)
						end
					end,
				})
			end
			if plugin.Path or plugin.Link then
				menu:Add({
					Text = plugin.Path and "Review Local Changes…" or "Check for Update…",
					OnClick = function()
						showDetails(id, "ReviewUpdate")
					end,
				})
			end
			menu:AddDivider()
			menu:Add({
				Text = "Uninstall…",
				OnClick = function()
					showDetails(id, "RequestRemove")
				end,
			})
			menu:Show(x, y)
		end

		local function makeButton(key, data)
			local button = createSimple("TextButton", {
				Name = key,
				Parent = grid,
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				BackgroundColor3 = theme.ExplorerHover,
				BackgroundTransparency = 1,
			})
			Lib.StudioCorner(button, 4)
			local icon = createSimple("ImageLabel", {
				Name = "Icon",
				Parent = button,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, -12, 0, 5),
				Size = UDim2.fromOffset(24, 24),
				ScaleType = Enum.ScaleType.Fit,
			})
			local caption = createSimple("TextLabel", {
				Parent = button,
				Name = "Caption",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(3, 31),
				Size = UDim2.new(1, -6, 0, 18),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Lib.StudioText(caption)
			caption.TextSize = 11
			local initial = createSimple("TextLabel", {
				Parent = icon,
				Name = "Initial",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
			})
			Lib.StudioText(initial)
			initial.TextSize = 19
			local entry = { Gui = button, Icon = icon, Caption = caption, Data = data, Hovered = false }
			local function paint()
				local current = entry.Data
				local image = current.Icon
				icon.Image = image and image ~= "" and image or Main.GetStudioAsset("native/plugins/manage") or ""
				icon.ImageTransparency = current.Enabled and 0 or 0.45
				initial.Visible = icon.Image == ""
				if initial.Visible then
					initial.Text = utf8.char(utf8.codepoint(current.Name, 1))
				end
				caption.Text = current.Name
				caption.TextColor3 = if current.Active
					then theme.SelectedText
					elseif current.Enabled then theme.Text
					else theme.PlaceholderText
				button.BackgroundColor3 = current.Active and theme.Focus or theme.ExplorerHover
				button.BackgroundTransparency = if current.Active then 0.65 elseif entry.Hovered then 0 else 1
			end
			entry.Paint = paint
			entry.Unbind = Lib.StudioTooltip(button, function()
				local current = entry.Data
				local tip = current.Name
				if current.Tooltip and current.Tooltip ~= "" and current.Tooltip ~= tip then
					tip ..= "\n" .. current.Tooltip
				end
				if not current.Enabled then
					return tip .. "\nDisabled"
				elseif current.Failed then
					return tip .. "\nPlugin error"
				end
				return tip
			end)
			button.MouseEnter:Connect(function()
				entry.Hovered = true
				paint()
			end)
			button.MouseLeave:Connect(function()
				entry.Hovered = false
				paint()
			end)
			button.MouseButton2Click:Connect(function()
				openMenu(entry.Data.PluginID)
			end)
			if userInput.TouchEnabled then
				local actions =
					Lib.StudioButton(button, "PluginActions", "…", UDim2.new(1, -20, 0, 0), UDim2.fromOffset(20, 20))
				Lib.SetNativeIcon(actions, "native/plugins/more", 14)
				actions.Activated:Connect(function()
					local position = button.AbsolutePosition
					openMenu(entry.Data.PluginID, position.X, position.Y + button.AbsoluteSize.Y)
				end)
			end
			button.MouseButton1Click:Connect(function()
				local current = entry.Data
				if not current.Enabled then
					showDetails(current.PluginID, "RequestEnable")
					return
				end
				Main.SetMainGuiOpen(false)
				local ok, problem = runtime.Activate(current.PluginID, current.ID)
				if not ok then
					showError(current.PluginID, problem)
				end
			end)
			return entry
		end

		local entries = {}
		local function render()
			local shown = {}
			for index, data in ipairs(runtime.GetButtons()) do
				local key = data.PluginID .. "/" .. data.ID
				local entry = entries[key] or makeButton(key, data)
				entry.Data = data
				entry.Gui.LayoutOrder = index
				entry.Paint()
				entries[key], shown[key] = entry, true
			end
			for key, entry in pairs(entries) do
				if not shown[key] then
					entry.Unbind()
					entry.Gui:Destroy()
					entries[key] = nil
				end
			end
			fit()
		end
		local queued = false
		local connection = runtime.Changed:Connect(function()
			if queued then
				return
			end
			queued = true
			task.defer(function()
				queued = false
				if Main.Alive then
					render()
				end
			end)
		end)
		Main.AddCleanup(function()
			connection:Disconnect()
			unbindAdd()
			for _, entry in pairs(entries) do
				entry.Unbind()
			end
			if menu then
				menu:Destroy()
				menu = nil
			end
		end)
		render()
		return section
	end

	return toolbar
end

return { InitDeps = InitDeps, Main = CreateModule }
