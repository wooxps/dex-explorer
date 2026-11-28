--!strict

local Apps, Main, Lib, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Lib, Settings, service = d.Apps, d.Main, d.Lib, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Tabs = {}
	function Tabs.Create(host, window, callbacks)
		local skin = Apps.StudioEditorSkin
		local hit = Apps.EditorHitTest
		local function node(class, props)
			local obj = Instance.new(class)
			for k, v in pairs(props) do
				obj[k] = v
			end
			return obj
		end
		local scroll = node("ScrollingFrame", {
			Name = "DocumentTabs",
			Parent = host,
			Active = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -58, 1, 0),
			CanvasSize = UDim2.fromOffset(0, skin.TabHeight),
			CanvasPosition = Vector2.new(0, 0),
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			ClipsDescendants = true,
		})
		local self = { Gui = scroll, Entries = {}, Documents = {}, TotalWidth = 0 }
		local adjusting = false
		local tabMenu, menuDocument
		local metrics = { Padding = 12, AccessoryGap = 4, Icon = 16, Close = 22, Modified = 6, Min = 96, Max = 240 }
		local textCache = {}
		local cacheCount = 0
		local middlePressed
		local drag
		local suppressClick
		local function textWidth(text, label)
			local key = tostring(label.Font) .. ":" .. label.TextSize .. ":" .. text
			if textCache[key] then
				return textCache[key]
			end
			local ok, size = pcall(function()
				return service.TextService:GetTextSize(
					text,
					label.TextSize,
					label.Font,
					Vector2.new(100000, skin.TabHeight)
				)
			end)
			if not ok then
				return nil
			end
			local width = math.ceil(size.X)
			if cacheCount == 256 then
				table.clear(textCache)
				cacheCount = 0
			end
			textCache[key] = width
			cacheCount += 1
			return width
		end
		local function layout(entry, doc)
			local measured = textWidth(doc.title, entry.Label)
			local iconWidth = entry.Icon.Image ~= "" and metrics.Icon or 0
			local overhead = metrics.Padding
				+ metrics.Close
				+ metrics.AccessoryGap
				+ metrics.Modified
				+ metrics.AccessoryGap
			if iconWidth > 0 then
				overhead += iconWidth + metrics.AccessoryGap
			end
			local width = measured and math.clamp(measured + overhead, metrics.Min, metrics.Max)
				or entry.Width
				or metrics.Min
			local left = metrics.Padding / 2
			entry.Icon.Visible = iconWidth > 0
			entry.Icon.Position = UDim2.new(0, left, 0.5, -8)
			if iconWidth > 0 then
				left += iconWidth + metrics.AccessoryGap
			end
			local right = width
				- metrics.Padding / 2
				- metrics.Close
				- metrics.AccessoryGap
				- metrics.Modified
				- metrics.AccessoryGap
			entry.Label.Position = UDim2.fromOffset(left, 0)
			entry.Label.Size = UDim2.new(0, math.max(0, right - left), 1, 0)
			entry.TextBounds = { Left = left, Right = right, Width = math.max(0, right - left), Measured = measured }
			entry.Dirty.Position = UDim2.new(0, right + metrics.AccessoryGap, 0.5, -metrics.Modified / 2)
			entry.Width = width
			entry.Title = doc.title
			entry.Label.Text = doc.title
		end
		local function clampScroll()
			if adjusting then
				return
			end
			local x = math.clamp(
				math.round(scroll.CanvasPosition.X),
				0,
				math.max(0, self.TotalWidth - math.floor(scroll.AbsoluteSize.X))
			)
			if x ~= scroll.CanvasPosition.X or scroll.CanvasPosition.Y ~= 0 then
				adjusting = true
				scroll.CanvasPosition = Vector2.new(x, 0)
				adjusting = false
			end
		end
		function self:EnsureActive()
			local entry = self.Entries[self.Active]
			if not entry then
				clampScroll()
				return
			end
			local x = scroll.CanvasPosition.X
			local width = math.floor(scroll.AbsoluteSize.X)
			if entry.Width >= width or entry.Left < x then
				x = entry.Left
			elseif entry.Left + entry.Width > x + width then
				x = entry.Left + entry.Width - width
			end
			if scroll.CanvasPosition.X ~= x or scroll.CanvasPosition.Y ~= 0 then
				scroll.CanvasPosition = Vector2.new(math.max(0, x), 0)
			end
			clampScroll()
		end
		local function make(doc)
			local root =
				node("Frame", { Name = "DocumentTab", Parent = scroll, BorderSizePixel = 0, ClipsDescendants = true })
			local select = node("TextButton", {
				Name = "Select",
				Parent = root,
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -22, 1, 0),
			})
			local icon = node("ImageLabel", {
				Name = "ScriptIcon",
				Parent = select,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 6, 0.5, -8),
				Size = UDim2.fromOffset(16, 16),
				ScaleType = Enum.ScaleType.Fit,
			})
			local label = node("TextLabel", {
				Name = "Title",
				Parent = select,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(27, 0),
				Size = UDim2.new(1, -38, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextScaled = false,
				TextWrapped = false,
			})
			Lib.StudioText(label)
			local dirty = node("Frame", {
				Name = "Modified",
				Parent = root,
				BorderSizePixel = 0,
				BackgroundColor3 = skin.Text,
				Size = UDim2.fromOffset(metrics.Modified, metrics.Modified),
				Visible = false,
			})
			node("UICorner", { Parent = dirty, CornerRadius = UDim.new(0.5, 0) })
			local close = node("TextButton", {
				Name = "Close",
				Parent = root,
				Text = "×",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -22, 0, 0),
				Size = UDim2.new(0, 22, 1, 0),
			})
			Lib.StudioText(close)
			Lib.SetNativeIcon(close, "nav/close", 14)
			node("Frame", {
				Name = "Divider",
				Parent = root,
				BorderSizePixel = 0,
				BackgroundColor3 = skin.Border,
				Position = UDim2.new(1, -1, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
			})
			select.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then suppressClick = nil end
			end)
			select.MouseButton1Click:Connect(function()
				if suppressClick == doc then
					suppressClick = nil
					return
				end
				if self.Active ~= doc then
					callbacks.Select(doc)
				end
			end)
			close.MouseButton1Click:Connect(function()
				callbacks.Close(doc)
			end)
			select.MouseEnter:Connect(function()
				if self.Active ~= doc then
					root.BackgroundColor3 = Settings.Theme.ButtonHover
				end
			end)
			select.MouseLeave:Connect(function()
				root.BackgroundColor3 = self.Active == doc and skin.Chrome or skin.Inactive
			end)
			close.MouseEnter:Connect(function()
				close.BackgroundTransparency = 0
				close.BackgroundColor3 = Settings.Theme.ButtonHover
			end)
			close.MouseLeave:Connect(function()
				close.BackgroundTransparency = 1
			end)
			Lib.StudioTooltip(select, function()
				return doc.title
			end)
			return { Root = root, Select = select, Label = label, Icon = icon, Close = close, Dirty = dirty }
		end
		function self:Update(documents, active)
			local previous = self.Active
			self.Active = active
			self.Documents = documents
			local present = {}
			local offset = 0
			for _, doc in ipairs(documents) do
				present[doc] = true
				local entry = self.Entries[doc]
				if not entry then
					entry = make(doc)
					self.Entries[doc] = entry
				end
				local image = (
					Main.GetStudioAsset
					and Main.GetStudioAsset("class/" .. (doc.script and doc.script.ClassName or "LocalScript"))
				) or ""
				local changed = entry.Title ~= doc.title
					or entry.Icon.Image ~= image
					or entry.MeasuredFont ~= entry.Label.Font
					or entry.MeasuredSize ~= entry.Label.TextSize
				entry.Icon.Image = image
				if changed then
					layout(entry, doc)
					entry.MeasuredFont = entry.Label.Font
					entry.MeasuredSize = entry.Label.TextSize
				end
				if entry.Left ~= offset then
					entry.Left = offset
					entry.Root.Position = UDim2.fromOffset(offset, 0)
				end
				if changed then
					entry.Root.Size = UDim2.fromOffset(entry.Width, skin.TabHeight)
				end
				if changed or previous ~= active and (previous == doc or active == doc) then
					entry.Root.BackgroundColor3 = if active == doc then skin.Chrome else skin.Inactive
				end
				local dirty = doc.dirty == true
				if entry.Dirty.Visible ~= dirty then
					entry.Dirty.Visible = dirty
				end
				offset += entry.Width
			end
			for doc, entry in pairs(self.Entries) do
				if not present[doc] then
					entry.Root:Destroy()
					self.Entries[doc] = nil
				end
			end
			if menuDocument and not present[menuDocument] then
				self:HideMenu()
			end
			if self.TotalWidth ~= offset then
				self.TotalWidth = offset
				scroll.CanvasSize = UDim2.fromOffset(offset, skin.TabHeight)
			end
			if previous ~= active then
				self:EnsureActive()
			else
				clampScroll()
			end
		end
		function self:ShowMenu(doc, x, y, touch)
			local menu = tabMenu or Apps.ContextMenu.new()
			tabMenu = menu
			menuDocument = doc
			self.ContextMenu = menu
			menu:Clear()
			menu.Iconless = true
			menu.Width = 256
			menu:ApplyTheme({ RowHeight = 22, CornerRadius = 0 })
			if touch and #self.Documents > 1 then
				for _, step in {-1, 1} do
					local index = table.find(self.Documents, doc)
					menu:Add({
						Text = if step < 0 then "Move Tab Left" else "Move Tab Right",
						Disabled = not index or not self.Documents[index + step],
						OnClick = function()
							local from = table.find(self.Documents, doc)
							if not from or not self.Documents[from + step] then return end
							table.remove(self.Documents, from)
							table.insert(self.Documents, from + step, doc)
							self:Update(self.Documents, self.Active)
							if callbacks.Reorder then callbacks.Reorder(doc, from, from + step) end
						end,
					})
				end
				menu:AddDivider()
			end
			menu:Add({
				Text = "Close",
				Shortcut = "Ctrl+W",
				OnClick = function()
					callbacks.Close(doc)
				end,
			})
			menu:Add({
				Text = "Close Other Tabs",
				Disabled = #self.Documents < 2,
				OnClick = function()
					for _, other in ipairs(table.clone(self.Documents)) do
						if other ~= doc then
							callbacks.Close(other)
						end
					end
				end,
			})
			menu:Add({
				Text = "Close Tabs to the Right",
				Disabled = self.Documents[#self.Documents] == doc,
				OnClick = function()
					local index = table.find(self.Documents, doc)
					if index then
						for i = #self.Documents, index + 1, -1 do
							callbacks.Close(self.Documents[i])
						end
					end
				end,
			})
			menu:Add({
				Text = "Close All Tabs",
				OnClick = function()
					for _, other in ipairs(table.clone(self.Documents)) do
						callbacks.Close(other)
					end
				end,
			})
			menu:Show(x, y)
		end
		function self:HideMenu()
			menuDocument = nil
			if tabMenu then
				tabMenu:Hide()
			end
		end
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(clampScroll)
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:EnsureActive()
		end)
		local function pointed(input)
			local px, py = hit.Pointer(input)
			if not px or not hit.OwnsPoint(window, scroll, px, py) then
				return nil, px, py
			end
			local x = px - scroll.AbsolutePosition.X + scroll.CanvasPosition.X
			local low, high = 1, #self.Documents
			while low <= high do
				local middle = (low + high) // 2
				local doc = self.Documents[middle]
				local entry = self.Entries[doc]
				if x < entry.Left then
					high = middle - 1
				elseif x >= entry.Left + entry.Width then
					low = middle + 1
				else
					return doc, px, py
				end
			end
			return nil, px, py
		end
		Main.TrackSignal(service.UserInputService.TouchLongPress, function(points, state)
			if state ~= Enum.UserInputState.Begin or #points ~= 1 then return end
			local point = points[1]
			local doc, x, y = pointed({UserInputType = Enum.UserInputType.Touch, Position = point})
			if doc then
				suppressClick = doc
				self:ShowMenu(doc, x, y, true)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			local button = input.UserInputType
			if
				button ~= Enum.UserInputType.MouseButton1
				and button ~= Enum.UserInputType.MouseButton2
				and button ~= Enum.UserInputType.MouseButton3
			then
				return
			end
			local doc, px, py = pointed(input)
			if button == Enum.UserInputType.MouseButton3 then
				middlePressed = doc
				return
			end
			if not doc then
				return
			end
			if button == Enum.UserInputType.MouseButton2 then
				self:ShowMenu(doc, px, py)
				return
			end
			local entry = self.Entries[doc]
			local localX = px - scroll.AbsolutePosition.X + scroll.CanvasPosition.X - entry.Left
			if localX < entry.Width - metrics.Close then
				suppressClick = nil
				drag = { Doc = doc, X = px, Y = py, Moving = false }
			end
		end)
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local target, px, py = pointed(input)
			if not px then
				return
			end
			local distance = callbacks.DragDistance or 10
			if not drag.Moving and math.abs(px - drag.X) + math.abs(py - drag.Y) < distance then
				return
			end
			drag.Moving = true
			suppressClick = drag.Doc
			if not target or target == drag.Doc then
				return
			end
			local from, to = table.find(self.Documents, drag.Doc), table.find(self.Documents, target)
			if not from or not to then
				return
			end
			local targetEntry = self.Entries[target]
			local canvasX = px - scroll.AbsolutePosition.X + scroll.CanvasPosition.X
			if
				(to > from and canvasX < targetEntry.Left + targetEntry.Width / 2)
				or (to < from and canvasX > targetEntry.Left + targetEntry.Width / 2)
			then
				return
			end
			table.remove(self.Documents, from)
			table.insert(self.Documents, to, drag.Doc)
			self:Update(self.Documents, self.Active)
			if callbacks.Reorder then
				callbacks.Reorder(drag.Doc, from, to)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton3 then
				local doc = pointed(input)
				local pressed = middlePressed
				middlePressed = nil
				if pressed and pressed == doc and self.Entries[pressed] then
					task.defer(function()
						if self.Entries[pressed] then
							callbacks.Close(pressed)
						end
					end)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				drag = nil
			end
		end)
		local function cancelPointer()
			middlePressed = nil
			drag = nil
			suppressClick = nil
			self:HideMenu()
		end

		Main.TrackSignal(window.OnDeactivate, cancelPointer)
		Main.TrackSignal(window.OnMinimize, cancelPointer)
		if service.UserInputService.WindowFocusReleased then
			Main.TrackSignal(service.UserInputService.WindowFocusReleased, cancelPointer)
		end
		Main.AddCleanup(function()
			if tabMenu then
				tabMenu:Destroy()
			end
		end)
		return self
	end
	return Tabs
end
return { InitDeps = InitDeps, Main = CreateModule }
