--!strict

local Apps, Main, Lib, Settings, service

local function InitDeps(deps)
	Apps, Main, Lib, Settings, service = deps.Apps, deps.Main, deps.Lib, deps.Settings, deps.service
end

local function CreateModule()
	local Dialog = {}
	local scriptTypes = { "ModuleScript", "LocalScript", "Script" }
	local suggestedRoots = {
		"ReplicatedStorage",
		"Workspace",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"ServerScriptService",
		"ServerStorage",
	}

	local function location(object)
		return typeof(object) == "Instance"
			and object ~= game
			and object:IsDescendantOf(game)
			and not Apps.Explorer.IsReadOnlyInferenceObject(object)
	end

	function Dialog.Create(content, window, createScript)
		local theme = Settings.Theme
		local hover = theme.ExplorerHover or theme.ButtonHover
		local userInput = service.UserInputService
		local function gui(class, parent, name, props)
			local object = Instance.new(class)
			object.Name = name
			object.BorderSizePixel = 0
			object.BackgroundTransparency = 1
			object.ZIndex = 42
			for key, value in pairs(props) do
				object[key] = value
			end
			object.Parent = parent
			return object
		end
		local function text(class, parent, name, caption, position, size)
			return gui(class, parent, name, {
				Position = position,
				Size = size,
				Font = Enum.Font.BuilderSans,
				TextSize = 14,
				TextColor3 = theme.Text,
				Text = caption,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
		local function line(parent, name, y)
			return gui("Frame", parent, name, {
				Position = y,
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Outline2,
			})
		end
		local function icon(parent, name, asset, position, rotation)
			return gui("ImageLabel", parent, name, {
				Image = asset or "",
				Position = position,
				Size = UDim2.fromOffset(16, 16),
				Rotation = rotation or 0,
				ZIndex = parent.ZIndex + 1,
			})
		end
		local function button(parent, name, caption, position, size, onClick)
			local control = text("TextButton", parent, name, caption, position, size)
			control.TextXAlignment = Enum.TextXAlignment.Center
			control.AutoButtonColor = false
			control.Activated:Connect(onClick)
			return control
		end
		local function fill(control, idle, hovered, enabled)
			local inside = false
			local function refresh()
				local color = if enabled and not enabled() then theme.Button else inside and hovered or idle
				control.BackgroundTransparency = color and 0 or 1
				if color then
					control.BackgroundColor3 = color
				end
			end
			control.MouseEnter:Connect(function()
				inside = true
				refresh()
			end)
			control.MouseLeave:Connect(function()
				inside = false
				refresh()
			end)
			refresh()
			return refresh
		end
		local function outline(object)
			local border = Instance.new("UIStroke")
			border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			border.Color = theme.Outline2
			border.Parent = object
			return border
		end
		local function input(parent, name, hint, position, size, indent)
			local box = text("TextBox", parent, name, "", position, size)
			box.ClearTextOnFocus = false
			box.MultiLine = false
			box.PlaceholderText = hint
			box.PlaceholderColor3 = theme.PlaceholderText
			box.BackgroundTransparency = 0
			box.BackgroundColor3 = theme.Menu or theme.Main2
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, indent)
			padding.PaddingRight = UDim.new(0, 6)
			padding.Parent = box
			local border = outline(box)
			box.Focused:Connect(function()
				border.Color = theme.Focus
			end)
			box.FocusLost:Connect(function()
				border.Color = theme.Outline2
			end)
			return box
		end
		local function objectIcon(object)
			return object
					and (Main.GetStudioAsset("class/" .. object.ClassName) or Main.GetStudioAsset("class/Placeholder"))
				or ""
		end
		local overlay = gui("TextButton", content, "NewScriptDialog", {
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			ZIndex = 39,
		})
		local shadow = gui("Frame", overlay, "Shadow", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 26),
			BackgroundTransparency = 0.72,
			BackgroundColor3 = Color3.new(),
			ZIndex = 40,
		})
		local panel = gui("Frame", overlay, "Panel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 24),
			BackgroundTransparency = 0,
			BackgroundColor3 = theme.Main2,
			ClipsDescendants = true,
			Active = true,
			ZIndex = 41,
		})
		outline(panel)
		local title = text("TextLabel", panel, "Title", "New Script", UDim2.fromOffset(10, 0), UDim2.new(1, -48, 0, 27))
		line(panel, "HeaderDivider", UDim2.fromOffset(0, 27))
		local body = gui("Frame", panel, "Fields", {
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 1, -68),
		})
		line(body, "TypeDivider", UDim2.fromOffset(0, 65))
		local nameLabel =
			text("TextLabel", body, "NameLabel", "Name", UDim2.fromOffset(0, 70), UDim2.fromOffset(54, 23))
		local parentLabel =
			text("TextLabel", body, "ParentLabel", "Parent", UDim2.fromOffset(0, 99), UDim2.fromOffset(54, 23))
		nameLabel.TextColor3, parentLabel.TextColor3 = theme.PlaceholderText, theme.PlaceholderText
		local name = input(body, "ScriptName", "Name", UDim2.fromOffset(54, 70), UDim2.new(1, -54, 0, 23), 7)
		local explorer = Apps.Explorer
		local layout, validate
		local self = {
			Gui = overlay,
			Name = name,
			ClassName = "ModuleScript",
			RecentParents = {},
			Mode = "Create",
			TypeButtons = {},
		}
		local function releaseNameFocus()
			if userInput:GetFocusedTextBox() == name then
				name:ReleaseFocus()
			end
		end
		local previousFocus
		function self:Hide(restoreFocus)
			if not overlay.Visible then
				return
			end
			self:CancelPicker(false)
			overlay.Visible = false
			releaseNameFocus()
			if restoreFocus and previousFocus and previousFocus.Parent and not userInput:GetFocusedTextBox() then
				previousFocus:CaptureFocus()
			end
			previousFocus = nil
		end
		overlay.Activated:Connect(function(inputObject)
			local mouse = inputObject and inputObject.UserInputType == Enum.UserInputType.MouseButton1
			local x, y =
				if mouse then Main.Mouse.X else inputObject and inputObject.Position.X,
				if mouse then Main.Mouse.Y else inputObject and inputObject.Position.Y
			local p, s = panel.AbsolutePosition, panel.AbsoluteSize
			if x and y and (x < p.X or y < p.Y or x >= p.X + s.X or y >= p.Y + s.Y) then
				self:Hide(true)
			end
		end)
		local function uniqueName(className)
			local candidate, suffix = className, 1
			while self.Parent and self.Parent:FindFirstChild(candidate) do
				candidate = className .. suffix
				suffix += 1
			end
			return candidate
		end
		local close = button(panel, "Dismiss", "", UDim2.new(1, -26, 0, 2), UDim2.fromOffset(24, 23), function()
			self:Hide(true)
		end)
		local closeAsset = Lib.PanelAsset("close")
		icon(close, "Icon", closeAsset, UDim2.fromOffset(4, 3))
		close.Text = closeAsset and "" or "×"
		Lib.PanelButtonHover(close)
		for index, className in ipairs(scriptTypes) do
			local row = button(
				body,
				className,
				"",
				UDim2.fromOffset(0, (index - 1) * 21),
				UDim2.new(1, 0, 0, 21),
				function()
					self:SelectType(className)
				end
			)
			icon(row, "ClassIcon", Main.GetStudioAsset("class/" .. className), UDim2.fromOffset(6, 2))
			local caption =
				text("TextLabel", row, "Caption", className, UDim2.fromOffset(28, 0), UDim2.new(1, -34, 1, 0))
			caption.ZIndex = 43
			local inside = false
			local function update()
				local selected = self.ClassName == className
				row.BackgroundTransparency = (selected or inside) and 0 or 1
				row.BackgroundColor3 = selected and theme.ListSelection or hover
				caption.TextColor3 = selected and (theme.SelectedText or theme.Text) or theme.Text
			end
			row.MouseEnter:Connect(function()
				inside = true
				update()
			end)
			row.MouseLeave:Connect(function()
				inside = false
				update()
			end)
			self.TypeButtons[className] = { Button = row, Caption = caption, Update = update }
		end
		local parentButton = button(
			body,
			"ScriptParent",
			"",
			UDim2.fromOffset(54, 99),
			UDim2.new(1, -54, 0, 23),
			function()
				if self.Mode == "Parent" then
					self:CancelPicker()
				else
					self:OpenPicker()
				end
			end
		)
		local parentBorder = outline(parentButton)
		fill(parentButton, theme.Menu or theme.Main2, hover)
		local parentIcon = icon(parentButton, "ParentIcon", "", UDim2.fromOffset(5, 3))
		local parentPath = text("TextLabel", parentButton, "Path", "", UDim2.fromOffset(26, 0), UDim2.new(1, -49, 1, 0))
		parentPath.ZIndex = 43
		Lib.StudioTooltip(parentButton, function()
			return self.Mode == "Parent" and "Cancel parent selection" or "Select in Explorer"
		end)
		local iconTheme = theme.IconTheme == "Light" and "light" or "dark"
		local selectAsset = Main.GetStudioAsset("native/dragger/select-" .. iconTheme)
		local pickerIcon = icon(parentButton, "Pick", selectAsset, UDim2.new(1, -20, 0, 3))
		pickerIcon.ScaleType = Enum.ScaleType.Fit
		pickerIcon.ResampleMode = Enum.ResamplerMode.Default
		self.ParentButton, self.ParentPath = parentButton, parentPath

		line(panel, "FooterDivider", UDim2.new(0, 0, 1, -33))
		local status = text("TextLabel", panel, "Status", "", UDim2.new(0, 10, 1, -28), UDim2.new(1, -162, 0, 23))
		status.TextSize = 12
		status.TextColor3 = Color3.fromRGB(241, 132, 120)
		status.Visible = false
		local cancel = button(
			panel,
			"Cancel",
			"Cancel",
			UDim2.new(1, -148, 1, -27),
			UDim2.fromOffset(64, 21),
			function()
				self:Hide(true)
			end
		)
		fill(cancel, theme.Button, theme.ButtonHover)
		local confirm = button(
			panel,
			"Create",
			"Create",
			UDim2.new(1, -77, 1, -27),
			UDim2.fromOffset(67, 21),
			function()
				self:Create()
			end
		)
		local primary = fill(confirm, theme.Focus, theme.Brand or theme.Focus, function()
			return confirm.Active
		end)
		self.CreateButton = confirm
		local function enabled(value)
			confirm.Active = value
			confirm.Interactable = value
			confirm.TextColor3 = value and Color3.new(1, 1, 1) or theme.PlaceholderText
			primary()
		end
		layout = function()
			local height = 198
			panel.Size = UDim2.fromOffset(
				math.max(1, math.min(350, content.AbsoluteSize.X - 20)),
				math.max(1, math.min(height, content.AbsoluteSize.Y - 30))
			)
			shadow.Size = panel.Size
		end
		local function setError(message)
			status.Text = message or ""
			status.Visible = message ~= nil
		end
		validate = function()
			local value = name.Text:match("^%s*(.-)%s*$")
			local issue
			if self.Mode == "Parent" then
				enabled(false)
				return false
			elseif not location(self.Parent) then
				issue = "Select a parent"
			elseif value == "" or value:find("%c") then
				issue = "Enter a valid name"
			elseif self.Parent:FindFirstChild(value) then
				issue = "Name already in use"
			end
			enabled(issue == nil)
			setError(issue)
			return issue == nil, value
		end
		function self:SelectType(className)
			if not self.TypeButtons[className] then
				return
			end
			local usingDefault = name.Text == self.DefaultName
			self.ClassName = className
			if usingDefault then
				self.DefaultName = uniqueName(className)
				name.Text = self.DefaultName
			end
			for _, record in pairs(self.TypeButtons) do
				record.Update()
			end
			if self.Mode == "Create" then
				validate()
			end
		end
		local function showParent()
			parentPath.Text = self.Parent and self.Parent:GetFullName() or "Select Parent…"
			parentIcon.Image = objectIcon(self.Parent) or ""
		end
		function self:CancelPicker(focus)
			if self.Mode ~= "Parent" then
				return
			end
			self.Mode = "Create"
			explorer.SetObjectPicker(nil)
			parentBorder.Color = theme.Outline2
			pickerIcon.Image = selectAsset or ""
			showParent()
			validate()
			if focus ~= false then
				window:Focus()
				name:CaptureFocus()
			end
		end
		function self:ChooseParent(object)
			if not location(object) then
				return false
			end
			self.Parent = object
			if name.Text == self.DefaultName then
				self.DefaultName = uniqueName(self.ClassName)
				name.Text = self.DefaultName
			end
			if self.Mode == "Parent" then
				self:CancelPicker()
			else
				showParent()
				validate()
			end
			return true
		end
		function self:Create()
			if self.Creating or not overlay.Visible or self.Mode ~= "Create" then
				return false
			end
			local valid, value = validate()
			if not valid then
				return false
			end
			self.Creating = true
			local ok, result = pcall(createScript, self.Parent, self.ClassName, value)
			self.Creating = false
			if not ok or not result then
				setError("Could not create script")
				return false
			end
			local previous = table.find(self.RecentParents, self.Parent)
			if previous then
				table.remove(self.RecentParents, previous)
			end
			table.insert(self.RecentParents, 1, self.Parent)
			if #self.RecentParents > 6 then
				table.remove(self.RecentParents)
			end
			self:Hide()
			return result
		end

		local function pick(object)
			if not self:ChooseParent(object) then
				setError("Invalid parent")
			end
		end
		function self:OpenPicker()
			if not overlay.Visible or self.Mode == "Parent" then
				return
			end
			self.Mode = "Parent"
			releaseNameFocus()
			if Apps.Properties.CancelObjectSelection then
				Apps.Properties.CancelObjectSelection()
			end
			parentPath.Text = "Click an object in Explorer"
			parentIcon.Image = ""
			parentBorder.Color = theme.Focus
			pickerIcon.Image = closeAsset or ""
			setError(nil)
			validate()
			explorer.SetObjectPicker(pick)
			explorer.Window:Show()
			explorer.Window:Focus()
		end
		function self:Show(contextObject)
			if overlay.Visible then
				return
			end
			previousFocus = userInput:GetFocusedTextBox()
			local selection = explorer.Selection.List
			local object = #selection == 1 and selection[1].Obj or contextObject
			if object and object:IsA("LuaSourceContainer") then
				object = object.Parent
			end
			if not location(object) then
				object = nil
				for _, parent in ipairs(self.RecentParents) do
					if location(parent) then
						object = parent
						break
					end
				end
			end
			if not object then
				for _, className in ipairs(suggestedRoots) do
					local parent = game:FindFirstChildOfClass(className)
					if location(parent) then
						object = parent
						break
					end
				end
			end
			self.Parent = object
			self.DefaultName = uniqueName(self.ClassName)
			name.Text = self.DefaultName
			showParent()
			overlay.Visible = true
			self:SelectType(self.ClassName)
			layout()
			name:CaptureFocus()
			name.CursorPosition = #name.Text + 1
			name.SelectionStart = 1
		end
		name:GetPropertyChangedSignal("Text"):Connect(function()
			if overlay.Visible and self.Mode == "Create" then
				validate()
			end
		end)
		name.FocusLost:Connect(function(enter)
			if enter then
				self:Create()
			end
		end)
		Main.TrackSignal(content:GetPropertyChangedSignal("AbsoluteSize"), function()
			if overlay.Visible then
				layout()
			end
		end)
		Main.TrackSignal(userInput.InputBegan, function(inputObject)
			if not overlay.Visible or not window:IsVisible() then
				return
			end
			local focused = userInput:GetFocusedTextBox()
			local key = inputObject.KeyCode
			if self.Mode == "Parent" and key == Enum.KeyCode.Escape then
				if focused == explorer.GuiElems.SearchBar then
					focused:ReleaseFocus()
				end
				self:CancelPicker()
			elseif not focused or focused == name then
				if key == Enum.KeyCode.Escape then
					self:Hide(true)
				elseif key == Enum.KeyCode.Tab and focused == name then
					self:OpenPicker()
				end
			end
		end)
		Main.TrackSignal(explorer.Window.OnDeactivate, function()
			self:CancelPicker(false)
		end)
		Main.TrackSignal(explorer.Window.OnMinimize, function()
			self:CancelPicker(false)
		end)
		Main.TrackSignal(window.OnDeactivate, function()
			self:Hide()
		end)
		Main.TrackSignal(window.OnMinimize, function()
			self:Hide()
		end)
		return self
	end
	return Dialog
end
return { InitDeps = InitDeps, Main = CreateModule }
