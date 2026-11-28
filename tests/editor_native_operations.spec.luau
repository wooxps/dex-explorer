--!strict

do
	(function()
		local set = Apps.EditorSelectionSet
		local reversed =
			set.Normalize("abcdef", { { Anchor = 6, Caret = 2, Id = 1 }, { Anchor = 3, Caret = 4, Id = 2 } })
		assert(
			#reversed == 1 and reversed[1].Anchor == 6 and reversed[1].Caret == 2,
			"merged selections retain the primary caret direction"
		)
		local inserted = set.Apply(
			"aaaa",
			{ { Anchor = 2, Caret = 2 }, { Anchor = 4, Caret = 4 } },
			"InsertText",
			{ Text = "a" }
		)
		assert(
			inserted.Text == "aaaaaa" and inserted.Ranges[1].Caret == 3 and inserted.Ranges[2].Caret == 6,
			"repeated glyphs cannot confuse edit-offset mapping"
		)
		local merged = set.Apply(
			"abcdef",
			{ { Anchor = 5, Caret = 2 }, { Anchor = 3, Caret = 6 } },
			"InsertText",
			{ Text = "X" }
		)
		assert(merged.Text == "aXf" and #merged.Ranges == 1, "overlapping multicursor selections edit once")
		local overwritten =
			Apps.EditorDocument.Apply("a🙂猫z", 2, 2, "InsertText", { Text = "é", Overwrite = true })
		assert(
			overwritten.Text == "aé猫z" and overwritten.Caret == 4,
			"overwrite replaces one complete Unicode codepoint"
		)
		assert(
			Apps.EditorDocument.Apply("a\nb", 2, 2, "InsertText", { Text = "X", Overwrite = true }).Text == "aX\nb",
			"overwrite never consumes a line separator"
		)
		local packet = set.Copy("red blue", { { Anchor = 1, Caret = 4 }, { Anchor = 5, Caret = 9 } })
		local pasted = set.Paste("1 2", { { Anchor = 1, Caret = 1 }, { Anchor = 3, Caret = 3 } }, packet.Text, packet)
		assert(pasted.Text == "red1 blue2", "matching clipboard entries paste to their respective carets")
		assert(
			set.Paste("1 2", { { Anchor = 1, Caret = 1 }, { Anchor = 3, Caret = 3 } }, "external", packet).Text
				== "external1 external2",
			"external clipboard invalidates structured entries"
		)
		local line = set.Copy("one\ntwo", { { Anchor = 2, Caret = 2 } })
		assert(
			line.Text == "one\n" and set.Paste("abc", { { Anchor = 2, Caret = 2 } }, line.Text, line).Text == "one\nabc",
			"whole-line copy/paste retains line-start semantics"
		)

		local editor = Apps.ScriptViewer
		local cf = editor.CodeFrame
		keys.LeftControl = false
		keys.LeftShift = false
		keys.LeftAlt = false
		editor.OpenDocument("touch-input-test", "Touch input", "")
		local keyboard = service.UserInputService
		local wasTouch, wasKeyboard = keyboard.TouchEnabled, keyboard.KeyboardEnabled
		keyboard.TouchEnabled, keyboard.KeyboardEnabled = true, false
		local nativeBox = cf.GuiElems.EditBox
		nativeBox:CaptureFocus()
		assert(cf.TouchTextInput)
		for _, snapshot in {"p", "pr", "pri", "prin", "print", "prin", ""} do
			nativeBox.Text = snapshot
			assert(cf:HandleNativeTextChange(snapshot))
			assert(cf:GetText() == snapshot, "native composition and deletion: " .. snapshot)
		end
		nativeBox:ReleaseFocus()
		keyboard.TouchEnabled, keyboard.KeyboardEnabled = wasTouch, wasKeyboard
		editor.OpenDocument("native-batch-test", "Native transactions", "foo\nbar")
		cf.SelectionRange = { { 0, 0 }, { 0, 0 } }
		cf:MoveCursor(0, 0)
		cf.AdditionalSelections = { { { 0, 1 }, { 0, 1 } } }
		cf:AppendText("!")
		assert(
			cf:GetText() == "!foo\n!bar" and #cf.AdditionalSelections == 1,
			"ordinary input edits every caret in one source update"
		)
		editor.Undo(false)
		assert(
			cf:GetText() == "foo\nbar" and #cf.AdditionalSelections == 1 and cf.AdditionalSelections[1][1][1] == 0,
			"one undo restores text and all caret positions"
		)
		editor.Undo(true)
		assert(
			cf:GetText() == "!foo\n!bar" and cf.AdditionalSelections[1][1][1] == 1,
			"one redo restores complete multicursor transaction"
		)
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Right })
		assert(cf.CursorX == 2 and cf.AdditionalSelections[1][2][1] == 2, "navigation moves every caret")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Insert })
		assert(cf.OverwriteMode, "Insert enables overwrite")
		cf:AppendText("Z")
		assert(cf:GetText() == "!fZo\n!bZr", "overwrite edits all carets without inserting extra characters")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Insert })
		assert(not cf.OverwriteMode, "Insert toggles back to insert")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Escape })
		assert(#cf.AdditionalSelections == 0, "Escape returns to a single caret")
		keys.LeftAlt = true
		cf:HandleEditorPointer({ UserInputType = Enum.UserInputType.MouseButton1 }, 0, 1)
		keys.LeftAlt = false
		assert(
			#cf.AdditionalSelections == 1 and cf.CursorY == 0,
			"Alt-click adds a secondary caret while retaining the initial primary"
		)
		local first = editor.ActiveDocument
		editor.OpenDocument("native-batch-second", "Other caret state", "other")
		assert(#cf.AdditionalSelections == 0 and not cf.OverwriteMode, "new document starts with one insert-mode caret")
		editor.SelectDocument(first)
		assert(#cf.AdditionalSelections == 1, "switching documents restores the whole selection set")
		local oldWrite, oldRead = deps.env.setclipboard, deps.env.getclipboard
		local clipboard
		deps.env.setclipboard = function(text)
			clipboard = text
		end
		deps.env.getclipboard = function()
			return clipboard
		end
		cf.AdditionalSelections = {}
		cf:SetText("alpha\nbeta")
		cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
		cf:MoveCursor(5, 0)
		cf.AdditionalSelections = { { { 0, 1 }, { 4, 1 } } }
		assert(editor.CopySelection() and clipboard == "alpha\nbeta", "copy collects ordered selected text")
		cf:SetText("x\ny")
		cf.SelectionRange = { { 0, 0 }, { 0, 0 } }
		cf:MoveCursor(0, 0)
		cf.AdditionalSelections = { { { 0, 1 }, { 0, 1 } } }
		editor.PasteFromClipboard()
		assert(cf:GetText() == "alphax\nbetay", "controller retains structured per-cursor clipboard data")
		cf.Editable = false
		local before = cf:GetText()
		editor.Command("InsertText", { Text = "blocked" })
		editor.PasteText("blocked")
		assert(cf:GetText() == before, "read-only guards cover every caret")
		cf.Editable = true
		cf.AdditionalSelections = {}
		editor.OpenDocument("unicode-input-route", "Unicode input", "a🙂b")
		cf:MoveCursor(1, 0)
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Right })
		assert(cf.CursorX == 5, "single-caret Right advances over an entire Unicode glyph")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Left })
		assert(cf.CursorX == 1, "single-caret Left returns to the legal insertion boundary")
		cf:SetText("")
		cf.SelectionRange = { { 0, 0 }, { 0, 0 } }
		cf:MoveCursor(0, 0)
		editor.PasteText("\tA\r\n\tB")
		assert(
			cf:GetText() == "A\nB" and cf.CursorX == 1 and cf.CursorY == 1,
			"paste formats tab-indented lines and normalizes CRLF before restoring the caret"
		)
		cf:SetText("one two\nthree four")
		cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
		cf:MoveCursor(7, 0)
		cf.AdditionalSelections = { { { 10, 1 }, { 10, 1 } } }
		keys.LeftControl = true
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Backspace })
		keys.LeftControl = false
		service.UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.Backspace })
		assert(
			cf:GetText() == "one \nthree ",
			"Ctrl+Backspace deletes words at every caret without legacy primary-only edits"
		)
		cf.AdditionalSelections = {}
		editor.OpenDocument("preferred-column", "Preferred column", "abcdefghij\nx\nabcdefghij")
		cf.SelectionRange = { { 8, 0 }, { 8, 0 } }
		cf:MoveCursor(8, 0)
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Down })
		assert(cf.CursorX == 1 and cf.CursorY == 1, "vertical motion clamps to short lines")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Down })
		assert(cf.CursorX == 8 and cf.CursorY == 2, "vertical motion restores the preferred column after a short line")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Left })
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Up })
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Up })
		assert(cf.CursorX == 7 and cf.CursorY == 0, "horizontal motion resets the preferred vertical column")
		editor.OpenDocument("cursor-shortcuts", "Cursor shortcuts", "abcdef\nx\nabcdef")
		cf.SelectionRange = { { 4, 0 }, { 4, 0 } }
		cf:MoveCursor(4, 0)
		keys.LeftControl = true
		keys.LeftAlt = true
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Down })
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Down })
		assert(
			#cf.AdditionalSelections == 2 and cf.CursorY == 0 and cf.AdditionalSelections[2].Caret[1] == 4,
			"Ctrl+Alt+Down adds consecutive carets retaining the primary and preferred column"
		)
		keys.LeftAlt = false
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.U })
		assert(#cf.AdditionalSelections == 1, "Ctrl+U removes only the newest secondary")
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.U })
		keys.LeftControl = false
		assert(
			#cf.AdditionalSelections == 0 and cf.CursorX == 4,
			"removing all secondary cursors preserves the primary"
		)
		keys.LeftAlt = true
		cf:HandleEditorPointer({ UserInputType = Enum.UserInputType.MouseButton1 }, 0, 1)
		assert(#cf.AdditionalSelections == 1, "Alt-click adds a cursor")
		cf:HandleEditorPointer({ UserInputType = Enum.UserInputType.MouseButton1 }, 0, 1)
		assert(#cf.AdditionalSelections == 0, "Alt-click on the same cursor removes it")
		service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		keys.LeftAlt = false
		editor.OpenDocument("matching-cursors", "Matching cursors", "cat cat cat")
		cf.SelectionRange = { { 1, 0 }, { 1, 0 } }
		cf:MoveCursor(1, 0)
		keys.LeftControl = true
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.D })
		assert(
			cf.SelectionRange[1][1] == 0 and cf.SelectionRange[2][1] == 3 and #cf.AdditionalSelections == 0,
			"first Ctrl+D selects the word at the caret"
		)
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.D })
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.D })
		assert(
			#cf.AdditionalSelections == 2 and cf.CursorX == 3,
			"subsequent Ctrl+D adds the next matching selection without moving the primary"
		)
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.D })
		keys.LeftControl = false
		assert(#cf.AdditionalSelections == 2, "matching selection wrap does not duplicate occupied ranges")
		cf:AppendText("dog")
		assert(cf:GetText() == "dog dog dog", "matching-cursor edits replace every selection in one action")
		editor.Undo(false)
		assert(
			cf:GetText() == "cat cat cat" and #cf.AdditionalSelections == 2,
			"one undo restores all matching selections"
		)
		editor.OpenDocument("split-cursors", "Split cursors", "abc\ndef\nghi")
		cf.SelectionRange = { { 1, 0 }, { 2, 2 } }
		cf:MoveCursor(2, 2)
		keys.LeftShift = true
		keys.LeftAlt = true
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.I })
		keys.LeftShift = false
		keys.LeftAlt = false
		assert(
			#cf.AdditionalSelections == 2 and cf:GetText() == "abc\ndef\nghi",
			"splitting a multiline selection adds one selection per line without editing source"
		)
		cf:AppendText("X")
		assert(cf:GetText() == "aX\nX\nXi", "split selections replace only their selected portions on each line")
		editor.OpenDocument("all-cursors-readonly", "Read-only cursor selection", "cat cat cat")
		cf.Editable = false
		cf.SelectionRange = { { 0, 0 }, { 3, 0 } }
		cf:MoveCursor(3, 0)
		keys.LeftShift = true
		keys.LeftAlt = true
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.L })
		keys.LeftShift = false
		keys.LeftAlt = false
		assert(
			#cf.AdditionalSelections == 2 and cf:GetText() == "cat cat cat",
			"select-all-matching works without editing a read-only document"
		)
		cf.Editable = true
		editor.OpenDocument("drag-cursors", "Drag cursors", "abcd\nefgh\nijkl")
		local oldScreenPoint, oldMouse = cf.ScreenToEditorPoint, Main.Mouse
		cf.ScreenToEditorPoint = function(_, x, y)
			return x, y
		end
		keys.LeftAlt = true
		cf:HandleEditorPointer({ UserInputType = Enum.UserInputType.MouseButton1 }, 1, 0)
		Main.Mouse = { X = 3, Y = 1 }
		service.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
		assert(
			#cf.AdditionalSelections == 1
				and cf.AdditionalSelections[1][1][1] == 1
				and cf.AdditionalSelections[1][2][2] == 1,
			"Alt-drag extends an added selection while retaining the primary"
		)
		Main.Mouse = { X = 1, Y = 0 }
		service.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
		assert(
			cf.AdditionalSelections[1][1][1] == cf.AdditionalSelections[1][2][1]
				and cf.AdditionalSelections[1][2][2] == 0,
			"dragging back to the anchor restores a collapsed secondary"
		)
		service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		keys.LeftShift = true
		cf:HandleEditorPointer({ UserInputType = Enum.UserInputType.MouseButton1 }, 1, 0)
		Main.Mouse = { X = 3, Y = 2 }
		service.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
		assert(
			#cf.AdditionalSelections == 2 and cf.SelectionRange[1][1] == 1 and cf.SelectionRange[2][1] == 3,
			"Shift+Alt drag creates measured column selections on all touched rows"
		)
		service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		keys.LeftAlt = false
		keys.LeftShift = false
		cf.ScreenToEditorPoint, Main.Mouse = oldScreenPoint, oldMouse
		cf:AppendText("X")
		assert(cf:GetText() == "aXd\neXh\niXl", "block selections edit independent row ranges in one transaction")
		deps.env.setclipboard, deps.env.getclipboard = oldWrite, oldRead
		print(
			"PASS: source-backed multicursor batches, Unicode overwrite, structured clipboard, whole-line paste and complete selection undo/redo"
		)
	end)()
end
