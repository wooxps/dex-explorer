--!strict

local Apps, world, native, clock, wait

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, world = d.Apps, d.Game or game
	native = d.Functions
		or { Filter = filtergc, Dump = dumpbytecode, Upvalues = debug and debug.getupvalues, Environment = getfenv }
	clock, wait = d.Clock or os.clock, d.Wait or function()
		task.wait()
	end
end
------------------------------ Module ------------------------------

local function Main()
	local Runtime = {}
	function Runtime.Collect(emit, checkpoint)
		local stats = {
			Mode = "Retained functions",
			Queries = 0,
			Matches = 0,
			Owned = 0,
			Dumped = 0,
			Parsed = 0,
			Claims = 0,
			Rejected = 0,
			NativeSeconds = 0,
			Truncated = 0,
			Errors = 0,
		}
		if
			type(native.Filter) ~= "function"
			or type(native.Dump) ~= "function"
			or type(native.Environment) ~= "function"
		then
			stats.Mode = "Unavailable"
			return stats
		end
		local candidates = Apps.Explorer
			and Apps.Explorer.GetInferenceCandidates
			and Apps.Explorer.GetInferenceCandidates()
		if not candidates then
			stats.Mode = "No ownership index"
			return stats
		end
		local function active()
			return not checkpoint or checkpoint() ~= false
		end
		local function call(name, fn)
			if not active() then
				stats.Cancelled = true
				return false
			end
			local start = clock()
			local ok, value = pcall(fn)
			local seconds = clock() - start
			stats.NativeSeconds += seconds
			if seconds > 0.02 then
				if name == "Filtered function discovery" and seconds <= 0.1 then
					stats.DiscoveryOverruns = (stats.DiscoveryOverruns or 0) + 1
					stats.MaxDiscoverySeconds = math.max(stats.MaxDiscoverySeconds or 0, seconds)
				else
					stats.Paused = true
					stats.Stop = name .. " exceeded native time limit"
				end
			end
			if not ok then
				stats.Errors += 1
				stats.LastError = tostring(value):sub(1, 350)
			end
			return ok, value
		end
		local selected, seen = {}, {}
		for _, root in ipairs({ "ServerStorage", "ServerScriptService" }) do
			stats.Queries += 1
			local ok, items = call("Filtered function discovery", function()
				return native.Filter("function", { IgnoreExecutor = true, Constants = { root } }, false)
			end)
			if stats.Paused or stats.Cancelled then
				return stats
			end
			wait()
			if ok and type(items) == "table" then
				stats.Matches += #items
				for index, fn in ipairs(items) do
					if not active() then
						stats.Cancelled = true
						return stats
					end
					if index > 2000 then
						stats.Truncated += #items - 2000
						break
					end
					if type(fn) == "function" and not seen[fn] then
						seen[fn] = true
						local good, environment = call("Function environment inspection", function()
							return native.Environment(fn)
						end)
						if stats.Paused or stats.Cancelled then
							return stats
						end
						local source = good and type(environment) == "table" and rawget(environment, "script")
						if not source and good and type(environment) == "table" then
							local mt = getmetatable(environment)
							local inherited = type(mt) == "table" and rawget(mt, "__index")
							if type(inherited) == "table" then
								source = rawget(inherited, "script")
							end
						end
						local node = source and candidates[source]
						if node and not node.Inferred and not node.Del then
							stats.Owned += 1
							if #selected < 512 then
								selected[#selected + 1] = { Function = fn, Source = source }
							else
								stats.Truncated += 1
							end
						end
					end
				end
			end
		end
		local ss, sss = world:GetService("ServerStorage"), world:GetService("ServerScriptService")
		for _, item in ipairs(selected) do
			if not active() then
				stats.Cancelled = true
				return stats
			end
			local ok, bytes = call("Function serialization", function()
				return native.Dump(item.Function)
			end)
			if stats.Paused or stats.Cancelled then
				return stats
			end
			if ok and type(bytes) == "string" and #bytes <= 1024 * 1024 then
				stats.Dumped += 1
				local seeds = {}
				if type(native.Upvalues) == "function" then
					local good, values = call("Upvalue inspection", function()
						return native.Upvalues(item.Function)
					end)
					if stats.Paused or stats.Cancelled then
						return stats
					end
					if good and type(values) == "table" then
						for slot, value in pairs(values) do
							if type(slot) == "number" and slot >= 1 and slot <= 200 then
								if type(value) == "string" and #value <= 512 then
									seeds[slot] = value
								elseif value == ss then
									seeds[slot] = { Path = { "ServerStorage" } }
								elseif value == sss then
									seeds[slot] = { Path = { "ServerScriptService" } }
								elseif value == world then
									seeds[slot] = { Global = "game" }
								end
							end
						end
					end
				end
				local good, label = pcall(function()
					return item.Source:GetFullName()
				end)
				local parsed, result = Apps.BytecodePaths.Analyze(
					bytes,
					(good and label or item.Source.Name) .. " (retained function)",
					emit,
					checkpoint,
					seeds
				)
				if not parsed and result == "Cancelled" then
					stats.Cancelled = true
					return stats
				end
				if parsed then
					stats.Parsed += 1
					stats.Claims += result.Claims
				else
					stats.Rejected += 1
					stats.Rejections = stats.Rejections or {}
					local reason = tostring(result)
					stats.Rejections[reason] = (stats.Rejections[reason] or 0) + 1
				end
			elseif ok then
				stats.Truncated += 1
			end
		end
		stats.Complete = not stats.Paused
			and not stats.Cancelled
			and stats.Truncated == 0
			and stats.Errors == 0
			and stats.Rejected == 0
		return stats
	end
	return Runtime
end
return { InitDeps = InitDeps, Main = Main }
