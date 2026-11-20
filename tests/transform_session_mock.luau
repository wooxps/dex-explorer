--!strict

-- Numerical doubles for transform calculations, not engine physics/rendering.
Apps.Explorer = {}
local vectorMT = {}
local function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vectorMT)
end
local function dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
local function cross(a, b)
	return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
vectorMT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(dot(v, v))
	end
	if k == "Unit" then
		return v / v.Magnitude
	end
	if k == "Dot" then
		return dot
	end
	if k == "Cross" then
		return cross
	end
end
vectorMT.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vectorMT.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vectorMT.__unm = function(v)
	return vec(-v.X, -v.Y, -v.Z)
end
vectorMT.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	return vec(a.X * b, a.Y * b, a.Z * b)
end
vectorMT.__div = function(v, n)
	return vec(v.X / n, v.Y / n, v.Z / n)
end
vectorMT.__eq = function(a, b)
	return math.abs(a.X - b.X) < 1e-9 and math.abs(a.Y - b.Y) < 1e-9 and math.abs(a.Z - b.Z) < 1e-9
end
Vector3.new = vec
local frameMT = {}
local function frame(position, right, up, back)
	return setmetatable({
		Position = position,
		RightVector = right or vec(1, 0, 0),
		UpVector = up or vec(0, 1, 0),
		ZVector = back or vec(0, 0, 1),
	}, frameMT)
end
local function rotate(cf, v)
	return cf.RightVector * v.X + cf.UpVector * v.Y + cf.ZVector * v.Z
end
frameMT.__index = {
	PointToObjectSpace = function(cf, v)
		v = v - cf.Position
		return vec(dot(cf.RightVector, v), dot(cf.UpVector, v), dot(cf.ZVector, v))
	end,
	VectorToObjectSpace = function(cf, v)
		return vec(dot(cf.RightVector, v), dot(cf.UpVector, v), dot(cf.ZVector, v))
	end,
	VectorToWorldSpace = rotate,
	Inverse = function(cf)
		local right = vec(cf.RightVector.X, cf.UpVector.X, cf.ZVector.X)
		local up = vec(cf.RightVector.Y, cf.UpVector.Y, cf.ZVector.Y)
		local back = vec(cf.RightVector.Z, cf.UpVector.Z, cf.ZVector.Z)
		local result = frame(vec(), right, up, back)
		result.Position = rotate(result, -cf.Position)
		return result
	end,
}
frameMT.__mul = function(a, b)
	if getmetatable(b) == vectorMT then
		return a.Position + rotate(a, b)
	end
	return frame(a * b.Position, rotate(a, b.RightVector), rotate(a, b.UpVector), rotate(a, b.ZVector))
end
frameMT.__add = function(a, b)
	return frame(a.Position + b, a.RightVector, a.UpVector, a.ZVector)
end
frameMT.__sub = function(a, b)
	return a + -b
end
frameMT.__eq = function(a, b)
	return a.Position == b.Position
		and a.RightVector == b.RightVector
		and a.UpVector == b.UpVector
		and a.ZVector == b.ZVector
end
CFrame = {
	new = function(x, y, z)
		return frame(type(x) == "table" and x or vec(x, y, z))
	end,
}
CFrame.fromAxisAngle = function(axis, angle)
	local unit = axis.Unit
	local cosine, sine = math.cos(angle), math.sin(angle)
	local function transform(v)
		return v * cosine + cross(unit, v) * sine + unit * dot(unit, v) * (1 - cosine)
	end
	return frame(vec(), transform(vec(1, 0, 0)), transform(vec(0, 1, 0)), transform(vec(0, 0, 1)))
end
CFrame.fromMatrix = function(position, right, up, back)
	return frame(position, right, up, back or cross(right, up))
end
CFrame.lookAt = function(position, target, up)
	local back = (position - target).Unit
	local right = cross(up or vec(0, 1, 0), back).Unit
	return frame(position, right, cross(back, right), back)
end
frameMT.__index.ToObjectSpace = function(cf, other)
	return cf:Inverse() * other
end
local baseFrameIndex = frameMT.__index
baseFrameIndex.GetComponents = function(cf)
	local p, x, y, z = cf.Position, cf.RightVector, cf.UpVector, cf.ZVector
	return p.X, p.Y, p.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z
end
frameMT.__index = function(cf, key)
	if key == "LookVector" then
		return -cf.ZVector
	end
	return baseFrameIndex[key]
end
local oldTypeof = typeof
typeof = function(value)
	return type(value) == "table" and value._props and "Instance" or oldTypeof(value)
end
function methods:GetPivot()
	if self:IsA("BasePart") then
		return self.CFrame * (self.PivotOffset or CFrame.new())
	end
	return self._props.Pivot or CFrame.new()
end
function methods:PivotTo(target)
	if self:IsA("BasePart") then
		self.CFrame = target * (self.PivotOffset or CFrame.new()):Inverse()
		return
	end
	local delta = target * self:GetPivot():Inverse()
	for _, object in ipairs(self:GetDescendants()) do
		if object:IsA("BasePart") then
			object.CFrame = delta * object.CFrame
		end
	end
	self.Pivot = target
end
function methods:GetScale()
	return self.Scale or 1
end
function methods:GetBoundingBox()
	local orientation = self:GetPivot() - self:GetPivot().Position
	local minimum = vec(math.huge, math.huge, math.huge)
	local maximum = -minimum
	for _, part in ipairs(self:GetDescendants()) do
		if part:IsA("BasePart") then
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local p = orientation:PointToObjectSpace(
							part.CFrame * vec(part.Size.X * x * 0.5, part.Size.Y * y * 0.5, part.Size.Z * z * 0.5)
						)
						minimum = vec(math.min(minimum.X, p.X), math.min(minimum.Y, p.Y), math.min(minimum.Z, p.Z))
						maximum = vec(math.max(maximum.X, p.X), math.max(maximum.Y, p.Y), math.max(maximum.Z, p.Z))
					end
				end
			end
		end
	end
	return orientation * CFrame.new((minimum + maximum) * 0.5), maximum - minimum
end
function methods:ScaleTo(value)
	local factor = value / self:GetScale()
	local pivot = self:GetPivot()
	for _, object in ipairs(self:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Size = object.Size * factor
			object.CFrame = object.CFrame
				+ (pivot.Position + (object.CFrame.Position - pivot.Position) * factor - object.CFrame.Position)
		end
	end
	self.Scale = value
end
local function newPart(parent, position, size, rotation)
	local object = Instance.new("Part", parent)
	object.CFrame = CFrame.new(position) * (rotation or CFrame.new())
	object.Size = size or vec(2, 2, 2)
	object.PivotOffset = CFrame.new()
	object.Locked = false
	return object
end
