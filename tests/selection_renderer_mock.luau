--!strict

-- Deterministic hierarchy/property signal double, not a Roblox renderer.
task.spawn = function(callback, ...)
	return coroutine.wrap(callback)(...)
end
local allSignals = {}
signal = function()
	local s = { Handlers = {}, Active = 0 }
	function s:Connect(fn)
		local entry = { Fn = fn, Active = true }
		self.Handlers[#self.Handlers + 1] = entry
		self.Active += 1
		return {
			Disconnect = function()
				if entry.Active then
					entry.Active = false
					self.Active -= 1
				end
			end,
		}
	end
	function s:Fire(...)
		local snapshot = table.clone(self.Handlers)
		for _, entry in ipairs(snapshot) do
			if entry.Active then
				entry.Fn(...)
			end
		end
	end
	allSignals[#allSignals + 1] = s
	return s
end
local function activeSignals()
	local n = 0
	for _, s in ipairs(allSignals) do
		n += s.Active
	end
	return n
end
local oldIndex = instMT.__index
instMT.__index = function(o, k)
	if k == "ChildRemoved" then
		o._events[k] = o._events[k] or signal()
		return o._events[k]
	end
	return oldIndex(o, k)
end
local oldNewIndex = instMT.__newindex
instMT.__newindex = function(o, k, v)
	local old = o._props[k]
	if old == v then
		return
	end
	if k == "Parent" then
		local descendants = o:GetDescendants()
		table.insert(descendants, 1, o)
		local ancestor = old
		while ancestor do
			for _, child in ipairs(descendants) do
				ancestor.DescendantRemoving:Fire(child)
			end
			ancestor = ancestor.Parent
		end
		oldNewIndex(o, k, v)
		if old then
			old.ChildRemoved:Fire(o)
		end
		if v then
			v.ChildAdded:Fire(o)
		end
		ancestor = v
		while ancestor do
			for _, child in ipairs(descendants) do
				ancestor.DescendantAdded:Fire(child)
			end
			ancestor = ancestor.Parent
		end
		for _, child in ipairs(descendants) do
			child.AncestryChanged:Fire(child, child.Parent)
		end
	else
		oldNewIndex(o, k, v)
	end
	if o._signals[k] then
		o._signals[k]:Fire()
	end
end
local originalNew = Instance.new
Instance.new = function(class, parent)
	local o = originalNew(class)
	if class == "Part" then
		o.Transparency = 0
		o.LocalTransparencyModifier = 0
	end
	o.GetPivot = function()
		return { Position = { Marker = true } }
	end
	o.Parent = parent
	return o
end
service.Workspace = workspace
local projection = { X = 120.4, Y = 80.6, Z = 10 }
local onScreen = true
workspace.CurrentCamera = {
	WorldToScreenPoint = function(_, p)
		assert(p.Marker)
		return projection, onScreen
	end,
}
service.RunService = { RenderStepped = signal() }
local function drain()
	for _ = 1, 5 do
		flushTasks()
	end
end
local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end
local function childCount(o, class)
	local n = 0
	for _, child in ipairs(o:GetChildren()) do
		if child:IsA(class) then
			n += 1
		end
	end
	return n
end
