--!strict

------------------------------ Module ------------------------------

local function Main()
	local View = { HeaderHeight = 24, FilterHeight = 21, FilterGap = 4, Indent = 20, ScrollRail = 16 }
	View.ToolbarHeight = View.FilterHeight + View.FilterGap
	function View.Viewport(width, height, totalWidth, totalHeight, allowHorizontal)
		local rail = View.ScrollRail
		local vertical = totalHeight > height
		local horizontal = allowHorizontal and totalWidth > math.max(0, width - (vertical and rail or 0))
		local visibleHeight = math.max(0, height - (horizontal and rail or 0))
		vertical = totalHeight > visibleHeight
		local visibleWidth = math.max(0, width - (vertical and rail or 0))
		return visibleWidth, visibleHeight, vertical, horizontal
	end
	function View.RowHeight(prop)
		if prop.CategoryName then
			return 26
		end
		local kind = prop.ValueType and prop.ValueType.Name
		if kind == "bool" or kind == "PhysicalProperties" then
			return 24
		end
		return 21
	end
	function View.Layout(rows)
		local offsets = { 0 }
		for i, prop in ipairs(rows) do
			offsets[i + 1] = offsets[i] + View.RowHeight(prop)
		end
		local layout = { Offsets = offsets, Count = #rows, Total = offsets[#rows + 1] }
		function layout:Visible(scroll, height)
			scroll = math.clamp(math.floor(scroll + 0.5), 0, math.max(0, self.Total - height))
			if height <= 0 or self.Count == 0 then
				return 1, 0, scroll
			end
			local low, high = 1, self.Count
			while low < high do
				local mid = math.floor((low + high) / 2)
				if offsets[mid + 1] <= scroll then
					low = mid + 1
				else
					high = mid
				end
			end
			local first, last = low, low
			while last < self.Count and offsets[last + 1] < scroll + height do
				last += 1
			end
			return first, last, scroll
		end
		return layout
	end
	return View
end
return { Main = Main }
