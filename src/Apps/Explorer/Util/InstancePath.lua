--!strict

local Lib, API, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(dependencies)
	Lib, API, Settings = dependencies.Lib, dependencies.API, dependencies.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local InstancePath = {}
	InstancePath.Build = function(obj: Instance): string
		local ffc = game.FindFirstChild
		local getCh = game.GetChildren
		local path = ""
		local curObj: Instance? = obj
		local ts = tostring
		local match = string.match
		local tableFind = table.find
		local useGetCh = Settings.Explorer.CopyPathUseGetChildren
		local formatLuaString = Lib.FormatLuaString

		while curObj do
			if curObj == game then
				path = "game" .. path
				break
			end

			local className = curObj.ClassName
			local curName = ts(curObj)
			local indexName
			if match(curName, "^[%a_][%w_]*$") then
				indexName = "." .. curName
			else
				local cleanName = formatLuaString(curName)
				indexName = '["' .. cleanName .. '"]'
			end

			local parObj = curObj.Parent
			if parObj then
				local fc = ffc(parObj, curName)
				if useGetCh and fc and fc ~= curObj then
					local parCh = getCh(parObj)
					local fcInd = tableFind(parCh, curObj)
					indexName = ":GetChildren()[" .. fcInd .. "]"
				elseif parObj == game and API.Classes[className] and API.Classes[className].Tags.Service then
					indexName = ':GetService("' .. className .. '")'
				end
			elseif parObj == nil then
				local getnil =
					"local getNil = function(name, class) for _, v in next, getnilinstances() do if v.ClassName == class and v.Name == name then return v end end end"
				local gotnil = '\n\ngetNil("%s", "%s")'
				indexName = getnil .. gotnil:format(curObj.Name, className)
			end

			path = indexName .. path
			curObj = parObj
		end

		return path
	end

	return InstancePath
end
return { InitDeps = InitDeps, Main = Main }
