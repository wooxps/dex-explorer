--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Rename = {}
	function Rename.Create(renderer, parent)
		local React = Apps.React.React
		local ref = React.createRef()
		renderer:Portal(
			"RenameBox",
			React.createElement("TextBox", {
				Name = "RenameBox",
				ref = ref,
				BackgroundColor3 = Settings.Theme.Main1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ClearTextOnFocus = false,
				Font = Enum.Font.BuilderSans,
				Position = UDim2.fromOffset(37, 0),
				Size = UDim2.fromOffset(204, 20),
				Text = "",
				TextColor3 = Settings.Theme.PlaceholderText,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				Visible = false,
				ZIndex = 5,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Padding = React.createElement("UIPadding", { PaddingLeft = UDim.new(0, 4) }),
				Border = React.createElement(
					"UIStroke",
					{ ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Settings.Theme.Focus, Thickness = 2 }
				),
			}),
			parent
		)
		return assert(ref.current, "Rename box did not mount")
	end
	return Rename
end
return { InitDeps = InitDeps, Main = Main }
