--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Engine = {}
	local function keyFor(terms)
		local parts = {}
		for _, term in ipairs(terms) do
			parts[#parts + 1] = tostring(#term) .. ":" .. term
		end
		return table.concat(parts)
	end
	function Engine.Create(context)
		local e = {
			Generation = 0,
			Busy = false,
			ResultCache = {},
			ResultOrder = {},
			Stats = { Queries = 0, Cancelled = 0, Yields = 0, MaxSlice = 0, ResultCacheHits = 0 },
		}
		context.TreeResults = true
		e.Snapshots = Apps.SearchSnapshot.Create(context)
		function e:Ready()
			local state = self.Snapshots.State
			if not state or state.Sorting ~= context.Sorting() or state.Scope ~= context.Scope() then
				return false
			end
			if state.MaxId > state.Live * 2 + 8192 or state.Postings.Stats.Names > state.Live * 2 + 8192 then
				return false
			end
			local roots = context.Roots()
			if #roots ~= #state.RootNodes then
				return false
			end
			for i, root in ipairs(roots) do
				if root ~= state.RootNodes[i] then
					return false
				end
			end
			return true
		end
		function e:Mark(node, subtree, reason)
			self.Snapshots:Mark(node, subtree, reason)
			local view = self.LastResult
			if not view or not self.LastTerms then
				return true
			end
			if view:Contains(node) then
				return true
			end
			if subtree and #node > 0 then
				return true
			end
			if node.Del then
				return false
			end
			local ok, name = pcall(function()
				return string.lower(node.Obj.Name)
			end)
			if not ok then
				return true
			end
			for _, term in ipairs(self.LastTerms) do
				if not name:find(term, 1, true) then
					return false
				end
			end
			return true
		end
		function e:HasChanges()
			return next(self.Snapshots.Pending) ~= nil
		end
		local cancelled = {}
		function e:Search(predicate, terms, valid, warm, fallbackLimit)
			self.Generation += 1
			local generation = self.Generation
			local function current()
				return context.Alive() and (warm or generation == self.Generation and valid())
			end
			if not warm then
				self.WaitingGeneration = generation
			end
			while self.Busy do
				if not current() then
					return nil
				end
				context.Wait()
			end
			if not current() then
				return nil
			end
			if not warm then
				self.WaitingGeneration = nil
			end
			local function budget()
				if warm and self.WaitingGeneration ~= self.Generation then
					return self.Snapshots.State and 0.001 or 0.003
				end
				return 0.004
			end
			self.Busy = true
			local deadline = os.clock() + budget()
			local slice = os.clock()
			local function checkpoint()
				if not context.Alive() or not current() then
					error(cancelled, 0)
				end
				local now = os.clock()
				if now >= deadline then
					self.Stats.MaxSlice = math.max(self.Stats.MaxSlice, now - slice)
					self.Stats.Yields += 1
					context.Wait()
					slice = os.clock()
					deadline = slice + budget()
					if not current() then
						error(cancelled, 0)
					end
				end
			end
			local ok, value, useFallback = pcall(function()
				local state = self.Snapshots:Refresh(checkpoint)
				if self.CacheDictionary ~= state.Postings then
					table.clear(self.ResultCache)
					table.clear(self.ResultOrder)
					self.CacheDictionary = state.Postings
					self.ObservedVersion = state.Version
				elseif self.ObservedVersion ~= state.Version then
					local changes = self.Snapshots:ChangesSince(self.ObservedVersion)
					for _, cached in pairs(self.ResultCache) do
						if not changes then
							cached.Invalid = true
						else
							for id in pairs(changes) do
								cached.Changes[id] = true
							end
						end
					end
					self.ObservedVersion = state.Version
				end
				if warm then
					return true
				end
				local members = Apps.SearchBits.Sparse()
				local cacheKey, cached
				if terms then
					cacheKey = keyFor(terms)
					cached = self.ResultCache[cacheKey]
					if cached and cached.State == state then
						local result = Apps.SearchTreeResults.Create(state, nil, context, checkpoint, cached.Seed, {})
						checkpoint()
						self.Stats.ResultCacheHits += 1
						self.Stats.Queries += 1
						self.LastResult, self.LastTerms = result, terms
						return result
					end
					if fallbackLimit and #terms == 1 and state.Postings:ExceedsLimit(terms[1], fallbackLimit) then
						return nil, true
					end
					local candidate, names = state.Postings:NodeCandidates(terms, checkpoint, fallbackLimit)
					if not candidate then
						return nil, true
					end
					members = candidate
					context.MemberCheck = function(entry)
						return names:Has(entry.NameId)
					end
				else
					for id = 1, state.MaxId do
						local entry = state.Entries[id]
						if entry and entry.Queryable then
							local readable, match =
								pcall(predicate, context.Object and context.Object(entry.Node) or entry.Node.Obj)
							if readable and match then
								members:Set(id)
							end
						end
						if id % 32 == 0 then
							checkpoint()
						end
					end
				end
				local changes = cached and not cached.Invalid and cached.Changes or nil
				local result =
					Apps.SearchTreeResults.Create(state, members, context, checkpoint, cached and cached.Seed, changes)
				context.MemberCheck = nil
				checkpoint()
				if cacheKey then
					local at = table.find(self.ResultOrder, cacheKey)
					if at then
						table.remove(self.ResultOrder, at)
					end
					if #self.ResultOrder >= 8 then
						self.ResultCache[table.remove(self.ResultOrder, 1)] = nil
					end
					self.ResultOrder[#self.ResultOrder + 1] = cacheKey
					self.ResultCache[cacheKey] = { State = state, Seed = result.Seed, Changes = {} }
				end
				self.Stats.Queries += 1
				self.LastResult, self.LastTerms = result, terms
				return result
			end)
			context.MemberCheck = nil
			self.Busy = false
			if not ok then
				if value == cancelled then
					self.Stats.Cancelled += 1
					return nil
				end
				error(value, 0)
			end
			return value, useFallback
		end
		function e:Warm()
			if self.Busy or self:Ready() and not self:HasChanges() then
				return
			end
			return self:Search(nil, nil, function()
				return true
			end, true)
		end
		return e
	end
	return Engine
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,

	Main = Main,
}
