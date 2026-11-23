--!strict

local Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps = d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local Service = {}
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
