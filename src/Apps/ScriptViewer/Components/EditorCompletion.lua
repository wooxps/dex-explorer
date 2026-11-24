--!strict

local Apps, Main, env, service, Lib

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, env, service, Lib = d.Apps, d.Main, d.env, d.service, d.Lib
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Completion = {}
	function Completion.Create(content, cf, accept, onSelect)
		local skin = Apps.StudioEditorSkin
		local surface = Color3.fromRGB(25, 27, 31)
		local textColor = Color3.new(1, 1, 1)
		local selectedColor = Color3.fromRGB(1, 39, 185)
		local scrollbarColor = Color3.fromRGB(179, 179, 179)
		local padding = 5
		local scrollbarWidth = 5
		local rowInset = 2
		local labelGap = 3
		local visibleRows = 5
		local borderAllowance = 2
		local docsWidthPreferred = 270
		local docsTextSize = 14
		local docsVerticalPadding = 7
		local exampleInset = 11
		local exampleToggleHeight = 20
		local examplePadding = 4
		local exampleLineHeight = 17
		local function node(class, props)
			local obj = Instance.new(class)
			for k, v in pairs(props) do
				obj[k] = v
			end
			return obj
		end
		local popup = node("Frame", {
			Name = "Autocomplete",
			Parent = content,
			Visible = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = false,
			ZIndex = 20,
		})
		local list = node("ScrollingFrame", {
			Name = "Suggestions",
			Parent = popup,
			BackgroundColor3 = surface,
			BorderSizePixel = 0,
			ScrollBarThickness = 0,
			ScrollBarImageColor3 = scrollbarColor,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarImageTransparency = 0,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			CanvasSize = UDim2.new(),
			CanvasPosition = Vector2.new(),
			ZIndex = 21,
		})
		local docs = node("ScrollingFrame", {
			Name = "Documentation",
			Parent = popup,
			BackgroundColor3 = surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ScrollBarThickness = 0,
			ScrollBarImageColor3 = scrollbarColor,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			CanvasSize = UDim2.new(),
			CanvasPosition = Vector2.new(),
			ZIndex = 21,
		})
		local function outline(panel)
			local shadow = node("Frame", {
				Name = panel.Name .. "Shadow",
				Parent = popup,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 20,
			})
			for offset, opacity in ipairs({ 0.18, 0.12, 0.07, 0.03 }) do
				node("Frame", {
					Parent = shadow,
					BackgroundColor3 = Color3.new(),
					BackgroundTransparency = 1 - opacity,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 2 + offset, 1, offset - 1),
					Size = UDim2.new(1, -2, 0, 1),
					ZIndex = 20,
				})
				node("Frame", {
					Parent = shadow,
					BackgroundColor3 = Color3.new(),
					BackgroundTransparency = 1 - opacity,
					BorderSizePixel = 0,
					Position = UDim2.new(1, offset - 1, 0, 2 + offset),
					Size = UDim2.new(0, 1, 1, -2),
					ZIndex = 20,
				})
			end
			local overlay = node("Frame", {
				Name = panel.Name .. "Outline",
				Parent = popup,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 29,
			})
			for _, edge in ipairs({
				{ UDim2.new(), UDim2.new(1, 0, 0, 1) },
				{ UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1) },
				{ UDim2.new(), UDim2.new(0, 1, 1, 0) },
				{ UDim2.new(1, -1, 0, 0), UDim2.new(0, 1, 1, 0) },
			}) do
				node("Frame", {
					Parent = overlay,
					BackgroundColor3 = Color3.new(),
					BorderSizePixel = 0,
					Position = edge[1],
					Size = edge[2],
					ZIndex = 29,
				})
			end
			return function()
				overlay.Position, overlay.Size, overlay.Visible = panel.Position, panel.Size, panel.Visible
				shadow.Position, shadow.Size, shadow.Visible = panel.Position, panel.Size, panel.Visible
			end
		end
		local listOutline, docsOutline = outline(list), outline(docs)
		local divider = node("Frame", {
			Name = "HeaderDivider",
			Parent = docs,
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 22,
		})
		local signature = node("TextLabel", {
			Name = "Signature",
			Parent = docs,
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LineHeight = 1.2,
			ZIndex = 22,
		})
		local description = node("TextLabel", {
			Name = "Description",
			Parent = docs,
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans,
			TextSize = docsTextSize,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			RichText = true,
			LineHeight = 1.25,
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 22,
		})
		local link = node("TextButton", {
			Name = "DocumentationLink",
			Parent = docs,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "<u>Open Documentation</u>",
			RichText = true,
			Font = Enum.Font.SourceSans,
			TextSize = docsTextSize,
			TextColor3 = Color3.fromRGB(79, 147, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 22,
		})
		local self =
			{ Gui = popup, List = list, Docs = docs, Items = nil, Selected = 1, Rows = {}, First = 1, Busy = false }
		function self:ContainsPoint(x, y)
			for _, panel in ipairs({ list, docs }) do
				local p, s = panel.AbsolutePosition, panel.AbsoluteSize
				if panel.Visible and x >= p.X and x < p.X + s.X and y >= p.Y and y < p.Y + s.Y then
					return true
				end
			end
			return false
		end
		local sampleExpanded = true
		local lastClicked, lastClickTime
		local sampleButton = node("TextButton", {
			Name = "CodeExampleToggle",
			Parent = docs,
			Visible = false,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 22,
		})
		local sampleChevron = node("ImageLabel", {
			Name = "Chevron",
			Parent = sampleButton,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(1, 2),
			ZIndex = 23,
		})
		local sampleCaption = node("TextLabel", {
			Name = "Caption",
			Parent = sampleButton,
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans,
			TextSize = docsTextSize,
			TextColor3 = textColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(19, 0),
			Size = UDim2.new(1, -19, 1, 0),
			ZIndex = 23,
		})
		local samplePanel, samplePreview
		local function sampleText(item)
			return item and type(item.CodeExample) == "string" and item.CodeExample ~= "" and item.CodeExample or nil
		end
		local function sampleHeight(text)
			if not text or not sampleExpanded then
				return 0
			end
			local _, lines = text:gsub("\n", "")
			return math.min(200, (lines + 1) * exampleLineHeight + 2 * examplePadding)
		end
		sampleButton.MouseButton1Click:Connect(function()
			sampleExpanded = not sampleExpanded
			if self.Items then
				self:Render({ Items = self.Items }, self.Selected)
			end
		end)
		local rowHeight = 18
		local function measure(text, width, font, size)
			local ok, value = pcall(function()
				return service.TextService:GetTextSize(text, size, font, Vector2.new(width, 10000))
			end)
			return ok and value
				or Vector2.new(
					math.min(width, #text * size / 2),
					math.ceil(math.max(1, #text * size / 2 / width)) * size
				)
		end
		local function documentation(item)
			if not item then
				return "", ""
			end
			local detail = item and item.Detail or ""
			local description = item and item.Documentation or ""
			if
				not item.TypeOnly
				and (detail == item.Kind or detail == "Identifier" or (detail == item.Name and description == ""))
			then
				detail = ""
			end
			if description == item.Kind or description == "Identifier" or description == detail then
				description = ""
			end
			return detail, description
		end
		local function documentationUrl(item)
			local url = item and item.Url
			return type(url) == "string" and url:match("^https://create%.roblox%.com/") and url or nil
		end
		local function wrappedHeight(text, width, font, size, lineHeight)
			if text == "" then
				return 0
			end
			local measuredHeight = measure(text, width, font, size).Y
			return math.ceil(math.max(size, measuredHeight + math.max(0, measuredHeight - size) * (lineHeight - 1)))
		end
		local function detailLayout(item, width)
			local heading, body = documentation(item)
			local linkUrl = documentationUrl(item)
			local sample = sampleText(item)
			if item.Overloads and item.Overloads > 0 then
				heading ..= "\n(+" .. item.Overloads .. (item.Overloads == 1 and " overload)" or " overloads)")
			end
			local signatureHeight = wrappedHeight(heading, width, Enum.Font.Code, cf.FontSize, signature.LineHeight)
			local bodyText, richBody = Apps.EditorDocumentationText.Format(body, item.DocumentationFormat)
			local bodyHeight =
				wrappedHeight(bodyText, width, Enum.Font.SourceSans, docsTextSize, description.LineHeight)
			local dividerTop = docsVerticalPadding + signatureHeight + 5
			local hasDivider = heading ~= "" and (body ~= "" or linkUrl ~= nil or sample ~= nil)
			local bodyTop = if hasDivider then dividerTop + 7 else docsVerticalPadding + signatureHeight
			local linkTop = bodyTop + bodyHeight + (bodyHeight > 0 and linkUrl and 5 or 0)
			local sampleTop = linkTop + (linkUrl and exampleToggleHeight or 0)
			local previewHeight = sampleHeight(sample)
			return {
				Heading = heading,
				Body = richBody,
				SignatureHeight = signatureHeight,
				DividerTop = dividerTop,
				HasDivider = hasDivider,
				BodyTop = bodyTop,
				BodyHeight = bodyHeight,
				Link = linkUrl,
				LinkTop = linkTop,
				Sample = sample,
				SampleTop = sampleTop,
				PreviewHeight = previewHeight,
				Height = sampleTop + (sample and exampleToggleHeight or 0) + previewHeight + docsVerticalPadding,
			}
		end
		local function renderDetail(layout, scrollbar)
			local inset = 2 * padding + scrollbar
			signature.Text = layout.Heading
			signature.TextSize = cf.FontSize
			signature.Visible = layout.Heading ~= ""
			signature.Position = UDim2.fromOffset(padding, docsVerticalPadding)
			signature.Size = UDim2.new(1, -inset, 0, layout.SignatureHeight)
			divider.Visible = layout.HasDivider
			divider.Position = UDim2.fromOffset(0, layout.DividerTop)
			description.Text = layout.Body
			description.Visible = layout.Body ~= ""
			description.Position = UDim2.fromOffset(padding, layout.BodyTop)
			description.Size = UDim2.fromOffset(math.max(1, docs.Size.X.Offset - inset), layout.BodyHeight)
			link.Visible = layout.Link ~= nil
			self.DocumentationUrl = layout.Link
			link.Text = "<u>Open Documentation</u>"
			link.Position = UDim2.fromOffset(padding, layout.LinkTop)
			link.Size = UDim2.fromOffset(
				math.ceil(measure("Open Documentation", 1000, link.Font, docsTextSize).X),
				exampleToggleHeight
			)
			sampleButton.Visible = layout.Sample ~= nil
			sampleButton.Position = UDim2.fromOffset(exampleInset, layout.SampleTop)
			sampleButton.Size = UDim2.new(1, -2 * exampleInset - scrollbar, 0, exampleToggleHeight)
			sampleCaption.Text = sampleExpanded and "Hide Code Example" or "Show Code Example"
			local arrow = sampleExpanded and "CollapseArrow" or "ExpandArrow"
			sampleChevron.Image = Main.GetStudioAsset and Main.GetStudioAsset("native/find-all/" .. arrow) or ""
			if layout.Sample and sampleExpanded then
				if not samplePreview then
					samplePanel = node("Frame", {
						Name = "CodeExample",
						Parent = docs,
						BackgroundColor3 = Color3.fromRGB(37, 37, 37),
						BorderColor3 = Color3.new(),
						BorderSizePixel = 1,
						BorderMode = Enum.BorderMode.Inset,
						ClipsDescendants = true,
						ZIndex = 22,
					})
					samplePreview = Lib.CodeFrame.new()
					samplePreview.Editable = false
					samplePreview.ReadOnlySnippet = true
					samplePreview.SnippetLineHeight = exampleLineHeight
					skin.Apply(samplePreview)
					samplePreview.ShowIndentGuides = false
					samplePreview.GutterWidthMinimum = 22
					samplePreview.GutterColor = Color3.fromRGB(43, 43, 43)
					samplePreview.ScrollBarThickness = scrollbarWidth
					samplePreview.ScrollV.ThumbThickness = 3
					samplePreview.ScrollH.ThumbThickness = 3
					samplePreview.ScrollV.ThumbInset = 1
					samplePreview.ScrollH.ThumbInset = 1
					samplePreview.Frame.Name = "Snippet"
					samplePreview.Frame.BackgroundTransparency = 1
					samplePreview.Frame.Position = UDim2.fromOffset(1, examplePadding)
					samplePreview.Frame.Size = UDim2.new(1, -2, 1, -2 * examplePadding)
					samplePreview.Frame.ZIndex = 23
					samplePreview.Frame.Parent = samplePanel
					local function layer(child)
						if child:IsA("GuiObject") and child.ZIndex < 24 then
							child.ZIndex += 23
						end
					end
					for _, child in ipairs(samplePreview.Frame:GetDescendants()) do
						layer(child)
					end
					samplePreview.Frame.DescendantAdded:Connect(layer)
				end
				samplePanel.Position = UDim2.fromOffset(exampleInset, layout.SampleTop + exampleToggleHeight)
				samplePanel.Size = UDim2.new(1, -2 * exampleInset - scrollbar, 0, layout.PreviewHeight)
				samplePanel.Visible = true
				local fontChanged = samplePreview.FontSize ~= docsTextSize
				samplePreview.FontSize = docsTextSize
				if self.Sample ~= layout.Sample then
					self.Sample = layout.Sample
					samplePreview:SetText(layout.Sample)
					samplePreview.ScrollV:ScrollTo(0)
					samplePreview.ScrollH:ScrollTo(0)
				elseif fontChanged then
					samplePreview:UpdateView()
					samplePreview:Refresh()
				end
			elseif samplePanel then
				samplePanel.Visible = false
			end
		end
		local function positionDocumentationFooter()
			if not docs.Visible or not description.Visible then
				return
			end
			local gap = link.Visible and 5 or 0
			local bottom = description.Position.Y.Offset + math.ceil(description.AbsoluteSize.Y)
			local linkTop = bottom + gap
			local sampleTop = linkTop + (link.Visible and exampleToggleHeight or 0)
			link.Position = UDim2.fromOffset(padding, linkTop)
			sampleButton.Position = UDim2.fromOffset(exampleInset, sampleTop)
			local endY = sampleTop
			if sampleButton.Visible then
				endY += exampleToggleHeight
				if samplePanel and samplePanel.Visible then
					samplePanel.Position = UDim2.fromOffset(exampleInset, endY)
					endY += samplePanel.Size.Y.Offset
				end
			end
			docs.CanvasSize = UDim2.fromOffset(0, endY + docsVerticalPadding)
			if docs.CanvasSize.Y.Offset > docs.Size.Y.Offset then
				docs.ScrollBarThickness = scrollbarWidth
			end
		end
		description:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionDocumentationFooter)
		link.MouseButton1Click:Connect(function()
			local url = self.DocumentationUrl
			if not url then
				return
			end
			local opened = pcall(function()
				game:GetService("BrowserService"):OpenBrowserWindow(url)
			end)
			if not opened and type(env.setclipboard) == "function" and pcall(env.setclipboard, url) then
				link.Text = "Link copied"
			end
		end)
		local function selectItem(index)
			if self.Items and self.Items[index] and index ~= self.Selected then
				if onSelect then
					onSelect(index)
				end
				self:Render({ Items = self.Items }, index)
			end
		end
		local function paint()
			if not self.Items then
				return
			end
			local scrollY = list.CanvasPosition.Y
			self.First = math.clamp(math.floor(math.max(0, scrollY - 1) / rowHeight) + 1, 1, #self.Items)
			local last = math.min(#self.Items, math.ceil((scrollY + list.Size.Y.Offset - 1) / rowHeight))
			local count = math.max(0, last - self.First + 1)
			for row = 1, count do
				local button = self.Rows[row]
				if not button then
					button = node("TextButton", {
						Name = "Suggestion" .. row,
						Parent = list,
						AutoButtonColor = false,
						BorderSizePixel = 0,
						Text = "",
						ZIndex = 22,
					})
					self.Rows[row] = button
					button.MouseButton1Click:Connect(function()
						local index = button:GetAttribute("CompletionIndex")
						local item = self.Items and self.Items[index]
						if not item then
							return
						end
						local now = os.clock()
						if lastClicked == item and now - lastClickTime <= 0.4 then
							lastClicked = nil
							accept(index)
							return
						end
						lastClicked, lastClickTime = item, now
						selectItem(index)
						if service.UserInputService:GetFocusedTextBox() ~= cf.GuiElems.EditBox then
							cf.GuiElems.EditBox:CaptureFocus()
						end
					end)
					node("ImageLabel", {
						Name = "Kind",
						Parent = button,
						BackgroundTransparency = 1,
						ZIndex = 23,
					})
					node("TextLabel", {
						Name = "Label",
						Parent = button,
						BackgroundTransparency = 1,
						Font = Enum.Font.Code,
						TextColor3 = textColor,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Center,
						TextTruncate = Enum.TextTruncate.AtEnd,
						ZIndex = 23,
					})
				end
				local index = self.First + row - 1
				local item = self.Items[index]
				button:SetAttribute("CompletionIndex", index)
				button.Position = UDim2.fromOffset(1, (index - 1) * rowHeight + 1)
				button.Size = UDim2.new(1, -2 - list.ScrollBarThickness, 0, rowHeight)
				button.BackgroundColor3 = self.Selected == index and selectedColor or surface
				local key = ({
					Function = "function",
					Method = "function",
					Property = "property",
					Variable = "property",
					Instance = "property",
					Global = "property",
					Event = "event",
					Keyword = "keyword",
					Enum = "enum",
					Type = "enum",
					Value = "property",
				})[item.Kind] or "text"
				local asset = Main.GetStudioAsset and Main.GetStudioAsset("native/editor/completion/" .. key)
				local iconSize = cf.FontSize
				button.Kind.Size = UDim2.fromOffset(iconSize, iconSize)
				button.Kind.Position = UDim2.fromOffset(rowInset, rowInset)
				button.Kind.Image = asset or ""
				button.Kind.Visible = asset ~= nil
				local textInset = rowInset + iconSize + labelGap
				button.Label.Position = UDim2.fromOffset(textInset, 0)
				button.Label.Size = UDim2.new(1, -textInset, 1, 0)
				button.Label.TextSize = cf.FontSize
				button.Label.RichText = item.Deprecated == true
				button.Label.Text = if item.Deprecated
					then "<s>" .. item.Name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") .. "</s>"
					else item.Name
				button.Visible = true
			end
			for row = count + 1, #self.Rows do
				self.Rows[row].Visible = false
			end
		end
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if not self.Busy then
				paint()
			end
		end)
		function self:Render(result, index)
			if not result or #result.Items == 0 then
				self.Items = nil
				lastClicked = nil
				popup.Visible = false
				return
			end
			local previousItem = self.Items and self.Items[self.Selected]
			local changedItems = self.Items ~= result.Items
			if changedItems then
				lastClicked = nil
			end
			self.Items = result.Items
			self.Selected = math.clamp(index, 1, #self.Items)
			local selectedItem = self.Items[self.Selected]
			local item = Apps.EditorApiDocumentation.Apply(selectedItem)
			local lines = cf.GuiElems.LinesFrame or cf.Frame
			local width, height = content.AbsoluteSize.X, content.AbsoluteSize.Y
			local listWidth = math.min(math.max(40, cf.FontSize * 19 + borderAllowance), math.max(1, width - 8))
			local caretX = lines.AbsolutePosition.X
				- content.AbsolutePosition.X
				+ cf:GetColumnPixelX(cf.CursorX, cf.CursorY)
				- Apps.CodeViewport.ScrollPixelX(cf)
			local caretTop = lines.AbsolutePosition.Y
				- content.AbsolutePosition.Y
				+ ((cf:SourceToDisplay(cf.CursorY) or cf.CursorY) - (cf.ViewY or 0)) * cf.FontSize
			local caretBottom = caretTop + cf.FontSize
			local listX = math.clamp(caretX, 0, math.max(0, width - listWidth))
			local heading, body = documentation(item)
			local hasDocs = heading ~= "" or body ~= "" or documentationUrl(item) ~= nil or sampleText(item) ~= nil
			local docsWidth, docsX, stacked = 0, 0, false
			if hasDocs then
				local preferred = if body == ""
						and not documentationUrl(item)
						and not sampleText(item)
						and not item.Overloads
					then math.min(
						docsWidthPreferred,
						math.ceil(measure(heading, 10000, Enum.Font.Code, cf.FontSize).X) + 2 * padding + 2
					)
					else docsWidthPreferred
				local rightSpace = width - listX - listWidth + 1
				local leftSpace = listX + 1
				if rightSpace >= preferred or rightSpace >= 220 and rightSpace >= leftSpace then
					docsX, docsWidth = listWidth - 1, math.min(rightSpace, preferred)
				elseif leftSpace >= preferred or leftSpace >= 220 then
					docsWidth = math.min(leftSpace, preferred)
					docsX = 1 - docsWidth
				else
					stacked = true
					docsWidth = math.min(listWidth, preferred)
				end
			end
			local layout = hasDocs and detailLayout(item, math.max(1, docsWidth - 2 * padding))
			rowHeight = cf.FontSize + 4
			local rows = math.min(visibleRows, #self.Items)
			local preferredListHeight = rows * rowHeight + borderAllowance
			local belowSpace, aboveSpace = math.max(0, height - caretBottom), math.max(0, caretTop)
			local above = preferredListHeight > belowSpace and aboveSpace > belowSpace
			local room = above and aboveSpace or belowSpace
			if room < rowHeight + borderAllowance then
				popup.Visible = false
				return
			end
			self.Count = math.max(1, math.min(rows, math.floor((room - borderAllowance) / rowHeight)))
			local listHeight = self.Count * rowHeight + borderAllowance
			local docsHeight, scrollbar = 0, 0
			if layout then
				local docRoom = math.max(0, room - (stacked and listHeight - 1 or 0))
				if docRoom >= cf.FontSize + 4 then
					docsHeight = math.min(docRoom, layout.Height)
					if docsHeight < layout.Height then
						scrollbar = scrollbarWidth
						layout = detailLayout(item, math.max(1, docsWidth - 2 * padding - scrollbar))
					end
				end
			end
			local popupLeft = listX + math.min(0, docsHeight > 0 and docsX or 0)
			local listOffset = listX - popupLeft
			local popupHeight = if stacked and docsHeight > 0
				then listHeight + docsHeight - 1
				else math.max(listHeight, docsHeight)
			local listTop = if above then popupHeight - listHeight else 0
			local docsTop = if above
				then (stacked and 0 or popupHeight - docsHeight)
				elseif stacked then listHeight - 1
				else 0
			local popupWidth = math.max(listOffset + listWidth, docsHeight > 0 and listOffset + docsX + docsWidth or 0)
			local popupY = above and caretTop - popupHeight or caretBottom
			popup.Position = UDim2.fromOffset(popupLeft, math.clamp(popupY, 0, math.max(0, height - popupHeight)))
			popup.Size = UDim2.fromOffset(popupWidth, popupHeight)
			list.Position = UDim2.fromOffset(listOffset, listTop)
			list.Size = UDim2.fromOffset(listWidth, listHeight)
			listOutline()
			list.ScrollBarThickness = #self.Items > self.Count and scrollbarWidth or 0
			docs.Visible = docsHeight > 0
			docs.Position = UDim2.fromOffset(listOffset + docsX, docsTop)
			docs.Size = UDim2.fromOffset(docsWidth, docsHeight)
			docsOutline()
			self.DocumentationUrl = nil
			if docs.Visible and layout then
				docs.ScrollBarThickness = scrollbar
				docs.CanvasSize = UDim2.fromOffset(0, layout.Height)
				local docsScroll = if previousItem == selectedItem then docs.CanvasPosition.Y else 0
				docs.CanvasPosition = Vector2.new(0, math.min(docsScroll, layout.Height - docsHeight))
				renderDetail(layout, scrollbar)
				positionDocumentationFooter()
			end
			self.Busy = true
			local canvasHeight = #self.Items * rowHeight + borderAllowance
			list.CanvasSize = UDim2.fromOffset(0, canvasHeight)
			local current = changedItems and 0 or list.CanvasPosition.Y
			local top = (self.Selected - 1) * rowHeight + 1
			local bottom = top + rowHeight
			if top < current + 1 then
				current = top - 1
			elseif bottom > current + listHeight - 1 then
				current = bottom - listHeight + 1
			end
			list.CanvasPosition = Vector2.new(0, math.clamp(current, 0, math.max(0, canvasHeight - listHeight)))
			self.Busy = false
			paint()
			popup.Visible = true
		end
		return self
	end
	return Completion
end
return { InitDeps = InitDeps, Main = CreateModule }
