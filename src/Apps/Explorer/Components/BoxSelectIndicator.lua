--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Box = {}
	function Box.Create(renderer)
		local React = Apps.React.React
		local ref = React.createRef()
		renderer:Portal(
			"BoxSelectIndicator",
			React.createElement("Frame", {
				Name = "SelectionBox",
				ref = ref,
				BackgroundColor3 = Settings.Theme.Focus,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				ZIndex = 12,
			}, {
				SelectionOutline = React.createElement("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Settings.Theme.Focus,
					Thickness = 1.5,
					Transparency = 0,
				}),
			}),
			renderer.Layer
		)
		return assert(ref.current)
	end
	return Box
end
return { InitDeps = InitDeps, Main = Main }
