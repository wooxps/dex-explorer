--!strict

local service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	service = d.service
end
------------------------------ Module ------------------------------

local function Main()
	local Playback = {}
	function Playback.Start(model, animator, track, report)
		local edges = {}
		local targets = {}
		local roots = {}
		local manual, blocked = false, false
		local lastPosition = track.TimePosition
		local stalled = 0
		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("BasePart") then
				object.Anchored = true
				roots[object] = true
			end
			if object:IsA("Motor6D") and object.Part0 and object.Part1 then
				local list = edges[object.Part0] or {}
				edges[object.Part0] = list
				list[#list + 1] = object
				targets[object.Part1] = true
			end
		end
		for part in pairs(targets) do
			roots[part] = nil
		end
		local connection = service.RunService.RenderStepped:Connect(function(dt)
			if track.IsPlaying and track.Speed ~= 0 and track.Length > 0 then
				local advanced = math.abs(track.TimePosition - lastPosition) >= 0.00001
				if advanced then
					stalled = 0
					manual = false
				else
					stalled += dt
				end
				if not blocked and (manual or stalled > 0.5) then
					local ok = pcall(animator.StepAnimations, animator, math.min(dt, 0.1))
					if ok then
						manual = true
					else
						blocked = true
						report("Animation stepping is unavailable in this client.")
					end
				end
			end
			lastPosition = track.TimePosition
			local queue = {}
			for part in pairs(roots) do
				queue[#queue + 1] = part
			end
			local seen = {}
			for index = 1, 1000 do
				local part = queue[index]
				if not part then
					break
				end
				if seen[part] then
					continue
				end
				seen[part] = true
				for _, motor in ipairs(edges[part] or {}) do
					if motor.Parent and motor.Part0 and motor.Part1 then
						motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * motor.Transform * motor.C1:Inverse()
						queue[#queue + 1] = motor.Part1
					end
				end
			end
		end)
		return {
			Destroy = function()
				connection:Disconnect()
			end,
		}
	end
	return Playback
end
return { InitDeps = InitDeps, Main = Main }
