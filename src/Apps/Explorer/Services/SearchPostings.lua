--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Bits = Apps.SearchBits
	local Postings = {}
	function Postings.Create()
		local p = {
			Names = {},
			NameBlocks = {},
			Ids = {},
			Groups = {},
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
			for term, bits in pairs(self.NodeCache) do
				if self.Cache[term]:Has(nameId) then
					bits:Set(id)
				end
			end
		end
		function p:RemoveMember(nameId, id)
			local group = self.Groups[nameId]
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
			local compared
			if candidate and best * 4 < #names * 3 then
				candidate:Each(function(id)
					if string.find(names[id], term, 1, true) then
						result:Set(id)
					end
				end, checkpoint)
				compared = candidate.Count
			elseif #term >= 3 and #names >= 1024 then
				compared = 0
				for first = 1, #names, 128 do
					local last = math.min(first + 127, #names)
					local block = (first - 1) // 128 + 1
					local text = self.NameBlocks[block]
					if not text then
						text = table.concat(names, "\0", first, last)
						if last == first + 127 then
							self.NameBlocks[block] = text
						end
					end
					if string.find(text, term, 1, true) then
						for id = first, last do
							if string.find(names[id], term, 1, true) then
								result:Set(id)
							end
						end
						compared += last - first + 1
					end
					if checkpoint then
						checkpoint()
					end
				end
			else
				for id, name in ipairs(names) do
					if string.find(name, term, 1, true) then
						result:Set(id)
					end
					if checkpoint and id % 128 == 0 then
						checkpoint()
					end
				end
				compared = #names
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
			local result
			for _, term in ipairs(terms) do
				local bits = self:Lookup(term, checkpoint)
				result = result and result:And(bits) or bits
				if checkpoint then
					checkpoint()
				end
			end
			return result or Bits.Sparse()
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
			local complete = matching:Each(function(nameId)
				local group = self.Groups[nameId]
				if type(group) == "number" then
					nodes:Set(group)
				elseif group then
					if limit and group.Count > limit then
						nodes.Count = group.Count
						return false
					end
					for word, value in pairs(group.Words) do
						local previous = words[word] or 0
						words[word] = bit32.bor(previous, value)
						nodes.Count += Bits.Pop(bit32.band(value, bit32.bnot(previous)))
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
			end, checkpoint)
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
	InitAfterMain = function() end,
	Main = Main,
}
