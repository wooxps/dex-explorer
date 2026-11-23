--!strict

local Settings, Apps, Main, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Settings, Apps, Main, service = d.Settings, d.Apps, d.Main, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local View = {}
	local geometryLimit = 256
	local function measured(self, text)
		local cache = self.GlyphWidths
		if not cache or self.GeometryFontSize ~= self.FontSize then
			cache = {}
			self.GlyphWidths = cache
			self.GeometryFontSize = self.FontSize
			self.LineGeometryCache = {}
			self.LineGeometryOrder = {}
			self.LineGeometrySlot = 1
			self.GlyphWidthCount = 0
			self.AsciiWidths = {}
		end
		local width = cache[text]
		if width == nil then
			local ok, size = pcall(function()
				return service.TextService:GetTextSize(
					text,
					self.FontSize,
					Enum.Font.Code,
					Vector2.new(1000000, self.FontSize * 2)
				)
			end)
			width = ok and size.X or math.ceil(self.FontSize / 2)
			if self.GlyphWidthCount >= 2048 then
				table.clear(cache)
				self.GlyphWidthCount = 0
			end
			cache[text] = width
			self.GlyphWidthCount += 1
		end
		return width
	end
	function View.ColumnWidth(self)
		return math.max(1, measured(self, "M"))
	end
	function View.LineGeometry(self, row)
		measured(self, "")
		local text = self.Lines[row + 1] or ""
		local cached = self.LineGeometryCache[text]
		if cached then
			return cached
		end
		local geometry = { Bytes = { 0 }, Pixels = { 0 }, Text = text, Width = 0 }
		local bytes, pixels = geometry.Bytes, geometry.Pixels
		local position = 1
		local function append(first, last)
			geometry.Width += measured(self, text:sub(first, last))
			bytes[#bytes + 1] = last
			pixels[#pixels + 1] = geometry.Width
		end
		if not text:find("[^ -~]") then
			local ascii = self.AsciiWidths
			bytes = table.create(#text + 1)
			pixels = table.create(#text + 1)
			bytes[1], pixels[1] = 0, 0
			local width = 0
			for i = 1, #text do
				local byte = text:byte(i)
				local advance = ascii[byte]
				if advance == nil then
					advance = measured(self, string.char(byte))
					ascii[byte] = advance
				end
				width += advance
				bytes[i+1], pixels[i+1] = i, width
			end
			geometry.Bytes, geometry.Pixels, geometry.Width = bytes, pixels, width
			position = #text + 1
		elseif utf8.graphemes then
			local valid = pcall(function()
				for first, last in utf8.graphemes(text) do
					append(first, last)
				end
			end)
			if not valid then
				geometry = { Bytes = { 0 }, Pixels = { 0 }, Text = text, Width = 0 }
				bytes, pixels = geometry.Bytes, geometry.Pixels
			end
			if valid then
				position = #text + 1
			end
		end
		while position <= #text do
			local first = position
			local lead = text:byte(position)
			local count = lead < 128 and 1 or lead < 224 and 2 or lead < 240 and 3 or 4
			position = math.min(#text + 1, position + count)
			append(first, position - 1)
		end
		self.LineGeometryCache[text] = geometry
		local order = self.LineGeometryOrder
		local slot = self.LineGeometrySlot
		local evicted = order[slot]
		if evicted then self.LineGeometryCache[evicted] = nil end
		order[slot] = text
		self.LineGeometrySlot = slot % geometryLimit + 1
		return geometry
	end
	local function floorIndex(values, value)
		local first, last = 1, #values
		while first < last do
			local middle = math.ceil((first + last) / 2)
			if values[middle] <= value then
				first = middle
			else
				last = middle - 1
			end
		end
		return first
	end
	function View.GetColumnPixelX(self, column, row)
		local geometry = View.LineGeometry(self, row)
		return geometry.Pixels[floorIndex(geometry.Bytes, math.clamp(column, 0, #geometry.Text))]
	end
	function View.GetPixelColumn(self, pixel, row)
		local geometry = View.LineGeometry(self, row)
		local pixels = geometry.Pixels
		local index = floorIndex(pixels, math.max(0, pixel))
		if index < #pixels and pixel - pixels[index] > (pixels[index + 1] - pixels[index]) / 2 then
			index += 1
		end
		return geometry.Bytes[index]
	end
	function View.ScrollPixelX(self)
		return math.round(self.ViewX * View.ColumnWidth(self))
	end
	function View.ScreenToEditorPoint(self, x, y, glyph)
		local lines = self.GuiElems.LinesFrame or self.Frame.Lines or self.Frame
		local display = self.ViewY + math.floor((y - lines.AbsolutePosition.Y) / self.FontSize)
		local pixel = x - lines.AbsolutePosition.X + View.ScrollPixelX(self)
		if glyph then
			local source = View.Model(self).display[display + 1]
			if not source then
				return nil
			end
			local row = source - 1
			local geometry = View.LineGeometry(self, row)
			if pixel < 0 or pixel >= geometry.Width then
				return nil
			end
			return geometry.Bytes[floorIndex(geometry.Pixels, pixel)], row
		end
		local row = View.DisplayToSource(self, math.max(0, display))
		row = math.clamp(row, 0, math.max(0, #self.Lines - 1))
		return View.GetPixelColumn(self, pixel, row), row
	end
	function View.UpdateCursor(self, input)
		if input then
			self.CursorX, self.CursorY = View.ScreenToEditorPoint(self, input.Position.X, input.Position.Y)
		end
		self.CursorY = math.clamp(self.CursorY, 0, math.max(0, #self.Lines - 1))
		local geometry = View.LineGeometry(self, self.CursorY)
		local index = floorIndex(geometry.Bytes, math.clamp(self.CursorX, 0, #geometry.Text))
		self.CursorX = geometry.Bytes[index]
		self:RevealSourceLine(self.CursorY)
		local display = View.SourceToDisplay(self, self.CursorY)
		local lines = self.GuiElems.LinesFrame or self.Frame.Lines or self.Frame
		local x = math.round(geometry.Pixels[index] - View.ScrollPixelX(self))
		local y = display and (display - self.ViewY) * self.FontSize or -self.FontSize
		local cursor = self.GuiElems.Cursor
		local viewportWidth = lines.AbsoluteSize.X
		cursor.Visible = not self.ReadOnlySnippet
			and display ~= nil
			and viewportWidth >= 1
			and x >= 0
			and x <= viewportWidth
			and y >= 0
			and y < lines.AbsoluteSize.Y
		if cursor.Visible then
			local width = self.OverwriteMode
					and math.max(
						1,
						(geometry.Pixels[index + 1] or geometry.Width + View.ColumnWidth(self)) - geometry.Pixels[index]
					)
				or 1
			x = math.min(x, viewportWidth - 1)
			cursor.Position = UDim2.fromOffset((self.GutterWidth or 0) + x, y)
			cursor.Size = UDim2.fromOffset(
				math.clamp(math.round(width), 1, viewportWidth - x),
				math.min(self.FontSize + 2, lines.AbsoluteSize.Y - y)
			)
			self:CursorAnim(true)
		end
	end
	function View.Model(self)
		if not self.FoldModel or self.FoldLines ~= self.Lines or self.FoldLineCount ~= #self.Lines then
			View.UpdateFolds(self)
		end
		return self.FoldModel
	end
	function View.UpdateFolds(self, source)
		self.FoldModel = Apps.EditorFolding.Create(self.Lines, source, self.FoldModel)
		self.FoldLines = self.Lines
		self.FoldLineCount = #self.Lines
	end
	function View.KeepFoldsForLine(self, row, previous)
		local model = self.FoldModel
		if not previous or not model or self.FoldLines ~= self.Lines or self.FoldLineCount ~= #self.Lines then
			return false
		end
		local changed = self.Lines[row]
		if not Apps.EditorFolding.SameStructure(previous, changed) then
			return false
		end
		if model.sourceLines then
			model.sourceLines[row] = changed
		end
		return true
	end
	function View.ResetFolds(self)
		self.FoldModel = nil
	end
	function View.GetCollapsedFolds(self)
		local model = self.FoldModel
		return model and next(model.collapsed) and table.clone(model.collapsed) or nil
	end
	function View.RestoreFolds(self, collapsed)
		if not collapsed then
			if not self.FoldModel then
				self:UpdateView()
			end
			return
		end
		local model = View.Model(self)
		for first in pairs(collapsed) do
			if model.ranges[first] then
				model.collapsed[first] = true
			end
		end
		self.FoldModel = Apps.EditorFolding.Rebuild(model, self.Lines)
		self:UpdateView()
	end
	function View.DisplayToSource(self, row)
		local model = View.Model(self)
		return (model.display[math.clamp(row + 1, 1, math.max(1, #model.display))] or 1) - 1
	end
	function View.SourceToDisplay(self, row)
		local model = View.Model(self)
		return model.reverse[row + 1] and model.reverse[row + 1] - 1 or nil
	end
	function View.RevealSourceLine(self, row)
		local model = View.Model(self)
		local line = row + 1
		if model.reverse[line] or not next(model.collapsed) then
			return
		end
		local changed = false
		for first in pairs(model.collapsed) do
			if line > first and line <= model.ranges[first] then
				model.collapsed[first] = nil
				changed = true
			end
		end
		if changed then
			self.FoldModel = Apps.EditorFolding.Rebuild(model, self.Lines)
			self:UpdateView()
		end
	end
	function View.SetAllFolds(self, collapse)
		local model = View.Model(self)
		model.collapsed = {}
		local destination = self.CursorY + 1
		for first, last in pairs(model.ranges) do
			if collapse then
				model.collapsed[first] = true
				if self.CursorY + 1 > first and self.CursorY + 1 <= last then
					destination = math.min(destination, first)
				end
			end
		end
		if destination ~= self.CursorY + 1 then
			self.CursorY = destination - 1
			self.CursorX = 0
		end
		self.FoldModel = Apps.EditorFolding.Rebuild(model, self.Lines)
		self:UpdateView()
		self:Refresh()
		self:UpdateCursor()
	end
	function View.ToggleFold(self, row)
		local model = View.Model(self)
		local line = row + 1
		local last = model.ranges[line]
		if not last then
			return false
		end
		model.collapsed[line] = not model.collapsed[line] or nil
		self.FoldModel = Apps.EditorFolding.Rebuild(model, self.Lines)
		if model.collapsed[line] and self.CursorY > row and self.CursorY < last then
			self.CursorY = row
			self.CursorX = math.min(self.CursorX, #self.Lines[line])
		end
		self:UpdateView()
		self:Refresh()
		return true
	end
	local function searchOffsets(self)
		if
			self.SearchOffsetLines ~= self.Lines
			or self.SearchOffsetText ~= self.Text
			or self.SearchOffsetCount ~= #self.Lines
		then
			local starts = { 1 }
			for index = 1, #self.Lines - 1 do
				starts[index + 1] = starts[index] + #self.Lines[index] + 1
			end
			self.SearchLineStarts = starts
			self.SearchOffsetLines = self.Lines
			self.SearchOffsetText = self.Text
			self.SearchOffsetCount = #self.Lines
		end
		return self.SearchLineStarts
	end
	local function searchMarkers(self, matches, starts, model)
		local track = self.ScrollV and self.ScrollV.Gui
		if not track then
			return
		end
		local host = self.SearchMarkerHost
		local visible = self.SearchVisible == true and #matches > 0
		if not host then
			if not visible then
				return
			end
			host = Instance.new("Frame")
			host.Name = "SearchMarkers"
			host.BackgroundTransparency = 1
			host.Size = UDim2.fromScale(1, 1)
			host.ZIndex = track.ZIndex + 3
			host.Parent = track
			self.SearchMarkerHost = host
		end
		host.Visible = visible
		if not visible then
			for _, marker in ipairs(host:GetChildren()) do
				marker:Destroy()
			end
			self.SearchMarkerMatches = nil
			return
		end
		local height = math.max(1, math.floor(track.AbsoluteSize.Y))
		if
			self.SearchMarkerMatches == matches
			and self.SearchMarkerStarts == starts
			and self.SearchMarkerModel == model
			and self.SearchMarkerHeight == height
		then
			return
		end
		local used, index = 0, 1
		local displayRows = math.max(1, #model.display)
		while index <= #matches do
			local line = floorIndex(starts, matches[index].Start)
			local display = floorIndex(model.display, line)
			local pixel = (display - 1) * height // displayRows
			local nextDisplay = ((pixel + 1) * displayRows + height - 1) // height + 1
			local nextStart = starts[model.display[nextDisplay]]
			if not nextStart then
				index = #matches + 1
			else
				local first, last = index + 1, #matches + 1
				while first < last do
					local middle = (first + last) // 2
					if matches[middle].Start < nextStart then
						first = middle + 1
					else
						last = middle
					end
				end
				index = first
			end
			used += 1
			local key = tostring(used)
			local marker = host:FindFirstChild(key)
			if not marker then
				marker = Instance.new("Frame")
				marker.Name = key
				marker.BorderSizePixel = 0
				marker.ZIndex = host.ZIndex
				marker.Parent = host
			end
			marker.BackgroundColor3 = self.Colors.SearchMatch or Color3.fromRGB(160, 125, 40)
			marker.Position = UDim2.fromOffset(0, pixel)
			marker.Size = UDim2.fromOffset(3, math.min(2, height - pixel))
			marker.Visible = true
		end
		for _, marker in ipairs(host:GetChildren()) do
			if tonumber(marker.Name) > used then
				marker:Destroy()
			end
		end
		self.SearchMarkerMatches = matches
		self.SearchMarkerStarts = starts
		self.SearchMarkerModel = model
		self.SearchMarkerHeight = height
	end
	local function drawLineText(self, frame, row, geometry, ranges, scroll, width, syntax)
		local highlights = self:HighlightLine(row + 1)
		local link = self.DefinitionLink
		if link and link.Row ~= row then
			link = nil
		end
		local hasSelection = false
		for _, range in ipairs(ranges) do
			local a, b = range[1], range[2]
			if a and b and row >= a[2] and row <= b[2] and (a[1] ~= b[1] or a[2] ~= b[2]) then
				hasSelection = true
				break
			end
		end
		local cache = self.PaintByFrame
		if not cache then
			cache = {}
			self.PaintByFrame = cache
		end
		local paint = cache[frame]
		if not hasSelection and not link then
			if
				paint
				and paint.Geometry == geometry
				and paint.Highlights == highlights
				and paint.Templates == self.RichTemplates
				and paint.Syntax == syntax
				and paint.Scroll == scroll
				and paint.Width == width
			then
				return
			end
			paint = paint or {}
			paint.Geometry = geometry
			paint.Highlights = highlights
			paint.Templates = self.RichTemplates
			paint.Syntax = syntax
			paint.Scroll = scroll
			paint.Width = width
			cache[frame] = paint
		else
			cache[frame] = nil
		end
		local first = floorIndex(geometry.Pixels, scroll)
		local last = math.min(#geometry.Bytes, floorIndex(geometry.Pixels, scroll + width) + 1)
		local line = geometry.Text
		local pieces = {}
		local currentTemplate, underlined
		local runStart = geometry.Bytes[first] + 1
		local function flush(lastByte)
			if lastByte < runStart then
				return
			end
			local text = line:sub(runStart, lastByte):gsub("['\"<>&]", syntax.richReplace)
			if currentTemplate ~= self.RichTemplates.Text then
				text = currentTemplate .. text .. "</font>"
			end
			pieces[#pieces + 1] = if underlined then "<u>" .. text .. "</u>" else text
		end
		for index = first, last - 1 do
			local column = geometry.Bytes[index]
			local byte = column + 1
			local template = self.RichTemplates[syntax.typeMap[highlights[byte]]] or self.RichTemplates.Text
			if hasSelection then
				for _, range in ipairs(ranges) do
					local a, b = range[1], range[2]
					if
						a
						and b
						and row >= a[2]
						and row <= b[2]
						and (row ~= a[2] or column >= a[1])
						and (row ~= b[2] or column < b[1])
					then
						template = self.RichTemplates.Selection
						break
					end
				end
			end
			local linked = link ~= nil and column >= link.First and column < link.Last
			if template ~= currentTemplate or linked ~= underlined then
				if currentTemplate ~= nil then
					flush(byte - 1)
				end
				currentTemplate, underlined, runStart = template, linked, byte
			end
		end
		if currentTemplate ~= nil then
			flush(geometry.Bytes[last])
		end
		local label = frame.Label
		label.Position = UDim2.fromOffset(math.round(geometry.Pixels[first] - scroll), 0)
		label.Size = UDim2.new(1, math.max(0, math.round(scroll - geometry.Pixels[first])), 0, self.FontSize)
		local text = table.concat(pieces)
		if label.Text ~= text then
			label.Text = text
		end
	end

	function View.SetDefinitionLink(self, link)
		local previous = self.DefinitionLink
		if
			previous == link
			or (
				previous
				and link
				and previous.Row == link.Row
				and previous.First == link.First
				and previous.Last == link.Last
			)
		then
			return
		end
		self.DefinitionLink = link
		if not self.LineSyntax then
			return
		end
		local scroll = View.ScrollPixelX(self)
		local width = self.Frame.Lines.AbsoluteSize.X
		local ranges = { self.SelectionRange }
		for _, range in ipairs(self.AdditionalSelections or {}) do
			ranges[#ranges + 1] = range
		end
		local function redraw(row)
			local display = View.SourceToDisplay(self, row)
			local frame = display and self.LineFrames[display - self.ViewY + 1]
			if frame and self.RowLines[frame] == row + 1 then
				drawLineText(self, frame, row, View.LineGeometry(self, row), ranges, scroll, width, self.LineSyntax)
			end
		end
		if previous and (not link or previous.Row ~= link.Row) then
			redraw(previous.Row)
		end
		if link then
			redraw(link.Row)
		end
	end

	local function wordAtCaret(self)
		if not self.HighlightOccurrences or self.ReadOnlySnippet or self.SearchVisible then
			return nil
		end
		local line = self.Lines[self.CursorY + 1] or ""
		local first = self.CursorX + 1
		while first > 1 and line:sub(first - 1, first - 1):match("[%w_]") do
			first -= 1
		end
		local last = line:match("^[%a_][%w_]*()", first)
		if not last then
			return nil
		end
		local range = self.SelectionRange
		local anchor, caret = range and range[1], range and range[2]
		if anchor and caret and anchor[1] >= 0 and (anchor[1] ~= caret[1] or anchor[2] ~= caret[2]) then
			if
				anchor[2] ~= self.CursorY
				or caret[2] ~= self.CursorY
				or math.min(anchor[1], caret[1]) ~= first - 1
				or math.max(anchor[1], caret[1]) ~= last - 1
			then
				return nil
			end
		end
		local word = line:sub(first, last - 1)
		return "%f[%w_]" .. word .. "%f[^%w_]", #word
	end

	local function paintWordMatches(self, frame, geometry, row, pattern, wordLength, scroll, width)
		local host = frame:FindFirstChild("WordMatches")
		if
			host
			and host:GetAttribute("WordPattern") == pattern
			and host:GetAttribute("WordScroll") == scroll
			and host:GetAttribute("WordWidth") == width
			and self.WordMatchGeometry
			and self.WordMatchGeometry[frame] == geometry
		then
			return
		end
		local used = 0
		if pattern and width > 0 then
			local bytes, pixels = geometry.Bytes, geometry.Pixels
			local first = math.max(1, bytes[floorIndex(pixels, scroll)] - wordLength + 2)
			local last = bytes[floorIndex(pixels, scroll + width)] + 1
			local from, to = geometry.Text:find(pattern, first)
			while from and from <= last do
				local x0 = math.max(0, math.round(View.GetColumnPixelX(self, from - 1, row) - scroll))
				local x1 = math.min(width, math.round(View.GetColumnPixelX(self, to, row) - scroll))
				if x1 > x0 then
					if not host then
						host = Instance.new("Frame")
						host.Name = "WordMatches"
						host.BackgroundTransparency = 1
						host.Size = UDim2.fromScale(1, 1)
						host.Parent = frame
					end
					used += 1
					local name = tostring(used)
					local match = host:FindFirstChild(name)
					if not match then
						match = Instance.new("Frame")
						match.Name = name
						match.BorderSizePixel = 0
						match.ZIndex = 1
						match.Parent = host
					end
					match.BackgroundColor3 = self.Colors.MatchingWord
					match.Position = UDim2.fromOffset(x0, 0)
					match.Size = UDim2.new(0, x1 - x0, 1, 0)
					match.Visible = true
				end
				from, to = geometry.Text:find(pattern, to + 1)
			end
		end
		if host then
			self.WordMatchGeometry = self.WordMatchGeometry or setmetatable({}, { __mode = "k" })
			self.WordMatchGeometry[frame] = geometry
			host:SetAttribute("WordPattern", pattern)
			host:SetAttribute("WordScroll", scroll)
			host:SetAttribute("WordWidth", width)
			for _, match in host:GetChildren() do
				match.Visible = tonumber(match.Name) <= used
			end
		end
	end

	function View.Refresh(self, syntax)
		self.LineSyntax = syntax

		local linesFrame = self.Frame.Lines
		local hSize = math.max(0, linesFrame.AbsoluteSize.X)
		local vSize = math.max(0, linesFrame.AbsoluteSize.Y)
		local lineHeight = self.SnippetLineHeight or self.FontSize
		local maxLines = math.ceil(vSize / lineHeight)
		local viewX, viewY = self.ViewX, self.ViewY
		local model = View.Model(self)
		if
			self.RenderedText ~= self.Text
			or self.RenderedViewX ~= viewX
			or self.RenderedViewY ~= viewY
			or self.RenderedFoldModel ~= model
			or self.RenderedFontSize ~= self.FontSize
		then
			self.DefinitionLink = nil
		end
		self.RenderedText, self.RenderedViewX, self.RenderedViewY = self.Text, viewX, viewY
		self.RenderedFoldModel, self.RenderedFontSize = model, self.FontSize
		local scrollPixel = View.ScrollPixelX(self)
		local searchMatches = self.SearchVisible == true and self.SearchMatches or {}
		searchMatches = searchMatches or {}
		local searchStarts = #searchMatches > 0 and searchOffsets(self) or nil
		local activeSearch = searchMatches[self.SearchActiveIndex or 0]
		local primary = self.SelectionRange
		local selectedSearch = false
		if activeSearch and searchStarts and primary and primary[1] and primary[2] then
			local first, last = primary[1], primary[2]
			local firstStart, lastStart = searchStarts[first[2] + 1], searchStarts[last[2] + 1]
			if firstStart and lastStart then
				local firstOffset, lastOffset = firstStart + first[1], lastStart + last[1]
				selectedSearch = math.min(firstOffset, lastOffset) == activeSearch.Start
					and math.max(firstOffset, lastOffset) == activeSearch.Finish
			end
		end
		searchMarkers(self, searchMatches, searchStarts, model)
		local wordPattern, wordLength = wordAtCaret(self)
		local ranges = { self.SelectionRange }
		for _, range in ipairs(self.AdditionalSelections or {}) do
			ranges[#ranges + 1] = range
		end
		local blankEnd, blankIndent = 0, 0

		self.RowLines = self.RowLines or {}
		self.NumberFrames = self.NumberFrames or {}
		self.FoldButtons = self.FoldButtons or {}
		local previous = table.clone(self.LineFrames)
		local retained, used = {}, {}
		for _, frame in ipairs(previous) do
			retained[self.RowLines[frame] or -1] = frame
		end
		for row = 1, maxLines do
			local frame = retained[model.display[viewY + row] or -row]
			if frame then
				self.LineFrames[row] = frame
				used[frame] = true
			else
				self.LineFrames[row] = false
			end
		end
		local free = 1
		self.Frame.LineNumbers.Text = ""

		for row = 1, maxLines do
			local lineFrame = self.LineFrames[row]
			if not lineFrame then
				while previous[free] and used[previous[free]] do
					free += 1
				end
				lineFrame = previous[free]
				free += 1
				if lineFrame then
					self.LineFrames[row] = lineFrame
					used[lineFrame] = true
				end
			end
			if not lineFrame then
				lineFrame = Instance.new("Frame")
				lineFrame.Name = "Line"
				lineFrame.BorderSizePixel = 0
				lineFrame.BackgroundTransparency = 1

				local activeLine = Instance.new("Frame")
				activeLine.Name = "ActiveLine"
				activeLine.BorderSizePixel = 0
				activeLine.Size = UDim2.fromScale(1, 1)
				activeLine.BackgroundTransparency = 0
				activeLine.Parent = lineFrame
				local selectionHighlight = Instance.new("Frame")
				selectionHighlight.Name = "SelectionHighlight"
				selectionHighlight.BorderSizePixel = 0
				selectionHighlight.BackgroundColor3 = self.Colors.SelectionBack
				selectionHighlight.ZIndex = 2
				selectionHighlight.Parent = lineFrame

				local label = Instance.new("TextLabel")
				label.Name = "Label"
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.Code
				label.TextSize = self.FontSize
				label.RichText = true
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextColor3 = self.Colors.Text
				label.ZIndex = 3
				label.Parent = lineFrame

				lineFrame.Parent = linesFrame
				self.LineFrames[row] = lineFrame
				used[lineFrame] = true
			end

			lineFrame.Position = UDim2.fromOffset(0, (row - 1) * lineHeight)
			lineFrame.Size = UDim2.new(1, 0, 0, lineHeight)
			lineFrame.Label.Size = UDim2.new(1, 0, 0, lineHeight)
			lineFrame.Label.TextSize = self.FontSize
			lineFrame.Label.TextColor3 = self.Colors.Text
			local number = self.NumberFrames[lineFrame]
			if not number then
				number = Instance.new("TextLabel")
				number.Name = "LineNumber"
				number.BackgroundTransparency = 1
				number.Font = Enum.Font.Code
				number.ZIndex = 3
				number.TextXAlignment = Enum.TextXAlignment.Right
				number.Parent = self.Frame.LineNumbers
				self.NumberFrames[lineFrame] = number
			end
			number.Position = lineFrame.Position
			number.Size = UDim2.new(1, 0, 0, lineHeight)
			number.TextSize = self.FontSize
			local relaY = model.display[viewY + row]
			local sourceLine = relaY
			relaY = relaY or (#self.Lines + row)
			self.RowLines[lineFrame] = sourceLine or -row
			local fold = self.FoldButtons[lineFrame]
			if not fold then
				fold = Instance.new("TextButton")
				fold.Name = "FoldToggle"
				fold.BackgroundTransparency = 1
				fold.BorderSizePixel = 0
				fold.AutoButtonColor = false
				fold.TextSize = 12
				fold.ZIndex = 3
				fold.MouseButton1Click:Connect(function()
					local source = self.RowLines[lineFrame]
					if source and source > 0 then
						View.ToggleFold(self, source - 1)
					end
				end)
				self.FoldButtons[lineFrame] = fold
			end
			fold.Parent = self.GutterFrame or self.Frame
			fold.Position = UDim2.fromOffset((self.GutterWidth or 42) - 20, (row - 1) * self.FontSize)
			fold.Size = UDim2.fromOffset(20, self.FontSize)
			local asset = Main.GetStudioAsset
				and Main.GetStudioAsset(
					model.collapsed[relaY] and "native/editor/fold_right" or "native/editor/fold_down"
				)
			local image = fold:FindFirstChild("StudioFold")
			if asset and not image then
				image = Instance.new("ImageLabel")
				image.Name = "StudioFold"
				image.BackgroundTransparency = 1
				image.AnchorPoint = Vector2.new(0.5, 0.5)
				image.Position = UDim2.fromScale(0.5, 0.5)
				image.ZIndex = 4
				image.Parent = fold
			end
			if image then
				local size = math.max(18, self.FontSize)
				image.Size = UDim2.fromOffset(size, size)
			end
			if image then
				image.Image = asset or ""
				image.ImageColor3 = Settings.Theme.PlaceholderText
				image.Visible = asset ~= nil
			end
			fold.Text = asset and ""
				or (model.collapsed[relaY] and string.char(226, 150, 184) or string.char(226, 150, 190))
			fold.TextColor3 = Settings.Theme.PlaceholderText
			fold.Visible = not self.ReadOnlySnippet and sourceLine ~= nil and model.ranges[sourceLine] ~= nil
			local active = not self.ReadOnlySnippet and relaY == self.CursorY + 1 and self.Lines[relaY] ~= nil
			lineFrame.ActiveLine.Visible = active
			lineFrame.ActiveLine.BackgroundColor3 = self.Colors.CurrentLine or Settings.Theme.Main2
			lineFrame.SelectionHighlight.BackgroundColor3 = self.Colors.SelectionBack
			number.TextColor3 = (active or self.ReadOnlySnippet) and self.Colors.Text or Settings.Theme.PlaceholderText
			local numberText = self.Lines[relaY] and tostring(relaY) or ""
			if number.Text ~= numberText then
				number.Text = numberText
			end
			local lineText = self.Lines[relaY] or ""
			local marker = lineFrame:FindFirstChild("SyntaxUnderline")
			local diagnostic = self.SyntaxDiagnostic
			if diagnostic and diagnostic.Line == sourceLine then
				local first = math.clamp((diagnostic.Column or 1) - 1, 0, #lineText)
				if not diagnostic.Column then
					first = #(lineText:match("^%s*") or "")
				end
				local startX = View.GetColumnPixelX(self, first, sourceLine - 1) - scrollPixel
				local endX = View.GetColumnPixelX(self, #lineText, sourceLine - 1) - scrollPixel
				if not marker then
					marker = Instance.new("Frame")
					marker.Name = "SyntaxUnderline"
					marker.BackgroundColor3 = Color3.fromRGB(234, 68, 68)
					marker.BorderSizePixel = 0
					marker.ZIndex = 4
					marker.Parent = lineFrame
				end
				local x = math.max(0, math.round(startX))
				local width = math.min(hSize, math.round(math.max(startX + 4, endX))) - x
				marker.Position = UDim2.new(0, x, 1, -1)
				marker.Size = UDim2.fromOffset(math.max(0, width), 1)
				marker.Visible = width > 0
			elseif marker then
				marker.Visible = false
			end
			local guideHost = lineFrame:FindFirstChild("IndentGuides")
			if self.ShowIndentGuides then
				if not guideHost then
					guideHost = Instance.new("Frame")
					guideHost.Name = "IndentGuides"
					guideHost.BackgroundTransparency = 1
					guideHost.Size = UDim2.fromScale(1, 1)
					guideHost.Parent = lineFrame
				end
				local whitespace = #(lineText:match("^ *") or "")
				if not lineText:find("%S") and self.Lines[relaY] then
					if relaY > blankEnd then
						local before, after = 0, 0
						for index = relaY - 1, 1, -1 do
							local text = self.Lines[index]
							if text:find("%S") then
								before = #(text:match("^ *") or "")
								break
							end
						end
						blankEnd = relaY
						for index = relaY + 1, #self.Lines do
							local text = self.Lines[index]
							if text:find("%S") then
								after = #(text:match("^ *") or "")
								break
							end
							blankEnd = index
						end
						blankIndent = math.min(before, after)
					end
					whitespace = blankIndent
				end
				local count = 0
				for column = 0, whitespace - 4, 4 do
					local x = math.round(measured(self, string.rep(" ", column)) - scrollPixel)
					if x >= 0 and x < hSize then
						count += 1
						local key = tostring(count)
						local guide = guideHost:FindFirstChild(key)
						if not guide then
							guide = Instance.new("Frame")
							guide.Name = key
							guide.BorderSizePixel = 0
							guide.ZIndex = 2
							guide.Parent = guideHost
						end
						guide.Position = UDim2.fromOffset(x, 0)
						guide.Size = UDim2.new(0, 1, 1, 0)
						guide.BackgroundColor3 = self.Colors.IndentGuide or Settings.Theme.Guide
						guide.Visible = true
					end
				end
				for _, guide in ipairs(guideHost:GetChildren()) do
					if tonumber(guide.Name) > count then
						guide.Visible = false
					end
				end
			elseif guideHost then
				guideHost:Destroy()
			end

			local geometry = View.LineGeometry(self, relaY - 1)
			paintWordMatches(self, lineFrame, geometry, relaY - 1, wordPattern, wordLength, scrollPixel, hSize)
			local searchHost = lineFrame:FindFirstChild("SearchMatches")
			local searchCount = 0
			if searchStarts and sourceLine then
				local start = searchStarts[sourceLine]
				local pixels, bytes = geometry.Pixels, geometry.Bytes
				local firstVisible = start + bytes[floorIndex(pixels, math.max(0, scrollPixel - 1))]
				local lastGlyph = math.min(#bytes, floorIndex(pixels, scrollPixel + hSize) + 1)
				local lastVisible = start + bytes[lastGlyph]
				local low, high = 1, #searchMatches + 1
				while low < high do
					local middle = math.floor((low + high) / 2)
					local match = searchMatches[middle]
					if match and (match.Finish > firstVisible or match.Finish == match.Start and match.Start >= firstVisible) then
						high = middle
					else
						low = middle + 1
					end
				end
				for index = low, #searchMatches do
					local match = searchMatches[index]
					if match.Start > lastVisible then
						break
					end
					if index ~= self.SearchActiveIndex or not selectedSearch then
						local from = View.GetColumnPixelX(
							self,
							math.clamp(match.Start - start, 0, #lineText),
							relaY - 1
						) - scrollPixel
						local to = View.GetColumnPixelX(self, math.clamp(match.Finish - start, 0, #lineText), relaY - 1)
							- scrollPixel
						if match.Start == match.Finish then
							to = from + 1
						end
						from = math.clamp(math.round(from), 0, hSize)
						to = math.clamp(math.round(to), 0, hSize)
						if to > from then
							if not searchHost then
								searchHost = Instance.new("Frame")
								searchHost.Name = "SearchMatches"
								searchHost.BackgroundTransparency = 1
								searchHost.Size = UDim2.fromScale(1, 1)
								searchHost.ZIndex = 1
								searchHost.Parent = lineFrame
							end
							searchCount += 1
							local key = tostring(searchCount)
							local span = searchHost:FindFirstChild(key)
							if not span then
								span = Instance.new("Frame")
								span.Name = key
								span.BorderSizePixel = 0
								span.ZIndex = 1
								span.Parent = searchHost
							end
							span.BackgroundColor3 = self.Colors.SearchMatch or Color3.fromRGB(124, 98, 33)
							span.Position = UDim2.fromOffset(from, 0)
							span.Size = UDim2.new(0, to - from, 1, 0)
							span.Visible = true
						end
					end
				end
			end
			if searchHost then
				for _, span in ipairs(searchHost:GetChildren()) do
					if tonumber(span.Name) > searchCount then
						span:Destroy()
					end
				end
			end
			local rowIndex = relaY - 1
			local rectangles = lineFrame:FindFirstChild("ExtraSelections")
			for index, range in ipairs(ranges) do
				local a, b = range[1], range[2]
				local visible = a and b and rowIndex >= a[2] and rowIndex <= b[2]
				if index > 1 and visible and not rectangles then
					rectangles = Instance.new("Frame")
					rectangles.Name = "ExtraSelections"
					rectangles.BackgroundTransparency = 1
					rectangles.Size = UDim2.fromScale(1, 1)
					rectangles.Parent = lineFrame
				end
				local rectangle = if index == 1 then lineFrame.SelectionHighlight
					else rectangles and rectangles:FindFirstChild(tostring(index))
				if not rectangle then
					if not visible then continue end
					rectangle = Instance.new("Frame")
					rectangle.Name = tostring(index)
					rectangle.BorderSizePixel = 0
					rectangle.ZIndex = 2
					rectangle.Parent = rectangles
				end
				rectangle.Visible = visible == true
				if visible then
					rectangle.BackgroundColor3 = self.Colors.SelectionBack
					local from = rowIndex == a[2] and View.GetColumnPixelX(self, a[1], rowIndex) or 0
					local to = rowIndex == b[2] and View.GetColumnPixelX(self, b[1], rowIndex) or scrollPixel + hSize
					from = math.clamp(math.round(from - scrollPixel), 0, hSize)
					to = math.clamp(math.round(to - scrollPixel), 0, hSize)
					rectangle.Position = UDim2.fromOffset(from, 0)
					rectangle.Size = UDim2.new(0, math.max(0, to - from), 1, 0)
				end
			end
			if rectangles then
				for _, rectangle in ipairs(rectangles:GetChildren()) do
					if tonumber(rectangle.Name) > #ranges then rectangle.Visible = false end
				end
			end
			local caretHost = lineFrame:FindFirstChild("ExtraCarets")
			local caretCount = 0
			for _, range in ipairs(self.AdditionalSelections or {}) do
				local point = range.Caret or range[2]
				if point and point[2] == rowIndex then
					local x = math.round(View.GetColumnPixelX(self, point[1], rowIndex) - scrollPixel)
					if x >= 0 and x < hSize then
						if not caretHost then
							caretHost = Instance.new("Frame")
							caretHost.Name = "ExtraCarets"
							caretHost.BackgroundTransparency = 1
							caretHost.Size = UDim2.fromScale(1, 1)
							caretHost.Parent = lineFrame
						end
						caretCount += 1
						local caret = caretHost:FindFirstChild(tostring(caretCount))
						if not caret then
							caret = Instance.new("Frame")
							caret.Name = tostring(caretCount)
							caret.BorderSizePixel = 0
							caret.ZIndex = 3
							caret.Parent = caretHost
						end
						caret.BackgroundColor3 = self.Colors.Text
						caret.Position = UDim2.fromOffset(x, 0)
						caret.Size = UDim2.fromOffset(1, self.FontSize)
						caret.Visible = true
					end
				end
			end
			if caretHost then
				for _, caret in ipairs(caretHost:GetChildren()) do
					if tonumber(caret.Name) > caretCount then
						caret.Visible = false
					end
				end
			end
			drawLineText(self, lineFrame, rowIndex, geometry, ranges, scrollPixel, hSize, syntax)
		end

		for i = maxLines + 1, #self.LineFrames do
			self.LineFrames[i] = nil
		end
		for _, frame in ipairs(previous) do
			if not used[frame] then
				if self.NumberFrames[frame] then
					self.NumberFrames[frame]:Destroy()
					self.NumberFrames[frame] = nil
				end
				if self.FoldButtons[frame] then
					self.FoldButtons[frame]:Destroy()
					self.FoldButtons[frame] = nil
				end
				self.RowLines[frame] = nil
				if self.PaintByFrame then
					self.PaintByFrame[frame] = nil
				end
				frame:Destroy()
			end
		end
		self:UpdateCursor()
	end

	function View.UpdateView(self)
		local fontWidth = View.ColumnWidth(self)
		local digits = #tostring(#self.Lines)
		local numberWidth = math.max(digits * fontWidth, math.ceil(measured(self, string.rep("9", digits))))
		local leading = self.ReadOnlySnippet and 2 or fontWidth
		local trailing = if self.ReadOnlySnippet then 8 elseif self.GutterWidthMinimum then 22 else 2 * fontWidth
		local gutter = math.max(leading + numberWidth + trailing, self.GutterWidthMinimum or 0)
		self.GutterWidth = gutter
		local model = View.Model(self)
		local width = math.max(0, self.Frame.AbsoluteSize.X - gutter)
		local height = math.max(0, self.Frame.AbsoluteSize.Y)
		local thickness = self.ScrollBarThickness or 10
		local lineHeight = self.SnippetLineHeight or self.FontSize
		local vertical = #model.display * lineHeight > height
		local horizontal = self.MaxTextCols * fontWidth > width - (vertical and thickness or 0)
		vertical = #model.display * lineHeight > height - (horizontal and thickness or 0)
		horizontal = self.MaxTextCols * fontWidth > width - (vertical and thickness or 0)
		local right = vertical and thickness or 0
		local bottom = horizontal and thickness or 0
		local scrollV, scrollH = self.ScrollV, self.ScrollH
		scrollV.VisibleSpace = math.max(0, math.floor((height - bottom) / lineHeight))
		scrollV.TotalSpace = #model.display
		scrollH.VisibleSpace = math.max(0, math.floor((width - right) / fontWidth))
		scrollH.TotalSpace = self.MaxTextCols
		scrollV.Gui.Visible = vertical
		scrollH.Gui.Visible = horizontal
		scrollV.Gui.Position = UDim2.new(1, -thickness, 0, 0)
		scrollV.Gui.Size = UDim2.new(0, thickness, 1, -bottom)
		scrollH.Gui.Position = UDim2.new(0, gutter, 1, -thickness)
		scrollH.Gui.Size = UDim2.new(1, -gutter - right, 0, thickness)
		self.GuiElems.ScrollCorner.Visible = vertical and horizontal
		self.GuiElems.ScrollCorner.Position = UDim2.new(1, -thickness, 1, -thickness)
		self.GuiElems.ScrollCorner.Size = UDim2.fromOffset(thickness, thickness)
		self.FrameOffsets = Vector2.new(-right, -bottom)
		self.Frame.Lines.Position = UDim2.fromOffset(gutter, 0)
		self.Frame.Lines.Size = UDim2.new(1, -gutter - right, 1, -bottom)
		if self.GutterColor and not self.GutterFrame then
			self.GutterFrame = Instance.new("Frame")
			self.GutterFrame.Name = "Gutter"
			self.GutterFrame.BorderSizePixel = 0
			self.GutterFrame.Parent = self.Frame
			self.GutterFrame.ClipsDescendants = true
			self.GutterFrame.ZIndex = 1
			self.Frame.LineNumbers.ZIndex = 2
		end
		if self.GutterFrame then
			self.GutterFrame.BackgroundColor3 = self.GutterColor or self.Colors.Background
			self.GutterFrame.Size = UDim2.new(0, gutter, 1, -bottom)
		end
		self.Frame.LineNumbers.Position = UDim2.fromOffset(leading, 0)
		self.Frame.LineNumbers.Size = UDim2.new(0, gutter - leading - trailing, 1, -bottom)
		self.Frame.LineNumbers.TextSize = self.FontSize
		scrollV:ScrollTo(self.ViewY, true)
		scrollH:ScrollTo(self.ViewX, true)
		self.ViewY = scrollV.Index
		self.ViewX = scrollH.Index
	end

	return View
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
