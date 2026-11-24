--!strict

local Main, service
local clock, wait = os.clock, task and task.wait

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, service = d.Main, d.service
	clock = d.Clock or os.clock
	wait = d.Wait or (task and task.wait)
end
------------------------------ Module ------------------------------

local function CreateModule()
	local P = { Budget = 0.003, Metrics = {}, SlowFrames = {}, Started = clock(), Yields = 0 }
	local deadline = clock() + P.Budget
	local names = 0
	local cursor = 0
	function P.Record(name, seconds)
		if type(seconds) ~= "number" or seconds < 0 or seconds ~= seconds then
			return
		end
		local m = P.Metrics[name]
		if not m then
			if names >= 192 then
				name = "Other"
				m = P.Metrics[name]
			end
			if not m then
				m = { Count = 0, Total = 0, Max = 0 }
				P.Metrics[name] = m
				names += 1
			end
		end
		m.Count += 1
		m.Total += seconds
		m.Max = math.max(m.Max, seconds)
	end
	function P.Available()
		return clock() < deadline
	end
	function P.Checkpoint(name, cancel)
		if cancel and not cancel() then
			return false
		end
		if not P.Available() then
			P.Yields += 1
			local started = clock()
			wait()
			P.Record("scheduler/wait", clock() - started)
			if cancel and not cancel() then
				return false
			end
		end
		return Main.Alive ~= false
	end
	function P.Snapshot()
		local out = { Uptime = clock() - P.Started, Yields = P.Yields, Metrics = {}, SlowFrames = {} }
		for name, m in pairs(P.Metrics) do
			out.Metrics[name] = table.clone(m)
		end
		for _, frame in pairs(P.SlowFrames) do
			out.SlowFrames[#out.SlowFrames + 1] = table.clone(frame)
		end
		table.sort(out.SlowFrames, function(a, b)
			return a.Sequence < b.Sequence
		end)
		return out
	end
	if service.RunService and service.RunService.Heartbeat then
		Main.TrackSignal(service.RunService.Heartbeat, function(dt)
			deadline = clock() + P.Budget
			if dt > 0.05 then
				cursor += 1
				P.SlowFrames[(cursor - 1) % 120 + 1] = { Sequence = cursor, At = clock() - P.Started, Seconds = dt }
			end
		end)
	end
	Main.Performance = P
	return P
end
return { InitDeps = InitDeps, Main = CreateModule }
