--!strict

------------------------------ Module ------------------------------

local function Main()
	local Camera = {}
	function Camera.Create()
		local self = {
			Yaw = math.rad(35),
			Pitch = math.rad(20),
			X = 0,
			Y = 0,
			Z = 0,
			Distance = 10,
			Radius = 1,
			Aspect = 1,
			FieldOfView = 45,
		}
		function self:Fit(radius, aspect, reset)
			self.Radius = math.max(0.01, radius)
			self.Aspect = math.max(0.01, aspect)
			local half = math.rad(self.FieldOfView / 2)
			self.FitDistance =
				math.max(0.1, self.Radius / math.sin(math.min(half, math.atan(math.tan(half) * self.Aspect))) * 1.12)
			self.Minimum = math.max(0.05, self.Radius * 0.03)
			self.Maximum = self.FitDistance * 50
			self.Distance = self.FitDistance
			self.X = 0
			self.Y = 0
			self.Z = 0
			if reset then
				self.Yaw = math.rad(35)
				self.Pitch = math.rad(20)
			end
		end
		function self:Resize(aspect)
			local ratio = self.Distance / (self.FitDistance or self.Distance)
			local x, y, z = self.X, self.Y, self.Z
			self:Fit(self.Radius, aspect)
			self.Distance = math.clamp(self.FitDistance * ratio, self.Minimum, self.Maximum)
			self.X, self.Y, self.Z = x, y, z
		end
		function self:Orbit(dx, dy)
			self.Yaw = (self.Yaw - dx * 0.008) % (math.pi * 2)
			self.Pitch = math.clamp(self.Pitch + dy * 0.008, -math.pi / 2 + 0.02, math.pi / 2 - 0.02)
		end
		function self:Basis()
			local sy, cy, sp, cp = math.sin(self.Yaw), math.cos(self.Yaw), math.sin(self.Pitch), math.cos(self.Pitch)
			return { X = cy, Y = 0, Z = -sy }, { X = -sy * sp, Y = cp, Z = -cy * sp }, {
				X = -sy * cp,
				Y = -sp,
				Z = -cy * cp,
			}
		end
		function self:Pan(dx, dy, height)
			local right, up = self:Basis()
			local scale = 2 * self.Distance * math.tan(math.rad(self.FieldOfView / 2)) / math.max(1, height)
			self.X += (-dx * right.X + dy * up.X) * scale
			self.Y += (-dx * right.Y + dy * up.Y) * scale
			self.Z += (-dx * right.Z + dy * up.Z) * scale
		end
		function self:Zoom(steps)
			self.Distance =
				math.clamp(self.Distance * math.exp(-steps * 0.15), self.Minimum or 0.05, self.Maximum or 1000)
		end
		function self:Pose()
			local _, _, forward = self:Basis()
			return {
				X = self.X - forward.X * self.Distance,
				Y = self.Y - forward.Y * self.Distance,
				Z = self.Z - forward.Z * self.Distance,
			}, { X = self.X, Y = self.Y, Z = self.Z }
		end
		function self:Ray(x, y, width, height)
			local right, up, forward = self:Basis()
			local tangent = math.tan(math.rad(self.FieldOfView / 2))
			local nx = (2 * x / math.max(1, width) - 1) * width / math.max(1, height) * tangent
			local ny = (1 - 2 * y / math.max(1, height)) * tangent
			local dx, dy, dz =
				forward.X + right.X * nx + up.X * ny,
				forward.Y + right.Y * nx + up.Y * ny,
				forward.Z + right.Z * nx + up.Z * ny
			local length = math.sqrt(dx * dx + dy * dy + dz * dz)
			local origin = self:Pose()
			return origin, { X = dx / length, Y = dy / length, Z = dz / length }
		end
		return self
	end
	return Camera
end
return { Main = Main }
