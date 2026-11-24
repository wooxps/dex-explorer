--!strict

local Apps, env, clock

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, env, clock = d.Apps, d.env, d.Clock or os.clock
end
------------------------------ Module ------------------------------

local function Main()
	local Reader = {}
	local sources = {}
	local literals = {}
	local total = 0
	local revision = 0
	local literalBytes = 0
	local paused = false
	local pendingRead
	local order = {}
	local queued = {}
	local remove
	local function touch(object)
		if not queued[object] then
			if #order >= 32768 then
				remove(table.remove(order, 1))
			end
			queued[object] = true
			order[#order + 1] = object
		end
	end
	remove = function(object)
		if sources[object] then
			total -= #sources[object].Source
			sources[object] = nil
		end
		if literals[object] then
			for _, text in ipairs(literals[object]) do
				literalBytes -= #text
			end
			literals[object] = nil
		end
		queued[object] = nil
	end
	function Reader.Store(object, text, kind)
		if type(text) ~= "string" or #text > 2 * 1024 * 1024 then
			return
		end
		local old = sources[object]
		local size = old and #old.Source or 0
		while total - size + #text > 32 * 1024 * 1024 and #order > 0 do
			local victim = table.remove(order, 1)
			remove(victim)
			old = sources[object]
			size = old and #old.Source or 0
		end
		touch(object)
		if literals[object] then
			for _, value in ipairs(literals[object]) do
				literalBytes -= #value
			end
			literals[object] = nil
		end
		sources[object] = { Source = text, SourceKind = kind or "Cached source" }
		total = total - size + #text
		if not old or old.Source ~= text then
			revision += 1
		end
	end
	function Reader.Revision()
		return revision
	end
	function Reader.BeginPass()
		paused = false
		local retained = 0
		for _, object in ipairs(order) do
			if object.Parent == nil then
				remove(object)
			else
				retained += 1
				order[retained] = object
			end
		end
		for index = #order, retained + 1, -1 do
			order[index] = nil
		end
	end
	function Reader.ClearBytecode()
		table.clear(literals)
		literalBytes = 0
	end
	function Reader.PeekCompiled(object)
		if literals[object] then
			return { Literals = literals[object], SourceKind = "Cached bytecode" }
		end
	end
	function Reader.Peek(object)
		return sources[object]
	end
	function Reader.Read(object, checkpoint, yieldNative, pass, bounded)
		if literals[object] then
			return { Literals = literals[object], SourceKind = "Cached bytecode" }
		end
		if not pass then
			local ok, source = pcall(function()
				return object.Source
			end)
			if ok and type(source) == "string" and source ~= "" then
				return { Source = source, SourceKind = "Readable source" }
			end
		end
		if sources[object] then
			return sources[object]
		end
		if object.ClassName == "Script" then
			local known, context = pcall(function()
				return object.RunContext
			end)
			if known and (context == Enum.RunContext.Legacy or context == Enum.RunContext.Server) then
				return { Unavailable = "Server script contents are not replicated" }
			end
		end
		if not pass and paused then
			return { Unavailable = "Bytecode reads paused after a slow call" }
		end
		if type(env.getscriptbytecode) ~= "function" then
			return { Unavailable = "Source and bytecode unavailable" }
		end
		if checkpoint and not checkpoint() then
			return { Cancelled = true }
		end
		local started = clock()
		local good, bytes, duration
		local yielded = false
		if bounded then
			if pendingRead then
				return { Unavailable = "A bytecode read is still pending" }
			end
			local read = {}
			pendingRead = read
			task.spawn(function()
				read.Good, read.Bytes = pcall(env.getscriptbytecode, object)
				read.Duration = clock() - started
				pendingRead = nil
			end)
			yielded = pendingRead == read
			while pendingRead == read do
				if clock() - started >= 0.5 then
					paused = true
					return { Unavailable = "Bytecode read timed out" }
				end
				yieldNative(true)
				if checkpoint and not checkpoint() then
					return { Cancelled = true }
				end
			end
			good, bytes, duration = read.Good, read.Bytes, read.Duration
		else
			good, bytes = pcall(env.getscriptbytecode, object)
			duration = clock() - started
		end
		if not pass and not yielded and duration > 0.02 then
			paused = true
		end
		if yieldNative then
			yieldNative(duration)
		end
		if not pass and checkpoint and not checkpoint() then
			return { Cancelled = true }
		end
		if not good or type(bytes) ~= "string" then
			return { Unavailable = "Bytecode unavailable" }
		end
		local strings = {}
		local size = 0
		local valid, problem = Apps.BytecodeStrings.VisitAll(bytes, function(text)
			strings[#strings + 1] = text
			size += #text
		end, pass and pass.ParseCheckpoint or checkpoint, pass ~= nil)
		if not valid then
			return { Unavailable = problem or "Unsupported bytecode" }
		end
		if not pass and literalBytes + size <= 48 * 1024 * 1024 and (queued[object] or #order < 32768) then
			touch(object)
			literals[object] = strings
			literalBytes += size
		end
		return { Literals = strings, SourceKind = "Bytecode strings", Bytes = size }
	end
	return Reader
end
return { InitDeps = InitDeps, Main = Main }
