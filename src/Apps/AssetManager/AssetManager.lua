--!strict

local Main, Apps, Lib, Settings, env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, Lib, Settings, env, service = d.Main, d.Apps, d.Lib, d.Settings, d.env, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local queryIndex = Apps.AssetQuery.Create()
	local Manager = {}
	local window, preview, results, uses, search, status, detail, mediaTime
	local records, filtered = {}, {}
	local selected
	local category = "All"
	local revision = 0
	local filtering = 0
	local downloading = false
	local running = false
	local needsScan = true
	local suspended = false
	local assetList, useList
	local refreshList, choose, clearSelection
	local tabs = {}
	local sortKey = "Name"
	local descending = false
	local grid = false
	local function node(class, props)
		local item = Instance.new(class)
		for key, value in pairs(props) do
			item[key] = value
		end
		return item
	end
	local function report(text)
		if status and Main.Alive ~= false then
			status.Text = tostring(text)
		end
	end
	local function path(object)
		local ok, value = pcall(function()
			return object:GetFullName()
		end)
		return ok and value or "Removed object"
	end
	function Manager.Refresh()
		if not window then
			return
		end
		needsScan = true
		revision += 1
		local token = revision
		running = true
		report("Scanning assets...")
		task.spawn(function()
			local deadline = os.clock() + 0.002
			local nextProgress = os.clock() + 0.25
			local ok, found, stats = pcall(Apps.AssetCatalog.Scan, Apps.Explorer.GetNodes(), function(count, total)
				if token ~= revision or Main.Alive == false then
					return false
				end
				local now = os.clock()
				if now >= nextProgress then
					report(string.format("Scanning assets... %d objects, %d assets", count, total))
					nextProgress = now + 0.25
				end
				if now >= deadline then
					task.wait()
					deadline = os.clock() + 0.002
				end
				return token == revision and Main.Alive ~= false
			end)
			if token ~= revision or Main.Alive == false then
				return
			end
			running = false
			if not ok or not found then
				report("Scan failed: " .. tostring(ok and stats or found))
				return
			end
			records = found
			needsScan = false
			local oldKey = selected and selected.Key
			local replacement
			if oldKey then
				for _, record in ipairs(records) do
					if record.Key == oldKey then
						replacement = record
						break
					end
				end
			end
			if replacement then
				choose(replacement, true)
			elseif selected then
				clearSelection()
			end
			refreshList()
			report(#records .. " assets")
		end)
	end
	local function resume()
		if Main.Alive == false or window.Minimized or not window:IsVisible() then
			return
		end
		if suspended then
			suspended = false
			if selected then
				preview:Show(selected)
			end
			refreshList(true)
		end
		if needsScan and not running then
			Manager.Refresh()
		end
	end
	local function create()
		window = Lib.Window.new()
		Manager.Window = window
		window:SetTitle("Asset Manager")
		window.MinX = 800
		window.MinY = 500
		window:Resize(1040, 620)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		local theme = Settings.Theme
		local content = window.GuiElems.Content
		content.BackgroundColor3 = theme.Menu
		local function label(parent, text, position, size)
			return node("TextLabel", {
				Parent = parent,
				Text = text,
				Position = position,
				Size = size,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = theme.Text,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
		local function button(parent, text, position, size, callback)
			local b = node("TextButton", {
				Parent = parent,
				Text = text,
				Position = position,
				Size = size,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = theme.Text,
				BackgroundColor3 = theme.TextBox,
				BorderSizePixel = 0,
				AutoButtonColor = false,
			})
			node("UICorner", { Parent = b, CornerRadius = UDim.new(0, 3) })
			b.MouseEnter:Connect(function()
				b.BackgroundColor3 = theme.Focus
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundColor3 = theme.TextBox
			end)
			b.Activated:Connect(callback)
			return b
		end
		local function box(parent, hint, position, size)
			local b = node("TextBox", {
				Parent = parent,
				Text = "",
				PlaceholderText = hint,
				Position = position,
				Size = size,
				Font = Lib.StudioFont,
				TextSize = 12,
				TextColor3 = theme.Text,
				PlaceholderColor3 = theme.PlaceholderText,
				ClearTextOnFocus = false,
				MultiLine = false,
				BackgroundColor3 = theme.TextBox,
				BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			node("UIPadding", { Parent = b, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
			return b
		end
		local function scroller(parent, position, size)
			return node("ScrollingFrame", {
				Parent = parent,
				Position = position,
				Size = size,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 5,
				ScrollBarImageColor3 = theme.PlaceholderText,
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			})
		end
		local right
		local assetActions = {}
		local toolbar = node("Frame", {
			Name = "Toolbar",
			Parent = content,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = theme.Main2 or theme.Menu,
			BorderSizePixel = 0,
		})
		local collapsed = false
		local compactSidebar = false
		local applySidebar
		local sidebarToggle = button(toolbar, "", UDim2.fromOffset(8, 6), UDim2.fromOffset(28, 28), function()
			if content.AbsoluteSize.X < 680 and selected then
				clearSelection()
			elseif content.AbsoluteSize.X < 680 then
				compactSidebar = not compactSidebar
				applySidebar()
			else
				collapsed = not collapsed
				applySidebar()
			end
		end)
		sidebarToggle.Name = "ToggleSidebar"
		node("ImageLabel", {
			Parent = sidebarToggle,
			Image = Main.GetStudioAsset("native/asset-manager/Menu") or "",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(16, 16),
		})
		search = box(toolbar, "Search assets", UDim2.fromOffset(44, 6), UDim2.new(1, -204, 0, 28))
		button(toolbar, "Refresh", UDim2.new(1, -152, 0, 6), UDim2.fromOffset(68, 28), Manager.Refresh)
		local view = button(toolbar, "", UDim2.new(1, -76, 0, 6), UDim2.fromOffset(28, 28), function()
			grid = not grid
			assetList:SetGrid(grid)
			refreshList()
		end)
		view.Name = "ViewMode"
		Lib.StudioTooltip(view, "List / Grid")
		node("ImageLabel", {
			Parent = view,
			Image = Main.GetStudioAsset("native/asset-manager/List") or "",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(16, 16),
		})
		view.TextXAlignment = Enum.TextXAlignment.Right
		local sortMenu
		local sort = button(toolbar, "", UDim2.new(1, -40, 0, 6), UDim2.fromOffset(28, 28), function()
			sortMenu = sortMenu or Apps.ContextMenu.new()
			sortMenu:Clear()
			sortMenu.Width = 180
			for _, key in ipairs({ "Name", "ID", "References" }) do
				sortMenu:Add({
					Name = key,
					OnClick = function()
						sortKey = key
						refreshList()
					end,
				})
			end
			sortMenu:Add({
				Name = descending and "Ascending" or "Descending",
				OnClick = function()
					descending = not descending
					refreshList()
				end,
			})
			sortMenu:Show(content.AbsolutePosition.X + content.AbsoluteSize.X - 188, content.AbsolutePosition.Y + 40)
		end)
		node("ImageLabel", {
			Parent = sort,
			Image = Main.GetStudioAsset("native/asset-manager/Sort") or "",
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, -8, 0.5, -8),
			Size = UDim2.fromOffset(16, 16),
		})
		Main.AddCleanup(function()
			if sortMenu then
				sortMenu:Destroy()
			end
		end)
		local sidebar = node("Frame", {
			Name = "Sidebar",
			Parent = content,
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(0, 144, 1, -82),
			BackgroundColor3 = theme.Main2 or theme.Menu,
			BorderSizePixel = 0,
		})
		local folderKeys =
			{ All = "ExperienceFolder", Images = "ImagesFolder", Sounds = "AudioFolder", Meshes = "MeshesFolder" }
		local function paintTabs()
			for name, b in pairs(tabs) do
				b.BackgroundColor3 = name == category and theme.Focus or theme.Main2 or theme.Menu
			end
		end
		for i, kind in ipairs({ "All", "Images", "Sounds", "Meshes", "Animations" }) do
			local b = button(
				sidebar,
				kind == "All" and "All assets" or kind,
				UDim2.fromOffset(6, 8 + (i - 1) * 30),
				UDim2.new(1, -12, 0, 28),
				function()
					category = kind
					compactSidebar = false
					if selected and kind ~= "All" and selected.Kind ~= kind then
						clearSelection()
					end
					applySidebar()
					paintTabs()
					refreshList()
				end
			)
			tabs[kind] = b
			b.TextXAlignment = Enum.TextXAlignment.Left
			node("UIPadding", { Parent = b, PaddingLeft = UDim.new(0, 32) })
			node("ImageLabel", {
				Parent = b,
				Image = Main.GetStudioAsset(
					folderKeys[kind] and "native/asset-manager/" .. folderKeys[kind] or "class/Animation"
				) or "",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(-26, 6),
				Size = UDim2.fromOffset(16, 16),
			})
			b.MouseLeave:Connect(paintTabs)
		end
		paintTabs()
		local browser = node("Frame", {
			Name = "Browser",
			Parent = content,
			Position = UDim2.fromOffset(152, 48),
			Size = UDim2.new(1, -472, 1, -90),
			BackgroundTransparency = 1,
		})
		applySidebar = function()
			local width = content.AbsoluteSize.X
			local compact = width < 680
			sidebar.Visible = compact and compactSidebar or not compact and not collapsed
			local x = sidebar.Visible and 152 or 8
			local inspectorWidth = compact and math.max(280, width - 16) or 300
			browser.Visible = not (compact and selected ~= nil)
			browser.Position = UDim2.fromOffset(x, 48)
			browser.Size = UDim2.new(1, -(x + (selected and not compact and 320 or 8)), 1, -90)
			if right then
				right.Visible = selected ~= nil
				right.Position = UDim2.new(1, -inspectorWidth - 8, 0, 48)
				right.Size = UDim2.new(0, inspectorWidth, 1, -96)
			end
			for _, action in ipairs(assetActions) do
				action.Visible = selected ~= nil
			end
		end
		local heading = node("Frame", {
			Parent = browser,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = theme.Main2 or theme.Menu,
			BorderSizePixel = 0,
		})
		local nameHeading = button(heading, "Name", UDim2.fromOffset(0, 0), UDim2.new(0.57, -3, 1, 0), function()
			if sortKey == "Name" then
				descending = not descending
			end
			sortKey = "Name"
			refreshList()
		end)
		local idHeading = button(
			heading,
			"Asset ID / Uses",
			UDim2.new(0.57, 3, 0, 0),
			UDim2.new(0.43, -3, 1, 0),
			function()
				if sortKey == "ID" then
					descending = not descending
				end
				sortKey = "ID"
				refreshList()
			end
		)
		nameHeading.TextXAlignment = Enum.TextXAlignment.Left
		idHeading.TextXAlignment = Enum.TextXAlignment.Left
		node("UIPadding", { Parent = nameHeading, PaddingLeft = UDim.new(0, 32) })
		results = scroller(browser, UDim2.fromOffset(0, 28), UDim2.new(1, 0, 1, -28))
		results.Name = "Assets"
		local empty = label(browser, "No assets found", UDim2.fromOffset(12, 42), UDim2.new(1, -24, 0, 50))
		empty.TextWrapped = true
		empty.Visible = false
		right = node("Frame", {
			Name = "Inspector",
			Parent = content,
			Position = UDim2.new(1, -308, 0, 48),
			Size = UDim2.new(0, 300, 1, -96),
			BackgroundTransparency = 1,
		})
		detail = label(right, "Select an asset", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 38))
		detail.TextWrapped = true
		local stage = node("Frame", {
			Name = "PreviewStage",
			Parent = right,
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 1, -230),
			BackgroundColor3 = theme.Main2 or theme.TextBox,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		})
		local hint = label(stage, "Select an asset", UDim2.fromOffset(16, 16), UDim2.new(1, -32, 1, -32))
		hint.TextXAlignment = Enum.TextXAlignment.Center
		hint.TextWrapped = true
		local image = node("ImageLabel", {
			Parent = stage,
			Visible = false,
			Image = "",
			ScaleType = Enum.ScaleType.Fit,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		local viewport = node("ViewportFrame", {
			Parent = stage,
			Visible = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Ambient = Color3.fromRGB(180, 180, 180),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-1, -1, -1),
		})
		preview = Apps.AssetPreview.Create(viewport, image, function(text)
			hint.Text = text
			hint.Visible = (not viewport.Visible and not image.Visible)
				or text:find("failed", 1, true) ~= nil
				or text:find("not loaded", 1, true) ~= nil
			if hint.Visible then
				hint.ZIndex = viewport.ZIndex + 1
			end
		end)
		local drag, last
		stage.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				drag = input
				last = input.Position
			end
		end)
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input == drag) then
				local delta = input.Position - last
				last = input.Position
				preview:Orbit(delta.X, delta.Y)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input == drag or input.UserInputType == Enum.UserInputType.MouseButton1 then
				drag = nil
			end
		end)
		stage.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				preview:Zoom(input.Position.Z)
			end
		end)
		local play = button(right, "Play / Pause", UDim2.new(0, 0, 1, -182), UDim2.fromOffset(78, 26), function()
			preview:Toggle()
		end)
		play.Name = "Playback"
		local loop
		loop = button(right, "Loop: On", UDim2.new(0, 84, 1, -182), UDim2.fromOffset(70, 26), function()
			preview:SetLoop(not preview.Looped)
			loop.Text = preview.Looped and "Loop: On" or "Loop: Off"
		end)
		local stopPlayback = button(right, "Stop", UDim2.new(0, 160, 1, -182), UDim2.fromOffset(46, 26), function()
			preview:ResetPlayback()
			report("Stopped")
		end)
		loop.Name = "LoopPlayback"
		stopPlayback.Name = "StopPlayback"
		local rig, rigMenu
		rig = button(right, "Rig: R15", UDim2.new(0, 212, 1, -182), UDim2.fromOffset(88, 26), function()
			rigMenu = rigMenu or Apps.ContextMenu.new()
			rigMenu:Clear()
			rigMenu.Width = 170
			for _, kind in ipairs({ "R15", "R6", "Selection" }) do
				rigMenu:Add({
					Name = kind == "Selection" and "Selected rig" or kind,
					OnClick = function()
						preview.Rig = kind
						rig.Text = kind == "Selection" and "Selected rig" or "Rig: " .. kind
						if selected and selected.Kind == "Animations" then
							preview:Show(selected)
						end
					end,
				})
			end
			rigMenu:Show(rig.AbsolutePosition.X, rig.AbsolutePosition.Y + rig.AbsoluteSize.Y + 2)
		end)
		rig.Name = "RigPicker"
		Main.AddCleanup(function()
			if rigMenu then
				rigMenu:Destroy()
			end
		end)
		local volume = box(right, "Volume %", UDim2.new(0, 0, 1, -150), UDim2.fromOffset(78, 24))
		volume.Text = "50%"
		volume.Name = "Volume"
		volume.FocusLost:Connect(function()
			local text = volume.Text:gsub("%%$", "")
			local value = tonumber(text)
			if value then
				preview:SetVolume(value / 100)
			end
			volume.Text = tostring(math.floor(preview.Volume * 100)) .. "%"
		end)
		local speed = box(right, "Speed", UDim2.new(0, 84, 1, -150), UDim2.fromOffset(60, 24))
		speed.Text = "1x"
		speed.Name = "Speed"
		speed.FocusLost:Connect(function()
			local text = speed.Text:gsub("x$", "")
			local value = tonumber(text)
			if value then
				preview:SetSpeed(value)
			end
			speed.Text = tostring(preview.Speed) .. "x"
		end)
		local seek = box(right, "Seek (s)", UDim2.new(0, 150, 1, -150), UDim2.fromOffset(66, 24))
		seek.Name = "Seek"
		seek.FocusLost:Connect(function(enter)
			if enter then
				local value = tonumber(seek.Text)
				if value then
					pcall(preview.Seek, preview, value)
				end
			end
		end)
		mediaTime = label(right, "", UDim2.new(0, 222, 1, -150), UDim2.new(1, -222, 0, 24))
		local usedBy = label(right, "Objects", UDim2.new(0, 0, 1, -120), UDim2.new(1, 0, 0, 22))
		uses = scroller(right, UDim2.new(0, 0, 1, -94), UDim2.new(1, 0, 0, 94))
		useList = Apps.AssetRows.Create(uses, function(use)
			if selected and Apps.AssetCatalog.IsCurrent(selected, use) and Apps.Explorer.GetNodes()[use.Object] then
				Apps.Explorer.SelectService(use.Object)
				Apps.Explorer.ViewObj(use.Object)
			else
				report("That reference changed. Refresh the asset list.")
			end
		end, function(b, use)
			if not use then
				return
			end
			b.BackgroundTransparency = 1
			b.Caption.Size = UDim2.new(1, -40, 1, 0)
			b.Meta.Text = ""
			b.Caption.Text = path(use.Object) .. " · " .. use.Property
			b.Icon.Image = Main.GetStudioAsset("class/" .. use.Object.ClassName) or ""
		end)
		local function layoutPreview(record)
			local audio = record and record.Kind == "Sounds"
			local animation = record and record.Kind == "Animations"
			local media = audio or animation
			for _, control in ipairs({ play, loop, stopPlayback, speed, seek, mediaTime }) do
				control.Visible = media
			end
			volume.Visible = audio
			rig.Visible = animation
			stage.Visible = record ~= nil and not audio
			stage.Size = UDim2.new(1, 0, 1, animation and -230 or -166)
			local y = audio and UDim.new(0, 54) or UDim.new(1, -182)
			for _, control in ipairs({ play, loop, stopPlayback, rig }) do
				control.Position = UDim2.new(control.Position.X.Scale, control.Position.X.Offset, y.Scale, y.Offset)
			end
			local secondY = audio and UDim.new(0, 88) or UDim.new(1, -150)
			for _, control in ipairs({ volume, speed, seek, mediaTime }) do
				control.Position =
					UDim2.new(control.Position.X.Scale, control.Position.X.Offset, secondY.Scale, secondY.Offset)
			end
			usedBy.Position = audio and UDim2.fromOffset(0, 126) or UDim2.new(0, 0, 1, -120)
			uses.Position = audio and UDim2.fromOffset(0, 152) or UDim2.new(0, 0, 1, -94)
			uses.Size = audio and UDim2.new(1, 0, 1, -152) or UDim2.new(1, 0, 0, 94)
		end
		clearSelection = function()
			selected = nil
			applySidebar()
			preview:Stop()
			layoutPreview(nil)
			useList:Set({})
			detail.Text = "Select an asset"
			assetList.Paint()
		end
		layoutPreview(nil)
		choose = function(record, preservePreview)
			selected = record
			applySidebar()
			layoutPreview(record)
			detail.Text = record.Name .. "\n" .. (record.Id or record.URI)
			if not preservePreview then
				hint.Visible = true
				hint.Text = "Loading..."
				uses.CanvasPosition = Vector2.new(0, 0)
			end
			useList:Set(record.Uses)
			if not preservePreview then
				preview:Show(record)
			end
			assetList.Paint()
		end
		assetList = Apps.AssetRows.Create(results, choose, function(b, record, isGrid)
			if not record then
				return
			end
			b.BackgroundColor3 = theme.Focus
			b.BackgroundTransparency = selected == record and 0.2 or 1
			b.Caption.Text = record.Name
			b.Meta.Text = (record.Id or record.URI) .. "  ·  " .. #record.Uses
			if isGrid and record.Kind == "Images" then
				b.Icon.Image = record.URI
			elseif isGrid and record.Id and record.Kind ~= "Sounds" then
				b.Icon.Image = "rbxthumb://type=Asset&id=" .. record.Id .. "&w=150&h=150"
			else
				b.Icon.Image = Main.GetStudioAsset(
					"class/"
						.. ({ Images = "Decal", Sounds = "Sound", Meshes = "MeshPart", Animations = "Animation" })[record.Kind]
				) or ""
			end
		end)
		refreshList = function(preserveScroll)
			filtering += 1
			local token = filtering
			local query = search.Text:lower()
			task.spawn(function()
				local deadline = os.clock() + 0.002
				local nextItems = queryIndex.Filter(records, category, query, sortKey, descending, function()
					if token ~= filtering or Main.Alive == false then
						return false
					end
					if os.clock() >= deadline then
						task.wait()
						deadline = os.clock() + 0.002
					end
					return token == filtering and Main.Alive ~= false
				end)
				if not nextItems or token ~= filtering or Main.Alive == false then
					return
				end
				filtered = nextItems
				empty.Visible = #filtered == 0
				empty.Text = #records == 0 and "No assets found. Refresh to try again." or "No matching assets"
				if not preserveScroll then
					results.CanvasPosition = Vector2.new(0, 0)
				end
				assetList:Set(filtered)
			end)
		end
		search:GetPropertyChangedSignal("Text"):Connect(refreshList)
		assetActions[1] = button(content, "Copy ID", UDim2.new(1, -270, 1, -36), UDim2.fromOffset(76, 26), function()
			if selected and env.setclipboard then
				env.setclipboard(selected.Id or selected.URI)
				report("Copied.")
			end
		end)
		assetActions[2] = button(content, "Copy link", UDim2.new(1, -188, 1, -36), UDim2.fromOffset(78, 26), function()
			if selected and env.setclipboard then
				env.setclipboard(selected.Id and "https://www.roblox.com/library/" .. selected.Id or selected.URI)
				report("Link copied.")
			end
		end)
		local download
		download = button(content, "Download", UDim2.new(1, -104, 1, -36), UDim2.fromOffset(78, 26), function()
			if downloading or not selected then
				return
			end
			local record = selected
			downloading = true
			download.Text = "Saving..."
			report("Downloading " .. (record.Id or record.URI) .. "...")
			task.spawn(function()
				local ok, result = pcall(Apps.AssetDownload.Save, record)
				downloading = false
				if Main.Alive ~= false then
					download.Text = "Download"
					report(ok and "Saved: " .. result or tostring(result))
				end
			end)
		end)
		Main.TrackSignal(content:GetPropertyChangedSignal("AbsoluteSize"), applySidebar)
		content.ClipsDescendants = true
		browser.ClipsDescendants = true
		right.ClipsDescendants = true
		assetActions[3] = download
		applySidebar()
		status = label(content, "Ready", UDim2.new(0, 10, 1, -36), UDim2.new(1, -288, 0, 28))
		Lib.StudioTooltip(status, function()
			return status.Text
		end)
		Lib.StudioTooltip(volume, "Volume (%)")
		Lib.StudioTooltip(speed, "Playback speed")
		Lib.StudioTooltip(seek, "Seek to time (seconds)")
		local elapsed = 0
		Main.TrackSignal(service.RunService.Heartbeat, function(dt)
			if window.Closed or window.Minimized then
				return
			end
			elapsed += dt
			if elapsed < 0.2 then
				return
			end
			elapsed = 0
			if not selected or (selected.Kind ~= "Sounds" and selected.Kind ~= "Animations") then
				return
			end
			local pos, length = preview:Time()
			mediaTime.Text = length > 0 and string.format("%.1f / %.1f s", pos, length) or "—"
		end)
		local function stop()
			if suspended then
				return
			end
			suspended = true
			revision += 1
			filtering += 1
			running = false
			drag = nil
			preview:Stop()
			if rigMenu then
				rigMenu:Hide()
			end
		end
		Main.TrackSignal(window.OnDeactivate, function()
			if window.Closed or not window:IsVisible() then
				stop()
			end
		end)
		Main.TrackSignal(window.OnMinimize, stop)
		Main.TrackSignal(window.OnRestore, resume)
		Main.TrackSignal(window.OnActivate, function()
			if suspended then
				resume()
			end
		end)
		Main.AddCleanup(stop)
	end
	function Manager.Open()
		if not window then
			create()
		end
		window:Show()
		resume()
	end
	function Manager.Hide()
		if window then
			window:Close()
		end
	end
	return Manager
end
return { InitDeps = InitDeps, Main = CreateModule }
