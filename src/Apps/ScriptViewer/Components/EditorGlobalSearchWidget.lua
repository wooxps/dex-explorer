--!strict

local Main, Lib, Apps, Settings, service, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, Settings, service, createSimple = d.Main, d.Lib, d.Apps, d.Settings, d.service, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Widget = {}
	function Widget.Attach(parent, callbacks)
		local theme = Settings.Theme
		local view = {
			Height = 260,
			Visible = false,
			Options = {
				MatchCase = false,
				WholeWord = false,
				Regex = false,
				Scope = "Game",
			},
		}
		local closed = false
		local confirm = false
		local ticket = 0
		local replacing = false
		local collapsed = {}
		local groupStarts = {}
		local rowCount = 0
		local pool = {}
		local selected
		local filtering = false
		local topologyVersion = 0
		local flatSignature
		view.RenderStats = { RowWidgets = 0, FlatRebuilds = 0 }
		local light = theme.IconTheme == "Light"
		local mutedHex = light and "#696A6D" or "#BBBCBE"
		local primary = Color3.fromRGB(60, 100, 250)
		local textColor = light and Color3.fromRGB(17, 18, 22) or Color3.fromRGB(249, 249, 249)
		local muted = light and Color3.fromRGB(105, 106, 109) or Color3.fromRGB(187, 188, 190)
		local contentDefault = light and Color3.fromRGB(73, 77, 90) or Color3.fromRGB(213, 215, 221)
		local emphasis = light and Color3.fromRGB(32, 34, 39) or Color3.fromRGB(247, 247, 248)
		local surface = light and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(31, 32, 36)
		local inputFill = light and Color3.fromRGB(51, 59, 76) or Color3.fromRGB(187, 194, 209)
		local inputAlpha = light and 0.92 or 0.88
		local shift300 = light and Color3.fromRGB(27, 37, 75) or Color3.fromRGB(208, 217, 251)
		local outline = light and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		local outlineAlpha = light and 0.85 or 0.88
		local function asset(name)
			if not Main.GetStudioAsset then
				return nil
			end
			return light and Main.GetStudioAsset("native/find-all-light/" .. name)
				or Main.GetStudioAsset("native/find-all/" .. name)
		end
		local state = { Groups = {}, MatchCount = 0 }
		local paint, layout, search, list
		local function make(class, props)
			return createSimple(class, props)
		end
		local root = make("Frame", {
			Name = "FindAll",
			Parent = parent,
			Visible = false,
			BorderSizePixel = 0,
			BackgroundColor3 = surface,
			ClipsDescendants = true,
		})
		view.Frame = root
		local function label(p, text, x, y, w, h)
			local item = make("TextLabel", {
				Parent = p,
				Text = text,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.new(0, w, 0, h),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Lib.StudioText(item)
			item.TextSize = 15.12
			item.TextColor3 = textColor
			return item
		end
		local function button(p, text, tip, icon, fn)
			local b = make("TextButton", {
				Parent = p,
				Text = text,
				Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = inputFill,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
			})
			Lib.StudioText(b)
			b.TextSize = 15.12
			b.TextColor3 = textColor
			if icon then
				local image = icon:sub(1, 16) == "native/find-all/" and asset(icon:sub(17))
					or Main.GetStudioAsset and Main.GetStudioAsset(icon)
				if image then
					b.Text = ""
					make("ImageLabel", {
						Parent = b,
						BackgroundTransparency = 1,
						Image = image,
						Position = UDim2.fromOffset(6, 6),
						Size = UDim2.fromOffset(16, 16),
					})
				end
			end
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = b:GetAttribute("Selected")
						and (b:GetAttribute("SelectedHoverTransparency") or b:GetAttribute("SelectionTransparency") or 0)
					or (b:GetAttribute("HoverTransparency") or 0.92)
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = b:GetAttribute("Selected") and (b:GetAttribute("SelectionTransparency") or 0)
					or (b:GetAttribute("RestTransparency") or 1)
			end)
			b.MouseButton1Click:Connect(fn)
			if tip then
				Lib.StudioTooltip(b, tip)
			end
			return b
		end
		local function input(placeholder)
			local field = make("TextBox", {
				Parent = root,
				Text = "",
				PlaceholderText = placeholder,
				ClearTextOnFocus = false,
				MultiLine = false,
				BackgroundColor3 = theme.TextBox,
				BorderSizePixel = 0,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Lib.StudioText(field)
			field.TextSize = 15.12
			field.TextColor3 = muted
			field.PlaceholderColor3 = muted
			field.BackgroundColor3 = inputFill
			field.BackgroundTransparency = inputAlpha
			make("UICorner", { Parent = field, CornerRadius = UDim.new(0, 6) })
			make("UIPadding", { Parent = field, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
			local stroke = make("UIStroke", {
				Parent = field,
				Color = outline,
				Transparency = outlineAlpha,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			})
			field.Focused:Connect(function()
				stroke.Color = primary
				stroke.Transparency = 0
			end)
			field.FocusLost:Connect(function()
				stroke.Color = outline
				stroke.Transparency = outlineAlpha
			end)
			return field
		end
		local find = input("Find in Place")
		local replacement = input("Replace")
		local filter = input("Where")
		filter.Visible = false
		view.Find = find
		view.Replace = replacement
		view.Filter = filter
		make("ImageLabel", {
			Parent = root,
			BackgroundTransparency = 1,
			Image = asset("FindBarSearchIcon") or "",
			Position = UDim2.fromOffset(13, 14),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = find.ZIndex + 1,
		})
		find:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 26)
		local clear = button(root, "×", "Clear", "native/find-all/ClearInput", function()
			find.Text = ""
			find:CaptureFocus()
		end)
		local liveSearch = true
		local settingsMenu
		local settingsButton = button(root, "···", "Search settings", "native/find-all/ThreeDots", function()
			local menu = settingsMenu or Apps.ContextMenu.new()
			settingsMenu = menu
			menu:Clear()
			menu:Add({
				Name = "Where to find",
				OnClick = function()
					filtering = not filtering
					if not filtering then
						filter.Text = ""
					end
					layout()
				end,
			})
			menu:Add({
				Name = "Replace",
				OnClick = function()
					replacing = not replacing
					confirm = false
					layout()
				end,
			})
			if state.BytecodePaused then
				menu:Add({
					Name = "Resume bytecode scan",
					OnClick = function()
						search(false, false, true)
					end,
				})
			end
			menu:Add({
				Name = "Search loaded function constants",
				OnClick = function()
					search(false, true)
				end,
			})
			menu:Add({
				Name = "Decompile uncached scripts",
				OnClick = function()
					search(true)
				end,
			})
			menu:Add({
				Name = liveSearch and "Turn off Find as you type" or "Turn on Find as you type",
				OnClick = function()
					liveSearch = not liveSearch
					if liveSearch then
						search()
					else
						ticket += 1
					end
				end,
			})
			for _, item in ipairs({
				{ "Game", "Game scripts" },
				{ "Open", "Open scripts" },
				{ "Selection", "Selection" },
			}) do
				local name = (view.Options.Scope == item[1] and "✓  " or "") .. item[2]
				menu:Add({
					Name = name,
					OnClick = function()
						view.Options.Scope = item[1]
						search()
					end,
				})
			end
			menu:Show(Main.Mouse.X, Main.Mouse.Y)
		end)
		settingsButton:SetAttribute("RestTransparency", inputAlpha)
		settingsButton.BackgroundTransparency = inputAlpha
		make("UICorner", { Parent = settingsButton, CornerRadius = UDim.new(0, 6) })
		local options = {}
		for i, data in ipairs({
			{ "MatchCase", "Aa", "Match case", "MatchCase" },
			{ "WholeWord", "Ab", "Match whole word", "MatchWholeWord" },
			{ "Regex", ".*", "Regular expression", "RegularExpression" },
		}) do
			local key = data[1]
			local b
			b = button(root, data[2], data[3], "native/find-all/" .. data[4], function()
				view.Options[key] = not view.Options[key]
				b:SetAttribute("Selected", view.Options[key])
				b.BackgroundTransparency = view.Options[key] and 0.76 or 0.92
				search()
			end)
			b:SetAttribute("SelectionTransparency", 0.76)
			b:SetAttribute("HoverTransparency", 0.92)
			local image = b:FindFirstChildOfClass("ImageLabel")
			if image then
				image.ImageTransparency = 0
			end
			options[i] = b
		end
		local cancel = button(root, "Cancel", "Cancel search", nil, function()
			ticket += 1
			callbacks.OnCancel()
		end)
		cancel.Size = UDim2.fromOffset(64, 28)
		cancel.Visible = false
		local summary = label(root, "", 8, 0, 300, 26)
		Lib.StudioTooltip(summary, function()
			local scope = state.Options and state.Options.Scope
			local detail = string.format(
				"%d source · %d compiled · %d runtime · %d pending · %d unavailable",
				state.SourceChecked or 0,
				state.CompiledChecked or 0,
				state.RuntimeChecked or 0,
				state.Pending or 0,
				state.Unavailable or 0
			)
			if state.Truncated then
				detail ..= " · Result limit reached"
			end
			if state.RuntimeLimited then
				detail ..= " · Runtime limit reached"
			end
			if (state.RuntimeMatches or 0) > 0 then
				detail ..= string.format(" · %d runtime hits", state.RuntimeMatches)
			end
			if state.CatalogScripts then
				detail ..= string.format("\n%d scripts in catalog", state.CatalogScripts)
			end
			if state.CatalogFull then
				detail ..= " · Catalog limit reached"
			end
			if state.MaxReadMs then
				detail ..= string.format(
					"\n%d native reads · slowest %.1f ms",
					state.NativeReads or 0,
					state.MaxReadMs
				)
			end
			return summary.Text .. "\n" .. (scope == "Game" and "Game scripts\n" or "") .. detail
		end)
		local function resultsCurrent()
			return state.Query == find.Text and (state.Options and state.Options.PathFilter or "") == filter.Text
		end
		local function canReplace()
			return resultsCurrent() and not state.Searching and (view.VisibleMatchCount or 0) > 0
		end
		local function canReplaceAll()
			return canReplace() and not (state.Truncated or state.Cancelled or state.Error)
		end
		local function rowAt(index: number)
			if index < 1 or index > rowCount then
				return nil
			end
			local low, high = 1, #groupStarts
			while low < high do
				local mid = (low + high + 1) // 2
				if groupStarts[mid] <= index then
					low = mid
				else
					high = mid - 1
				end
			end
			local group = view.VisibleGroups[low]
			local offset = index - groupStarts[low]
			return { Group = group, Match = group.Matches[offset], Index = index, Offset = offset }
		end
		local function navigate(direction)
			if not resultsCurrent() then
				return
			end
			local at = selected and selected.Index or (direction > 0 and 0 or rowCount + 1)
			for step = 1, rowCount do
				local index = (at - 1 + direction * step) % rowCount + 1
				local row = rowAt(index)
				if not row.Match and collapsed[row.Group] and #row.Group.Matches > 0 then
					collapsed[row.Group] = nil
					topologyVersion += 1
					view:Update(state)
					index += direction > 0 and 1 or #row.Group.Matches
					row = rowAt(index)
				end
				if row.Match then
					selected = row
					local top = (index - 1) * 24
					local height = list.AbsoluteSize.Y
					local scroll = list.CanvasPosition.Y
					if top < scroll then
						list.CanvasPosition = Vector2.new(0, top)
					elseif top + 24 > scroll + height then
						list.CanvasPosition = Vector2.new(0, math.max(0, top + 24 - height))
					end
					callbacks.OnNavigate(row.Group, row.Match)
					layout()
					return
				end
			end
		end
		local previous = button(root, "↑", "Previous result", "native/find-all/ArrowUp", function()
			navigate(-1)
		end)
		local nextButton = button(root, "↓", "Next result", "native/find-all/ArrowDown", function()
			navigate(1)
		end)
		local replace = button(root, "Replace", "Replace selected result", nil, function()
			if canReplace() and selected and selected.Match then
				callbacks.OnReplace(selected.Group, selected.Match, replacement.Text)
			end
		end)
		replace.Size = UDim2.fromOffset(70, 28)
		local confirmation
		local replaceAll = button(root, "Replace All", "Replace all matches in editor buffers", nil, function()
			if canReplaceAll() then
				confirm = true
				layout()
			end
		end)
		replaceAll.Size = UDim2.fromOffset(86, 28)
		confirmation = make("Frame", {
			Name = "ReplaceAllConfirmation",
			Parent = root,
			Visible = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 28),
		})
		local confirmLabel = label(confirmation, "Replace all matches in editor buffers?", 8, 0, 210, 28)
		confirmLabel.Size = UDim2.new(1, -108, 0, 28)
		confirmLabel.TextSize = 12
		Lib.StudioTooltip(
			confirmLabel,
			"Replace all displayed matches in editor buffers? Each document can be undone separately."
		)
		local yes = button(confirmation, "Yes", "Replace all", nil, function()
			if confirm and canReplaceAll() then
				confirm = false
				callbacks.OnReplaceAll(replacement.Text, view.VisibleGroups)
			end
			confirm = false
			layout()
		end)
		yes.Size = UDim2.fromOffset(42, 28)
		yes.Position = UDim2.new(1, -92, 0, 0)
		local no = button(confirmation, "No", "Cancel replacement", nil, function()
			confirm = false
			layout()
		end)
		no.Size = UDim2.fromOffset(42, 28)
		no.Position = UDim2.new(1, -46, 0, 0)
		list = make("ScrollingFrame", {
			Parent = root,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 10,
			ScrollBarImageColor3 = shift300,
			ScrollBarImageTransparency = 0.88,
			TopImage = asset("TopImage") or "",
			MidImage = asset("MidImage") or "",
			BottomImage = asset("BottomImage") or "",
			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.fromOffset(0, 0),
			ClipsDescendants = true,
		})
		view.List = list
		local function escape(s)
			return tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
		end
		paint = function()
			if closed or not view.Visible then
				return
			end
			local first = math.floor(list.CanvasPosition.Y / 24) + 1
			local count = math.ceil(list.AbsoluteSize.Y / 24) + 2
			for slot = 1, count do
				local row = rowAt(first + slot - 1)
				local entry = pool[slot]
				if not entry then
					local b = button(list, "", nil, nil, function()
						local item = pool[slot].Row
						if not item or not resultsCurrent() then
							return
						end
						if item.Match then
							selected = item
							callbacks.OnNavigate(item.Group, item.Match)
							if view.Visible and not closed then
								find:CaptureFocus()
							end
							layout()
						else
							collapsed[item.Group] = not collapsed[item.Group]
							topologyVersion += 1
							view:Update(state)
						end
					end)
					b:SetAttribute("SelectionTransparency", 0.76)
					b:SetAttribute("HoverTransparency", 0.92)
					b.TextColor3 = contentDefault
					b.TextXAlignment = Enum.TextXAlignment.Left
					b.RichText = true
					b.TextTruncate = Enum.TextTruncate.AtEnd
					local arrow = make("ImageLabel", {
						Parent = b,
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(4, 6),
						Size = UDim2.fromOffset(12, 12),
					})
					local icon = make("ImageLabel", {
						Parent = b,
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(20, 4),
						Size = UDim2.fromOffset(16, 16),
					})
					local pill = make("TextLabel", {
						Parent = b,
						BackgroundColor3 = shift300,
						BackgroundTransparency = 0.88,
						BorderSizePixel = 0,
						Position = UDim2.new(1, -24, 0, 3),
						Size = UDim2.fromOffset(22, 18),
						TextColor3 = emphasis,
						TextSize = 12,
						Font = Enum.Font.BuilderSans,
					})
					make("UICorner", { Parent = pill, CornerRadius = UDim.new(0, 9) })
					local rowText = label(b, "", 0, 0, 0, 24)
					rowText.RichText = true
					rowText.TextSize = 14
					rowText.TextColor3 = contentDefault
					entry = { Button = b, Arrow = arrow, Icon = icon, Pill = pill, Text = rowText }
					pool[slot] = entry
					view.RenderStats.RowWidgets += 1
				end
				entry.Row = row
				local b = entry.Button
				b.Visible = row ~= nil
				if row then
					b.Position = UDim2.fromOffset(0, (first + slot - 2) * 24)
					b.Size = UDim2.new(1, -12, 0, 24)
					b:SetAttribute(
						"Selected",
						selected and selected.Group == row.Group and selected.Match == row.Match or false
					)
					b.BackgroundColor3 = b:GetAttribute("Selected") and primary or inputFill
					b.BackgroundTransparency = b:GetAttribute("Selected") and 0.76 or 1
					entry.Arrow.Visible = row.Match == nil
					entry.Icon.Visible = row.Match == nil
					entry.Pill.Visible = row.Match == nil
					if row.Match then
						local match = row.Match
						local snippet = match.Text or ""
						local col = match.SnippetColumn or match.Column or 1
						local length = math.max(0, match.Finish - match.Start)
						local ending = math.min(#snippet, col + length - 1)
						entry.Text.Position = UDim2.fromOffset(40, 0)
						entry.Text.Size = UDim2.new(1, -44, 0, 24)
						entry.Text.Text = '<font color="'
							.. mutedHex
							.. '">'
							.. (match.Line and tostring(match.Line) or row.Group.Runtime and "Runtime" or "Compiled")
							.. "</font>  "
							.. escape(snippet:sub(1, col - 1))
							.. '<font color="'
							.. (light and "#473200" or "#F9DE6F")
							.. '">'
							.. escape(snippet:sub(col, ending))
							.. "</font>"
							.. escape(snippet:sub(ending + 1))
					else
						entry.Arrow.Image = asset(collapsed[row.Group] and "ExpandArrow" or "CollapseArrow") or ""
						local class = row.Group.Object and row.Group.Object.ClassName or "Script"
						entry.Icon.Image = asset(class .. "Icon") or asset("ScriptIcon") or ""
						entry.Pill.Text = tostring(#row.Group.Matches)
						entry.Text.Position = UDim2.fromOffset(42, 0)
						entry.Text.Size = UDim2.new(1, -70, 0, 24)
						entry.Text.Text = escape(row.Group.Path or row.Group.Name)
					end
				end
			end
			for slot = count + 1, #pool do
				pool[slot].Button.Visible = false
				pool[slot].Row = nil
			end
		end
		layout = function()
			if closed then
				return
			end
			local y = 8
			find.Position = UDim2.fromOffset(8, y)
			find.Size = UDim2.new(1, -52, 0, 28)
			find:FindFirstChildOfClass("UIPadding").PaddingRight = UDim.new(0, 112)
			clear.Position = UDim2.new(1, -164, 0, y)
			clear.Visible = find.Text ~= ""
			for i, b in ipairs(options) do
				b.Position = UDim2.new(1, -136 + (i - 1) * 28, 0, y)
			end
			settingsButton.Position = UDim2.new(1, -36, 0, y)
			y += 32
			filter.Visible = filtering
			if filtering then
				filter.Position = UDim2.fromOffset(8, y)
				filter.Size = UDim2.new(1, -16, 0, 28)
				y += 32
			end
			replacement.Visible = replacing
			if replacing then
				replacement.Position = UDim2.fromOffset(8, y)
				replacement.Size = UDim2.new(1, -16, 0, 28)
				y += 32
			end
			summary.Position = UDim2.fromOffset(8, y)
			summary.Size = UDim2.fromOffset(114, 24)
			summary.TextSize = 12
			local navX = 8 + math.min(114, math.ceil(summary.TextBounds.X)) + 8
			previous.Position = UDim2.fromOffset(navX, y - 2)
			nextButton.Position = UDim2.fromOffset(navX + 26, y - 2)
			for _, control in ipairs({ previous, nextButton }) do
				local glyph = control:FindFirstChildOfClass("ImageLabel")
				if glyph then
					glyph.ImageTransparency = (state.MatchCount or 0) > 0 and 0 or 0.6
				end
			end
			local available = canReplace()
			replace.Interactable = available and selected ~= nil and not selected.Group.Compiled
			replaceAll.Interactable = canReplaceAll()
			replace.Position = UDim2.new(1, -160, 0, y)
			replaceAll.Position = UDim2.new(1, -88, 0, y)
			cancel.Position = UDim2.new(1, replacing and -224 or -68, 0, y)
			cancel.Visible = state.Searching == true and not confirm
			confirmation.Visible = confirm
			confirmation.Position = UDim2.fromOffset(0, y)
			summary.Visible = not confirm
			previous.Visible = not confirm and not state.Searching
			nextButton.Visible = not confirm and not state.Searching
			replace.Visible = replacing and not confirm
			replaceAll.Visible = replacing and not confirm
			list.Position = UDim2.fromOffset(0, y + 24)
			list.Size = UDim2.new(1, 0, 1, -y - 24)
			paint()
		end
		search = function(includeUncached, includeRuntime, resume)
			ticket += 1
			confirm = false
			local opts = table.clone(view.Options)
			opts.IncludeRuntime = includeRuntime == true
			opts.IncludeDecompiled = includeUncached == true
			opts.IncludeCompiled = not opts.IncludeDecompiled and opts.Scope ~= "Open"
			opts.CachedCompiledOnly = not resume
			opts.ExcludePlatform = true
			opts.PathFilter = filter.Text
			callbacks.OnSearch(find.Text, opts)
		end
		find.FocusLost:Connect(function(enter)
			if enter then
				if
					resultsCurrent()
					and state.Options
					and (state.Options.IncludeRuntime or not state.Options.CachedCompiledOnly)
					and rowCount > 0
				then
					navigate(1)
				else
					search(false, false, not state.BytecodePaused)
				end
				if view.Visible and not closed then
					find:CaptureFocus()
				end
			end
		end)
		replacement.FocusLost:Connect(function(enter)
			if enter then
				navigate(1)
				if view.Visible and not closed then
					replacement:CaptureFocus()
				end
			end
		end)
		find:GetPropertyChangedSignal("Text"):Connect(function()
			confirm = false
			layout()
			ticket += 1
			local mine = ticket
			local normalized = find.Text:gsub("[\r\n]", "")
			if normalized ~= find.Text then
				find.Text = normalized
				return
			end
			task.delay(0.1, function()
				if liveSearch and not closed and view.Visible and mine == ticket then
					search()
				end
			end)
		end)
		replacement:GetPropertyChangedSignal("Text"):Connect(function()
			local normalized = replacement.Text:gsub("[\r\n]", "")
			if normalized ~= replacement.Text then
				replacement.Text = normalized
			end
			if confirm then
				confirm = false
				layout()
			end
		end)
		filter:GetPropertyChangedSignal("Text"):Connect(function()
			confirm = false
			layout()
			ticket += 1
			local mine = ticket
			task.delay(0.1, function()
				if liveSearch and not closed and view.Visible and mine == ticket then
					search()
				end
			end)
		end)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		function view:Update(value)
			if closed then
				return
			end
			if state ~= value then
				confirm = false
				table.clear(collapsed)
				selected = nil
				flatSignature = nil
				list.CanvasPosition = Vector2.new(0, 0)
			end
			state = value
			local signature = tostring(#(value.Groups or {}))
				.. ":"
				.. tostring(value.MatchCount)
				.. ":"
				.. filter.Text
				.. ":"
				.. topologyVersion
				.. ":"
				.. tostring(value.Searching)
				.. ":"
				.. tostring(value.ResultRevision or 0)
			if flatSignature ~= signature then
				flatSignature = signature
				table.clear(groupStarts)
				rowCount = 0
				view.VisibleGroups = {}
				view.VisibleMatchCount = 0
				view.RenderStats.FlatRebuilds += 1
				local hasSelected = false
				local pathFilter = string.lower(filter.Text)
				for _, group in value.Groups or {} do
					if pathFilter ~= "" and not string.find(string.lower(tostring(group.Path or group.Name)), pathFilter, 1, true) then
						continue
					end
					local header = rowCount + 1
					local count = #group.Matches
					table.insert(view.VisibleGroups, group)
					table.insert(groupStarts, header)
					view.VisibleMatchCount += count
					rowCount = if collapsed[group] then header else header + count
					if selected and selected.Group == group and not collapsed[group] then
						local offset = selected.Offset
						if group.Matches[offset] ~= selected.Match then
							offset = table.find(group.Matches, selected.Match)
						end
						if offset then
							selected.Offset = offset
							selected.Index = header + offset
							hasSelected = true
						end
					end
				end
				if not hasSelected then
					selected = nil
				end
				list.CanvasSize = UDim2.fromOffset(0, rowCount * 24)
			end
			if value.Error then
				summary.Text = value.Error
			elseif value.Searching then
				summary.Text = value.TotalScripts
						and string.format("%d / %d checked", value.Scanned or 0, value.TotalScripts)
					or "Searching…"
			elseif value.Cancelled then
				summary.Text = "Search cancelled"
			elseif value.BytecodePaused then
				summary.Text = "Bytecode paused"
			else
				summary.Text = (view.VisibleMatchCount or 0)
					.. " results in "
					.. #(view.VisibleGroups or {})
					.. " files"
			end
			summary.TextColor3 = value.Error and (light and Color3.fromRGB(217, 28, 21) or Color3.fromRGB(240, 68, 51))
				or muted
			layout()
		end
		function view:Open(showReplace, selection)
			self.Visible = true
			root.Visible = true
			replacing = showReplace == true
			if type(selection) == "string" and selection ~= "" and not selection:find("[\r\n]") then
				find.Text = selection
			end
			if callbacks.OnLayout then
				callbacks.OnLayout()
			end
			layout()
			find:CaptureFocus()
		end
		function view:Close()
			ticket += 1
			confirm = false
			callbacks.OnCancel()
			self.Visible = false
			root.Visible = false
			local focused = service.UserInputService:GetFocusedTextBox()
			if focused == find or focused == replacement or focused == filter then
				focused:ReleaseFocus()
			end
			if callbacks.OnClose then
				callbacks.OnClose()
			end
			if callbacks.OnLayout then
				callbacks.OnLayout()
			end
		end
		function view:GetHeight()
			return self.Visible and self.Height or 0
		end
		function view:Refresh()
			search()
		end
		function view:Next(backward)
			navigate(backward and -1 or 1)
		end
		Main.AddCleanup(function()
			view:Destroy()
		end)
		function view:Destroy()
			if closed then
				return
			end
			closed = true
			ticket += 1
			callbacks.OnCancel()
			if settingsMenu then
				settingsMenu:Hide()
			end
			root:Destroy()
		end
		view:Update(state)
		return view
	end
	return Widget
end
return { InitDeps = InitDeps, Main = CreateModule }
