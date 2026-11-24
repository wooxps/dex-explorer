--!strict

------------------------------ Module ------------------------------

local function Main()
	local History = { SnapshotDelay = 0.5 }
	local Stack = {}
	Stack.__index = Stack
	local function selection(range)
		if not range then
			return { { -1, -1 }, { -1, -1 } }
		end
		return { { range[1][1], range[1][2] }, { range[2][1], range[2][2] } }
	end
	local function copy(state)
		local additional = {}
		for index, range in ipairs(state.additional or {}) do
			local result = selection(range)
			if range.Caret then
				result.Caret = { range.Caret[1], range.Caret[2] }
			end
			additional[index] = result
		end
		return {
			text = state.text or "",
			x = state.x or 0,
			y = state.y or 0,
			selection = selection(state.selection),
			additional = additional,
		}
	end
	function Stack:_discardRedo()
		while self._pointer < #self._entries do
			self._bytes -= #self._entries[#self._entries].text
			table.remove(self._entries)
		end
	end
	function Stack:_trim()
		local minimum = self._pending and 1 or 2
		while
			#self._entries > minimum
			and (#self._entries + (self._pending and 1 or 0) > self._maxSize or self:bytes() > self._maxBytes)
		do
			self._bytes -= #self._entries[1].text
			table.remove(self._entries, 1)
			self._pointer -= 1
		end
	end
	function Stack:reset(state)
		self._entries = { copy(state) }
		self._pointer = 1
		self._bytes = #self._entries[1].text
		self._pending = nil
		self._lastEdit = nil
	end
	function Stack:push(state)
		self._pending = nil
		self._lastEdit = nil
		self:_discardRedo()
		local entry = copy(state)
		table.insert(self._entries, entry)
		self._bytes += #entry.text
		self._pointer = #self._entries
		self:_trim()
		return entry
	end
	function Stack:flush()
		local pending = self._pending
		if pending then
			self:push(pending)
		end
		self._lastEdit = nil
	end
	function Stack:record(state, now)
		now = now or os.clock()
		if self._pending and now - self._lastEdit >= History.SnapshotDelay then
			self:flush()
		end
		self:_discardRedo()
		local current = self._entries[self._pointer]
		if state.text == current.text then
			self._pending = nil
			self._lastEdit = nil
			self:updateSelection(state)
		else
			self._pending = copy(state)
			self._lastEdit = now
			self:_trim()
		end
	end
	function Stack:updateSelection(state)
		local current = self._pending or self._entries[self._pointer]
		if not current or current.text ~= state.text then
			return
		end
		current.x, current.y = state.x or 0, state.y or 0
		current.selection = selection(state.selection)
		current.additional = copy(state).additional
	end
	function Stack:undo()
		self:flush()
		if self._pointer <= 1 then
			return nil
		end
		self._pointer -= 1
		return self._entries[self._pointer]
	end
	function Stack:redo()
		self:flush()
		if #self._entries <= self._pointer then
			return nil
		end
		self._pointer += 1
		return self._entries[self._pointer]
	end
	function Stack:canUndo()
		return self._pending ~= nil or 1 < self._pointer
	end
	function Stack:canRedo()
		return self._pending == nil and self._pointer < #self._entries
	end
	function Stack:bytes()
		return self._bytes + (self._pending and #self._pending.text or 0)
	end
	function Stack:count()
		return #self._entries + (self._pending and 1 or 0)
	end
	function History.new(state, options)
		options = options or {}
		local self = setmetatable(
			{ _maxSize = math.max(2, options.MaxSize or 100), _maxBytes = options.MaxBytes or 8 * 1024 * 1024 },
			Stack
		)
		self:reset(state or { text = "" })
		return self
	end
	return History
end
return { Main = Main }
