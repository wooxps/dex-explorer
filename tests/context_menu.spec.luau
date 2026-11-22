--!strict

do
	local context = Explorer.RightClickContext
	local oldClass, oldHidden = API.Classes.Folder, Settings.Explorer.HiddenServices
	API.Classes.Folder = { Name = "Folder", Tags = { Service = true } }
	Settings.Explorer.HiddenServices = {}
	local root = Instance.new("Folder", game)
	root.Name = "ContextService"
	local child = Instance.new("Folder", root)
	child.Name = "ContextChild"
	local outside = Instance.new("Folder", workspace)
	outside.Name = "ContextOutside"
	Explorer.SyncHistoryObject(root)
	Explorer.SyncHistoryObject(outside)
	Explorer.ClearSearch()
	Explorer.Expanded[nodes[root]] = true
	Explorer.ForceUpdate()
	local function menu(selected)
		Explorer.Selection:SetTable(selected)
		Explorer.ShowRightClick(Vector2.new(12, 12))
		local names = {}
		local function collect(items)
			for index, item in ipairs(items) do
				if item.Divider then
					assert(
						index > 1 and index < #items and not items[index - 1].Divider,
						"menu separators belong between action groups"
					)
				else
					assert(not names[item.Name], "an action appears only once")
					names[item.Name] = item
					if item.Submenu then
						collect(item.Submenu)
					end
				end
			end
		end
		collect(context.Items)
		context:Hide()
		return names
	end

	-- One state-aware firing action, with one hook across repeated toggles.
	local savedHook = deps.env.hookmetamethod
	local hookCount = 0
	deps.env.hookmetamethod = function(_, _, callback)
		hookCount += 1
		return function()
			return "forwarded"
		end
	end
	local remote = Instance.new("RemoteEvent", root)
	local bindable = Instance.new("BindableEvent", root)
	Explorer.SyncHistoryObject(remote)
	Explorer.SyncHistoryObject(bindable)
	local actions = menu({ nodes[remote] })
	assert(actions["Block From Firing"] and not actions["Unblock From Firing"])
	context.Registered.BLOCK_REMOTE.OnClick()
	actions = menu({ nodes[remote] })
	assert(actions["Unblock From Firing"] and not actions["Block From Firing"])
	context.Registered.BLOCK_REMOTE.OnClick()
	actions = menu({ nodes[remote] })
	assert(actions["Block From Firing"])
	context.Registered.BLOCK_REMOTE.OnClick()
	actions = menu({ nodes[remote], nodes[bindable] })
	assert(actions["Block From Firing"], "mixed selection offers blocking")
	context.Registered.BLOCK_REMOTE.OnClick()
	actions = menu({ nodes[remote], nodes[bindable] })
	assert(actions["Unblock From Firing"])
	context.Registered.BLOCK_REMOTE.OnClick()
	assert(hookCount == 1, "toggles and new targets reuse a single hook")
	deps.env.hookmetamethod = savedHook
	-- Real player quick action can be stopped from any Explorer context menu.
	local camera = Instance.new("Camera", workspace)
	local oldCamera, oldCharacter = workspace.CurrentCamera, deps.plr.Character
	local viewPart = Instance.new("Part", workspace)
	local localCharacter = Instance.new("Model", workspace)
	local localHumanoid = Instance.new("Humanoid", localCharacter)
	deps.plr.Character = localCharacter
	workspace.CurrentCamera = camera
	camera.CameraSubject = localHumanoid
	local oldPlayerClass = API.Classes.Player
	API.Classes.Player = { Name = "Player", Superclass = API.Classes.Instance, Tags = {} }
	local player = Instance.new("Player", root)
	player.Character = Instance.new("Model", workspace)
	local targetHumanoid = Instance.new("Humanoid", player.Character)
	Explorer.SyncHistoryObject(player)
	Explorer.Selection:Set(nodes[player])
	context.Registered.VIEW_PLAYER.OnClick()
	assert(
		camera.CameraSubject == targetHumanoid and Explorer.IsViewing(),
		"View Player follows the selected character"
	)
	local playerMenu = menu({ nodes[player] })
	assert(
		playerMenu["Stop Viewing Player"] and not playerMenu["View Player"],
		"viewed player action changes its label without a duplicate stop entry"
	)
	playerMenu["Stop Viewing Player"].OnClick()
	assert(
		camera.CameraSubject == localHumanoid and not Explorer.IsViewing(),
		"normal click on the renamed player action stops viewing"
	)
	playerMenu = menu({ nodes[player] })
	assert(
		playerMenu["View Player"] and not playerMenu["Stop Viewing Player"],
		"player action returns to View Player after stopping"
	)
	playerMenu["View Player"].OnClick()
	local another = Instance.new("Player", root)
	another.Character = Instance.new("Model", workspace)
	Explorer.SyncHistoryObject(another)
	local otherMenu = menu({ nodes[another] })
	assert(
		otherMenu["View Player"] and otherMenu["Stop Viewing Player"],
		"another player still offers View Player and the general stop action"
	)
	playerMenu = menu({ nodes[player] })
	assert(
		playerMenu["Stop Viewing Player"] and not playerMenu["View Player"],
		"returning to the viewed player restores the contextual toggle"
	)
	another.Character:Destroy()
	another.Parent = nil
	Explorer.SyncHistoryObject(another)

	assert(
		menu({})["Stop Viewing Player"] and menu({ nodes[child] })["Stop Viewing Player"],
		"stop is reachable from blank and object menus"
	)
	context.Registered.STOP_VIEWING.OnClick()
	assert(
		camera.CameraSubject == localHumanoid and not Explorer.IsViewing(),
		"stop restores the original camera subject"
	)
	assert(not menu({})["Stop Viewing Player"], "stop action disappears when no view is active")
	Explorer.SyncHistoryObject(viewPart)
	local partNode = nodes[viewPart]
	local oldPartClass = API.Classes.Part
	API.Classes.Part = { Name = "Part", Superclass = { Name = "BasePart", Tags = {} }, Tags = {} }
	menu({ partNode })["View Object"].OnClick()
	assert(camera.CameraSubject == viewPart and Explorer.IsViewing(viewPart))
	local objectMenu = menu({ partNode })
	assert(objectMenu["Stop Viewing Object"] and not objectMenu["View Object"])
	assert(menu({})["Stop Viewing Object"], "the general stop action names the active object view")
	menu({ partNode })["Stop Viewing Object"].OnClick()
	assert(camera.CameraSubject == localHumanoid and not Explorer.IsViewing())
	assert(menu({ partNode })["View Object"])
	API.Classes.Part = oldPartClass
	assert(not Explorer.StartViewing(child), "non-camera subjects cannot start a view")
	Explorer.StartViewing(player.Character)
	Explorer.StartViewing(viewPart)
	Explorer.StopViewing()
	assert(camera.CameraSubject == localHumanoid, "switching targets retains the original subject")
	Explorer.StartViewing(player.Character)
	camera.CameraSubject = viewPart
	Explorer.StopViewing()
	assert(camera.CameraSubject == viewPart, "stop does not overwrite a camera changed by the game")
	camera.CameraSubject = localHumanoid
	Explorer.StartViewing(player.Character)
	localHumanoid.Parent = nil
	local replacement = Instance.new("Humanoid", localCharacter)
	Explorer.StopViewing()
	assert(camera.CameraSubject == replacement, "stop falls back to the current local character after respawn")
	Explorer.StartViewing(player.Character)
	targetHumanoid.Parent = nil
	targetHumanoid.AncestryChanged:Fire()
	assert(
		camera.CameraSubject == replacement and not Explorer.IsViewing(),
		"removed target automatically restores the camera"
	)
	context.Registered.STOP_VIEWING.OnClick()
	camera.CameraSubject = nil
	Explorer.StartViewing(player.Character)
	Explorer.StopViewing()
	assert(camera.CameraSubject == nil, "an originally nil camera subject is preserved")
	camera.CameraSubject = replacement
	Explorer.StartViewing(player.Character)
	local cleanup = table.find(Main.CleanupCallbacks, Explorer.StopViewing)
	assert(cleanup, "viewing is owned by Dex shutdown")
	Main.CleanupCallbacks[cleanup]()
	assert(
		camera.CameraSubject == replacement and not Explorer.IsViewing(),
		"shutdown restores the camera and stops viewing"
	)
	viewPart:Destroy()
	player.Parent = nil
	player.Character:Destroy()
	localCharacter:Destroy()
	camera:Destroy()
	workspace.CurrentCamera = oldCamera
	deps.plr.Character = oldCharacter
	API.Classes.Player = oldPlayerClass
	Explorer.SyncHistoryObject(player)
	local names = menu({ nodes[root] })
	for _, name in ipairs({
		"Cut",
		"Copy",
		"Duplicate",
		"Delete",
		"Group as Model",
		"Group as Folder",
		"Ungroup",
		"Select Parent(s)",
	}) do
		assert(not names[name], "pure service selection omits non-service action " .. name)
	end
	assert(
		names["Show Services..."] and names["Hide Service in Explorer"] and names["Select Children"],
		"service actions remain available"
	)
	names = menu({})
	assert(
		names["Show Services..."] and not names["Paste Into"] and not names["Rename"] and not names["Save to File..."],
		"blank menu omits actions requiring selection"
	)
	names = menu({ nodes[child] })
	Explorer.Selection:Set(nodes[child])
	context.Registered.COPY.OnClick()
	names = menu({ nodes[child] })
	assert(
		names.Copy and names.Cut and names["Paste Into"] and not names["Paste Into"].Disabled and not names["Hide Service in Explorer"] and not names["Show Services..."],
		"ordinary selection gets editable actions"
	)
	local layout = {}
	for _, item in ipairs(context.Items) do
		table.insert(layout, if item.Divider then "|" else item.Name)
	end
	local groups = table.concat(layout, ",")
	assert(groups:find("Paste Into,Paste into at Original Location,Duplicate,Delete,Rename,|,Group as Model,Group as Folder,Ungroup,Insert,Hierarchy,|", 1, true), groups)
	assert(groups:find(if deps.env.setclipboard then "|,Paste Into," else "Copy,Paste Into,", 1, true), groups)
	assert(names.Insert.Submenu[2].Name == "Insert Object...")
	assert(names.Insert.Submenu[3].Name == "Insert from File...")
	assert(names["Save / Export"].Submenu[2].Name == "Export as glTF")
	assert(not names["Load from CSV..."] and not names["Save as CSV..."])
	local l10n = Instance.new("LocalizationTable", workspace)
	Explorer.SyncHistoryObject(l10n)
	local tableMenu = menu({nodes[l10n]})
	assert(tableMenu["Load from CSV..."] and tableMenu["Save as CSV..."])
	assert(not menu({nodes[l10n], nodes[child]})["Load from CSV..."])
	l10n:Destroy()
	Explorer.SyncHistoryObject(l10n)

	assert(names.Hierarchy.Submenu[1].Name == "Select Parent(s)")
	assert(names["Save / Export"].Submenu[1].Name == "Save to File...")
	names = menu({ nodes[root], nodes[child], nodes[outside] })
	assert(
		names.Copy and names.Cut and names["Show Services..."] and names["Hide Service in Explorer"],
		"mixed selection follows any-service/any-nonservice action expectations"
	)
	local roots = Explorer.EditableRoots()
	assert(
		#roots == 2 and table.find(roots, nodes[child]) and table.find(roots, nodes[outside]),
		"selected service does not swallow editable child roots"
	)
	for _, key in ipairs({ "CUT", "COPY", "DUPLICATE", "DELETE", "GROUP", "GROUP_FOLDER", "UNGROUP" }) do
		Explorer.Selection:Set(nodes[root])
		context.Registered[key].OnClick()
		assert(
			root.Parent == game and #Explorer.Selection.List == 1 and Explorer.Selection.Map[nodes[root]],
			"service-only keyboard command leaves service and selection intact: " .. key
		)
	end
	Explorer.Selection:SetTable({ nodes[root], nodes[child], nodes[outside] })
	context.Registered.DELETE.OnClick()
	assert(
		root.Parent == game and child.Parent == nil and outside.Parent == nil,
		"mixed delete edits only non-services"
	)
	assert(Apps.History.Undo(), "mixed edit is undoable")
	assert(
		root.Parent == game and child.Parent == root and outside.Parent == workspace,
		"undo preserves service parent and restores editable children"
	)
	Explorer.Selection:SetTable({ nodes[root], nodes[child], nodes[outside] })
	Explorer.HideSelectedServices()
	assert(
		not Apps.ServiceVisibility.IsVisible(root)
			and #Explorer.Selection.List == 1
			and Explorer.Selection.Map[nodes[outside]],
		"mixed hide removes only hidden service ancestry from selection"
	)
	local savedClipboard = deps.env.setclipboard
	local copied
	deps.env.setclipboard = function(value)
		copied = value
	end
	Explorer.Selection:Set(nodes[outside])
	outside.UniqueId = "00000000-0000-0000-0000-000000000000"
	names = menu({ nodes[outside] })
	assert(#names["Copy As"].Submenu == 2 and names["Copy as JSON"] and not names["Copy Unique ID"])
	context.Registered.COPY_UNIQUE_ID.OnClick()
	assert(copied == nil, "unavailable IDs are not copied by direct command")
	outside.UniqueId = "12345678-abcd-4321-9876-123456789abc"
	names = menu({ nodes[outside] })
	assert(#names["Copy As"].Submenu == 3, "readable nonzero ID exposes guarded copy")
	context:Show(12, 12)
	context:OpenSubmenu(names["Copy As"])
	local childMenu = context.ChildMenu
	assert(
		childMenu.Shown and context.Shown and childMenu.Items[2].Name == "Copy Unique ID",
		"Copy As opens nested readable actions"
	)
	childMenu.Items[2].OnClick()
	assert(
		not context.Shown and not childMenu.Shown and copied == outside.UniqueId,
		"submenu action executes and closes full chain"
	)
	context.Registered.COPY_UNIQUE_ID.OnClick()
	assert(copied == outside.UniqueId, "copy uses actual unique ID")
	do
		child.UniqueId = "abcdef01-abcd-4321-9876-123456789abc"
		assert(menu({nodes[child], nodes[outside]})["Copy Unique ID"])
		context.Registered.COPY_UNIQUE_ID.OnClick()
		assert(copied == child.UniqueId .. "\n" .. outside.UniqueId)
		child.UniqueId = nil
		deps.env.setclipboard = nil
		menu({nodes[outside]})
		local seen = false
		for i, item in ipairs(context.Items) do
			if item.Name == "Paste Into" then seen = context.Items[i-1].Name == "Copy" end
		end
		assert(seen, "Copy directly precedes Paste Into without clipboard support")
		deps.env.setclipboard = function(value) copied = value end
		local scriptObject = Instance.new("LocalScript", workspace)
		Explorer.SyncHistoryObject(scriptObject)
		local oldView, oldCheck, oldDecompile = Apps.ScriptViewer.ViewScript, deps.env.isViableDecompileScript, deps.env.decompile
		local opened
		Apps.ScriptViewer.ViewScript = function(object) opened = object end
		deps.env.isViableDecompileScript = function(object) return object == scriptObject end
		deps.env.decompile = function() end
		Explorer.Selection:SetTable({nodes[outside], nodes[scriptObject]})
		context.Registered.VIEW_SCRIPT.OnClick()
		assert(opened == scriptObject, "Open uses the first eligible selected script")
		Apps.ScriptViewer.ViewScript, deps.env.isViableDecompileScript, deps.env.decompile = oldView, oldCheck, oldDecompile
		Explorer.Selection:Set(nodes[outside])
		scriptObject:Destroy()
	end
	local previousHttp = service.HttpService
	local payload
	service.HttpService = { JSONEncode = function(_, object)
		payload = object
		return "encoded fixture"
	end }
	local folderClass = API.Classes.Folder
	local previousProperties = folderClass.Properties
	folderClass.Properties = { { Name = "Archivable" }, { Name = "Parent" }, { Name = "Unchanged" } }
	for _, obj in { outside, child } do
		obj.GetAttributes = function() return { Enabled = false, Count = 3 } end
		rawset(obj, "GetTags", function() return { "Example" } end)
		obj.IsPropertyModified = function(_, key) return key == "Archivable" end
		obj.Archivable = false
	end
	context.Registered.COPY_AS_JSON.OnClick()
	assert(copied == "encoded fixture" and payload.ClassName == "Folder" and payload.Name == outside.Name)
	assert(payload.Archivable == "false" and payload.Parent == nil and payload.Unchanged == nil)
	assert(payload["$Enabled"] == false and payload["$Count"] == 3 and payload[".Example"] == true)
	Explorer.Selection:SetTable({ nodes[child], nodes[outside] })
	context.Registered.COPY_AS_JSON.OnClick()
	assert(#payload == 2 and payload[1].Name == child.Name and payload[2].Name == outside.Name)
	Explorer.Selection:Set(nodes[outside])
	local previousReader = deps.env.getclipboard
	local jsonText = '{"ClassName":"Folder","Name":"Renamed"}'
	local decoded = { ClassName = "Folder", Name = "Renamed" }
	service.HttpService.JSONDecode = function() return decoded end
	deps.env.getclipboard = function() return jsonText end
	assert(menu({nodes[outside]})["Paste Into"])
	folderClass.Properties = { { Name = "Name", ValueType = { Name = "string" } } }
	Explorer.Selection:SetTable({ nodes[child], nodes[outside] })
	context.Registered.PASTE.OnClick()
	assert(child.Name == "Renamed" and outside.Name == "Renamed", "paste updates both selected folders")
	assert(Apps.History.Undo() and child.Name == "ContextChild" and outside.Name == "ContextOutside")
	Explorer.Selection:Set(nodes[outside])
	local classTags = folderClass.Tags
	folderClass.Tags = {}
	jsonText = '[{"ClassName":"Folder"},{"ClassName":"Folder"}]'
	decoded = { { ClassName = "Folder" }, { ClassName = "Folder" } }
	context.Registered.PASTE.OnClick()
	assert(#Explorer.Selection.List == 2 and Explorer.Selection.List[1].Obj.Parent == outside, "array creates children")
	assert(Apps.History.Undo())
	context.Registered.COPY.OnClick()
	assert(pcall(context.Registered.PASTE.OnClick), "ordinary Copy takes priority over earlier clipboard JSON")
	assert(#Explorer.Selection.List == 1 and Explorer.Selection.List[1].Obj.Name == outside.Name)
	assert(Apps.History.Undo())
	folderClass.Tags = classTags
	deps.env.getclipboard = previousReader
	Explorer.Selection:Set(nodes[outside])
	service.HttpService, folderClass.Properties = previousHttp, previousProperties
	outside.UniqueId = nil
	deps.env.setclipboard = savedClipboard
	local oldScript = API.Classes.BaseScript
	API.Classes.BaseScript = { Name = "BaseScript", Tags = {}, Properties = {} }
	local first = Instance.new("BaseScript", workspace)
	first.Disabled = false
	local second = Instance.new("BaseScript", workspace)
	second.Disabled = true
	Explorer.SyncHistoryObject(first)
	Explorer.SyncHistoryObject(second)
	names = menu({ nodes[first], nodes[second] })
	assert(names["Disable Scripts"], "mixed script state offers disabling")
	context.Registered.TOGGLE_SCRIPTS.OnClick()
	assert(first.Disabled and second.Disabled, "toggle disables all selected scripts")
	assert(
		Apps.History.Undo() and first.Disabled == false and second.Disabled == true,
		"toggle restores mixed states as one history operation"
	)
	first.Disabled = true
	names = menu({ nodes[first], nodes[second] })
	assert(names["Enable Scripts"], "all disabled scripts offer enabling")
	context.Registered.TOGGLE_SCRIPTS.OnClick()
	assert(not first.Disabled and not second.Disabled, "all disabled scripts enable together")
	first.Parent = nil
	second.Parent = nil
	Explorer.SyncHistoryObject(first)
	Explorer.SyncHistoryObject(second)
	API.Classes.BaseScript = oldScript
	local savedInsert, savedCreate, savedView =
		Apps.InsertionService.Insert, Apps.ReflectionService.CanCreate, Explorer.ViewNode
	local inserted
	Apps.ReflectionService.CanCreate = function(class)
		return class == "Part"
	end
	Apps.InsertionService.Insert = function(class, targets, options)
		assert(class == "Part" and #targets == 1 and targets[1] == nodes[root], "Insert Part uses selected parent")
		inserted = Instance.new("Part", root)
		options.Reveal(targets[1])
		return { inserted }
	end
	Explorer.ViewNode = function() end
	Explorer.Selection:Set(nodes[root])
	context.Registered.INSERT_PART.OnClick()
	assert(
		inserted and inserted.Parent == root and Explorer.Selection.Map[nodes[inserted]],
		"Insert Part selects real inserted instance"
	)
	Apps.InsertionService.Insert = savedInsert
	Apps.ReflectionService.CanCreate = savedCreate
	Explorer.ViewNode = savedView
	local oldAttachment = API.Classes.Attachment
	local savedVector, savedFrame, savedCamera = Vector3, CFrame, workspace.CurrentCamera
	local vectorMT = {}
	local vector
	vector = function(x, y, z)
		return setmetatable({ X = x, Y = y, Z = z }, vectorMT)
	end
	vectorMT.__add = function(a, b)
		return vector(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	vectorMT.__sub = function(a, b)
		return vector(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
	end
	vectorMT.__mul = function(a, b)
		return vector(a.X * b, a.Y * b, a.Z * b)
	end
	vectorMT.__div = function(a, b)
		return vector(a.X / b, a.Y / b, a.Z / b)
	end
	vectorMT.__index = function(v, key)
		if key == "Magnitude" then
			return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		end
	end
	Vector3 = { new = vector }
	CFrame = {
		new = function(position)
			return { Position = position }
		end,
		lookAt = function(position, center)
			return { Position = position, Target = center, LookVector = vector(0, 0, -1) }
		end,
	}
	local attachment = Instance.new("Attachment", root)
	attachment.WorldPosition = vector(12, 23, 34)
	API.Classes.Attachment = { Name = "Attachment", Tags = {}, Properties = {} }
	Explorer.SyncHistoryObject(attachment)
	local camera =
		{ FieldOfView = 70, ViewportSize = Vector2.new(1600, 900), CFrame = { LookVector = vector(0, 0, -1) } }
	workspace.CurrentCamera = camera
	names = menu({ nodes[attachment] })
	assert(not names["Zoom to"] and not context.Registered.FOCUS_OBJECT, "Studio camera command is removed")
	Vector3, CFrame, workspace.CurrentCamera = savedVector, savedFrame, savedCamera
	API.Classes.Attachment = oldAttachment
	local menuInstance = Apps.ContextMenu.new()
	menuInstance:Clear()
	menuInstance:AddDivider()
	menuInstance:Register("X", { Name = "X" })
	menuInstance:AddRegistered("X")
	menuInstance:AddRegistered("X")
	menuInstance:AddDivider()
	menuInstance:AddDivider()
	menuInstance:Add({ Name = "Y" })
	assert(
		#menuInstance.Items == 3 and menuInstance.Items[2].Divider,
		"leading/repeated separators and duplicate registered actions are suppressed"
	)
	menuInstance:Show(10, 10)
	assert(Apps.ContextMenu.IsAnyShown(), "active menus block tree hover")
	menuInstance:Hide()
	assert(not Apps.ContextMenu.IsAnyShown(), "closing last menu restores tree hover")
	menuInstance:Hide()
	assert(not Apps.ContextMenu.IsAnyShown(), "repeated close does not corrupt menu state")
	menuInstance:Clear()
	menuInstance:Add({ Text = "Editor action" })
	menuInstance:Show(10, 10)
	assert(menuInstance.Items[1].Name == "Editor action", "Text callers receive a canonical menu name")
	assert(
		menuInstance.GuiElems.List:FindFirstChild("Item1"):FindFirstChild("EntryName").Text == "Editor action",
		"rendered label uses caller text instead of TextLabel default"
	)
	menuInstance:Clear()
	menuInstance:Add({ Name = "Nested", Submenu = { { Name = "Old selection action" } } })
	menuInstance:Show(10, 10)
	menuInstance:OpenSubmenu(menuInstance.Items[1])
	local staleChild = menuInstance.ChildMenu
	assert(staleChild.Shown, "submenu fixture opens")
	menuInstance:Clear()
	assert(
		staleChild.Destroyed and not staleChild.Shown and menuInstance.ChildMenu == nil,
		"rebuilding selection menu removes stale submenu and its portal"
	)
	menuInstance:Add({ Name = "Nested", Submenu = { { Name = "Current selection action" } } })
	menuInstance:OpenSubmenu(menuInstance.Items[1])
	local ownedChild = menuInstance.ChildMenu
	menuInstance:Destroy()
	assert(ownedChild.Destroyed and not Apps.ContextMenu.IsAnyShown(), "destroying parent releases cached child menus")
	menuInstance:Destroy()
	API.Classes.Folder = oldClass
	Settings.Explorer.HiddenServices = oldHidden
	root.Parent = nil
	outside.Parent = nil
	Explorer.SyncHistoryObject(root)
	Explorer.SyncHistoryObject(outside)
	Explorer.Selection:Clear()
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	print(
		"PASS: context expectations for blank/service/mixed selection, protected edit commands, unique IDs, script toggles, insertion, Attachment focus and separator hygiene"
	)
end
