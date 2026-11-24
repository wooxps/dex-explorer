--!strict

local Apps, env, service

local function InitDeps(deps)
	Apps, env, service = deps.Apps, deps.env, deps.service
end

local function Main()
	local Store = { MaxMacros = 32, Path = "dex-explorer/input-macros.json" }
	local maxBytes = 4 * 1024 * 1024

	function Store.Available()
		return type(env.isfile) == "function" and type(env.readfile) == "function" and type(env.writefile) == "function"
	end

	function Store.Exists()
		if not Store.Available() then
			return false
		end
		local ok, exists = pcall(env.isfile, Store.Path)
		return ok and exists == true
	end

	local function validHotkey(name)
		if name == nil then
			return true
		end
		if type(name) ~= "string" or #name > 32 or name == "Unknown" or name == "F8" then
			return false
		end
		local ok, item = pcall(function()
			return Enum.KeyCode[name]
		end)
		return ok and item ~= nil
	end

	local function validate(macros)
		if type(macros) ~= "table" or #macros > Store.MaxMacros then
			return false
		end
		local count = 0
		for key, macro in pairs(macros) do
			count += 1
			if
				type(key) ~= "number"
				or key % 1 ~= 0
				or key < 1
				or key > #macros
				or type(macro) ~= "table"
				or type(macro.Name) ~= "string"
				or #macro.Name > 96
				or not macro.Name:find("%S")
				or not utf8.len(macro.Name)
				or type(macro.Loop) ~= "boolean"
				or type(macro.Speed) ~= "number"
				or not (macro.Speed >= 0.25 and macro.Speed <= 4)
				or not validHotkey(macro.Hotkey)
				or not Apps.MacroEngine.Validate(macro.Events)
			then
				return false
			end
		end
		return count == #macros
	end

	function Store.Load()
		if not Store.Exists() then
			return {}
		end
		local ok, raw = pcall(env.readfile, Store.Path)
		if not ok or type(raw) ~= "string" or #raw > maxBytes then
			return {}, "Could not read saved macros"
		end
		local decoded, data = pcall(service.HttpService.JSONDecode, service.HttpService, raw)
		if not decoded or type(data) ~= "table" or data.Version ~= 1 or not validate(data.Macros) then
			return {}, "Invalid macro file"
		end
		return data.Macros
	end

	function Store.Save(macros)
		if not Store.Available() then
			return false, "File storage unavailable"
		end
		if not validate(macros) then
			return false, "Invalid macro data"
		end
		local ok, data = pcall(service.HttpService.JSONEncode, service.HttpService, { Version = 1, Macros = macros })
		if not ok or #data > maxBytes then
			return false, "Macro file exceeds the storage limit"
		end
		local written, result = pcall(env.writefile, Store.Path, data)
		if not written or result == false then
			return false, "Could not save macros"
		end
		return true
	end

	return Store
end

return { InitDeps = InitDeps, Main = Main }
