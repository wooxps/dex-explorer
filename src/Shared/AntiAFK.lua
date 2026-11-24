--!strict

local Main, Settings, service, plr

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Settings, service, plr = d.Main, d.Settings, d.service, d.plr
end
------------------------------ Module ------------------------------

local function CreateModule()
	local A = {}
	local connection, generation = nil, 0
	local function stop()
		generation += 1
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	local function refresh()
		if Main.RefreshSettings then
			Main.RefreshSettings()
		end
	end
	function A.SetEnabled(enabled)
		stop()
		Settings.Interface.AntiAFK = false
		if not enabled or Main.Alive == false then
			return not enabled
		end
		local token = generation
		local ok, problem = pcall(function()
			local player = plr or service.Players.LocalPlayer
			assert(player, "Local player is unavailable")
			connection = player.Idled:Connect(function()
				if token ~= generation or not Settings.Interface.AntiAFK or Main.Alive == false then
					return
				end
				local sent, reason = pcall(function()
					local virtualInput = Instance.new("VirtualInputManager")
					virtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 0)
					virtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 0)
					virtualInput:Destroy()
				end)
				if not sent and token == generation then
					stop()
					Settings.Interface.AntiAFK = false
					refresh()
					if Main.SaveSettings then
						Main.SaveSettings()
					end
					warn("[Dex Explorer] Anti AFK turned off: " .. tostring(reason))
				end
			end)
		end)
		if not ok then
			stop()
			warn("[Dex Explorer] Anti AFK unavailable: " .. tostring(problem))
			return false
		end
		Settings.Interface.AntiAFK = true
		return true
	end
	function A.Destroy()
		stop()
	end
	Main.AddCleanup(A.Destroy)
	return A
end
local control = { InitDeps = InitDeps, Main = CreateModule }
if gethsfuncs then
	_G.moduleData = control
else
	return control
end
