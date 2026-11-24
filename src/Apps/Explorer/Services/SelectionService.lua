--!strict

local Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps = d.Apps
end
------------------------------ Module ------------------------------

local function Main()
	local Service = {}
	function Service.NewStore()
		local store = { List = {}, Map = {}, Changed = Apps.Signal.new(), ShiftSet = {} }
		function store:SetTable(values)
			local list, map = {}, {}
			for _, value in ipairs(values) do
				if value ~= nil and not map[value] and not value.Del then
					list[#list + 1] = value
					map[value] = true
				end
			end
			local same = #list == #self.List
			if same then
				for index, value in ipairs(list) do
					if self.List[index] ~= value then
						same = false
						break
					end
				end
			end
			if same then
				return
			end
			self.List, self.Map = list, map
			self.Changed:Fire()
		end
		function store:Set(value)
			self:SetTable(value and { value } or {})
		end
		function store:Clear()
			self:SetTable({})
		end
		function store:Add(value)
			if value and not self.Map[value] then
				local list = table.clone(self.List)
				list[#list + 1] = value
				self:SetTable(list)
			end
		end
		function store:AddTable(values)
			local list = table.clone(self.List)
			for _, value in ipairs(values) do
				list[#list + 1] = value
			end
			self:SetTable(list)
		end
		function store:Remove(value)
			self:RemoveTable({ value })
		end
		function store:RemoveTable(values)
			local removed = {}
			for _, value in ipairs(values) do
				removed[value] = true
			end
			local list = {}
			for _, value in ipairs(self.List) do
				if not removed[value] then
					list[#list + 1] = value
				end
			end
			self:SetTable(list)
		end
		return store
	end
	function Service.Bind(store, resolve)
		local selection = { SelectionChanged = store.Changed }
		function selection:Get()
			local objects = {}
			for _, node in ipairs(store.List) do
				objects[#objects + 1] = node.Obj
			end
			return objects
		end
		function selection:Set(objects)
			local values = {}
			for _, object in ipairs(objects) do
				local node = resolve(object)
				assert(node and not node.Del, "Selecting an instance outside the Explorer session")
				values[#values + 1] = node
			end
			store:SetTable(values)
		end
		return selection
	end
	return Service
end
return { InitDeps = InitDeps, Main = Main }
