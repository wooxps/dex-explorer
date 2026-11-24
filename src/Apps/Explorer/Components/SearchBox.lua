--!strict

local Main, Lib, Apps, Settings, env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, env, service = d.Main, d.Lib, d.Apps, d.Settings, d.env, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local SearchBox = {}
	local function normalizeHistoryQuery(query)
		return query:sub(1, 32767):gsub("\n", " "):gsub("\r", ""):match("^%s*(.-)%s*$")
	end
	function SearchBox.LoadHistory(placeId)
		local all = Settings.Explorer.SearchHistoryByPlace
		local saved = type(all) == "table" and all[tostring(placeId or 0)]
		local history, seen = {}, {}
		if type(saved) == "table" then
			for _, query in ipairs(saved) do
				if type(query) == "string" then
					query = normalizeHistoryQuery(query)
					if query ~= "" and not seen[query] then
						seen[query] = true
						history[#history + 1] = query
						if #history == 10 then
							break
						end
					end
				end
			end
		end
		return history
	end
	function SearchBox.Bind(Explorer, toolBar, treeFrame)
		local placeId = game.PlaceId or 0
		Explorer.SearchHistory = SearchBox.LoadHistory(placeId)
		local function saveSettings()
			if Main.SaveSettings then
				pcall(Main.SaveSettings)
			end
		end
		local tokens = Apps.ExplorerPolicy.Tokens
		local function createSimple(class, props)
			return Apps.Dropdown.Create(Explorer.TreeRenderer, class, props)
		end
		local function corner(object, radius)
			return Apps.Dropdown.Corner(Explorer.TreeRenderer, object, radius)
		end
		local renderer = Explorer.TreeRenderer
		local widgets = Apps.SearchBar.Create(renderer, toolBar)
		local searchBox, history, options = widgets.SearchBox, widgets.History, widgets.Options
		Apps.TooltipActions.Bind(history, "Search history", renderer)
		Apps.TooltipActions.Bind(options, "Explorer settings", renderer)
		Explorer.GuiElems.SearchBar = searchBox
		toolBar.SearchFrame.Reset.Activated:Connect(Explorer.ClearSearch)

		local status = createSimple("Frame", {
			Name = "SearchStatus",
			Parent = Explorer.Window.GuiElems.Content,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, tokens.HeaderHeight - 1),
			Size = UDim2.new(1, 0, 0, 20),
			Visible = false,
		})
		Explorer.GuiElems.SearchStatus = status
		local count = createSimple("TextLabel", {
			Name = "Count",
			Parent = status,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -128, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		})
		Apps.Dropdown.StyleText(count)
		local spinner = createSimple("ImageLabel", {
			Name = "LoadingSpinner",
			Parent = status,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.fromOffset(16, 16),
			Visible = false,
			Rotation = -180,
			Image = Main.GetStudioAsset("explorer/loadingSpinner") or "",
			ImageColor3 = Settings.Theme.Text,
		})
		local spinElapsed, spinPending = 0, 0
		local spinConnection
		local function advanceSpinner(delta)
			if not Explorer.SearchBusy then
				spinPending = 0
				return
			end
			spinPending += delta
			if spinPending < 1 / 30 then
				return
			end
			spinElapsed += spinPending
			spinPending = 0
			spinner.Rotation = spinElapsed * 270 % 360 - 180
		end
		Explorer.AdvanceSearchSpinner = advanceSpinner
		local function stopSpinner()
			if spinConnection then
				spinConnection:Disconnect()
				spinConnection = nil
			end
			spinPending = 0
		end
		function Explorer.UpdateSearchSpinner()
			if Main.Alive ~= false and Explorer.SearchBusy and Explorer.Active and Explorer.Window:IsVisible() then
				local signal = service.RunService and service.RunService.Heartbeat
				if signal and not spinConnection then
					spinConnection = signal:Connect(advanceSpinner)
				end
			else
				stopSpinner()
			end
		end
		Main.AddCleanup(stopSpinner)
		local previous = Apps.SearchBrowserButton.Create(renderer, status, "Previous", UDim2.new(1, -84, 0, 0))
		local nextMatch = Apps.SearchBrowserButton.Create(renderer, status, "Next", UDim2.new(1, -64, 0, 0))
		local all = Apps.SearchBrowserButton.Create(renderer, status, "SelectAll", UDim2.new(1, -44, 0, 0))
		local refresh = Apps.SearchBrowserButton.Create(renderer, status, "Refresh", UDim2.new(1, -24, 0, 0))
		previous.Activated:Connect(function()
			Explorer.StepMatch(-1, Lib.IsCtrlDown())
		end)
		nextMatch.Activated:Connect(function()
			Explorer.StepMatch(1, Lib.IsCtrlDown())
		end)
		all.Activated:Connect(function()
			Explorer.SelectMatches(true)
		end)
		refresh.Activated:Connect(function()
			Explorer.DoSearch(searchBox.Text)
		end)
		local empty = createSimple("TextLabel", {
			Name = "Empty",
			Parent = treeFrame,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 18),
			Size = UDim2.new(1, -24, 0, 46),
			TextWrapped = true,
			Text = "",
			Visible = false,
		})
		Apps.Dropdown.StyleText(empty)
		empty.TextColor3 = Settings.Theme.PlaceholderText
		Explorer.GuiElems.Empty = empty
		local popupGui = createSimple("ScreenGui", {
			Name = "ExplorerHeaderPopup",
			DisplayOrder = Main.DisplayOrders.Menu,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		local popup = createSimple("Frame", {
			Name = "Panel",
			Parent = popupGui,
			Visible = false,
			Active = true,
			BorderSizePixel = 0,
			BackgroundColor3 = Settings.Theme.Menu,
			ClipsDescendants = true,
		})
		corner(popup, 6)
		local border = createSimple("UIStroke", { Parent = popup, Thickness = 1.5, Color = Settings.Theme.Outline2 })
		local list = createSimple("ScrollingFrame", {
			Name = "Items",
			Parent = popup,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Settings.Theme.PlaceholderText,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		})
		local historyRows, historyActions, historyIndex = {}, {}, 0
		local openKind, popupHeight
		local popupRevision = 0
		local holdGeneration, heldKey = 0, nil
		local function stopHold()
			holdGeneration += 1
			heldKey = nil
		end
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input.KeyCode == heldKey or input.UserInputType ~= Enum.UserInputType.Keyboard then
				stopHold()
			end
		end)
		if Main.AddCleanup then
			Main.AddCleanup(stopHold)
		end
		local insideInputs = setmetatable({}, { __mode = "k" })
		local function protectInput(gui)
			gui.InputBegan:Connect(function(input)
				insideInputs[input] = true
			end)
		end
		protectInput(popup)
		protectInput(list)
		protectInput(history)
		protectInput(options)
		protectInput(searchBox)
		protectInput(toolBar.SearchFrame)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			task.defer(function()
				insideInputs[input] = nil
			end)
		end)
		local searchStroke = toolBar.SearchFrame:FindFirstChildOfClass("UIStroke")
		local function closePopup()
			stopHold()
			local wasVisible = popup.Visible
			popupRevision += 1
			openKind = nil
			popup.Visible = false
			popupGui.Parent = nil
			if searchStroke then
				searchStroke.Enabled = service.UserInputService:GetFocusedTextBox() == searchBox
			end
			if wasVisible and Explorer.PerformRefresh then
				Explorer.PerformRefresh()
			end
		end
		Explorer.CloseHeaderPopup = closePopup
		Explorer.GuiElems.HeaderPopup = popup
		local function placePopup()
			local pos, size = toolBar.AbsolutePosition, toolBar.AbsoluteSize
			local width = math.min(math.max(0, size.X - 12), Main.Mouse.ViewSizeX - 8)
			local x = math.clamp(pos.X + 6, 4, math.max(4, Main.Mouse.ViewSizeX - width - 4))
			local y = pos.Y + size.Y
			local height = math.min(popupHeight or 0, math.max(0, Main.Mouse.ViewSizeY - y - 4))
			popup.Position = UDim2.fromOffset(x, y)
			popup.Size = UDim2.fromOffset(width, height)
		end
		local function label(text, y, muted)
			local row = createSimple("TextLabel", {
				Parent = list,
				Name = "Label",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, y),
				Size = UDim2.new(1, -16, 0, 24),
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Apps.Dropdown.StyleText(row)
			if muted then
				row.TextColor3 = Settings.Theme.PlaceholderText
			end
			return row
		end
		local function button(text, y, inset)
			local row = createSimple("TextButton", {
				Parent = list,
				Name = "Item",
				BackgroundTransparency = 1,
				BackgroundColor3 = Settings.Theme.ExplorerHoverFill or Color3.fromRGB(187, 194, 209),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, 22),
				Text = "",
			})
			corner(row, 6)
			local title = createSimple("TextLabel", {
				Parent = row,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(inset or 8, 0),
				Size = UDim2.new(1, -(inset or 8) - 8, 1, 0),
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Apps.Dropdown.StyleText(title)
			row.MouseEnter:Connect(function()
				row.BackgroundTransparency = 0.92
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundTransparency = 1
			end)
			return row
		end
		local function remember(query)
			query = normalizeHistoryQuery(query)
			if query == "" or Explorer.SearchError then
				return
			end
			local index = table.find(Explorer.SearchHistory, query)
			if index then
				table.remove(Explorer.SearchHistory, index)
			end
			table.insert(Explorer.SearchHistory, 1, query)
			while #Explorer.SearchHistory > 10 do
				table.remove(Explorer.SearchHistory)
			end
			if type(Settings.Explorer.SearchHistoryByPlace) ~= "table" then
				Settings.Explorer.SearchHistoryByPlace = {}
			end
			Settings.Explorer.SearchHistoryByPlace[tostring(placeId)] = table.clone(Explorer.SearchHistory)
			saveSettings()
		end
		Explorer.RememberSearch = remember
		local function selectHistory(index)
			if #historyRows == 0 then
				return
			end
			historyIndex = (index - 1) % #historyRows + 1
			for i, row in ipairs(historyRows) do
				row.BackgroundTransparency = i == historyIndex and 0.92 or 1
			end
			local top = historyRows[historyIndex].Position.Y.Offset
			local offset = list.CanvasPosition.Y
			if top < offset then
				offset = top
			elseif top + 22 > offset + list.AbsoluteSize.Y then
				offset = top + 22 - list.AbsoluteSize.Y
			end
			list.CanvasPosition = Vector2.new(0, math.max(0, offset))
		end
		local function openPopup(kind)
			if openKind == kind then
				closePopup()
				return
			end
			closePopup()
			openKind = kind
			Apps.Dropdown.Clear(renderer, list)
			list.CanvasPosition = Vector2.new(0, 0)
			if kind == "History" then
				searchBox:CaptureFocus()
				label("History", 0, false)
				historyRows, historyActions, historyIndex = {}, {}, 0
				if #Explorer.SearchHistory == 0 then
					label("No searches have been made yet", 24, true)
					popupHeight = 56
				else
					for i, query in ipairs(Explorer.SearchHistory) do
						local row = button(query, 25 + (i - 1) * 27)
						historyRows[i] = row
						historyActions[i] = function()
							closePopup()
							searchBox.Text = query
							Explorer.SearchRevision += 1
							Explorer.DoSearch(query)
							remember(query)
						end
						row.Activated:Connect(historyActions[i])
						row.MouseEnter:Connect(function()
							selectHistory(i)
						end)
					end
					popupHeight = 33 + math.min(130, math.max(0, #Explorer.SearchHistory * 27 - 5))
				end
				list.CanvasSize = UDim2.fromOffset(
					0,
					(#Explorer.SearchHistory == 0 and 48 or 25 + math.max(0, #Explorer.SearchHistory * 27 - 5))
				)
			else
				searchBox:CaptureFocus()
				historyRows, historyActions, historyIndex = {}, {}, 0
				local function checkbox(text, key, y, default)
					local row = button(text, y, 34)
					local check = createSimple("ImageLabel", {
						Name = "Check",
						Parent = row,
						BorderSizePixel = 0,
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(8, 6),
						Size = UDim2.fromOffset(16, 16),
						ScaleType = Enum.ScaleType.Fit,
					})
					local function sync()
						local value = Settings.Explorer[key]
						if value == nil then
							value = default
						end
						check.Image = Main.GetStudioAsset(
							value and "native/explorer/checked" or "native/explorer/unchecked"
						) or ""
					end
					local function activate()
						local value = Settings.Explorer[key]
						if value == nil then
							value = default
						end
						Settings.Explorer[key] = not value
						sync()
						saveSettings()
					end
					local index = #historyRows + 1
					historyRows[index], historyActions[index] = row, activate
					row.MouseEnter:Connect(function()
						selectHistory(index)
					end)
					row.Activated:Connect(activate)
					sync()
				end
				checkbox("Increment names for new Instances", "IncrementNames", 0, false)
				checkbox("Expand hierarchy when selecting", "ExpandHierarchy", 28, true)
				popupHeight = 64
				list.CanvasSize = UDim2.fromOffset(0, 56)
				if type(env.getnilinstances) == "function" then
					local refreshNil = button("Refresh Nil Instances", 60)
					refreshNil.Activated:Connect(function()
						if Explorer.RefreshNilInstances() then
							closePopup()
						else
							refreshNil:FindFirstChildOfClass("TextLabel").Text = Explorer.NilError
						end
					end)
					popupHeight = 96
					list.CanvasSize = UDim2.fromOffset(0, 88)
				end
			end
			for _, child in ipairs(list:GetDescendants()) do
				if child:IsA("GuiObject") then
					protectInput(child)
				end
			end
			placePopup()
			popup.Visible = true
			Lib.ShowGui(popupGui)
			if Explorer.PerformRefresh then
				Explorer.PerformRefresh()
			end
		end
		local suggestion, suggestionRows, selected = nil, {}, 1
		local suggestionIndices, suggestionFilters = {}, false
		local suggestionQuery, suggestionCursor
		local updateSuggestions
		local completing = false
		local completedQuery
		local function renderSuggestions()
			if openKind ~= "Autocomplete" or not suggestion then
				return
			end
			local first = suggestionFilters and 1
				or math.clamp(
					math.floor((list.CanvasPosition.Y - 4) / 27) + 1,
					1,
					math.max(1, #suggestion.Choices - #suggestionRows + 1)
				)
			for slot, row in ipairs(suggestionRows) do
				local index = first + slot - 1
				suggestionIndices[slot] = index
				row.Position = UDim2.fromOffset(8, (index - 1) * 27 + 4 + (suggestionFilters and 28 or 0))
				row:FindFirstChildOfClass("TextLabel").Text = suggestion.Choices[index]
				row.BackgroundTransparency = index == selected and 0.92 or 1
			end
		end
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(renderSuggestions)
		local function selectSuggestion(index)
			if not suggestion or #suggestion.Choices == 0 then
				return
			end
			selected = (index - 1) % #suggestion.Choices + 1
			local top = (selected - 1) * 27 + 4 + (suggestionFilters and 28 or 0)
			local view = (popupHeight or 143) - 8
			local offset = list.CanvasPosition.Y
			if top < offset then
				offset = top
			elseif top + 27 > offset + view then
				offset = top + 27 - view
			end
			list.CanvasPosition = Vector2.new(0, offset)
			renderSuggestions()
		end
		local function acceptSuggestion()
			if openKind ~= "Autocomplete" or not suggestion then
				return false
			end
			local value = suggestion.Choices[selected]
			if not value then
				return false
			end
			local query = searchBox.Text:sub(1, suggestion.First - 1)
				.. value
				.. searchBox.Text:sub(suggestion.Last + 1)
			local caret = suggestion.First + #value
			completing = true
			completedQuery = not value:match("[:=]$") and query or nil
			closePopup()
			searchBox.Text = query
			searchBox:CaptureFocus()
			searchBox.CursorPosition = caret
			completing = false
			if value:match("[:=]$") then
				updateSuggestions()
			end
			Explorer.SearchRevision += 1
			Explorer.DoSearch(query)
			return true
		end
		updateSuggestions = function(showFilters)
			if
				completing
				or searchBox.Text == completedQuery
				or service.UserInputService:GetFocusedTextBox() ~= searchBox
			then
				return
			end
			local cursor = searchBox.CursorPosition
			local filters = searchBox.Text == ""
			if filters and showFilters ~= true then
				return
			end
			local nextSuggestion
			if filters then
				nextSuggestion = {
					Choices = { "anchored=", "locked=", "transparency=", "material=", "meshId=", "textureId=", "tag:" },
					First = 1,
					Last = 0,
				}
			else
				nextSuggestion =
					Apps.SearchQuery.Suggest(searchBox.Text, cursor and cursor > 0 and cursor or #searchBox.Text + 1)
			end
			if not nextSuggestion then
				if openKind == "Autocomplete" then
					closePopup()
				end
				return
			end
			if
				openKind == "Autocomplete"
				and suggestionQuery == searchBox.Text
				and suggestionCursor == cursor
				and #suggestion.Choices == #nextSuggestion.Choices
			then
				local same = true
				for i, value in ipairs(nextSuggestion.Choices) do
					if suggestion.Choices[i] ~= value then
						same = false
						break
					end
				end
				if same then
					return
				end
			end
			closePopup()
			suggestion, suggestionFilters = nextSuggestion, filters
			suggestionQuery, suggestionCursor = searchBox.Text, cursor
			Apps.Dropdown.Clear(renderer, list)
			suggestionRows, suggestionIndices = {}, {}
			list.CanvasPosition = Vector2.new(0, 0)
			openKind = "Autocomplete"
			for i = 1, math.min(#suggestion.Choices, 7) do
				local value = suggestion.Choices[i]
				local row = button(value, (i - 1) * 27, filters and 30 or 8)
				row.Size = UDim2.new(1, -8, 0, 22)
				row:FindFirstChildOfClass("TextLabel").TextSize = 14
				row.Position = UDim2.fromOffset(8, (i - 1) * 27 + 4 + (filters and 28 or 0))
				if filters then
					local keys = { "anchor", "lock", "transparency", "material", "mesh", "texture", "tag" }
					local asset = Main.GetStudioAsset and Main.GetStudioAsset("native/filter/" .. keys[i])
					local icon = createSimple("Frame", {
						Name = "FilterIcon",
						Parent = row,
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(8, 3),
						Size = UDim2.fromOffset(16, 16),
					})
					if asset then
						createSimple("ImageLabel", {
							Name = "Native",
							Parent = icon,
							BackgroundTransparency = 1,
							Size = UDim2.fromScale(1, 1),
							Image = asset,
							ScaleType = Enum.ScaleType.Fit,
						})
					end
				end
				suggestionRows[i], suggestionIndices[i] = row, i
				row.MouseEnter:Connect(function()
					selectSuggestion(suggestionIndices[i])
				end)
				row.MouseLeave:Connect(function()
					row.BackgroundTransparency = selected == suggestionIndices[i] and 0.92 or 1
				end)
				row.Activated:Connect(function()
					selected = suggestionIndices[i]
					acceptSuggestion()
				end)
			end
			for _, child in ipairs(list:GetDescendants()) do
				if child:IsA("GuiObject") then
					protectInput(child)
				end
			end
			if filters then
				label("Suggested Filters", 4, true).TextSize = 13
				local help = createSimple("ImageButton", {
					Name = "FilterHelp",
					Parent = list,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Position = UDim2.new(1, -24, 0, 8),
					Size = UDim2.fromOffset(16, 16),
					Image = Main.GetStudioAsset and Main.GetStudioAsset("native/filter/help") or "",
				})
				protectInput(help)
				Apps.TooltipActions.Bind(
					help,
					"Choose a filter, then enter a value. Combine filters with AND or OR.",
					renderer
				)
				help.Activated:Connect(function()
					local url = "https://create.roblox.com/docs/studio/explorer#filtering-instances"
					local opened = pcall(function()
						game:GetService("BrowserService"):OpenBrowserWindow(url)
					end)
					if opened then
						closePopup()
						return
					end
					if type(env.setclipboard) == "function" then
						local copied = pcall(env.setclipboard, url)
						if copied then
							closePopup()
							return
						end
					end
					closePopup()
					Apps.Dropdown.Clear(renderer, list)
					label("Explorer syntax guide", 0, false)
					local link = createSimple("TextBox", {
						Name = "SyntaxGuideUrl",
						Parent = list,
						BackgroundTransparency = 1,
						ClearTextOnFocus = false,
						TextEditable = false,
						Position = UDim2.fromOffset(8, 25),
						Size = UDim2.new(1, -16, 0, 24),
						Text = url,
						TextXAlignment = Enum.TextXAlignment.Left,
					})
					Apps.Dropdown.StyleText(link)
					protectInput(link)
					popupHeight = 58
					list.CanvasSize = UDim2.fromOffset(0, 50)
					openKind = "Guide"
					placePopup()
					popup.Visible = true
					Lib.ShowGui(popupGui)
					if Explorer.PerformRefresh then
						Explorer.PerformRefresh()
					end
					link:CaptureFocus()
					link.SelectionStart = 1
					link.CursorPosition = #url + 1
				end)
			end
			popupHeight = filters and (44 + #suggestion.Choices * 27)
				or (8 + math.min(130, math.max(0, #suggestion.Choices * 27 - 5)))
			list.CanvasSize = UDim2.fromOffset(0, 8 + #suggestion.Choices * 27 + (filters and 28 or 0))
			if filters then
				selected = 0
				renderSuggestions()
			else
				selectSuggestion(1)
			end
			placePopup()
			popup.Visible = true
			Lib.ShowGui(popupGui)
			if Explorer.PerformRefresh then
				Explorer.PerformRefresh()
			end
		end
		searchBox:GetPropertyChangedSignal("CursorPosition"):Connect(updateSuggestions)
		searchBox.Focused:Connect(function()
			if not openKind then
				updateSuggestions(true)
			end
		end)
		local headerEnterConsumed = false
		local function movePopup(key)
			if openKind == "History" or openKind == "Options" then
				selectHistory(
					key == Enum.KeyCode.Down and historyIndex + 1
						or (historyIndex == 0 and #historyRows or historyIndex - 1)
				)
			elseif openKind == "Autocomplete" then
				selectSuggestion(
					key == Enum.KeyCode.Down and selected + 1 or (selected == 0 and #suggestion.Choices or selected - 1)
				)
			end
		end
		local function modifiersDown()
			return Lib.IsCtrlDown()
				or Lib.IsShiftDown()
				or service.UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
				or service.UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		end
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if service.UserInputService:GetFocusedTextBox() ~= searchBox then
				return
			end
			local key = input.KeyCode
			if
				(key == Enum.KeyCode.Up or key == Enum.KeyCode.Down)
				and (openKind == "History" or openKind == "Options" or openKind == "Autocomplete")
			then
				if modifiersDown() then
					stopHold()
					return
				end
				movePopup(key)
				if heldKey ~= key then
					stopHold()
					heldKey = key
					local generation, revision, kind, query = holdGeneration, popupRevision, openKind, searchBox.Text
					local function repeatKey()
						if
							holdGeneration ~= generation
							or not Main.Alive
							or popupRevision ~= revision
							or openKind ~= kind
							or searchBox.Text ~= query
							or not popup.Visible
							or not Explorer.Window:IsVisible()
							or service.UserInputService:GetFocusedTextBox() ~= searchBox
							or modifiersDown()
							or not service.UserInputService:IsKeyDown(key)
						then
							if holdGeneration == generation then
								stopHold()
							end
							return
						end
						movePopup(key)
						if holdGeneration == generation then
							task.delay(0.02, repeatKey)
						end
					end
					task.delay(0.5, repeatKey)
				end
				return
			end
			if openKind == "History" or openKind == "Options" then
				if input.KeyCode == Enum.KeyCode.Return then
					local action = historyActions[historyIndex]
					if action then
						headerEnterConsumed = true
						task.defer(function()
							headerEnterConsumed = false
						end)
						action()
					end
				end
				return
			end
			if
				not openKind
				and input.KeyCode == Enum.KeyCode.Down
				and not Lib.IsCtrlDown()
				and not Lib.IsShiftDown()
			then
				if Explorer.FocusFirstFromSearch then
					Explorer.FocusFirstFromSearch()
				end
				return
			end
			if openKind ~= "Autocomplete" then
				return
			end
			if input.KeyCode == Enum.KeyCode.Tab then
				acceptSuggestion()
			end
		end)
		history.Activated:Connect(function()
			openPopup("History")
		end)
		options.Activated:Connect(function()
			openPopup("Options")
		end)
		toolBar:GetPropertyChangedSignal("AbsolutePosition"):Connect(placePopup)
		toolBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePopup)
		Explorer.Window.OnMinimize:Connect(closePopup)
		Explorer.Window.OnDeactivate:Connect(closePopup)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if not openKind then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				Explorer.HeaderPopupEscapeInput = input
				closePopup()
				return
			end
			local kind = input.UserInputType
			if
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.Touch
			then
				local revision = popupRevision
				task.defer(function()
					if revision ~= popupRevision or not openKind or insideInputs[input] then
						return
					end
					if
						kind ~= Enum.UserInputType.Touch
						and (
							Lib.CheckMouseInGui(searchBox)
							or Lib.CheckMouseInGui(popup)
							or Lib.CheckMouseInGui(history)
							or Lib.CheckMouseInGui(options)
						)
					then
						return
					end
					closePopup()
				end)
			end
		end)
		Explorer.SearchRevision = 0
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = searchBox.Text
			Explorer.SearchInputPending = true
			Explorer.SearchRevision += 1
			local revision = Explorer.SearchRevision
			if query ~= completedQuery then
				completedQuery = nil
			end
			closePopup()
			updateSuggestions()
			task.delay(0.18, function()
				if
					revision == Explorer.SearchRevision
					and Explorer.SearchInputPending
					and Explorer.Window:IsVisible()
				then
					Explorer.DoSearch(query)
				end
			end)
		end)
		searchBox.FocusLost:Connect(function(enterPressed, causedBy)
			stopHold()
			if enterPressed and headerEnterConsumed then
				searchBox:CaptureFocus()
				return
			end
			if enterPressed and acceptSuggestion() then
				return
			end
			if not enterPressed then
				task.defer(function()
					if openKind ~= "Autocomplete" or service.UserInputService:GetFocusedTextBox() == searchBox then
						return
					end
					if causedBy and insideInputs[causedBy] then
						return
					end
					if Lib.CheckMouseInGui(popup) then
						return
					end
					closePopup()
				end)
			end
			local query = searchBox.Text
			if not enterPressed and (query == Explorer.Query or query == Explorer.SearchPendingQuery) then
				return
			end
			Explorer.SearchRevision += 1
			if not Explorer.DoSearch(query) then
				return
			end
			if enterPressed then
				remember(query)
				closePopup()
			end
			if enterPressed then
				Explorer.StepMatch(1)
			end
		end)
	end

	return SearchBox
end
return { InitDeps = InitDeps, Main = CreateModule }
