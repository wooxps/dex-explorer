--!strict

local Main, Lib, Apps, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, service = d.Main, d.Lib, d.Apps, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Finder = {}
	local window, list, filter, status, empty, refresh, stop
	local target, worker
	local results = { Direct = {}, Scripts = {}, Stats = {} }
	local rows, flat, collapsed = {}, {}, {}
	local active = false
	local modified = true
	local elapsed = 0
	local revision = 0
	local rowIndices = {}
	local renderedScripts, renderedDirect, renderedQuery = -1, -1, nil
	local selected, focused = nil, false
	local colors = {
		Surface = Color3.fromRGB(25, 26, 31),
		Chrome = Color3.fromRGB(33, 34, 39),
		Text = Color3.fromRGB(204, 204, 204),
		Muted = Color3.fromRGB(155, 157, 165),
		Selected = Color3.fromRGB(9, 71, 113),
	}
	local function node(class, props)
		local value = Instance.new(class)
		for key, item in pairs(props) do
			value[key] = item
		end
		return value
	end
	local function escaped(text)
		return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	end
	local function tip(widget, value)
		if Lib.StudioTooltip then
			Lib.StudioTooltip(widget, value)
		end
	end
	local function asset(key)
		return Main.GetStudioAsset and Main.GetStudioAsset(key) or ""
	end
	local function label(parent, name, size)
		return node("TextLabel", {
			Parent = parent,
			Name = name,
			Text = "",
			Font = Lib.StudioFont,
			TextSize = size or 12,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local paint, rebuild, update
	function Finder.GetObjects()
		local getter = Apps.Explorer.GetNodes
		assert(type(getter) == "function", "Explorer instance registry is unavailable")
		local objects = getter()
		assert(type(objects) == "table", "Explorer instance registry has not initialized")
		return objects
	end
	function Finder.Cancel()
		if worker then
			worker = nil
			revision += 1
			results.Stats.Cancelled = true
			modified = true
		end
	end
	function Finder.Activate(item)
		if not item then
			return false
		end
		if item.Kind == "Direct" then
			local ok, value = pcall(function()
				return item.Object[item.Property]
			end)
			if not ok or value ~= target then
				status.Text = "Link changed. Refresh to search again."
				return false
			end
			if Finder.GetObjects()[item.Object] then
				Apps.Explorer.SelectService(item.Object)
				Apps.Explorer.ViewObj(item.Object)
				return true
			end
			status.Text = "Object no longer available."
			return false
		end
		Apps.ScriptViewer.OpenReferenceResult(item)
		return true
	end
	paint = function()
		if not list then
			return
		end
		local first = math.floor(list.CanvasPosition.Y / 22) + 1
		local count = math.max(1, math.ceil(list.AbsoluteSize.Y / 22) + 1)
		local stats = results.Stats or {}
		local assessed = (stats.ReadableScripts or 0) + (stats.BytecodeScripts or 0)
		empty.Visible = #flat == 0
		empty.Text = worker and "Searching..."
			or filter.Text ~= "" and "No matching results"
			or (stats.Objects or 0) == 0 and "No objects discovered.\nRefresh after Explorer finishes loading."
			or (stats.Scripts or 0) == 0 and "No scripts discovered in Explorer."
			or assessed == 0 and (stats.UnavailableScripts or 0) > 0 and "Script contents unavailable.\nOpen a script in the editor, then refresh."
			or "No matches in the data that could be read."
		for slot = 1, count do
			local record = rows[slot]
			if not record then
				local gui = node("TextButton", {
					Name = "ReferenceRow",
					Parent = list,
					Text = "",
					BackgroundColor3 = colors.Selected,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Size = UDim2.new(1, -6, 0, 22),
				})
				local arrow = node("ImageLabel", {
					Name = "Arrow",
					Parent = gui,
					Image = asset("native/editor/submenu"),
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.fromOffset(2, 3),
				})
				local title = label(gui, "Title", 13)
				title.Size = UDim2.new(1, -100, 1, 0)
				local badge = label(gui, "Evidence", 11)
				badge.Position = UDim2.new(1, -82, 0, 0)
				badge.Size = UDim2.new(0, 72, 1, 0)
				badge.TextXAlignment = Enum.TextXAlignment.Right
				badge.TextColor3 = colors.Muted
				record = { Gui = gui, Title = title, Badge = badge, Arrow = arrow }
				rows[slot] = record
				gui.MouseButton1Click:Connect(function()
					local entry = record.Entry
					if not entry then
						return
					end
					selected = entry.Key or entry.Item
					if entry.Key then
						collapsed[entry.Key] = not collapsed[entry.Key]
						rebuild()
					else
						paint()
						Finder.Activate(entry.Item)
					end
				end)
				gui.MouseEnter:Connect(function()
					gui.BackgroundTransparency = 0
				end)
				gui.MouseLeave:Connect(function()
					gui.BackgroundTransparency = record.Entry and (record.Entry.Key or record.Item) == selected and 0
						or 1
				end)
				tip(gui, function()
					local entry = record.Entry
					if not entry then
						return ""
					end
					local item = entry.Item
					local explanation = item
						and (
							item.Kind == "Direct" and "This property currently points to the selected object."
							or item.Kind == "Bytecode" and "This object's name was found in the script's compiled data. Open the script to check how it is used."
							or "This object's name appears on this line. Check the code to confirm which object it refers to."
						)
					return escaped(
						item
								and (item.Path .. (item.Line and ":" .. item.Line or item.Property and "." .. item.Property or "") .. "\n" .. explanation)
							or entry.Path
							or entry.Text
					)
				end)
			end
			local entry = flat[first + slot - 1]
			record.Entry = entry
			record.Item = entry and entry.Item
			record.Gui.Visible = entry ~= nil
			if entry then
				record.Gui.Position = UDim2.fromOffset(0, (first + slot - 2) * 22)
				record.Gui.BackgroundTransparency = (entry.Key or entry.Item) == selected and 0 or 1
				local indent = entry.Depth * 16
				record.Arrow.Visible = entry.Key ~= nil
				record.Arrow.Position = UDim2.fromOffset(2 + indent, 3)
				record.Arrow.Rotation = entry.Key and (filter.Text ~= "" or not collapsed[entry.Key]) and 90 or 0
				local badge = entry.Item and entry.Item.Kind ~= "Text"
				record.Title.Position = UDim2.fromOffset(20 + indent, 0)
				record.Title.Size = UDim2.new(1, -((badge and 94 or 28) + indent), 1, 0)
				record.Title.RichText = true
				local text = escaped(entry.Text)
				if entry.Item and entry.Item.Kind ~= "Direct" then
					local at = Apps.ReferenceScan.FindName(entry.Text, entry.Item.TargetName)
					if at then
						text = escaped(entry.Text:sub(1, at - 1))
							.. '<font color="#E8C56A">'
							.. escaped(entry.Item.TargetName)
							.. "</font>"
							.. escaped(entry.Text:sub(at + #entry.Item.TargetName))
					end
				end
				record.Title.Text = text
				record.Title.TextColor3 = (entry.Key or (entry.Key or entry.Item) == selected) and colors.Text
					or colors.Muted
				record.Title.Font = entry.Item and entry.Item.Kind ~= "Direct" and Enum.Font.Code or Lib.StudioFont
				record.Badge.Position = UDim2.new(1, -66, 0, 0)
				record.Badge.Size = UDim2.new(0, 56, 1, 0)
				record.Badge.Text = badge and (entry.Item.Kind == "Direct" and "Link" or "Name") or ""
			end
		end
		for slot = count + 1, #rows do
			rows[slot].Gui.Visible = false
			rows[slot].Entry = nil
			rows[slot].Item = nil
		end
	end
	rebuild = function()
		flat = {}
		table.clear(rowIndices)
		local query = filter.Text:lower()
		local groups = {}
		local order = {}
		local direct = {}
		local function matches(item)
			return query == ""
				or (item.Path .. " " .. (item.Property or item.Snippet or "")):lower():find(query, 1, true) ~= nil
		end
		for _, item in ipairs(results.Scripts) do
			if matches(item) then
				local group = groups[item.Object]
				if not group then
					group = { Object = item.Object, Path = item.Path, Items = {} }
					groups[item.Object] = group
					order[#order + 1] = group
				end
				group.Items[#group.Items + 1] = item
			end
		end
		for _, item in ipairs(results.Direct) do
			if matches(item) then
				direct[#direct + 1] = item
			end
		end
		local function add(entry)
			local index = #flat + 1
			flat[index] = entry
			rowIndices[entry.Key or entry.Item] = index
		end
		if #order > 0 then
			add({ Key = "Scripts", Text = "Scripts (" .. #order .. ")", Depth = 0 })
			if query ~= "" or not collapsed.Scripts then
				for _, group in ipairs(order) do
					add({
						Key = group.Object,
						Text = group.Object.Name .. " (" .. #group.Items .. ")",
						Path = group.Path,
						Depth = 1,
					})
					if query ~= "" or not collapsed[group.Object] then
						for _, item in ipairs(group.Items) do
							add({
								Item = item,
								Text = (item.Line and tostring(item.Line) .. ": " or "") .. item.Snippet,
								Depth = 2,
							})
						end
					end
				end
			end
		end
		if #direct > 0 then
			add({ Key = "Direct", Text = "Property links (" .. #direct .. ")", Depth = 0 })
			if query ~= "" or not collapsed.Direct then
				for _, item in ipairs(direct) do
					add({ Item = item, Text = item.Path .. "." .. item.Property, Depth = 1 })
				end
			end
		end
		list.CanvasSize = UDim2.fromOffset(0, #flat * 22)
		Finder.Flat = flat
		paint()
	end
	update = function()
		if not window then
			return
		end
		local stats = results.Stats or {}
		local count = #results.Scripts + #results.Direct
		status.Text = (
			worker and "Searching...  "
			or stats.Cancelled and "Stopped.  "
			or stats.Truncated and "Result limit reached.  "
			or ""
		)
			.. count
			.. (count == 1 and " match" or " matches")
		local checked = (stats.ReadableScripts or 0)
			+ (stats.BytecodeScripts or 0)
			+ (stats.UnavailableScripts or 0)
			+ (stats.LargeScripts or 0)
		status.Text = status.Text .. "  |  " .. checked .. " scripts checked"
		if worker then
			status.Text ..= "  |  " .. (stats.Objects or 0) .. " objects"
		end
		if (stats.UnavailableScripts or 0) > 0 then
			status.Text ..= " (" .. stats.UnavailableScripts .. " unavailable)"
		end
		stop.Interactable = worker ~= nil
		stop.Icon.ImageTransparency = worker and 0 or 0.65
		if renderedScripts ~= #results.Scripts or renderedDirect ~= #results.Direct or renderedQuery ~= filter.Text then
			rebuild()
			renderedScripts = #results.Scripts
			renderedDirect = #results.Direct
			renderedQuery = filter.Text
		elseif #flat == 0 then
			paint()
		end
		modified = false
	end
	local function sources()
		local result = {}
		local viewer = Apps.ScriptViewer
		for _, doc in ipairs(viewer.Documents or {}) do
			if doc.script then
				local text = doc == viewer.ActiveDocument and viewer.CodeFrame:GetText() or doc.text
				if type(text) == "string" then
					result[doc.script] = text
				end
			end
		end
		return result
	end
	function Finder.Refresh(force)
		if not target then
			return
		end
		Finder.Cancel()
		revision += 1
		local version = revision
		results = { Direct = {}, Scripts = {}, Stats = {} }
		Finder.Results = results
		elapsed = 0
		renderedScripts = -1
		renderedDirect = -1
		selected = nil
		Finder.ScanStarted = os.clock()
		if force then
			Apps.ReferenceSource.ClearBytecode()
		end
		local steps = 0
		worker = coroutine.create(function()
			Apps.ReferenceSource.BeginPass()
			local cached = sources()
			local found = Apps.ReferenceScan.Run({
				Target = target,
				Objects = Finder.GetObjects(),
				Sources = cached,
				ReadScript = function(object, check)
					return Apps.ReferenceSource.Read(object, check, function(pending)
						coroutine.yield(pending == true and "pending" or "native")
					end, nil, true)
				end,
				Checkpoint = function(current)
					results = current
					Finder.Results = current
					modified = true
					steps += 1
					if steps % 32 == 0 then
						coroutine.yield()
					end
					return revision == version and Main.Alive
				end,
			})
			results = found
			Finder.Results = found
			modified = true
		end)
		update()
	end
	local function create()
		window = Lib.Window.new()
		Finder.Window = window
		window:SetTitle("Find References")
		window.MinX = 360
		window.MinY = 180
		window:Resize(560, 350)
		if window.SetResizeHandleStyle then
			window:SetResizeHandleStyle("Dock")
		end
		local content = window.GuiElems.Content
		content.BackgroundColor3 = colors.Surface
		local bar = node("Frame", {
			Name = "Toolbar",
			Parent = content,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		filter = node("TextBox", {
			Name = "Filter",
			Parent = bar,
			Text = "",
			PlaceholderText = "Filter results",
			ClearTextOnFocus = false,
			MultiLine = false,
			Font = Lib.StudioFont,
			TextSize = 13,
			TextColor3 = colors.Text,
			PlaceholderColor3 = colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = colors.Surface,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(5, 4),
			Size = UDim2.new(1, -69, 0, 22),
		})
		node("UIPadding", { Parent = filter, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
		local function action(name, key, x, callback, description)
			local button = node("TextButton", {
				Name = name,
				Parent = bar,
				Text = "",
				Position = UDim2.new(1, x, 0, 3),
				Size = UDim2.fromOffset(26, 24),
				BackgroundColor3 = colors.Selected,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
			})
			node("ImageLabel", {
				Name = "Icon",
				Parent = button,
				Image = asset(key),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(5, 4),
				Size = UDim2.fromOffset(16, 16),
			})
			button.MouseButton1Click:Connect(callback)
			button.MouseEnter:Connect(function()
				button.BackgroundTransparency = 0
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = 1
			end)
			tip(button, description)
			return button
		end
		refresh = action("Refresh", "native/references/refresh", -58, function()
			Finder.Refresh(true)
		end, "Refresh references")
		stop = action("Stop", "native/references/stop", -30, function()
			Finder.Cancel()
			update()
		end, "Stop search")
		list = node("ScrollingFrame", {
			Name = "Results",
			Parent = content,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 1, -52),
			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollBarThickness = 5,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		})
		empty = label(list, "Empty", 13)
		empty.Position = UDim2.fromOffset(12, 10)
		empty.Size = UDim2.new(1, -24, 0, 46)
		empty.TextColor3 = colors.Muted
		empty.TextWrapped = true
		local footer = node("Frame", {
			Name = "Footer",
			Parent = content,
			Position = UDim2.new(0, 0, 1, -22),
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = colors.Chrome,
			BorderSizePixel = 0,
		})
		status = label(footer, "Status", 12)
		status.Position = UDim2.fromOffset(8, 0)
		status.Size = UDim2.new(1, -16, 1, 0)
		tip(status, function()
			local stats = results.Stats or {}
			local read = (stats.ReadableScripts or 0) + (stats.BytecodeScripts or 0)
			local lines = {
				"Read " .. read .. " scripts.",
				"Script matches contain this object's name, but might refer to a different object.",
				"Property matches point directly to this object.",
			}
			if (stats.UnreadableProperties or 0) > 0 then
				lines[#lines + 1] = stats.UnreadableProperties .. " properties could not be read."
			end
			if (stats.LargeScripts or 0) > 0 then
				lines[#lines + 1] = "Skipped " .. stats.LargeScripts .. " scripts that were too large to search."
			end
			return escaped(table.concat(lines, "\n"))
		end)
		Finder.List = list
		Finder.Rows = rows
		Finder.Filter = filter
		Finder.Status = status
		filter:GetPropertyChangedSignal("Text"):Connect(function()
			list.CanvasPosition = Vector2.new(0, 0)
			modified = true
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		Main.TrackSignal(list:GetPropertyChangedSignal("AbsoluteSize"), paint)
		Main.TrackSignal(window.OnDeactivate, function()
			focused = false
			if window.Closed then
				active = false
				Finder.Cancel()
			end
		end)
		Main.TrackSignal(window.OnMinimize, function()
			active = false
			Finder.Cancel()
		end)
		Main.TrackSignal(window.OnActivate, function()
			active = true
			focused = true
			if modified then
				update()
			end
		end)
		Main.TrackSignal(window.OnRestore, function()
			active = true
			focused = true
			update()
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if not focused or not active then
				return
			end
			local box = service.UserInputService:GetFocusedTextBox()
			if box and box ~= filter then
				return
			end
			local direction = input.KeyCode == Enum.KeyCode.Up and -1 or input.KeyCode == Enum.KeyCode.Down and 1 or 0
			if direction == 0 and input.KeyCode ~= Enum.KeyCode.Return then
				return
			end
			local index = rowIndices[selected] or 0
			if direction ~= 0 and #flat > 0 then
				index = math.clamp(index + direction, 1, #flat)
				selected = flat[index].Key or flat[index].Item
				local top = (index - 1) * 22
				if top < list.CanvasPosition.Y then
					list.CanvasPosition = Vector2.new(0, top)
				elseif top + 22 > list.CanvasPosition.Y + list.AbsoluteSize.Y then
					list.CanvasPosition = Vector2.new(0, top + 22 - list.AbsoluteSize.Y)
				end
				paint()
			elseif input.KeyCode == Enum.KeyCode.Return and flat[index] then
				local entry = flat[index]
				if entry.Key then
					collapsed[entry.Key] = not collapsed[entry.Key]
					rebuild()
				else
					Finder.Activate(entry.Item)
				end
			end
		end)
		Main.TrackSignal(service.RunService.Heartbeat, function(dt)
			if not active then
				return
			end
			if worker then
				local started = os.clock()
				local nativeCalls = 0
				repeat
					local ok, reason = coroutine.resume(worker)
					if not ok then
						worker = nil
						results.Stats.Cancelled = true
						update()
						status.Text = "Search failed: " .. tostring(reason)
						break
					end
					if coroutine.status(worker) == "dead" then
						worker = nil
						results.Stats.Seconds = os.clock() - Finder.ScanStarted
						modified = true
						break
					end
					if reason == "pending" then
						break
					end
					if reason == "native" then
						nativeCalls += 1
						if nativeCalls >= 32 then
							break
						end
					end
				until os.clock() - started >= 0.002
			end
			elapsed += dt
			if modified and (not worker or elapsed >= 0.1) then
				elapsed = 0
				update()
			end
		end)
	end
	function Finder.Open(object)
		if not object then
			return
		end
		if not window then
			create()
		end
		Finder.Cancel()
		target = object
		Finder.Target = object
		table.clear(collapsed)
		window:SetTitle("References - " .. object.Name)
		window:Show()
		active = true
		filter.Text = ""
		list.CanvasPosition = Vector2.new(0, 0)
		Finder.Refresh()
	end
	Main.AddCleanup(function()
		active = false
		Finder.Cancel()
		for _, record in ipairs(rows) do
			record.Item = nil
			record.Entry = nil
		end
		table.clear(rows)
		table.clear(flat)
		table.clear(rowIndices)
		target = nil
		Finder.Target = nil
		Finder.Results = nil
		results = { Direct = {}, Scripts = {}, Stats = {} }
	end)
	return Finder
end
return { InitDeps = InitDeps, Main = CreateModule }
