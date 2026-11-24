--!strict

local Apps, API, RMD, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, API, RMD, Settings = d.Apps, d.API, d.RMD, d.Settings
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
	local function clipboardProperty(prop, value)
		local kind = prop.ValueType.Name
		local text = tostring(value)
		if prop.ValueType.Category == "Enum" then return Enum[kind][text] end
		if kind == "bool" then
			if text == "true" then return true elseif text == "false" then return false end
			return nil
		end
		if kind == "Color3" or kind == "NumberSequence" or kind == "ColorSequence" then
			local numbers = {}
			for token in text:gmatch("[^,%s]+") do table.insert(numbers, assert(tonumber(token))) end
			if kind == "Color3" then
				if #numbers == 3 then return Color3.new(table.unpack(numbers)) end
				return nil
			end
			local points = {}
			local stride = if kind == "ColorSequence" then 5 else 3
			if #numbers % stride ~= 0 then return nil end
			for i = 1, #numbers, stride do
				if kind == "ColorSequence" then
					table.insert(points, ColorSequenceKeypoint.new(numbers[i], Color3.new(numbers[i+1], numbers[i+2], numbers[i+3])))
				else
					table.insert(points, NumberSequenceKeypoint.new(numbers[i], numbers[i+1], numbers[i+2]))
				end
			end
			return if kind == "ColorSequence" then ColorSequence.new(points) else NumberSequence.new(points)
		end
		if kind == "BrickColor" then return BrickColor.new(text) end
		if kind == "ContentId" then return text end
		if kind == "NumberRange" then text = text:match("^%s*(.-)%s*$"):gsub("%s*,%s*", ","):gsub("%s+", ",") end
		return Apps.PropertyValueCodec.Parse(kind, text)
	end

	function Service.ApplyClipboard(object, row)
		for key, value in pairs(row) do
			if type(key) ~= "string" or type(value) == "table" then continue end
			local prefix, name = key:sub(1, 1), key:sub(2)
			if prefix == "$" or prefix == "." then
				if name == "" or name:sub(1, 3) == "RBX" then continue end
				if prefix == "$" then
					pcall(Apps.History.Attribute, object, name, value)
				elseif type(value) == "boolean" then
					pcall(Apps.History.Tag, object, name, value)
				end
			elseif key ~= "Parent" and key ~= "ClassName" then
				local prop = Service.GetProperty(object.ClassName, key)
				local tags = prop and prop.Tags or {}
				if prop and not tags.ReadOnly and not tags.NotScriptable and not tags.Hidden
					and (not prop.Security or prop.Security.Write == "None") then
					local ok, parsed = pcall(clipboardProperty, prop, value)
					if ok and parsed ~= nil then pcall(Apps.History.Set, object, key, parsed) end
				end
			end
		end
	end

	return Service
end
return { InitDeps = InitDeps, Main = Main }
