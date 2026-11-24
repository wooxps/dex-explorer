--!strict

local function getCanonicalNames(properties)
	local names = {}
	for _, property in ipairs(properties) do
		if property.Name:match("^%u") then
			names[string.lower(property.Name)] = property
		end
	end
	return names
end

------------------------------ Module ------------------------------

local function Main()
	local PropertySchema = {}

	function PropertySchema.GetReadableProperties(object, classData, ignoredProperties)
		local result = {}
		local canonicalNames = getCanonicalNames(classData.Properties)
		for _, property in ipairs(classData.Properties) do
			local canonical = canonicalNames[string.lower(property.Name)]
			local isLegacyAlias = canonical ~= nil
				and canonical.Name ~= property.Name
				and canonical.ValueType.Name == property.ValueType.Name
			if not ignoredProperties[property.Name] and not isLegacyAlias then
				local readable = pcall(function()
					return object[property.Name]
				end)
				if readable then
					table.insert(result, property)
				end
			end
		end
		return result
	end

	return PropertySchema
end

return { Main = Main }
