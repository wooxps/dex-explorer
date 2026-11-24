--!strict

local API, env, Main

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	API, env, Main = d.API, d.env or {}, d.Main
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Session = {}
	local function snapshot(value)
		return {
			Data = setmetatable({ value }, typeof(value) == "Instance" and { __mode = "v" } or nil),
			IsInstance = typeof(value) == "Instance",
		}
	end
	local function unpackSnapshot(saved)
		if not saved or saved.IsInstance and saved.Data[1] == nil then
			return false
		end
		return true, saved.Data[1]
	end
	function Session.Restore(event)
		if not event or (event.Kind ~= "Property" and event.Kind ~= "Attribute") then
			return false, "This event cannot be restored."
		end
		local object = event.Object and event.Object[1]
		if not object then
			return false, "The object is no longer available."
		end
		local beforeOK, before = unpackSnapshot(event.BeforeValue)
		local afterOK, after = unpackSnapshot(event.AfterValue)
		if not beforeOK or not afterOK or event.BeforeKnown == false then
			return false, "The previous value is not available."
		end
		local ok, problem = pcall(function()
			local current
			if event.Kind == "Attribute" then
				current = object:GetAttribute(event.Name)
			else
				current = object[event.Name]
			end
			if current ~= after then
				error("The value changed again. Select its latest event before restoring.", 0)
			end
			if event.Kind == "Attribute" then
				object:SetAttribute(event.Name, before)
			else
				object[event.Name] = before
			end
		end)
		return ok, ok and "Previous value restored." or tostring(problem)
	end
	function Session.Format(value)
		if value == nil then
			return "nil"
		end
		if typeof(value) == "Instance" then
			local ok, path = pcall(function()
				return value:GetFullName()
			end)
			return ok and path or value.Name
		end
		local text = tostring(value):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
		if #text > 300 then
			text = text:sub(1, 297) .. "..."
		end
		return type(value) == "string" and '"' .. text .. '"' or text
	end
	local classProperties = {}
	local function propertiesFor(className)
		if classProperties[className] then
			return classProperties[className]
		end
		local names, canonical, seen = {}, {}, {}
		local class = API.Classes[className]
		while class and not seen[class] do
			seen[class] = true
			for _, property in pairs(class.Properties or {}) do
				local name = property.Name
				if name and name:lower() ~= "source" and name:lower() ~= "parent" then
					local key = name:lower()
					local old = canonical[key]
					if not old or name:match("^%u") and not old:match("^%u") then
						canonical[key] = name
					end
				end
			end
			class = type(class.Superclass) == "table" and class.Superclass or API.Classes[class.Superclass]
		end
		if not canonical.name then
			canonical.name = "Name"
		end
		for _, name in pairs(canonical) do
			names[#names + 1] = name
		end
		classProperties[className] = names
		return names
	end
	local function read(object, key)
		local ok, value = pcall(function()
			return object[key]
		end)
		if not ok and type(env.gethiddenproperty) == "function" then
			return pcall(env.gethiddenproperty, object, key)
		end
		return ok, value
	end
	function Session.Create(options)
		options = options or {}
		local clock = options.Clock or os.clock
		local capacity = options.Capacity or 500
		local self = {
			Running = false,
			Paused = false,
			Count = 0,
			Dropped = 0,
			Revision = 0,
			ReadableProperties = 0,
			WatchedObjects = 0,
			PendingObjects = 0,
		}
		local records, roots, ring, pending, order, queue, queued, removing, addedKeys, removedKeys, sampling =
			{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
		local sampleIndex = 1
		local first, head, tail = 1, 1, 0
		local target
		local started = clock()
		local function reference(object)
			return setmetatable({ object }, { __mode = "v" })
		end
		local function inside(object)
			if not target or not object then
				return false
			end
			local ok, result = pcall(function()
				return object == target or object:IsDescendantOf(target)
			end)
			return ok and result and not (Main and Main.IsDexGuiObject and Main.IsDexGuiObject(object))
		end
		local function connect(bucket, signal, callback)
			local ok, connection = pcall(function()
				return signal:Connect(callback)
			end)
			if ok then
				bucket[#bucket + 1] = connection
			end
			return ok
		end
		local function disconnect(bucket)
			for _, connection in ipairs(bucket) do
				connection:Disconnect()
			end
			table.clear(bucket)
		end
		local function detach(object)
			local record = records[object]
			if not record then
				return
			end
			disconnect(record.Connections)
			self.ReadableProperties -= record.PropertyCount
			self.WatchedObjects -= 1
			records[object] = nil
			local index = record.SampleIndex
			local last = sampling[#sampling]
			sampling[index] = last
			sampling[#sampling] = nil
			if last and last ~= record then
				last.SampleIndex = index
			end
		end
		local function disconnectAll()
			disconnect(roots)
			for object in pairs(records) do
				detach(object)
			end
			table.clear(queue)
			table.clear(queued)
			table.clear(removing)
			table.clear(addedKeys)
			table.clear(removedKeys)
			head = 1
			tail = 0
			self.PendingObjects = 0
			sampleIndex = 1
		end
		local function append(event)
			event.Id = self.Revision + 1
			if self.Count < capacity then
				ring[(first + self.Count - 1) % capacity + 1] = event
				self.Count += 1
			else
				ring[first] = event
				first = first % capacity + 1
				self.Dropped += 1
			end
			self.Revision += 1
		end
		local function collect(key, kind, name, before, after, object, known)
			if not self.Running or self.Paused then
				return
			end
			local event = pending[key]
			if event then
				event.After = Session.Format(after)
				event.AfterValue = snapshot(after)
				event.Changes += 1
				return event
			end
			if #order >= 256 then
				self.Dropped += 1
				return
			end
			event = {
				Kind = kind,
				Name = name,
				Before = known == false and "Not observed" or Session.Format(before),
				After = Session.Format(after),
				BeforeKnown = known ~= false,
				BeforeValue = snapshot(before),
				AfterValue = snapshot(after),
				Time = clock() - started,
				Changes = 1,
				Object = reference(object or target),
				ObjectName = (object or target).Name,
				ObjectPath = Session.Format(object or target),
			}
			pending[key] = event
			order[#order + 1] = key
			return event
		end
		local function enqueue(object)
			if records[object] or queued[object] or not inside(object) then
				return
			end
			tail += 1
			queue[tail] = object
			queued[object] = true
			self.PendingObjects += 1
		end
		local function attach(object)
			if records[object] or not inside(object) then
				return
			end
			local record = {
				Connections = {},
				Properties = {},
				Attributes = {},
				Keys = {},
				PropertyCount = 0,
				Parent = object.Parent,
				Names = {},
				Canonical = {},
				NameIndex = 1,
				LastSample = clock(),
			}
			sampling[#sampling + 1] = record
			record.SampleIndex = #sampling
			records[object] = record
			self.WatchedObjects += 1
			local function remember(name, value)
				if not record.Properties[name] then
					record.PropertyCount += 1
					self.ReadableProperties += 1
					record.Names[#record.Names + 1] = name
					record.Canonical[name:lower()] = name
				end
				record.Properties[name] = snapshot(value)
			end
			for _, name in ipairs(propertiesFor(object.ClassName)) do
				local ok, value = read(object, name)
				if ok then
					remember(name, value)
				end
			end
			local valueBase = object:IsA("ValueBase")
			if valueBase and not record.Properties.Value then
				local ok, value = read(object, "Value")
				if ok then
					remember("Value", value)
				end
			end
			local function changed(name, sampled)
				if not sampled then
					if not inside(object) or type(name) ~= "string" then
						return
					end
					local lower = name:lower()
					if lower == "parent" or lower == "source" then
						return
					end
					name = record.Canonical[lower] or name
				end
				local ok, value = read(object, name)
				if not ok then
					return
				end
				local previous = record.Properties[name]
				local known, before = unpackSnapshot(previous)
				if not known or before ~= value then
					remember(name, value)
					local key = "Property:" .. name
					record.Keys[key] = record.Keys[key] or {}
					collect(record.Keys[key], "Property", name, before, value, object, known)
				end
			end
			if valueBase then
				for name in pairs(record.Properties) do
					local ok, signal = pcall(function()
						return object:GetPropertyChangedSignal(name)
					end)
					if ok then
						connect(record.Connections, signal, function()
							changed(name)
						end)
					end
				end
			else
				connect(record.Connections, object.Changed, changed)
			end
			local ok, attributes = pcall(function()
				return object:GetAttributes()
			end)
			if ok then
				for name, value in pairs(attributes) do
					record.Attributes[name] = snapshot(value)
				end
			end
			local function attributeChanged(name, sampled, currentValue)
				if not sampled and not inside(object) then
					return
				end
				local good, value = true, currentValue
				if not sampled then
					good, value = pcall(function()
						return object:GetAttribute(name)
					end)
				end
				if not good then
					return
				end
				local previous = record.Attributes[name]
				local _, before = unpackSnapshot(previous)
				if before ~= value then
					record.Attributes[name] = value ~= nil and snapshot(value) or nil
					local key = "Attribute:" .. name
					record.Keys[key] = record.Keys[key] or {}
					collect(record.Keys[key], "Attribute", name, before, value, object, true)
				end
			end
			connect(record.Connections, object.AttributeChanged, function(name)
				attributeChanged(name, false)
			end)
			record.Sample = function()
				if not inside(object) then
					return
				end
				for _ = 1, math.min(16, #record.Names) do
					if record.NameIndex > #record.Names then
						record.NameIndex = 1
					end
					changed(record.Names[record.NameIndex], true)
					record.NameIndex += 1
				end
				local good, current = pcall(function()
					return object:GetAttributes()
				end)
				if good then
					for name, value in pairs(current) do
						attributeChanged(name, true, value)
					end
					local deleted = {}
					for name in pairs(record.Attributes) do
						if current[name] == nil then
							deleted[#deleted + 1] = name
						end
					end
					for _, name in ipairs(deleted) do
						attributeChanged(name, true, nil)
					end
				end
			end
			record.Keys.Parent = {}
			connect(record.Connections, object.AncestryChanged, function(moved, newParent)
				if moved ~= object or record.Parent == newParent then
					return
				end
				local before = record.Parent
				record.Parent = newParent
				if removing[object] then
					return
				end
				collect(record.Keys.Parent, "Parent", "Parent", before, newParent, object, true)
			end)
			local childrenOK, children = pcall(function()
				return object:GetChildren()
			end)
			if childrenOK then
				for _, child in ipairs(children) do
					enqueue(child)
				end
			end
		end
		local function added(object, direct)
			if not inside(object) then
				return
			end
			if addedKeys[object] then
				return
			end
			addedKeys[object] = {}
			collect(
				addedKeys[object],
				direct and "Child added" or "Descendant added",
				object.Name,
				nil,
				object.Parent,
				object,
				false
			)
			enqueue(object)
		end
		local function removed(object, direct)
			if Main and Main.IsDexGuiObject and Main.IsDexGuiObject(object) then
				return
			end
			if removedKeys[object] then
				local existing = pending[removedKeys[object]]
				if existing and direct then
					existing.Direct = true
					existing.Kind = "Child removed"
					existing.Before = Session.Format(target)
					existing.BeforeKnown = true
				end
				return
			end
			removedKeys[object] = {}
			local record = records[object]
			local before = direct and target or record and record.Parent or object.Parent
			local event = collect(
				removedKeys[object],
				direct and "Child removed" or "Descendant removed",
				object.Name,
				before,
				nil,
				object,
				direct or before ~= nil
			)
			if event then
				event.ResolveParent = true
				event.Direct = direct
			end
			removing[object] = true
		end
		local function attachRoot()
			attach(target)
			connect(roots, target.ChildAdded, function(object)
				added(object, true)
			end)
			connect(roots, target.ChildRemoved, function(object)
				removed(object, true)
			end)
			connect(roots, target.DescendantAdded, function(object)
				added(object, object.Parent == target)
			end)
			connect(roots, target.DescendantRemoving, function(object)
				local record = records[object]
				removed(object, object.Parent == target or record ~= nil and record.Parent == target)
			end)
			connect(roots, target.Destroying, function()
				self:Flush()
				append({
					Kind = "Stopped",
					Name = "Object destroyed",
					Before = "",
					After = "",
					Time = clock() - started,
					Changes = 1,
				})
				self.Running = false
				self.Paused = false
				disconnectAll()
				target = nil
				self.Target = nil
			end)
		end
		function self:Step()
			if not self.Running or self.Paused then
				return
			end
			local deadline = os.clock() + 0.002
			local count = 0
			while head <= tail and count < 24 and os.clock() < deadline do
				local object = queue[head]
				queue[head] = nil
				head += 1
				queued[object] = nil
				self.PendingObjects -= 1
				attach(object)
				count += 1
			end
			if head > tail then
				table.clear(queue)
				head = 1
				tail = 0
			end
			for _ = 1, math.min(8, #sampling) do
				if os.clock() >= deadline then
					break
				end
				if sampleIndex > #sampling then
					sampleIndex = 1
				end
				local record = sampling[sampleIndex]
				sampleIndex += 1
				if clock() - record.LastSample >= 0.25 then
					record.LastSample = clock()
					record.Sample()
				end
			end
		end
		function self:Flush()
			self:Step()
			for _, key in ipairs(order) do
				local event = pending[key]
				if event then
					if event.ResolveParent then
						local object = event.Object and event.Object[1]
						local ok, parent = pcall(function()
							return object and object.Parent
						end)
						event.After = ok and Session.Format(parent) or "Unavailable"
						if ok and parent ~= nil then
							event.Kind = event.Direct and "Child moved" or "Descendant moved"
						end
						event.ResolveParent = nil
						event.Direct = nil
					end
					append(event)
				end
			end
			table.clear(order)
			table.clear(pending)
			table.clear(addedKeys)
			table.clear(removedKeys)
			for object in pairs(removing) do
				if not inside(object) then
					detach(object)
				end
			end
			table.clear(removing)
		end
		function self:Events()
			local result = {}
			for index = 1, self.Count do
				result[index] = ring[(first + index - 2) % capacity + 1]
			end
			return result
		end
		function self:Clear()
			table.clear(ring)
			table.clear(pending)
			table.clear(order)
			table.clear(addedKeys)
			table.clear(removedKeys)
			first = 1
			self.Count = 0
			self.Dropped = 0
			started = clock()
			self.Revision += 1
		end
		function self:Start(object)
			self:Stop()
			self:Clear()
			table.clear(classProperties)
			target = object
			self.Target = object
			self.Running = true
			self.Paused = false
			attachRoot()
		end
		function self:Pause(paused)
			if not self.Running or self.Paused == paused then
				return
			end
			self:Flush()
			self.Paused = paused
			disconnectAll()
			if not paused then
				attachRoot()
			else
				connect(roots, target.Destroying, function()
					self:Stop()
				end)
			end
			append({
				Kind = paused and "Paused" or "Resumed",
				Name = paused and "Recording paused" or "Recording resumed",
				Before = "",
				After = "",
				Time = clock() - started,
				Changes = 1,
			})
		end
		function self:Stop()
			self:Flush()
			disconnectAll()
			self.Running = false
			self.Paused = false
			target = nil
			self.Target = nil
		end
		function self:Destroy()
			self:Stop()
			self:Clear()
		end
		return self
	end
	return Session
end
return { InitDeps = InitDeps, Main = CreateModule }
