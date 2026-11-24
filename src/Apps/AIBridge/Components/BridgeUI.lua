--!strict

local Lib, Main, Settings, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Lib, Main, Settings, createSimple = d.Lib, d.Main, d.Settings, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local UI = {}
	function UI.Create(referenceStyle)
		local theme = Settings.Theme
		local light = theme.IconTheme == "Light"
		local palette = {
			Pane = light and theme.Main2 or Color3.fromRGB(29, 31, 35),
			Sidebar = light and theme.Menu or Color3.fromRGB(24, 26, 30),
			Raised = light and theme.TextBox or Color3.fromRGB(45, 48, 54),
			Border = light and theme.Outline2 or Color3.fromRGB(73, 77, 86),
			Input = light and theme.Menu or Color3.fromRGB(26, 28, 32),
			Selection = light and theme.ListSelection or Color3.fromRGB(6, 89, 228),
			Link = light and theme.Focus or Color3.fromRGB(81, 151, 255),
			SwitchOff = light and theme.Outline2 or Color3.fromRGB(78, 84, 96),
		}
		local selection = referenceStyle and palette.Selection or theme.Focus
		local input = referenceStyle and palette.Input or theme.TextBox
		local inputBorder = referenceStyle and palette.Border or theme.Outline2
		local switchOff = referenceStyle and palette.SwitchOff or theme.TextBox
		local ui = { Theme = theme, Palette = palette, Alive = true }
		function ui:Node(class, props)
			return createSimple(class, props)
		end
		function ui:Round(item, radius)
			local corner = item:FindFirstChildOfClass("UICorner") or self:Node("UICorner", { Parent = item })
			corner.CornerRadius = UDim.new(0, radius or 5)
			return item
		end
		function ui:Outline(item, color)
			local stroke = item:FindFirstChildOfClass("UIStroke")
				or self:Node("UIStroke", {
					Parent = item,
					Thickness = 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				})
			stroke.Color = color or palette.Border
			return stroke
		end
		function ui:Icon(parent, name, glyph, position, size, color)
			return self:Node("ImageLabel", {
				Parent = parent,
				Name = name,
				Position = position,
				Size = type(size) == "number" and UDim2.fromOffset(size, size) or size,
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				ImageColor3 = color or theme.Text,
				Image = Main.GetStudioAsset("bridge/" .. glyph) or "",
				ZIndex = parent.ZIndex + 1,
			})
		end
		function ui:Text(parent, name, value, position, size, muted, fontSize)
			local item = self:Node("TextLabel", {
				Parent = parent,
				Name = name,
				Text = value,
				Position = position,
				Size = size,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				RichText = false,
			})
			Lib.StudioText(item)
			item.TextSize = fontSize or 12
			if muted then
				item.TextColor3 = theme.PlaceholderText
			end
			return item
		end
		function ui:Rule(parent, name, y)
			return self:Node("Frame", {
				Parent = parent,
				Name = name,
				Position = UDim2.fromOffset(20, y),
				Size = UDim2.new(1, -40, 0, 1),
				BackgroundColor3 = theme.Outline2,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			})
		end
		function ui:Tip(item, value)
			Lib.StudioTooltip(item, value)
		end
		function ui:Button(parent, name, value, position, size, callback, kind)
			local gui = self:Node("TextButton", {
				Parent = parent,
				Name = name,
				Text = value,
				Position = position,
				Size = size,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				RichText = false,
			})
			Lib.StudioText(gui)
			gui.TextSize = 12
			self:Round(gui)
			local record = { Gui = gui, Enabled = true, Kind = kind or "secondary", Hovered = false, Pressed = false }
			function record:Paint()
				local primary = self.Kind == "primary"
				local quiet = self.Kind == "quiet"
				local outlined = self.Kind == "outlined"
				if outlined and not self.Stroke then
					self.Stroke = ui:Outline(gui)
				end
				if self.Stroke then
					self.Stroke.Enabled = outlined
				end
				gui.BackgroundTransparency = (self.Kind == "link" or quiet and not self.Hovered) and 1 or 0
				gui.BackgroundColor3 = not self.Enabled and theme.Button
					or primary and selection
					or self.Pressed and (theme.ButtonPress or theme.Menu)
					or self.Hovered and theme.ButtonHover
					or outlined and palette.Raised
					or theme.Button
				gui.TextColor3 = self.Enabled
						and (self.TextColor or (referenceStyle and primary and theme.SelectedText) or theme.Text)
					or theme.PlaceholderText
				if primary and self.Enabled then
					gui.BackgroundTransparency = self.Pressed and 0.25 or self.Hovered and 0.08 or 0
				end
			end
			function record:SetEnabled(value)
				self.Enabled = value == true
				gui.Active = self.Enabled
				gui.Selectable = self.Enabled
				if not self.Enabled then
					self.Hovered = false
					self.Pressed = false
				end
				self:Paint()
			end
			function record:SetKind(value)
				self.Kind = value
				self:Paint()
			end
			gui.MouseEnter:Connect(function()
				record.Hovered = true
				record:Paint()
			end)
			gui.MouseLeave:Connect(function()
				record.Hovered = false
				record.Pressed = false
				record:Paint()
			end)
			gui.MouseButton1Down:Connect(function()
				if record.Enabled then
					record.Pressed = true
					record:Paint()
				end
			end)
			gui.MouseButton1Up:Connect(function()
				record.Pressed = false
				record:Paint()
			end)
			gui.Activated:Connect(function()
				if ui.Alive and record.Enabled then
					callback()
				end
			end)
			record:Paint()
			return record
		end
		function ui:Field(parent, name, placeholder, position, size)
			local item = self:Node("TextBox", {
				Name = name,
				Parent = parent,
				Position = position,
				Size = size,
				Text = "",
				PlaceholderText = placeholder,
				PlaceholderColor3 = theme.PlaceholderText,
				ClearTextOnFocus = false,
				MultiLine = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = input,
				BorderSizePixel = 0,
				RichText = false,
			})
			Lib.StudioText(item)
			item.TextSize = 12
			self:Round(item)
			self:Node("UIPadding", { Parent = item, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
			local stroke = self:Outline(item, inputBorder)
			item.Focused:Connect(function()
				stroke.Color = theme.Focus
			end)
			item.FocusLost:Connect(function()
				stroke.Color = inputBorder
			end)
			return item
		end
		function ui:Switch(parent, name, position, callback)
			local control = self:Button(parent, name, "", position, UDim2.fromOffset(32, 20), callback, "quiet")
			local track = self:Round(
				self:Node(
					"Frame",
					{ Parent = control.Gui, Name = "Track", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }
				),
				10
			)
			local thumb = self:Round(
				self:Node("Frame", {
					Parent = track,
					Name = "Thumb",
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.fromOffset(16, 16),
					BorderSizePixel = 0,
					BackgroundColor3 = theme.Text,
				}),
				8
			)
			control.On = false
			function control:Paint()
				self.Gui.BackgroundTransparency = 1
				track.BackgroundColor3 = self.On and selection or switchOff
				track.BackgroundTransparency = self.Enabled and 0 or 0.4
				thumb.BackgroundColor3 = self.Enabled and (referenceStyle and theme.SelectedText or theme.Text)
					or theme.PlaceholderText
				thumb.Position = UDim2.fromOffset(self.On and 14 or 2, 2)
				thumb.BackgroundTransparency = self.Pressed and 0.2 or 0
				if self.Hovered and self.Enabled and not self.On then
					track.BackgroundColor3 = theme.ButtonHover
				end
			end
			function control:SetOn(value)
				self.On = value == true
				self:Paint()
			end
			control:Paint()
			return control
		end
		function ui:Destroy()
			self.Alive = false
		end
		return ui
	end
	return UI
end
return { InitDeps = InitDeps, Main = CreateModule }
