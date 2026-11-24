--!strict

local Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Settings = d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Status = {
		ChangedProperties = {
			ModifiedState = true,
			HasNewVersion = true,
			AutoUpdate = true,
			ChatVersion = true,
			IsAutoMigrated = true,
			AuthorityMode = true,
		},
	}
	local cache = setmetatable({}, { __mode = "k" })
	local linkParents = setmetatable({}, { __mode = "kv" })
	local epoch = 0
	local function read(object, property)
		local ok, value = pcall(function()
			return object[property]
		end)
		if ok then
			return value
		end
		return nil
	end
	local function service(name)
		local ok, value = pcall(function()
			return game:GetService(name)
		end)
		if ok then
			return value
		end
	end
	function Status.Invalidate(object, property)
		if not object then
			return
		end
		cache[object] = nil
		if property == "ChatVersion" or property == "IsAutoMigrated" or property == "AuthorityMode" then
			epoch += 1
		end
		if read(object, "ClassName") == "PackageLink" then
			local previous = linkParents[object]
			local parent = read(object, "Parent")
			if previous then
				cache[previous] = nil
			end
			if parent then
				cache[parent] = nil
			end
			linkParents[object] = parent
			return true
		end
		return false
	end
	function Status.Resolve(object, className)
		if not object then
			return nil
		end
		local theme = Settings.Theme.IconTheme == "Light" and "Light" or "Dark"
		local prior = cache[object]
		if prior and prior.epoch == epoch and prior.theme == theme then
			return prior.asset, prior.tooltip, prior.disabled
		end
		local asset, tooltip, disabled
		if className == "Chat" then
			local chatVersion = read(service("TextChatService"), "ChatVersion")
			local ok, modern = pcall(function()
				return Enum.ChatVersion.TextChatService
			end)
			if chatVersion ~= nil and ok and modern ~= nil then
				asset = "native/status/warning/" .. theme
				tooltip = "Legacy Chat is deprecated. Use TextChatService."
				disabled = chatVersion == modern
			end
		elseif className == "TextChatService" then
			local migrated = read(service("Chat"), "IsAutoMigrated")
			local chatVersion = read(object, "ChatVersion")
			local ok, modern = pcall(function()
				return Enum.ChatVersion.TextChatService
			end)
			if migrated == true and chatVersion ~= nil and ok and modern ~= nil and chatVersion ~= modern then
				asset = "native/status/warning/" .. theme
				tooltip = "Legacy chat is automatically migrated. Configure TextChatService explicitly."
			end
		elseif className == "AuroraScript" then
			local authority = read(service("Workspace"), "AuthorityMode")
			local ok, server = pcall(function()
				return Enum.AuthorityMode.Server
			end)
			if authority ~= nil and ok and server ~= nil and authority ~= server then
				asset = "native/status/warning/" .. theme
				tooltip = "AuroraScript requires Workspace authority mode Server."
				disabled = true
			end
		else
			local ok, link = pcall(function()
				return object:FindFirstChildOfClass("PackageLink")
			end)
			if ok and link and read(link, "Parent") == object then
				linkParents[link] = object
				local modified, newVersion, auto =
					read(link, "ModifiedState"), read(link, "HasNewVersion"), read(link, "AutoUpdate")
				if
					type(modified) == "number"
					and modified ~= 0
					and type(newVersion) == "boolean"
					and type(auto) == "boolean"
				then
					local suffix
					if newVersion then
						suffix = modified == 1 and "UpdateAvailable_Modified" or "UpdateAvailable_Old"
						tooltip = modified == 1 and "Package update available; local changes exist."
							or "Package update available."
					elseif modified == 1 then
						suffix = auto and "Modified_AutoupdateOn" or "Modified_AutoupdateOff"
						tooltip = "Package has local changes."
					else
						suffix = auto and "AutoupdateOn_Old" or "AutoupdateOff_Old"
						tooltip = auto and "Package automatic updates enabled." or "Package automatic updates disabled."
					end
					asset = "native/status/package/" .. theme .. "/" .. suffix
				end
			end
		end
		cache[object] = { epoch = epoch, theme = theme, asset = asset, tooltip = tooltip, disabled = disabled }
		return asset, tooltip, disabled
	end
	return Status
end
return { InitDeps = InitDeps, Main = Main }
