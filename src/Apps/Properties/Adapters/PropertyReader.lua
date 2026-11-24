--!strict

local function isUsableUniqueId(value): boolean
	if value == nil then
		return false
	end
	local compact = tostring(value):gsub("[%s%-%{%}]", "")
	return #compact == 32 and compact:match("^%x+$") ~= nil and compact:find("[1-9a-fA-F]") ~= nil
end

local function readUniqueId(object, readProperty, readHiddenProperty)
	local success, value = pcall(readProperty, object, "UniqueId")
	if success and isUsableUniqueId(value) then
		return value
	end
	if readHiddenProperty then
		success, value = pcall(readHiddenProperty, object, "UniqueId")
		if success and isUsableUniqueId(value) then
			return value
		end
	end
	return nil
end

------------------------------ Module ------------------------------

local function Main()
	local PropertyReader = {}

	function PropertyReader.Create(options)
		local typeNames = options.TypeNames
		local readProperty = options.ReadProperty or function(object, name)
			return object[name]
		end
		local readAttribute = options.ReadAttribute or game.GetAttribute
		local readHiddenProperty = options.ReadHiddenProperty
		local reader = {}

		function reader.Read(property, object)
			if property.MultiType then
				return "<Multiple Types>"
			end
			if object == nil then
				return nil
			end

			local value
			if property.IsAttribute then
				local success, attribute = pcall(readAttribute, object, property.AttributeName)
				if not success or attribute == nil then
					return nil
				end
				local actualType = typeNames[typeof(attribute)] or typeof(attribute)
				local expectedType = property.RootType or property.ValueType
				if expectedType.Name ~= actualType then
					return nil
				end
				value = attribute
			elseif property.Name == "UniqueId" then
				value = readUniqueId(object, readProperty, readHiddenProperty)
			else
				local success, result = pcall(readProperty, object, property.Name)
				if not success then
					return nil
				end
				value = result
			end

			if property.SubName then
				for _, name in ipairs(string.split(property.SubName, ".")) do
					if name ~= "" then
						if value == nil then
							return nil
						end
						local success, component = pcall(function()
							return value[name]
						end)
						if not success then
							return nil
						end
						value = component
					end
				end
			end
			return value
		end

		return reader
	end

	return PropertyReader
end

return { Main = Main }
