--!strict

local Main, Lib, Apps, Settings, env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, env, service = d.Main, d.Lib, d.Apps, d.Settings, d.env, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Save = { Engine = "Universal", Busy = false }
	local backend
	local raw, rows = {}, {}
	local scope = "Place"
	local status, saveButton, filename, scopeButton, provider
	local providerMenu, scopeMenu
	local preferences = "dex-explorer/save-instance.json"
	local function node(class, props)
		local item = Instance.new(class)
		for key, value in pairs(props) do
			item[key] = value
		end
		return item
	end
	local function persist()
		if not env.writefile then
			return
		end
		local ok, json = pcall(
			service.HttpService.JSONEncode,
			service.HttpService,
			{ Version = 1, Engine = Save.Engine, Options = raw }
		)
		if ok then
			pcall(env.writefile, preferences, json)
		end
	end
	local function message(text, errorState)
		if status then
			status.Text = text
			status.TextColor3 = errorState and Color3.fromRGB(240, 130, 130) or Settings.Theme.PlaceholderText
		end
	end
	function Save.Export(object, path, options)
		assert(not Save.Busy, "A save is already running")
		Save.Busy = true
		if saveButton then
			saveButton.Text = "Saving..."
			saveButton.Active = false
		end
		message("Saving with " .. Save.Engine .. "...")
		local started = os.clock()
		local ok, value = pcall(function()
			backend = backend or Main.LoadModule("SaveBackend")
			return backend.Run(Save.Engine, object, path, options)
		end)
		Save.Busy = false
		if Main.Alive ~= false then
			if saveButton then
				saveButton.Text = "Save"
				saveButton.Active = true
			end
			message(
				ok and string.format("Finished in %.1f s — check output for errors", os.clock() - started)
					or tostring(value),
				not ok
			)
		end
		if not ok then
			error(value, 0)
		end
		return value
	end
	function Save.Init()
		local definitions = Main.LoadModule("SaveOptions")
		if env.readfile then
			local ok, json = pcall(env.readfile, preferences)
			if ok then
				local good, data = pcall(service.HttpService.JSONDecode, service.HttpService, json)
				if good and type(data) == "table" and data.Version == 1 then
					if data.Engine == "Executor" then
						Save.Engine = "Executor"
					end
					if type(data.Options) == "table" then
						for _, field in ipairs(definitions) do
							local value = data.Options[field.Key]
							if type(value) == "boolean" or type(value) == "string" and #value <= 65536 then
								raw[field.Key] = value
							end
						end
					end
				end
			end
		end
		local window = Lib.Window.new()
		Save.Window = window
		window:SetTitle("Save Instance")
		window.MinX = 460
		window.MinY = 320
		window:Resize(560, 510)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		local theme = Settings.Theme
		local content = window.GuiElems.Content
		content.BackgroundColor3 = theme.Main1 or theme.Menu
		local font = Lib.StudioFont or Enum.Font.BuilderSans
		local accent = theme.Focus
		local tweens = {}
		local function animate(object, properties, duration)
			if tweens[object] then
				tweens[object]:Cancel()
				tweens[object] = nil
			end
			local ok, tween = pcall(function()
				return service.TweenService:Create(
					object,
					TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					properties
				)
			end)
			if ok and tween then
				tweens[object] = tween
				tween:Play()
			else
				for key, value in pairs(properties) do
					object[key] = value
				end
			end
		end
		Main.AddCleanup(function()
			for _, tween in pairs(tweens) do
				tween:Cancel()
			end
			table.clear(tweens)
		end)

		local function label(parent, text, x, y, width, height)
			return node("TextLabel", {
				Parent = parent,
				Text = text,
				BackgroundTransparency = 1,
				Font = font,
				TextSize = 13,
				TextColor3 = theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.new(width, width == 0 and 0 or -24, 0, height or 22),
			})
		end
		local function button(parent, text, pos, size, callback)
			local b = node("TextButton", {
				Parent = parent,
				Text = text,
				Position = pos,
				Size = size,
				Font = font,
				TextSize = 13,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.TextBox,
				BorderSizePixel = 0,
				AutoButtonColor = false,
			})
			node("UICorner", { Parent = b, CornerRadius = UDim.new(0, 3) })
			local function paint(hovered)
				b.BackgroundTransparency = 0
				local base = b.Name == "SaveAction" and accent
					or b:GetAttribute("Expanded") and theme.TextBox:Lerp(accent, 0.28)
					or theme.TextBox
				b.BackgroundColor3 = hovered and base:Lerp(accent, 0.16) or base
			end
			b.MouseEnter:Connect(function()
				paint(true)
			end)
			b.MouseLeave:Connect(function()
				paint(false)
			end)
			b.Activated:Connect(function()
				if not Save.Busy then
					callback()
				end
			end)
			return b
		end
		local function dropdownArrow(control)
			control.TextXAlignment = Enum.TextXAlignment.Left
			node("UIPadding", { Parent = control, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 28) })
			node("ImageLabel", {
				Name = "DropdownArrow",
				Parent = control,
				Image = Main.GetStudioAsset("native/editor/submenu") or "",
				Rotation = 90,
				BackgroundTransparency = 1,
				Position = UDim2.new(1, 8, 0.5, -8),
				Size = UDim2.fromOffset(16, 16),
			})
		end
		local function showDropdown(menu, control)
			if menu.Shown then
				menu:Hide()
				return
			end
			menu.Width = math.max(160, control.AbsoluteSize.X)
			if menu.ApplyTheme then
				menu:ApplyTheme({ RowHeight = 26, TextSize = 13, Font = font })
			end
			menu:Show(control.AbsolutePosition.X, control.AbsolutePosition.Y + control.AbsoluteSize.Y + 2)
		end
		local function textbox(parent, placeholder, pos, size)
			local b = node("TextBox", {
				Parent = parent,
				Text = "",
				PlaceholderText = placeholder,
				Position = pos,
				Size = size,
				Font = font,
				TextSize = 13,
				TextColor3 = theme.Text,
				PlaceholderColor3 = theme.PlaceholderText,
				BackgroundColor3 = theme.TextBox,
				BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				MultiLine = false,
			})
			node("UICorner", { Parent = b, CornerRadius = UDim.new(0, 3) })
			local focus = node("UIStroke", {
				Parent = b,
				Color = accent,
				Thickness = 1,
				Transparency = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			})
			b.Focused:Connect(function()
				animate(focus, { Transparency = 0 })
			end)
			b.FocusLost:Connect(function()
				animate(focus, { Transparency = 1 })
			end)
			node("UIPadding", { Parent = b, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
			return b
		end
		label(content, "Provider", 12, 10, 1, 20)
		provider = button(
			content,
			Save.Engine == "Universal" and "Universal (USSI)" or "Executor",
			UDim2.new(1, -196, 0, 10),
			UDim2.fromOffset(184, 26),
			function()
				local menu = providerMenu or Apps.ContextMenu.new()
				providerMenu = menu
				menu:Clear()
				for _, engine in ipairs({ "Universal", "Executor" }) do
					menu:Add({
						Name = engine == "Universal" and "Universal (USSI)" or "Executor",
						OnClick = function()
							Save.Engine = engine
							provider.Text = engine == "Universal" and "Universal (USSI)" or "Executor"
							persist()
							message(engine == "Executor" and "Using executor saveinstance." or "Ready")
						end,
					})
				end
				showDropdown(menu, provider)
			end
		)
		dropdownArrow(provider)
		label(content, "Objects", 12, 46, 1, 20)
		scopeButton = button(content, "Place", UDim2.new(1, -196, 0, 44), UDim2.fromOffset(184, 26), function()
			local menu = scopeMenu or Apps.ContextMenu.new()
			scopeMenu = menu
			menu:Clear()
			for _, choice in ipairs({ "Place", "Selection" }) do
				menu:Add({
					Name = choice,
					OnClick = function()
						scope = choice
						scopeButton.Text = choice
					end,
				})
			end
			showDropdown(menu, scopeButton)
		end)
		dropdownArrow(scopeButton)
		filename = textbox(content, "Automatic file name", UDim2.fromOffset(12, 80), UDim2.new(1, -24, 0, 28))
		filename.Text = type(raw.FilePath) == "string" and raw.FilePath or "Place_" .. game.PlaceId .. "_{TIMESTAMP}"
		Lib.StudioTooltip(
			filename,
			"File name or workspace-relative folder/path. Leave blank for USSI's automatic name. {TIMESTAMP} adds the current date and time."
		)
		local search = textbox(content, "Search options", UDim2.fromOffset(12, 118), UDim2.new(1, -100, 0, 28))
		local refresh
		button(content, "Reset", UDim2.new(1, -80, 0, 118), UDim2.fromOffset(68, 28), function()
			table.clear(raw)
			filename.Text = "Place_" .. game.PlaceId .. "_{TIMESTAMP}"
			for _, row in ipairs(rows) do
				if row.Input then
					row.Input.Text = ""
				else
					row.Paint()
				end
			end
			persist()
			message("Defaults restored.")
		end)
		local list = node("ScrollingFrame", {
			Name = "Options",
			Parent = content,
			Position = UDim2.fromOffset(0, 156),
			Size = UDim2.new(1, 0, 1, -210),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = theme.PlaceholderText,
			TopImage = "",
			BottomImage = "",
			ClipsDescendants = true,
		})
		node("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
		node("UIPadding", {
			Parent = list,
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 8),
		})
		local order = 0
		local groups = {}
		for _, group in ipairs({ "Output", "Scripts", "Objects", "Players", "Advanced" }) do
			order += 1
			local header = label(list, group, 0, 0, 1, 28)
			header.LayoutOrder = order
			header.TextColor3 = accent
			header.Font = Enum.Font.BuilderSansMedium
			groups[group] = { Header = header, Rows = {} }
			for _, field in ipairs(definitions) do
				if field.Group ~= group or field.Key == "FilePath" then
					continue
				end
				order += 1
				local frame = node("Frame", {
					Name = field.Key,
					Parent = list,
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundTransparency = 1,
				})
				local title = label(frame, field.Label, 0, 6, 0.5, 22)
				local row = { Field = field, Frame = frame }
				rows[#rows + 1] = row
				groups[group].Rows[#groups[group].Rows + 1] = row
				if field.Key == "mode" or field.Key == "CompressionMode" then
					local choices = field.Key == "mode"
							and {
								{ "Default" },
								{ "Optimized", "optimized" },
								{ "Full", "full" },
								{ "Scripts", "scripts" },
								{ "Custom", "custom" },
							}
						or { { "Default" }, { "Zstd", '"zstd"' }, { "LZ4", '"lz4"' }, { "None", "false" } }
					local b
					local menu
					row.Paint = function()
						b.Text = "Default"
						for _, choice in ipairs(choices) do
							if choice[2] == raw[field.Key] then
								b.Text = choice[1]
							end
						end
					end
					b = button(frame, "", UDim2.new(0.5, 0, 0, 3), UDim2.new(0.5, -32, 0, 28), function()
						menu = menu or Apps.ContextMenu.new()
						menu:Clear()
						for _, choice in ipairs(choices) do
							menu:Add({
								Name = choice[1],
								OnClick = function()
									raw[field.Key] = choice[2]
									row.Paint()
								end,
							})
						end
						showDropdown(menu, b)
					end)
					dropdownArrow(b)
					row.Paint()
					Main.AddCleanup(function()
						if menu then
							menu:Destroy()
						end
					end)
				elseif field.Kind == "boolean" then
					local b, icon
					row.Paint = function()
						local value = raw[field.Key]
						if value == nil then
							value = field.Default == "true"
						end
						icon.Image = Main.GetStudioAsset(value and "prop/checkbox_on" or "prop/checkbox_off") or ""
						b:SetAttribute("Checked", value)
					end
					b = button(frame, "", UDim2.new(1, -60, 0, 3), UDim2.fromOffset(28, 28), function()
						local value = raw[field.Key]
						if value == nil then
							value = field.Default == "true"
						end
						raw[field.Key] = not value
						row.Paint()
					end)
					b.BackgroundTransparency = 0
					icon = node("ImageLabel", {
						Parent = b,
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(6, 6),
						Size = UDim2.fromOffset(16, 16),
						ScaleType = Enum.ScaleType.Fit,
					})
					row.Paint()
				else
					local input = textbox(
						frame,
						field.Kind == "expression" and "Expression" or field.Default,
						UDim2.new(0.5, 0, 0, 3),
						UDim2.new(0.5, -32, 0, 28)
					)
					input.Text = type(raw[field.Key]) == "string" and raw[field.Key] or ""
					row.Input = input
					input:GetPropertyChangedSignal("Text"):Connect(function()
						raw[field.Key] = input.Text ~= "" and input.Text or nil
					end)
				end
				frame.ClipsDescendants = true
				local expanded = false
				local details = node("Frame", {
					Name = "Details",
					Parent = frame,
					Visible = false,
					BackgroundColor3 = accent,
					BackgroundTransparency = 0.94,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(0, 34),
					Size = UDim2.new(1, 0, 0, 72),
				})
				local defaultLabel = label(details, "Default: " .. field.Default, 8, 0, 1, 22)
				defaultLabel.TextColor3 = theme.Text
				defaultLabel.Size = UDim2.new(1, -56, 0, 22)
				local description = label(
					details,
					(field.Help or field.Label):match("^[^%.]+%.") or field.Help or field.Label,
					8,
					24,
					1,
					46
				)
				description.TextSize = 12
				description.TextWrapped = true
				description.TextYAlignment = Enum.TextYAlignment.Top
				description.TextColor3 = theme.PlaceholderText
				local reset = button(details, "", UDim2.new(1, -24, 0, 0), UDim2.fromOffset(24, 24), function()
					raw[field.Key] = nil
					if row.Input then
						row.Input.Text = ""
					else
						row.Paint()
					end
					persist()
				end)
				reset.Name = "ResetOption"
				node("ImageLabel", {
					Parent = reset,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.fromOffset(16, 16),
					Image = Main.GetStudioAsset("native/references/refresh") or "",
				})
				local more = button(frame, "", UDim2.new(1, -26, 0, 3), UDim2.fromOffset(26, 28), function()
					expanded = not expanded
					details.Visible = true
					local trigger = frame:FindFirstChild("OptionDetails")
					trigger:SetAttribute("Expanded", expanded)
					trigger.BackgroundColor3 = expanded and theme.TextBox:Lerp(accent, 0.28) or theme.TextBox
					trigger.BackgroundTransparency = 0
					animate(frame, { Size = UDim2.new(1, 0, 0, expanded and 112 or 30) }, 0.16)
				end)
				more.Name = "OptionDetails"
				more.BackgroundTransparency = 0
				node("ImageLabel", {
					Parent = more,
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(5, 6),
					Size = UDim2.fromOffset(16, 16),
					Image = Main.GetStudioAsset("explorer/options") or "",
				})
			end
		end
		refresh = function()
			local query = search.Text:lower()
			for _, group in pairs(groups) do
				local count = 0
				for _, row in ipairs(group.Rows) do
					local match = (row.Field.Key .. " " .. row.Field.Label .. " " .. row.Field.Group)
						:lower()
						:find(query, 1, true) ~= nil
					row.Frame.Visible = match
					if match then
						count += 1
					end
				end
				group.Header.Visible = count > 0
			end
			list.CanvasPosition = Vector2.new(0, 0)
		end
		search:GetPropertyChangedSignal("Text"):Connect(refresh)
		status = label(content, "Ready", 12, 0, 1, 22)
		status.Position = UDim2.new(0, 12, 1, -42)
		status.Size = UDim2.new(1, -130, 0, 30)
		status.TextSize = 12
		Lib.StudioTooltip(status, function()
			return status.Text
		end)
		saveButton = button(content, "Save", UDim2.new(1, -104, 1, -44), UDim2.fromOffset(92, 32), function()
			local selected = {}
			for _, entry in ipairs(Apps.Explorer.Selection.List) do
				selected[#selected + 1] = entry.Obj
			end
			local ok, options = pcall(function()
				return Main.LoadModule("SaveConfiguration").Build(raw, selected)
			end)
			if not ok then
				message(tostring(options), true)
				return
			end
			if scope == "Selection" then
				if #selected == 0 then
					message("Select at least one object in Explorer.", true)
					return
				end
				if options.Object == nil and options.ExtraInstances == nil then
					options.ExtraInstances = selected
				end
				if options.mode == nil then
					options.mode = "custom"
				end
				if options.IsModel == nil then
					options.IsModel = true
				end
			end
			if Save.Engine == "Executor" and scope == "Selection" and #selected ~= 1 then
				message("Use Universal for a multi-object selection.", true)
				return
			end
			local path = filename.Text:gsub("{TIMESTAMP}", os.date("%Y-%m-%d_%H-%M-%S"))
			if path:find('[<>:"|?*]') or path:find("..", 1, true) then
				message("Use a file name without reserved characters or '..'.", true)
				return
			end
			raw.FilePath = filename.Text
			persist()
			task.spawn(function()
				local success, problem = pcall(
					Save.Export,
					Save.Engine == "Executor" and scope == "Selection" and selected[1] or nil,
					path ~= "" and path or nil,
					options
				)
				if not success and Main.Alive ~= false then
					message(tostring(problem), true)
				end
			end)
		end)
		saveButton.Name = "SaveAction"
		saveButton.BackgroundColor3 = theme.Focus
		Main.AddCleanup(function()
			persist()
			if providerMenu then
				providerMenu:Destroy()
			end
			if scopeMenu then
				scopeMenu:Destroy()
			end
		end)
	end
	return Save
end
return { InitDeps = InitDeps, Main = CreateModule }
