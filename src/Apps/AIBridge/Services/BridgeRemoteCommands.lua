--!strict

------------------------------ Module ------------------------------

local function Main()
	local Module = {}
	function Module.Create(c)
		local registry, codec, service = c.Registry, c.Codec, c.service
		local api = { Commands = {} }
		local calls, order, watches = {}, {}, {}
		local sequence = 0
		local destroyed = false
		local lastCall = setmetatable({}, { __mode = "k" })
		local remoteClasses = {
			RemoteEvent = "event",
			UnreliableRemoteEvent = "unreliable",
			RemoteFunction = "function",
			BindableEvent = "bindable_event",
			BindableFunction = "bindable_function",
		}
		local function add(name, grant, run)
			api.Commands[#api.Commands + 1] = { Name = "dex_" .. name, Grant = grant, Run = run }
		end
		local function nextId(prefix)
			sequence += 1
			return prefix .. sequence
		end
		local function integer(value, default, maximum)
			value = value or default
			assert(
				type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum,
				"INVALID_ARGUMENT: integer out of range"
			)
			return value
		end
		local function target(args, classes)
			local value = registry:Resolve(args.instanceId)
			assert(classes[value.ClassName], "INVALID_TARGET: incompatible remote or bindable class")
			assert(
				not (c.Apps.Explorer.IsInferredObject and c.Apps.Explorer.IsInferredObject(value)),
				"INFERRED_READ_ONLY: reconstructed entries cannot receive calls"
			)
			return value
		end
		local function summary(value)
			local kind = remoteClasses[value.ClassName]
			local path
			pcall(function()
				path = value:GetFullName()
			end)
			return {
				instance = registry:Describe(value),
				path = path and path:sub(1, 1500),
				kind = kind,
				operation = value.ClassName == "RemoteFunction" and "InvokeServer"
					or value.ClassName == "BindableFunction" and "Invoke"
					or value.ClassName == "BindableEvent" and "Fire"
					or "FireServer",
				argumentSchema = "Unknown; use the game's documented contract or inspect readable callers",
				scope = kind and kind:find("bindable", 1, true) and "client" or "client_to_server",
				reversible = false,
			}
		end
		local function decodeArguments(args)
			local source = args.arguments or {}
			assert(type(source) == "table" and #source <= 64, "VALUE_LIMIT: at most 64 arguments")
			local result = { n = #source }
			for index = 1, #source do
				result[index] = codec:Decode(source[index])
			end
			return result
		end
		local function packValues(values, first)
			assert(values.n - first + 1 <= 128, "VALUE_LIMIT: too many returned values")
			local result = {}
			for index = first, values.n do
				result[index - first + 1] = values[index] == nil and { type = "nil" } or values[index]
			end
			return codec:Encode(result), values.n - first + 1
		end
		local function boundedPayload(value, maximum)
			local bytes = 0
			local count = 0
			local function visit(item)
				count += 1
				assert(count <= 4096, "VALUE_LIMIT: too many result values")
				if type(item) == "string" then
					bytes += #item + 2
				elseif type(item) == "table" then
					for key, child in pairs(item) do
						bytes += type(key) == "string" and #key + 4 or 16
						visit(child)
					end
				else
					bytes += 24
				end
				assert(bytes <= maximum, "VALUE_LIMIT: result exceeds its retained byte budget")
			end
			visit(value)
			return value
		end
		local function callSummary(value, withResults)
			return {
				callId = value.Id,
				instanceId = value.InstanceId,
				operation = value.Operation,
				status = value.Status,
				scope = value.Scope,
				returnCount = value.ReturnCount,
				returns = withResults ~= false and value.Returns or nil,
				error = value.Error,
				resultError = value.ResultError,
				slow = value.Slow or false,
				duration = (value.Finished or os.clock()) - value.Started,
				serverAcknowledged = false,
				serverResponded = value.Operation == "InvokeServer" and value.Status == "returned",
			}
		end
		local function newCall(value, operation)
			local active = 0
			for _, item in pairs(calls) do
				if item.Status == "pending" then
					active += 1
				end
			end
			if operation == "InvokeServer" or operation == "Invoke" then
				assert(
					active < 4,
					"PENDING_CALL_LIMIT: four calls are still pending; inspect results instead of starting more"
				)
			end
			local now = os.clock()
			assert(
				not lastCall[value] or now - lastCall[value] >= 0.1,
				"CALL_RATE_LIMIT: wait briefly before calling this instance again"
			)
			lastCall[value] = now
			while #order >= 32 do
				local removed = false
				for index, key in ipairs(order) do
					if calls[key].Status ~= "pending" then
						calls[key] = nil
						table.remove(order, index)
						removed = true
						break
					end
				end
				assert(removed, "PENDING_CALL_LIMIT: retained calls are still pending")
			end
			local call = {
				Id = nextId("call"),
				InstanceId = registry:Id(value),
				Operation = operation,
				Status = "pending",
				Started = now,
				Scope = value.ClassName:find("Bindable", 1, true) and "client" or "client_to_server",
			}
			calls[call.Id] = call
			order[#order + 1] = call.Id
			return call
		end
		local function fire(args, classes, operation)
			local value = target(args, classes)
			local values = decodeArguments(args)
			local call = newCall(value, operation)
			local ok, why = pcall(function()
				value[operation](value, table.unpack(values, 1, values.n))
			end)
			call.Finished = os.clock()
			call.Status = ok and "sent" or "failed"
			call.Error = not ok and tostring(why):sub(1, 2000) or nil
			return callSummary(call)
		end
		local function invoke(args, classes, operation)
			local value = target(args, classes)
			local values = decodeArguments(args)
			local call = newCall(value, operation)
			call.Thread = task.spawn(function()
				local returned = table.pack(pcall(function()
					return value[operation](value, table.unpack(values, 1, values.n))
				end))
				if destroyed then
					return
				end
				call.Finished = os.clock()
				if not returned[1] then
					call.Status = "failed"
					call.Error = tostring(returned[2]):sub(1, 2000)
					return
				end
				call.Status = "returned"
				local ok, result, count = pcall(packValues, returned, 2)
				call.ReturnCount = returned.n - 1
				if ok then
					local bounded, issue = pcall(boundedPayload, result, 32768)
					if bounded then
						call.Returns = result
					else
						call.ResultError = tostring(issue):sub(1, 1000)
					end
				else
					call.ResultError = tostring(result):sub(1, 1000)
				end
			end)
			task.delay(15, function()
				if not destroyed and call.Status == "pending" then
					call.Slow = true
				end
			end)
			return callSummary(call)
		end
		add("list_remotes", "inspect", function(args)
			local root = args.rootId and registry:Resolve(args.rootId) or c.Game
			local limit = integer(args.limit, 100, 200)
			local stack = { root }
			local visited = 0
			local rows = {}
			local truncated = false
			local started = os.clock()
			while #stack > 0 do
				local value = table.remove(stack)
				visited += 1
				if visited > 5000 then
					truncated = true
					break
				end
				if registry:Allowed(value) then
					if
						remoteClasses[value.ClassName]
						and (args.includeBindables ~= false or not value.ClassName:find("Bindable", 1, true))
						and (not args.name or value.Name:lower():find(args.name:lower(), 1, true))
					then
						if #rows >= limit then
							truncated = true
							break
						end
						rows[#rows + 1] = summary(value)
					end
					for _, child in ipairs(value:GetChildren()) do
						stack[#stack + 1] = child
					end
				end
				if os.clock() - started >= 0.002 then
					task.wait()
					assert(not destroyed, "DISCONNECTED")
					started = os.clock()
				end
			end
			return {
				items = rows,
				truncated = truncated,
				visited = visited,
				note = "Discovery does not invoke or probe any endpoint.",
			}
		end)
		add("get_remote_info", "inspect", function(args)
			return summary(target(args, remoteClasses))
		end)
		add("fire_remote", "execute", function(args)
			return fire(args, { RemoteEvent = true, UnreliableRemoteEvent = true }, "FireServer")
		end)
		add("invoke_remote", "execute", function(args)
			return invoke(args, { RemoteFunction = true }, "InvokeServer")
		end)
		add("fire_bindable", "execute", function(args)
			return fire(args, { BindableEvent = true }, "Fire")
		end)
		add("invoke_bindable", "execute", function(args)
			return invoke(args, { BindableFunction = true }, "Invoke")
		end)
		add("get_call", "inspect", function(args)
			local call = calls[args.callId]
			assert(call, "CALL_UNAVAILABLE: unknown or expired call")
			return callSummary(call)
		end)
		add("list_calls", "inspect", function()
			local result = {}
			for index = #order, 1, -1 do
				result[#result + 1] = callSummary(calls[order[index]], false)
			end
			return { calls = result }
		end)
		local function watchSummary(value)
			return {
				watchId = value.Id,
				instanceId = value.InstanceId,
				count = #value.Events,
				dropped = value.Dropped,
				scope = "incoming_client_event",
			}
		end
		add("watch_remote", "inspect", function(args)
			local count = 0
			for _ in pairs(watches) do
				count += 1
			end
			assert(count < 4, "WATCH_LIMIT: stop an incoming-event watch first")
			local value = target(args, { RemoteEvent = true, UnreliableRemoteEvent = true, BindableEvent = true })
			local watch = {
				Id = nextId("remoteWatch"),
				InstanceId = registry:Id(value),
				Events = {},
				Dropped = 0,
				Sequence = 0,
				Started = os.clock(),
				WindowStarted = os.clock(),
				WindowCount = 0,
			}
			watches[watch.Id] = watch
			local signal = value.ClassName == "BindableEvent" and value.Event or value.OnClientEvent
			local ok, connection = pcall(function()
				return signal:Connect(function(...)
					if destroyed then
						return
					end
					watch.Sequence += 1
					local now = os.clock()
					if now - watch.WindowStarted >= 1 then
						watch.WindowStarted = now
						watch.WindowCount = 0
					end
					watch.WindowCount += 1
					if watch.WindowCount > 20 then
						watch.Dropped += 1
						return
					end
					local packed = table.pack(...)
					local valid, values, n = pcall(packValues, packed, 1)
					if valid then
						local ok, why = pcall(boundedPayload, values, 2048)
						if not ok then
							valid = false
							values = tostring(why)
						end
					end
					local event = {
						id = watch.Sequence,
						time = os.clock() - watch.Started,
						arguments = valid and values or nil,
						argumentCount = valid and n or packed.n,
						error = not valid and tostring(values):sub(1, 500) or nil,
					}
					if #watch.Events >= 32 then
						table.remove(watch.Events, 1)
						watch.Dropped += 1
					end
					watch.Events[#watch.Events + 1] = event
				end)
			end)
			if not ok then
				watches[watch.Id] = nil
				error(connection, 0)
			end
			watch.Connection = connection
			return watchSummary(watch)
		end)
		add("get_remote_events", "inspect", function(args)
			local watch = watches[args.watchId]
			assert(watch, "WATCH_UNAVAILABLE")
			local limit = integer(args.limit, 25, 50)
			local after = args.afterId or 0
			assert(type(after) == "number" and after >= 0 and after % 1 == 0, "INVALID_ARGUMENT: afterId")
			local rows = {}
			local nextId = after
			for _, event in ipairs(watch.Events) do
				if event.id > after and #rows < limit then
					rows[#rows + 1] = event
					nextId = event.id
				end
			end
			return {
				events = rows,
				nextId = nextId,
				dropped = watch.Dropped,
				scope = "incoming_client_event",
				note = "Only subscribed incoming events are observed; outgoing calls from other scripts are not intercepted.",
			}
		end)
		add("stop_remote_watch", "inspect", function(args)
			local watch = watches[args.watchId]
			assert(watch, "WATCH_UNAVAILABLE")
			watch.Connection:Disconnect()
			watches[args.watchId] = nil
			return { stopped = true }
		end)
		add("list_remote_watches", "inspect", function()
			local result = {}
			for _, watch in pairs(watches) do
				result[#result + 1] = watchSummary(watch)
			end
			return { watches = result }
		end)
		local allowedBatch = {
			dex_set_properties = true,
			dex_set_attributes = true,
			dex_set_tags = true,
			dex_reparent_instances = true,
			dex_rename_instance = true,
			dex_set_pivot = true,
			dex_set_ui_layout = true,
		}
		add("apply_changes", "edit", function(args)
			assert(
				type(args.changes) == "table" and #args.changes > 0 and #args.changes <= 16,
				"WORK_LIMIT: batch requires 1 to 16 edits"
			)
			local work = 0
			for _, change in ipairs(args.changes) do
				assert(
					type(change) == "table" and allowedBatch[change.command] and type(change.args) == "table",
					"INVALID_COMMAND: batch allows only supported tracked object edits"
				)
				local values = change.args.properties or change.args.attributes or change.args.tags or { true }
				local width = 0
				for _ in pairs(values) do
					width += 1
				end
				work += math.max(1, #(change.args.instanceIds or {})) * math.max(1, width)
				assert(work <= 256, "WORK_LIMIT: batch may change at most 256 values")
			end
			c.Apps.History.Run("AI: apply change set", function()
				for _, change in ipairs(args.changes) do
					c.Handlers[change.command](change.args)
				end
			end)
			local h = c.Handlers.dex_get_history()
			return {
				applied = #args.changes,
				historyIndex = h.index,
				historyHead = h.head,
				scope = "client",
				reversible = true,
			}
		end)
		function api:Destroy()
			destroyed = true
			for _, watch in pairs(watches) do
				watch.Connection:Disconnect()
			end
			for _, call in pairs(calls) do
				if call.Status == "pending" and task.cancel and call.Thread then
					pcall(task.cancel, call.Thread)
				end
			end
			table.clear(watches)
			table.clear(calls)
			table.clear(order)
			table.clear(lastCall)
		end
		return api
	end
	return Module
end
return { Main = Main }
