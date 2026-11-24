--!strict

local Main, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(dependencies)
	Main, Apps = dependencies.Main, dependencies.Apps
end

------------------------------ Module ------------------------------

local function CreateModule()
	local ExplorerNodeRow = {}

	function ExplorerNodeRow.Render(props)
		local state = props.state
		local React = Apps.React.React
		local createElement = React.createElement
		local chevronAsset = if state.expanded then "explorer/expanded" else "explorer/collapsed"

		return createElement("TextButton", {
			Name = "Entry",
			ref = props.rowRef,
			AutoButtonColor = false,
			Text = "",
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = state.position,
			Size = state.size,
			BackgroundColor3 = state.BackgroundColor,
			BackgroundTransparency = 1,
		}, {
			Underlays = createElement(Apps.UnderlaysRow.Render, { state = state }),
			Guides = Apps.IndentGuides.Render(React, state.guideCount),
			Indent = createElement("Frame", {
				BackgroundTransparency = 1,
				ZIndex = 3,
				Position = UDim2.fromOffset(state.depth, 0),
				Size = UDim2.new(1, -state.depth, 1, 0),
			}, {
				Icon = createElement("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 0, 0.5, -8),
					Size = UDim2.fromOffset(16, 16),
					ZIndex = 3,
				}),
				EntryName = createElement("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.BuilderSans,
					TextSize = 14,
					Position = UDim2.fromOffset(21, 0),
					Size = UDim2.fromOffset(state.labelWidth, state.height),
					Text = state.name,
					TextColor3 = state.TextColor,
					ZIndex = 3,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = if state.truncate == false then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
					TextTransparency = if state.renaming then 1 else 0,
				}),
				StatusBadge = createElement("ImageLabel", {
					Name = "StatusBadge",
					BackgroundTransparency = 1,
					ZIndex = 3,
					Position = UDim2.new(0, state.statusX or 0, 0.5, -8),
					Size = UDim2.fromOffset(16, 16),
					Image = state.statusAsset or "",
					Visible = state.statusAsset ~= nil,
				}),
				Expand = createElement("TextButton", {
					BackgroundTransparency = 1,
					ZIndex = 3,
					AutoButtonColor = false,
					Text = "",
					Visible = state.hasChildren,
					Position = UDim2.fromOffset(-20, 0),
					Size = UDim2.new(0, 20, 1, 0),
				}, {
					StudioChevron = createElement("ImageLabel", {
						BackgroundTransparency = 1,
						ZIndex = 3,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0, 11.5, 0.5, 0),
						Size = UDim2.fromOffset(16, 16),
						Image = Main.GetStudioAsset(chevronAsset) or "",
						ImageColor3 = state.TextColor,
					}),
				}),
			}),
			Insert = Apps.InsertObjectOverlay.Render(React, state),
		})
	end

	return ExplorerNodeRow
end

return { InitDeps = InitDeps, Main = CreateModule }
