--!strict

local Main, Lib, Apps, Settings, createSimple

local function InitDeps(data)
	Main, Lib, Apps, Settings, createSimple = data.Main, data.Lib, data.Apps, data.Settings, data.createSimple
end

local function escapeRichText(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function createHighlighter()
	local highlighter = {}
	local keywords = {
		lua = {
			"and",
			"break",
			"or",
			"else",
			"elseif",
			"if",
			"then",
			"until",
			"repeat",
			"while",
			"do",
			"for",
			"in",
			"end",
			"local",
			"return",
			"function",
			"export",
			"const",
		},
		rbx = {
			"game",
			"workspace",
			"script",
			"math",
			"string",
			"table",
			"task",
			"wait",
			"select",
			"next",
			"Enum",
			"error",
			"warn",
			"tick",
			"assert",
			"shared",
			"loadstring",
			"tonumber",
			"tostring",
			"type",
			"typeof",
			"unpack",
			"print",
			"Instance",
			"CFrame",
			"Vector3",
			"Vector2",
			"Color3",
			"UDim",
			"UDim2",
			"Ray",
			"BrickColor",
			"OverlapParams",
			"RaycastParams",
			"Axes",
			"Random",
			"Region3",
			"Rect",
			"TweenInfo",
			"collectgarbage",
			"not",
			"utf8",
			"pcall",
			"xpcall",
			"_G",
			"setmetatable",
			"getmetatable",
			"os",
			"pairs",
			"ipairs",
			"_VERSION",
			"gcinfo",
			"getfenv",
			"newproxy",
			"rawequal",
			"rawget",
			"rawlen",
			"rawset",
			"require",
			"setfenv",
			"DebuggerManager",
			"delay",
			"elapsedTime",
			"plugin",
			"PluginManager",
			"printidentity",
			"settings",
			"spawn",
			"stats",
			"time",
			"UserSettings",
			"version",
			"ypcall",
			"bit32",
			"buffer",
			"coroutine",
			"debug",
			"vector",
			"CatalogSearchParams",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"Content",
			"DateTime",
			"DockWidgetPluginGuiInfo",
			"Faces",
			"FloatCurveKey",
			"Font",
			"InstanceHandle",
			"NumberRange",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"Path2DControlPoint",
			"PathWaypoint",
			"PhysicalProperties",
			"Region3int16",
			"RotationCurveKey",
			"SecurityCapabilities",
			"SharedTable",
			"User",
			"ValueCurveKey",
			"Vector2int16",
			"Vector3int16",
		},
		exploit = {
			"hookmetamethod",
			"hookfunction",
			"getgc",
			"filtergc",
			"Drawing",
			"getgenv",
			"getsenv",
			"getrenv",
			"getfenv",
			"setfenv",
			"decompile",
			"saveinstance",
			"getrawmetatable",
			"setrawmetatable",
			"checkcaller",
			"cloneref",
			"clonefunction",
			"iscclosure",
			"islclosure",
			"isexecutorclosure",
			"newcclosure",
			"getfunctionhash",
			"crypt",
			"writefile",
			"appendfile",
			"loadfile",
			"readfile",
			"listfiles",
			"makefolder",
			"isfolder",
			"isfile",
			"delfile",
			"delfolder",
			"getcustomasset",
			"fireclickdetector",
			"firetouchinterest",
			"fireproximityprompt",
			"setthreadidentity",
			"getcallingscript",
			"getloadedmodules",
			"getrunningscripts",
			"getscriptbytecode",
			"getscriptclosure",
			"getscriptfromthread",
			"getscripthash",
			"getscripts",
			"compareinstances",
			"loadstring",
			"firesignal",
			"getcallbackvalue",
			"getconnections",
			"gethui",
			"replicatesignal",
			"getinstances",
			"getnilinstances",
			"getnamecallmethod",
			"isreadonly",
			"lz4decompress",
			"setreadonly",
			"cleardrawcache",
			"identifyexecutor",
			"getrenderproperty",
			"restorefunction",
			"isrenderobj",
			"base64decode",
			"lz4compress",
			"request",
			"base64encode",
			"getthreadidentity",
			"isscriptable",
			"gethiddenproperty",
			"setrenderproperty",
			"sethiddenproperty",
			"getreg",
			"setscriptable",
			"WebSocket",
			"setclipboard",
			"oth",
			"setstackhidden",
			"cache",
			"raknet",
			"getbspval",
			"getpcd",
			"gethwid",
			"setfpscap",
			"zstdcompress",
			"zstddecompress",
			"create_comm_channel",
			"get_comm_channel",
			"getactors",
			"getactorthreads",
			"getdeletedactors",
			"is_parallel",
			"run_on_actor",
			"run_on_thread",
		},
		operators = {
			"#",
			"+",
			"-",
			"*",
			"%",
			"/",
			"^",
			"=",
			"~",
			"=",
			"<",
			">",
			",",
			".",
			"(",
			")",
			"{",
			"}",
			"[",
			"]",
			";",
			":",
		},
	}

	local colors = {
		numbers = Color3.fromRGB(255, 198, 0),
		boolean = Color3.fromRGB(255, 198, 0),
		operator = Color3.fromRGB(204, 204, 204),
		lua = Color3.fromRGB(132, 214, 247),
		exploit = Color3.fromRGB(171, 84, 247),
		rbx = Color3.fromRGB(248, 109, 124),
		str = Color3.fromRGB(173, 241, 132),
		comment = Color3.fromRGB(102, 102, 102),
		null = Color3.fromRGB(255, 198, 0),
		call = Color3.fromRGB(253, 251, 172),
		self_call = Color3.fromRGB(253, 251, 172),
		local_color = Color3.fromRGB(248, 109, 115),
		function_color = Color3.fromRGB(248, 109, 115),
		self_color = Color3.fromRGB(248, 109, 115),
		local_property = Color3.fromRGB(97, 161, 241),
	}

	local function createKeywordSet(keywords)
		local keywordSet = {}
		for _, keyword in ipairs(keywords) do
			keywordSet[keyword] = true
		end
		return keywordSet
	end

	local luaSet = createKeywordSet(keywords.lua)
	local exploitSet = createKeywordSet(keywords.exploit)
	local rbxSet = createKeywordSet(keywords.rbx)
	local operatorsSet = createKeywordSet(keywords.operators)

	local function getHighlight(tokens, index)
		local token = tokens[index]
		if token == "" then
			return nil
		end

		if colors[token .. "_color"] then
			return colors[token .. "_color"]
		end

		if tonumber(token) then
			return colors.numbers
		elseif token == "nil" then
			return colors.null
		elseif token:sub(1, 2) == "--" then
			return colors.comment
		elseif operatorsSet[token] then
			return colors.operator
		elseif luaSet[token] then
			return colors.rbx
		elseif rbxSet[token] then
			return colors.lua
		elseif exploitSet[token] then
			return colors.exploit
		elseif token:sub(1, 1) == '"' or token:sub(1, 1) == "'" then
			return colors.str
		elseif token == "true" or token == "false" then
			return colors.boolean
		end

		if tokens[index + 1] == "(" then
			if tokens[index - 1] == ":" then
				return colors.self_call
			end

			return colors.call
		end

		if tokens[index - 1] == "." then
			if tokens[index - 2] == "Enum" then
				return colors.rbx
			end

			return colors.local_property
		end
	end

	function highlighter.run(source)
		local tokens = {}
		local currentToken = ""

		local inString = false
		local inComment = false
		local commentPersist = false

		for i = 1, #source do
			local character = source:sub(i, i)

			if inComment then
				if character == "\n" and not commentPersist then
					table.insert(tokens, currentToken)
					table.insert(tokens, character)
					currentToken = ""

					inComment = false
				elseif source:sub(i - 1, i) == "]]" and commentPersist then
					currentToken ..= "]"

					table.insert(tokens, currentToken)
					currentToken = ""

					inComment = false
					commentPersist = false
				else
					currentToken = currentToken .. character
				end
			elseif inString then
				if character == inString and source:sub(i - 1, i - 1) ~= "\\" or character == "\n" then
					currentToken = currentToken .. character
					inString = false
				else
					currentToken = currentToken .. character
				end
			else
				if source:sub(i, i + 1) == "--" then
					table.insert(tokens, currentToken)
					currentToken = "-"
					inComment = true
					commentPersist = source:sub(i + 2, i + 3) == "[["
				elseif character == '"' or character == "'" then
					table.insert(tokens, currentToken)
					currentToken = character
					inString = character
				elseif operatorsSet[character] then
					table.insert(tokens, currentToken)
					table.insert(tokens, character)
					currentToken = ""
				elseif character:match("[%w_]") then
					currentToken = currentToken .. character
				else
					table.insert(tokens, currentToken)
					table.insert(tokens, character)
					currentToken = ""
				end
			end
		end

		table.insert(tokens, currentToken)

		local highlighted = {}

		for i, token in ipairs(tokens) do
			local highlight = getHighlight(tokens, i)

			if highlight then
				local syntax = string.format('<font color = "#%s">%s</font>', highlight:ToHex(), escapeRichText(token))

				table.insert(highlighted, syntax)
			else
				table.insert(highlighted, escapeRichText(token))
			end
		end

		return table.concat(highlighted)
	end

	return highlighter
end

local function CreateModule()
	local console = {}
	local theme = Settings.Theme
	local logLimit = 500
	local messageTypes = {
		{ Enum.MessageType.MessageOutput, "Output", theme.Text },
		{ Enum.MessageType.MessageInfo, "Information", Color3.fromRGB(128, 215, 255) },
		{ Enum.MessageType.MessageWarning, "Warning", Color3.fromRGB(255, 192, 93) },
		{ Enum.MessageType.MessageError, "Error", Color3.fromRGB(255, 101, 103) },
	}
	local messageColors = {}
	for _, messageType in ipairs(messageTypes) do
		messageColors[messageType[1]] = messageType[3]
	end

	local window = Lib.Window.new()
	window:SetTitle("Console")
	window.MinX = 284
	window.MinY = 165
	window:Resize(530, 335)
	window:SetResizeHandleStyle("Dock")
	console.Window = window

	local function node(class, props)
		props.BorderSizePixel = 0
		return createSimple(class, props)
	end
	local function label(class, props, size)
		local object = node(class, props)
		Lib.StudioText(object)
		object.TextSize = size or 12
		return object
	end
	local function button(parent, name, text, position, size, icon, tooltip, fill)
		local control = label("TextButton", {
			Parent = parent,
			Name = name,
			Text = text,
			Position = position,
			Size = size,
			BackgroundColor3 = fill or theme.ButtonHover,
			BackgroundTransparency = fill and 0 or 1,
			AutoButtonColor = false,
		})
		if icon then
			local image = Main.GetStudioAsset(icon)
			if image then
				control.Text = ""
				node("ImageLabel", {
					Parent = control,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(16, 16),
					BackgroundTransparency = 1,
					Image = image,
				})
			end
		end
		control.MouseEnter:Connect(function()
			control.BackgroundColor3 = theme.ButtonHover
			control.BackgroundTransparency = 0
		end)
		control.MouseLeave:Connect(function()
			control.BackgroundColor3 = fill or theme.ButtonHover
			control.BackgroundTransparency = fill and 0 or 1
		end)
		if tooltip then
			Lib.StudioTooltip(control, tooltip)
		end
		return control
	end
	local function outline(control)
		return createSimple("UIStroke", {
			Parent = control,
			Color = theme.Outline2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end

	local content = window.GuiElems.Content
	content.BackgroundColor3 = theme.Main1
	local toolbar = node("Frame", {
		Parent = content,
		Name = "Toolbar",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = theme.Main2,
	})
	local severity = button(
		toolbar,
		"MessageType",
		"All Messages",
		UDim2.fromOffset(6, 5),
		UDim2.fromOffset(108, 22),
		nil,
		nil,
		theme.TextBox
	)
	severity.TextXAlignment = Enum.TextXAlignment.Left
	createSimple("UIPadding", { Parent = severity, PaddingLeft = UDim.new(0, 7) })
	outline(severity)
	local chevron = Main.GetStudioAsset("bridge/chevron-down")
	node("ImageLabel", {
		Parent = severity,
		Position = UDim2.new(1, -23, 0, 5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Image = chevron or "",
	})

	local filter = label("TextBox", {
		Parent = toolbar,
		Name = "Filter",
		Position = UDim2.fromOffset(121, 5),
		Size = UDim2.new(1, -202, 0, 22),
		BackgroundColor3 = theme.TextBox,
		Text = "",
		PlaceholderText = "Filter...",
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
	})
	filter.PlaceholderColor3 = theme.PlaceholderText
	createSimple("UIPadding", { Parent = filter, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 6) })
	local filterStroke = outline(filter)
	filter.Focused:Connect(function()
		filterStroke.Color = theme.Focus
	end)
	filter.FocusLost:Connect(function()
		filterStroke.Color = theme.Outline2
	end)
	local clear =
		button(toolbar, "Clear", "Clear", UDim2.new(1, -75, 0, 5), UDim2.fromOffset(41, 22), nil, "Clear Output")
	local options = button(
		toolbar,
		"Options",
		"ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦",
		UDim2.new(1, -30, 0, 5),
		UDim2.fromOffset(24, 22),
		"native/plugins/more",
		"Output Options"
	)
	node("Frame", {
		Parent = toolbar,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.Outline2,
	})

	local output = node("ScrollingFrame", {
		Parent = content,
		Name = "Output",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = theme.PlaceholderText,
		Active = true,
	})
	local layout = createSimple("UIListLayout", { Parent = output, SortOrder = Enum.SortOrder.LayoutOrder })
	createSimple("UIPadding", {
		Parent = output,
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	})

	local commandBar = node("Frame", {
		Parent = content,
		Name = "CommandBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = theme.Main2,
	})
	node("Frame", { Parent = commandBar, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = theme.Outline2 })
	local prompt = label("TextLabel", {
		Parent = commandBar,
		Name = "Prompt",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(16, 24),
		BackgroundTransparency = 1,
		Text = ">",
	}, 15)
	prompt.Font = Enum.Font.Code
	prompt.TextColor3 = theme.Focus
	local commandField = node("Frame", {
		Parent = commandBar,
		Position = UDim2.fromOffset(25, 5),
		Size = UDim2.new(1, -72, 0, 22),
		BackgroundColor3 = theme.TextBox,
		ClipsDescendants = true,
	})
	local commandStroke = outline(commandField)
	local command = label("TextBox", {
		Parent = commandField,
		Name = "Command",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		PlaceholderText = "Run a command",
		ClearTextOnFocus = false,
	}, 14)
	command.Font = Enum.Font.Code
	command.PlaceholderColor3 = theme.PlaceholderText
	createSimple("UIPadding", { Parent = command, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
	local commandSyntax = label("TextLabel", {
		Parent = commandField,
		Name = "CommandSyntax",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Visible = false,
		Interactable = false,
	}, 14)
	commandSyntax.Font = Enum.Font.Code
	local run = button(commandBar, "Run", "Run", UDim2.new(1, -42, 0, 5), UDim2.fromOffset(36, 22))
	local compile = loadstring
	run.Active = type(compile) == "function"
	if not run.Active then
		run.TextColor3 = theme.PlaceholderText
		command.TextEditable = false
		command.PlaceholderText = "Command execution unavailable"
	end

	local initialized = false
	console.Init = function()
		if initialized then
			return
		end
		initialized = true

		local logService = game:GetService("LogService")
		local inputService = game:GetService("UserInputService")
		local highlighter = createHighlighter()
		local entries = {}
		local rows = {}
		local firstId, lastId, paintedId = 1, 0, 0
		local activeType
		local filterText = ""
		local showTimestamp = true
		local showContext = false
		local autoScroll = false
		local ctrlZoom = false
		local fontSize = 14
		local pending = false
		local needsReset = false
		local menu

		local function getRowText(entry)
			local timestamp = if showTimestamp
				then os.date("%H:%M:%S", math.floor(entry.Timestamp / 1000)) .. (".%03d   "):format(
					entry.Timestamp % 1000
				)
				else ""
			local suffix = if showContext then "  -  Client" else ""
			local color = messageColors[entry.Type] or theme.Text
			return timestamp .. entry.Message .. suffix,
				('<font color="#%s">%s</font><font color="#%s">%s</font><font color="#%s">%s</font>'):format(
					theme.PlaceholderText:ToHex(),
					timestamp,
					color:ToHex(),
					escapeRichText(entry.Message),
					theme.PlaceholderText:ToHex(),
					suffix
				)
		end
		local function addRow(entry, id)
			local plain, formatted = getRowText(entry)
			local row = node("TextBox", {
				Name = "Message",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ClearTextOnFocus = false,
				MultiLine = true,
				TextEditable = false,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Font = Enum.Font.Code,
				TextSize = fontSize,
				TextColor3 = messageColors[entry.Type] or theme.Text,
				Text = formatted,
				RichText = true,
				LayoutOrder = id,
			})
			createSimple("UIPadding", {
				Parent = row,
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 4),
			})
			row.Focused:Connect(function()
				row.RichText = false
				row.Text = plain
			end)
			row.FocusLost:Connect(function()
				row.RichText = true
				row.Text = formatted
			end)
			rows[id] = row
			row.Parent = output
		end
		local function clearRows()
			for _, row in pairs(rows) do
				row:Destroy()
			end
			table.clear(rows)
		end
		local function scrollToLatest()
			output.CanvasPosition =
				Vector2.new(0, math.max(0, layout.AbsoluteContentSize.Y + 8 - output.AbsoluteWindowSize.Y))
		end
		local function scheduleRender()
			if pending or not window:IsContentVisible() then
				return
			end
			pending = true
			task.defer(function()
				while Main.Alive and window:IsContentVisible() and (needsReset or paintedId < lastId) do
					if needsReset then
						needsReset = false
						clearRows()
						paintedId = firstId - 1
					end
					local first = math.max(firstId, paintedId + 1)
					local last = math.min(lastId, first + 31)
					for id = first, last do
						local entry = entries[id]
						if
							(not activeType or entry.Type == activeType)
							and (filterText == "" or string.find(string.lower(entry.Message), filterText, 1, true))
						then
							addRow(entry, id)
						end
					end
					paintedId = last
					if paintedId < lastId then
						task.wait()
					end
				end
				pending = false
			end)
		end
		local function refresh(resetScroll)
			needsReset = true
			if resetScroll then
				output.CanvasPosition = Vector2.new(0, 0)
			end
			scheduleRender()
		end
		local function setFontSize(value)
			fontSize = math.clamp(value, 8, 40)
			for _, row in pairs(rows) do
				row.TextSize = fontSize
			end
		end

		local function openMenu(anchor, populate)
			menu = menu or Apps.ContextMenu.new()
			menu:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
			menu.PreferredWidth = 176
			if menu.Shown and menu.Anchor == anchor then
				menu:Hide()
				return
			end
			menu:Clear()
			menu.Anchor = anchor
			populate(menu)
			menu:Show(anchor.AbsolutePosition.X, anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y + 3)
		end
		local checked = Main.GetStudioAsset("native/explorer/checked")
		local function addToggle(menu, text, enabled, callback)
			menu:Add({ Text = text, Icon = if enabled then checked else nil, OnClick = callback })
		end
		severity.Activated:Connect(function()
			openMenu(severity, function(menu)
				local function addType(messageType, caption)
					addToggle(menu, caption, activeType == messageType, function()
						activeType = messageType
						severity.Text = caption
						refresh(true)
					end)
				end
				addType(nil, "All Messages")
				for _, messageType in ipairs(messageTypes) do
					addType(messageType[1], messageType[2])
				end
			end)
		end)
		options.Activated:Connect(function()
			openMenu(options, function(menu)
				addToggle(menu, "Show Timestamp", showTimestamp, function()
					showTimestamp = not showTimestamp
					refresh(false)
				end)
				addToggle(menu, "Show Context", showContext, function()
					showContext = not showContext
					refresh(false)
				end)
				addToggle(menu, "Auto Scroll", autoScroll, function()
					autoScroll = not autoScroll
					if autoScroll then
						scrollToLatest()
					end
				end)
				menu:AddDivider()
				menu:Add({
					Text = "Increase Text Size",
					OnClick = function()
						setFontSize(fontSize + 1)
					end,
				})
				menu:Add({
					Text = "Decrease Text Size",
					OnClick = function()
						setFontSize(fontSize - 1)
					end,
				})
				menu:Add({
					Text = "Reset Text Size",
					OnClick = function()
						setFontSize(14)
					end,
				})
				addToggle(menu, "Ctrl + Scroll to Zoom", ctrlZoom, function()
					ctrlZoom = not ctrlZoom
					output.ScrollingEnabled = true
				end)
			end)
		end)

		local function clearOutput()
			table.clear(entries)
			firstId = lastId + 1
			paintedId = lastId
			needsReset = false
			clearRows()
			output.CanvasPosition = Vector2.new(0, 0)
		end
		clear.Activated:Connect(clearOutput)
		filter:GetPropertyChangedSignal("Text"):Connect(function()
			filterText = string.lower(filter.Text)
			refresh(true)
		end)
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			if autoScroll then
				scrollToLatest()
			end
		end)

		local insideOutput = false
		local function isControlDown()
			return inputService:IsKeyDown(Enum.KeyCode.LeftControl) or inputService:IsKeyDown(Enum.KeyCode.RightControl)
		end
		local function updateScroll()
			output.ScrollingEnabled = not (ctrlZoom and insideOutput and isControlDown())
		end
		output.MouseEnter:Connect(function()
			insideOutput = true
			updateScroll()
		end)
		output.MouseLeave:Connect(function()
			insideOutput = false
			updateScroll()
		end)
		Main.TrackSignal(inputService.InputBegan, function(input)
			if window:IsContentVisible() then
				if
					input.KeyCode == Enum.KeyCode.K
					and isControlDown()
					and Lib.CheckMouseInGui(content)
					and (not inputService:GetFocusedTextBox() or inputService:GetFocusedTextBox() == filter)
				then
					clearOutput()
				end
				updateScroll()
			end
		end)
		Main.TrackSignal(inputService.InputEnded, updateScroll)
		Main.TrackSignal(inputService.InputChanged, function(input)
			if
				ctrlZoom
				and insideOutput
				and window:IsContentVisible()
				and isControlDown()
				and input.UserInputType == Enum.UserInputType.MouseWheel
			then
				setFontSize(fontSize + input.Position.Z)
			end
		end)

		Main.TrackSignal(logService.MessageOut, function(message, messageType)
			lastId += 1
			entries[lastId] = {
				Message = message,
				Type = messageType,
				Timestamp = DateTime.now().UnixTimestampMillis,
			}
			if lastId - firstId >= logLimit then
				local row = rows[firstId]
				if row then
					row:Destroy()
					rows[firstId] = nil
				end
				entries[firstId] = nil
				firstId += 1
			end
			scheduleRender()
		end)
		Main.TrackSignal(window.OnActivate, scheduleRender)
		Main.TrackSignal(window.OnRestore, scheduleRender)
		Main.TrackSignal(window.OnDeactivate, function()
			if menu then
				menu:Hide()
			end
			insideOutput = false
			output.ScrollingEnabled = true
		end)
		Main.AddCleanup(function()
			if menu then
				menu:Destroy()
			end
			table.clear(entries)
			clearRows()
		end)

		local function executeCommand()
			local text = command.Text
			if not text:find("%S") or type(compile) ~= "function" then
				return
			end
			print("> " .. text)
			local chunk, compileError = compile(text)
			if not chunk then
				error(compileError, 0)
			end
			chunk()
		end
		command:GetPropertyChangedSignal("Text"):Connect(function()
			local text = command.Text:gsub("\n", "    ")
			if text ~= command.Text then
				command.Text = text
				return
			end
			commandSyntax.Text = highlighter.run(text)
			commandSyntax.Visible = text ~= ""
		end)
		command.Focused:Connect(function()
			commandStroke.Color = theme.Focus
		end)
		command.FocusLost:Connect(function(enterPressed)
			commandStroke.Color = theme.Outline2
			if enterPressed then
				executeCommand()
			end
		end)
		run.Activated:Connect(executeCommand)
	end

	return console
end

return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
