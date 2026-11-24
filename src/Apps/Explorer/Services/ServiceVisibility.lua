--!strict

local Main, Apps, Settings, API
local defaultVisible = {
	Workspace = true,
	Players = true,
	CoreGui = true,
	Lighting = true,
	MaterialService = true,
	ReplicatedFirst = true,
	ReplicatedStorage = true,
	ServerScriptService = true,
	ServerStorage = true,
	StarterGui = true,
	StarterPack = true,
	StarterPlayer = true,
	Teams = true,
	SoundService = true,
	TextChatService = true,
}

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, Settings, API = d.Main, d.Apps, d.Settings, d.API
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Visibility = {}
	local function hidden()
		if type(Settings.Explorer.HiddenServices) ~= "table" then
			Settings.Explorer.HiddenServices = {}
		end
		return Settings.Explorer.HiddenServices
	end
	function Visibility.IsService(object)
		if not object or object.Parent ~= game then
			return false
		end
		local class = API.Classes[object.ClassName]
		if class and class.Tags and class.Tags.Service then
			return true
		end
		local ok, found = pcall(function()
			return game:FindService(object.ClassName)
		end)
		return ok and found == object
	end
	function Visibility.IsVisible(object)
		if object.Parent ~= game then
			return true
		end
		local className = object.ClassName
		local override = hidden()[className]
		if type(override) == "boolean" then
			return not override
		end
		return defaultVisible[className] == true or not Visibility.IsService(object)
	end
	function Visibility.SetVisible(object, visible)
		if not Visibility.IsService(object) then
			return false
		end
		hidden()[object.ClassName] = not visible
		if Main.SaveSettings then
			Main.SaveSettings()
		end
		return true
	end
	function Visibility.GetHiddenServices()
		local entries, seen = {}, {}
		for _, object in ipairs(game:GetChildren()) do
			if Visibility.IsService(object) then
				seen[object.ClassName] = true
				if not Visibility.IsVisible(object) then
					entries[#entries + 1] = object.ClassName
				end
			end
		end
		for name, class in pairs(API.Classes) do
			local tags = class.Tags or {}
			if
				tags.Service
				and not tags.Hidden
				and not tags.Deprecated
				and not seen[name]
				and Apps.ReflectionService.IsVisible(name, nil, false, false)
			then
				entries[#entries + 1] = name
			end
		end
		table.sort(entries)
		return entries
	end
	function Visibility.Show(name)
		local class = API.Classes[name]
		local object = game:FindFirstChildOfClass(name)
		if not object and not (class and class.Tags and class.Tags.Service) then
			return nil, "Service unavailable"
		end
		local ok, result = pcall(function()
			return object or game:GetService(name)
		end)
		if not ok or not Visibility.IsService(result) then
			return nil, "This service is unavailable in this client."
		end
		Visibility.SetVisible(result, true)
		return result
	end
	return Visibility
end
return { InitDeps = InitDeps, Main = CreateModule }
