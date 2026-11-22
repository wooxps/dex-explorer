--!strict
local Popup = {}
local Main, Lib, Apps, service
local current
local function close()
	if current then
		if current.onClose then current.onClose() end
		current.gui:Destroy()
		current = nil
	end
end

local rgb = Color3.fromRGB
function Popup.Open(title, height, compact)
	close()
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn = "DexFileDialog", true, false
	gui.DisplayOrder = Main.DisplayOrders.Menu - 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local d = {gui=gui, busy=false}
	current = d
	local function make(class, parent, props)
		local obj = Instance.new(class)
		for key, value in pairs(props) do obj[key] = value end
		obj.Parent = parent
		return obj
	end
	local function round(obj, radius)
		return make("UICorner", obj, {CornerRadius=UDim.new(0,radius)})
	end
	local function frame(parent, x, y, w, h, color)
		return make("Frame",parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			BorderSizePixel=0,BackgroundColor3=color})
	end
	local layout = make("Frame",gui,{Name="PopupLayout",Active=false,
		Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
	local panelWidth = if compact then 252 else 520
	local holder = frame(layout,0,0,panelWidth,height,rgb(39,41,48))
	holder.BackgroundTransparency = 1
	for i = 4, 1, -1 do
		local shadow = frame(holder,-i,2-i,panelWidth+2*i,height+2*i,Color3.new(0,0,0))
		shadow.Name = "Shadow"
		shadow.BackgroundTransparency = .98
		round(shadow,8+i)
		make("UIGradient",shadow,{Rotation=90,Transparency=NumberSequence.new(1,0)})
	end
	local panel = frame(holder,0,0,panelWidth,height,if compact then rgb(25,26,31) else rgb(39,41,48))
	panel.ZIndex = 2
	holder.AnchorPoint, holder.Position = Vector2.new(.5,.5), UDim2.fromScale(.5,.5)
	panel.ClipsDescendants, panel.Active = true, true
	round(panel,8)
	make("UIStroke",panel,{Name="WindowBorder",Thickness=1,Color=rgb(120,120,120),Transparency=.5,
		ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
	local scale = make("UIScale", holder, {})
	local function resize()
		local size = layout.AbsoluteSize
		scale.Scale = math.clamp(math.min((size.X-12)/panelWidth,(size.Y-12)/height),.2,1)
	end
	layout:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	local white, pale = rgb(247,247,248), rgb(213,215,222)
	local function label(parent, text, x,y,w,h,size,bold,color)
		return make("TextLabel",parent,{Text=text, Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			BackgroundTransparency=1,Font=if bold then Enum.Font.BuilderSansBold else Enum.Font.BuilderSans,
			TextColor3=color or pale,TextSize=size,TextXAlignment=Enum.TextXAlignment.Left})
	end
	local hoverTiming = TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
	local function button(parent, text, x,y,w,h,color,callback)
		local btn = make("TextButton",parent,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			AutoButtonColor=false,BorderSizePixel=0,BackgroundColor3=color,TextColor3=white,Font=Enum.Font.BuilderSans,TextSize=13})
		if not compact then round(btn,8) end
		local hovered, tween = false, nil
		local function paint(animate)
			if tween then tween:Cancel(); tween = nil end
			local target = color
			if hovered and btn.Interactable ~= false then
				target = rgb(math.min(255,math.round(color.R*255)+12),
					math.min(255,math.round(color.G*255)+12),math.min(255,math.round(color.B*255)+14))
			end
			if animate then
				tween = service.TweenService:Create(btn,hoverTiming,{BackgroundColor3=target})
				tween:Play()
			else
				btn.BackgroundColor3 = target
			end
		end
		btn.MouseEnter:Connect(function() hovered=true; paint(true) end)
		btn.MouseLeave:Connect(function() hovered=false; paint(true) end)
		btn.Activated:Connect(callback)
		return btn, function(base)
			color = base
			paint(false)
		end
	end
	local atlas = Main.GetStudioAsset("export/dialog-controls-v1")
	local function sprite(parent, name, x, y, width, height, sourceX)
		return make("ImageLabel",parent,{Name=name,BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),
			Size=UDim2.fromOffset(width,height),Image=atlas,ImageRectOffset=Vector2.new(sourceX,2),
			ImageRectSize=Vector2.new(width,height)})
	end
	local titlebar = frame(panel,0,0,panelWidth,30,rgb(243,243,243))
	round(titlebar,8)
	frame(titlebar,0,20,panelWidth,10,titlebar.BackgroundColor3)
	local dragStart, panelStart, pointer
	titlebar.Active = true
	titlebar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragStart, panelStart, pointer = input.Position, holder.Position, input
		end
	end)
	local moving = service.UserInputService.InputChanged:Connect(function(input)
		if not pointer or (input ~= pointer and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
		local delta = input.Position-dragStart
		holder.Position = UDim2.new(panelStart.X.Scale,panelStart.X.Offset+delta.X,panelStart.Y.Scale,panelStart.Y.Offset+delta.Y)
	end)
	local released = service.UserInputService.InputEnded:Connect(function(input)
		if input == pointer then pointer = nil end
	end)
	gui.Destroying:Connect(function() moving:Disconnect(); released:Disconnect() end)
	local logo = frame(titlebar,8,7,16,16,rgb(21,22,26))
	round(logo,3)
	local brand = Main.GetStudioAsset("branding/dex/caption-12-v1")
	if brand then
		make("ImageLabel",logo,{Name="DexIcon",BackgroundTransparency=1,Position=UDim2.fromOffset(2,2),
			Size=UDim2.fromOffset(12,12),Image=brand,ResampleMode=Enum.ResamplerMode.Pixelated})
	else
		label(logo,"D",3,-1,14,17,14,true,white)
	end
	label(titlebar,title,29,0,panelWidth-80,30,12,false,rgb(20,20,20))
	local x = make("TextButton",titlebar,{Name="Close",Text="",AutoButtonColor=false,
		BorderSizePixel=0,Position=UDim2.fromOffset(panelWidth-30,0),Size=UDim2.fromOffset(30,30),BackgroundTransparency=1})
	local hover = frame(x,0,0,30,29,rgb(196,43,28))
	round(hover,8)
	local left = frame(hover,0,0,10,29,hover.BackgroundColor3)
	local bottom = frame(hover,0,20,30,9,hover.BackgroundColor3)
	local glyphs = {}
	if atlas then
		glyphs[1] = sprite(x,"CloseIcon",9,8,12,12,88)
	else
		for _, angle in ipairs({45,-45}) do
			local line = frame(x,8,14,14,1,rgb(23,24,24))
			line.Rotation = angle
			table.insert(glyphs,line)
		end
	end
	local over, down = false, false
	local function paintClose()
		hover.Visible = over
		local color = if down then rgb(171,38,26) else rgb(196,43,28)
		hover.BackgroundColor3, left.BackgroundColor3, bottom.BackgroundColor3 = color,color,color
		for _, glyph in ipairs(glyphs) do
			local ink = if over then Color3.new(1,1,1) else rgb(23,24,24)
			if atlas then glyph.ImageColor3 = ink else glyph.BackgroundColor3 = ink end
		end
	end
	Apps.TooltipActions.Bind(x,"Close")
	x.MouseEnter:Connect(function() over=true; paintClose() end)
	x.MouseLeave:Connect(function() over,down=false,false; paintClose() end)
	x.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then down=true; paintClose() end
	end)
	x.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then down=false; paintClose() end
	end)
	x.Activated:Connect(close)
	paintClose()
	local status = label(panel,"",20,height-57,312,46,13,false,rgb(255,180,172))
	status.TextWrapped = true
	if compact then
		status.Position, status.Size = UDim2.fromOffset(12,height-67), UDim2.fromOffset(panelWidth-24,25)
		status.TextSize = 12
	end
	local cancel = button(panel,"Cancel",0,height-52,57,32,if compact then rgb(53,55,65) else rgb(59,62,72),close)
	local submit
	local primary, setPrimaryColor = button(panel,"",0,height-52,53,32,rgb(51,95,255),function()
		if not d.busy and submit then submit() end
	end)
	local function buttons(text, width, busy)
		if compact then
			primary.Position, cancel.Position = UDim2.fromOffset(66,height-40), UDim2.fromOffset(147,height-40)
			primary.Size, cancel.Size = UDim2.fromOffset(75,25), UDim2.fromOffset(75,25)
		else
			primary.Position = UDim2.fromOffset(500-width,height-52)
			primary.Size = UDim2.fromOffset(width,32)
			cancel.Position = UDim2.fromOffset(435-width,height-52)
		end
		primary.Text, primary.Interactable = text, not busy
		setPrimaryColor(if compact then rgb(53,55,65) elseif busy then rgb(45,68,152) else rgb(51,95,255))
		primary.TextSize, cancel.TextSize = if compact then 12 else 13, if compact then 12 else 13
		primary.TextColor3 = if compact and busy then rgb(79,85,103) elseif busy then rgb(157,168,200) else white
	end
	function d.setPrimary(text, callback, message)
		submit = callback
		status.Text = message or ""
		buttons(text,89,callback == nil)
	end
	d.sprite = if atlas then sprite else nil
		function d.isOpen() return current == d end
	function d.close() if current == d then close() end end
	function d.hideCancel() cancel.Visible = false end
	function d.formAction(text, enabled, callback)
		submit = if enabled then callback else nil
		buttons(text,64,not enabled)
		status.Text = ""
	end
	function d.input(caption,initial,y)
		label(panel,caption,24,y,472,22,14,true)
		local box = make("TextBox",panel,{Name="NameBox",Text=initial,ClearTextOnFocus=false,
			Position=UDim2.fromOffset(24,y+27),Size=UDim2.fromOffset(472,34),TextSize=14,
			Font=Enum.Font.BuilderSans,TextColor3=white,TextXAlignment=Enum.TextXAlignment.Left,
			BackgroundColor3=rgb(29,30,36),BorderSizePixel=0})
		round(box,5)
		make("UIPadding",box,{PaddingLeft=UDim.new(0,9),PaddingRight=UDim.new(0,9)})
		make("UIStroke",box,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=rgb(76,79,91)})
		return box
	end
	function d.bindForm(box,text,valid,save)
		local working = false
		local function run()
			if working or not d.isOpen() or not valid() then return end
			working = true
			local ok,err = pcall(save)
			working = false
			if not d.isOpen() then return end
			if ok then d.close() else status.Text = tostring(err):gsub("^.-:%d+: ", "") end
		end
		local function refresh() d.formAction(text,valid(),run) end
		box:GetPropertyChangedSignal("Text"):Connect(refresh)
		box.FocusLost:Connect(function(enter) if enter then run() end end)
		refresh()
	end
	d.status = status
	function d.action(text, width, callback)
		buttons(text,width,false)
		submit = function()
			d.busy = true
			status.Text = ""
			buttons("Processing...",89,true)
			task.defer(function()
				task.wait()
				if d ~= current then return end
				local ok, message = pcall(callback, function() return d ~= current end)
				if d ~= current then return end
				d.busy = false
				if not ok then
					status.Text = tostring(message):gsub("^.-:%d+: ", "")
					buttons(text,width,false)
				elseif message then
					status.Text, status.TextColor3 = message, pale
					buttons("Done",53,false)
					submit = close
				else
					close()
				end
			end)
		end
	end
	d.panel, d.make, d.frame, d.round, d.label, d.button = panel,make,frame,round,label,button
	Lib.ShowGui(gui)
	resize()
	return d
end

return {
	InitDeps = function(d)
		Main, Lib, Apps, service = d.Main, d.Lib, d.Apps, d.service
		Main.AddCleanup(close)
	end,
	InitAfterMain = function() end,
	Main = function() return Popup end,
}
