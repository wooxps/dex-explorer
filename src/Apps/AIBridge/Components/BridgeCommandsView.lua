--!strict

local Apps, Lib

local function InitDeps(d)
	Apps, Lib = d.Apps, d.Lib
end

local function CreateModule()
	local View = {}
	local inset, listTop, footerHeight = 10, 46, 36
	local rowHeight, sectionHeight = 30, 26
	local grantLabels = { inspect = "Inspect", edit = "Edit objects", execute = "Run code", pair = "Pairing" }

	function View.Create(parent, ui, disabled, onChanged)
		local theme, palette = ui.Theme, ui.Palette
		local groups, matches, rows, headers = {}, {}, {}, {}
		local catalogSize = 0
		local disabledOnly = false
		local status = ""
		local rebuild, paint, filter, menu
		local api = {}
		local query =
			ui:Field(parent, "FindCommand", "Search commands", UDim2.fromOffset(inset, 10), UDim2.new(0.64, -13, 0, 26))
		ui:Round(query, 2)
		query:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 33)
		ui:Icon(parent, "SearchIcon", "search", UDim2.fromOffset(inset + 9, 16), UDim2.fromOffset(14, 14))

		local function showFilter()
			if not menu then
				menu = (Apps.ContextMenu or Lib.ContextMenu).new()
				api.FilterMenu = menu
				menu.Iconless = true
				menu:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
				for index, label in ipairs({ "All commands", "Disabled only" }) do
					menu:Add({
						Name = label,
						OnClick = function()
							disabledOnly = index == 2
							menu:Hide()
							rebuild(true)
						end,
					})
				end
			elseif menu.Shown then
				menu:Hide()
				return
			end
			local anchor = filter.Gui.AbsolutePosition
			local size = filter.Gui.AbsoluteSize
			menu.PreferredWidth = math.max(116, size.X)
			menu:Show(anchor.X + size.X - menu.PreferredWidth, anchor.Y + size.Y + 2)
		end
		filter = ui:Button(
			parent,
			"DisabledFilter",
			"All commands",
			UDim2.new(0.64, 5, 0, 10),
			UDim2.new(0.36, -15, 0, 26),
			showFilter,
			"outlined"
		)
		ui:Round(filter.Gui, 2)
		filter.Gui.TextXAlignment = Enum.TextXAlignment.Left
		filter.Gui.TextTruncate = Enum.TextTruncate.AtEnd
		ui:Node("UIPadding", {
			Parent = filter.Gui,
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 22),
		})
		ui:Icon(parent, "FilterChevron", "chevron-down", UDim2.new(1, -27, 0, 18), UDim2.fromOffset(10, 10))
		local function fitFilters()
			local width = math.max(114, math.floor(parent.AbsoluteSize.X * 0.36 - 15))
			query.Size = UDim2.new(1, -width - 2 * inset - 8, 0, 26)
			filter.Gui.Position = UDim2.new(1, -width - inset, 0, 10)
			filter.Gui.Size = UDim2.fromOffset(width, 26)
		end
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFilters)
		fitFilters()

		ui:Node("Frame", {
			Name = "CommandFooter",
			Parent = parent,
			Position = UDim2.new(0, 0, 1, -footerHeight),
			Size = UDim2.new(1, 0, 0, footerHeight),
			BackgroundColor3 = palette.Input,
			BorderSizePixel = 0,
		})
		local footerRule = ui:Rule(parent, "FooterRule", 0)
		footerRule.Position = UDim2.new(0, 0, 1, -footerHeight)
		footerRule.Size = UDim2.new(1, 0, 0, 1)
		footerRule.BackgroundColor3 = palette.Border
		local count = ui:Text(
			parent,
			"CommandCount",
			"",
			UDim2.new(0, inset, 1, -footerHeight),
			UDim2.new(1, -104, 0, footerHeight),
			true,
			12
		)
		local countTip = ""
		ui:Tip(count, function()
			return countTip
		end)
		local enableAll = ui:Button(
			parent,
			"EnableAll",
			"Enable all",
			UDim2.new(1, -85, 1, -31),
			UDim2.fromOffset(75, 26),
			function()
				table.clear(disabled)
				rebuild(false)
				onChanged()
			end,
			"link"
		)
		enableAll.TextColor = palette.Link
		enableAll.Gui.TextXAlignment = Enum.TextXAlignment.Right
		ui:Node("UIPadding", { Parent = enableAll.Gui, PaddingRight = UDim.new(0, 2) })

		local list = ui:Node("ScrollingFrame", {
			Name = "CommandList",
			Parent = parent,
			Position = UDim2.fromOffset(2, listTop),
			Size = UDim2.new(1, -4, 1, -listTop - footerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			CanvasPosition = Vector2.new(0, 0),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = theme.PlaceholderText,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ClipsDescendants = true,
		})
		local empty = ui:Text(list, "Empty", "", UDim2.fromOffset(inset, 16), UDim2.new(1, -2 * inset, 0, 40), true)
		empty.TextWrapped = true
		empty.TextTruncate = Enum.TextTruncate.None
		empty.TextYAlignment = Enum.TextYAlignment.Top

		local function addRule(gui)
			ui:Node("Frame", {
				Name = "RowRule",
				Parent = gui,
				Position = UDim2.new(0, 0, 1, -1),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = palette.Border,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			})
		end

		local function newHeader()
			local gui = ui:Node("Frame", {
				Name = "CommandGroup",
				Parent = list,
				Size = UDim2.new(1, 0, 0, sectionHeight),
				BackgroundColor3 = palette.Raised,
				BorderSizePixel = 0,
			})
			addRule(gui)
			local title = ui:Text(gui, "Title", "", UDim2.fromOffset(inset, 0), UDim2.new(1, -26, 1, 0), false, 13)
			title.Font = Lib.StudioBold or Enum.Font.BuilderSansBold
			return { Gui = gui, Title = title }
		end

		local function newRow()
			local gui = ui:Node("Frame", {
				Name = "Command",
				Parent = list,
				Size = UDim2.new(1, 0, 0, rowHeight),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			})
			local row = {
				Gui = gui,
				Name = ui:Text(gui, "Name", "", UDim2.fromOffset(inset, 0), UDim2.new(1, -62, 1, 0), false, 13),
			}
			addRule(gui)
			ui:Tip(row.Name, function()
				local item = row.Item
				return item and item.Tooltip
			end)
			row.Toggle = ui:Switch(gui, "Enabled", UDim2.new(1, -46, 0.5, -10), function()
				local item = row.Item
				if item then
					disabled[item.name] = not disabled[item.name] or nil
					rebuild(false)
					onChanged()
				end
			end)
			return row
		end

		paint = function()
			local offset = list.CanvasPosition.Y
			local bottom = offset + list.AbsoluteSize.Y + rowHeight
			local first, last = 1, #matches
			while first < last do
				local middle = math.floor((first + last) / 2)
				local item = matches[middle]
				if item.Top + item.Height <= offset then
					first = middle + 1
				else
					last = middle
				end
			end
			local visibleRows, visibleHeaders = 0, 0
			for index = first, #matches do
				local item = matches[index]
				if item.Top >= bottom then
					break
				end
				if item.GroupTitle then
					visibleHeaders += 1
					local header = headers[visibleHeaders] or newHeader()
					headers[visibleHeaders] = header
					header.Gui.Visible = true
					header.Gui.Position = UDim2.fromOffset(0, item.Top)
					header.Title.Text = item.GroupTitle
				else
					visibleRows += 1
					local row = rows[visibleRows] or newRow()
					rows[visibleRows] = row
					if row.Item ~= item then
						row.Toggle.Hovered = false
						row.Toggle.Pressed = false
					end
					row.Item = item
					row.Gui.Visible = true
					row.Gui.Position = UDim2.fromOffset(0, item.Top)
					row.Name.Text = item.Title
					row.Toggle:SetOn(not disabled[item.name])
				end
			end
			for index = visibleRows + 1, #rows do
				rows[index].Gui.Visible = false
				rows[index].Item = nil
			end
			for index = visibleHeaders + 1, #headers do
				headers[index].Gui.Visible = false
			end
		end

		rebuild = function(resetScroll)
			local disabledCount, visibleCount, height = 0, 0, 0
			local term = query.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
			table.clear(matches)
			for _, group in ipairs(groups) do
				local needsHeader = true
				for _, item in ipairs(group.Items) do
					local off = disabled[item.name] == true
					if off then
						disabledCount += 1
					end
					if (not disabledOnly or off) and (term == "" or item.Search:find(term, 1, true)) then
						if needsHeader then
							group.Header.Top = height
							matches[#matches + 1] = group.Header
							height += sectionHeight
							needsHeader = false
						end
						item.Top = height
						matches[#matches + 1] = item
						visibleCount += 1
						height += rowHeight
					end
				end
			end
			local countText = visibleCount .. (visibleCount == 1 and " command" or " commands")
			count.Text = catalogSize > 0 and countText .. (status ~= "" and "  ·  " .. status or "") or ""
			countTip = string.format("%d enabled · %d disabled", catalogSize - disabledCount, disabledCount)
			filter.Gui.Text = disabledOnly and "Disabled only" or "All commands"
			filter:SetEnabled(catalogSize > 0)
			enableAll:SetEnabled(next(disabled) ~= nil)
			empty.Visible = visibleCount == 0
			empty.Text = catalogSize == 0 and "No commands"
				or (term == "" and disabledOnly) and "No disabled commands"
				or "No matches"
			list.CanvasSize = UDim2.fromOffset(0, height)
			local newOffset = resetScroll and 0
				or math.clamp(list.CanvasPosition.Y, 0, math.max(0, height - list.AbsoluteSize.Y))
			if list.CanvasPosition.Y ~= newOffset then
				list.CanvasPosition = Vector2.new(0, newOffset)
			end
			paint()
		end
		query:GetPropertyChangedSignal("Text"):Connect(function()
			rebuild(true)
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)

		api.Query = query
		api.Rows = rows
		api.Filter = filter.Gui
		api.EnableAll = enableAll.Gui
		local source
		function api:Update(value, pending, state, controls)
			local nextStatus = pending and "Syncing…"
				or state ~= "Connected" and "Offline"
				or not controls and "Restart MCP client"
				or ""
			if source == value and status == nextStatus then
				return
			end
			status = nextStatus
			if source ~= value then
				source = value
				catalogSize = 0
				table.clear(groups)
				local groupByTitle = {}
				local inspectGroup
				for index, item in ipairs(value) do
					if index > 512 then
						break
					end
					if type(item) == "table" and type(item.name) == "string" then
						local name = item.name
						local description = type(item.description) == "string" and item.description or ""
						local category = type(item.category) == "string" and item.category or ""
						local grantTitle = type(item.grant) == "string" and grantLabels[item.grant] or nil
						local groupTitle = (category == "" or category == "Dex") and (grantTitle or "Dex") or category
						local group = groupByTitle[groupTitle]
						if not group then
							group = { Header = { GroupTitle = groupTitle, Height = sectionHeight }, Items = {} }
							groupByTitle[groupTitle] = group
							if groupTitle == "Inspect" then
								inspectGroup = group
							else
								groups[#groups + 1] = group
							end
						end
						local label = name:gsub("^dex_", ""):gsub("_", " ")
						local tooltip = name .. (description ~= "" and "\n" .. description or "")
						local record = {
							name = name,
							Height = rowHeight,
							Title = label:sub(1, 1):upper() .. label:sub(2),
							Tooltip = (tooltip:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")),
							Search = (
								name
								.. " "
								.. label
								.. " "
								.. description
								.. " "
								.. category
								.. " "
								.. groupTitle
							):lower(),
						}
						catalogSize += 1
						group.Items[#group.Items + 1] = record
					end
				end
				if inspectGroup then
					table.insert(groups, 1, inspectGroup)
				end
			end
			rebuild(false)
		end
		function api:CloseMenu()
			if menu then
				menu:Hide()
			end
		end
		function api:Destroy()
			if menu then
				menu:Destroy()
			end
		end
		rebuild(false)
		return api
	end

	return View
end

return { InitDeps = InitDeps, Main = CreateModule }
