--!strict

-- Regressions from recovered createShiftClick/useNavigationShortcuts/useDragAndDrop.
do
	local policy = Apps.ExplorerPolicy
	local savedSelection = table.clone(Explorer.Selection.List)
	local savedSorting = Settings.Explorer.Sorting
	Explorer.ClearSearch()
	local fixture = Instance.new("Folder", workspace)
	fixture.Name = "InteractionAudit"
	local first = Instance.new("Folder", fixture)
	first.Name = "A"
	local firstChild = Instance.new("Folder", first)
	firstChild.Name = "A1"
	local nested = Instance.new("Part", firstChild)
	nested.Name = "A1a"
	local last = Instance.new("Folder", fixture)
	last.Name = "B"
	local lastChild = Instance.new("Folder", last)
	lastChild.Name = "B1"
	Explorer.SyncHistoryObject(fixture)
	for _, object in ipairs({ workspace, fixture, first, firstChild, last }) do
		Explorer.Expanded[nodes[object]] = true
	end
	Explorer.ForceUpdate()
	Explorer.Selection:Set(nodes[firstChild])
	Explorer.ShiftClick(nodes[lastChild])
	assert(
		#Explorer.Selection.List == 2
			and Explorer.Selection.Map[nodes[lastChild]]
			and not Explorer.Selection.Map[nodes[nested]],
		"same-depth Shift click crosses parent boundaries while excluding deeper descendants"
	)
	Explorer.ShiftClick(nodes[firstChild])
	assert(
		#Explorer.Selection.List == 1 and Explorer.Selection.List[1] == nodes[firstChild],
		"reversing Shift click restores original anchor selection"
	)
	Explorer.Expanded[nodes[first]] = false
	Explorer.ForceUpdate()
	Explorer.Selection:Set(nodes[firstChild])
	Explorer.ShiftClick(nodes[last])
	assert(
		#Explorer.Selection.List == 2
			and Explorer.Selection.List[1] == nodes[firstChild]
			and Explorer.Selection.List[2] == nodes[last],
		"collapsed Shift anchor is retained and clicked object becomes next anchor"
	)
	Explorer.ShiftClick(nodes[lastChild])
	assert(
		Explorer.Selection.Map[nodes[firstChild]] and Explorer.Selection.Map[nodes[lastChild]],
		"next Shift gesture uses renewed anchor"
	)
	Explorer.Selection:Clear()
	Explorer.ShiftClick(nodes[last])
	assert(
		#Explorer.Selection.List == 1 and Explorer.Selection.List[1] == nodes[last],
		"Shift clicking from empty selection selects target"
	)

	local root = { Obj = game }
	local rootA = { Parent = root, Obj = { ClassName = "Workspace" } }
	local childA = { Parent = rootA, Obj = { ClassName = "Folder" } }
	local deepA = { Parent = childA, Obj = { ClassName = "Part" } }
	local rootB = { Parent = root, Obj = { ClassName = "Lighting" } }
	local childB = { Parent = rootB, Obj = { ClassName = "Folder" } }
	rootA[1] = childA
	childA[1] = deepA
	rootB[1] = childB
	local order = { rootA, childA, deepA, rootB, childB }
	assert(
		policy.Endpoint(order, false) == rootA and policy.Endpoint(order, true) == rootB,
		"Home/End select root children rather than deepest final descendant"
	)
	assert(policy.Endpoint(order, true, { [deepA] = true }) == deepA, "search End chooses final actual match")
	assert(
		policy.PageStep(order, { rootA, rootB }, 2) == deepA,
		"PageDown starts from earliest selected index in its direction"
	)
	assert(
		policy.PageStep(order, { rootA, rootB }, -2) == childA,
		"PageUp starts from latest selected index in its direction"
	)
	assert(
		policy.PageStep(order, { rootA }, 2, { [childB] = true }) == childB,
		"page navigation skips nonmatching search context"
	)
	assert(policy.PageStep(order, order, 2) == nil, "page stepping with every row selected keeps selection unchanged")
	local node, mode, parent = policy.DropTarget(order, 3, 0, 50, { [childA] = true }, 12)
	assert(
		node == childA and mode == "After" and parent == childA,
		"top boundary of expanded parent's first child drops into expanded parent"
	)
	node, mode, parent = policy.DropTarget(order, 3, 19, 10, {}, 12)
	assert(node == deepA and parent == rootA, "left edge of completed subtree outdents into grandparent")
	node, mode, parent = policy.DropTarget(order, 3, 5, 50, {}, 12)
	assert(node == deepA and mode == "Inside" and parent == deepA, "five pixels from edge remains ordinary row drop")
	assert(policy.DropTarget(order, 1, 0, 0, {}, 12) == nil, "above first row has no valid drop target")

	Explorer.Expanded[nodes[first]] = true
	Explorer.ForceUpdate()
	local moving = Instance.new("Part", fixture)
	moving.Name = "Mover"
	Explorer.SyncHistoryObject(moving)
	assert(
		Explorer.DropNodes({ nodes[moving] }, nodes[first], "After", nodes[first]),
		"expanded-parent boundary moves real object"
	)
	assert(
		moving.Parent == first and nodes[first][1] == nodes[moving],
		"expanded-parent boundary inserts before its first child"
	)
	assert(Apps.History.Undo() and moving.Parent == fixture, "boundary move remains reversible")
	assert(
		Explorer.DropNodes({ nodes[moving] }, nodes[nested], "After", nodes[fixture]),
		"outdent boundary move accepted"
	)
	assert(
		moving.Parent == fixture
			and table.find(nodes[fixture], nodes[moving]) == table.find(nodes[fixture], nodes[first]) + 1,
		"outdent reorder anchors below direct child containing preceding descendant"
	)
	assert(Apps.History.Undo() and moving.Parent == fixture, "outdent order and parenting undo together")

	local search = Explorer.GuiElems.SearchBar
	service.UserInputService.Focus = nil
	service.UserInputService.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(100, 100) },
		false
	)
	Explorer.Selection:Set(nodes[workspace])
	Explorer.KeyboardFocusNode = nil
	service.UserInputService.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Up },
		false
	)
	assert(
		#Explorer.Selection.List == 0 and service.UserInputService:GetFocusedTextBox() == search,
		"Up from first row focuses search and clears tree selection"
	)
	assert(
		Explorer.FocusFirstFromSearch()
			and Explorer.Selection.List[1] == nodes[workspace]
			and not service.UserInputService:GetFocusedTextBox(),
		"Down handoff from search selects first visible row and releases text focus"
	)
	local before = Explorer.Selection.List[1]
	keys.LeftControl = true
	service.UserInputService.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Down },
		false
	)
	keys.LeftControl = false
	assert(Explorer.Selection.List[1] == before, "Ctrl+arrow leaves tree selection unchanged")

	local oldDelay = task.delay
	local scheduled = {}
	task.delay = function(delay, callback)
		if delay == 0.5 or delay == 0.02 then
			scheduled[#scheduled + 1] = { delay, callback }
		else
			return oldDelay(delay, callback)
		end
	end
	service.UserInputService.InputEnded:Fire({
		UserInputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Down,
	})
	Explorer.Selection:Set(nodes[workspace])
	Explorer.KeyboardFocusNode = nil
	keys.Down = true
	service.UserInputService.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Down },
		false
	)
	local afterPress = Explorer.Selection.List[1]
	assert(#scheduled == 1 and scheduled[1][1] == 0.5, "arrow hold schedules source initial delay")
	scheduled[1][2]()
	assert(
		Explorer.Selection.List[1] ~= afterPress and #scheduled == 2 and scheduled[2][1] == 0.02,
		"held arrow repeats actual navigation with source repeat interval"
	)
	service.UserInputService.InputEnded:Fire({
		UserInputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Down,
	})
	local afterRelease = Explorer.Selection.List[1]
	scheduled[2][2]()
	assert(
		Explorer.Selection.List[1] == afterRelease and #scheduled == 2,
		"key release invalidates pending repeat callback"
	)
	local function pendingHold()
		service.UserInputService.Focus = nil
		service.UserInputService.InputBegan:Fire(
			{ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector2.new(100, 100) },
			false
		)
		Explorer.Selection:Set(nodes[workspace])
		Explorer.KeyboardFocusNode = nil
		service.UserInputService.InputBegan:Fire(
			{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Down },
			false
		)
		return scheduled[#scheduled][2], Explorer.Selection.List[1], #scheduled
	end
	local pending, current, count = pendingHold()
	search:CaptureFocus()
	pending()
	assert(Explorer.Selection.List[1] == current and #scheduled == count, "text focus stops a held navigation key")
	search:ReleaseFocus()
	pending, current, count = pendingHold()
	Explorer.Window.OnDeactivate:Fire()
	pending()
	assert(
		Explorer.Selection.List[1] == current and #scheduled == count,
		"window deactivation cancels pending arrow repeat"
	)
	pending, current, count = pendingHold()
	Main.Alive = false
	pending()
	Main.Alive = true
	assert(Explorer.Selection.List[1] == current and #scheduled == count, "shutdown guard stops pending arrow repeat")
	keys.Down = false
	task.delay = oldDelay
	service.UserInputService.InputEnded:Fire({
		UserInputType = Enum.UserInputType.Keyboard,
		KeyCode = Enum.KeyCode.Down,
	})
	Explorer.Selection:SetTable({ nodes[first], nodes[last] })
	service.UserInputService.InputBegan:Fire(
		{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F2 },
		false
	)
	local rename = Explorer.TreeRenderer.Layer:FindFirstChild("RenameBox")
	assert(not rename.Visible, "F2 does not rename an arbitrary member of a multiselection")
	Explorer.SetRenamingNode(nodes[lastChild])
	local renameIndex = Explorer.Index
	Explorer.Index = renameIndex + 1
	Explorer.Refresh()
	local renamedRow
	for _, row in ipairs(Explorer.TreeRenderer.Layer:GetChildren()) do
		if row.Name == "Entry" and row.Visible and row.Indent.EntryName.Text == lastChild.Name then
			renamedRow = row
			break
		end
	end
	assert(
		renamedRow and rename.Visible and rename.Position.Y.Offset == renamedRow.Position.Y.Offset,
		"rename overlay follows the retained row's new position in the same scroll repaint"
	)
	Explorer.CancelRename()
	Explorer.Index = renameIndex
	Explorer.Refresh()

	local pasteTarget = Instance.new("Folder", fixture)
	pasteTarget.Name = "PasteTarget"
	Explorer.SyncHistoryObject(pasteTarget)
	Explorer.Selection:SetTable({ nodes[first], nodes[firstChild] })
	Explorer.RightClickContext.Registered.COPY.OnClick()
	Explorer.Selection:Set(nodes[pasteTarget])
	Explorer.RightClickContext.Registered.PASTE.OnClick()
	assert(
		#pasteTarget:GetChildren() == 1 and #pasteTarget:GetChildren()[1]:GetChildren() == 1,
		"copy selected ancestor and descendant clones subtree only once"
	)

	local workspaceCount = #workspace:GetChildren()
	Explorer.Selection:SetTable({})
	Explorer.RightClickContext.Registered.PASTE_WORKSPACE.OnClick()
	assert(#workspace:GetChildren() == workspaceCount + 1, "Paste with no selection adds to Workspace")
	assert(#pasteTarget:GetChildren() == 1, "Paste leaves the previous target alone")
	Apps.History.Undo()
	assert(#workspace:GetChildren() == workspaceCount, "Undo removes the Workspace paste")

	local oldMouseX, oldMouseY = Main.Mouse.X, Main.Mouse.Y

	local oldRunService = service.RunService
	local frame = Explorer.GuiElems.TreeFrame
	local oldWindow, oldCanvas = frame.AbsoluteWindowSize, frame.CanvasSize
	local oldPosition = frame.CanvasPosition
	frame.AbsoluteWindowSize = Vector2.new(frame.AbsoluteSize.X - 6, 100)
	Explorer.UpdateView()
	local offscreen
	for index = 1, 35 do
		offscreen = Instance.new("Folder", fixture)
		offscreen.Name = string.format("Z%02d", index)
		Explorer.SyncHistoryObject(offscreen)
	end
	Explorer.ForceUpdate()
	local originalUpdate, updates = Explorer.Update, 0
	Explorer.Update = function()
		updates += 1
		return originalUpdate()
	end
	frame.CanvasPosition = Vector2.new(0, 0)
	Explorer.Index = 0
	Explorer.Refresh()
	local retainedRow = Explorer.TreeRenderer:NewRow(2)
	local retainedLabel = retainedRow.Indent.EntryName
	local retainedText = retainedLabel.Text
	frame.CanvasPosition = Vector2.new(0, 20)
	Explorer.Index = 1
	Explorer.Refresh()
	assert(
		Explorer.TreeRenderer:NewRow(1) == retainedRow
			and retainedRow.Indent.EntryName == retainedLabel
			and retainedLabel.Text == retainedText,
		"actual Explorer scroll retains each still-visible object's label instead of rewriting all viewport text"
	)
	frame.CanvasPosition = Vector2.new(0, 0)
	Explorer.Index = 0
	Explorer.Refresh()
	Explorer.Selection:Set(nodes[offscreen])
	assert(
		Explorer.Index > 0 and updates == 0,
		"external selection reveals offscreen row from cached index without rebuilding the tree"
	)
	local revealIndex = Explorer.Index
	Explorer.BoxSelecting = true
	Explorer.Selection:Set(nodes[first])
	Explorer.BoxSelecting = false
	assert(Explorer.Index == revealIndex and updates == 0, "marquee selection does not feed back into automatic reveal")
	Explorer.Update = originalUpdate
	frame.CanvasSize = UDim2.fromOffset(1000, 20000)
	frame.CanvasPosition = Vector2.new(0, 200)
	local render = Apps.Signal.new()
	service.RunService = { RenderStepped = render }
	local position = frame.AbsolutePosition
	local px, py = position.X + 50, position.Y + 50
	Explorer.StartBoxSelect({ Position = Vector2.new(px, py) }, true)
	service.UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector2.new(px, position.Y + 99),
	})
	render:Fire(0.1)
	assert(frame.CanvasPosition.Y == 200, "drag inside last viewport pixels does not autoscroll")
	service.UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector2.new(px, position.Y + 105),
	})
	render:Fire(0.1)
	assert(
		frame.CanvasPosition.Y > 200 and frame.CanvasPosition.Y < 204,
		"box selection outside edge scrolls immediately and retains fractional progress"
	)
	service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	Explorer.Selection:Set(nodes[firstChild])
	Main.Mouse.X = px
	Main.Mouse.Y = py
	frame.CanvasPosition = Vector2.new(0, 200)
	Explorer.StartDrag()
	service.UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector2.new(px, position.Y + 105),
	})
	render:Fire(0.1)
	render:Fire(0.1)
	render:Fire(0.1)
	assert(frame.CanvasPosition.Y == 200, "object drag waits before outside-edge scrolling")
	render:Fire(0.1)
	render:Fire(0.1)
	assert(frame.CanvasPosition.Y > 200, "object drag begins scrolling after dwell")
	local atBottom = frame.CanvasPosition.Y
	service.UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector2.new(px, position.Y - 5),
	})
	render:Fire(0.1)
	render:Fire(0.1)
	assert(frame.CanvasPosition.Y == atBottom, "reversing edge direction resets dwell instead of carrying acceleration")
	service.UserInputService.InputChanged:Fire({
		UserInputType = Enum.UserInputType.MouseMovement,
		Position = Vector2.new(px, position.Y + 140),
	})
	for _ = 1, 6 do
		render:Fire(0.1)
	end
	assert(frame.CanvasPosition.Y > atBottom, "object drag keeps scrolling beyond the narrow outside boundary")
	for _ = 1, 35 do
		render:Fire(0.1)
	end
	local beforeSlowFrame = frame.CanvasPosition.Y
	render:Fire(0.25)
	assert(
		math.abs(frame.CanvasPosition.Y - beforeSlowFrame - 375) < 0.001,
		"configured Studio 1500 pixel/sec peak uses full elapsed time even on slow frames"
	)
	service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	Explorer.StartBoxSelect({ Position = Vector2.new(position.X + frame.AbsoluteWindowSize.X + 2, py) }, true)
	assert(not Explorer.BoxSelecting, "native scrollbar gutter does not begin marquee selection")
	frame.AbsoluteWindowSize, frame.CanvasSize, frame.CanvasPosition = oldWindow, oldCanvas, oldPosition
	Main.Mouse.X, Main.Mouse.Y = oldMouseX, oldMouseY
	service.RunService = oldRunService
	render:Destroy()
	flushTasks()

	local clientMain = Instance.new("LocalScript", firstChild)
	clientMain.Name = "ClientMain"
	Explorer.SyncHistoryObject(clientMain)
	Explorer.SetExpanded(nodes[first], true, false)
	Explorer.SetExpanded(nodes[firstChild], true, false)
	Explorer.ForceUpdate()
	Explorer.ViewNode(nodes[clientMain])
	local function findRow(name)
		for _, entry in Explorer.TreeRenderer.Layer:GetChildren() do
			if entry.Name == "Entry" and entry.Indent.EntryName.Text == name then
				return entry
			end
		end
	end
	local clientRow = assert(findRow(clientMain.Name))
	local sys = Explorer.ClickSystem
	local oldView, oldRenameSetting = Apps.ScriptViewer.ViewScript, Settings.Explorer.ClickToRename
	local opened = {}
	Apps.ScriptViewer.ViewScript = function(object)
		opened[#opened + 1] = object
	end
	Settings.Explorer.ClickToRename = false
	local function press(row, combo, button)
		local label = row.Indent.EntryName
		Main.Mouse.X, Main.Mouse.Y = label.AbsolutePosition.X + 1, label.AbsolutePosition.Y + 1
		sys.OnDown:Fire(row, combo, button or 1)
	end
	local function click(row, combo)
		press(row, combo)
		sys.OnRelease:Fire(row, combo, 1)
	end
	Explorer.Window.OnDeactivate:Fire()
	Explorer.Selection:Clear()
	Explorer.SetExpanded(nodes[firstChild], false, false)
	Explorer.Update(true)
	assert(clientRow.Indent.EntryName.Text == clientMain.Name, "display is still on the previous tree projection")
	press(clientRow, 1)
	assert(Explorer.Selection.List[1] == nodes[clientMain], "a press selects the rendered object during a tree update")
	sys.OnRelease:Fire(clientRow, 1, 1)
	assert(#opened == 0, "recycling between press and release cannot open either object")
	Explorer.SetExpanded(nodes[firstChild], true, false)
	Explorer.ForceUpdate()
	Explorer.ViewNode(nodes[clientMain])
	clientRow = assert(findRow(clientMain.Name))
	click(assert(findRow(firstChild.Name)), 1)
	click(clientRow, 2)
	assert(#opened == 0, "clicks on different objects never form a double-click")
	press(clientRow, 1)
	assert(#opened == 0, "the editor opens only after the second click completes")
	sys.OnRelease:Fire(clientRow, 1, 1)
	assert(#opened == 1 and opened[1] == clientMain and Explorer.Selection.List[1] == nodes[clientMain])
	local wrongRow = assert(findRow(firstChild.Name))
	local oldHit = Lib.CheckMouseInGui
	Lib.CheckMouseInGui = function(gui)
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return Main.Mouse.X >= p.X and Main.Mouse.X < p.X + s.X and Main.Mouse.Y >= p.Y and Main.Mouse.Y < p.Y + s.Y
	end
	local label = clientRow.Indent.EntryName
	Main.Mouse.X, Main.Mouse.Y = label.AbsolutePosition.X + 1, label.AbsolutePosition.Y + 1
	Explorer.Selection:Clear()
	local count = 0
	local pressListener = sys.OnDown:Connect(function()
		count += 1
	end)
	for _ = 1, 2 do
		wrongRow.MouseButton1Down:Fire(Main.Mouse.X, Main.Mouse.Y)
		clientRow.MouseButton1Down:Fire(Main.Mouse.X, Main.Mouse.Y)
		assert(Explorer.Selection.List[1] == nodes[clientMain], "native event can name a different row than the pointer")
		service.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	end
	assert(count == 2 and #opened == 2 and opened[2] == clientMain, "one routed press per physical click opens the script once")
	pressListener:Disconnect()
	Lib.CheckMouseInGui = oldHit
	Explorer.Window.OnDeactivate:Fire()
	Apps.ScriptViewer.ViewScript, Settings.Explorer.ClickToRename = oldView, oldRenameSetting
	Main.Mouse.X, Main.Mouse.Y = oldMouseX, oldMouseY
	print("PASS: Explorer click targets follow displayed objects through refresh and double-click opens the exact script")

	local hidden = Instance.new("Frame")
	hidden.Visible = false
	assert(policy.IsEnabled(hidden), "invisible GuiObject remains bright outside StarterGui development visibility")
	local starter = Instance.new("StarterGui")
	starter.ShowDevelopmentGui = false
	hidden.Parent = starter
	assert(not policy.IsEnabled(hidden), "StarterGui development setting still dims hidden subtree")
	starter.ShowDevelopmentGui = true
	assert(policy.IsEnabled(hidden), "development visibility restores invisible Frame brightness")
	starter:Destroy()
	fixture:Destroy()
	Explorer.SyncHistoryObject(fixture)
	Settings.Explorer.Sorting = savedSorting
	Explorer.Selection:SetTable(savedSelection)
	Explorer.KeyboardFocusNode = nil
	Explorer.ForceUpdate()
	print(
		"PASS: anchored Shift selection, root/search endpoints, boundary drop/reorder/history, search focus, bounded arrow hold, single rename, subtree copy, live edge controller and GUI brightness policy"
	)
end
