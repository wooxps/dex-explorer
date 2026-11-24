--!strict

------------------------------ Module ------------------------------

local function Main()
	local Extra = {}
	function Extra.Create(c)
		local Apps, service, env, registry, codec = c.Apps, c.service, c.env, c.Registry, c.Codec
		local result = { Commands = {} }
		local jobs, watches, cameras = {}, {}, {}
		local sequence = 0
		local dead = false
		local heartbeat
		local function add(name, grant, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = grant, Run = run }
		end
		local function integer(v, default, max)
			v = v or default
			assert(type(v) == "number" and v % 1 == 0 and v >= 1 and v <= max, "INVALID_ARGUMENT: integer out of range")
			return v
		end
		local function stringArg(v, max)
			assert(type(v) == "string" and #v > 0 and #v <= max, "INVALID_ARGUMENT: nonempty bounded string required")
			return v
		end
		local function object(args)
			return registry:Resolve(args.instanceId)
		end
		local function available(module)
			assert(Apps[module], "UNSUPPORTED: " .. module .. " is unavailable")
			return Apps[module]
		end
		local function identity(value)
			if value and registry:Allowed(value) then
				return registry:Describe(value)
			end
		end
		local function id(prefix)
			sequence += 1
			return prefix .. sequence
		end
		local function bounds(objects, space)
			for _, value in ipairs(objects) do
				assert(
					(value:IsA("BasePart") or value:IsA("Model")) and value:IsDescendantOf(service.Workspace),
					"INVALID_TARGET: Workspace part or model required"
				)
			end
			local cf, size, pivot = available("TransformSession").Bounds(objects, space or "World")
			assert(cf, "INVALID_TARGET: selection has no bounds")
			return cf, size, pivot
		end
		local function jobSummary(job)
			return {
				jobId = job.Id,
				status = job.Status,
				result = job.Result,
				error = job.Error,
				progress = job.Progress,
				duration = (job.Ended or os.clock()) - job.Started,
			}
		end
		local function startJob(run, cleanup)
			local count = 0
			for key, job in pairs(jobs) do
				if job.Status ~= "running" and os.clock() - job.Started > 120 then
					jobs[key] = nil
				else
					count += 1
				end
			end
			if count >= 8 then
				local oldestKey, oldest
				for key, job in pairs(jobs) do
					if job.Status ~= "running" and (not oldest or job.Started < oldest.Started) then
						oldestKey, oldest = key, job
					end
				end
				assert(oldestKey, "JOB_LIMIT: cancel an active analysis job first")
				jobs[oldestKey] = nil
			end
			local job = { Id = id("j"), Status = "running", Started = os.clock(), Progress = 0 }
			jobs[job.Id] = job
			function job.Cleanup()
				if cleanup then
					local callback = cleanup
					cleanup = nil
					pcall(callback, job.Status)
				end
			end
			job.Thread = task.spawn(function()
				local last = os.clock()
				local function check()
					if dead or job.Status ~= "running" then
						return false
					end
					if os.clock() - job.Started > 30 then
						job.Status = "failed"
						job.Error = "Analysis exceeded its cooperative time budget"
						job.Cleanup()
						return false
					end
					job.Progress += 1
					if os.clock() - last >= 0.002 then
						task.wait()
						last = os.clock()
					end
					return not dead and job.Status == "running"
				end
				local ok, value = pcall(run, check)
				if dead or job.Status ~= "running" then
					job.Cleanup()
					return
				end
				job.Ended = os.clock()
				if ok then
					job.Status = "completed"
					job.Result = value
				else
					job.Status = "failed"
					job.Error = tostring(value):sub(1, 1000)
				end
				job.Cleanup()
			end)
			return jobSummary(job)
		end
		add("get_job", "inspect", function(args)
			local job = jobs[args.jobId]
			assert(job, "JOB_UNAVAILABLE: unknown or expired job")
			return jobSummary(job)
		end)
		add("cancel_job", "inspect", function(args)
			local job = jobs[args.jobId]
			assert(job, "JOB_UNAVAILABLE: unknown or expired job")
			if job.Status == "running" then
				job.Status = "cancelled"
				job.Ended = os.clock()
				if task.cancel and job.Thread then
					pcall(task.cancel, job.Thread)
				end
				job.Cleanup()
			end
			return jobSummary(job)
		end)
		add("resolve_path", "inspect", function(args)
			assert(
				type(args.segments) == "table" and #args.segments <= 32,
				"INVALID_ARGUMENT: path must be an array of at most 32 exact names"
			)
			local candidates = { args.rootId and registry:Resolve(args.rootId) or c.Game }
			local truncated = false
			for _, segment in ipairs(args.segments) do
				stringArg(segment, 512)
				local nextValues = {}
				for _, parent in ipairs(candidates) do
					for _, child in ipairs(parent:GetChildren()) do
						if child.Name == segment and registry:Allowed(child) then
							if #nextValues < 100 then
								nextValues[#nextValues + 1] = child
							else
								truncated = true
							end
						end
					end
				end
				candidates = nextValues
			end
			local rows = {}
			for _, value in ipairs(candidates) do
				rows[#rows + 1] = registry:Describe(value)
			end
			return { instances = rows, ambiguous = #rows > 1, truncated = truncated }
		end)
		add("get_ancestors", "inspect", function(args)
			local value = object(args).Parent
			local rows = {}
			while value and #rows < 64 do
				if not registry:Allowed(value) then
					break
				end
				rows[#rows + 1] = registry:Describe(value)
				value = value.Parent
			end
			return { ancestors = rows, truncated = value ~= nil }
		end)
		add("get_class_schema", "inspect", function(args)
			local name = stringArg(args.className, 128)
			local rows, seen = {}, {}
			local original = name
			while name and not seen[name] do
				seen[name] = true
				local class = Apps.ReflectionService.GetClass(name)
				assert(class, "INVALID_CLASS: unknown class")
				for _, member in pairs(class.Properties or {}) do
					if not seen["p:" .. member.Name] and #rows < 200 then
						seen["p:" .. member.Name] = true
						rows[#rows + 1] = {
							name = member.Name,
							valueType = member.ValueType and member.ValueType.Name,
							readOnly = member.Tags and member.Tags.ReadOnly == true or false,
							declaredBy = name,
						}
					end
				end
				name = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
			end
			table.sort(rows, function(a, b)
				return a.name < b.name
			end)
			return {
				className = original,
				creatable = Apps.ReflectionService.CanCreate(original),
				properties = rows,
				truncated = #rows >= 200,
			}
		end)
		add("rename_instance", "edit", function(args)
			local target = object(args)
			c.Editable(target, true)
			return c.SetProperties({ target }, { Name = stringArg(args.name, 512) }, "AI: rename object")
		end)
		add("duplicate_instances", "edit", function(args)
			local objects = c.Targets(args)
			assert(#objects <= 20, "WORK_LIMIT: duplicate at most 20 roots")
			local selected = {}
			local clones = {}
			local count = 0
			local parent = args.parentId and registry:Resolve(args.parentId)
			if parent then
				c.Editable(parent, true)
			end
			for _, value in ipairs(objects) do
				c.Editable(value, false)
				assert(value.Archivable ~= false, "NOT_ARCHIVABLE: object cannot be cloned")
				selected[value] = true
				count += 1 + #value:GetDescendants()
				assert(count <= 2000, "WORK_LIMIT: duplication exceeds 2000 instances")
			end
			for _, value in ipairs(objects) do
				local ancestor = value.Parent
				while ancestor do
					assert(not selected[ancestor], "INVALID_TARGET: choose independent roots")
					ancestor = ancestor.Parent
				end
			end
			local ok, why = pcall(function()
				for _, value in ipairs(objects) do
					local clone = value:Clone()
					assert(clone, "CLONE_FAILED: object could not be cloned")
					clones[#clones + 1] = clone
				end
				Apps.History.Run("AI: duplicate objects", function()
					for index, clone in ipairs(clones) do
						Apps.History.Set(clone, "Parent", parent or objects[index].Parent)
					end
				end)
			end)
			if not ok then
				for _, clone in ipairs(clones) do
					if not clone.Parent then
						clone:Destroy()
					end
				end
				error(why, 0)
			end
			return c.Changed(clones)
		end)
		add("get_bounds", "inspect", function(args)
			local cf, size, pivot = bounds(c.Targets(args), args.space)
			return { center = codec:Encode(cf), size = codec:Encode(size), pivot = codec:Encode(pivot) }
		end)
		add("set_pivot", "edit", function(args)
			local target = object(args)
			c.Editable(target, false)
			assert(
				(target:IsA("BasePart") or target:IsA("Model")) and target:IsDescendantOf(service.Workspace),
				"INVALID_TARGET: Workspace geometry required"
			)
			for _, part in ipairs(target:IsA("BasePart") and { target } or target:GetDescendants()) do
				if part:IsA("BasePart") then
					assert(not part.Locked, "LOCKED_TARGET: geometry is locked")
				end
			end
			local value = codec:Decode(args.pivot)
			assert(typeof(value) == "CFrame", "INVALID_VALUE: pivot requires CFrame")
			Apps.History.Change("AI: set object pivot", function()
				return target:GetPivot()
			end, function(nextValue)
				target:PivotTo(nextValue)
			end, value)
			return c.Changed({ target })
		end)
		local uiKeys = {
			Position = true,
			Size = true,
			Rotation = true,
			AnchorPoint = true,
			Visible = true,
			ZIndex = true,
			LayoutOrder = true,
		}
		add("get_ui_layout", "inspect", function(args)
			local target = object(args)
			assert(target:IsA("GuiObject"), "INVALID_TARGET: GuiObject required")
			local values = {}
			for key in pairs(uiKeys) do
				values[key] = codec:Encode(target[key])
			end
			values.AbsolutePosition = codec:Encode(target.AbsolutePosition)
			values.AbsoluteSize = codec:Encode(target.AbsoluteSize)
			return { instance = registry:Describe(target), layout = values }
		end)
		add("set_ui_layout", "edit", function(args)
			local objects = c.Targets(args)
			for _, value in ipairs(objects) do
				assert(value:IsA("GuiObject"), "INVALID_TARGET: GuiObject required")
			end
			assert(type(args.properties) == "table", "INVALID_ARGUMENT: properties required")
			for key in pairs(args.properties) do
				assert(uiKeys[key], "INVALID_PROPERTY: unsupported UI layout property")
			end
			return c.SetProperties(objects, args.properties, "AI: edit UI layout")
		end)
		add("raycast", "inspect", function(args)
			local origin, direction = codec:Decode(args.origin), codec:Decode(args.direction)
			assert(
				typeof(origin) == "Vector3"
					and typeof(direction) == "Vector3"
					and direction.Magnitude > 0
					and direction.Magnitude <= 15000,
				"INVALID_VALUE: finite Vector3 ray of length up to 15000 required"
			)
			local excluded = {}
			for _, key in ipairs(args.excludeIds or {}) do
				assert(#excluded < 100, "WORK_LIMIT: at most 100 exclusions")
				excluded[#excluded + 1] = registry:Resolve(key)
			end
			for value in pairs(c.Main.SelectionGeometryRoots or {}) do
				excluded[#excluded + 1] = value
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = excluded
			params.IgnoreWater = args.ignoreWater ~= false
			local hit = service.Workspace:Raycast(origin, direction, params)
			if not hit then
				return { hit = false }
			end
			return {
				hit = true,
				instance = identity(hit.Instance),
				position = codec:Encode(hit.Position),
				normal = codec:Encode(hit.Normal),
				distance = hit.Distance,
				material = codec:Encode(hit.Material),
			}
		end)
		add("save_camera", "inspect", function()
			local count = 0
			for _ in pairs(cameras) do
				count += 1
			end
			assert(count < 8, "SNAPSHOT_LIMIT: at most eight camera snapshots")
			local camera = assert(service.Workspace.CurrentCamera, "CAMERA_UNAVAILABLE")
			local key = id("camera")
			local values = {}
			for _, name in ipairs({ "CFrame", "Focus", "FieldOfView", "CameraType", "CameraSubject" }) do
				values[name] = codec:Encode(camera[name])
			end
			cameras[key] = { Camera = camera, Values = values }
			return { snapshotId = key }
		end)
		add("restore_camera", "edit", function(args)
			local saved = cameras[args.snapshotId]
			assert(saved, "SNAPSHOT_UNAVAILABLE: unknown camera snapshot")
			assert(service.Workspace.CurrentCamera == saved.Camera, "CAMERA_CHANGED: camera was replaced")
			local values = table.clone(saved.Values)
			return c.SetProperties({ saved.Camera }, values, "AI: restore camera")
		end)
		add("focus_camera", "edit", function(args)
			local cf, size = bounds(c.Targets(args), "World")
			local camera = assert(service.Workspace.CurrentCamera, "CAMERA_UNAVAILABLE")
			local viewport = camera.ViewportSize
			local aspect = viewport and viewport.Y > 0 and viewport.X / viewport.Y or 1
			local tangent = math.tan(math.rad(camera.FieldOfView * 0.5)) * math.min(1, aspect)
			local distance = math.max(size.Magnitude * 0.5 / tangent, 2) * 1.2
			local position = cf.Position - camera.CFrame.LookVector * distance
			return c.SetProperties({ camera }, {
				CFrame = codec:Encode(CFrame.lookAt(position, cf.Position)),
				Focus = codec:Encode(cf),
				CameraType = codec:Encode(Enum.CameraType.Scriptable),
			}, "AI: focus camera")
		end)
		add("check_luau", "inspect", function(args)
			assert(type(env.loadstring) == "function", "UNSUPPORTED: compiler unavailable")
			local source = stringArg(args.source, 65536)
			local ok, chunk, problem = pcall(env.loadstring, source, "@DexExplorer/AI/SyntaxCheck")
			return {
				valid = ok and type(chunk) == "function",
				error = not ok and tostring(chunk):sub(1, 2000)
					or type(chunk) ~= "function" and tostring(problem):sub(1, 2000)
					or nil,
				executed = false,
			}
		end)
		add("read_script", "inspect", function(args)
			local target = object(args)
			assert(target:IsA("LuaSourceContainer"), "INVALID_TARGET: script required")
			local start = integer(args.startLine, 1, 1000000)
			local count = integer(args.lineCount, 100, 400)
			return startJob(function(check)
				local ok, source = pcall(function()
					return target.Source
				end)
				local kind = "Readable source"
				if not ok or type(source) ~= "string" or source == "" then
					assert(
						args.decompile == true and type(env.decompile) == "function",
						"SOURCE_UNAVAILABLE: readable source is unavailable; explicit decompile=true is required for decompilation"
					)
					assert(check(), "CANCELLED")
					source = env.decompile(target)
					kind = "Decompiled source"
				end
				assert(
					type(source) == "string" and #source <= 2 * 1024 * 1024,
					"SOURCE_LIMIT: script is unavailable or exceeds 2 MiB"
				)
				local lines = {}
				local line = 0
				local total = 0
				local bytes = 0
				local clipped = false
				for value in (source .. "\n"):gmatch("(.-)\n") do
					total += 1
					if total >= start and #lines < count then
						if bytes + #value > 60000 then
							clipped = true
							break
						end
						lines[#lines + 1] = value
						bytes += #value + 1
					end
					line += 1
					if line % 256 == 0 then
						assert(check(), "CANCELLED")
					end
				end
				return {
					instance = registry:Describe(target),
					sourceKind = kind,
					startLine = start,
					source = table.concat(lines, "\n"),
					returnedLines = #lines,
					totalLines = not clipped and total or nil,
					truncated = clipped or total >= start + #lines,
				}
			end)
		end)
		add("find_references", "inspect", function(args)
			local target = object(args)
			local scan = available("ReferenceScan")
			return startJob(function(check)
				local found = scan.Run({
					Target = target,
					Objects = Apps.Explorer.GetNodes(),
					MaxResults = 100,
					MaxScriptBytes = 1024 * 1024,
					MaxTotalBytes = 8 * 1024 * 1024,
					Checkpoint = function()
						return check()
					end,
					ReadScript = function(value)
						local ok, source = pcall(function()
							return value.Source
						end)
						if ok and type(source) == "string" and source ~= "" then
							return { Source = source, SourceKind = "Readable source" }
						end
						if args.bytecode == true and Apps.ReferenceSource then
							return Apps.ReferenceSource.Read(value, check)
						end
						return { Unavailable = "Source unavailable" }
					end,
				})
				local direct, scripts = {}, {}
				for _, item in ipairs(found.Direct) do
					direct[#direct + 1] =
						{ instance = identity(item.Object), property = item.Property, kind = "confirmed" }
				end
				for _, item in ipairs(found.Scripts) do
					scripts[#scripts + 1] = {
						instance = identity(item.Object),
						line = item.Line,
						snippet = (item.Snippet or ""):sub(1, 300),
						kind = item.Kind,
						sourceKind = item.SourceKind,
					}
				end
				return {
					direct = direct,
					scripts = scripts,
					stats = found.Stats,
					note = "Script text and bytecode matches are possible references, not confirmed identity.",
				}
			end)
		end)
		local function watchSummary(key, value)
			return {
				watchId = key,
				instance = identity(value.Target),
				running = value.Session.Running,
				events = value.Session.Count,
				dropped = value.Session.Dropped,
				pendingObjects = value.Session.PendingObjects,
				limitReached = value.LimitReached or false,
			}
		end
		local function updateHeartbeat()
			local needed = next(watches) ~= nil
			if needed and not heartbeat then
				heartbeat = service.RunService.Heartbeat:Connect(function()
					for _, value in pairs(watches) do
						if value.Session.WatchedObjects + value.Session.PendingObjects > 1000 then
							value.Session:Stop()
							value.LimitReached = true
						else
							value.Session:Flush()
						end
					end
				end)
			elseif not needed and heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end
		add("watch_instance", "inspect", function(args)
			local target = object(args)
			local count = 0
			for _ in pairs(watches) do
				count += 1
			end
			assert(count < 2, "WATCH_LIMIT: stop a watch before starting another")
			assert(#target:GetDescendants() <= 1000, "WATCH_LIMIT: choose a subtree with at most 1000 descendants")
			local session = available("ActivitySession").Create({ Capacity = 200 })
			local key = id("watch")
			local ok, why = pcall(session.Start, session, target)
			if not ok then
				session:Destroy()
				error(why, 0)
			end
			watches[key] = { Session = session, Target = target }
			updateHeartbeat()
			return watchSummary(key, watches[key])
		end)
		add("list_watches", "inspect", function()
			local rows = {}
			for key, value in pairs(watches) do
				rows[#rows + 1] = watchSummary(key, value)
			end
			return { watches = rows }
		end)
		add("get_events", "inspect", function(args)
			local value = watches[args.watchId]
			assert(value, "WATCH_UNAVAILABLE")
			local limit = integer(args.limit, 50, 100)
			local after = args.afterId or 0
			assert(type(after) == "number" and after >= 0 and after % 1 == 0, "INVALID_ARGUMENT: afterId")
			value.Session:Flush()
			local events = {}
			local nextId = after
			for _, event in ipairs(value.Session:Events()) do
				if event.Id > after and #events < limit then
					events[#events + 1] = {
						id = event.Id,
						kind = event.Kind,
						name = event.Name,
						time = event.Time,
						before = event.Before,
						after = event.After,
						changes = event.Changes,
						instance = identity(event.Object and event.Object[1]),
						objectName = event.ObjectName,
					}
					nextId = event.Id
				end
			end
			return { events = events, nextId = nextId, dropped = value.Session.Dropped, running = value.Session.Running }
		end)
		add("stop_watch", "inspect", function(args)
			local value = watches[args.watchId]
			assert(value, "WATCH_UNAVAILABLE")
			value.Session:Destroy()
			watches[args.watchId] = nil
			updateHeartbeat()
			return { stopped = true }
		end)
		add("preview_instance", "edit", function(args)
			local target = object(args)
			assert(target:IsA("Model") or target:IsA("BasePart"), "INVALID_TARGET: part or model required")
			available("ModelViewer").ViewModel(target)
			return { opened = true, instance = registry:Describe(target) }
		end)
		add("reveal_instance", "edit", function(args)
			local target = object(args)
			assert(Apps.Explorer.ViewObj, "UNSUPPORTED: Explorer reveal unavailable")
			Apps.Explorer.ViewObj(target)
			return { revealed = true, instance = registry:Describe(target) }
		end)
		local function executorFunction(name: string): (...any) -> ...any
			local callback = env[name]
			assert(type(callback) == "function", "UNSUPPORTED: " .. name .. " is unavailable")
			return callback
		end

		local function textTarget(args)
			local target = object(args)
			assert(
				target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox"),
				"INVALID_TARGET: text GUI required"
			)
			return target
		end

		add("get_gui_text", "inspect", function(args)
			local target = textTarget(args)
			local text = target.Text
			local limit = utf8.offset(text, 2049)
			return {
				instanceId = args.instanceId,
				text = if limit then string.sub(text, 1, limit - 1) else text,
				truncated = limit ~= nil,
			}
		end)
		add("set_gui_text", "edit", function(args)
			local target = textTarget(args)
			assert(type(args.text) == "string" and #args.text <= 8192, "INVALID_ARGUMENT: text is too long")
			return c.SetProperties({ target }, { Text = args.text })
		end)
		add("click_button", "execute", function(args)
			local target = object(args)
			assert(target:IsA("GuiButton"), "INVALID_TARGET: GuiButton required")
			local button = args.button or "left"
			assert(button == "left" or button == "right", "INVALID_ARGUMENT: invalid mouse button")
			local fire = executorFunction("firesignal")
			fire(if button == "left" then target.MouseButton1Click else target.MouseButton2Click)
			return { instanceId = args.instanceId, fired = true }
		end)
		add("fire_click_detector", "execute", function(args)
			local target = object(args)
			assert(target:IsA("ClickDetector"), "INVALID_TARGET: ClickDetector required")
			local button = args.button or "left"
			assert(button == "left" or button == "right", "INVALID_ARGUMENT: invalid mouse button")
			executorFunction("fireclickdetector")(
				target,
				0,
				if button == "left" then "MouseClick" else "RightMouseClick"
			)
			return { instanceId = args.instanceId, triggered = true }
		end)
		add("fire_proximity_prompt", "execute", function(args)
			local target = object(args)
			assert(target:IsA("ProximityPrompt"), "INVALID_TARGET: ProximityPrompt required")
			executorFunction("fireproximityprompt")(target)
			return { instanceId = args.instanceId, triggered = true }
		end)
		add("type_text_box", "execute", function(args)
			local target = object(args)
			assert(target:IsA("TextBox"), "INVALID_TARGET: TextBox required")
			assert(type(args.text) == "string" and #args.text <= 8192, "INVALID_ARGUMENT: text is too long")
			assert(args.submit == nil or type(args.submit) == "boolean", "INVALID_ARGUMENT: submit must be boolean")
			local focused = service.UserInputService:GetFocusedTextBox()
			assert(not focused or focused == target, "BUSY: another text box is focused")
			if not focused then
				target:CaptureFocus()
			end
			local ok, problem = pcall(function()
				target.Text = args.text
			end)
			if ok and args.submit or not ok and not focused then
				target:ReleaseFocus(ok and args.submit == true)
			end
			if not ok then
				error(problem, 0)
			end
			return { instanceId = args.instanceId, submitted = args.submit == true }
		end)
		add("get_executor_info", "inspect", function()
			local capabilities = {}
			for _, name in
				{ "firesignal", "fireclickdetector", "fireproximityprompt", "getfpscap", "setfpscap", "setclipboard" }
			do
				capabilities[name] = type(env[name]) == "function"
			end
			return { capabilities = capabilities }
		end)
		add("get_fps_cap", "inspect", function()
			local cap = executorFunction("getfpscap")()
			assert(type(cap) == "number" and cap >= 0 and cap < math.huge, "UNAVAILABLE_VALUE: invalid FPS cap")
			return { fpsCap = cap }
		end)
		add("set_fps_cap", "execute", function(args)
			local cap = args.fpsCap
			assert(
				type(cap) == "number" and cap % 1 == 0 and cap >= 0 and cap <= 1000,
				"INVALID_ARGUMENT: FPS cap must be an integer from 0 to 1000"
			)
			executorFunction("setfpscap")(cap)
			return { requestedFpsCap = cap }
		end)
		add("set_clipboard", "execute", function(args)
			assert(type(args.text) == "string" and #args.text <= 8192, "INVALID_ARGUMENT: clipboard text is too long")
			executorFunction("setclipboard")(args.text)
			return { copied = true, bytes = #args.text }
		end)
		local fileRoot = "dex-explorer/bridge-files"
		local function workspacePath(path: string): string
			assert(type(path) == "string" and #path >= 1 and #path <= 180, "INVALID_ARGUMENT: invalid workspace path")
			local parts = string.split(path, "/")
			for _, segment in parts do
				assert(
					#segment <= 64 and string.match(segment, "^[%w_-][%w_.-]*$") and string.sub(segment, -1) ~= ".",
					"INVALID_ARGUMENT: use relative paths with letters, digits, dots, underscores or hyphens"
				)
				local stem = string.upper(string.match(segment, "^[^.]+") or "")
				assert(
					stem ~= "CON"
						and stem ~= "PRN"
						and stem ~= "AUX"
						and stem ~= "NUL"
						and not string.match(stem, "^[CL][OP][MT][0-9]$"),
					"INVALID_ARGUMENT: reserved filename"
				)
			end
			return fileRoot .. "/" .. path
		end
		local function ensureFileRoot(): ()
			local isFolder = executorFunction("isfolder")
			local makeFolder = executorFunction("makefolder")
			if not isFolder("dex-explorer") then
				makeFolder("dex-explorer")
			end
			if not isFolder(fileRoot) then
				makeFolder(fileRoot)
			end
		end
		local function fileText(value: string): string
			assert(
				type(value) == "string" and #value <= 64000 and utf8.len(value),
				"INVALID_ARGUMENT: expected UTF-8 text up to 64000 bytes"
			)
			return value
		end
		add("file_exists", "execute", function(args)
			local path = workspacePath(args.path)
			return { file = executorFunction("isfile")(path), folder = executorFunction("isfolder")(path) }
		end)
		add("list_files", "execute", function(args)
			local path = if args.path then workspacePath(args.path) else fileRoot
			local entries = {}
			if not executorFunction("isfolder")(path) then
				assert(args.path == nil, "INVALID_TARGET: workspace folder does not exist")
				return { entries = entries, truncated = false }
			end
			local listed = executorFunction("listfiles")(path)
			for i = 1, math.min(#listed, 200) do
				local name = string.match(listed[i], "[^/\\]+$")
				if name then
					entries[#entries + 1] = name
				end
			end
			table.sort(entries)
			return { entries = entries, truncated = #listed > 200 }
		end)
		add("read_file", "execute", function(args)
			local contents = executorFunction("readfile")(workspacePath(args.path))
			return { text = fileText(contents), bytes = #contents }
		end)
		add("write_file", "execute", function(args)
			local path, contents = workspacePath(args.path), fileText(args.text)
			ensureFileRoot()
			executorFunction("writefile")(path, contents)
			return { written = true, bytes = #contents }
		end)
		add("append_file", "execute", function(args)
			local path, contents = workspacePath(args.path), fileText(args.text)
			ensureFileRoot()
			if executorFunction("isfile")(path) then
				local existing = fileText(executorFunction("readfile")(path))
				assert(#existing + #contents <= 64000, "INVALID_ARGUMENT: append would exceed the file limit")
				executorFunction("appendfile")(path, contents)
			else
				executorFunction("writefile")(path, contents)
			end
			return { appended = true, bytes = #contents }
		end)
		add("make_folder", "execute", function(args)
			local path = workspacePath(args.path)
			ensureFileRoot()
			if not executorFunction("isfolder")(path) then
				executorFunction("makefolder")(path)
			end
			return { available = true }
		end)
		add("delete_file", "execute", function(args)
			executorFunction("delfile")(workspacePath(args.path))
			return { deleted = true }
		end)
		add("delete_folder", "execute", function(args)
			local path = workspacePath(args.path)
			assert(#executorFunction("listfiles")(path) == 0, "INVALID_TARGET: only empty folders can be deleted")
			executorFunction("delfolder")(path)
			return { deleted = true }
		end)
		add("get_custom_asset", "execute", function(args)
			return { asset = executorFunction("getcustomasset")(workspacePath(args.path)) }
		end)
		add("load_file", "execute", function(args)
			local path = workspacePath(args.path)
			local contents = fileText(executorFunction("readfile")(path))
			return c.RunLuau({ source = contents })
		end)
		local drawings = {}
		local drawingCount = 0
		local drawingTypes =
			{ Line = true, Text = true, Circle = true, Square = true, Quad = true, Triangle = true, Image = true }
		local drawingProperties = {
			Visible = true,
			Color = true,
			Transparency = true,
			ZIndex = true,
			From = true,
			To = true,
			Position = true,
			Thickness = true,
			Text = true,
			Size = true,
			Center = true,
			Outline = true,
			OutlineColor = true,
			Radius = true,
			NumSides = true,
			Filled = true,
			PointA = true,
			PointB = true,
			PointC = true,
			PointD = true,
			Font = true,
			Rounding = true,
		}
		local function applyDrawing(handle, properties)
			local applied, errors = {}, {}
			for key, value in properties or {} do
				if not drawingProperties[key] then
					errors[key] = "Unsupported drawing property"
					continue
				end
				local ok = pcall(function()
					local decoded = codec:Decode(value)
					local kind = typeof(decoded)
					assert(
						kind == "Vector2"
							or kind == "Color3"
							or kind == "number"
							or kind == "boolean"
							or kind == "string" and #decoded <= 4096
					)
					handle[key] = decoded
				end)
				if ok then
					applied[#applied + 1] = key
				else
					errors[key] = "Invalid value for drawing property"
				end
			end
			table.sort(applied)
			return { applied = applied, errors = errors }
		end
		local function removeDrawing(key)
			local item = assert(drawings[key], "INVALID_TARGET: unknown drawing ID")
			local remove = item.Handle.Remove or item.Handle.Destroy
			assert(type(remove) == "function", "UNSUPPORTED: drawing removal unavailable")
			remove(item.Handle)
			drawings[key] = nil
			drawingCount -= 1
		end
		add("draw_create", "execute", function(args)
			assert(drawingTypes[args.kind], "INVALID_ARGUMENT: unknown drawing type")
			assert(drawingCount < 128, "LIMIT_EXCEEDED: remove an existing drawing first")
			local drawing = env.Drawing
			assert(type(drawing) == "table" and type(drawing.new) == "function", "UNSUPPORTED: Drawing is unavailable")
			local handle = assert(drawing.new(args.kind), "UNAVAILABLE_VALUE: drawing was not created")
			local key = id("drawing")
			drawings[key] = { Kind = args.kind, Handle = handle }
			drawingCount += 1
			local out = applyDrawing(handle, args.properties)
			out.drawingId = key
			return out
		end)
		add("draw_update", "execute", function(args)
			local item = assert(drawings[args.drawingId], "INVALID_TARGET: unknown drawing ID")
			return applyDrawing(item.Handle, args.properties)
		end)
		add("draw_remove", "execute", function(args)
			removeDrawing(args.drawingId)
			return { removed = true }
		end)
		add("list_drawings", "inspect", function()
			local entries = {}
			for key, item in drawings do
				entries[#entries + 1] = { drawingId = key, kind = item.Kind }
			end
			table.sort(entries, function(left, right)
				return left.drawingId < right.drawingId
			end)
			return { drawings = entries }
		end)
		add("draw_clear", "execute", function()
			local removed, failures = 0, {}
			for key in drawings do
				if pcall(removeDrawing, key) then
					removed += 1
				else
					failures[#failures + 1] = key
				end
			end
			return { removed = removed, failedDrawingIds = failures }
		end)
		local function cryptFunction(name: string): (...any) -> ...any
			local library = env.crypt
			assert(type(library) == "table", "UNSUPPORTED: crypt is unavailable")
			local callback = library[name]
			if not callback and type(library.base64) == "table" then
				if name == "base64encode" then
					callback = library.base64.encode
				end
				if name == "base64decode" then
					callback = library.base64.decode
				end
			end
			assert(type(callback) == "function", "UNSUPPORTED: crypt." .. name .. " is unavailable")
			return callback
		end
		local function cryptText(value: string): string
			assert(type(value) == "string" and #value <= 8192, "INVALID_ARGUMENT: expected at most 8192 bytes")
			return value
		end
		local function cryptOutput(value: string)
			assert(type(value) == "string" and #value <= 16384, "UNAVAILABLE_VALUE: invalid crypt output")
			if utf8.len(value) and not string.find(value, "%c") then
				return { encoding = "utf8", data = value }
			end
			return { encoding = "base64", data = cryptFunction("base64encode")(value) }
		end
		add("crypt_base64_encode", "inspect", function(args)
			return { data = cryptFunction("base64encode")(cryptText(args.data)) }
		end)
		add("crypt_base64_decode", "inspect", function(args)
			return cryptOutput(cryptFunction("base64decode")(cryptText(args.data)))
		end)
		add("crypt_hash", "inspect", function(args)
			local algorithm = args.algorithm or "sha256"
			assert(
				table.find({ "sha1", "sha256", "sha384", "sha512", "md5" }, algorithm),
				"INVALID_ARGUMENT: unsupported digest"
			)
			return { hash = cryptFunction("hash")(cryptText(args.data), algorithm), algorithm = algorithm }
		end)
		add("crypt_generate_bytes", "inspect", function(args)
			return { data = cryptFunction("generatebytes")(integer(args.size, 32, 1024)) }
		end)
		add("crypt_generate_key", "inspect", function()
			return { key = cryptFunction("generatekey")() }
		end)
		add("crypt_encrypt", "inspect", function(args)
			local mode = args.mode or "CBC"
			assert(mode == "CBC" or mode == "CTR", "INVALID_ARGUMENT: unsupported cipher mode")
			local ciphertext, iv = cryptFunction("encrypt")(
				cryptText(args.data),
				cryptText(args.key),
				args.iv and cryptText(args.iv),
				mode
			)
			return { data = ciphertext, iv = iv }
		end)
		add("crypt_decrypt", "inspect", function(args)
			local mode = args.mode or "CBC"
			assert(mode == "CBC" or mode == "CTR", "INVALID_ARGUMENT: unsupported cipher mode")
			return cryptOutput(
				cryptFunction("decrypt")(cryptText(args.data), cryptText(args.key), cryptText(args.iv), mode)
			)
		end)
		result.StartJob = startJob
		function result:Destroy()
			dead = true
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
			for _, value in pairs(watches) do
				value.Session:Destroy()
			end
			for _, job in pairs(jobs) do
				if job.Status == "running" then
					job.Status = "cancelled"
					if task.cancel and job.Thread then
						pcall(task.cancel, job.Thread)
					end
					job.Cleanup()
				end
			end
			table.clear(watches)
			table.clear(jobs)
			for key in drawings do
				pcall(removeDrawing, key)
			end
			table.clear(drawings)
			table.clear(cameras)
		end
		return result
	end
	return Extra
end
return { Main = Main }
