--!strict

local function Main()
	local observers = {}
	local source
	local function dispatch(object, property)
		local listeners = observers[property]
		if not listeners then return end
		for _, listener in ipairs(listeners) do
			if listener.Connected and (not listener.Members or listener.Members[object]) then
				if #listeners == 1 then
					listener.Callback(object, property)
				else
					task.spawn(listener.Callback, object, property)
				end
			end
		end
	end
	local Changes = {}
	function Changes.For(properties, members)
		local signal = {}
		function signal:Connect(callback)
			if not source then source = game.ItemChanged:Connect(dispatch) end
			local listener = { Connected = true, Callback = callback, Members = members }
			for property in pairs(properties) do
				local list = observers[property] and table.clone(observers[property]) or {}
				list[#list + 1] = listener
				observers[property] = list
			end
			function listener:Disconnect()
				if not self.Connected then return end
				self.Connected = false
				for property in pairs(properties) do
					local list = observers[property]
					if #list == 1 then
						observers[property] = nil
					else
						local remaining = table.clone(list)
						table.remove(remaining, table.find(list, self))
						observers[property] = remaining
					end
				end
				self.Callback, self.Members = nil, nil
				if not next(observers) and source then
					source:Disconnect()
					source = nil
				end
			end
			return listener
		end
		return signal
	end
	return Changes
end

return { Main = Main }
