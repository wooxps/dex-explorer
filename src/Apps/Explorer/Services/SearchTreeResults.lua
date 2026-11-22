--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Tree = {}
	local empty = table.freeze({})
	local function record(id, entry, hit, children, keep, checkpoint)
		if not keep and not hit and #children == 0 then
			return nil
		end
		local rows, matches, width, height = entry.Display and 1 or 0, hit and 1 or 0, 0, entry.Display and 1 or 0
		local own = entry.Display and entry.Node.SearchRawName == entry.Name and entry.Node.NameWidth or nil
		local exact = not entry.Display or own ~= nil
		if entry.Display then
			width = own or math.min(100, #entry.Name) * 14
		end
		local rowEnds, matchEnds, indices = empty, empty, empty
		if #children > 0 then
			rowEnds, matchEnds, indices = {}, {}, {}
		end
		for i, child in ipairs(children) do
			rows += child.Rows
			matches += child.Matches
			rowEnds[i] = rows
			matchEnds[i] = matches
			indices[child.Id] = i
			width = math.max(width, child.Width)
			height = math.max(height, (entry.Display and 1 or 0) + child.Height)
			exact = exact and child.Exact
			if checkpoint and i % 128 == 0 then
				checkpoint()
			end
		end
		return {
			Id = id,
			Display = entry.Display,
			Hit = hit,
			Children = children,
			RowEnds = rowEnds,
			MatchEnds = matchEnds,
			Indices = indices,
			Rows = rows,
			Matches = matches,
			Width = width,
			Height = height,
			OwnWidth = own,
			Exact = exact,
		}
	end
	local function selectRecord(items, ends, rank, match)
		local low, high = 1, #items
		while low < high do
			local mid = math.floor((low + high) / 2)
			if ends[mid] < rank then
				low = mid + 1
			else
				high = mid
			end
		end
		local item = items[low]
		if not item then
			return nil
		end
		rank -= ends[low - 1] or 0
		while item do
			local own = match and (item.Hit and 1 or 0) or (item.Display and 1 or 0)
			if rank <= own then
				return item.Id
			end
			local offsets = match and item.MatchEnds or item.RowEnds
			low, high = 1, #item.Children
			while low < high do
				local mid = math.floor((low + high) / 2)
				if offsets[mid] < rank then
					low = mid + 1
				else
					high = mid
				end
			end
			rank -= low > 1 and offsets[low - 1] or own
			item = item.Children[low]
		end
		return nil
	end
	local function sortUniqueNames(children, entries, checkpoint): boolean
		local first = entries[children[1].Id]
		if first.Manual then return false end
		local names, byName = table.create(#children), {}
		for i, child in children do
			local entry = entries[child.Id]
			if entry.Manual or entry.Order ~= first.Order or byName[entry.Name] then return false end
			names[i], byName[entry.Name] = entry.Name, child
			if i % 256 == 0 then checkpoint() end
		end
		local pageSize = 512
		local page = table.create(pageSize)
		for firstIndex = 1, #names, pageSize do
			local last = math.min(firstIndex + pageSize - 1, #names)
			table.clear(page)
			table.move(names, firstIndex, last, 1, page)
			table.sort(page)
			table.move(page, 1, #page, firstIndex, names)
			checkpoint()
		end
		local width = pageSize
		local scratch = if width < #names then table.create(#names) else nil
		while width < #names do
			for start = 1, #names, width * 2 do
				local middle = math.min(start + width, #names + 1)
				local last = math.min(start + width * 2 - 1, #names)
				local left, right = start, middle
				for i = start, last do
					if left < middle and (right > last or names[left] < names[right]) then
						scratch[i] = names[left]
						left += 1
					else
						scratch[i] = names[right]
						right += 1
					end
					if i % 512 == 0 then checkpoint() end
				end
			end
			names, scratch = scratch, names
			width *= 2
		end
		for i, name in names do
			children[i] = byName[name]
			if i % 512 == 0 then checkpoint() end
		end
		return true
	end
	function Tree.Create(state, members, context, checkpoint, previous, changes)
		local old = previous and previous.State
		if old and old.Postings ~= state.Postings then
			previous, old = nil, nil
		end
		if previous and old ~= state and not changes then
			previous, old = nil, nil
		end
		local seed = previous
		if not seed or old ~= state then
			local map = Apps.SearchSnapshot.CopyMap(previous and previous.Map)
			local dirty, dirtyChildren = {}, {}
			local steps = 0
			local function tick()
				steps += 1
				if steps % 64 == 0 then
					checkpoint()
				end
			end
			local function path(id, source)
				while id and id ~= 0 do
					local done = source == state and dirty[id]
					dirty[id] = true
					local entry = source.Entries[id]
					local parent = entry and entry.Parent
					if parent and parent ~= 0 then
						local children = dirtyChildren[parent] or {}
						dirtyChildren[parent] = children
						children[id] = true
					end
					if done then
						break
					end
					id = parent
					tick()
				end
			end
			local function changed(id)
				path(id, state)
				if old then
					path(id, old)
				end
			end
			if previous then
				for id in pairs(changes) do
					changed(id)
					if not state.Entries[id] then
						map[id] = nil
					end
				end
				local visited = {}
				for word, value in pairs(members.Words) do
					local difference = bit32.bxor(value, previous.Members.Words[word] or 0)
					visited[word] = true
					while difference ~= 0 do
						local bit = 31 - bit32.countlz(bit32.band(difference, -difference))
						changed((word - 1) * 32 + bit + 1)
						difference = bit32.band(difference, difference - 1)
					end
					tick()
				end
				for word, value in pairs(previous.Members.Words) do
					if not visited[word] then
						while value ~= 0 do
							local bit = 31 - bit32.countlz(bit32.band(value, -value))
							changed((word - 1) * 32 + bit + 1)
							value = bit32.band(value, value - 1)
						end
					end
					tick()
				end
			else
				members:Each(function(id)
					path(id, state)
				end, checkpoint)
			end
			local rebuilt = 0
			local function less(a, b)
				local x, y = state.Entries[a], state.Entries[b]
				if x.Manual or y.Manual then
					local m, n = x.Manual or math.huge, y.Manual or math.huge
					if m ~= n then
						return m < n
					end
				end
				if x.Order ~= y.Order then
					return x.Order < y.Order
				end
				if x.Name ~= y.Name then
					return x.Name < y.Name
				end
				if x.Class ~= y.Class then
					return x.Class < y.Class
				end
				return x.Key < y.Key
			end
			local function build(id)
				if not dirty[id] then
					return map[id]
				end
				local entry = state.Entries[id]
				if not entry then
					map[id] = nil
					return nil
				end
				if entry.Order == nil then
					local ok = context.Metadata and pcall(context.Metadata, entry)
					if not ok then
						entry.Class, entry.Order = entry.Class or "Instance", 9999
					end
				end
				local children = empty
				local previousItem = map[id]
				if state.Sorting then
					local edits = dirtyChildren[id] or empty
					local count = 0
					for _ in pairs(edits) do
						count += 1
						if count > 64 then
							break
						end
					end
					if previousItem and count <= 64 then
						children = previousItem.Children
						if count > 0 then
							children = table.clone(children)
							local removals = {}
							local additions = {}
							for child in pairs(edits) do
								local at = previousItem.Indices[child]
								if at then
									removals[#removals + 1] = at
								end
								local value = state.Entries[child]
								if value and value.Parent == id then
									local item = build(child)
									if item then
										additions[#additions + 1] = item
									end
								end
								tick()
							end
							table.sort(removals, function(a, b)
								return a > b
							end)
							for _, at in ipairs(removals) do
								table.remove(children, at)
								tick()
							end
							for _, item in ipairs(additions) do
								local low, high = 1, #children + 1
								while low < high do
									local mid = math.floor((low + high) / 2)
									if less(children[mid].Id, item.Id) then
										low = mid + 1
									else
										high = mid
									end
								end
								table.insert(children, low, item)
								tick()
							end
						end
					else
						local ids = edits
						if previousItem then
							ids = table.clone(edits)
							for _, item in ipairs(previousItem.Children) do
								ids[item.Id] = true
								tick()
							end
						end
						for child in pairs(ids) do
							local value = state.Entries[child]
							if value and value.Parent == id then
								local item = build(child)
								if item then
									if children == empty then
										children = {}
									end
									children[#children + 1] = item
								end
							end
							tick()
						end
						local function before(a, b)
							return less(a.Id, b.Id)
						end
						local ordered = true
						for at = 2, #children do
							if before(children[at], children[at - 1]) then
								ordered = false
								break
							end
							tick()
						end
						if not ordered and not (#children >= 256 and sortUniqueNames(children, state.Entries, checkpoint)) then
							for first = 1, #children, 128 do
								local page = {}
								table.move(children, first, math.min(first + 127, #children), 1, page)
								table.sort(page, before)
								table.move(page, 1, #page, first, children)
								checkpoint()
							end
							local width = 128
							while width < #children do
								local merged = {}
								for first = 1, #children, width * 2 do
									local middle = math.min(first + width, #children + 1)
									local last = math.min(first + 2 * width - 1, #children)
									local left, right = first, middle
									for index = first, last do
										if
											left < middle
											and (right > last or not before(children[right], children[left]))
										then
											merged[index] = children[left]
											left += 1
										else
											merged[index] = children[right]
											right += 1
										end
										tick()
									end
								end
								children = merged
								width *= 2
							end
						end
					end
				else
					local siblings = state.Children[id] or empty
					if not previousItem and siblings.Increasing and #siblings >= 512 then
						local candidates = {}
						for child in pairs(dirtyChildren[id] or empty) do
							local childEntry = state.Entries[child]
							if childEntry and childEntry.Parent == id then
								candidates[#candidates + 1] = child
							end
							if #candidates > 128 then
								break
							end
							tick()
						end
						if #candidates <= 128 then
							table.sort(candidates)
							siblings = candidates
						end
					end
					for _, child in ipairs(siblings) do
						local item = build(child)
						if item then
							if children == empty then
								children = {}
							end
							children[#children + 1] = item
						end
						tick()
					end
				end
				local hit = entry.Queryable
						and members:Has(id)
						and (not context.MemberCheck or context.MemberCheck(entry))
					or false
				local item = record(id, entry, hit, children, false, checkpoint)
				map[id] = item
				rebuilt += 1
				tick()
				return item
			end
			for _, id in ipairs(state.RootIds) do
				build(id)
			end
			local packed = buffer.create(math.ceil(state.MaxId / 32) * 4)
			for word, value in pairs(members.Words) do
				buffer.writeu32(packed, (word - 1) * 4, value)
				tick()
			end
			seed =
				{ State = state, Map = map, Members = members:Clone(), Packed = packed, Stats = {}, Rebuilt = rebuilt }
		end
		local result = {
			State = state,
			Seed = seed,
			Pages = {},
			PageOrder = {},
			Resolved = 0,
			Overrides = {},
			Removed = {},
			ExpansionVersion = 0,
			OverrideRevision = 0,
			Allowed = {},
		}
		local function contextItem(node)
			local id = state.Ids[node]
			if not id then
				return nil
			end
			local item = result.ContextItems and result.ContextItems[id]
			if item ~= nil then
				return item or nil
			end
			return seed.Map[id]
		end
		function result:Contains(node)
			local id = state.Ids[node]
			return id and seed.Map[id] ~= nil or false
		end
		function result:HasChildren(node)
			local item = contextItem(node)
			return item ~= nil and #item.Children > 0
		end
		function result:NameOf(node)
			local id = state.Ids[node]
			return id and state.Entries[id].Name
		end
		function result:ParentOf(node)
			local id = state.Ids[node]
			local entry = id and state.Entries[id]
			local parent = entry and state.Entries[entry.Parent]
			return parent and parent.Node
		end
		function result:DepthOf(node)
			local id = state.Ids[node]
			local depth = 0
			while id and id ~= 0 do
				local entry = state.Entries[id]
				if not entry then
					return nil
				end
				if entry.Display then
					depth += 1
				end
				id = entry.Parent
			end
			return depth
		end
		function result:Remove(node)
			if self:Contains(node) and not self.Removed[node] then
				self.Removed[node] = true
				self.ExpansionVersion += 1
			end
		end
		result.Expanded = setmetatable({}, {
			__newindex = function(_, node, value)
				local previousValue = result.Expanded[node]
				if result.Overrides[node] ~= value then
					result.Overrides[node] = value
					result.OverrideRevision += 1
				end
				if result.Expanded[node] ~= previousValue then
					result.ExpansionVersion += 1
				end
			end,
			__index = function(_, node)
				local value = result.Overrides[node]
				if value ~= nil then
					return value
				end
				local id = state.Ids[node]
				local entry = id and state.Entries[id]
				local item = contextItem(node)
				if entry and not entry.Display then
					return true
				end
				return item and (#item.Children > 0 and true or 0) or nil
			end,
		})
		local function roots(map)
			local out = {}
			for _, id in ipairs(state.RootIds) do
				local item = map[id]
				local entry = state.Entries[id]
				if item then
					if not entry.Display then
						for _, child in ipairs(item.Children) do
							if context.Visible(state.Entries[child.Id].Node) then
								out[#out + 1] = child
							end
						end
					elseif context.Visible(entry.Node) then
						out[#out + 1] = item
					end
				end
			end
			return out
		end
		local function offsets(items, match)
			local ends, indices = {}, {}
			local total = 0
			for i, item in ipairs(items) do
				total += match and item.Matches or item.Rows
				ends[i] = total
				indices[item.Id] = i
			end
			return ends, indices, total
		end
		function result:RememberStats(width, depth, exact)
			if next(self.Removed) or next(self.Overrides) then
				return
			end
			seed.Stats[self.VisibilityKey] = { Width = width, Depth = depth, Exact = exact }
		end
		function result:Reflow(check)
			local baseRoots = roots(seed.Map)
			local flags = {}
			for _, item in ipairs(baseRoots) do
				flags[#flags + 1] = tostring(item.Id)
			end
			local key = table.concat(flags, ",")
			if self.AppliedExpansion == self.ExpansionVersion and self.VisibilityKey == key then
				return
			end
			local removedPaths, visiblePaths = {}, {}
			local contextItems = {}
			local hasCollapsed = false
			local work = 0
			local function tick()
				work += 1
				if check and work % 128 == 0 then
					check()
				end
			end
			local function mark(paths, node)
				local id = state.Ids[node]
				while id and id ~= 0 and not paths[id] do
					paths[id] = true
					local entry = state.Entries[id]
					id = entry and entry.Parent
					tick()
				end
			end
			for node in pairs(self.Removed) do
				mark(removedPaths, node)
			end
			for node, value in pairs(self.Overrides) do
				if value == false then
					hasCollapsed = true
					mark(visiblePaths, node)
				end
				tick()
			end
			if hasCollapsed then
				for id in pairs(removedPaths) do
					visiblePaths[id] = true
					tick()
				end
			end
			local function alter(item, paths, collapse)
				if not paths[item.Id] then
					return item
				end
				local entry = state.Entries[item.Id]
				if self.Removed[entry.Node] then
					if not collapse then
						contextItems[item.Id] = false
					end
					return nil
				end
				local children = {}
				if not (collapse and self.Overrides[entry.Node] == false) then
					for _, child in ipairs(item.Children) do
						tick()
						local visible = alter(child, paths, collapse)
						if visible then
							children[#children + 1] = visible
						end
					end
				end
				local updated = record(item.Id, entry, item.Hit, children, collapse, check)
				if not collapse then
					contextItems[item.Id] = updated or false
				end
				return updated
			end
			local visibleRoots, matchRoots = {}, {}
			for _, item in ipairs(baseRoots) do
				local match = alter(item, removedPaths, false)
				local visible = match
				if hasCollapsed then
					visible = alter(item, visiblePaths, true)
				end
				if match then
					matchRoots[#matchRoots + 1] = match
				end
				if visible then
					visibleRoots[#visibleRoots + 1] = visible
				end
			end
			self.VisibleRoots, self.MatchRoots = visibleRoots, matchRoots
			self.ContextItems = contextItems
			self.RowEnds, self.RootIndices, self.Count = offsets(visibleRoots, false)
			self.MatchEnds, self.MatchRootIndices, self.MatchCount = offsets(matchRoots, true)
			self.Width, self.Depth = 0, 1
			local exact = true
			for _, item in ipairs(self.VisibleRoots) do
				self.Width = math.max(self.Width, item.Width)
				self.Depth = math.max(self.Depth, item.Height)
				exact = exact and item.Exact
			end
			local hint = not next(self.Removed) and not next(self.Overrides) and seed.Stats[key]
			self.ExactWidth = hint and hint.Exact or exact
			if hint then
				self.Width, self.Depth = hint.Width, hint.Depth
			end
			self.VisibilityKey = key
			self.WidthRevision = (self.WidthRevision or 0) + 1
			self.AppliedExpansion = self.ExpansionVersion
			self.MatchBits = { Count = self.MatchCount, Data = seed.Packed }
			self.VisibleBits = { Count = self.Count }
			table.clear(self.Pages)
			table.clear(self.PageOrder)
		end
		local function position(node, match)
			local id = state.Ids[node]
			if not id then
				return nil
			end
			local indices = match and result.MatchRootIndices or result.RootIndices
			local path = {}
			local root = id
			while root and root ~= 0 and not indices[root] do
				path[#path + 1] = root
				local entry = state.Entries[root]
				root = entry and entry.Parent
			end
			local at = root and indices[root]
			if not at then
				return nil
			end
			local items = match and result.MatchRoots or result.VisibleRoots
			local ends = match and result.MatchEnds or result.RowEnds
			local count = ends[at - 1] or 0
			local item = items[at]
			for i = #path, 1, -1 do
				local child = item.Indices[path[i]]
				if not child then
					return nil
				end
				local own = match and (item.Hit and 1 or 0) or (item.Display and 1 or 0)
				local offsets = match and item.MatchEnds or item.RowEnds
				count += child > 1 and offsets[child - 1] or own
				item = item.Children[child]
			end
			if match and not item.Hit then
				return nil
			end
			return count + 1
		end
		function result:IndexOf(node)
			return position(node, false)
		end
		function result:PositionOfMatch(node)
			return position(node, true)
		end
		function result:Get(index)
			if index % 1 ~= 0 or index < 1 or index > self.Count then
				return nil
			end
			local page = math.floor((index - 1) / 32)
			local items = self.Pages[page]
			if not items then
				items = {}
				for at = page * 32 + 1, math.min(self.Count, page * 32 + 32) do
					local id = selectRecord(self.VisibleRoots, self.RowEnds, at, false)
					items[at - page * 32] = state.Entries[id].Node
					self.Resolved += 1
				end
				if #self.PageOrder >= 4 then
					self.Pages[table.remove(self.PageOrder, 1)] = nil
				end
				self.PageOrder[#self.PageOrder + 1] = page
				self.Pages[page] = items
			end
			return items[index - page * 32]
		end
		function result:EachVisibleEntry(fn, check)
			local work = 0
			local function visit(item)
				if item.Display then
					fn(state.Entries[item.Id])
				end
				work += 1
				if check and work % 128 == 0 then
					check()
				end
				for _, child in ipairs(item.Children) do
					visit(child)
				end
			end
			for _, item in ipairs(self.VisibleRoots) do
				visit(item)
			end
		end
		function result:MeasureWidths(measure, check)
			local work = 0
			local function visit(item)
				work += 1
				if check and work % 64 == 0 then
					check()
				end
				if item.Exact then
					return item.Width
				end
				local width = 0
				if item.Display then
					local own = item.OwnWidth
					if own == nil then
						own = measure(state.Entries[item.Id])
						item.OwnWidth = own
					end
					width = own
				end
				for _, child in ipairs(item.Children) do
					width = math.max(width, visit(child))
				end
				item.Width, item.Exact = width, true
				return width
			end
			local width = 0
			for _, item in ipairs(self.VisibleRoots) do
				width = math.max(width, visit(item))
			end
			return width
		end
		function result:MaterializeMatches(include)
			local out = table.create(self.MatchCount)
			local function visit(item)
				if item.Hit then
					local node = state.Entries[item.Id].Node
					if not include or include(node) then
						out[#out + 1] = node
					end
				end
				for _, child in ipairs(item.Children) do
					visit(child)
				end
			end
			for _, item in ipairs(self.MatchRoots) do
				visit(item)
			end
			return out
		end
		result.Matches = setmetatable({}, {
			__index = function(_, node)
				return result:PositionOfMatch(node) ~= nil or nil
			end,
		})
		result.Rows = setmetatable({
			IndexOf = function(node)
				return result:IndexOf(node)
			end,
			DepthOf = function(node)
				return result:DepthOf(node)
			end,
		}, {
			__len = function()
				return result.Count
			end,
			__index = function(_, index)
				return type(index) == "number" and result:Get(index) or nil
			end,
		})
		result.Indices = setmetatable({}, {
			__index = function(_, node)
				return result:IndexOf(node)
			end,
		})
		result.MatchList = setmetatable({
			IndexOf = function(node)
				return result:PositionOfMatch(node)
			end,
		}, {
			__len = function()
				return result.MatchCount
			end,
			__index = function(_, index)
				if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > result.MatchCount then
					return nil
				end
				local id = selectRecord(result.MatchRoots, result.MatchEnds, index, true)
				return id and state.Entries[id].Node
			end,
		})
		result:Reflow(checkpoint)
		return result
	end
	return Tree
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,
	InitAfterMain = function() end,
	Main = Main,
}
