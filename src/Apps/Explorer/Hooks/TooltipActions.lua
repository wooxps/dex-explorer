--!strict

local Apps, Main, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Settings, service = d.Apps, d.Main, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Tooltip = {}
	Tooltip.Style = table.freeze({
		ShowDelay = 0.4,
		HideDelay = 0.3,
		TextSize = 17,
		MaxWidth = 400,
		PaddingX = 6,
		PaddingY = 4,
		PanelAllowance = 6,
		BorderSize = 2,
	})
	local gui, root, owner, candidate
	local revision = 0
	local bindings = setmetatable({}, { __mode = "k" })
	local function flush(element)
		if root then
			Apps.React.ReactRoblox.flushSync(function()
				root:render(element)
			end)
		end
	end
	local function dismiss()
		revision += 1
		owner = nil
		candidate = nil
		if gui then
			gui.Enabled = false
		end
	end
	local function palette()
		if Settings.Theme.IconTheme == "Light" then
			return Color3.fromRGB(43, 45, 51), Color3.fromRGB(249, 249, 249), Color3.new(0, 0, 0)
		end
		return Color3.fromRGB(242, 242, 243), Color3.fromRGB(17, 18, 22), Color3.new(1, 1, 1)
	end
	local function show(widget, value)
		if not gui then
			gui = Instance.new("ScreenGui")
			gui.Name = "ExplorerTooltip"
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.DisplayOrder = Main.DisplayOrders.Menu + 1
			root = Apps.React.ReactRoblox.createRoot(gui)
		end
		local style = Tooltip.Style
		local maxWidth = math.max(1, math.min(style.MaxWidth, Main.Mouse.ViewSizeX - 18))
		local plain = value:gsub("<[^>]->", "")
		local measured =
			service.TextService:GetTextSize(plain, style.TextSize, Enum.Font.SourceSans, Vector2.new(maxWidth, 100000))
		local width = math.min(maxWidth, math.ceil(measured.X)) + style.PaddingX * 2 + style.PanelAllowance
		local height = math.min(Main.Mouse.ViewSizeY, math.ceil(measured.Y) + style.PaddingY * 2 + style.PanelAllowance)
		local x = widget.AbsolutePosition.X + widget.AbsoluteSize.X
		local y = widget.AbsolutePosition.Y + widget.AbsoluteSize.Y + 2
		if y + height > Main.Mouse.ViewSizeY then
			y = widget.AbsolutePosition.Y - height - 2
		end
		x = math.clamp(x, 0, math.max(0, Main.Mouse.ViewSizeX - width))
		y = math.clamp(y, 0, math.max(0, Main.Mouse.ViewSizeY - height))
		local background, text, border = palette()
		local React = Apps.React.React
		flush(React.createElement("TextLabel", {
			Name = "Tooltip",
			Font = Enum.Font.SourceSans,
			TextSize = style.TextSize,
			Text = value,
			RichText = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = text,
			BackgroundColor3 = background,
			BackgroundTransparency = 0,
			BorderColor3 = border,
			BorderSizePixel = style.BorderSize,
			BorderMode = Enum.BorderMode.Inset,
			Size = UDim2.fromOffset(width, height),
			Position = UDim2.fromOffset(x, y),
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, style.PaddingX),
				PaddingRight = UDim.new(0, style.PaddingX),
				PaddingTop = UDim.new(0, style.PaddingY),
				PaddingBottom = UDim.new(0, style.PaddingY),
			}),
		}))
		owner = widget
		gui.Enabled = true
		Main.SecureGui(gui)
	end
	function Tooltip.Bind(widget, text, _renderer)
		local existing = bindings[widget]
		if existing then
			existing.text = text
			return existing.destroy
		end
		local binding = { text = text, hovered = false, connections = {} }
		bindings[widget] = binding
		local function connect(event, callback)
			binding.connections[#binding.connections + 1] = event:Connect(callback)
		end
		local function hide(immediate)
			binding.hovered = false
			if candidate == widget then
				candidate = nil
				revision += 1
			end
			local current = revision
			if owner ~= widget then
				return
			end
			if immediate then
				owner = nil
				if gui then
					gui.Enabled = false
				end
				return
			end
			task.delay(Tooltip.Style.HideDelay, function()
				if current == revision and owner == widget and candidate == nil then
					dismiss()
				end
			end)
		end
		connect(widget.MouseEnter, function()
			binding.hovered = true
			candidate = widget
			revision += 1
			local current = revision
			task.delay(Tooltip.Style.ShowDelay, function()
				if
					current ~= revision
					or candidate ~= widget
					or not binding.hovered
					or not Main.Alive
					or not widget:IsDescendantOf(game)
				then
					return
				end
				local explorer = Apps.Explorer
				if explorer and (explorer.Dragging or explorer.BoxSelecting) then
					return
				end
				if _renderer and Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown() then
					return
				end
				local value = type(binding.text) == "function" and binding.text() or binding.text
				if type(value) == "string" and value ~= "" then
					show(widget, value)
				else
					dismiss()
				end
			end)
		end)
		connect(widget.MouseLeave, function()
			hide(false)
		end)
		connect(widget.InputBegan, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				hide(true)
			end
		end)
		if widget:IsA("GuiButton") or widget:IsA("TextButton") or widget:IsA("ImageButton") then
			connect(widget.Activated, function()
				hide(true)
			end)
		end
		function binding.destroy()
			if bindings[widget] ~= binding then
				return
			end
			if binding.hovered or owner == widget then
				hide(true)
			end
			bindings[widget] = nil
			for _, connection in ipairs(binding.connections) do
				connection:Disconnect()
			end
			table.clear(binding.connections)
		end
		connect(widget.Destroying, binding.destroy)
		return binding.destroy
	end
	Tooltip.Dismiss = dismiss
	Main.TrackSignal(service.UserInputService.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			dismiss()
		end
	end)
	Main.TrackSignal(service.UserInputService.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			dismiss()
		end
	end)
	if service.UserInputService.WindowFocusReleased then
		Main.TrackSignal(service.UserInputService.WindowFocusReleased, dismiss)
	end
	Main.AddCleanup(function()
		dismiss()
		local pending = {}
		for _, binding in pairs(bindings) do
			pending[#pending + 1] = binding
		end
		for _, binding in ipairs(pending) do
			binding.destroy()
		end
		if root then
			Apps.React.ReactRoblox.flushSync(function()
				root:unmount()
			end)
			root = nil
		end
		if gui then
			gui:Destroy()
			gui = nil
		end
	end)
	return Tooltip
end
return { InitDeps = InitDeps, Main = CreateModule }
