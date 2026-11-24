--!strict

local service

------------------------------ Initialization ------------------------------

local function InitDeps(deps)
	service = deps.service
end

------------------------------ Module ------------------------------

local function Main()
	local Gizmo = { Style = "StudioFullRing" }
	local axisColors = { Color3.new(1, 0, 0), Color3.new(0, 1, 0), Color3.new(0.15, 0.15, 1) }
	local white = Color3.new(1, 1, 1)
	local function component(v, index)
		return index == 1 and v.X or index == 2 and v.Y or v.Z
	end
	local function sameHandle(handle, descriptor)
		return handle == descriptor or handle == descriptor.Id or type(handle) == "table" and handle.Id == descriptor.Id
	end
	local function project(camera, point)
		local p = camera:WorldToScreenPoint(point)
		return p.X, p.Y, p.Z
	end
	local function segmentDistance(px, py, ax, ay, bx, by)
		local x, y = bx - ax, by - ay
		local length = x * x + y * y
		local t = length > 1e-9 and math.clamp(((px - ax) * x + (py - ay) * y) / length, 0, 1) or 0
		local dx, dy = px - ax - t * x, py - ay - t * y
		return math.sqrt(dx * dx + dy * dy), t
	end
	local function raySphere(origin, direction, center, radius)
		local offset = origin - center
		local b = offset:Dot(direction)
		local c = offset:Dot(offset) - radius * radius
		local discriminant = b * b - c
		if discriminant < 0 then
			return nil
		end
		local near = -b - math.sqrt(discriminant)
		local far = -b + math.sqrt(discriminant)
		return near >= 0 and near or far >= 0 and far or nil
	end
	local function rayPlane(origin, direction, point, normal)
		local denominator = direction:Dot(normal)
		if math.abs(denominator) < 1e-7 then
			return nil
		end
		local t = (point - origin):Dot(normal) / denominator
		return t >= 0 and origin + direction * t or nil
	end
	local function facing(position, direction)
		local up = math.abs(direction.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		return CFrame.lookAt(position, position + direction, up)
	end

	function Gizmo.Create(gui)
		local terrain = service.Workspace.Terrain
		local view = { Handles = {}, Instances = {}, Visible = false, Scale = 1, Tool = nil }
		local identity = CFrame.new()
		local terrainFrame = identity
		pcall(function()
			terrainFrame = terrain.CFrame or identity
		end)
		local function native(class, name)
			local adornment = Instance.new(class)
			adornment.Name = name
			adornment.Adornee = terrain
			adornment.Visible = false
			adornment.AlwaysOnTop = false
			adornment.ZIndex = 0
			adornment.AdornCullingMode = Enum.AdornCullingMode.Never
			adornment.Parent = gui
			view.Instances[#view.Instances + 1] = adornment
			return adornment
		end
		local function add(kind, axis, sign)
			local handle = {
				Id = kind .. tostring(axis or "") .. tostring(sign or ""),
				Kind = kind,
				Axis = axis,
				Sign = sign or 1,
				Parts = {},
			}
			view.Handles[#view.Handles + 1] = handle
			return handle
		end
		for axis = 1, 3 do
			for _, sign in ipairs({ -1, 1 }) do
				local handle = add("Axis", axis, sign)
				handle.Shaft = native("CylinderHandleAdornment", handle.Id .. "Shaft")
				handle.Head = native("ConeHandleAdornment", handle.Id .. "Head")
				handle.OverlayShaft = native("CylinderHandleAdornment", handle.Id .. "OverlayShaft")
				handle.OverlayHead = native("ConeHandleAdornment", handle.Id .. "OverlayHead")
				handle.Parts = { handle.Shaft, handle.Head, handle.OverlayShaft, handle.OverlayHead }
			end
		end
		for normal = 1, 3 do
			local handle = add("Plane", normal)
			handle.PlaneAxes = normal == 1 and { 2, 3 } or normal == 2 and { 3, 1 } or { 1, 2 }
			handle.Plate = native("BoxHandleAdornment", handle.Id)
			handle.Parts = { handle.Plate }
		end
		local free = add("Free")
		free.Center = native("BoxHandleAdornment", "FreeMove")
		free.Parts = { free.Center }
		for axis = 1, 4 do
			local handle = add("Rotate", axis)
			handle.Ring = native("CylinderHandleAdornment", handle.Id)
			handle.Overlay = native("CylinderHandleAdornment", handle.Id .. "Overlay")
			handle.Parts = { handle.Ring, handle.Overlay }
		end
		for axis = 1, 3 do
			for _, sign in ipairs({ -1, 1 }) do
				local handle = add("Scale", axis, sign)
				handle.Sphere = native("SphereHandleAdornment", handle.Id)
				handle.Ghost = native("SphereHandleAdornment", handle.Id .. "Ghost")
				handle.Parts = { handle.Sphere, handle.Ghost }
			end
		end
		view.Sweep = native("CylinderHandleAdornment", "RotationSweep")
		view.Ticks = {}

		local function pose(adornment, worldFrame, color, transparency, top)
			adornment.CFrame = terrainFrame:ToObjectSpace(worldFrame)
			adornment.Color3 = color
			adornment.Transparency = transparency
			adornment.AlwaysOnTop = top
			adornment.ZIndex = top and 1 or 0
			adornment.Visible = true
		end
		function view:Hide()
			if not self.Visible then
				return
			end
			self.Visible = false
			self.Camera = nil
			for _, adornment in ipairs(self.Instances) do
				adornment.Visible = false
			end
		end
		function view:Destroy()
			self:Hide()
			for _, adornment in ipairs(self.Instances) do
				adornment:Destroy()
			end
			table.clear(self.Instances)
			table.clear(self.Handles)
			self.Destroyed = true
		end
		function view:Update(camera, pivot, size, tool, hover, active, tickDegrees)
			if self.Destroyed then
				return
			end
			local _, _, depth = project(camera, pivot.Position)
			if depth <= 0.01 or camera.ViewportSize.Y <= 0 or tool == "Select" then
				self:Hide()
				return
			end
			local geometryChanged = not self.Visible
				or self.Camera ~= camera
				or self.CameraFrame ~= camera.CFrame
				or self.FOV ~= camera.FieldOfView
				or self.Viewport ~= camera.ViewportSize
				or self.Pivot ~= pivot
				or self.Size ~= size
				or self.Tool ~= tool
			if
				not geometryChanged
				and self.Hover == hover
				and self.Active == active
				and self.TickDegrees == tickDegrees
			then
				return
			end
			self.Animating = false
			self.Visible = true
			self.Camera = camera
			self.CameraFrame = camera.CFrame
			self.FOV = camera.FieldOfView
			self.Viewport = camera.ViewportSize
			self.Pivot = pivot
			self.Size = size
			self.Tool = tool
			self.Hover = hover
			self.Active = active
			self.TickDegrees = tickDegrees
			self.Sweep.Visible = false
			for _, tick in ipairs(self.Ticks) do
				tick.Visible = false
			end
			local unit = math.max(0.001, math.sin(math.rad(camera.FieldOfView)) * depth * 0.05)
			self.Scale = unit
			self.Axes = { pivot.RightVector, pivot.UpVector, -pivot.LookVector }
			local origin = pivot.Position
			for _, handle in ipairs(self.Handles) do
				local enabled = (tool == "Move" and handle.Kind == "Axis")
					or (tool == "Rotate" and handle.Kind == "Rotate" and handle.Axis ~= 4)
					or (tool == "Scale" and handle.Kind == "Scale")
				handle.Visible = enabled
				for _, adornment in ipairs(handle.Parts) do
					adornment.Visible = false
				end
				if not enabled then
					continue
				end
				if tool == "Rotate" and active and not sameHandle(active, handle) then
					handle.Visible = false
					continue
				end
				local highlighted = sameHandle(hover, handle) or sameHandle(active, handle)
				local target = highlighted and 1 or 0
				handle.HoverWeight = target
				local weight = handle.HoverWeight
				local color = handle.Axis and axisColors[handle.Axis] or white
				if not highlighted and (handle.Kind == "Axis" or handle.Kind == "Rotate") then
					color = handle.Axis == 3 and Color3.new(0, 0, 0.6)
						or Color3.new(color.R * 0.8, color.G * 0.8, color.B * 0.8)
				end
				local direction = handle.Axis == 4 and camera.CFrame.LookVector
					or handle.Axis and self.Axes[handle.Axis]
					or nil
				if handle.Kind == "Axis" then
					direction *= handle.Sign
				end
				handle.AxisVector = direction
				handle.Pivot = pivot
				if handle.Kind == "Axis" then
					local offset = (0.6 + 4 * 0.3) * unit
					local length = 4 * unit
					local radius = 0.1 * unit * (1 + 0.5 * weight)
					local headRadius = 3 * radius
					local shaftFrame = facing(origin + direction * (offset + length * 0.5), direction)
					local headFrame = facing(origin + direction * (offset + length), direction)
					handle.Start = origin + direction * offset
					handle.Finish = origin + direction * (offset + length + unit * (1 + 0.5 * weight))
					handle.Position = handle.Finish
					for _, shaft in ipairs({ handle.Shaft, handle.OverlayShaft }) do
						shaft.Radius = radius
						shaft.Height = length
					end
					for _, head in ipairs({ handle.Head, handle.OverlayHead }) do
						head.Radius = headRadius
						head.Height = unit * (1 + 0.5 * weight)
					end
					if not highlighted then
						pose(handle.Shaft, shaftFrame, color, 0, false)
						pose(handle.Head, headFrame, color, 0, false)
					end
					pose(handle.OverlayShaft, shaftFrame, color, 0.45 * (1 - weight), true)
					pose(handle.OverlayHead, headFrame, color, 0.45 * (1 - weight), true)
				elseif handle.Kind == "Plane" then
					local a, b = self.Axes[handle.PlaneAxes[1]], self.Axes[handle.PlaneAxes[2]]
					handle.Position = origin + (a + b) * (1.75 * unit)
					handle.HalfSize = 0.35 * unit * (highlighted and 1.3 or 1)
					handle.Plate.Size = Vector3.new(handle.HalfSize * 2, handle.HalfSize * 2, 0.01 * unit)
					pose(handle.Plate, CFrame.fromMatrix(handle.Position, a, b, a:Cross(b)), color, 0, true)
				elseif handle.Kind == "Free" then
					handle.Position = origin
					handle.Radius = 0.35 * unit
					handle.Center.Size = Vector3.new(0.7 * unit, 0.7 * unit, 0.01 * unit) * (highlighted and 1.3 or 1)
					pose(
						handle.Center,
						CFrame.fromMatrix(
							origin,
							camera.CFrame.RightVector,
							camera.CFrame.UpVector,
							-camera.CFrame.LookVector
						),
						color,
						0,
						true
					)
				elseif handle.Kind == "Rotate" then
					handle.Position = origin
					handle.Radius = (4.5 + (handle.Axis - 1) * 0.01 + (highlighted and 0.1 or 0)) * unit
					local a = self.Axes[handle.Axis % 3 + 1]
					local b = direction:Cross(a)
					local ringFrame = CFrame.fromMatrix(origin, a, b, direction)
					local thickness = 0.1 * unit * (highlighted and 1.5 or 1)
					local arc = 360
					for _, ring in ipairs(handle.Parts) do
						ring.Radius = handle.Radius + thickness * 0.5
						ring.InnerRadius = handle.Radius - thickness * 0.5
						ring.Height = thickness
						ring.Angle = arc
					end
					pose(handle.Ring, ringFrame, color, 0, false)
					pose(handle.Overlay, ringFrame, color, 0.45, true)
					if highlighted and tickDegrees and tickDegrees >= 5 then
						local increment = math.rad(tickDegrees)
						local count = math.min(72, math.ceil(math.rad(arc) / increment))
						for index = 1, count do
							local tick = self.Ticks[index]
							if not tick then
								tick = native("BoxHandleAdornment", "RotationTick" .. index)
								self.Ticks[index] = tick
							end
							local angle = (index - 1) * increment
							local radial = a * math.cos(angle) + b * math.sin(angle)
							local tangent = -a * math.sin(angle) + b * math.cos(angle)
							local major = math.abs(angle / (math.pi * 0.5) - math.floor(angle / (math.pi * 0.5) + 0.5))
								< 0.001
							local length = handle.Radius * (major and 0.3 or 0.1)
							local width = unit * (major and 0.1 or 0.05)
							tick.Size = Vector3.new(width, width, length)
							pose(
								tick,
								CFrame.fromMatrix(
									origin + radial * (handle.Radius - length * 0.5),
									tangent,
									direction,
									radial
								),
								color,
								0,
								true
							)
						end
					end
					if active and active.DragStart and active.DragAngle then
						local angle = active.DragAngle % (2 * math.pi)
						if angle > math.pi then
							angle -= 2 * math.pi
						end
						local start = active.DragStart
						if angle < 0 then
							start = CFrame.fromAxisAngle(direction, angle):VectorToWorldSpace(start)
						end
						if math.abs(angle) > 0.001 then
							self.Sweep.Height = 0
							self.Sweep.InnerRadius = 0
							self.Sweep.Radius = handle.Radius
							self.Sweep.Angle = math.deg(math.abs(angle))
							pose(
								self.Sweep,
								CFrame.fromMatrix(origin, start, direction:Cross(start), direction),
								color,
								0.6,
								true
							)
						end
					end
					if geometryChanged then
						local points = {}
						for index = 0, 64 do
							local angle = index * math.rad(arc) / 64
							local position = origin + (a * math.cos(angle) + b * math.sin(angle)) * handle.Radius
							local x, y, z = project(camera, position)
							points[#points + 1] =
								{ X = x, Y = y, Z = z, Radial = a * math.cos(angle) + b * math.sin(angle) }
						end
						handle.ProjectedRing = points
					end
				else
					handle.Position = origin
						+ direction * handle.Sign * (component(size, handle.Axis) * 0.5 + 1.5 * unit)
					handle.Radius = 0.5 * unit
					handle.Sphere.Radius = handle.Radius * (1 + 0.15 * weight)
					handle.Ghost.Radius = handle.Radius
					pose(handle.Sphere, CFrame.new(handle.Position), color, 0.2 * (1 - weight), highlighted)
					if not highlighted then
						pose(handle.Ghost, CFrame.new(handle.Position), color, 0.75, true)
					end
				end
			end
		end
		function view:HitTest(camera, screenPoint)
			if not self.Visible or self.Destroyed or camera ~= self.Camera then
				return nil
			end
			local ray = camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
			local direction = ray.Direction.Unit
			local best, bestScore = nil, math.huge
			for _, handle in ipairs(self.Handles) do
				if not handle.Visible then
					continue
				end
				local score
				if handle.Kind == "Scale" or handle.Kind == "Free" then
					local t = raySphere(ray.Origin, direction, handle.Position, handle.Radius * 1.25)
					if t then
						score = 0.1 + t * 1e-7
					end
				elseif handle.Kind == "Plane" then
					local point = rayPlane(ray.Origin, direction, handle.Position, handle.AxisVector)
					if point then
						local offset = point - handle.Position
						local a, b = self.Axes[handle.PlaneAxes[1]], self.Axes[handle.PlaneAxes[2]]
						if
							math.abs(offset:Dot(a)) <= handle.HalfSize
							and math.abs(offset:Dot(b)) <= handle.HalfSize
						then
							score = 0.2
						end
					end
				elseif handle.Kind == "Axis" then
					local ax, ay, az = project(camera, handle.Start)
					local bx, by, bz = project(camera, handle.Finish)
					if az > 0 and bz > 0 and (bx - ax) ^ 2 + (by - ay) ^ 2 > 16 then
						local distance = segmentDistance(screenPoint.X, screenPoint.Y, ax, ay, bx, by)
						if distance <= 8 then
							score = 0.3 + distance / 8
						end
					end
				else
					local points = handle.ProjectedRing
					if points then
						for index = 1, #points - 1 do
							local a, b = points[index], points[index + 1]
							if a.Z > 0 and b.Z > 0 then
								local distance, t = segmentDistance(screenPoint.X, screenPoint.Y, a.X, a.Y, b.X, b.Y)
								if distance <= 7 then
									local candidate = distance / 7 + (a.Z + (b.Z - a.Z) * t) * 1e-7
									if not score or candidate < score then
										score = candidate
										handle.HitVector = (a.Radial * (1 - t) + b.Radial * t).Unit
									end
								end
							end
						end
					end
				end
				if score and score < bestScore then
					best, bestScore = handle, score
				end
			end
			return best
		end
		return view
	end
	return Gizmo
end
return { InitDeps = InitDeps, Main = Main }
