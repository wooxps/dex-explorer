--!strict

local oldgame = oldgame or game
local game = workspace.Parent

cloneref = cloneref
	or function(ref)
		if not getreg then
			return ref
		end

		local InstanceList

		local a = Instance.new("Part")
		for _, c in pairs(getreg()) do
			if type(c) == "table" and #c then
				if rawget(c, "__mode") == "kvs" then
					for d, e in pairs(c) do
						if e == a then
							InstanceList = c
							break
						end
					end
				end
			end
		end
		local f = {}
		function f.invalidate(g)
			if not InstanceList then
				return
			end
			for b, c in pairs(InstanceList) do
				if c == g then
					InstanceList[b] = nil
					return g
				end
			end
		end
		return f.invalidate
	end

local isFsSupported = readfile and writefile and isfile and isfolder and listfiles and delfile and delfolder

local Main,
	Explorer,
	Properties,
	ScriptViewer,
	Console,
	SaveInstance,
	ModelViewer,
	DefaultSettings,
	Notebook,
	Serializer,
	Lib
local ggv = getgenv or nil
local API, RMD

DefaultSettings = (function()
	local rgb = Color3.fromRGB

	return {
		StudioThemeVersion = 4,
		Explorer = {
			_Recurse = true,
			Sorting = true,
			TeleportToOffset = Vector3.new(0, 0, 0),
			ClickToRename = false,
			RowHeight = 20,
			IndentGuides = true,
			AutoUpdateSearch = true,
			IncrementNames = false,
			ExpandHierarchy = true,
			AutoUpdateMode = 0,
			PartSelectionBox = true,
			GuiSelectionBox = true,
			CopyPathUseGetChildren = true,
			ShowNilInstances = false,
			ShowHiddenInsertClasses = false,
			ShowDeprecatedInsertClasses = false,
		},
		Properties = {
			_Recurse = true,
			MaxConflictCheck = 50,
			ShowDeprecated = false,
			ShowHidden = false,
			ClearOnFocus = false,
			LoadstringInput = true,
			NumberRounding = 3,
			ShowAttributes = true,
			MaxAttributes = 50,
			ScaleType = 1,
		},
		Theme = {
			_Recurse = true,
			Main1 = rgb(31, 32, 36),
			Main2 = rgb(31, 32, 36),
			Outline1 = rgb(33, 33, 33),
			Outline2 = rgb(55, 55, 55),
			Outline3 = rgb(30, 30, 30),
			TextBox = rgb(50, 51, 57),
			Menu = rgb(25, 27, 31),
			ListSelection = rgb(0, 39, 184),
			SelectionContext = rgb(20, 29, 62),
			Focus = rgb(51, 95, 255),
			Brand = rgb(60, 100, 250),
			SurfaceOutline = rgb(255, 255, 255),
			SurfaceOutlineTransparency = 0.88,
			TintDisabledIcons = false,
			IconTheme = "Dark",
			SelectionProfile = "Reference",
			StudioSelection = rgb(0, 92, 181),
			Guide = rgb(61, 63, 69),
			Button = rgb(60, 60, 60),
			ButtonHover = rgb(68, 68, 68),
			ExplorerHover = rgb(43, 45, 50),
			ButtonPress = rgb(40, 40, 40),
			Highlight = rgb(75, 75, 75),
			Text = rgb(213, 215, 221),
			SelectedText = rgb(238, 239, 241),
			DisabledText = rgb(105, 106, 109),
			PlaceholderText = rgb(187, 188, 190),
			Important = rgb(255, 0, 0),
			ExplorerIconMap = "",
			MiscIconMap = "",
			Syntax = {
				Text = rgb(204, 204, 204),
				Background = rgb(36, 36, 36),
				Selection = rgb(255, 255, 255),
				SelectionBack = rgb(11, 90, 175),
				Operator = rgb(204, 204, 204),
				Number = rgb(255, 198, 0),
				String = rgb(173, 241, 149),
				Comment = rgb(102, 102, 102),
				Keyword = rgb(248, 109, 124),
				Error = rgb(255, 0, 0),
				FindBackground = rgb(141, 118, 0),
				MatchingWord = rgb(85, 85, 85),
				BuiltIn = rgb(132, 214, 247),
				CurrentLine = rgb(45, 50, 65),
				LocalMethod = rgb(253, 251, 172),
				LocalProperty = rgb(97, 161, 241),
				Nil = rgb(255, 198, 0),
				Bool = rgb(255, 198, 0),
				Function = rgb(248, 109, 124),
				Local = rgb(248, 109, 124),
				Self = rgb(248, 109, 124),
				FunctionName = rgb(253, 251, 172),
				Bracket = rgb(204, 204, 204),
			},
		},
		Window = {
			TitleOnMiddle = true,
			Transparency = 0,
		},
		Interface = {
			_Recurse = true,
			FocusGameInput = false,
			FocusIndicator = false,
			AntiAFK = true,
		},
		RemoteBlockWriteAttribute = false,
		ClassIcon = "NewDark",
	}
end)()

local function copySettings(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = copySettings(child)
	end
	return result
end
local Settings = copySettings(DefaultSettings)
local Apps = {}
local env = {}

local service = setmetatable({}, {
	__index = function(self, name)
		local serv = cloneref(game:GetService(name))
		self[name] = serv
		return serv
	end,
})
local plr = service.Players.LocalPlayer or service.Players.PlayerAdded:wait()

local create = function(data)
	local insts = {}
	for i, v in pairs(data) do
		insts[v[1]] = Instance.new(v[2])
	end

	for _, v in pairs(data) do
		for prop, val in pairs(v[3]) do
			if type(val) == "table" then
				insts[v[1]][prop] = insts[val[1]]
			else
				insts[v[1]][prop] = val
			end
		end
	end

	for _, inst in pairs(insts) do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			if inst.Font == Enum.Font.SourceSans then
				inst.Font = Enum.Font.BuilderSans
			end
			if inst.Font == Enum.Font.SourceSansBold then
				inst.Font = Enum.Font.BuilderSansBold
			end
		end
	end
	return insts[1]
end

local createSimple = function(class, props)
	local inst = Instance.new(class)
	for i, v in next, props do
		inst[i] = v
	end
	return inst
end

Main = (function()
	local Main = {}

	Main.ModuleList = {
		"PerformanceRuntime",
		"EditorBuffer",
		"React",
		"Signal",
		"PropertyChanges",
		"LoadingSplash",
		"AntiAFK",
		"History",
		"SelectionService",
		"LocalizationCsv",
		"GltfGeometry",
		"GltfTerrain",
		"GltfFacs",
		"GltfTextures",
		"GltfExporter",
		"ObjExporter",
		"StudioPopup",
		"ExplorerFileActions",
		"SolidModeling",
		"ReflectionService",
		"TransformSession",
		"TransformGizmo",
		"GuiTransformSession",
		"GuiAlignment",
		"GuiTransformView",
		"GuiTransformTools",
		"TransformTools",
		"EditingService",
		"InsertionService",
		"SearchNameIndex",
		"SearchQuery",
		"ExplorerPolicy",
		"ExplorerProjection",
		"ExplorerSiblingSort",
		"SearchBits",
		"SearchPostings",
		"SearchSnapshot",
		"SearchResults",
		"SearchTreeResults",
		"ExplorerSearch",
		"IconAppearance",
		"RowStatus",
		"GradualEdgeScroll",
		"ServiceVisibility",
		"ServiceVisibilityDialog",
		"InsertObjectOverlay",
		"IndentGuides",
		"NodeDetailsPlaceholder",
		"UnderlaysRow",
		"RenameBox",
		"BoxSelectIndicator",
		"DragDropIndicator",
		"ExplorerNodeRow",
		"SearchBar",
		"Dropdown",
		"SearchBrowserButton",
		"TooltipActions",
		"SearchBox",
		"ContextMenu",
		"ScrollingView",
		"SessionView",
		"InstancePath",
		"InsertObjectMenu",
		"SelectionGeometryMask",
		"SelectionRenderer",
		"WindowLayout",
		"ExplorerQuickActions",
		"ModuleReconstruction",
		"ReconstructorEvidence",
		"ServerReferenceAnalysis",
		"BytecodeStrings",
		"BytecodePaths",
		"RetainedFunctionEvidence",
		"ScriptEvidenceReader",
		"ReconstructorSession",
		"ExplorerInferenceOverlay",
		"Reconstructor",
		"StudioPropertiesView",
		"PropertyColumnSplitter",
		"PropertyValueCodec",
		"PropertySchema",
		"PropertyReader",
		"PropertyValueEditors",
		"PropertyValueCell",
		"PropertyRow",
		"EditorNewScript",
		"PreviewCamera",
		"PreviewScene",
		"ReferenceSource",
		"ReferenceScan",
		"ReferenceFinder",
		"ActivitySession",
		"ActivityViewer",
		"EditorHitTest",
		"EditorTabs",
		"StudioMenuDefinition",
		"EditorContextMenu",
		"EditorFolding",
		"StudioEditorSkin",
		"CodeViewport",
		"EditorUndoStack",
		"EditorDocument",
		"EditorSelectionSet",
		"EditorRegex",
		"EditorFindModel",
		"EditorFindWidget",
		"EditorGlobalSearch",
		"EditorGlobalSearchWidget",
		"EditorSymbols",
		"EditorHoverTypes",
		"EditorModuleTypes",
		"EditorBuiltinSignatures",
		"EditorApiDocumentation",
		"EditorDocumentationText",
		"EditorHover",
		"EditorCompletion",
		"EditorSignature",
		"EditorLanguage",
		"EditorDefinitions",
		"EditorFormatter",
		"EditorNavigation",
		"EditorController",
		"BridgeRegistry",
		"BridgeValueCodec",
		"BridgeExtraCommands",
		"BridgeRemoteCommands",
		"BridgeCaptureCommands",
		"BridgeLogCommands",
		"BridgeQueryCommands",
		"BridgeSpatialCommands",
		"BridgeInspectionCommands",
		"BridgeComparisonCommands",
		"BridgeUIDiagnostics",
		"BridgeRuntimeDiagnostics",
		"BridgeConditions",
		"BridgeTestCommands",
		"BridgeCommandRouter",
		"BridgeClient",
		"BridgeUI",
		"BridgeConnectionView",
		"BridgeSetupView",
		"BridgeActivityView",
		"BridgeCommandCatalog",
		"BridgeCommandsView",
		"AIBridge",
		"AssetCatalog",
		"AssetQuery",
		"AssetDownload",
		"AssetRig",
		"AssetPlayback",
		"AssetPreview",
		"AssetRows",
		"AssetManager",
		"MacroEngine",
		"MacroStore",
		"InputMacros",
		"PluginRuntime",
		"PluginActions",
		"PluginManager",
		"PluginOutput",
		"PluginToolbar",
		"Explorer",
		"Properties",
		"ScriptViewer",
		"Console",
		"SaveInstance",
		"ModelViewer",
	}
	Main.Elevated = false
	Main.AllowDraggableOnMobile = true
	Main.MissingEnv = {}
	Main.Version = "2.2 · Studio UI"
	Main.Mouse = plr:GetMouse()
	Main.AppControls = {}
	Main.Apps = Apps
	Main.MenuApps = {}
	Main.InternalGuis = setmetatable({}, { __mode = "k" })
	Main.GitRepoName = "AZYsGithub/DexPlusPlus"

	Main.Alive = true
	Main.GlobalConnections = {}
	Main.CleanupCallbacks = {}

	Main.FocusIndicators = setmetatable({}, { __mode = "k" })
	Main.GuiFocusOwners = setmetatable({}, { __mode = "k" })
	Main.ActiveFocusOwner = nil

	Main.RegisterGuiFocusOwner = function(gui, owner)
		if gui then
			Main.GuiFocusOwners[gui] = owner
		end
	end

	Main.FocusOwnerForObject = function(object)
		local current = object
		while current do
			local owner = Main.GuiFocusOwners[current]
			if owner then
				return owner
			end
			current = current.Parent
		end
	end

	Main.RegisterFocusIndicator = function(owner, setVisible)
		if owner and type(setVisible) == "function" then
			Main.FocusIndicators[owner] = setVisible
		end
	end

	Main.UpdateFocusIndicator = function()
		local enabled = Main.Alive and Settings.Interface.FocusIndicator
		for owner, setVisible in pairs(Main.FocusIndicators) do
			pcall(setVisible, enabled and owner == Main.ActiveFocusOwner)
		end
	end

	Main.SetFocusOwner = function(owner)
		Main.ActiveFocusOwner = owner
		Main.UpdateFocusIndicator()
	end

	Main.TrackSignal = function(signal, callback)
		if not Main.Alive then
			return { Disconnect = function() end }
		end
		local connections = Main.GlobalConnections
		if #connections >= (Main.ConnectionSweepAt or 256) then
			local write = 1
			for read = 1, #connections do
				local item = connections[read]
				local ok, connected = pcall(function()
					return item.Connected
				end)
				if not ok or connected ~= false then
					connections[write] = item
					write += 1
				end
			end
			for i = #connections, write, -1 do
				connections[i] = nil
			end
			Main.ConnectionSweepAt = math.max(256, #connections * 2)
		end
		local con = signal:Connect(callback)
		Main.GlobalConnections[#Main.GlobalConnections + 1] = con
		return con
	end

	Main.AddCleanup = function(callback)
		if type(callback) == "function" then
			Main.CleanupCallbacks[#Main.CleanupCallbacks + 1] = callback
		end
	end

	Main.Shutdown = function()
		if not Main.Alive then
			return
		end
		Main.Alive = false

		for i = #Main.CleanupCallbacks, 1, -1 do
			pcall(Main.CleanupCallbacks[i])
		end
		table.clear(Main.CleanupCallbacks)

		if Main.MainGuiMouseEvent then
			pcall(function()
				Main.MainGuiMouseEvent:Disconnect()
			end)
			Main.MainGuiMouseEvent = nil
		end

		for i = #Main.GlobalConnections, 1, -1 do
			local con = Main.GlobalConnections[i]
			pcall(function()
				con:Disconnect()
			end)
		end
		table.clear(Main.GlobalConnections)

		local guis = {}
		for gui in pairs(Main.InternalGuis) do
			guis[#guis + 1] = gui
		end
		for _, gui in ipairs(guis) do
			pcall(function()
				gui:Destroy()
			end)
			Main.InternalGuis[gui] = nil
		end

		Main.MainGui = nil
		Main.MainGuiOpen = false
		Main.ActiveFocusOwner = nil
		table.clear(Main.FocusIndicators)
		table.clear(Main.GuiFocusOwners)
	end

	Main.DisplayOrders = {
		SideWindow = 8,
		Window = 10,
		Menu = 100000,
		Core = 101000,
	}


	Main.GetRandomString = function()
		local output = ""
		for i = 2, 25 do
			output = output .. string.char(math.random(1, 250))
		end

		return output
	end

	Main.SecureGui = function(gui)
		if not Main.Alive then
			pcall(function()
				gui:Destroy()
			end)
			return
		end
		Main.InternalGuis[gui] = true
		gui.Name = Main.GetRandomString()
		if gethui then
			gui.Parent = gethui()
		elseif syn and syn.protect_gui then
			syn.protect_gui(gui)
			gui.Parent = service.CoreGui
		elseif protect_gui then
			protect_gui(gui)
			gui.Parent = service.CoreGui
		elseif protectgui then
			protectgui(gui)
			gui.Parent = service.CoreGui
		else
			if Main.Elevated then
				gui.Parent = service.CoreGui
			else
				gui.Parent = service.Players.LocalPlayer:WaitForChild("PlayerGui")
			end
		end
	end

	Main.GameInputLocked = false
	Main.InputLockActionNames = {}
	Main.InputLockPriority = 10000000
	Main.InputLockActionPrefix = "__DexPlusInputLock_"
		.. tostring(math.floor(os.clock() * 1000000))
		.. "_"
		.. tostring(math.random(1, 1000000000))
		.. "_"

	Main.IsDexGuiObject = function(object)
		local current = object
		while current do
			if Main.InternalGuis[current] then
				return true
			end
			current = current.Parent
		end
		return false
	end

	local function isMeaningfulDexHit(object)
		if not object or not Main.IsDexGuiObject(object) then
			return false
		end
		local ancestor = object
		while ancestor do
			if Main.InternalGuis[ancestor] and ancestor.Parent == nil then
				return false
			end
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				return false
			end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then
				return false
			end
			if Main.FocusIgnoredGuis and Main.FocusIgnoredGuis[ancestor] then
				return false
			end
			ancestor = ancestor.Parent
		end
		local ok, result = pcall(function()
			if not object:IsA("GuiObject") or not object.Visible then
				return false
			end
			if object:IsA("Frame") or object:IsA("ScrollingFrame") then
				return object.Active or object.BackgroundTransparency < 0.995 or object.BorderSizePixel > 0
			elseif object:IsA("CanvasGroup") then
				return object.Active or object.GroupTransparency < 0.995 or object.BackgroundTransparency < 0.995
			end
			return true
		end)
		return ok and result or false
	end

	local function pointInGuiObject(object, x, y)
		local ok, result = pcall(function()
			if not object:IsA("GuiObject") or not object.Visible then
				return false
			end
			local p, size = object.AbsolutePosition, object.AbsoluteSize
			if x < p.X or x >= p.X + size.X or y < p.Y or y >= p.Y + size.Y then
				return false
			end
			local current = object
			while current do
				if current:IsA("GuiObject") and not current.Visible then
					return false
				end
				if current:IsA("ScreenGui") and not current.Enabled then
					return false
				end
				if Main.InternalGuis[current] then
					return current.Parent ~= nil
				end
				current = current.Parent
			end
			return false
		end)
		return ok and result or false
	end

	local guiHitSnapshots = setmetatable({}, { __mode = "k" })
	local function guiHitCandidates(gui)
		local snapshot = guiHitSnapshots[gui]
		if not snapshot then
			snapshot = { Dirty = true }
			guiHitSnapshots[gui] = snapshot
			local function invalidate()
				snapshot.Dirty = true
			end
			local ok = pcall(function()
				Main.TrackSignal(gui.DescendantAdded, invalidate)
				Main.TrackSignal(gui.DescendantRemoving, invalidate)
				Main.TrackSignal(gui.Destroying, function()
					guiHitSnapshots[gui] = nil
					snapshot.Items = nil
					snapshot.Roots = nil
				end)
			end)
			snapshot.Uncached = not ok
		end
		if snapshot.Dirty or snapshot.Uncached then
			local candidates, records, roots = {}, {}, {}
			for _, object in ipairs(gui:GetDescendants()) do
				if object:IsA("GuiObject") then
					candidates[#candidates + 1] = object
					records[object] = { Object = object, Children = {} }
				end
			end
			for _, object in ipairs(candidates) do
				local parent = object.Parent
				while parent and parent ~= gui and not records[parent] do
					parent = parent.Parent
				end
				local siblings = records[parent] and records[parent].Children or roots
				siblings[#siblings + 1] = records[object]
			end
			snapshot.Items = candidates
			snapshot.Roots = roots
			snapshot.Dirty = false
		end
		return snapshot.Items, snapshot.Roots
	end
	Main.AddCleanup(function()
		table.clear(guiHitSnapshots)
	end)
	local function findGuiHit(branches, x, y)
		for _, branch in ipairs(branches) do
			local object = branch.Object
			if not object.Visible then
				continue
			end
			local p, size = object.AbsolutePosition, object.AbsoluteSize
			local inside = x >= p.X and x < p.X + size.X and y >= p.Y and y < p.Y + size.Y
			if inside and pointInGuiObject(object, x, y) and isMeaningfulDexHit(object) then
				return object
			end
			if not inside and object.ClipsDescendants then
				continue
			end
			local hit = findGuiHit(branch.Children, x, y)
			if hit then
				return hit
			end
		end
	end
	Main.IsPointInDexUI = function(x, y)
		local roots = {}
		pcall(function()
			local playerGui = service.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				roots[#roots + 1] = playerGui
			end
		end)
		pcall(function()
			roots[#roots + 1] = service.CoreGui
		end)
		pcall(function()
			if gethui then
				local hidden = gethui()
				local duplicate = false
				for _, root in ipairs(roots) do
					if root == hidden then
						duplicate = true
						break
					end
				end
				if hidden and not duplicate then
					roots[#roots + 1] = hidden
				end
			end
		end)

		for _, root in ipairs(roots) do
			local ok, objects = pcall(function()
				return root:GetGuiObjectsAtPosition(x, y)
			end)
			if ok and type(objects) == "table" then
				for _, object in ipairs(objects) do
					if isMeaningfulDexHit(object) then
						return true, Main.FocusOwnerForObject(object)
					end
				end
			end
		end

		for gui in pairs(Main.InternalGuis) do
			if gui.Parent == nil then
				continue
			end
			if Main.FocusIgnoredGuis and Main.FocusIgnoredGuis[gui] then
				continue
			end
			local enabled = true
			pcall(function()
				enabled = gui.Enabled
			end)
			if enabled then
				local ok, descendants, branches = pcall(guiHitCandidates, gui)
				if ok then
					local readable, hit = pcall(findGuiHit, branches, x, y)
					if readable and hit then
						return true, Main.FocusOwnerForObject(hit)
					end
					if not readable then
						for _, object in ipairs(descendants) do
							if pointInGuiObject(object, x, y) and isMeaningfulDexHit(object) then
								return true, Main.FocusOwnerForObject(object)
							end
						end
					end
				end
			end
		end
		return false, nil
	end

	local function unbindGameInputLock()
		local cas = service.ContextActionService
		for _, name in ipairs(Main.InputLockActionNames) do
			pcall(function()
				cas:UnbindAction(name)
			end)
		end
		table.clear(Main.InputLockActionNames)
	end

	local function bindGameInputLock()
		unbindGameInputLock()
		local cas = service.ContextActionService
		local sink = function()
			return Enum.ContextActionResult.Sink
		end

		local inputs = {}
		local seen = {}
		local function addInput(input)
			if input and not seen[input] then
				seen[input] = true
				inputs[#inputs + 1] = input
			end
		end
		pcall(function()
			for _, key in ipairs(Enum.KeyCode:GetEnumItems()) do
				addInput(key)
			end
		end)
		pcall(function()
			for _, action in ipairs(Enum.PlayerActions:GetEnumItems()) do
				addInput(action)
			end
		end)

		local chunkSize = 48
		for first = 1, #inputs, chunkSize do
			local chunk = {}
			for i = first, math.min(first + chunkSize - 1, #inputs) do
				chunk[#chunk + 1] = inputs[i]
			end
			local name = Main.InputLockActionPrefix .. tostring(#Main.InputLockActionNames + 1)
			local ok = pcall(function()
				cas:BindActionAtPriority(name, sink, false, Main.InputLockPriority, table.unpack(chunk))
			end)
			if ok then
				Main.InputLockActionNames[#Main.InputLockActionNames + 1] = name
			end
		end

		local pointerName = Main.InputLockActionPrefix .. "Pointer"
		local pointerHandler = function(_, state, input)
			if not Main.GameInputLocked then
				return Enum.ContextActionResult.Pass
			end
			if
				state == Enum.UserInputState.Begin
				and input
				and input.UserInputType == Enum.UserInputType.MouseButton2
			then
				local pos = input.Position
				if pos and not Main.IsPointInDexUI(pos.X, pos.Y) then
					Main.SetFocusOwner(nil)
					Main.SetGameInputLocked(false)
					return Enum.ContextActionResult.Pass
				end
			end
			return Enum.ContextActionResult.Sink
		end
		local ok = pcall(function()
			cas:BindActionAtPriority(
				pointerName,
				pointerHandler,
				false,
				Main.InputLockPriority,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseButton3,
				Enum.UserInputType.MouseWheel
			)
		end)
		if ok then
			Main.InputLockActionNames[#Main.InputLockActionNames + 1] = pointerName
		end
	end

	Main.SetGameInputLocked = function(locked)
		local focusEnabled = not Settings.Interface or Settings.Interface.FocusGameInput ~= false
		locked = locked and Main.Alive and focusEnabled
		if Main.GameInputLocked == locked then
			return
		end
		Main.GameInputLocked = locked
		if locked then
			bindGameInputLock()
		else
			unbindGameInputLock()
		end
	end

	Main.InitGameInputFocus = function()
		if Main.GameInputFocusInitialized then
			return
		end
		Main.GameInputFocusInitialized = true
		local inputService = service.UserInputService

		Main.TrackSignal(inputService.InputBegan, function(input)
			local kind = input.UserInputType
			if
				kind ~= Enum.UserInputType.MouseButton1
				and kind ~= Enum.UserInputType.MouseButton2
				and kind ~= Enum.UserInputType.Touch
			then
				return
			end
			local pos = input.Position
			if not pos then
				return
			end
			local inside, owner = Main.IsPointInDexUI(pos.X, pos.Y)
			if Apps.TransformTools and (Apps.TransformTools.Dragging or Apps.TransformTools.GuiDragging) then
				return
			end
			if inside and owner then
				Main.SetFocusOwner(owner)
			elseif not inside and Main.ActiveFocusOwner then
				Main.SetFocusOwner(nil)
			end
			Main.SetGameInputLocked(inside)
		end)

		pcall(function()
			Main.TrackSignal(inputService.TextBoxFocused, function(textBox)
				if Main.IsDexGuiObject(textBox) then
					local owner = Main.FocusOwnerForObject(textBox)
					if owner then
						Main.SetFocusOwner(owner)
					end
					Main.SetGameInputLocked(true)
				end
			end)
		end)

		Main.AddCleanup(function()
			Main.GameInputLocked = false
			unbindGameInputLock()
		end)
	end

	Main.GetInitDeps = function()
		return {
			Main = Main,
			Game = game,
			Task = task,
			Lib = Lib,
			Apps = Apps,
			Settings = Settings,

			API = API,
			RMD = RMD,
			env = env,
			service = service,
			plr = plr,
			create = create,
			createSimple = createSimple,
		}
	end

	Main.Error = function(str)
		if rconsoleprint then
			rconsoleprint("DEX ERROR: " .. tostring(str) .. "\n")
			wait(9e9)
		else
			error(str)
		end
	end

	Main.LoadModule = function(name: string)
		local began = os.clock()
		if Main.StartupStatus then
			local path = DexRuntime and DexRuntime.ModulePaths[name]
			Main.StartupStatus("Loading " .. (path or name))
		end
		local control
		if EmbeddedModules or Main.Elevated then
			if EmbeddedModules then
				control = EmbeddedModules[name]()

				if gethsfuncs then
					control = _G.moduleData
				end

				if not control then
					Main.Error("Missing Embedded Module: " .. name)
				end
			elseif _G.DebugLoadModel then
				local model = Main.DebugModel
				if not model then
					model = oldgame:GetObjects(getsynasset("AfterModules.rbxm"))[1]
				end

				control = loadstring(model.Modules[name].Source)()
				print("Locally Loaded Module", name, control)
			else
				local hashs = Main.ModuleHashData
				if not hashs then
					local s, hashDataStr = pcall(
						oldgame.HttpGet,
						game,
						"https://api.github.com/repos/" .. Main.GitRepoName .. "/ModuleHashs.dat"
					)
					if not s then
						Main.Error("Failed to get module hashs")
					end

					local s, hashData = pcall(service.HttpService.JSONDecode, service.HttpService, hashDataStr)
					if not s then
						Main.Error("Failed to decode module hash JSON")
					end

					hashs = hashData
					Main.ModuleHashData = hashs
				end

				local hashfunc = (syn and syn.crypt.hash) or function()
					return ""
				end
				local filePath = "dex-explorer/ModuleCache/" .. name .. ".lua"
				local s, moduleStr = pcall(env.readfile, filePath)

				if s and hashfunc(moduleStr) == hashs[name] then
					control = loadstring(moduleStr)()
				else
					local s, moduleStr = pcall(
						oldgame.HttpGet,
						game,
						"https://api.github.com/repos/" .. Main.GitRepoName .. "/Modules/" .. name .. ".lua"
					)
					if not s then
						Main.Error("Failed to get external module data of " .. name)
					end

					env.writefile(filePath, moduleStr)
					control = loadstring(moduleStr)()
				end
			end
		else
			local module = script:WaitForChild("Modules"):WaitForChild(name, 2)
			if not module then
				Main.Error("CANNOT FIND MODULE " .. name)
			end

			control = require(module)
		end

		Main.AppControls[name] = control
		if control.InitDeps then control.InitDeps(Main.GetInitDeps()) end
		local moduleData = control.Main(Apps)
		assert(type(moduleData) == "table", `Module {name} must return its API table`)
		Apps[name] = moduleData
		if Main.Performance then
			Main.Performance.Record("module/" .. name, os.clock() - began)
		end
		return moduleData
	end

	local moduleAppTable
	Main.DeferModule = function(name)
		local loaded, loading, failure
		local function resolve()
			if loaded then
				return loaded
			end
			if failure then
				error(failure, 0)
			end
			assert(not loading, "Circular deferred module: " .. name)
			loading = true
			local ok, value = pcall(function()
				local api = Main.LoadModule(name)
				if moduleAppTable and Main.AppControls[name].InitAfterMain then
					Main.AppControls[name].InitAfterMain(moduleAppTable)
				end
				return api
			end)
			loading = false
			if not ok then
				failure = tostring(value)
				error(failure, 0)
			end
			loaded = value
			return loaded
		end
		return setmetatable({}, {
			__index = function(_, key)
				return resolve()[key]
			end,
			__newindex = function(_, key, value)
				resolve()[key] = value
			end,
		})
	end
	Main.LoadModules = function()
		for i, v in pairs(Main.ModuleList) do
			local optional = v:sub(1, 6) == "Bridge"
				or v:sub(1, 5) == "Asset"
				or v:sub(1, 6) == "Editor"
				or v == "CodeViewport"
				or v == "StudioEditorSkin"
				or v == "StudioMenuDefinition"
				or v == "PreviewCamera"
				or v == "PreviewScene"
				or v == "ReferenceScan"
				or v == "ActivitySession"
				or v == "AIBridge"
				or v == "MacroEngine"
				or v == "MacroStore"
				or v == "InputMacros"
				or v == "PluginManager"
				or v == "PluginOutput"
				or v == "ActivityViewer"
				or v == "ReferenceFinder"
			local s, e = true, nil
			if optional then
				Apps[v] = Main.DeferModule(v)
			else
				s, e = pcall(Main.LoadModule, v)
			end
			if not s then
				Main.Error("FAILED LOADING " .. v .. " CAUSE " .. e)
			end
		end

		Explorer = Apps.Explorer
		Properties = Apps.Properties
		ScriptViewer = Apps.ScriptViewer
		Console = Apps.Console
		SaveInstance = Apps.SaveInstance
		ModelViewer = Apps.ModelViewer
		Notebook = Apps.Notebook

		local appTable = {
			Explorer = Explorer,
			Properties = Properties,
			ScriptViewer = ScriptViewer,
			Console = Console,
			SaveInstance = SaveInstance,
			ModelViewer = ModelViewer,
			Notebook = Notebook,

		}

		moduleAppTable = appTable
		if Main.AppControls.Lib.InitAfterMain then Main.AppControls.Lib.InitAfterMain(appTable) end
		for i, v in pairs(Main.ModuleList) do
			local control = Main.AppControls[v]
			if control and control.InitAfterMain then
				control.InitAfterMain(appTable)
			end
		end
	end

	Main.InitEnv = function()
		setmetatable(env, {
			__newindex = function(self, name, func)
				if not func then
					Main.MissingEnv[#Main.MissingEnv + 1] = name
					return
				end
				rawset(self, name, func)
			end,
		})

		env.MacroInput = {
			keypress = keypress,
			keyrelease = keyrelease,
			mouse1press = mouse1press,
			mouse1release = mouse1release,
			mouse2press = mouse2press,
			mouse2release = mouse2release,
			mouse3press = mouse3press,
			mouse3release = mouse3release,
			mousemoveabs = mousemoveabs,
			mousemoverel = mousemoverel,
			mousescroll = mousescroll,
		}

		env.isonmobile = game:GetService("UserInputService").TouchEnabled

		env.loadstring = (pcall(loadstring, "local a = 1") and loadstring)
			or (
				game:GetService("RunService"):IsStudio()
				and script.Modules:FindFirstChild("Loadstring")
				and require(script.Modules:FindFirstChild("Loadstring"))
			)

		env.isfile = isfile
		env.isfolder = isfolder
		env.readfile = readfile
		env.writefile = writefile
		env.appendfile = appendfile
		env.makefolder = makefolder
		env.delfile = delfile
	env.delfolder = delfolder
	env.listfiles = listfiles
		env.loadfile = loadfile
		env.getcustomasset = getcustomasset or getsynasset or (syn and (syn.getcustomasset or syn.getsynasset))
		env.executorSaveInstance = saveinstance
		env.saveinstance = function(object, filePath, options)
			assert(Apps.SaveInstance, "Save Instance is not ready")
			return Apps.SaveInstance.Export(object, filePath, options)
		end

		env.parsefile = function(name)
			return tostring(name):gsub("[*\\?:<>|]+", ""):sub(1, 175)
		end

		env.getupvalues = debug.getupvalues or getupvalues or getupvals
		env.getconstants = debug.getconstants or getconstants or getconsts
		env.islclosure = islclosure or is_l_closure
		env.checkcaller = checkcaller
		env.getreg = getreg
		env.getgc = getgc
		if type(filtergc) == "function" then
			env.filtergc = filtergc
		end
		if type(getscripthash) == "function" then
			env.getscripthash = getscripthash
		end

		env.hookfunction = hookfunction
		env.hookmetamethod = hookmetamethod

		env.getscriptbytecode = getscriptbytecode
		env.gethiddenproperty = gethiddenproperty or gethiddenprop
		env.setfflag = setfflag
		env.protectgui = protect_gui or (syn and syn.protect_gui)
		env.gethui = gethui
		env.firesignal = firesignal
		env.fireclickdetector = fireclickdetector
		env.fireproximityprompt = fireproximityprompt
		env.Drawing = Drawing
		env.crypt = crypt
		env.getfpscap = getfpscap
		env.setfpscap = setfpscap
		env.setclipboard = setclipboard
		env.getclipboard = getclipboard or get_clipboard
		env.getnilinstances = getnilinstances or get_nil_instances
		env.getloadedmodules = getloadedmodules

		env.isViableDecompileScript = function(obj)
			if obj:IsA("ModuleScript") then
				return true
			elseif
				obj:IsA("LocalScript")
				and (obj.RunContext == Enum.RunContext.Client or obj.RunContext == Enum.RunContext.Legacy)
			then
				return true
			elseif obj:IsA("Script") and obj.RunContext == Enum.RunContext.Client then
				return true
			end
			return false
		end
		env.request = (syn and syn.request)
			or (http and http.request)
			or http_request
			or (fluxus and fluxus.request)
			or request

		env.decompile = decompile
			or (function()

				if not env.getscriptbytecode then
					return
				end

				local API = "http://api.plusgiant5.com"

				local last_call = 0

				local request = env.request

				local function call(konstantType, scriptPath)
					local success, bytecode = pcall(env.getscriptbytecode, scriptPath)

					if not success then
						return `-- Failed to get script bytecode, error:\n\n--[[\n{bytecode}\n--]]`
					end

					local time_elapsed = os.clock() - last_call
					if time_elapsed <= 0.5 then
						task.wait(0.5 - time_elapsed)
					end

					local httpResult = request({
						Url = API .. konstantType,
						Body = bytecode,
						Method = "POST",
						Headers = {
							["Content-Type"] = "text/plain",
						},
					})

					last_call = os.clock()

					if httpResult.StatusCode ~= 200 then
						return `-- Error occurred while requesting Konstant API, error:\n\n--[[\n{httpResult.Body}\n--]]`
					else
						return httpResult.Body
					end
				end

				local function decompile(scriptPath)
					return call("/konstant/decompile", scriptPath)
				end

				getgenv().decompile = decompile

				env.decompile = decompile
				return decompile
			end)()

		if identifyexecutor then
			Main.Executor = identifyexecutor()
		end

		Main.GuiHolder = Main.Elevated and service.CoreGui or plr:FindFirstChildOfClass("PlayerGui")

		setmetatable(env, nil)
	end

	Main.IncompatibleTest = function()
	end

	local function serialize(val)
		if typeof(val) == "Color3" then
			local serializedColor = {}
			serializedColor.R = val.R
			serializedColor.G = val.G
			serializedColor.B = val.B
			return serializedColor
		else
			return val
		end
	end

	local function deserialize(val)
		if typeof(val) == "table" then
			if val.R and val.G and val.B then
				return Color3.new(val.R, val.G, val.B)
			else
				return val
			end
		else
			return val
		end
	end

	Main.ExportSettings = function()
		local rawData = Settings or DefaultSettings

		local function recur(tbl)
			local newTbl = {}
			for i, v in pairs(tbl) do
				if typeof(v) == "table" then
					newTbl[i] = recur(v)
				else
					newTbl[i] = serialize(v)
				end
			end
			return newTbl
		end

		local serializedData = recur(rawData)

		local s, json = pcall(service.HttpService.JSONEncode, service.HttpService, serializedData)
		if s and json then
			return json
		end
	end

	local settingsPath = "dex-explorer/settings.json"

	Main.SaveSettings = function()
		if not env.writefile then
			return false
		end
		local json = Main.ExportSettings()
		if not json then
			return false
		end
		return pcall(env.writefile, settingsPath, json)
	end


	Main.LoadSettings = function()
		local s, data = pcall(env.readfile or error, settingsPath)
		if s and type(data) == "string" and data ~= "" then
			local s, decoded = pcall(service.HttpService.JSONDecode, service.HttpService, data)
			if s and type(decoded) == "table" then
				local function recur(tbl)
					local newTbl = {}
					for i, v in pairs(tbl) do
						if typeof(v) == "table" then
							newTbl[i] = deserialize(recur(v))
						else
							newTbl[i] = deserialize(v)
						end
					end
					return newTbl
				end

				local deserializedData = recur(decoded)
				local function merge(target, source)
					for k, v in pairs(source) do
						if type(target[k]) == "table" then
							if type(v) == "table" then
								merge(target[k], v)
							end
						elseif target[k] == nil or typeof(v) == typeof(target[k]) then
							target[k] = v
						end
					end
				end
				merge(Settings, deserializedData)
				if deserializedData.StudioThemeVersion ~= 3 and deserializedData.StudioThemeVersion ~= 4 then
					Settings.Theme = copySettings(DefaultSettings.Theme)
					if deserializedData.StudioThemeVersion ~= 2 then
						Settings.Window = copySettings(DefaultSettings.Window)
					end
				end
				if deserializedData.StudioThemeVersion ~= 4 then
					Settings.Theme.ListSelection = DefaultSettings.Theme.ListSelection
					Settings.Theme.SelectionContext = DefaultSettings.Theme.SelectionContext
					Settings.StudioThemeVersion = 4
				end
			else
				warn("failed to decode settings json")
			end
		else
			Main.ResetSettings()
		end
	end

	Main.ResetSettings = function()
		local function recur(t, res)
			for set, val in pairs(t) do
				if type(val) == "table" and val._Recurse then
					if type(res[set]) ~= "table" then
						res[set] = {}
					end
					recur(val, res[set])
				else
					res[set] = val
				end
			end
			return res
		end
		recur(DefaultSettings, Settings)
	end

	Main.FetchAPI = function(callbackiflong, callbackiftoolong, XD, onProgress)
		local downloaded = false
		local api, rawAPI
		local function decode(candidate)
			if type(candidate) ~= "string" or candidate == "" then
				return nil
			end
			local ok, value = pcall(service.HttpService.JSONDecode, service.HttpService, candidate)
			if
				not ok
				or type(value) ~= "table"
				or type(value.Classes) ~= "table"
				or type(value.Enums) ~= "table"
				or #value.Classes == 0
			then
				return nil
			end
			return value
		end
		if Main.Elevated then
			if Main.LocalDepsUpToDate() then
				if onProgress then
					onProgress("Reading dex-explorer/rbx_api.dat")
				end
				local localAPI = Lib.ReadFile("dex-explorer/rbx_api.dat")
				api = decode(localAPI)
				if api then
					rawAPI = localAPI
				else
					Main.DepsVersionData[1] = ""
				end
			end
			task.spawn(function()
				task.wait(10)
				if not downloaded and callbackiflong then
					callbackiflong()
				end

				task.wait(20)
				if not downloaded and callbackiftoolong then
					callbackiftoolong()
				end

				task.wait(30)
				if not downloaded and XD then
					XD()
				end
			end)
			if not api then
				local endpoints = {
					"https://setup.rbxcdn.com/" .. Main.RobloxVersion .. "-API-Dump.json",
					"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json",
				}
				for _, endpoint in ipairs(endpoints) do
					if onProgress then
						onProgress("Downloading " .. endpoint:match("([^/]+)$"))
					end
					local ok, response = pcall(game.HttpGet, game, endpoint, true)
					api = ok and decode(response) or nil
					if api then
						rawAPI = response
						break
					end
				end
			end
		else
			if script:FindFirstChild("API") then
				rawAPI = require(script.API)
			else
				error("NO API EXISTS")
			end
		end
		downloaded = true

		api = api or decode(rawAPI)
		if not api then
			error("Roblox API metadata was unavailable or invalid; please try loading Dex again")
		end
		Main.RawAPI = rawAPI
		if onProgress then
			onProgress("Reading API-Dump.json")
		end

		local classes, enums = {}, {}
		local categoryOrder, seenCategories = {}, {}

		local function insertAbove(t, item, aboveItem)
			local findPos = table.find(t, item)
			if not findPos then
				return
			end
			table.remove(t, findPos)

			local pos = table.find(t, aboveItem)
			if not pos then
				return
			end
			table.insert(t, pos, item)
		end

		for _, class in pairs(api.Classes) do
			local newClass = {}
			newClass.Name = class.Name
			newClass.Superclass = class.Superclass
			newClass.Properties = {}
			newClass.Functions = {}
			newClass.Events = {}
			newClass.Callbacks = {}
			newClass.Tags = {}

			if class.Tags then
				for c, tag in pairs(class.Tags) do
					newClass.Tags[tag] = true
				end
			end
			for __, member in pairs(class.Members) do
				local newMember = {}
				newMember.Name = member.Name
				newMember.Class = class.Name
				newMember.Security = member.Security
				newMember.Tags = {}
				if member.Tags then
					for c, tag in pairs(member.Tags) do
						newMember.Tags[tag] = true
					end
				end

				local mType = member.MemberType
				if mType == "Property" then
					local propCategory = member.Category or "Other"
					propCategory = propCategory:match("^%s*(.-)%s*$")
					if not seenCategories[propCategory] then
						categoryOrder[#categoryOrder + 1] = propCategory
						seenCategories[propCategory] = true
					end
					newMember.ValueType = member.ValueType
					newMember.Category = propCategory
					newMember.Serialization = member.Serialization
					table.insert(newClass.Properties, newMember)
				elseif mType == "Function" then
					newMember.Parameters = {}
					newMember.ReturnType = member.ReturnType.Name
					for c, param in pairs(member.Parameters) do
						table.insert(newMember.Parameters, { Name = param.Name, Type = param.Type.Name })
					end
					table.insert(newClass.Functions, newMember)
				elseif mType == "Event" then
					newMember.Parameters = {}
					for c, param in pairs(member.Parameters) do
						table.insert(newMember.Parameters, { Name = param.Name, Type = param.Type.Name })
					end
					table.insert(newClass.Events, newMember)
				end
			end

			classes[class.Name] = newClass
		end

		for _, class in pairs(classes) do
			class.Superclass = classes[class.Superclass]
		end

		for _, enum in pairs(api.Enums) do
			local newEnum = {}
			newEnum.Name = enum.Name
			newEnum.Items = {}
			newEnum.Tags = {}

			if enum.Tags then
				for c, tag in pairs(enum.Tags) do
					newEnum.Tags[tag] = true
				end
			end
			for __, item in pairs(enum.Items) do
				local newItem = {}
				newItem.Name = item.Name
				newItem.Value = item.Value
				table.insert(newEnum.Items, newItem)
			end

			enums[enum.Name] = newEnum
		end

		local function getMember(class, member)
			if not classes[class] or not classes[class][member] then
				return
			end
			local result = {}

			local currentClass = classes[class]
			while currentClass do
				for _, entry in pairs(currentClass[member]) do
					result[#result + 1] = entry
				end
				currentClass = currentClass.Superclass
			end

			table.sort(result, function(a, b)
				return a.Name < b.Name
			end)
			return result
		end

		insertAbove(categoryOrder, "Behavior", "Tuning")
		insertAbove(categoryOrder, "Appearance", "Data")
		insertAbove(categoryOrder, "Attachments", "Axes")
		insertAbove(categoryOrder, "Cylinder", "Slider")
		insertAbove(categoryOrder, "Localization", "Jump Settings")
		insertAbove(categoryOrder, "Surface", "Motion")
		insertAbove(categoryOrder, "Surface Inputs", "Surface")
		insertAbove(categoryOrder, "Part", "Surface Inputs")
		insertAbove(categoryOrder, "Assembly", "Surface Inputs")
		insertAbove(categoryOrder, "Character", "Controls")
		categoryOrder[#categoryOrder + 1] = "Unscriptable"
		categoryOrder[#categoryOrder + 1] = "Attributes"

		local categoryOrderMap = {}
		for i = 1, #categoryOrder do
			categoryOrderMap[categoryOrder[i]] = i
		end

		return {
			Classes = classes,
			Enums = enums,
			CategoryOrder = categoryOrderMap,
			GetMember = getMember,
		}
	end

	Main.FetchRMD = function(onProgress)
		local rawXML
		if Main.Elevated then
			if Main.LocalDepsUpToDate() then
				if onProgress then
					onProgress("Reading dex-explorer/rbx_rmd.dat")
				end
				local localRMD = Lib.ReadFile("dex-explorer/rbx_rmd.dat")
				if localRMD then
					rawXML = localRMD
				else
					Main.DepsVersionData[1] = ""
				end
			end
			if not rawXML then
				if onProgress then
					onProgress("Downloading ReflectionMetadata.xml")
				end
				rawXML = game:HttpGet(
					"https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml"
				)
			end
		else
			if script:FindFirstChild("RMD") then
				rawXML = require(script.RMD)
			else
				error("NO RMD EXISTS")
			end
		end
		Main.RawRMD = rawXML
		if onProgress then
			onProgress("Reading ReflectionMetadata.xml")
		end
		local shared = type(getgenv) == "function" and getgenv() or nil
		local function copy(value)
			if type(value) ~= "table" then
				return value
			end
			local result = {}
			for key, item in pairs(value) do
				result[key] = copy(item)
			end
			return result
		end
		local cached = shared and shared.DexReflectionMetadataCache
		if
			type(cached) == "table"
			and cached.Schema == 1
			and cached.Raw == rawXML
			and cached.Version == Main.RobloxVersion
			and type(cached.Data) == "table"
		then
			return copy(cached.Data)
		end
		local parsed = Lib.ParseXML(rawXML)
		local classList = parsed.children[1].children[1].children
		local enumList = parsed.children[1].children[2].children
		local propertyOrders = {}

		local classes, enums = {}, {}
		for _, class in pairs(classList) do
			local className = ""
			for _, child in pairs(class.children) do
				if child.tag == "Properties" then
					local data = { Properties = {}, Functions = {} }
					local props = child.children
					for _, prop in pairs(props) do
						local name = prop.attrs.name
						name = name:sub(1, 1):upper() .. name:sub(2)
						data[name] = prop.children[1].text
					end
					className = data.Name
					classes[className] = data
				elseif child.attrs.class == "ReflectionMetadataProperties" then
					local members = child.children
					for _, member in pairs(members) do
						if member.attrs.class == "ReflectionMetadataMember" then
							local data = {}
							if member.children[1].tag == "Properties" then
								local props = member.children[1].children
								for _, prop in pairs(props) do
									if prop.attrs then
										local name = prop.attrs.name
										name = name:sub(1, 1):upper() .. name:sub(2)
										data[name] = prop.children[1].text
									end
								end
								if data.PropertyOrder then
									local orders = propertyOrders[className]
									if not orders then
										orders = {}
										propertyOrders[className] = orders
									end
									orders[data.Name] = tonumber(data.PropertyOrder)
								end
								classes[className].Properties[data.Name] = data
							end
						end
					end
				elseif child.attrs.class == "ReflectionMetadataFunctions" then
					local members = child.children
					for _, member in pairs(members) do
						if member.attrs.class == "ReflectionMetadataMember" then
							local data = {}
							if member.children[1].tag == "Properties" then
								local props = member.children[1].children
								for _, prop in pairs(props) do
									if prop.attrs then
										local name = prop.attrs.name
										name = name:sub(1, 1):upper() .. name:sub(2)
										data[name] = prop.children[1].text
									end
								end
								classes[className].Functions[data.Name] = data
							end
						end
					end
				end
			end
		end

		for _, enum in pairs(enumList) do
			local enumName = ""
			for _, child in pairs(enum.children) do
				if child.tag == "Properties" then
					local data = { Items = {} }
					local props = child.children
					for _, prop in pairs(props) do
						local name = prop.attrs.name
						name = name:sub(1, 1):upper() .. name:sub(2)
						data[name] = prop.children[1].text
					end
					enumName = data.Name
					enums[enumName] = data
				elseif child.attrs.class == "ReflectionMetadataEnumItem" then
					local data = {}
					if child.children[1].tag == "Properties" then
						local props = child.children[1].children
						for _, prop in pairs(props) do
							local name = prop.attrs.name
							name = name:sub(1, 1):upper() .. name:sub(2)
							data[name] = prop.children[1].text
						end
						enums[enumName].Items[data.Name] = data
					end
				end
			end
		end

		local result = { Classes = classes, Enums = enums, PropertyOrders = propertyOrders }
		if shared then
			shared.DexReflectionMetadataCache =
				{ Schema = 1, Version = Main.RobloxVersion, Raw = rawXML, Data = copy(result) }
		end
		return result
	end

	Main.ShowGui = Main.SecureGui

	Main.CreateIntro = function(initStatus)
		return Main.LoadModule("LoadingSplash").Create(initStatus)
	end

	local menuTools = {
		["Explorer"] = { Order = 1 },
		["Properties"] = { Order = 2 },
		["Click part to select"] = { Order = 3 },
		["Click UI to select"] = { Order = 4 },
		["Transform Tools"] = { Order = 5 },
		["Script Editor"] = { Order = 6 },
		["Find in Place"] = { Order = 7 },
		["Console"] = { Order = 8 },
		["Asset Manager"] = { Order = 9 },
		["3D Viewer"] = { Order = 10 },
		["Reconstructor"] = { Order = 11 },
		["Spy"] = { Order = 12 },
		["Save Instance"] = { Order = 13 },
		["Dex MCP"] = { Order = 14 },
		["Input Macros"] = { Order = 15 },
		["Freecam"] = { Order = 16 },
	}

	Main.CreateApp = function(data)
		if Main.MenuApps[data.Name] then
			return
		end
		local control = {}

		local app = Main.AppTemplate:Clone()
		app.Name = data.Name
		local menuTool = menuTools[data.Name]

		local iconIndex = data.Icon
		if data.IconMap and iconIndex then
			if type(iconIndex) == "number" then
				data.IconMap:Display(app.Main.Icon, iconIndex)
			elseif type(iconIndex) == "string" then
				data.IconMap:DisplayByKey(app.Main.Icon, iconIndex)
			end
		elseif type(iconIndex) == "string" then
			app.Main.Icon.Image = iconIndex
			app.Main.Icon.ImageRectOffset = Vector2.new(0, 0)
			app.Main.Icon.ImageRectSize = Vector2.new(0, 0)
			app.Main.Icon.ScaleType = Enum.ScaleType.Fit
		else
			app.Main.Icon.Image = ""
		end

		local function updateState()
			app.Main.BackgroundTransparency = data.Open and 0 or (Lib.CheckMouseInGui(app.Main) and 0 or 1)
			app.Main.Highlight.Visible = data.Open
			app.Main.State.Text = data.Open and (data.Window and "Open" or "On") or (data.Window and "Show" or "Off")
			app.Main.State.TextColor3 = data.Open and Settings.Theme.Focus or Settings.Theme.PlaceholderText
		end

		local function enable(silent)
			if data.Open then
				return
			end
			data.Open = true
			updateState()
			if not silent then
				if data.Window then
					data.Window:Show()
				end
				if data.OnClick then
					data.OnClick(data.Open)
				end
			end
		end

		local function disable(silent)
			if not data.Open then
				return
			end
			data.Open = false
			updateState()
			if not silent then
				if data.Window then
					data.Window:Hide()
				end
				if data.OnClick then
					data.OnClick(data.Open)
				end
			end
		end

		updateState()

		app.Main.Size = UDim2.fromScale(1, 1)
		Lib.StudioTooltip(app.Main, data.Name .. (data.Description and "\n" .. data.Description or ""))

		app.Main.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				app.Main.BackgroundTransparency = 0
				app.Main.BackgroundColor3 = Settings.Theme.ButtonHover
			end
		end)

		app.Main.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				app.Main.BackgroundTransparency = data.Open and 0 or 1
				app.Main.BackgroundColor3 = Settings.Theme.Button
			end
		end)

		app.Main.MouseButton1Click:Connect(function()
			if data.Open then
				disable()
			else
				enable()
			end
		end)

		local window = data.Window
		if window then
			window.OnActivate:Connect(function()
				enable(true)
			end)
			window.OnDeactivate:Connect(function()
				disable(true)
			end)
		end

		app.Visible = true
		app.LayoutOrder = menuTool and menuTool.Order or 100
		app.Parent = Main.AppsContainer

		control.Enable = enable
		control.Disable = disable
		Main.MenuApps[data.Name] = control
		return control
	end

	local contributors = {
		{ "Wooxps", "Dex Explorer" },
		{ "Toon", "IY DeX and contributions" },
		{ "Moon", "DeX" },
		{ "Cazan", "3D Viewer" },
	}
	local creditsCanvasHeight = 90 + #contributors * 42
	local function resizeMainMenu(animate)
		local viewport = Main.MainGui.AbsoluteSize
		local width = math.clamp(viewport.X - 16, 1, 268)
		Main.AppsFrame.Size = UDim2.new(0, math.max(0, width - 12), 1, -52)
		local contentHeight = Main.AppsFrame.CanvasSize.Y.Offset + 52
		local height = Main.MainMenuPage == "credits" and creditsCanvasHeight + 56
			or Main.MainMenuCredits and 292
			or math.clamp(contentHeight, 220, 380)
		local size = UDim2.fromOffset(width, math.max(1, math.min(height, viewport.Y - 56)))
		if not animate and size == Main.MenuSize then
			return
		end
		Main.MenuSize = size
		Main.MainGui.OpenButton.MainFrame:TweenSize(
			Main.MainGuiOpen and size or UDim2.fromOffset(0, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Quad,
			0.2,
			true
		)
	end

	Main.SetMainGuiOpen = function(val)
		Main.MainGuiOpen = val

		if Main.RefreshMenuHistory then
			Main.RefreshMenuHistory()
		end
		if val then
			Main.MainGui.OpenButton.MainFrame.Visible = true
		end
		resizeMainMenu(true)
		if Main.UpdateLauncherStyle then
			Main.UpdateLauncherStyle()
		end

		if Main.MainGuiMouseEvent then
			Main.MainGuiMouseEvent:Disconnect()
		end

		if not val then
			Apps.PluginToolbar.HideMenu()
			local startTime = tick()
			Main.MainGuiCloseTime = startTime
			coroutine.wrap(function()
				Lib.FastWait(0.2)
				if not Main.MainGuiOpen and startTime == Main.MainGuiCloseTime then
					Main.MainGui.OpenButton.MainFrame.Visible = false
				end
			end)()
		else
			Main.MainGuiMouseEvent = Main.TrackSignal(service.UserInputService.InputBegan, function(input)
				if input.KeyCode == Enum.KeyCode.Escape then
					if Apps.PluginToolbar.IsMenuOpen() then
						Apps.PluginToolbar.HideMenu()
						return
					end
					if Main.ClosePrompt and Main.ClosePrompt.Visible then
						Main.ClosePrompt.Visible = false
						return
					end
					Main.SetMainGuiOpen(false)
					return
				end
				if Main.ClosePrompt and Main.ClosePrompt.Visible then
					return
				end
				if
					(
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.MouseButton2
						or input.UserInputType == Enum.UserInputType.Touch
					)
					and not Lib.CheckMouseInGui(Main.MainGui.OpenButton)
					and not Lib.CheckMouseInGui(Main.MainGui.OpenButton.MainFrame)
					and not Apps.PluginToolbar.MenuContainsPointer()
				then
					Main.SetMainGuiOpen(false)
				end
			end)
		end
		if Main.UpdateFocusIndicator then
			Main.UpdateFocusIndicator()
		end
	end

	Main.CreateMainGui = function()
		local gui = create({
			{ 1, "ScreenGui", { IgnoreGuiInset = true, Name = "MainMenu" } },
			{
				2,
				"TextButton",
				{
					AnchorPoint = Vector2.new(0.5, 0),
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
					BorderSizePixel = 0,
					Font = 4,
					Name = "OpenButton",
					Parent = { 1 },
					Position = UDim2.new(0.5, 0, 0, 2),
					Size = UDim2.new(0, 55, 0, 32),
					Text = "DeX",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 16,
					TextTransparency = 0.20000000298023,
				},
			},
			{ 3, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 2 } } },
			{
				4,
				"Frame",
				{
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
					ClipsDescendants = true,
					Name = "MainFrame",
					Parent = { 2 },
					Position = UDim2.new(0.5, 0, 1, -4),
					Size = UDim2.new(0, 224, 0, 200),
				},
			},
			{ 5, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 4 } } },
			{
				6,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
					Name = "BottomFrame",
					Parent = { 4 },
					Position = UDim2.new(0, 0, 1, -24),
					Size = UDim2.new(1, 0, 0, 24),
				},
			},
			{ 7, "UICorner", { CornerRadius = UDim.new(0, 4), Parent = { 6 } } },
			{
				8,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
					BorderSizePixel = 0,
					Name = "CoverFrame",
					Parent = { 6 },
					Size = UDim2.new(1, 0, 0, 4),
				},
			},
			{
				9,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.1294117718935, 0.1294117718935, 0.1294117718935),
					BorderSizePixel = 0,
					Name = "Line",
					Parent = { 8 },
					Position = UDim2.new(0, 0, 0, -1),
					Size = UDim2.new(1, 0, 0, 1),
				},
			},
			{
				10,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Font = 3,
					Name = "Settings",
					Parent = { 6 },
					Position = UDim2.new(1, -48, 0, 0),
					Size = UDim2.new(0, 24, 1, 0),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				11,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://6578871732",
					ImageTransparency = 0.20000000298023,
					Name = "Icon",
					Parent = { 10 },
					Position = UDim2.new(0, 4, 0, 4),
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				12,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Font = 3,
					Name = "Information",
					Parent = { 6 },
					Position = UDim2.new(1, -24, 0, 0),
					Size = UDim2.new(0, 24, 1, 0),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				13,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://6578933307",
					ImageTransparency = 0.20000000298023,
					Name = "Icon",
					Parent = { 12 },
					Position = UDim2.new(0, 4, 0, 4),
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				14,
				"ScrollingFrame",
				{
					Active = true,
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderColor3 = Color3.new(0.1294117718935, 0.1294117718935, 0.1294117718935),
					BorderSizePixel = 0,
					Name = "AppsFrame",
					Parent = { 4 },
					Position = UDim2.new(0.5, 0, 0, 0),
					ScrollBarImageColor3 = Color3.new(0, 0, 0),
					ScrollBarThickness = 4,
					Size = UDim2.new(0, 222, 1, -25),
				},
			},
			{
				15,
				"Frame",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Name = "Container",
					Parent = { 14 },
					Position = UDim2.new(0, 7, 0, 8),
					Size = UDim2.new(1, -14, 0, 2),
				},
			},
			{ 16, "UIGridLayout", { CellSize = UDim2.new(0, 66, 0, 74), Parent = { 15 }, SortOrder = 2 } },
			{
				17,
				"Frame",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Name = "App",
					Parent = { 1 },
					Size = UDim2.new(0, 100, 0, 100),
					Visible = false,
				},
			},
			{
				18,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
					BorderSizePixel = 0,
					Font = 3,
					Name = "Main",
					Parent = { 17 },
					Size = UDim2.new(1, 0, 0, 60),
					Text = "",
					TextColor3 = Color3.new(0, 0, 0),
					TextSize = 14,
				},
			},
			{
				19,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://6579106223",
					ImageRectSize = Vector2.new(32, 32),
					Name = "Icon",
					Parent = { 18 },
					Position = UDim2.new(0.5, -16, 0, 4),
					ScaleType = 4,
					Size = UDim2.new(0, 32, 0, 32),
				},
			},
			{
				21,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0, 0.66666668653488, 1),
					BorderSizePixel = 0,
					Name = "Highlight",
					Parent = { 18 },
					Position = UDim2.new(0, 0, 1, -2),
					Size = UDim2.new(1, 0, 0, 2),
				},
			},
		})
		Main.MainGui = gui
		gui.DisplayOrder = Main.DisplayOrders.Menu
		Main.AppsFrame = gui.OpenButton.MainFrame.AppsFrame
		Main.AppsContainer = Main.AppsFrame.Container
		Main.AppsContainerGrid = Main.AppsContainer.UIGridLayout
		Main.AppTemplate = gui.App
		Main.MainGuiOpen = false

		local panel = gui.OpenButton.MainFrame
		panel.Position = UDim2.new(0.5, 0, 1, 6)
		panel.BorderSizePixel = 0
		panel.BackgroundColor3 = Settings.Theme.Menu
		Lib.StudioCorner(panel, 6)
		local panelStroke = createSimple(
			"UIStroke",
			{ Name = "PanelOutline", Parent = panel, Color = Settings.Theme.Outline2, Thickness = 1 }
		)
		Main.AppsFrame.Position = UDim2.new(0.5, 0, 0, 8)
		Main.AppsFrame.Size = UDim2.new(0, 256, 1, -52)
		Main.AppsFrame.ScrollBarThickness = 3
		Main.AppsFrame.ScrollBarImageColor3 = Settings.Theme.PlaceholderText
		Main.AppsContainer.Position = UDim2.fromOffset(4, 2)
		Main.AppsContainer.Size = UDim2.new(1, -12, 0, 0)
		Main.AppsContainerGrid.CellSize = UDim2.fromOffset(44, 42)
		Main.AppsContainerGrid.CellPadding = UDim2.fromOffset(5, 8)
		Main.AppsContainerGrid.FillDirectionMaxCells = 5
		Main.AppsContainerGrid.SortOrder = Enum.SortOrder.LayoutOrder
		local plugins = Apps.PluginToolbar.Create(Main.AppsFrame)
		local function fitTools()
			local toolsHeight = Main.AppsContainerGrid.AbsoluteContentSize.Y
			Main.AppsContainer.Size = UDim2.new(1, -12, 0, toolsHeight)
			plugins.Position = UDim2.fromOffset(4, toolsHeight + 10)
			Main.AppsFrame.CanvasSize = UDim2.fromOffset(0, toolsHeight + 14 + plugins.Size.Y.Offset)
			if Main.MainGuiOpen and not Main.MainMenuCredits then
				resizeMainMenu(false)
			end
		end
		Main.AppsContainerGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitTools)
		plugins:GetPropertyChangedSignal("Size"):Connect(fitTools)
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if Main.MainGuiOpen then
				resizeMainMenu(false)
			end
		end)
		fitTools()
		local row = Main.AppTemplate.Main
		row.BackgroundColor3 = Settings.Theme.Button
		Lib.StudioCorner(row, 4)
		row.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Icon.Position = UDim2.new(0.5, 0, 0.5, -2)
		row.Icon.Size = UDim2.fromOffset(32, 32)
		row.Icon.ImageTransparency = 0
		row.Highlight.Position = UDim2.new(0.5, -8, 1, -3)
		row.Highlight.Size = UDim2.fromOffset(16, 2)
		row.Highlight.BackgroundColor3 = Settings.Theme.Focus
		local state = createSimple("TextLabel", {
			Name = "State",
			Parent = row,
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -50, 0, 0),
			Size = UDim2.new(0, 42, 1, 0),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		Lib.StudioText(state)
		state.TextSize = 11
		state.Visible = false
		local bottom = panel.BottomFrame
		bottom.Size = UDim2.new(1, 0, 0, 36)
		bottom.Position = UDim2.new(0, 0, 1, -36)
		bottom.BackgroundColor3 = Settings.Theme.Main2
		bottom.BorderSizePixel = 0
		bottom.CoverFrame.BackgroundColor3 = Settings.Theme.Main2
		bottom.CoverFrame.Line.BackgroundColor3 = Settings.Theme.Outline2
		local about = bottom.Information
		about.Icon.Visible = false
		about.Text = "Credits"
		about.Position = UDim2.new(1, -78, 0, 4)
		about.Size = UDim2.fromOffset(70, 28)
		Lib.StudioText(about)
		about.AutoButtonColor = false
		about.BackgroundColor3 = Settings.Theme.ButtonHover
		Lib.StudioCorner(about, 4)
		about.MouseEnter:Connect(function()
			about.BackgroundTransparency = 0
		end)
		about.MouseLeave:Connect(function()
			about.BackgroundTransparency = 1
		end)
		local function historyButton(text, x, callback)
			local b = createSimple("TextButton", {
				Name = text,
				Parent = bottom,
				Text = "",
				Position = UDim2.fromOffset(x, 4),
				Size = UDim2.fromOffset(32, 28),
				AutoButtonColor = false,
				BorderSizePixel = 0,
				BackgroundColor3 = Settings.Theme.ButtonHover,
				BackgroundTransparency = 1,
			})
			Lib.StudioText(b)
			Lib.StudioCorner(b, 4)
			local asset = Main.GetStudioAsset("menu/" .. text:lower())
			createSimple("ImageLabel", {
				Name = "Icon",
				Parent = b,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 16),
				Image = asset or "",
				ScaleType = Enum.ScaleType.Fit,
			})
			if not asset then
				b.Text = text == "Undo" and "↶" or "↷"
			end
			b.MouseEnter:Connect(function()
				if b.Interactable then
					b.BackgroundTransparency = 0
				end
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
			b.MouseButton1Click:Connect(function()
				callback()
				Main.RefreshMenuHistory()
			end)
			return b
		end
		local undo = historyButton("Undo", 8, function()
			Apps.History.Undo()
		end)
		local redo = historyButton("Redo", 44, function()
			Apps.History.Redo()
		end)
		Lib.StudioTooltip(undo, "Undo model edit (Ctrl+Z)")
		Lib.StudioTooltip(redo, "Redo model edit (Ctrl+Y)")
		Main.RefreshMenuHistory = function()
			undo.Interactable = Apps.History.CanUndo()
			redo.Interactable = Apps.History.CanRedo()
			for _, b in ipairs({ undo, redo }) do
				b.TextColor3 = b.Interactable and Settings.Theme.Text or Settings.Theme.PlaceholderText
				b.Icon.ImageTransparency = b.Interactable and 0 or 0.65
				if not b.Interactable then
					b.BackgroundTransparency = 1
				end
			end
		end
		Main.RefreshMenuHistory()

		local openButton = gui.OpenButton
		Lib.StudioText(openButton)
		openButton.Size = UDim2.fromOffset(32, 32)
		openButton.Position = UDim2.new(0.5, 0, 0, 8)
		openButton.Text = ""
		createSimple("ImageLabel", {
			Name = "DexIcon",
			Parent = openButton,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			Image = Main.GetStudioAsset("branding/dex/toolbar-white-v1") or "",
			ScaleType = Enum.ScaleType.Fit,
		})
		openButton.TextSize = 13
		openButton.TextTransparency = 0
		openButton.BackgroundColor3 = Settings.Theme.Main2
		Lib.StudioCorner(openButton, 4)
		openButton.BackgroundTransparency = 0
		local launcherStroke = createSimple("UIStroke", {
			Name = "LauncherOutline",
			Parent = openButton,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Settings.Theme.Outline2,
			Thickness = 1,
		})
		Main.MainGuiHovered = false
		Main.UpdateLauncherStyle = function()
			openButton.BackgroundTransparency = 0
			openButton.BackgroundColor3 = (Main.MainGuiOpen or Main.MainGuiHovered) and Settings.Theme.ButtonHover
				or Settings.Theme.Main2
			launcherStroke.Color = Settings.Theme.Outline2
		end
		Lib.StudioTooltip(openButton, "Open or close the Dex Explorer tools menu")
		openButton.MainFrame.Size = UDim2.new(0, 0, 0, 0)
		openButton.MainFrame.Visible = false
		if Main.RegisterGuiFocusOwner then
			Main.RegisterGuiFocusOwner(gui, openButton)
		end
		if Main.RegisterFocusIndicator then
			Main.RegisterFocusIndicator(openButton, function(visible)
				if panelStroke.Parent then
					panelStroke.Color = visible and Settings.Theme.Focus or Settings.Theme.Outline2
					panelStroke.Thickness = visible and 2 or 1
				end
			end)
		end
		if Main.UpdateFocusIndicator then
			Main.UpdateFocusIndicator()
		end
		openButton.MouseButton1Click:Connect(function()
			Main.SetMainGuiOpen(not Main.MainGuiOpen)
		end)

		openButton.MouseEnter:Connect(function()
			Main.MainGuiHovered = true
			Main.UpdateLauncherStyle()
		end)
		openButton.MouseLeave:Connect(function()
			Main.MainGuiHovered = false
			Main.UpdateLauncherStyle()
		end)

		local settingsButton = openButton.MainFrame.BottomFrame.Settings
		settingsButton.Visible = true
		settingsButton.AutoButtonColor = false
		settingsButton.Position = UDim2.new(1, -146, 0, 4)
		settingsButton.Size = UDim2.fromOffset(28, 28)
		settingsButton.BackgroundColor3 = Settings.Theme.ButtonHover
		settingsButton.BackgroundTransparency = 1
		settingsButton.BorderSizePixel = 0
		Lib.StudioCorner(settingsButton, 4)
		settingsButton.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
		settingsButton.Icon.Position = UDim2.fromScale(0.5, 0.5)
		settingsButton.Icon.Size = UDim2.fromOffset(16, 16)
		settingsButton.Icon.Image = Main.GetStudioAsset("menu/settings") or settingsButton.Icon.Image
		settingsButton.Icon.ImageTransparency = 0
		Lib.StudioTooltip(settingsButton, "Settings")
		settingsButton.MouseEnter:Connect(function()
			settingsButton.BackgroundTransparency = 0
		end)
		settingsButton.MouseLeave:Connect(function()
			if Main.MainMenuPage ~= "settings" then
				settingsButton.BackgroundTransparency = 1
			end
		end)

		local shutdownAsset = Lib.PanelAsset("close-launcher")
		local shutdownButton = createSimple("TextButton", {
			Name = "Shutdown",
			Parent = bottom,
			Text = shutdownAsset and "" or "×",
			Position = UDim2.new(1, -112, 0, 4),
			Size = UDim2.fromOffset(28, 28),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = Settings.Theme.ButtonHover,
			BackgroundTransparency = 1,
		})
		Lib.StudioText(shutdownButton)
		shutdownButton.TextSize = 18
		Lib.StudioCorner(shutdownButton, 4)
		createSimple("ImageLabel", {
			Name = "Icon",
			Parent = shutdownButton,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			Image = shutdownAsset or "",
			Visible = shutdownAsset ~= nil,
			ScaleType = Enum.ScaleType.Fit,
		})
		Lib.StudioTooltip(shutdownButton, "Close DeX")
		shutdownButton.MouseEnter:Connect(function()
			shutdownButton.BackgroundTransparency = 0
		end)
		shutdownButton.MouseLeave:Connect(function()
			shutdownButton.BackgroundTransparency = 1
		end)
		local closePrompt = createSimple("TextButton", {
			Name = "ClosePrompt",
			Parent = gui,
			Visible = false,
			Active = true,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.38,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 200,
		})
		Main.ClosePrompt = closePrompt
		local promptCard = createSimple("Frame", {
			Name = "Card",
			Parent = closePrompt,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(330, 142),
			BackgroundColor3 = Settings.Theme.Menu,
			BorderSizePixel = 0,
			ZIndex = 201,
		})
		Lib.StudioCorner(promptCard, 6)
		createSimple("UIStroke", { Parent = promptCard, Color = Settings.Theme.Outline2, Thickness = 1 })
		local promptTitle = createSimple("TextLabel", {
			Name = "Title",
			Parent = promptCard,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 16),
			Size = UDim2.new(1, -36, 0, 24),
			Text = "Close DeX",
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 202,
		})
		Lib.StudioText(promptTitle)
		promptTitle.TextSize = 16
		local promptText = createSimple("TextLabel", {
			Name = "Message",
			Parent = promptCard,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 47),
			Size = UDim2.new(1, -36, 0, 34),
			Text = "Are you sure you want to close DeX?",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 202,
		})
		Lib.StudioText(promptText)
		promptText.TextSize = 14
		promptText.TextColor3 = Settings.Theme.PlaceholderText
		local cancelClose = createSimple("TextButton", {
			Name = "Cancel",
			Parent = promptCard,
			AutoButtonColor = false,
			BackgroundColor3 = Settings.Theme.Button,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -184, 1, -46),
			Size = UDim2.fromOffset(78, 30),
			Text = "Cancel",
			ZIndex = 202,
		})
		Lib.StudioText(cancelClose)
		Lib.StudioCorner(cancelClose, 4)
		local confirmClose = createSimple("TextButton", {
			Name = "Confirm",
			Parent = promptCard,
			AutoButtonColor = false,
			BackgroundColor3 = Settings.Theme.ButtonHover,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -98, 1, -46),
			Size = UDim2.fromOffset(82, 30),
			Text = "Confirm",
			ZIndex = 202,
		})
		Lib.StudioText(confirmClose)
		Lib.StudioCorner(confirmClose, 4)
		cancelClose.MouseEnter:Connect(function()
			cancelClose.BackgroundColor3 = Settings.Theme.ButtonHover
		end)
		cancelClose.MouseLeave:Connect(function()
			cancelClose.BackgroundColor3 = Settings.Theme.Button
		end)
		confirmClose.MouseEnter:Connect(function()
			confirmClose.BackgroundColor3 = Settings.Theme.Outline2
		end)
		confirmClose.MouseLeave:Connect(function()
			confirmClose.BackgroundColor3 = Settings.Theme.ButtonHover
		end)
		cancelClose.MouseButton1Click:Connect(function()
			closePrompt.Visible = false
		end)
		confirmClose.MouseButton1Click:Connect(function()
			Main.Shutdown()
		end)
		closePrompt.MouseButton1Click:Connect(function()
			if not Lib.CheckMouseInGui(promptCard) then
				closePrompt.Visible = false
			end
		end)
		shutdownButton.MouseButton1Click:Connect(function()
			closePrompt.Visible = true
		end)

		local credits = createSimple("ScrollingFrame", {
			Name = "Credits",
			Parent = panel,
			Visible = false,
			Active = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 1, -54),
			CanvasSize = UDim2.fromOffset(0, creditsCanvasHeight),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Settings.Theme.PlaceholderText,
		})
		local function creditText(parent, name, text, x, y, height, fontSize, bold, muted)
			local label = createSimple("TextLabel", {
				Name = name,
				Parent = parent,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.new(1, -x - 8, 0, height),
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			Lib.StudioText(label)
			label.TextSize = fontSize
			if bold then
				label.Font = Lib.StudioBold
			end
			if muted then
				label.TextColor3 = Settings.Theme.PlaceholderText
			end
			return label
		end

		local logo = Main.GetStudioAsset("branding/dex/toolbar-white-v1")
		if logo then
			createSimple("ImageLabel", {
				Name = "Logo",
				Parent = credits,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(5, 13),
				Size = UDim2.fromOffset(28, 28),
				Image = logo,
				ImageColor3 = Settings.Theme.Text,
				ScaleType = Enum.ScaleType.Fit,
			})
		end
		local titleX = logo and 46 or 8
		creditText(credits, "ProductName", "Dex Explorer", titleX, 6, 24, 18, true)
		local version = string.split(Main.Version or "", " · ")[1]
		creditText(credits, "Version", version, titleX, 30, 17, 12, false, true)

		local contributionList = createSimple("Frame", {
			Name = "Contributors",
			Parent = credits,
			Position = UDim2.fromOffset(1, 63),
			Size = UDim2.new(1, -7, 0, 24 + #contributors * 42),
			BackgroundColor3 = Settings.Theme.Menu,
			BorderSizePixel = 0,
		})
		createSimple("UIStroke", {
			Parent = contributionList,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Settings.Theme.Outline2,
			Thickness = 1,
		})
		local section = createSimple("Frame", {
			Name = "SectionHeader",
			Parent = contributionList,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Settings.Theme.Main2,
			BorderSizePixel = 0,
		})
		creditText(section, "Heading", "Contributors", 10, 0, 24, 12, true)
		for i, person in ipairs(contributors) do
			local row = createSimple("Frame", {
				Name = person[1],
				Parent = contributionList,
				Position = UDim2.fromOffset(0, 24 + (i - 1) * 42),
				Size = UDim2.new(1, 0, 0, 42),
				BackgroundTransparency = 1,
			})
			createSimple("Frame", {
				Name = "Divider",
				Parent = row,
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Settings.Theme.Outline2,
				BorderSizePixel = 0,
			})
			creditText(row, "ContributorName", person[1], 10, 3, 19, 13, true)
			creditText(row, "Contribution", person[2], 10, 22, 16, 12, false, true)
		end

		local settingsPage = createSimple("ScrollingFrame", {
			Name = "SettingsPage",
			Parent = panel,
			Visible = false,
			Active = true,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 1, -54),
			CanvasSize = UDim2.fromOffset(0, 336),
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Settings.Theme.PlaceholderText,
		})
		local settingsTitle = createSimple("TextLabel", {
			Parent = settingsPage,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(2, 0),
			Size = UDim2.new(1, -4, 0, 26),
			Text = "Settings",
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Lib.StudioText(settingsTitle)
		settingsTitle.TextSize = 16
		local function settingsSection(text, y)
			local label = createSimple("TextLabel", {
				Parent = settingsPage,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(2, y),
				Size = UDim2.new(1, -4, 0, 16),
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Lib.StudioText(label)
			label.TextSize = 10
			label.TextColor3 = Settings.Theme.PlaceholderText
		end

		Settings.Interface = Settings.Interface or {}
		Settings.Explorer = Settings.Explorer or {}
		local function makeToggleRow(titleText, detailText, y, getValue, onChange)
			local row = createSimple("Frame", {
				Parent = settingsPage,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, -6, 0, 48),
			})
			local titleLabel = createSimple("TextLabel", {
				Parent = row,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(2, 1),
				Size = UDim2.new(1, -42, 0, 20),
				Text = titleText,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			Lib.StudioText(titleLabel)
			titleLabel.TextSize = 13
			local detail = createSimple("TextLabel", {
				Parent = row,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(2, 21),
				Size = UDim2.new(1, -42, 0, 24),
				Text = detailText,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			Lib.StudioText(detail)
			detail.TextSize = 10
			detail.TextColor3 = Settings.Theme.PlaceholderText

			local toggle = createSimple("TextButton", {
				Name = "Toggle",
				Parent = row,
				AutoButtonColor = false,
				Text = "",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -2, 0.5, 0),
				Size = UDim2.fromOffset(30, 16),
				BorderSizePixel = 0,
			})
			Lib.StudioCorner(toggle, 8)
			local knob = createSimple("Frame", {
				Name = "Knob",
				Parent = toggle,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(12, 12),
				BorderSizePixel = 0,
			})
			Lib.StudioCorner(knob, 6)
			local value = getValue() ~= false
			local function paint()
				toggle.BackgroundColor3 = value and Settings.Theme.Focus or Settings.Theme.Outline2
				knob.BackgroundColor3 = value and Settings.Theme.Text or Settings.Theme.PlaceholderText
				knob.Position = value and UDim2.new(1, -8, 0.5, 0) or UDim2.new(0, 8, 0.5, 0)
			end
			paint()
			toggle.MouseButton1Click:Connect(function()
				value = not value
				local accepted = onChange(value)
				if accepted == false then
					value = false
				end
				paint()
				Main.SaveSettings()
			end)
			return {
				Refresh = function()
					value = getValue() ~= false
					paint()
				end,
			}
		end

		settingsSection("INPUT", 30)
		local settingsRows = {}
		settingsRows[#settingsRows + 1] = makeToggleRow(
			"Block game input",
			"Block game controls while using Dex.",
			46,
			function()
				return Settings.Interface.FocusGameInput ~= false
			end,
			function(value)
				Settings.Interface.FocusGameInput = value
				Main.SetGameInputLocked(value)
				return true
			end
		)
		settingsRows[#settingsRows + 1] = makeToggleRow(
			"Show focus border",
			"Outline the Dex window you are using.",
			96,
			function()
				return Settings.Interface.FocusIndicator ~= false
			end,
			function(value)
				Settings.Interface.FocusIndicator = value
				if Main.UpdateFocusIndicator then
					Main.UpdateFocusIndicator()
				end
				return true
			end
		)
		settingsRows[#settingsRows + 1] = makeToggleRow("Anti AFK", "Stay connected while idle.", 146, function()
			return Settings.Interface.AntiAFK == true
		end, function(value)
			return Apps.AntiAFK.SetEnabled(value)
		end)
		settingsSection("EXPLORER", 202)
		settingsRows[#settingsRows + 1] = makeToggleRow(
			"Show nil instances",
			"Show objects with no parent.",
			218,
			function()
				return Settings.Explorer.ShowNilInstances ~= false
			end,
			function(value)
				Settings.Explorer.ShowNilInstances = value
				if value then
					if not Explorer.RefreshNilInstances() then
						Settings.Explorer.ShowNilInstances = false
						return false
					end
				else
					Explorer.HideNilInstances()
				end
				return true
			end
		)
		settingsRows[#settingsRows + 1] = makeToggleRow(
			"Auto-reveal selection",
			"Expand folders to show selected objects.",
			268,
			function()
				return Settings.Explorer.ExpandHierarchy ~= false
			end,
			function(value)
				Settings.Explorer.ExpandHierarchy = value
				return true
			end
		)

		Main.RefreshSettings = function()
			for _, entry in ipairs(settingsRows) do
				entry.Refresh()
			end
		end
		local function showMainPage(pageName)
			Apps.PluginToolbar.HideMenu()
			Main.MainMenuPage = pageName
			local showingSettings = pageName == "settings"
			local showingCredits = pageName == "credits"
			settingsPage.Visible = showingSettings
			credits.Visible = showingCredits
			if showingCredits then
				credits.CanvasPosition = Vector2.new(0, 0)
			end
			Main.AppsFrame.Visible = not showingSettings and not showingCredits
			settingsButton.BackgroundTransparency = showingSettings and 0 or 1
			about.Text = (showingSettings or showingCredits) and "Back" or "Credits"
			Main.MainMenuCredits = showingSettings or showingCredits
			if showingSettings then
				Main.RefreshSettings()
			end
			Main.SetMainGuiOpen(true)
		end
		settingsButton.MouseButton1Click:Connect(function()
			if Main.MainMenuPage == "settings" then
				showMainPage(nil)
			else
				showMainPage("settings")
			end
		end)
		about.MouseButton1Click:Connect(function()
			if Main.MainMenuPage ~= nil then
				showMainPage(nil)
			else
				showMainPage("credits")
			end
		end)

		Main.CreateApp({
			Name = "Explorer",
			Icon = Main.GetStudioAsset("menu/tool/explorer"),
			Open = true,
			Window = Explorer.Window,
		})

		Main.CreateApp({
			Name = "Properties",
			Icon = Main.GetStudioAsset("menu/tool/properties"),
			Open = true,
			Window = Properties.Window,
		})

		local cptsOnMouseClick, uiSelectInput, uiPickerEscapeInput = nil, nil, nil
		local uiCaptureGui, uiCaptureButton = nil, nil
		local partPickerControl, uiPickerControl, freecamControl

		local selectExplorerObject = Explorer.SelectObject

		local function isUiCaptureObject(object)
			local current = object
			while current do
				if current == uiCaptureGui or current == uiCaptureButton then
					return true
				end
				current = current.Parent
			end
			return false
		end

		local function isDexGuiObject(object)
			local current = object
			while current do
				if Main.InternalGuis[current] then
					return true
				end
				current = current.Parent
			end
			return false
		end

		local function queryGuiRoot(root, x, y)
			if not root then
				return nil
			end
			local ok, objects = pcall(function()
				return root:GetGuiObjectsAtPosition(x, y)
			end)
			if ok and type(objects) == "table" then
				return objects
			end
			return nil
		end

		local function isPassiveUiContainer(object)
			local ok, passive = pcall(function()
				if object:IsA("Frame") then
					return object.BackgroundTransparency >= 0.995 and object.BorderSizePixel <= 0 and not object.Active
				elseif object:IsA("CanvasGroup") then
					return object.GroupTransparency >= 0.995
						and object.BackgroundTransparency >= 0.995
						and not object.Active
				end
				return false
			end)
			return ok and passive
		end

		local function getGuiObjectsAtPosition(x, y)
			local playerGui
			pcall(function()
				playerGui = service.Players.LocalPlayer:FindFirstChild("PlayerGui")
			end)
			if not playerGui then
				return {}
			end

			local objects = queryGuiRoot(playerGui, x, y)
			if not objects then
				return {}
			end

			local primary, passive = {}, {}
			for _, object in ipairs(objects) do
				if not isUiCaptureObject(object) and not isDexGuiObject(object) then
					if isPassiveUiContainer(object) then
						passive[#passive + 1] = object
					else
						primary[#primary + 1] = object
					end
				end
			end

			for _, object in ipairs(passive) do
				primary[#primary + 1] = object
			end
			return primary
		end

		local uiLastPickPosition, uiLastPickStack, uiLastPickIndex = nil, nil, 0
		local function sameGuiHitStack(a, b)
			if not a or not b or #a ~= #b then
				return false
			end
			for i = 1, #a do
				if a[i] ~= b[i] then
					return false
				end
			end
			return true
		end

		local function selectGuiAtPosition(x, y)
			local objects = getGuiObjectsAtPosition(x, y)
			if #objects == 0 then
				uiLastPickPosition, uiLastPickStack, uiLastPickIndex = nil, nil, 0
				return false
			end

			local samePoint = uiLastPickPosition
				and math.abs(uiLastPickPosition.X - x) <= 2
				and math.abs(uiLastPickPosition.Y - y) <= 2
			local startIndex = 1
			if samePoint and sameGuiHitStack(objects, uiLastPickStack) then
				startIndex = (uiLastPickIndex % #objects) + 1
			end

			for offset = 0, #objects - 1 do
				local index = ((startIndex + offset - 1) % #objects) + 1
				if selectExplorerObject(objects[index]) then
					uiLastPickPosition = Vector2.new(x, y)
					uiLastPickStack = objects
					uiLastPickIndex = index
					return true
				end
			end

			uiLastPickPosition, uiLastPickStack, uiLastPickIndex = nil, nil, 0
			return false
		end

		partPickerControl = Main.CreateApp({
			Name = "Click part to select",
			Description = "Pick a part in the 3D world to reveal it in Explorer",
			Icon = Main.GetStudioAsset("native/transform/ribbon/select"),
			OnClick = function(callback)
				if callback and freecamControl then freecamControl.Disable() end
				if Apps.TransformTools and Apps.TransformTools.SetWorldSelection then
					Apps.TransformTools.SetWorldSelection(callback)
				end
				if callback then
					if uiPickerControl then
						uiPickerControl.Disable()
					end
					local mouse = Main.Mouse
					cptsOnMouseClick = Main.TrackSignal(mouse.Button1Down, function()
						if Apps.TransformTools and Apps.TransformTools.CapturesPointer(mouse.X, mouse.Y) then
							return
						end
						pcall(Explorer.PickWorld)
					end)
				else
					if cptsOnMouseClick ~= nil then
						cptsOnMouseClick:Disconnect()
						cptsOnMouseClick = nil
					end
				end
			end,
		})

		local function destroyUiCapture()
			uiLastPickPosition, uiLastPickStack, uiLastPickIndex = nil, nil, 0
			if uiSelectInput then
				uiSelectInput:Disconnect()
				uiSelectInput = nil
			end
			if uiPickerEscapeInput then
				uiPickerEscapeInput:Disconnect()
				uiPickerEscapeInput = nil
			end
			if uiCaptureGui then
				pcall(function()
					uiCaptureGui:Destroy()
				end)
			end
			uiCaptureGui, uiCaptureButton = nil, nil
		end

		local function createUiCapture()
			destroyUiCapture()

			local captureGui = createSimple("ScreenGui", {
				Name = "DeXUiPickerCapture",
				IgnoreGuiInset = true,
				ResetOnSpawn = false,
				DisplayOrder = Main.DisplayOrders.Menu - 1,
				ZIndexBehavior = Enum.ZIndexBehavior.Global,
			})
			local captureButton = createSimple("TextButton", {
				Name = "Capture",
				Parent = captureGui,
				Active = true,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Modal = true,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				ZIndex = 10,
			})

			uiCaptureGui, uiCaptureButton = captureGui, captureButton
			Main.SecureGui(captureGui)

			uiSelectInput = captureButton.InputBegan:Connect(function(input)
				local kind = input.UserInputType
				if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				pcall(function()
					selectGuiAtPosition(pos.X, pos.Y)
				end)
			end)

			uiPickerEscapeInput = Main.TrackSignal(service.UserInputService.InputBegan, function(input, processed)
				if input.KeyCode == Enum.KeyCode.Escape and uiPickerControl then
					uiPickerControl.Disable()
				end
			end)
		end

		uiPickerControl = Main.CreateApp({
			Name = "Click UI to select",
			Description = "Pick PlayerGui UI only and reveal it in Explorer (Esc to stop)",
			Icon = Main.GetStudioAsset("menu/tool/ui_select"),
			OnClick = function(callback)
				if callback then
					if freecamControl then freecamControl.Disable() end
					if partPickerControl then
						partPickerControl.Disable()
					end
					createUiCapture()
					if Main.MainGuiOpen then
						Main.SetMainGuiOpen(false)
					end
				else
					destroyUiCapture()
				end
			end,
		})

		do
			local stop
			local function start()
				local input = service.UserInputService
				local world = service.Workspace
				local camera = world.CurrentCamera
				if not camera or not input.KeyboardEnabled or not input.MouseEnabled then
					freecamControl.Disable(true)
					return
				end
				partPickerControl.Disable()
				uiPickerControl.Disable()
				local actions = service.ContextActionService
				local action = "DexExplorerFreecamMove"
				local frame = camera.CFrame
				local original, focus, cameraType = frame, camera.Focus, camera.CameraType
				local behavior, cursor = input.MouseBehavior, input.MouseIconEnabled
				local pitch, yaw = frame:ToOrientation()
				local held, connections = {}, {}
				local looking = false
				local function connect(signal, callback)
					table.insert(connections, signal:Connect(callback))
				end
				local function releaseLook()
					looking = false
					input.MouseBehavior = Enum.MouseBehavior.Default
					input.MouseIconEnabled = true
				end
				stop = function()
					stop = nil
					for _, connection in connections do connection:Disconnect() end
					actions:UnbindAction(action)
					input.MouseBehavior = behavior
					input.MouseIconEnabled = cursor
					if camera.Parent and camera.CameraType == Enum.CameraType.Scriptable then
						camera.CFrame, camera.Focus = original, focus
						camera.CameraType = cameraType
					end
				end
				camera.CameraType = Enum.CameraType.Scriptable
				releaseLook()
				local key = Enum.KeyCode
				actions:BindActionAtPriority(action, function(_, state, event)
					local code = event.KeyCode
					if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
						held[code] = nil
						return Enum.ContextActionResult.Pass
					end
					if input:GetFocusedTextBox() or service.GuiService.MenuIsOpen then return Enum.ContextActionResult.Pass end
					if state == Enum.UserInputState.Begin then held[code] = true end
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value + 1, key.W, key.A, key.S, key.D, key.Q, key.E)
				connect(input.InputBegan, function(event, processed)
					if input:GetFocusedTextBox() then return end
					if event.KeyCode == key.Escape then freecamControl.Disable() return end
					if processed or service.GuiService.MenuIsOpen then return end
					local mouse = Main.Mouse
					if Main.IsPointInDexUI and Main.IsPointInDexUI(mouse.X, mouse.Y) then return end
					if event.UserInputType == Enum.UserInputType.MouseButton2 then
						looking = true
						input.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
						input.MouseIconEnabled = false
					elseif event.UserInputType == Enum.UserInputType.MouseButton1 and not looking then
						if Apps.TransformTools and Apps.TransformTools.CapturesPointer(mouse.X, mouse.Y) then return end
						if Explorer.PickWorld() then
							Main.MenuApps.Explorer.Enable()
							Main.MenuApps.Properties.Enable()
						end
					end
				end)
				connect(input.InputChanged, function(event)
					if looking and event.UserInputType == Enum.UserInputType.MouseMovement then
						yaw -= event.Delta.X * 0.003
						pitch = math.clamp(pitch - event.Delta.Y * 0.003, -math.rad(89.5), math.rad(89.5))
						frame = CFrame.new(frame.Position) * CFrame.fromOrientation(pitch, yaw, 0)
					end
				end)
				connect(input.InputEnded, function(event)
					if looking and event.UserInputType == Enum.UserInputType.MouseButton2 then releaseLook() end
				end)
				local function pause()
					table.clear(held)
					if looking then releaseLook() end
				end
				connect(input.WindowFocusReleased, pause)
				connect(input.TextBoxFocused, pause)
				connect(service.GuiService.MenuOpened, pause)
				connect(world:GetPropertyChangedSignal("CurrentCamera"), freecamControl.Disable)
				connect(service.RunService.RenderStepped, function(dt)
					if camera.CameraType ~= Enum.CameraType.Scriptable then freecamControl.Disable() return end
					local x = (held[key.D] and 1 or 0) - (held[key.A] and 1 or 0)
					local y = (held[key.E] and 1 or 0) - (held[key.Q] and 1 or 0)
					local z = (held[key.S] and 1 or 0) - (held[key.W] and 1 or 0)
					local direction = frame.RightVector * x + Vector3.yAxis * y + frame.LookVector * -z
					if direction.Magnitude > 0 then
						local fast = input:IsKeyDown(key.LeftShift) or input:IsKeyDown(key.RightShift)
						frame += direction.Unit * (fast and 144 or 36) * math.min(dt, 0.1)
					end
					camera.CFrame = frame
					camera.Focus = frame * CFrame.new(0, 0, -16)
				end)
				if Main.MainGuiOpen then Main.SetMainGuiOpen(false) end
			end
			freecamControl = Main.CreateApp({
				Name = "Freecam",
				Description = "WASD fly, Q/E down/up, Shift boost, right-drag look, click to inspect, Esc to exit",
				Icon = Main.GetStudioAsset("class/Camera"),
				OnClick = function(enabled)
					if enabled then
						local ok, reason = pcall(start)
						if not ok then freecamControl.Disable() warn("Dex Freecam: " .. tostring(reason)) end
					elseif stop then stop() end
				end,
			})
			Main.AddCleanup(function() if stop then stop() end end)
		end

		Main.AddCleanup(function()
			if cptsOnMouseClick then
				pcall(function()
					cptsOnMouseClick:Disconnect()
				end)
				cptsOnMouseClick = nil
			end
			destroyUiCapture()
		end)

		Main.CreateApp({
			Name = "Script Editor",
			Icon = Main.GetStudioAsset("menu/tool/script"),
			Window = ScriptViewer.Window,
		})

		Main.CreateApp({ Name = "Console", Icon = Main.GetStudioAsset("menu/tool/console"), Window = Console.Window })
		local spyControl, spyLoading
		spyControl = Main.CreateApp({
			Name = "Spy",
			Description = "Launch Cobalt Spy",
			Icon = Main.GetStudioAsset("external/cobalt/logo"),
			OnClick = function(open)
				spyControl.Disable(true)
				if not open or spyLoading then
					return
				end
				spyLoading = true
				task.spawn(function()
					if not Main.Alive then
						spyLoading = false
						return
					end
					local ok, problem = pcall(function()
						assert(type(env.loadstring) == "function", "Cobalt requires executor loadstring support")
						local source = oldgame:HttpGet(
							"https://gitlab.com/upio/cobalt/-/releases/permalink/latest/downloads/Cobalt.luau"
						)
						if not Main.Alive then
							return
						end
						assert(type(source) == "string" and #source > 0, "Cobalt returned empty source")
						local run, compileProblem = env.loadstring(source, "@Cobalt/OfficialRelease")
						assert(run, compileProblem)
						run()
					end)
					spyLoading = false
					if not ok then
						warn("[Dex Explorer] Could not launch Cobalt Spy: " .. tostring(problem))
					end
				end)
			end,
		})

		Main.CreateApp({
			Name = "Save Instance",
			Icon = Main.GetStudioAsset("menu/tool/save"),
			Window = SaveInstance.Window,
		})

		local findInPlaceControl, findInPlaceWindow
		findInPlaceControl = Main.CreateApp({
			Name = "Find in Place",
			Icon = Main.GetStudioAsset("menu/tool/find_in_place_modern"),
			OnClick = function(open)
				if open then
					Apps.ScriptViewer.OpenFindAll(false)
					if not findInPlaceWindow then
						findInPlaceWindow = Apps.ScriptViewer.FindInPlaceWindow
						findInPlaceWindow.OnDeactivate:Connect(function()
							findInPlaceControl.Disable(true)
						end)
					end
				else
					Apps.ScriptViewer.CloseFindAll()
				end
			end,
		})
		local assetManagerControl
		assetManagerControl = Main.CreateApp({
			Name = "Asset Manager",
			Description = "Browse and preview assets used by game objects",
			Icon = Main.GetStudioAsset("native/asset-manager/icon"),
			OnClick = function(open)
				if open then
					local first = Apps.AssetManager.Window == nil
					Apps.AssetManager.Open()
					if first then
						Apps.AssetManager.Window.OnDeactivate:Connect(function()
							assetManagerControl.Disable(true)
						end)
					end
				else
					Apps.AssetManager.Hide()
				end
			end,
		})
		Main.CreateApp({
			Name = "3D Viewer",
			Icon = Main.GetStudioAsset("menu/tool/viewer"),
			Window = ModelViewer.Window,
		})
		Main.CreateApp({
			Name = "Transform Tools",
			Description = "Move, rotate and resize selected objects",
			Icon = Main.GetStudioAsset("native/transform/ribbon/move"),
			Open = true,
			OnClick = function(open)
				Apps.TransformTools.SetEnabled(open)
			end,
		})
		local ReconstructorControl
		ReconstructorControl = Main.CreateApp({
			Name = "Reconstructor",
			Description = "Browse reconstructed server paths and their sources",
			Icon = Main.GetStudioAsset("menu/tool/reconstructor"),
			OnClick = function(open)
				if open then
					local first = Apps.Reconstructor.Window == nil
					Apps.Reconstructor.Open()
					if first then
						Apps.Reconstructor.Window.OnDeactivate:Connect(function()
							ReconstructorControl.Disable(true)
						end)
					end
				else
					Apps.Reconstructor.Hide()
				end
			end,
		})

		local aiBridgeControl
		aiBridgeControl = Main.CreateApp({
			Name = "Dex MCP",
			Description = "Connect a desktop AI client to Dex",
			Icon = Main.GetStudioAsset("native/editor/analysis"),
			OnClick = function(open)
				if open then
					local first = Apps.AIBridge.Window == nil
					Apps.AIBridge.Open()
					if first then
						Apps.AIBridge.Window.OnDeactivate:Connect(function()
							aiBridgeControl.Disable(true)
						end)
					end
				else
					Apps.AIBridge.Hide()
				end
			end,
		})

		local macroControl
		macroControl = Main.CreateApp({
			Name = "Input Macros",
			Icon = Main.GetStudioAsset("macro/play"),
			Description = "Record and replay keyboard and mouse input",
			OnClick = function(open)
				if open then
					Main.SetMainGuiOpen(false)
					local first = Apps.InputMacros.Window == nil
					Apps.InputMacros.Open()
					if first then
						Apps.InputMacros.Window.OnActivate:Connect(function()
							macroControl.Enable(true)
						end)
						Apps.InputMacros.Window.OnDeactivate:Connect(function()
							macroControl.Disable(true)
						end)
					end
				else
					Apps.InputMacros.Hide()
				end
			end,
		})


		Lib.ShowGui(gui)
	end

	Main.StudioAssets = {}
	Main.SetupStudioAssets = function()
		if not StudioAssetData or not StudioAssetData.files or not env.writefile or not env.getcustomasset then
			return
		end
		if env.makefolder then
			for _, path in ipairs({ "dex-explorer", "dex-explorer/assets", "dex-explorer/assets/studio" }) do
				pcall(env.makefolder, path)
			end
		end
	end
	Main.GetStudioAsset = function(key)
		local cached = Main.StudioAssets[key]
		if cached ~= nil then
			return cached or nil
		end
		if not StudioAssetData or not env.writefile or not env.getcustomasset then
			return nil
		end
		local data = StudioAssetData.files[key]
		if not data then
			return nil
		end
		local filename = (StudioAssetData.version .. "_" .. key):gsub("[^%w%._%-]", "_") .. ".png"
		local path = "dex-explorer/assets/studio/" .. filename
		local ok, asset = pcall(function()
			if not env.isfile or not env.isfile(path) then
				env.writefile(path, data)
			end
			return env.getcustomasset(path)
		end)
		if ok and type(asset) == "string" and asset ~= "" then
			Main.StudioAssets[key] = asset
			return asset
		end
		Main.StudioAssets[key] = false
		return nil
	end

	Main.SetupFilesystem = function()
		if not env.writefile or not env.makefolder then
			return
		end

		for _, path in ipairs({
			"dex-explorer",
			"dex-explorer/assets",
			"dex-explorer/saved",
			"dex-explorer/plugins",
			"dex-explorer/ModuleCache",
		}) do
			pcall(env.makefolder, path)
		end
	end

	Main.LocalDepsUpToDate = function()
		return Main.DepsVersionData and Main.ClientVersion == Main.DepsVersionData[1]
	end

	Main.Init = function()
		Main.StartupBegan = os.clock()
		Main.StartupTimings = {}
		local phase = os.clock()
		local function finishPhase(name)
			local now = os.clock()
			Main.StartupTimings[name] = now - phase
			phase = now
		end
		Main.Elevated = pcall(function()
			local a = game:GetService("CoreGui"):GetFullName()
		end)

		Main.InitEnv()
		Main.SetupFilesystem()
		Main.LoadSettings()
		Main.SetupStudioAssets()
		finishPhase("environment")

		local intro = Main.CreateIntro("Loading src/Shared/Lib.lua")
		local function reportStartup(message, progress)
			intro.SetProgress(message, progress)
		end
		Main.StartupStatus = reportStartup
		Main.AddCleanup(function()
			if Main.StartupStatus == reportStartup then
				Main.StartupStatus = nil
			end
		end)
		if DexRuntime then
			DexRuntime.OnModuleLoading = function(path)
				if path ~= "main.lua" then
					intro.SetProgress("Loading " .. path)
				end
			end
			Main.AddCleanup(function()
				DexRuntime.OnModuleLoading = nil
			end)
		end
		Lib = Main.LoadModule("Lib")
		Lib.FastWait()

		Main.IncompatibleTest()
		finishPhase("base-runtime")

		Main.MiscIcons = Lib.IconMap.new("rbxassetid://6511490623", 256, 256, 16, 16)
		Main.MiscIcons:SetDict({
			Reference = 0,
			Cut = 1,
			Cut_Disabled = 2,
			Copy = 3,
			Copy_Disabled = 4,
			Paste = 5,
			Paste_Disabled = 6,
			Delete = 7,
			Delete_Disabled = 8,
			Group = 9,
			Group_Disabled = 10,
			Ungroup = 11,
			Ungroup_Disabled = 12,
			TeleportTo = 13,
			Rename = 14,
			JumpToParent = 15,
			ExploreData = 16,
			Save = 17,
			CallFunction = 18,
			CallRemote = 19,
			Undo = 20,
			Undo_Disabled = 21,
			Redo = 22,
			Redo_Disabled = 23,
			Expand_Over = 24,
			Expand = 25,
			Collapse_Over = 26,
			Collapse = 27,
			SelectChildren = 28,
			SelectChildren_Disabled = 29,
			InsertObject = 30,
			ViewScript = 31,
			AddStar = 32,
			RemoveStar = 33,
			Script_Disabled = 34,
			LocalScript_Disabled = 35,
			Play = 36,
			Pause = 37,
			Rename_Disabled = 38,
			Empty = 1000,
		})
		Main.LargeIcons = Lib.IconMap.new("rbxassetid://6579106223", 256, 256, 32, 32)
		Main.LargeIcons:SetDict({
			Explorer = 0,
			Properties = 1,
			Script_Viewer = 2,
			Watcher = 3,
			Output = 4,
		})


		intro.SetProgress(nil, 0.3)
		if Main.Elevated then
			intro.SetProgress("Reading dex-explorer/deps_version.dat")
			local fileVer = Lib.ReadFile("dex-explorer/deps_version.dat")
			Main.ClientVersion = Version()
			if fileVer then
				Main.DepsVersionData = string.split(fileVer, "\n")
				if Main.LocalDepsUpToDate() then
					Main.RobloxVersion = Main.DepsVersionData[2]
				end
			end

			if not Main.RobloxVersion then
				intro.SetProgress("Reading Roblox version: WindowsStudio64/LIVE")
				Main.RobloxVersion = oldgame
					:HttpGet("https://clientsettings.roblox.com/v2/client-version/WindowsStudio64/channel/LIVE")
					:match("(version%-[%w]+)")
			end
		end

		intro.SetProgress("Loading API-Dump.json", 0.35)
		local completed, failures = 0, {}
		local pending = { "Loading API-Dump.json", "Loading ReflectionMetadata.xml" }
		local function reportPending(index)
			local message = pending[index] or pending[1] or pending[2]
			intro.SetProgress(message, 0.35 + 0.2 * completed)
		end
		local function fetch(index, label, fn)
			task.spawn(function()
				local ok, result = pcall(fn, function(message)
					pending[index] = message
					reportPending(index)
				end)
				if not ok then
					failures[#failures + 1] = label .. ": " .. tostring(result)
				end
				pending[index] = nil
				completed += 1
				reportPending(index)
			end)
		end
		fetch(1, "API-Dump.json", function(onProgress)
			API = Main.FetchAPI(nil, nil, nil, onProgress)
		end)
		fetch(2, "ReflectionMetadata.xml", function(onProgress)
			RMD = Main.FetchRMD(onProgress)
		end)
		while completed < 2 do
			task.wait()
		end
		if #failures > 0 then
			error("[Dex Explorer] " .. table.concat(failures, "; "))
		end
		finishPhase("metadata")

		if Main.Elevated and env.writefile and not Main.LocalDepsUpToDate() then
			intro.SetProgress("Writing dex-explorer/deps_version.dat")
			env.writefile("dex-explorer/deps_version.dat", Main.ClientVersion .. "\n" .. Main.RobloxVersion)
			intro.SetProgress("Writing dex-explorer/rbx_api.dat")
			env.writefile("dex-explorer/rbx_api.dat", Main.RawAPI)
			intro.SetProgress("Writing dex-explorer/rbx_rmd.dat")
			env.writefile("dex-explorer/rbx_rmd.dat", Main.RawRMD)
		end

		intro.SetProgress("Initializing src/Shared/Lib.lua", 0.75)
		Main.AppControls.Lib.InitDeps(Main.GetInitDeps())
		Main.LoadModules()
		Lib.FastWait()
		finishPhase("modules")

		local function initPanel(name, progress, ...)
			local path = DexRuntime and DexRuntime.ModulePaths[name]
			intro.SetProgress("Initializing " .. (path or name), progress)
			Apps[name].Init(...)
		end
		initPanel("Explorer", 0.9)
		finishPhase("explorer")
		initPanel("Properties", 0.91)
		initPanel("ScriptViewer", 0.92, true)
		initPanel("Console", 0.93)
		initPanel("SaveInstance", 0.94)
		initPanel("ModelViewer", 0.95)
		finishPhase("panels")


		Lib.FastWait()

		intro.SetProgress("Initializing Lib.Window", 0.96)
		Lib.Window.Init()
		Apps.AntiAFK.SetEnabled(Settings.Interface.AntiAFK == true)
		intro.SetProgress("Creating Dex menu", 0.97)
		Main.CreateMainGui()
		Apps.GuiTransformTools.Init()
		Apps.TransformTools.Init()
		task.delay(1, function()
			if Main.Alive then
				Apps.Reconstructor.StartAutomatic()
			end
		end)
		Explorer.Window:Show({ Align = "right", Pos = 1, Size = 0.6, Silent = true })
		Properties.Window:Show({ Align = "right", Pos = 2, Size = 0.4, Silent = true })
		Main.InitGameInputFocus()
		Apps.PluginActions.Init()
		task.defer(function()
			if Main.Alive then
				Apps.PluginRuntime.Start()
				if type(env.isfile) == "function" then
					local ok, exists = pcall(env.isfile, "dex-explorer/input-macros.json")
					if ok and exists then
						Apps.InputMacros.Init()
					end
				end
			end
		end)

		local panels = {}
		for _, name in ipairs({ "Explorer", "Properties", "ScriptViewer", "Console", "SaveInstance", "ModelViewer" }) do
			if Apps[name].Window then
				panels[name] = Apps[name].Window
			end
		end
		intro.SetProgress("Restoring window layout", 0.99)
		Main.WindowLayout = Lib.Window.ConfigureLayoutPersistence(panels)
		finishPhase("windows-and-tools")
		Lib.DeferFunc(function()
			if not Main.WindowLayout:Restore() then
				Lib.Window.ToggleSide("right")
			end
		end)
		if DexRuntime then
			DexRuntime.OnModuleLoading = nil
		end
		Main.StartupStatus = nil
		intro.SetProgress("Ready", 1)
		if Main.Performance then
			Main.Performance.Record("startup/ready", os.clock() - (Main.StartupBegan or Main.Performance.Started))
		end
		intro.Close()
	end

	return Main
end)()

Main.Init()
if ggv then
	ggv().DexPlus = { Main = Main, Apps = Apps, Settings = Settings }
end
