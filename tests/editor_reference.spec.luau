--!strict

do
	local symbols = Apps.EditorSymbols.New()
	local source =
		"-- function fake() end\nlocal function createPart(pos: Vector3)\n return pos\nend\nlocal holder = workspace.Buildings\nlocal assigned = function(value) return value end\ncreatePart(1)"
	symbols:Index(source)
	assert(
		#symbols.Functions == 2
			and symbols.Functions[1].Name == "createPart"
			and symbols.Functions[2].Name == "assigned",
		"function index covers declarations/assignments while excluding comments"
	)
	assert(
		symbols.Functions[1].Signature == "createPart(pos: Vector3)",
		"function filter preserves actual parameter annotations"
	)
	local position = source:find("createPart(1)", 1, true)
	assert(
		symbols:Find("createPart", position).Position == source:find("createPart", 1, true),
		"go-to-declaration resolves source offset"
	)
	local folder = workspace:FindFirstChild("Buildings")
	assert(
		symbols:Resolve("holder", { Workspace = workspace }, #source + 1) == folder,
		"safe local alias resolution reads existing child path"
	)
	local _, kind = symbols:Resolve('Instance.new("Part")', {}, #source + 1)
	assert(kind == "Part", "constructor inference obtains class without constructing an object")
	local documented = Apps.EditorSymbols.New()
	documented:Index(
		"--[=[Utility comment]=]\nlocal function add(a: number): number return a end\n"
			.. "--[[A configured value.]]\nlocal value = 1\n"
			.. "export type Icon = { new: typeof(--[[Constructs an icon.]] function(): Icon end) }"
	)
	assert(documented:Find("add").Documentation == "Utility comment")
	assert(documented:Find("value").Documentation == "A configured value.")
	assert(documented.DocumentedFields.new.Documentation == "Constructs an icon.")
	local previousPart = API.Classes.Part.Functions
	API.Classes.Part.Functions =
		{ { Name = "IsDescendantOf", Parameters = { { Name = "ancestor", Type = "Instance" } }, ReturnType = "bool" } }
	local constructorSource = 'Instance.new("Part"):IsD'
	local constructor = Apps.EditorLanguage.New():Complete(constructorSource, #constructorSource + 1, {})
	assert(
		constructor and constructor.Items[1].Name == "IsDescendantOf",
		"inline constructor completion uses API class without evaluating constructor"
	)
	API.Classes.Part.Functions = previousPart
	local noEval = symbols:Resolve("workspace:InvokeServer()", {}, #source + 1)
	assert(noEval == nil, "unsupported call expressions are never invoked")
	local language = Apps.EditorLanguage.New()
	local typedSource = "local variable = 1\nvar"
	local typed = language:Complete(typedSource, #typedSource + 1, {})
	local variable
	for _, item in ipairs(typed.Items) do
		if item.Name == "variable" then
			variable = item
		end
	end
	assert(
		variable and variable.TypeOnly and variable.Detail == "number",
		"literal local variables provide a compact type card instead of Identifier boilerplate"
	)
	local result = language:Complete("workspace.Build", 16, { Workspace = workspace })
	local child
	for _, item in ipairs(result and result.Items or {}) do
		if item.Name == "Buildings" then
			child = item
		end
	end
	assert(
		child and child.Kind == "Instance" and child.ClassName == "Folder",
		"data-model completion includes actual child class"
	)
	local aliased = "local holder = workspace\nholder.Build"
	result = language:Complete(aliased, #aliased + 1, { Workspace = workspace })
	child = nil
	for _, item in ipairs(result and result.Items or {}) do
		if item.Name == "Buildings" then
			child = item
		end
	end
	assert(child, "local instance aliases receive client child suggestions")
	cf:SetText("local function sample(first: number, second: Vector3): number\n return first\nend\nsample(1, ")
	cf:MoveCursor(10, 3)
	cf.SelectionRange = { { 10, 3 }, { 10, 3 } }
	local measuredCursor = cf.GetColumnPixelX
	local anchorMeasurements = 0
	cf.GetColumnPixelX = function(self, column, row)
		anchorMeasurements += 1
		return measuredCursor(self, column, row)
	end
	editor.UpdateSignature()
	assert(anchorMeasurements > 0, "signature help anchors through measured cursor geometry")
	cf.GetColumnPixelX = measuredCursor
	assert(
		editor.SignatureHelp.Visible
			and editor.SignatureHelp.Signature.Text == "sample(first: number, <b>second: Vector3</b>): number",
		"signature help emphasizes the active argument inline"
	)
	cf:SetText("local function sample(a: {number}, f: (number, number) -> number) end\nsample({1, 2}, (")
	cf:MoveCursor(#cf.Lines[2], 1)
	editor.UpdateSignature()
	assert(
		editor.SignatureHelp.Visible
			and editor.SignatureHelp.Signature.Text
				== "sample(a: {number}, <b>f: (number, number) -&gt; number</b>)",
		"grouping and nested commas keep the enclosing active argument"
	)
	cf:SetText("local c1 = Color3.new(10,0)")
	cf:MoveCursor(25, 0)
	cf.SelectionRange = { { 25, 0 }, { 25, 0 } }
	editor.UpdateSignature()
	assert(
		editor.SignatureHelp.Visible
			and editor.SignatureHelp.Signature.Text == "new(red: number?, <b>green: number?</b>, blue: number?): Color3"
			and editor.SignatureHelp.Outline.Thickness == 1,
		"Color3 signature matches the documented type annotations and outlined card"
	)
	assert(
		editor.SignatureHelp.Parent.ColorSwatch.Visible,
		"numeric Color3 literals show a swatch while editing arguments"
	)
	local inferredCall =
		"local api = { Apply = function(value: number, amount: number) return value + amount end }\napi.Apply(1, "
	cf:SetText(inferredCall)
	cf:MoveCursor(#cf.Lines[2], 1)
	editor.UpdateSignature()
	assert(
		editor.SignatureHelp.Visible
			and editor.SignatureHelp.Signature.Text == "Apply(value: number, <b>amount: number</b>): number",
		"signature help uses inferred table functions and the current argument"
	)
	local callback =
		"local function spawn(fn: () -> (), delay: number) end\nspawn(function()\n    local label = 'end'\n    if label then\n        math.sqrt(4)\n    end\n    \nend, 1)"
	cf:SetText(callback)
	cf:MoveCursor(4, 6)
	editor.UpdateSignature()
	assert(not editor.SignatureHelp.Visible, "signature lookup cannot escape the active callback body")
	cf:MoveCursor(#"        math.sqrt(", 4)
	editor.UpdateSignature()
	assert(editor.SignatureHelp.Visible and editor.SignatureHelp.Signature.Text:find("sqrt", 1, true))
	cf:MoveCursor(#"end, ", 7)
	editor.UpdateSignature()
	assert(editor.SignatureHelp.Visible and editor.SignatureHelp.Signature.Text:find("<b>delay: number</b>", 1, true))
	cf:SetText("local function sample(first: number, second: Vector3): number\n return first\nend\nsample(1, ")
	editor.OpenFunctionFilter()
	local panel = editor.FunctionFilter
	assert(
		panel.Visible and panel.Filter.PlaceholderText == "Filter functions",
		"document function filter is focusable"
	)
	panel.Filter.Text = "missing"
	panel.Filter:GetPropertyChangedSignal("Text"):Fire()
	local visible = 0
	for _, row in ipairs(panel.Functions:GetChildren()) do
		if row.Visible then
			visible += 1
		end
	end
	assert(visible == 0, "function filter hides nonmatching rows")
	panel.Filter.Text = "sample"
	panel.Filter:GetPropertyChangedSignal("Text"):Fire()
	local row = panel.Functions:GetChildren()[1]
	assert(
		row
			and row.Visible
			and row.Text == "<b>sample(first : number, second : Vector3)</b>\n(number, Vector3) -&gt; number",
		"function filter shows the bold declaration and Luau type signature"
	)
	cf.AdditionalSelections = { { { 0, 2 }, { 0, 2 } } }
	row.MouseButton1Click:Fire()
	row.MouseButton1Click:Fire()
	assert(not panel.Visible and cf.CursorY == 0 and cf.CursorX == 15, "double click jumps to exact declaration name")
	assert(#cf.AdditionalSelections == 0, "declaration jumps clear unrelated extra carets")
	assert(
		cf.SelectionRange[1][1] == 15 and cf.SelectionRange[2][1] == 21,
		"function filter selects the declaration name"
	)
	cf:MoveCursor(4, 3)
	assert(editor.GoToDeclaration() and cf.CursorY == 0, "keyboard declaration navigation reaches function")
	assert(cf.SelectionRange[1][1] == 15 and cf.SelectionRange[2][1] == 21)
	local lines = cf.GuiElems.LinesFrame or cf.Frame
	local function pointerAt(column, row)
		Main.Mouse.X = lines.AbsolutePosition.X
			+ cf:GetColumnPixelX(column, row)
			- Apps.CodeViewport.ScrollPixelX(cf)
			+ 1
		Main.Mouse.Y = lines.AbsolutePosition.Y + (cf:SourceToDisplay(row) - cf.ViewY) * cf.FontSize + 1
	end
	local mouseDown = { UserInputType = Enum.UserInputType.MouseButton1 }
	do
		local oldX, oldY = Main.Mouse.X, Main.Mouse.Y
		local compiler, clipboard = deps.env.loadstring, deps.env.setclipboard
		local user = service.UserInputService
		local movement = { UserInputType = Enum.UserInputType.MouseMovement }
		local cursorOverlay = Instance.new("ScreenGui", game)
		cursorOverlay.DisplayOrder = (editor.Window.Gui.DisplayOrder or 0) + 100
		cursorOverlay.Enabled = true
		cursorOverlay:SetAttribute("DexCursorOverlay", true)
		local image = Instance.new("ImageLabel", cursorOverlay)
		image.Size = UDim2.fromScale(1, 1)
		local oldInternal = Main.InternalGuis
		Main.InternalGuis = { [cursorOverlay] = true }
		pointerAt(1, 0)
		assert(
			Apps.EditorHitTest.OwnsPoint(editor.Window, lines, Main.Mouse.X, Main.Mouse.Y),
			"cursor overlay cannot block editor hit tests"
		)
		Main.InternalGuis = oldInternal
		cursorOverlay:Destroy()
		local oldDocument = editor.ActiveDocument
		local fixture = editor.OpenDocument({}, "Hover lifecycle", "local  42 = 0")
		deps.env.loadstring = function()
			return nil, "DexEditor:1: Expected an expression"
		end
		local copied
		deps.env.setclipboard = function(url)
			copied = url
		end
		editor.CheckSyntax()
		cf.ScrollV:ScrollTo(0)
		cf.ScrollH:ScrollTo(0)
		pointerAt(7, 0)
		user.InputChanged:Fire(movement)
		flushTasks()
		local card = editor.Window.GuiElems.Content.EditorHover
		local hoverColor = card.BackgroundColor3
		assert(hoverColor.R == 25 / 255 and hoverColor.G == 26 / 255 and hoverColor.B == 31 / 255)
		assert(card.Visible and card.Link.Visible and card.Link.Text == "<u>Syntax Error:</u>")
		Main.Mouse.X = card.AbsolutePosition.X + 6
		Main.Mouse.Y = card.AbsolutePosition.Y + 8
		user.InputChanged:Fire(movement)
		flushTasks()
		user.InputBegan:Fire({
			UserInputType = Enum.UserInputType.MouseButton1,
			Position = Vector2.new(Main.Mouse.X, Main.Mouse.Y),
		})
		card.Link.Activated:Fire()
		assert(
			card.Visible and copied and copied:find("#script-analysis", 1, true),
			"syntax tooltip stays open and link activates"
		)
		Main.Mouse.X, Main.Mouse.Y = -10, -10
		user.InputChanged:Fire(movement)
		flushTasks()
		assert(not card.Visible, "moving away from code and card dismisses tooltip")
		deps.env.loadstring, deps.env.setclipboard = compiler, clipboard
		cf:SetText("--[[Adds one.]]\nlocal function add(value: number): number return value + 1 end\nadd(1)")
		cf.ScrollV:ScrollTo(0)
		pointerAt(1, 2)
		user.InputChanged:Fire(movement)
		flushTasks()
		assert(
			card.Visible
				and card.Signature.Text == "add(value: number): number"
				and card.DescriptionViewport.Description.Text == "Adds one."
		)
		local hoverView = Apps.EditorHover.Create(editor.Window.GuiElems.Content, cf)
		hoverView:Show(
			"xpcall",
			"Similar to <code>pcall()</code> except it uses a custom error handler.",
			2,
			0,
			false,
			"html",
			"https://create.roblox.com/docs/reference/engine/globals/LuaGlobals#xpcall"
		)
		local hoverCard = hoverView.Gui
		local viewport = hoverCard.DescriptionViewport
		viewport.Description.Size = UDim2.fromOffset(100, 500)
		viewport.Description:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		assert(viewport.Position.Y.Offset + viewport.Size.Y.Offset < hoverCard.Link.Position.Y.Offset)
		assert(hoverCard.Link.Position.Y.Offset + hoverCard.Link.Size.Y.Offset <= hoverCard.Size.Y.Offset)
		assert(viewport.CanvasSize.Y.Offset == 500 and viewport.ScrollBarThickness > 0)
		hoverCard:Destroy()
		editor.CloseDocument(fixture)
		editor.SelectDocument(oldDocument)
		Main.Mouse.X, Main.Mouse.Y = oldX, oldY
	end
	keys.LeftControl = true
	cf:MoveCursor(4, 3)
	cf.ScrollV:ScrollTo(0)
	pointerAt(4, 3)
	assert(
		cf:HandleEditorPointer(mouseDown, 4, 3) and cf.CursorY == 0,
		"Ctrl-click handler resolves the glyph under the pointer"
	)
	keys.LeftControl = false
	do
		local oldX, oldY = Main.Mouse.X, Main.Mouse.Y
		local module = Instance.new("ModuleScript", workspace)
		module.Name = "DefinitionTarget"
		module.Source = "return 'raw source'"
		local previousDecompiler = deps.env.decompile
		local decompiled
		deps.env.decompile = function(object)
			decompiled = object
			return "return 'decompiled source'"
		end
		local source = 'local unused = 1\n\tlocal target = require("@/Workspace/DefinitionTarget")'
		local origin = editor.OpenDocument({}, "Definition origin", source)
		cf.ScrollV:ScrollTo(0)
		cf.ScrollH:ScrollTo(0)
		pointerAt(assert(cf.Lines[2]:find("Definition", 1, true)) - 1, 1)
		keys.LeftControl = true
		local user = service.UserInputService
		user.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
		local link = cf.DefinitionLink
		assert(
			link and link.Row == 1 and cf.Lines[2]:sub(link.First + 1, link.Last) == "@/Workspace/DefinitionTarget",
			"Ctrl-hover marks the exact source span following the expanded tab"
		)
		keys.LeftControl = false
		user.InputEnded:Fire({ KeyCode = Enum.KeyCode.LeftControl })
		assert(not cf.DefinitionLink, "releasing Ctrl clears the underline")
		keys.LeftControl = true
		assert(cf:HandleEditorPointer(mouseDown), "click over a root-relative string path is consumed")
		flushTasks()
		keys.LeftControl = false
		assert(
			decompiled == module
				and editor.ActiveDocument.id == module
				and cf:GetText():find("return 'decompiled source'", 1, true)
				and not cf:GetText():find("return 'raw source'", 1, true),
			"Ctrl-click uses the same decompiler and source tab as manually opening the script"
		)
		keys.LeftAlt = true
		assert(
			editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Left })
				and editor.ActiveDocument == origin
				and cf.CursorY == 1,
			"Alt+Left restores the clicked location"
		)
		assert(
			editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Right }) and editor.ActiveDocument.id == module,
			"Alt+Right returns to the definition"
		)
		keys.LeftAlt = false
		editor.CloseDocument(editor.ActiveDocument)
		local folder = Instance.new("Folder", workspace)
		folder.Name = "DefinitionFolder"
		Apps.Explorer.SyncHistoryObject(folder)
		cf:SetText("return workspace.DefinitionFolder")
		cf:MoveCursor(22, 0)
		local explorerWindow = Apps.Explorer.Window
		local originalShow = explorerWindow.Show
		local shown = false
		explorerWindow.Show = function()
			shown = true
		end
		assert(editor.HandleEditorInput({ KeyCode = Enum.KeyCode.F12 }), "F12 navigates through the same resolver")
		assert(
			shown and Apps.Explorer.Selection.List[1].Obj == folder,
			"object paths reveal the actual Explorer instance"
		)
		explorerWindow.Show = originalShow
		folder:Destroy()
		editor.CloseDocument(origin)
		module:Destroy()
		deps.env.decompile = previousDecompiler
		Main.Mouse.X, Main.Mouse.Y = oldX, oldY
	end
	editor.OpenScriptPicker()
	assert(
		panel.Visible and panel.Filter.PlaceholderText == "Search open scripts",
		"quick open lists existing documents without decompiling scripts"
	)
	service.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Escape })
	assert(not panel.Visible, "Escape dismisses navigation")
	anchorMeasurements = 0
	cf.GetColumnPixelX = function(self, column, row)
		anchorMeasurements += 1
		return measuredCursor(self, column, row)
	end
	cf:SetText("math.sq")
	cf:MoveCursor(7, 0)
	cf.SelectionRange = { { 7, 0 }, { 7, 0 } }
	editor.Complete()
	assert(anchorMeasurements > 0, "completion anchors through measured cursor geometry")
	cf.GetColumnPixelX = measuredCursor
	assert(
		editor.CompletionPopup.Documentation.Signature.Text ~= ""
			and editor.CompletionPopup.Documentation.Size.X.Offset > 0,
		"completion has separate populated documentation panel"
	)
	do
		local testHost = Instance.new("Frame")
		testHost.Size = UDim2.fromOffset(900, 400)
		local view = Apps.EditorCompletion.Create(testHost, cf, function() end, function() end)
		local source = cf:GetText()
		local column, row = cf.CursorX, cf.CursorY
		cf:SetText("le")
		cf:MoveCursor(2, 0)
		view:Render({
			First = 1,
			Items = {
				{ Name = "level", Kind = "Identifier", Detail = "Identifier" },
				{ Name = "local", Kind = "Keyword", Detail = "Keyword" },
			},
		}, 1)
		assert(not view.Gui.Documentation.Visible, "generic kind labels do not manufacture an empty documentation card")
		assert(
			view.Gui.Size.Y.Offset == 2 * (cf.FontSize + 4) + 2 and view.List.Size.Y.Offset == view.Gui.Size.Y.Offset,
			"two suggestions occupy two font-sized rows and the native frame allowance without a forced 150 pixel panel"
		)
		assert(
			view.List.Size.X.Offset == cf.FontSize * 19 + 2 and #view.Gui.SuggestionsOutline:GetChildren() == 4,
			"completion list matches reference width with independently painted borders"
		)
		assert(
			view.Rows[1].Kind.Visible and view.Rows[1].Kind.Image == "mockasset://native/editor/completion/text",
			"identifiers use original autocomplete icons"
		)
		local firstRow = view.Rows[1]
		assert(
			firstRow.Kind.Position == UDim2.fromOffset(2, 2)
				and firstRow.Kind.Size == UDim2.fromOffset(cf.FontSize, cf.FontSize)
				and firstRow.Label.Position.X.Offset == cf.FontSize + 5,
			"completion row follows the native font-sized icon and text alignment"
		)
		assert(
			view.Rows[2].Kind.Image == "mockasset://native/editor/completion/keyword",
			"keywords use the native dedicated completion glyph"
		)
		local x = view.Gui.Position.X.Offset
		cf:SetText("lev")
		cf:MoveCursor(3, 0)
		view:Render({ First = 1, Items = { { Name = "level", Kind = "Identifier", Detail = "Identifier" } } }, 1)
		assert(
			view.Gui.Position.X.Offset > x,
			"popup follows the caret as shown in the official Studio reference images"
		)
		view:Render({ Items = { { Name = "variable", Kind = "Variable", Detail = "number", TypeOnly = true } } }, 1)
		assert(
			view.Gui.Documentation.Visible
				and view.Gui.Documentation.Signature.Text == "number"
				and view.Gui.Documentation.Size.X.Offset < 100
				and view.Gui.Documentation.Size.Y.Offset == cf.FontSize + 14
				and view.Gui.Documentation.Position == UDim2.fromOffset(view.List.Size.X.Offset - 1, 0)
				and not view.Gui.Documentation.HeaderDivider.Visible,
			"variable type details use a compact adjacent card"
		)
		assert(
			view.Rows[1].Kind.Image == "mockasset://native/editor/completion/property",
			"variable completion uses native property-kind icon"
		)
		view:Render({
			Items = {
				{
					Name = "example",
					Kind = "Function",
					Detail = "example(): number",
					Documentation = "Returns a `number` when a < b & valid.",
					CodeExample = "if true then\n\treturn 1\nend",
				},
			},
		}, 1)
		assert(
			view.Gui.Documentation.HeaderDivider.Visible and view.Gui.Documentation.CodeExampleToggle.Visible,
			"API card separates its signature and exposes supplied code examples"
		)
		assert(
			view.Gui.Documentation.CodeExample.Visible,
			"code example starts expanded and renders without executing it"
		)
		local card = view.Gui.Documentation
		assert(
			card.Size.X.Offset == 270
				and card.Description.Text == 'Returns a <font face="Code">number</font> when a &lt; b &amp; valid.'
				and card.CodeExample.Position.X.Offset == 11
				and card.CodeExampleToggle.Caption.Text == "Hide Code Example"
				and card.CodeExample.Snippet.BackgroundTransparency == 1,
			"documentation uses compact native spacing, safe inline code and a read-only example"
		)
		local expandedHeight = view.Gui.Documentation.Size.Y.Offset
		view.Gui.Documentation.CodeExampleToggle.MouseButton1Click:Fire()
		assert(
			not view.Gui.Documentation.CodeExample.Visible and view.Gui.Documentation.Size.Y.Offset < expandedHeight,
			"collapsing an example recalculates the documentation card height"
		)
		local oldRequest, oldRead, oldWrite = deps.env.request, deps.env.readfile, deps.env.writefile
		local oldHttp = service.HttpService
		local oldDocumentation = Apps.EditorApiDocumentation
		Apps.EditorApiDocumentation = newApiDocumentation()
		local cache, requests = {}, 0
		deps.env.readfile = function(path)
			return cache[path]
		end
		deps.env.writefile = function(path, text)
			cache[path] = text
		end
		deps.env.request = function(request)
			assert(request.Url:find("/refs/heads/roblox/api-docs/en-us.json", 1, true))
			requests += 1
			return { StatusCode = 200, Body = "studio-fixture" }
		end
		local docs = {
			["@roblox/globaltype/Instance.IsDescendantOf"] = {
				documentation = 'Returns <code>true</code> &amp; <strong>valid</strong>.<br><a href="https://example.test">Example</a>',
				code_sample = 'local part = Instance.new("Part")\nprint(part:IsDescendantOf(game))',
				learn_more_link = "https://create.roblox.com/docs/reference/engine/classes/Instance#IsDescendantOf",
			},
			["@luau/global/math.sqrt"] = { documentation = "Square root.", params = { { name = "x" } } },
			["@luau/global/table"] = { documentation = "Table library." },
			["@luau/global/table.freeze"] = {
				documentation = "Makes the given table read-only.",
				learn_more_link = "https://create.roblox.com/docs/reference/engine/libraries/table#freeze",
			},
		}
		service.HttpService = {
			JSONDecode = function(_, data)
				assert(data == "studio-fixture")
				return docs
			end,
		}
		local ready = 0
		Apps.EditorApiDocumentation.Load(function()
			ready += 1
		end)
		Apps.EditorApiDocumentation.Load(function()
			error("duplicate documentation load")
		end)
		assert(requests == 0, "documentation loading runs outside editor input")
		flushTasks()
		assert(requests == 1 and ready == 1 and next(cache), "download is shared and retained")
		local documented = {
			Name = "IsDescendantOf",
			Kind = "Method",
			Detail = "IsDescendantOf(ancestor: Instance): boolean",
			DocKey = "@roblox/globaltype/Instance.IsDescendantOf",
		}
		view:Render({ Items = { documented } }, 1)
		local oldClipboard, opened = deps.env.setclipboard, nil
		deps.env.setclipboard = function(url)
			opened = url
		end
		card.DocumentationLink.MouseButton1Click:Fire()
		assert(
			opened == docs[documented.DocKey].learn_more_link,
			"the rendered API link uses the enriched documentation"
		)
		deps.env.setclipboard = oldClipboard
		card.Description.Size = UDim2.fromOffset(100, 280)
		card.Description:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		assert(card.DocumentationLink.Position.Y.Offset == card.Description.Position.Y.Offset + 285)
		assert(
			card.CanvasSize.Y.Offset >= card.DocumentationLink.Position.Y.Offset + card.DocumentationLink.Size.Y.Offset
		)
		assert(
			card.Description.Text
					== 'Returns <font face="Code">true</font> &amp; <b>valid</b>.\n<font color="#00B8FF"><u>Example</u></font>'
				and card.DocumentationLink.Visible
				and card.CodeExampleToggle.Visible
				and not documented.Documentation,
			"Studio HTML, documentation link and sample reach the actual completion card without changing the suggestion"
		)
		local sqrt = language:Complete("math.sq", 8, {}).Items[1]
		local sqrtDoc = Apps.EditorApiDocumentation.Apply(sqrt)
		assert(sqrtDoc.Detail == "math.sqrt(n: number): number" and sqrtDoc.Documentation == "Square root.")
		assert(language:Hover("math.sqrt(4)", 7, {}).Detail == sqrtDoc.Detail)
		assert(language:Hover("math.sqrt(4)", 2, {}).DocGlobal == "math")
		local call = "return table.freeze({ Name = 'Prod' })"
		local tableAt = assert(call:find("table", 1, true))
		local library = language:Hover(call, tableAt, {})
		local freeze = language:Hover(call, tableAt + 6, {})
		assert(library.Documentation == "Table library." and library.Detail == "table: table")
		assert(freeze.Documentation == "Makes the given table read-only." and freeze.Url:find("#freeze", 1, true))
		assert(Apps.EditorApiDocumentation.Apply(freeze).HoverDetail == "freeze(t: { Name: string }): { Name: string }")
		local pcallSignature = Apps.EditorApiDocumentation.Signature("pcall")
		assert(pcallSignature == "pcall(f: (A...) -> R..., ...: A...): (boolean, R...)")
		assert(Apps.EditorApiDocumentation.Signature("task.spawn"):find("threadOrFunction", 1, true))
		local constructor = { Name = "new", DocGlobal = "CFrame.new", DocCallable = true }
		assert(Apps.EditorApiDocumentation.Apply(constructor).Overloads > 0)
		assert(Apps.EditorApiDocumentation.Apply(constructor, 3).Detail:find("z:", 1, true))
		local shadowed = language:Hover("local warn = {}\nwarn", 18, {})
		assert(not shadowed or shadowed.Kind ~= "Function", "a local binding shadows the builtin hover")
		Apps.EditorApiDocumentation.Load(function()
			error("fresh documentation reloaded")
		end)
		flushTasks()
		assert(requests == 1)
		local cacheFile = "dex-explorer/cache/studio-api-docs-en-us.json"
		cache[cacheFile .. ".timestamp"] = "0"
		deps.env.request = function()
			requests += 1
			return { StatusCode = 200, Body = "malformed response" }
		end
		Apps.EditorApiDocumentation = newApiDocumentation()
		Apps.EditorApiDocumentation.Load(function()
			ready += 1
		end)
		flushTasks()
		assert(
			requests == 2
				and ready == 2
				and cache[cacheFile] == "studio-fixture"
				and Apps.EditorApiDocumentation.Apply(sqrt).Documentation == "Square root.",
			"stale documentation remains available and cached when the source fails validation"
		)
		deps.env.request, deps.env.readfile, deps.env.writefile = oldRequest, oldRead, oldWrite
		service.HttpService = oldHttp
		Apps.EditorApiDocumentation = oldDocumentation
		local previousFont = cf.FontSize
		cf.FontSize = 10
		local candidates = {}
		for index = 1, 6 do
			candidates[index] = { Name = "item" .. index, Kind = "Identifier" }
		end
		view:Render({ Items = candidates }, 2)
		view.Rows[1].MouseEnter:Fire()
		assert(view.Selected == 2, "passing the pointer over a row preserves keyboard selection")
		view.Rows[1].MouseButton1Click:Fire()
		assert(view.Selected == 1, "clicking a suggestion changes selection")
		assert(
			view.List.Size.Y.Offset == 5 * 14 + 2
				and view.List.CanvasSize.Y.Offset == 6 * 14 + 2
				and view.List.ScrollBarThickness > 0,
			"the native five-row viewport scrolls at small font sizes without padding each row"
		)
		cf.FontSize = previousFont
		cf:SetText(source)
		cf:MoveCursor(column, row)
		testHost:Destroy()
	end
	local oldWidth = editor.Window.GuiElems.Content.Size
	editor.Window.GuiElems.Content.Size = UDim2.fromOffset(320, 250)
	editor.Complete()
	local popup = editor.CompletionPopup
	assert(
		popup.Size.X.Offset <= 312 and popup.Documentation.Position.Y.Offset > 0,
		"narrow floating window stacks docs below suggestions"
	)
	editor.Window.GuiElems.Content.Size = oldWidth
	editor.DismissCompletion()
	keys.LeftControl = true
	cf:SetText("safe")
	cf:MoveCursor(4, 0)
	assert(
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.D })
			and cf:GetText() == "safe"
			and editor.GetSelectionState().Selected,
		"Ctrl+D selects the current word without duplicating source"
	)
	editor.SetFontSize(22)
	editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Zero })
	assert(cf.FontSize == 14, "documented reset-zoom shortcut")
	keys.LeftAlt = true
	local before = cf:GetText()
	assert(
		editor.HandleEditorInput({ KeyCode = Enum.KeyCode.Up }) and cf:GetText() == before,
		"Ctrl+Alt cursor creation cannot move source lines"
	)
	keys.LeftAlt = false
	keys.LeftControl = false
	print(
		"PASS: reference-driven function filtering, declaration navigation, safe client object completion, signature help, documentation layout and shortcut corrections"
	)
end
