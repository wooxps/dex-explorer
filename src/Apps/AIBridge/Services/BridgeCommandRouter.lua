--!strict

------------------------------ Module ------------------------------

local function Main()
	local Router = {}
	local readTools = {
		"dex_get_session",
		"dex_get_capabilities",
		"dex_get_tree",
		"dex_find_instances",
		"dex_get_instance",
		"dex_get_selection",
		"dex_get_properties",
		"dex_get_attributes",
		"dex_get_tags",
		"dex_get_history",
		"dex_list_players",
		"dex_get_player",
		"dex_get_camera",
		"dex_get_run",
	}
	local editTools = {
		"dex_set_selection",
		"dex_set_properties",
		"dex_create_instances",
		"dex_reparent_instances",
		"dex_delete_instances",
		"dex_set_attributes",
		"dex_set_tags",
		"dex_transform_instances",
		"dex_undo",
		"dex_redo",
		"dex_move_local_player",
		"dex_set_camera",
	}
	local runTools = { "dex_run_luau", "dex_cancel_run" }
	local function bounded(value, default, minimum, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum,
			"INVALID_ARGUMENT: integer outside supported range"
		)
		return value
	end
	local function text(value, label, limit)
		assert(type(value) == "string" and #value > 0 and #value <= (limit or 256), "INVALID_ARGUMENT: " .. label)
		return value
	end
	local function names(values, maximum)
		assert(
			type(values) == "table" and #values >= 1 and #values <= maximum,
			"INVALID_ARGUMENT: list size outside supported range"
		)
		for _, value in ipairs(values) do
			text(value, "name", 128)
		end
		return values
	end
	function Router.Create(options)
		local Apps, Main, service, env = options.Apps, options.Main or {}, options.service, options.env or {}
		local registry = Apps.BridgeRegistry.Create({ Apps = Apps, Main = Main, Game = options.Game or game })
		local codec = Apps.BridgeValueCodec.Create(registry)
		local world = service.Workspace
		local root = options.Game or game
		local router = { Registry = registry, Codec = codec }
		local handlers = {}
		local access = {}
		local destroyed, busy = false, false
		local pageId = 0
		local pages = {}
		local pageOrder = {}
		local runs = {}
		local scriptEnvironments = {}
		local teachState = {}
		local runOrder = {}
		local runCounter = 0
		local historyHeads = setmetatable({}, { __mode = "k" })
		local nextHistoryHead = 0
		for _, name in ipairs(readTools) do
			access[name] = "inspect"
		end
		for _, name in ipairs(editTools) do
			access[name] = "edit"
		end
		for _, name in ipairs(runTools) do
			access[name] = "execute"
		end
		local function history()
			assert(Apps.History, "UNSUPPORTED: history unavailable")
			return Apps.History
		end
		local function editable(object, allowService)
			assert(
				registry:Editable(object) or allowService and object ~= root,
				"INVALID_TARGET: services cannot be moved or deleted"
			)
			return object
		end
		local function targets(args)
			names(args.instanceIds, 100)
			local list, seen = {}, {}
			for _, id in ipairs(args.instanceIds) do
				local object = registry:Resolve(id)
				if not seen[object] then
					seen[object] = true
					list[#list + 1] = object
				end
			end
			return list
		end
		local function summaries(objects)
			local result = {}
			for _, object in ipairs(objects) do
				result[#result + 1] = registry:Describe(object)
			end
			return result
		end
		local function changed(objects)
			return {
				instances = summaries(objects),
				historyIndex = history().Index,
				historyHead = handlers.dex_get_history().head,
				scope = "client",
			}
		end
		local function keys(values, limit)
			assert(type(values) == "table", "INVALID_ARGUMENT: values map required")
			local result = {}
			for key in pairs(values) do
				text(key, "property or attribute name", 128)
				result[#result + 1] = key
			end
			assert(#result >= 1 and #result <= limit, "INVALID_ARGUMENT: values map size outside supported range")
			table.sort(result)
			return result
		end
		local function property(object, key, write)
			local member = Apps.ReflectionService.GetProperty(object.ClassName, key)
			assert(member, "INVALID_PROPERTY: " .. key)
			assert(
				not write or not (member.Tags and member.Tags.ReadOnly) and key ~= "ClassName",
				"READ_ONLY_PROPERTY: " .. key
			)
			return member
		end
		local function propertyPlan(objects, values, creating)
			local order = keys(values, 32)
			local plan = {}
			assert(#objects * #order <= 256, "WORK_LIMIT: a property batch may change at most 256 values")
			for _, object in ipairs(objects) do
				if not creating then
					editable(object, true)
				end
				for _, key in ipairs(order) do
					assert(key ~= "Source", "UNSUPPORTED: editing live script Source is not supported by Dex MCP")
					assert(not creating or key ~= "Parent", "INVALID_PROPERTY: use parentId when creating an instance")
					property(object, key, true)
					local value = codec:Decode(values[key])
					if key == "Parent" then
						editable(object, false)
						if value ~= nil then
							editable(value, true)
							assert(value ~= object and not value:IsDescendantOf(object), "INVALID_PARENT: parent cycle")
						end
					end
					local good, before = pcall(function()
						return object[key]
					end)
					assert(good, "UNAVAILABLE_PROPERTY: " .. key)
					local valueType = typeof(before)
					if value ~= nil and before ~= nil then
						assert(typeof(value) == valueType, "INVALID_VALUE_TYPE: " .. key .. " requires " .. valueType)
					end
					if key == "Name" then
						text(value, "Name", 512)
					end
					plan[#plan + 1] = { Object = object, Key = key, Value = value }
				end
			end
			return plan
		end
		local function setProperties(objects, values, label)
			local plan = propertyPlan(objects, values)
			history().Run(label or "AI: set properties", function()
				for _, change in ipairs(plan) do
					history().Set(change.Object, change.Key, change.Value)
				end
			end)
			return changed(objects)
		end
		local function page(items, args, kind, truncated)
			local limit = bounded(args.limit, 100, 1, 200)
			if args.cursor then
				local cursor = pages[text(args.cursor, "cursor", 64)]
				assert(
					cursor and cursor.Kind == kind and os.clock() - cursor.Time <= 15,
					"STALE_CURSOR: repeat the query"
				)
				pages[args.cursor] = nil
				items = cursor.Items
				truncated = cursor.Truncated
			end
			local output = {}
			for index = 1, math.min(limit, #items) do
				output[index] = items[index]
			end
			local nextCursor
			if #items > limit then
				local remaining = {}
				for index = limit + 1, #items do
					remaining[#remaining + 1] = items[index]
				end
				pageId += 1
				nextCursor = "p" .. pageId
				pages[nextCursor] = { Items = remaining, Kind = kind, Time = os.clock(), Truncated = truncated }
				pageOrder[#pageOrder + 1] = nextCursor
				if #pageOrder > 8 then
					pages[table.remove(pageOrder, 1)] = nil
				end
			end
			return { items = output, nextCursor = nextCursor, truncated = not not truncated, snapshot = true }
		end
		local function walk(args, filter)
			local selected = args.rootId and registry:Resolve(args.rootId) or root
			local maximumDepth = bounded(args.depth, filter and 16 or 1, 1, 32)
			local stack = { { Object = selected, Depth = 0 } }
			local rows = {}
			local visited = 0
			local lastYield = os.clock()
			local truncated = false
			while #stack > 0 do
				local item = table.remove(stack)
				local object = item.Object
				visited += 1
				if visited > 5000 then
					truncated = true
					break
				end
				if registry:Allowed(object) then
					if item.Depth > 0 and (not filter or filter(object)) then
						local row = registry:Describe(object)
						row.depth = item.Depth
						rows[#rows + 1] = row
					end
					if item.Depth < maximumDepth then
						local children = object:GetChildren()
						for index = #children, 1, -1 do
							stack[#stack + 1] = { Object = children[index], Depth = item.Depth + 1 }
						end
					end
				end
				if os.clock() - lastYield >= 0.002 then
					task.wait()
					assert(not destroyed, "CANCELLED: bridge disconnected")
					lastYield = os.clock()
				end
			end
			return rows, truncated
		end
		handlers.dex_get_session = function()
			local player = service.Players.LocalPlayer
			return {
				placeId = root.PlaceId,
				gameId = root.GameId,
				jobId = root.JobId,
				player = player and { name = player.Name, userId = player.UserId },
				root = registry:Describe(root),
				scope = "client",
				protocol = 1,
			}
		end
		handlers.dex_get_capabilities = function()
			return router:Capabilities()
		end
		handlers.dex_get_instance = function(args)
			return registry:Describe(registry:Resolve(args.instanceId))
		end
		handlers.dex_get_tree = function(args)
			if args.cursor then
				return page({}, args, "tree", false)
			end
			local rows, truncated = walk(args)
			return page(rows, args, "tree", truncated)
		end
		handlers.dex_find_instances = function(args)
			if args.cursor then
				return page({}, args, "find", false)
			end
			local query = args.name and string.lower(text(args.name, "name", 256))
			local class = args.className and text(args.className, "className", 128)
			assert(query or class, "INVALID_ARGUMENT: name or className required")
			local rows, truncated = walk(args, function(object)
				return (not query or string.find(string.lower(object.Name), query, 1, true) ~= nil)
					and (not class or object:IsA(class))
			end)
			return page(rows, args, "find", truncated)
		end
		handlers.dex_get_selection = function()
			return { instances = summaries(Apps.Explorer.Services.Selection:Get()) }
		end
		handlers.dex_set_selection = function(args)
			local objects = type(args.instanceIds) == "table" and #args.instanceIds == 0 and {} or targets(args)
			local mode = args.mode or "set"
			assert(mode == "set" or mode == "add" or mode == "remove", "INVALID_ARGUMENT: selection mode")
			local selection = Apps.Explorer.Services.Selection
			if mode ~= "set" then
				local map = {}
				for _, object in ipairs(objects) do
					map[object] = true
				end
				local current = selection:Get()
				if mode == "remove" then
					objects = {}
					for _, object in ipairs(current) do
						if not map[object] then
							objects[#objects + 1] = object
						end
					end
				else
					for _, object in ipairs(current) do
						if not map[object] then
							objects[#objects + 1] = object
						end
					end
				end
			end
			selection:Set(objects)
			return { instances = summaries(objects) }
		end
		handlers.dex_get_properties = function(args)
			local object = registry:Resolve(args.instanceId)
			local wanted = args.properties or { "Name", "ClassName", "Parent" }
			names(wanted, 64)
			local result, errors = {}, {}
			for _, key in ipairs(wanted) do
				local ok, value = pcall(function()
					property(object, key, false)
					return codec:Encode(object[key])
				end)
				if ok then
					result[key] = value
				else
					errors[key] = tostring(value)
				end
			end
			return { instance = registry:Describe(object), properties = result, errors = errors }
		end
		handlers.dex_set_properties = function(args)
			return setProperties(targets(args), args.properties)
		end
		handlers.dex_get_attributes = function(args)
			local object = registry:Resolve(args.instanceId)
			return { instanceId = registry:Id(object), attributes = codec:Encode(object:GetAttributes()) }
		end
		handlers.dex_set_attributes = function(args)
			local objects = targets(args)
			local order = keys(args.attributes, 32)
			local values = {}
			assert(#objects * #order <= 256, "WORK_LIMIT: an attribute batch may change at most 256 values")
			for _, key in ipairs(order) do
				values[key] = codec:Decode(args.attributes[key])
			end
			for _, object in ipairs(objects) do
				editable(object, true)
			end
			history().Run("AI: set attributes", function()
				for _, object in ipairs(objects) do
					for _, key in ipairs(order) do
						history().Attribute(object, key, values[key])
					end
				end
			end)
			return changed(objects)
		end
		handlers.dex_get_tags = function(args)
			local object = registry:Resolve(args.instanceId)
			return { instanceId = registry:Id(object), tags = service.CollectionService:GetTags(object) }
		end
		handlers.dex_set_tags = function(args)
			local objects = targets(args)
			local tags = type(args.tags) == "table" and #args.tags == 0 and {} or names(args.tags, 64)
			local mode = args.mode or "add"
			assert(mode == "add" or mode == "remove" or mode == "replace", "INVALID_ARGUMENT: tag mode")
			local wanted = {}
			for _, tag in ipairs(tags) do
				wanted[tag] = true
			end
			local work = #objects * #tags
			for _, object in ipairs(objects) do
				editable(object, true)
				if mode == "replace" then
					work += #service.CollectionService:GetTags(object)
				end
			end
			assert(work <= 256, "WORK_LIMIT: a tag batch may change at most 256 values")
			history().Run("AI: set tags", function()
				for _, object in ipairs(objects) do
					if mode == "replace" then
						for _, tag in ipairs(service.CollectionService:GetTags(object)) do
							if not wanted[tag] then
								history().Tag(object, tag, false)
							end
						end
					end
					for _, tag in ipairs(tags) do
						history().Tag(object, tag, mode ~= "remove")
					end
				end
			end)
			return changed(objects)
		end
		handlers.dex_create_instances = function(args)
			text(args.className, "className", 128)
			assert(Apps.ReflectionService.CanCreate(args.className), "INVALID_CLASS: class is not insertable")
			local parent = registry:Resolve(args.parentId)
			editable(parent, true)
			if args.name then
				text(args.name, "Name", 512)
			end
			local object = Instance.new(args.className)
			local committed = false
			local ok, result = pcall(function()
				local plan = args.properties and propertyPlan({ object }, args.properties, true) or {}
				history().Run("AI: create " .. args.className, function()
					if args.name then
						object.Name = args.name
					end
					for _, change in ipairs(plan) do
						object[change.Key] = change.Value
					end
					history().Set(object, "Parent", parent)
				end)
				committed = true
				return changed({ object })
			end)
			if not ok then
				if not committed then
					object:Destroy()
				else
					error(
						"COMMITTED_RESULT_ERROR: instance was created; inspect history before retrying. "
							.. tostring(result),
						0
					)
				end
				error(result, 0)
			end
			return result
		end
		handlers.dex_reparent_instances = function(args)
			local objects = targets(args)
			local parent = registry:Resolve(args.parentId)
			editable(parent, true)
			for _, object in ipairs(objects) do
				editable(object, false)
				assert(object ~= parent and not parent:IsDescendantOf(object), "INVALID_PARENT: parent cycle")
			end
			Apps.EditingService.Reparent(objects, parent)
			return changed(objects)
		end
		handlers.dex_delete_instances = function(args)
			local objects = targets(args)
			for _, object in ipairs(objects) do
				editable(object, false)
			end
			local ids = {}
			for _, object in ipairs(objects) do
				ids[#ids + 1] = registry:Id(object)
			end
			Apps.EditingService.Reparent(objects, nil)
			return { instanceIds = ids, historyIndex = history().Index, scope = "client", reversible = true }
		end
		handlers.dex_get_history = function()
			local h = history()
			local entries = {}
			for index = math.max(1, #h.Entries - 49), #h.Entries do
				entries[#entries + 1] = { index = index, name = h.Entries[index].Name, applied = index <= h.Index }
			end
			local function token(entry)
				if not entry then
					return "h0"
				end
				if not historyHeads[entry] then
					nextHistoryHead += 1
					historyHeads[entry] = "h" .. nextHistoryHead
				end
				return historyHeads[entry]
			end
			local head = token(h.Entries[h.Index]) .. "." .. token(h.Entries[h.Index + 1]) .. "." .. #h.Entries
			return { index = h.Index, head = head, entries = entries, canUndo = h.CanUndo(), canRedo = h.CanRedo() }
		end
		local function replay(redo, args)
			local h = history()
			local state = handlers.dex_get_history()
			assert(
				args.expectedIndex ~= nil and args.expectedIndex == h.Index and args.expectedHead == state.head,
				"HISTORY_CONFLICT: expectedIndex and expectedHead must match the current history head"
			)
			local ok, problem = (redo and h.Redo or h.Undo)()
			assert(ok, "HISTORY_FAILED: " .. tostring(problem or "no matching transaction"))
			return handlers.dex_get_history()
		end
		handlers.dex_undo = function(args)
			return replay(false, args)
		end
		handlers.dex_redo = function(args)
			return replay(true, args)
		end
		handlers.dex_transform_instances = function(args)
			local objects = targets(args)
			for _, object in ipairs(objects) do
				editable(object, false)
			end
			local operation = args.operation
			assert(
				operation == "move" or operation == "rotate" or operation == "scale",
				"INVALID_ARGUMENT: transform operation"
			)
			local tools = Apps.TransformSession
			assert(tools, "UNSUPPORTED: transform service unavailable")
			local roots = tools.Collect(objects)
			assert(
				#roots == #objects,
				"INVALID_TARGET: every transform target must be an independent unlocked part or model"
			)
			local space = args.space or "World"
			assert(space == "World" or space == "Local", "INVALID_ARGUMENT: transform space")
			local _, size, pivot = tools.Bounds(roots, operation == "scale" and "Scale" or space)
			local gesture, problem = tools.Begin(
				objects,
				operation == "move" and "Move" or operation == "rotate" and "Rotate" or "Scale",
				pivot,
				size
			)
			assert(gesture, problem)
			local ok, result = pcall(function()
				local good, why
				if operation == "move" then
					local delta = codec:Decode(args.value)
					assert(typeof(delta) == "Vector3", "INVALID_ARGUMENT: move value must be Vector3")
					if space == "Local" then
						delta = pivot:VectorToWorldSpace(delta)
					end
					good, why = gesture:Move(delta)
				elseif operation == "rotate" then
					local angles = codec:Decode(args.value)
					assert(typeof(angles) == "Vector3", "INVALID_ARGUMENT: rotation value must be degrees Vector3")
					local rotation = CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
					local axis, angle = rotation:ToAxisAngle()
					if space == "Local" then
						axis = pivot:VectorToWorldSpace(axis)
					end
					good, why = gesture:Rotate(axis, angle)
				else
					local factor = args.value
					assert(
						type(factor) == "number" and factor == factor and factor > 0 and factor <= 100,
						"INVALID_ARGUMENT: scale value must be a positive factor up to 100"
					)
					good, why = gesture:Scale(1, size.X * (factor - 1) * 0.5, true, true, 1)
				end
				assert(good, why)
				local committed, commitProblem = gesture:Commit()
				assert(committed, commitProblem)
				return changed(objects)
			end)
			if not ok then
				gesture:Cancel()
				error(result, 0)
			end
			return result
		end
		local function playerInfo(player)
			return {
				name = player.Name,
				displayName = player.DisplayName,
				userId = player.UserId,
				localPlayer = player == service.Players.LocalPlayer,
				character = player.Character and registry:Allowed(player.Character) and registry:Describe(
					player.Character
				) or nil,
			}
		end
		handlers.dex_list_players = function()
			local list = {}
			for _, player in ipairs(service.Players:GetPlayers()) do
				list[#list + 1] = playerInfo(player)
			end
			return { players = list }
		end
		handlers.dex_get_player = function(args)
			local player = args.userId and service.Players:GetPlayerByUserId(args.userId) or service.Players.LocalPlayer
			assert(player, "PLAYER_UNAVAILABLE: player is no longer connected")
			return playerInfo(player)
		end
		handlers.dex_move_local_player = function(args)
			local character = service.Players.LocalPlayer.Character
			assert(character and character.Parent, "CHARACTER_UNAVAILABLE: local character has not spawned")
			local position = codec:Decode(args.position)
			assert(typeof(position) == "Vector3", "INVALID_ARGUMENT: position must be Vector3")
			local before = character:GetPivot()
			local after = CFrame.new(position) * (before - before.Position)
			history().Change("AI: move local character", function()
				return character:GetPivot()
			end, function(value)
				character:PivotTo(value)
			end, after)
			return {
				scope = "client",
				observedPivot = codec:Encode(character:GetPivot()),
				historyIndex = history().Index,
				replication = "Server or physics authority may override this local movement",
			}
		end
		handlers.dex_get_camera = function()
			local camera = world.CurrentCamera
			assert(camera, "CAMERA_UNAVAILABLE: no active camera")
			local props = {}
			for _, key in ipairs({ "CFrame", "Focus", "FieldOfView", "CameraType", "CameraSubject" }) do
				local ok, value = pcall(function()
					return codec:Encode(camera[key])
				end)
				if ok then
					props[key] = value
				end
			end
			return { properties = props, scope = "client" }
		end
		handlers.dex_set_camera = function(args)
			local camera = world.CurrentCamera
			assert(camera, "CAMERA_UNAVAILABLE: no active camera")
			local allowed = { CFrame = true, Focus = true, FieldOfView = true, CameraType = true, CameraSubject = true }
			for _, key in ipairs(keys(args.properties, 5)) do
				assert(allowed[key], "INVALID_PROPERTY: unsupported camera property")
			end
			setProperties({ camera }, args.properties, "AI: change camera")
			return handlers.dex_get_camera()
		end
		local function runResult(run)
			return {
				runId = run.Id,
				status = run.Status,
				output = table.clone(run.Output),
				outputDropped = run.Dropped,
				returns = run.Returns,
				returnCount = run.ReturnCount,
				error = run.Error,
				scope = "client_executor",
				started = run.Started,
				duration = run.Duration,
			}
		end
		handlers.dex_run_luau = function(args)
			local source = text(args.source, "source", 65536)
			local vmKey = args.vmKey or "default"
			local vm = args.vm
			assert(type(vmKey) == "string" and #vmKey <= 96, "INVALID_ARGUMENT: invalid script scope")
			assert(vm == nil or vm == "persistent" or vm == "reset", "INVALID_ARGUMENT: invalid script mode")
			if vm == "reset" then
				for _, run in runs do
					assert(run.Status ~= "running" or run.VmKey ~= vmKey, "BUSY: persistent script is already running")
				end
				scriptEnvironments[vmKey] = nil
				return { status = "completed", returns = { '{"value":{"reset":true}}' }, output = {} }
			end
			assert(type(env.loadstring) == "function", "UNSUPPORTED: executor loadstring unavailable")
			local active = 0
			for _, run in pairs(runs) do
				if run.Status == "running" then
					active += 1
				end
			end
			assert(active < 2, "RUN_LIMIT: at most two concurrent runs")
			if vm == "persistent" then
				for _, run in runs do
					assert(run.Status ~= "running" or run.VmKey ~= vmKey, "BUSY: persistent script is already running")
				end
				if not scriptEnvironments[vmKey] then
					local count = 0
					for _ in scriptEnvironments do
						count += 1
					end
					assert(count < 8, "RUN_LIMIT: too many persistent script scopes")
					scriptEnvironments[vmKey] = setmetatable({}, { __index = getfenv(0) })
				end
			end
			runCounter += 1
			local id = "r" .. runCounter
			local factory, problem = env.loadstring(
				"return function(dex, print, warn)\n" .. source .. "\nend",
				"@DexExplorer/AIBridge/" .. id
			)
			assert(type(factory) == "function", "COMPILE_ERROR: " .. tostring(problem))
			local chunk = factory()
			local run = {
				Id = id,
				Status = "running",
				Output = {},
				Dropped = 0,
				Started = os.clock(),
				VmKey = if vm == "persistent" then vmKey else nil,
			}
			runs[id] = run
			runOrder[#runOrder + 1] = id
			if #runOrder > 20 then
				local expired = table.remove(runOrder, 1)
				if runs[expired].Status ~= "running" then
					runs[expired] = nil
				else
					runOrder[#runOrder + 1] = expired
				end
			end
			local function output(level, ...)
				if run.Status ~= "running" then
					return
				end
				local values = table.pack(...)
				local strings = {}
				for index = 1, math.min(values.n, 16) do
					strings[index] = string.sub(tostring(values[index]), 1, 1024)
				end
				if #run.Output >= 100 then
					run.Dropped += 1
					return
				end
				local line = string.sub(table.concat(strings, "\t"), 1, 2048)
				run.OutputBytes = (run.OutputBytes or 0) + #line
				if run.OutputBytes > 32768 then
					run.Dropped += 1
					return
				end
				run.Output[#run.Output + 1] = { level = level, text = line }
			end
			run.Thread = task.spawn(function()
				local context = {
					get = function(instanceId)
						return registry:Resolve(instanceId)
					end,
				}
				context.teach = teachState
				context.vm = if vm == "persistent" then scriptEnvironments[vmKey] else nil
				local result = table.pack(pcall(chunk, context, function(...)
					output("print", ...)
				end, function(...)
					output("warn", ...)
				end))
				if destroyed or run.Status ~= "running" then
					return
				end
				run.Duration = os.clock() - run.Started
				if not result[1] then
					run.Status = "failed"
					run.Error = string.sub(tostring(result[2]), 1, 4096)
					return
				end
				local values = {}
				local ok, issue = pcall(function()
					assert(result.n <= 257, "VALUE_LIMIT: too many return values")
					local packed = {}
					for index = 2, result.n do
						packed[index - 1] = result[index] == nil and { type = "nil" } or result[index]
					end
					values = codec:Encode(packed)
				end)
				if ok then
					run.Returns = values
					run.ReturnCount = result.n - 1
					run.Status = "completed"
				else
					run.Status = "failed"
					run.Error = tostring(issue)
				end
			end)
			return runResult(run)
		end
		handlers.dex_get_run = function(args)
			local run = runs[text(args.runId, "runId", 32)]
			assert(run, "RUN_UNAVAILABLE: unknown run")
			return runResult(run)
		end
		handlers.dex_cancel_run = function(args)
			local run = runs[text(args.runId, "runId", 32)]
			assert(run, "RUN_UNAVAILABLE: unknown run")
			if run.Status == "running" then
				assert(
					type(task.cancel) == "function" and run.Thread,
					"CANNOT_CANCEL: executor cannot cancel this owned thread"
				)
				local ok, why = pcall(task.cancel, run.Thread)
				assert(ok, "CANNOT_CANCEL: " .. tostring(why))
				run.Status = "cancelled"
				run.Duration = os.clock() - run.Started
			end
			return runResult(run)
		end
		local extras = Apps.BridgeExtraCommands
			and Apps.BridgeExtraCommands.Create({
				Apps = Apps,
				Main = Main,
				service = service,
				env = env,
				Game = root,
				Registry = registry,
				Codec = codec,
				Targets = targets,
				Editable = editable,
				RunLuau = handlers.dex_run_luau,
				SetProperties = setProperties,
				Changed = changed,
			})
		if extras then
			for _, command in ipairs(extras.Commands) do
				assert(not handlers[command.Name], "Duplicate bridge command")
				handlers[command.Name] = command.Run
				access[command.Name] = command.Grant
			end
		end
		local remoteCommands = Apps.BridgeRemoteCommands
			and Apps.BridgeRemoteCommands.Create({
				Apps = Apps,
				Main = Main,
				service = service,
				env = env,
				Game = root,
				Registry = registry,
				Codec = codec,
				Handlers = handlers,
			})
		if remoteCommands then
			for _, command in ipairs(remoteCommands.Commands) do
				assert(not handlers[command.Name], "Duplicate bridge command")
				handlers[command.Name] = command.Run
				access[command.Name] = command.Grant
			end
		end
		local captures = Apps.BridgeCaptureCommands
			and Apps.BridgeCaptureCommands.Create({
				Apps = Apps,
				Main = Main,
				service = service,
				env = env,
				Game = root,
				Registry = registry,
				Codec = codec,
				Handlers = handlers,
				StartJob = extras and extras.StartJob,
			})
		if captures then
			for _, command in ipairs(captures.Commands) do
				assert(not handlers[command.Name], "Duplicate bridge command")
				handlers[command.Name] = command.Run
				access[command.Name] = command.Grant
			end
		end
		local logs = Apps.BridgeLogCommands and Apps.BridgeLogCommands.Create({ service = service, Game = root })
		if logs then
			for _, command in ipairs(logs.Commands) do
				assert(not handlers[command.Name], "Duplicate bridge command")
				handlers[command.Name] = command.Run
				access[command.Name] = command.Grant
			end
		end
		local inspections = {}
		for _, module in ipairs({
			"BridgeQueryCommands",
			"BridgeSpatialCommands",
			"BridgeInspectionCommands",
			"BridgeComparisonCommands",
			"BridgeUIDiagnostics",
			"BridgeRuntimeDiagnostics",
			"BridgeTestCommands",
		}) do
			if Apps[module] then
				local adapter = Apps[module].Create({
					Apps = Apps,
					Main = Main,
					service = service,
					env = env,
					Game = root,
					Registry = registry,
					Codec = codec,
					Handlers = handlers,
					StartJob = extras and extras.StartJob,
					Read = function(name, args)
						return router:Execute(name, args, { inspect = true, edit = false, execute = false })
					end,
				})
				inspections[#inspections + 1] = adapter
				for _, command in ipairs(adapter.Commands) do
					assert(not handlers[command.Name], "Duplicate bridge command")
					handlers[command.Name] = command.Run
					access[command.Name] = command.Grant
				end
			end
		end
		function router:Capabilities()
			local list = {}
			for name, grant in pairs(access) do
				if handlers[name] then
					list[#list + 1] = { name = name, grant = grant }
				end
			end
			table.sort(list, function(a, b)
				return a.name < b.name
			end)
			return {
				protocol = 1,
				scope = "client",
				commands = list,
				loadstring = type(env.loadstring) == "function",
				hardExecutionTimeout = false,
				limits = {
					targets = 100,
					treeNodes = 5000,
					pageSize = 200,
					sourceBytes = 65536,
					captures = 8,
					captureBytes = 8 * 1024 * 1024,
					totalCaptureBytes = 16 * 1024 * 1024,
					captureNodes = 5000,
					captureSourceBytes = 2 * 1024 * 1024,
					analysisJobs = 8,
					logEntries = 512,
					logBytes = 262144,
					logMessageBytes = 4096,
					logPageMessageBytes = 24576,
				},
			}
		end
		function router:Execute(name, args, grants)
			assert(not destroyed, "DISCONNECTED: bridge session ended")
			assert(type(name) == "string" and handlers[name], "UNKNOWN_COMMAND: unsupported bridge command")
			assert(
				not (options.DisabledTools and options.DisabledTools[name]),
				"COMMAND_DISABLED: Command is disabled in Dex MCP"
			)
			assert(
				type(args) == "table" and type(grants) == "table" and grants.inspect == true,
				"PERMISSION_DENIED: Inspect access required"
			)
			local permission = access[name]
			assert(
				permission == "inspect" or grants[permission] == true,
				"PERMISSION_DENIED: " .. permission .. " access required"
			)
			local mutation = permission ~= "inspect"
			if mutation then
				assert(not busy, "BUSY: another AI mutation is active")
				local tools = Apps.TransformTools
				assert(
					not (tools and (tools.Dragging or tools.GuiDragging)),
					"BUSY: finish the active transform gesture first"
				)
				busy = true
			end
			local result = table.pack(pcall(handlers[name], args))
			if mutation then
				busy = false
			end
			if not result[1] then
				error(result[2], 0)
			end
			return result[2]
		end
		function router:Destroy()
			if destroyed then
				return
			end
			destroyed = true
			table.clear(scriptEnvironments)
			local teach = teachState.State
			if type(teach) == "table" and type(teach.sessions) == "table" then
				for _, session in teach.sessions do
					session.active = false
					for _, connection in session.connections or {} do
						pcall(function()
							connection:Disconnect()
						end)
					end
				end
			end
			table.clear(teachState)

			for _, run in pairs(runs) do
				if run.Status == "running" and type(task.cancel) == "function" and run.Thread then
					pcall(task.cancel, run.Thread)
					run.Status = "cancelled"
				end
			end
			for _, adapter in ipairs(inspections) do
				adapter:Destroy()
			end
			if logs then
				logs:Destroy()
			end
			if captures then
				captures:Destroy()
			end
			if remoteCommands then
				remoteCommands:Destroy()
			end
			if extras then
				extras:Destroy()
			end
			registry:Destroy()
			table.clear(pages)
			table.clear(runs)
		end
		return router
	end
	return Router
end
return { Main = Main }
