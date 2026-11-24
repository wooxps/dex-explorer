--!strict

local Apps, Main, env, service, scheduler, world

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, env, service, scheduler, world = d.Apps, d.Main, d.env, d.service, d.Task or task, d.Game or game
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Session = {}
	local scanSliceSeconds = 0.002
	function Session.DecodeArguments(text)
		if type(text) ~= "string" or #text > 8192 or not text:match("^%s*%[") then
			return nil, "Enter a JSON array, up to 8 KB."
		end
		local ok, arguments = pcall(function()
			return service.HttpService:JSONDecode(text)
		end)
		if not ok or type(arguments) ~= "table" then
			return nil, "Invalid JSON argument array."
		end
		local depth, quoted, escaped, count, nonempty = 0, false, false, 0, false
		for i = 1, #text do
			local c = text:sub(i, i)
			if quoted then
				if escaped then
					escaped = false
				elseif c == "\\" then
					escaped = true
				elseif c == '"' then
					quoted = false
				end
			elseif c == '"' then
				quoted = true
				if depth == 1 then
					nonempty = true
				end
			elseif c == "[" or c == "{" then
				if depth == 1 then
					nonempty = true
				end
				depth += 1
			elseif c == "]" or c == "}" then
				depth -= 1
			elseif depth == 1 and c == "," then
				count += 1
			elseif depth == 1 and not c:match("%s") then
				nonempty = true
			end
		end
		count = nonempty and count + 1 or 0
		if count > 16 then
			return nil, "Use at most 16 arguments."
		end
		return arguments, count
	end
	function Session.Create(onChange)
		local self = {
			ModuleBudget = { Count = 0, Limit = 32768, Dropped = 0 },
			Tree = Apps.ReconstructorEvidence.Create(),
			Running = false,
			Stats = {},
			ProbePending = false,
		}
		local cache = setmetatable({}, { __mode = "k" })
		local generation, destroyed, logConnection = 0, false, nil
		local rescanRequested = false
		local function changed(message)
			if not destroyed and onChange then
				onChange(message)
			end
		end
		local function emit(path, evidence)
			if destroyed then
				return
			end
			if evidence.Class and (not Session.Classes or not Session.Classes[evidence.Class]) then
				evidence.Class = nil
			end
			local node = self.Tree:Add(path, evidence)
			if
				node
				and Apps.ModuleReconstruction
				and Apps.ModuleReconstruction.Merge(node, evidence.Member, self.ModuleBudget)
			then
				self.Tree.Revision += 1
			end
		end
		local reader = Apps.ScriptEvidenceReader
			and Apps.ScriptEvidenceReader.Create({
				Paths = Apps.BytecodePaths and function(obj, bytes, checkpoint)
					local ok, label = pcall(function()
						return obj:GetFullName()
					end)
					return Apps.BytecodePaths.Analyze(
						bytes,
						(ok and label or obj.Name) .. " (bytecode)",
						emit,
						checkpoint
					)
				end,
				Literal = function(obj, text)
					local ok, label = pcall(function()
						return obj:GetFullName()
					end)
					Apps.ServerReferenceAnalysis.Log(
						text,
						(ok and label or obj.Name) .. " (bytecode literal, unverified)",
						emit
					)
				end,
			})
		function self:Import(text, label)
			Apps.ServerReferenceAnalysis.Source(text, label or "Pasted source", emit)
			Apps.ServerReferenceAnalysis.Log(text, label or "Pasted log", emit)
			changed("Imported text; inferred entries are not live server objects.")
		end
		function self:Listen()
			if logConnection then
				return
			end
			local ok, history = pcall(function()
				return service.LogService:GetLogHistory()
			end)
			if ok and type(history) == "table" then
				for i = math.max(1, #history - 499), #history do
					local item = history[i]
					Apps.ServerReferenceAnalysis.Log(item.message, "Client log", emit)
				end
			end
			local success, connection = pcall(function()
				return service.LogService.MessageOut:Connect(function(message, kind)
					local revision = self.Tree.Revision
					Apps.ServerReferenceAnalysis.Log(message, "Client log", emit)
					if revision ~= self.Tree.Revision then
						changed("New path evidence in client log.")
					end
				end)
			end)
			if success then
				logConnection = connection
			end
		end
		function self:Cancel()
			generation += 1
			rescanRequested = false
			self.AutoPaused = true
			self.Running = false
			changed("Scan stopped. Existing evidence retained.")
		end
		function self:RequestScan()
			if destroyed or self.AutoPaused then
				return false
			end
			if self.Running then
				rescanRequested = true
				return false
			end
			return self:Scan()
		end
		function self:Scan(options)
			if self.Running or destroyed then
				return false
			end
			self.AutoPaused = false
			local deep = options and options.Deep == true
			local scanStarted = os.clock()
			generation += 1
			local ticket = generation
			self.Running = true
			self.Stats = {
				Mode = deep and "Deep" or "Budgeted",
				Scanned = 0,
				Unavailable = 0,
				TimedOut = 0,
				Oversize = 0,
				Discovered = 0,
				Cached = 0,
				Filtered = 0,
				EngineFiltered = 0,
				EngineRootsSkipped = 0,
				Processed = 0,
				Deferred = 0,
			}
			local stats = self.Stats
			stats.DataValues = 0
			stats.DeferredReasons = {}
			stats.Phase = "Starting"
			self.Worker = scheduler.spawn(function()
				local success, problem = xpcall(function()
					if reader then
						reader:BeginPass()
					end
					stats.Phase = "Log history"
					self:Listen()
					stats.Phase = "Discovery"
					local objects, seen = {}, {}
					local engineRoots = {
						CorePackages = true,
						CoreGui = true,
						RobloxReplicatedStorage = true,
						RobloxPluginGuiService = true,
					}
					local discoveryDeadline = os.clock() + scanSliceSeconds
					local collected = 0
					local function add(items)
						for _, obj in pairs(items) do
							collected += 1
							if collected % 250 == 0 then
								task.wait()
								if ticket ~= generation or destroyed then
									return
								end
							end
							local ok, isScript = pcall(function()
								return obj:IsA("LuaSourceContainer")
							end)
							if ok and isScript and not seen[obj] then
								seen[obj] = true
								local success, path = pcall(function()
									return obj:GetFullName()
								end)
								local root = success and path:match("^[^%.]+")
								if engineRoots[root] then
									stats.EngineFiltered += 1
								else
									objects[#objects + 1] = obj
								end
							end
						end
					end
					local known = Apps.Explorer
						and Apps.Explorer.GetInferenceNodes
						and Apps.Explorer.GetInferenceNodes()
					local candidates = Apps.Explorer
							and Apps.Explorer.GetInferenceCandidates
							and Apps.Explorer.GetInferenceCandidates()
						or known
					local ok, roots
					if known then
						for obj, node in pairs(candidates) do
							stats.DiscoveryVisited = (stats.DiscoveryVisited or 0) + 1
							if os.clock() >= discoveryDeadline then
								task.wait()
								discoveryDeadline = os.clock() + scanSliceSeconds
								if ticket ~= generation or destroyed then
									return
								end
							end
							if not node.Inferred and not node.Del then
								local class = node.Class or obj.ClassName
								if class == "StringValue" then
									local dataRoot = node
									local depth = 0
									while dataRoot.Parent and dataRoot.Parent ~= known[world] and depth < 64 do
										dataRoot = dataRoot.Parent
										depth += 1
									end
									local eligible = dataRoot.Parent == known[world]
										and not engineRoots[dataRoot.Obj.Name]
									local success, text = pcall(function()
										return obj.Value
									end)
									if
										eligible
										and success
										and type(text) == "string"
										and #text <= 65536
										and (
											text:find("ServerStorage", 1, true)
											or text:find("ServerScriptService", 1, true)
										)
									then
										local labelOk, label = pcall(function()
											return obj:GetFullName()
										end)
										Apps.ServerReferenceAnalysis.Log(
											text,
											(labelOk and label or obj.Name) .. " (replicated string, unverified)",
											emit
										)
										stats.DataValues += 1
									end
								end
								if class == "ModuleScript" or class == "LocalScript" or class == "Script" then
									local root = node
									local depth = 0
									while root.Parent and root.Parent ~= known[world] and depth < 64 do
										root = root.Parent
										depth += 1
									end
									if root.Parent == known[world] and not engineRoots[root.Obj.Name] then
										seen[obj] = true
										objects[#objects + 1] = obj
									end
								end
							end
						end
					else
						ok, roots = pcall(function()
							return world:GetChildren()
						end)
					end
					if not known and ok and type(roots) == "table" then
						for _, root in ipairs(roots) do
							if ticket ~= generation or destroyed then
								return
							end
							if engineRoots[root.Name] then
								stats.EngineRootsSkipped += 1
							else
								add({ root })
								local success, items = pcall(function()
									return root:GetDescendants()
								end)
								if success then
									add(items)
								end
							end
						end
					elseif not known then
						local success, items = pcall(function()
							return world:GetDescendants()
						end)
						if success then
							add(items)
						end
					end
					if deep and options.IncludeDetached and type(env.getloadedmodules) == "function" then
						local success, modules = pcall(env.getloadedmodules)
						if success and type(modules) == "table" then
							add(modules)
						end
					end
					stats.Phase = "Ordering"
					local labels = {}
					for _, obj in ipairs(objects) do
						local success, label = pcall(function()
							return obj:GetFullName()
						end)
						labels[obj] = success and label or obj.Name
						if os.clock() >= discoveryDeadline then
							task.wait()
							discoveryDeadline = os.clock() + scanSliceSeconds
							if ticket ~= generation or destroyed then
								return
							end
						end
					end
					table.sort(objects, function(a, b)
						return labels[a] < labels[b]
					end)
					stats.Discovered = #objects
					stats.Phase = "Reading scripts"
					changed(
						("Scanning %d game scripts; %d engine containers skipped."):format(
							#objects,
							stats.EngineRootsSkipped
						)
					)
					local lastYield = os.clock()
					stats.SliceSeconds = scanSliceSeconds
					stats.CooperativeYields = 0
					stats.YieldSeconds = 0
					local function checkpoint()
						if destroyed or ticket ~= generation then
							return false
						end
						if
							Main.Performance and not Main.Performance.Available()
							or not Main.Performance and os.clock() - lastYield > scanSliceSeconds
						then
							local started = os.clock()
							task.wait()
							lastYield = os.clock()
							stats.CooperativeYields += 1
							stats.YieldSeconds += lastYield - started
						end
						return not destroyed and ticket == generation
					end
					for scriptIndex, obj in ipairs(objects) do
						if not checkpoint() then
							return
						end
						stats.Processed = scriptIndex
						if scriptIndex % 100 == 0 then
							changed(
								("Scanning %d / %d game scripts (%d cached, %d filtered)..."):format(
									scriptIndex,
									#objects,
									stats.Cached,
									stats.Filtered
								)
							)
						end
						local source
						if not deep and reader then
							local outcome = reader:Read(obj, checkpoint)
							stats.Reader = reader.Stats
							stats.BytecodePaused = reader.BytecodePaused
							stats.DecompilePaused = reader.DecompilePaused
							if outcome.Status == "Cancelled" then
								return
							end
							if outcome.Status == "Cached" then
								stats.Cached += 1
								continue
							end
							if outcome.Status == "Filtered" then
								stats.Filtered += 1
								continue
							end
							if outcome.Status == "Deferred" then
								stats.Deferred += 1
								local reason = outcome.Reason or "Reader limit"
								stats.DeferredReasons[reason] = (stats.DeferredReasons[reason] or 0) + 1
								continue
							end
							source = outcome.Source
						else
							local readable
							readable, source = pcall(function()
								return obj.Source
							end)
							local previous = cache[obj]
							if
								readable
								and type(source) == "string"
								and source ~= ""
								and previous
								and previous.Source == source
							then
								stats.Cached += 1
								continue
							end
							if not readable or type(source) ~= "string" or source == "" then
								source = nil
								if not deep then
									stats.Unavailable += 1
									continue
								end
								local bytecode
								if type(env.getscriptbytecode) == "function" then
									local success, result = pcall(env.getscriptbytecode, obj)
									if success and type(result) == "string" then
										bytecode = result
									end
								end
								if bytecode then
									if previous and previous.Bytecode == bytecode then
										stats.Cached += 1
										continue
									end
									if
										not (
											Apps.BytecodeStrings and Apps.BytecodeStrings.HasServerHint(bytecode)
											or bytecode:find("ServerStorage", 1, true)
											or bytecode:find("ServerScriptService", 1, true)
										)
									then
										cache[obj] = { Bytecode = bytecode }
										stats.Filtered += 1
										continue
									end
								end
								local viable = false
								if type(env.isViableDecompileScript) == "function" then
									local success, result = pcall(env.isViableDecompileScript, obj)
									viable = success and result
								end
								if viable and type(env.decompile) == "function" then
									local done, result = false, nil
									local thread = task.spawn(function()
										local success, text = pcall(env.decompile, obj)
										if success then
											result = text
										end
										done = true
									end)
									local started = os.clock()
									while
										not done
										and os.clock() - started < 15
										and ticket == generation
										and not destroyed
									do
										task.wait(0.05)
									end
									if not done then
										pcall(task.cancel, thread)
										stats.TimedOut += 1
										if ticket == generation and not destroyed then
											self.Running = false
											changed("Decompiler timed out; scan stopped. Partial evidence retained.")
										end
										return
									end
									source = result
								end
							end
						end
						if ticket ~= generation or destroyed then
							return
						end
						if type(source) == "string" then
							if #source > 1024 * 1024 then
								stats.Oversize += 1
							else
								local labelOk, label = pcall(function()
									return obj:GetFullName()
								end)
								local complete = Apps.ServerReferenceAnalysis.Source(
									source,
									labelOk and label or obj.Name,
									emit,
									checkpoint,
									200000
								)
								if complete then
									if reader and not deep then
										reader:Commit(obj, source)
									end
									cache[obj] = cache[obj] or {}
									cache[obj].Source = source
									stats.Scanned += 1
								else
									stats.Deferred += 1
									stats.DeferredReasons["Analysis interrupted or token limit"] = (
										stats.DeferredReasons["Analysis interrupted or token limit"] or 0
									) + 1
								end
							end
						else
							stats.Unavailable += 1
						end
						if (stats.Scanned + stats.Unavailable) % 10 == 0 then
							changed(
								"Scanning " .. (stats.Scanned + stats.Unavailable) .. " / " .. #objects .. " scripts..."
							)
						end
					end
					if
						not deep
						and not self.RetainedCollected
						and Apps.RetainedFunctionEvidence
						and ticket == generation
						and not destroyed
					then
						self.RetainedCollected = true
						stats.Phase = "Retained functions"
						changed("Inspecting retained game functions...")
						stats.Retained = Apps.RetainedFunctionEvidence.Collect(emit, checkpoint)
						self.RetainedStats = stats.Retained
					elseif self.RetainedStats then
						stats.Retained = self.RetainedStats
					end
					if ticket == generation and not destroyed then
						self.Running = false
						stats.Seconds = os.clock() - scanStarted
						stats.Phase = "Complete"
						stats.Reconstruction = {
							Members = self.ModuleBudget.Count,
							Dropped = self.ModuleBudget.Dropped,
							PerModuleLimit = 2048,
							SessionLimit = self.ModuleBudget.Limit,
						}
						if reader then
							stats.Reader = table.clone(reader.Stats)
							if reader.Stats.PathRejections then
								stats.Reader.PathRejections = table.clone(reader.Stats.PathRejections)
							end
						end
						changed(
							("Scan complete: %d analyzed, %d cached, %d filtered, %d unavailable, %d deferred; %d inferred nodes."):format(
								stats.Scanned,
								stats.Cached,
								stats.Filtered,
								stats.Unavailable,
								stats.Deferred,
								self.Tree.Count - 2
							)
						)
						if
							rescanRequested
							or (stats.DeferredReasons["Pass decompile limit"] or 0) > 0
							or ((stats.DeferredReasons["Native circuit paused"] or 0) > 0 and reader and not reader.SeverePause)
							or (
								(stats.DeferredReasons["Bytecode circuit cooling down"] or 0) > 0
								and reader
								and not reader.SevereBytecodePause
							)
						then
							rescanRequested = false
							scheduler.delay(
								reader and (reader.DecompilePaused or reader.BytecodePaused) and 6 or 3,
								function()
									if not destroyed and ticket == generation then
										self:RequestScan()
									end
								end
							)
						end
					end
				end, debug.traceback)
				if not success and ticket == generation and not destroyed then
					self.Running = false
					stats.Error = tostring(problem)
					stats.FailedPhase = stats.Phase
					stats.Phase = "Failed"
					stats.Seconds = os.clock() - scanStarted
					changed("Reconstructor scan failed: " .. tostring(problem):sub(1, 350))
				end
			end)
			return true
		end
		function self:Probe(remote, arguments, argumentCount)
			if destroyed then
				return false, "Session closed"
			end
			if self.ProbePending then
				return false, "A call is still pending. A timeout does not cancel server execution."
			end
			local ok, valid = pcall(function()
				return remote:IsA("RemoteFunction") and remote:IsDescendantOf(world)
			end)
			if not ok or not valid then
				return false, "Select a live RemoteFunction in Explorer first."
			end
			if type(arguments) ~= "table" then
				return false, "Use a JSON array with at most 16 arguments."
			end
			argumentCount = argumentCount or #arguments
			if type(argumentCount) ~= "number" or argumentCount < 0 or argumentCount > 16 or argumentCount % 1 ~= 0 then
				return false, "Use a JSON array with at most 16 arguments."
			end
			for k in pairs(arguments) do
				if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > argumentCount then
					return false, "Arguments must be a JSON array."
				end
			end
			self.ProbePending = true
			local label = remote:GetFullName()
			local finished = false
			scheduler.delay(10, function()
				if not destroyed and not finished then
					changed("Remote timed out; still pending. No further calls until it returns.")
				end
			end)
			scheduler.spawn(function()
				local success, result = pcall(function()
					return remote:InvokeServer(table.unpack(arguments, 1, argumentCount))
				end)
				finished = true
				self.ProbePending = false
				if destroyed then
					return
				end
				local visited, budget = {}, 64
				local function collect(value, depth)
					if budget <= 0 or depth > 3 then
						return
					end
					budget -= 1
					if type(value) == "string" then
						Apps.ServerReferenceAnalysis.Log(
							value:sub(1, 65536),
							label .. (success and " response" or " error"),
							emit
						)
					elseif type(value) == "table" and not visited[value] then
						visited[value] = true
						for _, child in pairs(value) do
							collect(child, depth + 1)
							if budget <= 0 then
								break
							end
						end
					end
				end
				collect(result, 0)
				changed(
					success and "Remote returned. Any path text was added as evidence."
						or ("Remote error: " .. tostring(result):sub(1, 350))
				)
			end)
			changed("Calling " .. label .. " once. This may change server state.")
			return true
		end
		function self:Destroy()
			if destroyed then
				return
			end
			destroyed = true
			generation += 1
			self.Running = false
			if logConnection then
				logConnection:Disconnect()
				logConnection = nil
			end
		end
		if Main.AddCleanup then
			Main.AddCleanup(function()
				self:Destroy()
			end)
		end
		return self
	end
	return Session
end
return { InitDeps = InitDeps, Main = CreateModule }
