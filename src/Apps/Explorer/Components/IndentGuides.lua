--!strict

local Main, Settings, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Settings, createSimple = d.Main, d.Settings, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Guides = {}
	function Guides.Render(React, count)
		local children = {}
		for level = 1, count do
			children[tostring(level)] = React.createElement("ImageLabel", {
				BackgroundTransparency = 1,
				Image = Main.GetStudioAsset("native/explorer/indent_guide") or "",
				ImageColor3 = Settings.Theme.SurfaceOutline or Color3.new(1, 1, 1),
				ImageTransparency = Settings.Theme.SurfaceOutlineTransparency or 0.88,
				BorderSizePixel = 0,
				ZIndex = 3,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromScale(1, 1),
				Position = UDim2.fromOffset((level - 1) * 12, 0),
				Size = UDim2.new(0, 12, 1, 0),
			})
		end
		return React.createElement("Folder", {}, children)
	end
	function Guides.Update(folder, count)
		for level = 1, count do
			local name = tostring(level)
			local guide = folder:FindFirstChild(name)
			if not guide then
				guide = createSimple("ImageLabel", { Name = name, Parent = folder, BorderSizePixel = 0 })
			end
			guide.BackgroundTransparency = 1
			guide.Image = Main.GetStudioAsset("native/explorer/indent_guide") or ""
			guide.ImageColor3 = Settings.Theme.SurfaceOutline or Color3.new(1, 1, 1)
			guide.ImageTransparency = Settings.Theme.SurfaceOutlineTransparency or 0.88
			guide.ScaleType = Enum.ScaleType.Tile
			guide.TileSize = UDim2.fromScale(1, 1)
			guide.Position = UDim2.fromOffset((level - 1) * 12, 0)
			guide.Size = UDim2.new(0, 12, 1, 0)
			guide.Visible = true
		end
		for _, guide in ipairs(folder:GetChildren()) do
			guide.Visible = tonumber(guide.Name) <= count
		end
	end
	return Guides
end
return { InitDeps = InitDeps, Main = CreateModule }
