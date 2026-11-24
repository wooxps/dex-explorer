--!strict

local Apps, Lib, service

------------------------------ Initialization ------------------------------

local function InitDeps(deps)
	Apps, Lib, service = deps.Apps, deps.Lib, deps.service
end
------------------------------ Module ------------------------------

local function Main()
	local Widget = {}
	function Widget.Attach(panel, callbacks)
		local skin = Apps.StudioEditorSkin
		local state = { MatchCase = false, WholeWord = false, Regex = false }
		local view = { Gui = panel, Options = state, Expanded = false, Buttons = {} }
		local function node(class, props)
			local object = Instance.new(class)
			for key, value in pairs(props) do
				object[key] = value
			end
			return object
		end
		panel.ClipsDescendants = true
		panel.BackgroundColor3 = skin.Inactive
		panel.BorderSizePixel = 0
		local function field(name, placeholder, y)
			local input = node("TextBox", {
				Name = name,
				Parent = panel,
				Text = "",
				PlaceholderText = placeholder,
				ClearTextOnFocus = false,
				MultiLine = false,
				Position = UDim2.fromOffset(24, y),
				Size = UDim2.new(1, -88, 0, 20),
				BackgroundColor3 = Color3.fromRGB(37, 38, 43),
				BorderColor3 = skin.Border,
				BorderSizePixel = 1,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = skin.Text,
				PlaceholderColor3 = Color3.fromRGB(160, 162, 167),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 22,
			})
			input:SetAttribute("NativeObjectName", "EmbeddedFindReplace_" .. name .. "LineEdit")
			node("UIPadding", { Parent = input, PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) })
			input:GetPropertyChangedSignal("Text"):Connect(function()
				local cleaned = input.Text:gsub("[\r\n]", "")
				if cleaned ~= input.Text then
					input.Text = cleaned
				end
			end)
			input.Focused:Connect(function()
				input.BorderColor3 = Color3.fromRGB(51, 153, 255)
			end)
			input.FocusLost:Connect(function()
				input.BorderColor3 = skin.Border
			end)
			return input
		end
		view.Find = field("Find", "Find...", 4)
		view.Replace = field("Replace", "Replace...", 26)
		view.Replace.Visible = false
		local function control(name, icon, x, y, callback, description, right)
			local button = node("TextButton", {
				Name = name,
				Parent = panel,
				Text = "",
				Position = right and UDim2.new(1, x, 0, y) or UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(18, 18),
				AutoButtonColor = false,
				Interactable = true,
				BackgroundColor3 = Color3.fromRGB(54, 56, 65),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				BorderColor3 = skin.Border,
				BorderMode = Enum.BorderMode.Inset,
				ZIndex = 22,
			})
			local image = Lib.SetNativeIcon(button, icon)
			if image then
				image.Size = UDim2.fromOffset(16, 16)
				image.Position = UDim2.new(0.5, -8, 0.5, -8)
				image.AnchorPoint = Vector2.new()
			end
			button:SetAttribute("NativeObjectName", "EmbeddedFindReplace_" .. name .. "Button")
			Lib.StudioTooltip(button, description)
			button.MouseEnter:Connect(function()
				if button.Interactable then
					button.BackgroundTransparency = 0
				end
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = button:GetAttribute("Checked") and 0 or 1
			end)
			button.MouseButton1Click:Connect(function()
				if button.Interactable then
					callback()
				end
			end)
			view.Buttons[name] = button
			return button
		end
		control("ToggleReplace", "native/editor/expand", 4, 4, function()
			callbacks.ToggleReplace(not view.Expanded)
		end, "Show or hide Replace")
		control("FindPrevious", "native/editor/previous", -62, 4, function()
			callbacks.Next(true)
		end, "Previous match (Shift+F3)", true)
		control("FindNext", "native/editor/next", -42, 4, function()
			callbacks.Next(false)
		end, "Next match (F3)", true)
		control("CloseDialog", "native/editor/close", -22, 4, callbacks.Close, "Close (Escape)", true)
		control("ReplaceNext", "native/editor/replace", -62, 26, function()
			callbacks.Replace(false)
		end, "Replace next", true)
		control("ReplaceAll", "native/editor/replace_all", -42, 26, function()
			callbacks.Replace(true)
		end, "Replace all", true)
		local function toggle(name, key, icon, x, description)
			local button
			button = control(name, icon, x, 26, function()
				state[key] = not state[key]
				view:SetOptions(state)
				callbacks.OptionsChanged()
			end, description)
			return button
		end
		toggle("MatchCase", "MatchCase", "native/editor/match_case", 24, "Match case")
		toggle("MatchWholeWord", "WholeWord", "native/editor/whole_word", 44, "Match whole word")
		toggle("MatchRegularExpression", "Regex", "native/editor/regex", 64, "Use regular expressions")
		view.Results = node("TextLabel", {
			Name = "NumResults",
			Parent = panel,
			Text = "",
			BackgroundTransparency = 1,
			Font = Lib.StudioFont,
			TextSize = 12,
			TextColor3 = skin.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(84, 26),
			Size = UDim2.new(1, -88, 0, 20),
			ZIndex = 22,
		})
		view.Results:SetAttribute("NativeObjectName", "EmbeddedFindReplace_NumResults")
		node("Frame", {
			Name = "BottomBorder",
			Parent = panel,
			BackgroundColor3 = skin.Border,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -4),
			Size = UDim2.new(1, 0, 0, 4),
			ZIndex = 22,
		})
		function view:SetReplace(expanded)
			self.Expanded = expanded == true
			self.Replace.Visible = self.Expanded
			self.Buttons.ReplaceNext.Visible = self.Expanded
			self.Buttons.ReplaceAll.Visible = self.Expanded
			local y = self.Expanded and 48 or 26
			for _, name in ipairs({ "MatchCase", "MatchWholeWord", "MatchRegularExpression" }) do
				self.Buttons[name].Position = UDim2.fromOffset(self.Buttons[name].Position.X.Offset, y)
			end
			self.Results.Position = UDim2.fromOffset(84, y)
			Lib.SetNativeIcon(
				self.Buttons.ToggleReplace,
				self.Expanded and "native/editor/collapse" or "native/editor/expand"
			)
		end
		function view:SetOptions(options)
			for key, value in pairs(options) do
				state[key] = value == true
			end
			for name, key in pairs({
				MatchCase = "MatchCase",
				MatchWholeWord = "WholeWord",
				MatchRegularExpression = "Regex",
			}) do
				local button = self.Buttons[name]
				button:SetAttribute("Checked", state[key])
				button.BackgroundTransparency = state[key] and 0 or 1
				button.BorderSizePixel = state[key] and 1 or 0
			end
		end
		function view:SetResults(index, count, problem, canReplace)
			local countText = tostring(count) .. (count == 1 and " match" or " matches")
			if index and index > 0 and count > 0 then
				countText = tostring(index) .. " of " .. countText
			end
			self.Results.Text = problem and "Invalid expression" or self.Find.Text == "" and "" or "  " .. countText
			self.Results.TextColor3 = problem and Color3.fromRGB(255, 110, 110) or skin.Text
			self.Find.BorderColor3 = problem and Color3.fromRGB(255, 90, 90)
				or service.UserInputService:GetFocusedTextBox() == self.Find and Color3.fromRGB(51, 153, 255)
				or skin.Border
			for _, name in ipairs({ "FindNext", "FindPrevious", "ReplaceNext", "ReplaceAll" }) do
				local available = not problem and count > 0 and (canReplace ~= false or name:sub(1, 4) == "Find")
				local button = self.Buttons[name]
				button.Interactable = available
				local icon = button:FindFirstChild("NativeIcon")
				if icon then
					icon.ImageTransparency = available and 0 or 0.55
				end
			end
		end
		view:SetReplace(false)
		return view
	end
	return Widget
end
return { InitDeps = InitDeps, Main = Main }
