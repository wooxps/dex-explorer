--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Edge = {}
	function Edge.Create(renderer)
		local React = Apps.React.React
		local ref = React.createRef()
		renderer:Portal(
			"GradualEdgeScroll",
			React.createElement("Frame", {
				Name = "GradualEdgeScroll",
				ref = ref,
				Visible = false,
				BorderSizePixel = 0,
				BackgroundColor3 = Settings.Theme.Focus,
				ZIndex = 14,
			}, { Fade = React.createElement("UIGradient", { Transparency = NumberSequence.new(0, 1) }) }),
			renderer.Layer
		)
		local frame = assert(ref.current)
		local api = {}
		local previousDirection, previousTime, edgeAge = 0, 0, 0
		function api.Update(x, y, width, height, direction, elapsed)
			if direction == 0 then
				previousDirection = 0
				edgeAge = 0
				frame.Visible = false
				return
			end
			if direction ~= previousDirection then
				edgeAge = 0
			else
				edgeAge += math.max(0, elapsed - previousTime)
			end
			previousDirection, previousTime = direction, elapsed
			local extent = math.clamp(7 + 13 * edgeAge / 2.3, 7, 20)
			frame.Position = UDim2.fromOffset(x, y + (direction > 0 and height - extent or 0))
			frame.Size = UDim2.fromOffset(width, extent)
			frame.Fade.Rotation = direction > 0 and -90 or 90
			frame.Visible = true
		end
		function api.Destroy()
			renderer:RemovePortal("GradualEdgeScroll")
		end
		return api
	end
	return Edge
end
return { InitDeps = InitDeps, Main = Main }
