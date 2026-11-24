--!strict

local Main, Lib, Settings, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Settings, createSimple = d.Main, d.Lib, d.Settings, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Insert = { Size = 20, IconSize = 12, MenuWidth = 240 }
	function Insert.Render(React, state)
		local image = Main.GetStudioAsset("explorer/insert")
		local e = React.createElement
		return e("TextButton", {
			Name = "Insert",
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(state.insertX, math.floor((state.height - 20) / 2)),
			Size = UDim2.fromOffset(20, 20),
			Visible = state.insertVisible,
			ZIndex = 4,
		}, {
			StudioIcon = e("ImageLabel", {
				BackgroundTransparency = 1,
				Image = image or "",
				ImageColor3 = Settings.Theme.PlaceholderText,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(12, 12),
				ZIndex = 5,
			}),
			Horizontal = not image and e("Frame", {
				BackgroundColor3 = Settings.Theme.PlaceholderText,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(5, 9),
				Size = UDim2.fromOffset(10, 1),
				ZIndex = 5,
			}) or nil,
			Vertical = not image and e("Frame", {
				BackgroundColor3 = Settings.Theme.PlaceholderText,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(9, 5),
				Size = UDim2.fromOffset(1, 10),
				ZIndex = 5,
			}) or nil,
		})
	end
	function Insert.IsVisible(node, openFor, hovered, blocked)
		if openFor then
			return openFor == node
		end
		return hovered and not blocked
	end
	function Insert.Anchor(button)
		return button.AbsolutePosition.X + button.AbsoluteSize.X - Insert.MenuWidth,
			button.AbsolutePosition.Y + button.AbsoluteSize.Y
	end
	return Insert
end
return { InitDeps = InitDeps, Main = CreateModule }
