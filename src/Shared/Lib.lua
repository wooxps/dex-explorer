--!strict


------------------------------ Variables ------------------------------

local Main, Lib, Apps, Settings
local Explorer, Properties, ScriptViewer, Notebook
local API, RMD, env, service, plr, create, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function InitAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

------------------------------ Module ------------------------------

local function CreateModule()
	local Lib = {}

	Lib.StudioFont = Enum.Font.BuilderSans
	Lib.StudioBold = Enum.Font.BuilderSansBold
	local frameTasks, frameConnection = {}, nil
	local function stopIdleFrames()
		if frameConnection and next(frameTasks) == nil then
			frameConnection:Disconnect()
			frameConnection = nil
		end
	end
	Lib.FrameTask = function(callback)
		local item = { Version = 0 }
		function item:Cancel()
			self.Version += 1
			frameTasks[self] = nil
			self.Value = nil
			stopIdleFrames()
		end
		function item:Flush()
			if not frameTasks[self] then
				return
			end
			if Main.Alive == false then
				self:Cancel()
				return
			end
			frameTasks[self] = nil
			local value = self.Value
			self.Value = nil
			local ok, problem = pcall(callback, value)
			stopIdleFrames()
			if not ok then
				warn("[Dex Explorer] Frame update: " .. tostring(problem))
			end
		end
		function item:Push(value)
			if Main.Alive == false then
				return
			end
			self.Version += 1
			self.Value = value
			frameTasks[self] = self.Version
			if not frameConnection then
				frameConnection = service.RunService.RenderStepped:Connect(function()
					if next(frameTasks) == nil then
						stopIdleFrames()
						return
					end
					local batch = frameTasks
					frameTasks = {}
					for job, version in pairs(batch) do
						if Main.Alive == false then
							job.Value = nil
							continue
						end
						if job.Version ~= version then
							continue
						end
						local value = job.Value
						job.Value = nil
						local ok, problem = pcall(job.Callback, value)
						if not ok then
							warn("[Dex Explorer] Frame update: " .. tostring(problem))
						end
					end
					stopIdleFrames()
				end)
			end
		end
		item.Callback = callback
		return item
	end
	Main.AddCleanup(function()
		for item in pairs(frameTasks) do
			item.Value = nil
		end
		table.clear(frameTasks)
		stopIdleFrames()
	end)
	Lib.StudioText = function(obj)
		obj.Font = Lib.StudioFont
		obj.TextSize = 14
		obj.TextColor3 = Settings.Theme.Text
	end
	Lib.StudioCorner = function(obj, radius)
		local corner = obj:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", obj)
		corner.CornerRadius = UDim.new(0, radius or 4)
	end
	Lib.StudioTooltip = function(button, text)
		return Apps.TooltipActions.Bind(button, text)
	end
	Lib.StudioButton = function(parent, name, text, position, size)
		local button = createSimple("TextButton", {
			Name = name,
			Parent = parent,
			Text = text,
			Position = position,
			Size = size or UDim2.fromOffset(26, 26),
			AutoButtonColor = false,
			BackgroundColor3 = Settings.Theme.ButtonHover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		})
		Lib.StudioText(button)
		Lib.StudioCorner(button, 4)
		Lib.StudioIcon(button, name)
		button.MouseEnter:Connect(function()
			if not button:GetAttribute("NoHoverFill") then
				button.BackgroundTransparency = 0
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
		end)
		local tips = {
			History = "Recent searches",
			Options = "Explorer options",
			Previous = "Previous match",
			Next = "Next match",
			SelectAll = "Select all matches",
			Refresh = "Refresh results",
		}
		if tips[name] then
			Lib.StudioTooltip(button, tips[name])
		end
		return button
	end
	Lib.StudioIcon = function(button, kind)
		local keys = {
			Insert = "explorer/insert",
			History = "explorer/history",
			Options = "explorer/options",
			Previous = "explorer/previous",
			Next = "explorer/next",
			SelectAll = "explorer/selectall",
			Refresh = "explorer/refresh",
			Sidebar = "sidebar/collapse",
		}
		local key = keys[kind]
		if not key then
			return
		end
		local asset = Main.GetStudioAsset and Main.GetStudioAsset(key)
		local old = button:FindFirstChild("StudioIcon")
		if old then
			old:Destroy()
		end
		if not asset then
			local fallback = {
				Insert = "+",
				History = "Ã¢â€ Â¶",
				Options = "Ã¢â‚¬Â¢Ã¢â‚¬Â¢Ã¢â‚¬Â¢",
				Previous = "Ã¢â‚¬Â¹",
				Next = "Ã¢â‚¬Âº",
				SelectAll = "Ã¢â€“Â¡",
				Refresh = "Ã¢â€ Â»",
				Sidebar = "Ã¢â‚¬Â¹",
			}
			button.Text = fallback[kind] or ""
			return
		end
		button.Text = ""
		local layer = (button.ZIndex or 1) + 1
		local size = kind == "Insert" and 14 or 16
		local icon = createSimple("Frame", {
			Name = "StudioIcon",
			Parent = button,
			ZIndex = layer,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
		})
		createSimple("ImageLabel", {
			Name = "Native",
			Parent = icon,
			ZIndex = layer,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = asset,
			ScaleType = Enum.ScaleType.Fit,
		})
		return icon
	end

	Lib.SetNativeIcon = function(button, key, size)
		local asset = Main.GetStudioAsset and Main.GetStudioAsset(key)
		if not asset then
			return nil
		end
		local icon = button:FindFirstChild("NativeIcon")
		if not icon then
			icon = createSimple("ImageLabel", {
				Name = "NativeIcon",
				Parent = button,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = (button.ZIndex or 1) + 1,
				ScaleType = Enum.ScaleType.Fit,
			})
		end
		button.Text = ""
		icon.Image = asset
		icon.Size = UDim2.fromOffset(size or 16, size or 16)
		return icon
	end

	Lib.SetSidebarIcon = function(button, hidden, rightSide)
		local old = button:FindFirstChild("StudioIcon")
		if old then
			old:Destroy()
		end
		button.Text = ""
		local icon = button:FindFirstChild("DockChevron")
		local asset = Main.GetStudioAsset and Main.GetStudioAsset("native/sidebar/left")
		if not asset then
			if icon then
				icon.Visible = false
			end
			button.Text = (hidden ~= rightSide) and "Ã¢â‚¬Âº" or "Ã¢â‚¬Â¹"
			return
		end
		if not icon then
			icon = createSimple("ImageLabel", {
				Name = "DockChevron",
				Parent = button,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 16),
				Image = asset,
				ScaleType = Enum.ScaleType.Fit,
			})
		end
		icon.Visible = true
		icon.Rotation = (hidden ~= rightSide) and 180 or 0
	end

	Lib.StudioChevron = function(target, expanded, hovered)
		local legacy = target:FindFirstChild("Icon")
		local asset = Main.GetStudioAsset
			and Main.GetStudioAsset(expanded and "explorer/expanded" or "explorer/collapsed")
		local icon = target:FindFirstChild("StudioChevron")
		if not asset then
			if icon then
				icon.Visible = false
			end
			if legacy and legacy:IsA("ImageLabel") then
				legacy.Visible = true
			end
			return legacy
		end
		if legacy and legacy:IsA("ImageLabel") then
			legacy.Visible = false
		end
		if not icon then
			icon = createSimple("ImageLabel", {
				Name = "StudioChevron",
				Parent = target,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 16),
				ZIndex = (target.ZIndex or 1) + 1,
				ScaleType = Enum.ScaleType.Fit,
			})
		end
		icon.Visible = true
		icon.Image = asset
		icon.Rotation = 0
		icon.ImageTransparency = hovered and 0 or 0.08
		return icon
	end

	Lib.PanelAsset = function(name)
		local theme = Settings.Theme.IconTheme == "Light" and "light" or "dark"
		return Main.GetStudioAsset("native/panel-v2/" .. name .. "-" .. theme)
	end
	Lib.PanelButtonHover = function(button)
		local enabled, hovered, pressed = true, false, false
		local function paint()
			button.BackgroundTransparency = enabled and (hovered or pressed) and 0 or 1
			button.BackgroundColor3 = pressed and Color3.fromRGB(66, 68, 78) or Color3.fromRGB(53, 55, 65)
		end
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		local corner = button:FindFirstChildOfClass("UICorner")
		if corner then
			corner:Destroy()
		end
		button.MouseEnter:Connect(function()
			hovered = true
			paint()
		end)
		button.MouseLeave:Connect(function()
			hovered = false
			pressed = false
			paint()
		end)
		button.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				pressed = true
				paint()
			end
		end)
		button.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				pressed = false
				paint()
			end
		end)
		paint()
		return {
			Enable = function()
				enabled = true
				paint()
			end,
			Disable = function()
				enabled = false
				hovered = false
				pressed = false
				paint()
			end,
		}
	end

	Lib.StudioSearch = function(toolbar, placeholder, reserved, options)
		options = options or {}
		toolbar.BackgroundColor3 = Settings.Theme.Main2
		toolbar.Size = UDim2.new(1, 0, 0, 38)
		local frame = toolbar.SearchFrame
		frame.Position = UDim2.fromOffset(6, 5)
		frame.Size = UDim2.new(1, -12 - (reserved or 0), 0, 28)
		frame.BackgroundColor3 = Settings.Theme.TextBox
		if options.PixelBorder then
			local corner = frame:FindFirstChildOfClass("UICorner")
			if corner then
				corner:Destroy()
			end
		else
			Lib.StudioCorner(frame, 6)
		end
		local stroke = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", frame)
		stroke.Thickness = 1
		stroke.Color = options.BorderColor or Settings.Theme.Focus
		stroke.Enabled = options.PersistentBorder == true
		local box = frame.SearchBox
		Lib.StudioText(box)
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = Settings.Theme.PlaceholderText
		box.Position = UDim2.fromOffset(8, 0)
		box.Size = UDim2.new(1, -36, 1, 0)
		box.ClearTextOnFocus = false
		local hovered = false
		local function paintBorder()
			local focused = box:IsFocused()
			local color = focused and Settings.Theme.Focus
				or (hovered and options.HoverBorderColor or options.BorderColor or Settings.Theme.Focus)
			if options.BackgroundColor then
				frame.BackgroundColor3 = hovered and options.HoverBackgroundColor or options.BackgroundColor
			end
			if options.PixelBorder then
				stroke.Enabled = false
				frame.BorderSizePixel = 1
				frame.BorderMode = Enum.BorderMode.Inset
				frame.BorderColor3 = color
			else
				stroke.Enabled = focused or options.PersistentBorder == true
				stroke.Color = color
			end
		end
		if options.PixelBorder then
			paintBorder()
		end
		box.Focused:Connect(paintBorder)
		box.FocusLost:Connect(paintBorder)
		if options.HoverBorderColor then
			frame.MouseEnter:Connect(function()
				hovered = true
				paintBorder()
			end)
			frame.MouseLeave:Connect(function()
				hovered = false
				paintBorder()
			end)
		end
		local reset = frame.Reset
		reset.Position = UDim2.new(1, -26, 0, 1)
		reset.Size = UDim2.fromOffset(24, 26)
		reset.Text = ""
		local clearIcon = reset:FindFirstChild("ImageLabel")
		if clearIcon then
			local clearAsset = Main.GetStudioAsset and Main.GetStudioAsset("explorer/clear")
			if clearAsset then
				clearIcon.Image = clearAsset
			end
			clearIcon.Visible = true
			clearIcon.ImageColor3 = Color3.new(1, 1, 1)
			clearIcon.ImageTransparency = 0.15
			clearIcon.Position = UDim2.fromOffset(4, 5)
			clearIcon.Size = UDim2.fromOffset(16, 16)
			clearIcon.ScaleType = Enum.ScaleType.Fit
		end
		reset.Visible = box.Text ~= ""
		box:GetPropertyChangedSignal("Text"):Connect(function()
			reset.Visible = box.Text ~= ""
		end)
		return box
	end

	local renderStepped = service.RunService.RenderStepped
	local signalWait = renderStepped.wait
	local PH = newproxy()
	local SIGNAL = newproxy()

	local function initObj(props, mt)
		local type = type
		local function copy(t)
			local res = {}
			for i, v in pairs(t) do
				if v == SIGNAL then
					res[i] = Lib.Signal.new()
				elseif type(v) == "table" then
					res[i] = copy(v)
				else
					res[i] = v
				end
			end
			return res
		end

		local newObj = copy(props)
		return setmetatable(newObj, mt)
	end

	local function getGuiMT(props, funcs)
		return {
			__index = function(self, ind)
				if not props[ind] then
					return funcs[ind] or self.Gui[ind]
				end
			end,
			__newindex = function(self, ind, val)
				if not props[ind] then
					self.Gui[ind] = val
				else
					rawset(self, ind, val)
				end
			end,
		}
	end


	Lib.FormatLuaString = (function()
		local string = string
		local gsub = string.gsub
		local format = string.format
		local char = string.char
		local cleanTable = { ['"'] = '\\"', ["\\"] = "\\\\" }
		for i = 0, 31 do
			cleanTable[char(i)] = "\\" .. format("%03d", i)
		end
		for i = 127, 255 do
			cleanTable[char(i)] = "\\" .. format("%03d", i)
		end

		return function(str)
			return gsub(str, '["\\\0-\31\127-\255]', cleanTable)
		end
	end)()

	Lib.CheckMouseInGui = function(gui)
		if gui == nil then
			return false
		end
		local mouse = Main.Mouse
		local guiPosition = gui.AbsolutePosition
		local guiSize = gui.AbsoluteSize

		return mouse.X >= guiPosition.X
			and mouse.X < guiPosition.X + guiSize.X
			and mouse.Y >= guiPosition.Y
			and mouse.Y < guiPosition.Y + guiSize.Y
	end

	Lib.IsShiftDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or service.UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	Lib.IsCtrlDown = function()
		return service.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or service.UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	Lib.CreateArrow = function(size, num, dir)
		local max = num
		local arrowFrame = createSimple("Frame", {
			BackgroundTransparency = 1,
			Name = "Arrow",
			Size = UDim2.new(0, size, 0, size),
		})
		if dir == "up" then
			for i = 1, num do
				local newLine = createSimple("Frame", {
					BackgroundColor3 = Color3.new(220 / 255, 220 / 255, 220 / 255),
					BorderSizePixel = 0,
					Position = UDim2.new(
						0,
						math.floor(size / 2) - (i - 1),
						0,
						math.floor(size / 2) + i - math.floor(max / 2) - 1
					),
					Size = UDim2.new(0, i + (i - 1), 0, 1),
					Parent = arrowFrame,
				})
			end
			return arrowFrame
		elseif dir == "down" then
			for i = 1, num do
				local newLine = createSimple("Frame", {
					BackgroundColor3 = Color3.new(220 / 255, 220 / 255, 220 / 255),
					BorderSizePixel = 0,
					Position = UDim2.new(
						0,
						math.floor(size / 2) - (i - 1),
						0,
						math.floor(size / 2) - i + math.floor(max / 2) + 1
					),
					Size = UDim2.new(0, i + (i - 1), 0, 1),
					Parent = arrowFrame,
				})
			end
			return arrowFrame
		elseif dir == "left" then
			for i = 1, num do
				local newLine = createSimple("Frame", {
					BackgroundColor3 = Color3.new(220 / 255, 220 / 255, 220 / 255),
					BorderSizePixel = 0,
					Position = UDim2.new(
						0,
						math.floor(size / 2) + i - math.floor(max / 2) - 1,
						0,
						math.floor(size / 2) - (i - 1)
					),
					Size = UDim2.new(0, 1, 0, i + (i - 1)),
					Parent = arrowFrame,
				})
			end
			return arrowFrame
		elseif dir == "right" then
			for i = 1, num do
				local newLine = createSimple("Frame", {
					BackgroundColor3 = Color3.new(220 / 255, 220 / 255, 220 / 255),
					BorderSizePixel = 0,
					Position = UDim2.new(
						0,
						math.floor(size / 2) - i + math.floor(max / 2) + 1,
						0,
						math.floor(size / 2) - (i - 1)
					),
					Size = UDim2.new(0, 1, 0, i + (i - 1)),
					Parent = arrowFrame,
				})
			end
			return arrowFrame
		end
		error("r u ok")
	end

	Lib.ParseXML = (function()
		local func = function()

			local string, print, pairs = string, print, pairs

			-- http://lua-users.org/wiki/StringTrim
			local trim = function(s)
				local from = s:match("^%s*()")
				return from > #s and "" or s:match(".*%S", from)
			end

			local gtchar = string.byte(">", 1)
			local slashchar = string.byte("/", 1)
			local D = string.byte("D", 1)
			local E = string.byte("E", 1)

			function parse(s, evalEntities)
				s = s:gsub("<!%-%-(.-)%-%->", "")

				local entities, tentities = {}

				if evalEntities then
					local pos = s:find("<[_%w]")
					if pos then
						s:sub(1, pos):gsub("<!ENTITY%s+([_%w]+)%s+(.)(.-)%2", function(name, q, entity)
							entities[#entities + 1] = { name = name, value = entity }
						end)
						tentities = createEntityTable(entities)
						s = replaceEntities(s:sub(pos), tentities)
					end
				end

				local t, l = {}, {}

				local addtext = function(txt)
					local first = string.find(txt, "%S")
					if first then
						t[#t + 1] = { text = string.match(txt, ".*%S", first) }
					end
				end

				for type, name, closed, txt in string.gmatch(s, "<([?!/]?)([-:_%w]+)%s*(/?>?)([^<]*)") do
					if #type == 0 then
						local a = {}
						if #closed == 0 then
							local len = 0
							for all, aname, _, value, starttxt in
								string.gmatch(txt, "(.-([-_%w]+)%s*=%s*(.)(.-)%3%s*(/?>?))")
							do
								len = len + #all
								a[aname] = value
								if #starttxt ~= 0 then
									txt = txt:sub(len + 1)
									closed = starttxt
									break
								end
							end
						end
						t[#t + 1] = { tag = name, attrs = a, children = {} }

						if closed:byte(1) ~= slashchar then
							l[#l + 1] = t
							t = t[#t].children
						end

						addtext(txt)
					elseif "/" == type then
						t = l[#l]
						l[#l] = nil

						addtext(txt)
					elseif "!" == type then
						if E == name:byte(1) then
							txt:gsub("([_%w]+)%s+(.)(.-)%2", function(name, q, entity)
								entities[#entities + 1] = { name = name, value = entity }
							end, 1)
						end
					end
				end

				return { children = t, entities = entities, tentities = tentities }
			end

			function parseText(txt)
				return parse(txt)
			end

			function defaultEntityTable()
				return { quot = '"', apos = "'", lt = "<", gt = ">", amp = "&", tab = "\t", nbsp = " " }
			end

			function replaceEntities(s, entities)
				return s:gsub("&([^;]+);", entities)
			end

			function createEntityTable(docEntities, resultEntities)
				entities = resultEntities or defaultEntityTable()
				for _, e in pairs(docEntities) do
					e.value = replaceEntities(e.value, entities)
					entities[e.name] = e.value
				end
				return entities
			end

			return parseText
		end
		local newEnv = setmetatable({}, { __index = getfenv() })
		setfenv(func, newEnv)
		return func()
	end)()

	Lib.FastWait = function(s)
		if not s then
			return signalWait(renderStepped)
		end
		local start = tick()
		while tick() - start < s do
			signalWait(renderStepped)
		end
	end

	Lib.ButtonAnim = function(button, data)
		local holding = false
		local disabled = false
		local mode = data and data.Mode or 1
		local control = {}

		if mode == 2 then
			local lerpTo = data.LerpTo or Color3.new(0, 0, 0)
			local delta = data.LerpDelta or 0.2
			control.StartColor = data.StartColor or button.BackgroundColor3
			control.PressColor = data.PressColor or control.StartColor:lerp(lerpTo, delta)
			control.HoverColor = data.HoverColor or control.StartColor:lerp(control.PressColor, 0.6)
			control.OutlineColor = data.OutlineColor
		end

		button.InputBegan:Connect(function(input)
			if disabled then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if not holding then
					if mode == 1 then
						button.BackgroundTransparency = 0.4
					elseif mode == 2 then
						button.BackgroundColor3 = control.HoverColor
					end
				end
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				holding = true
				if mode == 1 then
					button.BackgroundTransparency = 0
				elseif mode == 2 then
					button.BackgroundColor3 = control.PressColor
					if control.OutlineColor then
						button.BorderColor3 = control.PressColor
					end
				end
			end
		end)

		button.InputEnded:Connect(function(input)
			if disabled then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if not holding then
					if mode == 1 then
						button.BackgroundTransparency = 1
					elseif mode == 2 then
						button.BackgroundColor3 = control.StartColor
					end
				end
			elseif
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				holding = false
				if mode == 1 then
					button.BackgroundTransparency = Lib.CheckMouseInGui(button) and 0.4 or 1
				elseif mode == 2 then
					button.BackgroundColor3 = Lib.CheckMouseInGui(button) and control.HoverColor or control.StartColor
					if control.OutlineColor then
						button.BorderColor3 = control.OutlineColor
					end
				end
			end
		end)

		control.Disable = function()
			disabled = true
			holding = false

			if mode == 1 then
				button.BackgroundTransparency = 1
			elseif mode == 2 then
				button.BackgroundColor3 = control.StartColor
			end
		end

		control.Enable = function()
			disabled = false
		end

		return control
	end

	Lib.FindAndRemove = function(t, item)
		local pos = table.find(t, item)
		if pos then
			table.remove(t, pos)
		end
	end

	Lib.AttachTo = function(obj, data)
		local target, posOffX, posOffY, sizeOffX, sizeOffY, resize, con
		local disabled = false

		local function update()
			if not obj or not target then
				return
			end

			local targetPos = target.AbsolutePosition
			local targetSize = target.AbsoluteSize
			obj.Position = UDim2.new(0, targetPos.X + posOffX, 0, targetPos.Y + posOffY)
			if resize then
				obj.Size = UDim2.new(0, targetSize.X + sizeOffX, 0, targetSize.Y + sizeOffY)
			end
		end

		local function setup(o, data)
			obj = o
			data = data or {}
			target = data.Target
			posOffX = data.PosOffX or 0
			posOffY = data.PosOffY or 0
			sizeOffX = data.SizeOffX or 0
			sizeOffY = data.SizeOffY or 0
			resize = data.Resize or false

			if con then
				con:Disconnect()
				con = nil
			end
			if target then
				con = target.Changed:Connect(function(prop)
					if not disabled and prop == "AbsolutePosition" or prop == "AbsoluteSize" then
						update()
					end
				end)
			end

			update()
		end
		setup(obj, data)

		return {
			SetData = function(obj, data)
				setup(obj, data)
			end,
			Enable = function()
				disabled = false
				update()
			end,
			Disable = function()
				disabled = true
			end,
			Destroy = function()
				con:Disconnect()
				con = nil
			end,
		}
	end

	Lib.ProtectedGuis = {}

	Lib.ShowGui = Main.SecureGui

	Lib.ColorToBytes = function(col)
		local round = math.round
		return string.format("%d, %d, %d", round(col.r * 255), round(col.g * 255), round(col.b * 255))
	end

	Lib.ReadFile = function(filename)
		if not env.readfile then
			return
		end

		local s, contents = pcall(env.readfile, filename)
		if s and contents then
			return contents
		end
	end

	Lib.DeferFunc = function(f, ...)
		signalWait(renderStepped)
		return f(...)
	end

	Lib.LoadCustomAsset = function(filepath)
		if not env.getcustomasset or not env.isfile or not env.isfile(filepath) then
			return
		end

		return env.getcustomasset(filepath)
	end

	Lib.FetchCustomAsset = function(url, filepath)
		if not env.writefile then
			return
		end

		local s, data = pcall(oldgame.HttpGet, game, url)
		if not s then
			return
		end

		env.writefile(filepath, data)
		return Lib.LoadCustomAsset(filepath)
	end

	Lib.SaveAsPrompt = function(filename, codeToSave, ext)
		local d = Apps.StudioPopup.Open("Save As",222)
		local box = d.input("File name",filename or "",52)
		local function save()
			local name = box.Text
			local extension = ext or name:match("%.([^%./\\]+)$") or "txt"
			name = name:gsub("%.[^%./\\]+$", "") .. "." .. extension
			if type(codeToSave) == "function" then
				codeToSave(name)
			else
				assert(env.writefile, "This executor does not support writing files")
				env.writefile(name,codeToSave)
			end
		end
		d.bindForm(box,"Save",function() return box.Text ~= "" end,save)
		box:CaptureFocus()
	end

	Lib.Signal = (function()
		local funcs = {}

		local disconnect = function(con)
			con.Connected = false
			local pos = table.find(con.Signal.Connections, con)
			if pos then
				table.remove(con.Signal.Connections, pos)
			end
		end

		funcs.Connect = function(self, func)
			if type(func) ~= "function" then
				error("Attempt to connect a non-function")
			end
			local con = {
				Signal = self,
				Func = func,
				Connected = true,
				Disconnect = disconnect,
			}
			self.Connections[#self.Connections + 1] = con
			return con
		end

		funcs.Fire = function(self, ...)
			if #self.Connections == 0 then
				return
			end
			for _, connection in ipairs(table.clone(self.Connections)) do
				if connection.Connected then
					xpcall(coroutine.wrap(connection.Func), function(e)
						warn(tostring(e) .. "\n" .. debug.traceback())
					end, ...)
				end
			end
		end

		local mt = {
			__index = funcs,
			__tostring = function(self)
				return "Signal: " .. tostring(#self.Connections) .. " Connections"
			end,
		}

		local function new()
			local obj = {}
			obj.Connections = {}

			return setmetatable(obj, mt)
		end

		return { new = new }
	end)()

	Lib.Set = (function()
		local funcs = {}

		funcs.Add = function(self, obj)
			if self.Map[obj] then
				return
			end

			local list = self.List
			list[#list + 1] = obj
			self.Map[obj] = true
			self.Changed:Fire()
		end

		funcs.AddTable = function(self, t)
			local changed
			local list, map = self.List, self.Map
			for i = 1, #t do
				local elem = t[i]
				if not map[elem] then
					list[#list + 1] = elem
					map[elem] = true
					changed = true
				end
			end
			if changed then
				self.Changed:Fire()
			end
		end

		funcs.Remove = function(self, obj)
			if not self.Map[obj] then
				return
			end

			local list = self.List
			local pos = table.find(list, obj)
			if pos then
				table.remove(list, pos)
			end
			self.Map[obj] = nil
			self.Changed:Fire()
		end

		funcs.RemoveTable = function(self, t)
			local changed
			local list, map = self.List, self.Map
			local removeSet = {}
			for i = 1, #t do
				local elem = t[i]
				map[elem] = nil
				removeSet[elem] = true
			end

			for i = #list, 1, -1 do
				local elem = list[i]
				if removeSet[elem] then
					table.remove(list, i)
					changed = true
				end
			end
			if changed then
				self.Changed:Fire()
			end
		end

		funcs.Set = function(self, obj)
			if #self.List == 1 and self.List[1] == obj then
				return
			end

			self.List = { obj }
			self.Map = { [obj] = true }
			self.Changed:Fire()
		end

		funcs.SetTable = function(self, t)
			if #self.List == #t then
				local same = true
				for i, item in ipairs(t) do
					if self.List[i] ~= item then
						same = false
						break
					end
				end
				if same then
					return false
				end
			end
			local newList, newMap = {}, {}
			for i = 1, #t do
				local item = t[i]
				if not newMap[item] then
					newList[#newList + 1] = item
					newMap[item] = true
				end
			end
			local same = #self.List == #newList
			if same then
				for i, item in ipairs(newList) do
					if self.List[i] ~= item then
						same = false
						break
					end
				end
			end
			if same then
				return false
			end
			self.List, self.Map = newList, newMap
			self.Changed:Fire()
			return true
		end

		funcs.Clear = function(self)
			if #self.List == 0 then
				return
			end
			self.List = {}
			self.Map = {}
			self.Changed:Fire()
		end

		local mt = { __index = funcs }

		local function new()
			local obj = setmetatable({
				List = {},
				Map = {},
				Changed = Lib.Signal.new(),
			}, mt)

			return obj
		end

		return { new = new }
	end)()

	Lib.IconMap = (function()
		local funcs = {}
		local IconList = {
			Old = {
				MapId = 483448923,
				IconSize = 16,
				Witdh = 16,
				Height = 16,
				Icons = {
					["Accessory"] = 32,
					["Accoutrement"] = 32,
					["AdService"] = 73,
					["Animation"] = 60,
					["AnimationController"] = 60,
					["AnimationTrack"] = 60,
					["Animator"] = 60,
					["ArcHandles"] = 56,
					["AssetService"] = 72,
					["Attachment"] = 34,
					["Backpack"] = 20,
					["BadgeService"] = 75,
					["BallSocketConstraint"] = 89,
					["BillboardGui"] = 64,
					["BinaryStringValue"] = 4,
					["BindableEvent"] = 67,
					["BindableFunction"] = 66,
					["BlockMesh"] = 8,
					["BloomEffect"] = 90,
					["BlurEffect"] = 90,
					["BodyAngularVelocity"] = 14,
					["BodyForce"] = 14,
					["BodyGyro"] = 14,
					["BodyPosition"] = 14,
					["BodyThrust"] = 14,
					["BodyVelocity"] = 14,
					["BoolValue"] = 4,
					["BoxHandleAdornment"] = 54,
					["BrickColorValue"] = 4,
					["Camera"] = 5,
					["CFrameValue"] = 4,
					["CharacterMesh"] = 60,
					["Chat"] = 33,
					["ClickDetector"] = 41,
					["CollectionService"] = 30,
					["Color3Value"] = 4,
					["ColorCorrectionEffect"] = 90,
					["ConeHandleAdornment"] = 54,
					["Configuration"] = 58,
					["ContentProvider"] = 72,
					["ContextActionService"] = 41,
					["CoreGui"] = 46,
					["CoreScript"] = 18,
					["CornerWedgePart"] = 1,
					["CustomEvent"] = 4,
					["CustomEventReceiver"] = 4,
					["CylinderHandleAdornment"] = 54,
					["CylinderMesh"] = 8,
					["CylindricalConstraint"] = 89,
					["Debris"] = 30,
					["Decal"] = 7,
					["Dialog"] = 62,
					["DialogChoice"] = 63,
					["DoubleConstrainedValue"] = 4,
					["Explosion"] = 36,
					["FileMesh"] = 8,
					["Fire"] = 61,
					["Flag"] = 38,
					["FlagStand"] = 39,
					["FloorWire"] = 4,
					["Folder"] = 70,
					["ForceField"] = 37,
					["Frame"] = 48,
					["GamePassService"] = 19,
					["Glue"] = 34,
					["GuiButton"] = 52,
					["GuiMain"] = 47,
					["GuiService"] = 47,
					["Handles"] = 53,
					["HapticService"] = 84,
					["Hat"] = 45,
					["HingeConstraint"] = 89,
					["Hint"] = 33,
					["HopperBin"] = 22,
					["HttpService"] = 76,
					["Humanoid"] = 9,
					["ImageButton"] = 52,
					["ImageLabel"] = 49,
					["InsertService"] = 72,
					["IntConstrainedValue"] = 4,
					["IntValue"] = 4,
					["JointInstance"] = 34,
					["JointsService"] = 34,
					["Keyframe"] = 60,
					["KeyframeSequence"] = 60,
					["KeyframeSequenceProvider"] = 60,
					["Lighting"] = 13,
					["LineHandleAdornment"] = 54,
					["LocalScript"] = 18,
					["LogService"] = 87,
					["MarketplaceService"] = 46,
					["Message"] = 33,
					["Model"] = 2,
					["ModuleScript"] = 71,
					["Motor"] = 34,
					["Motor6D"] = 34,
					["MoveToConstraint"] = 89,
					["NegateOperation"] = 78,
					["NetworkClient"] = 16,
					["NetworkReplicator"] = 29,
					["NetworkServer"] = 15,
					["NumberValue"] = 4,
					["ObjectValue"] = 4,
					["Pants"] = 44,
					["ParallelRampPart"] = 1,
					["Part"] = 1,
					["ParticleEmitter"] = 69,
					["PartPairLasso"] = 57,
					["PathfindingService"] = 37,
					["Platform"] = 35,
					["Player"] = 12,
					["PlayerGui"] = 46,
					["Players"] = 21,
					["PlayerScripts"] = 82,
					["PointLight"] = 13,
					["PointsService"] = 83,
					["Pose"] = 60,
					["PrismaticConstraint"] = 89,
					["PrismPart"] = 1,
					["PyramidPart"] = 1,
					["RayValue"] = 4,
					["ReflectionMetadata"] = 86,
					["ReflectionMetadataCallbacks"] = 86,
					["ReflectionMetadataClass"] = 86,
					["ReflectionMetadataClasses"] = 86,
					["ReflectionMetadataEnum"] = 86,
					["ReflectionMetadataEnumItem"] = 86,
					["ReflectionMetadataEnums"] = 86,
					["ReflectionMetadataEvents"] = 86,
					["ReflectionMetadataFunctions"] = 86,
					["ReflectionMetadataMember"] = 86,
					["ReflectionMetadataProperties"] = 86,
					["ReflectionMetadataYieldFunctions"] = 86,
					["RemoteEvent"] = 80,
					["RemoteFunction"] = 79,
					["ReplicatedFirst"] = 72,
					["ReplicatedStorage"] = 72,
					["RightAngleRampPart"] = 1,
					["RocketPropulsion"] = 14,
					["RodConstraint"] = 89,
					["RopeConstraint"] = 89,
					["Rotate"] = 34,
					["RotateP"] = 34,
					["RotateV"] = 34,
					["RunService"] = 66,
					["ScreenGui"] = 47,
					["Script"] = 6,
					["ScrollingFrame"] = 48,
					["Seat"] = 35,
					["Selection"] = 55,
					["SelectionBox"] = 54,
					["SelectionPartLasso"] = 57,
					["SelectionPointLasso"] = 57,
					["SelectionSphere"] = 54,
					["ServerScriptService"] = 0,
					["ServerStorage"] = 74,
					["Shirt"] = 43,
					["ShirtGraphic"] = 40,
					["SkateboardPlatform"] = 35,
					["Sky"] = 28,
					["SlidingBallConstraint"] = 89,
					["Smoke"] = 59,
					["Snap"] = 34,
					["Sound"] = 11,
					["SoundService"] = 31,
					["Sparkles"] = 42,
					["SpawnLocation"] = 25,
					["SpecialMesh"] = 8,
					["SphereHandleAdornment"] = 54,
					["SpotLight"] = 13,
					["SpringConstraint"] = 89,
					["StarterCharacterScripts"] = 82,
					["StarterGear"] = 20,
					["StarterGui"] = 46,
					["StarterPack"] = 20,
					["StarterPlayer"] = 88,
					["StarterPlayerScripts"] = 82,
					["Status"] = 2,
					["StringValue"] = 4,
					["SunRaysEffect"] = 90,
					["SurfaceGui"] = 64,
					["SurfaceLight"] = 13,
					["SurfaceSelection"] = 55,
					["Team"] = 24,
					["Teams"] = 23,
					["TeleportService"] = 81,
					["Terrain"] = 65,
					["TerrainRegion"] = 65,
					["TestService"] = 68,
					["TextBox"] = 51,
					["TextButton"] = 51,
					["TextLabel"] = 50,
					["Texture"] = 10,
					["TextureTrail"] = 4,
					["Tool"] = 17,
					["TouchTransmitter"] = 37,
					["TrussPart"] = 1,
					["UnionOperation"] = 77,
					["UserInputService"] = 84,
					["Vector3Value"] = 4,
					["VehicleSeat"] = 35,
					["VelocityMotor"] = 34,
					["WedgePart"] = 1,
					["Weld"] = 34,
					["Workspace"] = 19,
				},
			},
			Vanilla3 = {
				MapId = 114851699900089,
				IconSize = 32,
				Witdh = 25,
				Height = 25,
				Icons = {
					Accessory = 1,
					Accoutrement = 2,
					Actor = 3,
					AdGui = 4,
					AdPortal = 5,
					AdService = 6,
					AdvancedDragger = 7,
					AirController = 8,
					AlignOrientation = 9,
					AlignPosition = 10,
					AnalysticsService = 11,
					AnalysticsSettings = 12,
					AnalyticsService = 13,
					AngularVelocity = 14,
					Animation = 15,
					AnimationClip = 16,
					AnimationClipProvider = 17,
					AnimationController = 18,
					AnimationFromVideoCreatorService = 19,
					AnimationFromVideoCreatorStudioService = 20,
					AnimationRigData = 21,
					AnimationStreamTrack = 22,
					AnimationTrack = 23,
					Animator = 24,
					AppStorageService = 25,
					AppUpdateService = 26,
					ArcHandles = 27,
					AssetCounterService = 28,
					AssetDeliveryProxy = 29,
					AssetImportService = 30,
					AssetImportSession = 31,
					AssetManagerService = 32,
					AssetService = 33,
					AssetSoundEffect = 34,
					Atmosphere = 35,
					Attachment = 36,
					AvatarEditorService = 37,
					AvatarImportService = 38,
					Backpack = 39,
					BackpackItem = 40,
					BadgeService = 41,
					BallSocketConstraint = 42,
					BasePart = 43,
					BasePlayerGui = 44,
					BaseScript = 45,
					BaseWrap = 46,
					Beam = 47,
					BevelMesh = 48,
					BillboardGui = 49,
					BinaryStringValue = 50,
					BindableEvent = 51,
					BindableFunction = 52,
					BlockMesh = 53,
					BloomEffect = 54,
					BlurEffect = 55,
					BodyAngularVelocity = 56,
					BodyColors = 57,
					BodyForce = 58,
					BodyGyro = 59,
					BodyMover = 60,
					BodyPosition = 61,
					BodyThrust = 62,
					BodyVelocity = 63,
					Bone = 64,
					BoolValue = 65,
					BoxHandleAdornment = 66,
					Breakpoint = 67,
					BreakpointManager = 68,
					BrickColorValue = 69,
					BrowserService = 70,
					BubbleChatConfiguration = 71,
					BulkImportService = 72,
					CacheableContentProvider = 73,
					CalloutService = 74,
					Camera = 75,
					CanvasGroup = 76,
					CatalogPages = 77,
					CFrameValue = 78,
					ChangeHistoryService = 79,
					ChannelSelectorSoundEffect = 80,
					CharacterAppearance = 81,
					CharacterMesh = 82,
					Chat = 83,
					ChatInputBarConfiguration = 84,
					ChatWindowConfiguration = 85,
					ChorusSoundEffect = 86,
					ClickDetector = 87,
					ClientReplicator = 88,
					ClimbController = 89,
					Clothing = 90,
					Clouds = 91,
					ClusterPacketCache = 92,
					CollectionService = 93,
					Color3Value = 94,
					ColorCorrectionEffect = 95,
					CommandInstance = 96,
					CommandService = 97,
					CompressorSoundEffect = 98,
					ConeHandleAdornment = 99,
					Configuration = 100,
					ConfigureServerService = 101,
					Constraint = 102,
					ContentProvider = 103,
					ContextActionService = 104,
					Controller = 105,
					ControllerBase = 106,
					ControllerManager = 107,
					ControllerService = 108,
					CookiesService = 109,
					CoreGui = 110,
					CorePackages = 111,
					CoreScript = 112,
					CoreScriptSyncService = 113,
					CornerWedgePart = 114,
					CrossDMScriptChangeListener = 115,
					CSGDictionaryService = 116,
					CurveAnimation = 117,
					CustomEvent = 118,
					CustomEventReceiver = 119,
					CustomSoundEffect = 120,
					CylinderHandleAdornment = 121,
					CylinderMesh = 122,
					CylindricalConstraint = 123,
					DataModel = 124,
					DataModelMesh = 125,
					DataModelPatchService = 126,
					DataModelSession = 127,
					DataStore = 128,
					DataStoreIncrementOptions = 129,
					DataStoreInfo = 130,
					DataStoreKey = 131,
					DataStoreKeyInfo = 132,
					DataStoreKeyPages = 133,
					DataStoreListingPages = 134,
					DataStoreObjectVersionInfo = 135,
					DataStoreOptions = 136,
					DataStorePages = 137,
					DataStoreService = 138,
					DataStoreSetOptions = 139,
					DataStoreVersionPages = 140,
					Debris = 141,
					DebuggablePluginWatcher = 142,
					DebuggerBreakpoint = 143,
					DebuggerConnection = 144,
					DebuggerConnectionManager = 145,
					DebuggerLuaResponse = 146,
					DebuggerManager = 147,
					DebuggerUIService = 148,
					DebuggerVariable = 149,
					DebuggerWatch = 150,
					DebugSettings = 151,
					Decal = 152,
					DepthOfFieldEffect = 153,
					DeviceIdService = 154,
					Dialog = 155,
					DialogChoice = 156,
					DistortionSoundEffect = 157,
					DockWidgetPluginGui = 158,
					DoubleConstrainedValue = 159,
					DraftsService = 160,
					Dragger = 161,
					DraggerService = 162,
					DynamicRotate = 163,
					EchoSoundEffect = 164,
					EmotesPages = 165,
					EqualizerSoundEffect = 166,
					EulerRotationCurve = 167,
					EventIngestService = 168,
					Explosion = 169,
					FaceAnimatorService = 170,
					FaceControls = 171,
					FaceInstance = 172,
					FacialAnimationRecordingService = 173,
					FacialAnimationStreamingService = 174,
					Feature = 175,
					File = 176,
					FileMesh = 177,
					Fire = 178,
					Flag = 179,
					FlagStand = 180,
					FlagStandService = 181,
					FlangeSoundEffect = 182,
					FloatCurve = 183,
					FloorWire = 184,
					FlyweightService = 185,
					Folder = 186,
					ForceField = 187,
					FormFactorPart = 188,
					Frame = 189,
					FriendPages = 190,
					FriendService = 191,
					FunctionalTest = 192,
					GamepadService = 193,
					GamePassService = 194,
					GameSettings = 195,
					GenericSettings = 196,
					Geometry = 197,
					GetTextBoundsParams = 198,
					GlobalDataStore = 199,
					GlobalSettings = 200,
					Glue = 201,
					GoogleAnalyticsConfiguration = 202,
					GroundController = 203,
					GroupService = 204,
					GuiBase = 205,
					GuiBase2d = 206,
					GuiBase3d = 207,
					GuiButton = 208,
					GuidRegistryService = 209,
					GuiLabel = 210,
					GuiMain = 211,
					GuiObject = 212,
					GuiService = 213,
					HandleAdornment = 214,
					Handles = 215,
					HandlesBase = 216,
					HapticService = 217,
					Hat = 218,
					HeightmapImporterService = 219,
					HiddenSurfaceRemovalAsset = 220,
					Highlight = 221,
					HingeConstraint = 222,
					Hint = 223,
					Hole = 224,
					Hopper = 225,
					HopperBin = 226,
					HSRDataContentProvider = 227,
					HttpRbxApiService = 228,
					HttpRequest = 229,
					HttpService = 230,
					Humanoid = 231,
					HumanoidController = 232,
					HumanoidDescription = 233,
					IKControl = 234,
					ILegacyStudioBridge = 235,
					ImageButton = 236,
					ImageHandleAdornment = 237,
					ImageLabel = 238,
					ImporterAnimationSettings = 239,
					ImporterBaseSettings = 240,
					ImporterFacsSettings = 241,
					ImporterGroupSettings = 242,
					ImporterJointSettings = 243,
					ImporterMaterialSettings = 244,
					ImporterMeshSettings = 245,
					ImporterRootSettings = 246,
					IncrementalPatchBuilder = 247,
					InputObject = 248,
					InsertService = 249,
					Instance = 250,
					InstanceAdornment = 251,
					IntConstrainedValue = 252,
					IntValue = 253,
					InventoryPages = 254,
					IXPService = 255,
					JointInstance = 256,
					JointsService = 257,
					KeyboardService = 258,
					Keyframe = 259,
					KeyframeMarker = 260,
					KeyframeSequence = 261,
					KeyframeSequenceProvider = 262,
					LanguageService = 263,
					LayerCollector = 264,
					LegacyStudioBridge = 265,
					Light = 266,
					Lighting = 267,
					LinearVelocity = 268,
					LineForce = 269,
					LineHandleAdornment = 270,
					LocalDebuggerConnection = 271,
					LocalizationService = 272,
					LocalizationTable = 273,
					LocalScript = 274,
					LocalStorageService = 275,
					LodDataEntity = 276,
					LodDataService = 277,
					LoginService = 278,
					LogService = 279,
					LSPFileSyncService = 280,
					LuaSettings = 281,
					LuaSourceContainer = 282,
					LuauScriptAnalyzerService = 283,
					LuaWebService = 284,
					ManualGlue = 285,
					ManualSurfaceJointInstance = 286,
					ManualWeld = 287,
					MarkerCurve = 288,
					MarketplaceService = 289,
					MaterialService = 290,
					MaterialVariant = 291,
					MemoryStoreQueue = 292,
					MemoryStoreService = 293,
					MemoryStoreSortedMap = 294,
					MemStorageConnection = 295,
					MemStorageService = 296,
					MeshContentProvider = 297,
					MeshPart = 298,
					Message = 299,
					MessageBusConnection = 300,
					MessageBusService = 301,
					MessagingService = 302,
					MetaBreakpoint = 303,
					MetaBreakpointContext = 304,
					MetaBreakpointManager = 305,
					Model = 306,
					ModuleScript = 307,
					Motor = 308,
					Motor6D = 309,
					MotorFeature = 310,
					Mouse = 311,
					MouseService = 312,
					MultipleDocumentInterfaceInstance = 313,
					NegateOperation = 314,
					NetworkClient = 315,
					NetworkMarker = 316,
					NetworkPeer = 317,
					NetworkReplicator = 318,
					NetworkServer = 319,
					NetworkSettings = 320,
					NoCollisionConstraint = 321,
					NonReplicatedCSGDictionaryService = 322,
					NotificationService = 323,
					NumberPose = 324,
					NumberValue = 325,
					ObjectValue = 326,
					OrderedDataStore = 327,
					OutfitPages = 328,
					PackageLink = 329,
					PackageService = 330,
					PackageUIService = 331,
					Pages = 332,
					Pants = 333,
					ParabolaAdornment = 334,
					Part = 335,
					PartAdornment = 336,
					ParticleEmitter = 337,
					PartOperation = 338,
					PartOperationAsset = 339,
					PatchMapping = 340,
					Path = 341,
					PathfindingLink = 342,
					PathfindingModifier = 343,
					PathfindingService = 344,
					PausedState = 345,
					PausedStateBreakpoint = 346,
					PausedStateException = 347,
					PermissionsService = 348,
					PhysicsService = 349,
					PhysicsSettings = 350,
					PitchShiftSoundEffect = 351,
					Plane = 352,
					PlaneConstraint = 353,
					Platform = 354,
					Player = 355,
					PlayerEmulatorService = 356,
					PlayerGui = 357,
					PlayerMouse = 358,
					Players = 359,
					PlayerScripts = 360,
					Plugin = 361,
					PluginAction = 362,
					PluginDebugService = 363,
					PluginDragEvent = 364,
					PluginGui = 365,
					PluginGuiService = 366,
					PluginManagementService = 367,
					PluginManager = 368,
					PluginManagerInterface = 369,
					PluginMenu = 370,
					PluginMouse = 371,
					PluginPolicyService = 372,
					PluginToolbar = 373,
					PluginToolbarButton = 374,
					PointLight = 375,
					PointsService = 376,
					PolicyService = 377,
					Pose = 378,
					PoseBase = 379,
					PostEffect = 380,
					PrismaticConstraint = 381,
					ProcessInstancePhysicsService = 382,
					ProximityPrompt = 383,
					ProximityPromptService = 384,
					PublishService = 385,
					PVAdornment = 386,
					PVInstance = 387,
					QWidgetPluginGui = 388,
					RayValue = 389,
					RbxAnalyticsService = 390,
					ReflectionMetadata = 391,
					ReflectionMetadataCallbacks = 392,
					ReflectionMetadataClass = 393,
					ReflectionMetadataClasses = 394,
					ReflectionMetadataEnum = 395,
					ReflectionMetadataEnumItem = 396,
					ReflectionMetadataEnums = 397,
					ReflectionMetadataEvents = 398,
					ReflectionMetadataFunctions = 399,
					ReflectionMetadataItem = 400,
					ReflectionMetadataMember = 401,
					ReflectionMetadataProperties = 402,
					ReflectionMetadataYieldFunctions = 403,
					RemoteDebuggerServer = 404,
					RemoteEvent = 405,
					RemoteFunction = 406,
					RenderingTest = 407,
					RenderSettings = 408,
					ReplicatedFirst = 409,
					ReplicatedStorage = 410,
					ReverbSoundEffect = 411,
					RigidConstraint = 412,
					RobloxPluginGuiService = 413,
					RobloxReplicatedStorage = 414,
					RocketPropulsion = 415,
					RodConstraint = 416,
					RopeConstraint = 417,
					Rotate = 418,
					RotateP = 419,
					RotateV = 420,
					RotationCurve = 421,
					RtMessagingService = 422,
					RunningAverageItemDouble = 423,
					RunningAverageItemInt = 424,
					RunningAverageTimeIntervalItem = 425,
					RunService = 426,
					RuntimeScriptService = 427,
					ScreenGui = 428,
					ScreenshotHud = 429,
					Script = 430,
					ScriptChangeService = 431,
					ScriptCloneWatcher = 432,
					ScriptCloneWatcherHelper = 433,
					ScriptContext = 434,
					ScriptDebugger = 435,
					ScriptDocument = 436,
					ScriptEditorService = 437,
					ScriptRegistrationService = 438,
					ScriptService = 439,
					ScrollingFrame = 440,
					Seat = 441,
					Selection = 442,
					SelectionBox = 443,
					SelectionLasso = 444,
					SelectionPartLasso = 445,
					SelectionPointLasso = 446,
					SelectionSphere = 447,
					ServerReplicator = 448,
					ServerScriptService = 449,
					ServerStorage = 450,
					ServiceProvider = 451,
					SessionService = 452,
					Shirt = 453,
					ShirtGraphic = 454,
					SkateboardController = 455,
					SkateboardPlatform = 456,
					Skin = 457,
					Sky = 458,
					SlidingBallConstraint = 459,
					Smoke = 460,
					Snap = 461,
					SnippetService = 462,
					SocialService = 463,
					SolidModelContentProvider = 464,
					Sound = 465,
					SoundEffect = 466,
					SoundGroup = 467,
					SoundService = 468,
					Sparkles = 469,
					SpawnerService = 470,
					SpawnLocation = 471,
					Speaker = 472,
					SpecialMesh = 473,
					SphereHandleAdornment = 474,
					SpotLight = 475,
					SpringConstraint = 476,
					StackFrame = 477,
					StandalonePluginScripts = 478,
					StandardPages = 479,
					StarterCharacterScripts = 480,
					StarterGear = 481,
					StarterGui = 482,
					StarterPack = 483,
					StarterPlayer = 484,
					StarterPlayerScripts = 485,
					Stats = 486,
					StatsItem = 487,
					Status = 488,
					StopWatchReporter = 489,
					StringValue = 490,
					Studio = 491,
					StudioAssetService = 492,
					StudioData = 493,
					StudioDeviceEmulatorService = 494,
					StudioHighDpiService = 495,
					StudioPublishService = 496,
					StudioScriptDebugEventListener = 497,
					StudioService = 498,
					StudioTheme = 499,
					SunRaysEffect = 500,
					SurfaceAppearance = 501,
					SurfaceGui = 502,
					SurfaceGuiBase = 503,
					SurfaceLight = 504,
					SurfaceSelection = 505,
					SwimController = 506,
					TaskScheduler = 507,
					Team = 508,
					TeamCreateService = 509,
					Teams = 510,
					TeleportAsyncResult = 511,
					TeleportOptions = 512,
					TeleportService = 513,
					TemporaryCageMeshProvider = 514,
					TemporaryScriptService = 515,
					Terrain = 516,
					TerrainDetail = 517,
					TerrainRegion = 518,
					TestService = 519,
					TextBox = 520,
					TextBoxService = 521,
					TextButton = 522,
					TextChannel = 523,
					TextChatCommand = 524,
					TextChatConfigurations = 525,
					TextChatMessage = 526,
					TextChatMessageProperties = 527,
					TextChatService = 528,
					TextFilterResult = 529,
					TextLabel = 530,
					TextService = 531,
					TextSource = 532,
					Texture = 533,
					ThirdPartyUserService = 534,
					ThreadState = 535,
					TimerService = 536,
					ToastNotificationService = 537,
					Tool = 538,
					ToolboxService = 539,
					Torque = 540,
					TorsionSpringConstraint = 541,
					TotalCountTimeIntervalItem = 542,
					TouchInputService = 543,
					TouchTransmitter = 544,
					TracerService = 545,
					TrackerStreamAnimation = 546,
					Trail = 547,
					Translator = 548,
					TremoloSoundEffect = 549,
					TriangleMeshPart = 550,
					TrussPart = 551,
					Tween = 552,
					TweenBase = 553,
					TweenService = 554,
					UGCValidationService = 555,
					UIAspectRatioConstraint = 556,
					UIBase = 557,
					UIComponent = 558,
					UIConstraint = 559,
					UICorner = 560,
					UIGradient = 561,
					UIGridLayout = 562,
					UIGridStyleLayout = 563,
					UILayout = 564,
					UIListLayout = 565,
					UIPadding = 566,
					UIPageLayout = 567,
					UIScale = 568,
					UISizeConstraint = 569,
					UIStroke = 570,
					UITableLayout = 571,
					UITextSizeConstraint = 572,
					UnionOperation = 573,
					UniversalConstraint = 574,
					UnvalidatedAssetService = 575,
					UserGameSettings = 576,
					UserInputService = 577,
					UserService = 578,
					UserSettings = 579,
					UserStorageService = 580,
					ValueBase = 581,
					Vector3Curve = 582,
					Vector3Value = 583,
					VectorForce = 584,
					VehicleController = 585,
					VehicleSeat = 586,
					VelocityMotor = 587,
					VersionControlService = 588,
					VideoCaptureService = 589,
					VideoFrame = 590,
					ViewportFrame = 591,
					VirtualInputManager = 592,
					VirtualUser = 593,
					VisibilityService = 594,
					Visit = 595,
					VoiceChannel = 596,
					VoiceChatInternal = 597,
					VoiceChatService = 598,
					VoiceSource = 599,
					VRService = 600,
					WedgePart = 601,
					Weld = 602,
					WeldConstraint = 603,
					WireframeHandleAdornment = 604,
					Workspace = 605,
					WorldModel = 606,
					WorldRoot = 607,
					WrapLayer = 608,
					WrapTarget = 609,
				},
			},
			NewDark = {
				MapId = 135148380892747,
				Icons = {
					Accessory = 1,
					Actor = 2,
					AdGui = 3,
					AdPortal = 4,
					AirController = 5,
					AlignOrientation = 6,
					AlignPosition = 7,
					AngularVelocity = 8,
					Animation = 9,
					AnimationConstraint = 10,
					AnimationController = 11,
					AnimationFromVideoCreatorService = 12,
					Animator = 13,
					ArcHandles = 14,
					Atmosphere = 15,
					Attachment = 16,
					AudioAnalyzer = 17,
					AudioChannelMixer = 18,
					AudioChannelSplitter = 19,
					AudioChorus = 20,
					AudioCompressor = 21,
					AudioDeviceInput = 22,
					AudioDeviceOutput = 23,
					AudioDistortion = 24,
					AudioEcho = 25,
					AudioEmitter = 26,
					AudioEqualizer = 27,
					AudioFader = 28,
					AudioFilter = 29,
					AudioFlanger = 30,
					AudioGate = 31,
					AudioLimiter = 32,
					AudioListener = 33,
					AudioPitchShifter = 34,
					AudioPlayer = 35,
					AudioRecorder = 36,
					AudioReverb = 37,
					AudioTextToSpeech = 38,
					AuroraScript = 39,
					AvatarEditorService = 40,
					AvatarSettings = 41,
					Backpack = 42,
					BallSocketConstraint = 43,
					BasePlate = 44,
					Beam = 45,
					BillboardGui = 46,
					BindableEvent = 47,
					BindableFunction = 48,
					BlockMesh = 49,
					BloomEffect = 50,
					BlurEffect = 51,
					BodyAngularVelocity = 52,
					BodyColors = 53,
					BodyForce = 54,
					BodyGyro = 55,
					BodyPosition = 56,
					BodyThrust = 57,
					BodyVelocity = 58,
					Bone = 59,
					BoolValue = 60,
					BoxHandleAdornment = 61,
					Breakpoint = 62,
					BrickColorValue = 63,
					BubbleChatConfiguration = 64,
					Buggaroo = 65,
					Camera = 66,
					CanvasGroup = 67,
					CFrameValue = 68,
					ChannelTabsConfiguration = 69,
					CharacterControllerManager = 70,
					CharacterMesh = 71,
					Chat = 72,
					ChatInputBarConfiguration = 73,
					ChatWindowConfiguration = 74,
					ChorusSoundEffect = 75,
					Class = 76,
					Cleanup = 77,
					ClickDetector = 78,
					ClientReplicator = 79,
					ClimbController = 80,
					Clouds = 81,
					Color = 82,
					ColorCorrectionEffect = 83,
					CompressorSoundEffect = 84,
					ConeHandleAdornment = 85,
					Configuration = 86,
					Constant = 87,
					Constructor = 88,
					Controller = 89,
					CoreGui = 90,
					CornerWedgePart = 91,
					CylinderHandleAdornment = 92,
					CylindricalConstraint = 93,
					Decal = 94,
					DepthOfFieldEffect = 95,
					Dialog = 96,
					DialogChoice = 97,
					DistortionSoundEffect = 98,
					DragDetector = 99,
					EchoSoundEffect = 100,
					EditableImage = 101,
					EditableMesh = 102,
					Enum = 103,
					EnumMember = 104,
					EqualizerSoundEffect = 105,
					Event = 106,
					Explosion = 107,
					FaceControls = 108,
					Field = 109,
					File = 110,
					Fire = 111,
					FlangeSoundEffect = 112,
					Folder = 113,
					ForceField = 114,
					Frame = 115,
					Function = 116,
					GameSettings = 117,
					GroundController = 118,
					Handles = 119,
					HapticEffect = 120,
					HapticService = 121,
					HeightmapImporterService = 122,
					Highlight = 123,
					HingeConstraint = 124,
					Humanoid = 125,
					HumanoidDescription = 126,
					IKControl = 127,
					ImageButton = 128,
					ImageHandleAdornment = 129,
					ImageLabel = 130,
					InputAction = 131,
					InputBinding = 132,
					InputContext = 133,
					Interface = 134,
					IntersectOperation = 135,
					Keyword = 136,
					Lighting = 137,
					LinearVelocity = 138,
					LineForce = 139,
					LineHandleAdornment = 140,
					LocalFile = 141,
					LocalizationService = 142,
					LocalizationTable = 143,
					LocalScript = 144,
					MaterialService = 145,
					MaterialVariant = 146,
					MemoryStoreService = 147,
					MeshPart = 148,
					Meshparts = 149,
					MessagingService = 150,
					Method = 151,
					Model = 152,
					Modelgroups = 153,
					Module = 154,
					ModuleScript = 155,
					Motor6D = 156,
					NegateOperation = 157,
					NetworkClient = 158,
					NoCollisionConstraint = 159,
					Operator = 160,
					PackageLink = 161,
					Pants = 162,
					Part = 163,
					ParticleEmitter = 164,
					Path2D = 165,
					PathfindingLink = 166,
					PathfindingModifier = 167,
					PathfindingService = 168,
					PitchShiftSoundEffect = 169,
					Place = 170,
					Placeholder = 171,
					Plane = 172,
					PlaneConstraint = 173,
					Player = 174,
					Players = 175,
					PluginGuiService = 176,
					PointLight = 177,
					PrismaticConstraint = 178,
					Property = 179,
					ProximityPrompt = 180,
					PublishService = 181,
					Reference = 182,
					RemoteEvent = 183,
					RemoteFunction = 184,
					RenderingTest = 185,
					ReplicatedFirst = 186,
					ReplicatedScriptService = 187,
					ReplicatedStorage = 188,
					ReverbSoundEffect = 189,
					RigidConstraint = 190,
					RobloxPluginGuiService = 191,
					RocketPropulsion = 192,
					RodConstraint = 193,
					RopeConstraint = 194,
					Rotate = 195,
					ScreenGui = 196,
					Script = 197,
					ScrollingFrame = 198,
					Seat = 199,
					Selected_Workspace = 200,
					SelectionBox = 201,
					SelectionSphere = 202,
					ServerScriptService = 203,
					ServerStorage = 204,
					Service = 205,
					Shirt = 206,
					ShirtGraphic = 207,
					SkinnedMeshPart = 208,
					Sky = 209,
					Smoke = 210,
					Snap = 211,
					Snippet = 212,
					SocialService = 213,
					Sound = 214,
					SoundEffect = 215,
					SoundGroup = 216,
					SoundService = 217,
					Sparkles = 218,
					SpawnLocation = 219,
					SpecialMesh = 220,
					SphereHandleAdornment = 221,
					SpotLight = 222,
					SpringConstraint = 223,
					StandalonePluginScripts = 224,
					StarterCharacterScripts = 225,
					StarterGui = 226,
					StarterPack = 227,
					StarterPlayer = 228,
					StarterPlayerScripts = 229,
					Struct = 230,
					StyleDerive = 231,
					StyleLink = 232,
					StyleRule = 233,
					StyleSheet = 234,
					SunRaysEffect = 235,
					SurfaceAppearance = 236,
					SurfaceGui = 237,
					SurfaceLight = 238,
					SurfaceSelection = 239,
					SwimController = 240,
					TaskScheduler = 241,
					Team = 242,
					Teams = 243,
					Terrain = 244,
					TerrainDetail = 245,
					TestService = 246,
					TextBox = 247,
					TextBoxService = 248,
					TextButton = 249,
					TextChannel = 250,
					TextChatCommand = 251,
					TextChatService = 252,
					TextLabel = 253,
					TextString = 254,
					Texture = 255,
					Tool = 256,
					Torque = 257,
					TorsionSpringConstraint = 258,
					Trail = 259,
					TremoloSoundEffect = 260,
					TrussPart = 261,
					TypeParameter = 262,
					UGCValidationService = 263,
					UIAspectRatioConstraint = 264,
					UICorner = 265,
					UIDragDetector = 266,
					UIFlexItem = 267,
					UIGradient = 268,
					UIGridLayout = 269,
					UIListLayout = 270,
					UIPadding = 271,
					UIPageLayout = 272,
					UIScale = 273,
					UISizeConstraint = 274,
					UIStroke = 275,
					UITableLayout = 276,
					UITextSizeConstraint = 277,
					UnionOperation = 278,
					Unit = 279,
					UniversalConstraint = 280,
					UnreliableRemoteEvent = 281,
					UpdateAvailable = 282,
					UserService = 283,
					Value = 284,
					Variable = 285,
					VectorForce = 286,
					VehicleSeat = 287,
					VideoDisplay = 288,
					VideoFrame = 289,
					VideoPlayer = 290,
					ViewportFrame = 291,
					VirtualUser = 292,
					VoiceChannel = 293,
					Voicechat = 294,
					VoiceChatService = 295,
					VRService = 296,
					WedgePart = 297,
					Weld = 298,
					WeldConstraint = 299,
					Wire = 300,
					WireframeHandleAdornment = 301,
					Workspace = 302,
					WorldModel = 303,
					WrapDeformer = 304,
					WrapLayer = 305,
					WrapTarget = 306,

					Color3Value = 284,
					IntValue = 284,
					NumberValue = 284,
					ObjectValue = 284,
					RayValue = 284,
					StringValue = 284,
					Vector3Value = 284,
				},
				IconSize = 32,
				Witdh = 18,
				Height = 18,
			},
			NewLight = {
				MapId = "",
				Icons = {
					Class = "rbxasset://studio_svg_textures/Shared/InsertableObjects/Light/Standard/",
				},
				IconSize = 16,
				Witdh = 18,
				Height = 18,
			},
		}
		if Settings.ClassIcon and IconList[Settings.ClassIcon] then
			funcs.ExplorerIcons = {
				["MapId"] = IconList[Settings.ClassIcon].MapId,
				["Icons"] = IconList[Settings.ClassIcon].Icons,
				["IconSize"] = IconList[Settings.ClassIcon].IconSize,
				["Witdh"] = IconList[Settings.ClassIcon].Witdh,
				["Height"] = IconList[Settings.ClassIcon].Height,
			}
		else
			funcs.ExplorerIcons =
				{ ["MapId"] = IconList.Old.MapId, ["Icons"] = IconList.Old.Icons, ["IconSize"] = IconList.Old.IconSize }
		end

		funcs.GetLabel = function(self)
			local label = Instance.new("ImageLabel")
			self:SetupLabel(label)
			return label
		end

		funcs.SetupLabel = function(self, obj)
			obj.BackgroundTransparency = 1
			obj.ImageRectOffset = Vector2.new(0, 0)
			obj.ImageRectSize = Vector2.new(self.IconSizeX, self.IconSizeY)
			obj.ScaleType = Enum.ScaleType.Crop
			obj.Size = UDim2.new(0, self.IconSizeX, 0, self.IconSizeY)
		end

		funcs.Display = function(self, obj, index)
			obj.Image = self.MapId
			obj.ImageRectSize = Vector2.new(self.IconSizeX, self.IconSizeY)
			if not self.NumX then
				obj.ImageRectOffset = Vector2.new(self.IconSizeX * index, 0)
			else
				obj.ImageRectOffset =
					Vector2.new(self.IconSizeX * (index % self.NumX), self.IconSizeY * math.floor(index / self.NumX))
			end
		end

		funcs.DisplayByKey = function(self, obj, key)
			if self.IndexDict[key] then
				self:Display(obj, self.IndexDict[key])
			else
				local rmdEntry = RMD.Classes[obj.ClassName]
				Explorer.ClassIcons:Display(obj, rmdEntry and rmdEntry.ExplorerImageIndex or 0)
			end
		end

		funcs.IconDehash = function(self, _id)
			return math.floor(_id / 14 % 14), math.floor(_id % 14)
		end

		local ClassNameNoImage = {}
		funcs.GetExplorerIcon = function(self, obj, index)
			if Settings.ClassIcon == "Vanilla3" then
				obj.Size = UDim2.fromOffset(16, 16)

				index = (self.ExplorerIcons.Icons[index] or 250) - 1
				obj.ImageRectOffset = Vector2.new(
					funcs.ExplorerIcons.IconSize * (index % funcs.ExplorerIcons.Height),
					funcs.ExplorerIcons.IconSize * math.floor(index / funcs.ExplorerIcons.Height)
				)
				obj.ImageRectSize = Vector2.new(funcs.ExplorerIcons.IconSize, funcs.ExplorerIcons.IconSize)
			elseif Settings.ClassIcon == "Old" then
				index = (self.ExplorerIcons.Icons[index] or 0)
				local row, col = self:IconDehash(index)
				local MapSize = Vector2.new(256, 256)
				local pad, border = 2, 1

				obj.Position = UDim2.new(
					-col - (pad * (col + 1) + border) / funcs.ExplorerIcons.IconSize,
					0,
					-row - (pad * (row + 1) + border) / funcs.ExplorerIcons.IconSize,
					0
				)
				obj.Size =
					UDim2.new(MapSize.X / funcs.ExplorerIcons.IconSize, 0, MapSize.Y / funcs.ExplorerIcons.IconSize, 0)
			elseif Settings.ClassIcon == "NewLight" or Settings.ClassIcon == "NewDark" then
				local isService = string.find(index, "Service") and game:GetService(index)

				obj.Size = UDim2.fromOffset(16, 16)
				index = (
					self.ExplorerIcons.Icons[index]
					or (isService and self.ExplorerIcons.Icons.Service)
					or self.ExplorerIcons.Icons.Placeholder
				) - 1
				obj.ImageRectOffset = Vector2.new(
					funcs.ExplorerIcons.IconSize * (index % funcs.ExplorerIcons.Height),
					funcs.ExplorerIcons.IconSize * math.floor(index / funcs.ExplorerIcons.Height)
				)
				obj.ImageRectSize = Vector2.new(funcs.ExplorerIcons.IconSize, funcs.ExplorerIcons.IconSize)
			else
				index = (self.ExplorerIcons.Icons[index] or 0)
				local row, col = self:IconDehash(index)
				local MapSize = Vector2.new(256, 256)
				local pad, border = 2, 1

				obj.Position = UDim2.new(
					-col - (pad * (col + 1) + border) / funcs.ExplorerIcons.IconSize,
					0,
					-row - (pad * (row + 1) + border) / funcs.ExplorerIcons.IconSize,
					0
				)
				obj.Size =
					UDim2.new(MapSize.X / funcs.ExplorerIcons.IconSize, 0, MapSize.Y / funcs.ExplorerIcons.IconSize, 0)
			end
		end

		funcs.DisplayExplorerIcons = function(self, Frame, index)
			if Frame:FindFirstChild("IconMap") then
				self:GetExplorerIcon(Frame.IconMap, index)
			else
				Frame.ClipsDescendants = true

				local obj = Instance.new("ImageLabel", Frame)
				obj.BackgroundTransparency = 1
				obj.Image = ("http://www.roblox.com/asset/?id=" .. self.ExplorerIcons.MapId)
				obj.Name = "IconMap"
				self:GetExplorerIcon(obj, index)
			end
		end

		funcs.SetDict = function(self, dict)
			self.IndexDict = dict
		end

		local mt = {}
		mt.__index = funcs

		local function new(mapId, mapSizeX, mapSizeY, iconSizeX, iconSizeY)
			local obj = setmetatable({
				MapId = mapId,
				MapSizeX = mapSizeX,
				MapSizeY = mapSizeY,
				IconSizeX = iconSizeX,
				IconSizeY = iconSizeY,
				NumX = mapSizeX / iconSizeX,
				IndexDict = {},
			}, mt)
			return obj
		end

		local function newLinear(mapId, iconSizeX, iconSizeY)
			local obj = setmetatable({
				MapId = mapId,
				IconSizeX = iconSizeX,
				IconSizeY = iconSizeY,
				IndexDict = {},
			}, mt)
			return obj
		end

		local function getIconDataFromName(name)
			return IconList[name] or error("Name not found")
		end

		return { new = new, newLinear = newLinear, getIconDataFromName = getIconDataFromName }
	end)()

	Lib.ScrollBar = (function()
		local funcs = {}
		local user = service.UserInputService
		local mouse = plr:GetMouse()
		local checkMouseInGui = Lib.CheckMouseInGui
		local createArrow = Lib.CreateArrow

		local function drawThumb(self)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local index = self.Index
			local scrollThumb = self.GuiElems.ScrollThumb
			local scrollThumbFrame = self.GuiElems.ScrollThumbFrame

			if not (self:CanScrollUp() or self:CanScrollDown()) then
				scrollThumb.Visible = false
			else
				scrollThumb.Visible = true
			end

			local ratio = total > 0 and math.clamp(visible / total, 0, 1) or 1
			local percent = (total > visible and self:GetScrollPercent()) or 0
			local track = self.TrackLength or math.max(0, scrollThumbFrame.AbsoluteSize[self.Horizontal and "X" or "Y"])
			local length = math.min(track, math.max(self.MinimumThumbLength or 24, math.floor(track * ratio)))
			local offset = math.floor(percent * math.max(0, track - length) + 0.5)
			if self.Horizontal then
				scrollThumb.Size = UDim2.fromOffset(length, self.ThumbThickness or 6)
				scrollThumb.Position = UDim2.fromOffset(offset, self.ThumbInset or 2)
			else
				scrollThumb.Size = UDim2.fromOffset(self.ThumbThickness or 6, length)
				scrollThumb.Position = UDim2.fromOffset(self.ThumbInset or 2, offset)
			end
		end

		local function createFrame(self)
			local newFrame = createSimple("Frame", {
				Style = 0,
				Active = true,
				AnchorPoint = Vector2.new(0, 0),
				BackgroundColor3 = Settings.Theme.Main2,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = false,
				Draggable = false,
				Position = UDim2.new(1, -10, 0, 0),
				Rotation = 0,
				Selectable = false,
				Size = UDim2.new(0, 10, 1, 0),
				SizeConstraint = 0,
				Visible = true,
				ZIndex = 12,
				Name = "ScrollBar",
			})
			local button1, button2

			if self.Horizontal then
				newFrame.Size = UDim2.new(1, 0, 0, 10)
				button1 = createSimple("ImageButton", {
					Parent = newFrame,
					Name = "Left",
					Size = UDim2.new(0, 16, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
				})
				createArrow(16, 4, "left").Parent = button1
				button2 = createSimple("ImageButton", {
					Parent = newFrame,
					Name = "Right",
					Position = UDim2.new(1, -16, 0, 0),
					Size = UDim2.new(0, 16, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
				})
				createArrow(16, 4, "right").Parent = button2
			else
				newFrame.Size = UDim2.new(0, 10, 1, 0)
				button1 = createSimple("ImageButton", {
					Parent = newFrame,
					Name = "Up",
					Size = UDim2.new(0, 16, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
				})
				createArrow(16, 4, "up").Parent = button1
				button2 = createSimple("ImageButton", {
					Parent = newFrame,
					Name = "Down",
					Position = UDim2.new(0, 0, 1, -16),
					Size = UDim2.new(0, 16, 0, 16),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
				})
				createArrow(16, 4, "down").Parent = button2
			end

			local scrollThumbFrame = createSimple("ImageButton", {
				BackgroundTransparency = 1,
				Parent = newFrame,
			})
			button1.Visible = false
			button2.Visible = false
			button1.Size = UDim2.fromOffset(0, 0)
			button2.Size = UDim2.fromOffset(0, 0)
			scrollThumbFrame.Position = UDim2.fromOffset(0, 0)
			scrollThumbFrame.Size = UDim2.fromScale(1, 1)

			local buttonPress = false
			local thumbPress = false
			local thumbFramePress = false

			local scrollThumb = createSimple("Frame", {
				BackgroundColor3 = Color3.fromRGB(112, 112, 116),
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				Parent = scrollThumbFrame,
			})
			Lib.StudioCorner(scrollThumb, 3)
			local function paintLegacyThumb(color)
				if service.TweenService and TweenInfo then
					service.TweenService:Create(scrollThumb, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
				else
					scrollThumb.BackgroundColor3 = color
				end
			end
			scrollThumb.MouseEnter:Connect(function()
				if self.LegacyStudio or not thumbPress then
					scrollThumb.BackgroundTransparency = self.LegacyStudio and 0 or 0.08
					if self.LegacyStudio then
						paintLegacyThumb(self.LegacyHoverColor)
					end
				end
			end)
			scrollThumb.MouseLeave:Connect(function()
				if self.LegacyStudio or not thumbPress then
					scrollThumb.BackgroundTransparency = self.LegacyStudio and 0 or 0.25
					if self.LegacyStudio then
						paintLegacyThumb(self.ThumbColor)
					end
				end
			end)

			local markerFrame = createSimple("Frame", {
				BackgroundTransparency = 1,
				Name = "Markers",
				Size = UDim2.new(1, 0, 1, 0),
				Parent = scrollThumbFrame,
			})

			local function handleButtonPress(button, scrollDirection)
				if self:CanScroll(scrollDirection) then
					button.BackgroundTransparency = self.LegacyStudio and 0 or 0.5
					self:ScrollToDirection(scrollDirection)
					self.Scrolled:Fire()
					local buttonTick = tick()
					local releaseEvent
					releaseEvent = user.InputEnded:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						then
							releaseEvent:Disconnect()
							button.BackgroundTransparency = self.LegacyStudio and 0
								or (checkMouseInGui(button) and 0.8 or 1)
							buttonPress = false
						end
					end)
					while buttonPress do
						if tick() - buttonTick >= 0.25 and self:CanScroll(scrollDirection) then
							self:ScrollToDirection(scrollDirection)
							self.Scrolled:Fire()
						end
						task.wait()
					end
				end
			end

			button1.MouseButton1Down:Connect(function(input)
				buttonPress = true
				handleButtonPress(button1, "Up")
			end)

			button1.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					button1.BackgroundTransparency = self.LegacyStudio and 0 or 1
				end
			end)

			button2.MouseButton1Down:Connect(function(input)
				buttonPress = true
				handleButtonPress(button2, "Down")
			end)

			button2.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					button2.BackgroundTransparency = self.LegacyStudio and 0 or 1
				end
			end)

			scrollThumb.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local dir = self.Horizontal and "X" or "Y"
					local lastThumbPos = nil
					thumbPress = true
					scrollThumb.BackgroundTransparency = 0
					local pointer = input.UserInputType == Enum.UserInputType.Touch and input.Position[dir]
						or mouse[dir]
					local mouseOffset = pointer - scrollThumb.AbsolutePosition[dir]
					local releaseEvent
					local mouseEvent

					releaseEvent = user.InputEnded:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						then
							releaseEvent:Disconnect()
							if mouseEvent then
								mouseEvent:Disconnect()
							end
							scrollThumb.BackgroundTransparency = self.LegacyStudio and 0
								or (checkMouseInGui(scrollThumb) and 0.08 or 0.25)
							thumbPress = false
						end
					end)

					mouseEvent = user.InputChanged:Connect(function(input)
						if
							(
								input.UserInputType == Enum.UserInputType.MouseMovement
								or input.UserInputType == Enum.UserInputType.Touch
							) and thumbPress
						then
							local thumbFrameSize =
								math.max(0, scrollThumbFrame.AbsoluteSize[dir] - scrollThumb.AbsoluteSize[dir])
							if thumbFrameSize == 0 then
								return
							end
							local pointer = input.UserInputType == Enum.UserInputType.Touch and input.Position[dir]
								or mouse[dir]
							local pos = pointer - scrollThumbFrame.AbsolutePosition[dir] - mouseOffset
							if pos > thumbFrameSize then
								pos = thumbFrameSize
							elseif pos < 0 then
								pos = 0
							end
							if lastThumbPos ~= pos then
								lastThumbPos = pos
								self:ScrollTo(
									math.floor(0.5 + pos / thumbFrameSize * (self.TotalSpace - self.VisibleSpace))
								)
							end
						end
					end)
				end
			end)

			scrollThumb.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if not thumbPress then
						scrollThumb.BackgroundTransparency = self.LegacyStudio and 0
							or (checkMouseInGui(scrollThumb) and 0.08 or 0.25)
					end
				end
			end)

			scrollThumbFrame.InputBegan:Connect(function(input)
				if
					(
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					) and not checkMouseInGui(scrollThumb)
				then
					local dir = self.Horizontal and "X" or "Y"
					local scrollDir = (mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir])
							and 1
						or 0
					local function doTick()
						local scrollSize = math.max(1, self.VisibleSpace - 1)
						if scrollDir == 0 and mouse[dir] < scrollThumb.AbsolutePosition[dir] then
							self:ScrollTo(self.Index - scrollSize)
						elseif
							scrollDir == 1
							and mouse[dir] >= scrollThumb.AbsolutePosition[dir] + scrollThumb.AbsoluteSize[dir]
						then
							self:ScrollTo(self.Index + scrollSize)
						end
					end

					thumbPress = false
					thumbFramePress = true
					doTick()
					local thumbFrameTick = tick()
					local releaseEvent
					releaseEvent = user.InputEnded:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						then
							releaseEvent:Disconnect()
							thumbFramePress = false
						end
					end)

					while thumbFramePress do
						if tick() - thumbFrameTick >= 0.3 and checkMouseInGui(scrollThumbFrame) then
							doTick()
						end
						task.wait()
					end
				end
			end)

			newFrame.MouseWheelForward:Connect(function()
				self:ScrollTo(self.Index - self.WheelIncrement)
			end)

			newFrame.MouseWheelBackward:Connect(function()
				self:ScrollTo(self.Index + self.WheelIncrement)
			end)

			self.GuiElems.ScrollThumb = scrollThumb
			self.GuiElems.ScrollThumbFrame = scrollThumbFrame
			self.GuiElems.Button1 = button1
			self.GuiElems.Button2 = button2
			self.GuiElems.MarkerFrame = markerFrame

			return newFrame
		end

		funcs.UseLegacyStudioStyle = function(self)
			self.LegacyStudio = true
			self.ThumbThickness = 12
			self.ThumbInset = 1
			self.MinimumThumbLength = 16
			self.ThumbColor = Color3.fromRGB(53, 55, 65)
			self.LegacyHoverColor = Color3.fromRGB(66, 68, 78)
			self.Gui.BackgroundColor3 = Color3.fromRGB(25, 26, 31)
			self.Gui.BackgroundTransparency = 0
			local layer = self.Gui.ZIndex or 12
			local thumb = self.GuiElems.ScrollThumb
			thumb.BackgroundColor3 = self.ThumbColor
			thumb.BackgroundTransparency = 0
			thumb.ZIndex = layer + 2
			local corner = thumb:FindFirstChildOfClass("UICorner")
			if corner then
				corner:Destroy()
			end
			local track = self.GuiElems.ScrollThumbFrame
			track.AutoButtonColor = false
			track.BackgroundColor3 = Color3.fromRGB(39, 41, 48)
			track.BackgroundTransparency = 0
			track.BorderSizePixel = 0
			track.ClipsDescendants = true
			if not self.LegacyTrackResize then
				self.LegacyTrackResize = track:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					drawThumb(self)
				end)
			end
			track.ZIndex = layer + 1
			self.GuiElems.MarkerFrame.ZIndex = layer + 3
			track.Position = self.Horizontal and UDim2.fromOffset(16, 1) or UDim2.fromOffset(1, 16)
			track.Size = self.Horizontal and UDim2.new(1, -32, 1, -2) or UDim2.new(1, -2, 1, -32)
			for i, button in ipairs({ self.GuiElems.Button1, self.GuiElems.Button2 }) do
				button.Visible = true
				button.Size = self.Horizontal and UDim2.fromOffset(16, 14) or UDim2.fromOffset(14, 16)
				button.BackgroundTransparency = 0
				button.ZIndex = layer + 1
				button.Position = self.Horizontal and (i == 1 and UDim2.fromOffset(0, 1) or UDim2.new(1, -16, 0, 1))
					or (i == 1 and UDim2.fromOffset(1, 0) or UDim2.new(0, 1, 1, -16))
				button.BackgroundColor3 = self.ThumbColor
				button.Arrow.Visible = false
				local image = Instance.new("ImageLabel")
				image.Name = "StudioArrow"
				image.BackgroundTransparency = 1
				image.ZIndex = layer + 2
				image.Size = UDim2.fromOffset(16, 16)
				image.Image = Main.GetStudioAsset(i == 1 and "native/scroll/up" or "native/scroll/down") or ""
				image.Position = self.Horizontal and UDim2.fromOffset(0, -1) or UDim2.fromOffset(-1, 0)
				image.ImageColor3 = Color3.fromRGB(213, 215, 221)
				image.ImageTransparency = 0
				image.Rotation = self.Horizontal and -90 or 0
				image.Parent = button
			end
			self:Update()
		end

		funcs.Update = function(self, nocallback)
			local total = self.TotalSpace
			local visible = self.VisibleSpace
			local index = self.Index
			local button1 = self.GuiElems.Button1
			local button2 = self.GuiElems.Button2

			self.Index = math.clamp(self.Index, 0, math.max(0, total - visible))

			if self.LastTotalSpace ~= self.TotalSpace then
				self.LastTotalSpace = self.TotalSpace
				self:UpdateMarkers()
			end

			if self:CanScrollUp() then
				for i, v in pairs(button1.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0
				end
			else
				button1.BackgroundTransparency = self.LegacyStudio and 0 or 1
				for i, v in pairs(button1.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0.5
				end
			end
			if self:CanScrollDown() then
				for i, v in pairs(button2.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0
				end
			else
				button2.BackgroundTransparency = self.LegacyStudio and 0 or 1
				for i, v in pairs(button2.Arrow:GetChildren()) do
					v.BackgroundTransparency = 0.5
				end
			end

			drawThumb(self)
		end

		funcs.UpdateMarkers = function(self)
			local markerFrame = self.GuiElems.MarkerFrame
			markerFrame:ClearAllChildren()

			for i, v in pairs(self.Markers) do
				if i < self.TotalSpace then
					createSimple("Frame", {
						BackgroundTransparency = 0,
						BackgroundColor3 = v,
						BorderSizePixel = 0,
						Position = self.Horizontal and UDim2.new(i / self.TotalSpace, 0, 1, -6)
							or UDim2.new(1, -6, i / self.TotalSpace, 0),
						Size = self.Horizontal and UDim2.new(0, 1, 0, 6) or UDim2.new(0, 6, 0, 1),
						Name = "Marker" .. tostring(i),
						Parent = markerFrame,
					})
				end
			end
		end

		funcs.AddMarker = function(self, ind, color)
			self.Markers[ind] = color or Color3.new(0, 0, 0)
		end
		funcs.ScrollTo = function(self, ind, nocallback)
			self.Index = ind
			self:Update()
			if not nocallback then
				self.Scrolled:Fire()
			end
		end
		funcs.ScrollUp = function(self)
			self.Index = self.Index - self.Increment
			self:Update()
		end
		funcs.CanScroll = function(self, direction)
			if direction == "Up" then
				return self:CanScrollUp()
			elseif direction == "Down" then
				return self:CanScrollDown()
			end
			return false
		end
		funcs.ScrollDown = function(self)
			self.Index = self.Index + self.Increment
			self:Update()
		end
		funcs.CanScrollUp = function(self)
			return self.Index > 0
		end
		funcs.CanScrollDown = function(self)
			return self.Index + self.VisibleSpace < self.TotalSpace
		end
		funcs.GetScrollPercent = function(self)
			return self.Index / (self.TotalSpace - self.VisibleSpace)
		end
		funcs.SetScrollPercent = function(self, perc)
			self.Index = math.floor(perc * (self.TotalSpace - self.VisibleSpace))
			self:Update()
		end
		funcs.ScrollToDirection = function(self, Direaction)
			if Direaction == "Up" then
				self:ScrollUp()
			elseif Direaction == "Down" then
				self:ScrollDown()
			end
		end

		funcs.Texture = function(self, data)
			self.ThumbColor = data.ThumbColor or Color3.new(0, 0, 0)
			self.ThumbSelectColor = data.ThumbSelectColor or Color3.new(0, 0, 0)
			self.GuiElems.ScrollThumb.BackgroundColor3 = data.ThumbColor or Color3.new(0, 0, 0)
			self.Gui.BackgroundColor3 = data.FrameColor or Color3.new(0, 0, 0)
			self.GuiElems.Button1.BackgroundColor3 = data.ButtonColor or Color3.new(0, 0, 0)
			self.GuiElems.Button2.BackgroundColor3 = data.ButtonColor or Color3.new(0, 0, 0)
			for i, v in pairs(self.GuiElems.Button1.Arrow:GetChildren()) do
				v.BackgroundColor3 = data.ArrowColor or Color3.new(0, 0, 0)
			end
			for i, v in pairs(self.GuiElems.Button2.Arrow:GetChildren()) do
				v.BackgroundColor3 = data.ArrowColor or Color3.new(0, 0, 0)
			end
		end

		funcs.SetScrollFrame = function(self, frame)
			if self.ScrollUpEvent then
				self.ScrollUpEvent:Disconnect()
				self.ScrollUpEvent = nil
			end
			if self.ScrollDownEvent then
				self.ScrollDownEvent:Disconnect()
				self.ScrollDownEvent = nil
			end
			self.ScrollUpEvent = frame.MouseWheelForward:Connect(function()
				if not self.WheelFilter or self.WheelFilter() then
					self:ScrollTo(self.Index - self.WheelIncrement)
				end
			end)
			self.ScrollDownEvent = frame.MouseWheelBackward:Connect(function()
				if not self.WheelFilter or self.WheelFilter() then
					self:ScrollTo(self.Index + self.WheelIncrement)
				end
			end)
		end

		local mt = {}
		mt.__index = funcs

		local function new(hor)
			local obj = setmetatable({
				Index = 0,
				VisibleSpace = 0,
				TotalSpace = 0,
				Increment = 1,
				WheelIncrement = 1,
				Markers = {},
				GuiElems = {},
				Horizontal = hor,
				LastTotalSpace = 0,
				Scrolled = Lib.Signal.new(),
			}, mt)
			obj.Gui = createFrame(obj)
			obj:Texture({
				ThumbColor = Color3.fromRGB(112, 112, 116),
				ThumbSelectColor = Color3.fromRGB(145, 145, 150),
				ArrowColor = Color3.new(1, 1, 1),
				FrameColor = Color3.fromRGB(40, 40, 40),
				ButtonColor = Color3.fromRGB(75, 75, 75),
			})
			obj.Gui.BackgroundTransparency = 1
			obj.GuiElems.ScrollThumb.BackgroundTransparency = 0.25
			return obj
		end

		return { new = new }
	end)()

	Lib.Window = (function()
		local funcs = {}
		local static =
			{ MinWidth = 200, FreeWidth = 200, DragThreshold = 7, BeforeSideVisibilityChange = Lib.Signal.new() }
		local mouse = plr:GetMouse()
		local sidesGui, alignIndicator
		local visibleWindows = {}
		local leftSide = { Width = 340, Windows = {}, ResizeCons = {}, Hidden = true }
		local rightSide = { Width = 340, Windows = {}, ResizeCons = {}, Hidden = true }

		local displayOrderStart
		local sideDisplayOrder
		local sideTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tweens = {}
		local isA = game.IsA

		local theme = {
			MainColor1 = Color3.fromRGB(52, 52, 52),
			MainColor2 = Color3.fromRGB(45, 45, 45),
			Button = Color3.fromRGB(60, 60, 60),
		}

		local inputService = service.UserInputService
		local resizeCursorOwner
		local resizeDragOwner, resizeDragDirection
		local resizeTargets = setmetatable({}, { __mode = "k" })

		local function resizeCursorInfo(dir)
			if dir == "N" or dir == "S" or dir == "V" then
				return "cursor/qt_split_vertical_32", 0, 32
			elseif dir == "E" or dir == "W" or dir == "H" then
				return "cursor/qt_split_horizontal_32", 0, 32
			elseif dir == "NE" or dir == "SW" then
				return "cursor/windows_resize_nesw_32", 0, 32, 8, 8
			end
			return "cursor/windows_resize_nwse_32", 0, 32, 8, 8
		end

		local function currentMousePosition(fallback)
			local ok, pos = pcall(function()
				return inputService:GetMouseLocation()
			end)
			if ok and pos then
				return pos
			end
			if fallback then
				return fallback
			end
			return Vector2.new(mouse.X or 0, mouse.Y or 0)
		end

		local cursorOwner, cursorKey, cursorIcon, cursorSurface, cursorDetector
		local cursorTarget, cursorProperty, previousIcon, previousEnabled
		local function clearCursor(owner)
			if not cursorOwner or (owner and cursorOwner ~= owner) then return end
			if cursorDetector then cursorDetector:Destroy() end
			cursorSurface, cursorDetector = nil, nil
			if cursorTarget[cursorProperty] == cursorIcon then
				cursorTarget[cursorProperty] = previousIcon
			end
			if not previousEnabled then inputService.MouseIconEnabled = false end
			cursorOwner, cursorKey = nil, nil
		end
		local function setCursor(owner, key, fallback, surface)
			if cursorOwner == owner and cursorKey == key and cursorSurface == surface then return true end
			local icon = fallback or (Main.GetStudioAsset and Main.GetStudioAsset(key))
			if not icon then return false end
			if not cursorOwner then
				local ok, saved = pcall(function()
					local original = inputService.MouseIcon
					inputService.MouseIcon = icon
					return original
				end)
				if ok then
					cursorTarget, cursorProperty, previousIcon = inputService, "MouseIcon", saved
				else
					cursorTarget, cursorProperty, previousIcon = mouse, "Icon", mouse.Icon
					mouse.Icon = icon
				end
				previousEnabled = inputService.MouseIconEnabled
				if not previousEnabled then inputService.MouseIconEnabled = true end
			else
				local current = cursorTarget[cursorProperty]
				if current ~= cursorIcon then previousIcon = current end
				cursorTarget[cursorProperty] = icon
			end
			if cursorSurface ~= surface then
				if cursorDetector then cursorDetector:Destroy() end
				cursorDetector = nil
				cursorSurface = surface
				if surface then
					cursorDetector = Instance.new("UIDragDetector")
					cursorDetector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
					cursorDetector.CursorIcon = icon
					cursorDetector.ActivatedCursorIcon = icon
					cursorDetector.Parent = surface
				end
			elseif cursorDetector then
				cursorDetector.CursorIcon = icon
				cursorDetector.ActivatedCursorIcon = icon
			end
			cursorOwner, cursorKey, cursorIcon = owner, key, icon
			return true
		end
		static.SetTextCursor = function(owner, enabled)
			if enabled and not resizeCursorOwner and not resizeDragOwner then
				setCursor(owner, "cursor/text_ibeam", "rbxasset://textures/Cursors/KeyboardMouse/IBeamCursor.png", owner)
			else
				clearCursor(owner)
			end
		end
		static.SetHandleCursor = function(owner, key, surface)
			if key and not resizeCursorOwner and not resizeDragOwner and setCursor(owner, key, nil, surface) then return end
			clearCursor(owner)
		end
		local resizeCursorDirection, resizeCursorGui, resizeCursorImage
		local resizeCursorPreviousEnabled, resizeCursorPreviousIcon

		local function ensureResizeCursorGui()
			if resizeCursorGui and resizeCursorGui.Parent and resizeCursorImage then
				return true
			end
			resizeCursorGui = createSimple("ScreenGui", {
				Name = "DeXResizeCursor",
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = (Main.DisplayOrders.Core or Main.DisplayOrders.Menu or 100000) + 100,
			})
			resizeCursorGui:SetAttribute("DexCursorOverlay", true)
			resizeCursorImage = createSimple("ImageLabel", {
				Name = "Cursor",
				Parent = resizeCursorGui,
				Visible = false,
				Active = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(32, 32),
				ZIndex = 1000,
				ScaleType = Enum.ScaleType.Fit,
				ResampleMode = Enum.ResamplerMode.Pixelated,
			})
			Lib.ShowGui(resizeCursorGui)
			return resizeCursorGui.Parent ~= nil
		end

		local function readMouseIcon()
			local ok, current = pcall(function()
				return inputService.MouseIcon
			end)
			if ok and type(current) == "string" then
				return current
			end
			ok, current = pcall(function()
				return mouse.Icon
			end)
			return ok and current or ""
		end

		local function readMouseIconEnabled()
			local ok, current = pcall(function()
				return inputService.MouseIconEnabled
			end)
			return ok and current ~= false
		end

		local function restoreNativeCursor()
			local enabled = resizeCursorPreviousEnabled
			local icon = resizeCursorPreviousIcon or ""
			pcall(function()
				inputService.MouseIcon = icon
			end)
			pcall(function()
				mouse.Icon = icon
			end)
			if enabled ~= nil then
				pcall(function()
					inputService.MouseIconEnabled = enabled
				end)
			end
		end

		local function moveResizeCursor(pos)
			if not resizeCursorImage or not resizeCursorImage.Visible then
				return
			end
			pos = currentMousePosition(pos)
			resizeCursorImage.Position = UDim2.fromOffset(math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5))
		end
		local function showResizeCursor(owner, dir, pos)
			if
				resizeCursorOwner == owner
				and resizeCursorDirection == dir
				and resizeCursorImage
				and resizeCursorImage.Visible
			then
				pcall(function()
					inputService.MouseIconEnabled = false
				end)
				moveResizeCursor(pos)
				return
			end
			local key, rotation, size, hotX, hotY = resizeCursorInfo(dir)
			local asset = Main.GetStudioAsset and Main.GetStudioAsset(key)
			if not asset or not ensureResizeCursorGui() then
				return
			end
			if not resizeCursorOwner then
				clearCursor()
				resizeCursorPreviousEnabled = readMouseIconEnabled()
				resizeCursorPreviousIcon = readMouseIcon()
			end
			resizeCursorOwner = owner
			resizeCursorDirection = dir
			resizeCursorImage.Image = asset
			resizeCursorImage.Size = UDim2.fromOffset(size, size)
			resizeCursorImage.AnchorPoint = Vector2.new((hotX or size / 2) / size, (hotY or size / 2) / size)
			resizeCursorImage.Rotation = rotation
			resizeCursorImage.Visible = true
			pcall(function()
				inputService.MouseIconEnabled = false
			end)
			moveResizeCursor(pos)
		end

		local function clearResizeCursor(owner, force)
			if not resizeCursorOwner or not force and resizeCursorOwner ~= owner then
				return
			end
			resizeCursorOwner = nil
			resizeCursorDirection = nil
			if resizeCursorImage then
				resizeCursorImage.Visible = false
			end
			restoreNativeCursor()
			resizeCursorPreviousEnabled = nil
			resizeCursorPreviousIcon = nil
		end

		local function registerResizeTarget(resizer, dir, enabled)
			resizeTargets[resizer] = { Dir = dir, Enabled = enabled }
		end
		static.BindSplitterCursor = function(gui, enabled)
			registerResizeTarget(gui, "H", enabled)
			local control = {}
			function control:Begin(pos)
				resizeDragOwner = gui
				resizeDragDirection = "H"
				showResizeCursor(gui, "H", pos)
			end
			function control:End()
				if resizeDragOwner == gui then
					resizeDragOwner = nil
					resizeDragDirection = nil
				end
				clearResizeCursor(gui)
			end
			Main.AddCleanup(function()
				control:End()
				resizeTargets[gui] = nil
			end)
			return control
		end

		local function pointInResizeTarget(resizer, pos)
			local ok, result = pcall(function()
				if not resizer.Parent or not resizer.Visible then
					return false
				end
				local p, size = resizer.AbsolutePosition, resizer.AbsoluteSize
				return pos.X >= p.X and pos.X < p.X + size.X and pos.Y >= p.Y and pos.Y < p.Y + size.Y
			end)
			return ok and result or false
		end

		local function refreshResizeCursor(pos)
			if resizeDragOwner then
				showResizeCursor(resizeDragOwner, resizeDragDirection, pos)
				return
			end
			if not pos then
				return
			end
			for resizer, data in pairs(resizeTargets) do
				local enabled = true
				if data.Enabled then
					local ok, result = pcall(data.Enabled)
					enabled = ok and result
				end
				if enabled and pointInResizeTarget(resizer, pos) then
					showResizeCursor(resizer, data.Dir, pos)
					return
				end
			end
			if resizeCursorOwner then
				clearResizeCursor(resizeCursorOwner)
			end
		end

		Main.TrackSignal(inputService.InputChanged, function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if resizeDragOwner then
					return
				end
				refreshResizeCursor(input.Position)
			end
		end)

		Main.AddCleanup(function()
			clearCursor()
			resizeDragOwner = nil
			resizeDragDirection = nil
			clearResizeCursor(nil, true)
			if resizeCursorGui then
				pcall(function()
					resizeCursorGui:Destroy()
				end)
			end
			resizeCursorGui = nil
			resizeCursorImage = nil
			clearCursor()
		end)

		local function stopTweens()
			for i = 1, #tweens do
				tweens[i]:Cancel()
			end
			tweens = {}
		end

		local function setResizeHover(self, resizer, hovered)
			if self.ResizeHandleStyle == "Dock" then
				resizer.BackgroundTransparency = 1
				local bar = resizer:FindFirstChild("ResizeBar")
				if bar then
					bar.Visible = true
					bar.BackgroundColor3 = hovered and theme.MainColor2 or theme.Button
				end
				if #resizer.Name > 5 then
					local controls = self.GuiElems.ResizeControls
					for _, edge in ipairs({ "North", "South", "East", "West" }) do
						if resizer.Name:find(edge, 1, true) then
							local strip = controls[edge]:FindFirstChild("ResizeBar")
							if strip then
								strip.BackgroundColor3 = hovered and theme.MainColor2 or theme.Button
							end
						end
					end
				end
			else
				resizer.BackgroundTransparency = hovered and 0.5 or 1
			end
		end
		local function resizeHook(self, resizer, dir)
			registerResizeTarget(resizer, dir, function()
				return self.Resizable and self.ResizableInternal and not self.Closed
			end)

			local guiMain = self.GuiElems.Main

			resizer.MouseEnter:Connect(function()
				if resizeDragOwner and resizeDragOwner ~= resizer then
					return
				end
				setResizeHover(self, resizer, true)
				if self.Resizable and self.ResizableInternal then
					showResizeCursor(resizer, dir)
				end
			end)
			resizer.MouseLeave:Connect(function()
				if self.Resizing ~= resizer then
					clearResizeCursor(resizer)
				end
				if self.ResizeHandleStyle == "Dock" and self.Resizing ~= resizer then
					setResizeHover(self, resizer, false)
				end
			end)
			resizer.InputBegan:Connect(function(input)
				if
					not resizeDragOwner
					and not self.Dragging
					and not self.Resizing
					and self.Resizable
					and self.ResizableInternal
				then
					local isH = dir:find("[WE]") and true
					local isV = dir:find("[NS]") and true
					local signX = dir:find("W", 1, true) and -1 or 1
					local signY = dir:find("N", 1, true) and -1 or 1

					if self.Minimized and isV then
						return
					end

					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local releaseEvent, mouseEvent, resizeFrame

						local touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
						local startPointer = touch and touch.Position or currentMousePosition(input.Position)
						local startSizeX, startSizeY = self.SizeX, self.SizeY
						local startPosition = guiMain.Position
						local startTop = guiMain.AbsolutePosition.Y

						self.Resizing = resizer
						resizeDragOwner = resizer
						resizeDragDirection = dir
						showResizeCursor(resizer, dir, input.Position)
						self:StopTweens()

						releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
							if
								input == touch or (not touch and input.UserInputType == Enum.UserInputType.MouseButton1)
							then
								if resizeFrame then
									resizeFrame:Flush()
									resizeFrame:Cancel()
								end
								releaseEvent:Disconnect()
								if mouseEvent then
									mouseEvent:Disconnect()
								end
								self.Resizing = false
								resizeDragOwner = nil
								resizeDragDirection = nil
								setResizeHover(self, resizer, false)
								refreshResizeCursor(input.Position)
							end
						end)

						resizeFrame = Lib.FrameTask(function(position)
							if
								self.Resizing == resizer
								and not self.Closed
								and resizer.Parent
								and self.Resizable
								and self.ResizableInternal
							then
								local pointer = touch and position or currentMousePosition(position)
								if not touch then
									showResizeCursor(resizer, dir, pointer)
								end
								local deltaX = math.floor(pointer.X - startPointer.X + 0.5)
								local deltaY = math.floor(pointer.Y - startPointer.Y + 0.5)
								if startSizeX + deltaX * signX < self.MinX then
									deltaX = signX * (self.MinX - startSizeX)
								end
								if startSizeY + deltaY * signY < self.MinY then
									deltaY = signY * (self.MinY - startSizeY)
								end
								if signY < 0 and startTop + deltaY < 0 then
									deltaY = -startTop
								end
								local position = startPosition
									+ UDim2.new(0, signX < 0 and deltaX or 0, 0, signY < 0 and deltaY or 0)
								self.SizeX = startSizeX + (isH and deltaX * signX or 0)
								self.SizeY = startSizeY + (isV and deltaY * signY or 0)
								local size = UDim2.new(
									0,
									self.SizeX,
									0,
									self.Minimized and (self.TitleBarHeight or 28) or self.SizeY
								)
								if guiMain.Position ~= position then
									guiMain.Position = position
								end
								if guiMain.Size ~= size then
									guiMain.Size = size
									if self.OnResizeApplied then
										self:OnResizeApplied()
									end
								end
							end
						end)
						mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
							if
								input == touch
								or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
							then
								resizeFrame:Push(input.Position)
							end
						end)
					end
				end
			end)

			resizer.InputEnded:Connect(function(input)
				if
					(
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					) and self.Resizing ~= resizer
				then
					setResizeHover(self, resizer, false)
				end
			end)
		end

		local updateWindows

		local function moveToTop(window)
			local found = table.find(visibleWindows, window)
			if found then
				table.remove(visibleWindows, found)
				table.insert(visibleWindows, 1, window)
				updateWindows()
			end
		end

		local function measureSide(windows)
			local height = math.max(0, sidesGui.AbsoluteSize.Y - math.max(0, #windows - 1) * 4)
			local sizes, total, current, needed = {}, 0, 0, 0
			for _, win in ipairs(windows) do
				total += win.SizeY
			end
			for i, win in ipairs(windows) do
				if i == #windows then
					sizes[i] = height - current
					needed = math.max(0, (win.MinY or 100) - sizes[i])
				else
					sizes[i] = math.max(math.floor(win.SizeY / math.max(1, total) * height), win.MinY or 100)
				end
				current += sizes[i]
			end
			if needed > 0 then
				for i = #windows - 1, 1, -1 do
					local size = math.max(sizes[i] - needed, windows[i].MinY or 100)
					needed -= sizes[i] - size
					sizes[i] = size
				end
				sizes[#windows] = (windows[#windows].MinY or 100) - needed
			end
			return sizes
		end

		local function previewDock(side, window, pos)
			local windows = table.clone(side.Windows)
			table.insert(windows, pos, window)
			local sizes = measureSide(windows)
			local y = 0
			for i = 1, pos - 1 do
				y += sizes[i] + 4
			end
			local x = side == leftSide and 0 or sidesGui.AbsoluteSize.X - side.Width
			alignIndicator.Indicator.Position = UDim2.fromOffset(x, y)
			alignIndicator.Indicator.Size = UDim2.fromOffset(side.Width, sizes[pos])
			Lib.ShowGui(alignIndicator)
		end

		local function sideHasRoom(side, neededSize)
			local maxY = sidesGui.AbsoluteSize.Y - (#side.Windows * 4)
			local inc = 0
			for i, v in pairs(side.Windows) do
				inc = inc + (v.MinY or 100)
				if inc > maxY - neededSize then
					return false
				end
			end

			return true
		end

		local function getSideInsertPos(side, curY)
			local pos = #side.Windows + 1
			local range = { 0, sidesGui.AbsoluteSize.Y }

			for i, v in pairs(side.Windows) do
				local midPos = v.PosY + v.SizeY / 2
				if curY <= midPos then
					pos = i
					range[2] = midPos
					break
				else
					range[1] = midPos
				end
			end

			return pos, range
		end

		local function focusInput(self, obj)
			if isA(obj, "GuiButton") then
				obj.MouseButton1Down:Connect(function()
					moveToTop(self)
				end)
			elseif isA(obj, "TextBox") then
				obj.Focused:Connect(function()
					moveToTop(self)
				end)
			end
		end

		local createGui = function(self)
			local gui = create({
				{ 1, "ScreenGui", { Name = "Window" } },
				{
					2,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "Main",
						Parent = { 1 },
						Position = UDim2.new(0.40000000596046, 0, 0.40000000596046, 0),
						Size = UDim2.new(0, 300, 0, 300),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
						Name = "Content",
						Parent = { 2 },
						Position = UDim2.new(0, 0, 0, 20),
						Size = UDim2.new(1, 0, 1, -20),
						ClipsDescendants = true,
					},
				},
				{
					4,
					"Frame",
					{
						BackgroundColor3 = Color3.fromRGB(33, 33, 33),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 3 },
						Size = UDim2.new(1, 0, 0, 1),
					},
				},
				{
					5,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BorderSizePixel = 0,
						Name = "TopBar",
						Parent = { 2 },
						Size = UDim2.new(1, 0, 0, 20),
						Text = "",
					},
				},
				{
					6,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 5 },
						Position = UDim2.new(0, 5, 0, 0),
						Size = UDim2.new(1, -10, 0, 20),
						Text = "Window",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					7,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Close",
						Parent = { 5 },
						Position = UDim2.new(1, -18, 0, 2),
						Size = UDim2.new(0, 16, 0, 16),
						Text = "",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
					},
				},
				{
					8,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Image = Lib.PanelAsset("close") or "",
						Parent = { 7 },
						Position = UDim2.new(0, 3, 0, 3),
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
				{ 9, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 7 } } },
				{ 9, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 2 } } },
				{
					10,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Minimize",
						Parent = { 5 },
						Position = UDim2.new(1, -36, 0, 2),
						Size = UDim2.new(0, 16, 0, 16),
						Text = "",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
					},
				},
				{
					11,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Image = Lib.PanelAsset("pin") or "rbxassetid://5034768003",
						Parent = { 10 },
						Position = UDim2.new(0, 3, 0, 3),
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
				{ 12, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 10 } } },
				{
					13,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = "rbxassetid://1427967925",
						Name = "Outlines",
						Parent = { 2 },
						Position = UDim2.new(0, -5, 0, -5),
						ScaleType = 1,
						Size = UDim2.new(1, 10, 1, 10),
						SliceCenter = Rect.new(6, 6, 25, 25),
						TileSize = UDim2.new(0, 20, 0, 20),
					},
				},
				{
					14,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Name = "ResizeControls",
						Parent = { 2 },
						Position = UDim2.new(0, -5, 0, -5),
						Size = UDim2.new(1, 10, 1, 10),
					},
				},
				{
					15,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "North",
						Parent = { 14 },
						Position = UDim2.new(0, 10, 0, 0),
						Size = UDim2.new(1, -20, 0, 10),
					},
				},
				{
					16,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "South",
						Parent = { 14 },
						Position = UDim2.new(0, 10, 1, -10),
						Size = UDim2.new(1, -20, 0, 10),
					},
				},
				{
					17,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "NorthEast",
						Parent = { 14 },
						Position = UDim2.new(1, -10, 0, 0),
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
				{
					18,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "East",
						Parent = { 14 },
						Position = UDim2.new(1, -10, 0, 10),
						Size = UDim2.new(0, 10, 1, -20),
					},
				},
				{
					19,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "West",
						Parent = { 14 },
						Position = UDim2.new(0, 0, 0, 10),
						Size = UDim2.new(0, 10, 1, -20),
					},
				},
				{
					20,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "SouthEast",
						Parent = { 14 },
						Position = UDim2.new(1, -10, 1, -10),
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
				{
					21,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "NorthWest",
						Parent = { 14 },
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
				{
					22,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.27450981736183, 0.27450981736183, 0.27450981736183),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "SouthWest",
						Parent = { 14 },
						Position = UDim2.new(0, 0, 1, -10),
						Size = UDim2.new(0, 10, 0, 10),
					},
				},
			})

			local guiMain = gui.Main
			guiMain.Content.Position = UDim2.fromOffset(0, 28)
			guiMain.Content.Size = UDim2.new(1, 0, 1, -28)
			guiMain.Content.BackgroundColor3 = Settings.Theme.Main2
			guiMain.Content.Line.BackgroundColor3 = Settings.Theme.Outline2
			guiMain.TopBar.Size = UDim2.new(1, 0, 0, 28)
			guiMain.TopBar.BackgroundColor3 = Settings.Theme.Main1
			Lib.StudioText(guiMain.TopBar.Title)
			guiMain.TopBar.Title.TextColor3 = Settings.Theme.PlaceholderText
			guiMain.TopBar.Title.Position = UDim2.fromOffset(52, 0)
			guiMain.TopBar.Title.Size = UDim2.new(1, -104, 1, 0)
			guiMain.TopBar.Title.TextTruncate = Enum.TextTruncate.AtEnd
			for i, name in ipairs({ "Close", "Minimize" }) do
				local button = guiMain.TopBar[name]
				button.Position = UDim2.new(1, -20 * i, 0, 6)
				button.Size = UDim2.fromOffset(16, 16)
				button.ImageLabel.Position = UDim2.fromOffset(0, 0)
				button.ImageLabel.Size = UDim2.fromOffset(16, 16)
				button.ImageLabel.ScaleType = Enum.ScaleType.Fit
				button.ImageLabel.ImageColor3 = Color3.new(1, 1, 1)
				button.ZIndex = (guiMain.TopBar.ZIndex or 1) + 1
				button.ImageLabel.ZIndex = button.ZIndex + 1
			end
			guiMain.Outlines.ImageColor3 = Settings.Theme.Outline2
			local guiTopBar = guiMain.TopBar
			local guiResizeControls = guiMain.ResizeControls
			local focusStroke = createSimple("UIStroke", {
				Name = "FocusIndicator",
				Parent = guiMain,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Settings.Theme.Focus,
				Thickness = 2,
				Transparency = 1,
			})

			self.GuiElems.Main = guiMain
			self.GuiElems.TopBar = guiMain.TopBar
			self.GuiElems.Content = guiMain.Content
			self.GuiElems.Line = guiMain.Content.Line
			self.GuiElems.Outlines = guiMain.Outlines
			self.GuiElems.Title = guiTopBar.Title
			self.GuiElems.Close = guiTopBar.Close
			self.GuiElems.Minimize = guiTopBar.Minimize
			self.GuiElems.ResizeControls = guiResizeControls
			self.GuiElems.FocusIndicator = focusStroke
			self.ContentPane = guiMain.Content
			if Main.RegisterGuiFocusOwner then
				Main.RegisterGuiFocusOwner(gui, self)
				Main.RegisterGuiFocusOwner(guiMain, self)
			end
			if Main.RegisterFocusIndicator then
				Main.RegisterFocusIndicator(self, function(visible)
					if focusStroke.Parent then
						focusStroke.Transparency = visible and 0 or 1
					end
				end)
			end



			local ButtonDown = false
			guiTopBar.MouseButton1Down:Connect(function()
				ButtonDown = true
			end)
			guiTopBar.MouseButton1Up:Connect(function()
				ButtonDown = false
			end)

			if Settings.Window.TitleOnMiddle then
				self.GuiElems.Title.TextXAlignment = 2
				self.GuiElems.Title.Size = UDim2.new(1, -104, 1, 0)
			end

			if Settings.Window.Transparency then
				self.GuiElems.Content.BackgroundTransparency = Settings.Window.Transparency
			end

			guiTopBar.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if self.Draggable then
						local releaseEvent, mouseEvent

						local maxX = sidesGui.AbsoluteSize.X
						local initX = guiMain.AbsolutePosition.X
						local initY = guiMain.AbsolutePosition.Y
						local offX = input.Position.X - initX
						local offY = input.Position.Y - initY

						local alignInsertPos, alignInsertSide
						local dragActive = true
						local started = false

						releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
							if
								input.UserInputType == Enum.UserInputType.MouseButton1
								or input.UserInputType == Enum.UserInputType.Touch
							then
								releaseEvent:Disconnect()
								if mouseEvent then
									mouseEvent:Disconnect()
								end
								guiDragging = false
								self.Dragging = false
								dragActive = false
								alignIndicator.Parent = nil
								if alignInsertSide then
									local targetSide = (alignInsertSide == "left" and leftSide)
										or (alignInsertSide == "right" and rightSide)
									self:AlignTo(targetSide, alignInsertPos)
								end
							end
						end)

						mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
							if
								(
									input.UserInputType == Enum.UserInputType.MouseMovement
									or input.UserInputType == Enum.UserInputType.Touch
								)
								and self.Draggable
								and not self.Closed
								and dragActive
							then
								if not started then
									local distance = math.abs(input.Position.X - offX - initX)
										+ math.abs(input.Position.Y - offY - initY)
									if distance <= (Settings.Window.DragThreshold or Lib.Window.DragThreshold or 7) then
										return
									end
									started = true
									guiDragging = true
									self.Dragging = true
								end
								if self.Aligned then
									if leftSide.Resizing or rightSide.Resizing then
										return
									end
									local posX, posY = input.Position.X - offX, input.Position.Y - offY
									local delta = math.abs(posX - initX) + math.abs(posY - initY)
									if delta > (Settings.Window.DragThreshold or Lib.Window.DragThreshold or 7) then
										self:SetAligned(false)
									end
								else
									local inputX, inputY = input.Position.X, input.Position.Y
									local posX, posY = inputX - offX, inputY - offY
									if posY < 0 then
										posY = 0
									end
									guiMain.Position = UDim2.new(0, posX, 0, posY)

									if self.Alignable then
										if
											inputX
											< ((#leftSide.Windows == 0 or leftSide.Hidden) and 48 or leftSide.Width)
										then
											if sideHasRoom(leftSide, self.MinY or 100) then
												local insertPos = getSideInsertPos(leftSide, inputY)
												previewDock(leftSide, self, insertPos)
												alignInsertPos = insertPos
												alignInsertSide = "left"
												return
											end
										elseif
											inputX
											>= maxX
												- ((#rightSide.Windows == 0 or rightSide.Hidden) and 48 or rightSide.Width)
										then
											if sideHasRoom(rightSide, self.MinY or 100) then
												local insertPos = getSideInsertPos(rightSide, inputY)
												previewDock(rightSide, self, insertPos)
												alignInsertPos = insertPos
												alignInsertSide = "right"
												return
											end
										end
									end
									alignIndicator.Parent = nil
									alignInsertPos = nil
									alignInsertSide = nil
								end
							end
						end)
					end
				end
			end)

			guiTopBar.Close.MouseButton1Click:Connect(function()
				if self.Closed then
					return
				end
				self:Close()
			end)

			guiTopBar.Minimize.MouseButton1Click:Connect(function()
				if self.Closed then
					return
				end
				if self.Aligned then
					self:SetAligned(false)
				else
					self:SetMinimized()
				end
			end)

			guiTopBar.Minimize.MouseButton2Click:Connect(function()
				if self.Closed then
					return
				end
				if not self.Aligned then
					self:SetMinimized(nil, 2)
					guiTopBar.Minimize.BackgroundTransparency = 1
				end
			end)

			guiMain.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch and not self.Aligned and not self.Closed
				then
					moveToTop(self)
				end
			end)

			guiMain:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				local absPos = guiMain.AbsolutePosition
				self.PosX = absPos.X
				self.PosY = absPos.Y
			end)

			resizeHook(self, guiResizeControls.North, "N")
			resizeHook(self, guiResizeControls.NorthEast, "NE")
			resizeHook(self, guiResizeControls.East, "E")
			resizeHook(self, guiResizeControls.SouthEast, "SE")
			resizeHook(self, guiResizeControls.South, "S")
			resizeHook(self, guiResizeControls.SouthWest, "SW")
			resizeHook(self, guiResizeControls.West, "W")
			resizeHook(self, guiResizeControls.NorthWest, "NW")

			guiMain.Size = UDim2.new(0, self.SizeX, 0, self.SizeY)

			gui.DescendantAdded:Connect(function(obj)
				focusInput(self, obj)
			end)
			local descs = gui:GetDescendants()
			for i = 1, #descs do
				focusInput(self, descs[i])
			end

			self.MinimizeAnim = Lib.PanelButtonHover(guiTopBar.Minimize)
			self.CloseAnim = Lib.PanelButtonHover(guiTopBar.Close)

			return gui
		end

		local function updateSideFrames(noTween)
			stopTweens()
			leftSide.Frame.Size = UDim2.new(0, leftSide.Width, 1, 0)
			rightSide.Frame.Size = UDim2.new(0, rightSide.Width, 1, 0)
			leftSide.Frame.Resizer.Position = UDim2.new(0, leftSide.Width, 0, 0)
			rightSide.Frame.Resizer.Position = UDim2.new(0, -5, 0, 0)


			local leftHidden = #leftSide.Windows == 0 or leftSide.Hidden
			local rightHidden = #rightSide.Windows == 0 or rightSide.Hidden
			local leftPos = (leftHidden and UDim2.new(0, -leftSide.Width - 10, 0, 0) or UDim2.new(0, 0, 0, 0))
			local rightPos = (rightHidden and UDim2.new(1, 10, 0, 0) or UDim2.new(1, -rightSide.Width, 0, 0))

			sidesGui.LeftToggle.Text = ""
			sidesGui.RightToggle.Text = ""
			Lib.SetSidebarIcon(sidesGui.LeftToggle, leftHidden, false)
			Lib.SetSidebarIcon(sidesGui.RightToggle, rightHidden, true)

			if not noTween then
				local function insertTween(...)
					local tween = service.TweenService:Create(...)
					tweens[#tweens + 1] = tween
					tween:Play()
				end
				insertTween(leftSide.Frame, sideTweenInfo, { Position = leftPos })
				insertTween(rightSide.Frame, sideTweenInfo, { Position = rightPos })
				insertTween(
					sidesGui.LeftToggle,
					sideTweenInfo,
					{ Position = UDim2.new(0, #leftSide.Windows == 0 and -28 or 4, 0, -32) }
				)
				insertTween(
					sidesGui.RightToggle,
					sideTweenInfo,
					{ Position = UDim2.new(1, #rightSide.Windows == 0 and 4 or -28, 0, -32) }
				)
			else
				leftSide.Frame.Position = leftPos
				rightSide.Frame.Position = rightPos
				sidesGui.LeftToggle.Position = UDim2.new(0, #leftSide.Windows == 0 and -28 or 4, 0, -32)
				sidesGui.RightToggle.Position = UDim2.new(1, #rightSide.Windows == 0 and 4 or -28, 0, -32)
			end
		end

		local function getSideFramePos(side)
			local leftHidden = #leftSide.Windows == 0 or leftSide.Hidden
			local rightHidden = #rightSide.Windows == 0 or rightSide.Hidden
			if side == leftSide then
				return (leftHidden and UDim2.new(0, -leftSide.Width - 10, 0, 0) or UDim2.new(0, 0, 0, 0))
			else
				return (rightHidden and UDim2.new(1, 10, 0, 0) or UDim2.new(1, -rightSide.Width, 0, 0))
			end
		end

		local function sideResized(side)
			side.LayoutApplying = true
			local currentPos = 0
			local sideFramePos = getSideFramePos(side)
			local resizedWindows
			for i, v in pairs(side.Windows) do
				v.SizeX = side.Width
				local main = v.GuiElems.Main
				local size = UDim2.fromOffset(side.Width, v.SizeY)
				local resized = main.Size ~= size
				if resized then
					main.Size = size
				end
				local position = UDim2.new(sideFramePos.X.Scale, sideFramePos.X.Offset, 0, currentPos)
				if main.Position ~= position then
					main.Position = position
				end
				if resized and v.OnResizeApplied then
					resizedWindows = resizedWindows or {}
					resizedWindows[#resizedWindows + 1] = v
				end
				currentPos = currentPos + v.SizeY + 4
				local divider = side.Dividers and side.Dividers[i]
				if divider then
					divider.Position = UDim2.new(1, -side.Width, 0, currentPos - 4)
				end
			end
			if side.UpdateSeams then
				side.UpdateSeams(true)
			end
			side.LayoutApplying = false
			if resizedWindows then
				for _, window in ipairs(resizedWindows) do
					window:OnResizeApplied()
				end
			end
		end

		local function sideResizerHook(resizer, dir, side, pos)
			registerResizeTarget(resizer, dir, function()
				return resizer.Parent ~= nil
			end)

			local windows = side.Windows

			resizer.MouseEnter:Connect(function()
				if resizeDragOwner and resizeDragOwner ~= resizer then
					return
				end
				resizer.BackgroundColor3 = theme.MainColor2
				showResizeCursor(resizer, dir)
			end)
			resizer.MouseLeave:Connect(function()
				if side.Resizing ~= resizer then
					clearResizeCursor(resizer)
				end
			end)
			resizer.InputBegan:Connect(function(input)
				if not resizeDragOwner and not side.Resizing then
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						resizer.BackgroundColor3 = theme.MainColor2
					end
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local releaseEvent, mouseEvent, resizeFrame

						local touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
						local startPointer = touch and touch.Position or currentMousePosition(input.Position)
						local startWidth = side.Width
						local startHeights = {}
						for i, window in ipairs(windows) do
							startHeights[i] = window.SizeY
						end

						side.Resizing = resizer
						resizeDragOwner = resizer
						resizeDragDirection = dir
						showResizeCursor(resizer, dir, input.Position)
						resizer.BackgroundColor3 = theme.MainColor2

						releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
							if
								input == touch or (not touch and input.UserInputType == Enum.UserInputType.MouseButton1)
							then
								if resizeFrame then
									resizeFrame:Flush()
									resizeFrame:Cancel()
								end
								releaseEvent:Disconnect()
								mouseEvent:Disconnect()
								side.Resizing = false
								resizeDragOwner = nil
								resizeDragDirection = nil
								resizer.BackgroundColor3 = theme.Button
								refreshResizeCursor(input.Position)
							end
						end)

						resizeFrame = Lib.FrameTask(function(position)
							if not resizer.Parent then
								releaseEvent:Disconnect()
								mouseEvent:Disconnect()
								side.Resizing = false
								resizeDragOwner = nil
								resizeDragDirection = nil
								clearResizeCursor(resizer)
								return
							end
							if side.Resizing == resizer then
								local pointer = touch and position or currentMousePosition(position)
								if not touch then
									showResizeCursor(resizer, dir, pointer)
								end
								if dir == "V" then
									local delta = math.floor(pointer.Y - startPointer.Y + 0.5)
									for i, window in ipairs(windows) do
										window.SizeY = startHeights[i]
									end

									if delta > 0 then
										local neededSize = delta
										for i = pos + 1, #windows do
											local window = windows[i]
											local newSize = math.max(window.SizeY - neededSize, (window.MinY or 100))
											neededSize = neededSize - (window.SizeY - newSize)
											window.SizeY = newSize
										end
										windows[pos].SizeY = windows[pos].SizeY + math.max(0, delta - neededSize)
									else
										local neededSize = -delta
										for i = pos, 1, -1 do
											local window = windows[i]
											local newSize = math.max(window.SizeY - neededSize, (window.MinY or 100))
											neededSize = neededSize - (window.SizeY - newSize)
											window.SizeY = newSize
										end
										windows[pos + 1].SizeY = windows[pos + 1].SizeY
											+ math.max(0, -delta - neededSize)
									end

									updateSideFrames(true)
									sideResized(side)
								elseif dir == "H" then
									local maxWidth = math.max(300, sidesGui.AbsoluteSize.X - static.FreeWidth)
									local otherSide = (side == leftSide and rightSide or leftSide)
									local delta = math.floor(pointer.X - startPointer.X + 0.5)
									delta = (side == leftSide and delta or -delta)

									local proposedSize = math.max(static.MinWidth, startWidth + delta)
									if proposedSize + otherSide.Width <= maxWidth then
										side.Width = proposedSize
									else
										local newOtherSize = maxWidth - proposedSize
										if newOtherSize >= static.MinWidth then
											side.Width = proposedSize
											otherSide.Width = newOtherSize
										else
											side.Width = maxWidth - static.MinWidth
											otherSide.Width = static.MinWidth
										end
									end

									updateSideFrames(true)
									sideResized(side)
									sideResized(otherSide)
								end
							end
						end)
						mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
							if
								input == touch
								or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement)
							then
								resizeFrame:Push(input.Position)
							end
						end)
					end
				end
			end)

			resizer.InputEnded:Connect(function(input)
				if
					(
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					) and side.Resizing ~= resizer
				then
					resizer.BackgroundColor3 = theme.Button
				end
			end)
		end

		local function updateSideSeams(side, logical)
			local rail = side.Frame.Resizer
			local line = rail.Line
			if not side.SeamSizeConnection then
				side.SeamSizeConnection = Main.TrackSignal(rail:GetPropertyChangedSignal("AbsoluteSize"), function()
					if not side.LayoutApplying then
						updateSideSeams(side)
					end
				end)
			end
			local segments = side.SeamSegments or {}
			side.SeamSegments = segments
			if #side.Windows <= 1 then
				line.Visible = true
				for _, frame in ipairs(segments) do
					frame.Visible = false
				end
				return
			end
			local height = math.max(0, rail.AbsoluteSize.Y)
			local cursor, count = 0, 0
			local function segment(first, last)
				if last <= first then
					return
				end
				count += 1
				local frame = segments[count]
				if not frame then
					frame = createSimple("Frame", {
						Name = "SeamLine",
						Parent = rail,
						Active = false,
						BorderSizePixel = 0,
						BackgroundColor3 = line.BackgroundColor3,
						ZIndex = line.ZIndex,
					})
					segments[count] = frame
				end
				local pos = UDim2.new(line.Position.X.Scale, line.Position.X.Offset, 0, first)
				local size = UDim2.fromOffset(1, last - first)
				if frame.Position ~= pos then
					frame.Position = pos
				end
				if frame.Size ~= size then
					frame.Size = size
				end
				frame.Visible = true
			end
			local logicalTop = 0
			for i = 1, #side.Windows - 1 do
				local gui = side.Windows[i].GuiElems.Main
				local boundary = logical and logicalTop + side.Windows[i].SizeY
					or gui.Position.Y.Offset + gui.Size.Y.Offset
				local start = math.clamp(math.floor(boundary + 0.5), cursor, height)
				logicalTop = boundary + 4
				segment(cursor, start)
				cursor = math.min(height, start + 4)
			end
			segment(cursor, height)
			line.Visible = false
			for i = count + 1, #segments do
				segments[i].Visible = false
			end
		end

		local function renderSide(side, noTween)
			local currentPos = 0
			local sideFramePos = getSideFramePos(side)
			local template = side.WindowResizer:Clone()
			for i, v in pairs(side.ResizeCons) do
				v:Disconnect()
			end
			for i, v in pairs(side.Frame:GetChildren()) do
				if v.Name == "WindowResizer" then
					v:Destroy()
				end
			end
			side.ResizeCons = {}
			side.Dividers = {}
			side.UpdateSeams = function(logical)
				updateSideSeams(side, logical)
			end
			side.Resizing = nil

			for i, v in pairs(side.Windows) do
				v.SidePos = i
				local isEnd = i == #side.Windows
				local size = UDim2.new(0, side.Width, 0, v.SizeY)
				local pos = UDim2.new(sideFramePos.X.Scale, sideFramePos.X.Offset, 0, currentPos)
				Lib.ShowGui(v.Gui)
				if noTween then
					v.GuiElems.Main.Size = size
					v.GuiElems.Main.Position = pos
				else
					local tween =
						service.TweenService:Create(v.GuiElems.Main, sideTweenInfo, { Size = size, Position = pos })
					tweens[#tweens + 1] = tween
					tween:Play()
				end
				currentPos = currentPos + v.SizeY + 4

				if not isEnd then
					local newTemplate = template:Clone()
					side.Dividers[i] = newTemplate
					newTemplate.Position = UDim2.new(1, -side.Width, 0, currentPos - 4)
					side.ResizeCons[#side.ResizeCons + 1] = v.Gui.Main
						:GetPropertyChangedSignal("Size")
						:Connect(function()
							if side.LayoutApplying then
								return
							end
							newTemplate.Position = UDim2.new(
								1,
								-side.Width,
								0,
								v.GuiElems.Main.Position.Y.Offset + v.GuiElems.Main.Size.Y.Offset
							)
							updateSideSeams(side)
						end)
					side.ResizeCons[#side.ResizeCons + 1] = v.Gui.Main
						:GetPropertyChangedSignal("Position")
						:Connect(function()
							if side.LayoutApplying then
								return
							end
							newTemplate.Position = UDim2.new(
								1,
								-side.Width,
								0,
								v.GuiElems.Main.Position.Y.Offset + v.GuiElems.Main.Size.Y.Offset
							)
							updateSideSeams(side)
						end)
					sideResizerHook(newTemplate, "V", side, i)
					newTemplate.Parent = side.Frame
				end
			end

			updateSideSeams(side)
		end

		local function updateSide(side, noTween)
			local sizes = measureSide(side.Windows)
			for i, win in ipairs(side.Windows) do
				win.SizeY = sizes[i]
			end
			renderSide(side, noTween)
		end

		updateWindows = function(noTween)
			updateSideFrames(noTween)
			updateSide(leftSide, noTween)
			updateSide(rightSide, noTween)
			local count = 0
			for i = #visibleWindows, 1, -1 do
				visibleWindows[i].Gui.DisplayOrder = displayOrderStart + count
				Lib.ShowGui(visibleWindows[i].Gui)
				count = count + 1
			end

		end

		funcs.SetMinimized = function(self, set, mode)
			local titleHeight = self.TitleBarHeight or 28
			local oldVal = self.Minimized
			local newVal
			if set == nil then
				newVal = not self.Minimized
			else
				newVal = set
			end
			self.Minimized = newVal
			if not mode then
				mode = 1
			end

			local resizeControls = self.GuiElems.ResizeControls
			local minimizeControls = { "North", "NorthEast", "NorthWest", "South", "SouthEast", "SouthWest" }
			for i = 1, #minimizeControls do
				local control = resizeControls:FindFirstChild(minimizeControls[i])
				if control then
					control.Visible = not newVal
				end
			end

			if mode == 1 or mode == 2 then
				self:StopTweens()
				if mode == 1 then
					self.GuiElems.Main:TweenSize(
						UDim2.new(0, self.SizeX, 0, newVal and titleHeight or self.SizeY),
						Enum.EasingDirection.Out,
						Enum.EasingStyle.Quart,
						0.25,
						true
					)
				else
					local maxY = sidesGui.AbsoluteSize.Y
					local newPos = UDim2.new(
						0,
						self.PosX,
						0,
						newVal and math.min(maxY - titleHeight, self.PosY + self.SizeY - titleHeight)
							or math.max(0, self.PosY - self.SizeY + titleHeight)
					)

					self.GuiElems.Main:TweenPosition(
						newPos,
						Enum.EasingDirection.Out,
						Enum.EasingStyle.Quart,
						0.25,
						true
					)
					self.GuiElems.Main:TweenSize(
						UDim2.new(0, self.SizeX, 0, newVal and titleHeight or self.SizeY),
						Enum.EasingDirection.Out,
						Enum.EasingStyle.Quart,
						0.25,
						true
					)
				end
				self.GuiElems.Minimize.ImageLabel.Image = newVal
						and (Lib.PanelAsset("pinned") or "rbxassetid://5060023708")
					or (Lib.PanelAsset("pin") or "rbxassetid://5034768003")
			else
				self.GuiElems.Main.Size = UDim2.fromOffset(self.SizeX, newVal and titleHeight or self.SizeY)
				self.GuiElems.Minimize.ImageLabel.Image = newVal
						and (Lib.PanelAsset("pinned") or "rbxassetid://5060023708")
					or (Lib.PanelAsset("pin") or "rbxassetid://5034768003")
			end

			if oldVal ~= newVal then
				if newVal then
					self.OnMinimize:Fire()
				else
					self.OnRestore:Fire()
				end
			end
		end

		funcs.Resize = function(self, sizeX, sizeY)
			self.SizeX = sizeX or self.SizeX
			self.SizeY = sizeY or self.SizeY
			self.GuiElems.Main.Size = UDim2.new(0, self.SizeX, 0, self.SizeY)
		end

		funcs.SetSize = funcs.Resize

		funcs.SetTitle = function(self, title)
			self.GuiElems.Title.Text = title
		end

		funcs.SetTitleBarHeight = function(self, height)
			height = math.clamp(math.floor(height), 20, 48)
			self.TitleBarHeight = height
			self.GuiElems.TopBar.Size = UDim2.new(1, 0, 0, height)
			self.GuiElems.Content.Position = UDim2.fromOffset(0, height)
			self.GuiElems.Content.Size = UDim2.new(1, 0, 1, -height)
			for _, name in ipairs({ "Close", "Minimize" }) do
				local button = self.GuiElems[name]
				button.Position =
					UDim2.new(button.Position.X.Scale, button.Position.X.Offset, 0, math.floor((height - 16) / 2))
			end
			if self.Minimized then
				self.GuiElems.Main.Size = UDim2.fromOffset(self.SizeX, height)
			end
		end

		funcs.SetResizeHandleStyle = function(self, style)
			self.ResizeHandleStyle = style
			local controls = self.GuiElems.ResizeControls
			for _, name in ipairs({
				"North",
				"South",
				"East",
				"West",
				"NorthEast",
				"NorthWest",
				"SouthEast",
				"SouthWest",
			}) do
				local handle = controls[name]
				local bar = handle:FindFirstChild("ResizeBar")
				if bar then
					bar:Destroy()
				end
				handle.BackgroundTransparency = 1
				if style == "Dock" and (name == "North" or name == "South" or name == "East" or name == "West") then
					local horizontal = name == "North" or name == "South"
					bar = createSimple("Frame", {
						Name = "ResizeBar",
						Parent = handle,
						Active = false,
						BorderSizePixel = 0,
						Visible = true,
						BackgroundColor3 = theme.Button,
						ZIndex = handle.ZIndex + 1,
						Position = horizontal and UDim2.fromOffset(-10, name == "North" and 0 or 5)
							or UDim2.fromOffset(name == "West" and 0 or 5, -5),
						Size = horizontal and UDim2.new(1, 20, 0, 5) or UDim2.new(0, 5, 1, 10),
					})
					createSimple("Frame", {
						Name = "Line",
						Parent = bar,
						Active = false,
						BorderSizePixel = 0,
						BackgroundColor3 = Color3.fromRGB(36, 36, 36),
						ZIndex = bar.ZIndex + 1,
						Position = name == "South" and UDim2.new(0, 0, 1, -1)
							or name == "East" and UDim2.new(1, -1, 0, 0)
							or UDim2.fromOffset(0, 0),
						Size = horizontal and UDim2.new(1, 0, 0, 1) or UDim2.new(0, 1, 1, 0),
					})
					if horizontal then
						for _, right in ipairs({ false, true }) do
							createSimple("Frame", {
								Name = right and "RightBorder" or "LeftBorder",
								Parent = bar,
								Active = false,
								BorderSizePixel = 0,
								BackgroundColor3 = Color3.fromRGB(36, 36, 36),
								ZIndex = bar.ZIndex + 1,
								Position = right and UDim2.new(1, -1, 0, 0) or UDim2.fromOffset(0, 0),
								Size = UDim2.new(0, 1, 1, 0),
							})
						end
					end
				end
			end
		end
		funcs.SetResizable = function(self, val)
			self.Resizable = val
			self.GuiElems.ResizeControls.Visible = self.Resizable and self.ResizableInternal
		end

		funcs.SetResizableInternal = function(self, val)
			self.ResizableInternal = val
			self.GuiElems.ResizeControls.Visible = self.Resizable and self.ResizableInternal
		end

		funcs.SetAligned = function(self, val)
			self.Aligned = val
			self:SetResizableInternal(not val)
			self.GuiElems.Main.Active = not val
			self.GuiElems.Main.Outlines.Visible = not val
			if not val then
				for i, v in pairs(leftSide.Windows) do
					if v == self then
						table.remove(leftSide.Windows, i)
						break
					end
				end
				for i, v in pairs(rightSide.Windows) do
					if v == self then
						table.remove(rightSide.Windows, i)
						break
					end
				end
				if not table.find(visibleWindows, self) then
					table.insert(visibleWindows, 1, self)
				end
				self.GuiElems.Minimize.ImageLabel.Image = Lib.PanelAsset("pin") or "rbxassetid://5034768003"
				self.Side = nil
				updateWindows()
			else
				self:SetMinimized(false, 3)
				for i, v in pairs(visibleWindows) do
					if v == self then
						table.remove(visibleWindows, i)
						break
					end
				end
				self.GuiElems.Minimize.ImageLabel.Image = Lib.PanelAsset("pin") or "rbxassetid://5448127505"
			end
		end

		funcs.Add = function(self, obj, name)
			if type(obj) == "table" and obj.Gui and obj.Gui:IsA("GuiObject") then
				obj.Gui.Parent = self.ContentPane
			else
				obj.Parent = self.ContentPane
			end
			if name then
				self.Elements[name] = obj
			end
		end

		funcs.GetElement = function(self, obj, name)
			return self.Elements[name]
		end

		funcs.AlignTo = function(self, side, pos, size, silent)
			if table.find(side.Windows, self) or self.Closed then
				return
			end

			size = size or self.SizeY
			if size > 0 and size <= 1 then
				local totalSideHeight = 0
				for i, v in pairs(side.Windows) do
					totalSideHeight = totalSideHeight + v.SizeY
				end
				self.SizeY = (totalSideHeight > 0 and totalSideHeight * size * 2) or size
			else
				self.SizeY = (size > 0 and size or 100)
			end

			self:SetAligned(true)
			self.Side = side
			self.SizeX = side.Width
			self.Gui.DisplayOrder = sideDisplayOrder + 1
			for i, v in pairs(side.Windows) do
				v.Gui.DisplayOrder = sideDisplayOrder
			end
			pos = math.min(#side.Windows + 1, pos or 1)
			self.SidePos = pos
			table.insert(side.Windows, pos, self)

			if not silent then
				side.Hidden = false
			end
			updateWindows(silent)
		end

		funcs.Close = function(self, instant)
			self.Closed = true
			self:SetResizableInternal(false)

			Lib.FindAndRemove(leftSide.Windows, self)
			Lib.FindAndRemove(rightSide.Windows, self)
			Lib.FindAndRemove(visibleWindows, self)

			self.MinimizeAnim.Disable()
			self.CloseAnim.Disable()
			self.ClosedSide = self.Side
			self.Side = nil
			self.OnDeactivate:Fire()

			if instant == true then
				self:StopTweens()
			elseif not self.Aligned then
				self:StopTweens()
				local ti = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

				local closeTime = tick()
				self.LastClose = closeTime

				self:DoTween(self.GuiElems.Main, ti, { Size = UDim2.new(0, self.SizeX, 0, self.TitleBarHeight or 28) })
				self:DoTween(self.GuiElems.Title, ti, { TextTransparency = 1 })
				self:DoTween(self.GuiElems.Minimize.ImageLabel, ti, { ImageTransparency = 1 })
				self:DoTween(self.GuiElems.Close.ImageLabel, ti, { ImageTransparency = 1 })
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then
					return
				end

				self:DoTween(self.GuiElems.TopBar, ti, { BackgroundTransparency = 1 })
				self:DoTween(self.GuiElems.Outlines, ti, { ImageTransparency = 1 })
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then
					return
				end
			end

			self.Aligned = false
			self.Gui.Parent = nil
			updateWindows(true)
		end

		funcs.Destroy = function(self)
			self.Closed = true
			self:SetResizableInternal(false)

			Lib.FindAndRemove(leftSide.Windows, self)
			Lib.FindAndRemove(rightSide.Windows, self)
			Lib.FindAndRemove(visibleWindows, self)

			self.MinimizeAnim.Disable()
			self.CloseAnim.Disable()
			self.ClosedSide = self.Side
			self.Side = nil
			self.OnDeactivate:Fire()

			if not self.Aligned then
				self:StopTweens()
				local ti = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

				local closeTime = tick()
				self.LastClose = closeTime

				self:DoTween(self.GuiElems.Main, ti, { Size = UDim2.new(0, self.SizeX, 0, self.TitleBarHeight or 28) })
				self:DoTween(self.GuiElems.Title, ti, { TextTransparency = 1 })
				self:DoTween(self.GuiElems.Minimize.ImageLabel, ti, { ImageTransparency = 1 })
				self:DoTween(self.GuiElems.Close.ImageLabel, ti, { ImageTransparency = 1 })
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then
					return
				end

				self:DoTween(self.GuiElems.TopBar, ti, { BackgroundTransparency = 1 })
				self:DoTween(self.GuiElems.Outlines, ti, { ImageTransparency = 1 })
				Lib.FastWait(0.2)
				if closeTime ~= self.LastClose then
					return
				end
			end

			self.Aligned = false
			updateWindows(true)
			self.Gui:Destroy()
		end

		funcs.Hide = funcs.Close

		funcs.IsVisible = function(self)
			return not self.Closed and ((self.Side and not self.Side.Hidden) or not self.Side)
		end

		funcs.IsContentVisible = function(self)
			return self:IsVisible() and not self.Minimized
		end

		funcs.Focus = function(self)
			moveToTop(self)
		end

		funcs.MoveInBoundary = function(self)
			local posX, posY = self.PosX, self.PosY
			local maxX, maxY = sidesGui.AbsoluteSize.X, sidesGui.AbsoluteSize.Y
			posX = math.max(0, math.min(posX, maxX - self.SizeX))
			posY = math.max(0, math.min(posY, maxY - (self.TitleBarHeight or 28)))
			self.GuiElems.Main.Position = UDim2.new(0, posX, 0, posY)
		end

		funcs.DoTween = function(self, ...)
			local tween = service.TweenService:Create(...)
			self.Tweens[#self.Tweens + 1] = tween
			tween:Play()
		end

		funcs.StopTweens = function(self)
			for i, v in pairs(self.Tweens) do
				v:Cancel()
			end
			self.Tweens = {}
		end

		funcs.Show = function(self, data)
			return static.ShowWindow(self, data)
		end

		funcs.ShowAndFocus = function(self, data)
			static.ShowWindow(self, data)
			service.RunService.RenderStepped:wait()
			self:Focus()
		end

		static.ShowWindow = function(window, data)
			data = data or {}
			local align = data.Align
			local pos = data.Pos
			local size = data.Size
			local targetSide = (align == "left" and leftSide) or (align == "right" and rightSide)

			if not window.Closed then
				if not window.Aligned then
					window:SetMinimized(false)
				elseif window.Side and not data.Silent then
					static.SetSideVisible(window.Side, true)
				end
				return
			end

			window.Closed = false
			window.LastClose = tick()
			window.GuiElems.Title.TextTransparency = 0
			window.GuiElems.Minimize.ImageLabel.ImageTransparency = 0
			window.GuiElems.Close.ImageLabel.ImageTransparency = 0
			window.GuiElems.TopBar.BackgroundTransparency = 0
			window.GuiElems.Outlines.ImageTransparency = 0
			window.GuiElems.Minimize.ImageLabel.Image = Lib.PanelAsset("pin") or "rbxassetid://5034768003"
			window.GuiElems.Main.Active = true
			window.GuiElems.Main.Outlines.Visible = true
			window:SetMinimized(false, 3)
			window:SetResizableInternal(true)
			window.MinimizeAnim.Enable()
			window.CloseAnim.Enable()

			if align then
				window:AlignTo(targetSide, pos, size, data.Silent)
			else
				if align == nil and window.ClosedSide then
					window:AlignTo(window.ClosedSide, window.SidePos, size, true)
					static.SetSideVisible(window.ClosedSide, true)
				else
					if table.find(visibleWindows, window) then
						return
					end

					window.GuiElems.Main.Size = UDim2.new(0, window.SizeX, 0, window.TitleBarHeight or 28)
					local ti = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					window:StopTweens()
					window:DoTween(window.GuiElems.Main, ti, { Size = UDim2.new(0, window.SizeX, 0, window.SizeY) })

					window.SizeY = size or window.SizeY
					table.insert(visibleWindows, 1, window)
					updateWindows()
				end
			end

			window.ClosedSide = nil
			window.OnActivate:Fire()
		end

		static.ToggleSide = function(name)
			local side = (name == "left" and leftSide or rightSide)
			return static.SetSideVisible(side, side.Hidden)
		end

		static.SetSideVisible = function(s, vis)
			local side = (type(s) == "table" and s) or (s == "left" and leftSide or rightSide)
			if side.Hidden == not vis then
				return true
			end
			local transition = { Side = side == leftSide and "left" or "right", Visible = vis, Cancel = false }
			static.BeforeSideVisibilityChange:Fire(transition)
			if transition.Cancel then
				return false
			end
			side.Hidden = not vis
			for i, v in pairs(side.Windows) do
				if side.Hidden then
					v.OnDeactivate:Fire()
				else
					v.OnActivate:Fire()
				end
			end
			updateWindows()
			if static.Layout then
				static.Layout:Schedule()
			end
			return true
		end

		static.ConfigureLayoutPersistence = function(windows)
			static.Layout = Apps.WindowLayout.Create(windows, { left = leftSide, right = rightSide }, updateWindows)
			return static.Layout
		end

		static.Init = function()
			displayOrderStart = Main.DisplayOrders.Window
			sideDisplayOrder = Main.DisplayOrders.SideWindow

			sidesGui = Instance.new("ScreenGui")
			local leftFrame = create({
				{
					1,
					"Frame",
					{
						Active = true,
						Name = "LeftSide",
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
					},
				},
				{
					2,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.2549019753933, 0.2549019753933, 0.2549019753933),
						BorderSizePixel = 0,
						Name = "Resizer",
						Parent = { 1 },
						Size = UDim2.new(0, 5, 1, 0),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 2 },
						Position = UDim2.new(0, 0, 0, 0),
						Size = UDim2.new(0, 1, 1, 0),
					},
				},
				{
					4,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.2549019753933, 0.2549019753933, 0.2549019753933),
						BorderSizePixel = 0,
						Name = "WindowResizer",
						Parent = { 1 },
						Position = UDim2.new(1, -300, 0, 0),
						Size = UDim2.new(1, 0, 0, 4),
					},
				},
				{
					5,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 4 },
						Size = UDim2.new(1, 0, 0, 1),
					},
				},
			})
			leftSide.Frame = leftFrame
			leftFrame.Position = UDim2.new(0, -leftSide.Width - 10, 0, 0)
			leftSide.WindowResizer = leftFrame.WindowResizer
			leftFrame.WindowResizer.Parent = nil
			leftFrame.Parent = sidesGui

			local rightFrame = create({
				{
					1,
					"Frame",
					{
						Active = true,
						Name = "RightSide",
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
					},
				},
				{
					2,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.2549019753933, 0.2549019753933, 0.2549019753933),
						BorderSizePixel = 0,
						Name = "Resizer",
						Parent = { 1 },
						Size = UDim2.new(0, 5, 1, 0),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 2 },
						Position = UDim2.new(0, 4, 0, 0),
						Size = UDim2.new(0, 1, 1, 0),
					},
				},
				{
					4,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.2549019753933, 0.2549019753933, 0.2549019753933),
						BorderSizePixel = 0,
						Name = "WindowResizer",
						Parent = { 1 },
						Position = UDim2.new(1, -300, 0, 0),
						Size = UDim2.new(1, 0, 0, 4),
					},
				},
				{
					5,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 4 },
						Size = UDim2.new(1, 0, 0, 1),
					},
				},
			})
			rightSide.Frame = rightFrame
			rightFrame.Position = UDim2.new(1, 10, 0, 0)
			rightSide.WindowResizer = rightFrame.WindowResizer
			rightFrame.WindowResizer.Parent = nil
			rightFrame.Parent = sidesGui

			if Settings.Window.Transparency and Settings.Window.Transparency > 0 then
				leftSide.BackgroundTransparency = 1
				rightSide.BackgroundTransparency = 1

				leftFrame.BackgroundTransparency = 1
				rightFrame.BackgroundTransparency = 1
			end

			sideResizerHook(leftFrame.Resizer, "H", leftSide)
			sideResizerHook(rightFrame.Resizer, "H", rightSide)

			alignIndicator = Instance.new("ScreenGui")
			alignIndicator.DisplayOrder = Main.DisplayOrders.Menu + 1
			local indicator = Instance.new("Frame", alignIndicator)
			indicator.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
			indicator.BorderSizePixel = 0
			indicator.BackgroundTransparency = 0.8
			indicator.Name = "Indicator"
			local corner = Instance.new("UICorner", indicator)
			corner.CornerRadius = UDim.new(0, 2)
			createSimple("UIStroke", { Parent = indicator, Color = Settings.Theme.Focus, Thickness = 1 })

			local leftToggle = create({
				{
					1,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BorderColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderMode = 2,
						Font = 10,
						Name = "LeftToggle",
						Position = UDim2.new(0, 0, 0, -36),
						Size = UDim2.new(0, 16, 0, 36),
						Text = "<",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
					},
				},
			})
			local rightToggle = leftToggle:Clone()
			for _, button in ipairs({ leftToggle, rightToggle }) do
				button.Size = UDim2.fromOffset(24, 28)
				button.BorderSizePixel = 0
				button.BackgroundColor3 = Settings.Theme.Main1
				Lib.StudioCorner(button, 4)
				Lib.StudioIcon(button, "Sidebar")
				Lib.StudioTooltip(button, "Show or hide sidebar")
			end
			rightToggle.Name = "RightToggle"
			rightToggle.Position = UDim2.new(1, -16, 0, -36)
			Lib.ButtonAnim(leftToggle, { Mode = 2, PressColor = Color3.fromRGB(32, 32, 32) })
			Lib.ButtonAnim(rightToggle, { Mode = 2, PressColor = Color3.fromRGB(32, 32, 32) })

			leftToggle.MouseButton1Click:Connect(function()
				static.ToggleSide("left")
			end)

			rightToggle.MouseButton1Click:Connect(function()
				static.ToggleSide("right")
			end)

			leftToggle.Parent = sidesGui
			rightToggle.Parent = sidesGui

			sidesGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				local maxWidth = math.max(300, sidesGui.AbsoluteSize.X - static.FreeWidth)
				leftSide.Width = math.max(static.MinWidth, math.min(leftSide.Width, maxWidth - rightSide.Width))
				rightSide.Width = math.max(static.MinWidth, math.min(rightSide.Width, maxWidth - leftSide.Width))
				for i = 1, #visibleWindows do
					visibleWindows[i]:MoveInBoundary()
				end
				updateWindows(true)
			end)

			sidesGui.DisplayOrder = sideDisplayOrder - 1
			Lib.ShowGui(sidesGui)
			updateSideFrames()
		end

		local mt = { __index = funcs }
		static.new = function()
			local obj = setmetatable({
				Minimized = false,
				Dragging = false,
				Resizing = false,
				Aligned = false,
				Draggable = true,
				Resizable = true,
				ResizableInternal = true,
				Alignable = true,
				Closed = true,
				SizeX = 300,
				SizeY = 300,
				MinX = 200,
				MinY = 200,
				PosX = 0,
				PosY = 0,
				GuiElems = {},
				Tweens = {},
				Elements = {},
				OnActivate = Lib.Signal.new(),
				OnDeactivate = Lib.Signal.new(),
				OnMinimize = Lib.Signal.new(),
				OnRestore = Lib.Signal.new(),
			}, mt)
			obj.Gui = createGui(obj)
			return obj
		end

		return static
	end)()

	Lib.ContextMenu = (function()
		local funcs = {}
		local mouse

		local function createGui(self)
			local contextGui = create({
				{ 1, "ScreenGui", { DisplayOrder = 1000000, Name = "Context", ZIndexBehavior = 1 } },
				{
					2,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						Name = "Main",
						Parent = { 1 },
						Position = UDim2.new(0.5, -100, 0.5, -150),
						Size = UDim2.new(0, 200, 0, 100),
					},
				},
				{ 3, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 2 } } },
				{
					4,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						Name = "Container",
						Parent = { 2 },
						Position = UDim2.new(0, 1, 0, 1),
						Size = UDim2.new(1, -2, 1, -2),
					},
				},
				{ 5, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 4 } } },
				{
					6,
					"ScrollingFrame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						CanvasSize = UDim2.new(0, 0, 0, 0),
						Name = "List",
						Parent = { 4 },
						Position = UDim2.new(0, 2, 0, 2),
						ScrollBarImageColor3 = Color3.new(0, 0, 0),
						ScrollBarThickness = 4,
						Size = UDim2.new(1, -4, 1, -4),
						VerticalScrollBarInset = 1,
					},
				},
				{ 7, "UIListLayout", { Parent = { 6 }, SortOrder = 2 } },
				{
					8,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BorderSizePixel = 0,
						Name = "SearchFrame",
						Parent = { 4 },
						Size = UDim2.new(1, 0, 0, 24),
						Visible = false,
					},
				},
				{
					9,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.1176470592618, 0.1176470592618, 0.1176470592618),
						BorderSizePixel = 0,
						Name = "SearchContainer",
						Parent = { 8 },
						Position = UDim2.new(0, 3, 0, 3),
						Size = UDim2.new(1, -6, 0, 18),
					},
				},
				{
					10,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "SearchBox",
						Parent = { 9 },
						PlaceholderColor3 = Color3.new(0.39215689897537, 0.39215689897537, 0.39215689897537),
						PlaceholderText = "Search",
						Position = UDim2.new(0, 4, 0, 0),
						Size = UDim2.new(1, -8, 0, 18),
						Text = "",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{ 11, "UICorner", { CornerRadius = UDim.new(0, 2), Parent = { 9 } } },
				{
					12,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 8 },
						Position = UDim2.new(0, 0, 1, 0),
						Size = UDim2.new(1, 0, 0, 1),
					},
				},
				{
					13,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.33725491166115, 0.49019610881805, 0.73725491762161),
						BorderSizePixel = 0,
						Font = 3,
						Name = "Entry",
						Parent = { 1 },
						Size = UDim2.new(1, 0, 0, 22),
						Text = "",
						TextSize = 14,
						Visible = false,
					},
				},
				{
					14,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "EntryName",
						Parent = { 13 },
						Position = UDim2.new(0, 24, 0, 0),
						Size = UDim2.new(1, -24, 1, 0),
						Text = "Duplicate",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					15,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Shortcut",
						Parent = { 13 },
						Position = UDim2.new(0, 24, 0, 0),
						Size = UDim2.new(1, -30, 1, 0),
						Text = "Ctrl+D",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					16,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						ImageRectOffset = Vector2.new(304, 0),
						ImageRectSize = Vector2.new(16, 16),
						Name = "Icon",
						Parent = { 13 },
						Position = UDim2.new(0, 2, 0, 3),
						ScaleType = 4,
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{ 17, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 13 } } },
				{
					18,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.21568629145622, 0.21568629145622, 0.21568629145622),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "Divider",
						Parent = { 1 },
						Position = UDim2.new(0, 0, 0, 20),
						Size = UDim2.new(1, 0, 0, 7),
						Visible = false,
					},
				},
				{
					19,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 18 },
						Position = UDim2.new(0, 0, 0.5, 0),
						Size = UDim2.new(1, 0, 0, 1),
					},
				},
				{
					20,
					"TextLabel",
					{
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "DividerName",
						Parent = { 18 },
						Position = UDim2.new(0, 2, 0.5, 0),
						Size = UDim2.new(1, -4, 1, 0),
						Text = "Objects",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
						TextTransparency = 0.60000002384186,
						TextXAlignment = 0,
						Visible = false,
					},
				},
			})

			contextGui.Main.BorderSizePixel = 0
			contextGui.Main.BackgroundColor3 = Settings.Theme.Outline1
			Lib.StudioCorner(contextGui.Main, 7)
			contextGui.Main.Container.BorderSizePixel = 0
			contextGui.Main.Container.BackgroundColor3 = Settings.Theme.Menu
			Lib.StudioCorner(contextGui.Main.Container, 7)
			contextGui.Entry.Size = UDim2.new(1, 0, 0, 28)
			contextGui.Entry.Icon.Position = UDim2.fromOffset(6, 5)
			contextGui.Entry.EntryName.Position = UDim2.fromOffset(30, 0)
			contextGui.Entry.EntryName.Size = UDim2.new(1, -36, 1, 0)
			contextGui.Entry.Shortcut.TextColor3 = Settings.Theme.PlaceholderText
			contextGui.Main.Container.List.ScrollBarImageColor3 = Settings.Theme.PlaceholderText
			local search = contextGui.Main.Container.SearchFrame
			search.Size = UDim2.new(1, 0, 0, 38)
			search.BackgroundColor3 = Settings.Theme.Menu
			search.SearchContainer.Position = UDim2.fromOffset(6, 5)
			search.SearchContainer.Size = UDim2.new(1, -12, 0, 28)
			search.SearchContainer.BackgroundColor3 = Settings.Theme.TextBox
			Lib.StudioCorner(search.SearchContainer, 5)
			search.SearchContainer.SearchBox.Size = UDim2.new(1, -16, 1, 0)
			search.SearchContainer.SearchBox.Position = UDim2.fromOffset(8, 0)
			search.SearchContainer.SearchBox.PlaceholderColor3 = Settings.Theme.PlaceholderText
			search.SearchContainer.SearchBox.ClearTextOnFocus = false
			self.GuiElems.Main = contextGui.Main
			self.GuiElems.List = contextGui.Main.Container.List
			self.GuiElems.Entry = contextGui.Entry
			self.GuiElems.Divider = contextGui.Divider
			self.GuiElems.SearchFrame = contextGui.Main.Container.SearchFrame
			self.GuiElems.SearchBar = self.GuiElems.SearchFrame.SearchContainer.SearchBox
			Lib.ViewportTextBox.convert(self.GuiElems.SearchBar)

			self.GuiElems.SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
				local lower, find = string.lower, string.find
				local searchText = lower(self.GuiElems.SearchBar.Text)
				local items = self.Items
				local map = self.ItemToEntryMap

				if searchText ~= "" then
					local results = {}
					local count = 1
					for i = 1, #items do
						local item = items[i]
						local entry = map[item]
						if entry then
							if not item.Divider and find(lower(item.Name), searchText, 1, true) then
								results[count] = item
								count = count + 1
							else
								entry.Visible = false
							end
						end
					end
					table.sort(results, function(a, b)
						return a.Name < b.Name
					end)
					for i = 1, #results do
						local entry = map[results[i]]
						entry.LayoutOrder = i
						entry.Visible = true
					end
				else
					for i = 1, #items do
						local entry = map[items[i]]
						if entry then
							entry.LayoutOrder = i
							entry.Visible = true
						end
					end
				end

				local toSize = self.GuiElems.List.UIListLayout.AbsoluteContentSize.Y + 6
				self.GuiElems.List.CanvasSize = UDim2.new(0, 0, 0, toSize - 6)
			end)

			return contextGui
		end

		funcs.Add = function(self, item)
			local newItem = {
				Name = item.Name or "Item",
				Icon = item.Icon or "",
				Shortcut = item.Shortcut or "",
				OnClick = item.OnClick,
				OnHover = item.OnHover,
				Disabled = item.Disabled or false,
				DisabledIcon = item.DisabledIcon or "",
				IconMap = item.IconMap,
				OnRightClick = item.OnRightClick,
			}

			newItem.DisabledIcon = newItem.Icon

			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Items[#self.Items + 1] = newItem
			self.Updated = nil
		end

		funcs.AddRegistered = function(self, name, disabled)
			if not self.Registered[name] then
				error(name .. " is not registered")
			end

			if self.QueuedDivider then
				local text = self.QueuedDividerText and #self.QueuedDividerText > 0 and self.QueuedDividerText
				self:AddDivider(text)
			end
			self.Registered[name].Disabled = disabled
			self.Items[#self.Items + 1] = self.Registered[name]
			self.Updated = nil
		end

		funcs.Register = function(self, name, item)
			self.Registered[name] = {
				Name = item.Name or "Item",
				Icon = item.Icon or "",
				Shortcut = item.Shortcut or "",
				OnClick = item.OnClick,
				OnHover = item.OnHover,
				DisabledIcon = item.DisabledIcon or "",
				IconMap = item.IconMap,
				OnRightClick = item.OnRightClick,
			}
		end

		funcs.UnRegister = function(self, name)
			self.Registered[name] = nil
		end

		funcs.AddDivider = function(self, text)
			self.QueuedDivider = false
			local textWidth = text
					and service.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(999999999, 20)).X
				or nil
			table.insert(self.Items, { Divider = true, Text = text, TextSize = textWidth and textWidth + 4 })
			self.Updated = nil
		end

		funcs.QueueDivider = function(self, text)
			self.QueuedDivider = true
			self.QueuedDividerText = text or ""
		end

		funcs.Clear = function(self)
			self.Items = {}
			self.Updated = nil
		end

		funcs.Refresh = function(self)
			for i, v in pairs(self.GuiElems.List:GetChildren()) do
				if not v:IsA("UIListLayout") then
					v:Destroy()
				end
			end
			local map = {}
			self.ItemToEntryMap = map

			local dividerFrame = self.GuiElems.Divider
			local contextList = self.GuiElems.List
			local entryFrame = self.GuiElems.Entry
			local items = self.Items

			for i = 1, #items do
				local item = items[i]
				if item.Divider then
					local newDivider = dividerFrame:Clone()
					newDivider.Line.BackgroundColor3 = self.Theme.DividerColor
					if item.Text then
						newDivider.Size = UDim2.new(1, 0, 0, 20)
						newDivider.Line.Position = UDim2.new(0, item.TextSize, 0.5, 0)
						newDivider.Line.Size = UDim2.new(1, -item.TextSize, 0, 1)
						newDivider.DividerName.TextColor3 = self.Theme.TextColor
						newDivider.DividerName.Text = item.Text
						newDivider.DividerName.Visible = true
					end
					newDivider.Visible = true
					map[item] = newDivider
					newDivider.Parent = contextList
				else
					local newEntry = entryFrame:Clone()
					newEntry.BackgroundColor3 = self.Theme.HighlightColor
					newEntry.EntryName.TextColor3 = self.Theme.TextColor
					newEntry.EntryName.Text = item.Name
					newEntry.Shortcut.Text = item.Shortcut
					local shortcutWidth = item.Shortcut ~= ""
							and service.TextService:GetTextSize(
								item.Shortcut,
								14,
								Lib.StudioFont,
								Vector2.new(1000, 26)
							).X + 16
						or 0
					newEntry.EntryName.Size = UDim2.new(1, -36 - shortcutWidth, 1, 0)
					newEntry.EntryName.TextTruncate = Enum.TextTruncate.AtEnd
					if item.Disabled then
						newEntry.EntryName.TextColor3 = Color3.new(150 / 255, 150 / 255, 150 / 255)
						newEntry.Shortcut.TextColor3 = Color3.new(150 / 255, 150 / 255, 150 / 255)
					end

					if self.Iconless then
						newEntry.EntryName.Position = UDim2.new(0, 12, 0, 0)
						newEntry.EntryName.Size = UDim2.new(1, -18, 1, 0)
						newEntry.Icon.Visible = false
					else
						local iconIndex
						if item.Disabled and item.DisabledIcon then
							iconIndex = item.DisabledIcon
						elseif item.Icon then
							iconIndex = item.Icon
						end

						if item.IconMap then
							if type(iconIndex) == "number" then
								item.IconMap:Display(newEntry.Icon, iconIndex)
							elseif type(iconIndex) == "string" then
								item.IconMap:DisplayByKey(newEntry.Icon, iconIndex)
							end
						elseif type(iconIndex) == "string" then
							newEntry.Icon.Image = iconIndex
						end
					end

					if not item.Disabled then
						if item.OnClick then
							newEntry.MouseButton1Click:Connect(function()
								item.OnClick(item.Name)
								if not item.NoHide then
									self:Hide()
								end
							end)
						end

						if item.OnRightClick then
							newEntry.MouseButton2Click:Connect(function()
								item.OnRightClick(item.Name)
								if not item.NoHide then
									self:Hide()
								end
							end)
						end
					end

					newEntry.InputBegan:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch
						then
							newEntry.BackgroundTransparency = 0
						end
					end)

					newEntry.InputEnded:Connect(function(input)
						if
							input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch
						then
							newEntry.BackgroundTransparency = 1
						end
					end)

					newEntry.Visible = true
					map[item] = newEntry
					newEntry.Parent = contextList
				end
			end
			self.Updated = true
		end

		funcs.Show = function(self, x, y)
			local elems = self.GuiElems
			elems.SearchFrame.Visible = self.SearchEnabled
			elems.List.Position = UDim2.new(0, 2, 0, 2 + (self.SearchEnabled and 38 or 0))
			elems.List.Size = UDim2.new(1, -4, 1, -4 - (self.SearchEnabled and 38 or 0))
			if self.SearchEnabled and self.ClearSearchOnShow then
				elems.SearchBar.Text = ""
			end
			self.GuiElems.List.CanvasPosition = Vector2.new(0, 0)

			if not self.Updated then
				self:Refresh()
			end

			local reverseY = false
			local x, y = x or mouse.X, y or mouse.Y
			local maxX, maxY = mouse.ViewSizeX, mouse.ViewSizeY

			if x + self.Width > maxX then
				x = self.ReverseX and x - self.Width or maxX - self.Width
			end
			elems.Main.Position = UDim2.new(0, x, 0, y)
			elems.Main.Size = UDim2.new(0, self.Width, 0, 0)
			self.Gui.DisplayOrder = Main.DisplayOrders.Menu
			Lib.ShowGui(self.Gui)

			local contentHeight = elems.List.UIListLayout.AbsoluteContentSize.Y
			local searchHeight = self.SearchEnabled and 38 or 0
			local limit = math.min(self.MaxHeight or maxY - 8, maxY - 8)
			local toSize = math.min(contentHeight + 6 + searchHeight, limit)
			elems.List.CanvasSize = UDim2.fromOffset(0, contentHeight)
			x = math.clamp(x, 0, math.max(0, maxX - self.Width))
			y = math.clamp(y, 0, math.max(0, maxY - 8))
			elems.Main.Position = UDim2.fromOffset(x, y)
			if y + toSize > maxY then
				reverseY = true
			end

			local closable
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
			end
			self.CloseEvent = Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if not closable then
					return
				end

				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if not Lib.CheckMouseInGui(elems.Main) then
						self.CloseEvent:Disconnect()
						self:Hide()
					end
				end
			end)

			if reverseY then
				elems.Main.Position = UDim2.new(0, x, 0, y - (self.ReverseYOffset or 0))
				local newY = y - toSize - (self.ReverseYOffset or 0)
				y = newY >= 0 and newY or 0
				elems.Main:TweenSizeAndPosition(
					UDim2.new(0, self.Width, 0, toSize),
					UDim2.new(0, x, 0, y),
					Enum.EasingDirection.Out,
					Enum.EasingStyle.Quart,
					0.2,
					true
				)
			else
				elems.Main:TweenSize(
					UDim2.new(0, self.Width, 0, toSize),
					Enum.EasingDirection.Out,
					Enum.EasingStyle.Quart,
					0.2,
					true
				)
			end

			Lib.FastWait()
			if self.SearchEnabled and self.FocusSearchOnShow then
				elems.SearchBar:CaptureFocus()
			end
			closable = true
		end

		funcs.Hide = function(self)
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
				self.CloseEvent = nil
			end
			self.Gui.Parent = nil
		end

		funcs.ApplyTheme = function(self, data)
			local theme = self.Theme
			theme.ContentColor = data.ContentColor or Settings.Theme.Menu
			theme.OutlineColor = data.OutlineColor or Settings.Theme.Menu
			theme.DividerColor = data.DividerColor or Settings.Theme.Outline2
			theme.TextColor = data.TextColor or Settings.Theme.Text
			theme.HighlightColor = data.HighlightColor or Settings.Theme.Main1

			self.GuiElems.Main.BackgroundColor3 = theme.OutlineColor
			self.GuiElems.Main.Container.BackgroundColor3 = theme.ContentColor
		end

		local mt = { __index = funcs }
		local function new()
			if not mouse then
				mouse = Main.Mouse or service.Players.LocalPlayer:GetMouse()
			end

			local obj = setmetatable({
				Width = 248,
				MaxHeight = nil,
				Iconless = false,
				SearchEnabled = false,
				ClearSearchOnShow = true,
				FocusSearchOnShow = true,
				Updated = false,
				QueuedDivider = false,
				QueuedDividerText = "",
				Items = {},
				Registered = {},
				GuiElems = {},
				Theme = {},
			}, mt)
			obj.Gui = createGui(obj)
			obj:ApplyTheme({})
			return obj
		end

		return { new = new }
	end)()

	function Lib.NumberEnd(text, start)
		local prefix = text:sub(start, start + 1):lower()
		if prefix == "0x" or prefix == "0b" then
			local digits = if prefix == "0x" then "^%x[%x_]*" else "^[01][01_]*"
			local _, last = text:find(digits, start + 2)
			return last or start
		end
		local _, last = text:find("^%d[%d_]*", start)
		last = last or start - 1
		if text:sub(last + 1, last + 1) == "." and text:sub(last + 2, last + 2) ~= "." then
			last += 1
			local _, fraction = text:find("^%d[%d_]*", last + 1)
			last = fraction or last
		end
		local _, exponent = text:find("^[eE][+-]?%d[%d_]*", last + 1)
		return exponent or last
	end

	function Lib.LexLine(text, hasNext, stack, closer)
		stack = stack or ""
		local spans
		local function mark(start, kind, last)
			if last < start then return end
			spans = spans or {}
			spans[start] = {kind, last}
		end
		local i = 1
		while i <= #text do
			local mode = stack:sub(-1)
			if mode == "L" or mode == "C" then
				local _, last = text:find(closer, i, true)
				mark(i, if mode == "L" then 3 else 4, last or #text)
				if not last then break end
				stack, closer, i = stack:sub(1,-2), nil, last + 1
			elseif mode == "T" or mode == "'" or mode == '"' then
				local start = i
				local delimiter = if mode == "T" then "`" else mode
				local escapedNewline = false
				while i <= #text do
					local c = text:sub(i,i)
					if c == "\\" then
						escapedNewline = i == #text
						i += 2
					elseif c == delimiter then
						stack = stack:sub(1,-2)
						i += 1
						break
					elseif mode == "T" and c == "{" then
						break
					else
						i += 1
					end
				end
				mark(start, if mode == "T" then 18 elseif mode == "'" then 2 else 1, math.min(i-1,#text))
				if mode == "T" and stack:sub(-1) == "T" and text:sub(i,i) == "{" then
					mark(i,5,i)
					stack ..= "{"
					i += 1
				elseif mode ~= "T" and stack:sub(-1) == mode and not escapedNewline then
					stack = stack:sub(1,-2)
				end
			else
				local pos = text:find(if stack == "" then "[\"'`%[%-]" else "[\"'`%[%-%{%}]", i)
				if not pos then break end
				i = pos
				local ch = text:sub(i,i)
				local comment = text:sub(i,i+1) == "--"
				local opening = if comment then i+2 else i
				local _, last, equals = text:find("^%[(=*)%[", opening)
				if last then
					stack ..= if comment then "C" else "L"
					closer = "]"..equals.."]"
					mark(i, if comment then 4 else 3, last)
					i = last + 1
				elseif comment then
					mark(i,4,#text)
					break
				elseif ch == "'" or ch == '"' or ch == "`" then
					stack ..= if ch == "`" then "T" else ch
					mark(i, if ch == "`" then 18 elseif ch == "'" then 2 else 1, i)
					i += 1
					if i > #text and ch ~= "`" then stack = stack:sub(1,-2) end
				else
					if ch == "{" then stack ..= "{"
					elseif ch == "}" then stack = stack:sub(1,-2) mark(i,5,i) end
					i += 1
				end
			end
		end
		return spans, if hasNext and stack ~= "" then stack else nil, if hasNext then closer else nil
	end

	Lib.CodeFrame = (function()
		local funcs = {}

		local typeMap = {
			[1] = "String",
			[2] = "String",
			[3] = "String",
			[4] = "Comment",
			[5] = "Operator",
			[6] = "Number",
			[7] = "Keyword",
			[8] = "BuiltIn",
			[9] = "LocalMethod",
			[10] = "LocalProperty",
			[11] = "Nil",
			[12] = "Bool",
			[13] = "Function",
			[14] = "Local",
			[15] = "Self",
			[18] = "String",
			[16] = "FunctionName",
			[17] = "Bracket",
		}

		local specialKeywordsTypes = {
			["nil"] = 11,
			["true"] = 12,
			["false"] = 12,
			["function"] = 13,
			["local"] = 14,
			["self"] = 15,
		}

		local keywords = {
			["and"] = true,
			["break"] = true,
			["continue"] = true,
			["do"] = true,
			["else"] = true,
			["elseif"] = true,
			["end"] = true,
			["false"] = true,
			["for"] = true,
			["function"] = true,
			["if"] = true,
			["in"] = true,
			["local"] = true,
			["nil"] = true,
			["not"] = true,
			["or"] = true,
			["repeat"] = true,
			["return"] = true,
			["then"] = true,
			["true"] = true,
			["until"] = true,
			["while"] = true,
			["plugin"] = true,
			["const"] = true,
			["export"] = true,
		}

		local builtIns = {
			["delay"] = true,
			["elapsedTime"] = true,
			["require"] = true,
			["spawn"] = true,
			["tick"] = true,
			["time"] = true,
			["typeof"] = true,
			["UserSettings"] = true,
			["wait"] = true,
			["warn"] = true,
			["game"] = true,
			["shared"] = true,
			["script"] = true,
			["workspace"] = true,
			["assert"] = true,
			["collectgarbage"] = true,
			["error"] = true,
			["getfenv"] = true,
			["getmetatable"] = true,
			["ipairs"] = true,
			["loadstring"] = true,
			["newproxy"] = true,
			["next"] = true,
			["pairs"] = true,
			["pcall"] = true,
			["print"] = true,
			["rawequal"] = true,
			["rawget"] = true,
			["rawset"] = true,
			["select"] = true,
			["setfenv"] = true,
			["setmetatable"] = true,
			["tonumber"] = true,
			["tostring"] = true,
			["type"] = true,
			["unpack"] = true,
			["xpcall"] = true,
			["_G"] = true,
			["_VERSION"] = true,
			["coroutine"] = true,
			["debug"] = true,
			["math"] = true,
			["os"] = true,
			["string"] = true,
			["table"] = true,
			["bit32"] = true,
			["utf8"] = true,
			["Axes"] = true,
			["BrickColor"] = true,
			["CFrame"] = true,
			["Color3"] = true,
			["ColorSequence"] = true,
			["ColorSequenceKeypoint"] = true,
			["DockWidgetPluginGuiInfo"] = true,
			["Enum"] = true,
			["Faces"] = true,
			["Instance"] = true,
			["NumberRange"] = true,
			["NumberSequence"] = true,
			["NumberSequenceKeypoint"] = true,
			["PathWaypoint"] = true,
			["PhysicalProperties"] = true,
			["Random"] = true,
			["Ray"] = true,
			["Rect"] = true,
			["Region3"] = true,
			["Region3int16"] = true,
			["TweenInfo"] = true,
			["UDim"] = true,
			["UDim2"] = true,
			["Vector2"] = true,
			["Vector2int16"] = true,
			["Vector3"] = true,
			["Vector3int16"] = true,

			["getgenv"] = true,
			["getrenv"] = true,
			["getsenv"] = true,
			["getgc"] = true,
			["getreg"] = true,
			["filtergc"] = true,
			["saveinstave"] = true,
			["decompile"] = true,
			["syn"] = true,
			["getupvalue"] = true,
			["getupvalues"] = true,
			["setupvalue"] = true,
			["getstack"] = true,
			["setstack"] = true,
			["getconstants"] = true,
			["getconstant"] = true,
			["setconstant"] = true,
			["getproto"] = true,
			["getprotos"] = true,
			["checkcaller"] = true,
			["clonefunction"] = true,
			["cloneref"] = true,
			["getfunctionhash"] = true,
			["gethwid"] = true,
			["hookfunction"] = true,
			["hookmetamethod"] = true,
			["iscclosure"] = true,
			["islclosure"] = true,
			["newcclosure"] = true,
			["isexecutorclosure"] = true,
			["restorefunction"] = true,
			["crypt"] = true,
			["Drawing"] = true,
			["gcinfo"] = true,
			["rawlen"] = true,
			["DebuggerManager"] = true,
			["plugin"] = true,
			["PluginManager"] = true,
			["printidentity"] = true,
			["settings"] = true,
			["stats"] = true,
			["version"] = true,
			["ypcall"] = true,
			["buffer"] = true,
			["task"] = true,
			["vector"] = true,
			["CatalogSearchParams"] = true,
			["Content"] = true,
			["DateTime"] = true,
			["FloatCurveKey"] = true,
			["Font"] = true,
			["InstanceHandle"] = true,
			["OverlapParams"] = true,
			["Path2DControlPoint"] = true,
			["RaycastParams"] = true,
			["RotationCurveKey"] = true,
			["SecurityCapabilities"] = true,
			["SharedTable"] = true,
			["User"] = true,
			["ValueCurveKey"] = true,
		}

		local identifierColors = {
			["getcustomasset"] = 8,
			["setthreadidentity"] = 8,
			["isfile"] = 8,
			["isfolder"] = 8,
			["getcallingscript"] = 8,
			["listfiles"] = 8,
			["getloadedmodules"] = 8,
			["getrunningscripts"] = 8,
			["makefolder"] = 8,
			["getscriptbytecode"] = 8,
			["getscriptclosure"] = 8,
			["writefile"] = 8,
			["getscriptfromthread"] = 8,
			["getscripthash"] = 8,
			["getscripts"] = 8,
			["compareinstances"] = 8,
			["fireclickdetector"] = 8,
			["fireproximityprompt"] = 8,
			["firetouchinterest"] = 8,
			["firesignal"] = 8,
			["getcallbackvalue"] = 8,
			["getconnections"] = 8,
			["gethui"] = 8,
			["replicatesignal"] = 8,
			["getinstances"] = 8,
			["getnilinstances"] = 8,
			["getnamecallmethod"] = 8,
			["getrawmetatable"] = 8,
			["isreadonly"] = 8,
			["setrawmetatable"] = 8,
			["lz4decompress"] = 8,
			["setreadonly"] = 8,
			["cleardrawcache"] = 8,
			["identifyexecutor"] = 8,
			["getrenderproperty"] = 8,
			["isrenderobj"] = 8,
			["base64decode"] = 8,
			["lz4compress"] = 8,
			["request"] = 8,
			["base64encode"] = 8,
			["readfile"] = 8,
			["getthreadidentity"] = 8,
			["appendfile"] = 8,
			["isscriptable"] = 8,
			["gethiddenproperty"] = 8,
			["setrenderproperty"] = 8,
			["delfile"] = 8,
			["sethiddenproperty"] = 8,
			["loadfile"] = 8,
			["delfolder"] = 8,
			["setscriptable"] = 8,
			["WebSocket"] = 8,
			["setclipboard"] = 8,
			["oth"] = 8,
			["setstackhidden"] = 8,
			["cache"] = 8,
			["raknet"] = 8,
			["getbspval"] = 8,
			["getpcd"] = 8,
			["saveinstance"] = 8,
			["setfpscap"] = 8,
			["zstdcompress"] = 8,
			["zstddecompress"] = 8,
			["create_comm_channel"] = 8,
			["get_comm_channel"] = 8,
			["getactors"] = 8,
			["getactorthreads"] = 8,
			["getdeletedactors"] = 8,
			["is_parallel"] = 8,
			["run_on_actor"] = 8,
			["run_on_thread"] = 8,
		}

		local builtInInited = false

		local richReplace = {
			["'"] = "&apos;",
			['"'] = "&quot;",
			["<"] = "&lt;",
			[">"] = "&gt;",
			["&"] = "&amp;",
		}

		local tabSub = "\205"
		local tabReplacement = (" %s%s "):format(tabSub, tabSub)

		local tabJumps = {
			[("[^%s] %s"):format(tabSub, tabSub)] = 0,
			[(" %s%s"):format(tabSub, tabSub)] = -1,
			[("%s%s "):format(tabSub, tabSub)] = 2,
			[("%s [^%s]"):format(tabSub, tabSub)] = 1,
		}

		local tweenService = service.TweenService
		local lineTweens = {}

		local function initBuiltIn()
			local env = getfenv()
			local type = type
			local tostring = tostring
			for name, _ in next, builtIns do
				local envVal = env[name]
				if type(envVal) == "table" then
					local items = {}
					for i, v in next, envVal do
						items[i] = true
					end
					builtIns[name] = items
				end
			end

			local enumEntries = {}
			local enums = Enum:GetEnums()
			for i = 1, #enums do
				enumEntries[tostring(enums[i])] = true
			end
			builtIns["Enum"] = enumEntries

			builtInInited = true
		end

		local function setupEditBox(obj)
			local editBox = obj.GuiElems.EditBox

			editBox.Focused:Connect(function()
				obj:ConnectEditBoxEvent()
				obj.Editing = true
			end)

			editBox.FocusLost:Connect(function()
				obj:DisconnectEditBoxEvent()
				obj.Editing = false
			end)

			editBox:GetPropertyChangedSignal("Text"):Connect(function()
				local text = editBox.Text
				if obj.EditBoxCopying or text == obj.NativeInputBuffer then
					return
				end
				if obj.HandleNativeTextChange and obj:HandleNativeTextChange(text) then
					return
				end
				if #text == 0 then
					return
				end
				obj.EditBoxCopying = true
				obj.NativeInputBuffer = ""
				editBox.Text = ""
				obj.EditBoxCopying = false
				obj:AppendText(text)
			end)
		end

		local function setupMouseSelection(obj)
			local mouse = plr:GetMouse()
			local codeFrame = obj.GuiElems.LinesFrame
			local lines = obj.Lines
			local stopDrag

			codeFrame.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if stopDrag then
						stopDrag()
					end
					local touch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
					local pointer = if touch then touch.Position else mouse
					local fontSizeX, fontSizeY = math.ceil(obj.FontSize / 2), obj.FontSize

					local relX = pointer.X - codeFrame.AbsolutePosition.X
					local relY = pointer.Y - codeFrame.AbsolutePosition.Y
					local selX = math.round(relX / fontSizeX) + obj.ViewX
					local selY = obj:DisplayToSource(math.floor(relY / fontSizeY) + obj.ViewY)
					local releaseEvent, mouseEvent, scrollEvent, focusEvent
					local scrollPowerV, scrollPowerH = 0, 0
					selY = math.min(#lines - 1, selY)
					local relativeLine = lines[selY + 1] or ""
					if obj.ScreenToEditorPoint then
						selX, selY = obj:ScreenToEditorPoint(pointer.X, pointer.Y)
					else
						selX = math.min(#relativeLine, selX + obj:TabAdjust(selX, selY))
					end

					local handled, span, trackMove, onClick
					if obj.HandleEditorPointer then
						handled, span, trackMove, onClick = obj:HandleEditorPointer(input, selX, selY)
					end
					if handled then
						return
					end
					obj:SetEditing(true, input)
					if not span then
						if obj.ViewX > 0 and Apps.CodeViewport and obj.ScrollH then
							local view = Apps.CodeViewport
							local pixel = view.GetColumnPixelX(obj, selX, selY)
							if math.round(pixel) < view.ScrollPixelX(obj) then
								obj.ScrollH:ScrollTo(math.floor(pixel / view.ColumnWidth(obj)), true)
								obj.ViewX = obj.ScrollH.Index
							end
						end
						obj.SelectionRange = { { -1, -1 }, { -1, -1 } }
						obj:MoveCursor(selX, selY)
						obj.FloatCursorX = selX
					end

					local function updateSelection()
						local relX = pointer.X - codeFrame.AbsolutePosition.X
						local relY = pointer.Y - codeFrame.AbsolutePosition.Y
						local sel2X = math.max(0, math.round(relX / fontSizeX) + obj.ViewX)
						local sel2Y = obj:DisplayToSource(math.max(0, math.floor(relY / fontSizeY) + obj.ViewY))

						sel2Y = math.min(#lines - 1, sel2Y)
						local relativeLine = lines[sel2Y + 1] or ""
						if obj.ScreenToEditorPoint then
							sel2X, sel2Y = obj:ScreenToEditorPoint(pointer.X, pointer.Y)
						else
							sel2X = math.min(#relativeLine, sel2X + obj:TabAdjust(sel2X, sel2Y))
						end

						if span then
							span(sel2X, sel2Y, pointer.X, pointer.Y)
							return
						end
						if trackMove then
							trackMove(pointer.X, pointer.Y)
						end
						if sel2Y < selY or (sel2Y == selY and sel2X < selX) then
							obj.SelectionRange = { { sel2X, sel2Y }, { selX, selY } }
						else
							obj.SelectionRange = { { selX, selY }, { sel2X, sel2Y } }
						end

						obj:MoveCursor(sel2X, sel2Y)
						obj.FloatCursorX = sel2X
						obj:Refresh()
					end

					stopDrag = function()
						releaseEvent:Disconnect()
						mouseEvent:Disconnect()
						scrollEvent:Disconnect()
						if focusEvent then
							focusEvent:Disconnect()
						end
						stopDrag = nil
					end
					releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
						if
							not touch and input.UserInputType == Enum.UserInputType.MouseButton1 or input == touch
						then
							stopDrag()
							obj:SetCopyableSelection()
							if onClick then
								onClick()
							end
						end
					end)

					mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
						if
							not touch and input.UserInputType == Enum.UserInputType.MouseMovement or input == touch
						then
							if touch then pointer = input.Position end
							local upDelta = pointer.Y - codeFrame.AbsolutePosition.Y
							local downDelta = pointer.Y - codeFrame.AbsolutePosition.Y - codeFrame.AbsoluteSize.Y
							local leftDelta = pointer.X - codeFrame.AbsolutePosition.X
							local rightDelta = pointer.X - codeFrame.AbsolutePosition.X - codeFrame.AbsoluteSize.X
							scrollPowerV = 0
							scrollPowerH = 0
							if downDelta > 0 then
								scrollPowerV = math.floor(downDelta * 0.05) + 1
							elseif upDelta < 0 then
								scrollPowerV = math.ceil(upDelta * 0.05) - 1
							end
							if rightDelta > 0 then
								scrollPowerH = math.floor(rightDelta * 0.05) + 1
							elseif leftDelta < 0 then
								scrollPowerH = math.ceil(leftDelta * 0.05) - 1
							end
							updateSelection()
						end
					end)

					scrollEvent = Main.TrackSignal(service.RunService.RenderStepped, function()
						if scrollPowerV ~= 0 or scrollPowerH ~= 0 then
							obj:ScrollDelta(scrollPowerH, scrollPowerV)
							updateSelection()
						end
					end)
					if service.UserInputService.WindowFocusReleased then
						focusEvent = Main.TrackSignal(service.UserInputService.WindowFocusReleased, stopDrag)
					end

					if span then
						span(selX, selY, mouse.X, mouse.Y)
					else
						obj:Refresh()
					end
				end
			end)
		end

		local function makeFrame(obj)
			local frame = create({
				{
					1,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.15686275064945, 0.15686275064945, 0.15686275064945),
						BorderSizePixel = 0,
						Position = UDim2.new(0.5, -300, 0.5, -200),
						Size = UDim2.new(0, 600, 0, 400),
					},
				},
			})

			if Settings.Window.Transparency and Settings.Window.Transparency > 0 then
				frame.BackgroundTransparency = 0.5
			end

			local elems = {}

			local linesFrame = Instance.new("Frame")
			linesFrame.Name = "Lines"
			linesFrame.BackgroundTransparency = 1
			linesFrame.Size = UDim2.new(1, 0, 1, 0)
			linesFrame.ClipsDescendants = true
			linesFrame.Parent = frame

			local lineNumbersLabel = Instance.new("TextLabel")
			lineNumbersLabel.Name = "LineNumbers"
			lineNumbersLabel.BackgroundTransparency = 1
			lineNumbersLabel.Font = Enum.Font.Code
			lineNumbersLabel.TextXAlignment = Enum.TextXAlignment.Right
			lineNumbersLabel.TextYAlignment = Enum.TextYAlignment.Top
			lineNumbersLabel.ClipsDescendants = true
			lineNumbersLabel.RichText = true
			lineNumbersLabel.Parent = frame

			local cursor = Instance.new("Frame")
			cursor.Name = "Cursor"
			cursor.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
			cursor.BorderSizePixel = 0
			cursor.ZIndex = 4
			cursor.Parent = frame

			local editBox = Instance.new("TextBox")
			editBox.Name = "EditBox"
			editBox.MultiLine = true
			editBox.Visible = true
			editBox.ClearTextOnFocus = false
			editBox.TextEditable = true
			editBox.BackgroundTransparency = 1
			editBox.TextTransparency = 1
			editBox.BorderSizePixel = 0
			editBox.Size = UDim2.fromOffset(1, 1)
			editBox.Active = false
			editBox.Text = ""
			editBox.Parent = frame

			lineTweens.Invis = tweenService:Create(
				cursor,
				TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }
			)
			lineTweens.Vis = tweenService:Create(
				cursor,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 0 }
			)

			elems.LinesFrame = linesFrame
			elems.LineNumbersLabel = lineNumbersLabel
			elems.Cursor = cursor
			elems.EditBox = editBox
			elems.ScrollCorner = create({
				{
					1,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.15686275064945, 0.15686275064945, 0.15686275064945),
						BorderSizePixel = 0,
						Name = "ScrollCorner",
						Position = UDim2.new(1, -16, 1, -16),
						Size = UDim2.new(0, 16, 0, 16),
						Visible = false,
					},
				},
			})

			elems.ScrollCorner.Parent = frame
			obj.Frame = frame
			obj.Gui = frame
			obj.GuiElems = elems
			setupEditBox(obj)
			setupMouseSelection(obj)

			return frame
		end

		funcs.GetSelectionText = function(self)
			if not self:IsValidRange() then
				return ""
			end

			local selectionRange = self.SelectionRange
			local selX, selY = selectionRange[1][1], selectionRange[1][2]
			local sel2X, sel2Y = selectionRange[2][1], selectionRange[2][2]
			local deltaLines = sel2Y - selY
			local lines = self.Lines

			if not lines[selY + 1] or not lines[sel2Y + 1] then
				return ""
			end

			if deltaLines == 0 then
				return self:ConvertText(lines[selY + 1]:sub(selX + 1, sel2X), false)
			end

			local leftSub = lines[selY + 1]:sub(selX + 1)
			local rightSub = lines[sel2Y + 1]:sub(1, sel2X)

			local result = leftSub .. "\n"
			for i = selY + 1, sel2Y - 1 do
				result = result .. lines[i + 1] .. "\n"
			end
			result = result .. rightSub

			return self:ConvertText(result, false)
		end

		funcs.SetCopyableSelection = function(self)
			local text = self:GetSelectionText()
			local editBox = self.GuiElems.EditBox

			self.EditBoxCopying = true
			self.NativeInputBuffer = text
			editBox.Text = text
			editBox.SelectionStart = 1
			editBox.CursorPosition = #editBox.Text + 1
			self.EditBoxCopying = false
		end

		funcs.ConnectEditBoxEvent = function(self)
			if self.EditBoxEvent then
				self.EditBoxEvent:Disconnect()
			end

			self.EditBoxEvent = Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if input.UserInputType ~= Enum.UserInputType.Keyboard then
					return
				end
				if service.UserInputService:GetFocusedTextBox() ~= self.GuiElems.EditBox then
					return
				end
				if self.TouchTextInput and not Lib.IsCtrlDown() and (input.KeyCode == Enum.KeyCode.Backspace
					or input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Return) then
					return
				end
				if self.HandleEditorInput and self:HandleEditorInput(input) then
					return
				end

				local keycodes = Enum.KeyCode
				local keycode = input.KeyCode

				local function setupMove(key, func)
					local endCon, finished
					endCon = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
						if input.KeyCode ~= key then
							return
						end
						endCon:Disconnect()
						finished = true
					end)
					func()
					Lib.FastWait(0.5)
					while not finished do
						func()
						Lib.FastWait(0.03)
					end
				end

				if keycode == keycodes.Down then
					setupMove(keycodes.Down, function()
						self.CursorX = self.FloatCursorX
						self.CursorY = self.CursorY + 1
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Up then
					setupMove(keycodes.Up, function()
						self.CursorX = self.FloatCursorX
						self.CursorY = self.CursorY - 1
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Left then
					setupMove(keycodes.Left, function()
						local line = self.Lines[self.CursorY + 1] or ""
						self.CursorX = self.CursorX
							- 1
							- (line:sub(self.CursorX - 3, self.CursorX) == tabReplacement and 3 or 0)
						if self.CursorX < 0 then
							self.CursorY = self.CursorY - 1
							local line2 = self.Lines[self.CursorY + 1] or ""
							self.CursorX = #line2
						end
						self.FloatCursorX = self.CursorX
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Right then
					setupMove(keycodes.Right, function()
						local line = self.Lines[self.CursorY + 1] or ""
						self.CursorX = self.CursorX
							+ 1
							+ (line:sub(self.CursorX + 1, self.CursorX + 4) == tabReplacement and 3 or 0)
						if self.CursorX > #line then
							self.CursorY = self.CursorY + 1
							self.CursorX = 0
						end
						self.FloatCursorX = self.CursorX
						self:UpdateCursor()
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Backspace then
					setupMove(keycodes.Backspace, function()
						local startRange, endRange
						if self:IsValidRange() then
							startRange = self.SelectionRange[1]
							endRange = self.SelectionRange[2]
						else
							endRange = { self.CursorX, self.CursorY }
						end

						if not startRange then
							local line = self.Lines[self.CursorY + 1] or ""
							self.CursorX = self.CursorX
								- 1
								- (line:sub(self.CursorX - 3, self.CursorX) == tabReplacement and 3 or 0)
							if self.CursorX < 0 then
								self.CursorY = self.CursorY - 1
								local line2 = self.Lines[self.CursorY + 1] or ""
								self.CursorX = #line2
							end
							self.FloatCursorX = self.CursorX
							self:UpdateCursor()

							startRange = startRange or { self.CursorX, self.CursorY }
						end

						self:DeleteRange({ startRange, endRange }, false, true)
						self:ResetSelection(true)
						self:JumpToCursor()
					end)
				elseif keycode == keycodes.Delete then
					setupMove(keycodes.Delete, function()
						local startRange, endRange
						if self:IsValidRange() then
							startRange = self.SelectionRange[1]
							endRange = self.SelectionRange[2]
						else
							startRange = { self.CursorX, self.CursorY }
						end

						if not endRange then
							local line = self.Lines[self.CursorY + 1] or ""
							local endCursorX = self.CursorX
								+ 1
								+ (line:sub(self.CursorX + 1, self.CursorX + 4) == tabReplacement and 3 or 0)
							local endCursorY = self.CursorY
							if endCursorX > #line then
								endCursorY = endCursorY + 1
								endCursorX = 0
							end
							self:UpdateCursor()

							endRange = endRange or { endCursorX, endCursorY }
						end

						self:DeleteRange({ startRange, endRange }, false, true)
						self:ResetSelection(true)
						self:JumpToCursor()
					end)
				elseif service.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
					if keycode == keycodes.A then
						self.SelectionRange = { { 0, 0 }, { #self.Lines[#self.Lines], #self.Lines - 1 } }
						self:SetCopyableSelection()
						self:Refresh()
					end
				end
			end)
		end

		funcs.DisconnectEditBoxEvent = function(self)
			if self.EditBoxEvent then
				self.EditBoxEvent:Disconnect()
			end
		end

		funcs.ResetSelection = function(self, norefresh)
			self.SelectionRange = { { -1, -1 }, { -1, -1 } }
			if not norefresh then
				self:Refresh()
			end
		end

		funcs.IsValidRange = function(self, range)
			local selectionRange = range or self.SelectionRange
			local selX, selY = selectionRange[1][1], selectionRange[1][2]
			local sel2X, sel2Y = selectionRange[2][1], selectionRange[2][2]

			if selX == -1 or (selX == sel2X and selY == sel2Y) then
				return false
			end

			return true
		end

		funcs.DeleteRange = function(self, range, noprocess, updatemouse)
			range = range or self.SelectionRange
			if not self:IsValidRange(range) then
				return
			end

			local lines = self.Lines
			local selX, selY = range[1][1], range[1][2]
			local sel2X, sel2Y = range[2][1], range[2][2]
			local deltaLines = sel2Y - selY

			if not lines[selY + 1] or not lines[sel2Y + 1] then
				return
			end

			local leftSub = lines[selY + 1]:sub(1, selX)
			local rightSub = lines[sel2Y + 1]:sub(sel2X + 1)
			lines[selY + 1] = leftSub .. rightSub

			local remove = table.remove
			for i = 1, deltaLines do
				remove(lines, selY + 2)
			end

			if range == self.SelectionRange then
				self.SelectionRange = { { -1, -1 }, { -1, -1 } }
			end
			if updatemouse then
				self.CursorX = selX
				self.CursorY = selY
				self:UpdateCursor()
			end

			if not noprocess then
				self:ProcessTextChange()
			end
		end

		funcs.AppendText = function(self, text)
			local originalRow = self.CursorY + 1
			local originalLine = self.Lines[originalRow]
			local originalCount = #self.Lines
			local range = self.SelectionRange
			local singleRow = not range or range[1][1] < 0
				or range[1][2] == originalRow - 1 and range[2][2] == originalRow - 1
			self:DeleteRange(nil, true, true)
			local lines, cursorX, cursorY = self.Lines, self.CursorX, self.CursorY
			local line = lines[cursorY + 1]
			local before = line:sub(1, cursorX)
			local after = line:sub(cursorX + 1)

			if text == "\n" then
				local indent = before:match("^%s*") or ""
				if
					before:match("then%s*$")
					or before:match("do%s*$")
					or before:match("function.*%)%s*$")
					or before:match("{%s*$")
				then
					indent ..= "    "
				end
				text = "\n" .. indent
			end
			text = text:gsub("\r\n", "\n")
			text = self:ConvertText(text, true)

			local textLines = text:split("\n")
			local insert = table.insert

			for i = 1, #textLines do
				local linePos = cursorY + i
				if i > 1 then
					insert(lines, linePos, "")
				end

				local textLine = textLines[i]
				local newBefore = (i == 1 and before or "")
				local newAfter = (i == #textLines and after or "")

				lines[linePos] = newBefore .. textLine .. newAfter
			end

			if #textLines > 1 then
				cursorX = 0
			end

			self:ProcessTextChange(
				singleRow and originalRow == cursorY + 1 and originalCount == #lines and originalRow or nil,
				originalLine
			)
			self.CursorX = cursorX + #textLines[#textLines]
			self.CursorY = cursorY + #textLines - 1
			self:UpdateCursor()
		end

		funcs.ScrollDelta = function(self, x, y)
			self.ScrollV:ScrollTo(self.ScrollV.Index + y)
			self.ScrollH:ScrollTo(self.ScrollH.Index + x)
		end

		funcs.TabAdjust = function(self, x, y)
			local lines = self.Lines
			local line = lines[y + 1]
			x = x + 1

			if line then
				local left = line:sub(x - 1, x - 1)
				local middle = line:sub(x, x)
				local right = line:sub(x + 1, x + 1)
				local selRange = (#left > 0 and left or " ")
					.. (#middle > 0 and middle or " ")
					.. (#right > 0 and right or " ")

				for i, v in pairs(tabJumps) do
					if selRange:find(i) then
						return v
					end
				end
			end
			return 0
		end

		funcs.SetEditing = function(self, on, input)
			self:UpdateCursor(input)

			if on then
				if self.Editable then
					if self.TouchTextInput then
						self:SetCopyableSelection()
					else
						self.EditBoxCopying = true
						self.NativeInputBuffer = ""
						self.GuiElems.EditBox.Text = ""
						self.EditBoxCopying = false
					end
					self.GuiElems.EditBox:CaptureFocus()
				end
			else
				self.GuiElems.EditBox:ReleaseFocus()
			end
		end

		funcs.CursorAnim = function(self, on)
			local cursor = self.GuiElems.Cursor
			local animTime = tick()
			self.LastAnimTime = animTime

			if not on then
				return
			end

			lineTweens.Invis:Cancel()
			lineTweens.Vis:Cancel()
			cursor.BackgroundTransparency = 0

			coroutine.wrap(function()
				while self.Editable do
					Lib.FastWait(0.5)
					if self.LastAnimTime ~= animTime then
						return
					end
					lineTweens.Invis:Play()
					Lib.FastWait(0.4)
					if self.LastAnimTime ~= animTime then
						return
					end
					lineTweens.Vis:Play()
					Lib.FastWait(0.2)
				end
			end)()
		end

		funcs.MoveCursor = function(self, x, y)
			self.CursorX = x
			self.CursorY = y
			self:UpdateCursor()
			self:JumpToCursor()
		end

		funcs.JumpToCursor = function(self)
			self:Refresh()
		end

		funcs.UpdateCursor = function(self, input)
			if Apps.CodeViewport and Apps.CodeViewport.UpdateCursor then
				return Apps.CodeViewport.UpdateCursor(self, input)
			end
			local linesFrame = self.GuiElems.LinesFrame
			local cursor = self.GuiElems.Cursor
			local hSize = math.max(0, linesFrame.AbsoluteSize.X)
			local vSize = math.max(0, linesFrame.AbsoluteSize.Y)
			local maxLines = math.ceil(vSize / self.FontSize)
			local maxCols = math.ceil(hSize / math.ceil(self.FontSize / 2))
			local viewX, viewY = self.ViewX, self.ViewY
			local totalLinesStr = tostring(#self.Lines)
			local fontWidth = math.ceil(self.FontSize / 2)
			local linesOffset = self.GutterWidth or (#totalLinesStr * fontWidth + 3 * fontWidth)

			if input then
				local linesFrame = self.GuiElems.LinesFrame
				local frameX, frameY = linesFrame.AbsolutePosition.X, linesFrame.AbsolutePosition.Y
				local mouseX, mouseY = input.Position.X, input.Position.Y
				local fontSizeX, fontSizeY = math.ceil(self.FontSize / 2), self.FontSize

				self.CursorX = self.ViewX + math.round((mouseX - frameX) / fontSizeX)
				self.CursorY = self:DisplayToSource(self.ViewY + math.floor((mouseY - frameY) / fontSizeY))
			end

			local cursorX, cursorY = self.CursorX, self.CursorY

			local line = self.Lines[cursorY + 1] or ""
			if cursorX > #line then
				cursorX = #line
			elseif cursorX < 0 then
				cursorX = 0
			end

			if cursorY >= #self.Lines then
				cursorY = math.max(0, #self.Lines - 1)
			elseif cursorY < 0 then
				cursorY = 0
			end

			cursorX = cursorX + self:TabAdjust(cursorX, cursorY)

			self.CursorX = cursorX
			self.CursorY = cursorY

			self:RevealSourceLine(cursorY)
			local displayY = self:SourceToDisplay(cursorY)
			local cursorVisible = displayY ~= nil
				and (cursorX >= viewX)
				and (displayY >= viewY)
				and (cursorX <= viewX + maxCols)
				and (displayY < viewY + maxLines)
			if cursorVisible then
				local offX = (cursorX - viewX)
				local offY = (displayY - viewY)
				cursor.Position =
					UDim2.new(0, linesOffset + offX * math.ceil(self.FontSize / 2) - 1, 0, offY * self.FontSize)
				cursor.Size = UDim2.new(0, 1, 0, self.FontSize + 2)
				cursor.Visible = true
				self:CursorAnim(true)
			else
				cursor.Visible = false
			end
		end

		local function lexLine(...)
			return Lib.LexLine(...)
		end

		funcs.PreHighlight = function(self, changedRow)
			local lines = self.Lines
			local activeTypes = self.HighlightTypes
			local activeClosers = self.HighlightClosers
			local highlights = self.PreHighlights
			local incremental = changedRow ~= nil and activeTypes ~= nil
			if not incremental then
				changedRow = 1
				activeTypes, activeClosers, highlights = {}, {}, {}
				self.HighlightTypes, self.HighlightClosers = activeTypes, activeClosers
				self.PreHighlights = highlights
				self.ColoredLines = {}
			end

			local kind, closer = activeTypes[changedRow - 1], activeClosers[changedRow - 1]
			for row = changedRow, #lines do
				self.ColoredLines[row] = nil
				highlights[row], kind, closer = lexLine(lines[row], row < #lines, kind, closer)
				if incremental and activeTypes[row] == kind and activeClosers[row] == closer then
					break
				end
				activeTypes[row], activeClosers[row] = kind, closer
			end
		end

		funcs.HighlightLine = function(self, line)
			local cached = self.ColoredLines[line]
			if cached then
				return cached
			end

			local sub = string.sub
			local find = string.find
			local match = string.match
			local highlights = {}
			local preHighlights = self.PreHighlights[line] or {}
			local lineText = self.Lines[line] or ""
			local lineLen = #lineText
			local lastEnding = 0
			local currentType = 0
			local lastWord = nil
			local wordBeginsDotted = false
			local funcStatus = 0
		local continuation = preHighlights[0]
			if continuation then
				currentType = continuation[1]
				lastEnding = continuation[2]
			end

			for col = 1, #lineText do
				if col <= lastEnding then
					highlights[col] = currentType
					continue
				end

				local pre = preHighlights[col]
				if pre then
					currentType = pre[1]
					lastEnding = pre[2]
					highlights[col] = currentType
					wordBeginsDotted = false
					lastWord = nil
					funcStatus = 0
				else
					local char = sub(lineText, col, col)
					if find(char, "[%a_]") then
						local word = match(lineText, "[%a%d_]+", col)
						local wordType = (keywords[word] and 7) or (builtIns[word] and 8) or identifierColors[word]

						lastEnding = col + #word - 1

						if wordType ~= 7 then
							if wordBeginsDotted then
								local prevBuiltIn = lastWord and builtIns[lastWord]
								wordType = (prevBuiltIn and type(prevBuiltIn) == "table" and prevBuiltIn[word] and 8)
									or 10
							end

							if wordType ~= 8 then
								local x, y, br = find(lineText, "^%s*([%({\"'])", lastEnding + 1)
								if x then
									wordType = (funcStatus > 0 and br == "(" and 16) or 9
									funcStatus = 0
								end
							end
						else
							wordType = specialKeywordsTypes[word] or wordType
							funcStatus = (word == "function" and 1 or 0)
						end

						lastWord = word
						wordBeginsDotted = false
						if funcStatus > 0 then
							funcStatus = 1
						end

						if wordType then
							currentType = wordType
							highlights[col] = currentType
						else
							currentType = nil
						end
					elseif find(char, "%d") or (char == "." and find(sub(lineText,col+1,col+1), "%d")) then
						currentType = 6
						lastEnding = Lib.NumberEnd(lineText,col)
						highlights[col] = 6
						wordBeginsDotted, lastWord, funcStatus = false, nil, 0
					elseif find(char, "%p") then
						local isDot = (char == ".")
						highlights[col] = 5
						local dotStr = isDot and match(lineText, "%.%.?%.?", col)
						if dotStr and #dotStr > 1 then
							currentType = 5
							lastEnding = col + #dotStr - 1
							wordBeginsDotted = false
							lastWord = nil
							funcStatus = 0
						else
							if isDot then
								if wordBeginsDotted then
									lastWord = nil
								else
									wordBeginsDotted = true
								end
							else
								wordBeginsDotted = false
								lastWord = nil
							end

							funcStatus = ((isDot or char == ":") and funcStatus == 1 and 2) or 0
						end
					else
						highlights[col] = currentType
						local _, endPos = find(lineText, "%s+", col)
						if endPos then
							lastEnding = endPos
						end
					end
				end
			end

			self.ColoredLines[line] = highlights
			return highlights
		end

		funcs.GetColumnPixelX = function(self, col, row)
			return Apps.CodeViewport.GetColumnPixelX(self, col, row)
		end
		funcs.GetPixelColumn = function(self, pixel, row)
			return Apps.CodeViewport.GetPixelColumn(self, pixel, row)
		end
		funcs.ScreenToEditorPoint = function(self, x, y, glyph)
			return Apps.CodeViewport.ScreenToEditorPoint(self, x, y, glyph)
		end
		funcs.DisplayToSource = function(self, row)
			return Apps.CodeViewport.DisplayToSource(self, row)
		end
		funcs.SourceToDisplay = function(self, row)
			return Apps.CodeViewport.SourceToDisplay(self, row)
		end
		funcs.RevealSourceLine = function(self, row)
			return Apps.CodeViewport.RevealSourceLine(self, row)
		end
		funcs.ToggleFold = function(self, row)
			return Apps.CodeViewport.ToggleFold(self, row)
		end
		funcs.ResetFolds = function(self)
			return Apps.CodeViewport.ResetFolds(self)
		end
		local viewportSyntax = { typeMap = typeMap, richReplace = richReplace }
		funcs.Refresh = function(self)
			return Apps.CodeViewport.Refresh(self, viewportSyntax)
		end
		funcs.UpdateView = function(self)
			return Apps.CodeViewport.UpdateView(self)
		end

		funcs.ProcessTextChange = function(self, changedRow, previousLine, newSource)
			local source = newSource or table.concat(self.Lines, "\n")
			if self.ProcessedText == source then
				return
			end
			local maxCols = self.MaxTextCols
			local lines = self.Lines
			if self.ProcessedText and changedRow and previousLine and (#previousLine < maxCols or #lines[changedRow] >= maxCols) then
				maxCols = math.max(maxCols, #lines[changedRow])
			else
				maxCols = 0
				for i = 1, #lines do
					local lineLen = #lines[i]
					if lineLen > maxCols then
						maxCols = lineLen
					end
				end
			end

			self.ProcessedText = source
			self.MaxTextCols = maxCols
			if not changedRow or not Apps.CodeViewport.KeepFoldsForLine(self, changedRow, previousLine) then
				Apps.CodeViewport.UpdateFolds(self, source)
			end
			self:UpdateView()
			self.PreviousText, self.ChangedTextRow = changedRow and self.Text, changedRow
			self.Text = source
			self:PreHighlight(changedRow)
			self:Refresh()
		end

		funcs.ConvertText = function(self, text, toEditor)
			if toEditor then
				return text:gsub("\t", "    ")
			else
				return text:gsub((" %s%s "):format(tabSub, tabSub), "\t")
			end
		end

		funcs.GetText = function(self)
			local source = self.Text
			if self.DecodedTextSource ~= source then
				self.DecodedTextSource = source
				self.DecodedText = if source:find(tabSub, 1, true) then self:ConvertText(source, false) else source
			end
			return self.DecodedText
		end

		funcs.SetText = function(self, txt)
			local began = os.clock()
			txt = self:ConvertText(txt, true):gsub("\r\n", "\n"):gsub("\r", "\n")
			local lines = self.Lines
			local first = 1
			local offset = 1
			while first <= #lines do
				local line = lines[first]
				local ending = offset + #line
				if txt:sub(offset, ending - 1) ~= line or (first < #lines and txt:sub(ending, ending) ~= "\n") then
					break
				end
				if first == #lines then
					if ending == #txt + 1 then
						return
					end
					break
				end
				offset = ending + 1
				first += 1
			end
			local previousLine = lines[first]
			if previousLine then
				local newBreak = txt:find("\n", offset, true)
				local oldBreak = offset + #previousLine
				local sameSuffix = if first < #lines
					then newBreak and txt:sub(newBreak + 1) == self.Text:sub(oldBreak + 1)
					else not newBreak
				if sameSuffix then
					lines[first] = txt:sub(offset, (newBreak or #txt + 1) - 1)
					self:ProcessTextChange(first, previousLine, txt)
					if Main.Performance then
						Main.Performance.Record("editor/set-text", os.clock() - began)
					end
					return
				end
			end
			local replacement = txt:sub(offset):split("\n")
			for i = #lines, first, -1 do
				lines[i] = nil
			end
			for i, line in ipairs(replacement) do
				lines[first + i - 1] = line
			end

			self:ProcessTextChange(nil, nil, txt)
			if Main.Performance then
				Main.Performance.Record("editor/set-text", os.clock() - began)
			end
		end

		funcs.MakeRichTemplates = function(self)
			local floor = math.floor
			local templates = {}

			for name, color in pairs(self.Colors) do
				templates[name] = ('<font color="rgb(%s,%s,%s)">'):format(
					floor(color.r * 255),
					floor(color.g * 255),
					floor(color.b * 255)
				)
			end

			self.RichTemplates = templates
		end

		funcs.ApplyTheme = function(self)
			local colors = Settings.Theme.Syntax
			self.Colors = colors
			self.Frame.LineNumbers.TextColor3 = Settings.Theme.PlaceholderText
			self.Frame.BackgroundColor3 = colors.Background
		end

		local mt = { __index = funcs }

		local function new()
			if not builtInInited then
				initBuiltIn()
			end

			local scrollV = Lib.ScrollBar.new()
			local scrollH = Lib.ScrollBar.new(true)
			scrollH.Gui.Position = UDim2.new(0, 0, 1, -16)
			local obj = setmetatable({
				FontSize = 16,
				ViewX = 0,
				ViewY = 0,
				Colors = Settings.Theme.Syntax,
				ColoredLines = {},
				Lines = { "" },
				LineFrames = {},
				Editable = true,
				Editing = false,
				CursorX = 0,
				CursorY = 0,
				FloatCursorX = 0,
				Text = "",
				PreHighlights = {},
				SelectionRange = { { -1, -1 }, { -1, -1 } },
				FrameOffsets = Vector2.new(0, 0),
				MaxTextCols = 0,
				ScrollV = scrollV,
				ScrollH = scrollH,
			}, mt)

			scrollV.WheelIncrement = 3
			scrollH.Increment = 2
			scrollH.WheelIncrement = 7

			scrollV.Scrolled:Connect(function()
				obj.ViewY = scrollV.Index
				obj:Refresh()
			end)

			scrollH.Scrolled:Connect(function()
				obj.ViewX = scrollH.Index
				obj:Refresh()
			end)

			makeFrame(obj)
			obj:MakeRichTemplates()
			obj:ApplyTheme()
			scrollV:SetScrollFrame(obj.Frame.Lines)
			scrollV.Gui.Parent = obj.Frame
			scrollH.Gui.Parent = obj.Frame

			obj:UpdateView()
			obj.Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				obj:UpdateView()
				obj:Refresh()
			end)

			return obj
		end

		return { new = new }
	end)()

	Lib.Checkbox = (function()
		local funcs = {}
		local c3 = Color3.fromRGB
		local v2 = Vector2.new
		local ud2s = UDim2.fromScale
		local ud2o = UDim2.fromOffset
		local ud = UDim.new
		local max = math.max
		local new = Instance.new
		local TweenSize = new("Frame").TweenSize
		local ti = TweenInfo.new
		local delay = delay

		local function ripple(object, color)
			local circle = new("Frame")
			circle.BackgroundColor3 = color
			circle.BackgroundTransparency = 0.75
			circle.BorderSizePixel = 0
			circle.AnchorPoint = v2(0.5, 0.5)
			circle.Size = ud2o()
			circle.Position = ud2s(0.5, 0.5)
			circle.Parent = object
			local rounding = new("UICorner")
			rounding.CornerRadius = ud(1)
			rounding.Parent = circle

			local abssz = object.AbsoluteSize
			local size = max(abssz.X, abssz.Y) * 5 / 3

			TweenSize(circle, ud2o(size, size), "Out", "Quart", 0.4)
			service.TweenService
				:Create(
					circle,
					ti(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }
				)
				:Play()

			service.Debris:AddItem(circle, 0.4)
		end

		local function buildStyle0()
			return create({
				{
					1,
					"ImageButton",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "Checkbox",
						Position = UDim2.new(0, 3, 0, 3),
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ripples",
						Parent = { 1 },
						Size = UDim2.new(1, 0, 1, 0),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.10196078568697, 0.10196078568697, 0.10196078568697),
						BorderSizePixel = 0,
						Name = "outline",
						Parent = { 1 },
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					4,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
						BorderSizePixel = 0,
						Name = "filler",
						Parent = { 3 },
						Position = UDim2.new(0, 1, 0, 1),
						Size = UDim2.new(0, 14, 0, 14),
					},
				},
				{
					5,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.90196084976196, 0.90196084976196, 0.90196084976196),
						BorderSizePixel = 0,
						Name = "top",
						Parent = { 4 },
						Size = UDim2.new(0, 16, 0, 0),
					},
				},
				{
					6,
					"Frame",
					{
						AnchorPoint = Vector2.new(0, 1),
						BackgroundColor3 = Color3.new(0.90196084976196, 0.90196084976196, 0.90196084976196),
						BorderSizePixel = 0,
						Name = "bottom",
						Parent = { 4 },
						Position = UDim2.new(0, 0, 0, 14),
						Size = UDim2.new(0, 16, 0, 0),
					},
				},
				{
					7,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.90196084976196, 0.90196084976196, 0.90196084976196),
						BorderSizePixel = 0,
						Name = "left",
						Parent = { 4 },
						Size = UDim2.new(0, 0, 0, 16),
					},
				},
				{
					8,
					"Frame",
					{
						AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = Color3.new(0.90196084976196, 0.90196084976196, 0.90196084976196),
						BorderSizePixel = 0,
						Name = "right",
						Parent = { 4 },
						Position = UDim2.new(0, 14, 0, 0),
						Size = UDim2.new(0, 0, 0, 16),
					},
				},
				{
					9,
					"Frame",
					{
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "checkmark",
						Parent = { 4 },
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 0, 0, 20),
					},
				},
				{
					10,
					"ImageLabel",
					{
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = "rbxassetid://6234266378",
						Parent = { 9 },
						Position = UDim2.new(0.5, 0, 0.5, 0),
						ScaleType = 3,
						Size = UDim2.new(0, 15, 0, 11),
					},
				},
				{
					11,
					"Frame",
					{
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "checkmark2",
						Parent = { 4 },
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0, 12, 0, 12),
						Visible = false,
					},
				},
				{
					12,
					"Frame",
					{
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "middle",
						Parent = { 4 },
						Size = UDim2.new(1, 0, 1, 0),
						Visible = false,
					},
				},
				{ 13, "UICorner", { CornerRadius = UDim.new(0, 2), Parent = { 3 } } },
			})
		end

		local function buildStyle1()
			return create({
				{
					1,
					"ImageButton",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						AutoButtonColor = false,
						Name = "Checkbox",
						Position = UDim2.new(0, 3, 0, 3),
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "ripples",
						Parent = { 1 },
						Size = UDim2.new(1, 0, 1, 0),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "outline",
						Parent = { 1 },
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					4,
					"Frame",
					{
						BackgroundColor3 = c3(0, 0, 0),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "boxOutline",
						Parent = { 3 },
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					6,
					"Frame",
					{
						BackgroundColor3 = c3(36, 39, 45),
						BorderSizePixel = 0,
						Name = "filler",
						Parent = { 4 },
						Position = UDim2.new(0, 0, 0, 0),
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					8,
					"ImageLabel",
					{
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "stateImage",
						Parent = { 3 },
						Size = UDim2.new(1, 0, 1, 0),
						Image = (Main.GetStudioAsset and Main.GetStudioAsset("prop/checkbox_off")) or "",
						ScaleType = Enum.ScaleType.Fit,
						Visible = false,
					},
				},
				{
					9,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "tl_h",
						Parent = { 6 },
						Position = UDim2.new(0, 1, 0, 1),
						Size = UDim2.new(0, 2, 0, 1),
					},
				},
				{
					10,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "tl_v",
						Parent = { 6 },
						Position = UDim2.new(0, 1, 0, 1),
						Size = UDim2.new(0, 1, 0, 2),
					},
				},
				{
					11,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "tr_h",
						Parent = { 6 },
						Position = UDim2.new(1, -3, 0, 1),
						Size = UDim2.new(0, 2, 0, 1),
					},
				},
				{
					12,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "tr_v",
						Parent = { 6 },
						Position = UDim2.new(1, -2, 0, 1),
						Size = UDim2.new(0, 1, 0, 2),
					},
				},
				{
					13,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "bl_h",
						Parent = { 6 },
						Position = UDim2.new(0, 1, 1, -2),
						Size = UDim2.new(0, 2, 0, 1),
					},
				},
				{
					14,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "bl_v",
						Parent = { 6 },
						Position = UDim2.new(0, 1, 1, -3),
						Size = UDim2.new(0, 1, 0, 2),
					},
				},
				{
					15,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "br_h",
						Parent = { 6 },
						Position = UDim2.new(1, -3, 1, -2),
						Size = UDim2.new(0, 2, 0, 1),
					},
				},
				{
					16,
					"Frame",
					{
						BackgroundColor3 = c3(118, 124, 136),
						BorderSizePixel = 0,
						Name = "br_v",
						Parent = { 6 },
						Position = UDim2.new(1, -2, 1, -3),
						Size = UDim2.new(0, 1, 0, 2),
					},
				},
			})
		end

		local function initGui(self, frame)
			local checkbox = frame or ((self.Style == 0) and buildStyle0() or buildStyle1())
			local outline = checkbox:FindFirstChild("outline")
			local boxOutline = outline and outline:FindFirstChild("boxOutline")
			local filler = outline and outline:FindFirstChild("filler")
				or (boxOutline and boxOutline:FindFirstChild("filler"))
			if not outline or not filler then
				error("Checkbox visual hierarchy is missing outline/filler")
			end
			local checkmark = filler:FindFirstChild("checkmark")
			local ripples_container = checkbox:FindFirstChild("ripples")

			self.Gui = checkbox
			self.GuiElems = {
				Top = filler:FindFirstChild("top"),
				Bottom = filler:FindFirstChild("bottom"),
				Left = filler:FindFirstChild("left"),
				Right = filler:FindFirstChild("right"),
				Outline = outline,
				Filler = filler,
				BoxOutline = boxOutline,
				Checkmark = checkmark,
				Checkmark2 = filler:FindFirstChild("checkmark2"),
				Middle = filler:FindFirstChild("middle"),
				StateImage = outline:FindFirstChild("stateImage"),
				TLH = filler:FindFirstChild("tl_h"),
				TLV = filler:FindFirstChild("tl_v"),
				TRH = filler:FindFirstChild("tr_h"),
				TRV = filler:FindFirstChild("tr_v"),
				BLH = filler:FindFirstChild("bl_h"),
				BLV = filler:FindFirstChild("bl_v"),
				BRH = filler:FindFirstChild("br_h"),
				BRV = filler:FindFirstChild("br_v"),
				CornerTL = outline:FindFirstChild("cornerTL"),
				CornerTR = outline:FindFirstChild("cornerTR"),
				CornerBL = outline:FindFirstChild("cornerBL"),
				CornerBR = outline:FindFirstChild("cornerBR"),
			}

			checkbox.MouseButton1Up:Connect(function()
				if Lib.CheckMouseInGui(checkbox) then
					if self.Style == 0 then
						ripple(ripples_container, self.Disabled and self.Colors.Disabled or self.Colors.Primary)
					end

					if not self.Disabled then
						self:SetState(not self.Toggled, true)
					else
						self:Paint()
					end

					self.OnInput:Fire()
				end
			end)

			self:Paint()
		end

		funcs.Collapse = function(self, anim)
			local guiElems = self.GuiElems
			if not guiElems.Top then
				return
			end
			if anim then
				TweenSize(guiElems.Top, ud2o(14, 14), "In", "Quart", 4 / 15, true)
				TweenSize(guiElems.Bottom, ud2o(14, 14), "In", "Quart", 4 / 15, true)
				TweenSize(guiElems.Left, ud2o(14, 14), "In", "Quart", 4 / 15, true)
				TweenSize(guiElems.Right, ud2o(14, 14), "In", "Quart", 4 / 15, true)
			else
				guiElems.Top.Size = ud2o(14, 14)
				guiElems.Bottom.Size = ud2o(14, 14)
				guiElems.Left.Size = ud2o(14, 14)
				guiElems.Right.Size = ud2o(14, 14)
			end
		end

		funcs.Expand = function(self, anim)
			local guiElems = self.GuiElems
			if not guiElems.Top then
				return
			end
			if anim then
				TweenSize(guiElems.Top, ud2o(14, 0), "InOut", "Quart", 4 / 15, true)
				TweenSize(guiElems.Bottom, ud2o(14, 0), "InOut", "Quart", 4 / 15, true)
				TweenSize(guiElems.Left, ud2o(0, 14), "InOut", "Quart", 4 / 15, true)
				TweenSize(guiElems.Right, ud2o(0, 14), "InOut", "Quart", 4 / 15, true)
			else
				guiElems.Top.Size = ud2o(14, 0)
				guiElems.Bottom.Size = ud2o(14, 0)
				guiElems.Left.Size = ud2o(0, 14)
				guiElems.Right.Size = ud2o(0, 14)
			end
		end

		funcs.Paint = function(self)
			local guiElems = self.GuiElems

			if self.Style == 0 then
				local color_base = self.Disabled and self.Colors.Disabled
				guiElems.Outline.BackgroundColor3 = color_base
					or (self.Toggled and self.Colors.Primary)
					or self.Colors.Secondary
				local walls_color = color_base or self.Colors.Primary
				guiElems.Top.BackgroundColor3 = walls_color
				guiElems.Bottom.BackgroundColor3 = walls_color
				guiElems.Left.BackgroundColor3 = walls_color
				guiElems.Right.BackgroundColor3 = walls_color
			else
				local isUnchecked = self.Toggled == false
				local accent = self.Disabled and self.Colors.DisabledAccent or self.Colors.Highlight
				local fill = self.Disabled and self.Colors.DisabledBackground or self.Colors.Background

				if guiElems.BoxOutline then
					guiElems.BoxOutline.Visible = isUnchecked
					guiElems.BoxOutline.BackgroundTransparency = 1
				end
				if guiElems.Filler then
					guiElems.Filler.Visible = isUnchecked
					guiElems.Filler.BackgroundColor3 = fill
				end
				for _, key in ipairs({ "TLH", "TLV", "TRH", "TRV", "BLH", "BLV", "BRH", "BRV" }) do
					local seg = guiElems[key]
					if seg then
						seg.Visible = isUnchecked
						seg.BackgroundColor3 = accent
					end
				end

				if guiElems.StateImage then
					guiElems.StateImage.Visible = not isUnchecked
					if not isUnchecked then
						local assetKey
						if self.Disabled then
							if self.Toggled == true then
								assetKey = "prop/checkbox_on_disabled"
							elseif self.Toggled == nil then
								assetKey = "prop/checkbox_mix_disabled"
							else
								assetKey = "prop/checkbox_off_disabled"
							end
						else
							if self.Toggled == true then
								assetKey = "prop/checkbox_on"
							elseif self.Toggled == nil then
								assetKey = "prop/checkbox_mix"
							else
								assetKey = "prop/checkbox_off"
							end
						end
						local asset = Main.GetStudioAsset and Main.GetStudioAsset(assetKey)
						if asset then
							guiElems.StateImage.Image = asset
						end
					end
				end
			end
		end

		funcs.SetState = function(self, val, anim)
			self.Toggled = val

			if self.OutlineColorTween then
				self.OutlineColorTween:Cancel()
			end
			local setStateTime = tick()
			self.LastSetStateTime = setStateTime

			if self.Toggled then
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(
							self.GuiElems.Outline,
							ti(4 / 15, Enum.EasingStyle.Circular, Enum.EasingDirection.Out),
							{ BackgroundColor3 = self.Colors.Primary }
						)
						self.OutlineColorTween:Play()
						delay(0.15, function()
							if setStateTime ~= self.LastSetStateTime then
								return
							end
							self:Paint()
							TweenSize(self.GuiElems.Checkmark, ud2o(14, 20), "Out", "Bounce", 2 / 15, true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Primary
						self:Paint()
						self.GuiElems.Checkmark.Size = ud2o(14, 20)
					end
					self:Collapse(anim)
				else
					self:Paint()
				end
			else
				if self.Style == 0 then
					if anim then
						self.OutlineColorTween = service.TweenService:Create(
							self.GuiElems.Outline,
							ti(4 / 15, Enum.EasingStyle.Circular, Enum.EasingDirection.In),
							{ BackgroundColor3 = self.Colors.Secondary }
						)
						self.OutlineColorTween:Play()
						delay(0.15, function()
							if setStateTime ~= self.LastSetStateTime then
								return
							end
							self:Paint()
							TweenSize(self.GuiElems.Checkmark, ud2o(0, 20), "Out", "Quad", 1 / 15, true)
						end)
					else
						self.GuiElems.Outline.BackgroundColor3 = self.Colors.Secondary
						self:Paint()
						self.GuiElems.Checkmark.Size = ud2o(0, 20)
					end
					self:Expand(anim)
				else
					self:Paint()
				end
			end
		end

		local mt = { __index = funcs }

		local function new(style)
			local obj = setmetatable({
				Toggled = false,
				Disabled = false,
				OnInput = Lib.Signal.new(),
				Style = style or 0,
				Colors = {
					Background = c3(36, 39, 45),
					CheckedBackground = c3(243, 246, 250),
					Primary = c3(31, 34, 39),
					Secondary = c3(78, 84, 95),
					CheckedOutline = c3(171, 177, 186),
					Highlight = c3(118, 124, 136),
					CheckedHighlight = c3(255, 255, 255),
					Middle = c3(171, 177, 186),
					BoxOutline = c3(60, 65, 73),
					Disabled = c3(71, 74, 80),
					DisabledBackground = c3(44, 47, 53),
					DisabledCheck = c3(102, 106, 114),
					DisabledAccent = c3(84, 88, 96),
					DisabledBoxOutline = c3(55, 59, 65),
				},
			}, mt)
			initGui(obj)
			return obj
		end

		local function fromFrame(frame)
			local obj = setmetatable({
				Toggled = false,
				Disabled = false,
				OnInput = Lib.Signal.new(),
				Style = 1,
				Colors = {
					Background = c3(36, 39, 45),
					CheckedBackground = c3(243, 246, 250),
					Primary = c3(31, 34, 39),
					Secondary = c3(78, 84, 95),
					CheckedOutline = c3(171, 177, 186),
					Highlight = c3(118, 124, 136),
					CheckedHighlight = c3(255, 255, 255),
					Middle = c3(171, 177, 186),
					BoxOutline = c3(60, 65, 73),
					Disabled = c3(71, 74, 80),
					DisabledBackground = c3(44, 47, 53),
					DisabledCheck = c3(102, 106, 114),
					DisabledAccent = c3(84, 88, 96),
					DisabledBoxOutline = c3(55, 59, 65),
				},
			}, mt)
			initGui(obj, frame)
			return obj
		end

		return { new = new, fromFrame = fromFrame }
	end)()

	Lib.BrickColorPicker = (function()
		local funcs = {}
		local mouse = service.Players.LocalPlayer:GetMouse()
		local hexStartX = 4
		local hexSizeX = 27
		local hexTriangleStart = 1
		local hexTriangleSize = 8

		local bottomColors = {
			Color3.fromRGB(17, 17, 17),
			Color3.fromRGB(99, 95, 98),
			Color3.fromRGB(163, 162, 165),
			Color3.fromRGB(205, 205, 205),
			Color3.fromRGB(223, 223, 222),
			Color3.fromRGB(237, 234, 234),
			Color3.fromRGB(27, 42, 53),
			Color3.fromRGB(91, 93, 105),
			Color3.fromRGB(159, 161, 172),
			Color3.fromRGB(202, 203, 209),
			Color3.fromRGB(231, 231, 236),
			Color3.fromRGB(248, 248, 248),
		}

		local function isMouseInHexagon(hex, touchPos)
			local relativeX = touchPos.X - hex.AbsolutePosition.X
			local relativeY = touchPos.Y - hex.AbsolutePosition.Y
			if relativeX >= hexStartX and relativeX < hexStartX + hexSizeX then
				relativeX = relativeX - 4
				local relativeWidth = (13 - math.min(relativeX, 26 - relativeX)) / 13
				if
					relativeY >= hexTriangleStart + hexTriangleSize * relativeWidth
					and relativeY < hex.AbsoluteSize.Y - hexTriangleStart - hexTriangleSize * relativeWidth
				then
					return true
				end
			end
			return false
		end

		local function hexInput(self, hex, color)
			hex.MouseLeave:Connect(function()
				if self.Hovered == hex then
					self.Hover(nil)
				end
			end)
			hex.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if isMouseInHexagon(hex, input.Position) then
						self.OnSelect:Fire(color)
						self:Close()
					end
				end
			end)

			hex.InputChanged:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if isMouseInHexagon(hex, input.Position) then
						self.Hover(hex, color)
						self.OnPreview:Fire(color)
					elseif self.Hovered == hex then
						self.Hover(nil)
					end
				end
			end)
		end

		local function createGui(self)
			local paletteCount = 0
			self.Swatches = {}
			local gui = create({
				{ 1, "ScreenGui", { Name = "BrickColor", ZIndexBehavior = Enum.ZIndexBehavior.Global } },
				{
					2,
					"Frame",
					{
						Active = true,
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderColor3 = Color3.new(0.1294117718935, 0.1294117718935, 0.1294117718935),
						Parent = { 1 },
						Position = UDim2.new(0.40000000596046, 0, 0.40000000596046, 0),
						Size = UDim2.new(0, 376, 0, 400),
					},
				},
				{
					3,
					"TextButton",
					{
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						BorderSizePixel = 0,
						Font = 3,
						Name = "MoreColors",
						Parent = { 2 },
						Position = UDim2.new(0, 10, 1, -36),
						Size = UDim2.new(1, -20, 0, 30),
						Text = "More Colors",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 14,
					},
				},
				{
					4,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = "rbxassetid://1281023007",
						ImageColor3 = Color3.new(0.33333334326744, 0.33333334326744, 0.49803924560547),
						Name = "Hex",
						Parent = { 2 },
						Size = UDim2.new(0, 35, 0, 35),
						Visible = false,
					},
				},
			})
			local colorFrame = gui.Frame
			local hex = colorFrame.Hex
			hex.Image = Main.GetStudioAsset and Main.GetStudioAsset("color/hex") or hex.Image
			hex.ScaleType = Enum.ScaleType.Fit
			colorFrame.BackgroundColor3 = Settings.Theme.Main1
			colorFrame.BorderColor3 = Settings.Theme.Outline2
			colorFrame.MoreColors.BackgroundColor3 = Settings.Theme.Button
			Lib.StudioText(colorFrame.MoreColors)
			colorFrame.MoreColors.TextSize = 12
			hex.ZIndex = 3
			local ring = hex:Clone()
			ring.Name = "SelectedOutline"
			ring.Size = UDim2.fromOffset(39, 39)
			ring.ImageColor3 = Color3.fromRGB(255, 145, 0)
			ring.ZIndex = 1
			ring.Parent = colorFrame
			local inner = ring:Clone()
			inner.Name = "SelectedRing"
			inner.Size = UDim2.fromOffset(37, 37)
			inner.ImageColor3 = Color3.fromRGB(255, 240, 0)
			inner.ZIndex = 2
			inner.Parent = colorFrame
			local hover = ring:Clone()
			hover.Name = "HoverOutline"
			hover.ImageColor3 = Color3.fromRGB(40, 140, 255)
			hover.Visible = false
			hover.Parent = colorFrame
			local hoverInner = inner:Clone()
			hoverInner.ImageColor3 = Color3.new(1, 1, 1)
			hoverInner.Name = "HoverRing"
			hoverInner.Visible = false
			hoverInner.Parent = colorFrame
			local selectedAsset = Main.GetStudioAsset and Main.GetStudioAsset("color/selected")
			local hoverAsset = Main.GetStudioAsset and Main.GetStudioAsset("color/hover")
			if selectedAsset then
				ring.Image = selectedAsset
				ring.ImageColor3 = Color3.new(1, 1, 1)
				ring.Size = UDim2.fromScale(1, 1)
				ring.ZIndex = 8
				inner.ImageTransparency = 1
			end
			if hoverAsset then
				hover.Image = hoverAsset
				hover.ImageColor3 = Color3.new(1, 1, 1)
				hover.Size = UDim2.fromScale(1, 1)
				hover.ZIndex = 9
				hoverInner.ImageTransparency = 1
			end
			local hoverRevision = 0
			local tip = createSimple("TextLabel", {
				Name = "ColorName",
				Parent = colorFrame,
				BackgroundColor3 = Settings.Theme.Menu,
				BorderColor3 = Settings.Theme.Outline2,
				ZIndex = 10,
				Visible = false,
			})
			Lib.StudioText(tip)
			tip.TextSize = 12
			self.Hover = function(swatch, color)
				if self.Hovered == swatch then
					return
				end
				hoverRevision += 1
				local revision = hoverRevision
				self.Hovered = swatch
				hover.Visible = swatch ~= nil
				hoverInner.Visible = swatch ~= nil
				tip.Visible = false
				if not swatch then
					return
				end
				if hoverAsset then
					hover.Parent = swatch
					hover.Position = UDim2.fromOffset(0, 0)
				else
					hover.Position = UDim2.fromOffset(swatch.Position.X.Offset - 2, swatch.Position.Y.Offset - 2)
				end
				hoverInner.Position = UDim2.fromOffset(swatch.Position.X.Offset - 1, swatch.Position.Y.Offset - 1)
				tip.Text = BrickColor.new(color).Name
				local width = service.TextService:GetTextSize(tip.Text, 12, Lib.StudioFont, Vector2.new(500, 30)).X + 12
				tip.Size = UDim2.fromOffset(width, 24)
				tip.Position = UDim2.fromOffset(
					math.clamp(swatch.Position.X.Offset + 16, 0, 376 - width),
					swatch.Position.Y.Offset + 28
				)
				task.delay(1, function()
					if revision == hoverRevision and self.Hovered == swatch and self.Gui.Parent then
						tip.Visible = true
					end
				end)
			end
			self.Highlight = function(color)
				local best, distance
				for _, swatch in ipairs(self.Swatches) do
					local value = swatch.ImageColor3
					local d = (value.R - color.R) ^ 2 + (value.G - color.G) ^ 2 + (value.B - color.B) ^ 2
					if not distance or d < distance then
						best = swatch
						distance = d
					end
				end
				if best then
					if selectedAsset then
						ring.Parent = best
						ring.Position = UDim2.fromOffset(0, 0)
					else
						ring.Position = UDim2.fromOffset(best.Position.X.Offset - 2, best.Position.Y.Offset - 2)
					end
					inner.Position = UDim2.fromOffset(best.Position.X.Offset - 1, best.Position.Y.Offset - 1)
					ring.Visible = true
					inner.Visible = true
				end
			end

			local edgeAsset = Main.GetStudioAsset and Main.GetStudioAsset("color/edge")
			if edgeAsset then
				createSimple("ImageLabel", {
					Name = "SwatchBorder",
					Parent = hex,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = edgeAsset,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 4,
				})
			end
			for row = 1, 13 do
				local columns = math.min(row, 14 - row) + 6
				for column = 1, columns do
					local nextColor = BrickColor.palette(paletteCount).Color
					local newHex = hex:Clone()
					newHex.Position = UDim2.new(0, (column - 1) * 28 - (columns - 7) * 14 + 88, 0, (row - 1) * 24 + 4)
					newHex.ImageColor3 = nextColor
					newHex.Visible = true
					hexInput(self, newHex, nextColor)
					newHex.Parent = colorFrame
					self.Swatches[#self.Swatches + 1] = newHex
					paletteCount = paletteCount + 1
				end
			end

			for column = 1, 12 do
				local nextColor = bottomColors[column]
				local newHex = hex:Clone()
				newHex.Position = UDim2.new(0, (column - 1) * 28 + 18, 0, 320)
				newHex.ImageColor3 = nextColor
				newHex.Visible = true
				hexInput(self, newHex, nextColor)
				newHex.Parent = colorFrame
				self.Swatches[#self.Swatches + 1] = newHex
				paletteCount = paletteCount + 1
			end

			colorFrame.MoreColors.MouseButton1Click:Connect(function()
				self:Close()
				self.OnMoreColors:Fire()
			end)

			self.Gui = gui
		end

		funcs.SetMoreColorsVisible = function(self, vis)
			local colorFrame = self.Gui.Frame
			colorFrame.Size = UDim2.new(0, 376, 0, 400 - (not vis and 40 or 0))
			colorFrame.MoreColors.Visible = vis
		end

		funcs.Show = function(self, x, y, prevColor)
			self.PrevColor = prevColor or self.PrevColor
			self.Highlight(self.PrevColor)
			self.Hover(nil)

			local reverseY = false

			local x, y = x or mouse.X, y or mouse.Y
			local maxX, maxY = mouse.ViewSizeX, mouse.ViewSizeY
			Lib.ShowGui(self.Gui)
			local sizeX, sizeY = self.Gui.Frame.AbsoluteSize.X, self.Gui.Frame.AbsoluteSize.Y

			if x + sizeX > maxX then
				x = self.ReverseX and x - sizeX or maxX - sizeX
			end
			if y + sizeY > maxY then
				reverseY = true
			end

			local closable = false
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
			end

			self.CloseEvent = Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if
					not closable
					or (
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					)
				then
					return
				end

				if not Lib.CheckMouseInGui(self.Gui.Frame) then
					self.CloseEvent:Disconnect()
					self:Close()
				end
			end)

			if reverseY then
				local newY = y - sizeY - (self.ReverseYOffset or 0)
				y = newY >= 0 and newY or 0
			end

			self.Gui.Frame.Position = UDim2.new(0, x, 0, y)

			Lib.FastWait()
			closable = true
		end

		funcs.Close = function(self)
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
				self.CloseEvent = nil
			end
			self.Hover(nil)
			self.Gui.Parent = nil
			self.OnCancel:Fire()
		end

		local mt = { __index = funcs }

		local function new()
			local obj = setmetatable({
				OnPreview = Lib.Signal.new(),
				OnSelect = Lib.Signal.new(),
				OnCancel = Lib.Signal.new(),
				OnMoreColors = Lib.Signal.new(),
				PrevColor = Color3.new(0, 0, 0),
			}, mt)
			createGui(obj)
			return obj
		end

		return { new = new }
	end)()

	Lib.ColorPicker = (function()
		local funcs = {}

		local function new()
			local newMt = setmetatable({}, {})

			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()

			local guiContents = create({
				{
					1,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "Content",
						Position = UDim2.new(0, 0, 0, 20),
						Size = UDim2.new(1, 0, 1, -20),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Name = "BasicColors",
						Parent = { 1 },
						Position = UDim2.new(0, 5, 0, 5),
						Size = UDim2.new(0, 180, 0, 200),
					},
				},
				{
					3,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 2 },
						Position = UDim2.new(0, 0, 0, -5),
						Size = UDim2.new(1, 0, 0, 26),
						Text = "Basic Colors",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					4,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Blue",
						Parent = { 1 },
						Position = UDim2.new(1, -63, 0, 255),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					5,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 4 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					6,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 5 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					7,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 6 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					8,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 7 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					9,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 8 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					10,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 8 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					11,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 8 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					12,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 6 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					13,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 12 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					14,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 13 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					15,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 13 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					16,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 13 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					17,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 4 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Blue:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					18,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "ColorSpaceFrame",
						Parent = { 1 },
						Position = UDim2.new(1, -261, 0, 4),
						Size = UDim2.new(0, 222, 0, 202),
					},
				},
				{
					19,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						BorderSizePixel = 0,
						Image = "rbxassetid://1072518406",
						Name = "ColorSpace",
						Parent = { 18 },
						Position = UDim2.new(0, 1, 0, 1),
						Size = UDim2.new(0, 220, 0, 200),
					},
				},
				{
					20,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "Scope",
						Parent = { 19 },
						Position = UDim2.new(0, 210, 0, 190),
						Size = UDim2.new(0, 20, 0, 20),
					},
				},
				{
					21,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 20 },
						Position = UDim2.new(0, 9, 0, 0),
						Size = UDim2.new(0, 2, 0, 20),
					},
				},
				{
					22,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Name = "Line",
						Parent = { 20 },
						Position = UDim2.new(0, 0, 0, 9),
						Size = UDim2.new(0, 20, 0, 2),
					},
				},
				{
					23,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Name = "CustomColors",
						Parent = { 1 },
						Position = UDim2.new(0, 5, 0, 210),
						Size = UDim2.new(0, 180, 0, 90),
					},
				},
				{
					24,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 23 },
						Size = UDim2.new(1, 0, 0, 20),
						Text = "Custom Colors (RC = Set)",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					25,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Green",
						Parent = { 1 },
						Position = UDim2.new(1, -63, 0, 233),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					26,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 25 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					27,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 26 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					28,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 27 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					29,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 28 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					30,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 29 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					31,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 29 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					32,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 29 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					33,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 27 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					34,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 33 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					35,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 34 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					36,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 34 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					37,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 34 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					38,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 25 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Green:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					39,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Hue",
						Parent = { 1 },
						Position = UDim2.new(1, -180, 0, 211),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					40,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 39 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					41,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 40 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					42,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 41 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					43,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 42 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					44,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 43 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					45,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 43 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					46,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 43 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					47,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 41 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					48,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 47 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					49,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 48 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					50,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 48 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					51,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 48 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					52,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 39 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Hue:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					53,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Name = "Preview",
						Parent = { 1 },
						Position = UDim2.new(1, -260, 0, 211),
						Size = UDim2.new(0, 35, 1, -245),
					},
				},
				{
					54,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Red",
						Parent = { 1 },
						Position = UDim2.new(1, -63, 0, 211),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					55,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 54 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					56,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 55 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					57,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 56 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					58,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 57 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					59,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 58 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					60,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 58 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					61,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 58 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					62,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 56 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					63,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 62 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					64,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 63 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					65,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 63 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					66,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 63 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					67,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 54 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Red:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					68,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Sat",
						Parent = { 1 },
						Position = UDim2.new(1, -180, 0, 233),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					69,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 68 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					70,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 69 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					71,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 70 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					72,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 71 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					73,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 72 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					74,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 72 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					75,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 72 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					76,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 70 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					77,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 76 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					78,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 77 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					79,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 77 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					80,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 77 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					81,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 68 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Sat:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					82,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Val",
						Parent = { 1 },
						Position = UDim2.new(1, -180, 0, 255),
						Size = UDim2.new(0, 52, 0, 16),
					},
				},
				{
					83,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Font = 3,
						Name = "Input",
						Parent = { 82 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 50, 0, 16),
						Text = "255",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					84,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 83 },
						Position = UDim2.new(1, -16, 0, 0),
						Size = UDim2.new(0, 16, 1, 0),
					},
				},
				{
					85,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Up",
						Parent = { 84 },
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					86,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 85 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					87,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 86 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					88,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 86 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					89,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 86 },
						Position = UDim2.new(0, 6, 0, 5),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					90,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Font = 3,
						Name = "Down",
						Parent = { 84 },
						Position = UDim2.new(0, 0, 0, 8),
						Size = UDim2.new(1, 0, 0, 8),
						Text = "",
						TextSize = 14,
					},
				},
				{
					91,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 90 },
						Size = UDim2.new(0, 16, 0, 8),
					},
				},
				{
					92,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 91 },
						Position = UDim2.new(0, 8, 0, 5),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					93,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 91 },
						Position = UDim2.new(0, 7, 0, 4),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					94,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 91 },
						Position = UDim2.new(0, 6, 0, 3),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
				{
					95,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 82 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Val:",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					96,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Font = 3,
						Name = "Cancel",
						Parent = { 1 },
						Position = UDim2.new(1, -105, 1, -28),
						Size = UDim2.new(0, 100, 0, 25),
						Text = "Cancel",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					97,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Font = 3,
						Name = "Ok",
						Parent = { 1 },
						Position = UDim2.new(1, -210, 1, -28),
						Size = UDim2.new(0, 100, 0, 25),
						Text = "OK",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					98,
					"ImageLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Image = "rbxassetid://1072518502",
						Name = "ColorStrip",
						Parent = { 1 },
						Position = UDim2.new(1, -30, 0, 5),
						Size = UDim2.new(0, 13, 0, 200),
					},
				},
				{
					99,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.3137255012989, 0.3137255012989, 0.3137255012989),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "ArrowFrame",
						Parent = { 1 },
						Position = UDim2.new(1, -16, 0, 1),
						Size = UDim2.new(0, 5, 0, 208),
					},
				},
				{
					100,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 99 },
						Position = UDim2.new(0, -2, 0, -4),
						Size = UDim2.new(0, 8, 0, 16),
					},
				},
				{
					101,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Parent = { 100 },
						Position = UDim2.new(0, 2, 0, 8),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					102,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Parent = { 100 },
						Position = UDim2.new(0, 3, 0, 7),
						Size = UDim2.new(0, 1, 0, 3),
					},
				},
				{
					103,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Parent = { 100 },
						Position = UDim2.new(0, 4, 0, 6),
						Size = UDim2.new(0, 1, 0, 5),
					},
				},
				{
					104,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Parent = { 100 },
						Position = UDim2.new(0, 5, 0, 5),
						Size = UDim2.new(0, 1, 0, 7),
					},
				},
				{
					105,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
						Parent = { 100 },
						Position = UDim2.new(0, 6, 0, 4),
						Size = UDim2.new(0, 1, 0, 9),
					},
				},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window.Alignable = false
			window:SetTitle("Select Color")
			window:Resize(524, 430)
			for i, v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			newMt.Window = window
			newMt.Gui = window.Gui
			local pickerGui = window.Gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			local colorSpace = pickerFrame.ColorSpaceFrame.ColorSpace
			local colorStrip = pickerFrame.ColorStrip
			local previewFrame = pickerFrame.Preview
			local basicColorsFrame = pickerFrame.BasicColors
			local customColorsFrame = pickerFrame.CustomColors
			local okButton = pickerFrame.Ok
			local cancelButton = pickerFrame.Cancel
			local closeButton = pickerTopBar.Close

			pickerFrame.BackgroundColor3 = Settings.Theme.Main1
			pickerTopBar.BackgroundColor3 = Color3.fromRGB(242, 242, 242)
			pickerTopBar.Title.TextColor3 = Color3.fromRGB(20, 20, 20)
			pickerTopBar.Title.Position = UDim2.fromOffset(30, 0)
			pickerTopBar.Title.TextXAlignment = Enum.TextXAlignment.Left
			pickerTopBar.Minimize.Visible = false
			pickerTopBar.Close.ImageLabel.ImageColor3 = Color3.fromRGB(20, 20, 20)
			basicColorsFrame.Position = UDim2.fromOffset(12, 8)
			basicColorsFrame.Size = UDim2.fromOffset(224, 164)
			basicColorsFrame.Title.Text = "Basic colors"
			customColorsFrame.Position = UDim2.fromOffset(12, 250)
			customColorsFrame.Size = UDim2.fromOffset(224, 68)
			customColorsFrame.Title.Text = "Custom colors"
			pickerFrame.ColorSpaceFrame.Position = UDim2.fromOffset(248, 20)
			colorStrip.Position = UDim2.fromOffset(487, 21)
			pickerFrame.ArrowFrame.Position = UDim2.fromOffset(501, 17)
			previewFrame.Position = UDim2.fromOffset(248, 244)
			previewFrame.Size = UDim2.fromOffset(58, 107)
			for i, name in ipairs({ "Hue", "Sat", "Val", "Red", "Green", "Blue" }) do
				local field = pickerFrame[name]
				field.Position = UDim2.fromOffset(i <= 3 and 363 or 462, 244 + ((i - 1) % 3) * 27)
				field.Size = UDim2.fromOffset(43, 21)
				field.BackgroundColor3 = Settings.Theme.TextBox
				field.BorderSizePixel = 0
				field.Input.Size = UDim2.new(1, -2, 1, 0)
			end
			for _, child in ipairs(pickerFrame:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextBox") or child:IsA("TextButton") then
					Lib.StudioText(child)
					child.TextSize = 12
				end
			end
			local function action(name, text, x, y, w)
				local b = createSimple("TextButton", {
					Name = name,
					Parent = pickerFrame,
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(w, 25),
					Text = text,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					BackgroundColor3 = Settings.Theme.Button,
				})
				Lib.StudioText(b)
				b.TextSize = 12
				return b
			end
			local pickScreen = action("PickScreen", "Pick Screen Color", 12, 183, 224)
			local addCustom = action("AddCustom", "Add to Custom Colors", 12, 327, 224)
			okButton.Position = UDim2.fromOffset(355, 364)
			okButton.Size = UDim2.fromOffset(75, 25)
			cancelButton.Position = UDim2.fromOffset(436, 364)
			cancelButton.Size = UDim2.fromOffset(75, 25)
			for _, b in ipairs({ okButton, cancelButton }) do
				b.BackgroundColor3 = Settings.Theme.Button
				b.BorderSizePixel = 0
			end
			local hexInput = createSimple("TextBox", {
				Name = "Hex",
				Parent = pickerFrame,
				Position = UDim2.fromOffset(363, 332),
				Size = UDim2.fromOffset(92, 20),
				BackgroundColor3 = Settings.Theme.TextBox,
				BorderColor3 = Settings.Theme.Outline2,
				ClearTextOnFocus = false,
				Text = "#000000",
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Lib.StudioText(hexInput)
			hexInput.TextSize = 12
			local hexLabel = createSimple("TextLabel", {
				Parent = pickerFrame,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(326, 332),
				Size = UDim2.fromOffset(32, 20),
				Text = "Hex:",
			})
			Lib.StudioText(hexLabel)
			hexLabel.TextSize = 12

			local colorScope = colorSpace.Scope
			local colorArrow = pickerFrame.ArrowFrame.Arrow

			local hueInput = pickerFrame.Hue.Input
			local satInput = pickerFrame.Sat.Input
			local valInput = pickerFrame.Val.Input

			local redInput = pickerFrame.Red.Input
			local greenInput = pickerFrame.Green.Input
			local blueInput = pickerFrame.Blue.Input

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			local hue, sat, val = 0, 0, 1
			local red, green, blue = 1, 1, 1
			local chosenColor = Color3.new(0, 0, 0)

			local basicColors = {
				Color3.new(0, 0, 0),
				Color3.new(0.66666668653488, 0, 0),
				Color3.new(0, 0.33333334326744, 0),
				Color3.new(0.66666668653488, 0.33333334326744, 0),
				Color3.new(0, 0.66666668653488, 0),
				Color3.new(0.66666668653488, 0.66666668653488, 0),
				Color3.new(0, 1, 0),
				Color3.new(0.66666668653488, 1, 0),
				Color3.new(0, 0, 0.49803924560547),
				Color3.new(0.66666668653488, 0, 0.49803924560547),
				Color3.new(0, 0.33333334326744, 0.49803924560547),
				Color3.new(0.66666668653488, 0.33333334326744, 0.49803924560547),
				Color3.new(0, 0.66666668653488, 0.49803924560547),
				Color3.new(0.66666668653488, 0.66666668653488, 0.49803924560547),
				Color3.new(0, 1, 0.49803924560547),
				Color3.new(0.66666668653488, 1, 0.49803924560547),
				Color3.new(0, 0, 1),
				Color3.new(0.66666668653488, 0, 1),
				Color3.new(0, 0.33333334326744, 1),
				Color3.new(0.66666668653488, 0.33333334326744, 1),
				Color3.new(0, 0.66666668653488, 1),
				Color3.new(0.66666668653488, 0.66666668653488, 1),
				Color3.new(0, 1, 1),
				Color3.new(0.66666668653488, 1, 1),
				Color3.new(0.33333334326744, 0, 0),
				Color3.new(1, 0, 0),
				Color3.new(0.33333334326744, 0.33333334326744, 0),
				Color3.new(1, 0.33333334326744, 0),
				Color3.new(0.33333334326744, 0.66666668653488, 0),
				Color3.new(1, 0.66666668653488, 0),
				Color3.new(0.33333334326744, 1, 0),
				Color3.new(1, 1, 0),
				Color3.new(0.33333334326744, 0, 0.49803924560547),
				Color3.new(1, 0, 0.49803924560547),
				Color3.new(0.33333334326744, 0.33333334326744, 0.49803924560547),
				Color3.new(1, 0.33333334326744, 0.49803924560547),
				Color3.new(0.33333334326744, 0.66666668653488, 0.49803924560547),
				Color3.new(1, 0.66666668653488, 0.49803924560547),
				Color3.new(0.33333334326744, 1, 0.49803924560547),
				Color3.new(1, 1, 0.49803924560547),
				Color3.new(0.33333334326744, 0, 1),
				Color3.new(1, 0, 1),
				Color3.new(0.33333334326744, 0.33333334326744, 1),
				Color3.new(1, 0.33333334326744, 1),
				Color3.new(0.33333334326744, 0.66666668653488, 1),
				Color3.new(1, 0.66666668653488, 1),
				Color3.new(0.33333334326744, 1, 1),
				Color3.new(1, 1, 1),
			}
			local customColors = Lib.CustomColors or {}
			Lib.CustomColors = customColors
			local customSlots, customIndex = {}, 1

			local function updateColor(noupdate)
				red = math.clamp(red, 0, 1)
				green = math.clamp(green, 0, 1)
				blue = math.clamp(blue, 0, 1)
				local relativeX, relativeY, relativeStripY = 219 - hue * 219, 199 - sat * 199, 199 - val * 199

				if noupdate == 2 or not noupdate then
					hueInput.Text = tostring(math.ceil(359 * hue))
					satInput.Text = tostring(math.ceil(255 * sat))
					valInput.Text = tostring(math.floor(255 * val))
				end
				if noupdate == 1 or not noupdate then
					redInput.Text = tostring(math.floor(255 * red))
					greenInput.Text = tostring(math.floor(255 * green))
					blueInput.Text = tostring(math.floor(255 * blue))
				end

				chosenColor = Color3.new(red, green, blue)
				colorScope.Position = UDim2.new(0, (relativeX - 9), 0, (relativeY - 9))
				colorStrip.ImageColor3 = Color3.fromHSV(hue, sat, 1)
				colorArrow.Position = UDim2.new(0, -2, 0, (relativeStripY - 4))
				previewFrame.BackgroundColor3 = chosenColor

				hexInput.Text = "#" .. chosenColor:ToHex():upper()
				newMt.Color = chosenColor
				newMt.OnPreview:Fire(chosenColor)
			end

			local function handleInputBegan(input, updateFunc)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					updateFunc()
					while user:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						task.wait()
						if user:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
							updateFunc()
						end
					end
				end
			end

			local function colorSpaceInput()
				local relativeX = mouse.X - colorSpace.AbsolutePosition.X
				local relativeY = mouse.Y - colorSpace.AbsolutePosition.Y

				if relativeX < 0 then
					relativeX = 0
				elseif relativeX > 219 then
					relativeX = 219
				end
				if relativeY < 0 then
					relativeY = 0
				elseif relativeY > 199 then
					relativeY = 199
				end

				hue = (219 - relativeX) / 219
				sat = (199 - relativeY) / 199
				if val == 0 then
					val = 1
				end

				local hsvColor = Color3.fromHSV(hue, sat, val)
				red, green, blue = hsvColor.R, hsvColor.G, hsvColor.B
				updateColor()
			end

			local function colorStripInput()
				local relativeY = mouse.Y - colorStrip.AbsolutePosition.Y

				if relativeY < 0 then
					relativeY = 0
				elseif relativeY > 199 then
					relativeY = 199
				end

				val = (199 - relativeY) / 199

				local hsvColor = Color3.fromHSV(hue, sat, val)
				red, green, blue = hsvColor.R, hsvColor.G, hsvColor.B
				updateColor()
			end

			colorSpace.InputBegan:Connect(function(input)
				handleInputBegan(input, colorSpaceInput)
			end)
			colorStrip.InputBegan:Connect(function(input)
				handleInputBegan(input, colorStripInput)
			end)

			local function hookButtons(frame, func)
				frame.ArrowFrame.Up.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local releaseEvent, runEvent
						local startTime = tick()
						local pressing = true
						local startNum = tonumber(frame.Text)

						if not startNum then
							return
						end

						releaseEvent = user.InputEnded:Connect(function(endInput)
							if
								endInput.UserInputType == Enum.UserInputType.MouseButton1
								or endInput.UserInputType == Enum.UserInputType.Touch
							then
								releaseEvent:Disconnect()
								pressing = false
							end
						end)

						startNum = startNum + 1
						func(startNum)
						while pressing do
							if tick() - startTime > 0.3 then
								startNum = startNum + 1
								func(startNum)
								startTime = tick()
							end
							task.wait(0.1)
						end
					end
				end)

				frame.ArrowFrame.Down.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local releaseEvent, runEvent
						local startTime = tick()
						local pressing = true
						local startNum = tonumber(frame.Text)

						if not startNum then
							return
						end

						releaseEvent = user.InputEnded:Connect(function(endInput)
							if
								endInput.UserInputType == Enum.UserInputType.MouseButton1
								or endInput.UserInputType == Enum.UserInputType.Touch
							then
								releaseEvent:Disconnect()
								pressing = false
							end
						end)

						startNum = startNum - 1
						func(startNum)
						while pressing do
							if tick() - startTime > 0.3 then
								startNum = startNum - 1
								func(startNum)
								startTime = tick()
							end
							task.wait(0.1)
						end
					end
				end)
			end


			local function updateHue(str)
				local num = tonumber(str)
				if num then
					hue = math.clamp(math.floor(num), 0, 359) / 359
					local hsvColor = Color3.fromHSV(hue, sat, val)
					red, green, blue = hsvColor.r, hsvColor.g, hsvColor.b

					hueInput.Text = tostring(hue * 359)
					updateColor(1)
				end
			end
			hueInput.FocusLost:Connect(function()
				updateHue(hueInput.Text)
			end)
			hookButtons(hueInput, updateHue)

			local function updateSat(str)
				local num = tonumber(str)
				if num then
					sat = math.clamp(math.floor(num), 0, 255) / 255
					local hsvColor = Color3.fromHSV(hue, sat, val)
					red, green, blue = hsvColor.r, hsvColor.g, hsvColor.b
					satInput.Text = tostring(sat * 255)
					updateColor(1)
				end
			end
			satInput.FocusLost:Connect(function()
				updateSat(satInput.Text)
			end)
			hookButtons(satInput, updateSat)

			local function updateVal(str)
				local num = tonumber(str)
				if num then
					val = math.clamp(math.floor(num), 0, 255) / 255
					local hsvColor = Color3.fromHSV(hue, sat, val)
					red, green, blue = hsvColor.r, hsvColor.g, hsvColor.b
					valInput.Text = tostring(val * 255)
					updateColor(1)
				end
			end
			valInput.FocusLost:Connect(function()
				updateVal(valInput.Text)
			end)
			hookButtons(valInput, updateVal)

			local function updateRed(str)
				local num = tonumber(str)
				if num then
					red = math.clamp(math.floor(num), 0, 255) / 255
					local newColor = Color3.new(red, green, blue)
					hue, sat, val = Color3.toHSV(newColor)
					redInput.Text = tostring(red * 255)
					updateColor(2)
				end
			end
			redInput.FocusLost:Connect(function()
				updateRed(redInput.Text)
			end)
			hookButtons(redInput, updateRed)

			local function updateGreen(str)
				local num = tonumber(str)
				if num then
					green = math.clamp(math.floor(num), 0, 255) / 255
					local newColor = Color3.new(red, green, blue)
					hue, sat, val = Color3.toHSV(newColor)
					greenInput.Text = tostring(green * 255)
					updateColor(2)
				end
			end
			greenInput.FocusLost:Connect(function()
				updateGreen(greenInput.Text)
			end)
			hookButtons(greenInput, updateGreen)

			local function updateBlue(str)
				local num = tonumber(str)
				if num then
					blue = math.clamp(math.floor(num), 0, 255) / 255
					local newColor = Color3.new(red, green, blue)
					hue, sat, val = Color3.toHSV(newColor)
					blueInput.Text = tostring(blue * 255)
					updateColor(2)
				end
			end
			blueInput.FocusLost:Connect(function()
				updateBlue(blueInput.Text)
			end)
			hookButtons(blueInput, updateBlue)

			local colorChoice = Instance.new("TextButton")
			colorChoice.Name = "Choice"
			colorChoice.Size = UDim2.new(0, 20, 0, 16)
			colorChoice.BorderColor3 = Color3.fromRGB(55, 55, 55)
			colorChoice.Text = ""
			colorChoice.AutoButtonColor = false

			local row = 0
			local column = 0
			for i, v in pairs(basicColors) do
				local newColor = colorChoice:Clone()
				newColor.BackgroundColor3 = v
				newColor.Position = UDim2.new(0, 4 + 28 * column, 0, 28 + 24 * row)

				newColor.MouseButton1Click:Connect(function()
					red, green, blue = v.r, v.g, v.b
					local newColor = Color3.new(red, green, blue)
					hue, sat, val = Color3.toHSV(newColor)
					updateColor()
				end)

				newColor.Parent = basicColorsFrame
				column = column + 1
				if column == 8 then
					row = row + 1
					column = 0
				end
			end

			row = 0
			column = 0
			for i = 1, 16 do
				local color = customColors[i] or Color3.new(1, 1, 1)
				local newColor = colorChoice:Clone()
				newColor.BackgroundColor3 = color
				newColor.Position = UDim2.new(0, 4 + 28 * column, 0, 28 + 24 * row)

				newColor.MouseButton1Click:Connect(function()
					customIndex = i
					local curColor = customColors[i] or Color3.new(1, 1, 1)
					red, green, blue = curColor.r, curColor.g, curColor.b
					hue, sat, val = Color3.toHSV(curColor)
					updateColor()
				end)

				newColor.MouseButton2Click:Connect(function()
					customColors[i] = chosenColor
					newColor.BackgroundColor3 = chosenColor
				end)

				newColor.Parent = customColorsFrame
				customSlots[i] = newColor
				column = column + 1
				if column == 8 then
					row = row + 1
					column = 0
				end
			end

			hexInput.FocusLost:Connect(function()
				local hex = hexInput.Text:gsub("^#", "")
				if #hex == 6 and hex:match("^%x+$") then
					local color = Color3.fromRGB(
						tonumber(hex:sub(1, 2), 16),
						tonumber(hex:sub(3, 4), 16),
						tonumber(hex:sub(5, 6), 16)
					)
					red, green, blue = color.R, color.G, color.B
					hue, sat, val = color:ToHSV()
				end
				updateColor()
			end)
			addCustom.Activated:Connect(function()
				customColors[customIndex] = chosenColor
				customSlots[customIndex].BackgroundColor3 = chosenColor
				customIndex = customIndex % 16 + 1
			end)
			local picking
			pickScreen.Activated:Connect(function()
				if picking then
					picking:Disconnect()
					picking = nil
					return
				end
				pickScreen.Text = "Click an object Ã‚Â· Esc to cancel"
				picking = user.InputBegan:Connect(function(input)
					if
						input.KeyCode == Enum.KeyCode.Escape
						or input.UserInputType == Enum.UserInputType.MouseButton1
					then
						if input.KeyCode ~= Enum.KeyCode.Escape and mouse.Target then
							newMt:SetColor(mouse.Target.Color)
						end
						picking:Disconnect()
						picking = nil
						pickScreen.Text = "Pick Screen Color"
					end
				end)
			end)
			window.OnDeactivate:Connect(function()
				if picking then
					picking:Disconnect()
					picking = nil
				end
				pickScreen.Text = "Pick Screen Color"
			end)

			okButton.MouseButton1Click:Connect(function()
				newMt.OnSelect:Fire(chosenColor)
				window:Close()
			end)
			okButton.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					okButton.BackgroundTransparency = 0.4
				end
			end)
			okButton.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					okButton.BackgroundTransparency = 0
				end
			end)

			cancelButton.MouseButton1Click:Connect(function()
				newMt.OnCancel:Fire()
				window:Close()
			end)
			cancelButton.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					cancelButton.BackgroundTransparency = 0.4
				end
			end)
			cancelButton.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					cancelButton.BackgroundTransparency = 0
				end
			end)

			updateColor()

			newMt.SetColor = function(self, color)
				red = math.clamp(color.R, 0, 1)
				green = math.clamp(color.G, 0, 1)
				blue = math.clamp(color.B, 0, 1)
				hue, sat, val = Color3.toHSV(Color3.new(red, green, blue))
				updateColor()
			end

			newMt.Show = function(self)
				self.Window:Show()
			end

			return newMt
		end

		return { new = new }
	end)()

	Lib.NumberSequenceEditor = (function()
		local function new()
			local newMt = setmetatable({}, {})
			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()

			local guiContents = create({
				{
					1,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "Content",
						Position = UDim2.new(0, 0, 0, 20),
						Size = UDim2.new(1, 0, 1, -20),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Time",
						Parent = { 1 },
						Position = UDim2.new(0, 40, 0, 210),
						Size = UDim2.new(0, 60, 0, 20),
					},
				},
				{
					3,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						ClipsDescendants = true,
						Font = 3,
						Name = "Input",
						Parent = { 2 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 58, 0, 20),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					4,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 2 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Time",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					5,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Font = 3,
						Name = "Close",
						Parent = { 1 },
						Position = UDim2.new(1, -90, 0, 210),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Close",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					6,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Font = 3,
						Name = "Reset",
						Parent = { 1 },
						Position = UDim2.new(1, -180, 0, 210),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Reset",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					7,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Font = 3,
						Name = "Delete",
						Parent = { 1 },
						Position = UDim2.new(0, 380, 0, 210),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Delete",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					8,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Name = "NumberLineOutlines",
						Parent = { 1 },
						Position = UDim2.new(0, 10, 0, 20),
						Size = UDim2.new(1, -20, 0, 170),
					},
				},
				{
					9,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						Name = "NumberLine",
						Parent = { 1 },
						Position = UDim2.new(0, 10, 0, 20),
						Size = UDim2.new(1, -20, 0, 170),
					},
				},
				{
					10,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Value",
						Parent = { 1 },
						Position = UDim2.new(0, 170, 0, 210),
						Size = UDim2.new(0, 60, 0, 20),
					},
				},
				{
					11,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 10 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Value",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					12,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						ClipsDescendants = true,
						Font = 3,
						Name = "Input",
						Parent = { 10 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 58, 0, 20),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					13,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Envelope",
						Parent = { 1 },
						Position = UDim2.new(0, 300, 0, 210),
						Size = UDim2.new(0, 60, 0, 20),
					},
				},
				{
					14,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						ClipsDescendants = true,
						Font = 3,
						Name = "Input",
						Parent = { 13 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 58, 0, 20),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					15,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 13 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Envelope",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window:Resize(680, 265)
			window:SetTitle("NumberSequence Editor")
			newMt.Window = window
			newMt.Gui = window.Gui
			for i, v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			local gui = window.Gui
			local pickerGui = gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			pickerFrame.BackgroundColor3 = Settings.Theme.Main1
			for _, child in ipairs(pickerFrame:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextBox") or child:IsA("TextButton") then
					Lib.StudioText(child)
					child.TextSize = 12
					if child:IsA("TextButton") then
						child.BackgroundColor3 = Settings.Theme.Button
						child.BorderSizePixel = 0
					end
					if child:IsA("TextBox") and child.Parent:IsA("Frame") then
						child.Parent.BackgroundColor3 = Settings.Theme.TextBox
						child.Parent.BorderColor3 = Settings.Theme.Outline2
					end
				end
			end
			local numberLine = pickerFrame.NumberLine
			local numberLineOutlines = pickerFrame.NumberLineOutlines
			local timeBox = pickerFrame.Time.Input
			local valueBox = pickerFrame.Value.Input
			local envelopeBox = pickerFrame.Envelope.Input
			local deleteButton = pickerFrame.Delete
			local resetButton = pickerFrame.Reset
			local closeButton = pickerFrame.Close
			local topClose = pickerTopBar.Close

			local points = { { 1, 0, 3 }, { 8, 0.05, 1 }, { 5, 0.6, 2 }, { 4, 0.7, 4 }, { 6, 1, 4 } }
			local lines = {}
			local eLines = {}
			local beginPoint = points[1]
			local endPoint = points[#points]
			local currentlySelected = nil
			local currentPoint = nil
			local resetSequence = nil

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			for i = 2, 10 do
				local newLine = Instance.new("Frame")
				newLine.BackgroundTransparency = 0.5
				newLine.BackgroundColor3 = Color3.new(96 / 255, 96 / 255, 96 / 255)
				newLine.BorderSizePixel = 0
				newLine.Size = UDim2.new(0, 1, 1, 0)
				newLine.Position = UDim2.new((i - 1) / (11 - 1), 0, 0, 0)
				newLine.Parent = numberLineOutlines
			end

			for i = 2, 4 do
				local newLine = Instance.new("Frame")
				newLine.BackgroundTransparency = 0.5
				newLine.BackgroundColor3 = Color3.new(96 / 255, 96 / 255, 96 / 255)
				newLine.BorderSizePixel = 0
				newLine.Size = UDim2.new(1, 0, 0, 1)
				newLine.Position = UDim2.new(0, 0, (i - 1) / (5 - 1), 0)
				newLine.Parent = numberLineOutlines
			end

			local lineTemp = Instance.new("Frame")
			lineTemp.BackgroundColor3 = Color3.new(0, 0, 0)
			lineTemp.BorderSizePixel = 0
			lineTemp.Size = UDim2.new(0, 1, 0, 1)

			local sequenceLine = Instance.new("Frame")
			sequenceLine.BackgroundColor3 = Color3.new(0, 0, 0)
			sequenceLine.BorderSizePixel = 0
			sequenceLine.Size = UDim2.new(0, 1, 0, 0)

			for i = 1, numberLine.AbsoluteSize.X do
				local line = sequenceLine:Clone()
				eLines[i] = line
				line.Name = "E" .. tostring(i)
				line.BackgroundTransparency = 0.5
				line.BackgroundColor3 = Color3.new(199 / 255, 44 / 255, 28 / 255)
				line.Position = UDim2.new(0, i - 1, 0, 0)
				line.Parent = numberLine
			end

			for i = 1, numberLine.AbsoluteSize.X do
				local line = sequenceLine:Clone()
				lines[i] = line
				line.Name = tostring(i)
				line.Position = UDim2.new(0, i - 1, 0, 0)
				line.Parent = numberLine
			end

			local envelopeDrag = Instance.new("Frame")
			envelopeDrag.BackgroundTransparency = 1
			envelopeDrag.BackgroundColor3 = Color3.new(0, 0, 0)
			envelopeDrag.BorderSizePixel = 0
			envelopeDrag.Size = UDim2.new(0, 7, 0, 20)
			envelopeDrag.Visible = false
			envelopeDrag.ZIndex = 2
			local envelopeDragLine = Instance.new("Frame", envelopeDrag)
			envelopeDragLine.Name = "Line"
			envelopeDragLine.BackgroundColor3 = Color3.new(0, 0, 0)
			envelopeDragLine.BorderSizePixel = 0
			envelopeDragLine.Position = UDim2.new(0, 3, 0, 0)
			envelopeDragLine.Size = UDim2.new(0, 1, 0, 20)
			envelopeDragLine.ZIndex = 2

			local envelopeDragTop, envelopeDragBottom = envelopeDrag:Clone(), envelopeDrag:Clone()
			envelopeDragTop.Parent = numberLine
			envelopeDragBottom.Parent = numberLine

			local function buildSequence()
				local newPoints = {}
				for i, v in pairs(points) do
					table.insert(newPoints, NumberSequenceKeypoint.new(v[2], v[1], v[3]))
				end
				newMt.Sequence = NumberSequence.new(newPoints)
				newMt.OnSelect:Fire(newMt.Sequence)
			end

			local function round(num, places)
				local multi = 10 ^ places
				return math.floor(num * multi + 0.5) / multi
			end

			local function updateInputs(point)
				if point then
					currentPoint = point
					local rawT, rawV, rawE = point[2], point[1], point[3]
					timeBox.Text = round(rawT, (rawT < 0.01 and 5) or (rawT < 0.1 and 4) or 3)
					valueBox.Text = round(rawV, (rawV < 0.01 and 5) or (rawV < 0.1 and 4) or (rawV < 1 and 3) or 2)
					envelopeBox.Text = round(rawE, (rawE < 0.01 and 5) or (rawE < 0.1 and 4) or (rawV < 1 and 3) or 2)

					local envelopeDistance = numberLine.AbsoluteSize.Y * (point[3] / 10)
					envelopeDragTop.Position = UDim2.new(
						0,
						point[4].Position.X.Offset - 1,
						0,
						point[4].Position.Y.Offset - envelopeDistance - 17
					)
					envelopeDragTop.Visible = true
					envelopeDragBottom.Position = UDim2.new(
						0,
						point[4].Position.X.Offset - 1,
						0,
						point[4].Position.Y.Offset + envelopeDistance + 2
					)
					envelopeDragBottom.Visible = true
				end
			end

			envelopeDragTop.InputBegan:Connect(function(input)
				if
					(
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					)
					or not currentPoint
					or Lib.CheckMouseInGui(currentPoint[4].Select)
				then
					return
				end

				local mouseEvent, releaseEvent
				local maxSize = numberLine.AbsoluteSize.Y
				local mouseDelta = math.abs(envelopeDragTop.AbsolutePosition.Y - mouse.Y)

				envelopeDragTop.Line.Position = UDim2.new(0, 2, 0, 0)
				envelopeDragTop.Line.Size = UDim2.new(0, 3, 0, 20)

				releaseEvent = user.InputEnded:Connect(function(input)
					if
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					then
						return
					end
					mouseEvent:Disconnect()
					releaseEvent:Disconnect()
					envelopeDragTop.Line.Position = UDim2.new(0, 3, 0, 0)
					envelopeDragTop.Line.Size = UDim2.new(0, 1, 0, 20)
				end)

				mouseEvent = user.InputChanged:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local topDiff = (currentPoint[4].AbsolutePosition.Y + 2) - (mouse.Y - mouseDelta) - 19
						local newEnvelope = 10 * (math.max(topDiff, 0) / maxSize)
						local maxEnvelope = math.min(currentPoint[1], 10 - currentPoint[1])
						currentPoint[3] = math.min(newEnvelope, maxEnvelope)
						newMt:Redraw()
						buildSequence()
						updateInputs(currentPoint)
					end
				end)
			end)

			envelopeDragBottom.InputBegan:Connect(function(input)
				if
					(
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					)
					or not currentPoint
					or Lib.CheckMouseInGui(currentPoint[4].Select)
				then
					return
				end

				local mouseEvent, releaseEvent
				local maxSize = numberLine.AbsoluteSize.Y
				local mouseDelta = math.abs(envelopeDragBottom.AbsolutePosition.Y - mouse.Y)

				envelopeDragBottom.Line.Position = UDim2.new(0, 2, 0, 0)
				envelopeDragBottom.Line.Size = UDim2.new(0, 3, 0, 20)

				releaseEvent = user.InputEnded:Connect(function(input)
					if
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					then
						return
					end
					mouseEvent:Disconnect()
					releaseEvent:Disconnect()
					envelopeDragBottom.Line.Position = UDim2.new(0, 3, 0, 0)
					envelopeDragBottom.Line.Size = UDim2.new(0, 1, 0, 20)
				end)

				mouseEvent = user.InputChanged:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local bottomDiff = (mouse.Y + (20 - mouseDelta)) - (currentPoint[4].AbsolutePosition.Y + 2) - 19
						local newEnvelope = 10 * (math.max(bottomDiff, 0) / maxSize)
						local maxEnvelope = math.min(currentPoint[1], 10 - currentPoint[1])
						currentPoint[3] = math.min(newEnvelope, maxEnvelope)
						newMt:Redraw()
						buildSequence()
						updateInputs(currentPoint)
					end
				end)
			end)

			local function placePoint(point)
				local newPoint = Instance.new("Frame")
				newPoint.Name = "Point"
				newPoint.BorderSizePixel = 0
				newPoint.Size = UDim2.new(0, 5, 0, 5)
				newPoint.Position = UDim2.new(
					0,
					math.floor((numberLine.AbsoluteSize.X - 1) * point[2]) - 2,
					0,
					numberLine.AbsoluteSize.Y * (10 - point[1]) / 10 - 2
				)
				newPoint.BackgroundColor3 = Color3.new(0, 0, 0)

				local newSelect = Instance.new("Frame")
				newSelect.Name = "Select"
				newSelect.BackgroundTransparency = 1
				newSelect.BackgroundColor3 = Color3.new(199 / 255, 44 / 255, 28 / 255)
				newSelect.Position = UDim2.new(0, -2, 0, -2)
				newSelect.Size = UDim2.new(0, 9, 0, 9)
				newSelect.Parent = newPoint

				newPoint.Parent = numberLine

				newSelect.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						for i, v in pairs(points) do
							v[4].Select.BackgroundTransparency = 1
						end

						newSelect.BackgroundTransparency = 0
						updateInputs(point)
					end

					if
						(
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						) and not currentlySelected
					then
						currentPoint = point
						local mouseEvent, releaseEvent
						currentlySelected = true
						newSelect.BackgroundColor3 = Color3.new(249 / 255, 191 / 255, 59 / 255)

						local oldEnvelope = point[3]

						releaseEvent = user.InputEnded:Connect(function(input)
							if
								input.UserInputType ~= Enum.UserInputType.MouseButton1
								and input.UserInputType ~= Enum.UserInputType.Touch
							then
								return
							end

							mouseEvent:Disconnect()
							releaseEvent:Disconnect()
							currentlySelected = nil
							newSelect.BackgroundColor3 = Color3.new(199 / 255, 44 / 255, 28 / 255)
						end)

						mouseEvent = user.InputChanged:Connect(function(input)
							if
								input.UserInputType == Enum.UserInputType.MouseMovement
								or input.UserInputType == Enum.UserInputType.Touch
							then
								local maxX = numberLine.AbsoluteSize.X - 1
								local relativeX = (input.Position.X - numberLine.AbsolutePosition.X)
								if relativeX < 0 then
									relativeX = 0
								end
								if relativeX > maxX then
									relativeX = maxX
								end

								local maxY = numberLine.AbsoluteSize.Y - 1
								local relativeY = (input.Position.Y - numberLine.AbsolutePosition.Y)
								if relativeY < 0 then
									relativeY = 0
								end
								if relativeY > maxY then
									relativeY = maxY
								end

								if point ~= beginPoint and point ~= endPoint then
									point[2] = relativeX / maxX
								end

								point[1] = 10 - (relativeY / maxY) * 10
								local maxEnvelope = math.min(point[1], 10 - point[1])
								point[3] = math.min(oldEnvelope, maxEnvelope)
								newMt:Redraw()
								updateInputs(point)

								for i, v in pairs(points) do
									v[4].Select.BackgroundTransparency = 1
								end

								newSelect.BackgroundTransparency = 0
								buildSequence()
							end
						end)
					end
				end)

				return newPoint
			end

			local function placePoints()
				for i, v in pairs(points) do
					v[4] = placePoint(v)
				end
			end

			local function redraw(self)
				local numberLineSize = numberLine.AbsoluteSize
				table.sort(points, function(a, b)
					return a[2] < b[2]
				end)
				for i, v in pairs(points) do
					v[4].Position = UDim2.new(
						0,
						math.floor((numberLineSize.X - 1) * v[2]) - 2,
						0,
						(numberLineSize.Y - 1) * (10 - v[1]) / 10 - 2
					)
				end
				lines[1].Size = UDim2.new(0, 1, 0, 0)
				for i = 1, #points - 1 do
					local fromPoint = points[i]
					local toPoint = points[i + 1]
					local deltaY = toPoint[4].Position.Y.Offset - fromPoint[4].Position.Y.Offset
					local deltaX = toPoint[4].Position.X.Offset - fromPoint[4].Position.X.Offset
					local slope = deltaY / deltaX

					local fromEnvelope = fromPoint[3]
					local nextEnvelope = toPoint[3]

					local currentRise = math.abs(slope)
					local totalRise = 0
					local maxRise = math.abs(toPoint[4].Position.Y.Offset - fromPoint[4].Position.Y.Offset)

					for lineCount = math.min(fromPoint[4].Position.X.Offset + 1, toPoint[4].Position.X.Offset), toPoint[4].Position.X.Offset do
						if deltaX == 0 and deltaY == 0 then
							return
						end
						local riseNow = math.floor(currentRise)
						local line = lines[lineCount + 3]
						if line then
							if totalRise + riseNow > maxRise then
								riseNow = maxRise - totalRise
							end
							if math.sign(slope) == -1 then
								line.Position = UDim2.new(
									0,
									lineCount + 2,
									0,
									fromPoint[4].Position.Y.Offset + -(totalRise + riseNow) + 2
								)
							else
								line.Position =
									UDim2.new(0, lineCount + 2, 0, fromPoint[4].Position.Y.Offset + totalRise + 2)
							end
							line.Size = UDim2.new(0, 1, 0, math.max(riseNow, 1))
						end
						totalRise = totalRise + riseNow
						currentRise = currentRise - riseNow + math.abs(slope)

						local envPercent = (lineCount - fromPoint[4].Position.X.Offset)
							/ (toPoint[4].Position.X.Offset - fromPoint[4].Position.X.Offset)
						local envLerp = fromEnvelope + (nextEnvelope - fromEnvelope) * envPercent
						local relativeSize = (envLerp / 10) * numberLineSize.Y

						local line = eLines[lineCount + 3]
						if line then
							line.Position = UDim2.new(
								0,
								lineCount + 2,
								0,
								lines[lineCount + 3].Position.Y.Offset - math.floor(relativeSize)
							)
							line.Size = UDim2.new(0, 1, 0, math.floor(relativeSize * 2))
						end
					end
				end
			end
			newMt.Redraw = redraw

			local function loadSequence(self, seq)
				resetSequence = seq
				for i, v in pairs(points) do
					if v[4] then
						v[4]:Destroy()
					end
				end
				points = {}
				for i, v in pairs(seq.Keypoints) do
					local maxEnvelope = math.min(v.Value, 10 - v.Value)
					local newPoint = { v.Value, v.Time, math.min(v.Envelope, maxEnvelope) }
					newPoint[4] = placePoint(newPoint)
					table.insert(points, newPoint)
				end
				beginPoint = points[1]
				endPoint = points[#points]
				currentlySelected = nil
				redraw()
				envelopeDragTop.Visible = false
				envelopeDragBottom.Visible = false
			end
			newMt.SetSequence = loadSequence

			timeBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(timeBox.Text)
				if point and num and point ~= beginPoint and point ~= endPoint then
					num = math.clamp(num, 0, 1)
					point[2] = num
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			valueBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(valueBox.Text)
				if point and num then
					local oldEnvelope = point[3]
					num = math.clamp(num, 0, 10)
					point[1] = num
					local maxEnvelope = math.min(point[1], 10 - point[1])
					point[3] = math.min(oldEnvelope, maxEnvelope)
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			envelopeBox.FocusLost:Connect(function()
				local point = currentPoint
				local num = tonumber(envelopeBox.Text)
				if point and num then
					num = math.clamp(num, 0, 5)
					local maxEnvelope = math.min(point[1], 10 - point[1])
					point[3] = math.min(num, maxEnvelope)
					redraw()
					buildSequence()
					updateInputs(point)
				end
			end)

			local function buttonAnimations(button, inverse)
				button.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						button.BackgroundTransparency = (inverse and 0.5 or 0.4)
					end
				end)
				button.InputEnded:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						button.BackgroundTransparency = (inverse and 1 or 0)
					end
				end)
			end

			numberLine.InputBegan:Connect(function(input)
				if
					(
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					) and #points < 20
				then
					if Lib.CheckMouseInGui(envelopeDragTop) or Lib.CheckMouseInGui(envelopeDragBottom) then
						return
					end

					for i, v in pairs(points) do
						if Lib.CheckMouseInGui(v[4].Select) then
							return
						end
					end

					local maxX = numberLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - numberLine.AbsolutePosition.X)
					if relativeX < 0 then
						relativeX = 0
					end
					if relativeX > maxX then
						relativeX = maxX
					end

					local maxY = numberLine.AbsoluteSize.Y - 1
					local relativeY = (input.Position.Y - numberLine.AbsolutePosition.Y)
					if relativeY < 0 then
						relativeY = 0
					end
					if relativeY > maxY then
						relativeY = maxY
					end

					local raw = relativeX / maxX
					local newPoint = { 10 - (relativeY / maxY) * 10, raw, 0 }
					newPoint[4] = placePoint(newPoint)
					table.insert(points, newPoint)
					redraw()
					buildSequence()
				end
			end)

			deleteButton.MouseButton1Click:Connect(function()
				if currentPoint and currentPoint ~= beginPoint and currentPoint ~= endPoint then
					for i, v in pairs(points) do
						if v == currentPoint then
							v[4]:Destroy()
							table.remove(points, i)
							break
						end
					end
					currentlySelected = nil
					redraw()
					buildSequence()
					updateInputs(points[1])
				end
			end)

			resetButton.MouseButton1Click:Connect(function()
				if resetSequence then
					newMt:SetSequence(resetSequence)
					buildSequence()
				end
			end)

			closeButton.MouseButton1Click:Connect(function()
				window:Close()
			end)

			buttonAnimations(deleteButton)
			buttonAnimations(resetButton)
			buttonAnimations(closeButton)

			placePoints()
			redraw()

			newMt.Show = function(self)
				window:Show()
			end

			return newMt
		end

		return { new = new }
	end)()

	Lib.ColorSequenceEditor = (function()
		local function new()
			local newMt = setmetatable({}, {})
			newMt.OnSelect = Lib.Signal.new()
			newMt.OnCancel = Lib.Signal.new()
			newMt.OnPreview = Lib.Signal.new()
			newMt.OnPickColor = Lib.Signal.new()

			local guiContents = create({
				{
					1,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Name = "Content",
						Position = UDim2.new(0, 0, 0, 20),
						Size = UDim2.new(1, 0, 1, -20),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Name = "ColorLine",
						Parent = { 1 },
						Position = UDim2.new(0, 10, 0, 5),
						Size = UDim2.new(1, -20, 0, 70),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderSizePixel = 0,
						Name = "Gradient",
						Parent = { 2 },
						Size = UDim2.new(1, 0, 1, 0),
					},
				},
				{ 4, "UIGradient", { Parent = { 3 } } },
				{
					5,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Name = "Arrows",
						Parent = { 1 },
						Position = UDim2.new(0, 1, 0, 73),
						Size = UDim2.new(1, -2, 0, 16),
					},
				},
				{
					6,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.5,
						BorderSizePixel = 0,
						Name = "Cursor",
						Parent = { 1 },
						Position = UDim2.new(0, 10, 0, 0),
						Size = UDim2.new(0, 1, 0, 80),
					},
				},
				{
					7,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
						BorderColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
						Name = "Time",
						Parent = { 1 },
						Position = UDim2.new(0, 40, 0, 95),
						Size = UDim2.new(0, 100, 0, 20),
					},
				},
				{
					8,
					"TextBox",
					{
						BackgroundColor3 = Color3.new(0.25098040699959, 0.25098040699959, 0.25098040699959),
						BackgroundTransparency = 1,
						BorderColor3 = Color3.new(0.37647062540054, 0.37647062540054, 0.37647062540054),
						ClipsDescendants = true,
						Font = 3,
						Name = "Input",
						Parent = { 7 },
						Position = UDim2.new(0, 2, 0, 0),
						Size = UDim2.new(0, 98, 0, 20),
						Text = "0",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 0,
					},
				},
				{
					9,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 7 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Time",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					10,
					"Frame",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						Name = "ColorBox",
						Parent = { 1 },
						Position = UDim2.new(0, 220, 0, 95),
						Size = UDim2.new(0, 20, 0, 20),
					},
				},
				{
					11,
					"TextLabel",
					{
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 1,
						Font = 3,
						Name = "Title",
						Parent = { 10 },
						Position = UDim2.new(0, -40, 0, 0),
						Size = UDim2.new(0, 34, 1, 0),
						Text = "Color",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
						TextXAlignment = 1,
					},
				},
				{
					12,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						BorderSizePixel = 0,
						Font = 3,
						Name = "Close",
						Parent = { 1 },
						Position = UDim2.new(1, -90, 0, 95),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Close",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					13,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						BorderSizePixel = 0,
						Font = 3,
						Name = "Reset",
						Parent = { 1 },
						Position = UDim2.new(1, -180, 0, 95),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Reset",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					14,
					"TextButton",
					{
						AutoButtonColor = false,
						BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
						BorderColor3 = Color3.new(0.21568627655506, 0.21568627655506, 0.21568627655506),
						BorderSizePixel = 0,
						Font = 3,
						Name = "Delete",
						Parent = { 1 },
						Position = UDim2.new(0, 280, 0, 95),
						Size = UDim2.new(0, 80, 0, 20),
						Text = "Delete",
						TextColor3 = Color3.new(0.86274516582489, 0.86274516582489, 0.86274516582489),
						TextSize = 14,
					},
				},
				{
					15,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "Arrow",
						Parent = { 1 },
						Size = UDim2.new(0, 16, 0, 16),
						Visible = false,
					},
				},
				{
					16,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 15 },
						Position = UDim2.new(0, 8, 0, 3),
						Size = UDim2.new(0, 1, 0, 2),
					},
				},
				{
					17,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 15 },
						Position = UDim2.new(0, 7, 0, 5),
						Size = UDim2.new(0, 3, 0, 2),
					},
				},
				{
					18,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 15 },
						Position = UDim2.new(0, 6, 0, 7),
						Size = UDim2.new(0, 5, 0, 2),
					},
				},
				{
					19,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 15 },
						Position = UDim2.new(0, 5, 0, 9),
						Size = UDim2.new(0, 7, 0, 2),
					},
				},
				{
					20,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 15 },
						Position = UDim2.new(0, 4, 0, 11),
						Size = UDim2.new(0, 9, 0, 2),
					},
				},
			})
			local window = Lib.Window.new()
			window.Resizable = false
			window:Resize(650, 150)
			window:SetTitle("ColorSequence Editor")
			newMt.Window = window
			newMt.Gui = window.Gui
			for i, v in pairs(guiContents:GetChildren()) do
				v.Parent = window.GuiElems.Content
			end
			local gui = window.Gui
			local pickerGui = gui.Main
			local pickerTopBar = pickerGui.TopBar
			local pickerFrame = pickerGui.Content
			pickerFrame.BackgroundColor3 = Settings.Theme.Main1
			for _, child in ipairs(pickerFrame:GetDescendants()) do
				if child:IsA("TextLabel") or child:IsA("TextBox") or child:IsA("TextButton") then
					Lib.StudioText(child)
					child.TextSize = 12
					if child:IsA("TextButton") then
						child.BackgroundColor3 = Settings.Theme.Button
						child.BorderSizePixel = 0
					end
					if child:IsA("TextBox") and child.Parent:IsA("Frame") then
						child.Parent.BackgroundColor3 = Settings.Theme.TextBox
						child.Parent.BorderColor3 = Settings.Theme.Outline2
					end
				end
			end
			local colorLine = pickerFrame.ColorLine
			local gradient = colorLine.Gradient.UIGradient
			local arrowFrame = pickerFrame.Arrows
			local arrow = pickerFrame.Arrow
			local cursor = pickerFrame.Cursor
			local timeBox = pickerFrame.Time.Input
			local colorBox = pickerFrame.ColorBox
			local deleteButton = pickerFrame.Delete
			local resetButton = pickerFrame.Reset
			local closeButton = pickerFrame.Close
			local topClose = pickerTopBar.Close

			local user = service.UserInputService
			local mouse = service.Players.LocalPlayer:GetMouse()

			local colors = {
				{ Color3.new(1, 0, 1), 0 },
				{ Color3.new(0.2, 0.9, 0.2), 0.2 },
				{ Color3.new(0.4, 0.5, 0.9), 0.7 },
				{ Color3.new(0.6, 1, 1), 1 },
			}
			local resetSequence = nil

			local beginPoint = colors[1]
			local endPoint = colors[#colors]

			local currentlySelected = nil
			local currentPoint = nil

			local sequenceLine = Instance.new("Frame")
			sequenceLine.BorderSizePixel = 0
			sequenceLine.Size = UDim2.new(0, 1, 1, 0)

			newMt.Sequence = ColorSequence.new(Color3.new(1, 1, 1))
			local function buildSequence(noupdate)
				local newPoints = {}
				table.sort(colors, function(a, b)
					return a[2] < b[2]
				end)
				for i, v in pairs(colors) do
					table.insert(newPoints, ColorSequenceKeypoint.new(v[2], v[1]))
				end
				newMt.Sequence = ColorSequence.new(newPoints)
				if not noupdate then
					newMt.OnSelect:Fire(newMt.Sequence)
				end
			end

			local function round(num, places)
				local multi = 10 ^ places
				return math.floor(num * multi + 0.5) / multi
			end

			local function updateInputs(point)
				if point then
					currentPoint = point
					local raw = point[2]
					timeBox.Text = round(raw, (raw < 0.01 and 5) or (raw < 0.1 and 4) or 3)
					colorBox.BackgroundColor3 = point[1]
				end
			end

			local function placeArrow(ind, point)
				local newArrow = arrow:Clone()
				newArrow.Position = UDim2.new(0, ind - 1, 0, 0)
				newArrow.Visible = true
				newArrow.Parent = arrowFrame

				newArrow.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						cursor.Visible = true
						cursor.Position = UDim2.new(0, 9 + newArrow.Position.X.Offset, 0, 0)
					end

					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						updateInputs(point)
						if point == beginPoint or point == endPoint or currentlySelected then
							return
						end

						local mouseEvent, releaseEvent
						currentlySelected = true

						releaseEvent = user.InputEnded:Connect(function(input)
							if
								input.UserInputType ~= Enum.UserInputType.MouseButton1
								and input.UserInputType ~= Enum.UserInputType.Touch
							then
								return
							end
							mouseEvent:Disconnect()
							releaseEvent:Disconnect()
							currentlySelected = nil
							cursor.Visible = false
						end)

						mouseEvent = user.InputChanged:Connect(function(input)
							if
								input.UserInputType == Enum.UserInputType.MouseMovement
								or input.UserInputType == Enum.UserInputType.Touch
							then
								local maxSize = colorLine.AbsoluteSize.X - 1
								local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
								if relativeX < 0 then
									relativeX = 0
								end
								if relativeX > maxSize then
									relativeX = maxSize
								end
								local raw = relativeX / maxSize
								point[2] = relativeX / maxSize
								updateInputs(point)
								cursor.Visible = true
								cursor.Position = UDim2.new(0, 9 + newArrow.Position.X.Offset, 0, 0)
								buildSequence()
								newMt:Redraw()
							end
						end)
					end
				end)

				newArrow.InputEnded:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						cursor.Visible = false
					end
				end)

				return newArrow
			end

			local function placeArrows()
				for i, v in pairs(colors) do
					v[3] = placeArrow(math.floor((colorLine.AbsoluteSize.X - 1) * v[2]) + 1, v)
				end
			end

			local function redraw(self)
				gradient.Color = newMt.Sequence or ColorSequence.new(Color3.new(1, 1, 1))

				for i = 2, #colors do
					local nextColor = colors[i]
					local endPos = math.floor((colorLine.AbsoluteSize.X - 1) * nextColor[2]) + 1
					nextColor[3].Position = UDim2.new(0, endPos, 0, 0)
				end
			end
			newMt.Redraw = redraw

			local function loadSequence(self, seq)
				resetSequence = seq
				for i, v in pairs(colors) do
					if v[3] then
						v[3]:Destroy()
					end
				end
				colors = {}
				currentlySelected = nil
				for i, v in pairs(seq.Keypoints) do
					local newPoint = { v.Value, v.Time }
					newPoint[3] = placeArrow(v.Time, newPoint)
					table.insert(colors, newPoint)
				end
				beginPoint = colors[1]
				endPoint = colors[#colors]
				currentlySelected = nil
				updateInputs(colors[1])
				buildSequence(true)
				redraw()
			end
			newMt.SetSequence = loadSequence

			local function buttonAnimations(button, inverse)
				button.InputBegan:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						button.BackgroundTransparency = (inverse and 0.5 or 0.4)
					end
				end)
				button.InputEnded:Connect(function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						button.BackgroundTransparency = (inverse and 1 or 0)
					end
				end)
			end

			colorLine.InputBegan:Connect(function(input)
				if
					(
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					) and #colors < 20
				then
					local maxSize = colorLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
					if relativeX < 0 then
						relativeX = 0
					end
					if relativeX > maxSize then
						relativeX = maxSize
					end

					local raw = relativeX / maxSize
					local fromColor = nil
					local toColor = nil
					for i, col in pairs(colors) do
						if col[2] >= raw then
							fromColor = colors[math.max(i - 1, 1)]
							toColor = colors[i]
							break
						end
					end
					local lerpColor = fromColor[1]:lerp(toColor[1], (raw - fromColor[2]) / (toColor[2] - fromColor[2]))
					local newPoint = { lerpColor, raw }
					newPoint[3] = placeArrow(newPoint[2], newPoint)
					table.insert(colors, newPoint)
					updateInputs(newPoint)
					buildSequence()
					redraw()
				end
			end)

			colorLine.InputChanged:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local maxSize = colorLine.AbsoluteSize.X - 1
					local relativeX = (input.Position.X - colorLine.AbsolutePosition.X)
					if relativeX < 0 then
						relativeX = 0
					end
					if relativeX > maxSize then
						relativeX = maxSize
					end
					cursor.Visible = true
					cursor.Position = UDim2.new(0, 10 + relativeX, 0, 0)
				end
			end)

			colorLine.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local inArrow = false
					for i, v in pairs(colors) do
						if Lib.CheckMouseInGui(v[3]) then
							inArrow = v[3]
						end
					end
					cursor.Visible = inArrow and true or false
					if inArrow then
						cursor.Position = UDim2.new(0, 9 + inArrow.Position.X.Offset, 0, 0)
					end
				end
			end)

			timeBox:GetPropertyChangedSignal("Text"):Connect(function()
				local point = currentPoint
				local num = tonumber(timeBox.Text)
				if point and num and point ~= beginPoint and point ~= endPoint then
					num = math.clamp(num, 0, 1)
					point[2] = num
					buildSequence()
					redraw()
				end
			end)

			colorBox.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local editor = newMt.ColorPicker
					if not editor then
						editor = Lib.ColorPicker.new()
						editor.Window:SetTitle("ColorSequence Color Picker")

						editor.OnSelect:Connect(function(col)
							if currentPoint then
								currentPoint[1] = col
							end
							buildSequence()
							redraw()
						end)

						newMt.ColorPicker = editor
					end

					editor.Window:ShowAndFocus()
				end
			end)

			deleteButton.MouseButton1Click:Connect(function()
				if currentPoint and currentPoint ~= beginPoint and currentPoint ~= endPoint then
					for i, v in pairs(colors) do
						if v == currentPoint then
							v[3]:Destroy()
							table.remove(colors, i)
							break
						end
					end
					currentlySelected = nil
					updateInputs(colors[1])
					buildSequence()
					redraw()
				end
			end)

			resetButton.MouseButton1Click:Connect(function()
				if resetSequence then
					newMt:SetSequence(resetSequence)
				end
			end)

			closeButton.MouseButton1Click:Connect(function()
				window:Close()
			end)

			topClose.MouseButton1Click:Connect(function()
				window:Close()
			end)

			buttonAnimations(deleteButton)
			buttonAnimations(resetButton)
			buttonAnimations(closeButton)

			placeArrows()
			redraw()

			newMt.Show = function(self)
				window:Show()
			end

			return newMt
		end

		return { new = new }
	end)()

	Lib.ViewportTextBox = (function()
		local textService = service.TextService

		local props = {
			OffsetX = 0,
			TextBox = PH,
			CursorPos = -1,
			Gui = PH,
			View = PH,
		}
		local funcs = {}
		funcs.Update = function(self)
			local cursorPos = self.CursorPos or -1
			local text = self.TextBox.Text
			if text == "" then
				self.TextBox.Position = UDim2.new(0, 0, 0, 0)
				return
			end
			if cursorPos == -1 then
				return
			end

			local cursorText = text:sub(1, cursorPos - 1)
			local pos = nil
			local leftEnd = -self.TextBox.Position.X.Offset
			local rightEnd = leftEnd + self.View.AbsoluteSize.X

			local totalTextSize =
				textService:GetTextSize(text, self.TextBox.TextSize, self.TextBox.Font, Vector2.new(999999999, 100)).X
			local cursorTextSize = textService:GetTextSize(
				cursorText,
				self.TextBox.TextSize,
				self.TextBox.Font,
				Vector2.new(999999999, 100)
			).X

			if cursorTextSize > rightEnd then
				pos = math.max(-1, cursorTextSize - self.View.AbsoluteSize.X + 2)
			elseif cursorTextSize < leftEnd then
				pos = math.max(-1, cursorTextSize - 2)
			elseif totalTextSize < rightEnd then
				pos = math.max(-1, totalTextSize - self.View.AbsoluteSize.X + 2)
			end

			if pos then
				self.TextBox.Position = UDim2.new(0, -pos, 0, 0)
				self.TextBox.Size = UDim2.new(1, pos, 1, 0)
			end
		end

		funcs.GetText = function(self)
			return self.TextBox.Text
		end

		funcs.SetText = function(self, text)
			self.TextBox.Text = text
		end

		local mt = getGuiMT(props, funcs)

		local function convert(textbox)
			local obj = initObj(props, mt)

			local view = Instance.new("Frame")
			view.BackgroundTransparency = textbox.BackgroundTransparency
			view.BackgroundColor3 = textbox.BackgroundColor3
			view.BorderSizePixel = textbox.BorderSizePixel
			view.BorderColor3 = textbox.BorderColor3
			view.Position = textbox.Position
			view.Size = textbox.Size
			view.ClipsDescendants = true
			view.Name = textbox.Name
			textbox.BackgroundTransparency = 1
			textbox.Position = UDim2.new(0, 0, 0, 0)
			textbox.Size = UDim2.new(1, 0, 1, 0)
			textbox.TextXAlignment = Enum.TextXAlignment.Left
			textbox.Name = "Input"

			obj.TextBox = textbox
			obj.View = view
			obj.Gui = view

			textbox.Changed:Connect(function(prop)
				if prop == "Text" or prop == "CursorPosition" or prop == "AbsoluteSize" then
					local cursorPos = obj.TextBox.CursorPosition
					if cursorPos ~= -1 then
						obj.CursorPos = cursorPos
					end
					obj:Update()
				end
			end)

			obj:Update()

			view.Parent = textbox.Parent
			textbox.Parent = view

			return obj
		end

		local function new()
			local textBox = Instance.new("TextBox")
			textBox.Active = true
			textBox.Size = UDim2.new(0, 100, 0, 20)
			textBox.BackgroundColor3 = Settings.Theme.TextBox
			textBox.BorderColor3 = Settings.Theme.Outline3
			textBox.ClearTextOnFocus = false
			textBox.TextColor3 = Settings.Theme.Text
			textBox.Font = Enum.Font.BuilderSans
			textBox.TextSize = 14
			textBox.Text = ""
			return convert(textBox)
		end

		return { new = new, convert = convert }
	end)()

	Lib.Label = (function()
		local props, funcs = {}, {}

		local mt = getGuiMT(props, funcs)

		local function new()
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Settings.Theme.Text
			label.TextTransparency = 0.1
			label.Size = UDim2.new(0, 100, 0, 20)
			label.Font = Enum.Font.BuilderSans
			label.TextSize = 14

			local obj = setmetatable({
				Gui = label,
			}, mt)
			return obj
		end

		return { new = new }
	end)()

	Lib.Frame = (function()
		local props, funcs = {}, {}

		local mt = getGuiMT(props, funcs)

		local function new()
			local fr = Instance.new("Frame")
			fr.BackgroundColor3 = Settings.Theme.Main1
			fr.BorderColor3 = Settings.Theme.Outline1
			fr.Size = UDim2.new(0, 50, 0, 50)

			local obj = setmetatable({
				Gui = fr,
			}, mt)
			return obj
		end

		return { new = new }
	end)()

	Lib.Button = (function()
		local props = {
			Gui = PH,
			Anim = PH,
			Disabled = false,
			OnClick = SIGNAL,
			OnDown = SIGNAL,
			OnUp = SIGNAL,
			AllowedButtons = { 1 },
		}
		local funcs = {}
		local tableFind = table.find

		funcs.Trigger = function(self, event, button)
			if not self.Disabled and tableFind(self.AllowedButtons, button) then
				self["On" .. event]:Fire(button)
			end
		end

		funcs.SetDisabled = function(self, dis)
			self.Disabled = dis

			if dis then
				self.Anim:Disable()
				self.Gui.TextTransparency = 0.5
			else
				self.Anim.Enable()
				self.Gui.TextTransparency = 0
			end
		end

		local mt = getGuiMT(props, funcs)

		local function new()
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.TextColor3 = Settings.Theme.Text
			b.TextTransparency = 0.1
			b.Size = UDim2.new(0, 100, 0, 20)
			b.Font = Enum.Font.BuilderSans
			b.TextSize = 14
			b.BackgroundColor3 = Settings.Theme.Button
			b.BorderColor3 = Settings.Theme.Outline2

			local obj = initObj(props, mt)
			obj.Gui = b
			obj.Anim = Lib.ButtonAnim(b, {
				Mode = 2,
				StartColor = Settings.Theme.Button,
				HoverColor = Settings.Theme.ButtonHover,
				PressColor = Settings.Theme.ButtonPress,
				OutlineColor = Settings.Theme.Outline2,
			})

			b.MouseButton1Click:Connect(function()
				obj:Trigger("Click", 1)
			end)
			b.MouseButton1Down:Connect(function()
				obj:Trigger("Down", 1)
			end)
			b.MouseButton1Up:Connect(function()
				obj:Trigger("Up", 1)
			end)

			b.MouseButton2Click:Connect(function()
				obj:Trigger("Click", 2)
			end)
			b.MouseButton2Down:Connect(function()
				obj:Trigger("Down", 2)
			end)
			b.MouseButton2Up:Connect(function()
				obj:Trigger("Up", 2)
			end)

			return obj
		end

		return { new = new }
	end)()

	Lib.DropDown = (function()
		local props = {
			Gui = PH,
			Anim = PH,
			Context = PH,
			Selected = PH,
			Disabled = false,
			CanBeEmpty = true,
			Options = {},
			GuiElems = {},
			OnSelect = SIGNAL,
		}
		local funcs = {}

		funcs.Update = function(self)
			local options = self.Options

			if #options > 0 then
				if not self.Selected then
					if not self.CanBeEmpty then
						self.Selected = options[1]
						self.GuiElems.Label.Text = options[1]
					else
						self.GuiElems.Label.Text = "- Select -"
					end
				else
					self.GuiElems.Label.Text = self.Selected
				end
			else
				self.GuiElems.Label.Text = "- Select -"
			end
		end

		funcs.ShowOptions = function(self)
			local context = self.Context

			context.Width = self.Gui.AbsoluteSize.X
			context.ReverseYOffset = self.Gui.AbsoluteSize.Y
			context:Show(self.Gui.AbsolutePosition.X, self.Gui.AbsolutePosition.Y + context.ReverseYOffset)
		end

		funcs.SetOptions = function(self, opts)
			self.Options = opts

			local context = self.Context
			local options = self.Options
			context:Clear()

			local onClick = function(option)
				self.Selected = option
				self.OnSelect:Fire(option)
				self:Update()
			end

			if self.CanBeEmpty then
				context:Add({
					Name = "- Select -",
					function()
						self.Selected = nil
						self.OnSelect:Fire(nil)
						self:Update()
					end,
				})
			end

			for i = 1, #options do
				context:Add({ Name = options[i], OnClick = onClick })
			end

			self:Update()
		end

		funcs.SetSelected = function(self, opt)
			self.Selected = type(opt) == "number" and self.Options[opt] or opt
			self:Update()
		end

		local mt = getGuiMT(props, funcs)

		local function new()
			local f = Instance.new("TextButton")
			f.AutoButtonColor = false
			f.Text = ""
			f.Size = UDim2.new(0, 100, 0, 20)
			f.BackgroundColor3 = Settings.Theme.TextBox
			f.BorderColor3 = Settings.Theme.Outline3

			local label = Lib.Label.new()
			label.Position = UDim2.new(0, 2, 0, 0)
			label.Size = UDim2.new(1, -22, 1, 0)
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Parent = f
			local arrow = create({
				{
					1,
					"Frame",
					{
						BackgroundTransparency = 1,
						Name = "EnumArrow",
						Position = UDim2.new(1, -16, 0, 2),
						Size = UDim2.new(0, 16, 0, 16),
					},
				},
				{
					2,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 1 },
						Position = UDim2.new(0, 8, 0, 9),
						Size = UDim2.new(0, 1, 0, 1),
					},
				},
				{
					3,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 1 },
						Position = UDim2.new(0, 7, 0, 8),
						Size = UDim2.new(0, 3, 0, 1),
					},
				},
				{
					4,
					"Frame",
					{
						BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
						BorderSizePixel = 0,
						Parent = { 1 },
						Position = UDim2.new(0, 6, 0, 7),
						Size = UDim2.new(0, 5, 0, 1),
					},
				},
			})
			arrow.Parent = f

			local obj = initObj(props, mt)
			obj.Gui = f
			obj.Anim = Lib.ButtonAnim(
				f,
				{ Mode = 2, StartColor = Settings.Theme.TextBox, LerpTo = Settings.Theme.Button, LerpDelta = 0.15 }
			)
			obj.Context = Lib.ContextMenu.new()
			obj.Context.Iconless = true
			obj.Context.MaxHeight = 200
			obj.Selected = nil
			obj.GuiElems = { Label = label }
			f.MouseButton1Down:Connect(function()
				obj:ShowOptions()
			end)
			obj:Update()
			return obj
		end

		return { new = new }
	end)()

	Lib.ClickSystem = (function()
		local props = {
			LastItem = PH,
			OnDown = SIGNAL,
			OnRelease = SIGNAL,
			AllowedButtons = { 1 },
			Combo = 0,
			MaxCombo = 2,
			ComboTime = 0.5,
			Items = {},
			ItemCons = {},
			ClickId = -1,
			LastButton = "",
			ActivePresses = {},
		}
		local funcs = {}
		local tostring = tostring

		local disconnect = function(con)
			local pos = table.find(con.Signal.Connections, con)
			if pos then
				table.remove(con.Signal.Connections, pos)
			end
		end

		funcs.Trigger = function(self, item, button, X, Y)
			if table.find(self.AllowedButtons, button) then
				if self.ActivePresses[button] then
					return
				end
				if self.ResolveItem then
					item = self.ResolveItem(item, X, Y)
					if not item then
						return
					end
				end
				if
					self.LastButton ~= button
					or self.LastItem ~= item
					or self.Combo == self.MaxCombo
					or tick() - self.ClickId > self.ComboTime
				then
					self.Combo = 0
					self.LastButton = button
					self.LastItem = item
				end

				self.Combo = self.Combo + 1
				self.ClickId = tick()

				local touchPress = button == 1 and service.UserInputService.TouchEnabled
					and service.UserInputService:GetLastInputType() == Enum.UserInputType.Touch
				local press = { Combo = self.Combo }
				self.ActivePresses[button] = press
				if button == 1 and not (self.OnTouchHold and touchPress) then
					task.delay(0.4, function()
						if
							Main.Alive
							and self.ActivePresses[button] == press
							and item.Parent
							and not Explorer.Dragging
							and Lib.CheckMouseInGui(item)
						then
							press.Held = true
							self.OnRelease:Fire(item, press.Combo, 2, Vector2.new(Main.Mouse.X, Main.Mouse.Y))
						end
					end)
				end

				local release
				release = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
					if input.UserInputType == Enum.UserInputType["MouseButton" .. button]
						or touchPress and input.UserInputType == Enum.UserInputType.Touch then
						release:Disconnect()
						self.ActivePresses[button] = nil
						if not press.Held and item.Parent and Lib.CheckMouseInGui(item) then
							self.OnRelease:Fire(item, press.Combo, button)
						end
					end
				end)

				self.OnDown:Fire(item, press.Combo, button)
			end
		end

		funcs.Add = function(self, item)
			if table.find(self.Items, item) then
				return
			end

			local cons = {}
			cons[1] = item.MouseButton1Down:Connect(function(X, Y)
				if self.OnTouchTap and service.UserInputService.TouchEnabled
					and service.UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
				self:Trigger(item, 1, X, Y)
			end)
			cons[2] = item.MouseButton2Down:Connect(function(X, Y)
				self:Trigger(item, 2, X, Y)
			end)

			if self.OnTouchHold and service.UserInputService.TouchEnabled then
				local pressed, held
				cons[3] = item.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.Touch then
						pressed, held = self.TouchTarget(item), false
					end
				end)
				cons[4] = item.TouchLongPress:Connect(function(points, state)
					if state == Enum.UserInputState.Begin and #points == 1 and pressed and pressed == self.TouchTarget(item) then
						held = true
						self:OnTouchHold(item, points[1])
					end
				end)
				cons[5] = item.TouchTap:Connect(function(points)
					if not held and #points == 1 and pressed and pressed == self.TouchTarget(item) then
						self:OnTouchTap(item, points[1])
					end
				end)
			end

			self.ItemCons[item] = cons
			self.Items[#self.Items + 1] = item
		end

		funcs.Remove = function(self, item)
			local ind = table.find(self.Items, item)
			if not ind then
				return
			end

			for i, v in pairs(self.ItemCons[item]) do
				v:Disconnect()
			end
			self.ItemCons[item] = nil
			table.remove(self.Items, ind)
		end

		local mt = { __index = funcs }

		local function new()
			local obj = initObj(props, mt)

			return obj
		end

		return { new = new }
	end)()

	return Lib
end

return { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
