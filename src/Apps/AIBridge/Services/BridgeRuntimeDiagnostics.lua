--!strict

------------------------------ Module ------------------------------

local function Main()
	local Diagnostics = {}
	local MAX_BYTES = 48 * 1024
	local function prefix(text, maximum)
		local length = math.min(#text, maximum)
		if length < #text then
			while length > 0 do
				local byte = text:byte(length + 1)
				if byte < 128 or byte >= 192 then
					break
				end
				length -= 1
			end
		end
		return text:sub(1, length)
	end
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local total = 2
		for key, item in pairs(value) do
			total += size(key) + size(item) + 2
		end
		return total
	end
	local function validate(args, allowed)
		assert(type(args) == "table", "INVALID_ARGUMENT: argument map required")
		for key in pairs(args) do
			assert(allowed[key], "INVALID_ARGUMENT: unsupported diagnostic argument")
		end
	end
	local function finite(value)
		assert(
			type(value) == "number" and value == value and math.abs(value) < math.huge and value >= 0,
			"UNAVAILABLE_VALUE: expected finite nonnegative number"
		)
		return value
	end
	function Diagnostics.Create(c)
		local registry, codec, service = c.Registry, c.Codec, c.service
		local dead = false
		local result = { Commands = {} }
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		local function alive()
			assert(not dead, "DISCONNECTED: diagnostic service ended")
		end
		local function snapshot(kind)
			alive()
			return {
				scope = "client",
				kind = kind,
				observedAt = DateTime and DateTime.now().UnixTimestampMillis or os.time() * 1000,
				timestampUnit = "unix_milliseconds",
				nonAtomic = true,
				truncated = false,
				resultByteLimit = MAX_BYTES,
				errors = {},
			}
		end
		local function put(out, target, key, value)
			if size(value) > 8192 or size(out) + size(key) + size(value) > MAX_BYTES - 2048 then
				out.truncated = true
				return false
			end
			target[key] = value
			return true
		end
		local function failure(out, target, key, why)
			return put(out, target, key, prefix(tostring(why), 160))
		end
		local function getService(out, name)
			local ok, value = pcall(function()
				return service[name] or (c.Game or game):GetService(name)
			end)
			if not ok or not value then
				failure(out, out.errors, name, ok and "service unavailable" or value)
				return nil
			end
			return value
		end
		local function identity(object)
			if not registry:Allowed(object) then
				return nil
			end
			local name = object.Name
			return {
				id = registry:Id(object),
				name = prefix(name, 256),
				nameTruncated = #name > 256,
				className = object.ClassName,
			}
		end
		local function encoded(raw)
			if typeof(raw) == "Instance" and not registry:Allowed(raw) then
				return { type = "UnavailableInstance" }
			end
			assert(type(raw) ~= "string" or #raw <= 2048, "UNAVAILABLE_VALUE: diagnostic string exceeds limit")
			local value = codec:Encode(raw)
			assert(
				not (type(value) == "table" and (value.type == "Unsupported" or value.type == "TruncatedString")),
				"UNAVAILABLE_VALUE: unsupported diagnostic value"
			)
			return value
		end
		local function call(out, values, errors, key, callback)
			local ok, value = pcall(function()
				return encoded(callback())
			end)
			if ok then
				if not put(out, values, key, value) then
					failure(out, errors, key, "RESULT_LIMIT: diagnostic value omitted")
				end
			else
				failure(out, errors, key, value)
			end
		end
		local function fields(out, object, keys)
			local row = { properties = {}, errors = {} }
			for _, key in ipairs(keys) do
				call(out, row.properties, row.errors, key, function()
					return object[key]
				end)
			end
			return row
		end
		local function finish(out)
			out.estimatedBytes = size(out) + 64
			return out
		end
		add("get_character_state", function(args)
			validate(args, { userId = true })
			local out = snapshot("character_state")
			if args.userId ~= nil then
				assert(
					type(args.userId) == "number"
						and args.userId % 1 == 0
						and args.userId >= 0
						and args.userId <= 9007199254740991,
					"INVALID_ARGUMENT: userId must be a nonnegative safe integer"
				)
			end
			local players = getService(out, "Players")
			if not players then
				out.available = false
				out.reason = "players_unavailable"
				return finish(out)
			end
			local ok, player = pcall(function()
				if args.userId ~= nil then
					return players:GetPlayerByUserId(args.userId)
				end
				return players.LocalPlayer
			end)
			if not ok or not player or not registry:Allowed(player) then
				out.available = false
				out.reason = "player_unavailable"
				if not ok then
					failure(out, out.errors, "player", player)
				end
				return finish(out)
			end
			out.player = identity(player)
			out.userId = player.UserId
			local character = player.Character
			if not character or not registry:Allowed(character) then
				out.available = false
				out.reason = "character_unavailable"
				return finish(out)
			end
			out.available = true
			out.character = identity(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root
			if humanoid and registry:Allowed(humanoid) then
				local row = fields(out, humanoid, {
					"Health",
					"MaxHealth",
					"MoveDirection",
					"FloorMaterial",
					"WalkSpeed",
					"UseJumpPower",
					"JumpPower",
					"JumpHeight",
					"AutoRotate",
					"Sit",
					"PlatformStand",
					"RigType",
					"RootPart",
				})
				row.instance = identity(humanoid)
				call(out, row.properties, row.errors, "State", function()
					return humanoid:GetState()
				end)
				put(out, out, "humanoid", row)
				local good, value = pcall(function()
					return humanoid.RootPart
				end)
				if good then
					root = value
				end
			else
				out.humanoid = { available = false }
			end
			if not root then
				root = character:FindFirstChild("HumanoidRootPart")
			end
			if root and root:IsA("BasePart") and registry:Allowed(root) then
				local row = fields(out, root, {
					"CFrame",
					"Position",
					"AssemblyLinearVelocity",
					"AssemblyAngularVelocity",
					"Anchored",
					"CanCollide",
					"CanQuery",
				})
				row.instance = identity(root)
				put(out, out, "rootPart", row)
			else
				out.rootPart = { available = false }
			end
			out.tools = {}
			out.toolLimit = 20
			out.examinedChildren = 0
			local function tools(parent, equipped)
				if not parent then
					return
				end
				local good, children = pcall(parent.GetChildren, parent)
				if not good then
					failure(out, out.errors, equipped and "equippedTools" or "backpackTools", children)
					return
				end
				for index = 1, math.min(#children, 256) do
					out.examinedChildren += 1
					local tool = children[index]
					if tool:IsA("Tool") and registry:Allowed(tool) then
						if #out.tools >= 20 then
							out.truncated = true
							return
						end
						local row = fields(out, tool, {
							"Enabled",
							"RequiresHandle",
							"CanBeDropped",
							"ManualActivationOnly",
							"TextureId",
							"ToolTip",
							"Grip",
						})
						row.instance = identity(tool)
						row.equipped = equipped
						if size(out) + size(row) > MAX_BYTES - 2048 then
							out.truncated = true
							return
						end
						out.tools[#out.tools + 1] = row
					end
				end
				if #children > 256 then
					out.truncated = true
				end
			end
			tools(character, true)
			tools(player:FindFirstChildOfClass("Backpack"), false)
			return finish(out)
		end)
		add("get_input_state", function(args)
			validate(args, {})
			local out = snapshot("input_state")
			local input = getService(out, "UserInputService")
			if not input then
				out.available = false
				return finish(out)
			end
			out.available = true
			out.capabilities = { properties = {}, errors = {} }
			out.pressedKeys = {}
			out.pressedKeyLimit = 64
			for _, key in ipairs({
				"KeyboardEnabled",
				"MouseEnabled",
				"GamepadEnabled",
				"TouchEnabled",
				"AccelerometerEnabled",
				"GyroscopeEnabled",
				"MouseIconEnabled",
				"MouseBehavior",
				"PreferredInput",
			}) do
				call(out, out.capabilities.properties, out.capabilities.errors, key, function()
					return input[key]
				end)
			end
			out.pointer = {
				properties = {},
				errors = {},
				coordinateSpace = "client_viewport_pixels",
				note = "Native GetMouseLocation does not account for GUI insets; position may be undetermined without an active mouse.",
			}
			call(out, out.pointer.properties, out.pointer.errors, "position", function()
				return input:GetMouseLocation()
			end)
			call(out, out.pointer.properties, out.pointer.errors, "lastInputType", function()
				return input:GetLastInputType()
			end)
			local ok, focused = pcall(input.GetFocusedTextBox, input)
			if not ok then
				failure(out, out.errors, "focusedTextBox", focused)
			elseif not focused then
				out.focusedTextBox = { type = "nil" }
			elseif registry:Allowed(focused) then
				out.focusedTextBox = identity(focused)
			else
				out.focusedTextBox = { available = false, reason = "outside_inspectable_game_ui" }
			end
			local good, keys = pcall(input.GetKeysPressed, input)
			if not good then
				failure(out, out.errors, "pressedKeys", keys)
			elseif type(keys) ~= "table" then
				failure(out, out.errors, "pressedKeys", "invalid engine result")
			else
				out.nativePressedKeys = #keys
				for index = 1, math.min(#keys, 64) do
					local row = fields(out, keys[index], { "KeyCode", "UserInputType", "UserInputState" })
					if size(out) + size(row) > MAX_BYTES - 2048 then
						out.truncated = true
						break
					end
					out.pressedKeys[#out.pressedKeys + 1] = row
				end
				if #keys > 64 then
					out.truncated = true
				end
			end
			out.note =
				"Momentary client input state only; no typed text, input history, virtual input, or background subscription."
			return finish(out)
		end)
		add("get_runtime_stats", function(args)
			validate(args, {})
			local out = snapshot("runtime_stats")
			out.memory = { unit = "MB", tags = {}, tagLimit = 32, properties = {}, errors = {} }
			local stats = getService(out, "Stats")
			if stats then
				call(out, out.memory.properties, out.memory.errors, "total", function()
					return finite(stats:GetTotalMemoryUsageMb())
				end)
				call(out, out.memory.properties, out.memory.errors, "trackingEnabled", function()
					return stats.MemoryTrackingEnabled
				end)
				local ok, tags = pcall(function()
					return Enum.DeveloperMemoryTag:GetEnumItems()
				end)
				if not ok or type(tags) ~= "table" then
					failure(out, out.memory.errors, "tags", ok and "invalid enum result" or tags)
				else
					out.memory.nativeTags = #tags
					for index = 1, math.min(#tags, 32) do
						local tag = tags[index]
						local row = { tag = prefix(tostring(tag), 128), properties = {}, errors = {} }
						call(out, row.properties, row.errors, "usage", function()
							return finite(stats:GetMemoryUsageMbForTag(tag))
						end)
						if size(out) + size(row) > MAX_BYTES - 2048 then
							out.truncated = true
							break
						end
						out.memory.tags[#out.memory.tags + 1] = row
					end
					if #tags > 32 then
						out.truncated = true
					end
				end
				local row = fields(out, stats, {
					"InstanceCount",
					"PrimitivesCount",
					"MovingPrimitivesCount",
					"ContactsCount",
					"DataReceiveKbps",
					"DataSendKbps",
					"PhysicsReceiveKbps",
					"PhysicsSendKbps",
					"FrameTime",
					"HeartbeatTime",
					"PhysicsStepTime",
					"RenderCPUFrameTime",
					"RenderGPUFrameTime",
					"SceneDrawcallCount",
					"SceneTriangleCount",
				})
				row.note =
					"Native client Stats fields; timings are seconds and transfer rates are Kbps. No derived render FPS is calculated."
				put(out, out, "stats", row)
			end
			local run = getService(out, "RunService")
			out.run = { properties = {}, errors = {} }
			if run then
				for _, key in ipairs({ "IsClient", "IsRunning", "IsStudio" }) do
					call(out, out.run.properties, out.run.errors, key, function()
						return run[key](run)
					end)
				end
			end
			local world = getService(out, "Workspace")
			if world then
				local row = fields(out, world, { "StreamingEnabled", "Gravity", "DistributedGameTime" })
				call(out, row.properties, row.errors, "physicsSimulationFPS", function()
					return finite(world:GetRealPhysicsFPS())
				end)
				row.note =
					"physicsSimulationFPS is the local physics simulation rate, not rendered frame rate or server performance."
				put(out, out, "workspace", row)
			end
			local performance = c.Main and c.Main.Performance
			if performance and type(performance.Snapshot) == "function" then
				local ok, report = pcall(performance.Snapshot)
				if ok then
					local metrics = {}
					for name, m in pairs(report.Metrics) do
						metrics[#metrics + 1] =
							{ name = name, count = m.Count, totalSeconds = m.Total, maxSeconds = m.Max }
					end
					table.sort(metrics, function(a, b)
						if a.totalSeconds == b.totalSeconds then
							return a.name < b.name
						end
						return a.totalSeconds > b.totalSeconds
					end)
					local total = #metrics
					for i = #metrics, 21, -1 do
						metrics[i] = nil
					end
					local frames = report.SlowFrames
					local frameCount = #frames
					local recent = {}
					for i = math.max(1, frameCount - 9), frameCount do
						recent[#recent + 1] = frames[i]
					end
					put(out, out, "dexPerformance", {
						uptimeSeconds = report.Uptime,
						schedulerYields = report.Yields,
						metrics = metrics,
						totalMetrics = total,
						metricsTruncated = total > 20,
						slowFrames = recent,
						retainedSlowFrameCount = frameCount,
						note = "Local Dex timings. Slow frames describe the whole client, not attribution to Dex.",
					})
				else
					failure(out, out.errors, "dexPerformance", report)
				end
			end
			out.renderFPS = { available = false, reason = "not_sampled" }
			out.note =
				"On-demand client snapshot. Memory, network counters and physics timing may change between reads; no frame sampling loop is started."
			return finish(out)
		end)
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Diagnostics
end
return { Main = Main }
