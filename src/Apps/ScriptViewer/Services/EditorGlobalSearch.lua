--!strict

local Main, Apps, env
------------------------------ Module ------------------------------

local function CreateModule()
	local Search = { MaxResults = 20000, MaxSourceBytes = 2 * 1024 * 1024, MaxRetainedBytes = 32 * 1024 * 1024 }
	local queue, pending = {}, {}
	local retryAfter = setmetatable({}, { __mode = "k" })
	local hashOwners = setmetatable({}, { __mode = "v" })
	local workerRunning = false
	local workerEpoch = 0
	local function queueSource(object)
		if pending[object] then
			return
		end
		pending[object] = true
		queue[#queue + 1] = object
	end
	local function startWorker()
		if workerRunning or #queue == 0 then
			return
		end
		workerRunning = true
		local epoch = workerEpoch
		task.spawn(function()
			local index = 1
			while index <= #queue and Main.Alive ~= false and epoch == workerEpoch do
				local object = queue[index]
				local started = os.clock()
				local reader = Apps.ReferenceSource
				local cached = reader and reader.Peek(object)
				local hash
				if not cached and type(env.getscripthash) == "function" then
					local ok, value = pcall(env.getscripthash, object)
					if ok and type(value) == "string" and #value >= 16 then
						hash = value
					end
				end
				if epoch ~= workerEpoch then
					break
				end
				if not cached and hash and reader and hashOwners[hash] then
					cached = reader.Peek(hashOwners[hash])
					if cached then
						reader.Store(object, cached.Source, cached.SourceKind)
					end
				end
				if not cached then
					local ok, source = pcall(env.decompile, object)
					if ok and type(source) == "string" and source ~= "" and reader then
						reader.Store(object, source, "Cached decompiled source")
						cached = reader.Peek(object)
					end
				end
				if cached and hash then
					hashOwners[hash] = object
				end
				retryAfter[object] = not cached and os.clock() + 60 or nil
				if epoch ~= workerEpoch then
					break
				end
				pending[object] = nil
				index += 1
				task.wait(math.clamp((os.clock() - started) * 3, 0, 0.5))
			end
			if epoch == workerEpoch then
				table.clear(queue)
				table.clear(pending)
			end
			workerRunning = false
		end)
	end
	local function sourceOf(object)
		return object.Source
	end
	local function pathOf(object)
		local ok, path = pcall(object.GetFullName, object)
		return ok and path or object.Name
	end
	local function continuation(source, position)
		local byte = source:byte(position)
		return byte ~= nil and byte >= 128 and byte < 192
	end
	function Search.Create(adapter)
		adapter = adapter or {}
		local session = { State = { Groups = {}, MatchCount = 0, Scanned = 0, Unavailable = 0, Searching = false } }
		local runtimeCatalog = {}
		local runtimeCoverage = 0
		local catalog, failedReads = {}, setmetatable({}, { __mode = "k" })
		local protectedSource = setmetatable({}, { __mode = "k" })
		local stringIds, strings, folded = {}, {}, {}
		local catalogCount, catalogBytes = 0, 0
		local function retain(object, literals, destination)
			local cost = #literals * 4 + 64
			local unique = {}
			for _, literal in ipairs(literals) do
				if not stringIds[literal] and not unique[literal] then
					unique[literal] = true
					cost += #literal * 2 + 80
				end
			end
			if catalogCount >= 40000 or catalogBytes + cost > 64 * 1024 * 1024 then
				return nil
			end
			local ids = buffer.create(#literals * 4)
			for index, literal in ipairs(literals) do
				local id = stringIds[literal]
				if not id then
					id = #strings + 1
					stringIds[literal] = id
					strings[id] = literal
					folded[id] = literal:lower()
				end
				buffer.writeu32(ids, (index - 1) * 4, id)
			end
			destination[object] = ids
			catalogCount += 1
			catalogBytes += cost
			return ids
		end
		local generation, destroyed = 0, false
		local clock = adapter.Clock or os.clock
		local wait = adapter.Wait or task.wait
		local spawn = adapter.Spawn or task.spawn
		local function notify(state)
			if adapter.OnChanged and session.State == state and not destroyed then
				adapter.OnChanged(state)
			end
		end
		local function editorSource(source)
			if adapter.NormalizeSource and type(source) == "string" then
				return adapter.NormalizeSource(source)
			end
			return source
		end
		function session:Cancel()
			generation += 1
			if self.State.Searching then
				self.State.Cancelled = true
				if self.State.Options and self.State.Options.IncludeDecompiled then
					workerEpoch += 1
					table.clear(queue)
					table.clear(pending)
				end
			end
			self.State.Searching = false
			notify(self.State)
		end
		local function documents()
			local list = adapter.GetDocuments and adapter.GetDocuments() or {}
			local byObject = {}
			for _, doc in ipairs(list) do
				if doc.script then
					byObject[doc.script] = doc
				elseif typeof(doc.id) == "Instance" then
					byObject[doc.id] = doc
				end
			end
			return list, byObject
		end
		local function documentText(doc)
			if adapter.GetActiveText then
				local text = adapter.GetActiveText(doc)
				if type(text) == "string" then
					return text
				end
			end
			return doc.text
		end
		local function collectRuntime(registry, coverage, state, checkpoint)
			if
				runtimeCoverage >= coverage
				or type(env.filtergc) ~= "function"
				or type(env.getconstants) ~= "function"
			then
				return
			end
			local start = clock()
			local ok, functions = pcall(env.filtergc, "function", { IgnoreExecutor = true }, false)
			state.RuntimeDiscoveryMs = (clock() - start) * 1000
			wait()
			if not checkpoint() then
				return
			end
			if not ok or type(functions) ~= "table" or state.RuntimeDiscoveryMs >= 50 then
				state.RuntimeLimited = true
				runtimeCoverage = coverage
				return
			end
			local owners, byEnvironment = {}, {}
			local retainedConstants = 0
			for index, fn in ipairs(functions) do
				if index > 50000 then
					state.RuntimeLimited = true
					break
				end
				if not checkpoint() then
					return
				end
				if type(fn) ~= "function" then
					continue
				end
				local readable, environment = pcall(getfenv, fn)
				if not readable or type(environment) ~= "table" then
					continue
				end
				local object = byEnvironment[environment]
				if object == nil then
					object = rawget(environment, "script")
					if not object then
						local mt = getmetatable(environment)
						local inherited = type(mt) == "table" and rawget(mt, "__index")
						if type(inherited) == "table" then
							object = rawget(inherited, "script")
						end
					end
					object = object and registry[object] and object or false
					byEnvironment[environment] = object
				end
				if not object or runtimeCatalog[object] then
					continue
				end
				local began = clock()
				local valid, constants = pcall(env.getconstants, fn)
				local ms = (clock() - began) * 1000
				state.MaxConstantReadMs = math.max(state.MaxConstantReadMs or 0, ms)
				if valid and type(constants) == "table" then
					local set = owners[object]
					if not set then
						set = {}
						owners[object] = set
					end
					for _, value in pairs(constants) do
						if type(value) == "string" and #value <= 1024 * 1024 and not set[value] then
							set[value] = true
							retainedConstants += 1
							if retainedConstants >= 400000 then
								state.RuntimeLimited = true
								break
							end
						end
					end
					if retainedConstants >= 400000 then
						break
					end
				end
				if ms >= 20 then
					state.RuntimeLimited = true
					break
				end
			end
			local count = 0
			for object, set in pairs(owners) do
				if not checkpoint() then
					return
				end
				if not runtimeCatalog[object] then
					local values = {}
					for value in pairs(set) do
						values[#values + 1] = value
					end
					if retain(object, values, runtimeCatalog) then
						count += 1
					else
						state.CatalogFull = true
					end
				end
			end
			runtimeCoverage = coverage
			state.RuntimeIndexed = count
		end
		function session:Start(query, options)
			self:Cancel()
			generation += 1
			local ticket = generation
			options = table.clone(options or {})
			local state = {
				Groups = {},
				MatchCount = 0,
				Scanned = 0,
				Unavailable = 0,
				Searching = true,
				Query = query,
				Options = options,
				RetainedBytes = 0,
			}
			self.State = state
			notify(state)
			if type(query) ~= "string" or query == "" then
				state.Searching = false
				notify(state)
				return
			end
			spawn(function()
				local ok, problem = pcall(function()
					local deadline, lastPublish = clock() + 0.003, clock()
					local function checkpoint()
						if destroyed or generation ~= ticket or Main.Alive == false then
							return false
						end
						local now = clock()
						if now >= deadline then
							if now - lastPublish >= 0.1 then
								notify(state)
								lastPublish = now
							end
							wait()
							deadline = clock() + 0.003
						end
						return not destroyed and generation == ticket and Main.Alive ~= false
					end
					local validation = Apps.EditorFindModel.Search(
						"",
						query,
						{ Regex = options.Regex, MatchCase = options.MatchCase, WorkLimit = 100000 }
					)
					if validation.Error then
						state.Error = validation.Error
						return
					end
					local docs, byObject = documents()
					local selected = {}
					if options.Scope == "Selection" and Apps.Explorer.Selection then
						for _, node in ipairs(Apps.Explorer.Selection.List) do
							selected[node.Obj] = true
						end
					end
					local function inScope(object)
						if options.Scope ~= "Selection" then
							return true
						end
						local current = object
						while current do
							if selected[current] then
								return true
							end
							current = current.Parent
						end
						return false
					end
					local allScripts = Apps.Explorer.GetScriptCandidates and Apps.Explorer.GetScriptCandidates()
						or Apps.Explorer.GetNodes()
					local gameScripts = (options.Scope == "Game" or options.ExcludePlatform)
						and Apps.Explorer.GetInferenceCandidates
						and Apps.Explorer.GetInferenceCandidates()
					local scopeRegistry = gameScripts or allScripts
					local candidates, seen = {}, {}
					for _, doc in ipairs(docs) do
						local object = doc.script or (typeof(doc.id) == "Instance" and doc.id or nil)
						if
							(not options.ExcludePlatform or not object or object.ClassName ~= "CoreScript")
							and (options.Scope ~= "Selection" or object and inScope(object))
							and (not gameScripts or not object or not allScripts[object] or gameScripts[object])
						then
							candidates[#candidates + 1] = { Object = object, Document = doc }
							if object then
								seen[object] = true
							end
						end
					end
					if options.Scope ~= "Open" then
						local nodes = table.clone(scopeRegistry)
						local visited = 0
						for object, node in pairs(nodes) do
							if not seen[object] and not node.Del then
								local class = node.Class or object.ClassName
								if
									(class == "Script" or class == "LocalScript" or class == "ModuleScript")
									and inScope(object)
								then
									candidates[#candidates + 1] = { Object = object, Document = byObject[object] }
								end
							end
							visited += 1
							if visited % 256 == 0 and not checkpoint() then
								return
							end
						end
					end
					local where = (options.PathFilter or ""):lower()
					state.TotalScripts = #candidates
					local reader = options.IncludeCompiled and Apps.ReferenceSource
					local pass = { ParseCheckpoint = checkpoint }
					local runtimeRequested = options.IncludeRuntime
					local readLimit = 8
					local readsThisFrame, moderateStalls = 0, 0
					local function onNativeRead(duration)
						readsThisFrame += 1
						state.NativeReads = (state.NativeReads or 0) + 1
						state.MaxReadMs = math.max(state.MaxReadMs or 0, duration * 1000)
						if duration >= 0.1 then
							state.BytecodePaused = true
						elseif duration >= 0.02 then
							moderateStalls += 1
							if moderateStalls >= 3 then
								state.BytecodePaused = true
							end
						end
						if duration >= 0.004 then
							readLimit = math.max(1, math.floor(readLimit / 2))
						end
					end
					local literalMemo, literalMemoCount = {}, 0
					local literalNeedle = options.MatchCase and query or query:lower()
					for _, item in ipairs(candidates) do
						if not checkpoint() then
							return
						end
						local object, doc = item.Object, item.Document
						local path
						if where ~= "" then
							path = object and pathOf(object) or doc.title
							if not path:lower():find(where, 1, true) then
								continue
							end
						end
						local source, kind
						if doc then
							source = documentText(doc)
							kind = "Buffer"
						elseif not item.ReadCompiled then
							local readable, text
							if not protectedSource[object] then
								readable, text = pcall(sourceOf, object)
								if not readable then
									protectedSource[object] = true
								end
							end
							if readable and type(text) == "string" and text ~= "" then
								source = text
								kind = "Readable"
							else
								local cached = Apps.ReferenceSource and Apps.ReferenceSource.Peek(object)
								if cached then
									source = cached.Source
									kind = "Decompiler"
								end
								if not source and options.IncludeDecompiled and type(env.decompile) == "function" then
									if not item.NeedsDecompile and (retryAfter[object] or 0) <= os.clock() then
										item.NeedsDecompile = true
										candidates[#candidates + 1] = item
										queueSource(object)
										state.Queued = (state.Queued or 0) + 1
										continue
									end
									if item.NeedsDecompile then
										while pending[object] do
											startWorker()
											if not pending[object] then
												break
											end
											wait()
											if not checkpoint() then
												return
											end
										end
										local latest = Apps.ReferenceSource and Apps.ReferenceSource.Peek(object)
										if latest then
											source = latest.Source
											kind = "Decompiler"
										end
									end
								end
								if not source and readable and text == "" then
									source = ""
									kind = "Readable"
								end
							end
						end
						if item.ReadCompiled then
							local cached = reader.Peek(object)
							if cached then
								source = cached.Source
								kind = "Decompiler"
							end
						end
						if reader and object and not doc and (not source or source == "") then
							if not item.ReadCompiled and (runtimeRequested or not options.CachedCompiledOnly) then
								item.ReadCompiled = true
								candidates[#candidates + 1] = item
								continue
							end
							if runtimeRequested then
								runtimeRequested = false
								notify(state)
								collectRuntime(scopeRegistry, gameScripts and 1 or 2, state, checkpoint)
								if not checkpoint() then
									return
								end
							end
							local ids = catalog[object]
							local runtime = false
							local evidence
							if not ids then
								evidence = reader.PeekCompiled(object)
								if not evidence then
									local failed = failedReads[object]
									if failed and failed.Until > clock() then
										evidence = { Unavailable = failed.Reason }
									elseif options.CachedCompiledOnly or state.BytecodePaused then
										ids = runtimeCatalog[object]
										runtime = ids ~= nil
										if not ids then
											state.Pending = (state.Pending or 0) + 1
											state.Scanned += 1
											continue
										end
									else
										if readsThisFrame >= readLimit then
											wait()
											deadline = clock() + 0.003
											readsThisFrame = 0
											if not checkpoint() then
												return
											end
										end
										local before = state.NativeReads
										evidence = reader.Read(object, checkpoint, onNativeRead, pass)
										if
											evidence.Unavailable
											and not evidence.Cancelled
											and evidence.Unavailable ~= "Cancelled"
										then
											failedReads[object] =
												{ Until = clock() + 60, Reason = evidence.Unavailable }
										end
										if
											state.NativeReads ~= before
											and (
												state.BytecodePaused
												or readsThisFrame >= readLimit
												or clock() >= deadline
											)
										then
											readsThisFrame = 0
											wait(
												state.BytecodePaused and 0
													or math.min(0.2, (state.MaxReadMs or 0) / 1000)
											)
											deadline = clock() + 0.003
										end
									end
								end
								if evidence and evidence.Literals then
									ids = retain(object, evidence.Literals, catalog)
									if not ids then
										state.CatalogFull = true
									end
								end
								if not ids and evidence and evidence.Unavailable and runtimeCatalog[object] then
									ids = runtimeCatalog[object]
									runtime = true
									evidence = nil
								end
								if not checkpoint() then
									return
								end
							end
							evidence = evidence or {}
							if evidence.Cancelled then
								return
							end
							if evidence.Source then
								source = evidence.Source
								kind = evidence.SourceKind
							elseif ids or evidence.Literals then
								if runtime then
									state.RuntimeChecked = (state.RuntimeChecked or 0) + 1
								else
									state.CompiledChecked = (state.CompiledChecked or 0) + 1
								end
								local count = ids and buffer.len(ids) / 4 or #evidence.Literals
								for index = 1, count do
									local id = ids and buffer.readu32(ids, (index - 1) * 4)
									local literal = id and strings[id] or evidence.Literals[index]
									local key = id or literal
									if index % 64 == 0 and not checkpoint() then
										return
									end
									local match = literalMemo[key]
									if match == nil then
										match = false
										local first, last
										if not options.Regex then
											first, last = (
												options.MatchCase and literal or (id and folded[id] or literal:lower())
											):find(literalNeedle, 1, true)
										end
										if
											first
											and not options.WholeWord
											and not continuation(literal, first)
											and not continuation(literal, last + 1)
										then
											match = { Start = first, Finish = last + 1 }
										elseif options.Regex or first then
											local hit = Apps.EditorFindModel.Search(literal, query, {
												Regex = options.Regex,
												MatchCase = options.MatchCase,
												WholeWord = options.WholeWord,
												MaxMatches = 1,
												WorkLimit = 100000,
												Checkpoint = checkpoint,
											})
											if hit.Cancelled then
												return
											end
											match = hit.Matches[1] or false
										end
										if literalMemoCount < 65536 then
											literalMemo[key] = match
											literalMemoCount += 1
										end
									end
									if match then
										match = table.clone(match)
										local first = math.max(1, match.Start - 80)
										while continuation(literal, first) do
											first += 1
										end
										local last = math.min(#literal + 1, first + 240)
										while continuation(literal, last) do
											last -= 1
										end
										match.Text = literal:sub(first, last - 1):gsub("[%c]", " ")
										match.SnippetColumn = match.Start - first + 1
										state.Groups[#state.Groups + 1] = {
											Object = object,
											Name = object.Name,
											Path = path or pathOf(object),
											Compiled = true,
											Runtime = runtime,
											Matches = { match },
										}
										state.MatchCount += 1
										if runtime then
											state.RuntimeMatches = (state.RuntimeMatches or 0) + 1
										else
											state.CompiledMatches = (state.CompiledMatches or 0) + 1
										end
										break
									end
								end
								state.Scanned += 1
								if state.MatchCount >= Search.MaxResults then
									state.Truncated = true
									break
								end
								continue
							elseif evidence.Unavailable then
								source = nil
								if evidence.Unavailable == "Bytecode reads paused after a slow call" then
									state.BytecodePaused = true
									state.Pending = (state.Pending or 0) + 1
									state.Scanned += 1
									continue
								end
							end
						end
						if item.NeedsDecompile then
							state.Queued -= 1
						end
						state.Scanned += 1
						if type(source) ~= "string" or #source > Search.MaxSourceBytes then
							state.Unavailable += 1
							continue
						end
						source = editorSource(source)
						if #source > Search.MaxSourceBytes then
							state.Unavailable += 1
							continue
						end
						state.SourceChecked = (state.SourceChecked or 0) + 1
						local remaining = Search.MaxResults - state.MatchCount
						local result = Apps.EditorFindModel.Search(source, query, {
							Regex = options.Regex,
							MatchCase = options.MatchCase,
							WholeWord = options.WholeWord,
							WorkLimit = 1000000,
							MaxMatches = remaining,
							Checkpoint = checkpoint,
						})
						if result.Cancelled then
							return
						end
						if result.Error then
							state.Error = result.Error
							return
						end
						if #result.Matches > 0 then
							if state.RetainedBytes + #source > Search.MaxRetainedBytes then
								state.Truncated = true
								state.Limit = "Source memory limit"
								break
							end
							local group = {
								Object = object,
								Document = doc,
								Id = doc or object,
								Name = doc and doc.title or object.Name,
								Path = path or (object and pathOf(object) or doc.title),
								Source = source,
								SourceKind = kind,
								Matches = result.Matches,
							}
							local line, start = 1, 1
							local nextLine = source:find("\n", 1, true) or #source + 1
							for matchIndex, match in ipairs(group.Matches) do
								while nextLine < match.Start do
									line += 1
									start = nextLine + 1
									nextLine = source:find("\n", start, true) or #source + 1
									if line % 256 == 0 and not checkpoint() then
										return
									end
								end
								match.Line = line
								match.Column = match.Start - start + 1
								local clipStart = math.max(start, match.Start - 100)
								while continuation(source, clipStart) do
									clipStart += 1
								end
								local clipFinish = math.min(nextLine, clipStart + 240)
								while clipFinish > clipStart and continuation(source, clipFinish) do
									clipFinish -= 1
								end
								match.Text = source:sub(clipStart, clipFinish - 1)
								match.SnippetColumn = match.Start - clipStart + 1
								if matchIndex % 256 == 0 and not checkpoint() then
									return
								end
							end
							state.Groups[#state.Groups + 1] = group
							state.MatchCount += #group.Matches
							state.RetainedBytes += #source
						end
						if result.Truncated then
							state.Truncated = true
							state.Limit = "20,000 results"
							break
						end
					end
				end)
				if destroyed or ticket ~= generation then
					return
				end
				state.Searching = false
				if not ok then
					state.Error = tostring(problem)
				end
				state.CatalogScripts = catalogCount
				table.sort(state.Groups, function(a, b)
					return tostring(a.Path) < tostring(b.Path)
				end)
				notify(state)
			end)
		end
		local function current(group)
			if adapter.ReadCurrent then
				local value = adapter.ReadCurrent(group)
				if type(value) == "string" then
					return value
				end
			end
			if group.Document then
				return documentText(group.Document)
			end
			if group.SourceKind == "Readable" then
				local ok, value = pcall(sourceOf, group.Object)
				return ok and editorSource(value) or nil
			end
			local cached = Apps.ReferenceSource and Apps.ReferenceSource.Peek(group.Object)
			return cached and editorSource(cached.Source) or group.Source
		end
		local function replace(groups, replacement, single)
			if destroyed then
				return { Error = "The search panel is closed." }
			end
			if session.State.Searching then
				return { Error = "Wait for the search to finish." }
			end
			if not single and (session.State.Truncated or session.State.Cancelled or session.State.Error) then
				return {
					Error = "Search results are incomplete. Search again or narrow the scope before replacing all.",
				}
			end
			if not adapter.Apply then
				return { Error = "Editor replacement is unavailable." }
			end
			local activeGroups
			if groups ~= session.State.Groups then
				activeGroups = {}
				for _, group in ipairs(session.State.Groups) do
					activeGroups[group] = true
				end
			end
			local edits = {}
			local total = 0
			for _, group in ipairs(groups) do
				if (activeGroups and not activeGroups[group]) or (single and not table.find(group.Matches, single)) then
					return { Error = "Search results changed. Select a current result before replacing." }
				end
				if group.Compiled then
					if single then
						return { Error = "Open this script to verify the compiled match before replacing." }
					end
					continue
				end
				if group.Replaced or current(group) ~= group.Source then
					return { Error = "A script changed. Search again before replacing." }
				end
				local result = single and Apps.EditorFindModel.Replace(group.Source, single, replacement)
					or Apps.EditorFindModel.ReplaceAll(group.Source, group.Matches, replacement)
				if result.Error then
					return result
				end
				edits[#edits + 1] = { Group = group, Text = result.Text, Count = result.Count }
				total += result.Count
			end
			local applied = 0
			for _, edit in ipairs(edits) do
				local ok, value = pcall(adapter.Apply, edit.Group, edit.Text)
				if not ok or value == false then
					return {
						Error = not ok and tostring(value) or "The editor could not apply a replacement.",
						Count = applied,
						Partial = applied > 0,
					}
				end
				edit.Group.Replaced = true
				applied += edit.Count
			end
			return { Count = total, Scripts = #edits }
		end
		function session:Replace(group, match, replacement)
			if not group or not match then
				return { Error = "Select a search result before replacing." }
			end
			return replace({ group }, replacement, match)
		end
		function session:ReplaceAll(replacement, groups)
			return replace(groups or self.State.Groups, replacement)
		end
		function session:Destroy()
			self:Cancel()
			destroyed = true
			generation += 1
			table.clear(self.State.Groups)
			table.clear(catalog)
			table.clear(runtimeCatalog)
			table.clear(failedReads)
			table.clear(protectedSource)
			table.clear(stringIds)
			table.clear(strings)
			table.clear(folded)
		end
		if Main.AddCleanup then
			Main.AddCleanup(function()
				session:Destroy()
			end)
		end
		return session
	end
	return Search
end
return {
	InitDeps = function(d)
		Main, Apps, env = d.Main, d.Apps, d.env or {}
	end,

	Main = CreateModule,
}
