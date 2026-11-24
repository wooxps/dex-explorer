--!strict

------------------------------ Module ------------------------------

local function Main()
	local Policy = {}
	local function indexOf(tree, node)
		local lookup = rawget(tree, "IndexOf")
		return lookup and lookup(node) or table.find(tree, node)
	end
	Policy.Tokens = table.freeze({
		RowHeight = 20,
		IndentWidth = 12,
		IconSize = 16,
		FieldSize = 16,
		SearchBarHeight = 20,
		SearchPadding = 4,
		HeaderHeight = 29,
		ScrollBarWidth = 6,
		ScrollBarPadding = 2,
		ScrollRate = 3,
		TextOffset = 20,
		RowRadius = 6,
		DragThreshold = 7,
	})

	function Policy.FormatName(name)
		return name:sub(1, 100):gsub("\n", " "):gsub("\r", "")
	end

	function Policy.Navigate(tree, current, direction, matches)
		if #tree == 0 then
			return nil
		end
		local index = indexOf(tree, current) or (direction > 0 and 0 or #tree + 1)
		for i = index + direction, direction > 0 and #tree or 1, direction do
			local node = tree[i]
			if not node.Del and (not matches or matches[node]) then
				return node
			end
		end
		return current
	end

	function Policy.Range(tree, anchor, target, matches, base)
		local first, last = indexOf(tree, anchor), indexOf(tree, target)
		if not first or not last then
			return { target }
		end
		first, last = math.min(first, last), math.max(first, last)
		local result, seen = {}, {}
		for _, node in ipairs(base or {}) do
			if not node.Del and not seen[node] then
				result[#result + 1] = node
				seen[node] = true
			end
		end
		for i = first, last do
			local node = tree[i]
			if not node.Del and (not matches or matches[node]) and not seen[node] then
				result[#result + 1] = node
				seen[node] = true
			end
		end
		return result
	end

	function Policy.Depth(node)
		local depth = 0
		while node and node.Parent do
			depth += 1
			node = node.Parent
		end
		return depth
	end

	function Policy.ShiftRange(tree, base, target, matches)
		local result, seen = {}, {}
		for _, node in ipairs(base) do
			if not node.Del and not seen[node] then
				result[#result + 1] = node
				seen[node] = true
			end
		end
		local anchor = result[#result]
		if not anchor then
			return { target }
		end
		if anchor == target then
			return result
		end
		local first, last = indexOf(tree, anchor), indexOf(tree, target)
		if not first or not last then
			if not seen[target] then
				result[#result + 1] = target
			end
			return result
		end
		local searchRange = matches and matches[anchor] and matches[target]
		local depth = Policy.Depth(anchor)
		local sameDepth = not searchRange and depth == Policy.Depth(target)
		local direction = last > first and 1 or -1
		for index = first + direction, last, direction do
			local node = tree[index]
			if
				not node.Del
				and not seen[node]
				and (not searchRange or matches[node])
				and (not sameDepth or Policy.Depth(node) == depth)
			then
				result[#result + 1] = node
				seen[node] = true
			end
		end
		return result
	end

	function Policy.Endpoint(tree, last, matches)
		if #tree == 0 then
			return nil
		end
		local direction = last and -1 or 1
		local rootDepth = Policy.Depth(tree[1])
		for index = last and #tree or 1, last and 1 or #tree, direction do
			local node = tree[index]
			if not node.Del and (matches and matches[node] or not matches and Policy.Depth(node) <= rootDepth) then
				return node
			end
		end
		return nil
	end

	function Policy.PageStep(tree, selected, distance, matches, indices)
		if #tree == 0 or distance == 0 then
			return nil
		end
		local direction = distance > 0 and 1 or -1
		local boundary, seen = nil, {}
		if not indices then
			indices = setmetatable({}, {
				__index = function(_, node)
					return indexOf(tree, node)
				end,
			})
		end
		for _, node in ipairs(selected) do
			local index = indices[node]
			if index then
				seen[node] = true
				if not boundary or direction * index < direction * boundary then
					boundary = index
				end
			end
		end
		local start = boundary and math.clamp(boundary + distance, 1, #tree) or (direction > 0 and 1 or #tree)
		local function candidate(index)
			local node = tree[index]
			if not node.Del and not seen[node] and (not matches or matches[node]) then
				return node
			end
		end
		for index = start, direction > 0 and #tree or 1, direction do
			local node = candidate(index)
			if node then
				return node
			end
		end
		if boundary then
			for index = start, boundary, -direction do
				local node = candidate(index)
				if node then
					return node
				end
			end
		end
		return nil
	end

	function Policy.DropTarget(tree, index, within, canvasX, expanded, indentWidth)
		local between = within <= 4 or within >= Policy.Tokens.RowHeight - 4
		if within <= 4 then
			index -= 1
		end
		local node = tree[index]
		if not node then
			return nil
		end
		if not between then
			return node, "Inside", node
		end
		local parent = node
		local nextNode = tree[index + 1]
		local depth = Policy.Depth(node)
		if
			nextNode
			and depth > Policy.Depth(nextNode)
			and canvasX < indentWidth * depth
			and node.Parent
			and node.Parent.Parent
			and node.Parent.Parent.Obj
			and node.Parent.Parent.Obj.ClassName ~= "DataModel"
		then
			parent = node.Parent.Parent
		elseif
			(#node == 0 or not expanded[node] or expanded[node] == 0)
			and node.Parent
			and node.Parent.Obj.ClassName ~= "DataModel"
		then
			parent = node.Parent
		end
		return node, "After", parent
	end

	function Policy.IsEnabled(object)
		local ok, enabled = pcall(function()
			local starter = object:IsA("StarterGui") and object or object:FindFirstAncestorWhichIsA("StarterGui")
			if starter then
				local readable, shown = pcall(function()
					return starter.ShowDevelopmentGui
				end)
				if readable and shown == false then
					return false
				end
			end
			if object:IsA("BaseScript") then
				return not object.Disabled
			end
			return true
		end)
		return not ok or enabled ~= false
	end

	function Policy.RowState(selected, context, hovered, enabled, theme)
		local hover = theme.ExplorerHoverFill or Color3.fromRGB(187, 194, 209)
		local studioPalette = theme.SelectionProfile == "Studio"
		local selection = studioPalette and (theme.StudioSelection or Color3.fromRGB(0, 92, 181)) or theme.ListSelection
		local surface = theme.Main1
		local tint = context
				and not selected
				and ((studioPalette and selection) or theme.SelectionContext or Color3.new(
					surface.R * 0.8 + selection.R * 0.2,
					surface.G * 0.8 + selection.G * 0.2,
					surface.B * 0.8 + selection.B * 0.2
				))
			or nil
		return {
			BackgroundColor = selected and selection or (tint or (hovered and hover or surface)),
			BackgroundTransparency = selected and 0
				or (
					context and (studioPalette and 0.8 or 0)
					or (hovered and (theme.ExplorerHoverTransparency or 0.92) or 1)
				),
			HoverOverlayColor = hover,
			HoverOverlayTransparency = context and not selected and hovered and 0.94 or 1,
			TextColor = selected and (theme.SelectedText or theme.Text)
				or (enabled and theme.Text or (theme.DisabledText or theme.PlaceholderText)),
			IconTransparency = enabled and 0 or 0.62,
		}
	end

	return Policy
end
return { Main = Main }
