--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Underlay = {}
	function Underlay.Render(props)
		local React = Apps.React.React
		local e = React.createElement
		local s = props.state
		local x = s.backgroundX or 0
		local width = s.backgroundWidth
		local size = width and UDim2.fromOffset(width, s.height) or UDim2.fromScale(1, 1)
		local stripSize = width and UDim2.fromOffset(width, 6) or UDim2.new(1, 0, 0, 6)
		return e(React.Fragment, nil, {
			Background = e("Frame", {
				BorderSizePixel = 0,
				ZIndex = 1,
				BackgroundColor3 = s.BackgroundColor,
				BackgroundTransparency = s.BackgroundTransparency,
				Position = UDim2.fromOffset(x, 0),
				Size = size,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),
			HoverOverlay = e("Frame", {
				BorderSizePixel = 0,
				ZIndex = 2,
				BackgroundColor3 = s.HoverOverlayColor or Settings.Theme.Text,
				BackgroundTransparency = s.HoverOverlayTransparency or 1,
				Position = UDim2.fromOffset(x, 0),
				Size = size,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),
			SelectionTop = e("Frame", {
				BorderSizePixel = 0,
				ZIndex = 1,
				Visible = s.connectedAbove and true or false,
				BackgroundColor3 = s.BackgroundColor,
				BackgroundTransparency = s.BackgroundTransparency,
				Size = stripSize,
				Position = UDim2.fromOffset(x, 0),
			}),
			SelectionBottom = e("Frame", {
				BorderSizePixel = 0,
				ZIndex = 1,
				Visible = s.connectedBelow and true or false,
				BackgroundColor3 = s.BackgroundColor,
				BackgroundTransparency = s.BackgroundTransparency,
				Size = stripSize,
				Position = UDim2.fromOffset(x, (s.height or 20) - 6),
			}),
			SelectionWithin = e("Frame", {
				BackgroundTransparency = 1,
				Visible = (s.selectedWithin or s.hoveredWithin) and true or false,
				Position = UDim2.fromOffset(x + 2.5, 2.5),
				Size = width and UDim2.fromOffset(math.max(0, width - 5), (s.height or 20) - 5)
					or UDim2.new(1, -5, 1, -5),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Stroke = e("UIStroke", {
					Color = s.selectedWithin and (Settings.Theme.Brand or Color3.fromRGB(60, 100, 250))
						or (Settings.Theme.ExplorerHoverFill or Color3.fromRGB(187, 194, 209)),
					Transparency = s.selectedWithin and 0.84 or (Settings.Theme.ExplorerHoverTransparency or 0.92),
					Thickness = 2.5,
				}),
			}),
		})
	end
	return Underlay
end
return { InitDeps = InitDeps, Main = Main }
