--!strict

local Main, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, env = d.Main, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Rig = {}
	local templates = {}
	local function clean(model)
		assert(model and model:IsA("Model"), "Reference rig did not load as a Model")
		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("LuaSourceContainer") or object:IsA("Sound") then
				object:Destroy()
			end
		end
		assert(model:FindFirstChildOfClass("Humanoid"), "Reference rig has no Humanoid")
		return model
	end
	function Rig.Create(kind)
		assert(kind == "R6" or kind == "R15", "Unknown rig type")
		if not templates[kind] then
			local ok, objects = pcall(function()
				return (oldgame or game):GetObjects("rbxasset://avatar/morpherEditor" .. kind .. ".rbxmx")
			end)
			if not ok or not objects or not objects[1] then
				assert(
					env.writefile and env.getcustomasset,
					"Loading reference rigs requires writefile and getcustomasset support"
				)
				local data = Main.LoadModule("AssetRigData")[kind]
				if env.makefolder then
					pcall(env.makefolder, "dex-explorer")
					pcall(env.makefolder, "dex-explorer/assets")
				end
				local path = "dex-explorer/assets/reference-" .. kind .. ".rbxmx"
				env.writefile(path, data)
				objects = (oldgame or game):GetObjects(env.getcustomasset(path))
			end
			local loaded = objects[1]
			local good, result = pcall(clean, loaded)
			for index = 2, #objects do
				objects[index]:Destroy()
			end
			if not good then
				if loaded then
					loaded:Destroy()
				end
				error(result, 0)
			end
			templates[kind] = result
		end
		return assert(templates[kind]:Clone(), "Reference rig could not be cloned")
	end
	Main.AddCleanup(function()
		for _, model in pairs(templates) do
			model:Destroy()
		end
		table.clear(templates)
	end)
	return Rig
end
return { InitDeps = InitDeps, Main = CreateModule }
