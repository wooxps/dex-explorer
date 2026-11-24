--!strict

------------------------------ Types ------------------------------

type Node = { Obj: Instance, Class: string?, Id: number?, ManualOrder: number?, Del: boolean?, Parent: Node?, SearchRawName: string? }
type Nodes = { Node }
type Names = { [Node]: string }
type Comparator = (Node, Node) -> boolean
type Checkpoint = () -> ()
type Classes = { [string]: { ExplorerOrder: string | number } }
type SortState = {
	Names: Names?,
	Compare: (Node, Node, Names?, boolean?) -> boolean,
	DefaultSorter: Comparator,
	ColdName: (Node) -> string,
	SortNamed: (Nodes, Names, Comparator, ((Node) -> string)?) -> (),
	Sort: (Nodes, Comparator) -> (),
	SortItems: (Nodes, Comparator, Checkpoint) -> Nodes,
	AlreadyOrdered: (Nodes, Checkpoint) -> boolean,
	SortNumbered: (Nodes, Checkpoint) -> boolean,
	SortColdNames: (Nodes, Checkpoint, boolean?) -> (boolean, string?, string?),
}

------------------------------ Module ------------------------------

local function Create(classes: Classes, explorerOrders: { [string]: number }): SortState
	local state = {} :: SortState
	local idCounter = 0
	local function Compare(a: Node, b: Node, names: Names?, includeDeleted: boolean?): boolean
		if not includeDeleted and (a.Del or b.Del) then
			return false
		end
		if a.Parent == b.Parent and (a.ManualOrder or b.ManualOrder) then
			local x, y = a.ManualOrder or math.huge, b.ManualOrder or math.huge
			if x ~= y then
				return x < y
			end
		end

		local aClass = a.Class
		local bClass = b.Class
		if not aClass then
			aClass = a.Obj.ClassName
			a.Class = aClass
		end
		if not bClass then
			bClass = b.Obj.ClassName
			b.Class = bClass
		end

		local aOrder = explorerOrders[aClass]
		local bOrder = explorerOrders[bClass]
		if not aOrder then
			aOrder = classes[aClass] and tonumber(classes[aClass].ExplorerOrder) or 9999
			explorerOrders[aClass] = aOrder
		end
		if not bOrder then
			bOrder = classes[bClass] and tonumber(classes[bClass].ExplorerOrder) or 9999
			explorerOrders[bClass] = bOrder
		end

		if aOrder ~= bOrder then
			return aOrder < bOrder
		else
			local aName, bName
			if names then
				aName, bName = names[a], names[b]
				if not aName then
					aName = tostring(a.Obj)
					names[a] = aName
				end
				if not bName then
					bName = tostring(b.Obj)
					names[b] = bName
				end
			else
				aName, bName = tostring(a.Obj), tostring(b.Obj)
			end
			if aName ~= bName then
				return aName < bName
			elseif aClass ~= bClass then
				return aClass < bClass
			else
				local aId = a.Id
				if not aId then
					aId = idCounter
					idCounter = (idCounter + 0.001) % 999999999
					a.Id = aId
				end
				local bId = b.Id
				if not bId then
					bId = idCounter
					idCounter = (idCounter + 0.001) % 999999999
					b.Id = bId
				end
				return aId < bId
			end
		end
	end

	local function DefaultSorter(a: Node, b: Node): boolean
		return Compare(a, b, state.Names)
	end
	local function ColdName(node: Node): string
		local name = node.SearchRawName
		if name == nil then
			name = node.Obj.Name
			node.SearchRawName = name
		end
		return name
	end
	local function SortNamed(children: Nodes, namesByNode: Names, sort: Comparator, readName: ((Node) -> string)?): ()
		local class
		local names = table.create(#children)
		local byName = {}
		local firstRepeat
		local ordered = true
		local fallback = false
		for i = 1, #children do
			local node = children[i]
			if node.Del or node.ManualOrder then
				fallback = true
				break
			end
			local nodeClass = node.Class or node.Obj.ClassName
			if class and nodeClass ~= class then
				fallback = true
				break
			end
			class = nodeClass
			node.Class = nodeClass
			local name = namesByNode[node] or (if readName then readName(node) else tostring(node.Obj))
			if ordered and i > 1 then
				local previous = names[i - 1]
				local previousId = children[i - 1].Id
				ordered = previous < name or (previous == name and previousId and node.Id and previousId < node.Id)
			end
			names[i] = name
			if not firstRepeat then
				if byName[name] then firstRepeat = i else byName[name] = node end
			end
		end

		if ordered and not fallback then return end
		if fallback or firstRepeat then
			if not fallback and firstRepeat <= #children // 4 and children[1].Id then
				local groups, keys = {}, {}
				local orderedTies = true
				for i, name in names do
					local node = children[i]
					local group = groups[name]
					if group then
						local previousId = group[#group].Id
						if not node.Id or not previousId or node.Id <= previousId then
							orderedTies = false
							break
						end
						group[#group + 1] = node
					else
						groups[name] = { node }
						keys[#keys + 1] = name
					end
				end
				if orderedTies then
					table.sort(keys)
					local at = 1
					for _, name in keys do
						local group = groups[name]
						table.move(group, 1, #group, at, children)
						at += #group
					end
					return
				end
			end
			for i, name in names do namesByNode[children[i]] = name end
			if fallback then
				table.sort(children, sort)
				return
			end
			table.sort(children, function(a, b)
				local left, right = namesByNode[a], namesByNode[b]
				if left == right then
					if a.Id and b.Id then return a.Id < b.Id end
					return sort(a, b)
				end
				return left < right
			end)
			return
		end

		table.sort(names)
		for i, name in names do
			children[i] = byName[name]
		end
	end
	local function Sort(children: Nodes, sort: Comparator): ()
		if #children >= 16 and sort == DefaultSorter then
			SortNamed(children, assert(state.Names), sort)
		else
			table.sort(children, sort)
		end
	end

	local function SortItems(items: Nodes, less: Comparator, check: Checkpoint): Nodes
		if #items <= 512 then
			table.sort(items, less)
			check()
			return items
		end
		local page = {}
		for first = 1, #items, 512 do
			table.clear(page)
			table.move(items, first, math.min(first + 511, #items), 1, page)
			table.sort(page, less)
			table.move(page, 1, #page, first, items)
			check()
		end
		local count, width = #items, 512
		local merged = table.create(count)
		while width < count do
			for first = 1, count, width * 2 do
				local middle = math.min(first + width, count + 1)
				local last = math.min(first + width * 2 - 1, count)
				local left, right, at = first, middle, first
				if right > last or not less(items[right], items[middle - 1]) then
					table.move(items, first, last, first, merged)
					check()
					continue
				end
				while left < middle and right <= last do
					if less(items[right], items[left]) then
						merged[at] = items[right]
						right += 1
					else
						merged[at] = items[left]
						left += 1
					end
					at += 1
					if at % 128 == 0 then
						check()
					end
				end
				if left < middle then
					table.move(items, left, middle - 1, at, merged)
				elseif right <= last then
					table.move(items, right, last, at, merged)
				end
				check()
			end
			items, merged = merged, items
			width *= 2
		end
		return items
	end

	local function AlreadyOrdered(items: Nodes, check: Checkpoint): boolean
		local previous = items[1]
		local class = previous.Class or previous.Obj.ClassName
		local name = ColdName(previous)
		if previous.ManualOrder then return false end
		for i = 2, #items do
			local node = items[i]
			if node.ManualOrder or (node.Class or node.Obj.ClassName) ~= class then return false end
			local nextName = ColdName(node)
			if nextName < name or (nextName == name and (not previous.Id or not node.Id or previous.Id >= node.Id)) then
				return false
			end
			previous, name = node, nextName
			if i % 128 == 0 then check() end
		end
		return true
	end

	local function SortNumbered(items: Nodes, check: Checkpoint): boolean
		local first = items[1]
		local firstName = ColdName(first)
		local digits = firstName:match("([0-9]+)$")
		if not digits or #digits > 8 then return false end
		local start = #firstName - #digits + 1
		local prefix = firstName:sub(1, start - 1)
		local class = first.Class or first.Obj.ClassName
		local origin = tonumber(digits)
		local capacity = #items * 2
		local minimum, maximum = origin, origin
		local fixedWidth, padded = true, false
		local function key(node: Node): number?
			if node.ManualOrder or (node.Class or node.Obj.ClassName) ~= class then return nil end
			local name = ColdName(node)
			if #name < start or #name >= start + 8 or name:sub(1, start - 1) ~= prefix then return nil end
			local suffix = name:sub(start)
			if suffix:find("[^0-9]") then return nil end
			local n = tonumber(suffix)
			minimum, maximum = math.min(minimum, n), math.max(maximum, n)
			fixedWidth = fixedWidth and #suffix == #digits
			padded = padded or (#suffix > 1 and string.byte(suffix) == 48)
			if maximum - minimum >= capacity or (not fixedWidth and (padded or maximum > capacity)) then return nil end
			return n
		end
		for i = 1, 8 do
			if not key(items[1 + (i - 1) * (#items - 1) // 7]) then return false end
		end
		local slots = table.create(#items)
		local base = minimum
		for i, node in items do
			local n = key(node)
			if not n then return false end
			local slot = n - base + 1
			if slots[slot] then return false end
			slots[slot] = node
			if i % 128 == 0 then check() end
		end
		local index = 0
		if fixedWidth then
			for n = minimum, maximum do
				local node = slots[n - base + 1]
				if node then
					index += 1
					items[index] = node
				end
				if n % 256 == 0 then check() end
			end
		else
			local function emit(n: number): ()
				local node = slots[n - base + 1]
				if node then
					index += 1
					items[index] = node
				end
				if n % 128 == 0 then check() end
				if n > 0 then
					for child = n * 10, math.min(n * 10 + 9, maximum) do emit(child) end
				end
			end
			for n = 0, math.min(9, maximum) do emit(n) end
		end
		return true
	end

	local function SortColdNames(items: Nodes, check: Checkpoint, sameOrder: boolean?): (boolean, string?, string?)
		local class = items[1].Class or items[1].Obj.ClassName
		local names, byName = table.create(#items), {}
		local duplicates = {}
		local first, last
		for i, node in items do
			if node.ManualOrder then return false, nil, nil end
			local nodeClass = node.Class or node.Obj.ClassName
			if not sameOrder and nodeClass ~= class then
				local orders, groups = {}, {}
				for at, child in items do
					if child.ManualOrder then return false, nil, nil end
					local childClass = child.Class or child.Obj.ClassName
					child.Class = childClass
					local order = explorerOrders[childClass]
					if not order then
						local details = classes[childClass]
						order = details and tonumber(details.ExplorerOrder) or 9999
						explorerOrders[childClass] = order
					end
					local group = groups[order]
					if not group then
						group = {}
						groups[order] = group
						orders[#orders + 1] = order
					end
					group[#group + 1] = child
					if at % 128 == 0 then check() end
				end
				table.sort(orders)
				for _, order in orders do
					local group = groups[order]
					if #group > 1 and not SortColdNames(group, check, true) then return false, nil, nil end
				end
				local at = 1
				for _, order in orders do
					local group = groups[order]
					table.move(group, 1, #group, at, items)
					at += #group
				end
				return true, nil, nil
			end
			node.Class = nodeClass
			local name = ColdName(node)
			local previous = byName[name]
			if previous then
				local group = duplicates[name]
				if not group then
					group = { previous }
					duplicates[name] = group
				end
				group[#group + 1] = node
			else
				names[#names + 1], byName[name] = name, node
			end
			if not first or name < first then
				first = name
			end
			if not last or name > last then
				last = name
			end
			if i % 128 == 0 then
				check()
			end
		end
		for name, group in duplicates do
			local ordered, previousId, previousClass = true, -math.huge, nil
			for index, node in group do
				if not node.Id then
					node.Id = idCounter
					idCounter = (idCounter + 0.001) % 999999999
				end
				ordered = ordered and (not previousClass or previousClass < node.Class
					or previousClass == node.Class and previousId <= node.Id)
				previousClass = node.Class
				previousId = node.Id
				if index % 128 == 0 then
					check()
				end
			end
			if not ordered then
				duplicates[name] = SortItems(group, function(a, b)
					if a.Class ~= b.Class then return a.Class < b.Class end
					return a.Id < b.Id
				end, check)
			end
			check()
		end
		local out = 0
		local function emit(group: { string }): ()
			table.sort(group)
			for i = 1, #group do
				local name = group[i]
				local repeated = duplicates[name]
				if repeated then
					table.move(repeated, 1, #repeated, out + 1, items)
					out += #repeated
				else
					out += 1
					items[out] = byName[name]
				end
			end
			check()
		end
		local function partition(group: { string }, minimum: string, maximum: string, at: number): ()
			if #group <= 1024 then
				emit(group)
				return
			end
			while string.byte(minimum, at) == string.byte(maximum, at) do
				at += 1
			end
			local buckets, keys = {}, {}
			for i = 1, #group do
				local name = group[i]
				local key = string.byte(name, at) or -1
				local bucket = buckets[key]
				if not bucket then
					bucket = { Min = name, Max = name }
					buckets[key] = bucket
					keys[#keys + 1] = key
				end
				bucket[#bucket + 1] = name
				if name < bucket.Min then
					bucket.Min = name
				end
				if name > bucket.Max then
					bucket.Max = name
				end
				if i % 128 == 0 then
					check()
				end
			end
			table.sort(keys)
			for _, key in keys do
				local bucket = buckets[key]
				partition(bucket, bucket.Min, bucket.Max, at + 1)
			end
		end
		partition(names, first, last, 1)
		return true, first, last
	end

	state.DefaultSorter = DefaultSorter
	state.Compare = Compare
	state.ColdName = ColdName
	state.SortNamed = SortNamed
	state.Sort = Sort
	state.SortItems = SortItems
	state.AlreadyOrdered = AlreadyOrdered
	state.SortNumbered = SortNumbered
	state.SortColdNames = SortColdNames
	return state
end

local Module = table.freeze({ Create = Create })
return table.freeze({ Main = function() return Module end })
