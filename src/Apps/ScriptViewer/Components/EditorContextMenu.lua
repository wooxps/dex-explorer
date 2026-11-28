--!strict

local Apps, Main, Lib, service, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Lib, service, env = d.Apps, d.Main, d.Lib, d.service, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Context = {}
	function Context.Attach(viewer, cf, window, options)
		local hit = Apps.EditorHitTest
		local menu
		local function editorArea()
			return cf.GuiElems.LinesFrame or cf.Frame
		end
		local function position(x, y)
			local column, row = cf:ScreenToEditorPoint(x, y)
			return viewer.GetEditorOffset(column, row), column, row
		end
		local function canOpen(x, y)
			if not hit.OwnsPoint(window, editorArea(), x, y) then
				return false
			end
			for _, gui in ipairs(window.GuiElems.Content:GetChildren()) do
				if
					gui:IsA("GuiObject")
					and gui ~= cf.Frame
					and (gui.ZIndex or 1) > (cf.Frame.ZIndex or 1)
					and hit.Contains(gui, x, y)
				then
					return false
				end
			end
			return true
		end
		function viewer.CloseEditorContextMenu()
			if menu then
				menu:Hide()
			end
		end
		function viewer.OpenEditorContextMenu(x, y, keyboard)
			if not window:IsVisible() then
				return false
			end
			local lines = editorArea()
			if keyboard then
				x = lines.AbsolutePosition.X
					+ cf:GetColumnPixelX(cf.CursorX, cf.CursorY)
					- Apps.CodeViewport.ScrollPixelX(cf)
				y = lines.AbsolutePosition.Y
					+ ((cf:SourceToDisplay(cf.CursorY) or cf.CursorY) - cf.ViewY + 1) * cf.FontSize
			elseif not canOpen(x, y) then
				return false
			end
			viewer.DismissCompletion()
			viewer.CloseNavigation()
			if viewer.SignatureHelp then
				viewer.SignatureHelp.Visible = false
			end
			local at, column, row
			if keyboard then
				at = viewer.GetSelectionState().Caret
				column = cf.CursorX
				row = cf.CursorY
			else
				at, column, row = position(x, y)
			end
			local selections = viewer.GetSelections()
			local insideSelection = false
			local hasSelection = false
			for _, range in ipairs(selections) do
				if range.Anchor ~= range.Caret then
					hasSelection = true
					if at >= math.min(range.Anchor, range.Caret) and at <= math.max(range.Anchor, range.Caret) then
						insideSelection = true
					end
				end
			end
			if not keyboard and not insideSelection then
				cf.AdditionalSelections = {}
				cf.SelectionRange = { { column, row }, { column, row } }
				cf:MoveCursor(column, row)
				cf:SetCopyableSelection()
				cf:Refresh()
				hasSelection = false
			end
			local selectedDocument = viewer.ActiveDocument
			menu = menu or Apps.ContextMenu.new()
			menu:Clear()
			menu.Iconless = false
			menu.Width = 280
			menu.MaxHeight = Main.Mouse.ViewSizeY - 8
			local skin = Apps.StudioEditorSkin
			menu:ApplyTheme({
				RowHeight = 22,
				CornerRadius = 0,
				TextSize = 12,
				TextInset = 27,
				IconInset = 1,
				SubmenuImage = Main.GetStudioAsset("native/editor/submenu"),
				Font = Lib.StudioFont,
				ShortcutColumnWidth = 74,
				ShortcutColor = skin.Text,
				ContentColor = skin.Inactive,
				OutlineColor = skin.Border,
				HighlightColor = Color3.fromRGB(53, 55, 67),
				TextColor = skin.Text,
			})
			viewer.EditorContextMenu = menu
			local function guarded(callback)
				return function()
					if viewer.ActiveDocument ~= selectedDocument then
						return
					end
					menu:Hide()
					callback()
					if service.UserInputService:GetFocusedTextBox() == nil then
						cf.GuiElems.EditBox:CaptureFocus()
					end
				end
			end
			local editable = cf.Editable ~= false
			local function format(selectionOnly)
				if cf.Editable ~= false then
					local result =
						Apps.EditorFormatter.Edit(cf:GetText(), viewer.GetSelections(), selectionOnly, "    ")
					if result.Changed then
						viewer.ApplyEditorEdit(result)
					end
				end
			end
			local bindings = {
				undoAction = {
					Callback = function()
						viewer.Undo(false)
					end,
					Disabled = not editable or not viewer.CanUndo(false),
				},
				redoAction = {
					Callback = function()
						viewer.Undo(true)
					end,
					Disabled = not editable or not viewer.CanUndo(true),
				},
				cutAction = {
					Callback = viewer.CutSelection,
					Disabled = not editable or type(env.setclipboard) ~= "function",
				},
				copyAction = { Callback = viewer.CopySelection, Disabled = type(env.setclipboard) ~= "function" },
				pasteAction = {
					Callback = viewer.PasteFromClipboard,
					Disabled = not editable or type(env.getclipboard) ~= "function",
				},
				deleteSelectedAction = {
					Callback = function()
						viewer.Command("Delete")
					end,
					Disabled = not editable or not hasSelection,
				},
				selectAllAction = { Callback = viewer.SelectAll, Disabled = #cf:GetText() == 0 },
				FORMATSEL = {
					Callback = function()
						format(true)
					end,
					Disabled = not editable or not hasSelection,
				},
				FORMATALL = {
					Callback = function()
						format(false)
					end,
					Disabled = not editable or #cf.Text == 0,
				},
				INDENT = {
					Callback = function()
						viewer.Command("Indent", { Indent = "    ", WholeLines = true })
					end,
					Disabled = not editable,
				},
				UNINDENT = {
					Callback = function()
						viewer.Command("Outdent")
					end,
					Disabled = not editable,
				},
				GOTOERR = {
					Callback = viewer.GoToDiagnostic,
					Disabled = not viewer.Diagnostics or not viewer.Diagnostics.Line,
				},
				GOTODECL = {
					Callback = function()
						viewer.GoToDeclaration(at)
					end,
					Disabled = #cf.Text <= 65536 and viewer.GetDefinition(at) == nil,
				},
				INVOKESYMBOLS = { Callback = viewer.OpenFunctionFilter },
				TOGGLECOMMENT = {
					Callback = function()
						viewer.Command("ToggleComment")
					end,
					Disabled = not editable,
				},
				UNFOLDALL = {
					Callback = function()
						Apps.CodeViewport.SetAllFolds(cf, false)
					end,
				},
				FOLDALL = {
					Callback = function()
						Apps.CodeViewport.SetAllFolds(cf, true)
					end,
				},
				zoomInAction = {
					Callback = function()
						viewer.SetFontSize(cf.FontSize + 1)
					end,
					Disabled = cf.FontSize >= 32,
				},
				zoomOutAction = {
					Callback = function()
						viewer.SetFontSize(cf.FontSize - 1)
					end,
					Disabled = cf.FontSize <= 10,
				},
				resetScriptZoomAction = {
					Callback = function()
						viewer.SetFontSize(14)
					end,
				},
				showScriptInExplorerAction = {
					Callback = viewer.ShowScriptInExplorer,
					Disabled = viewer.ActiveScript == nil,
				},
			}
			for _, entry in ipairs(Apps.StudioMenuDefinition.Build(bindings, guarded, Main.GetStudioAsset)) do
				if entry.Divider then
					menu:AddDivider()
				else
					menu:Add(entry)
				end
			end
			if selectedDocument and Apps.PluginActions then
				Apps.PluginActions.AddMenu(menu, "Editor", function()
					return Apps.PluginActions.EditorContext(viewer, cf)
				end, guarded)
			end
			menu:Show(x, y)
			return true
		end
		Main.TrackSignal(service.UserInputService.TouchLongPress, function(points, state)
			if state == Enum.UserInputState.Begin and #points == 1 then
				local point = points[1]
				viewer.OpenEditorContextMenu(point.X, point.Y, false)
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
				return
			end
			local x, y = hit.Pointer(input)
			if not x then
				return
			end
			if menu and menu.Shown and hit.Contains(menu.GuiElems.Main, x, y) then
				return
			end
			viewer.CloseEditorContextMenu()
			viewer.OpenEditorContextMenu(x, y, false)
		end)
		Main.TrackSignal(window.OnDeactivate, viewer.CloseEditorContextMenu)
		Main.TrackSignal(window.OnMinimize, viewer.CloseEditorContextMenu)
		if service.UserInputService.WindowFocusReleased then
			Main.TrackSignal(service.UserInputService.WindowFocusReleased, viewer.CloseEditorContextMenu)
		end
		Main.AddCleanup(function()
			if menu then
				menu:Destroy()
			end
		end)
		viewer.CanOpenEditorContextMenuAt = canOpen
	end
	return Context
end
return { InitDeps = InitDeps, Main = CreateModule }
