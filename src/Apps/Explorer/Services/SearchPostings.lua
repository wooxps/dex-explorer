--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Bits = Apps.SearchBits
	local Postings = {}
	local function BlockPrefix(names: { string }, first: number, last: number): string
		local prefix = string.sub(names[first], 1, 64)
		for index = last, first + 1, -1 do
			local name = names[index]
			if string.find(name, prefix, 1, true) ~= 1 then
				local length = 0
				for byteIndex = 1, math.min(#prefix, #name) do
					if string.byte(prefix, byteIndex) ~= string.byte(name, byteIndex) then break end
					length = byteIndex
				end
				if length == 0 then return "" end
				prefix = string.sub(prefix, 1, length)
			end
		end
		return prefix
	end
	function Postings.Create()
		local p = {
			Names = {},
			NameBlocks = {},
			BlockPrefixes = {},
			Ids = {},
			Groups = {},
			LinearBlocks = {},
			Cache = {},
			NodeCache = {},
			BroadCounts = {},
			CacheOrder = {},
			Stats = { Names = 0, Comparisons = 0, CacheHits = 0 },
		}
		local function contains(name, term)
			return string.find(name, term, 1, true) ~= nil
		end
		function p:Intern(raw, checkpoint)
			local name = string.lower(raw)
			local id = self.Ids[name]
			if id then
				return id
			end
			id = #self.Names + 1
			self.Names[id] = name
			self.Ids[name] = id
			self.Stats.Names += 1
			if id % 128 == 0 then
				self.NameBlocks[id // 128] = table.concat(self.Names, "\0", id - 127, id)
			end
			for term, bits in pairs(self.Cache) do
				if contains(name, term) then
					bits:Set(id)
				end
			end
			if checkpoint and id % 64 == 0 then
				checkpoint()
			end
			return id
		end
		function p:AddMember(nameId, id)
			local group = self.Groups[nameId]
			if not group then
				self.Groups[nameId] = id
			elseif type(group) == "number" then
				if group ~= id then
					local bits = Bits.Sparse()
					bits:Set(group)
					bits:Set(id)
					self.Groups[nameId] = bits
				end
			else
				group:Set(id)
			end
			local block = (nameId - 1) // 32 + 1
			self.LinearBlocks[block] = nil
			if not group and nameId % 32 == 0 then
				local first = id - 31
				local consecutive = true
				for offset = 1, 31 do
					if self.Groups[nameId - offset] ~= id - offset then
						consecutive = false
						break
					end
				end
				if consecutive then self.LinearBlocks[block] = first end
			end
			for term, bits in pairs(self.NodeCache) do
				if self.Cache[term]:Has(nameId) then
					bits:Set(id)
				end
			end
		end
		function p:RemoveMember(nameId, id)
			local group = self.Groups[nameId]
			self.LinearBlocks[(nameId - 1) // 32 + 1] = nil
			table.clear(self.BroadCounts)
			for _, bits in pairs(self.NodeCache) do
				bits:Set(id, false)
			end
			if type(group) == "number" then
				if group == id then
					self.Groups[nameId] = nil
				end
			elseif group then
				group:Set(id, false)
				if group.Count == 0 then
					self.Groups[nameId] = nil
				elseif group.Count == 1 then
					group:Each(function(value)
						self.Groups[nameId] = value
					end)
				end
			end
		end
		function p:Members(nameId, fn, checkpoint)
			local group = self.Groups[nameId]
			if type(group) == "number" then
				fn(group)
			elseif group then
				group:Each(fn, checkpoint)
			end
		end
		function p:Lookup(term, checkpoint)
			term = string.lower(term)
			local cached = self.Cache[term]
			if cached then
				self.Stats.CacheHits += 1
				return cached
			end
			local candidate
			local best = math.huge
			for cachedTerm, bits in pairs(self.Cache) do
				if bits.Count < best and string.find(term, cachedTerm, 1, true) then
					candidate = bits
					best = bits.Count
				end
			end
			local result = Bits.Sparse()
			local names = self.Names
			local compared = 0
			local eligible = candidate and best * 4 < #names * 3 and candidate.Words
			local function scanWords(first, last)
				compared += last - first + 1
				for start = first, last, 32 do
					local mask = 0
					local word = (start - 1) // 32 + 1
					local pending = eligible and (eligible[word] or 0)
					if pending and pending ~= 0xffffffff then
						compared -= math.min(32, last - start + 1) - Bits.Pop(pending)
						while pending ~= 0 do
							local bit = bit32.band(pending, -pending)
							local id = start + bit32.countrz(bit)
							if string.find(names[id], term, 1, true) then mask = bit32.bor(mask, bit) end
							pending -= bit
						end
					else
						for id = start, math.min(start + 31, last) do
							if string.find(names[id], term, 1, true) then
								mask = bit32.bor(mask, bit32.lshift(1, id - start))
							end
						end
					end
					if mask ~= 0 then
						result.Words[word] = mask
						result.Count += Bits.Pop(mask)
					end
				end
			end
			if eligible and (best <= #names // 64 or #names < 1024) then
				candidate:Each(function(id)
					if string.find(names[id], term, 1, true) then
						result:Set(id)
					end
				end, checkpoint)
				compared = candidate.Count
			elseif #names >= 1024 then
				local commonShortTerm = #term < 3 and contains(names[1], term)
					and contains(names[#names // 2], term) and contains(names[#names], term)
				for first = 1, #names, 128 do
					local last = math.min(first + 127, #names)
					local block = (first - 1) // 128 + 1
					local text = self.NameBlocks[block]
					if commonShortTerm or not text or string.find(text, term, 1, true) then
						local prefix = self.BlockPrefixes[block]
						if prefix == nil and text and contains(names[first], term) and contains(names[last], term) then
							prefix = BlockPrefix(names, first, last)
							self.BlockPrefixes[block] = prefix
						end
						if prefix and contains(prefix, term) then
							local word = (first - 1) // 32 + 1
							for offset = 0, 3 do
								result.Words[word + offset] = 0xffffffff
							end
							result.Count += 128
						else
							scanWords(first, last)
						end
					end
					if checkpoint then
						checkpoint()
					end
				end
			else
				for first = 1, #names, 128 do
					scanWords(first, math.min(first + 127, #names))
					if checkpoint then checkpoint() end
				end
			end
			self.Stats.Comparisons += compared
			if #self.CacheOrder >= 12 then
				local oldest = table.remove(self.CacheOrder, 1)
				self.Cache[oldest] = nil
				self.NodeCache[oldest] = nil
				self.BroadCounts[oldest] = nil
			end
			self.CacheOrder[#self.CacheOrder + 1] = term
			self.Cache[term] = result
			return result
		end
		function p:Candidates(terms, checkpoint)
			if #terms == 0 then return Bits.Sparse() end
			if #terms == 1 then return self:Lookup(terms[1], checkpoint) end
			local normalized = table.create(#terms)
			local first, best = 1, math.huge
			for i, term in ipairs(terms) do
				local lower = string.lower(term)
				normalized[i] = lower
				local cached = self.Cache[lower]
				local cost = cached and cached.Count or #self.Names + 1
				if cost < best or (cost == best and #lower > #normalized[first]) then
					first, best = i, cost
				end
			end
			local result = self:Lookup(normalized[first], checkpoint)
			for i, term in ipairs(normalized) do
				if result.Count == 0 then break end
				if i == first or contains(normalized[first], term) then continue end
				local bits = self.Cache[term]
				if not bits and result.Count <= #self.Names // 16 then
					local narrowed = Bits.Sparse()
					result:Each(function(id)
						if contains(self.Names[id], term) then narrowed:Set(id) end
					end, checkpoint)
					self.Stats.Comparisons += result.Count
					result = narrowed
				else
					bits = bits or self:Lookup(term, checkpoint)
					result = if result.Count <= bits.Count then result:And(bits) else bits:And(result)
				end
				if checkpoint then checkpoint() end
			end
			return result
		end
		function p:ExceedsLimit(term, limit)
			for cachedTerm, candidate in pairs(self.NodeCache) do
				if candidate.Count > limit and contains(cachedTerm, term) then
					return true
				end
			end
			for cachedTerm, count in pairs(self.BroadCounts) do
				if count > limit and contains(cachedTerm, term) then
					return true
				end
			end
			return false
		end
		function p:NodeCandidates(terms, checkpoint, limit)
			local term = #terms == 1 and terms[1] or nil
			local matching = self:Candidates(terms, checkpoint)
			local cached = term and self.NodeCache[term]
			if cached then
				if limit and cached.Count > limit then
					return nil, matching
				end
				return cached, matching
			end
			local nodes = Bits.Sparse()
			local words = nodes.Words
			local work = 0
			local function mergeWord(word: number, value: number)
				local previous = words[word] or 0
				words[word] = bit32.bor(previous, value)
				nodes.Count += Bits.Pop(bit32.band(value, bit32.bnot(previous)))
			end
			local function addGroup(nameId: number): boolean
				local group = self.Groups[nameId]
				if type(group) == "number" then
					nodes:Set(group)
				elseif group then
					if limit and group.Count > limit then
						nodes.Count = group.Count
						return false
					end
					for word, value in pairs(group.Words) do
						mergeWord(word, value)
						if limit and nodes.Count > limit then
							return false
						end
						work += 1
						if checkpoint and work % 128 == 0 then
							checkpoint()
						end
					end
				end
				return not limit or nodes.Count <= limit
			end
			local complete = true
			for block, mask in matching.Words do
				local first = self.LinearBlocks[block]
				if first then
					local word = (first - 1) // 32 + 1
					local shift = (first - 1) % 32
					local low = bit32.lshift(mask, shift)
					if low ~= 0 then mergeWord(word, low) end
					if shift ~= 0 then
						local high = bit32.rshift(mask, 32 - shift)
						if high ~= 0 then mergeWord(word + 1, high) end
					end
					complete = not limit or nodes.Count <= limit
				else
					while mask ~= 0 do
						local nameId = (block - 1) * 32 + bit32.countrz(mask) + 1
						if not addGroup(nameId) then complete = false break end
						mask = bit32.band(mask, mask - 1)
					end
				end
				if not complete then break end
				work += 1
				if checkpoint and work % 16 == 0 then checkpoint() end
			end
			if not complete then
				if term then
					self.BroadCounts[term] = nodes.Count
				end
				return nil, matching
			end
			if term then
				self.NodeCache[term] = nodes
			end
			return nodes, matching
		end
		return p
	end
	return Postings
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,

	Main = Main,
}
