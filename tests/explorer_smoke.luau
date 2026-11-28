--!strict

Explorer.UpdateSelectionVisuals = function() end -- 3D adornments are outside this UI smoke test
Explorer.Init()
assert(Explorer.GuiElems.ToolBar.SearchFrame.Size.Y.Offset == 20, "search height")
Explorer.Expanded[nodes[workspace]] = true
Explorer.Expanded[nodes[folder]] = true
Explorer.Expanded[nodes[model]] = true
Explorer.ForceUpdate()
local tree = Explorer.GuiElems.TreeFrame
assert(tree.Position.Y.Offset == 29, "initial tree header")
assert(
	tree.Size.X.Offset == -2 and tree.Size.Y.Offset == -Explorer.HeaderHeight - 2,
	"source two-pixel scrollbar right and bottom padding"
)
local rows = {}
for _, child in ipairs(tree.ReactViewport:GetChildren()) do
	if child.Name == "Entry" then
		rows[#rows + 1] = child
	end
end
table.sort(rows, function(a, b)
	return a.Position.Y.Offset < b.Position.Y.Offset
end)
do
	local original = Explorer.ShowRightClick
	local target, touchPoint
	Explorer.ShowRightClick = function(point, node) target, touchPoint = node, point end
	local origin = tree.ReactViewport.AbsolutePosition
	local point = Vector2.new(origin.X + 20, origin.Y + Explorer.RowHeight + 2)
	Explorer.ClickSystem:OnTouchHold(rows[2], point)
	assert(target and Explorer.Selection.Map[target] and touchPoint == point, "hold opens actions at the touched row")
	local previousX, previousY = Main.Mouse.X, Main.Mouse.Y
	Main.Mouse.X, Main.Mouse.Y = -100, -100
	Explorer.Selection:Clear()
	Explorer.ClickSystem:OnTouchTap(rows[2], Vector2.new(origin.X + 82, point.Y))
	assert(Explorer.Selection.Map[target], "row tap selects the touched object with the mouse elsewhere")
	Main.Mouse.X, Main.Mouse.Y = previousX, previousY
	Explorer.ShowRightClick = original
end
assert(#rows == 5, "only the five actual visible objects receive row widgets")
assert(rows[1].Size.Y.Offset == 20, "modern row size")
assert(rows[2].Position.Y.Offset == 20, "row positioning")
Explorer.Selection:Set(nodes[model])
Explorer.Refresh()
assert(rows[3].Background.BackgroundColor3 == Settings.Theme.ListSelection, "full-width selection")
assert(
	rows[4].Background.BackgroundTransparency == 0
		and rows[4].Background.BackgroundColor3 == Settings.Theme.SelectionContext,
	"selected subtree uses its reference color independently of the window surface"
)
assert(
	rows[3].SelectionBottom.Visible and rows[4].SelectionTop.Visible,
	"parent and descendant highlights join across their color boundary"
)
assert(rows[4].SelectionBottom.Visible and rows[5].SelectionTop.Visible, "descendant rows join each other")
assert(#rows[4].Guides:GetChildren() == 3, "nested indentation guides")
Explorer.Selection:Clear()
Main.Mouse.X = tree.AbsolutePosition.X + tree.AbsoluteSize.X - 24
Main.Mouse.Y = rows[3].AbsolutePosition.Y + 10
assert(
	not Explorer.IsEmptyPoint(Main.Mouse.X, Main.Mouse.Y),
	"trailing space beyond the insert button belongs to the object row"
)
Explorer.ClickSystem.OnDown:Fire(rows[3], 1, 1)
assert(Explorer.Selection.Map[nodes[model]] and not Explorer.BoxSelecting, "clicking beyond insert selects the object")
rows[3].InputBegan:Fire({
	UserInputType = Enum.UserInputType.MouseButton1,
	Position = Vector2.new(Main.Mouse.X, Main.Mouse.Y),
})
Main.Mouse.X -= 30
service.UserInputService.InputChanged:Fire({
	UserInputType = Enum.UserInputType.MouseMovement,
	Position = Vector2.new(Main.Mouse.X, Main.Mouse.Y),
})
assert(
	Explorer.BoxSelecting and not Explorer.Dragging,
	"dragging beyond insert starts marquee selection instead of moving objects"
)
service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
assert(not Explorer.BoxSelecting, "releasing the trailing-space gesture closes marquee selection")
flushTasks()
Explorer.Selection:Set(nodes[model])
Main.Mouse.X = -100
Main.Mouse.Y = -100

Explorer.DoSearch("door")
assert(#Explorer.MatchList == 2, "only actual matches counted")
assert(tree.Position.Y.Offset == 53, "search controls reserve space")
Explorer.SelectMatches()
assert(#Explorer.Selection.List == 2, "select matches excludes ancestors")
Explorer.StepMatch(1)
assert(#Explorer.Selection.List == 2, "next match skips already selected matches when all matches are selected")
Explorer.DoSearch("is:Part Anchored=true")
assert(#Explorer.MatchList == 1 and Explorer.MatchList[1].Obj == part, "typed property search")
Explorer.DoSearch("no such name")
assert(Explorer.GuiElems.Empty.Visible, "no-results state")
Explorer.DoSearch('"unfinished')
assert(Explorer.SearchError and Explorer.GuiElems.Empty.Visible, "invalid query state")
Explorer.ClearSearch()
assert(Explorer.Query == "" and tree.Position.Y.Offset == 29, "clear restores layout")
assert(Explorer.Expanded[nodes[model]], "clear preserves expansion")
-- Clearing a search must reveal selected search results in the normal hierarchy.
Explorer.Expanded[nodes[folder]] = false
Explorer.Expanded[nodes[model]] = false
Explorer.DoSearch("door")
Explorer.Selection:Set(nodes[part])
Explorer.Selection.Piviot = nodes[part]
local originalViewNode = Explorer.ViewNode
local focusedAfterSearch
Explorer.ViewNode = function(node)
	focusedAfterSearch = node
	return originalViewNode(node)
end
Explorer.DoSearch("")
Explorer.ViewNode = originalViewNode
assert(
	Explorer.Expanded[nodes[folder]] and Explorer.Expanded[nodes[model]],
	"clear search expands selected result ancestor paths"
)
assert(focusedAfterSearch == nodes[part], "clear search scrolls selected result into view")
-- Studio does not zero the scroll position before revealing the selection.
-- ViewNode starts from the old viewport and only scrolls as far as necessary.
Explorer.DoSearch("door")
Explorer.Index = 3
local indexBeforeSearchExit
Explorer.ViewNode = function(node)
	indexBeforeSearchExit = Explorer.Index
	focusedAfterSearch = node
end
Explorer.DoSearch("")
Explorer.ViewNode = originalViewNode
assert(indexBeforeSearchExit == 3, "clear search preserves previous scroll position before reveal")
-- Multiple selections use the current/pivot item as the reveal target, like a
-- tree view's single current item inside an extended selection.
Explorer.DoSearch("door")
Explorer.Selection:SetTable({ nodes[part], nodes[second] })
Explorer.Selection.Piviot = nodes[second]
Explorer.ViewNode = function(node)
	focusedAfterSearch = node
end
Explorer.DoSearch("")
Explorer.ViewNode = originalViewNode
assert(focusedAfterSearch == nodes[second], "clear search reveals the multi-selection pivot")
Explorer.ToggleExpanded(nodes[folder], true)
assert(not Explorer.Expanded[nodes[model]], "recursive collapse")
Explorer.ToggleExpanded(nodes[folder], true)
assert(Explorer.Expanded[nodes[model]], "recursive expand")
Explorer.RowHeight = 20
Explorer.ForceUpdate()
assert(rows[2].Position.Y.Offset == 20 and rows[2].Size.Y.Offset == 20, "compact density updates recycled rows")
Explorer.OpenInsert(nodes[model], rows[3].Insert)
assert(Explorer.InsertObjectContext.Shown, "insert menu opens")
assert(Explorer.InsertObjectOpenFor == nodes[model], "insert targets hovered parent independently of selection")
Explorer.InsertObjectContext:Hide()
assert(Explorer.InsertObjectOpenFor == nil, "closing insert clears the pinned overlay")
local box = Explorer.GuiElems.SearchBar
box.Text = "door"
box:GetPropertyChangedSignal("Text"):Fire()
box.Text = "Cabin"
box:GetPropertyChangedSignal("Text"):Fire()
flushTasks()
assert(Explorer.Query == "Cabin" and #Explorer.MatchList == 1, "debounce uses latest query")
print("PASS: Explorer startup, geometry, selection, search, density, insertion and debounce smoke checks")
Explorer.ClearSearch()
Explorer.Selection:Set(nodes[model])
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(100, 100) },
	false
)
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Down },
	false
)
assert(Explorer.Selection.List[1].Obj == second, "arrow navigation follows sorted tree")
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(700, 100) },
	false
)
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Up },
	false
)
assert(Explorer.Selection.List[1].Obj == second, "unfocused Explorer does not steal arrows")
keys.LeftControl = true
keys.LeftShift = true
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.X },
	false
)
assert(service.UserInputService.Focus == Explorer.GuiElems.SearchBar, "search shortcut")
keys.LeftControl = false
keys.LeftShift = false
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape },
	true
)
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape },
	true
)
assert(not service.UserInputService.Focus and Explorer.Query == "", "second Escape clears and exits search")
Explorer.DoSearch("door")
Explorer.ToggleExpanded(nodes[folder], false)
Explorer.ForceUpdate()
assert(#Explorer.MatchList == 2, "collapsing search context retains total matches")
Explorer.SelectMatches()
assert(#Explorer.Selection.List == 2, "select all includes hidden matches")
print("PASS: keyboard focus, search shortcuts and collapsed search match selection")
assert(rows[1].Insert.Text == "", "insert does not depend on a font glyph")
assert(rows[1].Insert.StudioIcon, "insert icon geometry survives row cloning")
assert(rows[1].Insert.StudioIcon.ZIndex > rows[1].Insert.ZIndex, "icon renders above hover background")
for _, kind in ipairs({ "History", "Options", "Previous", "Next", "SelectAll", "Refresh", "Sidebar" }) do
	local b = Lib.StudioButton(tree, kind, "placeholder", UDim2.fromOffset(0, 0))
	assert(b.Text == "" and b.StudioIcon, "drawn icon: " .. kind)
end
print("PASS: drawn control icons and hover layering")

-- Recorded Studio header interactions; exercise actual popup handlers.
Explorer.ClearSearch()
local toolbar = Explorer.GuiElems.ToolBar
local history = toolbar.SearchFrame.History
local options = toolbar.Options
local popup = Explorer.GuiElems.HeaderPopup
history.Activated:Fire()
assert(popup.Visible and popup.Parent.Parent == game, "history opens")
assert(popup.Size.X.Offset == toolbar.AbsoluteSize.X - 12, "history spans panel")
assert(popup.Items:GetChildren()[1].Text == "History", "Studio history heading")
assert(popup.Items:GetChildren()[2].Text == "No searches have been made yet", "Studio empty-history copy")
assert(toolbar.SearchFrame:FindFirstChildOfClass("UIStroke").Enabled, "history focuses search")
local p = history.AbsolutePosition
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(p.X + 1, p.Y + 1) },
	false
)
assert(popup.Visible, "trigger press is not mistaken for outside dismissal")
history.Activated:Fire()
assert(not popup.Visible, "second click closes history")
history.Activated:Fire()
options.Activated:Fire()
assert(popup.Visible and #popup.Items:GetChildren() == 2, "options replaces history")
local checks = popup.Items:GetChildren()
assert(
	checks[1].Check.Image == "mockasset://native/explorer/unchecked"
		and checks[2].Check.Image == "mockasset://native/explorer/checked",
	"Studio preference default images"
)
checks[1].Activated:Fire()
assert(Settings.Explorer.IncrementNames and popup.Visible, "checkbox toggles without closing")
assert(checks[1].Check.Image == "mockasset://native/explorer/checked", "toggling swaps the original state image")
assert(Explorer.GetInsertName(workspace, "Buildings") == "Buildings1", "unique insertion name")
local sibling = Instance.new("Folder", workspace)
sibling.Name = "Buildings1"
assert(Explorer.GetInsertName(workspace, "Buildings") == "Buildings2", "name skips existing suffix")
assert(Explorer.GetInsertName(workspace, "Buildings1") == "Buildings2", "numbered names increment")
local largeSuffixParent = Instance.new("Folder")
local largeSuffix = Instance.new("Folder", largeSuffixParent)
largeSuffix.Name = "Part9007199254740992"
local nextLargeSuffix = Instance.new("Folder", largeSuffixParent)
nextLargeSuffix.Name = "Part9007199254740993"
assert(
	Explorer.GetInsertName(largeSuffixParent, largeSuffix.Name) == "Part9007199254740994",
	"name increment is exact above double precision"
)
largeSuffix.Name = "Part99999999999999999999"
assert(
	Explorer.GetInsertName(largeSuffixParent, largeSuffix.Name) == "Part100000000000000000000",
	"all-nines suffix carries without changing to scientific notation"
)
largeSuffixParent:Destroy()
sibling:Destroy()
checks[2].Activated:Fire()
assert(Settings.Explorer.ExpandHierarchy == false, "expand preference toggles")
Explorer.Expanded[nodes[folder]] = false
Explorer.ViewNode(nodes[model])
assert(not Explorer.Expanded[nodes[folder]], "disabled auto expansion preserves collapsed parent")
Settings.Explorer.ExpandHierarchy = true
Explorer.ViewNode(nodes[model])
assert(Explorer.Expanded[nodes[folder]], "enabled auto expansion reveals parent")
for _, kind in ipairs({ Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.Touch }) do
	Explorer.CloseHeaderPopup()
	history.Activated:Fire()
	service.UserInputService.InputBegan:Fire({ UserInputType = kind, Position = Vector2.new(900, 700) }, false)
	flushTasks()
	assert(not popup.Visible, "outside input closes: " .. kind)
end
Explorer.DoSearch("door")
box.Text = "door"
history.Activated:Fire()
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape },
	true
)
assert(not popup.Visible and Explorer.Query == "door", "Escape dismisses popup before clearing query")
Explorer.RememberSearch("door")
Explorer.RememberSearch("Cabin")
Explorer.RememberSearch("door")
assert(
	#Explorer.SearchHistory == 2 and Explorer.SearchHistory[1] == "door",
	"history deduplicates and orders recent queries"
)
history.Activated:Fire()
local rows = popup.Items:GetChildren()
rows[3].Activated:Fire()
assert(not popup.Visible and Explorer.Query == "Cabin", "history selection restores query and closes")
history.Activated:Fire()
box.Text = "door"
box:GetPropertyChangedSignal("Text"):Fire()
assert(not popup.Visible, "typing dismisses history")
history.Activated:Fire()
Explorer.Window.OnMinimize:Fire()
assert(not popup.Visible, "minimizing closes detached popup")
print("PASS: header popup toggle, switching, focus, Escape, outside mouse/touch, history and preference behaviors")

-- Real scrollbar implementation, including tiny viewports and zero-length drag.
local bar = Lib.ScrollBar.new()
bar.Gui.Size = UDim2.fromOffset(10, 100)
bar.TotalSpace = 100
bar.VisibleSpace = 10
bar:ScrollTo(90)
assert(bar.GuiElems.ScrollThumb.Size.Y.Offset == 24, "minimum thumb size")
assert(bar.GuiElems.ScrollThumb.Position.Y.Offset == 76, "thumb reaches exact track end")
bar:ScrollTo(1000)
assert(bar.Index == 90, "scroll clamps to final page")
bar:ScrollTo(-1000)
assert(bar.Index == 0, "scroll clamps to start")
bar.Gui.Size = UDim2.fromOffset(10, 12)
bar:Update()
assert(bar.GuiElems.ScrollThumb.Size.Y.Offset == 12, "tiny track does not overflow")
bar.GuiElems.ScrollThumb.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
service.UserInputService.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement })
assert(bar.Index == 0, "zero travel drag does not divide by zero")
service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
bar.VisibleSpace = 100
bar:Update()
assert(not bar.GuiElems.ScrollThumb.Visible, "no thumb when content fits")
local horizontal = Lib.ScrollBar.new(true)
horizontal.Gui.Size = UDim2.fromOffset(100, 10)
horizontal.VisibleSpace = 20
horizontal.TotalSpace = 100
horizontal:ScrollTo(80)
assert(horizontal.GuiElems.ScrollThumb.Position.X.Offset == 76, "horizontal users retain correct geometry")
print("PASS: real scrollbar endpoints, clamping, minimum size, tiny-track drag and horizontal geometry")

-- GUI delivery must win over global outside dismissal, even with host insets.
Explorer.CloseHeaderPopup()
options.Activated:Fire()
service.GuiService = {
	GetGuiInset = function()
		return Vector2.new(0, 58)
	end,
}
for _, kind in ipairs({ Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch }) do
	local row = popup.Items:GetChildren()[1]
	local input = { UserInputType = kind, Position = Vector2.new(999, 999) }
	service.UserInputService.InputBegan:Fire(input, false)
	row.InputBegan:Fire(input) -- engine targets the row; global handler may run first
	flushTasks()
	assert(popup.Visible, "inside GUI input survives global dismissal with host inset")
	local previous = Settings.Explorer.IncrementNames
	row.Activated:Fire()
	assert(Settings.Explorer.IncrementNames ~= previous, "protected checkbox click activates")
end
Explorer.CloseHeaderPopup()
Explorer.RememberSearch("Cabin")
history.Activated:Fire()
local historyRow = popup.Items:GetChildren()[2]
local input = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(999, 999) }
service.UserInputService.InputBegan:Fire(input, false)
historyRow.InputBegan:Fire(input)
flushTasks()
assert(popup.Visible, "history remains until activation")
historyRow.Activated:Fire()
assert(Explorer.Query == "Cabin" and not popup.Visible, "history click selects before closing")
service.GuiService = nil
print("PASS: GUI-first popup input handling across host insets and global event ordering")
Explorer.ClearSearch()
Settings.Explorer.ExpandHierarchy = false
Explorer.Expanded[nodes[folder]] = false
Explorer.Selection:Set(nodes[part])
Explorer.ForceUpdate()
local visibleParent
for _, row in ipairs(Explorer.GuiElems.TreeFrame.ReactViewport:GetChildren()) do
	if row.Name == "Entry" and row.Visible and row.Indent.EntryName.Text == "Buildings" then
		visibleParent = row
		break
	end
end
assert(
	visibleParent and visibleParent.SelectionWithin.Visible,
	"collapsed visible ancestor highlights hidden selection"
)
do
	Explorer.Selection:SetTable({ nodes[part], nodes[second] })
	local original = Explorer.IsNodeVisible
	local siblingChecks = 0
	Explorer.IsNodeVisible = function(node)
		if node == nodes[part] or node == nodes[second] then siblingChecks += 1 end
		return original(node)
	end
	Explorer.Refresh()
	Explorer.IsNodeVisible = original
	assert(siblingChecks == 1 and visibleParent.SelectionWithin.Visible, "collapsed siblings share a visibility check")
	Explorer.Selection:Set(nodes[part])
end
assert(
	visibleParent.Insert.Position.X.Offset < Explorer.GuiElems.TreeFrame.AbsoluteSize.X - 40,
	"insert sits beside short object name"
)
Settings.Explorer.ExpandHierarchy = true
print("PASS: visible-ancestor selection and name-adjacent insert position")

local search = Explorer.GuiElems.SearchBar
local function typeQuery(query)
	search.Text = query
	search.CursorPosition = #query + 1
	search:CaptureFocus()
	search:GetPropertyChangedSignal("Text"):Fire()
end
typeQuery("is:")
assert(popup.Visible and #popup.Items:GetChildren() == 4, "class suggestions")
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Down },
	true
)
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Tab },
	true
)
assert(search.Text == "is:Model" and not popup.Visible, "arrow and Tab completion")
typeQuery("Anchored=")
assert(#popup.Items:GetChildren() == 2, "boolean suggestions")
search.FocusLost:Fire(true)
assert(search.Text == "Anchored=false" and not popup.Visible, "Enter accepts suggestion")
typeQuery("is:Pa")
local row = popup.Items:GetChildren()[1]
search:ReleaseFocus()
row.Activated:Fire()
assert(search.Text == "is:Part" and not popup.Visible, "mouse accepts after textbox focus loss")
typeQuery("is:")
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape },
	true
)
assert(not popup.Visible and search.Text == "is:", "Escape dismisses without clearing")
assert(
	visibleParent.Insert.Size.X.Offset == 20 and visibleParent.Insert.BackgroundTransparency == 1,
	"source-sized insert without hover fill"
)
print("PASS: autocomplete popup filtering, keyboard, mouse focus-loss ordering and Escape")

search:ReleaseFocus()
search.Text = ""
search:GetPropertyChangedSignal("Text"):Fire()
search:CaptureFocus()
assert(popup.Visible and #popup.Items:GetChildren() == 9, "empty focus displays seven suggested filters and heading")
popup.Items:GetChildren()[1].Activated:Fire()
assert(
	search.Text == "anchored=" and popup.Visible and #popup.Items:GetChildren() == 2,
	"suggested filter transitions to boolean values"
)
typeQuery("Anch")
assert(not popup.Visible, "ordinary typing does not autocomplete")
print("PASS: empty-focus suggested filters and delimiter-only autocomplete")

search.Text = ""
search:GetPropertyChangedSignal("Text"):Fire()
assert(not popup.Visible, "deleting text during same focus does not show filters")
search:GetPropertyChangedSignal("CursorPosition"):Fire()
assert(not popup.Visible, "caret change cannot reopen filters")
search:ReleaseFocus()
search:CaptureFocus()
assert(popup.Visible, "leaving and refocusing empty search shows filters")
local first = popup.Items:GetChildren()[1]
assert(
	first.BackgroundTransparency == 1 and first.FilterIcon and not first:FindFirstChild("TextIcon"),
	"filters initially unselected with fixed icon slot"
)
local click = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(999, 999) }
service.UserInputService.InputBegan:Fire(click, false)
search.InputBegan:Fire(click)
flushTasks()
assert(popup.Visible, "initial focus click does not count as outside dismissal")
search.Text = "door"
search:GetPropertyChangedSignal("Text"):Fire()
assert(not popup.Visible, "typing dismisses filters")
search:ReleaseFocus()
search:CaptureFocus()
assert(not popup.Visible, "refocusing nonempty search does not show filters")
print("PASS: suggested filters focus lifecycle, clear suppression, first-click protection and neutral initial rows")

Explorer.ClearSearch()
Explorer.CloseHeaderPopup()
Explorer.Expanded[nodes[folder]] = true
Explorer.Expanded[nodes[model]] = true
Explorer.ForceUpdate()
Explorer.Selection:SetTable({ nodes[model], nodes[part] })
assert(#Explorer.DragRoots() == 1, "drag preserves selected descendants beneath selected parent")
assert(not Explorer.CanDrop({ nodes[model] }, nodes[part]), "reject descendant cycle")
assert(Explorer.DropNodes({ nodes[second] }, nodes[part], "Before"), "drop before sibling")
assert(nodes[model][1] == nodes[second] and second.Parent == model, "insertion preserves parent and chosen order")
Explorer.ForceUpdate()
assert(nodes[model][1] == nodes[second], "manual sibling order survives refresh")
assert(Explorer.DropNodes({ nodes[second] }, nodes[part], "After"), "drop after sibling")
assert(nodes[model][2] == nodes[second], "after position")
local frame = Explorer.GuiElems.TreeFrame
local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
Explorer.StartBoxSelect({ Position = Vector2.new(pos.X + size.X - 10, pos.Y + size.Y - 2) }, true)
assert(Explorer.BoxSelecting, "trailing space starts box selection after the drag threshold")
service.UserInputService.InputChanged:Fire({
	UserInputType = Enum.UserInputType.MouseMovement,
	Position = Vector2.new(pos.X + size.X - 2, pos.Y),
})
assert(
	Explorer.Selection.Map[nodes[part]] and Explorer.Selection.Map[nodes[second]],
	"a narrow rectangle entirely past the insert buttons selects full rows"
)
service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
assert(not Explorer.BoxSelecting, "release removes selection box")
flushTasks()
Explorer.DoSearch("Front Door")
Explorer.StartBoxSelect({ Position = Vector2.new(pos.X + 1, pos.Y + size.Y - 2) })
service.UserInputService.InputChanged:Fire({
	UserInputType = Enum.UserInputType.MouseMovement,
	Position = Vector2.new(pos.X + size.X - 2, pos.Y),
})
assert(
	#Explorer.Selection.List == 1 and Explorer.Selection.Map[nodes[part]],
	"searched box excludes ancestor context rows"
)
service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
flushTasks()
print(
	"PASS: sibling before/after drops, stable order, cycle prevention, selected roots, rectangle selection and searched match-only selection"
)

Explorer.ClearSearch()
Explorer.ForceUpdate()
Explorer.Selection:Set(nodes[second])
local targetRow
for _, row in ipairs(frame.ReactViewport:GetChildren()) do
	if row.Name == "Entry" and row.Visible and row.Indent.EntryName.Text == "Front Door" then
		targetRow = row
		break
	end
end
assert(targetRow, "drop target row visible")
Main.Mouse.X = targetRow.AbsolutePosition.X + 80
Main.Mouse.Y = targetRow.AbsolutePosition.Y + 1
Explorer.StartDrag()
local indicator = frame.ReactViewport:FindFirstChild("DropIndicator")
assert(
	indicator and indicator.Visible and indicator.Size.Y.Offset == 1,
	"row edge displays source one-pixel insertion line"
)
service.UserInputService.InputChanged:Fire({
	UserInputType = Enum.UserInputType.MouseMovement,
	Position = Vector2.new(Main.Mouse.X, targetRow.AbsolutePosition.Y + Explorer.RowHeight / 2),
})
assert(
	indicator.Size.Y.Offset == Explorer.RowHeight - 4 and indicator.BackgroundTransparency == 1,
	"row center displays source inset parent outline"
)
service.UserInputService.InputBegan:Fire(
	{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape },
	true
)
assert(not Explorer.Dragging and indicator.Destroyed and second.Parent == model, "Escape cancels drop")
flushTasks()
print("PASS: actual drag indicators switch between insertion line and parent outline; Escape cancels")

search.Text = "Anchored="
search.CursorPosition = 10
search:CaptureFocus()
search:GetPropertyChangedSignal("Text"):Fire()
popup.Items:GetChildren()[1].Activated:Fire()
search:GetPropertyChangedSignal("Text"):Fire()
search:GetPropertyChangedSignal("CursorPosition"):Fire()
flushTasks()
assert(
	search.Text == "Anchored=false" and not popup.Visible,
	"completed value remains closed through deferred text/caret events"
)
search:ReleaseFocus()
search.Text = ""
search:GetPropertyChangedSignal("Text"):Fire()
search:CaptureFocus()
assert(popup.Visible, "empty focus opens filters")
search:ReleaseFocus()
flushTasks()
assert(not popup.Visible, "focus loss dismisses filters without typing")
print("PASS: focus-loss dismissal and completion remains closed after text/caret notifications")

do
	local vertical = Lib.ScrollBar.new()
	vertical:UseLegacyStudioStyle()
	vertical.Gui.Size = UDim2.fromOffset(16, 200)
	vertical.TotalSpace = 100
	vertical.VisibleSpace = 10
	vertical:Update()
	assert(vertical.GuiElems.Button1.Visible and vertical.GuiElems.Button2.Visible, "legacy Properties arrows visible")
	assert(
		vertical.GuiElems.ScrollThumb.ZIndex > vertical.Gui.ZIndex
			and vertical.GuiElems.Button1.ZIndex > vertical.Gui.ZIndex
			and vertical.GuiElems.Button1.StudioArrow.ZIndex > vertical.GuiElems.Button1.ZIndex,
		"legacy controls paint above opaque track with global Z ordering"
	)
	assert(
		vertical.GuiElems.ScrollThumbFrame.Position.Y.Offset == 16
			and vertical.GuiElems.ScrollThumbFrame.Size.Y.Offset == -32,
		"legacy track reserves both arrow buttons"
	)
	assert(vertical.GuiElems.ScrollThumbFrame.ClipsDescendants, "thumb cannot paint into arrow buttons")
	for _, height in ipairs({ 200, 80, 300 }) do
		vertical.Gui.Size = UDim2.fromOffset(16, height)
		vertical:ScrollTo(90)
		vertical.GuiElems.ScrollThumbFrame:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		local thumb = vertical.GuiElems.ScrollThumb
		assert(
			thumb.Position.Y.Offset + thumb.Size.Y.Offset == height - 32,
			"bottom thumb tracks resized rail between arrow buttons"
		)
		vertical:ScrollTo(0)
		assert(thumb.Position.Y.Offset == 0, "top thumb stays below top arrow")
	end
	assert(
		vertical.GuiElems.ScrollThumbFrame.Position.X.Offset == 1
			and vertical.GuiElems.ScrollThumbFrame.Size.X.Offset == -2,
		"14px rail has one pixel of outer space on each side"
	)
	assert(
		vertical.GuiElems.Button1.Position.X.Offset == 1 and vertical.GuiElems.Button1.Size.X.Offset == 14,
		"arrows share the inset rail width"
	)
	assert(
		vertical.GuiElems.ScrollThumb.Size.X.Offset == 12 and vertical.GuiElems.ScrollThumb.Position.X.Offset == 1,
		"thumb has one more pixel of space inside the rail"
	)
	assert(not vertical.GuiElems.ScrollThumb:FindFirstChildOfClass("UICorner"), "legacy thumb is square")
	assert(
		vertical.GuiElems.ScrollThumb.BackgroundTransparency == 0 and vertical.Gui.BackgroundTransparency == 0,
		"legacy palette stays opaque"
	)
	vertical.GuiElems.ScrollThumb.MouseEnter:Fire()
	vertical.GuiElems.ScrollThumb.MouseLeave:Fire()
	assert(vertical.GuiElems.ScrollThumb.BackgroundTransparency == 0, "hover exit preserves legacy thumb")
	vertical.GuiElems.Button1.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	assert(vertical.GuiElems.Button1.BackgroundTransparency == 0, "arrow release preserves button background")
	local horizontal = Lib.ScrollBar.new(true)
	horizontal:UseLegacyStudioStyle()
	assert(
		horizontal.GuiElems.ScrollThumbFrame.Position.X.Offset == 16
			and horizontal.GuiElems.Button1.StudioArrow.Rotation == -90,
		"horizontal legacy arrows rotate original assets"
	)
	assert(Explorer.GuiElems.TreeFrame.ScrollBarImageTransparency == 0, "Explorer texture uses full opacity")
end
