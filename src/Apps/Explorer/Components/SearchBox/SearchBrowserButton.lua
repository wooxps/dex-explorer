--!strict

local Apps, Main, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Settings = d.Apps, d.Main, d.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Button = {}
	function Button.Create(renderer, parent, name, position)
		local React = Apps.React.React
		local e = React.createElement
		local ref = React.createRef()
		local keys = { Previous = "previous", Next = "next", SelectAll = "selectall", Refresh = "refresh" }
		renderer:Portal(
			"SearchBrowser" .. name,
			e("TextButton", {
				Name = name,
				ref = ref,
				Text = "",
				AutoButtonColor = false,
				BorderSizePixel = 0,
				BackgroundColor3 = Settings.Theme.ExplorerHoverFill or Color3.fromRGB(187, 194, 209),
				BackgroundTransparency = 1,
				Position = position,
				Size = UDim2.fromOffset(20, 20),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
				StudioIcon = e("ImageLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(2, 2),
					Size = UDim2.fromOffset(16, 16),
					Image = Main.GetStudioAsset("explorer/" .. keys[name]) or "",
					ImageColor3 = Settings.Theme.Text,
				}),
			}),
			parent
		)
		local widget = assert(ref.current)
		widget.MouseEnter:Connect(function()
			widget.BackgroundTransparency = 0.92
		end)
		widget.MouseLeave:Connect(function()
			widget.BackgroundTransparency = 1
		end)
		Apps.TooltipActions.Bind(
			widget,
			({
				Previous = "Select previous match",
				Next = "Select next match",
				SelectAll = "Select all matches",
				Refresh = "Refresh results",
			})[name],
			renderer
		)
		return assert(ref.current)
	end
	return Button
end
return { InitDeps = InitDeps, Main = CreateModule }
