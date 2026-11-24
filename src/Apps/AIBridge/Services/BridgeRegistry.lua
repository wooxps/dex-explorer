--!strict

------------------------------ Module ------------------------------

local function Main()
	local Registry = {}
	function Registry.Create(options)
		local owner = options.Main or {}
		local apps = options.Apps or {}
		local root = options.Game or game
		local nextId = 0
		local destroyed = false
		local maximum = options.Maximum or 50000
		local ids = setmetatable({}, { __mode = "k" })
		local objects = setmetatable({}, { __mode = "v" })
		local registry = {}
		function registry:Allowed(object)
			if destroyed or typeof(object) ~= "Instance" then
				return false
			end
			if owner.IsDexGuiObject and owner.IsDexGuiObject(object) then
				return false
			end
			if apps.SelectionGeometryMask and apps.SelectionGeometryMask.IsInternal(object) then
				return false
			end
			return object == root or object:IsDescendantOf(root)
		end
		function registry:Id(object)
			assert(self:Allowed(object), "INSTANCE_UNAVAILABLE: instance is outside this client session")
			if ids[object] then
				return ids[object]
			end
			assert(nextId < maximum, "HANDLE_LIMIT: reconnect the bridge to start a new handle session")
			nextId += 1
			local id = "i" .. nextId
			ids[object] = id
			objects[id] = object
			return id
		end
		function registry:Resolve(id)
			assert(type(id) == "string" and #id <= 32, "INVALID_ARGUMENT: instanceId must be a session handle")
			local object = objects[id]
			assert(self:Allowed(object), "STALE_INSTANCE: instance no longer exists in this client session")
			return object
		end
		function registry:Editable(object)
			assert(self:Allowed(object) and object ~= root, "INVALID_TARGET: target cannot be edited")
			assert(
				not (apps.Explorer and apps.Explorer.IsInferredObject and apps.Explorer.IsInferredObject(object)),
				"INFERRED_READ_ONLY: reconstructed server entries cannot be edited through Dex MCP"
			)
			local class = apps.ReflectionService and apps.ReflectionService.GetClass(object.ClassName)
			return not (class and class.Tags and class.Tags.Service)
		end
		function registry:Describe(object)
			local inferred = apps.Explorer and apps.Explorer.IsInferredObject and apps.Explorer.IsInferredObject(object)
			local children = object:GetChildren()
			local count = 0
			for _, child in ipairs(children) do
				if self:Allowed(child) then
					count += 1
				end
			end
			return {
				id = self:Id(object),
				name = object.Name,
				className = object.ClassName,
				parentId = object.Parent and self:Allowed(object.Parent) and self:Id(object.Parent) or nil,
				childCount = count,
				provenance = inferred and "reconstructed" or "client_visible",
			}
		end
		function registry:Destroy()
			destroyed = true
			table.clear(ids)
			table.clear(objects)
		end
		return registry
	end
	return Registry
end
return { Main = Main }
