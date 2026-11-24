--!strict

local Apps, Main, service, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, service, Settings = d.Apps, d.Main, d.service, d.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Scroll = {}
	function Scroll.AttachHoverBorders(frame, options)
		options = options or {}
		local holder = Instance.new("Frame")
		holder.Name = "ScrollBarBorders"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Active = false
		holder.Position = frame.Position
		holder.Size = frame.Size
		holder.ZIndex = (frame.ZIndex or 1) + 5
		holder.Parent = frame.Parent
		local vertical = Instance.new("Frame")
		vertical.Name = "VerticalScrollBarBorder"
		vertical.AnchorPoint = Vector2.new(0.5, 0)
		vertical.Position = UDim2.new(1, -8, 0, 0)
		vertical.Size = UDim2.new(0, 1, 1, 0)
		local horizontal = Instance.new("Frame")
		horizontal.Name = "HorizontalScrollBarBorder"
		horizontal.AnchorPoint = Vector2.new(0, 0.5)
		horizontal.Position = UDim2.new(0, 0, 1, -8)
		horizontal.Size = UDim2.new(1, 0, 0, 1)
		local lines = { vertical, horizontal }
		for _, line in ipairs(lines) do
			line.BorderSizePixel = 0
			line.Active = false
			line.Visible = false
			line.ZIndex = holder.ZIndex
			line.Parent = holder
		end
		local controller = { Vertical = vertical, Horizontal = horizontal }
		local destroyed = false
		local lastX, lastY, lastTheme
		function controller.Update(x, y)
			if destroyed then
				return
			end
			if x ~= nil then
				lastX, lastY = x, y
			end
			if holder.Position ~= frame.Position then
				holder.Position = frame.Position
			end
			if holder.Size ~= frame.Size then
				holder.Size = frame.Size
			end
			local theme = Settings.Theme.IconTheme or "Dark"
			if lastTheme ~= theme then
				lastTheme = theme
				local light = lastTheme == "Light"
				local color = light and Color3.fromRGB(51, 59, 76) or Color3.fromRGB(187, 194, 209)
				for _, line in ipairs(lines) do
					line.BackgroundColor3 = color
					line.BackgroundTransparency = light and 0.92 or 0.88
				end
			end
			local axis
			if not options.IsActive or options.IsActive() then
				local ok, drag = pcall(function()
					return frame.DraggingScrollBar
				end)
				if ok and drag == Enum.DraggingScrollBar.Vertical then
					axis = "Vertical"
				elseif ok and drag == Enum.DraggingScrollBar.Horizontal then
					axis = "Horizontal"
				elseif not options.IsBlocked or not options.IsBlocked() then
					local p, s = frame.AbsolutePosition, frame.AbsoluteSize
					local view = frame.AbsoluteWindowSize or s
					local canvas = frame.AbsoluteCanvasSize
					local cx = canvas and canvas.X or frame.CanvasSize.X.Offset
					local cy = canvas and canvas.Y or frame.CanvasSize.Y.Offset
					local width = frame.ScrollBarThickness
					local px, py = lastX, lastY
					if px and py and px >= p.X and py >= p.Y and px < p.X + s.X and py < p.Y + s.Y then
						if cy > view.Y and px >= p.X + s.X - width then
							axis = "Vertical"
						elseif cx > view.X and py >= p.Y + s.Y - width then
							axis = "Horizontal"
						end
					end
				end
			end
			local v, h = axis == "Vertical", axis == "Horizontal"
			if vertical.Visible ~= v then
				vertical.Visible = v
			end
			if horizontal.Visible ~= h then
				horizontal.Visible = h
			end
		end
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and input.Position then
				controller.Update(input.Position.X, input.Position.Y)
			end
		end)
		for _, property in ipairs({
			"AbsolutePosition",
			"AbsoluteSize",
			"AbsoluteWindowSize",
			"AbsoluteCanvasSize",
			"CanvasSize",
			"Position",
			"Size",
			"DraggingScrollBar",
		}) do
			local ok, signal = pcall(frame.GetPropertyChangedSignal, frame, property)
			if ok then
				Main.TrackSignal(signal, function()
					controller.Update()
				end)
			end
		end
		Main.AddCleanup(function()
			destroyed = true
			holder:Destroy()
		end)
		controller.Update()
		return controller
	end
	function Scroll.New(frame, horizontal)
		local step = horizontal and 1 or 20
		local self = {
			Index = 0,
			VisibleSpace = 0,
			TotalSpace = 0,
			Increment = 1,
			WheelIncrement = 3,
			Scrolled = Apps.Signal.new(),
		}
		function self:Update()
			self.Index = math.clamp(math.floor(self.Index), 0, math.max(0, self.TotalSpace - self.VisibleSpace))
			local current = frame.CanvasPosition
			local axis = horizontal and current.X or current.Y
			local target = math.floor(axis / step) == self.Index
					and math.clamp(axis, 0, math.max(0, (self.TotalSpace - self.VisibleSpace) * step))
				or self.Index * step
			local position = horizontal and Vector2.new(target, current.Y) or Vector2.new(current.X, target)
			if current.X ~= position.X or current.Y ~= position.Y then
				frame.CanvasPosition = position
			end
		end
		function self:SetScrollFrame() end
		Main.TrackSignal(frame:GetPropertyChangedSignal("CanvasPosition"), function()
			local position = frame.CanvasPosition
			local index = math.floor((horizontal and position.X or position.Y) / step)
			if self.Index ~= index then
				self.Index = index
				if not self.SuppressEvents then
					self.Scrolled:Fire()
				end
			end
		end)
		if not horizontal then
			Main.TrackSignal(frame.InputChanged, function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseWheel then
					return
				end
				local modified = false
				if input.IsModifierKeyDown then
					modified = input:IsModifierKeyDown(Enum.ModifierKey.Ctrl)
						or input:IsModifierKeyDown(Enum.ModifierKey.Shift)
				else
					local user = service.UserInputService
					modified = user:IsKeyDown(Enum.KeyCode.LeftControl)
						or user:IsKeyDown(Enum.KeyCode.RightControl)
						or user:IsKeyDown(Enum.KeyCode.LeftShift)
						or user:IsKeyDown(Enum.KeyCode.RightShift)
				end
				if not modified then
					return
				end
				local page = math.max(0, self.VisibleSpace * step - 3)
				local current = frame.CanvasPosition
				local size = frame.AbsoluteWindowSize or frame.AbsoluteSize
				local limit = math.max(0, frame.CanvasSize.Y.Offset - size.Y)
				local direction = input.Position.Z < 0 and 1 or -1
				frame.CanvasPosition = Vector2.new(current.X, math.clamp(current.Y + direction * page, 0, limit))
			end)
		end
		Main.AddCleanup(function()
			self.Scrolled:Destroy()
		end)
		return self
	end
	return Scroll
end
return { InitDeps = InitDeps, Main = CreateModule }
