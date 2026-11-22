--!strict

------------------------------ Types ------------------------------

type Checkpoint = () -> ()
type Visit = (id: number) -> ()
type SparseVisit = (id: number) -> boolean?
type SparseFields = {
	Words: { [number]: number? },
	Count: number,
}

type Dense = {
	Size: number,
	Data: buffer,
	Count: number,
	Prefix: { number }?,
	Has: (Dense, number?) -> boolean,
	Set: (Dense, number, boolean?) -> boolean,
	Clone: (Dense) -> Dense,
	ClearRange: (Dense, number, number) -> (),
	Prepare: (Dense, Checkpoint?) -> Dense,
	Rank: (Dense, number) -> number,
	Select: (Dense, number) -> number?,
	Each: (Dense, Visit, Checkpoint?) -> (),
}

------------------------------ Module ------------------------------

local function Main()
	local Bits = {}
	local band, bor, bxor, rshift, lshift = bit32.band, bit32.bor, bit32.bxor, bit32.rshift, bit32.lshift
	local function pop(x: number): number
		x = x - band(rshift(x, 1), 0x55555555)
		x = band(x, 0x33333333) + band(rshift(x, 2), 0x33333333)
		x = band(x + rshift(x, 4), 0x0f0f0f0f)
		return band(x + rshift(x, 8) + rshift(x, 16) + rshift(x, 24), 255)
	end
	Bits.Pop = pop
	local Sparse = {}
	local sparseMeta = { __index = Sparse }
	function Bits.Sparse()
		local fields: SparseFields = { Words = {}, Count = 0 }
		return setmetatable(fields, sparseMeta)
	end
	function Sparse.Has(self: SparseFields, id: number?): boolean
		if not id or id < 1 then
			return false
		end
		local w = (id - 1) // 32 + 1
		return band(self.Words[w] or 0, lshift(1, (id - 1) % 32)) ~= 0
	end
	function Sparse.Set(self: SparseFields, id: number, on: boolean?): boolean
		local w = (id - 1) // 32 + 1
		local b = lshift(1, (id - 1) % 32)
		local old = self.Words[w] or 0
		local value = if on == false then band(old, bxor(b, 0xffffffff)) else bor(old, b)
		if old == value then
			return false
		end
		self.Words[w] = if value ~= 0 then value else nil
		self.Count += on == false and -1 or 1
		return true
	end
	function Sparse.Clone(self: SparseFields)
		local out = Bits.Sparse()
		out.Words = table.clone(self.Words)
		out.Count = self.Count
		return out
	end
	function Sparse.Each(self: SparseFields, fn: SparseVisit, checkpoint: Checkpoint?): boolean
		local work = 0
		for word, value in self.Words do
			while value ~= 0 do
				local low = band(value, -value)
				local bit = 31 - bit32.countlz(low)
				if fn((word - 1) * 32 + bit + 1) == false then
					return false
				end
				value = band(value, value - 1)
				work += 1
				if checkpoint and work % 128 == 0 then
					checkpoint()
				end
			end
		end
		return true
	end
	function Sparse.And(self: SparseFields, other: SparseFields)
		local out = Bits.Sparse()
		for word, value in self.Words do
			local v = band(value, other.Words[word] or 0)
			if v ~= 0 then
				out.Words[word] = v
				out.Count += pop(v)
			end
		end
		return out
	end
	function Bits.Dense(size: number): Dense
		local words = math.ceil(size / 32)
		local s = { Size = size, Data = buffer.create(words * 4), Count = 0, Prefix = nil :: { number }? }
		function s.Has(self: Dense, id: number?): boolean
			return if id
				then id and id >= 1 and id <= self.Size and band(
					buffer.readu32(self.Data, ((id - 1) // 32) * 4),
					lshift(1, (id - 1) % 32)
				) ~= 0
				else false
		end
		function s.Set(self: Dense, id: number, on: boolean?): boolean
			assert(id >= 1 and id <= self.Size, "Membership position outside snapshot")
			local offset = ((id - 1) // 32) * 4
			local b = lshift(1, (id - 1) % 32)
			local old = buffer.readu32(self.Data, offset)
			local value = if on == false then band(old, bxor(b, 0xffffffff)) else bor(old, b)
			if value == old then
				return false
			end
			buffer.writeu32(self.Data, offset, value)
			self.Count += on == false and -1 or 1
			self.Prefix = nil
			return true
		end
		function s.Clone(self: Dense): Dense
			local out = Bits.Dense(self.Size)
			buffer.copy(out.Data, 0, self.Data)
			out.Count = self.Count
			return out
		end
		function s.ClearRange(self: Dense, first: number, last: number): ()
			first = math.max(1, first)
			last = math.min(self.Size, last)
			if last < first then
				return
			end
			local a, b = (first - 1) // 32, (last - 1) // 32
			for word = a, b do
				local low = word == a and (first - 1) % 32 or 0
				local high = word == b and (last - 1) % 32 or 31
				local mask = band(lshift(0xffffffff, low), rshift(0xffffffff, 31 - high))
				local old = buffer.readu32(self.Data, word * 4)
				local value = band(old, bxor(mask, 0xffffffff))
				buffer.writeu32(self.Data, word * 4, value)
				self.Count -= pop(old) - pop(value)
			end
			self.Prefix = nil
		end
		function s.Prepare(self: Dense, checkpoint: Checkpoint?): Dense
			local prefix = table.create(words, 0)
			local count = 0
			for word = 1, words do
				count += pop(buffer.readu32(self.Data, (word - 1) * 4))
				prefix[word] = count
				if checkpoint and word % 128 == 0 then
					checkpoint()
				end
			end
			self.Prefix = prefix
			self.Count = count
			return self
		end
		function s.Rank(self: Dense, id: number): number
			if id < 1 or self.Size == 0 then
				return 0
			end
			id = math.min(id, self.Size)
			if not self.Prefix then
				self:Prepare()
			end
			if self.Count == self.Size and id % 1 == 0 then return id end
			local prefix = assert(self.Prefix)
			local word = (id - 1) // 32 + 1
			local mask = rshift(0xffffffff, 31 - (id - 1) % 32)
			return (prefix[word - 1] or 0) + pop(band(buffer.readu32(self.Data, (word - 1) * 4), mask))
		end
		local lastWord = 1
		function s.Select(self: Dense, rank: number): number?
			if rank % 1 ~= 0 or rank < 1 or rank > self.Count then
				return nil
			end
			if not self.Prefix then
				self:Prepare()
			end
			if self.Count == self.Size then return rank end
			local prefix = assert(self.Prefix)
			local word = lastWord
			if rank <= (prefix[word - 1] or 0) or rank > prefix[word] then
				local low = (rank - 1) // 32 + 1
				local high = (rank - 1 + self.Size - self.Count) // 32 + 1
				while low < high do
					local mid = (low + high) // 2
					if prefix[mid] < rank then
						low = mid + 1
					else
						high = mid
					end
				end
				word = low
				lastWord = word
			end
			local offset = (word - 1) * 32
			local value = buffer.readu32(self.Data, (word - 1) * 4)
			local nth = rank - (prefix[word - 1] or 0)
			if value == 0xffffffff then return offset + nth end
			for _ = 1, nth - 1 do
				value = band(value, value - 1)
			end
			return offset + bit32.countrz(value) + 1
		end
		function s.Each(self: Dense, fn: Visit, checkpoint: Checkpoint?): ()
			if self.Count == 0 and self.Prefix then return end
			for word = 0, words - 1 do
				local value = buffer.readu32(self.Data, word * 4)
				while value ~= 0 do
					local bit = 31 - bit32.countlz(band(value, -value))
					fn(word * 32 + bit + 1)
					value = band(value, value - 1)
				end
				if checkpoint and word % 128 == 0 then
					checkpoint()
				end
			end
		end
		return s
	end
	return table.freeze(Bits)
end
return { InitDeps = function() end, InitAfterMain = function() end, Main = Main }
