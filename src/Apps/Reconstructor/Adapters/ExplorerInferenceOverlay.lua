--!strict

local Main, API, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, API, Apps = d.Main, d.API, d.Apps
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Overlay = {}
	function Overlay.Create(options)
		local Explorer, nodes, addObject, markSearchDirty =
			options.Explorer, options.Nodes, options.EnsureNode, options.MarkDirty
		local previous, revision, count
		local busy, pending = false, nil
		local function createDisplay(class, name)
			local info = API.Classes[class]
			local tags = info and info.Tags or {}
			if tags.NotCreatable or tags.Service or class == "Terrain" then
				class = "Folder"
			end
			local ok, obj = pcall(Instance.new, class)
			if not ok then
				obj = Instance.new("Folder")
			end
			obj.Name = name
			if obj:IsA("BaseScript") or obj.ClassName == "Script" or obj.ClassName == "LocalScript" then
				obj.Disabled = true
			end
			return obj
		end
		if Main.AddCleanup then
			Main.AddCleanup(function()
				for obj in pairs(Explorer.InferredObjects) do
					nodes[obj] = nil
					pcall(function()
						obj:Destroy()
					end)
				end
			end)
		end
		local function synchronize(evidence)
			if not nodes[game] then
				return
			end
			if previous == evidence and revision == evidence.Revision and count == evidence.Count then
				return
			end
			previous, revision, count = evidence, evidence.Revision, evidence.Count
			local changed = false
			local yielded = os.clock()
			local function attach(claim, parent)
				if Main.Alive == false then
					return
				end
				if task.wait and os.clock() - yielded > 0.001 then
					task.wait()
					yielded = os.clock()
				end
				local resolved, status = evidence:ResolveClass(claim)
				if not API.Classes[resolved] then
					resolved = "Folder"
					status = "Unsupported class; Folder fallback"
				end
				local node = Explorer.InferredNodes[claim.Id]
				if not node then
					for _, child in ipairs(parent) do
						if not child.Inferred and child.Obj.Name == claim.Name then
							node = child
							break
						end
					end
					if not node then
						local display = createDisplay(resolved, claim.Name)
						node = { Obj = display, Parent = parent, Inferred = claim, Materialized = true }
						Explorer.InferredObjects[display] = node
						nodes[display] = node
						parent[#parent + 1] = node
						parent.Sorted = false
						display.Parent = parent.Obj
						markSearchDirty(node, true)
						changed = true
					end
					Explorer.InferredNodes[claim.Id] = node
				end
				if node.Inferred then
					node.Inferred = claim
					local class = evidence:ClassLabel(claim)
					if node.ResolvedClass ~= resolved then
						if node.Obj.ClassName ~= resolved then
							local old = node.Obj
							local replacement = createDisplay(resolved, claim.Name)
							nodes[old] = nil
							Explorer.InferredObjects[old] = nil
							node.Obj = replacement
							nodes[replacement] = node
							Explorer.InferredObjects[replacement] = node
							replacement.Parent = parent.Obj
							for _, child in ipairs(node) do
								if child.Inferred then
									child.Obj.Parent = replacement
								end
							end
							old:Destroy()
						end
						node.ResolvedClass = resolved
						changed = true
					end
					local nextClass = node.Obj.ClassName
					if nextClass ~= node.InferredClass then
						changed = true
						parent.Sorted = false
					end
					node.InferredClass = nextClass
					node.Class = node.InferredClass or "Instance"
					local lines = {}
					for _, item in ipairs(claim.Evidence) do
						lines[#lines + 1] = tostring(item.Source)
							.. (item.Line and ":" .. item.Line or "")
							.. " — "
							.. item.Kind
					end
					local display = node.Obj
					if resolved == "ModuleScript" and Apps and Apps.ModuleReconstruction then
						Apps.ModuleReconstruction.Bind(display, claim)
					end
					node.ClassStatus = display.ClassName == resolved and status or "Uncreatable class; Folder fallback"
					node.EvidenceSummary = #lines > 0 and table.concat(lines, "\n")
						or "Implied container; class unknown"
				end
				for _, child in ipairs(claim.Children) do
					attach(child, node)
				end
			end
			for _, root in ipairs(evidence.Roots) do
				local ok, obj = pcall(function()
					return game:GetService(root.Name)
				end)
				if ok and obj then
					if not nodes[obj] then
						addObject(obj)
					end
					local parent = nodes[obj]
					if parent then
						for _, child in ipairs(root.Children) do
							attach(child, parent)
						end
					end
				end
			end
			if changed then
				options.Changed()
				Explorer.PerformUpdate(true)
			end
		end
		return function(evidence)
			pending = evidence
			if busy then
				return
			end
			busy = true
			local ok, problem = pcall(function()
				while pending and Main.Alive ~= false do
					local current = pending
					pending = nil
					synchronize(current)
				end
			end)
			busy = false
			if not ok then
				previous = nil
				Explorer.ReconstructionError = tostring(problem)
				error(problem, 0)
			end
		end
	end
	return Overlay
end
return { InitDeps = InitDeps, Main = CreateModule }
