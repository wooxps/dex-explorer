--!strict

------------------------------ Types ------------------------------

type Callback<T...> = (T...) -> ()

export type Connection = {
	Connected: boolean,
	Disconnect: (Connection) -> (),
}

export type Type<T...> = {
	Connect: (Type<T...>, Callback<T...>) -> Connection,
	Once: (Type<T...>, Callback<T...>) -> Connection,
	Fire: (Type<T...>, T...) -> (),
	Destroy: (Type<T...>) -> (),
}

------------------------------ Module ------------------------------

local function Main()
	local Signal = {}

	function Signal.new<T...>(): Type<T...>
		local listeners: { [Connection]: Callback<T...>? } = {}
		local signal = {}

		function signal.Connect(_self: Type<T...>, callback: Callback<T...>): Connection
			local connection = { Connected = true }

			function connection.Disconnect(self: Connection): ()
				self.Connected = false
				listeners[self] = nil
			end

			listeners[connection] = callback
			return connection
		end

		function signal.Once(self: Type<T...>, callback: Callback<T...>): Connection
			local connection: Connection
			connection = self:Connect(function(...: T...)
				connection:Disconnect()
				callback(...)
			end)
			return connection
		end

		function signal.Fire(_self: Type<T...>, ...: T...): ()
			local snapshot: { { Connection: Connection, Callback: Callback<T...> } } = {}
			for connection, callback in listeners do
				if not callback then
					continue
				end
				table.insert(snapshot, { Connection = connection, Callback = callback })
			end

			for _, item in snapshot do
				if not item.Connection.Connected then
					continue
				end

				local ok, problem = pcall(item.Callback, ...)
				if not ok then
					warn(`[Dex Explorer] Signal callback: {problem}`)
				end
			end
		end

		function signal.Destroy(_self: Type<T...>): ()
			for connection in listeners do
				connection.Connected = false
			end
			table.clear(listeners)
		end

		return signal
	end

	return table.freeze(Signal)
end

return table.freeze({
	Main = Main,
})
