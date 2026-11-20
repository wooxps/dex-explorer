--!strict

------------------------------ Variables ------------------------------

local Main, Lib, Apps, Settings
local Explorer, Properties, ScriptViewer, ModelViewer, Notebook
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
	ModelViewer = Apps.ModelViewer
	Notebook = Apps.Notebook
end

------------------------------ Module ------------------------------

local function CreateModule()
	local Explorer = {}
	local viewing
	local function clearViewing()
		local previous = viewing
		viewing = nil
		if previous and previous.Connection then
			previous.Connection:Disconnect()
		end
		return previous
	end
	Explorer.IsViewing = function(target)
		local camera = workspace.CurrentCamera
		return viewing ~= nil
			and camera == viewing.Camera
			and camera.CameraSubject == viewing.Subject
			and (target == nil or target == viewing.Target or target == viewing.Subject)
	end
	Explorer.StopViewing = function()
		local previous = clearViewing()
		if
			not previous
			or workspace.CurrentCamera ~= previous.Camera
			or previous.Camera.CameraSubject ~= previous.Subject
		then
			return
		end
		local subject = previous.Original
		if subject and not subject:IsDescendantOf(game) then
			local character = plr.Character
			subject = character and (character:FindFirstChildOfClass("Humanoid") or character) or nil
		end
		previous.Camera.CameraSubject = subject
	end
	Explorer.StartViewing = function(subject, isPlayer)
		local camera = workspace.CurrentCamera
		if Main.Alive == false or not camera or not subject or not subject:IsDescendantOf(game) then
			return false
		end
		if not subject:IsA("BasePart") and not subject:IsA("Model") and not subject:IsA("Humanoid") then
			return false
		end
		local target = subject
		if subject:IsA("Model") then
			subject = subject:FindFirstChildOfClass("Humanoid") or subject
		end
		if not Explorer.IsViewing() then
			clearViewing()
			viewing = { Camera = camera, Original = camera.CameraSubject }
		elseif viewing.Connection then
			viewing.Connection:Disconnect()
		end
		viewing.Target = target
		viewing.IsPlayer = isPlayer == true
		viewing.Subject = subject
		camera.CameraSubject = subject
		viewing.Connection = subject.AncestryChanged:Connect(function()
			if not subject:IsDescendantOf(game) then
				Explorer.StopViewing()
			end
		end)
		return true
	end
	Main.AddCleanup(Explorer.StopViewing)
	Explorer.InferredObjects = setmetatable({}, { __mode = "k" })
	Explorer.InferredNodes = {}
	Explorer.IsInferredObject = function(obj)
		return Explorer.InferredObjects[obj] ~= nil
	end
	Explorer.GetInferenceNodes = function()
		return nodes
	end
	Explorer.GetNodes = function()
		return nodes
	end
	local evidenceCandidates = setmetatable({}, { __mode = "k" })
	local scriptCandidates = setmetatable({}, { __mode = "k" })
	local engineEvidenceRoots =
		{ CorePackages = true, CoreGui = true, RobloxReplicatedStorage = true, RobloxPluginGuiService = true }
	local function indexEvidenceCandidate(obj, node)
		evidenceCandidates[obj] = nil
		local class = obj.ClassName
		if class == "Script" or class == "LocalScript" or class == "ModuleScript" then
			node.Class = class
			scriptCandidates[obj] = node
		else
			scriptCandidates[obj] = nil
		end
		if class ~= "Script" and class ~= "LocalScript" and class ~= "ModuleScript" and class ~= "StringValue" then
			return
		end
		local root, depth = node, 0
		while root.Parent and root.Parent.Obj ~= game and depth < 64 do
			root = root.Parent
			depth += 1
		end
		if root.Parent and root.Parent.Obj == game and not engineEvidenceRoots[root.Obj.Name] then
			evidenceCandidates[obj] = node
		end
	end
	Explorer.GetInferenceCandidates = function()
		return evidenceCandidates
	end
	Explorer.GetScriptCandidates = function()
		return scriptCandidates
	end
	Explorer.HasReconstructedSelection = function()
		for _, node in ipairs(Explorer.Selection and Explorer.Selection.List or {}) do
			if node.Materialized then
				return true
			end
		end
		return false
	end
	Explorer.IsReadOnlyInferenceObject = function(obj)
		local node = Explorer.InferredObjects[obj]
		return node ~= nil and not node.Materialized
	end
	Explorer.HasInferredSelection = function()
		for _, node in ipairs(Explorer.Selection and Explorer.Selection.List or {}) do
			if node.Inferred and not node.Materialized then
				return true
			end
		end
		return false
	end
	local projection, searchEngine, searchView
	local retainedSearchQuery
	local searchExpansionDirty = false
	local scheduleSearchRefresh, startSearchWidths, scheduleIndexMaintenance
	local searchRefreshQueued = false
	local characterSearch = {}
	local function canRefreshDisplayedSearch()
		return not Explorer.SearchInputPending and not Explorer.SearchBusy
	end
	local branchViews = {}
	local sortedSearchChildren = setmetatable({}, { __mode = "k" })
	local function invalidateBranch(node)
		if projection then
			projection:Mark(node)
		end
		while node do
			branchViews[node] = nil
			sortedSearchChildren[node] = nil
			node = node.Parent
		end
	end
	local function markSearchDirty(node, subtree, reason)
		if node then
			node.SearchRawName = nil
		end
		if searchEngine then
			local affects = searchEngine:Mark(node, subtree, reason)
			if scheduleIndexMaintenance and searchEngine.Snapshots.PendingCount >= 512 then
				scheduleIndexMaintenance()
			end
			if searchView then
				if node and node.Del then
					searchView:Remove(node)
				end
				if affects and scheduleSearchRefresh then
					scheduleSearchRefresh()
				end
			end
		end
		invalidateBranch(node)
		if projection then
			projection:Mark(node and node.Parent)
		end
		local index = Apps.SearchQuery.NameIndex
		if index then
			index.MarkDirty(node, subtree)
		end
	end
	local Policy = Apps.ExplorerPolicy
	local tokens = Policy.Tokens
	local tree, listEntries, explorerOrders, searchResults, specResults = {}, {}, {}, {}, {}
	local displayedNodes = setmetatable({}, { __mode = "k" })
	local objectPicker
	local visibleIndices = {}
	local selectingRow = false
	local normalTree, normalIndices = tree, visibleIndices
	local expanded
	local function rowIndex(node)
		return searchView and searchView:IndexOf(node) or visibleIndices[node]
	end
	Explorer.HasChildren = function(node)
		if not node or node.Del then
			return false
		end
		if searchView then
			return searchView:HasChildren(node)
		end
		return #node > 0 and (expanded ~= Explorer.SearchExpanded or expanded[node] ~= 0)
	end
	projection = Apps.ExplorerProjection.Create(tree, visibleIndices)
	Explorer.ProjectionStats = projection.Stats
	Explorer.VisibleProjection = projection
	local treeFrame, toolBar, descendantAddedCon, descendantRemovingCon, itemChangedCon
	local ffa = game.FindFirstAncestorWhichIsA
	local getDescendants = game.GetDescendants
	local function readParent(object)
		return object.Parent
	end
	local getTextSize = service.TextService.GetTextSize
	local updateDebounce, refreshDebounce = false, false
	local updateTicket, refreshTicket = 0, 0
	local dirtyParents = {}
	local cleanupScheduled = false
	local function scheduleDeletedChildrenCleanup()
		if cleanupScheduled then
			return
		end
		cleanupScheduled = true
		task.delay(0.5, function()
			cleanupScheduled = false
			if Main.Alive ~= false and Explorer.CleanDeletedChildren() and not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end)
	end
	local searchGeneration, searchTreeVersion = 0, 0
	local function changeSearchTree(removal)
		searchTreeVersion += 1
		if not removal then
			characterSearch.ContentVersion = (characterSearch.ContentVersion or 0) + 1
		end
		characterSearch.Layout = nil
		if characterSearch.Schedule and not characterSearch.Pending then
			characterSearch.Schedule()
		end
	end
	local nilNode = { Obj = Instance.new("Folder") }
	local idCounter = 0
	local scrollV, scrollH, clipboard
	local renameBox, renamingNode, searchFunc
	local sortingEnabled, autoUpdateSearch
	local table, math = table, math
	local nilMap, nilCons = {}, {}
	local connectSignal = game.DescendantAdded.Connect
	local addObject, removeObject, moveObject = nil, nil, nil
	local function unwatchNil(obj)
		local connections = nilCons[obj]
		if connections then
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			nilCons[obj] = nil
		end
	end
	local function watchNil(obj)
		if nilCons[obj] then
			return
		end
		nilCons[obj] = {
			connectSignal(obj.ChildAdded, function(child)
				if not nilMap[obj] or (Apps.History and Apps.History.IsHidden(child)) then
					return
				end
				nilMap[child] = true
				for _, item in ipairs(getDescendants(child)) do
					nilMap[item] = true
					watchNil(item)
				end
				watchNil(child)
				Explorer.SyncHistoryObject(child)
			end),
			connectSignal(obj.AncestryChanged, function()
				task.defer(function()
					if not nilMap[obj] then
						return
					end
					if obj:IsDescendantOf(game) or (Apps.History and Apps.History.IsHidden(obj)) then
						local descendants = getDescendants(obj)
						descendants[#descendants + 1] = obj
						for _, item in ipairs(descendants) do
							nilMap[item] = nil
							unwatchNil(item)
						end
					end
					Explorer.SyncHistoryObject(obj)
					Explorer.PerformUpdate()
				end)
			end),
			obj:GetPropertyChangedSignal("Name"):Connect(function()
				local node = nodes[obj]
				if node then
					changeSearchTree()
					node.NameWidth = nil
					markSearchDirty(node, false)
					if node.Parent then
						node.Parent.Sorted = false
					end
					Explorer.PerformUpdate()
				end
			end),
		}
	end

	local iconData
	local remote_blocklist = {}
	nodes = nodes or {}

	addObject = function(root)
		if
			nodes[root]
			or (Main.SelectionGeometryObjects and Main.SelectionGeometryObjects[root])
			or (Main.SelectionGeometryRoots and Main.SelectionGeometryRoots[root])
			or (Apps.History and Apps.History.IsHidden(root))
		then
			return
		end

		local isNil = false
		local rootParObj = root.Parent
		local par = nodes[rootParObj]

		if not par then
			if nilMap[root] then
				watchNil(root)
				par = nilNode
				isNil = true
			else
				return
			end
		elseif nilMap[rootParObj] or par == nilNode then
			nilMap[root] = true
			watchNil(root)
			isNil = true
		end

		changeSearchTree()
		local newNode = { Obj = root, Parent = par }
		nodes[root] = newNode
		indexEvidenceCandidate(root, newNode)

		if sortingEnabled and expanded[par] and par.Sorted then
			local left, right = 1, #par
			local floor = math.floor
			local sorter = Explorer.NodeSorter
			local pos = (right == 0 and 1)

			if not pos then
				while true do
					if left >= right then
						if sorter(newNode, par[left]) then
							pos = left
						else
							pos = left + 1
						end
						break
					end

					local mid = floor((left + right) / 2)
					if sorter(newNode, par[mid]) then
						right = mid - 1
					else
						left = mid + 1
					end
				end
			end

			table.insert(par, pos, newNode)
		else
			par[#par + 1] = newNode
			par.Sorted = nil
		end

		local insts = getDescendants(root)
		for i = 1, #insts do
			local obj = insts[i]
			if nodes[obj] then
				continue
			end

			local par = nodes[obj.Parent]
			if not par then
				continue
			end
			local newNode = { Obj = obj, Parent = par }
			nodes[obj] = newNode
			indexEvidenceCandidate(obj, newNode)
			par[#par + 1] = newNode

			if isNil then
				nilMap[obj] = true
				watchNil(obj)
			end
		end

		markSearchDirty(newNode, true)
		if searchFunc and autoUpdateSearch then
			searchFunc({ newNode })
		end

		if not updateDebounce and Explorer.IsNodeVisible(par) then
			if expanded[par] then
				Explorer.PerformUpdate(false, true)
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	removeObject = function(root)
		local node = nodes[root]
		if not node then
			return
		end
		if characterSearch.RemovedNodes then
			characterSearch.RemovedNodes[node] = true
		end
		changeSearchTree(true)

		if nilMap[node.Obj] and not (Apps.History and Apps.History.IsHidden(root)) then
			moveObject(node.Obj)
			return
		end

		local par = node.Parent
		if par then
			par.HasDel = true
			dirtyParents[par] = true
			scheduleDeletedChildrenCleanup()
		end

		local function recur(root)
			for i = 1, #root do
				local node = root[i]
				if not node.Del and nodes[node.Obj] == node and node.Obj:IsDescendantOf(root.Obj) then
					nodes[node.Obj] = nil
					sortedSearchChildren[node] = nil
					evidenceCandidates[node.Obj] = nil
					scriptCandidates[node.Obj] = nil
					if #node > 0 then
						recur(node)
					end
				end
			end
		end
		recur(node)
		node.Del = true
		markSearchDirty(node, true)
		nodes[root] = nil
		evidenceCandidates[root] = nil
		scriptCandidates[root] = nil

		if par and not updateDebounce and Explorer.IsNodeVisible(par) then
			if expanded[par] then
				Explorer.PerformUpdate(false, true)
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	moveObject = function(obj)
		local node = nodes[obj]
		if not node then
			return
		end

		local oldPar = node.Parent
		local newPar = nodes[obj.Parent]
		if oldPar == newPar then
			return
		end
		invalidateBranch(oldPar)
		changeSearchTree()

		if not newPar then
			if nilMap[obj] then
				newPar = nilNode
			else
				return
			end
		elseif nilMap[newPar.Obj] or newPar == nilNode then
			nilMap[obj] = true
			watchNil(obj)
		end

		if oldPar then
			local parPos = table.find(oldPar, node)
			if parPos then
				table.remove(oldPar, parPos)
			end
		end

		node.Id = nil
		node.Parent = newPar
		indexEvidenceCandidate(obj, node)
		node.ManualOrder = nil

		if sortingEnabled and expanded[newPar] and newPar.Sorted then
			local left, right = 1, #newPar
			local floor = math.floor
			local sorter = Explorer.NodeSorter
			local pos = (right == 0 and 1)

			if not pos then
				while true do
					if left >= right then
						if sorter(node, newPar[left]) then
							pos = left
						else
							pos = left + 1
						end
						break
					end

					local mid = floor((left + right) / 2)
					if sorter(node, newPar[mid]) then
						right = mid - 1
					else
						left = mid + 1
					end
				end
			end

			table.insert(newPar, pos, node)
		else
			newPar[#newPar + 1] = node
			newPar.Sorted = nil
		end

		markSearchDirty(node, true, "move")
		if searchFunc and not searchView and not retainedSearchQuery and searchResults[node] then
			local currentNode = node.Parent
			while currentNode and (not searchResults[currentNode] or expanded[currentNode] == 0) do
				expanded[currentNode] = true
				searchResults[currentNode] = true
				currentNode = currentNode.Parent
			end
		end

		if not updateDebounce and (Explorer.IsNodeVisible(newPar) or Explorer.IsNodeVisible(oldPar)) then
			if expanded[newPar] or expanded[oldPar] then
				Explorer.PerformUpdate(false, true)
			elseif not refreshDebounce then
				Explorer.PerformRefresh()
			end
		end
	end

	Explorer.ViewWidth = 0
	Explorer.Index = 0
	Explorer.EntryIndent = tokens.IndentWidth
	Explorer.RowHeight = tokens.RowHeight
	Explorer.HeaderHeight = tokens.HeaderHeight
	Explorer.Matches = {}
	Explorer.SearchHistory = {}
	Explorer.MatchList = {}
	Explorer.FreeWidth = 20
	Explorer.GuiElems = {}
	Explorer.NativeClassIconCache = {}

	Explorer.DisplayClassIcon = function(container, className, assetKey)
		Explorer.MiscIcons:DisplayExplorerIcons(container, className)
		local fallback = container:FindFirstChild("IconMap")
		if fallback then
			fallback.ZIndex = container.ZIndex
		end

		local native = container:FindFirstChild("StudioClassIcon")
		if not native then
			native = createSimple("ImageLabel", {
				Name = "StudioClassIcon",
				Parent = container,
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromOffset(16, 16),
				ZIndex = container.ZIndex + 1,
				ScaleType = Enum.ScaleType.Fit,
			})
		end

		local cacheKey = assetKey or className
		local data = Explorer.NativeClassIconCache[cacheKey]
		if data == nil then
			local asset = Main.GetStudioAsset and Main.GetStudioAsset(assetKey or "class/" .. className)
			if not asset and assetKey then
				asset = Main.GetStudioAsset and Main.GetStudioAsset("class/" .. className)
			end
			if not asset and className:match("Service$") then
				asset = Main.GetStudioAsset and Main.GetStudioAsset("class/Service")
			end
			if not asset then
				asset = Main.GetStudioAsset and Main.GetStudioAsset("class/Placeholder")
			end
			if asset then
				data = { Image = asset, ImageRectOffset = Vector2.new(0, 0), ImageRectSize = Vector2.new(0, 0) }
			else
				local ok, result = pcall(function()
					return game:GetService("StudioService"):GetClassIcon(className)
				end)
				if ok and type(result) == "table" and type(result.Image) == "string" and result.Image ~= "" then
					data = result
				else
					data = false
				end
			end
			Explorer.NativeClassIconCache[cacheKey] = data
		end

		if data and data.Image then
			native.Image = data.Image
			native.ImageRectOffset = data.ImageRectOffset or Vector2.new(0, 0)
			native.ImageRectSize = data.ImageRectSize or Vector2.new(0, 0)
			native.Visible = true
			if fallback then
				fallback.Visible = false
			end
		else
			native.Visible = false
			if fallback then
				fallback.Visible = true
			end
		end
	end

	Explorer.InitRenameBox = function()
		renameBox = Apps.RenameBox.Create(Explorer.TreeRenderer, Explorer.TreeRenderer.Layer)
		pcall(function()
			renameBox.ShouldEmitTabEvents = true
			renameBox.ShouldEmitUpAndDownArrowEvents = true
		end)
		local function commit(node, text)
			text = Policy.FormatName(text)
			if node and text ~= "" and text ~= tostring(node.Obj) then
				local ok, problem = pcall(Apps.EditingService.Rename, node.Obj, text)
				if not ok then
					warn("Dex rename failed: " .. tostring(problem))
				end
			end
		end
		local function iterate(direction)
			local node = renamingNode
			if not node then
				return
			end
			local index = rowIndex(node)
			local target = index and tree[index + direction]
			local text = renameBox.Text
			renamingNode = nil
			renameBox:ReleaseFocus()
			commit(node, text)
			if target then
				selection:Set(target)
				Explorer.SetRenamingNode(target)
			else
				Explorer.Refresh()
			end
		end
		renameBox:GetPropertyChangedSignal("Text"):Connect(function()
			if not renamingNode then
				return
			end
			local value = Policy.FormatName(renameBox.Text)
			if value:sub(-1) == "\t" then
				renameBox.Text = value:sub(1, -2)
				iterate(1)
			elseif value ~= renameBox.Text then
				renameBox.Text = value
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if service.UserInputService:GetFocusedTextBox() ~= renameBox then
				return
			end
			if input.KeyCode == Enum.KeyCode.Down then
				iterate(1)
			elseif input.KeyCode == Enum.KeyCode.Up or (input.KeyCode == Enum.KeyCode.Tab and Lib.IsShiftDown()) then
				iterate(-1)
			end
		end)

		Explorer.CancelRename = function()
			if not renamingNode then
				return
			end
			renamingNode = nil
			renameBox:ReleaseFocus()
			renameBox.Visible = false
			Explorer.Refresh()
		end
		renameBox.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				Explorer.CancelRename()
			end
		end)
		renameBox.FocusLost:Connect(function(_, input)
			if not renamingNode then
				return
			end
			if not input or input.KeyCode == Enum.KeyCode.Escape then
				Explorer.CancelRename()
				return
			end

			commit(renamingNode, renameBox.Text)
			renamingNode = nil
			Explorer.Refresh()
		end)

		renameBox.Focused:Connect(function()
			renameBox.SelectionStart = 1
			renameBox.CursorPosition = #renameBox.Text + 1
		end)
	end

	Explorer.SetRenamingNode = function(node)
		if not node or (node.Inferred and not node.Materialized) or node == nilNode or node.Del or node.Obj == game then
			return
		end
		Explorer.ViewNode(node)
		renamingNode = node
		renameBox.Text = tostring(node.Obj)
		renameBox:CaptureFocus()
		Explorer.Refresh()
	end

	Explorer.SetSortingEnabled = function(val)
		projection.Valid = false
		local changed = sortingEnabled ~= val
		sortingEnabled = val
		Settings.Explorer.Sorting = val
		if changed then
			changeSearchTree()
		end
	end

	Explorer.UpdateView = function()
		treeFrame.Size = UDim2.new(1, -2, 1, -Explorer.HeaderHeight - 2)
		local viewport = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
		local maxNodes = math.max(1, math.floor(viewport.Y / Explorer.RowHeight))
		scrollV.VisibleSpace = maxNodes
		scrollV.TotalSpace = #tree
		scrollH.VisibleSpace = viewport.X
		scrollH.TotalSpace = Explorer.ViewWidth + Explorer.FreeWidth
		treeFrame.CanvasSize = UDim2.fromOffset(Explorer.ViewWidth + Explorer.FreeWidth, #tree * Explorer.RowHeight)
		Explorer.Window.GuiElems.Content.ScrollCorner.Visible = false
		scrollV:Update()
		scrollH:Update()
		renameBox.Size = UDim2.fromOffset(math.max(60, viewport.X - 100), Explorer.RowHeight - 2)
		Explorer.Index = scrollV.Index
	end

	local sortingNames
	local function compareNodes(a, b, names, includeDeleted)
		if not includeDeleted and (a.Del or b.Del) then
			return false
		end
		if a.Parent == b.Parent and (a.ManualOrder or b.ManualOrder) then
			local x, y = a.ManualOrder or math.huge, b.ManualOrder or math.huge
			if x ~= y then
				return x < y
			end
		end

		local aClass = a.Class
		local bClass = b.Class
		if not aClass then
			aClass = a.Obj.ClassName
			a.Class = aClass
		end
		if not bClass then
			bClass = b.Obj.ClassName
			b.Class = bClass
		end

		local aOrder = explorerOrders[aClass]
		local bOrder = explorerOrders[bClass]
		if not aOrder then
			aOrder = RMD.Classes[aClass] and tonumber(RMD.Classes[aClass].ExplorerOrder) or 9999
			explorerOrders[aClass] = aOrder
		end
		if not bOrder then
			bOrder = RMD.Classes[bClass] and tonumber(RMD.Classes[bClass].ExplorerOrder) or 9999
			explorerOrders[bClass] = bOrder
		end

		if aOrder ~= bOrder then
			return aOrder < bOrder
		else
			local aName, bName
			if names then
				aName, bName = names[a], names[b]
				if not aName then
					aName = tostring(a.Obj)
					names[a] = aName
				end
				if not bName then
					bName = tostring(b.Obj)
					names[b] = bName
				end
			else
				aName, bName = tostring(a.Obj), tostring(b.Obj)
			end
			if aName ~= bName then
				return aName < bName
			elseif aClass ~= bClass then
				return aClass < bClass
			else
				local aId = a.Id
				if not aId then
					aId = idCounter
					idCounter = (idCounter + 0.001) % 999999999
					a.Id = aId
				end
				local bId = b.Id
				if not bId then
					bId = idCounter
					idCounter = (idCounter + 0.001) % 999999999
					b.Id = bId
				end
				return aId < bId
			end
		end
	end

	Explorer.NodeSorter = function(a, b)
		return compareNodes(a, b, sortingNames)
	end
	local defaultNodeSorter = Explorer.NodeSorter
	local function sortNamedSiblings(children, namesByNode, sort)
		local class
		local names = table.create(#children)
		local byName = {}
		local unique = true
		for i, node in ipairs(children) do
			if node.Del or node.ManualOrder then
				table.sort(children, sort)
				return
			end
			local nodeClass = node.Class or node.Obj.ClassName
			if class and nodeClass ~= class then
				table.sort(children, sort)
				return
			end
			class = nodeClass
			node.Class = nodeClass
			local name = namesByNode[node]
			if not name then
				name = tostring(node.Obj)
				namesByNode[node] = name
			end
			names[i] = name
			if byName[name] then
				unique = false
			else
				byName[name] = node
			end
		end

		if not unique then
			table.sort(children, function(a, b)
				local left, right = namesByNode[a], namesByNode[b]
				if left == right then
					if a.Id and b.Id then return a.Id < b.Id end
					return sort(a, b)
				end
				return left < right
			end)
			return
		end

		table.sort(names)
		for i, name in ipairs(names) do
			children[i] = byName[name]
		end
	end
	local function sortSiblings(children, sort)
		if #children >= 16 and sort == defaultNodeSorter then
			sortNamedSiblings(children, sortingNames, sort)
		else
			table.sort(children, sort)
		end
	end

	local function coldName(node)
		local name = node.SearchRawName or node.Obj.Name
		node.SearchRawName = name
		return name
	end

	local function sortColdItems(items, less, check)
		if #items <= 512 then
			table.sort(items, less)
			check()
			return items
		end
		local page = {}
		for first = 1, #items, 512 do
			table.clear(page)
			table.move(items, first, math.min(first + 511, #items), 1, page)
			table.sort(page, less)
			table.move(page, 1, #page, first, items)
			check()
		end
		local count, width = #items, 512
		local merged = table.create(count)
		while width < count do
			for first = 1, count, width * 2 do
				local middle = math.min(first + width, count + 1)
				local last = math.min(first + width * 2 - 1, count)
				local left, right, at = first, middle, first
				if right > last or not less(items[right], items[middle - 1]) then
					table.move(items, first, last, first, merged)
					check()
					continue
				end
				while left < middle and right <= last do
					if less(items[right], items[left]) then
						merged[at] = items[right]
						right += 1
					else
						merged[at] = items[left]
						left += 1
					end
					at += 1
					if at % 128 == 0 then
						check()
					end
				end
				if left < middle then
					table.move(items, left, middle - 1, at, merged)
				elseif right <= last then
					table.move(items, right, last, at, merged)
				end
				check()
			end
			items, merged = merged, items
			width *= 2
		end
		return items
	end

	local function sortColdNames(items, check, sameOrder)
		local class = items[1].Class or items[1].Obj.ClassName
		local names, byName = table.create(#items), {}
		local duplicates = {}
		local first, last
		for i, node in ipairs(items) do
			if node.ManualOrder then return false end
			local nodeClass = node.Class or node.Obj.ClassName
			if not sameOrder and nodeClass ~= class then
				local orders, groups = {}, {}
				for at, child in ipairs(items) do
					if child.ManualOrder then return false end
					local childClass = child.Class or child.Obj.ClassName
					child.Class = childClass
					local order = explorerOrders[childClass]
					if not order then
						local details = RMD.Classes[childClass]
						order = details and tonumber(details.ExplorerOrder) or 9999
						explorerOrders[childClass] = order
					end
					local group = groups[order]
					if not group then
						group = {}
						groups[order] = group
						orders[#orders + 1] = order
					end
					group[#group + 1] = child
					if at % 128 == 0 then check() end
				end
				table.sort(orders)
				for _, order in ipairs(orders) do
					local group = groups[order]
					if #group > 1 and not sortColdNames(group, check, true) then return false end
				end
				local at = 1
				for _, order in ipairs(orders) do
					local group = groups[order]
					table.move(group, 1, #group, at, items)
					at += #group
				end
				return true
			end
			node.Class = nodeClass
			local name = coldName(node)
			local previous = byName[name]
			if previous then
				local group = duplicates[name]
				if not group then
					group = { previous }
					duplicates[name] = group
				end
				group[#group + 1] = node
			else
				names[#names + 1], byName[name] = name, node
			end
			if not first or name < first then
				first = name
			end
			if not last or name > last then
				last = name
			end
			if i % 128 == 0 then
				check()
			end
		end
		for name, group in pairs(duplicates) do
			local ordered, previousId, previousClass = true, -math.huge, nil
			for index, node in ipairs(group) do
				if not node.Id then
					node.Id = idCounter
					idCounter = (idCounter + 0.001) % 999999999
				end
				ordered = ordered and (not previousClass or previousClass < node.Class
					or previousClass == node.Class and previousId <= node.Id)
				previousClass = node.Class
				previousId = node.Id
				if index % 128 == 0 then
					check()
				end
			end
			if not ordered then
				duplicates[name] = sortColdItems(group, function(a, b)
					if a.Class ~= b.Class then return a.Class < b.Class end
					return a.Id < b.Id
				end, check)
			end
			check()
		end
		local out = 0
		local function emit(group)
			table.sort(group)
			for _, name in ipairs(group) do
				local repeated = duplicates[name]
				if repeated then
					table.move(repeated, 1, #repeated, out + 1, items)
					out += #repeated
				else
					out += 1
					items[out] = byName[name]
				end
			end
			check()
		end
		local function partition(group, minimum, maximum, at)
			if #group <= 1024 then
				emit(group)
				return
			end
			while string.byte(minimum, at) == string.byte(maximum, at) do
				at += 1
			end
			local buckets, keys = {}, {}
			for i, name in ipairs(group) do
				local key = string.byte(name, at) or -1
				local bucket = buckets[key]
				if not bucket then
					bucket = { Min = name, Max = name }
					buckets[key] = bucket
					keys[#keys + 1] = key
				end
				bucket[#bucket + 1] = name
				if name < bucket.Min then
					bucket.Min = name
				end
				if name > bucket.Max then
					bucket.Max = name
				end
				if i % 128 == 0 then
					check()
				end
			end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local bucket = buckets[key]
				partition(bucket, bucket.Min, bucket.Max, at + 1)
			end
		end
		partition(names, first, last, 1)
		return true
	end

	local function coldChildren(parent, check)
		if not sortingEnabled or parent.Sorted or #parent < 2 then
			return parent
		end
		local cached = sortedSearchChildren[parent]
		if cached and cached.Sorter == Explorer.NodeSorter then
			return cached.Items
		end
		local version, sorter = searchTreeVersion, Explorer.NodeSorter
		local function remember(items)
			if searchTreeVersion == version and Explorer.NodeSorter == sorter then
				sortedSearchChildren[parent] = { Sorter = sorter, Items = items }
			end
			return items
		end
		local items = table.move(parent, 1, #parent, 1, table.create(#parent))
		local count = 0
		for i = 1, #items do
			local child = items[i]
			if not child.Del and child.Parent == parent then
				count += 1
				if count ~= i then
					items[count], items[i] = child, nil
				end
			else
				items[i] = nil
			end
			if i % 128 == 0 then
				check()
			end
		end
		local names = {}
		local less = Explorer.NodeSorter
		if less == defaultNodeSorter then
			if #items > 512 and sortColdNames(items, check) then
				return remember(items)
			end
			less = function(a, b)
				return compareNodes(a, b, names, true)
			end
			if #items >= 16 and #items <= 512 then
				sortNamedSiblings(items, names, less)
				check()
				return remember(items)
			end
		end
		return remember(sortColdItems(items, less, check))
	end

	local widthRecent, widthPrevious, widthCount = {}, {}, 0
	local function rememberWidth(name, value)
		if widthCount >= 4096 then
			widthPrevious = widthRecent
			widthRecent = {}
			widthCount = 0
		end
		widthRecent[name] = value
		widthCount += 1
		return value
	end
	Explorer.Update = function(incremental)
		if searchView then
			searchView:Reflow(function() end)
			if startSearchWidths then
				startSearchWidths(searchView)
			end
			Explorer.MaxNameWidth, Explorer.MaxDepth = searchView.Width, searchView.Depth
			Explorer.ViewWidth = Explorer.EntryIndent * math.max(0, searchView.Depth - 1) + searchView.Width + 41
			Explorer.UpdateSearchStatus()
			Explorer.UpdateView()
			return
		end
		if
			incremental
			and not searchExpansionDirty
			and retainedSearchQuery == Explorer.Query
			and expanded == Explorer.SearchExpanded
		then
			Explorer.UpdateSearchStatus()
			Explorer.UpdateView()
			return
		end
		searchExpansionDirty = false
		local searching = expanded == Explorer.SearchExpanded
		if searching then
			projection.Valid = false
		end
		if
			incremental
			and not searching
			and projection:Try({
				Root = nodes[game],
				Expanded = expanded,
				Sort = function(parent)
					if sortingEnabled and not parent.Sorted then
						sortingNames = {}
						local ok, problem = pcall(sortSiblings, parent, Explorer.NodeSorter)
						sortingNames = nil
						if not ok then
							error(problem, 0)
						end
						parent.Sorted = true
						changeSearchTree()
					end
				end,
				Measure = function(node)
					if node.NameWidth then
						return
					end
					local name = Policy.FormatName(tostring(node.Obj))
					local width = widthRecent[name] or widthPrevious[name]
					if not width then
						width = getTextSize(
							service.TextService,
							name,
							14,
							Enum.Font.BuilderSans,
							Vector2.new(math.huge, 20)
						).X
						rememberWidth(name, width)
					end
					node.NameWidth = width
				end,
			})
		then
			Explorer.MaxNameWidth, Explorer.MaxDepth = projection.Width, projection.Depth
			Explorer.ViewWidth = Explorer.EntryIndent * math.max(0, projection.Depth - 1) + projection.Width + 41
			Explorer.UpdateView()
			return
		end
		if not incremental then
			table.clear(branchViews)
		end
		table.clear(tree)
		table.clear(visibleIndices)
		local maxNameWidth, maxDepth, count = 0, 1, 1
		local font = Enum.Font.BuilderSans
		local size = Vector2.new(math.huge, 20)
		local useNameWidth = true
		local sortFunc = Explorer.NodeSorter
		local isSearching = (expanded == Explorer.SearchExpanded)
		local provisional = isSearching and retainedSearchQuery ~= nil
		local textServ = service.TextService
		local searchChildren
		if isSearching and sortingEnabled then
			searchChildren = {}
			for node in pairs(searchResults) do
				local parent = node.Parent
				if parent and not node.Del then
					local children = searchChildren[parent]
					if not children then
						children = {}
						searchChildren[parent] = children
					end
					children[#children + 1] = node
				end
			end
			sortingNames = {}
			local ok, problem = pcall(function()
				for parent, children in pairs(searchChildren) do
					if #children * 4 >= #parent then
						if not parent.Sorted then
							sortSiblings(parent, sortFunc)
							parent.Sorted = true
							changeSearchTree()
						end
						searchChildren[parent] = parent
					else
						sortSiblings(children, sortFunc)
					end
				end
			end)
			sortingNames = nil
			if not ok then
				error(problem, 0)
			end
		end
		local emptyChildren = {}
		local function childrenOf(root)
			return searchChildren and (searchChildren[root] or emptyChildren) or root
		end

		table.clear(Explorer.MatchList)
		local function collectMatches(root)
			for _, node in ipairs(childrenOf(root)) do
				if root.Obj == game and not Apps.ServiceVisibility.IsVisible(node.Obj) then
					continue
				end
				if not node.Del and searchResults[node] then
					if Explorer.Matches[node] then
						Explorer.MatchList[#Explorer.MatchList + 1] = node
					end
					if #node > 0 then
						collectMatches(node)
					end
				end
			end
		end

		local branchDepth
		local function recur(root, depth)
			local cached = not isSearching and depth == 2 and branchViews[root]
			if cached then
				for _, node in ipairs(cached.Rows) do
					tree[count] = node
					visibleIndices[node] = count
					count += 1
				end
				maxNameWidth = math.max(maxNameWidth, cached.Width)
				maxDepth = math.max(maxDepth, cached.Depth)
				return
			end
			local branchStart = count
			local previousWidth
			if not isSearching and depth == 2 then
				previousWidth, maxNameWidth = maxNameWidth, 0
				branchDepth = 2
			end
			if depth > maxDepth then
				maxDepth = depth
			end
			depth = depth + 1
			if not searchChildren and sortingEnabled and not root.Sorted then
				changeSearchTree()
				sortingNames = {}
				local sorted, sortError = pcall(sortSiblings, root, sortFunc)
				sortingNames = nil
				if not sorted then
					error(sortError, 0)
				end
				root.Sorted = true
			end
			local children = childrenOf(root)
			for i = 1, #children do
				local n = children[i]

				if (isSearching and not searchResults[n]) or n.Del then
					continue
				end
				if root.Obj == game and not Apps.ServiceVisibility.IsVisible(n.Obj) then
					continue
				end

				if isSearching and Explorer.Matches[n] then
					Explorer.MatchList[#Explorer.MatchList + 1] = n
				end

				if useNameWidth then
					local nameWidth = n.NameWidth
					if not nameWidth and provisional then
						nameWidth = 100 * 14
					elseif not nameWidth then
						local objName = Policy.FormatName(tostring(n.Obj))
						nameWidth = widthRecent[objName] or widthPrevious[objName]
						if not nameWidth then
							nameWidth = getTextSize(textServ, objName, 14, font, size).X
							rememberWidth(objName, nameWidth)
						end
						n.NameWidth = nameWidth
					end
					if nameWidth > maxNameWidth then
						maxNameWidth = nameWidth
					end
				end

				tree[count] = n
				visibleIndices[n] = count
				count = count + 1
				if #n > 0 then
					if expanded[n] then
						recur(n, depth)
					elseif isSearching then
						collectMatches(n)
					end
				end
			end
			if branchDepth and count > branchStart then
				branchDepth = math.max(branchDepth, depth - 1)
			end
			if previousWidth ~= nil then
				local rows = table.move(tree, branchStart, count - 1, 1, table.create(count - branchStart))
				branchViews[root] = { Rows = rows, Width = maxNameWidth, Depth = branchDepth }
				maxNameWidth = math.max(previousWidth, maxNameWidth)
				branchDepth = nil
			end
		end

		recur(nodes[game], 1)

		if env.getnilinstances and Settings.Explorer.ShowNilInstances ~= false then
			if not (isSearching and not searchResults[nilNode]) then
				tree[count] = nilNode
				visibleIndices[nilNode] = count
				count = count + 1
				if expanded[nilNode] then
					recur(nilNode, 2)
				elseif isSearching then
					collectMatches(nilNode)
				end
			end
		end

		if Explorer.UpdateSearchStatus then
			Explorer.UpdateSearchStatus()
		end
		Explorer.MaxNameWidth = maxNameWidth
		Explorer.MaxDepth = maxDepth
		Explorer.ViewWidth = useNameWidth and Explorer.EntryIndent * math.max(0, maxDepth - 1) + maxNameWidth + 41
			or Explorer.EntryIndent * maxDepth + 226
		Explorer.UpdateView()
		if not isSearching then
			projection:Rebuild(nodes[game])
		end
	end

	local updateTree = Explorer.Update
	Explorer.Update = function(...)
		local began = os.clock()
		updateTree(...)
		if Main.Performance then
			Main.Performance.Record("explorer/update", os.clock() - began)
		end
	end
	Explorer.IsTreeContentPoint = function(x, y)
		local position = treeFrame.AbsolutePosition
		local size = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
		return x >= position.X and y >= position.Y and x < position.X + size.X and y < position.Y + size.Y
	end

	local function displayedRowAt(y)
		local layer = Explorer.TreeRenderer.Layer
		local i = math.floor((y - layer.AbsolutePosition.Y) / Explorer.RowHeight) + 1
		local entry = listEntries[i]
		if entry and entry.Visible and displayedNodes[entry] then
			return entry
		end
	end

	Explorer.IsEmptyPoint = function(x, y)
		local entry = displayedRowAt(y)
		if not entry then
			return true
		end
		local left = entry.AbsolutePosition.X + entry.Indent.Position.X.Offset
		return x < left
	end

	Explorer.SetObjectPicker = function(picker)
		objectPicker = picker
		Explorer.Window:SetTitle(picker and "Explorer - Select Parent" or "Explorer")
	end

	Explorer.DragRoots = function()
		local result = {}
		for _, node in ipairs(selection.List) do
			local ancestor, covered = node.Parent, false
			while ancestor do
				if selection.Map[ancestor] then
					covered = true
					break
				end
				ancestor = ancestor.Parent
			end
			if not covered then
				result[#result + 1] = node
			end
		end
		local positions = visibleIndices
		table.sort(result, function(a, b)
			return (positions[a] or math.huge) < (positions[b] or math.huge)
		end)
		return result
	end

	Explorer.CanDrop = function(roots, parent)
		if not parent or (parent.Inferred and not parent.Materialized) or not parent.Obj or parent.Obj == game then
			return false
		end
		for _, node in ipairs(roots) do
			if node.Inferred and not node.Materialized then
				return false
			end
			if node.Obj.Parent == game or node.Obj:IsA("Player") then
				return false
			end
			local ancestor = parent
			while ancestor do
				if ancestor == node then
					return false
				end
				ancestor = ancestor.Parent
			end
		end
		return #roots > 0
	end

	Explorer.SyncHistoryObject = function(obj, batchRemoval)
		if obj == game or Explorer.IsReadOnlyInferenceObject(obj) then
			return
		end
		local hidden = Apps.History and Apps.History.IsHidden(obj)
		local visible = not hidden and (obj:IsDescendantOf(game) or nilMap[obj])
		if not visible then
			local node = nodes[obj]
			local parent = node and node.Parent
			removeObject(obj)
			if parent then
				if batchRemoval then
					return true
				end
				local i = table.find(parent, node)
				if i then
					table.remove(parent, i)
				end
			end
		else
			local parent = obj.Parent
			if parent and not nodes[parent] then
				Explorer.SyncHistoryObject(parent)
			end
			if nodes[obj] then
				moveObject(obj)
			else
				addObject(obj)
			end
		end
	end

	Explorer.GetHistoryOrder = function(obj)
		return nodes[obj] and nodes[obj].ManualOrder
	end
	Explorer.SetHistoryOrder = function(obj, order)
		local node = nodes[obj]
		if node then
			if node.ManualOrder ~= order then
				changeSearchTree()
			end
			node.ManualOrder = order
			markSearchDirty(node, false)
			if node.Parent then
				node.Parent.Sorted = false
			end
		end
	end
	Explorer.CaptureHistorySelection = function()
		local objects = {}
		for _, node in ipairs(selection.List) do
			objects[#objects + 1] = node.Obj
		end
		return objects
	end
	Explorer.RestoreHistorySelection = function(objects)
		local selected = {}
		for _, obj in ipairs(objects) do
			Explorer.SyncHistoryObject(obj)
			local node = nodes[obj]
			if node and obj.Parent then
				selected[#selected + 1] = node
				Explorer.MakeNodeVisible(node)
			end
		end
		selection:SetTable(selected)
		Explorer.ForceUpdate()
	end
	local function readOrder(parents)
		local state = {}
		for parent in pairs(parents) do
			for _, node in ipairs(parent) do
				state[#state + 1] = { Obj = node.Obj, Order = node.ManualOrder }
			end
		end
		return state
	end
	local function applyOrder(state)
		local changed
		for _, item in ipairs(state) do
			local node = nodes[item.Obj]
			if node then
				changed = changed or node.ManualOrder ~= item.Order
				node.ManualOrder = item.Order
				if node.Parent then
					node.Parent.Sorted = false
				end
			end
		end
		if changed then
			changeSearchTree()
		end
	end

	Explorer.DropNodes = function(roots, target, mode, dropParent)
		return Apps.History.Run("Move objects", function()
			local parent = dropParent or (mode == "Inside" and target or target.Parent)
			if not Explorer.CanDrop(roots, parent) then
				return false
			end
			for _, node in ipairs(roots) do
				if node == target then
					return false
				end
			end
			local parents = { [parent] = true }
			for _, node in ipairs(roots) do
				if node.Parent then
					parents[node.Parent] = true
				end
			end
			local beforeOrder = readOrder(parents)
			local moved = {}
			for _, node in ipairs(roots) do
				local ok = pcall(function()
					Apps.History.Set(node.Obj, "Parent", parent.Obj)
				end)
				if ok then
					moveObject(node.Obj)
					moved[#moved + 1] = node
				end
			end
			if mode ~= "Inside" then
				for _, node in ipairs(moved) do
					local i = table.find(parent, node)
					if i then
						table.remove(parent, i)
					end
				end
				local anchor = target
				while anchor ~= parent and anchor.Parent and anchor.Parent ~= parent do
					anchor = anchor.Parent
				end
				local index = anchor == parent and 1 or (table.find(parent, anchor) or #parent)
				if anchor ~= parent and mode == "After" then
					index += 1
				end
				for i, node in ipairs(moved) do
					table.insert(parent, math.min(index + i - 1, #parent + 1), node)
				end
				for i, node in ipairs(parent) do
					node.ManualOrder = i
				end
				parent.Sorted = true
				changeSearchTree()
			else
				expanded[parent] = true
			end
			if #moved > 0 then
				Apps.History.Record(function()
					return readOrder(parents)
				end, applyOrder, beforeOrder, readOrder(parents), true)
			end
			Explorer.ForceUpdate()
			return #moved > 0
		end)
	end

	local function scrollAtEdge(x, y, dt, elapsed, glow, immediate)
		local pos = treeFrame.AbsolutePosition
		local size = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
		local canvas = treeFrame.CanvasPosition
		local state = glow.ScrollState
		if not state then
			state =
				{ x = canvas.X, y = canvas.Y, lastX = canvas.X, lastY = canvas.Y, dx = 0, dy = 0, ageX = 0, ageY = 0 }
			glow.ScrollState = state
		end
		local distance = y < pos.Y and pos.Y - y or (y > pos.Y + size.Y and y - pos.Y - size.Y or 0)
		local inColumn = x >= pos.X and x <= pos.X + size.X
		local active = inColumn and distance > 0
		local dx = 0
		local dy = active and (y < pos.Y and -1 or 1) or 0
		state.ageX = dx ~= 0 and dx == state.dx and state.ageX + dt or 0
		state.ageY = dy ~= 0 and dy == state.dy and state.ageY + dt or 0
		state.dx, state.dy = dx, dy
		if canvas.X ~= state.lastX or dx == 0 then
			state.x = canvas.X
		end
		if math.abs(canvas.Y - state.lastY) > 1 or dy == 0 then
			state.y = canvas.Y
		end
		local function advance(value, dir, age, maximum)
			local delay = immediate and 0 or 0.3
			if age < delay then
				return value
			end
			local speed = 32 + 1468 * math.min((age - delay) / 3, 1)
			return math.clamp(value + dir * speed * math.max(dt, 0), 0, math.max(0, maximum))
		end
		state.x = advance(state.x, dx, state.ageX, treeFrame.CanvasSize.X.Offset - size.X)
		state.y = advance(state.y, dy, state.ageY, treeFrame.CanvasSize.Y.Offset - size.Y)
		scrollV.SuppressEvents = true
		scrollH.SuppressEvents = true
		treeFrame.CanvasPosition = Vector2.new(state.x, state.y)
		scrollV.SuppressEvents = false
		scrollH.SuppressEvents = false
		local actual = treeFrame.CanvasPosition
		state.lastX, state.lastY = actual.X, actual.Y
		local moved = actual.X ~= canvas.X or actual.Y ~= canvas.Y
		if moved then
			local oldIndex = Explorer.Index
			scrollV.Index = math.floor(actual.Y / Explorer.RowHeight)
			scrollH.Index = math.floor(actual.X)
			Explorer.Index = scrollV.Index
			if Explorer.Index ~= oldIndex then
				Explorer.Refresh()
			end
		end
		glow.Update(
			actual.X,
			actual.Y - Explorer.Index * Explorer.RowHeight,
			size.X,
			size.Y,
			actual.Y == canvas.Y and 0 or dy,
			state.ageY
		)
		return moved
	end

	Explorer.StartDrag = function()
		if Explorer.Dragging then
			return
		end
		local roots = Explorer.DragRoots()
		if #roots == 0 then
			return
		end
		Explorer.Dragging = true
		local marker = Apps.DragDropIndicator.Create(Explorer.TreeRenderer)
		local glow = Apps.GradualEdgeScroll.Create(Explorer.TreeRenderer)
		local outline = marker.Outline
		local input = service.UserInputService
		local mouse = Main.Mouse or plr:GetMouse()
		local x, y = mouse.X, mouse.Y
		local target, mode, dropParent
		local hoverTarget, hoverTicket = nil, 0
		local connections = {}
		local function update()
			local previousHover = hoverTarget
			hoverTarget = nil
			target = nil
			dropParent = nil
			marker.Visible = false
			local pos, size = treeFrame.AbsolutePosition, treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
			if x < pos.X or x > pos.X + size.X or y < pos.Y or y > pos.Y + size.Y then
				return
			end
			local canvasY = y - pos.Y + treeFrame.CanvasPosition.Y - Explorer.Index * Explorer.RowHeight
			local row = math.floor(canvasY / Explorer.RowHeight) + 1
			local within = canvasY % Explorer.RowHeight
			local node, parent
			node, mode, parent = Policy.DropTarget(
				tree,
				row + Explorer.Index,
				within,
				x - pos.X + treeFrame.CanvasPosition.X,
				expanded,
				Explorer.EntryIndent
			)
			if not node then
				return
			end
			if not Explorer.CanDrop(roots, parent) or table.find(roots, node) then
				return
			end
			target, dropParent = node, parent
			local hoverKey = mode == "Inside" and node or nil
			hoverTarget = hoverKey
			if previousHover ~= hoverKey then
				hoverTicket += 1
				local ticket = hoverTicket
				if mode == "Inside" and not expanded[node] and #node > 0 then
					task.delay(0.5, function()
						if Explorer.Dragging and hoverTicket == ticket and target == node and mode == "Inside" then
							Explorer.SetExpanded(node, true, false)
							Explorer.ForceUpdate(false, true)
							update()
						end
					end)
				end
			end
			local viewport = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
			local indent = Explorer.EntryIndent * Explorer.NodeDepth(parent)
			local inside = mode == "Inside"
			local markerRow = rowIndex(node) - Explorer.Index
			marker.Position = UDim2.fromOffset(
				inside and scrollH.Index + 2 or indent,
				(markerRow - 1) * Explorer.RowHeight + (inside and 2 or Explorer.RowHeight - 1)
			)
			marker.Size = UDim2.fromOffset(
				math.max(0, viewport.X - (inside and 4 or math.max(0, indent - scrollH.Index))),
				inside and Explorer.RowHeight - 4 or 1
			)
			marker.BackgroundTransparency = mode == "Inside" and 1 or 0
			outline.Enabled = mode == "Inside"
			marker.Visible = true
		end
		local function finish(commit)
			if not Explorer.Dragging then
				return
			end
			Explorer.Dragging = false
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			Explorer.TreeRenderer:RemovePortal("DragDropIndicator")
			glow.Destroy()
			Explorer.SuppressRelease = true
			task.defer(function()
				Explorer.SuppressRelease = false
			end)
			if commit and target then
				Explorer.DropNodes(roots, target, mode, dropParent)
			end
		end
		connections[#connections + 1] = input.InputChanged:Connect(function(event)
			if
				event.UserInputType == Enum.UserInputType.MouseMovement
				or event.UserInputType == Enum.UserInputType.Touch
			then
				x, y = event.Position.X, event.Position.Y
				update()
			end
		end)
		connections[#connections + 1] = input.InputEnded:Connect(function(event)
			if
				event.UserInputType == Enum.UserInputType.MouseButton1
				or event.UserInputType == Enum.UserInputType.Touch
			then
				update()
				finish(true)
			end
		end)
		connections[#connections + 1] = input.InputBegan:Connect(function(event)
			if event.KeyCode == Enum.KeyCode.Escape then
				finish(false)
			end
		end)
		if service.RunService and service.RunService.RenderStepped then
			local elapsed = 0
			connections[#connections + 1] = service.RunService.RenderStepped:Connect(function(dt)
				elapsed += dt
				if scrollAtEdge(x, y, dt, elapsed, glow) then
					update()
				end
			end)
		end
		connections[#connections + 1] = Explorer.Window.OnDeactivate:Connect(function()
			finish(false)
		end)
		connections[#connections + 1] = Explorer.Window.OnMinimize:Connect(function()
			finish(false)
		end)
		update()
	end

	Explorer.StartBoxSelect = function(event, allowRow, baseSelection, currentPosition)
		if objectPicker or Explorer.BoxSelecting or Explorer.Dragging then
			return
		end
		local x, y = event.Position.X, event.Position.Y
		if not Explorer.IsTreeContentPoint(x, y) then
			return
		end
		if not allowRow and not Explorer.IsEmptyPoint(x, y) then
			return
		end
		Explorer.BoxSelecting = true
		local pos = treeFrame.AbsolutePosition
		local startX, startY = x - pos.X + treeFrame.CanvasPosition.X, y - pos.Y + treeFrame.CanvasPosition.Y
		local base = Lib.IsCtrlDown() and table.clone(baseSelection or selection.List) or {}
		local box = Apps.BoxSelectIndicator.Create(Explorer.TreeRenderer)
		local glow = Apps.GradualEdgeScroll.Create(Explorer.TreeRenderer)
		local connections = {}
		local previousFirst, previousLast, previousIntersects
		local function update(px, py)
			x, y = px, py
			local size = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
			local canvas = treeFrame.CanvasPosition
			local dx = math.clamp(px - pos.X, 0, size.X) + canvas.X
			local dy = math.clamp(py - pos.Y, 0, size.Y) + canvas.Y
			local left, right = math.min(startX, dx), math.max(startX, dx)
			local top, bottom = math.min(startY, dy), math.max(startY, dy)
			box.Position = UDim2.fromOffset(left, top - Explorer.Index * Explorer.RowHeight)
			box.Size = UDim2.fromOffset(right - left, bottom - top)
			local chosen = table.clone(base)
			local first = math.max(1, math.floor(top / Explorer.RowHeight) + 1)
			local last = math.min(#tree, math.ceil(bottom / Explorer.RowHeight))
			local intersects = canvas.X < right and canvas.X + size.X - 2 > left
			if first == previousFirst and last == previousLast and intersects == previousIntersects then
				return
			end
			previousFirst, previousLast, previousIntersects = first, last, intersects
			for i = first, last do
				local node = tree[i]
				if intersects then
					if expanded ~= Explorer.SearchExpanded or Explorer.Matches[node] then
						chosen[#chosen + 1] = node
					end
				end
			end
			selection:SetTable(chosen)
			Explorer.Refresh()
		end
		local function finish()
			if not Explorer.BoxSelecting then
				return
			end
			Explorer.BoxSelecting = false
			Explorer.SuppressRelease = true
			glow.Destroy()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			Explorer.TreeRenderer:RemovePortal("BoxSelectIndicator")
			task.defer(function()
				Explorer.SuppressRelease = false
			end)
		end
		connections[#connections + 1] = Main.TrackSignal(service.UserInputService.InputChanged, function(e)
			if e.UserInputType == Enum.UserInputType.MouseMovement or e.UserInputType == Enum.UserInputType.Touch then
				update(e.Position.X, e.Position.Y)
			end
		end)
		connections[#connections + 1] = Main.TrackSignal(service.UserInputService.InputEnded, function(e)
			if e.UserInputType == Enum.UserInputType.MouseButton1 or e.UserInputType == Enum.UserInputType.Touch then
				finish()
			end
		end)
		if service.RunService and service.RunService.RenderStepped then
			local elapsed = 0
			connections[#connections + 1] = service.RunService.RenderStepped:Connect(function(dt)
				elapsed += dt
				if scrollAtEdge(x, y, dt, elapsed, glow, true) then
					update(x, y)
				end
			end)
		end
		connections[#connections + 1] = Explorer.Window.OnDeactivate:Connect(finish)
		connections[#connections + 1] = Explorer.Window.OnMinimize:Connect(finish)
		update(currentPosition and currentPosition.X or x, currentPosition and currentPosition.Y or y)
	end

	local function overRowControl(entry)
		local insert, expand = entry.Insert, entry.Indent.Expand
		return (insert.Visible and Lib.CheckMouseInGui(insert)) or (expand.Visible and Lib.CheckMouseInGui(expand))
	end

	Explorer.NewListEntry = function(index)
		local newEntry = Explorer.TreeRenderer:NewRow(index)
		local function currentIndex()
			return table.find(listEntries, newEntry) or 0
		end
		newEntry.Position = UDim2.new(0, 0, 0, Explorer.RowHeight * (index - 1))
		Apps.TooltipActions.Bind(newEntry.Indent.StatusBadge, function()
			local node = displayedNodes[newEntry]
			if not node then
				return nil
			end
			local _, text = Apps.RowStatus.Resolve(node.Obj, node.Obj.ClassName)
			return text
		end, Explorer.TreeRenderer)

		newEntry.MouseEnter:Connect(function()
			Explorer.Refresh(currentIndex())
		end)
		newEntry.MouseLeave:Connect(function()
			Explorer.Refresh(currentIndex())
		end)

		newEntry.InputBegan:Connect(function(input)
			if objectPicker then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				if not Explorer.IsTreeContentPoint(input.Position.X, input.Position.Y) then
					return
				end
				if displayedRowAt(input.Position.Y) ~= newEntry then
					return
				end
				if overRowControl(newEntry) then
					return
				end
				if Explorer.IsEmptyPoint(input.Position.X, input.Position.Y) then
					Explorer.StartBoxSelect(input)
					return
				end
				local releaseEvent, mouseEvent

				local mouse = Main.Mouse or plr:GetMouse()
				local startX, startY

				if input.UserInputType == Enum.UserInputType.Touch then
					startX = input.Position.X
					startY = input.Position.Y
				else
					startX = mouse.X
					startY = mouse.Y
				end

				local listOffsetX = startX - treeFrame.AbsolutePosition.X
				local listOffsetY = startY - treeFrame.AbsolutePosition.Y
				local marquee = startX >= newEntry.Insert.AbsolutePosition.X + newEntry.Insert.AbsoluteSize.X
				local dragBase = table.clone(selection.List)

				releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
						releaseEvent:Disconnect()
						mouseEvent:Disconnect()
					end
				end)

				mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						local currentX, currentY

						if input.UserInputType == Enum.UserInputType.Touch then
							currentX = input.Position.X
							currentY = input.Position.Y
						else
							currentX = mouse.X
							currentY = mouse.Y
						end

						local deltaX = currentX - startX
						local deltaY = currentY - startY
						local dist = math.sqrt(deltaX ^ 2 + deltaY ^ 2)

						if dist > 7 then
							releaseEvent:Disconnect()
							mouseEvent:Disconnect()
							if marquee then
								Explorer.StartBoxSelect(
									{ Position = Vector2.new(startX, startY) },
									true,
									dragBase,
									Vector2.new(currentX, currentY)
								)
							else
								Explorer.StartDrag(listOffsetX, listOffsetY)
							end
						end
					end
				end)
			end
		end)

		newEntry.Indent.Expand.InputBegan:Connect(function(input)
			local node = displayedNodes[newEntry]
			if
				not node
				or (
					input.UserInputType ~= Enum.UserInputType.MouseMovement
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end
			newEntry.Indent.Expand.StudioChevron.ImageTransparency = 0
		end)

		newEntry.Indent.Expand.InputEnded:Connect(function(input)
			local node = displayedNodes[newEntry]
			if
				not node
				or (
					input.UserInputType ~= Enum.UserInputType.MouseMovement
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end
			newEntry.Indent.Expand.StudioChevron.ImageTransparency = 0.08
		end)

		newEntry.Indent.Expand.MouseButton1Down:Connect(function()
			local node = displayedNodes[newEntry]
			if
				not node
				or not Explorer.HasChildren(node)
				or displayedRowAt(Main.Mouse.Y) ~= newEntry
				or not Lib.CheckMouseInGui(newEntry.Indent.Expand)
			then
				return
			end

			local value = not expanded[node]
			Explorer.SetExpanded(node, value, Lib.IsShiftDown())
			if not Lib.IsShiftDown() then
				Explorer.ExpandSweepValue = value
				Explorer.ExpandSweepVisited = { [node] = true }
			end
			Explorer.Update(true)
			Explorer.Refresh()
		end)
		newEntry.Indent.Expand.MouseEnter:Connect(function()
			local value = Explorer.ExpandSweepValue
			local node = displayedNodes[newEntry]
			if value == nil or not Explorer.HasChildren(node) or Explorer.ExpandSweepVisited[node] then
				return
			end
			Explorer.ExpandSweepVisited[node] = true
			Explorer.SetExpanded(node, value, false)
			Explorer.ForceUpdate(false, true)
		end)

		newEntry.Insert.Activated:Connect(function(input)
			local node = displayedNodes[newEntry]
			local mouse = input and input.UserInputType == Enum.UserInputType.MouseButton1
			if
				node
				and not node.Del
				and (not mouse or (displayedRowAt(Main.Mouse.Y) == newEntry and Lib.CheckMouseInGui(newEntry.Insert)))
			then
				Explorer.OpenInsert(node, newEntry.Insert)
			end
		end)
		if not Explorer.TreeRenderer then
			newEntry.Parent = treeFrame
		end
		return newEntry
	end

	local rowIcons = setmetatable({}, { __mode = "k" })
	Explorer.UpdateRowIcon = function(entry, className, transparency, enabled, object)
		local iconClass, assetKey, folderTint = Apps.IconAppearance.Resolve(object, className)
		local tint = not enabled
				and Settings.Theme.TintDisabledIcons
				and (Settings.Theme.DisabledText or Color3.fromRGB(105, 106, 109))
			or folderTint
		local previous = rowIcons[entry]
		if
			previous
			and previous.className == iconClass
			and previous.assetKey == assetKey
			and previous.transparency == transparency
			and previous.tint == tint
		then
			return false
		end
		if not previous or previous.className ~= iconClass or previous.assetKey ~= assetKey then
			Explorer.DisplayClassIcon(entry.Indent.Icon, iconClass, assetKey)
		end
		local originals = previous and previous.originals or setmetatable({}, { __mode = "k" })
		for _, icon in ipairs(entry.Indent.Icon:GetDescendants()) do
			if icon:IsA("ImageLabel") then
				if originals[icon] == nil then
					originals[icon] = icon.ImageColor3 or Color3.new(1, 1, 1)
				end
				icon.ImageTransparency = transparency
				icon.ImageColor3 = tint or originals[icon]
			end
		end
		rowIcons[entry] = {
			className = iconClass,
			assetKey = assetKey,
			transparency = transparency,
			tint = tint,
			originals = originals,
		}
		return true
	end

	Explorer.ResolveHoveredNode = function(object)
		local node = object and nodes[object]
		local original = node
		if Explorer.Query and Explorer.Query ~= "" then
			while node and not visibleIndices[node] do
				node = node.Parent
			end
		else
			while node and not Explorer.IsNodeVisible(node) do
				node = node.Parent
			end
		end
		return node, node ~= nil and node ~= original
	end
	Explorer.SetHoveredObject = function(object)
		if Explorer.HoveredObject == object then
			return
		end
		local previous, previousWithin = Explorer.ResolveHoveredNode(Explorer.HoveredObject)
		Explorer.HoveredObject = object
		local nextNode, nextWithin = Explorer.ResolveHoveredNode(object)
		if previous == nextNode and previousWithin == nextWithin then
			return
		end
		Explorer.PerformRefresh()
	end

	local boundRows = setmetatable({}, { __mode = "k" })
	Explorer.Refresh = function(rowIndex)
		if Explorer.ScrollBarBorders then
			Explorer.ScrollBarBorders.Update()
		end
		local hoverBlocked = Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown() or false
		local popup = Explorer.GuiElems.HeaderPopup
		if popup and popup.Visible then
			hoverBlocked = true
		end
		local dialog = Apps.ServiceVisibilityDialog.Window
		if dialog and dialog.Closed == false then
			hoverBlocked = true
		end
		local readable, dragging = pcall(function()
			return treeFrame.DraggingScrollBar
		end)
		if readable and dragging ~= nil and dragging ~= Enum.DraggingScrollBar.None then
			hoverBlocked = true
		end
		local highlightMemo = {}
		local hasSelection = #selection.List > 0
		local function highlighted(node)
			if not hasSelection or not node then
				return false
			end
			local known = highlightMemo[node]
			if known ~= nil then
				return known
			end
			local trail = {}
			local result = false
			while node do
				local cached = highlightMemo[node]
				if cached ~= nil then
					result = cached
					break
				end
				trail[#trail + 1] = node
				if selection.Map[node] then
					result = true
					break
				end
				node = node.Parent
			end
			for _, ancestor in ipairs(trail) do
				highlightMemo[ancestor] = result
			end
			return result
		end
		local hiddenSelectionParents = {}
		local hoverNode, hoveredWithin
		if not hoverBlocked then
			hoverNode, hoveredWithin = Explorer.ResolveHoveredNode(Explorer.HoveredObject)
		end
		if Settings.Explorer.ExpandHierarchy == false then
			for _, selectedNode in ipairs(selection.List) do
				local parent = selectedNode
				while parent and not Explorer.IsNodeVisible(parent) do
					parent = parent.Parent
				end
				if parent and parent ~= selectedNode then
					hiddenSelectionParents[parent] = true
				end
			end
		end
		local treeSize = treeFrame.AbsoluteSize
		local scrollIndex, rowHeight = Explorer.Index, Explorer.RowHeight
		local maxNodes = math.min(math.max(math.ceil(treeSize.Y / rowHeight) + 1, 0), math.max(0, #tree - scrollIndex))
		if
			rowIndex
			and (#listEntries ~= maxNodes or displayedNodes[listEntries[rowIndex]] ~= tree[rowIndex + scrollIndex])
		then
			rowIndex = nil
		end
		local renameNodeVisible = false
		local visibleNodes
		if Explorer.TreeRenderer then
			Explorer.TreeRenderer:SetCanvasIndex(scrollIndex)
			Explorer.TreeRenderer:BeginFrame(maxNodes)
			if not rowIndex and (#listEntries == maxNodes or #listEntries == 0) then
				visibleNodes = table.create(maxNodes)
				for i = 1, maxNodes do
					visibleNodes[i] = tree[i + scrollIndex]
				end
				Explorer.TreeRenderer:BindNodes(visibleNodes)
				for i = 1, maxNodes do
					listEntries[i] = Explorer.TreeRenderer:NewRow(i)
				end
			end
		end

		local viewport = treeFrame.AbsoluteWindowSize or treeSize
		local scrollX = scrollH.Index
		local backgroundWidth = math.max(0, viewport.X - 2)
		local insertLimit = viewport.X - 22 + scrollX
		local rowSize =
			UDim2.fromOffset(math.max((Explorer.ViewWidth or 0) + Explorer.FreeWidth, treeSize.X), rowHeight)
		for i = rowIndex or 1, math.min(rowIndex or maxNodes, maxNodes) do
			local entry = listEntries[i]
			if not entry or not boundRows[entry] then
				entry = Explorer.NewListEntry(i)
				listEntries[i] = entry
				boundRows[entry] = true
				Explorer.ClickSystem:Add(entry)
			end

			local treeIndex = i + scrollIndex
			local node = if visibleNodes then visibleNodes[i] else tree[treeIndex]
			if searchView and node and (node.Del or node ~= nilNode and nodes[node.Obj] ~= node) then
				node = nil
			end
			displayedNodes[entry] = node
			if node then
				local obj = node.Obj
				local nodeDepth = (searchView and searchView:DepthOf(node) or Explorer.NodeDepth(node)) - 1
				local depth = Apps.NodeDetailsPlaceholder.IconLeft(nodeDepth)
				if Explorer.TreeRenderer then
					local selected = selection.Map[node]
					local context = highlighted(node.Parent)
					local hovered = not hoverBlocked
						and (Lib.CheckMouseInGui(entry) or (hoverNode == node and not hoveredWithin))
					local statusKey, statusText, statusDisabled = Apps.RowStatus.Resolve(obj, obj.ClassName)
					local enabled = Policy.IsEnabled(obj) and not statusDisabled
					local state = Policy.RowState(selected, context, hovered, enabled, Settings.Theme)
					local name = Policy.FormatName(searchView and searchView:NameOf(node) or tostring(obj))
					if node.MeasuredName ~= name then
						node.MeasuredName = name
						node.LabelWidth =
							getTextSize(service.TextService, name, 14, Enum.Font.BuilderSans, Vector2.new(10000, 30)).X
					end
					local joined = selected or context
					state.connectedAbove = joined and highlighted(tree[treeIndex - 1]) or false
					state.connectedBelow = joined and highlighted(tree[treeIndex + 1]) or false
					state.backgroundX = scrollX
					state.backgroundWidth = backgroundWidth
					state.name = name
					state.depth = depth
					state.height = rowHeight
					state.size = rowSize
					state.position = UDim2.fromOffset(0, rowHeight * (i - 1))
					state.labelWidth = math.max(4, node.LabelWidth)
					state.statusAsset = statusKey and Main.GetStudioAsset(statusKey) or nil
					state.statusText = statusText
					state.statusX = 21 + state.labelWidth + 4
					state.truncate = false
					state.expandHovered = not hoverBlocked and Lib.CheckMouseInGui(entry.Indent.Expand)
					state.guideCount = Settings.Explorer.IndentGuides and math.max(0, nodeDepth) or 0
					state.expanded = expanded[node] and expanded[node] ~= 0
					state.hasChildren = Explorer.HasChildren(node)
					state.renaming = node == renamingNode
					state.selectedWithin = hiddenSelectionParents[node] and true or false
					state.hoveredWithin = hoveredWithin and hoverNode == node or false
					state.insertVisible = (not node.Inferred or node.Materialized)
						and node ~= nilNode
						and Apps.InsertObjectOverlay.IsVisible(
							node,
							Explorer.InsertObjectOpenFor,
							hovered,
							Explorer.BoxSelecting or Explorer.Dragging or state.renaming
						)
					state.insertX = math.max(
						0,
						math.min(depth + 21 + node.LabelWidth + (state.statusAsset and 24 or 0), insertLimit)
					)
					if expanded == Explorer.SearchExpanded and not Explorer.Matches[node] and not selected then
						state.TextColor = Settings.Theme.PlaceholderText
					end
					Explorer.TreeRenderer:UpdateRow(entry, state)
					entry.Visible = true
					local className = node.Inferred and (node.InferredClass or "Instance") or obj.ClassName
					Explorer.UpdateRowIcon(entry, className, state.IconTransparency, enabled, obj)
					if state.renaming then
						renameNodeVisible = true
						renameBox.Visible = true
						local left = math.max(scrollX, depth + 21)
						renameBox.Position = UDim2.fromOffset(left - 4, state.position.Y.Offset)
						renameBox.Size = UDim2.fromOffset(math.max(4, viewport.X - (left - scrollX) + 2), rowHeight)
					end
					continue
				end
			else
				entry.Visible = false
			end
		end

		if not rowIndex and not renameNodeVisible then
			renameBox.Visible = false
		end

		for i = rowIndex and (#listEntries + 1) or (maxNodes + 1), #listEntries do
			displayedNodes[listEntries[i]] = nil
			Explorer.ClickSystem:Remove(listEntries[i])
			if Explorer.TreeRenderer then
				Explorer.TreeRenderer:DestroyRow(listEntries[i])
			else
				listEntries[i]:Destroy()
			end
			listEntries[i] = nil
		end
		if Explorer.TreeRenderer then
			Explorer.TreeRenderer:EndFrame()
		end
	end

	local function searchNeedsRefresh()
		if not searchView then
			return false
		end
		if searchView.Cold then
			return searchView.TreeVersion ~= searchTreeVersion
				or not Apps.SearchResults.MatchesVisibility(searchView.ColdLayout, characterSearch.Context.Visible)
		end
		return searchEngine:HasChanges() or searchView.State ~= searchEngine.Snapshots.State
	end

	Explorer.PerformUpdate = function(instant, incremental)
		if not incremental then
			table.clear(branchViews)
		end
		if updateDebounce and not instant then
			return
		end
		updateDebounce = true
		updateTicket += 1
		local ticket = updateTicket
		task.delay(instant and 0 or 0.1, function()
			if ticket ~= updateTicket or not updateDebounce then
				return
			end
			updateDebounce = false
			refreshDebounce = false
			refreshTicket += 1
			if not Explorer.Window:IsVisible() then
				return
			end
			if not (searchRefreshQueued and searchView and #searchView.MatchList > 8192) then
				Explorer.Update(true)
				Explorer.Refresh()
			end
		end)
	end

	Explorer.ForceUpdate = function(norefresh, incremental)
		if searchNeedsRefresh() and canRefreshDisplayedSearch() then
			Explorer.DoSearch(Explorer.Query)
			return
		end
		table.clear(branchViews)
		updateTicket += 1
		refreshTicket += 1
		updateDebounce, refreshDebounce = false, false
		Explorer.Update(incremental)
		if not norefresh then
			Explorer.Refresh()
		end
	end

	Explorer.PerformRefresh = function()
		if refreshDebounce or updateDebounce then
			return
		end
		refreshDebounce = true
		refreshTicket += 1
		local ticket = refreshTicket
		task.delay(0.1, function()
			if ticket ~= refreshTicket or not refreshDebounce then
				return
			end
			refreshDebounce = false
			if updateDebounce or not Explorer.Window:IsVisible() then
				return
			end
			Explorer.Refresh()
		end)
	end

	Explorer.IsNodeVisible = function(node)
		if not node then
			return
		end
		if searchView then
			return visibleIndices[node] ~= nil
		end
		local root = node
		while root.Parent and root.Parent.Obj ~= game do
			root = root.Parent
		end
		if root.Parent and root.Parent.Obj == game and not Apps.ServiceVisibility.IsVisible(root.Obj) then
			return false
		end

		local curNode = node.Parent
		while curNode do
			if not expanded[curNode] then
				return false
			end
			curNode = curNode.Parent
		end
		return true
	end

	Explorer.NodeDepth = function(node)
		local depth = 0

		if node == nilNode then
			return 1
		end

		local curNode = node.Parent
		while curNode do
			if curNode == nilNode then
				depth = depth + 1
			end
			curNode = curNode.Parent
			depth = depth + 1
		end
		return depth
	end

	Explorer.SetupConnections = function()
		if descendantAddedCon then
			descendantAddedCon:Disconnect()
		end
		if descendantRemovingCon then
			descendantRemovingCon:Disconnect()
		end
		if itemChangedCon then
			itemChangedCon:Disconnect()
		end
		Explorer.ConnectionRevision = (Explorer.ConnectionRevision or 0) + 1
		local revision = Explorer.ConnectionRevision
		local pending, scheduled = {}, false
		local function reconcile(obj, renamed)
			if Main.SelectionGeometryObjects and Main.SelectionGeometryObjects[obj] then
				return
			end
			pending[obj] = bit32.bor(pending[obj] or 0, renamed and 2 or 1)
			if scheduled then
				return
			end
			scheduled = true
			task.defer(function()
				if Main.Alive == false or revision ~= Explorer.ConnectionRevision then
					return
				end
				local batch = pending
				pending = {}
				scheduled = false
				local renamedVisible, needsPaint, removals = false, false, false
				for object, flags in pairs(batch) do
					if bit32.band(flags, 1) ~= 0 then
						needsPaint = Apps.RowStatus.Invalidate(object, "Parent") or needsPaint
						local ok, removed = pcall(Explorer.SyncHistoryObject, object, true)
						removals = removals or (ok and removed == true)
					end
					if flags >= 2 then
						local node = nodes[object]
						if node and Explorer.IsNodeVisible(node) then
							renamedVisible = true
						end
					end
				end
				if removals then
					Explorer.CleanDeletedChildren()
				end
				if Explorer.Window:IsVisible() then
					if renamedVisible and not (searchRefreshQueued and searchView) then
						Explorer.Update(true)
						Explorer.Refresh()
					elseif needsPaint then
						Explorer.Refresh()
					end
				end
			end)
		end
		descendantAddedCon = Main.TrackSignal(game.DescendantAdded, reconcile)
		descendantRemovingCon = Main.TrackSignal(game.DescendantRemoving, reconcile)
		local globalStatus = { ChatVersion = true, IsAutoMigrated = true, AuthorityMode = true }
		local function painted(object)
			local node = nodes[object]
			local index = node and visibleIndices[node]
			return index and index > Explorer.Index and index <= Explorer.Index + (scrollV.VisibleSpace or 0) + 2
		end
		local watchedProperties = { Parent = true, Name = true, Disabled = true, Visible = true, Enabled = true }
		for property in pairs(Apps.RowStatus.ChangedProperties) do
			watchedProperties[property] = true
		end
		for property in pairs(Apps.IconAppearance.ChangedProperties) do
			watchedProperties[property] = true
		end
		itemChangedCon = Main.TrackSignal(game.ItemChanged, function(obj, prop)
			if not watchedProperties[prop] or Main.SelectionGeometryObjects and Main.SelectionGeometryObjects[obj] then
				return
			end
			if Apps.RowStatus.ChangedProperties[prop] then
				Apps.RowStatus.Invalidate(obj, prop)
				if globalStatus[prop] or painted(obj) or (obj:IsA("PackageLink") and painted(obj.Parent)) then
					Explorer.PerformRefresh()
				end
			end
			if prop == "Parent" then
				reconcile(obj)
			elseif
				(
					prop == "Disabled"
					or prop == "Visible"
					or prop == "Enabled"
					or Apps.IconAppearance.ChangedProperties[prop]
				)
				and nodes[obj]
				and painted(obj)
			then
				Explorer.PerformRefresh()
			elseif prop == "Name" and nodes[obj] then
				changeSearchTree()
				nodes[obj].NameWidth = nil
				markSearchDirty(nodes[obj], false)
				if nodes[obj].Parent then
					nodes[obj].Parent.Sorted = false
				end
				reconcile(obj, true)
			end
		end)
	end

	Explorer.GetInsertName = function(parent, name)
		if not Settings.Explorer.IncrementNames or not parent:FindFirstChild(name) then
			return name
		end
		local base, suffix = name:match("^(.-)(%d+)$")
		base = base or name
		local digits = suffix and suffix:gsub("^0+", "") or ""
		repeat
			local at = #digits
			while at > 0 and digits:sub(at, at) == "9" do
				at -= 1
			end
			local zeros = string.rep("0", #digits - at)
			if at == 0 then
				digits = "1" .. zeros
			else
				digits = string.sub(digits, 1, at - 1) .. string.char(string.byte(digits, at) + 1) .. zeros
			end
		until not parent:FindFirstChild(base .. digits)
		return base .. digits
	end

	Explorer.ViewNode = function(node, nearest, cached)
		if not node then
			return
		end

		if not cached or not visibleIndices[node] then
			if Settings.Explorer.ExpandHierarchy ~= false then
				Explorer.MakeNodeVisible(node)
			end
			Explorer.ForceUpdate(true)
		end
		local visibleSpace = scrollV.VisibleSpace
		local index = visibleIndices[node]
		if index then
			local relative = index - 1
			if Explorer.Index > relative or Explorer.Index + visibleSpace - 1 <= relative then
				if nearest then
					scrollV.Index = Explorer.Index > relative and relative or relative - visibleSpace + 1
				else
					local inset = visibleSpace * 0.25
					if inset <= 1 then
						inset = 0
					end
					scrollV.Index = relative - inset
				end
			end
		end

		scrollV:Update()
		Explorer.Index = scrollV.Index
		Explorer.Refresh()
	end

	Explorer.ViewObj = function(obj)
		Explorer.ViewNode(nodes[obj])
	end
	Explorer.SelectService = function(object)
		if nodes[object] then
			selection:Set(nodes[object])
		end
	end
	local uniqueIdReader
	Explorer.GetReadableUniqueId = function(object)
		if not uniqueIdReader then
			uniqueIdReader = Apps.PropertyReader.Create({ TypeNames = {}, ReadHiddenProperty = env.gethiddenproperty })
		end
		local value = uniqueIdReader.Read({ Name = "UniqueId" }, object)
		return value ~= nil and tostring(value) or nil
	end
	Explorer.EditableRoots = function()
		local allowed, positions, result = {}, {}, {}
		for _, node in ipairs(selection.List) do
			if not Apps.ServiceVisibility.IsService(node.Obj) then
				allowed[node] = true
			end
		end
		for _, node in ipairs(selection.List) do
			if not allowed[node] then
				continue
			end
			local ancestor, covered = node.Parent, false
			while ancestor do
				if allowed[ancestor] then
					covered = true
					break
				end
				ancestor = ancestor.Parent
			end
			if not covered then
				result[#result + 1] = node
			end
		end
		positions = visibleIndices
		table.sort(result, function(a, b)
			return (positions[a] or math.huge) < (positions[b] or math.huge)
		end)
		return result
	end
	Explorer.HideSelectedServices = function()
		local roots = {}
		for _, node in ipairs(selection.List) do
			if Apps.ServiceVisibility.SetVisible(node.Obj, false) then
				roots[node] = true
			end
		end
		local keep = {}
		for _, node in ipairs(selection.List) do
			local root = node
			while root.Parent and root.Parent.Obj ~= game do
				root = root.Parent
			end
			if not roots[root] then
				keep[#keep + 1] = node
			end
		end
		selection:SetTable(keep)
		Explorer.CancelRename()
		Explorer.ForceUpdate()
	end

	Explorer.MakeNodeVisible = function(node, expandRoot)
		if not node then
			return
		end

		local hasExpanded = false

		if expandRoot and not expanded[node] then
			expanded[node] = true
			hasExpanded = true
		end

		local currentNode = node.Parent
		while currentNode do
			hasExpanded = true
			expanded[currentNode] = true
			currentNode = currentNode.Parent
		end

		if hasExpanded and not updateDebounce then
			coroutine.wrap(Explorer.PerformUpdate)(true)
		end
	end

	Explorer.ShowRightClick = function(MousePos, targetNode)
		local Mouse = MousePos or Main.Mouse
		local context = Explorer.RightClickContext
		local absoluteSize = context.Gui.AbsoluteSize
		context.MaxHeight = (absoluteSize.Y <= 600 and (absoluteSize.Y - 40)) or nil
		context:Clear()
		local selectedObject = #selection.List == 1 and selection.List[1].Obj
		local function appendPluginActions()
			if Apps.PluginActions then
				Apps.PluginActions.AddMenu(context, "Explorer", function()
					return Apps.PluginActions.ExplorerContext(selection.List, targetNode and targetNode.Obj)
				end)
			end
		end
		local stopPlayer = selectedObject
			and selectedObject:IsA("Player")
			and selectedObject.Character
			and Explorer.IsViewing(selectedObject.Character)
		local stopObject = selectedObject
			and (selectedObject:IsA("BasePart") or selectedObject:IsA("Model"))
			and Explorer.IsViewing(selectedObject)
		context.Registered.VIEW_PLAYER.Name = stopPlayer and "Stop Viewing Player" or "View Player"
		context.Registered.VIEW_OBJECT.Name = stopObject and "Stop Viewing Object" or "View Object"
		if Explorer.IsViewing() and not stopPlayer and not stopObject then
			context.Registered.STOP_VIEWING.Name = viewing.IsPlayer and "Stop Viewing Player" or "Stop Viewing Object"
			context:AddRegistered("STOP_VIEWING")
			context:QueueDivider()
		end
		local hasService, hasNonService = false, false
		for _, node in ipairs(selection.List) do
			if Apps.ServiceVisibility.IsService(node.Obj) then
				hasService = true
			else
				hasNonService = true
			end
		end

		if Explorer.HasInferredSelection() then
			context:Add({
				Name = "View inference evidence",
				OnClick = function()
					Apps.Reconstructor.Open()
				end,
			})
			if env.setclipboard then
				context:Add({
					Name = "Copy inferred paths",
					OnClick = function()
						local paths = {}
						for _, node in ipairs(selection.List) do
							if node.Inferred then
								paths[#paths + 1] = table.concat(node.Inferred.Path, ".")
							end
						end
						env.setclipboard(table.concat(paths, "\n"))
					end,
				})
			end
			appendPluginActions()
			context:Show(Mouse.X, Mouse.Y)
			return
		end
		context:AddRegistered("UNDO", not Apps.History.CanUndo())
		context:AddRegistered("REDO", not Apps.History.CanRedo())
		context:QueueDivider()
		if not hasService and not hasNonService then
			context:Add({
				Name = "Show Services…",
				OnClick = function()
					Apps.ServiceVisibilityDialog.Open()
				end,
			})
			Explorer.LastRightClickX, Explorer.LastRightClickY = Mouse.X, Mouse.Y
			appendPluginActions()
			context:Show(Mouse.X, Mouse.Y)
			return
		end

		local sList = table.clone(selection.List)
		local sMap = selection.Map
		local emptyClipboard = #clipboard == 0
		local presentClasses = {}
		local apiClasses = API.Classes

		for i = 1, #sList do
			local node = sList[i]
			local class = node.Class
			local obj = node.Obj

			if not presentClasses.isViableDecompileScript then
				presentClasses.isViableDecompileScript = env.isViableDecompileScript
					and env.isViableDecompileScript(obj)
			end
			if not class then
				class = obj.ClassName
				node.Class = class
			end

			local curClass = apiClasses[class]
			while curClass and not presentClasses[curClass.Name] do
				presentClasses[curClass.Name] = true
				curClass = curClass.Superclass
			end
		end

		if hasNonService then
			context:AddRegistered("CUT")
			context:AddRegistered("COPY")
		end
		if env.setclipboard then
			local copyItems = { table.clone(context.Registered.COPY_PATH) }
			copyItems[1].Name = "Path"
			if #sList == 1 and Explorer.GetReadableUniqueId(sList[1].Obj) then
				local unique = table.clone(context.Registered.COPY_UNIQUE_ID)
				unique.Name = "Unique ID"
				copyItems[#copyItems + 1] = unique
			end
			context:Add({ Name = "Copy As", Submenu = copyItems })
		end
		context:AddRegistered("PASTE", emptyClipboard or #sList == 0)
		if hasNonService then
			context:AddRegistered("DUPLICATE")
			context:AddRegistered("DELETE")
		end
		context:AddRegistered("DELETE_CHILDREN", #sList ~= 1)
		context:AddRegistered("RENAME", #sList ~= 1)

		context:AddDivider()
		if hasNonService then
			context:AddRegistered("GROUP")
			context:AddRegistered("GROUP_FOLDER")
			context:AddRegistered("UNGROUP", not (presentClasses.Model or presentClasses.Folder))
		end
		local function action(key, disabled)
			local item = table.clone(context.Registered[key])
			item.Disabled = disabled
			return item
		end
		context:QueueDivider()
		context:Add({
			Name = "Insert",
			Submenu = {
				action("INSERT_PART", not Apps.ReflectionService.CanCreate("Part")),
				action("INSERT_OBJECT", #sList ~= 1),
			},
		})
		local hierarchy = {}
		if hasNonService then
			hierarchy[#hierarchy + 1] = action("JUMP_TO_PARENT")
		end
		hierarchy[#hierarchy + 1] = action("SELECT_CHILDREN")
		hierarchy[#hierarchy + 1] = action("EXPAND_ALL")
		hierarchy[#hierarchy + 1] = action("COLLAPSE_ALL")
		if expanded == Explorer.SearchExpanded then
			hierarchy[#hierarchy + 1] = action("CLEAR_SEARCH_AND_JUMP_TO")
		end
		context:Add({ Name = "Hierarchy", Submenu = hierarchy })
		context:QueueDivider()
		context:Add({ Name = "Save / Export", Submenu = { action("SAVE_INST") } })
		context:AddRegistered("FIND_REFERENCES", #sList ~= 1)
		context:AddRegistered("VIEW_ACTIVITY", #sList ~= 1)
		if env.setclipboard then
			context:AddRegistered("COPY_API_PAGE")
		end

		context:QueueDivider()

		if not Apps.ExplorerQuickActions and presentClasses["BaseScript"] then
			local readable, anyEnabled = false, false
			for _, node in ipairs(sList) do
				if node.Obj:IsA("BaseScript") then
					local ok, disabled = pcall(function()
						return node.Obj.Disabled
					end)
					if ok and type(disabled) == "boolean" then
						readable = true
						anyEnabled = anyEnabled or not disabled
					end
				end
			end
			if readable then
				context.Registered.TOGGLE_SCRIPTS.Name = anyEnabled and "Disable Scripts" or "Enable Scripts"
				context:AddRegistered("TOGGLE_SCRIPTS")
			end
		end
		if presentClasses["BasePart"] or presentClasses["Model"] then
			context:AddRegistered("TELEPORT_TO")
			context:AddRegistered("VIEW_OBJECT")
			context:AddRegistered("3DVIEW_MODEL")
		end
		if presentClasses["Tween"] then
			context:AddRegistered("PLAY_TWEEN")
		end

		if presentClasses["TouchTransmitter"] then
			context:AddRegistered("FIRE_TOUCHTRANSMITTER", firetouchinterest == nil)
		end
		if presentClasses["ClickDetector"] then
			context:AddRegistered("FIRE_CLICKDETECTOR", fireclickdetector == nil)
		end
		if presentClasses["ProximityPrompt"] then
			context:AddRegistered("FIRE_PROXIMITYPROMPT", fireproximityprompt == nil)
		end

		local remoteClasses = {
			RemoteEvent = true,
			RemoteFunction = true,
			UnreliableRemoteEvent = true,
			BindableEvent = true,
			BindableFunction = true,
		}
		local hasRemote, allBlocked = false, true
		for _, node in ipairs(selection.List) do
			if remoteClasses[node.Obj.ClassName] then
				hasRemote = true
				if not remote_blocklist[node.Obj] then
					allBlocked = false
				end
			end
		end
		if hasRemote then
			context.Registered.BLOCK_REMOTE.Name = allBlocked and "Unblock From Firing" or "Block From Firing"
			context.Registered.BLOCK_REMOTE.Icon = allBlocked and "Play" or "Delete"
			context:AddRegistered("BLOCK_REMOTE", env.hookmetamethod == nil or type(getnamecallmethod) ~= "function")
		end

		if presentClasses["Player"] then
			context:AddRegistered("SELECT_CHARACTER")
			context:AddRegistered("VIEW_PLAYER")
		end
		if Apps.ExplorerQuickActions then
			Apps.ExplorerQuickActions.Add(context, selection)
		end
		if presentClasses["Players"] then
			context:AddRegistered("SELECT_LOCAL_PLAYER")
			context:AddRegistered("SELECT_ALL_CHARACTERS")
		end

		if presentClasses["LuaSourceContainer"] then
			local first = sList[1] and sList[1].Obj
			local generated = first and Apps.ModuleReconstruction and Apps.ModuleReconstruction.GetSource(first)
			context:AddRegistered(
				"VIEW_SCRIPT",
				not generated and (not presentClasses.isViableDecompileScript or env.decompile == nil)
			)
			context:AddRegistered(
				"DUMP_FUNCTIONS",
				not presentClasses.isViableDecompileScript or env.getupvalues == nil or env.getconstants == nil
			)
			context:AddRegistered(
				"SAVE_SCRIPT",
				not presentClasses.isViableDecompileScript or env.decompile == nil or env.writefile == nil
			)
			context:AddRegistered(
				"SAVE_BYTECODE",
				not presentClasses.isViableDecompileScript or env.getscriptbytecode == nil or env.writefile == nil
			)
		end

		if sMap[nilNode] then
			context:AddRegistered("REFRESH_NIL")
			context:AddRegistered("HIDE_NIL")
		end

		if hasService then
			context:QueueDivider()
			context:Add({
				Name = "Show Services…",
				OnClick = function()
					Apps.ServiceVisibilityDialog.Open()
				end,
			})
			context:Add({ Name = "Hide Service in Explorer", OnClick = Explorer.HideSelectedServices })
		end
		Explorer.LastRightClickX, Explorer.LastRightClickY = Mouse.X, Mouse.Y
		appendPluginActions()
		context:Show(Mouse.X, Mouse.Y)
	end

	Explorer.InitRightClick = function()
		local context = Apps.ContextMenu.new()
		context.Iconless = true
		context.Width = 162
		context:ApplyTheme({
			Compact = true,
			CornerRadius = 0,
			RowHeight = 22,
			TextSize = 12,
			TextInset = 29,
			ContentColor = Color3.fromRGB(25, 26, 31),
			HighlightColor = Color3.fromRGB(53, 55, 65),
			OutlineColor = Color3.fromRGB(43, 45, 54),
			DividerColor = Color3.fromRGB(32, 34, 39),
			TextColor = Color3.fromRGB(214, 216, 225),
			SubmenuImage = Main.GetStudioAsset("native/editor/submenu"),
		})
		local register = context.Register
		local edits = {
			CUT = true,
			PASTE = true,
			DUPLICATE = true,
			DELETE = true,
			DELETE_CHILDREN = true,
			GROUP = true,
			GROUP_FOLDER = true,
			UNGROUP = true,
			TOGGLE_SCRIPTS = true,
		}
		context.Register = function(self, key, data)
			if key == "COPY" then
				local callback = data.OnClick
				data.OnClick = function(...)
					if Explorer.HasInferredSelection() then
						return
					end
					return callback(...)
				end
			end
			if edits[key] then
				local callback = data.OnClick
				data.OnClick = function(...)
					if Explorer.HasInferredSelection() then
						return
					end
					return Apps.History.Run(data.Name, callback, ...)
				end
			end
			return register(self, key, data)
		end
		context:Register("UNDO", {
			Name = "Undo",
			Shortcut = "Ctrl+Z",
			OnClick = function()
				Apps.History.Undo()
			end,
		})
		context:Register("REDO", {
			Name = "Redo",
			Shortcut = "Ctrl+Y",
			OnClick = function()
				Apps.History.Redo()
			end,
		})

		context:Register("CUT", {
			Name = "Cut",
			IconMap = Explorer.MiscIcons,
			Icon = "Cut",
			DisabledIcon = "Cut_Disabled",
			Shortcut = "Ctrl+X",
			OnClick = function()
				local destroy, clone = game.Destroy, game.Clone
				local sList, newClipboard = Explorer.EditableRoots(), {}
				if #sList == 0 then
					return
				end
				local count = 1
				for i = 1, #sList do
					local inst = sList[i].Obj
					local s, cloned = pcall(clone, inst)
					if s and cloned then
						newClipboard[count] = cloned
						count = count + 1
					end
					pcall(Apps.History.Set, inst, "Parent", nil)
				end
				clipboard = newClipboard
				selection:Clear()
			end,
		})

		context:Register("COPY", {
			Name = "Copy",
			IconMap = Explorer.MiscIcons,
			Icon = "Copy",
			DisabledIcon = "Copy_Disabled",
			Shortcut = "Ctrl+C",
			OnClick = function()
				local clone = game.Clone
				local sList, newClipboard = Explorer.EditableRoots(), {}
				if #sList == 0 then
					return
				end
				local count = 1
				for i = 1, #sList do
					local inst = sList[i].Obj
					local s, cloned = pcall(clone, inst)
					if s and cloned then
						newClipboard[count] = cloned
						count = count + 1
					end
				end
				clipboard = newClipboard
			end,
		})

		context:Register("PASTE", {
			Name = "Paste Into",
			IconMap = Explorer.MiscIcons,
			Icon = "Paste",
			DisabledIcon = "Paste_Disabled",
			Shortcut = "Ctrl+Shift+V",
			OnClick = function()
				local sList = table.clone(selection.List)
				local newSelection = {}
				local count = 1
				for i = 1, #sList do
					local node = sList[i]
					local inst = node.Obj
					if Settings.Explorer.ExpandHierarchy ~= false then
						Explorer.MakeNodeVisible(node, true)
					end
					for c = 1, #clipboard do
						local cloned = clipboard[c]:Clone()
						if cloned then
							cloned.Name = Explorer.GetInsertName(inst, cloned.Name)
							Apps.History.Set(cloned, "Parent", inst)
							local clonedNode = nodes[cloned]
							if clonedNode then
								newSelection[count] = clonedNode
								count = count + 1
							end
						end
					end
				end
				selection:SetTable(newSelection)

				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				end
			end,
		})

		context:Register("DUPLICATE", {
			Name = "Duplicate",
			IconMap = Explorer.MiscIcons,
			Icon = "Copy",
			DisabledIcon = "Copy_Disabled",
			Shortcut = "Ctrl+D",
			OnClick = function()
				local clone = game.Clone
				local sList = Explorer.EditableRoots()
				if #sList == 0 then
					return
				end
				local newSelection = {}
				local count = 1
				for i = 1, #sList do
					local node = sList[i]
					local inst = node.Obj
					local instPar = node.Parent and node.Parent.Obj
					Explorer.MakeNodeVisible(node)
					local s, cloned = pcall(clone, inst)
					if s and cloned then
						if instPar then
							cloned.Name = Explorer.GetInsertName(instPar, cloned.Name)
						end
						Apps.History.Set(cloned, "Parent", instPar)
						local clonedNode = nodes[cloned]
						if clonedNode then
							newSelection[count] = clonedNode
							count = count + 1
						end
					end
				end

				selection:SetTable(newSelection)
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				end
			end,
		})

		context:Register("DELETE", {
			Name = "Delete",
			IconMap = Explorer.MiscIcons,
			Icon = "Delete",
			DisabledIcon = "Delete_Disabled",
			Shortcut = "Del",
			OnClick = function()
				local destroy = game.Destroy
				local sList = Explorer.EditableRoots()
				if #sList == 0 then
					return
				end
				for i = 1, #sList do
					pcall(Apps.History.Set, sList[i].Obj, "Parent", nil)
				end
				selection:Clear()
			end,
		})

		context:Register("DELETE_CHILDREN", {
			Name = "Delete Children",
			IconMap = Explorer.MiscIcons,
			Icon = "Delete",
			DisabledIcon = "Delete_Disabled",
			Shortcut = "Shift+Del",
			OnClick = function()
				local sList = table.clone(selection.List)
				for i = 1, #sList do
					for _, child in ipairs(sList[i].Obj:GetChildren()) do
						pcall(Apps.History.Set, child, "Parent", nil)
					end
				end
				selection:Clear()
			end,
		})
		context:Register("RENAME", {
			Name = "Rename",
			IconMap = Explorer.MiscIcons,
			Icon = "Rename",
			DisabledIcon = "Rename_Disabled",
			Shortcut = "F2",
			OnClick = function()
				local sList = table.clone(selection.List)
				if #sList == 1 then
					Explorer.SetRenamingNode(sList[1])
				end
			end,
		})

		context:Register("GROUP", {
			Name = "Group as Model",
			IconMap = Explorer.MiscIcons,
			Icon = "Group",
			DisabledIcon = "Group_Disabled",
			Shortcut = "Ctrl+G",
			OnClick = function()
				local sList = Explorer.EditableRoots()
				if #sList == 0 then
					return
				end

				local model = Instance.new("Model")
				Apps.History.Set(model, "Parent", sList[#sList].Obj.Parent)
				for i = 1, #sList do
					pcall(function()
						Apps.History.Set(sList[i].Obj, "Parent", model)
					end)
				end

				if nodes[model] then
					selection:Set(nodes[model])
					Explorer.ViewNode(nodes[model])
				end
			end,
		})

		context:Register("GROUP_FOLDER", {
			Name = "Group as Folder",
			Shortcut = "Ctrl+Alt+G",
			OnClick = function()
				local roots = Explorer.EditableRoots()
				if #roots == 0 then
					return
				end
				local parent = roots[#roots].Obj.Parent
				if not parent then
					return
				end
				local group = Instance.new("Folder")
				group.Name = Explorer.GetInsertName(parent, "Folder")
				Apps.History.Set(group, "Parent", parent)
				for _, node in ipairs(roots) do
					Apps.History.Set(node.Obj, "Parent", group)
				end
				Explorer.SyncHistoryObject(group)
				Explorer.RestoreHistorySelection({ group })
				Explorer.MakeNodeVisible(nodes[group], true)
			end,
		})

		context:Register("UNGROUP", {
			Name = "Ungroup",
			IconMap = Explorer.MiscIcons,
			Icon = "Ungroup",
			DisabledIcon = "Ungroup_Disabled",
			Shortcut = "Ctrl+U",
			OnClick = function()
				local groups = {}
				for _, node in ipairs(table.clone(selection.List)) do
					if
						not Apps.ServiceVisibility.IsService(node.Obj)
						and (node.Obj:IsA("Model") or node.Obj:IsA("Folder"))
					then
						groups[#groups + 1] = node.Obj
					end
				end
				if #groups == 0 then
					return
				end
				local function depth(obj)
					local n = 0
					while obj.Parent do
						n += 1
						obj = obj.Parent
					end
					return n
				end
				table.sort(groups, function(a, b)
					return depth(a) > depth(b)
				end)
				local objects = {}
				for _, group in ipairs(groups) do
					local parent = group.Parent
					if parent then
						for _, child in ipairs(group:GetChildren()) do
							Apps.History.Set(child, "Parent", parent)
							objects[#objects + 1] = child
						end
						Apps.History.Set(group, "Parent", nil)
					end
				end
				Explorer.RestoreHistorySelection(objects)
			end,
		})

		context:Register("SELECT_CHILDREN", {
			Name = "Select Children",
			IconMap = Explorer.MiscIcons,
			Icon = "SelectChildren",
			DisabledIcon = "SelectChildren_Disabled",
			OnClick = function()
				local newSelection = {}
				local count = 1
				local sList = table.clone(selection.List)

				for i = 1, #sList do
					local node = sList[i]
					for ind = 1, #node do
						local cNode = node[ind]
						if ind == 1 then
							Explorer.MakeNodeVisible(cNode)
						end

						newSelection[count] = cNode
						count = count + 1
					end
				end

				selection:SetTable(newSelection)
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				else
					Explorer.Refresh()
				end
			end,
		})

		context:Register("JUMP_TO_PARENT", {
			Name = "Jump to Parent",
			IconMap = Explorer.MiscIcons,
			Icon = "JumpToParent",
			OnClick = function()
				local newSelection = {}
				local count = 1
				local sList = table.clone(selection.List)

				for i = 1, #sList do
					local node = sList[i]
					if node.Parent then
						newSelection[count] = node.Parent
						count = count + 1
					end
				end

				selection:SetTable(newSelection)
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				else
					Explorer.Refresh()
				end
			end,
		})

		context:Register("TELEPORT_TO", {
			Name = "Teleport Here",
			IconMap = Explorer.MiscIcons,
			Icon = "TeleportTo",
			OnClick = function()
				local sList = table.clone(selection.List)
				local plrRP = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")

				if not plrRP then
					return
				end

				for _, node in next, sList do
					local Obj = node.Obj

					if Obj:IsA("BasePart") then
						if Obj.CanCollide then
							plr.Character:MoveTo(Obj.Position)
						else
							plrRP.CFrame = CFrame.new(Obj.Position + Settings.Explorer.TeleportToOffset)
						end
						break
					elseif Obj:IsA("Model") then
						if Obj.PrimaryPart then
							if Obj.PrimaryPart.CanCollide then
								plr.Character:MoveTo(Obj.PrimaryPart.Position)
							else
								plrRP.CFrame = CFrame.new(Obj.PrimaryPart.Position + Settings.Explorer.TeleportToOffset)
							end
							break
						else
							local part = Obj:FindFirstChildWhichIsA("BasePart", true)
							if part and nodes[part] then
								if part.CanCollide then
									plr.Character:MoveTo(part.Position)
								else
									plrRP.CFrame = CFrame.new(part.Position + Settings.Explorer.TeleportToOffset)
								end
								break
							elseif Obj.WorldPivot then
								plrRP.CFrame = Obj.WorldPivot
							end
						end
					end
				end
			end,
		})

		context:Register("PLAY_TWEEN", {
			Name = "Play Tween",
			IconMap = Explorer.MiscIcons,
			Icon = "Play",
			OnClick = function()
				local sList = table.clone(selection.List)

				for i = 1, #sList do
					local node = sList[i]
					local Obj = node.Obj

					if Obj:IsA("Tween") then
						Obj:Play()
					end
				end
			end,
		})

		context:Register("EXPAND_ALL", {
			Name = "Expand All",
			OnClick = function()
				local sList = table.clone(selection.List)

				local function expand(node)
					expanded[node] = true
					for i = 1, #node do
						if #node[i] > 0 then
							expand(node[i])
						end
					end
				end

				for i = 1, #sList do
					expand(sList[i])
				end

				Explorer.ForceUpdate()
			end,
		})

		context:Register("COLLAPSE_ALL", {
			Name = "Collapse All",
			OnClick = function()
				local sList = table.clone(selection.List)

				local function expand(node)
					expanded[node] = false
					for i = 1, #node do
						if #node[i] > 0 then
							expand(node[i])
						end
					end
				end

				for i = 1, #sList do
					expand(sList[i])
				end

				Explorer.ForceUpdate()
			end,
		})

		context:Register("CLEAR_SEARCH_AND_JUMP_TO", {
			Name = "Clear Search and Jump to",
			OnClick = function()
				local newSelection = {}
				local count = 1
				local sList = table.clone(selection.List)

				for i = 1, #sList do
					newSelection[count] = sList[i]
					count = count + 1
				end

				selection:SetTable(newSelection)
				Explorer.ClearSearch()
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				end
			end,
		})

		local clth = function(str)
			if str:sub(1, 28) == 'game:GetService("Workspace")' then
				str = str:gsub('game:GetService%("Workspace"%)', "workspace", 1)
			end
			if str:sub(1, 27 + #plr.Name) == 'game:GetService("Players").' .. plr.Name then
				str = str:gsub('game:GetService%("Players"%).' .. plr.Name, 'game:GetService("Players").LocalPlayer', 1)
			end
			return str
		end

		context:Register("COPY_PATH", {
			Name = "Copy Path",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 50,
			OnClick = function()
				local sList = table.clone(selection.List)
				if #sList == 1 then
					env.setclipboard(clth(Explorer.GetInstancePath(sList[1].Obj)))
				elseif #sList > 1 then
					local resList = { "{" }
					local count = 2
					for i = 1, #sList do
						local path = "\t" .. clth(Explorer.GetInstancePath(sList[i].Obj)) .. ","
						if #path > 0 then
							resList[count] = path
							count = count + 1
						end
					end
					resList[count] = "}"
					env.setclipboard(table.concat(resList, "\n"))
				end
			end,
		})

		context:Register("COPY_UNIQUE_ID", {
			Name = "Copy Unique ID",
			OnClick = function()
				if type(env.setclipboard) ~= "function" or #selection.List ~= 1 then
					return
				end
				local id = Explorer.GetReadableUniqueId(selection.List[1].Obj)
				if id then
					env.setclipboard(id)
				end
			end,
		})
		context:Register("TOGGLE_SCRIPTS", {
			Name = "Toggle Scripts",
			OnClick = function()
				local scripts, disable = {}, false
				for _, node in ipairs(selection.List) do
					if node.Obj:IsA("BaseScript") then
						local ok, current = pcall(function()
							return node.Obj.Disabled
						end)
						if ok and type(current) == "boolean" then
							scripts[#scripts + 1] = node.Obj
							disable = disable or not current
						end
					end
				end
				for _, object in ipairs(scripts) do
					Apps.History.Set(object, "Disabled", disable)
				end
			end,
		})
		context:Register("INSERT_PART", {
			Name = "Insert Part",
			OnClick = function()
				if #selection.List == 0 or not Apps.ReflectionService.CanCreate("Part") then
					return
				end
				local created = Apps.InsertionService.Insert("Part", table.clone(selection.List), {
					DefaultProperties = Explorer.DefaultProps,
					GetName = Explorer.GetInsertName,
					Reveal = function(node)
						if Settings.Explorer.ExpandHierarchy ~= false then
							Explorer.MakeNodeVisible(node, true)
						end
					end,
				})
				local selected = {}
				for _, object in ipairs(created) do
					Explorer.SyncHistoryObject(object)
					if nodes[object] then
						selected[#selected + 1] = nodes[object]
					end
				end
				selection:SetTable(selected)
				if selected[1] then
					Explorer.ViewNode(selected[1])
				end
			end,
		})

		context:Register("INSERT_OBJECT", {
			Name = "Insert Object",
			IconMap = Explorer.MiscIcons,
			Icon = "InsertObject",
			OnClick = function()
				local mouse = Main.Mouse
				local x, y = Explorer.LastRightClickX or mouse.X, Explorer.LastRightClickY or mouse.Y
				Explorer.InsertObjectContext:Show(x, y)
			end,
		})

		context:Register("FIND_REFERENCES", {
			Name = "Find References",
			OnClick = function()
				local selected = selection.List[1]
				if selected then
					Apps.ReferenceFinder.Open(selected.Obj)
				end
			end,
		})
		context:Register("VIEW_ACTIVITY", {
			Name = "View Activity",
			OnClick = function()
				local selected = selection.List[1]
				if selected then
					Apps.ActivityViewer.Open(selected.Obj)
				end
			end,
		})
		context:Register("SAVE_INST", {
			Name = "Save to File",
			IconMap = Explorer.MiscIcons,
			Icon = "Save",
			OnClick = function()
				local sList = table.clone(selection.List)
				if #sList == 1 then
					Lib.SaveAsPrompt(
						"Place_"
							.. game.PlaceId
							.. "_"
							.. sList[1].Obj.ClassName
							.. "_"
							.. sList[1].Obj.Name
							.. "_"
							.. os.time(),
						function(filename)
							env.saveinstance(sList[1].Obj, filename, {
								Decompile = true,
								RemovePlayerCharacters = false,
							})
						end
					)
				elseif #sList > 1 then
					for i = 1, #sList do
						Lib.SaveAsPrompt(
							"Place_"
								.. game.PlaceId
								.. "_"
								.. sList[i].Obj.ClassName
								.. "_"
								.. sList[i].Obj.Name
								.. "_"
								.. os.time(),
							function(filename)
								env.saveinstance(sList[i].Obj, filename, {
									Decompile = true,
									RemovePlayerCharacters = false,
								})
							end
						)

						task.wait(0.1)
					end
				end
			end,
		})

		local ClassFire = {
			RemoteEvent = "FireServer",
			RemoteFunction = "InvokeServer",
			UnreliableRemoteEvent = "FireServer",

			BindableEvent = "Fire",
			BindableFunction = "Invoke",
		}
		local remoteHooked = false
		context:Register("BLOCK_REMOTE", {
			Name = "Block From Firing",
			IconMap = Explorer.MiscIcons,
			Icon = "Delete",
			DisabledIcon = "Empty",
			OnClick = function()
				local targets = {}
				local allBlocked = true
				for _, node in ipairs(selection.List) do
					local obj = node.Obj
					if ClassFire[obj.ClassName] then
						targets[#targets + 1] = obj
						if not remote_blocklist[obj] then
							allBlocked = false
						end
					end
				end
				if #targets == 0 then
					return
				end
				if not allBlocked and not remoteHooked then
					local old
					old = env.hookmetamethod((oldgame or game), "__namecall", function(self, ...)
						if remote_blocklist[self] and getnamecallmethod() == ClassFire[self.ClassName] then
							return nil
						end
						return old(self, ...)
					end)
					remoteHooked = true
				end
				for _, obj in ipairs(targets) do
					remote_blocklist[obj] = not allBlocked or nil
					if Settings.RemoteBlockWriteAttribute then
						pcall(obj.SetAttribute, obj, "IsBlocked", not allBlocked)
					end
				end
			end,
		})
		Main.AddCleanup(function()
			table.clear(remote_blocklist)
		end)

		context:Register("COPY_API_PAGE", {
			Name = "Copy Roblox API Page URL",
			IconMap = Explorer.MiscIcons,
			Icon = "Reference",
			OnClick = function()
				local sList = table.clone(selection.List)
				if #sList == 1 then
					env.setclipboard(
						"https://create.roblox.com/docs/reference/engine/classes/" .. sList[1].Obj.ClassName
					)
				end
			end,
		})

		context:Register("3DVIEW_MODEL", {
			Name = "3D Preview Object",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 54,
			OnClick = function()
				local sList = table.clone(selection.List)
				local isa = game.IsA

				if #sList == 1 then
					if isa(sList[1].Obj, "BasePart") or isa(sList[1].Obj, "Model") then
						ModelViewer.ViewModel(sList[1].Obj)
						return
					end
				end
			end,
		})

		context:Register("VIEW_OBJECT", {
			Name = "View Object",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 5,
			OnClick = function()
				local sList = table.clone(selection.List)
				local isa = game.IsA

				for i = 1, #sList do
					local node = sList[i]

					if isa(node.Obj, "BasePart") or isa(node.Obj, "Model") then
						if #sList == 1 and Explorer.IsViewing(node.Obj) then
							Explorer.StopViewing()
						else
							Explorer.StartViewing(node.Obj)
						end
						break
					end
				end
			end,
			OnRightClick = function()
				Explorer.StopViewing()
			end,
		})

		context:Register("VIEW_SCRIPT", {
			Name = "View Script",
			IconMap = Explorer.MiscIcons,
			Icon = "ViewScript",
			DisabledIcon = "Empty",
			OnClick = function()
				local scr = selection.List[1] and selection.List[1].Obj
				local generated = scr and Apps.ModuleReconstruction and Apps.ModuleReconstruction.GetSource(scr)
				if not generated and (Explorer.HasInferredSelection() or Explorer.HasReconstructedSelection()) then
					return
				end
				if scr then
					ScriptViewer.ViewScript(scr)
				end
			end,
		})
		context:Register("DUMP_FUNCTIONS", {
			Name = "Dump Functions",
			IconMap = Explorer.MiscIcons,
			Icon = "SelectChildren",
			DisabledIcon = "Empty",
			OnClick = function()
				if Explorer.HasInferredSelection() or Explorer.HasReconstructedSelection() then
					return
				end
				local scr = selection.List[1] and selection.List[1].Obj
				if scr then
					ScriptViewer.DumpFunctions(scr)
				end
			end,
		})

		if Apps.ExplorerQuickActions then
			Apps.ExplorerQuickActions.Register(context, selection)
		end

		context:Register("VIEW_SCRIPT", {
			Name = "View Script",
			IconMap = Explorer.MiscIcons,
			Icon = "ViewScript",
			DisabledIcon = "Empty",
			OnClick = function()
				local scr = selection.List[1] and selection.List[1].Obj
				local generated = scr and Apps.ModuleReconstruction and Apps.ModuleReconstruction.GetSource(scr)
				if not generated and (Explorer.HasInferredSelection() or Explorer.HasReconstructedSelection()) then
					return
				end
				if scr then
					ScriptViewer.ViewScript(scr)
				end
			end,
		})

		context:Register("SAVE_SCRIPT", {
			Name = "Save Script",
			IconMap = Explorer.MiscIcons,
			Icon = "Save",
			DisabledIcon = "Empty",
			OnClick = function()
				if Explorer.HasInferredSelection() or Explorer.HasReconstructedSelection() then
					return
				end
				for _, v in next, selection.List do
					if v.Obj:IsA("LuaSourceContainer") and env.isViableDecompileScript(v.Obj) then
						local success, source = pcall(env.decompile, v.Obj)
						if not success or not source then
							source = ("-- DEX - %s failed to decompile %s"):format(env.executor, v.Obj.ClassName)
						end
						local fileName = ("%s_%s_%i_Source.txt"):format(
							env.parsefile(v.Obj.Name),
							v.Obj.ClassName,
							game.PlaceId
						)
						Lib.SaveAsPrompt(fileName, source)

						task.wait(0.2)
					end
				end
			end,
		})

		context:Register("SAVE_BYTECODE", {
			Name = "Save Script Bytecode",
			IconMap = Explorer.MiscIcons,
			Icon = "Save",
			DisabledIcon = "Empty",
			OnClick = function()
				if Explorer.HasInferredSelection() or Explorer.HasReconstructedSelection() then
					return
				end
				for _, v in next, selection.List do
					if v.Obj:IsA("LuaSourceContainer") and env.isViableDecompileScript(v.Obj) then
						local success, bytecode = pcall(env.getscriptbytecode, v.Obj)
						if success and type(bytecode) == "string" then
							local fileName = ("%s_%s_%i_Bytecode.txt"):format(
								env.parsefile(v.Obj.Name),
								v.Obj.ClassName,
								game.PlaceId
							)
							Lib.SaveAsPrompt(fileName, bytecode)
							task.wait(0.2)
						end
					end
				end
			end,
		})

		context:Register("SELECT_CHARACTER", {
			Name = "Select Character",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 9,
			OnClick = function()
				local newSelection = {}
				local count = 1
				local sList = table.clone(selection.List)
				local isa = game.IsA

				for i = 1, #sList do
					local node = sList[i]
					if isa(node.Obj, "Player") and nodes[node.Obj.Character] then
						newSelection[count] = nodes[node.Obj.Character]
						count = count + 1
					end
				end

				selection:SetTable(newSelection)
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				else
					Explorer.Refresh()
				end
			end,
		})

		context:Register(
			"STOP_VIEWING",
			{ Name = "Stop Viewing", IconMap = Explorer.LegacyClassIcons, Icon = 5, OnClick = Explorer.StopViewing }
		)
		context:Register("VIEW_PLAYER", {
			Name = "View Player",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 5,
			OnClick = function()
				local newSelection = {}
				local count = 1
				local sList = table.clone(selection.List)
				local isa = game.IsA

				for i = 1, #sList do
					local node = sList[i]
					local Obj = node.Obj
					if Obj:IsA("Player") and Obj.Character then
						if #sList == 1 and Explorer.IsViewing(Obj.Character) then
							Explorer.StopViewing()
						else
							Explorer.StartViewing(Obj.Character, true)
						end
						break
					end
				end
			end,
		})

		context:Register("SELECT_LOCAL_PLAYER", {
			Name = "Select Local Player",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 9,
			OnClick = function()
				pcall(function()
					if nodes[plr] then
						selection:Set(nodes[plr])
						Explorer.ViewNode(nodes[plr])
					end
				end)
			end,
		})

		context:Register("SELECT_ALL_CHARACTERS", {
			Name = "Select All Characters",
			IconMap = Explorer.LegacyClassIcons,
			Icon = 2,
			OnClick = function()
				local newSelection = {}
				local sList = table.clone(selection.List)

				for i, v in next, service.Players:GetPlayers() do
					if v.Character and nodes[v.Character] then
						if i == 1 then
							Explorer.MakeNodeVisible(v.Character)
						end
						table.insert(newSelection, nodes[v.Character])
					end
				end

				selection:SetTable(newSelection)
				if #newSelection > 0 then
					Explorer.ViewNode(newSelection[1])
				else
					Explorer.Refresh()
				end
			end,
		})

		context:Register("REFRESH_NIL", {
			Name = "Refresh Nil Instances",
			OnClick = function()
				Explorer.RefreshNilInstances()
			end,
		})

		context:Register("HIDE_NIL", {
			Name = "Hide Nil Instances",
			OnClick = function()
				Explorer.HideNilInstances()
			end,
		})

		Explorer.RightClickContext = context
	end

	Explorer.HideNilInstances = function()
		local previous = nilMap
		nilMap = {}
		for obj in pairs(nilCons) do
			unwatchNil(obj)
		end
		local roots = {}
		for i = 1, #nilNode do
			local node = nilNode[i]
			if node and node.Obj then
				roots[#roots + 1] = node.Obj
			end
		end
		for _, obj in ipairs(roots) do
			if obj.Parent == nil then
				removeObject(obj)
			else
				pcall(Explorer.SyncHistoryObject, obj)
			end
		end
		for i = #nilNode, 1, -1 do
			nilNode[i] = nil
		end
		for obj in pairs(previous) do
			pcall(Explorer.SyncHistoryObject, obj)
		end
		nodes[nilNode.Obj] = nil
		Explorer.NilLoaded = false
		Explorer.Expanded[nilNode] = false
		Explorer.FinishNilRefresh()
	end

	Explorer.FinishNilRefresh = function()
		local kept = {}
		for _, node in ipairs(selection.List) do
			if node == nilNode or nodes[node.Obj] == node then
				kept[#kept + 1] = node
			end
		end
		if #kept ~= #selection.List then
			selection:SetTable(kept)
		end
		if Explorer.Query and Explorer.Query ~= "" and canRefreshDisplayedSearch() then
			Explorer.DoSearch(Explorer.Query)
		else
			Explorer.ForceUpdate()
		end
	end

	Explorer.RefreshNilInstances = function()
		if Settings.Explorer.ShowNilInstances == false then
			return false
		end
		if type(env.getnilinstances) ~= "function" then
			Explorer.NilError = "This environment does not support Nil Instances."
			return false
		end
		local ok, nilInsts = pcall(env.getnilinstances)
		if not ok or type(nilInsts) ~= "table" then
			Explorer.NilError = "Unable to refresh Nil Instances. Try again."
			return false
		end
		local nextMap, roots, seen = {}, {}, {}
		for _, obj in pairs(nilInsts) do
			local valid, descendants = pcall(function()
				if obj == game or obj == nilNode.Obj or not game.IsA(obj, "Instance") or obj.Parent ~= nil then
					return
				end
				if Apps.History and Apps.History.IsHidden(obj) then
					return
				end
				return getDescendants(obj)
			end)
			if valid and descendants and not seen[obj] then
				seen[obj] = true
				roots[#roots + 1] = obj
				nextMap[obj] = true
				for _, child in ipairs(descendants) do
					nextMap[child] = true
				end
			end
		end
		local previous = nilMap
		nilMap = nextMap
		nodes[nilNode.Obj] = nilNode
		changeSearchTree()
		for obj in pairs(nilCons) do
			if not nextMap[obj] then
				unwatchNil(obj)
			end
		end
		for obj in pairs(previous) do
			if not nextMap[obj] then
				pcall(Explorer.SyncHistoryObject, obj)
			end
		end
		for _, obj in ipairs(roots) do
			if nodes[obj] then
				moveObject(obj)
			else
				addObject(obj)
			end
		end
		for obj in pairs(nextMap) do
			if nodes[obj] then
				moveObject(obj)
			else
				addObject(obj)
			end
			watchNil(obj)
		end
		if not Explorer.NilLoaded then
			Explorer.Expanded[nilNode] = true
		end
		Explorer.NilLoaded, Explorer.NilError = true, nil
		Explorer.FinishNilRefresh()
		return true
	end

	Explorer.InitNilInstances = function()
		if Settings.Explorer.ShowNilInstances == false then
			Explorer.NilLoaded = false
			Explorer.Expanded[nilNode] = false
			return
		end
		if type(env.getnilinstances) == "function" then
			nodes[nilNode.Obj] = nilNode
			Explorer.RefreshNilInstances()
		end
	end

	Explorer.GetInstancePath = Apps.InstancePath.Build

	Explorer.SyncInferredTree = Apps.ExplorerInferenceOverlay.Create({
		Explorer = Explorer,
		Nodes = nodes,
		EnsureNode = addObject,
		MarkDirty = markSearchDirty,
		Changed = function()
			changeSearchTree()
			if Explorer.Query and Explorer.Query ~= "" then
				task.defer(function()
					if Main.Alive and Explorer.Query and Explorer.Query ~= "" and canRefreshDisplayedSearch() then
						Explorer.DoSearch(Explorer.Query)
					end
				end)
			end
		end,
	})

	Explorer.DefaultProps = {
		["BasePart"] = {
			Position = function(Obj)
				local Player = service.Players.LocalPlayer
				if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
					Obj.Position = (Player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -10)).p
				end
				return Obj.Position
			end,
			Anchored = true,
		},
		["GuiObject"] = {
			Position = function(Obj)
				return (Obj.Parent:IsA("ScreenGui") and UDim2.new(0.5, 0, 0.5, 0)) or Obj.Position
			end,
			Active = true,
		},
	}

	Explorer.InitInsertObject = function()
		Explorer.InsertObjectContext = Apps.InsertObjectMenu.Create({
			GetIconData = function()
				return iconData
			end,
			GetTarget = function()
				return Explorer.InsertObjectOpenFor
			end,
			GetSelection = function()
				return Explorer.Selection.List
			end,
			DefaultProperties = Explorer.DefaultProps,
			GetName = Explorer.GetInsertName,
			ClassIcons = Explorer.ClassIcons,
			Reveal = function(node)
				if Settings.Explorer.ExpandHierarchy ~= false then
					Explorer.MakeNodeVisible(node, true)
				end
			end,
			OnClosed = function()
				Explorer.InsertObjectOpenFor = nil
				Explorer.Refresh()
			end,
		})
	end

	Explorer.SearchFilters = {
		Comparison = {
			["isa"] = function(argString)
				local lower = string.lower
				local find = string.find
				local classQuery = string.split(argString)[1]
				if not classQuery then
					return
				end
				classQuery = lower(classQuery)

				local className
				for class, _ in pairs(API.Classes) do
					local cName = lower(class)
					if cName == classQuery then
						className = class
						break
					elseif find(cName, classQuery, 1, true) then
						className = class
					end
				end
				if not className then
					return
				end

				return {
					Headers = { "local isa = game.IsA" },
					Predicate = "isa(obj,'" .. className .. "')",
				}
			end,
			["remotes"] = function(argString)
				return {
					Headers = { "local isa = game.IsA" },
					Predicate = "isa(obj,'RemoteEvent') or isa(obj,'RemoteFunction') or isa(obj,'UnreliableRemoteFunction')",
				}
			end,
			["bindables"] = function(argString)
				return {
					Headers = { "local isa = game.IsA" },
					Predicate = "isa(obj,'BindableEvent') or isa(obj,'BindableFunction')",
				}
			end,
			["rad"] = function(argString)
				local num = tonumber(argString)
				if not num then
					return
				end

				if
					not service.Players.LocalPlayer.Character
					or not service.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
					or not service.Players.LocalPlayer.Character.HumanoidRootPart:IsA("BasePart")
				then
					return
				end

				return {
					Headers = {
						"local isa = game.IsA",
						"local hrp = service.Players.LocalPlayer.Character.HumanoidRootPart",
					},
					Setups = { "local hrpPos = hrp.Position" },
					ObjectDefs = { "local isBasePart = isa(obj,'BasePart')" },
					Predicate = "(isBasePart and (obj.Position-hrpPos).Magnitude <= " .. num .. ")",
				}
			end,
		},
		Specific = {
			["players"] = function()
				return function()
					return service.Players:GetPlayers()
				end
			end,
			["loadedmodules"] = function()
				return env.getloadedmodules
			end,
		},
		Default = function(argString, caseSensitive)
			local cleanString = argString:gsub('"', '\\"'):gsub("\n", "\\n")
			if caseSensitive then
				return {
					Headers = { "local find = string.find" },
					ObjectDefs = { "local objName = tostring(obj)" },
					Predicate = 'find(objName,"' .. cleanString .. '",1,true)',
				}
			else
				return {
					Headers = { "local lower = string.lower", "local find = string.find", "local tostring = tostring" },
					ObjectDefs = { "local lowerName = lower(tostring(obj))" },
					Predicate = 'find(lowerName,"' .. cleanString:lower() .. '",1,true)',
				}
			end
		end,
		SpecificDefault = function(n)
			return {
				Headers = {},
				ObjectDefs = { "local isSpec" .. n .. " = specResults[" .. n .. "][node]" },
				Predicate = "isSpec" .. n,
			}
		end,
	}

	Explorer.BuildSearchFunc = function(query)
		local specFilterList, specMap = {}, {}
		local finalPredicate = ""
		local rep = string.rep
		local formatQuery = query:gsub("\\.", "  "):gsub('".-"', function(str)
			return rep(" ", #str)
		end)
		local headers = {}
		local objectDefs = {}
		local setups = {}
		local find = string.find
		local sub = string.sub
		local lower = string.lower
		local match = string.match
		local ops = {
			["("] = "(",
			[")"] = ")",
			["||"] = " or ",
			["&&"] = " and ",
		}
		local filterCount = 0
		local compFilters = Explorer.SearchFilters.Comparison
		local specFilters = Explorer.SearchFilters.Specific
		local init = 1
		local lastOp = nil

		local function processFilter(dat)
			if dat.Headers then
				local t = dat.Headers
				for i = 1, #t do
					headers[t[i]] = true
				end
			end

			if dat.ObjectDefs then
				local t = dat.ObjectDefs
				for i = 1, #t do
					objectDefs[t[i]] = true
				end
			end

			if dat.Setups then
				local t = dat.Setups
				for i = 1, #t do
					setups[t[i]] = true
				end
			end

			finalPredicate = finalPredicate .. dat.Predicate
		end

		local found = {}
		local foundData = {}
		local find = string.find
		local sub = string.sub

		local function findAll(str, pattern)
			local count = #found + 1
			local init = 1
			local sz = #pattern
			local x, y, extra = find(str, pattern, init, true)
			while x do
				found[count] = x
				foundData[x] = { sz, pattern }

				count = count + 1
				init = y + 1
				x, y, extra = find(str, pattern, init, true)
			end
		end
		local start = tick()
		findAll(formatQuery, "&&")
		findAll(formatQuery, "||")
		findAll(formatQuery, "(")
		findAll(formatQuery, ")")
		table.sort(found)
		table.insert(found, #formatQuery + 1)

		local function inQuotes(str)
			local len = #str
			if sub(str, 1, 1) == '"' and sub(str, len, len) == '"' then
				return sub(str, 2, len - 1)
			end
		end

		for i = 1, #found do
			local nextInd = found[i]
			local nextData = foundData[nextInd] or { 1 }
			local op = ops[nextData[2]]
			local term = sub(query, init, nextInd - 1)
			term = match(term, "^%s*(.-)%s*$") or ""

			if #term > 0 then
				if sub(term, 1, 1) == "!" then
					term = sub(term, 2)
					finalPredicate = finalPredicate .. "not "
				end

				local qTerm = inQuotes(term)
				if qTerm then
					processFilter(Explorer.SearchFilters.Default(qTerm, true))
				else
					local x, y = find(term, "%S+")
					if x then
						local first = sub(term, x, y)
						local specifier = sub(first, 1, 1) == "/" and lower(sub(first, 2))
						local compFunc = specifier and compFilters[specifier]
						local specFunc = specifier and specFilters[specifier]

						if compFunc then
							local argStr = sub(term, y + 2)
							local ret = compFunc(inQuotes(argStr) or argStr)
							if ret then
								processFilter(ret)
							else
								finalPredicate = finalPredicate .. "false"
							end
						elseif specFunc then
							local argStr = sub(term, y + 2)
							local ret = specFunc(inQuotes(argStr) or argStr)
							if ret then
								if not specMap[term] then
									specFilterList[#specFilterList + 1] = ret
									specMap[term] = #specFilterList
								end
								processFilter(Explorer.SearchFilters.SpecificDefault(specMap[term]))
							else
								finalPredicate = finalPredicate .. "false"
							end
						else
							processFilter(Explorer.SearchFilters.Default(term))
						end
					end
				end
			end

			if op then
				finalPredicate = finalPredicate .. op
				if op == "(" and (#term > 0 or lastOp == ")") then
					return
				else
					lastOp = op
				end
			end
			init = nextInd + nextData[1]
		end

		local finalSetups = ""
		local finalHeaders = ""
		local finalObjectDefs = ""

		for setup, _ in next, setups do
			finalSetups = finalSetups .. setup .. "\n"
		end
		for header, _ in next, headers do
			finalHeaders = finalHeaders .. header .. "\n"
		end
		for oDef, _ in next, objectDefs do
			finalObjectDefs = finalObjectDefs .. oDef .. "\n"
		end

		local template = [==[
local searchResults = searchResults
local nodes = nodes
local expandTable = Explorer.SearchExpanded
local specResults = specResults
local service = service

%s
local function search(root)	
%s
	
	local expandedpar = false
	for i = 1,#root do
		local node = root[i]
		local obj = node.Obj
		
%s
		
		if %s then
			expandTable[node] = 0
			searchResults[node] = true
			Explorer.Matches[node] = true
			if not expandedpar then
				local parnode = node.Parent
				while parnode and (not searchResults[parnode] or expandTable[parnode] == 0) do
					expandTable[parnode] = true
					searchResults[parnode] = true
					parnode = parnode.Parent
				end
				expandedpar = true
			end
		end
		
		if #node > 0 then search(node) end
	end
end
return search]==]

		local funcStr = template:format(finalHeaders, finalSetups, finalObjectDefs, finalPredicate)
		local s, func = pcall(loadstring, funcStr)
		if not s or not func then
			return nil, specFilterList
		end

		local env = setmetatable({
			["searchResults"] = searchResults,
			["nodes"] = nodes,
			["Explorer"] = Explorer,
			["specResults"] = specResults,
			["service"] = service,
		}, { __index = getfenv() })
		setfenv(func, env)

		return func(), specFilterList
	end

	local function revealSelectedNodesInNormalTree()
		if not selection or not Explorer.Expanded then
			return
		end
		for _, selectedNode in ipairs(selection.List) do
			local parent = selectedNode and selectedNode.Parent
			while parent do
				Explorer.Expanded[parent] = true
				parent = parent.Parent
			end
		end
	end

	local function getSearchExitFocusNode()
		if not selection then
			return nil
		end
		local pivot = selection.Piviot
		if pivot and selection.Map[pivot] and not pivot.Del then
			return pivot
		end
		for _, selectedNode in ipairs(selection.List) do
			if selectedNode and not selectedNode.Del then
				return selectedNode
			end
		end
	end

	local restoredSearch = function(query, provisional)
		local searchStarted = os.clock()
		searchGeneration += 1
		local generation, revision = searchGeneration, Explorer.SearchRevision
		if Main.Elevated and query:match("^%s*/") then
			if Explorer.SetSearchBusy then
				Explorer.SetSearchBusy(false, query)
			end
			Explorer.DoLegacySearch(query)
			return true
		end

		local predicate, queryError
		if #query > 0 then
			predicate, queryError = Apps.SearchQuery.Compile(query)
		end
		if Explorer.SetSearchBusy then
			Explorer.SetSearchBusy(predicate ~= nil, query)
		end
		local results, matches, expandTable
		local attempts = 0
		local function current()
			return generation == searchGeneration and revision == Explorer.SearchRevision
		end
		local function cancelled()
			if generation == searchGeneration and Explorer.SetSearchBusy then
				Explorer.SetSearchBusy(false, query)
			end
			return false
		end
		repeat
			results, matches, expandTable = {}, {}, setmetatable({}, { __mode = "k" })
			if not predicate then
				break
			end
			local version = searchTreeVersion
			local deadline = os.clock() + 0.004
			local roots = { nodes[game] }
			if Settings.Explorer.ShowNilInstances ~= false then
				roots[#roots + 1] = nilNode
			end
			local complete = Apps.SearchQuery.Scan(roots, predicate, results, matches, expandTable, function()
				if
					(
						Main.Performance and not Main.Performance.Available()
						or not Main.Performance and os.clock() >= deadline
					) and attempts < 2
				then
					task.wait()
					deadline = os.clock() + 0.004
				end
				return current() and version == searchTreeVersion
			end, { Revision = version, Incremental = true })
			if not current() then
				return cancelled()
			end
			if complete then
				break
			end
			attempts += 1
		until false

		if not current() then
			return cancelled()
		end
		local leavingSearch = #query == 0 and Explorer.Query and Explorer.Query ~= ""
		local focusNode = leavingSearch and getSearchExitFocusNode() or nil
		if leavingSearch then
			revealSelectedNodesInNormalTree()
		end
		if Explorer.Query ~= query and not leavingSearch then
			scrollV.Index = 0
			Explorer.Index = 0
		end
		retainedSearchQuery = provisional and query or nil
		searchResults, Explorer.Matches, Explorer.SearchExpanded = results, matches, expandTable
		Explorer.SearchError, Explorer.Query = queryError, query
		if Explorer.SetSearchBusy then
			Explorer.SetSearchBusy(false, query)
		end
		expanded = #query == 0 and Explorer.Expanded or expandTable
		searchFunc = predicate
				and function(root)
					Apps.SearchQuery.Scan({ root }, predicate, results, matches, expandTable)
				end
			or nil
		if focusNode then
			Explorer.ViewNode(focusNode, true)
		else
			Explorer.ForceUpdate()
		end
		if Main.Performance then
			Main.Performance.Record("explorer/search", os.clock() - searchStarted)
		end
		return true
	end

	local function exitSearchView()
		retainedSearchQuery = nil
		if not searchView then
			return
		end
		searchView = nil
		Explorer.SearchView = nil
		if searchEngine then
			searchEngine.LastResult, searchEngine.LastTerms = nil, nil
		end
		tree, visibleIndices = normalTree, normalIndices
		Explorer.MatchList = {}
		Explorer.Matches = {}
		Explorer.SearchExpanded = setmetatable({}, { __mode = "k" })
		projection.Valid = false
	end
	startSearchWidths = function(view)
		if view.ExactWidth or not canRefreshDisplayedSearch() then
			return
		end
		local revision = view.WidthRevision
		if view.MeasuringRevision == revision then
			return
		end
		view.MeasuringRevision = revision
		local searchRevision = Explorer.SearchRevision
		task.defer(function()
			local function current()
				return Main.Alive ~= false
					and searchView == view
					and revision == view.WidthRevision
					and searchRevision == Explorer.SearchRevision
					and canRefreshDisplayedSearch()
			end
			local deadline = os.clock() + 0.001
			local stopped = {}
			local function checkpoint()
				if not current() then
					error(stopped, 0)
				end
				if os.clock() >= deadline then
					task.wait()
					while current() and not Explorer.Window:IsVisible() do
						task.wait(0.1)
					end
					if not current() then
						error(stopped, 0)
					end
					deadline = os.clock() + 0.001
				end
			end
			local ok, maximum = pcall(function()
				return view:MeasureWidths(function(entry)
					local node = entry.Node
					local width = node.SearchRawName == entry.Name and node.NameWidth or nil
					local reusable = true
					if not width then
						local name = Policy.FormatName(entry.Name)
						width = widthRecent[name] or widthPrevious[name]
						if not width then
							local readable, measured = pcall(
								getTextSize,
								service.TextService,
								name,
								14,
								Enum.Font.BuilderSans,
								Vector2.new(math.huge, 20)
							)
							width = readable and measured.X or math.min(100, #name) * 14
							reusable = readable
							if readable then
								rememberWidth(name, width)
							end
						end
						if reusable and node.SearchRawName == entry.Name then
							node.NameWidth = width
						end
					end
					checkpoint()
					return width, reusable
				end, checkpoint)
			end)
			if ok and current() then
				view.Width = maximum
				view.ExactWidth = true
				view:RememberStats(maximum, view.Depth, true)
				Explorer.MaxNameWidth = maximum
				Explorer.ViewWidth = Explorer.EntryIndent * math.max(0, view.Depth - 1) + maximum + 41
				Explorer.UpdateView()
			end
			if view.MeasuringRevision == revision then
				view.MeasuringRevision = nil
			end
		end)
	end
	local function ensureSearchEngine()
		if searchEngine then
			return searchEngine
		end
		searchEngine = Apps.ExplorerSearch.Create({
			Roots = function()
				local roots = { nodes[game] }
				if env.getnilinstances and Settings.Explorer.ShowNilInstances ~= false then
					roots[#roots + 1] = nilNode
				end
				return roots
			end,
			Sorting = function()
				return sortingEnabled
			end,
			Scope = function()
				return env.getnilinstances and Settings.Explorer.ShowNilInstances ~= false
			end,
			Alive = function()
				return Main.Alive ~= false
			end,
			Wait = function()
				task.wait()
			end,
			Visible = function(node)
				return node == nilNode or Apps.ServiceVisibility.IsVisible(node.Obj)
			end,
			Object = Apps.SearchQuery.Object,
			Read = function(node)
				local index = Apps.SearchQuery.NameIndex
				local name = index and index.CachedName and index.CachedName(node) or node.Obj.Name
				node.SearchRawName = name
				local class = node.Class
				return name, class, class and explorerOrders[class], node.Id
			end,
			Metadata = function(entry)
				local node = entry.Node
				local class = node.Class or node.Obj.ClassName
				node.Class = class
				local order = explorerOrders[class]
				if not order then
					order = RMD.Classes[class] and tonumber(RMD.Classes[class].ExplorerOrder) or 9999
					explorerOrders[class] = order
				end
				entry.Class, entry.Order = class, order
			end,
		})
		Explorer.SearchEngine = searchEngine
		return searchEngine
	end
	local function getSearchNilRoot()
		return env.getnilinstances and Settings.Explorer.ShowNilInstances ~= false and nilNode or nil
	end
	characterSearch.Context = {
		Name = coldName,
		Children = coldChildren,
		VisibleOnly = true,
		Object = Apps.SearchQuery.Object,
		Visible = function(node)
			return node == nilNode or Apps.ServiceVisibility.IsVisible(node.Obj)
		end,
	}
	function characterSearch.IsLarge()
		return (Explorer.InitialObjectCount or 0) + #nilNode > 8192
			or searchEngine and searchEngine.Snapshots.State and searchEngine.Snapshots.State.Live > 8192
	end
	function characterSearch.Ready(nilRoot)
		if
			characterSearch.Version == searchTreeVersion
			and characterSearch.Sorter == Explorer.NodeSorter
			and characterSearch.NilRoot == nilRoot
			and Apps.SearchResults.MatchesVisibility(characterSearch.Layout, characterSearch.Context.Visible)
		then
			return characterSearch.Layout
		end
	end
	function characterSearch.Schedule()
		if
			characterSearch.Pending
			or Main.Alive == false
			or not Explorer.Active
			or not characterSearch.IsLarge()
			or characterSearch.FailedVersion == searchTreeVersion
		then
			return
		end
		local ready = characterSearch.Ready(getSearchNilRoot())
		if ready and ready.Characters then
			return
		end
		characterSearch.Pending = true
		local version = searchTreeVersion
		task.delay(0.5, function()
			if Main.Alive == false or not Explorer.Active then
				characterSearch.Pending = false
				return
			end
			if version ~= searchTreeVersion or not canRefreshDisplayedSearch() or searchEngine and searchEngine.Busy then
				characterSearch.Pending = false
				characterSearch.Schedule()
				return
			end

			local nilRoot = getSearchNilRoot()
			local sorter = Explorer.NodeSorter
			local roots = { nodes[game], nilRoot }
			local context = characterSearch.Context
			context.Estimate = Explorer.InitialObjectCount
			local function current()
				return Main.Alive ~= false
					and Explorer.Active
					and searchTreeVersion == version
					and Explorer.NodeSorter == sorter
					and getSearchNilRoot() == nilRoot
			end
			local started = os.clock()
			local deadline = started + 0.002
			local cancelled = {}
			local function checkpoint()
				if not current() then
					error(cancelled, 0)
				end
				if os.clock() >= deadline or not canRefreshDisplayedSearch() or searchEngine and searchEngine.Busy then
					local elapsed = task.wait()
					if elapsed and elapsed > 1 / 30 and current() then
						task.wait()
					end
					while current() and (not canRefreshDisplayedSearch() or searchEngine and searchEngine.Busy) do
						task.wait(0.1)
					end
					if not current() then
						error(cancelled, 0)
					end
					deadline = os.clock() + 0.002
				end
			end
			local ok, layout = pcall(function()
				local previous = characterSearch.Ready(nilRoot)
					or searchView and searchView.TreeVersion == version and searchView.ColdLayout
				if not previous or previous.NilRoot ~= nilRoot then
					previous = Apps.SearchResults.CreateLayout(roots, context, checkpoint)
				end
				if not current() then
					error(cancelled, 0)
				end
				characterSearch.Layout = previous
				characterSearch.Version = version
				characterSearch.Sorter = sorter
				characterSearch.NilRoot = nilRoot
				Apps.SearchResults.PrepareCharacters(previous, checkpoint)
				return previous
			end)
			characterSearch.Pending = false
			if ok and current() then
				if Main.Performance then
					Main.Performance.Record("explorer/search-character-index", os.clock() - started)
				end
			elseif not ok and layout ~= cancelled then
				characterSearch.FailedVersion = version
			end
			characterSearch.Schedule()
		end)
	end
	local maintenanceScheduled = false
	scheduleIndexMaintenance = function()
		if maintenanceScheduled then
			return
		end
		maintenanceScheduled = true
		task.delay(1, function()
			maintenanceScheduled = false
			if Main.Alive ~= false and searchEngine and searchEngine:HasChanges() then
				if searchEngine.Busy or not canRefreshDisplayedSearch() then
					scheduleIndexMaintenance()
				else
					pcall(function()
						searchEngine:Warm()
					end)
				end
			end
		end)
	end
	scheduleSearchRefresh = function()
		if searchRefreshQueued or not searchView or autoUpdateSearch == false or not canRefreshDisplayedSearch() then
			return
		end
		searchRefreshQueued = true
		task.delay(0.35, function()
			searchRefreshQueued = false
			if Main.Alive ~= false and searchNeedsRefresh() and canRefreshDisplayedSearch() then
				Explorer.DoSearch(Explorer.Query)
			end
		end)
	end
	local function publishSearchView(view, query, current, started)
		local sameQuery = Explorer.Query == query
		local source = sameQuery and searchView or nil
		local previousOverrides = source and source.Overrides
			or retainedSearchQuery == query and Explorer.SearchExpanded
			or nil
		local cancelled = {}
		local deadline = os.clock() + 0.002
		local function checkpoint()
			if not current() then
				error(cancelled, 0)
			end
			if os.clock() >= deadline then
				task.wait()
				deadline = os.clock() + 0.002
			end
			if not current() then
				error(cancelled, 0)
			end
		end
		local ok, problem = pcall(function()
			local work = 0
			local function tick()
				work += 1
				if work % 128 == 0 then
					checkpoint()
				end
			end
			if not view.Cold then
				for node in pairs(searchEngine.Snapshots.Pending) do
					if node.Del then
						view:Remove(node)
					end
					tick()
				end
			end
			repeat
				local revision = source and source.OverrideRevision
				if previousOverrides then
					local copied = {}
					for node, value in pairs(previousOverrides) do
						if (source or value == false) and not node.Del and view:Contains(node) then
							view.Expanded[node] = value
							copied[node] = true
						end
						tick()
					end
					for node in pairs(view.Overrides) do
						if not copied[node] then
							view.Expanded[node] = nil
						end
						tick()
					end
				end
				view:Reflow(checkpoint)
				if not current() then
					error(cancelled, 0)
				end
			until not source or source.OverrideRevision == revision
		end)
		if not ok then
			if problem == cancelled then
				return false
			end
			error(problem, 0)
		end
		if not sameQuery then
			scrollV.Index = 0
			Explorer.Index = 0
		end
		updateTicket += 1
		refreshTicket += 1
		updateDebounce, refreshDebounce = false, false
		retainedSearchQuery = nil
		searchView = view
		Explorer.SearchView = view
		tree, visibleIndices = view.Rows, view.Indices
		searchResults, Explorer.Matches, Explorer.MatchList = view.Matches, view.Matches, view.MatchList
		expanded, Explorer.SearchExpanded = view.Expanded, view.Expanded
		Explorer.Query, Explorer.SearchError = query, nil
		projection.Valid = false
		searchFunc = function()
			scheduleSearchRefresh()
		end
		Explorer.SetSearchBusy(false, query)
		Explorer.MaxNameWidth, Explorer.MaxDepth = view.Width, view.Depth
		Explorer.ViewWidth = Explorer.EntryIndent * math.max(0, view.Depth - 1) + view.Width + 41
		startSearchWidths(view)
		Explorer.UpdateSearchStatus()
		Explorer.UpdateView()
		Explorer.Refresh()
		if searchNeedsRefresh() then
			scheduleSearchRefresh()
		end
		if started and Main.Performance then
			Main.Performance.Record("explorer/search", os.clock() - started)
		end
		return true
	end

	local pendingPreparation, activePreparation, preparationRunning
	local function prepareSearch(query)
		if Explorer.Query ~= query or not canRefreshDisplayedSearch() then
			return
		end
		if (pendingPreparation and pendingPreparation.Generation == searchGeneration)
			or (activePreparation and activePreparation.Generation == searchGeneration)
		then
			return
		end
		pendingPreparation = { Query = query, Generation = searchGeneration, Revision = Explorer.SearchRevision }
		if preparationRunning then
			return
		end
		preparationRunning = true
		task.defer(function()
			local ok, problem = pcall(function()
				while Main.Alive ~= false and pendingPreparation do
					local request = pendingPreparation
					pendingPreparation = nil
					activePreparation = request
					local function current()
						return Main.Alive ~= false
							and searchGeneration == request.Generation
							and Explorer.SearchRevision == request.Revision
							and Explorer.Query == request.Query
							and canRefreshDisplayedSearch()
					end
					local predicate = current() and Apps.SearchQuery.Compile(request.Query)
					if predicate and current() then
						local started = os.clock()
						local view = searchEngine:Search(predicate, Apps.SearchQuery.LiteralTerms(predicate), current)
						if view and current() then
							local published = publishSearchView(view, request.Query, current)
							if published and Main.Performance then
								Main.Performance.Record("explorer/search-prepare", os.clock() - started)
							end
						end
					end
					activePreparation = nil
				end
			end)
			preparationRunning = false
			activePreparation = nil
			if not ok and Main.Performance then
				Main.Performance.Record("explorer/search-prepare-failure", 0)
			end
		end)
	end
	Explorer.DoSearch = function(query)
		Explorer.SearchInputPending = false
		pendingPreparation = nil
		if #query == 0 or Main.Elevated and query:match("^%s*/") then
			retainedSearchQuery = nil
			if searchEngine then
				searchEngine.Generation += 1
			end
			exitSearchView()
			return restoredSearch(query)
		end
		local started = os.clock()
		searchGeneration += 1
		local generation, revision = searchGeneration, Explorer.SearchRevision
		local function current()
			return Main.Alive ~= false and generation == searchGeneration and revision == Explorer.SearchRevision
		end
		local predicate = Apps.SearchQuery.Compile(query)
		if not predicate then
			exitSearchView()
			return restoredSearch(query)
		end
		local engine = ensureSearchEngine()
		local terms = Apps.SearchQuery.LiteralTerms(predicate)
		local nilRoot = getSearchNilRoot()
		local refreshing = searchView ~= nil and Explorer.Query == query
		local layout = searchView and searchView.TreeVersion == searchTreeVersion and searchView.ColdLayout
			or characterSearch.Ready(nilRoot)
		if layout and layout.NilRoot ~= nilRoot then
			layout = nil
		end
		if layout and not Apps.SearchResults.MatchesVisibility(layout, characterSearch.Context.Visible) then
			layout = nil
		end
		if terms and layout and Explorer.Query == query then
			Explorer.SetSearchBusy(false, query)
			Explorer.Update()
			Explorer.Refresh()
			return true
		end
		local large = characterSearch.IsLarge()
		local roots = { nodes[game], nilRoot }
		if large and not terms then
			Explorer.SetSearchBusy(true, query)
			local context = characterSearch.Context
			context.Estimate = Explorer.InitialObjectCount
			local changed = {}
			local className = Apps.SearchQuery.ClassFilter(predicate)
			local matchNode = Apps.SearchQuery.ClassNodeMatcher(predicate)
			for _ = 1, 2 do
				local version = searchTreeVersion
				local sorter = Explorer.NodeSorter
				local function exact()
					return current()
						and searchTreeVersion == version
						and Explorer.NodeSorter == sorter
						and getSearchNilRoot() == nilRoot
				end
				local deadline = os.clock() + 0.006
				local function checkpoint()
					if os.clock() >= deadline then
						task.wait()
						deadline = os.clock() + 0.006
					end
					if not exact() then
						error(changed, 0)
					end
				end
				local ok, view = pcall(
					Apps.SearchResults.CreatePredicate,
					characterSearch.Ready(nilRoot) or layout,
					predicate,
					context,
					checkpoint,
					roots,
					matchNode,
					className
				)
				if not current() then
					if generation == searchGeneration then
						Explorer.SetSearchBusy(false, query)
					end
					return false
				end
				if ok and exact() then
					view.TreeVersion = version
					view.PackedPredicate = true
					if publishSearchView(view, query, exact, started) then
						engine.LastResult, engine.LastTerms = view, nil
						characterSearch.Layout = view.ColdLayout
						characterSearch.Version = version
						characterSearch.Sorter = sorter
						characterSearch.NilRoot = nilRoot
						characterSearch.Schedule()
						return true
					end
					if not current() then
						if generation == searchGeneration then
							Explorer.SetSearchBusy(false, query)
						end
						return false
					end
				elseif not ok and view ~= changed then
					break
				end
				layout = nil
				nilRoot = getSearchNilRoot()
				roots[2] = nilRoot
			end
		end
		if large and terms and #terms == 1 and #terms[1] == 1 then
			local indexed = characterSearch.Ready(nilRoot)
			if indexed then
				local version = searchTreeVersion
				local function indexedCurrent()
					return current() and searchTreeVersion == version and characterSearch.Ready(nilRoot) == indexed
				end
				local deadline = os.clock() + 0.004
				local function checkpoint()
					if os.clock() >= deadline then
						Explorer.SetSearchBusy(true, query)
						task.wait()
						if not indexedCurrent() then
							error("Explorer search changed", 0)
						end
						deadline = os.clock() + 0.004
					end
				end
				local ok, view = pcall(Apps.SearchResults.CreateIndexed, indexed, terms[1], characterSearch.Context, checkpoint)
				if not current() then
					if generation == searchGeneration then
						Explorer.SetSearchBusy(false, query)
					end
					return false
				end
				if ok and view and indexedCurrent() then
					view.TreeVersion = version
					local published = publishSearchView(view, query, indexedCurrent, started)
					if published then
						engine.LastResult, engine.LastTerms = view, terms
					elseif generation == searchGeneration then
						Explorer.SetSearchBusy(false, query)
					end
					return published
				end
				if indexedCurrent() then
					layout = layout or indexed
				else
					layout = nil
				end
			end
			characterSearch.Schedule()
		end
		local function fallback()
			exitSearchView()
			local complete = restoredSearch(query, true)
			if complete then
				searchFunc = function()
					prepareSearch(query)
				end
				Explorer.SearchFallbacks = (Explorer.SearchFallbacks or 0) + 1
				prepareSearch(query)
			end
			return complete
		end
		if large and terms and not refreshing and not layout and characterSearch.UnstableAt then
			if os.clock() - characterSearch.UnstableAt < 1 then
				return fallback()
			end
		end
		local ready = engine:Ready()
		if
			large
			and terms
			and (not refreshing or searchView.Cold)
			and (not ready or layout or engine:HasChanges() or #terms[1] == 1)
		then
			Explorer.SetSearchBusy(true, query)
			local changed = {}
			for _ = 1, 2 do
				local version = searchTreeVersion
				local budget = 0.006
				local contentVersion = characterSearch.ContentVersion
				local removed = {}
				characterSearch.RemovedNodes = removed
				local deadline = os.clock() + budget
				local function checkpoint()
					if not current() or characterSearch.ContentVersion ~= contentVersion then
						error(changed, 0)
					end
					local now = os.clock()
					if now >= deadline then
						local waited = task.wait()
						if not current() or characterSearch.ContentVersion ~= contentVersion then
							error(changed, 0)
						end
						budget = if waited and waited > 1 / 60 then 0.004 else math.min(budget + 0.002, 0.010)
						deadline = os.clock() + budget
					end
				end
				local ok, view = pcall(Apps.SearchResults.CreateCold, roots, terms, {
					Name = coldName,
					Children = coldChildren,
					VisibleOnly = true,
					Estimate = Explorer.InitialObjectCount,
					Visible = function(node)
						return node == nilNode or Apps.ServiceVisibility.IsVisible(node.Obj)
					end,
				}, checkpoint, layout)
				if characterSearch.RemovedNodes == removed then
					characterSearch.RemovedNodes = nil
				end
				if not current() then
					if generation == searchGeneration then
						Explorer.SetSearchBusy(false, query)
					end
					return false
				end
				if ok and characterSearch.ContentVersion == contentVersion then
					for node in pairs(removed) do
						view:Remove(node)
					end
					view.TreeVersion = version
					characterSearch.UnstableAt = nil
					engine.LastResult, engine.LastTerms = view, terms
					return publishSearchView(view, query, current, started)
				end
				if not ok and view == changed and not refreshing then
					characterSearch.UnstableAt = os.clock()
					return fallback()
				end
				if not ok and view ~= changed then
					break
				end
				layout = nil
			end
		end
		if not refreshing and large and not engine:Ready() then
			return fallback()
		end
		Explorer.SetSearchBusy(true, query)
		local view, useFallback = engine:Search(predicate, terms, current, false, not refreshing and large and 8192 or nil)
		if useFallback and current() then
			return fallback()
		end
		if not view or not current() then
			if generation == searchGeneration then
				Explorer.SetSearchBusy(false, query)
			end
			return false
		end
		local published = publishSearchView(view, query, current, started)
		if not published and generation == searchGeneration then
			Explorer.SetSearchBusy(false, query)
		end
		return published
	end

	Explorer.DoLegacySearch = function(query)
		exitSearchView()
		local leavingSearch = #query == 0 and Explorer.Query and Explorer.Query ~= ""
		local focusNode = leavingSearch and getSearchExitFocusNode() or nil
		if leavingSearch then
			revealSelectedNodesInNormalTree()
		end
		if Explorer.Query ~= query and not leavingSearch then
			scrollV.Index = 0
			Explorer.Index = 0
		end
		table.clear(Explorer.SearchExpanded)
		table.clear(searchResults)
		table.clear(Explorer.Matches)
		Explorer.SearchError = nil
		Explorer.Query = query
		expanded = (#query == 0 and Explorer.Expanded or Explorer.SearchExpanded)
		searchFunc = nil

		if #query > 0 then
			local expandTable = Explorer.SearchExpanded
			local specFilters

			local lower = string.lower
			local find = string.find
			local tostring = tostring

			local lowerQuery = lower(query)
			local predicate, queryError = Apps.SearchQuery.Compile(query)
			Explorer.SearchError = queryError

			local function defaultSearch(root)
				local expandedpar = false
				for i = 1, #root do
					local node = root[i]
					local obj = node.Obj

					local matchOK, matched = pcall(predicate or function()
						return false
					end, obj)
					if matchOK and matched then
						expandTable[node] = 0
						searchResults[node] = true
						Explorer.Matches[node] = true
						if not expandedpar then
							local parnode = node.Parent
							while parnode and (not searchResults[parnode] or expandTable[parnode] == 0) do
								expanded[parnode] = true
								searchResults[parnode] = true
								parnode = parnode.Parent
							end
							expandedpar = true
						end
					end

					if #node > 0 then
						defaultSearch(node)
					end
				end
			end

			if Main.Elevated and query:match("^%s*/") then
				local start = tick()
				Explorer.SearchError = nil
				local ok, fn, filters = pcall(Explorer.BuildSearchFunc, query)
				searchFunc, specFilters = ok and fn or nil, ok and filters or nil
				if not searchFunc then
					Explorer.SearchError = "Check the DeX query syntax"
				end
			else
				searchFunc = defaultSearch
			end

			if specFilters then
				table.clear(specResults)
				for i = 1, #specFilters do
					local resMap = {}
					specResults[i] = resMap
					local objs = specFilters[i]()
					for c = 1, #objs do
						local node = nodes[objs[c]]
						if node then
							resMap[node] = true
						end
					end
				end
			end

			if searchFunc then
				local start = tick()
				searchFunc(nodes[game])
				if Settings.Explorer.ShowNilInstances ~= false then
					searchFunc(nilNode)
				end
			end
		end

		if focusNode then
			Explorer.ViewNode(focusNode, true)
		else
			Explorer.ForceUpdate()
		end
	end

	Explorer.SetExpanded = function(node, value, recursive)
		if not Explorer.HasChildren(node) then
			return
		end
		expanded[node] = value
		if retainedSearchQuery then
			searchExpansionDirty = true
		end
		invalidateBranch(node)
		if recursive then
			local stack = { node }
			while #stack > 0 do
				local parent = table.remove(stack)
				for _, child in ipairs(parent) do
					if #child > 0 and not child.Del then
						expanded[child] = value
						stack[#stack + 1] = child
					end
				end
			end
		end
	end
	Explorer.ToggleExpanded = function(node, recursive)
		Explorer.SetExpanded(node, not expanded[node], recursive)
	end

	Explorer.OpenInsert = function(node, anchor)
		if not node or (node.Inferred and not node.Materialized) or node.Del or node == nilNode then
			return
		end
		selection:Set(node)
		selection.Piviot = node
		Explorer.InsertObjectOpenFor = node
		Explorer.Refresh()
		local context = Explorer.InsertObjectContext
		context.Width = Apps.InsertObjectOverlay.MenuWidth
		context.GuiElems.SearchBar.PlaceholderText = "Search objects"
		context.FocusSearchOnShow = true
		local x, y
		if anchor then
			x, y = Apps.InsertObjectOverlay.Anchor(anchor)
		end
		context:Show(x, y)
	end

	Explorer.GetSearchMatches = function()
		return searchView and searchView:MaterializeMatches() or table.clone(Explorer.MatchList)
	end
	Explorer.IterSearchMatches = function()
		local list = Explorer.MatchList
		local index = 0
		return function()
			index += 1
			if index <= #list then
				return index, list[index]
			end
		end
	end
	Explorer.SelectMatches = function(toggle)
		local allSelected = #Explorer.MatchList > 0 and #selection.List == #Explorer.MatchList
		if searchView then
			if allSelected then
				for _, node in ipairs(selection.List) do
					if not searchView:PositionOfMatch(node) then
						allSelected = false
						break
					end
				end
			end
		else
			for i = 1, #Explorer.MatchList do
				if not selection.Map[Explorer.MatchList[i]] then
					allSelected = false
					break
				end
			end
		end
		if toggle and allSelected then
			selection:Clear()
		elseif searchView then
			selection:SetTable(searchView:MaterializeMatches(function(node)
				return not node.Del and nodes[node.Obj] == node
			end))
		else
			selection:SetTable(Explorer.MatchList)
		end
		selection.Piviot = selection.List[1]
		Explorer.Refresh()
	end

	Explorer.StepMatch = function(direction, additive)
		local matches = Explorer.MatchList
		if #matches == 0 or direction == 0 then
			return
		end
		direction = direction > 0 and 1 or -1
		local boundary
		local selectedMatches = 0
		for _, node in ipairs(selection.List) do
			local index = searchView and searchView:PositionOfMatch(node) or table.find(matches, node)
			if index then
				selectedMatches += 1
				if not boundary or direction > 0 and index < boundary or direction < 0 and index > boundary then
					boundary = index
				end
			end
		end
		if selectedMatches == #matches then
			return
		end
		boundary = boundary or (direction > 0 and 0 or #matches + 1)
		for offset = 1, #matches do
			local node = matches[(boundary - 1 + direction * offset) % #matches + 1]
			if not node.Del and (not searchView or nodes[node.Obj] == node) and not selection.Map[node] then
				if additive then
					selection:Add(node)
				else
					selection:Set(node)
				end
				selection.Piviot = node
				Explorer.KeyboardFocusNode = node
				Explorer.ViewNode(node)
				return
			end
		end
	end

	Explorer.UpdateSearchStatus = function()
		local status = Explorer.GuiElems.SearchStatus
		if not status then
			return
		end
		local searching = Explorer.SearchBusy or (Explorer.Query and Explorer.Query ~= "")
		status.Visible = searching
		Explorer.HeaderHeight = tokens.HeaderHeight + (searching and 24 or 0)
		if toolBar:FindFirstChild("BottomBorder") then
			toolBar.BottomBorder.Position = UDim2.fromOffset(0, Explorer.HeaderHeight - 1)
		end
		treeFrame.Position = UDim2.fromOffset(0, Explorer.HeaderHeight)
		treeFrame.Size = UDim2.new(1, 0, 1, -Explorer.HeaderHeight)

		local count = #Explorer.MatchList
		status.Count.Text = Explorer.SearchBusy and "Searching…"
			or (Explorer.SearchError and "Check search" or (tostring(count) .. (count == 1 and " match" or " matches")))
		status.Count.Position = UDim2.fromOffset(Explorer.SearchBusy and 30 or 10, 0)
		local spinner = status:FindFirstChild("LoadingSpinner")
		if spinner then
			spinner.Visible = Explorer.SearchBusy == true
			Explorer.UpdateSearchSpinner()
		end
		status.Count.TextColor3 = not Explorer.SearchBusy and Explorer.SearchError and Color3.fromRGB(255, 160, 150)
			or Settings.Theme.PlaceholderText
		Explorer.GuiElems.Empty.Visible = searching and not Explorer.SearchBusy and count == 0
		Explorer.GuiElems.Empty.Text = Explorer.SearchError or "No results found"
	end
	Explorer.SetSearchBusy = function(busy, query)
		local changed = Explorer.SearchBusy ~= busy
		Explorer.SearchBusy = busy
		Explorer.SearchPendingQuery = busy and query or nil
		if changed and Main.Alive ~= false then
			Explorer.UpdateSearchStatus()
		end
	end

	Explorer.ClearSearch = function()
		if Explorer.CloseHeaderPopup then
			Explorer.CloseHeaderPopup()
		end
		Explorer.SearchRevision = (Explorer.SearchRevision or 0) + 1
		Explorer.GuiElems.SearchBar.Text = ""
		Explorer.DoSearch("")
	end

	Explorer.InitSearch = function()
		Apps.SearchBox.Bind(Explorer, toolBar, treeFrame)
	end

	Explorer.InitKeyboard = function()
		Apps.History.Bind()
		local inputService = service.UserInputService
		local focused = false
		local holdGeneration, heldKey = 0, nil
		local function stopHold()
			holdGeneration += 1
			heldKey = nil
		end
		local processInput
		Explorer.FocusFirstFromSearch = function()
			local node = tree[1]
			if not node then
				return false
			end
			focused = true
			Explorer.GuiElems.SearchBar:ReleaseFocus()
			selection:Set(node)
			selection.Piviot = node
			Explorer.KeyboardFocusNode = node
			Explorer.ViewNode(node)
			return true
		end
		Main.TrackSignal(inputService.InputEnded, function(input)
			if input.KeyCode == heldKey or input.UserInputType ~= Enum.UserInputType.Keyboard then
				stopHold()
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				Explorer.ExpandSweepValue = nil
				Explorer.ExpandSweepVisited = nil
			end
		end)
		processInput = function(input, processed, repeated)
			local kind, key = input.UserInputType, input.KeyCode
			if Explorer.HeaderPopupEscapeInput == input then
				Explorer.HeaderPopupEscapeInput = nil
				return
			end
			if
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.Touch
			then
				stopHold()
				local p, size =
					Explorer.Window.GuiElems.Main.AbsolutePosition, Explorer.Window.GuiElems.Main.AbsoluteSize
				focused = input.Position.X >= p.X
					and input.Position.X < p.X + size.X
					and input.Position.Y >= p.Y
					and input.Position.Y < p.Y + size.Y
				return
			end
			if kind ~= Enum.UserInputType.Keyboard or not Explorer.Window:IsVisible() then
				stopHold()
				return
			end
			local ctrl = Lib.IsCtrlDown()
				or inputService:IsKeyDown(Enum.KeyCode.LeftMeta)
				or inputService:IsKeyDown(Enum.KeyCode.RightMeta)
			local shift = Lib.IsShiftDown()
			local textBox = inputService:GetFocusedTextBox()
			if objectPicker and key == Enum.KeyCode.Escape then
				return
			end
			if ctrl and shift and key == Enum.KeyCode.X and not textBox then
				focused = true
				Explorer.GuiElems.SearchBar:CaptureFocus()
				return
			end
			if key == Enum.KeyCode.Escape and textBox == Explorer.GuiElems.SearchBar then
				Explorer.ClearSearch()
				textBox:ReleaseFocus()
				focused = true
				return
			end
			if (processed and not Main.GameInputLocked) or textBox or not focused then
				stopHold()
				return
			end
			local arrow = key == Enum.KeyCode.Up
				or key == Enum.KeyCode.Down
				or key == Enum.KeyCode.Left
				or key == Enum.KeyCode.Right
			if arrow and not ctrl and not repeated and heldKey ~= key then
				stopHold()
				heldKey = key
				local generation = holdGeneration
				local function repeatKey()
					if
						holdGeneration ~= generation
						or not Main.Alive
						or not focused
						or not Explorer.Window:IsVisible()
						or inputService:GetFocusedTextBox()
						or not inputService:IsKeyDown(key)
					then
						if holdGeneration == generation then
							stopHold()
						end
						return
					end
					processInput(input, processed, true)
					if holdGeneration == generation then
						task.delay(0.02, repeatKey)
					end
				end
				task.delay(0.5, repeatKey)
			end
			local node
			for selectedIndex = #selection.List, 1, -1 do
				local candidate = selection.List[selectedIndex]
				if visibleIndices[candidate] then
					node = candidate
					break
				end
			end
			local index = visibleIndices[node] or 1
			if objectPicker and not ctrl and (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter) then
				if node and not node.Del and #selection.List == 1 then
					objectPicker(node.Obj)
				end
				return
			end
			if
				not repeated
				and not objectPicker
				and not Explorer.Window.Minimized
				and (not Main.ActiveFocusOwner or Main.ActiveFocusOwner == Explorer.Window)
				and Apps.PluginActions
				and Apps.PluginActions.HandleShortcut("Explorer", input, function()
					return Apps.PluginActions.ExplorerContext(selection.List, node and node.Obj)
				end)
			then
				return
			end
			local target
			local command
			if ctrl then
				local alt = inputService:IsKeyDown(Enum.KeyCode.LeftAlt)
					or inputService:IsKeyDown(Enum.KeyCode.RightAlt)
				if key == Enum.KeyCode.C then
					command = "COPY"
				elseif key == Enum.KeyCode.X then
					command = "CUT"
				elseif key == Enum.KeyCode.V then
					command = "PASTE"
				elseif key == Enum.KeyCode.D then
					command = "DUPLICATE"
				elseif key == Enum.KeyCode.G then
					command = alt and "GROUP_FOLDER" or (shift and "UNGROUP" or "GROUP")
				elseif key == Enum.KeyCode.U then
					command = "UNGROUP"
				end
			elseif key == Enum.KeyCode.Delete then
				command = shift and "DELETE_CHILDREN" or "DELETE"
			end
			if command and not objectPicker then
				if #selection.List > 0 and (command ~= "PASTE" or #clipboard > 0) then
					local action = Explorer.RightClickContext.Registered[command]
					local ok, err = pcall(action.OnClick)
					if not ok then
						warn("[Dex Explorer] " .. action.Name .. " failed: " .. tostring(err))
					end
				end
				return
			end
			if
				ctrl
				and (
					key == Enum.KeyCode.Up
					or key == Enum.KeyCode.Down
					or key == Enum.KeyCode.Left
					or key == Enum.KeyCode.Right
				)
			then
				return
			end
			if arrow and not node and #selection.List > 0 then
				return
			end
			if shift and (key == Enum.KeyCode.Up or key == Enum.KeyCode.Down) then
				local nextNode = Explorer.ShiftArrow(key == Enum.KeyCode.Down and 1 or -1)
				if nextNode then
					Explorer.KeyboardFocusNode = nextNode
					Explorer.ViewNode(nextNode)
				end
				return
			end
			if key == Enum.KeyCode.Up and node and index == 1 and not shift then
				selection:Clear()
				Explorer.Refresh()
				Explorer.GuiElems.SearchBar:CaptureFocus()
				return
			end
			if key == Enum.KeyCode.Up then
				target = node and index - 1 or #tree
			elseif key == Enum.KeyCode.Down then
				target = node and index + 1 or 1
			elseif key == Enum.KeyCode.Home or key == Enum.KeyCode.End then
				local endpoint = Policy.Endpoint(
					tree,
					key == Enum.KeyCode.End,
					Explorer.Query and Explorer.Query ~= "" and Explorer.Matches or nil
				)
				target = endpoint and rowIndex(endpoint)
			elseif key == Enum.KeyCode.PageUp or key == Enum.KeyCode.PageDown then
				local distance = math.max(1, math.floor(scrollV.VisibleSpace))
					* (key == Enum.KeyCode.PageDown and 1 or -1)
				local pageNode = Policy.PageStep(
					tree,
					selection.List,
					distance,
					Explorer.Query and Explorer.Query ~= "" and Explorer.Matches or nil,
					visibleIndices
				)
				target = pageNode and visibleIndices[pageNode]
			elseif key == Enum.KeyCode.Right and node then
				if expanded[node] and expanded[node] ~= 0 then
					target = #node > 0 and index + 1 or nil
				elseif shift then
					Explorer.SetExpanded(node, true, true)
					Explorer.ForceUpdate(false, true)
				else
					Explorer.ToggleExpanded(node, shift)
					Explorer.ForceUpdate(false, true)
				end
			elseif key == Enum.KeyCode.Left and node then
				if shift then
					Explorer.SetExpanded(node, false, true)
					Explorer.ForceUpdate(false, true)
				elseif expanded[node] and expanded[node] ~= 0 then
					Explorer.ToggleExpanded(node, shift)
					Explorer.ForceUpdate(false, true)
				else
					target = rowIndex(node.Parent)
				end
			elseif key == Enum.KeyCode.F2 and node and #selection.List == 1 and not objectPicker then
				Explorer.SetRenamingNode(node)
			elseif ctrl and key == Enum.KeyCode.I and node and not objectPicker then
				Explorer.OpenInsert(node)
			elseif ctrl and key == Enum.KeyCode.A then
				if Explorer.Query and Explorer.Query ~= "" then
					Explorer.SelectMatches()
				else
					selection:SetTable(tree)
					Explorer.Refresh()
				end
			elseif key == Enum.KeyCode.Escape then
				selection:Clear()
				Explorer.Refresh()
			end
			if target and #tree > 0 then
				local nextNode = tree[math.clamp(target, 1, #tree)]
				if Explorer.Query and Explorer.Query ~= "" and not Explorer.Matches[nextNode] then
					nextNode = Policy.Navigate(tree, node, target < index and -1 or 1, Explorer.Matches)
				end
				if not nextNode then
					return
				end
				if
					shift
					and key ~= Enum.KeyCode.Home
					and key ~= Enum.KeyCode.End
					and key ~= Enum.KeyCode.PageUp
					and key ~= Enum.KeyCode.PageDown
					and key ~= Enum.KeyCode.Right
					and key ~= Enum.KeyCode.Left
				then
					selection.Piviot = selection.Piviot or node or nextNode
					selection:SetTable(
						Policy.Range(
							tree,
							selection.Piviot,
							nextNode,
							expanded == Explorer.SearchExpanded and Explorer.Matches or nil
						)
					)
				else
					selection:Set(nextNode)
					selection.Piviot = nextNode
				end
				Explorer.KeyboardFocusNode = nextNode
				Explorer.ViewNode(nextNode)
			end
		end
		Main.TrackSignal(inputService.InputBegan, processInput)
		Main.TrackSignal(Explorer.Window.OnDeactivate, function()
			focused = false
			stopHold()
		end)
		Main.TrackSignal(Explorer.Window.OnMinimize, function()
			focused = false
			stopHold()
		end)
		Main.AddCleanup(stopHold)
	end

	Explorer.InitClickSystem = function()
		local sys = Lib.ClickSystem.new()
		sys.ResolveItem = function()
			local mouse = Main.Mouse
			if Explorer.IsTreeContentPoint(mouse.X, mouse.Y) then
				return displayedRowAt(mouse.Y)
			end
		end
		local pressedRows = {}
		local lastClick, clickRevision = nil, 0
		local function resetClicks()
			lastClick = nil
			clickRevision += 1
			table.clear(pressedRows)
		end
		Main.TrackSignal(Explorer.Window.OnDeactivate, resetClicks)
		Main.TrackSignal(Explorer.Window.OnMinimize, resetClicks)
		local anchoredSelection, applyingShift, arrowRange
		selection.Changed:Connect(function()
			if not applyingShift then
				anchoredSelection = nil
				arrowRange = nil
			end
		end)
		Explorer.ShiftClick = function(node)
			local base = anchoredSelection or table.clone(selection.List)
			local anchor = base[#base]
			if #base > 0 and not anchoredSelection then
				anchoredSelection = base
			end
			local anchorVisible = anchor and rowIndex(anchor)
			applyingShift = true
			local values =
				Policy.ShiftRange(tree, base, node, expanded == Explorer.SearchExpanded and Explorer.Matches or nil)
			selection:SetTable(values)
			selection.Piviot = anchor or node
			applyingShift = false
			if anchor and not anchorVisible then
				anchoredSelection = table.clone(values)
			end
		end
		Explorer.ShiftArrow = function(direction)
			local state = arrowRange
			if not state then
				state = { base = table.clone(selection.List), direction = direction, added = {} }
				arrowRange = state
			end
			if direction ~= state.direction then
				table.remove(state.added)
				local previous = state.added[#state.added]
				if not previous then
					applyingShift = true
					selection:SetTable(state.base)
					applyingShift = false
					arrowRange = nil
					anchoredSelection = nil
					return state.base[#state.base]
				end
				Explorer.ShiftClick(previous)
				return previous
			end
			local index
			for selectedIndex = #selection.List, 1, -1 do
				index = visibleIndices[selection.List[selectedIndex]]
				if index then
					break
				end
			end
			if not index then
				return nil
			end
			for nextIndex = index + direction, direction > 0 and #tree or 1, direction do
				local node = tree[nextIndex]
				if not selection.Map[node] then
					Explorer.ShiftClick(node)
					state.added[#state.added + 1] = node
					return node
				end
			end
			return nil
		end
		sys.AllowedButtons = { 1, 2 }
		sys.OnDown:Connect(function(item, _, button)
			clickRevision += 1
			local previous = lastClick
			lastClick = nil
			pressedRows[button] = nil
			if not Explorer.IsTreeContentPoint(Main.Mouse.X, Main.Mouse.Y) then
				return
			end
			if Explorer.BoxSelecting or (button == 1 and Explorer.IsEmptyPoint(Main.Mouse.X, Main.Mouse.Y)) then
				return
			end
			local node = displayedNodes[item]
			if not node or node.Del or overRowControl(item) then
				return
			end
			if objectPicker then
				if button == 1 then
					pressedRows[1] = { Item = item, Node = node, Picker = objectPicker }
				end
				return
			end
			if Properties.SelectObject(node.Obj) then
				return
			end
			local shift, ctrl = Lib.IsShiftDown(), Lib.IsCtrlDown()
			local plain = button == 1 and not shift and not ctrl
			local now = os.clock()
			pressedRows[button] = {
				Item = item,
				Node = node,
				Time = now,
				Plain = plain,
				Double = plain and previous and previous.Node == node and now - previous.Time <= sys.ComboTime,
				Rename = plain and selection.Map[node],
			}

			selectingRow = true
			if button == 1 then
				if shift then
					selection.ShiftSet = {}
					Explorer.ShiftClick(node)
				elseif ctrl then
					selection.ShiftSet = {}
					if selection.Map[node] then
						selection:Remove(node)
					else
						selection:Add(node)
					end
					selection.Piviot = node
				elseif not selection.Map[node] then
					selection.ShiftSet = {}
					selection:Set(node)
					selection.Piviot = node
				end
			elseif button == 2 and not selection.Map[node] then
				selection.ShiftSet = {}
				selection:Set(node)
				selection.Piviot = node
			end
			selectingRow = false

			Explorer.Refresh()
		end)

		sys.OnRelease:Connect(function(item, _, button, position)
			local pressedButton = if button == 2 and position then 1 else button
			local pressed = pressedRows[pressedButton]
			pressedRows[pressedButton] = nil
			if
				Explorer.Dragging
				or Explorer.BoxSelecting
				or Explorer.SuppressRelease
				or not Explorer.IsTreeContentPoint(Main.Mouse.X, Main.Mouse.Y)
				or displayedRowAt(Main.Mouse.Y) ~= item
			then
				return
			end
			local node = displayedNodes[item]
			if not node or node.Del or not pressed or pressed.Item ~= item or pressed.Node ~= node then
				return
			end
			if pressed.Picker then
				if button == 1 and objectPicker == pressed.Picker and not overRowControl(item) then
					pressed.Picker(node.Obj)
				end
				return
			end
			if button == 1 then
				if pressed.Plain and selection.Map[node] then
					selectingRow = true
					selection.ShiftSet = {}
					selection:Set(node)
					selection.Piviot = node
					selectingRow = false
					Explorer.Refresh()
				end

				if not pressed.Plain then
					return
				end
				if pressed.Double then
					if
						node.Obj:IsA("LuaSourceContainer")
						and (
							not node.Inferred
							or (Apps.ModuleReconstruction and Apps.ModuleReconstruction.GetSource(node.Obj))
						)
					then
						ScriptViewer.ViewScript(node.Obj)
					elseif Explorer.HasChildren(node) then
						Explorer.SetExpanded(node, not expanded[node], false)
						Explorer.Update(true)
						Explorer.Refresh()
					end
					return
				end
				lastClick = pressed
				if
					pressed.Rename
					and Settings.Explorer.ClickToRename
					and Lib.CheckMouseInGui(item.Indent.EntryName)
				then
					local revision = clickRevision
					task.delay(sys.ComboTime, function()
						local index = rowIndex(node)
						if
							revision == clickRevision
							and Explorer.Window:IsVisible()
							and not node.Del
							and displayedNodes[item] == node
							and index
							and listEntries[index - Explorer.Index] == item
							and selection.Map[node]
							and Settings.Explorer.ClickToRename
						then
							Explorer.SetRenamingNode(node)
						end
					end)
				end
			elseif button == 2 then
				Explorer.ShowRightClick(position, node)
			end
		end)
		Explorer.ClickSystem = sys
	end

	Explorer.CleanDeletedChildren = function()
		if not next(dirtyParents) then
			return false
		end
		local processed = false

		local pendingParents = dirtyParents
		dirtyParents = {}

		for node in pairs(pendingParents) do
			if node.HasDel then
				local write = 1
				local count = #node
				for read = 1, count do
					local child = node[read]
					if not child.Del then
						if write ~= read then
							node[write] = child
						end
						write += 1
					end
				end
				if write <= count then
					for i = write, count do
						node[i] = nil
					end
					processed = true
				end
				node.HasDel = false
			end
		end
		if processed then
			changeSearchTree()
		end
		return processed
	end

	Explorer.SelectObject = function(object)
		if not object then
			return false
		end
		if not nodes[object] and Explorer.SyncHistoryObject then
			pcall(Explorer.SyncHistoryObject, object)
		end
		local node = nodes[object]
		if not node then
			return false
		end
		selection:Set(node)
		Explorer.ViewNode(node)
		return true
	end

	Explorer.PickWorld = function(position)
		local world = service.Workspace
		local camera = world.CurrentCamera
		if not camera then
			return false
		end
		local pointer, screenPosition
		if position then
			screenPosition = position
		else
			pointer = service.UserInputService:GetMouseLocation()
			local ok, inset = pcall(function()
				return service.GuiService:GetGuiInset()
			end)
			inset = ok and inset or Vector2.new(0, 0)
			screenPosition = Vector2.new(pointer.X - inset.X, pointer.Y - inset.Y)
		end
		if Main.IsPointInDexUI and Main.IsPointInDexUI(screenPosition.X, screenPosition.Y) then
			return false
		end
		local ray
		if position then
			ray = camera:ScreenPointToRay(position.X, position.Y)
		else
			ray = camera:ViewportPointToRay(pointer.X, pointer.Y)
		end
		local ignore = {}
		local character = service.Players.LocalPlayer.Character
		if character then
			ignore[#ignore + 1] = character
		end
		for root in pairs(Main.SelectionGeometryRoots or {}) do
			ignore[#ignore + 1] = root
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		params.RespectCanCollide = false
		for _ = 1, 64 do
			params.FilterDescendantsInstances = ignore
			local hit = world:Raycast(ray.Origin, ray.Direction * 15000, params)
			if not hit then
				return false
			end
			local object = hit.Instance
			local hidden = object:IsA("BasePart")
				and (1 - (1 - object.Transparency) * (1 - object.LocalTransparencyModifier)) >= 1
			if not hidden then
				return Explorer.SelectObject(object)
			end
			ignore[#ignore + 1] = object
		end
		return false
	end

	Explorer.UpdateSelectionVisuals = function()
		local manager = Explorer.SelectionVisualManager
		if not manager then
			local holder = Instance.new("ScreenGui")
			holder.Name = "ExplorerSelections"
			holder.DisplayOrder = Main.DisplayOrders.Core
			Lib.ShowGui(holder)
			Explorer.SelectionVisualsHolder = holder
			local function pivotSpace()
				local tools = Apps.TransformTools
				return tools and (tools.Tool == "Scale" and "Scale" or tools.Space) or "World"
			end
			manager = Apps.SelectionRenderer.Create({
				Parent = holder,
				Workspace = service.Workspace,
				GeometryMask = type(Instance.fromExisting) == "function" and Apps.SelectionGeometryMask or nil,
				PivotSpace = pivotSpace,
				CreateSelectionPivot = function(roots, records)
					local transform = Apps.TransformSession
					return transform and transform.CreateSelectionPivot(roots, records)
				end,
				SelectionPivot = function(roots)
					local _, _, pivot = Apps.TransformSession.Bounds(roots, pivotSpace())
					return pivot
				end,
				ReportFailure = function(object, problem)
					warn(
						"[Dex Explorer] Selection geometry fallback for "
							.. tostring(object)
							.. ": "
							.. tostring(problem)
					)
				end,
				IsExcluded = function(object)
					return Main.IsDexGuiObject and Main.IsDexGuiObject(object)
						or Apps.SelectionGeometryMask and Apps.SelectionGeometryMask.IsInternal(object)
				end,
				HandlesGui = function(object)
					return Apps.GuiTransformTools and Apps.GuiTransformTools.HandlesObject(object)
				end,
				AttachGui = function(object, parent)
					local visual = Instance.new("Frame")
					visual.Name = "GuiSelection"
					visual.BackgroundTransparency = 1
					visual.BorderSizePixel = 0
					local edges = {
						{ UDim2.new(0, -1, 0, -1), UDim2.new(1, 2, 0, 1) },
						{ UDim2.new(0, -1, 1, 0), UDim2.new(1, 2, 0, 1) },
						{ UDim2.new(0, -1, 0, 0), UDim2.new(0, 1, 1, 0) },
						{ UDim2.new(1, 0, 0, 0), UDim2.new(0, 1, 1, 0) },
					}
					for _, edge in ipairs(edges) do
						local border = Instance.new("Frame")
						border.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
						border.BorderSizePixel = 0
						border.Position, border.Size = edge[1], edge[2]
						border.Parent = visual
					end
					local attachment = Lib.AttachTo(visual, { Target = object, Resize = true })
					visual.Parent = parent
					return visual, attachment
				end,
			})
			Explorer.SelectionVisualManager = manager
		end
		local objects = table.create(#selection.List)
		for _, node in ipairs(selection.List) do
			objects[#objects + 1] = node.Obj
		end
		manager:Update(objects, {
			PartEnabled = Settings.Explorer.PartSelectionBox,
			GuiEnabled = Settings.Explorer.GuiSelectionBox,
			Color = Color3.fromRGB(0, 170, 255),
		})
		Explorer.SelectionRenderingMode = type(Instance.fromExisting) == "function"
				and Apps.SelectionGeometryMask
				and "PlayerGeometryMaskAdapter"
			or "PublicFallback"
	end

	Explorer.Init = function()
		Explorer.LegacyClassIcons = Lib.IconMap.newLinear("rbxasset://textures/ClassImages.PNG", 16, 16)

		if Settings.ClassIcon ~= nil and Settings.ClassIcon ~= "Old" then
			iconData = Lib.IconMap.getIconDataFromName(Settings.ClassIcon)

			Explorer.ClassIcons = Lib.IconMap.new(
				"rbxassetid://" .. tostring(iconData.MapId),
				iconData.IconSize * iconData.Witdh,
				iconData.IconSize * iconData.Height,
				iconData.IconSize,
				iconData.IconSize
			)
			local fixed = {}
			for i, v in pairs(iconData.Icons) do
				fixed[i] = v - 1
			end

			iconData.Icons = fixed
			Explorer.ClassIcons:SetDict(fixed)
		else
			Explorer.ClassIcons = Lib.IconMap.newLinear("rbxasset://textures/ClassImages.PNG", 16, 16)
		end

		Explorer.MiscIcons = Main.MiscIcons

		clipboard = {}

		selection = Apps.SelectionService.NewStore()
		selection.ShiftSet = {}
		selection.Changed:Connect(Properties.ShowExplorerProps)
		Explorer.Selection = selection
		Explorer.Services = {
			Selection = Apps.SelectionService.Bind(selection, function(object)
				return nodes[object]
			end),
			Reflection = Apps.ReflectionService,
			Editing = Apps.EditingService,
			Insertion = Apps.InsertionService,
		}

		Explorer.SetSortingEnabled(Settings.Explorer.Sorting)
		Explorer.Expanded = setmetatable({}, { __mode = "k" })
		Explorer.SearchExpanded = setmetatable({}, { __mode = "k" })
		expanded = Explorer.Expanded

		nilNode.Obj.Name = "Nil Instances"
		nilNode.Locked = true

		local explorerItems = create({
			{ 1, "Folder", { Name = "ExplorerItems" } },
			{
				2,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
					BorderSizePixel = 0,
					Name = "ToolBar",
					Parent = { 1 },
					Size = UDim2.new(1, 0, 0, 22),
				},
			},
			{
				3,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
					BorderColor3 = Color3.new(0.1176470592618, 0.1176470592618, 0.1176470592618),
					BorderSizePixel = 0,
					Name = "SearchFrame",
					Parent = { 2 },
					Position = UDim2.new(0, 3, 0, 1),
					Size = UDim2.new(1, -6, 0, 18),
				},
			},
			{
				4,
				"TextBox",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					Font = 3,
					Name = "SearchBox",
					Parent = { 3 },
					PlaceholderColor3 = Color3.new(0.39215689897537, 0.39215689897537, 0.39215689897537),
					PlaceholderText = "Search workspace",
					Position = UDim2.new(0, 4, 0, 0),
					Size = UDim2.new(1, -24, 0, 18),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextXAlignment = 0,
				},
			},
			{ 5, "UICorner", { CornerRadius = UDim.new(0, 2), Parent = { 3 } } },
			{ 6, "UIStroke", { Thickness = 1.4, Parent = { 3 }, Color = Color3.fromRGB(42, 42, 42) } },
			{
				7,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "Reset",
					Parent = { 3 },
					Position = UDim2.new(1, -17, 0, 1),
					Size = UDim2.new(0, 16, 0, 16),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				8,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5034718129",
					ImageColor3 = Color3.new(0.39215686917305, 0.39215686917305, 0.39215686917305),
					Parent = { 7 },
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				9,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "Refresh",
					Parent = { 2 },
					Position = UDim2.new(1, -20, 0, 1),
					Size = UDim2.new(0, 18, 0, 18),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					Visible = false,
				},
			},
			{
				10,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5642310344",
					Parent = { 9 },
					Position = UDim2.new(0, 3, 0, 3),
					Size = UDim2.new(0, 12, 0, 12),
				},
			},
			{
				11,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.15686275064945, 0.15686275064945, 0.15686275064945),
					BorderSizePixel = 0,
					Name = "ScrollCorner",
					Parent = { 1 },
					Position = UDim2.new(1, -16, 1, -16),
					Size = UDim2.new(0, 16, 0, 16),
					Visible = false,
				},
			},
			{
				12,
				"ScrollingFrame",
				{
					CanvasPosition = Vector2.new(0, 0),
					CanvasSize = UDim2.fromOffset(0, 0),
					BorderSizePixel = 0,
					ScrollBarThickness = 6,
					VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
					ScrollBarImageColor3 = Settings.Theme.ExplorerScrollBar or Color3.fromRGB(116, 116, 118),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Name = "List",
					Parent = { 1 },
					Position = UDim2.new(0, 0, 0, 23),
					Size = UDim2.new(1, 0, 1, -23),
				},
			},
		})

		toolBar = explorerItems.ToolBar
		treeFrame = explorerItems.List
		treeFrame.TopImage = Main.GetStudioAsset("native/scroll/top") or treeFrame.TopImage
		treeFrame.MidImage = Main.GetStudioAsset("native/scroll/mid") or treeFrame.MidImage
		treeFrame.BottomImage = Main.GetStudioAsset("native/scroll/bottom") or treeFrame.BottomImage
		treeFrame.ScrollBarImageTransparency = 0
		treeFrame.ScrollBarImageColor3 = Settings.Theme.ExplorerScrollBar
			or (Settings.Theme.IconTheme == "Light" and Color3.fromRGB(148, 148, 150) or Color3.fromRGB(116, 116, 118))
		pcall(function()
			treeFrame.SmoothScroll = false
			treeFrame.ScrollRate = 20 * 3 / 140
		end)
		Explorer.TreeRenderer = Apps.SessionView.Create(treeFrame)
		Explorer.InitRightClick()
		Explorer.InitInsertObject()
		treeFrame.Position = UDim2.fromOffset(0, Explorer.HeaderHeight)

		Explorer.GuiElems.ToolBar = toolBar
		Explorer.GuiElems.TreeFrame = treeFrame

		scrollV = Apps.ScrollingView.New(treeFrame, false)
		scrollH = Apps.ScrollingView.New(treeFrame, true)
		scrollV.Scrolled:Connect(function()
			Explorer.Index = scrollV.Index
			Explorer.Refresh()
		end)
		scrollH.Scrolled:Connect(function()
			Explorer.Refresh()
		end)
		local window = Lib.Window.new()
		Explorer.Window = window
		window:SetTitle("Explorer")
		window.GuiElems.Line.Visible = false

		Explorer.InitClickSystem()
		toolBar.Parent = window.GuiElems.Content
		treeFrame.Parent = window.GuiElems.Content
		Explorer.ScrollBarBorders = Apps.ScrollingView.AttachHoverBorders(treeFrame, {
			IsActive = function()
				return Explorer.Active and window:IsVisible()
			end,
			IsBlocked = function()
				local dialog = Apps.ServiceVisibilityDialog.Window
				return Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown()
					or Explorer.GuiElems.HeaderPopup and Explorer.GuiElems.HeaderPopup.Visible
					or dialog and dialog.Closed == false
			end,
		})
		explorerItems.ScrollCorner.Parent = window.GuiElems.Content

		Explorer.InitRenameBox()
		Explorer.InitSearch()
		Explorer.InitKeyboard()
		Main.TrackSignal(service.UserInputService.InputChanged, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement or not Explorer.Active then
				return
			end
			local overWindow = Lib.CheckMouseInGui(window.GuiElems.Main)
			Explorer.SetHoveredObject(not overWindow and not Explorer.Dragging and Main.Mouse.Target or nil)
		end)
		local resizeView = Lib.FrameTask(function()
			if not Explorer.Active then
				return
			end
			local previousIndex = Explorer.Index
			Explorer.UpdateView()
			local viewport = treeFrame.AbsoluteWindowSize or treeFrame.AbsoluteSize
			local count = math.min(
				math.max(math.ceil(treeFrame.AbsoluteSize.Y / Explorer.RowHeight) + 1, 0),
				math.max(0, #tree - Explorer.Index)
			)
			if
				renamingNode
				or previousIndex ~= Explorer.Index
				or not Explorer.TreeRenderer:ResizeViewport(
					count,
					math.max(Explorer.ViewWidth + Explorer.FreeWidth, treeFrame.AbsoluteSize.X),
					viewport.X,
					scrollH.Index
				)
			then
				Explorer.Refresh()
			end
		end)
		Main.AddCleanup(function()
			resizeView:Cancel()
		end)
		Main.TrackSignal(treeFrame:GetPropertyChangedSignal("AbsoluteWindowSize"), function()
			resizeView:Push(true)
		end)
		treeFrame.Active = true
		treeFrame.InputBegan:Connect(function(event)
			if
				event.UserInputType == Enum.UserInputType.MouseButton1
				or event.UserInputType == Enum.UserInputType.Touch
			then
				Explorer.StartBoxSelect(event)
			end
			if
				event.UserInputType == Enum.UserInputType.MouseButton2
				and not objectPicker
				and Explorer.IsTreeContentPoint(event.Position.X, event.Position.Y)
				and Explorer.IsEmptyPoint(event.Position.X, event.Position.Y)
			then
				selection:Clear()
				Explorer.Refresh()
				Explorer.ShowRightClick(event.Position)
			end
		end)
		selection.Changed:Connect(Explorer.UpdateSelectionVisuals)
		local previousSelection = selection.Map
		selection.Changed:Connect(function()
			local old = previousSelection
			previousSelection = selection.Map
			if selectingRow or Explorer.BoxSelecting or Explorer.Dragging or renamingNode then
				return
			end
			for _, node in ipairs(selection.List) do
				if not old[node] then
					local index = visibleIndices[node]
					if index and (index - 1 < Explorer.Index or index - 1 >= Explorer.Index + scrollV.VisibleSpace) then
						Explorer.ViewNode(node, nil, true)
					end
					break
				end
			end
		end)

		window.GuiElems.Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if Explorer.Active then
				resizeView:Push(true)
			end
		end)
		local function resumeTree()
			Explorer.Active = true
			Explorer.UpdateSearchSpinner()
			characterSearch.Schedule()
			if Explorer.SearchInputPending and window:IsVisible() then
				Explorer.DoSearch(Explorer.GuiElems.SearchBar.Text)
				return
			end
			Explorer.UpdateView()
			Explorer.Update()
			Explorer.Refresh()
		end
		window.OnActivate:Connect(resumeTree)
		window.OnRestore:Connect(resumeTree)
		window.OnDeactivate:Connect(function()
			Explorer.Active = false
			Explorer.UpdateSearchSpinner()
			if Explorer.ScrollBarBorders then
				Explorer.ScrollBarBorders.Update()
			end
		end)
		window.OnMinimize:Connect(function()
			Explorer.Active = false
			Explorer.UpdateSearchSpinner()
			if Explorer.ScrollBarBorders then
				Explorer.ScrollBarBorders.Update()
			end
		end)

		autoUpdateSearch = Settings.Explorer.AutoUpdateSearch

		nodes[game] = { Obj = game }
		expanded[nodes[game]] = true

		if env.getnilinstances and Settings.Explorer.ShowNilInstances ~= false then
			nodes[nilNode.Obj] = nilNode
		end

		Explorer.SetupConnections()

		local insts = getDescendants(game)
		Explorer.InitialObjectCount = #insts
		if Main.Elevated then
			for i = 1, #insts do
				local obj = insts[i]
				if Main.SelectionGeometryRoots and Main.SelectionGeometryRoots[obj] then
					continue
				end
				local par = nodes[obj.Parent]
				if not par then
					continue
				end
				local newNode = {
					Obj = obj,
					Parent = par,
				}
				nodes[obj] = newNode
				indexEvidenceCandidate(obj, newNode)
				par[#par + 1] = newNode
			end
		else
			for i = 1, #insts do
				local obj = insts[i]
				if Main.SelectionGeometryRoots and Main.SelectionGeometryRoots[obj] then
					continue
				end
				local s, parObj = pcall(readParent, obj)
				local par = nodes[parObj]
				if not par then
					continue
				end
				local newNode = {
					Obj = obj,
					Parent = par,
				}
				nodes[obj] = newNode
				indexEvidenceCandidate(obj, newNode)
				par[#par + 1] = newNode
			end
		end
		Explorer.InitNilInstances()
		characterSearch.Schedule()
	end

	return Explorer
end

return { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
