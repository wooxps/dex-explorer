--!strict

------------------------------ Variables ------------------------------

local Main, Lib, Apps, Settings
local Explorer, Properties, ScriptViewer, Notebook
local API, RMD, env, service, plr, create, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function InitAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local executorName = "Unknown"
local executorVersion = "???"
if identifyexecutor then
	local name, ver = identifyexecutor()
	executorName = name
	executorVersion = ver
elseif game:GetService("RunService"):IsStudio() then
	executorName = "Studio"
	executorVersion = version()
end

local function getPath(obj)
	if obj.Parent == nil then
		return "Nil parented"
	else
		return Explorer.GetInstancePath(obj)
	end
end

------------------------------ Module ------------------------------

local function CreateModule()
	local ScriptViewer = {}
	local window, codeFrame
	local ensureEditor

	local execute, clear, dumpbtn

	local PreviousScr = nil

	ScriptViewer.DumpFunctions = function(scr)
		ensureEditor()
		local getgc = getgc or get_gc_objects
		local getupvalues = (debug and debug.getupvalues) or getupvalues or getupvals
		local getconstants = (debug and debug.getconstants) or getconstants or getconsts
		local getinfo = (debug and (debug.getinfo or debug.info)) or getinfo
		local original = ("\n-- // Function Dumper made by King.Kevin\n-- // Script Path: %s\n\n--[["):format(
			getPath(scr)
		)
		local dump = original
		local functions, function_count, data_base = {}, 0, {}
		function functions:add_to_dump(str, indentation, new_line)
			local new_line = new_line or true
			dump = dump .. ("%s%s%s"):format(string.rep("		", indentation), tostring(str), new_line and "\n" or "")
		end
		function functions:get_function_name(func)
			local n = getinfo(func).name
			return n ~= "" and n or "Unknown Name"
		end
		function functions:dump_table(input, indent, index)
			local indent = indent < 0 and 0 or indent
			functions:add_to_dump(
				("%s [%s] %s"):format(tostring(index), tostring(typeof(input)), tostring(input)),
				indent - 1
			)
			local count = 0
			for index, value in pairs(input) do
				count = count + 1
				if type(value) == "function" then
					functions:add_to_dump(
						("%d [function] = %s"):format(count, functions:get_function_name(value)),
						indent
					)
				elseif type(value) == "table" then
					if not data_base[value] then
						data_base[value] = true
						functions:add_to_dump(("%d [table]:"):format(count), indent)
						functions:dump_table(value, indent + 1, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(count), indent)
					end
				else
					functions:add_to_dump(
						("%d [%s] = %s"):format(count, tostring(typeof(value)), tostring(value)),
						indent
					)
				end
			end
		end
		function functions:dump_function(input, indent)
			functions:add_to_dump(("\nFunction Dump: %s"):format(functions:get_function_name(input)), indent)
			functions:add_to_dump(("\nFunction Upvalues: %s"):format(functions:get_function_name(input)), indent)
			for index, upvalue in pairs(getupvalues(input)) do
				if type(upvalue) == "function" then
					functions:add_to_dump(
						("%d [function] = %s"):format(index, functions:get_function_name(upvalue)),
						indent + 1
					)
				elseif type(upvalue) == "table" then
					if not data_base[upvalue] then
						data_base[upvalue] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(upvalue, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(
						("%d [%s] = %s"):format(index, tostring(typeof(upvalue)), tostring(upvalue)),
						indent + 1
					)
				end
			end
			functions:add_to_dump(("\nFunction Constants: %s"):format(functions:get_function_name(input)), indent)
			for index, constant in pairs(getconstants(input)) do
				if type(constant) == "function" then
					functions:add_to_dump(
						("%d [function] = %s"):format(index, functions:get_function_name(constant)),
						indent + 1
					)
				elseif type(constant) == "table" then
					if not data_base[constant] then
						data_base[constant] = true
						functions:add_to_dump(("%d [table]:"):format(index), indent + 1)
						functions:dump_table(constant, indent + 2, index)
					else
						functions:add_to_dump(("%d [table] (Recursive table detected)"):format(index), indent + 1)
					end
				else
					functions:add_to_dump(
						("%d [%s] = %s"):format(index, tostring(typeof(constant)), tostring(constant)),
						indent + 1
					)
				end
			end
		end
		for _, _function in pairs(env.getgc()) do
			if typeof(_function) == "function" and getfenv(_function).script and getfenv(_function).script == scr then
				functions:dump_function(_function, 0)
				functions:add_to_dump("\n" .. ("="):rep(100), 0, false)
			end
		end
		local source = codeFrame:GetText()

		if dump ~= original then
			source = source .. dump .. "]]"
		end
		codeFrame:SetText(source)

		window:Show()
	end

	local initialized, building, buildError = false, false, nil
	local function buildEditor()
		window.GuiElems.Line.Visible = false
		local content = window.GuiElems.Content
		local theme = Settings.Theme
		local skin = Apps.StudioEditorSkin
		local toolbarCommands = {}
		local function frame(name, y, height)
			return createSimple("Frame", {
				Name = name,
				Parent = content,
				BorderSizePixel = 0,
				BackgroundColor3 = theme.Main2,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, height),
			})
		end
		local tabs = frame("Documents", 0, skin.TabHeight)
		tabs.BackgroundColor3 = skin.Chrome
		local toolbarHost = frame("EditorCommands", 0, 0)
		toolbarHost.Visible = false
		local toolbar = createSimple("ScrollingFrame", {
			Name = "EditorToolbar",
			Parent = toolbarHost,
			Active = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.fromOffset(740, 0),
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ClipsDescendants = true,
		})

		local findBar = frame("FindReplace", skin.TabHeight, skin.FindHeight)
		findBar.Visible = false
		findBar.BackgroundColor3 = skin.Inactive
		findBar.BorderSizePixel = 1
		findBar.BorderColor3 = skin.Border
		findBar.ZIndex = 20
		local replaceVisible = false
		local footer = frame("EditorFooter", 0, skin.FooterHeight)
		footer.Position = UDim2.new(0, 0, 1, -skin.FooterHeight)
		footer.BackgroundColor3 = skin.Chrome
		local function button(parent, text, x, width, callback, enabled)
			local b = createSimple("TextButton", {
				Parent = parent,
				Text = text,
				Position = UDim2.fromOffset(x, 2),
				Size = UDim2.new(0, width, 1, -4),
				BorderSizePixel = 0,
				BackgroundColor3 = theme.ButtonHover,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Interactable = enabled ~= false,
			})
			Lib.StudioText(b)
			b.TextColor3 = enabled == false and theme.PlaceholderText or theme.Text
			b.MouseEnter:Connect(function()
				if b.Interactable then
					b.BackgroundTransparency = 0
				end
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
			b.MouseButton1Click:Connect(callback)
			if parent == toolbar then
				toolbarCommands[#toolbarCommands + 1] = { Label = text, Button = b, Callback = callback }
			end
			if parent == findBar then
				b.ZIndex = 21
			end
			return b
		end
		local function box(parent, name, placeholder, x, y, width)
			local b = createSimple("TextBox", {
				Name = name,
				Parent = parent,
				Text = "",
				PlaceholderText = placeholder,
				ClearTextOnFocus = false,
				Position = UDim2.new(0, x, 0, y),
				Size = width,
				BackgroundColor3 = theme.TextBox,
				BorderColor3 = theme.Outline2,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Lib.StudioText(b)
			if parent == findBar then
				b.ZIndex = 21
				b.BackgroundColor3 = skin.Inactive
				b.BorderColor3 = skin.Border
			end
			createSimple("UIPadding", { Parent = b, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
			return b
		end
		local status = createSimple("TextLabel", {
			Name = "Status",
			Parent = footer,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -145, 1, 0),
			Text = "Ready",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Lib.StudioText(status)
		local location = createSimple("TextLabel", {
			Parent = footer,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -135, 0, 0),
			Size = UDim2.new(0, 127, 1, 0),
			Text = "Ln 1, Col 1  |  Luau",
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		Lib.StudioText(location)
		local function message(text, isError)
			status.Text = tostring(text)
			status.TextColor3 = isError and Color3.fromRGB(255, 125, 125) or theme.PlaceholderText
		end
		codeFrame = Lib.CodeFrame.new()
		codeFrame.Frame.Parent = content
		codeFrame.Frame.BackgroundTransparency = 0
		skin.Apply(codeFrame)

		local placed = false
		local function fitWindow()
			if window.Aligned or not window:IsVisible() then
				return
			end
			if window.StopTweens then
				window:StopTweens()
			end
			local viewport = window.Gui.AbsoluteSize
			local width = viewport.X > 0 and viewport.X or Main.Mouse.ViewSizeX
			local height = viewport.Y > 0 and viewport.Y or Main.Mouse.ViewSizeY
			local w = math.min(900, math.max(300, width - 48))
			local h = math.min(640, math.max(220, height - 48))
			if not placed then
				window:Resize(w, h)
				window.GuiElems.Main.Position = UDim2.fromOffset(
					math.max(0, math.floor((width - w) / 2)),
					math.max(0, math.floor((height - h) / 2))
				)
				placed = true
			else
				w = math.min(window.SizeX or w, math.max(300, width - 24))
				h = math.min(window.SizeY or h, math.max(220, height - 24))
				window:Resize(w, h)
				local pos = window.GuiElems.Main.AbsolutePosition
				window.GuiElems.Main.Position = UDim2.fromOffset(
					math.clamp(pos.X, 0, math.max(0, width - w)),
					math.clamp(pos.Y, 0, math.max(0, height - h))
				)
			end
		end
		window.OnActivate:Connect(fitWindow)
		window.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
		ScriptViewer.CodeFrame = codeFrame
		local globalSearchView, globalSearchSession
		local function layout()
			local top = skin.TabHeight
			local width = math.min(skin.FindWidth, math.max(160, content.AbsoluteSize.X - 14))
			findBar.Position = UDim2.new(1, -width - 14, 0, top)
			findBar.Size = UDim2.fromOffset(width, replaceVisible and skin.ReplaceHeight or skin.FindHeight)
			codeFrame.Frame.Position = UDim2.fromOffset(0, top)
			codeFrame.Frame.Size = UDim2.new(1, 0, 1, -top - skin.FooterHeight)
		end
		layout()
		local documents, closed = {}, {}
		local active, restoring, sequence = nil, false, 0
		local initializing = true
		local renderTabs, tabStrip
		local mutationDepth, mutationRecorded = 0, false
		local function copyAdditional(ranges)
			local result = {}
			for index, range in ipairs(ranges or {}) do
				local r = { { range[1][1], range[1][2] }, { range[2][1], range[2][2] } }
				if range.Caret then
					r.Caret = { range.Caret[1], range.Caret[2] }
				end
				result[index] = r
			end
			return result
		end
		local function snapshot(source)
			local range = codeFrame.SelectionRange or { { -1, -1 }, { -1, -1 } }
			return {
				text = source or codeFrame:GetText(),
				x = codeFrame.CursorX,
				y = codeFrame.CursorY,
				selection = { { range[1][1], range[1][2] }, { range[2][1], range[2][2] } },
				additional = copyAdditional(codeFrame.AdditionalSelections),
			}
		end
		local function historyAliases(doc)
			doc.history = doc.undoStack._entries
			doc.index = doc.undoStack._pointer
		end
		local function boundary()
			if active then
				active.undoStack:updateSelection(snapshot(active.text))
				active.undoStack:flush()
				historyAliases(active)
			end
		end
		local function remember(state)
			if not active then
				return
			end
			state = state or snapshot()
			active.text = state.text
			active.x = state.x
			active.y = state.y
			active.selection = state.selection
			active.additional = copyAdditional(state.additional)
			active.overwrite = codeFrame.OverwriteMode or false
			active.undoStack:updateSelection(state)
			active.vx = codeFrame.ViewX
			active.vy = codeFrame.ViewY
		end
		local function restore(state, restoreFolds)
			restoring = true
			codeFrame:SetText(state.text)
			if restoreFolds then
				Apps.CodeViewport.RestoreFolds(codeFrame, state.folds)
			end
			local range = state.selection or { { -1, -1 }, { -1, -1 } }
			codeFrame.SelectionRange = { { range[1][1], range[1][2] }, { range[2][1], range[2][2] } }
			codeFrame.AdditionalSelections = copyAdditional(state.additional)
			if state.overwrite ~= nil then
				codeFrame.OverwriteMode = state.overwrite
			end
			codeFrame:MoveCursor(state.x or 0, state.y or 0)
			codeFrame:SetCopyableSelection()
			restoring = false
		end
		ScriptViewer.SelectDocument = function(doc)
			if active == doc then
				return
			end
			if ScriptViewer.CloseEditorContextMenu then
				ScriptViewer.CloseEditorContextMenu()
			end
			if tabStrip then
				tabStrip:HideMenu()
			end
			remember()
			if active then
				active.folds = Apps.CodeViewport.GetCollapsedFolds(codeFrame)
			end
			boundary()
			if ScriptViewer.CancelDefinitionNavigation then
				ScriptViewer.CancelDefinitionNavigation()
			end
			active = doc
			PreviousScr = doc.script
			ScriptViewer.ActiveScript = doc.script
			ScriptViewer.ActiveDocument = doc
			if ScriptViewer.CloseNavigation then
				ScriptViewer.CloseNavigation()
			end
			if ScriptViewer.DismissCompletion then
				ScriptViewer.DismissCompletion()
			end
			codeFrame:ResetFolds()
			findBar.Visible = false
			codeFrame.SearchVisible = false
			codeFrame.SearchMatches = {}
			layout()
			local savedVX, savedVY = doc.vx, doc.vy
			restore(doc, true)
			if not doc.historyInitialized then
				doc.undoStack:reset(snapshot())
				doc.historyInitialized = true
				historyAliases(doc)
				remember()
			end
			codeFrame.ScrollV:ScrollTo(savedVY or 0)
			codeFrame.ScrollH:ScrollTo(savedVX or 0)
			window:SetTitle(doc.title .. " - Script Editor")
			message("Ready")
			renderTabs()
		end
		ScriptViewer.RefreshGeneratedDocument = function(doc, source)
			if not doc or doc.dirty or doc.GeneratedSource == source or doc.text == source then
				return false
			end
			if active == doc then
				boundary()
			end
			doc.GeneratedSource = source
			doc.text = source
			doc.folds = nil
			doc.x = 0
			doc.y = 0
			doc.selection = { { -1, -1 }, { -1, -1 } }
			doc.undoStack:reset(doc)
			historyAliases(doc)
			doc.historyInitialized = true
			if active == doc then
				codeFrame:ResetFolds()
				restore(doc, true)
				renderTabs()
			end
			return true
		end
		ScriptViewer.OpenDocument = function(id, title, text, scriptObject, recovery)
			for _, doc in ipairs(documents) do
				if doc.id == id then
					ScriptViewer.SelectDocument(doc)
					if not initializing then
						window:Show()
					end
					return doc
				end
			end
			local doc = {
				id = id,
				title = title,
				text = text or "",
				script = scriptObject,
				x = 0,
				y = 0,
				dirty = false,
				overwrite = false,
			}
			if recovery then
				doc.x, doc.y, doc.vx, doc.vy, doc.dirty =
					recovery.x, recovery.y, recovery.vx, recovery.vy, recovery.dirty
			end
			doc.undoStack = Apps.EditorUndoStack.new(doc)
			historyAliases(doc)
			documents[#documents + 1] = doc
			if recovery and recovery.deferSelection then
				return doc
			end
			ScriptViewer.SelectDocument(doc)
			if not initializing then
				window:Show()
			end
			return doc
		end
		ScriptViewer.OpenReferenceResult = function(result)
			if result.Kind == "Bytecode" then
				ScriptViewer.ViewScript(result.Object)
				if not ScriptViewer.ActiveDocument or ScriptViewer.ActiveDocument.script ~= result.Object then
					return ScriptViewer.ActiveDocument
				end
				ScriptViewer.HighlightReference(result)
				return ScriptViewer.ActiveDocument
			end
			local id = result.DocumentId
			for _, doc in ipairs(documents) do
				local text = doc == active and codeFrame:GetText() or doc.text
				if doc.id == result.DocumentId and text ~= result.Source then
					id = {}
				end
				if doc.script == result.Object and text == result.Source then
					id = doc.id
					break
				end
			end
			local doc = ScriptViewer.OpenDocument(id, result.Object.Name .. " (reference)", result.Source)
			ScriptViewer.HighlightReference(result)
			return doc
		end
		ScriptViewer.CloseDocument = function(doc)
			local index = table.find(documents, doc)
			if not index then
				return
			end
			remember()
			if active == doc then
				doc.folds = Apps.CodeViewport.GetCollapsedFolds(codeFrame)
			end
			boundary()
			table.remove(documents, index)
			closed[#closed + 1] = doc
			if #closed > 10 then
				table.remove(closed, 1)
			end
			if active == doc then
				active = nil
				if #documents > 0 then
					ScriptViewer.SelectDocument(documents[math.min(index, #documents)])
				else
					ScriptViewer.NewDocument(true)
				end
			else
				renderTabs()
			end
			message("Tab closed. Ctrl+Shift+T reopens it with its edits.")
		end
		ScriptViewer.NewDocument = function(internal)
			if not internal and ScriptViewer.NewScriptDialog then
				ScriptViewer.NewScriptDialog:Show(active and active.script)
				return
			end
			sequence += 1
			return ScriptViewer.OpenDocument({}, "Untitled " .. sequence, "")
		end
		ScriptViewer.NewScriptDialog = Apps.EditorNewScript.Create(content, window, function(parent, className, name)
			local explorer = Apps.Explorer
			local created = Apps.InsertionService.Insert(className, { { Obj = parent } }, {
				GetName = function()
					return name
				end,
				DefaultProperties = className == "LocalScript" and { BaseScript = { Disabled = true } } or nil,
			})
			local object = assert(created[1], "Script creation returned no object")
			explorer.SyncHistoryObject(object)
			explorer.SelectService(object)
			explorer.ViewObj(object)
			return ScriptViewer.OpenDocument(object, object.Name, "", object)
		end)
		tabStrip = Apps.EditorTabs.Create(tabs, window, {
			Select = function(doc)
				ScriptViewer.SelectDocument(doc)
			end,
			Close = function(doc)
				ScriptViewer.CloseDocument(doc)
			end,
		})
		ScriptViewer.TabStrip = tabStrip
		renderTabs = function()
			tabStrip:Update(documents, active)
			dumpbtn.Interactable = env.getgc ~= nil and PreviousScr ~= nil
			dumpbtn.TextColor3 = dumpbtn.Interactable and theme.Text or theme.PlaceholderText
		end
		local process = codeFrame.ProcessTextChange
		codeFrame.ProcessTextChange = function(self, ...)
			local old = self.Text
			process(self, ...)
			if restoring or not active or old == self.Text then
				return
			end
			local state = snapshot()
			active.undoStack:record(state)
			historyAliases(active)
			mutationRecorded = true
			if not active.dirty then
				active.dirty = true
				renderTabs()
			end
			remember(state)
			if ScriptViewer.RefreshFind and findBar.Visible then
				local source = self.Text
				task.defer(function()
					if Main.Alive and findBar.Visible and codeFrame.Text == source then
						ScriptViewer.RefreshFind(false)
					end
				end)
			end
		end
		for _, name in ipairs({ "AppendText", "DeleteRange", "SetText" }) do
			local operation = codeFrame[name]
			codeFrame[name] = function(self, ...)
				if mutationDepth > 0 then
					return operation(self, ...)
				end
				mutationRecorded = false
				if active and not restoring then
					active.undoStack:updateSelection(snapshot(active.text))
				end
				mutationDepth = 1
				local result = table.pack(pcall(operation, self, ...))
				mutationDepth = 0
				if active and not restoring then
					remember(snapshot(active.text))
				end
				if not result[1] then
					error(result[2], 0)
				end
				return table.unpack(result, 2, result.n)
			end
		end
		local updateCursor = codeFrame.UpdateCursor
		codeFrame.UpdateCursor = function(self, ...)
			updateCursor(self, ...)
			location.Text = ("Ln %d, Col %d  |  Luau"):format(self.CursorY + 1, self.CursorX + 1)
			if active and not restoring and (mutationDepth == 0 or mutationRecorded) then
				active.undoStack:updateSelection(snapshot(active.text))
			end
		end
		ScriptViewer.Undo = function(redo)
			if not active or codeFrame.Editable == false then
				return
			end
			local state
			if redo then
				state = active.undoStack:redo()
			else
				state = active.undoStack:undo()
			end
			if not state then
				return
			end
			historyAliases(active)
			restore(state)
			remember()
			if ScriptViewer.RefreshFind and findBar.Visible then
				ScriptViewer.RefreshFind(false)
			end
			message(redo and "Redo" or "Undo")
		end
		ScriptViewer.CanUndo = function(redo)
			if not active or codeFrame.Editable == false then
				return false
			end
			if redo then
				return active.undoStack:canRedo()
			end
			return active.undoStack:canUndo()
		end
		ScriptViewer.SelectRelativeDocument = function(direction)
			local index = table.find(documents, active) or 1
			ScriptViewer.SelectDocument(documents[(index - 1 + direction) % #documents + 1])
		end
		local findView
		local findModel = Apps.EditorFindModel
		local findDocument = Apps.EditorDocument.Create("")
		local findDocumentText
		local matchSource, matchQuery, matchOptions, matches, matchIndex, searchError = nil, nil, nil, {}, 0, nil
		local findTicket = 0
		local function currentFindDocument()
			if findDocumentText ~= codeFrame.Text then
				findDocument:SetText(codeFrame:GetText())
				findDocumentText = codeFrame.Text
			end
			return findDocument
		end
		local function position(offset)
			local document = currentFindDocument()
			local line, column = document:PositionToLineColumn(offset)
			local prefix = document:GetLine(line):sub(1, column - 1)
			return { #codeFrame:ConvertText(prefix, true), line - 1 }
		end
		local function currentFindSelection()
			local selected = ScriptViewer.GetSelectionState()
			local current = matches[matchIndex]
			local matchesSelection = current and selected.First == current.Start and selected.Last == current.Finish
			return selected.Caret, matchesSelection
		end
		local function publishSearch()
			codeFrame.SearchVisible = findBar.Visible and findView.Find.Text ~= ""
			codeFrame.SearchMatches = matches
			codeFrame.SearchActiveIndex = matchIndex
			findView:SetResults(matchIndex, #matches, searchError, codeFrame.Editable ~= false)
		end
		local function scan()
			local source, query = currentFindDocument():GetText(), findView.Find.Text
			local state = findView.Options
			local signature = tostring(state.MatchCase) .. tostring(state.WholeWord) .. tostring(state.Regex)
			if source == matchSource and query == matchQuery and signature == matchOptions then
				return
			end
			matchSource, matchQuery, matchOptions = source, query, signature
			matchIndex = 0
			local result = query == "" and { Matches = {} } or findModel.Search(source, query, state)
			matches, searchError = result.Matches, result.Error
			publishSearch()
		end
		local function selectMatch(match)
			local first, last = position(match.Start), position(match.Finish)
			codeFrame.AdditionalSelections = {}
			codeFrame.SelectionRange = { first, last }
			codeFrame:MoveCursor(last[1], last[2])
			codeFrame:RevealSourceLine(first[2])
			local lines = codeFrame.GuiElems.LinesFrame or codeFrame.Frame
			local scroll = Apps.CodeViewport.ScrollPixelX(codeFrame)
			local left = codeFrame:GetColumnPixelX(first[1], first[2])
			local right = if first[2] == last[2] then codeFrame:GetColumnPixelX(last[1], last[2]) else left
			local width = math.max(1, lines.AbsoluteSize.X - 8)
			local columnWidth = Apps.CodeViewport.ColumnWidth(codeFrame)
			if left < scroll or right - left > width then
				codeFrame.ScrollH:ScrollTo(math.max(0, math.floor(left / columnWidth)))
			elseif right > scroll + width then
				codeFrame.ScrollH:ScrollTo(math.max(0, math.ceil((right - width) / columnWidth)))
			end
			local top = codeFrame:SourceToDisplay(first[2]) or first[2]
			local bottom = codeFrame:SourceToDisplay(last[2]) or last[2]
			local viewHeight = math.max(1, math.floor(lines.AbsoluteSize.Y / codeFrame.FontSize))
			local clearance = 0
			if
				findBar.Visible
				and (
					first[2] ~= last[2]
					or right
						>= findBar.AbsolutePosition.X - lines.AbsolutePosition.X + Apps.CodeViewport.ScrollPixelX(
							codeFrame
						)
				)
			then
				clearance = math.min(viewHeight - 1, math.ceil(findBar.Size.Y.Offset / codeFrame.FontSize))
			end
			local current = codeFrame.ViewY
			local latestTop = math.max(0, top - clearance)
			local earliestTop = math.max(0, math.min(bottom - viewHeight + 1, latestTop))
			local target = math.clamp(current, earliestTop, latestTop)
			if target ~= current then
				codeFrame.ScrollV:ScrollTo(target)
			end
		end
		local function showMatch()
			local match = matches[matchIndex]
			if not match then
				publishSearch()
				codeFrame:Refresh()
				return false
			end
			selectMatch(match)
			if service.UserInputService:GetFocusedTextBox() == codeFrame.GuiElems.EditBox then
				codeFrame:SetCopyableSelection()
			end
			publishSearch()
			codeFrame:Refresh()
			return true
		end
		ScriptViewer.FindNext = function(backward)
			findTicket += 1
			scan()
			if #matches == 0 then
				publishSearch()
				message(searchError or "No matches", searchError ~= nil)
				return false
			end
			local wrapped
			local caret, continueMatch = currentFindSelection()
			matchIndex, wrapped = findModel.Step(matches, caret, backward, continueMatch and matchIndex or nil)
			showMatch()
			message(
				wrapped and (backward and "Search wrapped to end" or "Search wrapped to start")
					or matchIndex .. " of " .. #matches .. " matches"
			)
			return true
		end
		ScriptViewer.RefreshFind = function(selectMatch)
			findTicket += 1
			scan()
			if selectMatch and #matches > 0 then
				local caret, sameMatch = currentFindSelection()
				if not sameMatch then
					matchIndex = findModel.Step(matches, caret, false, nil)
				end
				showMatch()
			else
				publishSearch()
				codeFrame:Refresh()
			end
		end
		ScriptViewer.Replace = function(all)
			if codeFrame.Editable == false then
				return false
			end
			findTicket += 1
			scan()
			if searchError or #matches == 0 then
				message(searchError or "No matches", searchError ~= nil)
				return false
			end
			if not all then
				local caret, matchesSelection = currentFindSelection()
				if not matchesSelection then
					matchIndex = findModel.Step(matches, caret, false, nil)
				end
			end
			local replacement = findView.Replace.Text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "    ")
			local result = all and findModel.ReplaceAll(codeFrame:GetText(), matches, replacement)
				or findModel.Replace(codeFrame:GetText(), matches[matchIndex], replacement)
			if result.Error then
				message(result.Error, true)
				return false
			end
			boundary()
			codeFrame.AdditionalSelections = {}
			codeFrame:SetText(result.Text)
			local caret = position(result.Caret)
			codeFrame.SelectionRange = { caret, caret }
			codeFrame:MoveCursor(caret[1], caret[2])
			codeFrame:SetCopyableSelection()
			boundary()
			matchSource = nil
			scan()
			if not all and #matches > 0 then
				matchIndex = findModel.Step(matches, result.Caret, false, nil)
				showMatch()
			else
				publishSearch()
				codeFrame:Refresh()
			end
			message("Replaced " .. result.Count .. " match" .. (result.Count == 1 and "" or "es"))
			return true
		end
		local function closeFind()
			findTicket += 1
			findBar.Visible = false
			codeFrame.SearchVisible = false
			codeFrame:Refresh()
			codeFrame.GuiElems.EditBox:CaptureFocus()
		end
		local function setReplace(show)
			replaceVisible = show == true
			findView:SetReplace(replaceVisible)
			layout()
		end
		findView = Apps.EditorFindWidget.Attach(findBar, {
			Next = function(backward)
				ScriptViewer.FindNext(backward)
			end,
			Replace = function(all)
				ScriptViewer.Replace(all)
			end,
			Close = closeFind,
			ToggleReplace = setReplace,
			OptionsChanged = function()
				ScriptViewer.RefreshFind(true)
			end,
		})
		local findBox, replaceBox = findView.Find, findView.Replace
		ScriptViewer.FindWidget = findView
		ScriptViewer.CloseFind = closeFind
		ScriptViewer.GetMultiCursorMatchOptions = function()
			return { MatchCase = findView.Options.MatchCase, WholeWord = findView.Options.WholeWord }
		end
		ScriptViewer.SetWholeWord = function(value)
			findView:SetOptions({ WholeWord = value })
			ScriptViewer.RefreshFind(true)
		end
		ScriptViewer.SetMatchCase = function(value)
			findView:SetOptions({ MatchCase = value })
			ScriptViewer.RefreshFind(true)
		end
		ScriptViewer.SetRegex = function(value)
			findView:SetOptions({ Regex = value })
			ScriptViewer.RefreshFind(true)
		end
		findBox:GetPropertyChangedSignal("Text"):Connect(function()
			findTicket += 1
			local ticket = findTicket
			task.delay(0.12, function()
				if ticket == findTicket and Main.Alive and findBar.Visible then
					ScriptViewer.RefreshFind(true)
				end
			end)
		end)
		findBox.FocusLost:Connect(function(enter)
			if enter then
				ScriptViewer.FindNext(Lib.IsShiftDown())
				findBox:CaptureFocus()
			end
		end)
		replaceBox.FocusLost:Connect(function(enter)
			if enter then
				ScriptViewer.FindNext(Lib.IsShiftDown())
				replaceBox:CaptureFocus()
			end
		end)
		local function openFind(replace)
			local selected = codeFrame:GetSelectionText()
			findBar.Visible = true
			setReplace(replace == true)
			if selected ~= "" and not selected:find("\n", 1, true) then
				findBox.Text = selected
			end
			ScriptViewer.RefreshFind(false)
			if replace then
				replaceBox:CaptureFocus()
			else
				findBox:CaptureFocus()
			end
		end
		ScriptViewer.OpenFind = openFind
		ScriptViewer.HighlightReference = function(result)
			findTicket += 1
			findBar.Visible = true
			setReplace(false)
			findView.Find.Text = result.TargetName
			findView:SetOptions({
				MatchCase = true,
				WholeWord = result.TargetName:sub(1, 1):match("[%w_]") ~= nil
					and result.TargetName:sub(-1):match("[%w_]") ~= nil,
				Regex = false,
			})
			matchSource = nil
			scan()
			local source = codeFrame:GetText()
			local bodyStart = 1
			if source:sub(1, 15) == "-- Script Path:" then
				local ending = source:find("\n\n", 1, true)
				if ending then
					bodyStart = ending + 2
				end
			end
			local codeMatches = {}
			for _, match in ipairs(matches) do
				if match.Start >= bodyStart then
					codeMatches[#codeMatches + 1] = match
				end
			end
			matches = codeMatches
			matchIndex = 0
			local preferred = bodyStart
			if result.Line then
				preferred = Apps.EditorDocument
					.Create(source)
					:LineColumnToPosition(result.Line, result.EditorColumn or result.Column or 1)
			end
			local distance = math.huge
			for index, match in ipairs(matches) do
				local delta = math.abs(match.Start - preferred)
				if delta < distance then
					distance = delta
					matchIndex = index
				end
			end
			if matchIndex == 0 then
				publishSearch()
				codeFrame:Refresh()
				message("No matching name in the available code", true)
				return false
			end
			showMatch()
			codeFrame:SetCopyableSelection()
			codeFrame.GuiElems.EditBox:CaptureFocus()
			message(matchIndex .. " of " .. #matches .. " matches")
			return true
		end
		local function globalDocument(group, open)
			for _, doc in ipairs(documents) do
				if doc == group.Document or group.Object and (doc.script == group.Object or doc.id == group.Object) then
					return doc
				end
			end
			if open then
				return ScriptViewer.OpenDocument(group.Object or {}, group.Name or "Script", group.Source, group.Object)
			end
		end
		globalSearchSession = Apps.EditorGlobalSearch.Create({
			NormalizeSource = function(source: string): string
				if string.find(source, "\t", 1, true) then
					source = codeFrame:ConvertText(source, true)
				end
				if string.find(source, "\r", 1, true) then
					source = string.gsub(source, "\r\n?", "\n")
				end
				return source
			end,
			GetDocuments = function()
				return documents
			end,
			GetActiveText = function(doc)
				return doc == active and codeFrame:GetText() or doc.text
			end,
			ReadCurrent = function(group)
				local doc = globalDocument(group)
				if doc then
					return doc == active and codeFrame:GetText() or doc.text
				end
			end,
			Apply = function(group, text)
				if codeFrame.Editable == false then
					error("The editor is read-only.")
				end
				local doc = globalDocument(group, true)
				window:Show()
				ScriptViewer.SelectDocument(doc)
				boundary()
				codeFrame.AdditionalSelections = {}
				codeFrame:SetText(text)
				boundary()
			end,
			OnChanged = function(state)
				if globalSearchView then
					globalSearchView:Update(state)
				end
			end,
		})
		local function globalReplacement(result)
			if result.Error then
				message(result.Error, true)
			else
				message("Replaced " .. result.Count .. " matches in editor buffers")
				globalSearchView:Refresh()
			end
		end
		local searchWindow = Lib.Window.new()
		searchWindow:SetTitle("Find in Place")
		searchWindow.MinX = 350
		searchWindow.MinY = 170
		searchWindow:Resize(410, 440)
		if searchWindow.SetResizeHandleStyle then
			searchWindow:SetResizeHandleStyle("Dock")
		end
		ScriptViewer.FindInPlaceWindow = searchWindow
		globalSearchView = Apps.EditorGlobalSearchWidget.Attach(searchWindow.GuiElems.Content, {
			OnSearch = function(query, options)
				globalSearchSession:Start(query, options)
			end,
			OnCancel = function()
				globalSearchSession:Cancel()
			end,
			OnClose = function()
				if not findBar.Visible then
					codeFrame.SearchVisible = false
					codeFrame.SearchMatches = {}
					codeFrame.SearchActiveIndex = 0
					codeFrame:Refresh()
				end
			end,
			OnLayout = layout,
			OnNavigate = function(group, match)
				local hits = group.Matches
				if group.Compiled then
					local state = globalSearchSession.State
					ScriptViewer.ViewScript(group.Object)
					if not active or active.id ~= group.Object or globalSearchSession.State ~= state then
						return
					end
					window:Show()
					local source = codeFrame:GetText()
					local headerEnd = source:sub(1, 15) == "-- Script Path:" and source:find("\n\n", 1, true)
					if group.ResolvedSource == source then
						match = table.find(hits, match) and match or hits[1]
					else
						local options = state.Options
						local result = Apps.EditorFindModel.Search(source, state.Query, {
							MatchCase = options.MatchCase,
							WholeWord = options.WholeWord,
							Regex = options.Regex,
							Scope = { Start = headerEnd and headerEnd + 2 or 1 },
							MaxMatches = math.max(1, 20000 - state.MatchCount + #group.Matches),
							WorkLimit = 1000000,
						})
						hits = result.Matches
						match = hits[1]
						if not match then
							message(result.Error or "The compiled match was not found in the available source.", true)
							return
						end
						local line, start, stop = 1, 1, source:find("\n", 1, true) or #source + 1
						for _, hit in ipairs(hits) do
							while stop < hit.Start do
								line += 1
								start = stop + 1
								stop = source:find("\n", start, true) or #source + 1
							end
							local clip = math.max(start, hit.Start - 80)
							while clip < hit.Start and source:byte(clip) >= 128 and source:byte(clip) < 192 do
								clip += 1
							end
							local finish = math.min(stop, clip + 240)
							while
								finish > clip
								and finish <= #source
								and source:byte(finish) >= 128
								and source:byte(finish) < 192
							do
								finish -= 1
							end
							hit.Line = line
							hit.SnippetColumn = hit.Start - clip + 1
							hit.Text = source:sub(clip, finish - 1)
						end
						state.MatchCount += #hits - #group.Matches
						group.Matches = hits
						group.ResolvedSource = source
						state.ResultRevision = (state.ResultRevision or 0) + 1
						globalSearchView:Update(state)
					end
				else
					local doc = globalDocument(group, true)
					window:Show()
					ScriptViewer.SelectDocument(doc)
					if codeFrame:GetText() ~= group.Source then
						message("Script changed. Search again to update its results.", true)
						return
					end
				end
				findTicket += 1
				findBar.Visible = false
				selectMatch(match)
				codeFrame.SearchVisible = true
				codeFrame.SearchMatches = hits
				codeFrame.SearchActiveIndex = table.find(hits, match) or 0
				codeFrame:SetCopyableSelection()
				codeFrame:Refresh()
			end,
			OnReplace = function(group, match, text)
				globalReplacement(globalSearchSession:Replace(group, match, text))
			end,
			OnReplaceAll = function(text, groups)
				globalReplacement(globalSearchSession:ReplaceAll(text, groups))
			end,
		})
		ScriptViewer.GlobalSearch = globalSearchSession
		ScriptViewer.GlobalSearchWidget = globalSearchView
		globalSearchView.Frame.Size = UDim2.fromScale(1, 1)
		ScriptViewer.OpenFindAll = function(showReplace, query)
			query = query or (active and codeFrame:GetSelectionText())
			searchWindow:Show()
			globalSearchView:Open(showReplace, query)
		end
		searchWindow.OnDeactivate:Connect(function()
			globalSearchView:Close()
		end)
		ScriptViewer.CloseFindAll = function()
			searchWindow:Close()
		end
		Main.AddCleanup(function()
			globalSearchSession:Destroy()
		end)
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		button(toolbar, "Copy", 4, 44, function()
			if env.setclipboard then
				env.setclipboard(codeFrame:GetText())
				message("Copied")
			end
		end, env.setclipboard ~= nil)
		button(toolbar, "Save", 50, 44, function()
			Lib.SaveAsPrompt("Place_" .. game.PlaceId .. "_Script_" .. os.time() .. ".luau", codeFrame:GetText())
		end, env.writefile ~= nil)
		dumpbtn = button(toolbar, "Functions", 96, 76, function()
			if PreviousScr then
				local ok, err = pcall(ScriptViewer.DumpFunctions, PreviousScr)
				message(ok and "Functions appended" or err, not ok)
			end
		end, false)
		button(toolbar, "Undo", 176, 46, function()
			ScriptViewer.Undo(false)
		end)
		button(toolbar, "Redo", 224, 46, function()
			ScriptViewer.Undo(true)
		end)
		button(toolbar, "Find", 274, 44, function()
			openFind(false)
		end)
		execute = button(toolbar, "Run", 322, 42, function()
			if not env.loadstring then
				return
			end
			local source = codeFrame:GetText()
			message("Running…")
			task.spawn(function()
				local ok, fn, err = pcall(env.loadstring, source)
				if not ok or type(fn) ~= "function" then
					message("Compile error: " .. tostring(ok and err or fn), true)
					return
				end
				local success, result = pcall(fn)
				message(success and "Execution completed" or "Runtime error: " .. tostring(result), not success)
			end)
		end, env.loadstring ~= nil)
		execute.TextColor3 = env.loadstring and theme.Focus or theme.PlaceholderText
		clear = button(toolbar, "Clear", 366, 44, function()
			boundary()
			codeFrame.AdditionalSelections = {}
			codeFrame:ResetSelection(true)
			codeFrame:SetText("")
			codeFrame:MoveCursor(0, 0)
			codeFrame:SetCopyableSelection()
			boundary()
		end)
		local gotoBox = box(toolbar, "GoToLine", "Line…", 416, 4, UDim2.fromOffset(64, 24))
		gotoBox.FocusLost:Connect(function(enter)
			if enter then
				local n = tonumber(gotoBox.Text)
				if n then
					local row = math.clamp(math.floor(n), 1, #codeFrame.Lines) - 1
					codeFrame.AdditionalSelections = {}
					codeFrame.SelectionRange = { { 0, row }, { 0, row } }
					codeFrame:MoveCursor(0, row)
					codeFrame.ScrollV:ScrollTo(
						math.max(0, (codeFrame:SourceToDisplay(codeFrame.CursorY) or codeFrame.CursorY) - 2)
					)
					codeFrame:SetCopyableSelection()
					codeFrame:Refresh()
					codeFrame.GuiElems.EditBox:CaptureFocus()
				else
					message("Enter a line number", true)
				end
			end
		end)
		local add = button(tabs, "+", 0, 28, function()
			ScriptViewer.NewDocument()
		end)
		add.Name = "NewScript"
		add.Position = UDim2.new(1, -56, 0, 0)
		add.Size = UDim2.new(0, 28, 1, 0)
		add.Font = Enum.Font.Arial
		add.TextSize = 22
		add.TextScaled = false
		Lib.StudioTooltip(add, "New script (Ctrl+N)")
		gotoBox.Parent = footer
		gotoBox.Position = UDim2.new(1, -204, 0, 0)
		gotoBox.Size = UDim2.fromOffset(64, 22)
		gotoBox.Visible = false
		gotoBox.FocusLost:Connect(function()
			gotoBox.Visible = false
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			local focused = service.UserInputService:GetFocusedTextBox()
			if
				globalSearchView.Visible
				and (
					focused == globalSearchView.Find
					or focused == globalSearchView.Replace
					or focused == globalSearchView.Filter
				)
			then
				if input.KeyCode == Enum.KeyCode.Escape then
					searchWindow:Close()
				elseif input.KeyCode == Enum.KeyCode.F3 then
					globalSearchView:Next(Lib.IsShiftDown())
				elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
					globalSearchView:Next(input.KeyCode == Enum.KeyCode.Up)
				end
				return
			end
			if not window:IsVisible() then
				return
			end
			if
				focused ~= codeFrame.GuiElems.EditBox
				and focused ~= findBox
				and focused ~= replaceBox
				and focused ~= gotoBox
			then
				return
			end
			local key = input.KeyCode
			local inlineQuery = findBar.Visible and (focused == findBox or focused == replaceBox) and findBox.Text
				or nil
			if Lib.IsCtrlDown() then
				if key == Enum.KeyCode.Tab then
					ScriptViewer.SelectRelativeDocument(Lib.IsShiftDown() and -1 or 1)
					if focused ~= codeFrame.GuiElems.EditBox then
						codeFrame.GuiElems.EditBox:CaptureFocus()
					end
				elseif key == Enum.KeyCode.F then
					if Lib.IsShiftDown() then
						ScriptViewer.OpenFindAll(false, inlineQuery)
					else
						openFind(false)
					end
				elseif key == Enum.KeyCode.H then
					if Lib.IsShiftDown() then
						ScriptViewer.OpenFindAll(true, inlineQuery)
					else
						openFind(true)
					end
				elseif key == Enum.KeyCode.G then
					gotoBox.Visible = true
					gotoBox:CaptureFocus()
				elseif key == Enum.KeyCode.N then
					ScriptViewer.NewDocument()
				elseif key == Enum.KeyCode.W then
					ScriptViewer.CloseDocument(active)
				elseif key == Enum.KeyCode.T and Lib.IsShiftDown() and #closed > 0 then
					local doc = table.remove(closed)
					documents[#documents + 1] = doc
					ScriptViewer.SelectDocument(doc)
				end
			elseif key == Enum.KeyCode.F3 then
				if globalSearchView.Visible and not findBar.Visible then
					globalSearchView:Next(Lib.IsShiftDown())
				else
					ScriptViewer.FindNext(Lib.IsShiftDown())
				end
			elseif key == Enum.KeyCode.Escape then
				if findBar.Visible then
					closeFind()
				end
			end
		end)
		ScriptViewer.Documents = documents
		Apps.EditorController.Attach(ScriptViewer, codeFrame, window, {
			Message = message,
			BeforeCommand = boundary,
			AfterCommand = boundary,
			FindPanel = findBar,
			NewScriptOverlay = ScriptViewer.NewScriptDialog.Gui,
			FindInPlaceWindow = searchWindow,
		})
		local editorMenu
		local commands = button(toolbar, "Edit", 486, 44, function()
			local menu = editorMenu or Apps.ContextMenu.new()
			editorMenu = menu
			menu:Clear()
			for _, item in ipairs({
				{ "Indent", "Tab", "Indent" },
				{ "Unindent", "Shift+Tab", "Outdent" },
				{ "Toggle Comment", "Ctrl+/", "ToggleComment" },
				{ "Duplicate Line", "", "DuplicateLines" },
				{ "Move Line Up", "Alt+Up", "MoveLinesUp" },
				{ "Move Line Down", "Alt+Down", "MoveLinesDown" },
				{ "Delete Line", "Ctrl+Shift+K", "DeleteLines" },
			}) do
				local command = item[3]
				menu:Add({
					Text = item[1],
					Shortcut = item[2],
					OnClick = function()
						ScriptViewer.Command(command)
						codeFrame.GuiElems.EditBox:CaptureFocus()
					end,
				})
			end
			menu:Show(Main.Mouse.X, Main.Mouse.Y)
		end)
		commands.Name = "EditCommands"
		Lib.StudioTooltip(commands, "Indentation, comments and line commands")
		local complete = button(toolbar, "Complete", 534, 76, function()
			codeFrame.GuiElems.EditBox:CaptureFocus()
			ScriptViewer.Complete()
		end)
		complete.Name = "Complete"
		Lib.StudioTooltip(complete, "Complete word (Ctrl+Space)")
		local check = button(toolbar, "Check", 614, 52, function()
			ScriptViewer.CheckSyntax()
		end)
		check.Name = "CheckSyntax"
		Lib.SetNativeIcon(check, "native/editor/analysis")
		Lib.StudioTooltip(check, "Check syntax without executing the script")
		local diagnostic = button(toolbar, "Error", 670, 50, function()
			ScriptViewer.GoToDiagnostic()
		end)
		diagnostic.Name = "GoToError"
		Lib.StudioTooltip(diagnostic, "Go to the last reported syntax error")
		local commandMenu
		local menuButton = button(tabs, "...", 0, 26, function()
			local menu = commandMenu or Apps.ContextMenu.new()
			commandMenu = menu
			menu:Clear()
			for _, item in ipairs(toolbarCommands) do
				local command = item
				menu:Add({
					Text = command.Label,
					Disabled = not command.Button.Interactable,
					OnClick = function()
						if command.Button.Interactable then
							command.Callback()
						end
					end,
				})
			end
			menu:Add({ Text = "Script Function Filter", Shortcut = "Alt+F", OnClick = ScriptViewer.OpenFunctionFilter })
			menu:Add({
				Text = "Go to Definition",
				Shortcut = "F12",
				OnClick = function()
					ScriptViewer.GoToDeclaration()
				end,
			})
			menu:Add({ Text = "Open Scripts", Shortcut = "Ctrl+P", OnClick = ScriptViewer.OpenScriptPicker })
			menu:Add({
				Text = "Find All",
				Shortcut = "Ctrl+Shift+F",
				OnClick = function()
					ScriptViewer.OpenFindAll(false)
				end,
			})
			menu:Add({
				Text = "Replace All",
				Shortcut = "Ctrl+Shift+H",
				OnClick = function()
					ScriptViewer.OpenFindAll(true)
				end,
			})
			menu:Add({
				Text = "Show Script in Explorer",
				Shortcut = "Ctrl+Alt+K",
				Disabled = ScriptViewer.ActiveScript == nil,
				OnClick = ScriptViewer.ShowScriptInExplorer,
			})
			menu:Add({
				Text = "Go to Line…",
				Shortcut = "Ctrl+G",
				OnClick = function()
					gotoBox.Visible = true
					gotoBox:CaptureFocus()
				end,
			})
			if active and Apps.PluginActions then
				local document = active
				Apps.PluginActions.AddMenu(menu, "Editor", function()
					return Apps.PluginActions.EditorContext(ScriptViewer, codeFrame)
				end, function(callback)
					return function()
						if active == document then
							callback()
						end
					end
				end)
			end
			menu:Show(Main.Mouse.X, Main.Mouse.Y)
		end)
		menuButton.Name = "DocumentCommands"
		menuButton.Position = UDim2.new(1, -28, 0, 0)
		Lib.StudioTooltip(menuButton, "Editor commands")
		ScriptViewer.NewDocument(true)
		initializing = false
	end

	ensureEditor = function()
		if initialized or building then
			return
		end
		if buildError then
			error(buildError, 0)
		end
		if not window then
			ScriptViewer.Init(true)
		end
		building = true
		local ok, problem = pcall(buildEditor)
		building = false
		if not ok then
			buildError = tostring(problem)
			error(buildError, 0)
		end
		initialized = true
	end
	ScriptViewer.EnsureEditor = ensureEditor
	ScriptViewer.Init = function(deferred)
		if not window then
			window = Lib.Window.new()
			window:SetTitle("Script Editor")
			window.MinX = 340
			window.MinY = 260
			window:Resize(900, 600)
			ScriptViewer.Window = window
			window.OnActivate:Connect(ensureEditor)
			window.OnRestore:Connect(ensureEditor)
		end
		if not deferred then
			ensureEditor()
		end
	end
	local lazyFields =
		{ Documents = true, CodeFrame = true, TabStrip = true, FindWidget = true, NewScriptDialog = true }
	lazyFields["SetWholeWord"] = true
	lazyFields["RefreshFind"] = true
	lazyFields["SelectDocument"] = true
	lazyFields["FindNext"] = true
	lazyFields["Undo"] = true
	lazyFields["SetRegex"] = true
	lazyFields["CloseDocument"] = true
	lazyFields["HighlightReference"] = true
	lazyFields["CloseFind"] = true
	lazyFields["OpenReferenceResult"] = true
	lazyFields["GetMultiCursorMatchOptions"] = true
	lazyFields["OpenFind"] = true
	lazyFields["OpenFindAll"] = true
	lazyFields["CloseFindAll"] = true
	lazyFields["GlobalSearch"] = true
	lazyFields["GlobalSearchWidget"] = true
	lazyFields["NewDocument"] = true
	lazyFields["OpenDocument"] = true
	lazyFields["SelectRelativeDocument"] = true
	lazyFields["Replace"] = true
	lazyFields["RefreshGeneratedDocument"] = true
	lazyFields["CanUndo"] = true
	lazyFields["SetMatchCase"] = true
	setmetatable(ScriptViewer, {
		__index = function(self, key)
			if lazyFields[key] and not building then
				ensureEditor()
				return rawget(self, key)
			end
		end,
	})

	ScriptViewer.ViewScript = function(scr, shouldOpen)
		if ensureEditor then
			ensureEditor()
		end
		if shouldOpen and not shouldOpen() then
			return nil
		end
		local generated = Apps.ModuleReconstruction and Apps.ModuleReconstruction.GetSource(scr)
		for _, doc in ipairs(ScriptViewer.Documents) do
			if doc.id == scr then
				if generated and ScriptViewer.RefreshGeneratedDocument then
					ScriptViewer.RefreshGeneratedDocument(doc, generated)
				end
				ScriptViewer.SelectDocument(doc)
				window:Show()
				return doc
			end
		end
		if generated then
			local doc = ScriptViewer.OpenDocument(scr, scr.Name, generated, nil)
			if doc then
				doc.GeneratedSource = generated
			end
			window:Show()
			return doc
		end
		local oldtick = tick()
		local success, decompiled = pcall(env.decompile or function() end, scr)
		if shouldOpen and not shouldOpen() then
			return nil
		end

		local source
		if not success or type(decompiled) ~= "string" then
			local readable, rawSource = pcall(function()
				return scr.Source
			end)
			if readable and type(rawSource) == "string" and (rawSource ~= "" or executorName == "Studio") then
				return ScriptViewer.OpenDocument(scr, scr.Name, rawSource, scr)
			end
			PreviousScr = nil
			dumpbtn.TextColor3 = Color3.new(0.5, 0.5, 0.5)
			source = "-- Unable to view source.\n"
			source = source .. "-- Script Path: " .. getPath(scr) .. "\n"
			local hasContext, context = false, nil
			if scr.ClassName == "Script" then
				hasContext, context = pcall(function()
					return scr.RunContext
				end)
			end
			if hasContext and (context == Enum.RunContext.Legacy or context == Enum.RunContext.Server) then
				source = source
					.. "-- Reason: The script is not running on client. (attempt to decompile ServerScript or 'Script' with RunContext Server)\n"
			elseif not env.decompile then
				source = source
					.. "-- Reason: Your executor does not support decompiler. (missing 'decompile' function)\n"
			else
				source = source .. "-- Reason: Unknown\n"
			end
			source = source .. "-- Executor: " .. executorName .. " (" .. executorVersion .. ")"
		else
			PreviousScr = scr
			dumpbtn.TextColor3 = Color3.new(1, 1, 1)

			if Apps.ReferenceSource then
				Apps.ReferenceSource.Store(scr, decompiled, "Cached decompiled source")
			end

			source = "-- Script Path: " .. getPath(scr) .. "\n"
			source = source .. "-- Took " .. tostring(math.floor((tick() - oldtick) * 100) / 100) .. "s to decompile.\n"
			source = source .. "-- Executor: " .. executorName .. " (" .. executorVersion .. ")\n\n"

			source = source .. decompiled
		end

		return ScriptViewer.OpenDocument(scr, scr.Name, source, PreviousScr)
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
else
	return { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
end
