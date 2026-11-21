--!strict

local API, RMD, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	API, RMD, Settings = d.API, d.RMD, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Service = {}
	local function marked(value)
		return value == true or value == "true"
	end
	function Service.GetMetadata(name, property)
		local seen = {}
		while name and not seen[name] do
			seen[name] = true
			local metadata = RMD.Classes[name]
			if metadata and (not property or metadata.Properties and metadata.Properties[property]) then
				return property and metadata.Properties[property] or metadata
			end
			local class = API.Classes[name]
			local parent = class and class.Superclass
			name = type(parent) == "table" and parent.Name or parent
		end
	end
	function Service.GetSummary(name, property)
		local metadata = Service.GetMetadata(name, property)
		local summary = metadata and (metadata.Summary or metadata.Description)
		return type(summary) == "string" and summary ~= "" and summary or nil
	end
	function Service.IsVisible(name, property, showHidden, showDeprecated)
		local metadata = Service.GetMetadata(name, property)
		if not metadata then
			return true
		end
		return (
			showHidden or not (marked(metadata.Hidden) or metadata.Browsable == false or metadata.Browsable == "false")
		) and (showDeprecated or not marked(metadata.Deprecated))
	end
	function Service.GetClass(name)
		return API.Classes[name]
	end
	function Service.CanCreate(name)
		local class = API.Classes[name]
		return class ~= nil and not class.Tags.NotCreatable and not class.Tags.Service
	end
	function Service.GetCreatableClasses()
		local classes = {}
		local preferences = Settings and Settings.Explorer or {}
		for name, class in pairs(API.Classes) do
			local tags = class.Tags or {}
			if
				Service.CanCreate(name)
				and (preferences.ShowDeprecatedInsertClasses or not tags.Deprecated)
				and (preferences.ShowHiddenInsertClasses or not tags.Hidden)
				and Service.IsVisible(
					name,
					nil,
					preferences.ShowHiddenInsertClasses,
					preferences.ShowDeprecatedInsertClasses
				)
			then
				local metadata = RMD.Classes[name]
				classes[#classes + 1] = { class, metadata and metadata.ClassCategory or "Uncategorized" }
			end
		end
		table.sort(classes, function(a, b)
			if a[2] ~= b[2] then
				return a[2] < b[2]
			end
			return a[1].Name < b[1].Name
		end)
		return classes
	end
	function Service.Read(object, property)
		return pcall(function()
			return object[property]
		end)
	end
	local function clipboardValue(value)
		local kind = typeof(value)
		if kind == "EnumItem" then return value.Name end
		if kind == "Instance" or kind == "buffer" or value == nil then return nil end
		return tostring(value)
	end

	function Service.DescribeForClipboard(object)
		local className = object.ClassName
		local result = { ClassName = className }
		if object.Name ~= className then result.Name = object.Name end
		local class = API.Classes[className]
		while class do
			for _, prop in ipairs(class.Properties or {}) do
				local key, tags = prop.Name, prop.Tags or {}
				if key ~= "Parent" and key ~= "Name" and not tags.ReadOnly and not tags.Hidden
					and not tags.NotScriptable and (not prop.Security or prop.Security.Read == "None")
				then
					local ok, modified = pcall(object.IsPropertyModified, object, key)
					if ok and modified then
						local readable, value = Service.Read(object, key)
						if readable then result[key] = clipboardValue(value) end
					end
				end
			end
			class = class.Superclass
		end
		for key, value in pairs(object:GetAttributes()) do
			local kind = typeof(value)
			if kind == "boolean" or kind == "number" then
				result["$" .. key] = value
			else
				result["$" .. key] = clipboardValue(value)
			end
		end
		for _, tag in ipairs(object:GetTags()) do result["." .. tag] = true end
		return result
	end
	function Service.GetProperty(name, property)
		local seen = {}
		while name and not seen[name] do
			seen[name] = true
			local class = API.Classes[name]
			if not class then
				break
			end
			for _, member in ipairs(class.Properties or {}) do
				if member.Name == property then
					return member
				end
			end
			name = type(class.Superclass) == "table" and class.Superclass.Name or class.Superclass
		end
		return nil
	end
	return Service
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = Main }
