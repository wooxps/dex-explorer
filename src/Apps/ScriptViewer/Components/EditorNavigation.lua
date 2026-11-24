--!strict

local Apps, Main, Lib, service, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Lib, service, Settings = d.Apps, d.Main, d.Lib, d.service, d.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Navigation = {}
	function Navigation.Attach(viewer, cf, window, language, options)
		local skin = Apps.StudioEditorSkin
		local content = window.GuiElems.Content
		local panelColor = Color3.fromRGB(36, 36, 36)
		local panelBorder = Color3.new()
		local activeRowColor = Color3.fromRGB(2, 77, 158)
		local rowHeight, queryHeight = 52, 24
		local escape = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }
		local function node(class, props)
			local obj = Instance.new(class)
			for k, v in pairs(props) do
				obj[k] = v
			end
			return obj
		end
		local panel = node("Frame", {
			Name = "FunctionFilter",
			Parent = content,
			Visible = false,
			BackgroundColor3 = panelColor,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(360, 238),
			Position = UDim2.new(1, -372, 0, 30),
			ClipsDescendants = true,
			ZIndex = 30,
		})
		node("Frame", {
			Name = "FilterBorder",
			Parent = panel,
			BackgroundColor3 = panelBorder,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, queryHeight),
			ZIndex = 31,
		})
		local query = node("TextBox", {
			Name = "Filter",
			Parent = panel,
			ClearTextOnFocus = false,
			Text = "",
			PlaceholderText = "Filter functions",
			BackgroundColor3 = panelColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 0, queryHeight - 1),
			Font = Enum.Font.Code,
			TextSize = 14,
			TextColor3 = skin.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 32,
		})
		node("UIPadding", { Parent = query, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
		node("Frame", {
			Name = "ListBorder",
			Parent = panel,
			BackgroundColor3 = panelBorder,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, queryHeight),
			Size = UDim2.new(1, 0, 1, -queryHeight),
			ZIndex = 31,
		})
		local list = node("ScrollingFrame", {
			Name = "Functions",
			Parent = panel,
			BackgroundColor3 = panelColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(1, queryHeight + 1),
			Size = UDim2.new(1, -2, 1, -queryHeight - 2),
			ScrollBarThickness = 0,
			ScrollBarImageColor3 = Color3.fromRGB(179, 179, 179),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			CanvasSize = UDim2.new(),
			CanvasPosition = Vector2.new(),
			ZIndex = 32,
		})
		local rows, items, filtered = {}, {}, {}
		local displayedSignatures = {}
		local selected, mode = 1, "Functions"
		local lastClick, lastTime
		local function index(source)
			language:Index(source or cf:GetText())
			return language.Symbols
		end
		local historyBack, historyForward = {}, {}
		local navigationRevision = 0
		function viewer.CancelDefinitionNavigation()
			navigationRevision += 1
		end
		local document = Apps.EditorDocument.Create("")
		local editorText
		local function getDocument()
			if editorText ~= cf.Text then
				editorText = cf.Text
				document:SetText(cf:GetText())
			end
			return document
		end
		local function offset(column, row)
			local doc = getDocument()
			local prefix = (cf.Lines[row + 1] or ""):sub(1, column)
			if cf.ConvertText then
				prefix = cf:ConvertText(prefix, false)
			end
			return doc:LineColumnToPosition(row + 1, #prefix + 1)
		end
		local function point(position)
			local doc = getDocument()
			local line, column = doc:PositionToLineColumn(position)
			local prefix = doc:GetLine(line):sub(1, column - 1)
			if cf.ConvertText then
				prefix = cf:ConvertText(prefix, true)
			end
			return #prefix, line - 1
		end
		function viewer.JumpToOffset(position, selectionLength)
			cf.AdditionalSelections = {}
			local column, row = point(position)
			local endColumn, endRow = point(position + (selectionLength or 0))
			cf.SelectionRange = { { column, row }, { endColumn, endRow } }
			cf:MoveCursor(column, row)
			cf.ScrollV:ScrollTo(math.max(0, (cf:SourceToDisplay(row) or row) - 2))
			local pixel = cf:GetColumnPixelX(column, row)
			local viewStart = Apps.CodeViewport.ScrollPixelX(cf)
			if pixel < viewStart or pixel >= viewStart + (cf.GuiElems.LinesFrame or cf.Frame).AbsoluteSize.X then
				cf.ScrollH:ScrollTo(math.max(0, math.floor(pixel / Apps.CodeViewport.ColumnWidth(cf)) - 4))
			end
			cf:SetCopyableSelection()
			cf:Refresh()
			cf.GuiElems.EditBox:CaptureFocus()
		end
		local definitions = Apps.EditorDefinitions
		local largeSymbols, pendingIndex
		local function prepareDefinition(onReady, explicit)
			local source = getDocument():GetText()
			if #source <= 65536 then
				return true
			end
			if definitions.IsPrimed(source) and largeSymbols and largeSymbols.Source == source then
				return true
			end
			if
				pendingIndex
				and pendingIndex.Source == source
				and pendingIndex.Document == viewer.ActiveDocument
				and pendingIndex.Revision == navigationRevision
			then
				if not pendingIndex.Explicit or explicit then
					pendingIndex.OnReady = onReady
					pendingIndex.Explicit = explicit
				end
				return false
			end
			local request = {
				Source = source,
				Text = cf.Text,
				Document = viewer.ActiveDocument,
				Revision = navigationRevision,
				OnReady = onReady,
				Explicit = explicit,
			}
			pendingIndex = request
			task.defer(function()
				local function current()
					return pendingIndex == request
						and Main.Alive ~= false
						and window:IsVisible()
						and request.Document == viewer.ActiveDocument
						and request.Revision == navigationRevision
						and request.Text == cf.Text
				end
				local deadline = os.clock() + 0.003
				local function checkpoint()
					if os.clock() >= deadline then
						task.wait()
						deadline = os.clock() + 0.003
					end
					return current()
				end
				local stopped = {}
				local ok, problem = pcall(function()
					if not current() or not definitions.Prime(source, checkpoint) then
						return
					end
					if not largeSymbols or largeSymbols.Source ~= source then
						local symbols = Apps.EditorSymbols.New()
						symbols:Index(source, function()
							if not checkpoint() then
								error(stopped, 0)
							end
						end)
						largeSymbols = symbols
					end
				end)
				local ready = ok and current() and largeSymbols and largeSymbols.Source == source
				if pendingIndex == request then
					pendingIndex = nil
				end
				if ready and request.OnReady then
					request.OnReady()
				elseif not ok and problem ~= stopped then
					error(problem, 0)
				end
			end)
			return false
		end
		local function localDefinition(position, strict)
			local source = getDocument():GetText()
			local symbols = largeSymbols and largeSymbols.Source == source and largeSymbols or index(source)
			local token, first, last = symbols:Token(position)
			if token and (not strict or (position >= first and position < last)) then
				local declaration = symbols:Find(token, position)
				if
					declaration
					and (position < declaration.Position or position >= declaration.Position + #declaration.Name)
				then
					return { Declaration = declaration, First = first, Last = last }
				end
			end
		end
		function viewer.GetDeclaration(position)
			local result = localDefinition(position or offset(cf.CursorX, cf.CursorY), false)
			return result and result.Declaration
		end
		function viewer.GetDefinition(position, strict)
			local doc = viewer.ActiveDocument
			if not doc then
				return nil
			end
			position = position or offset(cf.CursorX, cf.CursorY)
			if not prepareDefinition() then
				return nil
			end
			local object = viewer.ActiveScript
			if not object and typeof(doc.id) == "Instance" then
				object = doc.id
			end
			local source = getDocument():GetText()
			local result = definitions.Resolve(source, position, object, game, workspace)
			if not result and not strict and position > 1 then
				result = definitions.Resolve(source, position - 1, object, game, workspace)
			end
			if result and result.Object ~= game and result.Object ~= object then
				return result
			end
			return localDefinition(position, strict)
		end
		local function location()
			return {
				Document = viewer.ActiveDocument,
				Position = offset(cf.CursorX, cf.CursorY),
				ViewX = cf.ViewX,
				ViewY = cf.ViewY,
			}
		end
		local function push(stack, item)
			if #stack == 64 then
				table.remove(stack, 1)
			end
			stack[#stack + 1] = item
		end
		local function travel(from, to)
			navigationRevision += 1
			while #from > 0 do
				local item = table.remove(from)
				if table.find(viewer.Documents, item.Document) then
					push(to, location())
					viewer.SelectDocument(item.Document)
					viewer.JumpToOffset(item.Position)
					cf.ScrollV:ScrollTo(item.ViewY)
					cf.ScrollH:ScrollTo(item.ViewX)
					cf:Refresh()
					return true
				end
			end
			return false
		end
		function viewer.NavigateBack()
			return travel(historyBack, historyForward)
		end
		function viewer.NavigateForward()
			return travel(historyForward, historyBack)
		end
		local function remember(origin)
			push(historyBack, origin)
			table.clear(historyForward)
		end
		function viewer.GoToDeclaration(position, strict, quiet)
			position = position or offset(cf.CursorX, cf.CursorY)
			if not prepareDefinition(function()
				viewer.GoToDeclaration(position, strict, quiet)
			end, true) then
				return true
			end
			local result = viewer.GetDefinition(position, strict)
			if not result then
				if options.Message and not quiet then
					options.Message("No definition found")
				end
				return false
			end
			local origin = location()
			if strict then
				origin.Position = position
			end
			navigationRevision += 1
			if result.Declaration then
				remember(origin)
				viewer.JumpToOffset(result.Declaration.Position, #result.Declaration.Name)
			elseif
				result.Object:IsA("ModuleScript")
				or result.Object:IsA("Script")
				or result.Object:IsA("LocalScript")
			then
				local revision, text = navigationRevision, cf.Text
				task.spawn(function()
					local function stillCurrent()
						return Main.Alive ~= false
							and window:IsVisible()
							and navigationRevision == revision
							and viewer.ActiveDocument == origin.Document
							and cf.Text == text
					end
					if not stillCurrent() then
						return
					end
					local doc = viewer.ViewScript(result.Object, stillCurrent)
					if doc and viewer.ActiveDocument == doc then
						remember(origin)
						viewer.JumpToOffset(1)
					end
				end)
			else
				local explorer = Apps.Explorer
				local node = explorer.GetNodes()[result.Object]
				if not node then
					return false
				end
				explorer.Window:Show()
				if explorer.SearchView and not explorer.SearchView:Contains(node) then
					explorer.ClearSearch()
				end
				explorer.SelectService(result.Object)
				explorer.ViewObj(result.Object)
			end
			return true
		end
		local function activate(item)
			if not item then
				return
			end
			panel.Visible = false
			query:ReleaseFocus()
			if mode == "Documents" then
				viewer.SelectDocument(item.Document)
				cf.GuiElems.EditBox:CaptureFocus()
			else
				viewer.JumpToOffset(item.Position, #item.Name)
			end
		end
		local function parameterParts(parameters)
			local parts, stack = {}, {}
			local closing = { ["("] = ")", ["{"] = "}", ["["] = "]", ["<"] = ">" }
			local first = 1
			for position = 1, #parameters do
				local char = parameters:sub(position, position)
				if closing[char] then
					stack[#stack + 1] = closing[char]
				elseif char == stack[#stack] and (char ~= ">" or parameters:sub(position - 1, position - 1) ~= "-") then
					stack[#stack] = nil
				elseif char == "," and #stack == 0 then
					parts[#parts + 1] = parameters:sub(first, position - 1)
					first = position + 1
				end
			end
			local tail = parameters:sub(first)
			if tail:find("%S") then
				parts[#parts + 1] = tail
			end
			return parts
		end
		local function functionSignatures(item, source, symbols, ranges)
			local startLine = document:PositionToLineColumn(item.Position)
			local opening = symbols.Masked:find("(", item.Position, true)
			local after = opening and opening + #(item.Parameters or "") + 2
			local lastLine = ranges[startLine]
			local finish = lastLine and document:LineColumnToPosition(lastLine, 1) or nil
			local body = after and finish and symbols.Masked:sub(after, finish - 1) or ""
			local context = { Game = game, Workspace = workspace, Script = viewer.ActiveScript }
			local named, types = {}, {}
			for _, parameter in ipairs(parameterParts(item.Parameters or "")) do
				local name, annotation = parameter:match("^%s*([%w_%.]+)%s*:%s*(.-)%s*$")
				name = name or parameter:match("^%s*(.-)%s*$")
				if not annotation and name:match("^[%a_][%w_]*$") then
					for at, object, property, assigned in
						body:gmatch("()([%a_][%w_]*)%.([%a_][%w_]*)%s*=%s*([%a_][%w_]*)[ \t]*[\r\n]")
					do
						if assigned == name then
							local _, class = symbols:Resolve(object, context, after + at - 1)
							local member = class and Apps.ReflectionService.GetProperty(class, property)
							local valueType = member and member.ValueType
							if type(valueType) == "table" then
								annotation = valueType.Name
							elseif property == "Parent" and class then
								annotation = "Instance?"
							end
							if annotation then
								break
							end
						end
					end
				end
				annotation = annotation or "any"
				named[#named + 1] = name .. " : " .. annotation
				types[#types + 1] = annotation
			end
			local returnType = after and source:match("^[ \t]*:[ \t]*([^\r\n]+)", after)
			if returnType then
				returnType = returnType:match("^(.-)%s+return%f[%W]") or returnType:match("^%s*(.-)%s*$")
			elseif body ~= "" then
				local expression = body:match("%f[%w_]return%s+([^\r\n]+)")
				if expression then
					expression = expression:match("^%s*(.-)%s*$")
					local _, class = symbols:Resolve(expression, context, finish)
					returnType = class
						or (tonumber(expression) and "number")
						or ((expression == "true" or expression == "false") and "boolean")
						or "any"
				else
					returnType = "()"
				end
			end
			return item.Name .. "(" .. table.concat(named, ", ") .. ")",
				"(" .. table.concat(types, ", ") .. ") -> " .. (returnType or "any")
		end
		local paint
		paint = function()
			local first = math.max(1, math.floor(list.CanvasPosition.Y / rowHeight) + 1)
			local visibleRows = math.max(1, math.ceil(list.AbsoluteSize.Y / rowHeight) + 1)
			local scrollbar = #filtered * rowHeight > list.AbsoluteSize.Y and 8 or 0
			list.ScrollBarThickness = scrollbar
			for row = 1, math.max(visibleRows, #rows) do
				local b = rows[row]
				local at = first + row - 1
				local item = row <= visibleRows and filtered[at]
				if not b and item then
					b = node("TextButton", {
						Name = "Function" .. row,
						Parent = list,
						BorderSizePixel = 0,
						AutoButtonColor = false,
						Font = Enum.Font.Code,
						TextSize = 14,
						RichText = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Center,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextColor3 = Color3.new(1, 1, 1),
						ZIndex = 33,
					})
					node("UIPadding", { Parent = b, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6) })
					rows[row] = b
					b.MouseButton1Click:Connect(function()
						local n = b:GetAttribute("ItemIndex")
						selected = n
						local now = os.clock()
						if lastClick == filtered[n] and now - (lastTime or 0) < 0.4 then
							activate(filtered[n])
						else
							paint()
						end
						lastClick = filtered[n]
						lastTime = now
					end)
				end
				if b then
					b.Visible = item ~= nil
					if item then
						b:SetAttribute("ItemIndex", at)
						b.Position = UDim2.fromOffset(0, (at - 1) * rowHeight)
						b.Size = UDim2.new(1, -scrollbar, 0, rowHeight)
						if mode == "Functions" then
							local signature = displayedSignatures[item]
							if not signature then
								signature =
									{ functionSignatures(item, functionSource, functionSymbols, functionRanges) }
								displayedSignatures[item] = signature
							end
							b.Text = "<b>"
								.. signature[1]:gsub("[&<>]", escape)
								.. "</b>\n"
								.. signature[2]:gsub("[&<>]", escape)
						else
							b.Text = item.Signature:gsub("[&<>]", escape)
						end
						b.BackgroundColor3 = selected == at and activeRowColor or panelColor
					end
				end
			end
		end
		local function filter()
			filtered = {}
			local search = query.Text:lower()
			for _, item in ipairs(items) do
				if item.Name:lower():find(search, 1, true) then
					filtered[#filtered + 1] = item
				end
			end
			selected = 1
			lastClick = nil
			list.CanvasPosition = Vector2.new(0, 0)
			list.CanvasSize = UDim2.fromOffset(0, #filtered * rowHeight)
			paint()
		end
		query:GetPropertyChangedSignal("Text"):Connect(filter)
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		function viewer.OpenFunctionFilter()
			viewer.DismissCompletion()
			mode = "Functions"
			functionSymbols = index()
			functionSource = getDocument():GetText()
			functionRanges = Apps.CodeViewport.Model(cf).ranges
			items = functionSymbols.Functions
			table.clear(displayedSignatures)
			query.PlaceholderText = "Filter functions"
			query.Text = ""
			panel.Visible = true
			filter()
			query:CaptureFocus()
		end
		function viewer.OpenScriptPicker()
			viewer.DismissCompletion()
			mode = "Documents"
			items = {}
			for _, doc in ipairs(viewer.Documents or {}) do
				items[#items + 1] = { Name = doc.title, Signature = doc.title, Document = doc }
			end
			query.PlaceholderText = "Search open scripts"
			query.Text = ""
			panel.Visible = true
			filter()
			query:CaptureFocus()
		end
		function viewer.CloseNavigation()
			if panel.Visible and service.UserInputService:GetFocusedTextBox() == query then
				query:ReleaseFocus()
			end
			panel.Visible = false
		end
		function viewer.ShowScriptInExplorer()
			local object = viewer.ActiveScript
			local explorer = Apps.Explorer
			if not object or not explorer then
				return false
			end
			if explorer.SelectService then
				explorer.SelectService(object)
			end
			if explorer.ViewObj then
				explorer.ViewObj(object)
			end
			return true
		end
		function viewer.HandleNavigationInput(input)
			local key = input.KeyCode
			local ctrl = Lib.IsCtrlDown()
			local alt = service.UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
				or service.UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
			if alt and not ctrl and key == Enum.KeyCode.F and not Lib.IsShiftDown() then
				viewer.OpenFunctionFilter()
				return true
			end
			if ctrl and key == Enum.KeyCode.P then
				viewer.OpenScriptPicker()
				return true
			end
			if not alt and not Lib.IsShiftDown() and key == Enum.KeyCode.F12 then
				viewer.GoToDeclaration()
				return true
			end
			if alt and not ctrl and not Lib.IsShiftDown() then
				if key == Enum.KeyCode.Left then
					return viewer.NavigateBack()
				elseif key == Enum.KeyCode.Right then
					return viewer.NavigateForward()
				end
			end
			if ctrl and alt and key == Enum.KeyCode.K then
				viewer.ShowScriptInExplorer()
				return true
			end
			return false
		end
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if not panel.Visible then
				return
			end
			if not window:IsVisible() then
				viewer.CloseNavigation()
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local p, z = panel.AbsolutePosition, panel.AbsoluteSize
				local mouse = Main.Mouse
				if mouse.X < p.X or mouse.X >= p.X + z.X or mouse.Y < p.Y or mouse.Y >= p.Y + z.Y then
					viewer.CloseNavigation()
				end
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				viewer.CloseNavigation()
				cf.GuiElems.EditBox:CaptureFocus()
				return
			end
			if service.UserInputService:GetFocusedTextBox() ~= query then
				return
			end
			if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
				activate(filtered[selected])
			elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.Up then
				selected =
					math.clamp(selected + (input.KeyCode == Enum.KeyCode.Down and 1 or -1), 1, math.max(1, #filtered))
				local top = (selected - 1) * rowHeight
				local current = list.CanvasPosition.Y
				if top < current then
					list.CanvasPosition = Vector2.new(0, top)
				elseif top + rowHeight > current + list.AbsoluteSize.Y then
					list.CanvasPosition = Vector2.new(0, math.max(0, top + rowHeight - list.AbsoluteSize.Y))
				end
				paint()
			end
		end)
		local lines = cf.GuiElems.LinesFrame or cf.Frame
		local user = service.UserInputService
		local hit = Apps.EditorHitTest
		local function controlKey(input)
			return input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl
		end
		local function targetAt(x, y)
			if
				not x
				or not window:IsVisible()
				or not hit.Contains(lines, x, y)
				or (Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown())
				or (viewer.CanOpenEditorContextMenuAt and not viewer.CanOpenEditorContextMenuAt(x, y))
			then
				return nil
			end
			local column, row = cf:ScreenToEditorPoint(x, y, true)
			return column and offset(column, row)
		end
		local function clearLink()
			Apps.CodeViewport.SetDefinitionLink(cf, nil)
		end
		local function updateLink(input)
			local x, y = hit.Pointer(input)
			local position = Lib.IsCtrlDown() and targetAt(x, y)
			local result = position and prepareDefinition(updateLink) and viewer.GetDefinition(position, true)
			if not result then
				clearLink()
				return
			end
			local first, row = point(result.First)
			local last, lastRow = point(result.Last)
			if row ~= lastRow then
				clearLink()
				return
			end
			Apps.CodeViewport.SetDefinitionLink(cf, { Row = row, First = first, Last = last })
		end
		cf.HandleEditorPointer = function(_, input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not Lib.IsCtrlDown() then
				return false
			end
			local x, y = hit.Pointer(input)
			local position = targetAt(x, y)
			return position ~= nil and viewer.GoToDeclaration(position, true, true)
		end
		Main.TrackSignal(user.InputChanged, function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and (Lib.IsCtrlDown() or cf.DefinitionLink) then
				updateLink(input)
			end
		end)
		Main.TrackSignal(user.InputBegan, function(input)
			if controlKey(input) then
				updateLink(input)
			end
		end)
		Main.TrackSignal(user.InputEnded, function(input)
			if controlKey(input) then
				clearLink()
			end
		end)
		local function closeOverlays()
			viewer.CloseNavigation()
			clearLink()
		end
		Main.TrackSignal(window.OnDeactivate, closeOverlays)
		Main.TrackSignal(window.OnMinimize, closeOverlays)
		if user.WindowFocusReleased then
			Main.TrackSignal(user.WindowFocusReleased, clearLink)
		end
		local function fit()
			local width = math.min(360, math.max(120, content.AbsoluteSize.X - 12))
			panel.Position = UDim2.new(1, -width - 6, 0, 30)
			panel.Size = UDim2.fromOffset(width, math.min(238, math.max(80, content.AbsoluteSize.Y - 36)))
			if panel.Visible then
				paint()
			end
		end
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		viewer.FunctionFilter = panel
		Main.AddCleanup(function()
			panel:Destroy()
		end)
	end
	return Navigation
end
return { InitDeps = InitDeps, Main = CreateModule }
