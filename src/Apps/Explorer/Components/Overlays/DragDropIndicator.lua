--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Indicator = {}
	function Indicator.Create(renderer)
		local React = Apps.React.React
		local ref = React.createRef()
		renderer:Portal(
			"DragDropIndicator",
			React.createElement("Frame", {
				Name = "DropIndicator",
				ref = ref,
				BorderSizePixel = 0,
				BackgroundColor3 = Settings.Theme.Focus,
				ZIndex = 10,
				Visible = false,
			}, {
				Outline = React.createElement("UIStroke", { Color = Settings.Theme.Focus, Thickness = 1 }),
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}),
			renderer.Layer
		)
		return assert(ref.current)
	end
	return Indicator
end
return { InitDeps = InitDeps, Main = Main }
