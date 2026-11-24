--!strict

------------------------------ Module ------------------------------

local function Main()
	local Scene = {}
	local function part(parent, name, size, frame, color)
		local value = Instance.new("Part")
		value.Name = name
		value.Size = size
		value.CFrame = frame
		value.Anchored = true
		value.CanCollide = false
		value.CanTouch = false
		value.CanQuery = false
		value.CastShadow = false
		value.Material = Enum.Material.SmoothPlastic
		value.Color = color
		value.Parent = parent
		return value
	end
	local function snapshot(source)
		local restored, childrenAtCopy = {}, {}
		local clone
		local ok, problem = pcall(function()
			local originals = source:GetDescendants()
			originals[#originals + 1] = source
			for _, object in ipairs(originals) do
				if object ~= source then
					local parent = object.Parent
					if parent then
						local children = childrenAtCopy[parent]
						if not children then
							children = { Objects = {}, Names = {} }
							childrenAtCopy[parent] = children
						end
						children.Objects[#children.Objects + 1] = object
						children.Names[#children.Names + 1] = object.Name
					end
				end
				if not object.Archivable then
					restored[#restored + 1] = object
					object.Archivable = true
				end
			end
			clone = assert(source:Clone(), "This object could not be cloned")
		end)
		for _, object in ipairs(restored) do
			pcall(function()
				object.Archivable = false
			end)
		end
		if not ok then
			if clone then
				clone:Destroy()
			end
			error(problem, 0)
		end
		return clone, childrenAtCopy
	end
	local function matchChildren(stack, children, snapshot)
		local originals, names = snapshot.Objects, snapshot.Names
		local ordered = #children == #originals
		if ordered then
			for index, child in ipairs(children) do
				if child.Name ~= names[index] or child.ClassName ~= originals[index].ClassName then
					ordered = false
					break
				end
			end
		end
		if ordered then
			for index, child in ipairs(children) do
				stack[#stack + 1] = { child, originals[index] }
			end
			return
		end
		local matches, counts = {}, {}
		for index, original in ipairs(originals) do
			local key = original.ClassName .. ":" .. names[index]
			matches[key] = if matches[key] == nil then original else false
		end
		for _, child in ipairs(children) do
			local key = child.ClassName .. ":" .. child.Name
			counts[key] = (counts[key] or 0) + 1
		end
		for _, child in ipairs(children) do
			local key = child.ClassName .. ":" .. child.Name
			if counts[key] == 1 and matches[key] then
				stack[#stack + 1] = { child, matches[key] }
			end
		end
	end
	function Scene.Build(source)
		assert(
			source ~= workspace and not source:IsA("Terrain") and (source:IsA("Model") or source:IsA("BasePart")),
			"Choose a Model or BasePart to preview"
		)
		local world = Instance.new("WorldModel")
		world.Name = "PreviewWorld"
		local model
		local ok, result = pcall(function()
			local clone, childrenAtCopy = snapshot(source)
			model = Instance.new("Model")
			model.Name = "PreviewContent"
			clone.Parent = model
			local map, reverse = {}, {}
			local stack = { { clone, source } }
			while #stack > 0 do
				local pair = table.remove(stack)
				local copied, original = pair[1], pair[2]
				map[copied] = original
				reverse[original] = copied
				local children = childrenAtCopy[original]
				if children then
					matchChildren(stack, copied:GetChildren(), children)
				end
			end
			local count = 0
			for _, object in ipairs(model:GetDescendants()) do
				if object:IsA("LuaSourceContainer") or object:IsA("Sound") then
					object:Destroy()
				elseif object:IsA("BasePart") and object:IsDescendantOf(model) then
					object.Anchored = true
					object.CanCollide = false
					object.CanTouch = false
					object.CanQuery = object.Transparency < 1
					count += 1
				end
			end
			assert(count > 0, "This object has no parts to preview")
			local bounds, size = model:GetBoundingBox()
			model:PivotTo(CFrame.new(-bounds.Position) * model:GetPivot())
			bounds = model:GetBoundingBox()
			local bottom = math.huge
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						bottom =
							math.min(bottom, (bounds * Vector3.new(size.X * x / 2, size.Y * y / 2, size.Z * z / 2)).Y)
					end
				end
			end
			local radius = math.max(0.01, size.Magnitude / 2)
			local grid = Instance.new("Model")
			grid.Name = "FloorGrid"
			grid.Parent = world
			local spacing = 10 ^ math.floor(math.log10(math.max(0.01, radius / 5)))
			local ratio = radius / 5 / spacing
			spacing *= ratio > 5 and 10 or ratio > 2 and 5 or ratio > 1 and 2 or 1
			local extent = spacing * 10
			local thickness = math.max(0.002, spacing * 0.012)
			local floor = bottom - math.max(0.01, radius * 0.005)
			for index = -10, 10 do
				local shade = index == 0 and Color3.fromRGB(100, 115, 130) or Color3.fromRGB(65, 68, 74)
				part(
					grid,
					"X",
					Vector3.new(extent * 2, thickness, thickness),
					CFrame.new(0, floor, index * spacing),
					index == 0 and Color3.fromRGB(157, 77, 80) or shade
				)
				part(
					grid,
					"Z",
					Vector3.new(thickness, thickness, extent * 2),
					CFrame.new(index * spacing, floor, 0),
					index == 0 and Color3.fromRGB(72, 110, 153) or shade
				)
			end
			model.Parent = world
			local outline = Instance.new("Model")
			outline.Name = "SelectionOutline"
			outline.Parent = world
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { model }
			params.IgnoreWater = true
			local self = {
				World = world,
				Model = model,
				Grid = grid,
				Map = map,
				Reverse = reverse,
				Radius = radius,
				Size = size,
				PartCount = count,
				Source = source,
				Spacing = spacing,
			}
			function self:SetGrid(enabled)
				grid.Parent = enabled and world or nil
			end
			local outlined
			function self:Select(original)
				local object = reverse[original]
				if object == outlined then
					return
				end
				outlined = object
				outline:ClearAllChildren()
				if not object or not object:IsA("BasePart") or not object:IsDescendantOf(model) then
					return
				end
				local size = object.Size + Vector3.new(0.015, 0.015, 0.015)
				local half = { size.X / 2, size.Y / 2, size.Z / 2 }
				local color = Color3.fromRGB(75, 166, 255)
				local thickness = math.clamp(math.min(size.X, size.Y, size.Z) * 0.025, 0.008, 0.1)
				for axis = 1, 3 do
					local a = axis % 3 + 1
					local b = (axis + 1) % 3 + 1
					for _, signA in ipairs({ -1, 1 }) do
						for _, signB in ipairs({ -1, 1 }) do
							local offsets = { 0, 0, 0 }
							offsets[a] = half[a] * signA
							offsets[b] = half[b] * signB
							local dimensions = { thickness, thickness, thickness }
							dimensions[axis] = half[axis] * 2
							part(
								outline,
								"Edge",
								Vector3.new(dimensions[1], dimensions[2], dimensions[3]),
								object.CFrame * CFrame.new(offsets[1], offsets[2], offsets[3]),
								color
							)
						end
					end
				end
			end
			function self:Pick(origin, direction, length)
				local hit = world:Raycast(
					Vector3.new(origin.X, origin.Y, origin.Z),
					Vector3.new(direction.X, direction.Y, direction.Z) * length,
					params
				)
				local original = hit and map[hit.Instance]
				if original and (original == source or original:IsDescendantOf(source)) then
					return original
				end
				return nil
			end
			function self:Destroy()
				grid:Destroy()
				world:Destroy()
				table.clear(map)
				table.clear(reverse)
			end
			return self
		end)
		if not ok then
			if model and not model.Parent then
				model:Destroy()
			end
			world:Destroy()
			error(result, 0)
		end
		return result
	end
	return Scene
end
return { Main = Main }
