--!strict

do
	(function()
		-- Reject invalid Roblox property access rather than relying on permissive GUI mocks.
		local function strict(class, parent, properties)
			properties = properties or {}
			properties.ClassName = class
			properties.Parent = parent
			local allowed = { Parent = true }
			return setmetatable({}, {
				__index = function(_, key)
					if key == "IsA" then
						return function(_, kind)
							return kind == class
								or (kind == "GuiObject" and class == "Frame")
								or (kind == "LayerCollector" and class == "ScreenGui")
						end
					end
					if properties[key] ~= nil or allowed[key] then
						return properties[key]
					end
					error("Invalid " .. class .. " property: " .. key)
				end,
			})
		end
		local folder = strict("Folder", nil)
		local screen = strict("ScreenGui", folder, { Enabled = true })
		local strictFrame = strict("Frame", screen, {
			Visible = true,
			ClipsDescendants = false,
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(40, 40),
		})
		assert(
			Apps.EditorHitTest.Contains(strictFrame, 10, 10),
			"typed hit tests never read Frame.Enabled or ScreenGui.Visible"
		)
		local disabledScreen = strict("ScreenGui", folder, { Enabled = false })
		local hiddenFrame = strict("Frame", disabledScreen, {
			Visible = true,
			ClipsDescendants = false,
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(40, 40),
		})
		assert(not Apps.EditorHitTest.Contains(hiddenFrame, 10, 10), "disabled layer collectors reject pointer hits")
		local background
		local queryRoot = strict("Folder", nil, {
			GetGuiObjectsAtPosition = function()
				return { background }
			end,
		})
		local ownScreen = strict("ScreenGui", queryRoot, { Enabled = true, DisplayOrder = 12 })
		local bounds = {
			Visible = true,
			ClipsDescendants = false,
			BackgroundTransparency = 0,
			Active = false,
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(40, 40),
		}
		background = strict("Frame", ownScreen, table.clone(bounds))
		local emptyArea = strict("Frame", background, table.clone(bounds))
		assert(
			Apps.EditorHitTest.OwnsPoint({
				Gui = ownScreen,
				IsVisible = function()
					return true
				end,
			}, emptyArea, 10, 10),
			"blank code space accepts its own ancestor background from GUI hit testing"
		)
		local sibling = strict("Frame", background, table.clone(bounds))
		background = sibling
		assert(
			Apps.EditorHitTest.OwnsPoint({
				Gui = ownScreen,
				IsVisible = function()
					return true
				end,
			}, emptyArea, 10, 10),
			"caret and selection siblings must not block the LinesFrame hit target"
		)
	end)()
	local previousClipboard, previousReadClipboard = deps.env.setclipboard, deps.env.getclipboard
	local previousMouse, previousHit = Main.Mouse, Main.IsPointInDexUI
	local clipboard
	deps.env.setclipboard = function(text)
		clipboard = text
	end
	deps.env.getclipboard = function()
		return "replacement"
	end
	local doc = editor.OpenDocument("menu-tests", "Menu Test", "alpha beta\nsecond")
	cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
	cf:MoveCursor(5, 0)
	local area = cf.GuiElems.LinesFrame or cf.Frame
	local x, y = area.AbsolutePosition.X + 14, area.AbsolutePosition.Y + 7
	Main.Mouse = { X = x, Y = y, ViewSizeX = 1100, ViewSizeY = 800 }
	-- No GUI frame/row event is fired: this must work over rendered row children.
	service.UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton2,
		Position = Vector2.new(x, y + 36),
	})
	local menu = editor.EditorContextMenu
	assert(menu and menu.Shown, "global right-click opens editor menu without parent GUI event bubbling")
	editor.CloseEditorContextMenu()
	Main.Mouse.X, Main.Mouse.Y = -50, -50
	local touch = Vector2.new(x,y)
	local tx, ty = Apps.EditorHitTest.Pointer({UserInputType = Enum.UserInputType.Touch, Position = touch})
	assert(tx == x and ty == y)
	service.UserInputService.TouchLongPress:Fire({touch, touch}, Enum.UserInputState.Begin)
	assert(not menu.Shown)
	service.UserInputService.TouchLongPress:Fire({touch}, Enum.UserInputState.Begin)
	assert(menu.Shown, "touch opens the editor menu independently of mouse position")
	Main.Mouse.X, Main.Mouse.Y = x, y
	for _, row in ipairs(menu.GuiElems.List:GetChildren()) do
		local label = row:FindFirstChild("EntryName")
		if label and label.Text == "Format" then
			assert(
				row.Shortcut.Text == ""
					and row.SubmenuArrow.Visible
					and row.SubmenuArrow.Image == "mockasset://native/editor/submenu",
				"submenu uses the original Studio triangle image without a font glyph"
			)
		end
	end
	local newScript = editor.TabStrip.Gui.Parent:FindFirstChild("NewScript")
	assert(
		newScript and newScript.Size.X.Offset == 28 and newScript.Size.Y.Scale == 1 and newScript.Size.Y.Offset == 0,
		"new-script click target spans the tab bar height"
	)
	assert(
		newScript.Text == "+" and newScript.TextSize == 22,
		"new-script plus remains legible at normal display scale"
	)
	local function item(name)
		for _, entry in ipairs(menu.Items) do
			if entry.Name == name then
				return entry
			end
		end
		error("Missing editor menu action " .. name)
	end
	for _, name in ipairs({
		"Undo",
		"Redo",
		"Cut",
		"Copy",
		"Paste",
		"Delete",
		"Select All",
		"Format",
		"Go to Declaration",
		"Open Script Function Filter",
		"Toggle Comment",
		"Expand Script Folds",
		"Collapse Script Folds",
		"Zoom In",
		"Zoom Out",
		"Reset Script Zoom",
		"Show in Explorer",
	}) do
		assert(item(name), name)
	end
	for _, row in ipairs(menu.GuiElems.List:GetChildren()) do
		local label = row:FindFirstChild("EntryName")
		if label and row.Name ~= "Divider" then
			assert(label.Text ~= "" and label.Text ~= "Label", "actual rendered actions must have explicit names")
		end
	end
	assert(
		item("Format").Submenu[1].Name == "Format Selection"
			and item("Format").Submenu[2].Name == "Format Document"
			and item("Format").Submenu[3].Name == "Indent"
			and item("Format").Submenu[4].Name == "Unindent",
		"native Format submenu retains supported commands"
	)
	assert(
		item("Format").Icon == "mockasset://native/editor/format" and not menu.Iconless,
		"Format uses the byte-verified original native menu icon"
	);
	(function()
		local found = false
		for _, row in ipairs(menu.GuiElems.List:GetChildren()) do
			local label = row:FindFirstChild("EntryName")
			if label and label.Text == "Format" then
				local icon = row:FindFirstChild("Icon")
				assert(
					icon and icon.Visible and icon.Image == item("Format").Icon,
					"native image reaches the rendered row"
				)
				found = true
			end
			if label and label.Text == "Copy" then
				local shortcut = row:FindFirstChild("Shortcut")
				assert(
					shortcut.TextXAlignment == Enum.TextXAlignment.Left and shortcut.Position.X.Offset == 200,
					"native shortcut column aligns prefixes, not text ends"
				)
			end
		end
		assert(found, "Format row is mounted")
		menu:OpenSubmenu(item("Format"))
		assert(
			menu.ChildMenu.Width == 224 and menu.ChildMenu.Theme.TextSize == 12,
			"Format submenu preserves native width and typography"
		)
		menu.ChildMenu:Hide()
	end)()
	assert(
		editor.GetSelectionState().Selected and not item("Copy").Disabled,
		"right-click inside selection preserves copy range"
	)
	item("Copy").OnClick()
	assert(
		clipboard == "alpha" and cf:GetText() == "alpha beta\nsecond",
		"copy menu uses existing range without editing"
	)
	cf.SelectionRange = { { 0, 1 }, { 6, 1 } }
	cf:MoveCursor(6, 1)
	cf.AdditionalSelections = { { { 0, 0 }, { 5, 0 } } }
	assert(
		editor.OpenEditorContextMenu(x, y) and #cf.AdditionalSelections == 1,
		"right-click within an additional selection preserves the complete selection set"
	)
	editor.CloseEditorContextMenu()
	cf.SelectionRange = { { 8, 0 }, { 8, 0 } }
	cf:MoveCursor(8, 0)
	cf.AdditionalSelections = { { { 0, 1 }, { 6, 1 } } }
	assert(
		editor.OpenEditorContextMenu(x, y) and #cf.AdditionalSelections == 0,
		"right-click relocation clears old additional cursors"
	)
	editor.CloseEditorContextMenu()
	cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
	cf:MoveCursor(5, 0)
	assert(editor.OpenEditorContextMenu(x, y), "menu reopens")
	item("Paste").OnClick()
	assert(cf:GetText() == "replacement beta\nsecond", "paste menu replaces selected source")
	editor.Undo(false)
	assert(cf:GetText() == "alpha beta\nsecond", "paste menu is one undo transaction")
	cf:SetText("if enabled then\n\nend\n  -- untouched")
	cf.SelectionRange = { { 0, 1 }, { 0, 1 } }
	cf:MoveCursor(0, 1)
	assert(editor.PasteText("if ready then\nprint([=[hello\n literal space]=])\nend"))
	assert(
		cf:GetText() == "if enabled then\n    if ready then\n        print([=[hello\n literal space]=])\n    end\nend\n  -- untouched",
		"paste indents nested code while preserving literal content and unrelated lines"
	)
	editor.Undo(false)
	assert(cf:GetText() == "if enabled then\n\nend\n  -- untouched", "formatted paste undoes in one step")
	cf:SetText("alpha beta\nsecond")

	cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
	cf:MoveCursor(5, 0)
	deps.env.getclipboard = function()
		error("denied")
	end
	editor.OpenEditorContextMenu(x, y)
	item("Paste").OnClick()
	assert(
		cf:GetText() == "alpha beta\nsecond" and editor.GetSelectionState().Selected,
		"clipboard failure preserves source and selection"
	)
	deps.env.getclipboard = nil
	editor.OpenEditorContextMenu(x, y)
	assert(item("Paste").Disabled, "paste is disabled when clipboard read capability is absent")
	cf.Editable = false
	editor.OpenEditorContextMenu(x, y)
	assert(
		item("Cut").Disabled and item("Undo").Disabled and item("Paste").Disabled,
		"read-only source disables mutating menu actions"
	)
	assert(
		not editor.Command("Delete") and cf:GetText() == "alpha beta\nsecond",
		"read-only command guard preserves text"
	)
	cf.Editable = true
	menu:Hide()
	local outsideX = area.AbsolutePosition.X - 10
	Main.Mouse.X = outsideX
	service.UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton2,
		Position = Vector2.new(outsideX, y),
	})
	assert(not menu.Shown, "outside right-click cannot open code menu")
	Main.IsPointInDexUI = function()
		return true, {}
	end
	assert(editor.CanOpenEditorContextMenuAt(x, y), "unordered window lookup cannot veto editor input");
	(function()
		local previous = Main.InternalGuis
		local overlay = Instance.new("ScreenGui", game)
		overlay.Enabled = true
		overlay.DisplayOrder = (editor.Window.Gui.DisplayOrder or 0) + 1
		local panel = Instance.new("Frame", overlay)
		panel.BackgroundTransparency = 0
		panel.Size = UDim2.fromOffset(1100, 800)
		Main.InternalGuis = { [overlay] = true }
		assert(not editor.CanOpenEditorContextMenuAt(x, y), "a visible higher layer blocks the editor")
		overlay.DisplayOrder = (editor.Window.Gui.DisplayOrder or 0) - 1
		assert(editor.CanOpenEditorContextMenuAt(x, y), "a lower window cannot block the foreground editor")
		Main.InternalGuis = previous
		overlay:Destroy()
	end)()
	Main.IsPointInDexUI = previousHit
	local content = editor.Window.GuiElems.Content
	local findPanel = content:FindFirstChild("FindReplace")
	findPanel.Visible = true
	assert(
		not editor.CanOpenEditorContextMenuAt(findPanel.AbsolutePosition.X + 6, findPanel.AbsolutePosition.Y + 6),
		"find overlay cannot open the underlying code menu"
	)
	findPanel.Visible = false
	cf:SetText("local value = 3\nprint(value)")
	cf:MoveCursor(8, 1)
	cf.SelectionRange = { { 8, 1 }, { 8, 1 } }
	keys.LeftShift = true
	editor.HandleEditorInput({ KeyCode = Enum.KeyCode.F10 })
	keys.LeftShift = false
	assert(
		menu.Shown and not item("Go to Declaration").Disabled,
		"keyboard context menu targets current caret, not the next display row"
	)
	assert(
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Down }),
		"menu navigation cannot move the underlying code caret"
	)
	item("Go to Declaration").OnClick()
	assert(cf.CursorY == 0 and cf.CursorX == 6, "context declaration action goes to the intended token")
	editor.OpenEditorContextMenu(nil, nil, true)
	item("Select All").OnClick()
	assert(
		editor.GetSelectionState().First == 1 and editor.GetSelectionState().Last == #cf:GetText() + 1,
		"select-all menu selects complete source"
	)
	editor.OpenEditorContextMenu(nil, nil, true)
	flushTasks()
	service.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Escape })
	assert(not menu.Shown, "Escape closes editor context menu")
	editor.OpenEditorContextMenu(nil, nil, true)
	editor.OpenDocument("context-other", "Other", "other source")
	assert(not menu.Shown, "switching documents dismisses stale edit actions")
	local raw = "if ok then\nprint('first')\nprint('second')\nend"
	local formatted = "if ok then\n    print('first')\n    print('second')\nend"
	editor.OpenDocument("format-menu", "Format Menu", raw)
	editor.OpenEditorContextMenu(nil, nil, true)
	assert(item("Format").Submenu[1].Disabled, "Format Selection needs a nonempty range")
	item("Format").Submenu[2].OnClick()
	assert(cf:GetText() == formatted, "Format Document fixes indentation through the editor transaction")
	editor.Undo(false)
	assert(cf:GetText() == raw, "Format Document undoes in one operation")
	cf.SelectionRange = { { 0, 1 }, { 0, 2 } }
	cf:MoveCursor(0, 2)
	editor.OpenEditorContextMenu(nil, nil, true)
	assert(not item("Format").Submenu[1].Disabled, "Format Selection is available with a nonempty range")
	item("Format").Submenu[1].OnClick()
	assert(cf:GetText() == "if ok then\n    print('first')\nprint('second')\nend", "Format Selection uses only selected lines")
	editor.CloseDocument(editor.ActiveDocument)
	local literal = "local s = [=[\r\n   quoted\r\n ]=]\r\nlocal t = {\r\na = if ok then 1 else 2,\r\nb = function()\r\n--[=[\r\n   comment\r\n ]=]\r\nreturn s\r\nend,\r\n}\r\n"
	local expected = "local s = [=[\r\n   quoted\r\n ]=]\r\nlocal t = {\r\n    a = if ok then 1 else 2,\r\n    b = function()\r\n        --[=[\r\n   comment\r\n ]=]\r\n        return s\r\n    end,\r\n}\r\n"
	local ranges = { { Id = 1, Anchor = 1, Caret = #literal + 1 } }
	local result = Apps.EditorFormatter.Edit(literal, ranges, false, "    ")
	assert(result.Text == expected, "formatter preserves CRLF and the contents of multiline strings and comments")
	assert(result.Anchor == 1 and result.Caret == #expected + 1, "formatter preserves selection endpoints")
	assert(not Apps.EditorFormatter.Edit(expected, result.Ranges, false, "    ").Changed, "formatting is idempotent")
	deps.env.setclipboard = previousClipboard
	deps.env.getclipboard = previousReadClipboard
	Main.Mouse = previousMouse
	print(
		"PASS: real editor right-click routing, selection preservation, grouped edit actions, capability states, clipboard failures, keyboard menu and overlay/window exclusion"
	)

	local tabs = editor.TabStrip
	local a = editor.OpenDocument("tab-a", "A moderately wide script", "first")
	local entry = tabs.Entries[a]
	local root, label, icon = entry.Root, entry.Label, entry.Icon
	local width = entry.Width
	assert(
		not root:FindFirstChildOfClass("UIPadding") and not label.TextScaled,
		"tab has independent unscaled icon/title/close geometry"
	)
	assert(
		icon.Position.X.Offset + icon.Size.X.Offset <= label.Position.X.Offset,
		"script icon cannot overlap tab title"
	)
	assert(label.Font == Lib.StudioFont and label.TextSize == 14, "tab uses the same font it measures")
	assert(
		label.AbsolutePosition.X + label.AbsoluteSize.X <= entry.Dirty.AbsolutePosition.X,
		"title does not overlap modified indicator"
	)
	assert(entry.Close.Size.Y.Scale == 1 and root.Size.Y.Offset == 26, "close hit target spans fixed tab height")
	cf.ViewY = 7
	entry.Select.MouseButton1Click:Fire()
	assert(cf.ViewY == 7, "clicking active tab preserves viewport instead of resetting document")
	cf:MoveCursor(5, 0)
	cf:AppendText("x")
	assert(
		tabs.Entries[a].Root == root
			and entry.Label == label
			and entry.Icon == icon
			and entry.Width == width
			and entry.Dirty.Visible,
		"first edit preserves tab widgets and width"
	)
	local b = editor.OpenDocument("tab-b", "B", "second")
	editor.SelectDocument(a)
	assert(tabs.Entries[a].Root == root and entry.Label == label, "tab switching does not recreate glyph widgets")
	local oldSize = tabs.Gui.Size
	tabs.Gui.Size = UDim2.fromOffset(30, oldSize.Y.Offset)
	tabs:EnsureActive()
	assert(tabs.Gui.CanvasPosition.X == entry.Left, "an oversized tab starts at its title edge")
	tabs:EnsureActive()
	assert(tabs.Gui.CanvasPosition.X == entry.Left, "repeated layout cannot oscillate oversized tabs")
	tabs.Gui.Size = oldSize
	for i = 1, 7 do
		editor.OpenDocument("overflow-" .. i, "Overflow Script " .. i, "text")
	end
	tabs.Gui.CanvasPosition = Vector2.new(42.7, 0)
	tabs.Gui:GetPropertyChangedSignal("CanvasPosition"):Fire()
	assert(tabs.Gui.CanvasPosition.X == 43, "tab scroll snaps to whole pixels")
	assert(
		entry.TextBounds.Width == entry.Label.Size.X.Offset
			and entry.TextBounds.Right + 4 == entry.Dirty.Position.X.Offset,
		"measured elision uses the free rectangle before accessories"
	)
	local oldMeasure = service.TextService.GetTextSize
	local measurements = 0
	service.TextService.GetTextSize = function(_, text, size, font, bounds)
		measurements += 1
		return oldMeasure(service.TextService, text, size, font, bounds)
	end
	tabs:Update(editor.Documents, editor.ActiveDocument)
	assert(measurements == 0, "unchanged titles reuse cached font metrics")
	service.TextService.GetTextSize = oldMeasure
	local before = tabs.Gui.CanvasPosition.X
	cf:MoveCursor(4, 0)
	cf:AppendText("x")
	assert(tabs.Gui.CanvasPosition.X == before, "dirty update preserves manual tab scroll")
	editor.SelectDocument(a)
	local left = tabs.Gui.AbsolutePosition.X + entry.Left - tabs.Gui.CanvasPosition.X + 8
	local top = tabs.Gui.AbsolutePosition.Y + 12
	Main.Mouse = { X = left, Y = top, ViewSizeX = 1100, ViewSizeY = 800 }
	service.UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton2,
		Position = Vector2.new(left, top),
	})
	assert(tabs.ContextMenu and tabs.ContextMenu.Shown, "right-click tab opens tab management menu")
	tabs:HideMenu()
	service.UserInputService.TouchLongPress:Fire({Vector2.new(left, top)}, Enum.UserInputState.Begin)
	assert(tabs.ContextMenu.Shown, "holding a tab opens its menu")
	local moveRight
	for _, action in tabs.ContextMenu.Items do
		if action.Text == "Move Tab Right" then moveRight = action end
	end
	assert(moveRight, "tab reordering has a touch action")
	local closeOthers
	for _, action in ipairs(tabs.ContextMenu.Items) do
		if action.Text == "Close Other Tabs" then
			closeOthers = action
		end
	end
	closeOthers.OnClick()
	tabs:HideMenu()
	assert(
		#editor.Documents == 1 and editor.Documents[1] == a and tabs.Entries[a].Root == root,
		"close-other-tabs preserves target controls and source"
	)
	editor.OpenDocument("tab-cycle", "Cycle", "do not indent")
	editor.SelectDocument(a)
	cf.GuiElems.EditBox:CaptureFocus()
	keys.LeftControl = true
	service.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Tab })
	assert(editor.ActiveDocument.id == "tab-cycle", "Ctrl+Tab switches exactly one document")
	editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Tab })
	cf:AppendText("\t")
	assert(cf:GetText() == "do not indent", "Ctrl+Tab does not insert a stray indentation character")
	keys.LeftControl = false
	editor.SelectDocument(a)
	Main.Mouse.X = tabs.Gui.AbsolutePosition.X + entry.Left - tabs.Gui.CanvasPosition.X + 8
	Main.Mouse.Y = top
	service.UserInputService.InputBegan:Fire({
		UserInputType = Enum.UserInputType.MouseButton3,
		Position = Vector2.new(Main.Mouse.X, Main.Mouse.Y),
	})
	assert(tabs.Entries[a], "middle press alone must not close the document")
	service.UserInputService.InputEnded:Fire({
		UserInputType = Enum.UserInputType.MouseButton3,
		Position = Vector2.new(Main.Mouse.X, Main.Mouse.Y),
	})
	assert(tabs.Entries[a], "matching middle release queues close outside the event dispatch")
	flushTasks()
	assert(
		not tabs.Entries[a] and not table.find(editor.Documents, a),
		"matching middle press and release closes the pointed tab"
	);
	(function()
		-- Keep just two short tabs visible so pointer tests do not depend on overflow.
		local first = editor.OpenDocument("native-tab-first", "First", "first")
		local second = editor.OpenDocument("native-tab-second", "Second", "second")
		for _, doc in ipairs(table.clone(editor.Documents)) do
			if doc ~= first and doc ~= second then
				editor.CloseDocument(doc)
			end
		end
		editor.SelectDocument(first)
		tabs.Gui.CanvasPosition = Vector2.new(0, 0)
		local function point(doc, offset)
			local e = tabs.Entries[doc]
			return Vector2.new(
				tabs.Gui.AbsolutePosition.X + e.Left + (offset or e.Width / 2),
				tabs.Gui.AbsolutePosition.Y + 12
			)
		end
		local function fire(signalName, kind, position)
			Main.Mouse.X = position.X
			Main.Mouse.Y = position.Y
			service.UserInputService[signalName]:Fire({ UserInputType = kind, Position = position })
		end
		local p = point(first)
		local q = point(second)
		fire("InputBegan", Enum.UserInputType.MouseButton3, p)
		fire("InputEnded", Enum.UserInputType.MouseButton3, q)
		flushTasks()
		assert(
			tabs.Entries[first] and tabs.Entries[second],
			"middle press on one tab and release on another closes neither"
		)
		fire("InputBegan", Enum.UserInputType.MouseButton1, p)
		fire("InputChanged", Enum.UserInputType.MouseMovement, Vector2.new(p.X + 3, p.Y))
		assert(editor.Documents[1] == first, "pointer jitter below drag threshold cannot reorder tabs")
		q = point(second, tabs.Entries[second].Width - 25)
		fire("InputChanged", Enum.UserInputType.MouseMovement, q)
		fire("InputEnded", Enum.UserInputType.MouseButton1, q)
		assert(
			editor.Documents[1] == second and editor.Documents[2] == first,
			"drag across the neighbor midpoint reorders actual document state"
		)
		assert(
			editor.ActiveDocument == first and tabs.Entries[first].Root and tabs.Entries[second].Root,
			"reorder preserves active source and keyed widgets"
		)
	end)()
	Main.Mouse = previousMouse
	print(
		"PASS: persistent tab controls, correct font/geometry, no dirty reflow, pixel-aligned scrolling, context actions, middle close and Ctrl+Tab without text corruption"
	)
end
