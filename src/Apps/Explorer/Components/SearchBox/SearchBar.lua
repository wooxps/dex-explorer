--!strict

local Apps, Main, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main, Settings = d.Apps, d.Main, d.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Bar = {}
	function Bar.Create(renderer, parent)
		local React = Apps.React.React
		local e = React.createElement
		local searchRef, optionsRef = React.createRef(), React.createRef()
		local function icon(key, size)
			return e("Frame", {
				Name = "StudioIcon",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
			}, {
				Native = e("ImageLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = Main.GetStudioAsset(key) or "",
					ScaleType = Enum.ScaleType.Fit,
				}),
			})
		end
		local old = parent:FindFirstChild("SearchFrame")
		if old then
			old:Destroy()
		end
		parent.BackgroundColor3 = Settings.Theme.Main2
		parent.Size = UDim2.new(1, 0, 0, 29)
		renderer:Portal(
			"SearchHeader",
			e(React.Fragment, nil, {
				SearchFrame = e("Frame", {
					ref = searchRef,
					BackgroundColor3 = Settings.Theme.TextBox,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.new(1, -33, 0, 20),
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
					Stroke = e("UIStroke", {
						Thickness = 1.5,
						Color = Settings.Theme.Brand or Color3.fromRGB(60, 100, 250),
						Enabled = false,
					}),
					SearchBox = e("TextBox", {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						ClearTextOnFocus = false,
						Font = Enum.Font.BuilderSans,
						TextSize = 14,
						Text = "",
						PlaceholderText = "Search",
						TextColor3 = Settings.Theme.Text,
						PlaceholderColor3 = Settings.Theme.PlaceholderText,
						TextXAlignment = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(5, 0),
						Size = UDim2.new(1, -31, 1, 0),
					}),
					Reset = e("TextButton", {
						AutoButtonColor = false,
						BorderSizePixel = 0,
						BackgroundTransparency = 1,
						Text = "",
						Visible = false,
						Position = UDim2.new(1, -42, 0, 2),
						Size = UDim2.fromOffset(16, 16),
					}, {
						Icon = e("ImageLabel", {
							BackgroundTransparency = 1,
							Position = UDim2.fromOffset(0, 0),
							Size = UDim2.fromOffset(16, 16),
							Image = Main.GetStudioAsset("explorer/clear") or "",
						}),
					}),
					History = e("TextButton", {
						AutoButtonColor = false,
						BorderSizePixel = 0,
						BackgroundTransparency = 1,
						Text = "",
						Position = UDim2.new(1, -21, 0, 2),
						Size = UDim2.fromOffset(16, 16),
					}, { StudioIcon = icon("explorer/history", 16) }),
				}),
				Options = e("TextButton", {
					ref = optionsRef,
					AutoButtonColor = false,
					BackgroundColor3 = Settings.Theme.TextBox,
					BorderSizePixel = 0,
					Text = "",
					Position = UDim2.new(1, -24, 0, 4),
					Size = UDim2.fromOffset(20, 20),
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
					StudioIcon = icon("explorer/options", 16),
				}),
				BottomBorder = e("Frame", {
					BorderSizePixel = 0,
					BackgroundColor3 = Settings.Theme.TextBox,
					Position = UDim2.new(0, 0, 1, -1),
					Size = UDim2.new(1, 0, 0, 1),
				}),
			}),
			parent
		)
		local frame = assert(searchRef.current)
		local box = frame.SearchBox
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		pcall(function()
			box.ShouldEmitUpAndDownArrowEvents = true
		end)
		box.Focused:Connect(function()
			stroke.Enabled = true
		end)
		box.FocusLost:Connect(function()
			stroke.Enabled = false
		end)
		local function changed()
			local normalized = box.Text:sub(1, 32767):gsub("\n", " "):gsub("\r", "")
			if box.Text ~= normalized then
				box.Text = normalized
			end
			frame.Reset.Visible = box.Text ~= ""
			box.Size = UDim2.new(1, box.Text == "" and -31 or -52, 1, 0)
		end
		box:GetPropertyChangedSignal("Text"):Connect(changed)
		return { SearchBox = box, History = frame.History, Options = optionsRef.current }
	end
	return Bar
end
return { InitDeps = InitDeps, Main = CreateModule }
