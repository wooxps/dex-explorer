--!strict

local Main, Lib, service, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, service, createSimple = d.Main, d.Lib, d.service, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Module = {}
	function Module.Create(options)
		local gui = createSimple("Frame", {
			Name = "ColumnSplitter",
			Parent = options.Parent,
			Active = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 5, 1, 0),
			ZIndex = 16,
		})
		local cursor = Lib.Window.BindSplitterCursor(gui, options.Enabled)
		local dragging, touch = false, nil
		local function apply(pos)
			if not dragging or not options.Enabled() then
				return
			end
			local width = options.Parent.AbsoluteSize.X
			if width <= 0 then
				return
			end
			local margin = math.min(80, width / 2)
			options.Change(math.clamp(pos.X - options.Parent.AbsolutePosition.X, margin, width - margin) / width)
		end
		local frame = Lib.FrameTask(apply)
		local self = { Gui = gui }
		function self:Stop()
			frame:Flush()
			frame:Cancel()
			dragging = false
			touch = nil
			cursor:End()
		end
		function self:Layout(x, visible)
			gui.Position = UDim2.fromOffset(math.floor(x + 0.5) - 2, 0)
			gui.Visible = visible
			if not visible then
				self:Stop()
			end
		end
		Main.TrackSignal(gui.InputBegan, function(input)
			if
				dragging or not options.Enabled()
				or (
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end
			dragging = true
			touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
			cursor:Begin(input.Position)
		end)
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if not dragging or (touch and input ~= touch) or (not touch and input.UserInputType == Enum.UserInputType.Touch) then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				frame:Push(input.Position)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if not dragging or (touch and input ~= touch) or (not touch and input.UserInputType == Enum.UserInputType.Touch) then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if touch then frame:Push(input.Position) end
				self:Stop()
			end
		end)
		if service.UserInputService.WindowFocusReleased then
			Main.TrackSignal(service.UserInputService.WindowFocusReleased, function()
				self:Stop()
			end)
		end
		Main.AddCleanup(function()
			self:Stop()
			gui:Destroy()
		end)
		return self
	end
	return Module
end
return { InitDeps = InitDeps, Main = CreateModule }
