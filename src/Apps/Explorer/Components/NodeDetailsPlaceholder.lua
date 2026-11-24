--!strict

------------------------------ Module ------------------------------

local function Main()
	local Details = {}
	function Details.IconLeft(depth)
		return math.max(0, depth) * 12 + 20
	end
	function Details.Measure(depth, textWidth)
		local iconLeft = Details.IconLeft(depth)
		return {
			iconLeft = iconLeft,
			leftOfName = iconLeft + 21,
			textWidth = textWidth,
			total = iconLeft + 21 + textWidth,
		}
	end
	return Details
end
return { Main = Main }
