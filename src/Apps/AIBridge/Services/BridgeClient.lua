--!strict

local Apps, Main, service, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, service, env = d.Apps, d.Main, d.service, d.env or {}
end

------------------------------ Module ------------------------------

local function CreateModule()
	local Transport = { Protocol = 1 }
	local authorizationError = "Connection code expired or access was denied"

	function Transport.ParseCode(code)
		if type(code) ~= "string" then
			return nil
		end

		local port, token = code:match("^%s*(%d+)%.([%w_%-]+)%s*$")

		port = tonumber(port)

		if not port or port < 1024 or port > 65535 or not token or #token < 20 or #token > 128 then
			return nil
		end

		return "http://127.0.0.1:" .. port, token
	end

	function Transport.Create(options)
		options = options or {}

		local json = options.Http or service.HttpService

		local send = options.Request
			or env.request
			or request
			or http_request
			or (syn and syn.request)
			or (http and http.request)

		local sockets = options.WebSocket or env.WebSocket or WebSocket or websocket or (syn and syn.websocket)

		local connect = sockets and (sockets.connect or sockets.new)

		local disabledTools = options.DisabledTools or {}
		local routerFactory = options.Router
			or function()
				return Apps.BridgeCommandRouter.Create({
					Apps = Apps,
					Main = Main,
					service = service,
					env = env,
					DisabledTools = disabledTools,
				})
			end

		local spawn = options.Spawn or task.spawn
		local delay = options.Delay or task.delay

		local self = {
			State = "Disconnected",
			Grants = { inspect = true, edit = false, execute = false },
			Recent = {},
			Completed = 0,
			Failed = 0,
			Generation = 0,
			Paused = false,
			Destroyed = false,
			DisabledTools = disabledTools,
			CommandCatalog = options.CommandCatalog or {},
		}

		local socket, links, router, base, agentToken, sessionId, expiresAt = nil, {}, nil, nil, nil, nil, nil

		local ledger, order, queue, pending = {}, {}, {}, {}
		local processing = false
		local socketEpoch = 0
		local retry = 0

		local openSocket
		local failedHandshakes = 0
		local policyRevision = 0
		local activityById = {}
		local activeHostIds, activeHostNames = {}, {}

		local function notify()
			if options.OnChanged then
				pcall(options.OnChanged, self)
			end
		end

		local function grants(value)
			return {
				inspect = true,
				edit = value and value.edit == true or false,
				execute = value and value.execute == true or false,
			}
		end

		local function closeSocket()
			socketEpoch += 1
			self.ToolControls = false
			self.PolicyPending = nil
			table.clear(activeHostIds)
			table.clear(activeHostNames)
			self.ActiveHostCommand = nil
			for id, entry in pairs(activityById) do
				if entry.Status == "running" then
					entry.Status = "failed"
					entry.Error = "Connection closed. Result unknown."
					self.ActivityVersion = (self.ActivityVersion or 0) + 1
					activityById[id] = nil
				end
			end

			for _, link in ipairs(links) do
				link:Disconnect()
			end
			table.clear(links)

			local old = socket
			socket = nil
			if old then
				pcall(old.Close, old)
			end
		end

		local function encode(value)
			local data = json:JSONEncode(value)

			assert(#data <= 262144, "Bridge response exceeded its size limit")
			return data
		end

		local function requestJson(url, method, token, body)
			assert(type(send) == "function", "Executor HTTP requests are unavailable")

			local sent, response = pcall(send, {
				Url = url,
				Method = method,
				Headers = { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" },
				Body = body and json:JSONEncode(body) or nil,
			})

			if not sent or type(response) ~= "table" then
				error("Could not reach Dex MCP", 0)
			end

			local status = response.StatusCode or response.Status

			if status == 401 or status == 403 then
				error(authorizationError, 0)
			end

			assert(
				type(status) == "number" and status >= 200 and status < 300,
				"Dex MCP request failed (" .. tostring(status) .. ")"
			)

			if status == 204 then
				return {}
			end

			assert(type(response.Body) == "string" and #response.Body <= 65536, "Invalid Dex MCP response")

			return json:JSONDecode(response.Body)
		end

		local function write(value, expected)
			if not socket or expected ~= socketEpoch then
				return false
			end

			local ok = pcall(function()
				socket:Send(encode(value))
			end)
			return ok
		end

		local function preview(value)
			local remaining, items = 16000, 0
			local chunks, seen = {}, {}

			local function put(text)
				if remaining <= 0 then
					return
				end

				if #text > remaining then
					text = text:sub(1, remaining) .. "… [preview truncated]"
				end

				chunks[#chunks + 1] = text
				remaining -= #text
			end

			local function visit(item, depth)
				if remaining <= 0 then
					return
				end

				local kind = type(item)

				if kind == "string" then
					put(string.format("%q", item:sub(1, 16000)))
					if #item > 16000 then
						put(" [string truncated]")
					end
				elseif kind ~= "table" then
					put(tostring(item))
				elseif seen[item] then
					put("[circular]")
				elseif depth >= 6 then
					put("[nested value omitted]")
				else
					seen[item] = true
					put("{\n")

					local keys = {}
					for key in pairs(item) do
						keys[#keys + 1] = key
						if #keys >= 129 then
							break
						end
					end

					table.sort(keys, function(a, b)
						return tostring(a) < tostring(b)
					end)

					for _, key in ipairs(keys) do
						items += 1
						if items > 128 then
							put("… [items omitted]\n")
							break
						end

						put(string.rep("  ", depth + 1) .. tostring(key) .. " = ")

						local normalized = tostring(key):lower():gsub("[_%-]", "")

						if
							normalized:find("token", 1, true)
							or normalized:find("password", 1, true)
							or normalized:find("secret", 1, true)
							or normalized == "authorization"
							or normalized == "apikey"
							or normalized == "pairingcode"
						then
							put("[redacted]")
						else
							visit(item[key], depth + 1)
						end

						put(",\n")
						if remaining <= 0 then
							break
						end
					end

					put(string.rep("  ", depth) .. "}")
					seen[item] = nil
				end
			end

			visit(value, 0)
			return table.concat(chunks)
		end

		local function recent(command, result, elapsed, requestText)
			if result.ok then
				self.Completed += 1
			else
				self.Failed += 1
			end

			self.ActiveCommand = nil

			self.Recent[#self.Recent + 1] = {
				Name = command.name,
				CommandId = command.id,
				Ok = result.ok,
				Duration = elapsed,
				Error = result.error and result.error.message,
				RequestText = requestText,
				ResultText = preview(result.ok and { result = result.result } or result.error),
				TimeLabel = os.date("%H:%M:%S"),
			}

			if #self.Recent > 60 then
				table.remove(self.Recent, 1)
			end
			notify()
		end

		local function recordActivity(message)
			local id, name, state = message.id, message.name, message.state
			if
				type(id) ~= "string"
				or #id > 100
				or type(name) ~= "string"
				or #name > 105
				or not (state == "running" or state == "completed" or state == "failed" or state == "blocked")
			then
				return
			end
			local activeIndex = table.find(activeHostIds, id)
			if state == "running" then
				if not activeIndex then
					if #activeHostIds == 64 then
						activeHostNames[table.remove(activeHostIds, 1)] = nil
					end
					table.insert(activeHostIds, id)
					activeHostNames[id] = name
				end
			elseif activeIndex then
				table.remove(activeHostIds, activeIndex)
				activeHostNames[id] = nil
			end
			self.ActiveHostCommand = activeHostNames[activeHostIds[#activeHostIds]]
			local entry = activityById[id]
			if not entry then
				entry = {
					Id = id,
					Name = name,
					TimeLabel = os.date(
						"%H:%M:%S",
						type(message.time) == "number" and math.floor(message.time / 1000) or os.time()
					),
				}
				activityById[id] = entry
				table.insert(self.Recent, entry)
				if #self.Recent > 60 then
					local removed = table.remove(self.Recent, 1)
					if removed.Id then
						activityById[removed.Id] = nil
					end
				end
			end
			entry.Status = state
			entry.Ok = state == "completed"
			entry.CommandId = type(message.commandId) == "string" and message.commandId or nil
			entry.Duration = type(message.duration) == "number" and message.duration / 1000 or nil
			entry.RequestText = type(message.request) == "string" and message.request or entry.RequestText
			entry.ResultText = type(message.result) == "string" and message.result or nil
			entry.Error = type(message.error) == "string" and message.error or nil
			self.ActivityVersion = (self.ActivityVersion or 0) + 1
			notify()
		end

		local function disabledNames()
			local names = {}
			for name, disabled in pairs(self.DisabledTools) do
				if disabled == true and type(name) == "string" and #name <= 104 and name:match("^dex_[a-z0-9_]+$") then
					names[#names + 1] = name
				end
			end
			table.sort(names)
			return names
		end

		function self:SyncToolPolicy()
			if self.ToolControls and self.State == "Connected" then
				policyRevision += 1
				self.PolicyPending = policyRevision
				if
					not write({
						type = "tool_policy",
						revision = policyRevision,
						disabledTools = disabledNames(),
						paused = self.Paused,
					}, socketEpoch)
				then
					self.PolicyPending = nil
					self.Error = "Command settings didn't sync. Reconnect to retry."
					self:Disconnect()
				end
			end
			notify()
		end

		local function responseError(id, code, message)
			return { type = "result", id = id, ok = false, error = { code = code, message = message } }
		end

		local function process()
			if processing then
				return
			end
			processing = true

			spawn(function()
				while not self.Destroyed and #queue > 0 do
					local item = table.remove(queue, 1)
					local command = item.Command
					local generation = self.Generation

					self.ActiveCommand = command.name
					notify()

					local started = os.clock()
					local requestText = not self.ToolControls and preview(command.args or {}) or nil
					local result

					if generation ~= item.Generation then
						pending[command.id] = nil
						continue
					end

					if self.Paused then
						result = responseError(command.id, "PAUSED", "AI control is paused in Dex")
					elseif self.DisabledTools[command.name] then
						result = responseError(command.id, "COMMAND_DISABLED", "Command is disabled in Dex MCP")
					elseif type(command.deadline) == "number" and command.deadline < os.time() * 1000 then
						result = responseError(command.id, "EXPIRED", "Command deadline elapsed")
					else
						local ok, value =
							pcall(router.Execute, router, command.name, command.args or {}, table.clone(self.Grants))

						if ok then
							result = { type = "result", id = command.id, ok = true, result = value }
						else
							local message = tostring(value):sub(1, 500)
							local code, description = message:match("^([A-Z][A-Z0-9_]+): (.*)$")
							if not code then
								code, description = message:match("^[^\r\n]-:%d+: ([A-Z][A-Z0-9_]+): (.*)$")
							end
							result = responseError(command.id, code or "COMMAND_FAILED", description or message)
						end
					end

					if generation == self.Generation and not self.Destroyed then
						local valid = pcall(encode, result)

						if not valid then
							result = responseError(
								command.id,
								"RESULT_TOO_LARGE",
								"Result could not be serialized within the bridge limit"
							)
						end

						ledger[command.id] = result
						order[#order + 1] = command.id
						pending[command.id] = nil

						if #order > 128 then
							ledger[table.remove(order, 1)] = nil
						end

						write(result, item.Epoch)
						if self.ToolControls then
							if result.ok then
								self.Completed += 1
							else
								self.Failed += 1
							end
							self.ActiveCommand = nil
							notify()
						else
							recent(command, result, os.clock() - started, requestText)
						end
					end
				end

				processing = false
			end)
		end

		local function receive(data, epoch)
			if self.Destroyed or epoch ~= socketEpoch or type(data) ~= "string" or #data > 262144 then
				return
			end

			local ok, message = pcall(json.JSONDecode, json, data)

			if not ok or type(message) ~= "table" then
				return
			end

			if message.type == "ready" then
				self.State = "Connected"
				self.Error = nil
				retry = 0
				failedHandshakes = 0
				self.ToolControls = type(message.tools) == "table" and #message.tools > 0
				if self.ToolControls then
					self.CommandCatalog = message.tools
					self:SyncToolPolicy()
				end
				notify()
				return
			end
			if message.type == "tool_policy_ack" and self.ToolControls then
				if self.PolicyPending == message.revision then
					self.PolicyPending = nil
					notify()
				end
				return
			end
			if message.type == "tool_activity" and self.ToolControls then
				recordActivity(message)
				return
			end

			if message.type == "ping" then
				write({ type = "pong" }, epoch)
				return
			end

			if message.type == "error" then
				self.Error = "Connection rejected. Get a new pairing code."

				self:Disconnect()
				return
			end

			if message.type ~= "command" or self.State ~= "Connected" then
				return
			end

			if
				type(message.id) ~= "string"
				or #message.id > 128
				or type(message.name) ~= "string"
				or type(message.args or {}) ~= "table"
			then
				return
			end

			if message.sessionId and message.sessionId ~= sessionId then
				return
			end

			if ledger[message.id] then
				write(ledger[message.id], epoch)
				return
			end

			if pending[message.id] then
				return
			end

			if #queue >= 32 then
				write(responseError(message.id, "BUSY", "Dex command queue is full"), epoch)
				return
			end

			pending[message.id] = true
			queue[#queue + 1] = { Command = message, Epoch = epoch, Generation = self.Generation }
			process()
		end

		openSocket = function(generation)
			if self.Destroyed or generation ~= self.Generation or not agentToken then
				return
			end

			closeSocket()
			local epoch = socketEpoch

			self.State = retry > 0 and "Reconnecting" or "Connecting"
			notify()

			local ok, opened = pcall(function()
				local response = requestJson(base .. "/bridge/ticket", "POST", agentToken, {})

				assert(
					type(response.ticket) == "string" and response.ticket:match("^[%w_%-]+$"),
					"Invalid connection ticket"
				)

				return connect(base:gsub("^http:", "ws:") .. "/bridge/ws?ticket=" .. response.ticket)
			end)

			if self.Destroyed or generation ~= self.Generation then
				if ok and opened then
					pcall(opened.Close, opened)
				end
				return
			end

			if not ok and opened == authorizationError then
				self.Error = "Connection expired. Get a new pairing code."
				self:Disconnect()
				return false
			end

			if not ok or not opened then
				retry += 1
				self.Error = "Dex MCP unavailable"
				self.State = "Reconnecting"
				notify()

				delay(math.min(2 ^ (math.min(retry, 4) - 1), 15), function()
					openSocket(generation)
				end)
				return
			end

			socket = opened

			links[#links + 1] = socket.OnMessage:Connect(function(data)
				receive(data, epoch)
			end)

			links[#links + 1] = socket.OnClose:Connect(function()
				if self.Destroyed or generation ~= self.Generation or epoch ~= socketEpoch then
					return
				end

				if self.State ~= "Connected" then
					failedHandshakes += 1
				end

				if failedHandshakes >= 3 then
					self.Error = "Connection expired. Get a new pairing code."

					self:Disconnect()
					return
				end

				closeSocket()

				for _, item in ipairs(queue) do
					pending[item.Command.id] = nil
				end
				table.clear(queue)

				retry += 1
				self.State = "Reconnecting"
				self.Error = "Dex MCP disconnected"
				notify()

				delay(math.min(2 ^ (math.min(retry, 4) - 1), 15), function()
					openSocket(generation)
				end)
			end)

			if
				not write({
					type = "hello",
					version = 1,
					sessionId = sessionId,
					token = agentToken,
					capabilities = router:Capabilities(),
					toolControls = true,
					disabledTools = disabledNames(),
					paused = self.Paused,
				}, epoch)
			then
				self.Error = "Could not authenticate the connection"
				self:Disconnect()
				return false
			end

			delay(10, function()
				if generation == self.Generation and epoch == socketEpoch and self.State ~= "Connected" then
					self.Error = "Dex MCP handshake timed out"
					self:Disconnect()
					notify()
				end
			end)
		end

		function self:Connect(code, requestedGrants)
			assert(not self.Destroyed, "Bridge has been closed")

			assert(
				type(send) == "function" and type(connect) == "function",
				"This executor needs HTTP request and WebSocket support"
			)

			local nextBase, token = Transport.ParseCode(code)

			assert(nextBase, "Paste the full pairing code")

			self:Disconnect()
			self.Generation += 1
			local generation = self.Generation

			self.State = "Connecting"
			self.Error = nil
			self.Paused = false
			self.Grants = grants(requestedGrants)
			notify()

			local player = service.Players.LocalPlayer

			local metadata = {
				placeId = game.PlaceId,
				jobId = game.JobId,
				userId = player.UserId,
				displayName = player.DisplayName or player.Name,
				release = Main.Version,
			}

			local ok, result = pcall(
				requestJson,
				nextBase .. "/bridge/sessions",
				"POST",
				token,
				{ grants = self.Grants, info = metadata }
			)

			if generation ~= self.Generation or self.Destroyed then
				if ok and type(result) == "table" and type(result.agentToken) == "string" then
					pcall(requestJson, nextBase .. "/bridge/session", "DELETE", result.agentToken)
				end

				return false, "Connection cancelled"
			end

			if not ok then
				self.State = "Disconnected"
				self.Error = tostring(result):sub(1, 180)
				notify()
				return false, self.Error
			end

			if type(result) ~= "table" or type(result.sessionId) ~= "string" or type(result.agentToken) ~= "string" then
				self.State = "Disconnected"
				self.Error = "Invalid Dex MCP session"
				notify()
				return false, self.Error
			end

			base, agentToken, sessionId, expiresAt = nextBase, result.agentToken, result.sessionId, result.expiresAt
			self.SessionId = sessionId

			local created, nextRouter = pcall(routerFactory)

			if not created or type(nextRouter) ~= "table" then
				self.Error = "Could not start the command service"
				self:Disconnect()
				return false, self.Error
			end

			router = nextRouter
			table.clear(ledger)
			table.clear(order)
			retry = 0
			failedHandshakes = 0
			if openSocket(generation) == false then
				return false, self.Error
			end
			return true
		end

		function self:SetGrants(value)
			local target = grants(value)
			local previous = self.Grants
			local generation = self.Generation

			self.Grants = {
				inspect = true,
				edit = previous.edit and target.edit,
				execute = previous.execute and target.execute,
			}

			self.PendingGrants = target
			notify()

			if self.UpdatingGrants then
				return false
			end

			self.UpdatingGrants = true
			local success = true

			repeat
				target = self.PendingGrants
				self.PendingGrants = nil

				local ok = not agentToken
					or pcall(requestJson, base .. "/bridge/session", "PATCH", agentToken, { grants = target })

				if generation ~= self.Generation then
					return false
				end

				if ok then
					if not self.PendingGrants then
						self.Grants = target
					end
				else
					success = false
					self.Error = "Could not update access."
				end

				notify()

			until not self.PendingGrants

			self.UpdatingGrants = false
			return success
		end

		function self:SetPaused(paused)
			self.Paused = paused == true
			self:SyncToolPolicy()
		end

		function self:Disconnect()
			self.Generation += 1
			closeSocket()

			local url, token = base, agentToken
			base, agentToken, sessionId, expiresAt = nil, nil, nil, nil
			self.SessionId = nil

			table.clear(queue)
			table.clear(pending)
			table.clear(ledger)
			table.clear(order)
			self.PendingGrants = nil
			self.UpdatingGrants = false

			if router then
				router:Destroy()
				router = nil
			end

			if url and token then
				spawn(function()
					pcall(requestJson, url .. "/bridge/session", "DELETE", token)
				end)
			end

			self.State = "Disconnected"
			self.Paused = false
			self.ActiveCommand = nil
			notify()
		end

		function self:Destroy()
			if self.Destroyed then
				return
			end
			self:Disconnect()
			self.Destroyed = true
		end

		function self:GetSummary()
			return {
				SessionId = sessionId,
				Port = base and tonumber(base:match(":(%d+)$")) or nil,
				Completed = self.Completed,
				Failed = self.Failed,
				ActiveCommand = self.ActiveHostCommand or self.ActiveCommand,
				Queued = #queue,
			}
		end

		function self:ClearRecent()
			table.clear(self.Recent)
			table.clear(activityById)
			notify()
		end

		function self:Supported()
			return type(send) == "function" and type(connect) == "function"
		end

		return self
	end

	return Transport
end

return { InitDeps = InitDeps, Main = CreateModule }
