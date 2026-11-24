--!strict

local Apps
------------------------------ Module ------------------------------

local function Main()
	local Snapshots = {}
	function Snapshots.CopyMap(previous)
		if not previous then
			return {}
		end
		local base = previous.Base or previous
		local pages = previous.Pages and table.clone(previous.Pages) or {}
		local owned = {}
		return setmetatable({ Pages = pages, Base = base }, {
			__index = function(_, id)
				if type(id) ~= "number" then
					return nil
				end
				local page = pages[math.floor((id - 1) / 256)]
				if page then
					return page[(id - 1) % 256 + 1]
				end
				return base[id]
			end,
			__newindex = function(_, id, value)
				local pageId = math.floor((id - 1) / 256)
				local page = pages[pageId]
				if not owned[pageId] then
					if page then
						page = table.clone(page)
					elseif base.Lazy then
						page = {}
						for at = 1, 256 do
							page[at] = base[pageId * 256 + at]
						end
					else
						page = table.move(base, pageId * 256 + 1, pageId * 256 + 256, 1, {})
					end
					pages[pageId] = page
					owned[pageId] = true
				end
				page[(id - 1) % 256 + 1] = value
			end,
		})
	end
	local function bindIds(state, identities)
		return setmetatable({}, {
			__index = function(_, node)
				local id = identities[node]
				local entry = id and state.Entries[id]
				return entry and entry.Node == node and id or nil
			end,
			__newindex = function(_, node, id)
				if id then
					identities[node] = id
				end
			end,
		})
	end
	function Snapshots.Create(context)
		local owner = {
			Pending = {},
			Moves = {},
			PendingCount = 0,
			Version = 0,
			Journal = {},
			Stats = { Builds = 0, Updates = 0, OrderBuilds = 0, NativeReads = 0 },
		}
		function owner:ChangesSince(version)
			if version == self.Version then
				return {}
			end
			if not self.Journal[version + 1] then
				return nil
			end
			local changes = {}
			for at = version + 1, self.Version do
				local batch = self.Journal[at]
				if not batch then
					return nil
				end
				for id in pairs(batch) do
					changes[id] = true
				end
			end
			return changes
		end
		function owner:Mark(node, subtree, reason)
			if node then
				if self.Pending[node] == nil then
					self.PendingCount += 1
					self.Moves[node] = reason == "move"
				else
					self.Moves[node] = self.Moves[node] and reason == "move"
				end
				self.Pending[node] = self.Pending[node] or subtree or false
			end
		end
		function owner:Refresh(checkpoint)
			local old = self.State
			local roots = context.Roots()
			local reset = not old or old.Sorting ~= context.Sorting() or old.Scope ~= context.Scope()
			if old and (#old.RootNodes ~= #roots) then
				reset = true
			end
			if old then
				for i, root in ipairs(roots) do
					if old.RootNodes[i] ~= root then
						reset = true
						break
					end
				end
			end
			if old and (old.MaxId > old.Live * 2 + 8192 or old.Postings.Stats.Names > old.Live * 2 + 8192) then
				reset = true
			end
			local pending, moves = self.Pending, self.Moves
			self.Pending, self.Moves = {}, {}
			self.PendingCount = 0
			local state
			local columns
			if reset then
				state = {
					Entries = Snapshots.CopyMap(),
					Children = Snapshots.CopyMap(),
					Identities = setmetatable({}, { __mode = "k" }),
					Free = {},
					MaxId = 0,
					Live = 0,
					Sorting = context.Sorting(),
					Scope = context.Scope(),
					RootNodes = roots,
					RootIds = {},
					Postings = Apps.SearchPostings.Create(),
				}
				if context.TreeResults then
					columns = {
						Nodes = {},
						Names = {},
						Parents = {},
						NameIds = {},
						Keys = {},
						Classes = {},
						Orders = {},
						Manual = {},
					}
					state.Entries = setmetatable({ Lazy = true }, {
						__index = function(entries, id)
							if type(id) ~= "number" or not columns.Nodes[id] then
								return nil
							end
							local node = columns.Nodes[id]
							local entry = {
								Node = node,
								Parent = columns.Parents[id],
								Name = columns.Names[id],
								NameId = columns.NameIds[id],
								Key = columns.Keys[id] or id,
								Class = columns.Classes[id],
								Order = columns.Orders[id],
								Queryable = columns.NameIds[id] ~= nil,
								Display = node ~= roots[1],
								Manual = columns.Manual[id],
							}
							rawset(entries, id, entry)
							return entry
						end,
					})
				end
			else
				if not next(pending) then
					return old
				end
				state = {
					Entries = Snapshots.CopyMap(old.Entries),
					Children = Snapshots.CopyMap(old.Children),
					Identities = old.Identities,
					Free = table.clone(old.Free),
					MaxId = old.MaxId,
					Live = old.Live,
					Sorting = old.Sorting,
					Scope = old.Scope,
					RootNodes = old.RootNodes,
					RootIds = old.RootIds,
					Postings = old.Postings,
					Order = old.Order,
					Positions = old.Positions,
					Parents = old.Parents,
					Ends = old.Ends,
					Depths = old.Depths,
					TopStarts = old.TopStarts,
				}
			end
			state.Ids = reset and {} or bindIds(state, state.Identities)
			local rootSet = {}
			for _, root in ipairs(roots) do
				rootSet[root] = true
			end
			local function inScope(node)
				local seen = {}
				while node do
					if node.Del or seen[node] then
						return false
					end
					if rootSet[node] then
						return true
					end
					seen[node] = true
					node = node.Parent
				end
				return false
			end
			local orderChanged = reset
			local work = 0
			local captured = {}
			local changes = {}
			local sortCandidates = {}
			local nameEdits = {}
			local fullParents = {}
			local function tick()
				work += 1
				if work % 64 == 0 then
					checkpoint()
				end
			end
			local function remove(id)
				local entry = state.Entries[id]
				if not entry then
					return
				end
				tick()
				for _, child in ipairs(state.Children[id] or {}) do
					local childEntry = state.Entries[child]
					if childEntry and childEntry.Parent == id and childEntry.Node.Parent == entry.Node then
						remove(child)
					end
				end
				changes[id] = true
				if entry.NameId then
					state.Postings:RemoveMember(entry.NameId, id)
				end
				state.Ids[entry.Node] = nil
				state.Entries[id] = nil
				state.Children[id] = nil
				state.Free[#state.Free + 1] = id
				state.Live -= 1
				orderChanged = true
				tick()
			end
			local capture
			capture = function(node, parentId, descendants)
				local id = state.Ids[node]
				if node.Del then
					if id then
						remove(id)
					end
					return nil
				end
				if captured[node] then
					return id
				end
				captured[node] = true
				local previous = id and state.Entries[id]
				if not id then
					id = table.remove(state.Free)
					if not id then
						state.MaxId += 1
						id = state.MaxId
					end
					state.Ids[node] = id
					state.Identities[node] = id
					state.Live += 1
					orderChanged = true
				end
				local root = rootSet[node]
				local readable, name, class, order, key = pcall(context.Read, node)
				owner.Stats.NativeReads += 1
				if not readable or type(name) ~= "string" then
					name, class, order, key = "", "Instance", 9999, id
					owner.Stats.Unreadable = (owner.Stats.Unreadable or 0) + 1
					readable = false
				end
				local queryable = not root and readable
				local nameId = queryable and state.Postings:Intern(name, checkpoint) or nil
				if previous and previous.NameId ~= nameId and previous.NameId then
					state.Postings:RemoveMember(previous.NameId, id)
				end
				if nameId and (not previous or previous.NameId ~= nameId) then
					state.Postings:AddMember(nameId, id)
				end
				if not reset then
					changes[id] = true
				end
				if columns then
					columns.Nodes[id], columns.Parents[id], columns.Names[id], columns.NameIds[id] =
						node, parentId or 0, name, nameId
					columns.Keys[id], columns.Classes[id], columns.Orders[id] = key, class, order
					columns.Manual[id] = node.ManualOrder
				else
					state.Entries[id] = {
						Node = node,
						Parent = parentId or 0,
						Name = name,
						Class = class,
						Order = order,
						Key = key or previous and previous.Key or id,
						Manual = node.ManualOrder,
						NameId = nameId,
						Queryable = queryable,
						Display = not root or node ~= roots[1],
					}
				end
				if
					previous
					and (
						previous.Parent ~= parentId
						or previous.Name ~= name
						or previous.Order ~= order
						or previous.Manual ~= node.ManualOrder
					)
				then
					orderChanged = true
				end
				tick()
				if (descendants or not previous) and #node == 0 then
					if not reset then state.Children[id] = nil end
					orderChanged = true
				elseif descendants or not previous then
					local children = {}
					local increasing, last = true, 0
					local source = table.clone(node)
					for _, child in ipairs(source) do
						if not child.Del and child.Parent == node then
							local childId = capture(child, id, true)
							if childId then
								children[#children + 1] = childId
								increasing = increasing and childId > last
								last = childId
							end
						end
						tick()
					end
					children.Increasing = increasing
					state.Children[id] = children
					if #children > 1 then
						sortCandidates[id] = true
					end
					orderChanged = true
				end
				tick()
				return id
			end
			local function refreshChildren(node)
				local parentId = state.Ids[node]
				if not parentId or not state.Entries[parentId] then
					return
				end
				local children = {}
				local increasing, last = true, 0
				for _, child in ipairs(table.clone(node)) do
					if not child.Del and child.Parent == node then
						local childId = state.Ids[child] or capture(child, parentId, true)
						if childId then
							local entry = state.Entries[childId]
							if entry and entry.Parent ~= parentId then
								entry = table.clone(entry)
								entry.Parent = parentId
								state.Entries[childId] = entry
							end
							children[#children + 1] = childId
							increasing = increasing and childId > last
							last = childId
						end
					end
					tick()
				end
				children.Increasing = increasing
				state.Children[parentId] = children
				if #children > 1 then
					sortCandidates[parentId] = true
				end
				changes[parentId] = true
				orderChanged = true
			end
			local ok, problem = pcall(function()
				if reset then
					for _, root in ipairs(roots) do
						state.RootIds[#state.RootIds + 1] = capture(root, 0, true)
					end
				else
					local parents = {}
					for node, subtree in pairs(pending) do
						local id = state.Ids[node]
						local previous = id and state.Entries[id]
						local included = inScope(node)
						local nameOnly = included
							and previous
							and not subtree
							and previous.Parent == (state.Ids[node.Parent] or 0)
						if nameOnly then
							if state.Sorting and node.Parent then
								local edits = nameEdits[node.Parent] or {}
								nameEdits[node.Parent] = edits
								edits[id] = true
							end
						else
							if previous and previous.Parent ~= 0 then
								local entry = state.Entries[previous.Parent]
								if entry then
									parents[entry.Node] = true
								end
							end
							if node.Parent then
								parents[node.Parent] = true
							end
						end
						if included then
							local lineage = {}
							local parent = node.Parent
							while parent and not state.Ids[parent] do
								lineage[#lineage + 1] = parent
								parent = parent.Parent
							end
							for i = #lineage, 1, -1 do
								local ancestor = lineage[i]
								capture(ancestor, state.Ids[ancestor.Parent] or 0, false)
							end
							capture(node, state.Ids[node.Parent] or 0, subtree and not moves[node])
							if moves[node] then
								parents[node] = true
							end
						elseif id then
							remove(id)
						end
						tick()
					end
					for parent in pairs(parents) do
						fullParents[parent] = true
						refreshChildren(parent)
					end
				end
				if orderChanged and not context.TreeResults then
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
					for parent, edits in pairs(nameEdits) do
						if not fullParents[parent] then
							local id = state.Ids[parent]
							local items = id and state.Children[id]
							if items and #items > 1 then
								local count = 0
								for _ in pairs(edits) do
									count += 1
								end
								if count <= 64 and count <= math.max(1, #items / 16) then
									items = table.clone(items)
									for child in pairs(edits) do
										local at = table.find(items, child)
										if at then
											table.remove(items, at)
										end
										tick()
									end
									for child in pairs(edits) do
										local low, high = 1, #items + 1
										while low < high do
											local mid = math.floor((low + high) / 2)
											if less(items[mid], child) then
												low = mid + 1
											else
												high = mid
											end
										end
										table.insert(items, low, child)
										tick()
									end
									state.Children[id] = items
									changes[id] = true
								else
									sortCandidates[id] = true
								end
							end
						end
					end
					for id in pairs(sortCandidates) do
						local items = state.Children[id]
						if items and state.Sorting and #items > 1 then
							local ordered = true
							for position = 2, #items do
								if less(items[position], items[position - 1]) then
									ordered = false
									break
								end
								tick()
							end
							if not ordered then
								items = table.clone(items)
								for first = 1, #items, 128 do
									local page = {}
									table.move(items, first, math.min(first + 127, #items), 1, page)
									table.sort(page, less)
									table.move(page, 1, #page, first, items)
									checkpoint()
								end
								local width = 128
								while width < #items do
									local nextItems = {}
									for first = 1, #items, width * 2 do
										local middle = math.min(first + width, #items + 1)
										local last = math.min(first + 2 * width - 1, #items)
										local a, b = first, middle
										for index = first, last do
											if a < middle and (b > last or not less(items[b], items[a])) then
												nextItems[index] = items[a]
												a += 1
											else
												nextItems[index] = items[b]
												b += 1
											end
											tick()
										end
									end
									items = nextItems
									width *= 2
								end
								state.Children[id] = items
							end
						end
						tick()
					end
					if not context.TreeResults then
						local order, positions, parents, ends, depths, top = {}, {}, {}, {}, {}, {}
						local seen = {}
						local function visit(id, parentPosition, depth, topNode)
							local entry = state.Entries[id]
							if not entry or seen[id] then
								return
							end
							seen[id] = true
							tick()
							local position = parentPosition
							if entry.Display then
								position = #order + 1
								order[position] = id
								positions[id] = position
								parents[position] = parentPosition
								depths[position] = depth
								if parentPosition == 0 then
									top[#top + 1] = position
								end
							end
							for _, child in ipairs(state.Children[id] or {}) do
								visit(child, position, entry.Display and depth + 1 or depth, topNode)
								tick()
							end
							if entry.Display then
								ends[position] = #order
							end
						end
						for _, id in ipairs(state.RootIds) do
							visit(id, 0, 1, nil)
						end
						state.Order, state.Positions, state.Parents, state.Ends, state.Depths, state.TopStarts =
							order, positions, parents, ends, depths, top
						owner.Stats.OrderBuilds += 1
					end
				end
			end)
			if not ok then
				for node, subtree in pairs(pending) do
					self:Mark(node, subtree, moves[node] and "move" or nil)
				end
				if reset then
					self.State = nil
				end
				error(problem, 0)
			end
			self.State = state
			self.Version += 1
			state.Version = self.Version
			if reset then
				table.clear(self.Journal)
			else
				self.Journal[self.Version] = changes
			end
			self.Journal[self.Version - 32] = nil
			self.Stats[reset and "Builds" or "Updates"] += 1
			return state
		end
		return owner
	end
	return Snapshots
end
return {
	InitDeps = function(d)
		Apps = d.Apps
	end,

	Main = Main,
}
