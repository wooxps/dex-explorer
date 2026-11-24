--!strict

------------------------------ Module ------------------------------

local function Main()
	local Projection = {}
	function Projection.Create(rows, indices)
		local p = {
			Rows = rows,
			Indices = indices,
			Valid = false,
			Dirty = {},
			Depths = {},
			Parents = {},
			Widths = {},
			Stats = { Patches = 0, Fallbacks = 0, Projected = 0, Reindexed = 0 },
		}
		local widths, depths = {}, {}
		local childEdit
		local function adjust(map, key, delta)
			local count = (map[key] or 0) + delta
			map[key] = count > 0 and count or nil
		end
		function p:Mark(node)
			if self.Valid and node and (indices[node] or node == self.Root) then
				childEdit = nil
				self.Dirty[node] = true
			end
		end
		function p:MarkChild(node, insertion)
			local parent = node.Parent
			local previous = childEdit
			local alreadyMarked = self.Dirty[node]
			local clean = not next(self.Dirty)
			self:Mark(node)
			self:Mark(parent)
			if alreadyMarked or not self.Valid or not parent or not indices[parent] or parent == self.Root then return end
			if not clean and (not previous or previous.Parent ~= parent or previous.Insert ~= (insertion ~= nil)) then
				return
			end
			if insertion then
				if previous and (insertion < previous.First or insertion > previous.First + previous.Count) then return end
				childEdit = previous or { Parent = parent, Insert = true, First = insertion, Count = 0 }
				childEdit.Count += 1
			elseif indices[node] and self.Parents[node] == parent then
				local first = indices[node]
				local last = first
				if rows[last + 1] and self.Depths[rows[last + 1]] > self.Depths[node] then return end
				childEdit = previous or { Parent = parent, Insert = false, First = first, Last = last, Count = 0 }
				childEdit.First = math.min(childEdit.First, first)
				childEdit.Last = math.max(childEdit.Last, last)
				childEdit.Count += last - first + 1
			end
		end
		local function childPlan(self, context)
			local edit = childEdit
			if not edit or not context.Expanded[edit.Parent] or (context.NeedsSort and context.NeedsSort(edit.Parent)) then
				return nil
			end
			local depth = self.Depths[edit.Parent] + 1
			if not edit.Insert then
				if edit.Count == edit.Last - edit.First + 1 then
					return { First = edit.First, Last = edit.Last, Rows = {}, Depths = {} }
				end
				return nil
			end
			local parent, first, last = edit.Parent, edit.First, edit.First + edit.Count - 1
			local following = parent[last + 1]
			local previous = parent[first - 1]
			local at
			if following and indices[following] then
				at = indices[following]
			elseif not previous and not following then
				at = indices[parent] + 1
			elseif indices[previous] then
				at = indices[previous] + 1
				while rows[at] and self.Depths[rows[at]] > depth do
					at += 1
				end
			else
				return nil
			end
			local plan = { First = at, Last = at - 1, Rows = table.create(edit.Count), Depths = {} }
			for i = first, last do
				local node = parent[i]
				if not node or node.Del or indices[node] or (context.Expanded[node] and #node > 0) then return nil end
				plan.Rows[i - first + 1] = node
				plan.Depths[node] = depth
			end
			for _, node in plan.Rows do
				context.Measure(node)
			end
			return plan
		end
		function p:Rebuild(root)
			self.Root = root
			childEdit = nil
			table.clear(self.Dirty)
			table.clear(self.Depths)
			table.clear(self.Parents)
			table.clear(self.Widths)
			table.clear(widths)
			table.clear(depths)
			self.Width, self.Depth = 0, 1
			for _, node in ipairs(rows) do
				local depth = (self.Depths[node.Parent] or 0) + 1
				local width = node.NameWidth or 0
				self.Depths[node], self.Parents[node], self.Widths[node] = depth, node.Parent, width
				adjust(widths, width, 1)
				adjust(depths, depth, 1)
				self.Width = math.max(self.Width, width)
				self.Depth = math.max(self.Depth, depth)
			end
			self.Valid = true
		end
		local function branchPlans(self, context)
			local limit = context.Limit or 512
			local roots = {}
			for node in pairs(self.Dirty) do
				if node == context.Root then
					self.Stats.Fallbacks += 1
					return false
				end
				if indices[node] then
					if node.Del or self.Parents[node] ~= node.Parent then
						if self.Parents[node] then
							roots[self.Parents[node]] = true
						end
						if node.Parent then
							roots[node.Parent] = true
						end
					else
						roots[node] = true
					end
				end
			end
			local candidates = {}
			for root in pairs(roots) do
				if root == context.Root then
					self.Stats.Fallbacks += 1
					return false
				end
				if indices[root] then
					candidates[#candidates + 1] = root
				end
			end
			if #candidates > 32 then
				self.Stats.Fallbacks += 1
				return false
			end
			table.sort(candidates, function(a, b)
				return indices[a] < indices[b]
			end)
			local plans = {}
			local covered = 0
			local work = 0
			for _, root in ipairs(candidates) do
				local position = indices[root]
				if position <= covered then
					continue
				end
				local depth = self.Depths[root]
				local last = position
				while rows[last + 1] and self.Depths[rows[last + 1]] > depth do
					last += 1
					work += 1
					if work > limit then
						self.Stats.Fallbacks += 1
						return false
					end
				end
				local plan = { Root = root, First = position + 1, Last = last, Depth = depth, Rows = {}, Depths = {} }
				plans[#plans + 1] = plan
				covered = last
				local stack = {}
				if context.Expanded[root] then
					stack[1] = { Parent = root, Index = 1 }
				end
				while #stack > 0 do
					local frame = stack[#stack]
					local node = frame.Parent[frame.Index]
					if not node then
						stack[#stack] = nil
					else
						frame.Index += 1
						if not node.Del then
							work += 1
							if work > limit then
								self.Stats.Fallbacks += 1
								return false
							end
							if context.Expanded[node] and #node > 0 then
								stack[#stack + 1] = { Parent = node, Index = 1 }
							end
						end
					end
				end
			end
			for _, plan in ipairs(plans) do
				local function visit(parent, depth)
					context.Sort(parent)
					for _, node in ipairs(parent) do
						if not node.Del then
							plan.Rows[#plan.Rows + 1] = node
							plan.Depths[node] = depth
							context.Measure(node)
							if context.Expanded[node] and #node > 0 then
								visit(node, depth + 1)
							end
						end
					end
				end
				if context.Expanded[plan.Root] then
					visit(plan.Root, plan.Depth + 1)
				end
			end
			return plans
		end
		function p:Try(context)
			if not self.Valid then return false end
			local edit = childPlan(self, context)
			local plans = if edit then { edit } else branchPlans(self, context)
			if not plans then return false end
			for _, plan in ipairs(plans) do
				for index = plan.First, plan.Last do
					local node = rows[index]
					adjust(widths, self.Widths[node], -1)
					adjust(depths, self.Depths[node], -1)
					indices[node] = nil
					self.Widths[node] = nil
					self.Depths[node] = nil
					self.Parents[node] = nil
				end
			end
			for index = #plans, 1, -1 do
				local plan = plans[index]
				local oldCount = #rows
				local removed = plan.Last - plan.First + 1
				local delta = #plan.Rows - removed
				if delta ~= 0 then
					table.move(rows, plan.Last + 1, oldCount, plan.First + #plan.Rows, rows)
					for at = oldCount + delta + 1, oldCount do
						rows[at] = nil
					end
				end
				table.move(plan.Rows, 1, #plan.Rows, plan.First, rows)
			end
			for _, plan in ipairs(plans) do
				for _, node in ipairs(plan.Rows) do
					local width, depth = node.NameWidth or 0, plan.Depths[node]
					self.Widths[node], self.Depths[node], self.Parents[node] = width, depth, node.Parent
					adjust(widths, width, 1)
					adjust(depths, depth, 1)
					self.Width = math.max(self.Width, width)
					self.Depth = math.max(self.Depth, depth)
					self.Stats.Projected += 1
				end
			end
			if not widths[self.Width] then
				self.Width = 0
				for width in pairs(widths) do
					self.Width = math.max(self.Width, width)
				end
			end
			if not depths[self.Depth] then
				self.Depth = 1
				for depth in pairs(depths) do
					self.Depth = math.max(self.Depth, depth)
				end
			end
			local function reindex(first, last)
				for index = first, last do
					indices[rows[index]] = index
				end
				self.Stats.Reindexed += last - first + 1
			end
			local offset, nextRow = 0, 1
			for _, plan in ipairs(plans) do
				local first = plan.First + offset
				local last = first + #plan.Rows - 1
				if offset ~= 0 then
					reindex(nextRow, first - 1)
				end
				reindex(first, last)
				offset += #plan.Rows - (plan.Last - plan.First + 1)
				nextRow = last + 1
			end
			if offset ~= 0 then
				reindex(nextRow, #rows)
			end
			table.clear(self.Dirty)
			childEdit = nil
			self.Stats.Patches += 1
			return true
		end
		return p
	end
	return Projection
end
return { Main = Main }
