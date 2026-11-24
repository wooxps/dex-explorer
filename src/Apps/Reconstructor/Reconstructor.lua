--!strict

local Main, Lib, Apps, Settings, API, env, service, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, API, env, service, createSimple =
		d.Main, d.Lib, d.Apps, d.Settings, d.API, d.env, d.service, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local app = { ViewStats = { Sorts = 0, Rebuilds = 0 } }
	local window, session, treeFrame, renderer, status, detail, searchBox, pasteBox, detailsFrame, pathLabel, classLabel, scanButton, importFrame, importTitle, importButton, empty
	local entries, flat, expanded = {}, {}, {}
	local childOrder = setmetatable({}, { __mode = "k" })
	local names = setmetatable({}, { __mode = "k" })
	local paths = setmetatable({}, { __mode = "k" })
	local selected, hovered
	local notice = ""
	local displayRevision = -1
	local scheduled = false
	local destroyed = false
	Main.AddCleanup(function()
		destroyed = true
	end)
	local theme = Settings.Theme
	local colors = {
		Surface = Color3.fromRGB(25, 26, 31),
		Chrome = Color3.fromRGB(33, 34, 39),
		Muted = Color3.fromRGB(155, 157, 165),
	}
	local function label(parent, text, position, size)
		local gui = createSimple("TextLabel", {
			Parent = parent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = position,
			Size = size,
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Lib.StudioText(gui)
		gui.TextSize = 12
		return gui
	end
	local function button(parent, text, x, y, width, action)
		local gui = createSimple("TextButton", {
			Parent = parent,
			Name = text,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = theme.ButtonHover,
			BackgroundTransparency = 1,
			Text = text,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, 24),
		})
		Lib.StudioText(gui)
		gui.TextSize = 12
		gui.Activated:Connect(action)
		gui.MouseEnter:Connect(function()
			gui.BackgroundTransparency = 0
		end)
		gui.MouseLeave:Connect(function()
			gui.BackgroundTransparency = 1
		end)
		return gui
	end
	local function textbox(parent, text, position, size, multi)
		local gui = createSimple("TextBox", {
			Parent = parent,
			BorderSizePixel = 0,
			BackgroundColor3 = colors.Surface,
			Text = text,
			ClearTextOnFocus = false,
			Position = position,
			Size = size,
			MultiLine = multi or false,
			TextWrapped = multi or false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			PlaceholderColor3 = colors.Muted,
		})
		Lib.StudioText(gui)
		gui.TextSize = 12
		createSimple("UIPadding", {
			Parent = gui,
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, multi and 6 or 0),
		})
		return gui
	end
	local function layout()
		if not treeFrame then
			return
		end
		local importing = importFrame and importFrame.Visible
		treeFrame.Visible = not importing
		detailsFrame.Visible = selected ~= nil and not importing
		treeFrame.Size = UDim2.new(1, 0, 1, selected and -180 or -54)
	end
	local function updateStatus()
		if not status then
			return
		end
		local stats = session.Stats or {}
		local state = session.Running and "Scanning"
			or stats.Phase == "Failed" and "Scan failed"
			or session.AutoPaused and "Scan stopped"
			or stats.Phase == "Complete" and "Scan complete"
			or "Ready"
		status.Text = notice ~= "" and notice
			or state .. "  ·  " .. math.max(0, session.Tree.Count - #session.Tree.Roots) .. " objects"
		scanButton.Text = session.Running and "Stop" or "Scan"
	end
	local function showEvidence(node)
		selected = node and node.Id
		layout()
		if not node then
			return
		end
		pathLabel.Text = table.concat(node.Path, ".")
		local class = session.Tree:ClassLabel(node)
		classLabel.Text = class == "Unknown" and "Type unknown" or "Type: " .. class:gsub("%?$", " (suggested)")
		local lines = {}
		for _, evidence in ipairs(node.Evidence) do
			lines[#lines + 1] = tostring(evidence.Source)
				.. (evidence.Line and ":" .. evidence.Line or "")
				.. " — "
				.. evidence.Kind
		end
		if #node.Evidence == 0 then
			lines[#lines + 1] = "Contains referenced objects; no direct source match."
		end
		detail.Text = table.concat(lines, "\n")
	end
	local refresh
	local function rebuild()
		flat = {}
		app.ViewStats.Rebuilds += 1
		displayRevision = session.Tree.Revision
		local query = searchBox.Text:lower()
		local matches = {}
		local function pathMatches(node)
			local path = paths[node]
			if not path then
				path = table.concat(node.Path, "."):lower()
				paths[node] = path
			end
			return path:find(query, 1, true) ~= nil
		end
		local function childrenOf(node)
			local cached = childOrder[node]
			if cached and cached.Count == #node.Children then
				return cached.Items
			end
			local children = table.clone(node.Children)
			for _, child in ipairs(children) do
				if not names[child] then
					names[child] = child.Name:lower()
				end
			end
			table.sort(children, function(a, b)
				return names[a] < names[b]
			end)
			app.ViewStats.Sorts += 1
			childOrder[node] = { Count = #node.Children, Items = children }
			return children
		end
		local function visit(node, depth)
			local children = childrenOf(node)
			if query ~= "" then
				local matched = pathMatches(node)
				for _, child in ipairs(children) do
					if matches[child.Id] then
						matched = true
						break
					end
				end
				if not matched then
					return
				end
			end
			flat[#flat + 1] = { Node = node, Depth = depth }
			if expanded[node.Id] or query ~= "" then
				for _, child in ipairs(children) do
					visit(child, depth + 1)
				end
			end
		end
		if query ~= "" then
			local function mark(node)
				local found = pathMatches(node)
				for _, child in ipairs(node.Children) do
					if mark(child) then
						found = true
					end
				end
				matches[node.Id] = found
				return found
			end
			for _, root in ipairs(session.Tree.Roots) do
				mark(root)
			end
		end
		for _, root in ipairs(session.Tree.Roots) do
			visit(root, 0)
		end
		empty.Visible = #flat == 0
		treeFrame.CanvasSize = UDim2.fromOffset(0, #flat * 20)
		refresh()
	end
	refresh = function()
		if not renderer then
			return
		end
		local offset = math.floor(treeFrame.CanvasPosition.Y / 20)
		local count = math.min(math.ceil(treeFrame.AbsoluteSize.Y / 20) + 1, math.max(0, #flat - offset))
		renderer:SetCanvasIndex(offset)
		renderer:BeginFrame(count)
		local function highlighted(node)
			while node do
				if node.Id == selected then
					return true
				end
				node = node.Parent
			end
			return false
		end
		for i = 1, count do
			local row = entries[i]
			if not row then
				row = renderer:NewRow(i)
				entries[i] = row
				row.Activated:Connect(function()
					local item = flat[math.floor(treeFrame.CanvasPosition.Y / 20) + i]
					if item then
						showEvidence(item.Node)
						refresh()
					end
				end)
				row.Indent.Expand.Activated:Connect(function()
					local item = flat[math.floor(treeFrame.CanvasPosition.Y / 20) + i]
					if item then
						expanded[item.Node.Id] = not expanded[item.Node.Id]
						rebuild()
					end
				end)
				row.MouseEnter:Connect(function()
					hovered = i
					refresh()
				end)
				row.MouseLeave:Connect(function()
					if hovered == i then
						hovered = nil
						refresh()
					end
				end)
			end
			local item = flat[offset + i]
			local node = item.Node
			local context = highlighted(node.Parent)
			local state = Apps.ExplorerPolicy.RowState(selected == node.Id, context, hovered == i, true, theme)
			local depth = Apps.NodeDetailsPlaceholder.Measure(item.Depth, 0).iconLeft
			state.connectedAbove = highlighted(node) and offset + i > 1 and highlighted(flat[offset + i - 1].Node)
				or false
			state.connectedBelow = highlighted(node) and offset + i < #flat and highlighted(flat[offset + i + 1].Node)
				or false
			local viewport = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
			state.name = node.Name
			state.depth = depth
			state.height = 20
			state.size = UDim2.new(1, 0, 0, 20)
			state.position = UDim2.fromOffset(0, (i - 1) * 20)
			state.labelWidth = math.max(4, viewport.X - depth - 24)
			state.guideCount = Settings.Explorer.IndentGuides and item.Depth or 0
			state.expanded = expanded[node.Id] or searchBox.Text ~= ""
			state.hasChildren = #node.Children > 0
			state.insertVisible = false
			state.insertX = 0
			state.backgroundX = 0
			state.backgroundWidth = math.max(0, viewport.X - 2)
			renderer:UpdateRow(row, state)
			local class = session.Tree:ClassLabel(node):gsub("%?$", "")
			Apps.Explorer.DisplayClassIcon(row.Indent.Icon, API.Classes[class] and class or "Instance")
		end
		for i = #entries, count + 1, -1 do
			entries[i] = nil
		end
		renderer:EndFrame()
	end
	local function changed(message)
		app.Status = message or app.Status
		if message then
			notice = ""
		end
		updateStatus()
		if scheduled then
			return
		end
		scheduled = true
		task.delay(0.1, function()
			scheduled = false
			if destroyed then
				return
			end
			if app.Session and Apps.Explorer.SyncInferredTree then
				Apps.Explorer.SyncInferredTree(app.Session.Tree)
			end
			if window and window:IsVisible() and not window.Minimized and displayRevision ~= session.Tree.Revision then
				rebuild()
				if selected then
					showEvidence(session.Tree.Nodes[selected])
				end
			end
		end)
	end
	function app.GetSession()
		if not app.Session then
			Apps.ReconstructorSession.Classes = API.Classes
			app.Session = Apps.ReconstructorSession.Create(changed)
		end
		return app.Session
	end
	function app.StartAutomatic()
		if app.Automatic then
			return
		end
		app.Automatic = true
		local current = app.GetSession()
		current:Listen()
		current:Scan()
		task.delay(10, function()
			if not destroyed then
				current:RequestScan()
			end
		end)
		local queued = false
		Main.TrackSignal(game.DescendantAdded, function(obj)
			if Apps.Explorer.IsInferredObject(obj) then
				return
			end
			if queued or (not obj:IsA("LuaSourceContainer") and not obj:IsA("StringValue")) then
				return
			end
			queued = true
			task.delay(2, function()
				queued = false
				current:RequestScan()
			end)
		end)
	end
	function app.Open()
		if window then
			updateStatus()
			window:Show()
			return
		end
		window = Lib.Window.new()
		window:SetTitle("Reconstructor")
		window.MinX = 420
		window.MinY = 260
		window:Resize(640, 440)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		app.Window = window
		local content = window.GuiElems.Content
		content.BackgroundColor3 = colors.Surface
		session = app.GetSession()
		for _, root in ipairs(session.Tree.Roots) do
			expanded[root.Id] = true
		end
		local bar = createSimple("Frame", {
			Name = "Toolbar",
			Parent = content,
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		searchBox = textbox(bar, "", UDim2.fromOffset(5, 4), UDim2.new(1, -117, 0, 24))
		searchBox.Name = "Search"
		searchBox.PlaceholderText = "Filter paths"
		scanButton = button(bar, "Scan", 0, 4, 72, function()
			if session.Running then
				session:Cancel()
			else
				session:Scan()
			end
			updateStatus()
		end)
		scanButton.Position = UDim2.new(1, -108, 0, 4)
		local function showText(text, exporting)
			pasteBox.Text = text or ""
			pasteBox.TextEditable = not exporting
			importTitle.Text = exporting and "Reconstructor JSON" or "Add source or traceback"
			importButton.Visible = not exporting
			importFrame.Visible = true
			layout()
			pasteBox:CaptureFocus()
		end
		local more
		more = button(bar, "⋯", 0, 4, 28, function()
			local menu = Apps.ContextMenu.new()
			menu.Iconless = true
			menu.Width = 210
			menu:Add({
				Name = "Expand all",
				OnClick = function()
					for id in pairs(session.Tree.Nodes) do
						expanded[id] = true
					end
					rebuild()
				end,
			})
			menu:Add({
				Name = "Collapse all",
				OnClick = function()
					table.clear(expanded)
					showEvidence(nil)
					rebuild()
				end,
			})
			menu:AddDivider()
			menu:Add({
				Name = "Copy selected path",
				Disabled = not selected or type(env.setclipboard) ~= "function",
				OnClick = function()
					local node = selected and session.Tree.Nodes[selected]
					if node then
						local ok = pcall(env.setclipboard, table.concat(node.Path, "."))
						notice = ok and "Path copied" or "Could not copy path"
						updateStatus()
					end
				end,
			})
			menu:Add({
				Name = "Export tree as JSON",
				OnClick = function()
					local json = service.HttpService:JSONEncode(session.Tree:Export())
					if type(env.setclipboard) == "function" then
						local ok = pcall(env.setclipboard, json)
						notice = ok and "Tree JSON copied" or "Could not copy JSON"
						updateStatus()
					else
						showText(json, true)
					end
				end,
			})
			menu:Add({
				Name = "Add source or traceback…",
				OnClick = function()
					showText("", false)
				end,
			})
			menu:Show(more.AbsolutePosition.X, more.AbsolutePosition.Y + 24)
		end)
		more.Name = "More"
		more.Position = UDim2.new(1, -32, 0, 4)
		treeFrame = createSimple("ScrollingFrame", {
			Parent = content,
			Name = "InferredTree",
			BackgroundColor3 = colors.Surface,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 1, -54),
			CanvasSize = UDim2.fromOffset(0, 0),
			CanvasPosition = Vector2.new(0, 0),
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = colors.Muted,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ClipsDescendants = true,
		})
		renderer = Apps.SessionView.Create(treeFrame)
		empty = label(treeFrame, "No matching paths", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 24))
		empty.Name = "Empty"
		empty.TextColor3 = colors.Muted
		empty.Visible = false
		detailsFrame = createSimple("Frame", {
			Name = "Details",
			Parent = content,
			Visible = false,
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -148),
			Size = UDim2.new(1, 0, 0, 126),
		})
		pathLabel = label(detailsFrame, "", UDim2.fromOffset(8, 5), UDim2.new(1, -16, 0, 20))
		pathLabel.Name = "Path"
		classLabel = label(detailsFrame, "", UDim2.fromOffset(8, 27), UDim2.new(1, -16, 0, 18))
		classLabel.TextColor3 = colors.Muted
		classLabel.Name = "Type"
		local sources = createSimple("ScrollingFrame", {
			Name = "Sources",
			Parent = detailsFrame,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 50),
			Size = UDim2.new(1, -16, 1, -56),
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = colors.Muted,
			ClipsDescendants = true,
		})
		detail = label(sources, "", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0))
		detail.Name = "Evidence"
		detail.TextWrapped = true
		detail.TextTruncate = Enum.TextTruncate.None
		detail.TextYAlignment = Enum.TextYAlignment.Top
		detail.AutomaticSize = Enum.AutomaticSize.Y
		detail.TextSize = 11
		importFrame = createSimple("Frame", {
			Name = "TextImport",
			Parent = content,
			Visible = false,
			BackgroundColor3 = colors.Surface,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 1, -54),
		})
		importTitle = label(importFrame, "Add source or traceback", UDim2.fromOffset(8, 4), UDim2.new(1, -16, 0, 24))
		pasteBox = textbox(importFrame, "", UDim2.fromOffset(8, 32), UDim2.new(1, -16, 1, -72), true)
		pasteBox.Name = "Text"
		pasteBox.PlaceholderText = "Paste source or an error traceback"
		importButton = button(importFrame, "Analyze", 0, 0, 72, function()
			if pasteBox.Text:match("^%s*$") then
				notice = "Paste source or a traceback first"
				updateStatus()
				return
			end
			local ok, problem = pcall(function()
				session:Import(pasteBox.Text)
			end)
			if ok then
				importFrame.Visible = false
				pasteBox:ReleaseFocus()
				layout()
				rebuild()
				notice = "Text analyzed"
			else
				notice = "Could not analyze text: " .. tostring(problem)
			end
			updateStatus()
		end)
		importButton.Position = UDim2.new(1, -80, 1, -32)
		local back = button(importFrame, "Back", 8, 0, 60, function()
			importFrame.Visible = false
			pasteBox:ReleaseFocus()
			layout()
			refresh()
		end)
		back.Position = UDim2.new(0, 8, 1, -32)
		local footer = createSimple("Frame", {
			Name = "Footer",
			Parent = content,
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -22),
			Size = UDim2.new(1, 0, 0, 22),
		})
		status = label(footer, "", UDim2.fromOffset(8, 0), UDim2.new(1, -16, 1, 0))
		status.Name = "Status"
		Lib.StudioTooltip(status, function()
			return app.Status
				or "Paths reconstructed from accessible scripts and logs; this is not direct access to the server's objects."
		end)
		Lib.StudioTooltip(pathLabel, function()
			return pathLabel.Text
		end)
		Lib.StudioTooltip(scanButton, "Scan accessible scripts, or stop the current scan")
		app.GuiElems = {
			Tree = treeFrame,
			Search = searchBox,
			Details = detailsFrame,
			Scan = scanButton,
			More = more,
			Status = status,
			TextImport = importFrame,
		}
		Main.TrackSignal(treeFrame:GetPropertyChangedSignal("CanvasPosition"), refresh)
		Main.TrackSignal(treeFrame:GetPropertyChangedSignal("AbsoluteSize"), refresh)
		local function showLatest()
			updateStatus()
			if displayRevision ~= session.Tree.Revision then
				rebuild()
				if selected then
					showEvidence(session.Tree.Nodes[selected])
				end
			end
		end
		Main.TrackSignal(window.OnActivate, showLatest)
		Main.TrackSignal(window.OnRestore, showLatest)
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			treeFrame.CanvasPosition = Vector2.new(0, 0)
			rebuild()
		end)
		Main.AddCleanup(function()
			window = nil
		end)
		layout()
		updateStatus()
		rebuild()
		window:Show()
	end
	function app.Hide()
		if window then
			window:Hide()
		end
	end
	return app
end
return { InitDeps = InitDeps, Main = CreateModule }
