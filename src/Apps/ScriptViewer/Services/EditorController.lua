--!strict

local Main, Apps, Lib, Settings, service, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, Lib, Settings, service, env = d.Main, d.Apps, d.Lib, d.Settings, d.service, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Controller = {}
	function Controller.Attach(viewer, cf, window, options)
		local document = Apps.EditorDocument.Create(cf:GetText())
		local frameText = cf.Text
		local indexedDocument = viewer.ActiveDocument
		local moduleRevision = 0
		local language = Apps.EditorLanguage.New()
		local completionLanguage = Apps.EditorLanguage.New()
		local apiDocumentation = Apps.EditorApiDocumentation
		local content = window.GuiElems.Content
		local function node(class, props)
			local object = Instance.new(class)
			for key, value in pairs(props) do
				object[key] = value
			end
			return object
		end
		local completion, selected = nil, 1
		local completionView = Apps.EditorCompletion.Create(content, cf, function(index)
			selected = index
			viewer.AcceptCompletion(true)
		end, function(index)
			selected = index
		end)
		local popup = completionView.Gui
		local hover = Apps.EditorHover.Create(content, cf)
		local hoverTicket = 0
		local hoverTarget
		local hoverLeaving = false
		local analysisTicket = 0
		local generation = 0
		local completionAttempt = 0
		local typing = false
		local refreshCompletion
		local syntax = { Available = false, Message = "Not checked" }
		local function hideHover()
			if not hoverTarget and not hoverLeaving and not hover.Gui.Visible then return end
			hoverTicket += 1
			hoverTarget = nil
			hoverLeaving = false
			hover.Gui.Visible = false
		end
		local function sync()
			if indexedDocument ~= viewer.ActiveDocument then
				indexedDocument = viewer.ActiveDocument
				moduleRevision += 1
			end
			if frameText ~= cf.Text then
				frameText = cf.Text
				local source = cf:GetText()
				local changedLine = source == frameText
					and document:GetText() == cf.PreviousText
					and cf.ChangedTextRow
					or nil
				document:SetText(source, changedLine)
			end
		end
		local function offset(point)
			local y = math.clamp(point[2] or 0, 0, #cf.Lines - 1)
			local prefix = (cf.Lines[y + 1] or ""):sub(1, math.max(0, point[1] or 0))
			if cf.ConvertText then
				prefix = cf:ConvertText(prefix, false)
			end
			return document:LineColumnToPosition(y + 1, #prefix + 1)
		end
		function viewer.GetEditorOffset(column, row)
			sync()
			return offset({ column, row })
		end
		local function point(position)
			local y, x = document:PositionToLineColumn(position)
			local prefix = document:GetLine(y):sub(1, x - 1)
			if cf.ConvertText then
				prefix = cf:ConvertText(prefix, true)
			end
			return { #prefix, y - 1 }
		end
		local function selection()
			sync()
			local range = cf.SelectionRange
			if range and range[1][1] >= 0 and (range[1][1] ~= range[2][1] or range[1][2] ~= range[2][2]) then
				local first, last = offset(range[1]), offset(range[2])
				if offset({ cf.CursorX, cf.CursorY }) == first then
					return last, first
				end
				return first, last
			end
			local caret = offset({ cf.CursorX, cf.CursorY })
			return caret, caret
		end
		local function ranges()
			local anchor, caret = selection()
			local all = { { Anchor = anchor, Caret = caret, Id = 1 } }
			for index, range in ipairs(cf.AdditionalSelections or {}) do
				local first, last = offset(range[1]), offset(range[2])
				local caret = offset(range.Caret or range[2])
				all[#all + 1] = { Anchor = caret == first and last or first, Caret = caret, Id = index + 1 }
			end
			return all
		end
		function viewer.GetSelections()
			local all = ranges()
			return Apps.EditorSelectionSet.Normalize(document:GetText(), all)
		end
		function viewer.GetSelectionState()
			local anchor, caret = selection()
			return {
				Anchor = anchor,
				Caret = caret,
				First = math.min(anchor, caret),
				Last = math.max(anchor, caret),
				Selected = anchor ~= caret,
			}
		end
		local apply, readOpenModuleSource
		local signatureView = Apps.EditorSignature.Create(content, cf, language, function()
			local active = viewer.ActiveDocument
			return {
				Game = game,
				Workspace = workspace,
				Script = viewer.ActiveScript or (active and typeof(active.id) == "Instance" and active.id or nil),
				Document = active,
				ModuleSource = readOpenModuleSource,
				ModuleRevision = moduleRevision,
			}
		end, function(target, value)
			if cf.Editable == false or viewer.ActiveDocument ~= target.Document or cf:GetText() ~= target.Source then
				return
			end
			local position = target.First + #value
			apply({
				Text = target.Source:sub(1, target.First - 1) .. value .. target.Source:sub(target.Last),
				Anchor = position,
				Caret = position,
				Changed = true,
			})
		end)
		local signatureTicket = 0
		local function workBudget(valid, noYield)
			local started = os.clock()
			return function()
				if not valid() then
					return false
				end
				local elapsed = os.clock() - started
				if task.wait and elapsed >= 0.003 then
					if Main.Performance then
						Main.Performance.Record("editor/analysis-slice", elapsed)
					end
					if noYield then
						return false
					end
					task.wait()
					started = os.clock()
				end
				return valid()
			end
		end
		local function hideSignature()
			signatureTicket += 1
			signatureView:Hide()
		end
		viewer.SignatureHelp = signatureView.Gui
		function viewer.UpdateSignature(checkpoint)
			sync()
			signatureView:Update(offset({ cf.CursorX, cf.CursorY }), checkpoint)
		end
		local function scheduleSignature()
			signatureTicket += 1
			local ticket = signatureTicket
			task.delay(0.08, function()
				if
					ticket == signatureTicket
					and Main.Alive
					and window:IsVisible()
					and not (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
					and service.UserInputService:GetFocusedTextBox() == cf.GuiElems.EditBox
				then
					local source, active = cf.Text, viewer.ActiveDocument
					viewer.UpdateSignature(workBudget(function()
						return ticket == signatureTicket
							and Main.Alive
							and window:IsVisible()
							and cf.Text == source
							and viewer.ActiveDocument == active
					end))
				end
			end)
		end
		local pendingNative
		local clipboardInput
		local function nativeKeyMatches(key, text)
			if key == Enum.KeyCode.Tab then
				return text == "\t" or text == "    "
			end
			return text == "\n" or text == "\r" or text == "\r\n"
		end
		local function suppressNativeKey(text, native)
			local pending = pendingNative
			if pending then
				if os.clock() <= pending.Expires and nativeKeyMatches(pending.Key, text) then
					return true
				end
				pendingNative = nil
			end
			if not native then
				return false
			end
			local user = service.UserInputService
			if text == "\t" or (text == "    " and user:IsKeyDown(Enum.KeyCode.Tab)) then
				return true
			end
			return nativeKeyMatches(Enum.KeyCode.Return, text)
				and not Lib.IsCtrlDown()
				and not Lib.IsShiftDown()
				and not user:IsKeyDown(Enum.KeyCode.LeftAlt)
				and not user:IsKeyDown(Enum.KeyCode.RightAlt)
				and (user:IsKeyDown(Enum.KeyCode.Return) or user:IsKeyDown(Enum.KeyCode.KeypadEnter))
		end
		local function touchKeyboard()
			local input = service.UserInputService
			return input.TouchEnabled and (not input.KeyboardEnabled or input.OnScreenKeyboardVisible
				or input:GetLastInputType() == Enum.UserInputType.Touch)
		end
		local function resetNativeBuffer()
			cf:SetCopyableSelection()
		end
		function cf.HandleNativeTextChange(_, text)
			if
				service.UserInputService:GetFocusedTextBox() ~= cf.GuiElems.EditBox
				or cf.Editable == false
				or (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
			then
				resetNativeBuffer()
				return true
			end
			if cf.TouchTextInput and not clipboardInput and not Lib.IsCtrlDown() then
				local previous = cf.NativeInputBuffer or ""
				local caret = cf.GuiElems.EditBox.CursorPosition
				local expected = (cf.NativeSelectionEnd or #previous + 1) + #text - #previous
				if not caret or caret <= 0 or caret == cf.NativeSelectionEnd then caret = expected end
				caret = Apps.EditorDocument.ClampSelectionPosition(text, math.clamp(caret, 1, #text + 1))
				apply({Text = text, Changed = text ~= cf:GetText(), Anchor = caret, Caret = caret})
				return true
			end
			local operation = clipboardInput
			if operation and operation.Document ~= viewer.ActiveDocument then
				resetNativeBuffer()
				return true
			end
			if not operation and Lib.IsCtrlDown() then
				local user = service.UserInputService
				if user:IsKeyDown(Enum.KeyCode.V) then
					operation = { Kind = "Paste" }
				elseif user:IsKeyDown(Enum.KeyCode.X) then
					operation = { Kind = "Cut" }
				elseif
					user:IsKeyDown(Enum.KeyCode.Z)
					or user:IsKeyDown(Enum.KeyCode.Y)
					or user:IsKeyDown(Enum.KeyCode.Backspace)
					or user:IsKeyDown(Enum.KeyCode.Delete)
				then
					operation = { Kind = "Suppress" }
				end
			end
			if not operation then
				if suppressNativeKey(text, true) then
					resetNativeBuffer()
					return true
				end
				return false
			end
			operation.Document = viewer.ActiveDocument
			clipboardInput = operation
			if not operation.Applied then
				operation.Applied = true
				if operation.Kind == "Paste" then
					viewer.PasteText(text)
				elseif operation.Kind == "Cut" and text == "" then
					viewer.CaptureClipboardPacket()
					viewer.DeleteClipboardSelection()
				end
			end
			resetNativeBuffer()
			return true
		end
		local function clipboardShortcut(kind, callback)
			if clipboardInput and clipboardInput.Kind == kind and clipboardInput.Applied then
				return true
			end
			clipboardInput = { Kind = kind, Document = viewer.ActiveDocument }
			if callback and callback() then
				clipboardInput.Applied = true
			end
			return true
		end
		local function closeCompletion()
			generation += 1
			refreshCompletion = nil
			completion = nil
			popup.Visible = false
		end
		function viewer.SelectAll()
			closeCompletion()
			cf.AdditionalSelections = {}
			local last = #cf.Lines - 1
			local column = #cf.Lines[last + 1]
			cf.SelectionRange = { { 0, 0 }, { column, last } }
			cf:MoveCursor(column, last)
			cf:SetCopyableSelection()
			cf:Refresh()
			cf.GuiElems.EditBox:CaptureFocus()
		end
		local function consumeNative(key)
			pendingNative = { Key = key, Expires = os.clock() + 0.25 }
		end
		local function pointerInsidePopup()
			local mouse = Main.Mouse
			if not mouse or not popup.Visible then
				return false
			end
			return completionView:ContainsPoint(mouse.X, mouse.Y)
		end
		function viewer.DismissCompletion()
			closeCompletion()
			hideSignature()
			hideHover()
		end
		local preferredColumns = {}
		local preferredDocument
		function apply(result)
			if result.Changed then
				table.clear(preferredColumns)
				if options.BeforeCommand then
					options.BeforeCommand()
				end
				cf:SetText(result.Text)
			end
			sync()
			local anchor, caret = point(result.Anchor), point(result.Caret)
			local function ordered(a, c)
				if a[2] > c[2] or a[2] == c[2] and a[1] > c[1] then
					return { c, a, Caret = c }
				end
				return { a, c, Caret = c }
			end
			cf.SelectionRange = ordered(anchor, caret)
			cf.AdditionalSelections = {}
			for index, range in ipairs(result.Ranges or {}) do
				if index > 1 then
					local a, c = point(range.Anchor), point(range.Caret)
					cf.AdditionalSelections[#cf.AdditionalSelections + 1] = ordered(a, c)
				end
			end
			cf:MoveCursor(caret[1], caret[2])
			cf:SetCopyableSelection()
			cf:Refresh()
			if options.AfterCommand then
				options.AfterCommand()
			end
			return result.Changed
		end
		viewer.ApplyEditorEdit = apply
		local function normalizeInput(text)
			return text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "    ")
		end
		local cursorDrag
		local pointerClick
		local function setSelections(all)
			sync()
			closeCompletion()
			table.clear(preferredColumns)
			local normalized = Apps.EditorSelectionSet.Normalize(document:GetText(), all)
			table.sort(normalized, function(a, b)
				return a.Id < b.Id
			end)
			if #normalized == 0 then
				return false
			end
			return apply({
				Text = document:GetText(),
				Anchor = normalized[1].Anchor,
				Caret = normalized[1].Caret,
				Ranges = normalized,
				Changed = false,
			})
		end
		local function nextId(all)
			local id = 0
			for _, range in ipairs(all) do
				id = math.max(id, range.Id)
			end
			return id + 1
		end
		function viewer.RemoveLastCursor()
			local all = ranges()
			if #all > 1 then
				table.remove(all)
				setSelections(all)
				return true
			end
			return false
		end
		local addingColumn
		function viewer.AddCursorLine(direction)
			local all = ranges()
			local last = all[#all]
			local line, column = document:PositionToLineColumn(last.Caret)
			local target = line + direction
			if target < 1 or target > document:GetLineCount() then
				return false
			end
			local at = point(last.Caret)
			if
				not addingColumn
				or addingColumn.Document ~= viewer.ActiveDocument
				or addingColumn.Caret ~= last.Caret
				or addingColumn.Source ~= document:GetText()
			then
				addingColumn = {
					Document = viewer.ActiveDocument,
					Source = document:GetText(),
					Column = column,
					Pixel = cf.GetColumnPixelX and cf:GetColumnPixelX(at[1], at[2]),
				}
			end
			local position
			if addingColumn.Pixel and cf.GetPixelColumn then
				position = offset({ cf:GetPixelColumn(addingColumn.Pixel, target - 1), target - 1 })
			else
				position = document:LineColumnToPosition(target, addingColumn.Column)
			end
			for _, range in ipairs(all) do
				if range.Caret == position then
					return false
				end
			end
			all[#all + 1] = { Anchor = position, Caret = position, Id = nextId(all) }
			setSelections(all)
			addingColumn.Caret = position
			return true
		end
		local function seedMatchingSelection(all)
			local primary = all[1]
			if primary.Anchor ~= primary.Caret then
				return false
			end
			local source = document:GetText()
			local position = primary.Caret
			local function word(at)
				local byte = source:byte(at)
				return byte and (byte >= 128 or source:sub(at, at):match("[%w_]"))
			end
			if not word(position) and position > 1 then
				position = utf8.offset(source, -1, position) or position
			end
			if not word(position) then
				return false
			end
			local first, last = position, position
			while first > 1 do
				local previous = utf8.offset(source, -1, first)
				if not previous or not word(previous) then
					break
				end
				first = previous
			end
			while last <= #source and word(last) do
				last = utf8.offset(source, 2, last) or #source + 1
			end
			primary.Anchor, primary.Caret = first, last
			setSelections(all)
			return true
		end
		function viewer.AddMatchingCursors(every)
			local all = ranges()
			local seeded = seedMatchingSelection(all)
			if seeded and not every then
				return true
			end
			all = ranges()
			local primary = all[1]
			local first, last = math.min(primary.Anchor, primary.Caret), math.max(primary.Anchor, primary.Caret)
			if first == last then
				return false
			end
			local source = document:GetText()
			local searchOptions = viewer.GetMultiCursorMatchOptions and viewer.GetMultiCursorMatchOptions()
				or { MatchCase = true }
			local found = Apps.EditorFindModel.Search(source, source:sub(first, last - 1), searchOptions)
			if found.Error then
				return false
			end
			local function overlaps(match, range)
				return match.Start < range.Last and match.Finish > range.First
					or range.First == range.Last and match.Start <= range.First and range.First <= match.Finish
			end
			local id = nextId(all)
			local function add(match)
				all[#all + 1] = { Anchor = match.Start, Caret = match.Finish, Id = id }
				id += 1
			end
			local ordered = Apps.EditorSelectionSet.Normalize(source, all, document)
			local function occupied(match, index)
				local range = ordered[index]
				while range and (range.Last < match.Start or range.Last == match.Start and range.First < range.Last) do
					index += 1
					range = ordered[index]
				end
				return range and overlaps(match, range), index
			end
			if every then
				local index = 1
				for _, match in ipairs(found.Matches) do
					local conflict
					conflict, index = occupied(match, index)
					if not conflict then
						add(match)
					end
				end
			else
				local latest = all[#all]
				local after = math.max(latest.Anchor, latest.Caret)
				local candidates = found.Matches
				for pass = 1, 2 do
					local added = false
					local index = 1
					for _, match in ipairs(candidates) do
						if pass == 1 and match.Start >= after or pass == 2 and match.Start < after then
							local conflict
							conflict, index = occupied(match, index)
							if not conflict then
								add(match)
								added = true
								break
							end
						end
					end
					if added then
						break
					end
				end
			end
			setSelections(all)
			return true
		end
		function viewer.SplitSelectionsIntoLines()
			local all = ranges()
			local result = {}
			for _, range in ipairs(all) do
				local first, last = math.min(range.Anchor, range.Caret), math.max(range.Anchor, range.Caret)
				local firstLine, lastLine = document:SelectedLines(first, last)
				for line = firstLine, lastLine do
					local start = math.max(first, document:LineColumnToPosition(line, 1))
					local finish = math.min(last, document:LineColumnToPosition(line, #document:GetLine(line) + 1))
					result[#result + 1] = {
						Anchor = range.Anchor > range.Caret and finish or start,
						Caret = range.Anchor > range.Caret and start or finish,
						Id = #result + 1,
					}
				end
			end
			setSelections(result)
			return true
		end
		function viewer.Command(command, commandOptions)
			if cf.Editable == false then
				return false
			end
			closeCompletion()
			if commandOptions and commandOptions.Text then
				commandOptions = table.clone(commandOptions)
				commandOptions.Text = normalizeInput(commandOptions.Text)
			end
			local all = ranges()
			return apply(
				Apps.EditorSelectionSet.Apply(document:GetText(), all, command, commandOptions or { Indent = "    " }, document)
			)
		end
		local function renderCompletion()
			completionView:Render(completion, selected)
		end
		local function documentationReady()
			if Main.Alive and completion and popup.Visible then
				renderCompletion()
			end
			local target = hoverTarget
			if Main.Alive and window:IsVisible() and target and target.Item and hover.Gui.Visible then
				local item = apiDocumentation.Apply(target.Item)
				hover:Show(
					item.HoverDetail or item.Detail or "",
					item.Documentation,
					target.Row,
					target.First,
					false,
					item.DocumentationFormat,
					item.Url
				)
			end
			if
				Main.Alive
				and window:IsVisible()
				and signatureView.Gui.Visible
				and not (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
				and service.UserInputService:GetFocusedTextBox() == cf.GuiElems.EditBox
			then
				scheduleSignature()
			end
		end
		apiDocumentation.Load(documentationReady)
		readOpenModuleSource = function(module)
			for _, doc in ipairs(viewer.Documents or {}) do
				if
					(doc.script == module or doc.id == module)
					and not doc.GeneratedSource
					and not doc.text:match("^%-%- Unable to view source%.")
				then
					if doc == viewer.ActiveDocument then
						sync()
						return document:GetText()
					end
					return doc.text
				end
			end
		end
		local function complete(keepSelection, noYield)
			if cf.Editable == false then
				closeCompletion()
				return false
			end
			sync()
			local anchor, caret = selection()
			if anchor ~= caret then
				closeCompletion()
				return false
			end
			local source = document:GetText()
			local active = viewer.ActiveDocument
			local object = viewer.ActiveScript or (active and typeof(active.id) == "Instance" and active.id or nil)
			local previous = keepSelection and completion
			local previousItem = previous and previous.Items[selected]
			local ticket = generation
			completionAttempt += 1
			local attempt = completionAttempt
			local frameSource = cf.Text
			local function valid()
				return ticket == generation
					and Main.Alive
					and window:IsVisible()
					and frameSource == cf.Text
					and active == viewer.ActiveDocument
			end
			local function moduleRequestValid()
				return valid() and service.UserInputService:GetFocusedTextBox() == cf.GuiElems.EditBox
			end
			local checkpoint = workBudget(function()
				return attempt == completionAttempt and valid()
			end, noYield)
			local result = completionLanguage:Complete(source, caret, {
				Game = game,
				Workspace = workspace,
				Script = object,
				ModuleSource = readOpenModuleSource,
				ModuleRevision = moduleRevision,
				ModuleRequestValid = moduleRequestValid,
				OnModuleReady = function()
					if moduleRequestValid() then
						complete(true)
					end
				end,
			}, checkpoint)
			if attempt ~= completionAttempt or not valid() then
				return false
			end
			completion = result
			selected = 1
			if completion then
				if previousItem and previous.First == completion.First then
					for index, item in ipairs(completion.Items) do
						if item.Name == previousItem.Name and item.Kind == previousItem.Kind then
							selected = index
							break
						end
					end
				end
				completion.Source = source
				completion.Anchor = anchor
				completion.Caret = caret
				apiDocumentation.Load(documentationReady)
			end
			renderCompletion()
			return completion ~= nil
		end
		function viewer.Complete()
			generation += 1
			refreshCompletion = nil
			return complete(false)
		end
		local function afterTyping(before, trigger)
			if cf.Text == before then
				return
			end
			generation += 1
			if not trigger or #cf.Text > 1000000 or #cf.Lines > 5000 then
				closeCompletion()
				return
			end
			local ticket = generation
			local activeDocument = viewer.ActiveDocument
			local x, y = cf.CursorX, cf.CursorY
			local function refresh(noYield)
				if refreshCompletion ~= refresh then
					return
				end
				refreshCompletion = nil
				if
					ticket ~= generation
					or not Main.Alive
					or not window:IsVisible()
					or viewer.ActiveDocument ~= activeDocument
					or cf.CursorX ~= x
					or cf.CursorY ~= y
					or (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
					or service.UserInputService:GetFocusedTextBox() ~= cf.GuiElems.EditBox
				then
					return
				end
				complete(true, noYield)
			end
			refreshCompletion = refresh
			task.delay(0.06, refresh)
		end
		local function retargetCompletion()
			sync()
			local anchor, caret = selection()
			local text = document:GetText()
			local oldCaret = completion.Caret
			local added = caret - oldCaret
			if anchor ~= caret or added <= 0 or #text ~= #completion.Source + added then
				return false
			end
			local prefix = text:sub(completion.First, caret - 1)
			local item = completion.Items[selected]
			local name = item.Name:lower()
			if
				oldCaret <= completion.First
				or not prefix:match("^[%a_][%w_]*$")
				or name:sub(1, #prefix) ~= prefix:lower()
				or (#name == #prefix and not item.InsertCall)
				or text:sub(1, oldCaret - 1) ~= completion.Source:sub(1, oldCaret - 1)
				or text:sub(caret) ~= completion.Source:sub(oldCaret)
			then
				return false
			end
			completion.Source = text
			completion.Anchor, completion.Caret = anchor, caret
			completion.Last += added
			return true
		end
		function viewer.AcceptCompletion(insertOnly)
			if not completion or cf.Editable == false then
				return false
			end
			sync()
			local anchor, caret = selection()
			local result = completion
			if document:GetText() ~= result.Source or anchor ~= result.Anchor or caret ~= result.Caret then
				closeCompletion()
				return false
			end
			local item = result.Items[selected]
			local insertion = item.InsertText or item.Name
			local text = document:GetText()
			local first = result.First
			local ending = insertOnly and caret or result.Last
			local moveInside = false
			if ending == result.Last and item.InsertCall then
				if item.MethodSeparator and text:sub(item.MethodSeparator, item.MethodSeparator) == "." then
					insertion = ":" .. text:sub(item.MethodSeparator + 1, first - 1) .. insertion
					first = item.MethodSeparator
				end
				if not text:match([=[^%s*[%({"']]=], ending) and not text:match("^%s*%[=*%[", ending) then
					insertion ..= "()"
					moveInside = item.HasParameters ~= false
				end
			end
			local position = first + #insertion - (moveInside and 1 or 0)
			local updated = text:sub(1, first - 1) .. insertion .. text:sub(ending)
			local currentRanges = ranges()
			currentRanges[1].Anchor, currentRanges[1].Caret = position, position
			local delta = #insertion - (ending - first)
			local function map(p)
				return if p <= first then p elseif p < ending then position else p + delta
			end
			for index = 2, #currentRanges do
				local range = currentRanges[index]
				range.Anchor, range.Caret = map(range.Anchor), map(range.Caret)
			end
			local normalized = Apps.EditorSelectionSet.Normalize(updated, currentRanges)
			table.sort(normalized, function(a, b)
				return a.Id < b.Id
			end)
			closeCompletion()
			apply({
				Text = updated,
				Anchor = position,
				Caret = position,
				Ranges = normalized,
				Changed = updated ~= text,
			})
			if service.UserInputService:GetFocusedTextBox() ~= cf.GuiElems.EditBox then
				cf.GuiElems.EditBox:CaptureFocus()
			end
			if moveInside then
				scheduleSignature()
			end
			return true
		end
		local clipboardPacket
		local function readClipboardSelection()
			local all = ranges()
			return Apps.EditorSelectionSet.Copy(document:GetText(), all, document)
		end
		function viewer.CaptureClipboardPacket()
			clipboardPacket = readClipboardSelection()
			return clipboardPacket
		end
		local copyBuffer = cf.SetCopyableSelection
		cf.SetCopyableSelection = function(self, ...)
			local focused = service.UserInputService:GetFocusedTextBox()
			if focused and focused ~= self.GuiElems.EditBox then
				return
			end
			if not viewer.ActiveDocument then
				return copyBuffer(self, ...)
			end
			if self.TouchTextInput then
				sync()
				local text = document:GetText()
				local anchor, caret = selection()
				local box = self.GuiElems.EditBox
				self.EditBoxCopying = true
				self.NativeInputBuffer = text
				self.NativeSelectionEnd = math.max(anchor, caret)
				if box.Text ~= text then box.Text = text end
				box.CursorPosition = caret
				box.SelectionStart = if anchor ~= caret then anchor else -1
				self.EditBoxCopying = false
				return
			end
			local packet = readClipboardSelection()
			local box = self.GuiElems.EditBox
			self.EditBoxCopying = true
			self.NativeInputBuffer = packet.Text
			box.Text = packet.Text
			box.SelectionStart = 1
			box.CursorPosition = #packet.Text + 1
			self.EditBoxCopying = false
		end
		Main.TrackSignal(cf.GuiElems.EditBox.Focused, function()
			cf.TouchTextInput = touchKeyboard()
			if cf.TouchTextInput then cf:SetCopyableSelection() end
		end)
		Main.TrackSignal(cf.GuiElems.EditBox.FocusLost, function()
			cf.TouchTextInput = false
		end)
		function viewer.DeleteClipboardSelection()
			if cf.Editable == false then
				return false
			end
			local all = ranges()
			for _, range in ipairs(all) do
				if range.Anchor == range.Caret then
					local line = document:PositionToLineColumn(range.Caret)
					range.Anchor = document:LineColumnToPosition(line, 1)
					range.Caret = line < document:GetLineCount() and document:LineColumnToPosition(line + 1, 1)
						or #document:GetText() + 1
				end
			end
			return apply(Apps.EditorSelectionSet.Apply(document:GetText(), all, "Delete", { Indent = "    " }))
		end
		function viewer.CopySelection(cut)
			if cut and cf.Editable == false then
				return false
			end
			local packet = readClipboardSelection()
			if type(env.setclipboard) ~= "function" then
				clipboardPacket = packet
				return false
			end
			local ok, problem = pcall(env.setclipboard, packet.Text)
			if not ok then
				if options.Message then
					options.Message("Clipboard failed: " .. tostring(problem), true)
				end
				return false
			end
			clipboardPacket = packet
			if cut then
				viewer.DeleteClipboardSelection()
			end
			return true
		end
		function viewer.CutSelection()
			return viewer.CopySelection(true)
		end
		function viewer.PasteText(text)
			if cf.Editable == false then
				return false
			end
			local plain = normalizeInput(text)
			local packet
			if clipboardPacket and clipboardPacket.Text == text then
				packet = { Text = plain, Entries = {}, WholeLines = clipboardPacket.WholeLines }
				for index, value in ipairs(clipboardPacket.Entries) do
					packet.Entries[index] = normalizeInput(value)
				end
			end
			local all = ranges()
			local source = document:GetText()
			local result = Apps.EditorSelectionSet.Paste(source, all, plain, packet, document)
			if result.Changed and #result.Insertions > 0 then
				result = Apps.EditorFormatter.Edit(result.Text, result.Ranges, true, "    ", result.Insertions)
				result.Changed = result.Text ~= source
			end
			return apply(result)
		end
		function viewer.PasteFromClipboard()
			if type(env.getclipboard) ~= "function" or cf.Editable == false then
				return false
			end
			local ok, text = pcall(env.getclipboard)
			if not ok or type(text) ~= "string" then
				if options.Message then
					options.Message("Clipboard could not be read", true)
				end
				return false
			end
			return viewer.PasteText(text)
		end
		local function updateDiagnostics()
			sync()
			local source, owner, ticket = document:GetText(), viewer.ActiveDocument, analysisTicket
			local function current()
				return Main.Alive and viewer.ActiveDocument == owner and analysisTicket == ticket
			end
			local record = Apps.EditorParser.ParseDocument(document, workBudget(current))
			if not record or not current() or cf:GetText() ~= source then return nil end
			syntax = record.Diagnostics
			sync()
			local ranges = {}
			for _, diagnostic in syntax.Errors do
				local start = document:LineColumnToPosition(diagnostic.Line, diagnostic.Column)
				local finish = document:LineColumnToPosition(diagnostic.EndLine, diagnostic.EndColumn)
				local first, last = point(start), point(finish)
				ranges[#ranges + 1] = { First = first, Last = last, Message = diagnostic.Message }
			end
			cf.SyntaxRanges = ranges
			viewer.Diagnostics = syntax
			viewer.DiagnosticRevision = document.Revision
			cf:Refresh()
			return syntax
		end
		function viewer.CheckSyntax()
			analysisTicket += 1
			if not updateDiagnostics() then return syntax end
			if options.Message then
				options.Message(syntax.Message, syntax.Available and not syntax.Passed)
			end
			return syntax
		end
		function viewer.GoToDiagnostic()
			if not syntax.Line then
				return false
			end
			closeCompletion()
			local row = math.clamp(syntax.Line - 1, 0, #cf.Lines - 1)
			cf.AdditionalSelections = {}
			local column = if cf.SyntaxRanges and cf.SyntaxRanges[1] then cf.SyntaxRanges[1].First[1] else 0
			cf.SelectionRange = { { column, row }, { column, row } }
			cf:MoveCursor(column, row)
			cf:SetCopyableSelection()
			cf:Refresh()
			cf.GuiElems.EditBox:CaptureFocus()
			return true
		end
		function viewer.SetFontSize(size)
			table.clear(preferredColumns)
			cf.FontSize = math.clamp(math.floor(size), 10, 32)
			cf:UpdateView()
			cf:Refresh()
			cf:UpdateCursor()
			return cf.FontSize
		end
		local function moveSelections(key, extend, word)
			local all = ranges()
			local source = document:GetText()
			local vertical = key == Enum.KeyCode.Up
				or key == Enum.KeyCode.Down
				or key == Enum.KeyCode.PageUp
				or key == Enum.KeyCode.PageDown
			if not vertical or preferredDocument ~= viewer.ActiveDocument then
				table.clear(preferredColumns)
			end
			preferredDocument = viewer.ActiveDocument
			local function adjacent(p, direction)
				if Apps.CodeViewport.LineGeometry then
					local at = point(p)
					local bytes = Apps.CodeViewport.LineGeometry(cf, at[2]).Bytes
					local low, high = 1, #bytes
					while low <= high do
						local middle = math.floor((low + high) / 2)
						if bytes[middle] < at[1] or direction > 0 and bytes[middle] == at[1] then
							low = middle + 1
						else
							high = middle - 1
						end
					end
					local column = bytes[direction < 0 and high or low]
					if column then
						return offset({ column, at[2] })
					end
				end
				return document:AdjacentPosition(p, direction)
			end
			for _, range in ipairs(all) do
				local caret = range.Caret
				if not extend and range.Anchor ~= caret and (key == Enum.KeyCode.Left or key == Enum.KeyCode.Right) then
					caret = key == Enum.KeyCode.Left and math.min(range.Anchor, caret) or math.max(range.Anchor, caret)
				elseif key == Enum.KeyCode.Left then
					caret = word and document:WordBoundary(caret, -1) or adjacent(caret, -1)
				elseif key == Enum.KeyCode.Right then
					caret = word and document:WordBoundary(caret, 1) or adjacent(caret, 1)
				else
					local line, column = document:PositionToLineColumn(caret)
					if key == Enum.KeyCode.Home then
						caret = document:LineColumnToPosition(word and 1 or line, 1)
					elseif key == Enum.KeyCode.End then
						local destination = word and document:GetLineCount() or line
						caret = document:LineColumnToPosition(destination, #document:GetLine(destination) + 1)
					else
						local at = point(caret)
						local page = key == Enum.KeyCode.PageUp or key == Enum.KeyCode.PageDown
						local amount = page
								and math.max(
									1,
									(cf.ScrollV.VisibleSpace or math.floor(cf.Frame.AbsoluteSize.Y / cf.FontSize)) - 1
								)
							or 1
						local backwards = key == Enum.KeyCode.Up or key == Enum.KeyCode.PageUp
						local display = cf:SourceToDisplay(line - 1) or line - 1
						local target = cf:DisplayToSource(math.max(0, display + (backwards and -amount or amount))) + 1
						target = math.clamp(target, 1, document:GetLineCount())
						local preferred = preferredColumns[range.Id]
						if not preferred or preferred.Caret ~= range.Caret then
							preferred = {
								Column = column,
								Pixel = cf.GetColumnPixelX and cf:GetColumnPixelX(at[1], line - 1),
							}
							preferredColumns[range.Id] = preferred
						end
						if cf.GetColumnPixelX and cf.GetPixelColumn then
							caret = offset({ cf:GetPixelColumn(preferred.Pixel, target - 1), target - 1 })
						else
							caret = document:LineColumnToPosition(target, preferred.Column)
						end
						preferred.Caret = caret
					end
				end
				range.Caret = caret
				if not extend then
					range.Anchor = caret
				end
			end
			local normalized = Apps.EditorSelectionSet.Normalize(source, all, document)
			table.sort(normalized, function(a, b)
				return a.Id < b.Id
			end)
			apply({
				Text = source,
				Anchor = normalized[1].Anchor,
				Caret = normalized[1].Caret,
				Ranges = normalized,
				Changed = false,
			})
		end
		local held = {}
		local function repeatKey(key, action, canRepeat)
			action()
			local token = {}
			held[key] = token
			local function tick()
				if
					held[key] ~= token
					or not Main.Alive
					or not window:IsVisible()
					or service.UserInputService:GetFocusedTextBox() ~= cf.GuiElems.EditBox
					or not service.UserInputService:IsKeyDown(key)
					or (canRepeat and not canRepeat())
				then
					if held[key] == token then
						held[key] = nil
					end
					return
				end
				action()
				task.delay(0.05, tick)
			end
			task.delay(0.4, tick)
		end
		function viewer.HandleEditorInput(input)
			if viewer.EditorContextMenu and viewer.EditorContextMenu.Shown then
				return true
			end
			local key = input.KeyCode
			if pendingNative and key ~= pendingNative.Key then
				pendingNative = nil
			end
			local ctrl = Lib.IsCtrlDown()
			local shift = Lib.IsShiftDown()
			local user = service.UserInputService
			local alt = user:IsKeyDown(Enum.KeyCode.LeftAlt) or user:IsKeyDown(Enum.KeyCode.RightAlt)
			if alt and ctrl and (key == Enum.KeyCode.Up or key == Enum.KeyCode.Down) then
				viewer.AddCursorLine(key == Enum.KeyCode.Up and -1 or 1)
				return true
			end
			if ctrl and not alt and key == Enum.KeyCode.U then
				viewer.RemoveLastCursor()
				return true
			end
			if ctrl and not alt and key == Enum.KeyCode.D then
				viewer.AddMatchingCursors(false)
				return true
			end
			if shift and alt and not ctrl and key == Enum.KeyCode.L then
				viewer.AddMatchingCursors(true)
				return true
			end
			if shift and alt and not ctrl and key == Enum.KeyCode.I then
				viewer.SplitSelectionsIntoLines()
				return true
			end
			local tab = key == Enum.KeyCode.Tab
			local enter = key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter
			if ctrl and tab then
				consumeNative(key)
				return true
			end
			if not ctrl and not alt and not shift and (tab or enter) then
				local retargeted = completion and completion.Source ~= cf.Text and retargetCompletion()
				if refreshCompletion and not retargeted then
					refreshCompletion(true)
				end
			end
			if completion then
				if key == Enum.KeyCode.Escape then
					closeCompletion()
					return true
				end
				if not ctrl and not alt and not shift then
					local pageSize = math.max(1, (completionView.Count or 1) - 1)
					local direction = if key == Enum.KeyCode.Up
						then -1
						elseif key == Enum.KeyCode.Down then 1
						elseif key == Enum.KeyCode.PageUp then -pageSize
						elseif key == Enum.KeyCode.PageDown then pageSize
						elseif key == Enum.KeyCode.Home then -math.huge
						elseif key == Enum.KeyCode.End then math.huge
						else nil
					if direction then
						repeatKey(key, function()
							if completion then
								selected = math.clamp(selected + direction, 1, #completion.Items)
								renderCompletion()
							end
						end)
						return true
					end
				end
				if not ctrl and not alt and not shift and (tab or enter) then
					if enter then
						local anchor, caret = selection()
						if anchor == caret and document:CompletesHeaderOnEnter(caret) then
							consumeNative(key)
							viewer.Command("Newline")
							return true
						end
					end
					consumeNative(key)
					if viewer.AcceptCompletion(enter) then
						return true
					end
					pendingNative = nil
				end
			end
			if key == Enum.KeyCode.Escape then
				generation += 1
				local wasVisible = signatureView.Gui.Visible
				hideSignature()
				if wasVisible then
					return true
				end
			end
			if (key == Enum.KeyCode.F10 and shift) or key == Enum.KeyCode.Menu then
				viewer.OpenEditorContextMenu(nil, nil, true)
				return true
			end
			if ctrl and key == Enum.KeyCode.Space then
				viewer.Complete()
				return true
			end
			if ctrl and key == Enum.KeyCode.A then
				viewer.SelectAll()
				return true
			end
			if key == Enum.KeyCode.Insert and not ctrl and not alt and not shift then
				if cf.Editable ~= false then
					cf.OverwriteMode = not cf.OverwriteMode
					if viewer.ActiveDocument then
						viewer.ActiveDocument.overwrite = cf.OverwriteMode
					end
					cf:UpdateCursor()
					if options.Message then
						options.Message(cf.OverwriteMode and "Overwrite" or "Insert")
					end
				end
				return true
			end
			if key == Enum.KeyCode.Escape and #(cf.AdditionalSelections or {}) > 0 then
				cf.AdditionalSelections = {}
				cf:Refresh()
				return true
			end
			if ctrl and key == Enum.KeyCode.C then
				viewer.CopySelection(false)
				return true
			end
			if ctrl and key == Enum.KeyCode.X then
				return clipboardShortcut("Cut", viewer.CutSelection)
			end
			if ctrl and key == Enum.KeyCode.V then
				return clipboardShortcut("Paste", viewer.PasteFromClipboard)
			end
			if ctrl and (key == Enum.KeyCode.Z or key == Enum.KeyCode.Y) then
				clipboardInput = { Kind = "Suppress", Applied = true, Document = viewer.ActiveDocument }
				closeCompletion()
				if held[key] then
					return true
				end
				local activeDocument = viewer.ActiveDocument
				local redo = key == Enum.KeyCode.Y or shift == true
				repeatKey(key, function()
					viewer.Undo(redo)
					resetNativeBuffer()
				end, function()
					return Lib.IsCtrlDown()
						and viewer.ActiveDocument == activeDocument
						and (key == Enum.KeyCode.Y or Lib.IsShiftDown() == shift)
						and not (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
						and viewer.CanUndo(redo)
				end)
				return true
			end
			if ctrl and key == Enum.KeyCode.LeftBracket then
				viewer.Command("Outdent")
				return true
			end
			if ctrl and key == Enum.KeyCode.RightBracket then
				viewer.Command("Indent", { Indent = "    ", WholeLines = true })
				return true
			end
			if ctrl and key == Enum.KeyCode.Zero then
				viewer.SetFontSize(14)
				return true
			end
			if
				not alt
				and (
					key == Enum.KeyCode.Left
					or key == Enum.KeyCode.Right
					or key == Enum.KeyCode.Up
					or key == Enum.KeyCode.Down
					or key == Enum.KeyCode.Home
					or key == Enum.KeyCode.End
					or key == Enum.KeyCode.PageUp
					or key == Enum.KeyCode.PageDown
				)
			then
				repeatKey(key, function()
					moveSelections(key, Lib.IsShiftDown(), Lib.IsCtrlDown())
				end)
				return true
			end
			if ctrl and key == Enum.KeyCode.E then
				Apps.CodeViewport.SetAllFolds(cf, shift == true)
				return true
			end
			if ctrl and shift and key == Enum.KeyCode.Backspace then
				clipboardInput = { Kind = "Suppress", Applied = true, Document = viewer.ActiveDocument }
				viewer.Command("DeleteToLineStart")
				return true
			end
			if viewer.HandleNavigationInput and viewer.HandleNavigationInput(input) then
				return true
			end
			if ctrl and key == Enum.KeyCode.Slash then
				viewer.Command("ToggleComment")
				return true
			end
			if ctrl and shift and key == Enum.KeyCode.K then
				viewer.Command("DeleteLines")
				return true
			end
			if alt and not ctrl and (key == Enum.KeyCode.Up or key == Enum.KeyCode.Down) then
				viewer.Command(key == Enum.KeyCode.Up and "MoveLinesUp" or "MoveLinesDown")
				return true
			end
			if tab or (enter and not ctrl and not alt and not shift) then
				consumeNative(key)
				viewer.Command(if enter then "Newline" elseif shift then "Outdent" else "Indent")
				return true
			end
			if key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
				if ctrl then
					clipboardInput = { Kind = "Suppress", Applied = true, Document = viewer.ActiveDocument }
				end
				repeatKey(key, function()
					local before = cf.Text
					local refresh = completion ~= nil and not Lib.IsCtrlDown()
					typing = refresh
					viewer.Command(
						key == Enum.KeyCode.Backspace and (Lib.IsCtrlDown() and "DeletePreviousWord" or "Backspace")
							or (Lib.IsCtrlDown() and "DeleteNextWord" or "Delete")
					)
					typing = false
					if refresh then
						afterTyping(before, true)
					end
				end)
				return true
			end
			if ctrl and (key == Enum.KeyCode.Equals or key == Enum.KeyCode.Minus) then
				viewer.SetFontSize(cf.FontSize + (key == Enum.KeyCode.Equals and 1 or -1))
				return true
			end
			if
				viewer.ActiveDocument
				and window:IsVisible()
				and not window.Minimized
				and not (options.NewScriptOverlay and options.NewScriptOverlay.Visible)
				and Apps.PluginActions
				and Apps.PluginActions.HandleShortcut("Editor", input, function()
					return Apps.PluginActions.EditorContext(viewer, cf)
				end)
			then
				return true
			end
			return false
		end
		cf.HandleEditorInput = function(_, input)
			return viewer.HandleEditorInput(input)
		end
		local append = cf.AppendText
		cf.AppendText = function(self, text)
			if suppressNativeKey(text, false) then
				return
			end
			local before = self.Text
			local single = #text == 1
			typing = true
			if text == "\n" or text == "\r" then
				viewer.Command("Newline")
			elseif self.OverwriteMode then
				viewer.Command("InsertText", { Text = text, Overwrite = true, Indent = "    " })
			elseif single and text:find("[%(%)%[%]{}\"'`]") then
				viewer.Command("PairCharacter", { Text = text, Indent = "    " })
			elseif #(self.AdditionalSelections or {}) > 0 then
				viewer.Command("InsertText", { Text = text, Indent = "    " })
			else
				append(self, text)
			end
			typing = false
			if single and (text == "(" or text == "," or signatureView.Gui.Visible) then
				scheduleSignature()
			end
			afterTyping(before, single and text:find([=[[%w_%.:/@"'%[%(%-]]=]) ~= nil)
		end
		local process = cf.ProcessTextChange
		cf.ProcessTextChange = function(self, ...)
			local before = self.Text
			process(self, ...)
			if before == self.Text then
				return
			end
			local hadMarks = cf.SyntaxRanges and #cf.SyntaxRanges > 0
			hideHover()
			cf.SyntaxRanges = nil
			if hadMarks then cf:Refresh() end
			viewer.DiagnosticRevision = nil
			syntax = { Available = false, Message = "Not checked" }
			viewer.Diagnostics = syntax
			analysisTicket += 1
			local ticket = analysisTicket
			if #self.Text <= 1048576 then
				task.delay(0.35, function()
					if ticket == analysisTicket and Main.Alive and window:IsVisible() then
						updateDiagnostics()
					end
				end)
			end
			if not typing then
				closeCompletion()
				hideSignature()
			end
		end
		local updateCursor = cf.UpdateCursor
		local lastX, lastY = cf.CursorX, cf.CursorY
		cf.UpdateCursor = function(self, ...)
			updateCursor(self, ...)
			if lastX == self.CursorX and lastY == self.CursorY then
				return
			end
			lastX, lastY = self.CursorX, self.CursorY
			if not typing then
				closeCompletion()
				hideSignature()
			end
		end
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				cursorDrag = nil
			end
			if input.KeyCode then
				held[input.KeyCode] = nil
				if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
					if not Lib.IsCtrlDown() then
						held[Enum.KeyCode.Z], held[Enum.KeyCode.Y] = nil, nil
					end
				end
				if pendingNative and pendingNative.Key == input.KeyCode then
					pendingNative.Expires = os.clock() + 0.08
				end
			end
			if
				input.KeyCode == Enum.KeyCode.X
				or input.KeyCode == Enum.KeyCode.V
				or input.KeyCode == Enum.KeyCode.Z
				or input.KeyCode == Enum.KeyCode.Y
				or input.KeyCode == Enum.KeyCode.Backspace
				or input.KeyCode == Enum.KeyCode.Delete
			then
				clipboardInput = nil
			end
		end)
		Main.TrackSignal(cf.GuiElems.EditBox.FocusLost, function()
			cursorDrag = nil
			table.clear(held)
			clipboardInput = nil
			pendingNative = nil
			generation += 1
			signatureTicket += 1
			local x, y = Apps.EditorHitTest.Pointer()
			if not x or not signatureView:ContainsSwatch(x, y) then
				signatureView:Hide()
			end
			if not pointerInsidePopup() then
				closeCompletion()
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton2 then
				pointerClick = nil
			end
			if hover.Gui.Visible then
				local x, y = Apps.EditorHitTest.Pointer()
				if
					not x
					or not hover:Contains(x, y)
					or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch)
				then
					hideHover()
				end
			elseif hoverTarget then
				hideHover()
			end
			if
				popup.Visible
				and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch)
				and not pointerInsidePopup()
			then
				closeCompletion()
			end
		end)
		if service.UserInputService.WindowFocusReleased then
			Main.TrackSignal(service.UserInputService.WindowFocusReleased, function()
				cursorDrag = nil
				pointerClick = nil
				table.clear(held)
				clipboardInput = nil
				pendingNative = nil
				closeCompletion()
				signatureView:Hide()
				hideHover()
			end)
		end
		Main.AddCleanup(function()
			generation += 1
			analysisTicket += 1
			hideHover()
			signatureTicket += 1
			popup:Destroy()
			signatureView:Destroy()
			hover.Gui:Destroy()
		end)
		Apps.EditorNavigation.Attach(viewer, cf, window, language, options)
		local pointer = cf.HandleEditorPointer
		cf.HandleEditorPointer = function(self, input, x, y)
			hideSignature()
			table.clear(preferredColumns)
			local user = service.UserInputService
			local alt = user:IsKeyDown(Enum.KeyCode.LeftAlt) or user:IsKeyDown(Enum.KeyCode.RightAlt)
			if alt and not Lib.IsCtrlDown() then
				pointerClick = nil
				local all = ranges()
				local position = offset({ x, y })
				local removed
				for index, range in ipairs(all) do
					if range.Caret == position then
						removed = table.remove(all, index)
						break
					end
				end
				local id = removed and removed.Id or nextId(all)
				local base = {}
				for index, range in ipairs(all) do
					base[index] = table.clone(range)
				end
				local block = Lib.IsShiftDown()
				cursorDrag = {
					Document = viewer.ActiveDocument,
					Source = cf:GetText(),
					Anchor = position,
					Row = y,
					Column = x,
					Pixel = cf.GetColumnPixelX and cf:GetColumnPixelX(x, y),
					Id = id,
					Base = base,
					Block = block,
				}
				if block then
					all = { { Anchor = position, Caret = position, Id = 1 } }
				elseif not removed or #all == 0 then
					all[#all + 1] = { Anchor = position, Caret = position, Id = id }
				end
				setSelections(all)
				cf.GuiElems.EditBox:CaptureFocus()
				return true
			end
			cursorDrag = nil
			addingColumn = nil
			cf.AdditionalSelections = {}
			if pointer and pointer(self, input, x, y) then
				pointerClick = nil
				return true
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 or Lib.IsCtrlDown() or x == nil then
				pointerClick = nil
				return false
			end
			if Lib.IsShiftDown() then
				pointerClick = nil
				local anchor = selection()
				local active, source = viewer.ActiveDocument, frameText
				local lastCaret
				return false,
					function(column, row)
						if active ~= viewer.ActiveDocument or source ~= cf.Text or not window:IsVisible() then
							return
						end
						local caret = offset({ column, row })
						if lastCaret ~= caret then
							lastCaret = caret
							setSelections({ { Anchor = anchor, Caret = caret, Id = 1 } })
						end
					end
			end
			local px, py = Apps.EditorHitTest.Pointer(input)
			if not px then
				pointerClick = nil
				return false
			end
			local now = os.clock()
			local previous = pointerClick
			sync()
			local source = frameText
			local count = 1
			if
				previous
				and previous.Row == y
				and previous.Document == viewer.ActiveDocument
				and previous.Source == source
				and now - previous.Time <= 0.5
				and math.abs(previous.X - px) <= 5
				and math.abs(previous.Y - py) <= 5
			then
				count = previous.Count % 3 + 1
			end
			local click = {
				Count = count,
				Row = y,
				X = px,
				Y = py,
				Time = now,
				Document = viewer.ActiveDocument,
				Source = source,
			}
			pointerClick = click
			if count == 1 then
				return false,
					nil,
					function(sx, sy)
						if pointerClick == click and (math.abs(sx - px) > 5 or math.abs(sy - py) > 5) then
							pointerClick = nil
						end
					end,
					function()
						if pointerClick == click and viewer.ActiveDocument == click.Document and cf.Text == source then
							local anchor, caret = selection()
							if anchor == caret then
								scheduleSignature()
							end
						end
					end
			end
			local function rangeAt(column, row, sx, sy)
				if count == 2 and self.ScreenToEditorPoint then
					local glyph, line = self:ScreenToEditorPoint(sx, sy, true)
					if glyph ~= nil then
						column, row = glyph, line
					end
				end
				return document:PointerRange(offset({ column, row }), count)
			end
			local first, last = rangeAt(x, y, px, py)
			local selectedFirst, selectedLast
			return false,
				function(column, row, sx, sy)
					if click.Document ~= viewer.ActiveDocument or source ~= cf.Text or not window:IsVisible() then
						return
					end
					local from, to = rangeAt(column, row, sx, sy)
					if from ~= first or to ~= last then
						pointerClick = nil
					end
					local anchor, caret = first, math.max(to, last)
					if from < first then
						anchor, caret = last, from
					end
					if selectedFirst == anchor and selectedLast == caret then
						return
					end
					selectedFirst, selectedLast = anchor, caret
					setSelections({ { Anchor = anchor, Caret = caret, Id = 1 } })
				end
		end
		if cf.ScrollV then
			cf.ScrollV.WheelFilter = function()
				return not Lib.IsCtrlDown()
			end
		end
		if cf.ScrollH then
			cf.ScrollH.WheelFilter = function()
				return not Lib.IsCtrlDown()
			end
		end
		local function leaveHover()
			if not hoverTarget or hoverLeaving then
				return
			end
			if not hover.Gui.Visible then
				hideHover()
				return
			end
			hoverTicket += 1
			hoverLeaving = true
			local ticket = hoverTicket
			task.delay(0.18, function()
				if ticket == hoverTicket then
					hideHover()
				end
			end)
		end
		local textArea = cf.GuiElems.LinesFrame or cf.Frame
		local hit = Apps.EditorHitTest
		local overlays = {
			popup,
			hover.Gui,
			signatureView.Gui,
			signatureView.Swatch,
			viewer.FunctionFilter,
			options.FindPanel,
		}
		local function setTextCursor(enabled)
			if Lib.Window.SetTextCursor then
				Lib.Window.SetTextCursor(textArea, enabled)
			end
		end
		local function updateTextCursor(x, y, insideText)
			if
				not insideText
				or window.Minimized
				or (options.NewScriptOverlay and options.NewScriptOverlay.Visible)
				or Apps.ContextMenu.IsAnyShown()
			then
				setTextCursor(false)
				return
			end
			for _, overlay in ipairs(overlays) do
				if hit.Contains(overlay, x, y) then
					setTextCursor(false)
					return
				end
			end
			local search = options.FindInPlaceWindow
			if
				search
				and search:IsVisible()
				and hit.Contains(search.GuiElems.Main, x, y)
				and (search.Gui.DisplayOrder or 0) >= (window.Gui.DisplayOrder or 0)
			then
				setTextCursor(false)
				return
			end
			setTextCursor(hit.OwnsPoint(window, textArea, x, y, true))
		end
		local function resetPointer()
			pointerClick = nil
			setTextCursor(false)
		end
		Main.TrackSignal(textArea.MouseLeave, resetPointer)
		Main.TrackSignal(window.OnDeactivate, resetPointer)
		Main.TrackSignal(window.OnMinimize, resetPointer)
		if service.UserInputService.WindowFocusReleased then
			Main.TrackSignal(service.UserInputService.WindowFocusReleased, resetPointer)
		end
		Main.AddCleanup(resetPointer)
		local function refreshTextCursor()
			if Main.Alive then
				local x, y = hit.Pointer()
				updateTextCursor(x, y, x and window:IsVisible() and hit.Contains(textArea, x, y))
			end
		end
		local function watchOverlay(overlay)
			Main.TrackSignal(overlay:GetPropertyChangedSignal("Visible"), refreshTextCursor)
			Main.TrackSignal(overlay.MouseEnter, refreshTextCursor)
			Main.TrackSignal(overlay.MouseLeave, refreshTextCursor)
		end
		Main.TrackSignal(textArea.MouseEnter, refreshTextCursor)
		Main.TrackSignal(Apps.ContextMenu.VisibilityChanged, refreshTextCursor)
		for _, overlay in ipairs(overlays) do
			watchOverlay(overlay)
		end
		if options.FindPanel then
			Main.TrackSignal(options.FindPanel:GetPropertyChangedSignal("AbsoluteSize"), refreshTextCursor)
		end
		if options.NewScriptOverlay then
			Main.TrackSignal(options.NewScriptOverlay:GetPropertyChangedSignal("Visible"), refreshTextCursor)
		end
		if options.FindInPlaceWindow then
			local search = options.FindInPlaceWindow
			Main.TrackSignal(search.OnActivate, refreshTextCursor)
			Main.TrackSignal(search.Gui:GetPropertyChangedSignal("DisplayOrder"), refreshTextCursor)
			Main.TrackSignal(search.OnDeactivate, refreshTextCursor)
			Main.TrackSignal(search.GuiElems.Main.MouseEnter, refreshTextCursor)
			Main.TrackSignal(search.GuiElems.Main.MouseLeave, refreshTextCursor)
		end
		local function updateHover(input, x, y, insideText)
			if
				not x
				or not window:IsVisible()
				or Lib.IsCtrlDown()
				or popup.Visible
				or (viewer.EditorContextMenu and viewer.EditorContextMenu.Shown)
			then
				hideHover()
				return
			end
			local target = hoverTarget
			if
				target
				and (target.ViewX ~= cf.ViewX or target.ViewY ~= cf.ViewY or target.Document ~= viewer.ActiveDocument)
			then
				hideHover()
				target = nil
			end
			if hover:Contains(x, y) then
				if hoverLeaving or (target and not target.Resolved) then
					hoverTicket += 1
					hoverLeaving = false
					if target then
						target.Resolved = true
					end
				end
				return
			end
			local lines = cf.GuiElems.LinesFrame or cf.Frame
			if not cf.ScreenToEditorPoint or not insideText then
				leaveHover()
				return
			end
			local column, row = cf:ScreenToEditorPoint(x, y, true)
			if column == nil then
				leaveHover()
				return
			end
			if
				target
				and target.Row == row
				and column >= target.First
				and column < target.Last
				and (not hoverLeaving or hover.Gui.Visible)
			then
				if hoverLeaving then
					hoverTicket += 1
					hoverLeaving = false
				end
				return
			end
			hoverTicket += 1
			hoverLeaving = false
			local ticket = hoverTicket
			target = {
				Row = row,
				First = column,
				Last = column + 1,
				ViewX = cf.ViewX,
				ViewY = cf.ViewY,
				Document = viewer.ActiveDocument,
			}
			hoverTarget = target
			task.delay(0.35, function()
				if ticket ~= hoverTicket or not Main.Alive then
					return
				end
				local px, py = Apps.EditorHitTest.Pointer(input)
				if
					not px
					or popup.Visible
					or Lib.IsCtrlDown()
					or target.ViewX ~= cf.ViewX
					or target.ViewY ~= cf.ViewY
					or target.Document ~= viewer.ActiveDocument
					or not Apps.EditorHitTest.OwnsPoint(window, lines, px, py)
				then
					hideHover()
					return
				end
				for _, mark in cf.SyntaxRanges or {} do
					if row < mark.First[2] or row > mark.Last[2] then continue end
					local first = if row == mark.First[2] then mark.First[1] else 0
					local last = if row == mark.Last[2] then mark.Last[1] else #cf.Lines[row + 1]
					if column >= first and column < math.max(first + 1, last) then
						target.Resolved = true
						target.First, target.Last = first, last
						hover:Show("", mark.Message, row, first, true)
						return
					end
				end
				local source = cf:GetText()
				if #source > 65536 then
					hideHover()
					return
				end
				sync()
				apiDocumentation.Load(documentationReady)
				local checkpoint = workBudget(function()
					return ticket == hoverTicket and Main.Alive
				end)
				local item = language:Hover(source, offset({ column, row }), {
					Game = game,
					Workspace = workspace,
					Script = viewer.ActiveScript
						or (
							viewer.ActiveDocument
								and typeof(viewer.ActiveDocument.id) == "Instance"
								and viewer.ActiveDocument.id
							or nil
						),
					ModuleSource = readOpenModuleSource,
					ModuleRevision = moduleRevision,
				}, checkpoint)
				if ticket ~= hoverTicket then
					return
				end
				if not item then
					hideHover()
					return
				end
				local first, last = point(item.First), point(item.Last)
				target.Resolved = true
				target.Item = item
				target.First, target.Last = first[1], math.max(first[1] + 1, last[1])
				hover:Show(
					item.HoverDetail or item.Detail or "",
					item.Documentation,
					row,
					first[1],
					false,
					item.DocumentationFormat,
					item.Url
				)
			end)
		end
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local x, y = hit.Pointer(input)
				local insideText = x and window:IsVisible() and hit.Contains(textArea, x, y)
				updateTextCursor(x, y, insideText)
				if not cursorDrag then
					updateHover(input, x, y, insideText)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseWheel then
				hideHover()
			end
			if cursorDrag and input.UserInputType == Enum.UserInputType.MouseMovement then
				local drag = cursorDrag
				if drag.Document ~= viewer.ActiveDocument or drag.Source ~= cf:GetText() or not window:IsVisible() then
					cursorDrag = nil
					return
				end
				local screenX, screenY = Apps.EditorHitTest.Pointer(input)
				if not screenX or not cf.ScreenToEditorPoint then
					return
				end
				local x, y = cf:ScreenToEditorPoint(screenX, screenY)
				local position = offset({ x, y })
				if position == drag.Anchor and not drag.Moved then
					return
				end
				drag.Moved = true
				local all = {}
				if drag.Block then
					local targetPixel = cf.GetColumnPixelX and cf:GetColumnPixelX(x, y)
					for row = math.min(drag.Row, y), math.max(drag.Row, y) do
						local start = drag.Pixel and cf.GetPixelColumn and cf:GetPixelColumn(drag.Pixel, row)
							or drag.Column
						local finish = targetPixel and cf.GetPixelColumn and cf:GetPixelColumn(targetPixel, row) or x
						all[#all + 1] = {
							Anchor = offset({ start, row }),
							Caret = offset({ finish, row }),
							Id = row == drag.Row and 1 or #all + 2,
						}
					end
				else
					for index, range in ipairs(drag.Base) do
						all[index] = table.clone(range)
					end
					all[#all + 1] = { Anchor = drag.Anchor, Caret = position, Id = drag.Id }
				end
				setSelections(all)
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.MouseWheel
				or not Lib.IsCtrlDown()
				or not window:IsVisible()
			then
				return
			end
			local x, y = Apps.EditorHitTest.Pointer(input)
			if not x or not Apps.EditorHitTest.OwnsPoint(window, cf.GuiElems.LinesFrame or cf.Frame, x, y) then
				return
			end
			local delta = input.Position.Z
			if delta ~= 0 then
				viewer.SetFontSize(cf.FontSize + (delta > 0 and 1 or -1))
			end
		end)
		Apps.EditorContextMenu.Attach(viewer, cf, window, options)
		viewer.LanguageCapabilities = {
			Completion = "Lexical and API metadata",
			Diagnostics = "LuauParser syntax diagnostics",
			NativeDebugger = false,
			NativeTypeChecker = false,
		}
		viewer.CompletionPopup = popup
		return { Dismiss = closeCompletion, Document = document }
	end
	return Controller
end
return { InitDeps = InitDeps, Main = CreateModule }
