--!strict

local Main, Lib, Apps, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, service = d.Main, d.Lib, d.Apps, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Menu = { VisibilityChanged = Lib.Signal.new() }
	local serial = 0
	local activeMenus = setmetatable({}, { __mode = "k" })
	function Menu.IsAnyShown()
		return next(activeMenus) ~= nil
	end
	local function stateChanged()
		Menu.VisibilityChanged:Fire()
		if Main.Alive and Apps.Explorer and Apps.Explorer.PerformRefresh then
			Apps.Explorer.PerformRefresh()
		end
	end
	function Menu.new()
		serial += 1
		local key = "ContextMenu" .. serial
		local React = Apps.React.React
		local e = React.createElement
		local renderer = assert(Apps.Explorer.TreeRenderer)
		local self = {
			Items = {},
			Added = {},
			Registered = {},
			GuiElems = {},
			Theme = {
				RowHeight = 22,
				CornerRadius = 0,
				TextSize = 12,
				ContentColor = Color3.fromRGB(25, 26, 31),
				HighlightColor = Color3.fromRGB(53, 55, 65),
				OutlineColor = Color3.fromRGB(43, 45, 54),
				DividerColor = Color3.fromRGB(32, 34, 39),
				TextColor = Color3.fromRGB(214, 216, 225),
			},
			Width = 248,
			MaxHeight = 400,
			SearchEnabled = false,
			ClearSearchOnShow = true,
			FocusSearchOnShow = true,
			Selected = 0,
		}
		local gui = Instance.new("ScreenGui")
		gui.Name = key
		gui.DisplayOrder = Main.DisplayOrders.Menu
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		self.Gui = gui
		local mainRef, listRef, searchRef = React.createRef(), React.createRef(), React.createRef()
		local fadeRef = React.createRef()
		local shadowOpacity = { 0.40, 0.29, 0.16, 0.04 }
		local filtered, offsets, heights = {}, {}, {}
		local contentHeight = 0
		local tooltipItems = setmetatable({}, { __mode = "k" })
		local height = 40
		local position = UDim2.fromOffset(0, 0)
		local render
		local openingFade
		local fadeTicket = 0
		function self:OpenSubmenu(item)
			if item and self.ChildMenu == item.ChildMenu and self.ChildMenu and self.ChildMenu.Shown then
				return
			end
			if self.ChildMenu then
				self.ChildMenu:Hide()
			end
			if not item or not item.Submenu then
				self.ChildMenu = nil
				return
			end
			local child = item.ChildMenu
			if not child then
				child = Menu.new()
				item.ChildMenu = child
			end
			child:Clear()
			child.ParentMenu = self
			child.Iconless = self.Iconless
			child.Width = item.Width or self.Width
			child.PreferredWidth = item.Width
			child:ApplyTheme(self.Theme)
			for _, entry in ipairs(item.Submenu) do
				local leaf = table.clone(entry)
				local callback = leaf.OnClick
				leaf.OnClick = function(...)
					if callback then
						callback(...)
					end
					self:Hide()
				end
				child:Add(leaf)
			end
			local index = table.find(filtered, item) or 1
			local origin = self.GuiElems.List.AbsolutePosition
			local x = self.GuiElems.Main.AbsolutePosition.X + self.Width - (self.Theme.Compact and 0 or 2)
			if x + child.Width > Main.Mouse.ViewSizeX then
				x = self.GuiElems.Main.AbsolutePosition.X - child.Width + (self.Theme.Compact and 0 or 2)
			end
			child:Show(
				x,
				origin.Y
					+ (offsets[index] or 0)
					- (self.GuiElems.List.CanvasPosition.Y or 0)
					- (self.Theme.Compact and 1 or 0)
			)
			self.ChildMenu = child
		end
		local function compactVisible(item)
			if item.Disabled then
				return false
			end
			if not item.Submenu then
				return true
			end
			for _, child in ipairs(item.Submenu) do
				if not child.Divider and compactVisible(child) then
					return true
				end
			end
			return false
		end
		local function rebuild()
			local query = self.GuiElems.SearchBar and self.GuiElems.SearchBar.Text:lower() or ""
			filtered = {}
			local separator
			for _, item in ipairs(self.Items) do
				if self.Theme.Compact and query == "" then
					if item.Divider then
						if #filtered > 0 then
							separator = item
						end
					elseif compactVisible(item) then
						if separator then
							filtered[#filtered + 1] = separator
							separator = nil
						end
						filtered[#filtered + 1] = item
					end
				elseif query == "" or (not item.Divider and item.Name:lower():find(query, 1, true)) then
					filtered[#filtered + 1] = item
				end
			end
			if query ~= "" then
				table.sort(filtered, function(a, b)
					return a.Name < b.Name
				end)
			end
			contentHeight = 0
			offsets = {}
			heights = {}
			for index, item in ipairs(filtered) do
				offsets[index] = contentHeight
				heights[index] = item.Divider and (item.Text and 20 or (self.Theme.Compact and 8 or 7))
					or self.Theme.RowHeight
					or 28
				contentHeight += heights[index]
			end
			self.ContentHeight = contentHeight
		end
		local function activate(item, right)
			if item.Disabled or item.Divider then
				return
			end
			if item.Submenu then
				self:OpenSubmenu(item)
				return
			end
			local callback = right and item.OnRightClick or item.OnClick
			if callback then
				callback(item.Name)
				if not item.NoHide then
					self:Hide()
				end
			end
		end
		render = function()
			local children = {}
			local offset = self.GuiElems.List
					and self.GuiElems.List.CanvasPosition
					and self.GuiElems.List.CanvasPosition.Y
				or 0
			local first, last = 1, #filtered
			while first < last do
				local middle = math.floor((first + last) / 2)
				if offsets[middle] + heights[middle] <= offset then
					first = middle + 1
				else
					last = middle
				end
			end
			local bottom = offset
				+ height
				- (self.SearchEnabled and 39 or (self.Theme.Compact and 2 or 6))
				+ (self.Theme.RowHeight or 28)
			self.MountedRows = 0
			if #filtered == 0 then
				children.Empty = e("TextLabel", {
					BackgroundTransparency = 1,
					Text = "No results found",
					Font = Enum.Font.BuilderSans,
					TextSize = 14,
					TextColor3 = Settings.Theme.PlaceholderText,
					Size = UDim2.new(1, 0, 0, 28),
				})
			end
			for index = first, #filtered do
				if offsets[index] >= bottom then
					break
				end
				local slot = index - first + 1
				local item = filtered[index]
				if item then
					self.MountedRows += 1
					local label = item.Divider and (item.Text or "") or item.Name
					children["Item" .. slot] = e("TextButton", {
						Name = item.Divider and "Divider" or "Item" .. slot,
						AutoButtonColor = false,
						Text = "",
						BorderSizePixel = 0,
						ref = function(button)
							if not button then
								return
							end
							if tooltipItems[button] == nil then
								Lib.StudioTooltip(button, function()
									local current = tooltipItems[button]
									return self.Shown and current and current.Description or nil
								end)
							end
							tooltipItems[button] = item
						end,
						BackgroundColor3 = self.Theme.HighlightColor or Settings.Theme.ButtonHover,
						BackgroundTransparency = not item.Divider
								and not item.Disabled
								and self.Selected == index
								and 0
							or 1,
						Position = UDim2.fromOffset(0, offsets[index]),
						Size = UDim2.new(1, 0, 0, heights[index]),
						[React.Event.MouseEnter] = function(button)
							if item.Divider or item.Disabled then
								return
							end
							if self.HoveredButton and self.HoveredButton ~= button then
								self.HoveredButton.BackgroundTransparency = 1
							end
							self.HoveredButton = button
							self.Selected = index
							if item.Submenu then
								self:OpenSubmenu(item)
							elseif self.ChildMenu then
								self.ChildMenu:Hide()
								self.ChildMenu = nil
							end
							if not item.Disabled and not item.Divider then
								button.BackgroundTransparency = 0
							end
							if item.OnHover then
								item.OnHover(item.Name)
							end
						end,
						[React.Event.MouseLeave] = function(button)
							button.BackgroundTransparency = self.ChildMenu
									and self.ChildMenu.Shown
									and self.Selected == index
									and 0
								or 1
						end,
						[React.Event.Activated] = function()
							activate(item, false)
						end,
						[React.Event.MouseButton2Click] = function()
							activate(item, true)
						end,
					}, {
						Line = e("Frame", {
							Name = "Line",
							Visible = item.Divider and true or false,
							BorderSizePixel = 0,
							BackgroundColor3 = self.Theme.DividerColor or Settings.Theme.Outline2,
							Position = UDim2.new(
								0,
								item.Text and (#item.Text * 7 + 16) or (self.Theme.Compact and 28 or 7),
								0.5,
								0
							),
							Size = UDim2.new(
								1,
								-(item.Text and (#item.Text * 7 + 23) or (self.Theme.Compact and 30 or 14)),
								0,
								1
							),
						}),
						Icon = e("ImageLabel", {
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(
								self.Theme.IconInset or 6,
								math.floor(((heights[index] or 28) - 16) / 2)
							),
							Size = UDim2.fromOffset(16, 16),
							Visible = not item.Divider and not self.Iconless and not item.Checked,
							Image = type(item.Icon) == "string" and item.Icon or "",
							ref = function(icon)
								if not icon or not item.IconMap or item.Divider then
									return
								end
								local image = item.Disabled and item.DisabledIcon or item.Icon
								local paint = type(image) == "number" and item.IconMap.Display
									or item.IconMap.DisplayByKey
								if type(paint) == "function" then
									pcall(paint, item.IconMap, icon, image)
								end
							end,
						}),
						Checkmark = not item.Divider and item.Checked and e("TextLabel", {
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(self.Theme.IconInset or 4, 0),
							Size = UDim2.new(0, 16, 1, 0),
							Font = Enum.Font.BuilderSans,
							TextSize = 12,
							Text = "✓",
							TextColor3 = item.Disabled and Settings.Theme.PlaceholderText
								or (self.Theme.TextColor or Settings.Theme.Text),
						}),
						EntryName = e("TextLabel", {
							BackgroundTransparency = 1,
							Font = self.Theme.Font or Enum.Font.BuilderSans,
							TextSize = item.Divider and 12 or self.Theme.TextSize or 14,
							Text = label,
							TextColor3 = (item.Disabled or item.Divider) and Settings.Theme.PlaceholderText
								or (self.Theme.TextColor or Settings.Theme.Text),
							TextXAlignment = Enum.TextXAlignment.Left,
							TextTruncate = Enum.TextTruncate.AtEnd,
							Position = UDim2.fromOffset(
								self.Theme.TextInset or ((self.Iconless or item.Divider) and 10 or 30),
								0
							),
							Size = UDim2.new(
								1,
								-(
										not self.Theme.Compact and item.Shortcut and item.Shortcut ~= "" and 110
										or (self.Theme.Compact and 43 or 36)
									),
								1,
								0
							),
						}),
						SubmenuArrow = e("ImageLabel", {
							Name = "SubmenuArrow",
							BackgroundTransparency = 1,
							Visible = item.Submenu ~= nil and self.Theme.SubmenuImage ~= nil,
							Image = self.Theme.SubmenuImage or "",
							Position = self.Theme.Compact and UDim2.new(1, -18, 0.5, -6) or UDim2.new(1, -22, 0.5, -8),
							Size = self.Theme.Compact and UDim2.fromOffset(12, 12) or UDim2.fromOffset(16, 16),
							ImageTransparency = item.Disabled and 0.55 or 0,
						}),
						Shortcut = e("TextLabel", {
							BackgroundTransparency = 1,
							Font = self.Theme.Font or Enum.Font.BuilderSans,
							TextSize = self.Theme.TextSize or 14,
							Text = item.Submenu and (self.Theme.SubmenuImage and "" or self.Theme.SubmenuGlyph or ">")
								or (not self.Theme.Compact and item.Shortcut)
								or "",
							TextColor3 = (item.Disabled and Settings.Theme.PlaceholderText)
								or self.Theme.ShortcutColor
								or Settings.Theme.PlaceholderText,
							TextXAlignment = not item.Submenu
									and self.Theme.ShortcutColumnWidth
									and Enum.TextXAlignment.Left
								or Enum.TextXAlignment.Right,
							Position = UDim2.fromOffset(
								not item.Submenu
										and self.Theme.ShortcutColumnWidth
										and (self.Width - 6 - self.Theme.ShortcutColumnWidth)
									or 0,
								0
							),
							Size = not item.Submenu
									and self.Theme.ShortcutColumnWidth
									and UDim2.new(0, self.Theme.ShortcutColumnWidth - 10, 1, 0)
								or UDim2.new(1, -10, 1, 0),
						}),
					})
				end
			end
			local panel = e("Frame", {
				Name = "Main",
				ref = mainRef,
				BorderSizePixel = 0,
				BackgroundColor3 = self.Theme.ContentColor or Settings.Theme.Menu,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromOffset(self.Width, height),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, self.Theme.CornerRadius or 6) }),
				TopEdge = e("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = self.Theme.OutlineColor or Settings.Theme.Outline2,
					Size = UDim2.new(1, 0, 0, 1),
					ZIndex = 3,
				}),
				BottomEdge = e("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = self.Theme.OutlineColor or Settings.Theme.Outline2,
					Position = UDim2.new(0, 0, 1, -1),
					Size = UDim2.new(1, 0, 0, 1),
					ZIndex = 3,
				}),
				LeftEdge = e("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = self.Theme.OutlineColor or Settings.Theme.Outline2,
					Size = UDim2.new(0, 1, 1, 0),
					ZIndex = 3,
				}),
				RightEdge = e("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = self.Theme.OutlineColor or Settings.Theme.Outline2,
					Position = UDim2.new(1, -1, 0, 0),
					Size = UDim2.new(0, 1, 1, 0),
					ZIndex = 3,
				}),
				SearchFrame = e("Frame", {
					BackgroundTransparency = 1,
					Visible = self.SearchEnabled,
					Position = UDim2.fromOffset(5, 5),
					Size = UDim2.new(1, -10, 0, 26),
				}, {
					SearchBox = e("TextBox", {
						ref = searchRef,
						ClearTextOnFocus = false,
						Text = "",
						PlaceholderText = "Search objects",
						Font = Enum.Font.BuilderSans,
						TextSize = 14,
						TextColor3 = Settings.Theme.Text,
						PlaceholderColor3 = Settings.Theme.PlaceholderText,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundColor3 = Settings.Theme.TextBox,
						BorderSizePixel = 0,
						Size = UDim2.fromScale(1, 1),
					}),
				}),
				List = e("ScrollingFrame", {
					ref = listRef,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(
						self.Theme.Compact and 1 or 3,
						self.SearchEnabled and 36 or (self.Theme.Compact and 1 or 3)
					),
					Size = UDim2.new(
						1,
						self.Theme.Compact and -2 or -6,
						1,
						-(self.SearchEnabled and 39 or (self.Theme.Compact and 2 or 6))
					),
					CanvasSize = UDim2.fromOffset(0, contentHeight),
					ScrollBarThickness = 6,
					ScrollBarImageColor3 = Settings.Theme.PlaceholderText,
				}, children),
			})
			do
				local layers = { Panel = panel }
				for i, opacity in ipairs(shadowOpacity) do
					local color = Color3.new(0, 0, 0)
					layers["Right" .. i] = e("Frame", {
						BackgroundColor3 = color,
						BackgroundTransparency = 1 - opacity,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(self.Width + i - 1, 2 + i - 1),
						Size = UDim2.fromOffset(1, height - 1),
						Active = false,
					})
					layers["Bottom" .. i] = e("Frame", {
						BackgroundColor3 = color,
						BackgroundTransparency = 1 - opacity,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(2 + i - 1, height + i - 1),
						Size = UDim2.fromOffset(self.Width - 2, 1),
						Active = false,
					})
				end
				panel = e("CanvasGroup", {
					Name = "Popup",
					ref = fadeRef,
					GroupTransparency = 1,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Active = false,
					Position = position,
					Size = UDim2.fromOffset(self.Width + 4, height + 4),
				}, layers)
			end
			renderer:Portal(key, panel, gui)
			self.GuiElems.Main, self.GuiElems.List, self.GuiElems.SearchBar =
				mainRef.current, listRef.current, searchRef.current
		end
		function self:ApplyTheme(theme)
			for name, value in pairs(theme) do
				self.Theme[name] = value
			end
		end
		function self:Register(name, item)
			self.Registered[name] = table.clone(item)
		end
		function self:UnRegister(name)
			self.Registered[name] = nil
		end
		function self:QueueDivider(text)
			self.QueuedDivider = true
			self.QueuedDividerText = text
		end
		function self:AddDivider(text)
			self.QueuedDivider = false
			self.QueuedDividerText = nil
			if #self.Items == 0 or self.Items[#self.Items].Divider then
				return
			end
			self.Items[#self.Items + 1] = { Divider = true, Text = text }
		end
		function self:Add(item)
			if self.QueuedDivider then
				self:AddDivider(self.QueuedDividerText)
			end
			local entry = table.clone(item)
			entry.Name = entry.Name or entry.Text or ""
			self.Items[#self.Items + 1] = entry
		end
		function self:AddRegistered(name, disabled)
			if self.Added[name] then
				return
			end
			self.Added[name] = true
			local item = table.clone(assert(self.Registered[name], "Unregistered menu action: " .. name))
			item.Disabled = disabled
			self:Add(item)
		end
		local function clearSubmenus()
			if self.ChildMenu then
				self.ChildMenu:Hide()
				self.ChildMenu = nil
			end
			for _, item in ipairs(self.Items) do
				if item.ChildMenu then
					item.ChildMenu:Destroy()
					item.ChildMenu = nil
				end
			end
		end
		function self:Clear()
			clearSubmenus()
			self.Items = {}
			self.Added = {}
			self.QueuedDivider = false
			self.QueuedDividerText = nil
		end
		function self:Refresh()
			rebuild()
			render()
		end
		function self:Hide()
			if self.Destroyed then
				return
			end
			fadeTicket += 1
			if openingFade then
				openingFade:Cancel()
				openingFade = nil
			end
			if self.ChildMenu then
				self.ChildMenu:Hide()
				self.ChildMenu = nil
			end
			local wasShown = self.Shown
			self.Shown = false
			activeMenus[self] = nil
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
				self.CloseEvent = nil
			end
			if service.UserInputService:GetFocusedTextBox() == self.GuiElems.SearchBar then
				self.GuiElems.SearchBar:ReleaseFocus()
			end
			self.Gui.Parent = nil
			if wasShown then
				stateChanged()
			end
		end
		function self:Destroy()
			if self.Destroyed then
				return
			end
			self:Hide()
			clearSubmenus()
			renderer:RemovePortal(key)
			self.Gui:Destroy()
			self.Destroyed = true
		end
		function self:Show(x, y)
			local wasShown = self.Shown
			self.Shown = true
			activeMenus[self] = true
			self.X = x
			self.Y = y
			if not wasShown then
				stateChanged()
			end
			if self.SearchEnabled and self.ClearSearchOnShow then
				self.GuiElems.SearchBar.Text = ""
			end
			rebuild()
			self.Selected = 0
			self.HoveredButton = nil
			if self.Theme.Compact then
				local width = self.PreferredWidth or (self.ParentMenu and 0 or 162)
				for _, item in ipairs(filtered) do
					if not item.Divider then
						local bounds = service.TextService:GetTextSize(
							item.Name .. "     ",
							12,
							Enum.Font.BuilderSans,
							Vector2.new(1000, 22)
						)
						width = math.max(width, math.ceil(bounds.X) + 37)
					end
				end
				self.Width = width
			end
			local mouse = Main.Mouse
			height = math.min(
				math.max(self.Theme.Compact and 22 or 28, contentHeight)
					+ (self.SearchEnabled and 42 or (self.Theme.Compact and 2 or 6)),
				self.MaxHeight or mouse.ViewSizeY - 8,
				mouse.ViewSizeY - 8
			)
			if self.Theme.Compact and self.ParentMenu then
				local parent = self.ParentMenu
				local left = parent.GuiElems.Main.AbsolutePosition.X
				x = left + parent.Width - 1
				if x + self.Width > mouse.ViewSizeX then
					x = left - self.Width + 1
				end
			end
			position = UDim2.fromOffset(
				math.clamp(x or mouse.X, 0, math.max(0, mouse.ViewSizeX - self.Width)),
				math.clamp(y or mouse.Y, 0, math.max(0, mouse.ViewSizeY - height))
			)
			self.GuiElems.List.CanvasPosition = Vector2.new(0, 0)
			render()
			if not wasShown and fadeRef.current then
				fadeRef.current.GroupTransparency = 1
			end
			Lib.ShowGui(self.Gui)
			if not wasShown then
				fadeTicket += 1
				local ticket = fadeTicket
				task.delay(0.025, function()
					local panel = fadeRef.current
					if ticket ~= fadeTicket or not self.Shown or not panel then
						return
					end
					openingFade = service.TweenService:Create(
						panel,
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ GroupTransparency = 0 }
					)
					openingFade:Play()
				end)
			end
			if self.CloseEvent then
				self.CloseEvent:Disconnect()
			end
			local ready = false
			self.CloseEvent = Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if not ready then
					return
				end
				if self.ChildMenu and self.ChildMenu.Shown then
					return
				end
				if input.KeyCode == Enum.KeyCode.Escape then
					self:Hide()
				elseif input.KeyCode == Enum.KeyCode.Right then
					local item = filtered[self.Selected]
					if item and item.Submenu then
						self:OpenSubmenu(item)
					end
				elseif input.KeyCode == Enum.KeyCode.Left and self.ParentMenu then
					self:Hide()
				elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
					local direction = input.KeyCode == Enum.KeyCode.Up and -1 or 1
					local index = self.Selected > 0 and self.Selected or (direction < 0 and 1 or 0)
					for _ = 1, #filtered do
						index = (index - 1 + direction) % #filtered + 1
						if not filtered[index].Divider and not filtered[index].Disabled then
							self.Selected = index
							break
						end
					end
					local offset = offsets[self.Selected] or 0
					local visible = height - (self.SearchEnabled and 39 or (self.Theme.Compact and 2 or 6))
					local current = self.GuiElems.List.CanvasPosition.Y
					if offset < current then
						current = offset
					elseif offset + (heights[self.Selected] or 0) > current + visible then
						current = offset + (heights[self.Selected] or 0) - visible
					end
					self.GuiElems.List.CanvasPosition = Vector2.new(0, current)
					render()
				elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
					local item = filtered[self.Selected]
					if item then
						activate(item, false)
					end
				elseif
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if not Lib.CheckMouseInGui(self.GuiElems.Main) then
						local parent = self.ParentMenu
						if parent and Lib.CheckMouseInGui(parent.GuiElems.Main) then
							self:Hide()
						elseif parent then
							parent:Hide()
						else
							self:Hide()
						end
					end
				end
			end)
			task.defer(function()
				ready = true
			end)
			if self.SearchEnabled and self.FocusSearchOnShow then
				self.GuiElems.SearchBar:CaptureFocus()
			end
		end
		render()
		self.GuiElems.SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
			rebuild()
			self.Selected = 0
			if self.GuiElems.SearchBar.Text ~= "" then
				for index, item in ipairs(filtered) do
					if not item.Divider and not item.Disabled then
						self.Selected = index
						break
					end
				end
			end
			self.GuiElems.List.CanvasPosition = Vector2.new(0, 0)
			render()
		end)
		self.GuiElems.List:GetPropertyChangedSignal("CanvasPosition"):Connect(render)
		Main.AddCleanup(function()
			self:Hide()
		end)
		return self
	end
	return Menu
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
