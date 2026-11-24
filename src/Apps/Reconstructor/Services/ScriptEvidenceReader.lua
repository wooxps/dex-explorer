--!strict

local env, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	env, Apps = d.env, d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local Reader = {}
	function Reader.Create(options)
		options = options or {}
		local clock, wait = options.Clock or os.clock, options.Wait or task.wait
		local cache = setmetatable({}, { __mode = "k" })
		local totalCache = 0
		local lastDecompile, lastBytecode = -math.huge, -math.huge
		local passDecompiled = 0
		local self = {
			Stats = {
				BytecodeReads = 0,
				Decompiled = 0,
				BytecodeSeconds = 0,
				DecompileSeconds = 0,
				Deferred = 0,
				PathAnalyses = 0,
				PathClaims = 0,
				PathRejected = 0,
				PathSeconds = 0,
			},
			BytecodePaused = false,
			DecompilePaused = false,
		}
		local function remember(obj, record)
			if record.Source and Apps.ReferenceSource then
				Apps.ReferenceSource.Store(obj, record.Source, "Cached decompiled source")
			end
			local previous = cache[obj]
			local cost = #(record.Source or "") + #(record.Bytecode or "")
			if cost > 1024 * 1024 or totalCache - (previous and previous.Cost or 0) + cost > 32 * 1024 * 1024 then
				return
			end
			if previous then
				totalCache -= previous.Cost
			end
			record.Cost = cost
			cache[obj] = record
			totalCache += cost
		end
		function self:BeginPass()
			passDecompiled = 0
			if self.BytecodePaused and not self.SevereBytecodePause and clock() - lastBytecode >= 5 then
				self.BytecodePaused = false
			end
			if self.DecompilePaused and not self.SeverePause and clock() - lastDecompile >= 5 then
				self.DecompilePaused = false
			end
		end
		function self:Commit(obj, source)
			local record = cache[obj]
			if record and record.Source == source then
				record.Analyzed = true
			end
		end
		function self:Read(obj, checkpoint)
			if checkpoint and checkpoint() == false then
				return { Status = "Cancelled" }
			end
			local ok, source = pcall(function()
				return obj.Source
			end)
			if
				(not ok or type(source) ~= "string" or source == "")
				and Apps.ReferenceSource
				and Apps.ReferenceSource.Peek
			then
				local stored = Apps.ReferenceSource.Peek(obj)
				if stored and type(stored.Source) == "string" then
					ok, source = true, stored.Source
					self.Stats.CachedSourceReads = (self.Stats.CachedSourceReads or 0) + 1
				end
			end
			local previous = cache[obj]
			if ok and type(source) == "string" and source ~= "" then
				if previous and previous.Source == source then
					return previous.Analyzed and { Status = "Cached" } or { Status = "Source", Source = source }
				end
				if #source > 1024 * 1024 then
					return { Status = "Deferred", Reason = "Source size limit" }
				end
				remember(obj, { Source = source })
				return { Status = "Source", Source = source }
			end
			if self.BytecodePaused then
				return {
					Status = "Deferred",
					Reason = self.SevereBytecodePause and "Severe bytecode stall" or "Bytecode circuit cooling down",
				}
			end
			if type(env.getscriptbytecode) ~= "function" then
				return { Status = "Unavailable" }
			end
			local started = clock()
			local success, bytes = pcall(env.getscriptbytecode, obj)
			local seconds = clock() - started
			self.Stats.BytecodeReads += 1
			self.Stats.BytecodeSeconds += seconds
			lastBytecode = clock()
			if seconds > 0.01 then
				self.BytecodePaused = true
				self.Stats.BytecodePauseCount = (self.Stats.BytecodePauseCount or 0) + 1
			end
			if seconds > 0.1 then
				self.SevereBytecodePause = true
			end
			if not success or type(bytes) ~= "string" then
				return { Status = "Unavailable" }
			end
			if self.SevereBytecodePause then
				return { Status = "Deferred", Reason = "Severe bytecode stall" }
			end
			if previous and previous.Bytecode == bytes then
				if previous.Source then
					return previous.Analyzed and { Status = "Cached" }
						or { Status = "Source", Source = previous.Source }
				end
				if previous.Final then
					return { Status = "Cached" }
				end
				if (previous.Failures or 0) >= 2 then
					return { Status = "Unavailable" }
				end
			end
			if #bytes > 1024 * 1024 then
				self.Stats.Deferred += 1
				return { Status = "Deferred" }
			end
			if not Apps.BytecodeStrings.HasServerHint(bytes) then
				remember(obj, { Bytecode = bytes, Final = true })
				return { Status = "Filtered" }
			end
			if options.Literal and not (previous and previous.Bytecode == bytes and previous.LiteralsDone) then
				local valid, problem = Apps.BytecodeStrings.Visit(bytes, function(text)
					options.Literal(obj, text)
				end, checkpoint)
				if problem == "Cancelled" then
					return { Status = "Cancelled" }
				end
				if not valid then
					self.Stats.InvalidBytecode = (self.Stats.InvalidBytecode or 0) + 1
				end
			end
			local pathsDone = previous and previous.Bytecode == bytes and previous.PathsDone
			if options.Paths and not pathsDone then
				local pathStart = clock()
				local analyzed, result = options.Paths(obj, bytes, checkpoint)
				self.Stats.PathSeconds += clock() - pathStart
				if not analyzed and result == "Cancelled" then
					return { Status = "Cancelled" }
				end
				pathsDone = true
				if analyzed then
					self.Stats.PathAnalyses += 1
					self.Stats.PathClaims += result.Claims
					if result.CacheHit then
						self.Stats.PathCacheHits = (self.Stats.PathCacheHits or 0) + 1
					end
					if (result.TrailerBytes or 0) > 0 then
						self.Stats.PathTrailers = (self.Stats.PathTrailers or 0) + 1
					end
				else
					self.Stats.PathRejected += 1
					self.Stats.PathRejections = self.Stats.PathRejections or {}
					local reason = tostring(result)
					self.Stats.PathRejections[reason] = (self.Stats.PathRejections[reason] or 0) + 1
				end
			end
			if self.DecompilePaused or #bytes > 4096 or type(env.decompile) ~= "function" or passDecompiled >= 32 then
				self.Stats.Deferred += 1
				remember(obj, { Bytecode = bytes, LiteralsDone = true, PathsDone = pathsDone })
				return {
					Status = "Deferred",
					Reason = self.DecompilePaused and "Native circuit paused"
						or #bytes > 4096 and "Native size limit"
						or type(env.decompile) ~= "function" and "Decompiler unavailable"
						or "Pass decompile limit",
				}
			end
			local viable = false
			if type(env.isViableDecompileScript) == "function" then
				local good, value = pcall(env.isViableDecompileScript, obj)
				viable = good and value
			end
			if not viable then
				remember(obj, { Bytecode = bytes, LiteralsDone = true, PathsDone = pathsDone })
				return { Status = "Unavailable" }
			end
			local delay = 0.05 - (clock() - lastDecompile)
			if delay > 0 then
				wait(delay)
			end
			if checkpoint and checkpoint() == false then
				return { Status = "Cancelled" }
			end
			started = clock()
			local good, text = pcall(env.decompile, obj)
			seconds = clock() - started
			lastDecompile = clock()
			self.Stats.Decompiled += 1
			passDecompiled += 1
			self.Stats.DecompileSeconds += seconds
			if seconds > 0.025 then
				self.DecompilePaused = true
			end
			if seconds > 0.1 then
				self.SeverePause = true
			end
			if not good or type(text) ~= "string" then
				remember(obj, {
					Bytecode = bytes,
					LiteralsDone = true,
					PathsDone = pathsDone,
					Failures = (previous and previous.Failures or 0) + 1,
				})
				return { Status = "Unavailable" }
			end
			if #text > 65536 then
				remember(obj, { Bytecode = bytes })
				return { Status = "Deferred" }
			end
			remember(obj, { Bytecode = bytes, Source = text, LiteralsDone = true, PathsDone = pathsDone })
			return { Status = "Source", Source = text }
		end
		return self
	end
	return Reader
end
return { InitDeps = InitDeps, Main = Main }
