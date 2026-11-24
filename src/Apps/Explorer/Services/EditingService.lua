--!strict

local Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps = d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local Service = {}
	function Service.Rename(object, name)
		assert(type(name) == "string" and name ~= "", "Instance name cannot be empty")
		return Apps.History.Set(object, "Name", name)
	end
	function Service.SetProperty(objects, property, value)
		return Apps.History.Run("Set " .. property, function()
			for _, object in ipairs(objects) do
				Apps.History.Set(object, property, value)
			end
		end)
	end
	function Service.Reparent(objects, parent)
		for _, object in ipairs(objects) do
			assert(
				object ~= parent and (not parent or not parent:IsDescendantOf(object)),
				"Cannot parent an instance into its own hierarchy"
			)
		end
		return Service.SetProperty(objects, "Parent", parent)
	end
	return Service
end
return { InitDeps = InitDeps, Main = Main }
