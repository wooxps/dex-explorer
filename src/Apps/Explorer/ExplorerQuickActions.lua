--!strict

local Main, Apps, env, service, plr, Lib

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, env, service, plr, Lib = d.Main, d.Apps, d.env, d.service, d.plr, d.Lib
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Actions = {}
	local tracks = {}
	local listening, originalListener, listenerConnections
	local function character()
		return plr.Character
	end
	local function humanoid()
		local c = character()
		return c and c:FindFirstChildOfClass("Humanoid")
	end
	local function stopListening()
		if not listening then
			return
		end
		listening = nil
		for _, connection in ipairs(listenerConnections or {}) do
			connection:Disconnect()
		end
		listenerConnections = nil
		if originalListener then
			local saved = originalListener
			originalListener = nil
			local ok = pcall(function()
				service.SoundService:SetListener(table.unpack(saved, 1, saved.n))
			end)
			if not ok then
				pcall(function()
					service.SoundService:SetListener(Enum.ListenerType.Camera)
				end)
			end
		end
	end
	local function stopTrack(animation)
		local item = tracks[animation]
		tracks[animation] = nil
		if item then
			if item.Connection then
				item.Connection:Disconnect()
			end
			pcall(function()
				item.Track:Stop()
				item.Track:Destroy()
			end)
		end
	end
	local highlights = {}
	local highlightRoot
	local function highlightTarget(object)
		if object:IsA("Player") then
			return object.Parent == service.Players and object or nil
		end
		if object:IsA("Model") then
			local player = service.Players:GetPlayerFromCharacter(object)
			if player then
				return player
			end
		end
		if
			(object:IsA("BasePart") or object:IsA("Model"))
			and not object:IsA("Terrain")
			and object:IsDescendantOf(service.Workspace)
		then
			return object
		end
	end
	local function clearHighlight(record)
		if record.TargetConnection then
			record.TargetConnection:Disconnect()
			record.TargetConnection = nil
		end
		if record.Visual then
			record.Visual:Destroy()
			record.Visual = nil
		end
	end
	local function removeHighlight(target)
		local record = highlights[target]
		if not record then
			return
		end
		highlights[target] = nil
		for _, connection in ipairs(record.Connections) do
			connection:Disconnect()
		end
		clearHighlight(record)
		if highlightRoot and not next(highlights) then
			Main.SelectionGeometryRoots[highlightRoot] = nil
			highlightRoot:Destroy()
			highlightRoot = nil
		end
	end
	local function showHighlight(record, object)
		clearHighlight(record)
		if not object then
			return
		end
		if not highlightRoot then
			highlightRoot = Instance.new("Folder")
			highlightRoot.Name = "DexObjectHighlights"
			highlightRoot.Archivable = false
			Main.SelectionGeometryRoots = Main.SelectionGeometryRoots or setmetatable({}, { __mode = "k" })
			Main.SelectionGeometryRoots[highlightRoot] = true
			highlightRoot.Parent = service.Workspace
		end
		local visual = Instance.new("Highlight")
		visual.Name = "ObjectHighlight"
		visual.Archivable = false
		visual.FillColor = Color3.fromRGB(255, 255, 255)
		visual.FillTransparency = 0.82
		visual.OutlineColor = visual.FillColor
		visual.OutlineTransparency = 0
		visual.DepthMode = Enum.HighlightDepthMode.Occluded
		visual.Adornee = object
		visual.Parent = highlightRoot
		record.Visual = visual
	end
	local function addHighlight(target)
		local record = { Connections = {} }
		highlights[target] = record
		if target:IsA("Player") then
			local function attach(character)
				if highlights[target] ~= record or target.Character ~= character then
					return
				end
				showHighlight(record, character)
				if character then
					record.TargetConnection = character.Destroying:Connect(function()
						if record.Visual and record.Visual.Adornee == character then
							clearHighlight(record)
						end
					end)
				end
			end
			record.Connections = {
				target.CharacterAdded:Connect(attach),
				target.CharacterRemoving:Connect(function(character)
					if record.Visual and record.Visual.Adornee == character then
						clearHighlight(record)
					end
				end),
				target.AncestryChanged:Connect(function()
					if target.Parent ~= service.Players then
						removeHighlight(target)
					end
				end),
				target.Destroying:Connect(function()
					removeHighlight(target)
				end),
			}
			attach(target.Character)
		else
			record.Connections = {
				target.Destroying:Connect(function()
					removeHighlight(target)
				end),
				target.AncestryChanged:Connect(function()
					if not target:IsDescendantOf(service.Workspace) then
						removeHighlight(target)
					end
				end),
			}
			showHighlight(record, target)
		end
	end
	local function highlightSelection(selection)
		local targets, seen = {}, {}
		local allHighlighted = true
		for _, node in ipairs(selection.List) do
			local target = highlightTarget(node.Obj)
			if target and not seen[target] then
				targets[#targets + 1] = target
				seen[target] = true
				if not highlights[target] then
					allHighlighted = false
				end
			end
		end
		return targets, allHighlighted
	end
	local function supportedProperty(object)
		if object:IsA("GuiObject") then
			return "Visible"
		end
		if object:IsA("LayerCollector") then
			return "Enabled"
		end
	end
	local function enabledProperty(object)
		if object:IsA("BaseScript") then
			return "Disabled", true
		end
		if
			object:IsA("ProximityPrompt")
			or object:IsA("ParticleEmitter")
			or object:IsA("Beam")
			or object:IsA("Trail")
			or object:IsA("Light")
			or object:IsA("PostEffect")
			or object:IsA("Highlight")
			or object:IsA("Constraint")
			or object:IsA("SoundEffect")
		then
			return "Enabled", false
		end
	end
	local function objects(selection)
		local out = {}
		for _, node in ipairs(selection.List) do
			out[#out + 1] = node.Obj
		end
		return out
	end
	local function first(selection, predicate)
		for _, node in ipairs(selection.List) do
			if predicate(node.Obj) then
				return node.Obj
			end
		end
	end
	local function position(object)
		if object:IsA("BasePart") then
			return object.Position
		elseif object:IsA("Model") then
			return object:GetPivot().Position
		end
	end
	local indicators = {}
	local indicatorGui
	local function clearIndicator(part)
		local item = indicators[part]
		if not item then return end
		indicators[part] = nil
		for _, conn in item.Connections do conn:Disconnect() end
		item.Root:Destroy()
		if not next(indicators) then indicatorGui:Destroy() indicatorGui = nil end
	end
	local function showIndicator(part)
		if not indicatorGui then
			indicatorGui = Instance.new("ScreenGui")
			indicatorGui.Name = "DexOrientationIndicators"
			Lib.ShowGui(indicatorGui)
		end
		local root = Instance.new("Folder", indicatorGui)
		local function adorn(class, color)
			local item = Instance.new(class)
			item.Adornee, item.Color3, item.AlwaysOnTop, item.ZIndex = part, color, true, 1
			item.Parent = root
			return item
		end
		local blue, green = Color3.fromRGB(50,145,255), Color3.fromRGB(76,205,99)
		local front = adorn("LineHandleAdornment", blue)
		local tip = adorn("ConeHandleAdornment", green)
		local badge = Instance.new("BillboardGui", root)
		badge.Adornee, badge.AlwaysOnTop, badge.Size = part, true, UDim2.fromOffset(20,20)
		local label = Instance.new("TextLabel", badge)
		label.Size, label.BackgroundColor3 = UDim2.fromScale(1,1), blue
		label.Text, label.TextColor3, label.Font, label.TextSize = "F", Color3.new(1,1,1), Enum.Font.SourceSansBold, 15
		Instance.new("UICorner",label).CornerRadius = UDim.new(1,0)
		local function update()
			local size = part.Size
			local length = math.clamp(size.Magnitude * 0.2, 0.4, 4)
			local frontMarker = Vector3.new(0, 0, -size.Z / 2 - length)
			local base = CFrame.new(frontMarker + Vector3.new(0, length * 0.2, 0)) * CFrame.Angles(math.pi / 2, 0, 0)
			front.CFrame, front.Length, front.Thickness = CFrame.new(0,0,-size.Z/2), length, 2
			tip.CFrame, tip.Radius, tip.Height = base, length * 0.12, length * 0.3
			badge.StudsOffsetWorldSpace = part.CFrame:VectorToWorldSpace(frontMarker)
		end
		update()
		indicators[part] = { Root = root, Connections = {
			service.RunService.RenderStepped:Connect(function()
				local offset = part.CFrame.LookVector * (part.Size.Z/2 + front.Length)
				if badge.StudsOffsetWorldSpace ~= offset then badge.StudsOffsetWorldSpace = offset end
			end),
			part:GetPropertyChangedSignal("Size"):Connect(update),
			part.AncestryChanged:Connect(function()
				if not part:IsDescendantOf(service.Workspace) then clearIndicator(part) end
			end),
			part.Destroying:Connect(function() clearIndicator(part) end),
		} }
	end
	function Actions.AddOrientation(context, list)
		local parts, all = {}, true
		for _, node in list do
			local part = node.Obj
			if part:IsA("BasePart") and not part:IsA("Terrain") and part:IsDescendantOf(service.Workspace) then
				parts[#parts+1] = part
				if not indicators[part] then all = false end
			end
		end
		if #parts == 0 then return end
		context:Add({
			Name = if all then "Hide Orientation Indicator" else "Show Orientation Indicator",
			Checked = all,
			OnClick = function()
				for _, part in parts do
					if all then clearIndicator(part)
					elseif not indicators[part] and part:IsDescendantOf(service.Workspace) then showIndicator(part) end
				end
			end,
		})
	end
	function Actions.Register(context, selection)
		local function register(id, name, callback)
			context:Register(id, {
				Name = name,
				OnClick = function()
					if Apps.Explorer.HasInferredSelection() or Apps.Explorer.HasReconstructedSelection() then
						return
					end
					local ok, err = pcall(callback)
					if not ok then
						warn("[Dex] " .. name .. ": " .. tostring(err))
					end
				end,
			})
		end
		local function each(class, callback)
			for _, object in ipairs(objects(selection)) do
				if object:IsA(class) then
					local ok, err = pcall(callback, object)
					if not ok then
						warn("[Dex] " .. tostring(err))
					end
				end
			end
		end
		register("TOGGLE_HIGHLIGHT", "Highlight", function()
			local targets, allHighlighted = highlightSelection(selection)
			for _, target in ipairs(targets) do
				if allHighlighted then
					removeHighlight(target)
				elseif not highlights[target] then
					local ok, problem = pcall(addHighlight, target)
					if not ok then
						removeHighlight(target)
						warn("[Dex] Highlight: " .. tostring(problem))
					end
				end
			end
		end)
		register("SIT_HERE", "Sit Here", function()
			local seat = first(selection, function(o)
				return o:IsA("Seat") or o:IsA("VehicleSeat")
			end)
			local h = humanoid()
			assert(seat and h, "Select a seat and spawn your character first")
			seat:Sit(h)
		end)
		register("WALK_TO", "Walk To", function()
			local target = first(selection, function(o)
				return o:IsA("BasePart") or o:IsA("Model")
			end)
			local h = humanoid()
			assert(target and h, "Select a part or model and spawn your character first")
			h:MoveTo(position(target))
		end)
		register("LISTEN_PLAYER", "Listen To", function()
			local player = first(selection, function(o)
				return o:IsA("Player")
			end)
			if not player then
				return
			end
			if listening == player then
				stopListening()
				return
			end
			local c = player.Character
			local root = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head"))
			assert(root, "This player has no character to listen to")
			stopListening()
			originalListener = table.pack(service.SoundService:GetListener())
			local ok, err = pcall(function()
				service.SoundService:SetListener(Enum.ListenerType.ObjectPosition, root)
			end)
			if not ok then
				originalListener = nil
				error(err)
			end
			listening = player
			listenerConnections = {
				player.CharacterRemoving:Connect(function()
					stopListening()
				end),
				player.AncestryChanged:Connect(function(_, parent)
					if not parent then
						stopListening()
					end
				end),
			}
		end)
		register("EQUIP_TOOL", "Equip", function()
			local h = humanoid()
			assert(h, "Spawn your character first")
			local c = character()
			local backpack = plr:FindFirstChildOfClass("Backpack")
			local unequip = first(selection, function(o)
				return o:IsA("Tool") and o.Parent == c
			end) ~= nil
			each("Tool", function(tool)
				assert(tool.Parent == c or tool.Parent == backpack, "Tool must be in your character or backpack")
				if unequip then
					if tool.Parent == c then
						tool.Parent = backpack
					end
				else
					h:EquipTool(tool)
				end
			end)
		end)
		register("ACTIVATE_TOOL", "Activate", function()
			each("Tool", function(tool)
				assert(tool.Parent == character(), "Equip this tool first")
				tool:Activate()
			end)
		end)
		register("DROP_TOOL", "Drop", function()
			each("Tool", function(tool)
				assert(
					tool.Parent == character() or tool.Parent == plr:FindFirstChildOfClass("Backpack"),
					"Tool must belong to your character"
				)
				assert(tool.CanBeDropped, "This tool cannot be dropped")
				tool.Parent = workspace
			end)
		end)
		register("LOAD_ANIMATION", "Play on My Character", function()
			local animation = first(selection, function(o)
				return o:IsA("Animation")
			end)
			if not animation then
				return
			end
			local old = tracks[animation]
			if old and old.Track.IsPlaying then
				stopTrack(animation)
				return
			end
			stopTrack(animation)
			local h = humanoid()
			assert(h, "Spawn your character first")
			local animator = h:FindFirstChildOfClass("Animator")
			assert(animator, "Your character has no Animator")
			local track = animator:LoadAnimation(animation)
			tracks[animation] = { Track = track }
			tracks[animation].Connection = track.Stopped:Connect(function()
				stopTrack(animation)
			end)
			local ok, err = pcall(function()
				track:Play()
			end)
			if not ok then
				stopTrack(animation)
				error(err)
			end
		end)
		local function toggle(propertyGetter)
			local targets = {}
			local turnOn = false
			for _, object in ipairs(objects(selection)) do
				local property, inverted = propertyGetter(object)
				if property then
					local ok, value = pcall(function()
						return object[property]
					end)
					if ok and type(value) == "boolean" then
						local on = value
						if inverted then
							on = not value
						end
						targets[#targets + 1] = { Object = object, Property = property, Inverted = inverted }
						turnOn = turnOn or not on
					end
				end
			end
			Apps.History.Run("Toggle selected objects", function()
				for _, target in ipairs(targets) do
					local value = turnOn
					if target.Inverted then
						value = not value
					end
					Apps.History.Set(target.Object, target.Property, value)
				end
			end)
		end
		register("TOGGLE_VISIBILITY", "Hide", function()
			toggle(supportedProperty)
		end)
		register("TOGGLE_ENABLED", "Disable", function()
			toggle(enabledProperty)
		end)
		register("FIRE_PROXIMITYPROMPT", "Trigger Prompt", function()
			assert(type(fireproximityprompt) == "function", "Prompt triggering is unavailable")
			each("ProximityPrompt", fireproximityprompt)
		end)
		register("FIRE_CLICKDETECTOR", "Click", function()
			assert(type(fireclickdetector) == "function", "Click triggering is unavailable")
			each("ClickDetector", function(o)
				fireclickdetector(o, 0, "MouseClick")
			end)
		end)
		register("RIGHT_CLICKDETECTOR", "Right Click", function()
			assert(type(fireclickdetector) == "function", "Click triggering is unavailable")
			each("ClickDetector", function(o)
				fireclickdetector(o, 0, "RightMouseClick")
			end)
		end)
		register("FIRE_TOUCHTRANSMITTER", "Trigger Touch", function()
			assert(type(firetouchinterest) == "function", "Touch triggering is unavailable")
			local c = character()
			local root = c and c:FindFirstChild("HumanoidRootPart")
			assert(root, "Spawn your character first")
			each("TouchTransmitter", function(o)
				local part = o.Parent
				assert(part and part:IsA("BasePart"), "Touch transmitter has no part")
				firetouchinterest(root, part, 0)
				task.defer(function()
					local ok, err = pcall(firetouchinterest, root, part, 1)
					if not ok then
						warn("[Dex] Touch release: " .. tostring(err))
					end
				end)
			end)
		end)
	end
	function Actions.Add(context, selection)
		local function has(class)
			return first(selection, function(o)
				return o:IsA(class)
			end) ~= nil
		end
		local highlightTargets, allHighlighted = highlightSelection(selection)
		if #highlightTargets > 0 then
			context.Registered.TOGGLE_HIGHLIGHT.Name = allHighlighted and "Remove Highlight" or "Highlight"
			context.Registered.TOGGLE_HIGHLIGHT.Checked = allHighlighted
			context:AddRegistered("TOGGLE_HIGHLIGHT")
		end
		if has("Seat") or has("VehicleSeat") then
			context:AddRegistered("SIT_HERE", humanoid() == nil)
		end
		if has("BasePart") or has("Model") then
			context:AddRegistered("WALK_TO", humanoid() == nil)
		end
		if has("Player") then
			local player = first(selection, function(o)
				return o:IsA("Player")
			end)
			context.Registered.LISTEN_PLAYER.Name = listening == player and "Stop Listening To" or "Listen To"
			context:AddRegistered("LISTEN_PLAYER")
		end
		if has("Tool") then
			local c = character()
			local backpack = plr:FindFirstChildOfClass("Backpack")
			local own = false
			local equipped = false
			local droppable = false
			for _, o in ipairs(objects(selection)) do
				if o:IsA("Tool") then
					own = own or (c ~= nil and o.Parent == c) or (backpack ~= nil and o.Parent == backpack)
					equipped = equipped or (c ~= nil and o.Parent == c)
					droppable = droppable or (o.CanBeDropped and (o.Parent == c or o.Parent == backpack))
				end
			end
			context.Registered.EQUIP_TOOL.Name = equipped and "Unequip" or "Equip"
			context:AddRegistered("EQUIP_TOOL", not own or humanoid() == nil)
			context:AddRegistered("ACTIVATE_TOOL", not equipped)
			context:AddRegistered("DROP_TOOL", not droppable)
		end
		local animation = first(selection, function(o)
			return o:IsA("Animation")
		end)
		if animation then
			local item = tracks[animation]
			context.Registered.LOAD_ANIMATION.Name = item and item.Track.IsPlaying and "Stop Playing on My Character"
				or "Play on My Character"
			context:AddRegistered("LOAD_ANIMATION", humanoid() == nil)
		end
		local function addToggle(getter, id, onName, offName)
			local any = false
			local allOn = true
			for _, object in ipairs(objects(selection)) do
				local property, inverted = getter(object)
				if property then
					local ok, value = pcall(function()
						return object[property]
					end)
					if ok and type(value) == "boolean" then
						any = true
						local on = value
						if inverted then
							on = not value
						end
						allOn = allOn and on
					end
				end
			end
			if any then
				context.Registered[id].Name = allOn and offName or onName
				context.Registered[id].Checked = allOn
				context:AddRegistered(id)
			end
		end
		addToggle(supportedProperty, "TOGGLE_VISIBILITY", "Show", "Hide")
		local scriptOnly = #selection.List > 0
		for _, node in ipairs(selection.List) do
			if not node.Obj:IsA("BaseScript") then scriptOnly = false break end
		end
		if not scriptOnly or not (context.Added and context.Added.TOGGLE_SCRIPTS) then
			addToggle(enabledProperty, "TOGGLE_ENABLED", "Enable", "Disable")
		end
		if has("ClickDetector") then
			context:AddRegistered("RIGHT_CLICKDETECTOR", type(fireclickdetector) ~= "function")
		end
	end
	Main.AddCleanup(function()
		while next(indicators) do clearIndicator(next(indicators)) end
		while next(highlights) do
			removeHighlight(next(highlights))
		end
		stopListening()
		local keys = {}
		for animation in pairs(tracks) do
			keys[#keys + 1] = animation
		end
		for _, animation in ipairs(keys) do
			stopTrack(animation)
		end
	end)
	if plr and plr.CharacterRemoving then
		local connection = plr.CharacterRemoving:Connect(function()
			local keys = {}
			for a in pairs(tracks) do
				keys[#keys + 1] = a
			end
			for _, a in ipairs(keys) do
				stopTrack(a)
			end
		end)
		Main.AddCleanup(function()
			connection:Disconnect()
		end)
	end
	return Actions
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
