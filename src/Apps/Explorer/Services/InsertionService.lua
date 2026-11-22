--!strict

local Apps, MainApp, Settings, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, MainApp, Settings, service = d.Apps, d.Main, d.Settings, d.service
end
------------------------------ Module ------------------------------

local function Main()
	local Service = {}
	local cached = {}
	local function presets()
		Settings.Explorer.InstanceDefaults = Settings.Explorer.InstanceDefaults or {}
		return Settings.Explorer.InstanceDefaults
	end
	function Service.HasDefault(className)
		return presets()[className] ~= nil
	end
	function Service.ResetDefault(className)
		presets()[className] = nil
		cached[className] = nil
		MainApp.SaveSettings()
	end
	local function configurable(object, prop)
		local key, tags = prop.Name, prop.Tags or {}
		if tags.ReadOnly or tags.Hidden or tags.Deprecated or tags.NotScriptable then return false end
		if prop.Serialization and prop.Serialization.CanSave == false and prop.Serialization.CanLoad == false then return false end
		if prop.Security and prop.Security.Write and prop.Security.Write ~= "None" then return false end
		if key == "Parent" or key == "Name" or key == "Source" or key == "Origin" or key == "WorldPivot" then return false end
		if object:IsA("BasePart") and (key == "Position" or key == "CFrame" or key == "Orientation"
			or key == "Rotation" or key == "BrickColor" or key == "AssemblyLinearVelocity" or key == "AssemblyAngularVelocity") then return false end
		if object:IsA("Attachment") and (key == "Axis" or key == "SecondaryAxis" or key == "Position"
			or key == "Orientation" or string.sub(key, 1, 5) == "World") then return false end
		return prop.ValueType.Category ~= "Class"
	end
	function Service.SaveDefault(object)
		local className = object.ClassName
		assert(Apps.ReflectionService.CanCreate(className))
		local class = Apps.ReflectionService.GetClass(className)
		local codec = Apps.BridgeValueCodec.Create()
		local fresh = Instance.new(className)
		local overrides = {}
		for base, props in Apps.Explorer and Apps.Explorer.DefaultProps or {} do
			if object:IsA(base) then
				for key in props do overrides[key] = true end
			end
		end
		local saved = {}
		local success, problem = pcall(function()
			while class do
				for _, prop in class.Properties or {} do
					if configurable(object, prop) then
						local ok, value = Apps.ReflectionService.Read(object, prop.Name)
						if ok and value ~= nil and typeof(value) ~= "Instance" and (overrides[prop.Name] or fresh[prop.Name] ~= value) then
							if type(value) == "string" then
								saved[prop.Name] = value
							elseif type(value) == "number" and math.abs(value) == math.huge then
								saved[prop.Name] = { Infinity = math.sign(value) }
							else
								local encoded = codec:Encode(value)
								assert(type(encoded) ~= "table" or encoded.type ~= "Unsupported", "Cannot save default for " .. prop.Name)
								saved[prop.Name] = encoded
							end
						end
					end
				end
				class = class.Superclass
			end
		end)
		fresh:Destroy()
		if not success then error(problem, 0) end
		local json = service.HttpService:JSONEncode(saved)
		presets()[className] = json
		cached[className] = nil
		MainApp.SaveSettings()
	end
	local function applyDefault(object)
		local className = object.ClassName
		local json = Settings and Settings.Explorer and Settings.Explorer.InstanceDefaults
		json = json and json[className]
		if type(json) ~= "string" then return end
		local record = cached[className]
		if not record or record.Json ~= json then
			local codec = Apps.BridgeValueCodec.Create()
			local values = {}
			for key, value in service.HttpService:JSONDecode(json) do
				local prop = Apps.ReflectionService.GetProperty(className, key)
				if prop and configurable(object, prop) then
					if type(value) == "string" then values[key] = value
					elseif type(value) == "table" and (value.Infinity == -1 or value.Infinity == 1) then
						values[key] = math.huge * value.Infinity
					else
						values[key] = codec:Decode(value)
					end
				end
			end
			record = { Json = json, Values = values }
			cached[className] = record
		end
		for key, value in record.Values do
			if object[key] ~= value then object[key] = value end
		end
	end
	function Service.Insert(className, targets, options)
		assert(Apps.ReflectionService.CanCreate(className), "Class is not insertable: " .. tostring(className))
		options = options or {}
		local created = {}
		local ok, problem = pcall(Apps.History.Run, "Insert " .. className, function()
			for _, node in ipairs(targets) do
				assert(not node.Del, "Insert target no longer exists")
				local object = Instance.new(className)
				created[#created + 1] = object
				Apps.History.Set(object, "Parent", node.Obj)
				for class, properties in pairs(options.DefaultProperties or {}) do
					if object:IsA(class) then
						for property, value in pairs(properties) do
							if type(value) == "function" then
								value = value(object)
							end
							object[property] = value
						end
					end
				end
				applyDefault(object)
				if options.GetName then
					object.Name = options.GetName(node.Obj, object.Name)
				end
				if options.Reveal then
					options.Reveal(node)
				end
			end
		end)
		if not ok then
			for _, object in ipairs(created) do
				object:Destroy()
			end
			error(problem, 0)
		end
		return created
	end
	return Service
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = Main }
