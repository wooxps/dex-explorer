--!strict

do
	local doc = editor.OpenDocument("reconstruction", "Client Editor", "local value = 1\nprint(value)")
	cf:MoveCursor(0, 0)
	editor.Command("ToggleComment")
	assert(cf:GetText():sub(1, 2) == "--", "comment command edits selected line")
	editor.Undo(false)
	assert(cf:GetText() == "local value = 1\nprint(value)", "comment command is one undo transaction")
	cf:MoveCursor(0, 0)
	editor.Command("DuplicateLines")
	assert(
		cf:GetText() == "local value = 1\nlocal value = 1\nprint(value)",
		"duplicate line through actual document/controller"
	)
	editor.Undo(false)
	cf:SetText("")
	cf:MoveCursor(0, 0)
	cf:AppendText("(")
	assert(cf:GetText() == "()" and cf.CursorX == 1, "typing opening bracket pairs and leaves caret inside")
	cf:AppendText(")")
	assert(cf:GetText() == "()" and cf.CursorX == 2, "existing closer is skipped rather than duplicated")
	cf:MoveCursor(1, 0)
	editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Backspace })
	assert(cf:GetText() == "", "backspace removes matching pair")
	cf:SetText("local uniqueName = 3\nuni")
	cf:MoveCursor(3, 1)
	assert(editor.Complete(), "lexical completion offers local identifiers")
	local popup = editor.CompletionPopup
	assert(popup.Visible and #popup.Suggestions:GetChildren() <= 8, "completion viewport has bounded suggestion rows")
	local found
	for _, button in ipairs(popup.Suggestions:GetChildren()) do
		if button.Label.Text == "uniqueName" then
			found = button
		end
	end
	assert(found, "local identifier suggestion")
	found.MouseButton1Click:Fire()
	assert(cf:GetText() == "local uniqueName = 3\nuni", "first click selects a completion")
	found.MouseButton1Click:Fire()
	assert(cf:GetText() == "local uniqueName = 3\nuniqueName", "double-click inserts the selected completion")
	editor.Undo(false)
	assert(cf:GetText() == "local uniqueName = 3\nuni", "completion has one undo step")
	local language = Apps.EditorLanguage.New()
	assert(not language:Complete('print("pri', 11), "no completion within quoted strings")
	assert(not language:Complete("-- pri", 7), "no completion within comments")
	local suggestion = language:Complete("math.sq", 8)
	assert(
		suggestion and suggestion.Items[1].Name == "sqrt",
		"known library functions complete without executing game functions"
	)
	assert(not language:Complete('print("math.', 13), "empty member prefix inside a string is not code")
	assert(not language:Complete("-- math.", 9), "empty member prefix inside a comment is not code")
	assert(not language:Complete("--[=[ math.", 12), "long comment member access is not code")
	assert(not language:Complete("[==[ math.", 11), "long string member access is not code")
	do
		local folder = Instance.new("Folder", workspace)
		folder.Name = "Completion Fixture"
		local rocket = Instance.new("Model", folder)
		rocket.Name = "RocketShip"
		local module = Instance.new("ModuleScript", folder)
		module.Name = "RocketModule"
		local enums = API.Enums
		API.Enums = { KeyCode = { Items = { { Name = "Space" } } } }
		local function expect(text, name, kind)
			local result = language:Complete(text, #text + 1, { Workspace = workspace, Game = game })
			for _, item in ipairs(result and result.Items or {}) do
				if item.Name == name and item.Kind == kind then
					return item
				end
			end
			error("Missing completion for " .. text)
		end
		assert(expect("Enum.KeyCode.Sp", "Space", "Enum").Detail == "Enum.KeyCode.Space")
		assert(expect('Instance.new("Pa', "Part", "Instance").InsertText == "Part")
		assert(
			expect('workspace:WaitForChild("Comp', "Completion Fixture", "Instance").InsertText == "Completion Fixture"
		)
		assert(expect('workspace["Completion Fixture"].Roc', "RocketShip", "Instance").Detail == "Model")
		assert(expect('workspace["Completion Fixture"].Ship', "RocketShip", "Instance").Detail == "Model")
		assert(expect('workspace["Completion Fixture"].Rkt', "RocketShip", "Instance").Detail == "Model")
		local exact = 'workspace["Completion Fixture"].RocketShip'
		assert(not language:Complete(exact, #exact + 1), "a sole exact suggestion is suppressed")
		assert(expect('workspace:WaitForChild("Completion Fixture").Roc', "RocketShip", "Instance").Detail == "Model")
		assert(
			expect('require("@/Workspace/Completion Fixture/Rock', "RocketModule", "Instance").InsertText
				== "RocketModule"
		)
		API.Enums = enums
		folder:Destroy()
	end
	local typingSource = "local apple = 1\nlocal apply = 2\na"
	cf:SetText(typingSource)
	cf:MoveCursor(1, 2)
	cf.SelectionRange = { { 1, 2 }, { 1, 2 } }
	cf.GuiElems.EditBox:CaptureFocus()
	flushTasks()
	assert(not popup.Visible, "programmatic buffer changes do not reopen completion")
	cf:AppendText("p")
	flushTasks()
	assert(popup.Visible, "typing opens suggestions after the caret moves")
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.PageDown }))
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Home }))
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.End }))
	assert(cf.CursorX == 2 and cf.CursorY == 2, "popup navigation does not move the editor caret")
	cf:AppendText("p")
	assert(popup.Visible, "the same completion session survives typing before debounce")
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Tab }))
	cf:AppendText("\t")
	flushTasks()
	assert(cf:GetText() == typingSource .. "pply", "Tab retains the selected suggestion during debounce")
	cf:SetText("math.sqTAIL")
	cf:MoveCursor(7, 0)
	cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
	assert(editor.Complete() and editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Return }))
	cf:AppendText("\n")
	assert(cf:GetText() == "math.sqrtTAIL", "Enter completes the prefix and keeps the suffix")
	cf:SetText("math.sqTAIL")
	cf:MoveCursor(7, 0)
	cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
	assert(editor.Complete())
	cf:AppendText("r")
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Return }))
	cf:AppendText("\n")
	flushTasks()
	assert(cf:GetText() == "math.sqrtTAIL", "Enter keeps the suffix during debounce")
	cf:SetText("math.sqTAIL")
	cf:MoveCursor(7, 0)
	cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
	assert(editor.Complete() and editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Tab }))
	cf:AppendText("\t")
	assert(cf:GetText() == "math.sqrt()", "Tab replaces the complete word")
	local function acceptCall(source, x, y, expected, expectedX)
		cf:SetText(source)
		cf:MoveCursor(x, y)
		cf.SelectionRange = { { x, y }, { x, y } }
		assert(editor.Complete() and editor.AcceptCompletion(false), source)
		assert(cf:GetText() == expected and cf.CursorX == expectedX, source .. " produced " .. cf:GetText())
	end
	acceptCall("math.sq", 7, 0, "math.sqrt()", 10)
	acceptCall("math.sq (9)", 7, 0, "math.sqrt (9)", 9)
	acceptCall('war "hello"', 3, 0, 'warn "hello"', 4)
	acceptCall("os.clo", 6, 0, "os.clock()", 10)
	acceptCall("Color3.ne", 9, 0, "Color3.new()", 11)
	acceptCall("local v = Vector3.new()\nv . Do", 6, 1, "local v = Vector3.new()\nv : Dot()", 8)
	acceptCall("local function refresh() end\nrefre", 5, 1, "local function refresh() end\nrefresh()", 9)
	acceptCall("local refresh = function(value) end\nrefre", 5, 1, "local refresh = function(value) end\nrefresh()", 8)
	acceptCall(
		"local callback: (number) -> number = math.sq",
		44,
		0,
		"local callback: (number) -> number = math.sqrt",
		46
	)
	cf:SetText("local uniqueName = 3\nuni")
	cf:MoveCursor(3, 1)
	editor.Complete()
	cf:MoveCursor(0, 0)
	assert(
		not editor.AcceptCompletion() and cf:GetText() == "local uniqueName = 3\nuni",
		"moving caret invalidates stale replacement range"
	)
	cf:SetText("target")
	cf.SelectionRange = { { 0, 0 }, { 6, 0 } }
	cf:MoveCursor(6, 0)
	cf:AppendText("(")
	assert(
		cf:GetText() == "(target)" and cf.SelectionRange[1][1] == 1 and cf.SelectionRange[2][1] == 7,
		"bracket pair wraps selection without losing selected content"
	)
	cf:SetText("{}")
	cf:MoveCursor(1, 0)
	cf.SelectionRange = { { 1, 0 }, { 1, 0 } }
	cf:AppendText("\n")
	assert(
		cf:GetText() == "{\n    \n}" and cf.CursorX == 4 and cf.CursorY == 1,
		"newline between matching braces preserves closing line and inner caret"
	)
	editor.Undo(false)
	assert(cf:GetText() == "{}", "paired newline is one undo transaction")
	cf:SetText("uni")
	cf:MoveCursor(3, 0)
	cf.SelectionRange = { { 3, 0 }, { 3, 0 } }
	editor.Complete()
	-- The visible source identifier is gone in this buffer, so explicitly use a
	-- library member whose replacement is deterministic.
	cf:SetText("math.sq")
	cf:MoveCursor(7, 0)
	cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
	editor.Complete()
	local previousMouse = Main.Mouse
	Main.Mouse = { X = popup.AbsolutePosition.X + 1, Y = popup.AbsolutePosition.Y + 1 }
	cf.GuiElems.EditBox.FocusLost:Fire(false)
	assert(popup.Visible, "suggestion mouse-down focus loss preserves popup until mouse-up acceptance")
	Main.Mouse = { X = -999, Y = -999 }
	cf.GuiElems.EditBox.FocusLost:Fire(false)
	assert(not popup.Visible, "focus loss outside popup dismisses suggestions")
	Main.Mouse = previousMouse
	editor.Complete()
	assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Tab }), "Tab accepts a visible completion")
	cf:AppendText("\t")
	assert(
		cf:GetText() == "math.sqrt()",
		"native TextBox Tab does not append a second indent after accepting completion"
	)
	cf:MoveCursor(#cf:GetText(), 0)
	cf.SelectionRange = { { #cf:GetText(), 0 }, { #cf:GetText(), 0 } }
	editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Tab })
	cf:AppendText("\t")
	assert(cf:GetText() == "math.sqrt()    ", "Tab command consumes duplicate native tab only once")
	cf:AppendText("x")
	assert(cf:GetText() == "math.sqrt()    x", "native suppression cannot swallow unrelated text")
	local clipboard, previousClipboard = nil, deps.env.setclipboard
	deps.env.setclipboard = function(text)
		clipboard = text
	end
	cf:SetText("first second")
	cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
	cf:MoveCursor(5, 0)
	assert(
		editor.CopySelection() and clipboard == "first" and cf:GetText() == "first second",
		"copy only copies actual source selection"
	)
	assert(
		editor.CutSelection() and clipboard == "first" and cf:GetText() == " second",
		"cut copies and deletes selection"
	)
	editor.Undo(false)
	assert(cf:GetText() == "first second", "cut is one undo transaction")
	cf.SelectionRange = { { 0, 0 }, { 0, 0 } }
	cf:MoveCursor(0, 0)
	assert(
		editor.CutSelection() and cf:GetText() == "" and clipboard == "first second\n",
		"native no-selection cut removes the current line"
	)
	editor.Undo(false)
	assert(cf:GetText() == "first second", "whole-line cut is one undo transaction")
	cf.SelectionRange = { { 0, 0 }, { 5, 0 } }
	cf:MoveCursor(5, 0)
	deps.env.setclipboard = function()
		error("clipboard denied")
	end
	assert(
		not editor.CutSelection() and cf:GetText() == "first second",
		"failed clipboard write cannot discard selected source"
	)
	deps.env.setclipboard = previousClipboard
	cf:SetText("local one = 1\nreturn one")
	local compilerCalls = 0
	local previousCompiler = deps.env.loadstring
	deps.env.loadstring = function()
		compilerCalls += 1
		error("Unexpected compiler call")
	end
	local checked = editor.CheckSyntax()
	assert(checked.Passed and compilerCalls == 0, "syntax checking uses only the parser")
	cf:SetText("local one = 1\nlocal 42 = 2\nlocal 37 = 3")
	checked = editor.CheckSyntax()
	assert(#checked.Errors >= 2 and #cf.SyntaxRanges == #checked.Errors and compilerCalls == 0)
	assert(cf.SyntaxRanges[1].First[1] == 6 and cf.SyntaxRanges[1].Last[1] == 8)
	cf.AdditionalSelections = { { { 0, 0 }, { 0, 0 } } }
	assert(
		checked.Line == 2 and editor.GoToDiagnostic() and cf.CursorY == 1,
		"syntax error points to exact editor line"
	)
	assert(
		#cf.AdditionalSelections == 0 and cf.SelectionRange[1][2] == 1,
		"diagnostic navigation replaces the complete selection"
	)
	deps.env.loadstring = previousCompiler
	cf:SetText("cat concatenate cat")
	find.Text = "cat"
	editor.SetWholeWord(true)
	replace.Text = "dog"
	editor.Replace(true)
	assert(cf:GetText() == "dog concatenate dog", "whole-word replacement leaves substrings intact")
	editor.SetWholeWord(false)
	assert(
		editor.LanguageCapabilities.NativeDebugger == false and editor.LanguageCapabilities.NativeTypeChecker == false,
		"native services are not presented as implemented"
	)
	editor.DismissCompletion()
	print(
		"PASS: integrated editor commands, atomic undo, pairing, bounded completion, lexical context, parser diagnostics and whole-word replacement"
	)
end
