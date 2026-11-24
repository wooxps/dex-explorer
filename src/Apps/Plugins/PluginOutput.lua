--!strict

local Apps, Main, Lib, env

local function InitDeps(deps)
	Apps, Main, Lib, env = deps.Apps, deps.Main, deps.Lib, deps.env
end

local function CreateModule()
	local Output = {}
	local runtime = Apps.PluginRuntime
	local rowHeight = 24
	local severityColors = {
		Warning = Color3.fromRGB(240, 193, 102),
		Error = Color3.fromRGB(243, 141, 138),
	}
	local linkColor = Color3.fromRGB(119, 162, 255)
	local activeId, window, render

	local function openSource(id, entry)
		local plugin = runtime.Get(id)
		if not plugin or type(entry.Source) ~= "string" or type(entry.Line) ~= "number" then
			return
		end
		local editor = Apps.ScriptViewer
		local identity
		for _, document in ipairs(editor.Documents) do
			local source = if editor.ActiveDocument == document then editor.CodeFrame:GetText() else document.text
			if source == entry.Source and document.PluginOutputId == id then
				identity = document.id
				break
			end
		end
		local document = editor.OpenDocument(identity or {}, plugin.Name .. " (Plugin)", entry.Source)
		document.PluginOutputId = id
		local frame = editor.CodeFrame
		local row = math.clamp(entry.Line, 1, #frame.Lines) - 1
		frame.AdditionalSelections = {}
		frame.SelectionRange = { { 0, row }, { #(frame.Lines[row + 1] or ""), row } }
		frame:MoveCursor(0, row)
		frame.ScrollV:ScrollTo(math.max(0, (frame:SourceToDisplay(row) or row) - 2))
		frame:SetCopyableSelection()
		frame:Refresh()
		if editor.Window then
			editor.Window:Focus()
		end
	end

	local function buildWindow()
		local ui = Apps.BridgeUI.Create()
		local theme = ui.Theme
		window = Lib.Window.new()
		window.MinX = 340
		window.MinY = 280
		window:Resize(560, 365)
		window:SetResizeHandleStyle("Dock")
		Output.Window = window

		local content = window.GuiElems.Content
		content.BackgroundColor3 = theme.Menu
		local count = ui:Text(content, "EntryCount", "", UDim2.fromOffset(12, 4), UDim2.new(1, -94, 0, 32), true)
		local clear = ui:Button(content, "Clear", "Clear", UDim2.new(1, -70, 0, 8), UDim2.fromOffset(58, 24), function()
			runtime.ClearOutput(activeId)
		end)
		ui:Rule(content, "ToolbarDivider", 39)

		local list = ui:Node("ScrollingFrame", {
			Name = "Entries",
			Parent = content,
			Position = UDim2.fromOffset(8, 42),
			Size = UDim2.new(1, -16, 1, -50),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = theme.PlaceholderText,
			ClipsDescendants = true,
		})
		local empty =
			ui:Text(list, "Empty", "No output yet", UDim2.fromOffset(4, 5), UDim2.new(1, -13, 0, rowHeight), true)

		local details = ui:Node("Frame", {
			Name = "Details",
			Parent = content,
			Position = UDim2.new(0, 0, 0.58, 20),
			Size = UDim2.new(1, 0, 0.42, -20),
			BackgroundColor3 = theme.Main2,
			BorderSizePixel = 0,
			Visible = false,
		})
		ui:Node("Frame", {
			Parent = details,
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = theme.Outline2,
			BorderSizePixel = 0,
		})
		local detailTitle = ui:Text(details, "Summary", "", UDim2.fromOffset(12, 2), UDim2.new(1, -107, 0, 27))
		local detailScroll = ui:Node("ScrollingFrame", {
			Name = "Text",
			Parent = details,
			Position = UDim2.fromOffset(12, 30),
			Size = UDim2.new(1, -24, 1, -36),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = theme.PlaceholderText,
		})
		local detailText = ui:Text(detailScroll, "Message", "", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0))
		detailText.Font = Enum.Font.Code
		detailText.TextSize = 13
		detailText.TextWrapped = true
		detailText.TextTruncate = Enum.TextTruncate.None
		detailText.TextYAlignment = Enum.TextYAlignment.Top
		detailText.AutomaticSize = Enum.AutomaticSize.Y

		local selected, renderedId
		local rows = {}
		if type(env.setclipboard) == "function" then
			ui:Button(details, "Copy", "Copy", UDim2.new(1, -70, 0, 4), UDim2.fromOffset(58, 22), function()
				pcall(env.setclipboard, detailText.Text)
			end)
		end

		local function paintRow(row)
			row.Gui.BackgroundTransparency = (row.Entry == selected or row.Hover) and 0 or 1
			row.Gui.BackgroundColor3 = row.Entry == selected and theme.SelectionContext or theme.ExplorerHover
		end
		local function select(entry)
			local previous = selected
			selected = entry
			details.Visible = entry ~= nil
			list.Size = if entry then UDim2.new(1, -16, 0.58, -28) else UDim2.new(1, -16, 1, -50)
			if previous and rows[previous.Sequence] then
				paintRow(rows[previous.Sequence])
			end
			if entry then
				paintRow(rows[entry.Sequence])
				detailTitle.Text = entry.Level
				detailTitle.TextColor3 = severityColors[entry.Level] or theme.Text
				detailText.Text = if entry.Traceback and entry.Traceback ~= ""
					then entry.Message .. "\n\n" .. entry.Traceback
					else entry.Message
				detailScroll.CanvasPosition = Vector2.new(0, 0)
			end
		end

		local function addRow(entry)
			local row = { Entry = entry }
			local canOpen = entry.Line ~= nil and type(entry.Source) == "string"
			local rowFrame = ui:Node("Frame", {
				Name = "Output" .. entry.Sequence,
				Parent = list,
				Size = UDim2.new(1, -5, 0, rowHeight),
				BorderSizePixel = 0,
			})
			row.Gui = rowFrame
			paintRow(row)
			local button = ui:Node("TextButton", {
				Name = "Message",
				Parent = rowFrame,
				Size = UDim2.new(1, canOpen and -62 or 0, 1, 0),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				BorderSizePixel = 0,
				Text = "",
			})
			local time = os.date("%H:%M:%S", entry.Timestamp)
			ui:Text(button, "Time", time, UDim2.fromOffset(5, 0), UDim2.fromOffset(56, rowHeight), true, 11)
			local level =
				ui:Text(button, "Level", entry.Level, UDim2.fromOffset(63, 0), UDim2.fromOffset(55, rowHeight))
			level.TextColor3 = severityColors[entry.Level] or theme.PlaceholderText
			ui:Text(
				button,
				"Text",
				entry.Message:gsub("[\r\n]+", " "),
				UDim2.fromOffset(120, 0),
				UDim2.new(1, -124, 1, 0)
			)
			button.MouseEnter:Connect(function()
				row.Hover = true
				paintRow(row)
			end)
			button.MouseLeave:Connect(function()
				row.Hover = false
				paintRow(row)
			end)
			button.Activated:Connect(function()
				select(if entry == selected then nil else entry)
			end)
			if canOpen then
				local link = ui:Button(
					rowFrame,
					"Source",
					"Line " .. entry.Line,
					UDim2.new(1, -62, 0, 1),
					UDim2.fromOffset(60, rowHeight - 2),
					function()
						openSource(activeId, entry)
					end,
					"quiet"
				)
				link.TextColor = linkColor
				link:Paint()
			end
			return row
		end

		render = function()
			local plugin = runtime.Get(activeId)
			local entries = if plugin then runtime.GetOutput(activeId) else {}
			local newHeight = #entries * rowHeight
			local oldHeight = list.CanvasSize.Y.Offset
			local follow = renderedId ~= activeId
				or list.CanvasPosition.Y + list.AbsoluteSize.Y >= oldHeight - rowHeight
			if renderedId ~= activeId then
				select(nil)
				for sequence, row in pairs(rows) do
					row.Gui:Destroy()
					rows[sequence] = nil
				end
			end
			renderedId = activeId
			count.Text = ("%d %s"):format(#entries, #entries == 1 and "entry" or "entries")
			empty.Text = if plugin then "No output yet" else "Plugin was uninstalled"
			empty.Visible = #entries == 0
			clear:SetEnabled(#entries > 0)

			local seen = {}
			for index, entry in ipairs(entries) do
				local row = rows[entry.Sequence] or addRow(entry)
				rows[entry.Sequence], seen[entry.Sequence] = row, true
				row.Gui.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
			end
			if selected and not seen[selected.Sequence] then
				select(nil)
			end
			for sequence, row in pairs(rows) do
				if not seen[sequence] then
					row.Gui:Destroy()
					rows[sequence] = nil
				end
			end
			list.CanvasSize = UDim2.fromOffset(0, newHeight)
			if follow then
				list.CanvasPosition = Vector2.new(0, math.max(0, newHeight - list.AbsoluteSize.Y))
			end
		end

		local queued = false
		local connection = runtime.OutputChanged:Connect(function(id)
			if id == activeId and not queued and window:IsContentVisible() then
				queued = true
				task.defer(function()
					queued = false
					if Main.Alive and window:IsContentVisible() then
						render()
					end
				end)
			end
		end)
		window.OnRestore:Connect(render)
		Main.AddCleanup(function()
			connection:Disconnect()
			ui:Destroy()
			window:Destroy()
		end)
	end

	function Output.Open(id)
		local plugin = runtime.Get(id)
		if not plugin then
			return
		end
		if not window then
			buildWindow()
		end
		activeId = id
		window:SetTitle(plugin.Name .. " - Plugin Output")
		window:Show()
		window:Focus()
		render()
	end

	return Output
end

return { InitDeps = InitDeps, Main = CreateModule }
