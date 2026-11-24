--!strict

local Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Settings = d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Appearance = {}
	Appearance.ChangedProperties = { IconTint = true, RunContext = true, AutoUpdate = true, ShowDevelopmentGui = true }
	function Appearance.Resolve(object, className)
		if not object then
			return className
		end
		if className == "Script" or className == "LocalScript" then
			local ok, context = pcall(function()
				return object.RunContext
			end)
			if ok and context == Enum.RunContext.Client then
				return "LocalScript"
			end
		end
		local ok, isFolder = pcall(function()
			return object:IsA("Folder")
		end)
		if ok and isFolder then
			local readable, hue, saturation = pcall(function()
				return object.IconTint:ToHSV()
			end)
			if readable and type(saturation) == "number" and saturation > 0 then
				local light = Settings.Theme.IconTheme == "Light"
				local theme = light and "Light" or "Dark"
				local color = Color3.fromHSV(hue, light and 0.636364 or 0.492, light and 0.905882 or 0.980392)
				return className, "native/folder/tint/" .. theme, color
			end
		elseif className == "PackageLink" then
			local readable, auto = pcall(function()
				return object.AutoUpdate
			end)
			if readable and auto == true then
				return className, "native/package/autoupdate"
			end
		end
		return className
	end
	return Appearance
end
return { InitDeps = InitDeps, Main = Main }
