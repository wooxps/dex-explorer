--!strict

local Main, service

------------------------------ Initialization ------------------------------

local function InitDeps(deps)
	Main, service = deps.Main, deps.service
end

------------------------------ Module ------------------------------

local function CreateModule()
	local GeometryMask = {}
	local COPY_ALPHA = 0.9999999
	local MAX_PARTS = 8192
	local MAX_TOTAL_PARTS = 16384
	local BULK_MOVE_THRESHOLD = 32
	local copies = setmetatable({}, { __mode = "k" })
	Main.SelectionGeometryObjects = copies
	local totalParts = 0
	local activeMasks = 0
	local root
	local function disconnect(connections)
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	local function isGeometryChild(object)
		return object:IsA("DataModelMesh") or object:IsA("SurfaceAppearance") or object:IsA("Bone")
	end
	local function unsupportedGeometry(source)
		return source:FindFirstChildOfClass("WrapLayer") or source:FindFirstChildOfClass("WrapTarget")
	end
	local function copyInstance(source)
		assert(type(Instance.fromExisting) == "function", "Shallow geometry copying is unavailable")
		local copy = Instance.fromExisting(source)
		copies[copy] = true
		local ok, problem = pcall(function()
			copy.Archivable = false
			for _, tag in ipairs(copy:GetTags()) do
				copy:RemoveTag(tag)
			end
			for name in pairs(copy:GetAttributes()) do
				copy:SetAttribute(name, nil)
			end
		end)
		if not ok then
			copy:Destroy()
			error(problem, 0)
		end
		return copy
	end
	local function getRoot()
		if root then
			return root
		end
		root = Instance.new("Folder")
		copies[root] = true
		root.Name = "DexSelectionGeometry"
		root.Archivable = false
		Main.SelectionGeometryRoots = Main.SelectionGeometryRoots or setmetatable({}, { __mode = "k" })
		Main.SelectionGeometryRoots[root] = true
		root.Parent = service.Workspace
		return root
	end
	local function releaseRoot()
		if activeMasks == 0 and root then
			root:Destroy()
			if Main.SelectionGeometryRoots then
				Main.SelectionGeometryRoots[root] = nil
			end
			root = nil
		end
	end
	function GeometryMask.IsInternal(object)
		if not root then
			return false
		end
		return object == root or object:IsDescendantOf(root)
	end
	function GeometryMask.Create(parts, onChanged, onStepChanged)
		if type(Instance.fromExisting) ~= "function" then
			return nil, "No shallow geometry copier"
		end
		local sources = {}
		for source in pairs(parts) do
			if #sources == MAX_PARTS then
				return nil, "Geometry mask size limit"
			end
			if unsupportedGeometry(source) then
				return nil, "Wrapped geometry requires the original renderer"
			end
			sources[#sources + 1] = source
		end
		if #sources == 0 then
			return nil, "Geometry mask size limit"
		end
		local model = Instance.new("Model")
		copies[model] = true
		model.Name = "SelectionMask"
		model.Archivable = false
		local humanoid = Instance.new("Humanoid")
		copies[humanoid] = true
		humanoid.Name = "MaskRenderer"
		humanoid.AutoRotate = false
		humanoid.AutomaticScalingEnabled = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.Parent = model
		local self = {
			Model = model,
			Entries = {},
			Dynamic = {},
			NeedsStep = false,
			Bones = {},
			Count = 0,
			Version = 0,
			Ready = false,
			Failed = false,
			Destroyed = false,
		}
		local queue, queued, head = sources, {}, 1
		for _, source in ipairs(sources) do
			queued[source] = true
		end
		activeMasks += 1
		local scheduled = false
		local pump
		local movedParts, movedPoses, movedEntries = {}, {}, {}
		local function updateStepping()
			local needed = next(self.Dynamic) ~= nil or next(self.Bones) ~= nil
			if needed ~= self.NeedsStep then
				self.NeedsStep = needed
				if not self.Destroyed and onStepChanged then onStepChanged(self, needed) end
			end
		end
		local function changed()
			if not self.Destroyed and onChanged then
				onChanged()
			end
		end
		local function setFailure(problem)
			self.Failed = true
			self.Problem = tostring(problem)
			changed()
		end
		local function destroyEntry(source)
			local entry = self.Entries[source]
			if not entry then
				return
			end
			self.Entries[source] = nil
			self.Dynamic[source] = nil
			for _, binding in ipairs(entry.Bones) do
				self.Bones[binding.Source] = nil
			end
			updateStepping()
			disconnect(entry.Connections)
			entry.Copy:Destroy()
			self.Count -= 1
			totalParts -= 1
		end
		local function createEntry(source)
			assert(totalParts < MAX_TOTAL_PARTS, "Total geometry mask size limit")
			assert(not unsupportedGeometry(source), "Wrapped geometry requires the original renderer")
			local copy = copyInstance(source)
			local connections, bones = {}, {}
			local entry = { Copy = copy, Connections = connections, Bones = bones, LastPose = copy.CFrame }
			local ok, problem = pcall(function()
				copy.Anchored = true
				copy.CanCollide = false
				copy.CanTouch = false
				copy.CanQuery = false
				copy.CastShadow = false
				copy.Transparency = COPY_ALPHA
				copy.LocalTransparencyModifier = 0
				copy.Material = Enum.Material.SmoothPlastic
				copy.Reflectance = 0
				copy.Color = Color3.new(0, 0, 0)
				local function geometryChildren(original, parent)
					for _, child in ipairs(original:GetChildren()) do
						if isGeometryChild(child) then
							local childCopy = copyInstance(child)
							if child:IsA("Bone") then
								local binding = { Source = child, Copy = childCopy }
								bones[#bones + 1] = binding
							else
								connections[#connections + 1] = child.Changed:Connect(function(property)
									if property == "Parent" or property == "Name" or property == "Archivable" then
										return
									end
									pcall(function()
										childCopy[property] = child[property]
									end)
								end)
							end
							geometryChildren(child, childCopy)
							childCopy.Parent = parent
						end
					end
				end
				geometryChildren(source, copy)
				local refreshing = false
				local function refresh()
					if refreshing then
						return
					end
					refreshing = true
					task.defer(function()
						if self.Destroyed or self.Entries[source] ~= entry then
							return
						end
						self.Ready = false
						changed()
						destroyEntry(source)
						self:Add(source)
					end)
				end
				connections[#connections + 1] = source.Changed:Connect(function(property)
					if self.Destroyed or self.Entries[source] ~= entry then
						return
					end
					if property == "CFrame" or property == "Size" or property == "Shape" then
						local value = source[property]
						copy[property] = value
						if property == "CFrame" then
							entry.LastPose = value
						end
					elseif property == "Anchored" then
						self.Dynamic[source] = not source.Anchored and entry or nil
						updateStepping()
					elseif property == "TextureID" or property == "TextureContent" or property == "RenderFidelity" then
						pcall(function()
							copy[property] = source[property]
						end)
					elseif property == "MeshId" or property == "MeshContent" or property == "DoubleSided" then
						refresh()
					end
				end)
				connections[#connections + 1] = source.DescendantAdded:Connect(function(child)
					if isGeometryChild(child) or child:IsA("WrapLayer") or child:IsA("WrapTarget") then
						refresh()
					end
				end)
				connections[#connections + 1] = source.DescendantRemoving:Connect(function(child)
					if isGeometryChild(child) then
						refresh()
					end
				end)
				copy.Parent = model
			end)
			if not ok then
				disconnect(connections)
				copy:Destroy()
				error(problem, 0)
			end
			self.Entries[source] = entry
			self.Dynamic[source] = not source.Anchored and entry or nil
			for _, binding in ipairs(bones) do
				self.Bones[binding.Source] = binding
			end
			updateStepping()
			self.Count += 1
			totalParts += 1
		end
		pump = function()
			scheduled = false
			if self.Destroyed or self.Failed then
				return
			end
			local started, processed = os.clock(), 0
			while head <= #queue and processed < 256 and os.clock() - started < 0.003 do
				local source = queue[head]
				queue[head] = false
				head += 1
				if queued[source] then
					queued[source] = nil
					if not self.Entries[source] then
						local ok, problem = pcall(createEntry, source)
						if not ok then
							setFailure(problem)
							return
						end
					end
				end
				processed += 1
			end
			if head <= #queue then
				scheduled = true
				task.delay(0, pump)
			else
				table.clear(queue)
				head = 1
				if not model.Parent then
					model.Parent = getRoot()
				end
				self.Ready = true
				self.Version += 1
				changed()
			end
		end
		function self:Add(source)
			if self.Destroyed or self.Failed or self.Entries[source] or queued[source] then
				return
			end
			if self.Count + #queue - head + 1 >= MAX_PARTS then
				setFailure("Geometry mask size limit")
				return
			end
			if self.Ready then
				self.Ready = false
				changed()
			end
			queued[source] = true
			queue[#queue + 1] = source
			if not scheduled then
				scheduled = true
				task.delay(0, pump)
			end
		end
		function self:Remove(source)
			queued[source] = nil
			destroyEntry(source)
		end
		function self:Step()
			if self.Destroyed or self.Failed or not model.Parent then
				return
			end
			for source, entry in pairs(self.Dynamic) do
				local pose = source.CFrame
				if entry.LastPose ~= pose then
					if self.Count < BULK_MOVE_THRESHOLD then
						entry.Copy.CFrame = pose
						entry.LastPose = pose
					else
						local index = #movedParts + 1
						movedParts[index], movedPoses[index], movedEntries[index] = entry.Copy, pose, entry
					end
				end
			end
			if #movedParts > 0 then
				local bulk = #movedParts >= BULK_MOVE_THRESHOLD and service.Workspace.BulkMoveTo
				if bulk then
					bulk = pcall(bulk, service.Workspace, movedParts, movedPoses, Enum.BulkMoveMode.FireCFrameChanged)
				end
				for index, entry in ipairs(movedEntries) do
					local pose = movedPoses[index]
					if not bulk then
						entry.Copy.CFrame = pose
					end
					entry.LastPose = pose
				end
				table.clear(movedParts)
				table.clear(movedPoses)
				table.clear(movedEntries)
			end
			for source, binding in pairs(self.Bones) do
				local pose, transform = source.CFrame, source.Transform
				if binding.LastPose ~= pose then
					binding.Copy.CFrame = pose
					binding.LastPose = pose
				end
				if binding.LastTransform ~= transform then
					binding.Copy.Transform = transform
					binding.LastTransform = transform
				end
			end
		end
		function self:Fail(problem)
			if not self.Destroyed and not self.Failed then
				setFailure(problem)
			end
		end
		function self:Destroy()
			if self.Destroyed then
				return
			end
			self.Destroyed = true
			for source in pairs(self.Entries) do
				destroyEntry(source)
			end
			table.clear(queue)
			table.clear(queued)
			model:Destroy()
			activeMasks -= 1
			releaseRoot()
		end
		scheduled = true
		task.defer(pump)
		return self
	end
	return GeometryMask
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
