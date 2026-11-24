--!strict

local Main, Lib, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Settings = d.Main, d.Lib, d.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Rows = {}
	function Rows.Create(list, clicked, render)
		local items, pool, bindings = {}, {}, setmetatable({}, { __mode = "k" })
		local grid = false
		local function node(class, props)
			local item = Instance.new(class)
			for key, value in pairs(props) do
				item[key] = value
			end
			return item
		end
		local lastWidth, lastHeight, lastFirst, lastCount
		local function paint(force)
			local width = math.max(1, list.AbsoluteSize.X - 6)
			local columns = grid and math.max(1, math.floor(width / 128)) or 1
			local height = grid and 146 or 30
			local cell = grid and width / columns or width
			local firstRow = math.floor(list.CanvasPosition.Y / height)
			local count = (math.ceil(list.AbsoluteSize.Y / height) + 1) * columns
			if
				not force
				and lastWidth == width
				and lastHeight == list.AbsoluteSize.Y
				and lastFirst == firstRow
				and lastCount == count
			then
				return
			end
			lastWidth, lastHeight, lastFirst, lastCount = width, list.AbsoluteSize.Y, firstRow, count
			list.CanvasSize = UDim2.fromOffset(0, math.ceil(#items / columns) * height)
			for slot = 1, count do
				local button = pool[slot]
				if not button then
					button = node("TextButton", {
						Parent = list,
						Text = "",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						AutoButtonColor = false,
					})
					node(
						"ImageLabel",
						{ Name = "Icon", Parent = button, BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit }
					)
					node("TextLabel", {
						Name = "Caption",
						Parent = button,
						Text = "",
						Font = Lib.StudioFont,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextColor3 = Settings.Theme.Text,
						BackgroundTransparency = 1,
					})
					node("TextLabel", {
						Name = "Meta",
						Parent = button,
						Text = "",
						Font = Lib.StudioFont,
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextColor3 = Settings.Theme.PlaceholderText,
						BackgroundTransparency = 1,
					})
					button.Activated:Connect(function()
						local item = bindings[button]
						if item then
							clicked(item)
						end
					end)
					button.MouseEnter:Connect(function()
						button.BackgroundTransparency = 0.55
						button.BackgroundColor3 = Settings.Theme.Focus
					end)
					button.MouseLeave:Connect(function()
						render(button, bindings[button], grid)
					end)
					pool[slot] = button
				end
				local index = firstRow * columns + slot
				local item = items[index]
				bindings[button] = item
				button.Visible = item ~= nil
				button.Position =
					UDim2.fromOffset(((index - 1) % columns) * cell, math.floor((index - 1) / columns) * height)
				button.Size = UDim2.fromOffset(cell - 2, height - 2)
				button.Icon.Position = grid and UDim2.fromOffset(12, 6) or UDim2.fromOffset(8, 7)
				button.Icon.Size = grid and UDim2.new(1, -24, 0, 96) or UDim2.fromOffset(16, 16)
				button.Caption.Position = grid and UDim2.fromOffset(8, 106) or UDim2.fromOffset(32, 0)
				button.Caption.Size = grid and UDim2.new(1, -16, 0, 18) or UDim2.new(0.57, -36, 1, 0)
				button.Meta.Position = grid and UDim2.fromOffset(8, 124) or UDim2.new(0.57, 0, 0, 0)
				button.Meta.Size = grid and UDim2.new(1, -16, 0, 18) or UDim2.new(0.43, -8, 1, 0)
				if item then
					render(button, item, grid)
				end
			end
			for slot = count + 1, #pool do
				pool[slot].Visible = false
				bindings[pool[slot]] = nil
			end
		end
		Main.TrackSignal(list:GetPropertyChangedSignal("CanvasPosition"), function()
			paint(false)
		end)
		Main.TrackSignal(list:GetPropertyChangedSignal("AbsoluteSize"), function()
			paint(false)
		end)
		return {
			Set = function(_, nextItems)
				items = nextItems
				paint(true)
			end,
			SetGrid = function(_, value)
				grid = value
				list.CanvasPosition = Vector2.new(0, 0)
				paint(true)
			end,
			Paint = function()
				paint(true)
			end,
		}
	end
	return Rows
end
return { InitDeps = InitDeps, Main = CreateModule }
