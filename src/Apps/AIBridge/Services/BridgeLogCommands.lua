--!strict

------------------------------ Module ------------------------------

local function Main()
	local Logs = {}
	local active
	local sequence, droppedTotal = 0, 0
	local MAX_ENTRIES, MAX_BYTES, MAX_MESSAGE_BYTES, PAGE_BYTES = 512, 262144, 4096, 24576
	local levels =
		{ MessageOutput = "output", MessageInfo = "info", MessageWarning = "warning", MessageError = "error" }
	local function integer(value, default, minimum, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum,
			"INVALID_ARGUMENT: integer outside supported range"
		)
		return value
	end
	local function now()
		return DateTime and DateTime.now().UnixTimestampMillis or os.time() * 1000
	end
	local function discard(state)
		local entry = state.entries[state.first]
		if not entry then
			return
		end
		state.entries[state.first] = nil
		state.first += 1
		state.count -= 1
		state.bytes -= entry._bytes
		droppedTotal += 1
	end
	function Logs.Create(c)
		if not active then
			local state = { entries = {}, first = 1, last = 0, count = 0, bytes = 0, refs = 0, startedAt = now() }
			active = state
			local ok, connection = pcall(function()
				local log = c.service.LogService or (c.Game or game):GetService("LogService")
				return log.MessageOut:Connect(function(message, messageType)
					if active ~= state or type(message) ~= "string" then
						return
					end
					local name = tostring(messageType):match("Message%w+$") or "MessageOutput"
					local originalBytes = #message
					local length = math.min(originalBytes, MAX_MESSAGE_BYTES)
					if length < originalBytes then
						while length > 0 do
							local byte = message:byte(length + 1)
							if byte < 128 or byte >= 192 then
								break
							end
							length -= 1
						end
					end
					local text = message:sub(1, length)
					sequence += 1
					local entry = {
						sequence = sequence,
						timestamp = now(),
						messageType = name,
						level = levels[name] or "info",
						message = text,
						truncated = length < originalBytes,
						originalBytes = originalBytes,
						_bytes = #text + #name + 64,
					}
					state.last += 1
					state.entries[state.last] = entry
					state.count += 1
					state.bytes += entry._bytes
					while state.count > MAX_ENTRIES or state.bytes > MAX_BYTES do
						discard(state)
					end
				end)
			end)
			if ok then
				state.connection = connection
			end
		end
		local state = active
		state.refs += 1
		local destroyed = false
		local function available()
			assert(not destroyed, "DISCONNECTED: bridge session ended")
			assert(state.connection, "UNSUPPORTED: client LogService.MessageOut is unavailable")
		end
		local function read(args)
			available()
			local oldest = state.entries[state.first]
			local minimum = oldest and oldest.sequence or sequence + 1
			local after = integer(args.afterSequence, minimum - 1, 0, 9007199254740991)
			assert(
				after <= sequence,
				"INVALID_ARGUMENT: log cursor is ahead of this client; omit afterSequence after changing clients"
			)
			local limit = integer(args.limit, 100, 1, 200)
			assert(
				args.level == nil
					or args.level == "output"
					or args.level == "info"
					or args.level == "warning"
					or args.level == "error",
				"INVALID_ARGUMENT: unknown client log level"
			)
			assert(
				args.text == nil or type(args.text) == "string" and #args.text <= 1024,
				"INVALID_ARGUMENT: text must be a literal string of at most 1024 bytes"
			)
			local entries = {}
			local cursor = math.max(after, minimum - 1)
			local bytes = 0
			local hasMore = false
			for index = state.first, state.last do
				local entry = state.entries[index]
				if entry.sequence > after then
					local matches = (not args.level or entry.level == args.level)
						and (not args.text or entry.message:find(args.text, 1, true) ~= nil)
					if matches and (#entries >= limit or bytes + #entry.message > PAGE_BYTES) then
						hasMore = true
						break
					end
					cursor = entry.sequence
					if matches then
						entries[#entries + 1] = {
							sequence = entry.sequence,
							timestamp = entry.timestamp,
							messageType = entry.messageType,
							level = entry.level,
							message = entry.message,
							truncated = entry.truncated,
							originalBytes = entry.originalBytes,
						}
						bytes += #entry.message
					end
				end
			end
			return {
				scope = "client",
				entries = entries,
				nextSequence = cursor,
				latestSequence = sequence,
				oldestSequence = minimum,
				hasMore = hasMore,
				droppedMessages = droppedTotal,
				droppedSinceCursor = math.max(0, minimum - 1 - after),
				bufferedMessages = state.count,
				bufferedBytes = state.bytes,
				captureStartedAt = state.startedAt,
				timestampUnit = "unix_milliseconds",
			}
		end
		local function clear()
			available()
			local count = state.count
			while state.count > 0 do
				discard(state)
			end
			state.entries = {}
			state.first = 1
			state.last = 0
			return {
				scope = "client",
				clearedMessages = count,
				nextSequence = sequence,
				droppedMessages = droppedTotal,
				robloxOutputCleared = false,
			}
		end
		local result = {
			Commands = {
				{ Name = "dex_get_logs", Grant = "inspect", Run = read },
				{ Name = "dex_clear_logs", Grant = "inspect", Run = clear },
			},
		}
		function result:Destroy()
			if destroyed then
				return
			end
			destroyed = true
			state.refs -= 1
			if state.refs == 0 then
				if state.connection then
					state.connection:Disconnect()
				end
				while state.count > 0 do
					discard(state)
				end
				state.entries = {}
				active = nil
			end
		end
		return result
	end
	return Logs
end
return { Main = Main }
