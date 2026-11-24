--!strict

local Apps, Lib, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Lib, env = d.Apps, d.Lib, d.env or {}
end
------------------------------ Module ------------------------------

local function Main()
	local View = {}
	function View.Create(parent, ui, clearActivity)
		ui = ui or Apps.BridgeUI.Create(true)
		local theme, palette = ui.Theme, ui.Palette
		local rows, entries = {}, {}
		local selected
		local detailMode = "Overview"
		local filter = ""
		local resultFilter = "All"
		local rowHeight, tableTop, headingHeight, margin = 22, 43, 22, 7
		local resultColumn, timeColumn = 0.43, 0.77
		local root = ui:Node("Frame", {
			Name = "CommandActivity",
			Parent = parent,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		})
		local query =
			ui:Field(root, "FilterCommands", "Filter commands...", UDim2.fromOffset(10, 10), UDim2.new(1, -79, 0, 24))
		ui:Round(query, 2)
		query:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 33)
		ui:Icon(root, "SearchIcon", "search", UDim2.fromOffset(20, 15), UDim2.fromOffset(14, 14))
		local clear = ui:Button(
			root,
			"ClearActivity",
			"Clear",
			UDim2.new(1, -61, 0, 10),
			UDim2.fromOffset(51, 24),
			clearActivity,
			"outlined"
		)
		ui:Round(clear.Gui, 2)
		ui:Tip(clear.Gui, "Clear activity")

		local panel = ui:Node("Frame", {
			Name = "ActivityTable",
			Parent = root,
			Position = UDim2.fromOffset(margin, tableTop),
			Size = UDim2.new(1, -2 * margin, 1, -tableTop - margin),
			BackgroundColor3 = palette.Input,
			BorderSizePixel = 0,
		})
		ui:Outline(panel)
		local columns = ui:Node("Frame", {
			Name = "Columns",
			Parent = panel,
			Size = UDim2.new(1, 0, 0, headingHeight),
			BackgroundColor3 = palette.Raised,
			BorderSizePixel = 0,
		})
		local columnLabel =
			ui:Text(columns, "Command", "Command", UDim2.fromOffset(8, 0), UDim2.new(resultColumn, -16, 1, 0), true, 12)
		columnLabel.Font = Lib.StudioBold or Enum.Font.BuilderSansBold

		local api = {}
		local paint, choose, list, resultControl, resultMenu
		local function showResultFilter()
			if not resultMenu then
				resultMenu = (Apps.ContextMenu or Lib.ContextMenu).new()
				api.ResultMenu = resultMenu
				resultMenu.Iconless = true
				resultMenu.PreferredWidth = 122
				resultMenu:ApplyTheme({ Compact = true, RowHeight = 22, CornerRadius = 0 })
				for _, mode in ipairs({ "All", "Completed", "Failed" }) do
					resultMenu:Add({
						Name = mode == "All" and "All results" or mode,
						OnClick = function()
							resultFilter = mode
							resultMenu:Hide()
							resultControl.Gui.Text = mode == "All" and "Result" or mode
							list.CanvasPosition = Vector2.new(0, 0)
							choose(nil)
						end,
					})
				end
			elseif resultMenu.Shown then
				resultMenu:Hide()
				return
			end
			local anchor = resultControl.Gui.AbsolutePosition
			resultMenu:Show(anchor.X, anchor.Y + headingHeight)
		end
		resultControl = ui:Button(
			columns,
			"ResultFilter",
			"Result",
			UDim2.new(resultColumn, 0, 0, 0),
			UDim2.new(timeColumn - resultColumn, 0, 1, 0),
			showResultFilter,
			"quiet"
		)
		ui:Round(resultControl.Gui, 0)
		resultControl.Gui.TextXAlignment = Enum.TextXAlignment.Left
		resultControl.Gui.TextTruncate = Enum.TextTruncate.AtEnd
		resultControl.Gui.Font = columnLabel.Font
		resultControl.TextColor = theme.PlaceholderText
		resultControl:Paint()
		ui:Node("UIPadding", {
			Parent = resultControl.Gui,
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 20),
		})
		ui:Icon(
			columns,
			"ResultChevron",
			"chevron-down",
			UDim2.new(timeColumn, -17, 0.5, -5),
			UDim2.fromOffset(10, 10),
			theme.PlaceholderText
		)
		ui:Tip(resultControl.Gui, "Filter by result")
		local timeLabel = ui:Text(
			columns,
			"Time",
			"Time",
			UDim2.new(timeColumn, 8, 0, 0),
			UDim2.new(1 - timeColumn, -16, 1, 0),
			true,
			12
		)
		timeLabel.Font = columnLabel.Font
		for _, fraction in ipairs({ resultColumn, timeColumn }) do
			ui:Node("Frame", {
				Parent = columns,
				Position = UDim2.new(fraction, 0, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = palette.Border,
				BorderSizePixel = 0,
			})
		end
		local rule = ui:Rule(columns, "HeadingRule", headingHeight - 1)
		rule.Position = UDim2.new(0, 0, 1, -1)
		rule.Size = UDim2.new(1, 0, 0, 1)
		rule.BackgroundColor3 = palette.Border
		local countText
		ui:Tip(columnLabel, function()
			return countText
		end)

		list = ui:Node("ScrollingFrame", {
			Name = "Commands",
			Parent = panel,
			Position = UDim2.fromOffset(0, headingHeight),
			Size = UDim2.new(1, 0, 1, -headingHeight),
			CanvasSize = UDim2.fromOffset(0, 0),
			CanvasPosition = Vector2.new(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = theme.PlaceholderText,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ClipsDescendants = true,
		})
		local empty = ui:Text(list, "EmptyState", "", UDim2.fromOffset(8, 10), UDim2.new(1, -16, 0, 24), true)
		local details = ui:Node("Frame", {
			Name = "CommandDetails",
			Parent = root,
			Position = UDim2.new(0, margin, 0.58, 0),
			Size = UDim2.new(1, -2 * margin, 0.42, -margin),
			BackgroundColor3 = palette.Input,
			BorderSizePixel = 0,
			Visible = false,
		})
		ui:Outline(details)
		ui:Node("Frame", {
			Name = "DetailHeader",
			Parent = details,
			Size = UDim2.new(1, 0, 0, headingHeight),
			BackgroundColor3 = palette.Raised,
			BorderSizePixel = 0,
		})
		local divider = ui:Rule(details, "DetailsRule", headingHeight - 1)
		divider.Position = UDim2.fromOffset(0, headingHeight - 1)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.BackgroundColor3 = palette.Border
		local info =
			ui:Text(details, "Summary", "", UDim2.fromOffset(7, headingHeight + 3), UDim2.new(1, -14, 0, 17), true, 11)
		ui:Tip(info, function()
			return info.Text
		end)
		local body = ui:Node("ScrollingFrame", {
			Name = "DetailBody",
			Parent = details,
			Position = UDim2.fromOffset(7, headingHeight + 24),
			Size = UDim2.new(1, -14, 1, -headingHeight - 29),
			CanvasSize = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.PlaceholderText,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		})
		local explanation = ui:Text(body, "Explanation", "", UDim2.fromOffset(0, 0), UDim2.new(1, -6, 0, 60), false, 12)
		explanation.Font = Enum.Font.Code
		explanation.TextWrapped = true
		explanation.TextTruncate = Enum.TextTruncate.None
		explanation.TextYAlignment = Enum.TextYAlignment.Top
		local copyControl, renderDetails
		local detailButtons = {}
		for index, label in ipairs({ "Arguments", "Result", "Overview" }) do
			local control = ui:Button(
				details,
				label,
				label == "Arguments" and "Request" or label,
				UDim2.fromOffset((index - 1) * 62, 0),
				UDim2.fromOffset(62, headingHeight - 1),
				function()
					detailMode = label
					renderDetails()
				end,
				"quiet"
			)
			ui:Round(control.Gui, 0)
			ui:Node("Frame", {
				Parent = control.Gui,
				Position = UDim2.new(1, -1, 0, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = palette.Border,
				BorderSizePixel = 0,
			})
			detailButtons[label] = control
		end
		copyControl = ui:Button(
			details,
			"CopyDetails",
			"",
			UDim2.new(1, -47, 0, 0),
			UDim2.fromOffset(24, headingHeight - 1),
			function()
				if selected and type(env.setclipboard) == "function" then
					local ok = pcall(env.setclipboard, selected.Name .. "\n" .. info.Text .. "\n" .. explanation.Text)
					copyControl.Gui.Text = ok and "✓" or "!"
				end
			end,
			"quiet"
		)
		ui:Round(copyControl.Gui, 0)
		local copyIcon = ui:Icon(copyControl.Gui, "Icon", "copy", UDim2.fromOffset(6, 4), UDim2.fromOffset(13, 13))
		copyControl.Gui:GetPropertyChangedSignal("Text"):Connect(function()
			copyIcon.Visible = copyControl.Gui.Text == ""
		end)
		local close = ui:Button(
			details,
			"CloseDetails",
			"",
			UDim2.new(1, -23, 0, 0),
			UDim2.fromOffset(23, headingHeight - 1),
			function()
				choose(nil)
			end,
			"quiet"
		)
		ui:Round(close.Gui, 0)
		ui:Icon(close.Gui, "Icon", "close", UDim2.fromOffset(6, 5), UDim2.fromOffset(11, 11))
		ui:Tip(close.Gui, "Close command details")
		ui:Tip(copyControl.Gui, "Copy command details")
		local function friendly(name)
			local value = name:gsub("^dex_", ""):gsub("_", " ")
			return value:sub(1, 1):upper() .. value:sub(2)
		end
		local function duration(value)
			if not value then
				return ""
			end
			return value >= 1 and string.format("%.2f s", value) or string.format("%.0f ms", value * 1000)
		end
		local function status(entry)
			return entry.Status or (entry.Ok and "completed" or "failed")
		end
		local statusNames = { running = "Running", completed = "Completed", failed = "Failed", blocked = "Blocked" }
		local function tint(row)
			local active = row.Entry == selected
			row.Gui.BackgroundColor3 = active and palette.Selection or theme.ExplorerHover
			row.Gui.BackgroundTransparency = (active or row.Hovered) and 0 or 1
			local color = active and theme.SelectedText or theme.Text
			row.Name.TextColor3 = color
			row.Result.TextColor3 = color
			row.Time.TextColor3 = color
			row.Rule.Visible = not active
		end
		local function refreshBody()
			local columns = math.max(20, math.floor((body.AbsoluteSize.X - 12) / 7))
			local lines = 0
			for line in (explanation.Text .. "\n"):gmatch("(.-)\n") do
				lines += math.max(1, math.ceil(#line / columns))
			end
			local height = math.max(60, lines * 18)
			explanation.Size = UDim2.new(1, -6, 0, height)
			body.CanvasSize = UDim2.fromOffset(0, height)
		end
		body:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshBody)
		local function layout()
			local split = 0.59
			panel.Size = selected and UDim2.new(1, -2 * margin, split, -tableTop - margin)
				or UDim2.new(1, -2 * margin, 1, -tableTop - margin)
			details.Position = UDim2.new(0, margin, split, 1)
			details.Size = UDim2.new(1, -2 * margin, 1 - split, -margin - 1)
		end
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		renderDetails = function()
			local entry = selected
			if not entry then
				return
			end
			for mode, control in pairs(detailButtons) do
				control.TextColor = mode == detailMode and theme.SelectedText or theme.Text
				control:SetKind(mode == detailMode and "primary" or "quiet")
			end
			local state = status(entry)
			local title = friendly(entry.Name)
			info.Text = title
				.. "  ·  "
				.. statusNames[state]
				.. (entry.Duration and "  ·  " .. duration(entry.Duration) or "")
				.. (entry.TimeLabel and "  ·  " .. entry.TimeLabel or "")
			local showSummary = detailMode == "Overview"
			local bodyTop = headingHeight + (showSummary and 24 or 7)
			info.Visible = showSummary
			body.Position = UDim2.fromOffset(7, bodyTop)
			body.Size = UDim2.new(1, -14, 1, -bodyTop - 5)
			local content = {}
			if detailMode == "Arguments" then
				content[1] = entry.RequestText or "No arguments"
			elseif detailMode == "Result" then
				content[1] = entry.ResultText or entry.Error or (state == "running" and "Running…" or "No result")
			else
				if entry.Error then
					content[#content + 1] = entry.Error
				end
				if entry.RequestText then
					content[#content + 1] = "Arguments\n" .. entry.RequestText
				end
				if entry.ResultText then
					content[#content + 1] = "Result\n" .. entry.ResultText
				end
				if entry.CommandId then
					content[#content + 1] = "Command ID  " .. entry.CommandId
				end
			end
			explanation.Text = #content > 0 and table.concat(content, "\n\n")
				or (state == "running" and "Running…" or "No details")
			explanation.TextColor3 = theme.Text
			refreshBody()
			body.CanvasPosition = Vector2.new(0, 0)
			copyControl.Gui.Text = ""
			copyControl:SetEnabled(type(env.setclipboard) == "function")
		end
		choose = function(entry)
			selected = entry
			detailMode = "Overview"
			details.Visible = entry ~= nil
			layout()
			renderDetails()
			if paint then
				paint()
			end
		end
		paint = function()
			local count, painted = 0, 0
			local first = math.max(1, math.floor(list.CanvasPosition.Y / rowHeight) + 1)
			local last = first + math.max(1, math.ceil(list.AbsoluteSize.Y / rowHeight))
			for index = #entries, 1, -1 do
				local entry = entries[index]
				local name = friendly(entry.Name)
				local state = status(entry)
				if
					(
						resultFilter == "All"
						or resultFilter == "Completed" and state == "completed"
						or resultFilter == "Failed" and (state == "failed" or state == "blocked")
					)
					and (
						filter == ""
						or (entry.Name .. " " .. name .. " " .. state .. " " .. (entry.Error or ""))
							:lower()
							:find(filter, 1, true)
					)
				then
					count += 1
					if count < first or count > last then
						continue
					end
					painted += 1
					local row = rows[painted]
					if not row then
						local control = ui:Button(
							list,
							"CommandRow",
							"",
							UDim2.fromOffset(0, 0),
							UDim2.new(1, 0, 0, rowHeight),
							function() end,
							"quiet"
						)
						local gui = control.Gui
						ui:Round(gui, 0)
						row = {
							Gui = gui,
							Name = ui:Text(gui, "Name", "", UDim2.fromOffset(8, 0), UDim2.new(resultColumn, -16, 1, 0)),
							Result = ui:Text(
								gui,
								"Result",
								"",
								UDim2.new(resultColumn, 8, 0, 0),
								UDim2.new(timeColumn - resultColumn, -16, 1, 0)
							),
							Time = ui:Text(
								gui,
								"Time",
								"",
								UDim2.new(timeColumn, 8, 0, 0),
								UDim2.new(1 - timeColumn, -14, 1, 0)
							),
						}
						ui:Tip(row.Time, function()
							return row.Entry and row.Entry.Duration and duration(row.Entry.Duration) or nil
						end)
						row.Rule = ui:Node("Frame", {
							Name = "RowRule",
							Parent = gui,
							Position = UDim2.new(0, 0, 1, -1),
							Size = UDim2.new(1, 0, 0, 1),
							BackgroundColor3 = palette.Border,
							BackgroundTransparency = 0.3,
							BorderSizePixel = 0,
						})
						rows[painted] = row
						control.Paint = function()
							tint(row)
						end
						gui.Activated:Connect(function()
							if ui.Alive then
								choose(row.Entry ~= selected and row.Entry or nil)
							end
						end)
						gui.MouseEnter:Connect(function()
							row.Hovered = true
							tint(row)
						end)
						gui.MouseLeave:Connect(function()
							row.Hovered = false
							tint(row)
						end)
					end
					if row.Entry ~= entry then
						row.Hovered = false
					end
					row.Entry = entry
					row.Gui.Visible = true
					row.Gui.Position = UDim2.fromOffset(0, (count - 1) * rowHeight)
					tint(row)
					row.Name.Text = name
					row.Result.Text = statusNames[state]
					row.Time.Text = entry.TimeLabel or ""
				end
			end
			for index = painted + 1, #rows do
				rows[index].Gui.Visible = false
				rows[index].Entry = nil
				rows[index].Hovered = false
			end
			countText = #entries == 0 and ""
				or (
					count ~= #entries and string.format("%d of %d calls", count, #entries)
					or count .. (count == 1 and " call" or " calls")
				)
			empty.Visible = count == 0
			empty.Text = (filter ~= "" or resultFilter ~= "All") and "No matches" or "No activity"
			list.CanvasSize = UDim2.fromOffset(0, count * rowHeight)
		end
		query:GetPropertyChangedSignal("Text"):Connect(function()
			filter = query.Text:lower()
			list.CanvasPosition = Vector2.new(0, 0)
			choose(nil)
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		list:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
		api.Gui = root
		api.Filter = query
		api.ResultFilter = resultControl.Gui
		api.Clear = clear.Gui
		api.CloseDetails = close.Gui
		api.List = list
		api.Rows = rows
		api.Details = details
		api.CopyDetails = copyControl.Gui
		local lastCount, lastEntry, lastVersion, selectedStatus
		function api:Update(value, version)
			value = value or {}
			local count = #value
			if value == entries and count == lastCount and value[count] == lastEntry and version == lastVersion then
				return
			end
			entries = value
			lastCount = count
			lastEntry = value[count]
			lastVersion = version
			clear:SetEnabled(count > 0)
			if count == 0 then
				list.CanvasPosition = Vector2.new(0, 0)
			end
			if selected and not table.find(entries, selected) then
				choose(nil)
			else
				if selected and selectedStatus ~= status(selected) then
					selectedStatus = status(selected)
					renderDetails()
				end
				paint()
			end
		end
		function api:ClearSelection()
			choose(nil)
		end
		function api:CloseMenu()
			if resultMenu then
				resultMenu:Hide()
			end
		end
		function api:Destroy()
			if resultMenu then
				resultMenu:Destroy()
			end
			table.clear(rows)
			entries = {}
			selected = nil
			root:Destroy()
		end
		clear:SetEnabled(false)
		paint()
		return api
	end
	return View
end
return { InitDeps = InitDeps, Main = Main }
