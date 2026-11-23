--!strict

-- Calculated GUI layout double: tests geometry/UDim math, not engine rendering.
local actualTypeof = typeof
typeof = function(o)
	return type(o) == "table" and o._props and "Instance" or actualTypeof(o)
end
local originalIsa = methods.IsA
function methods:IsA(class)
	if class == "LayerCollector" then
		return self.ClassName == "ScreenGui" or self.ClassName == "BillboardGui" or self.ClassName == "SurfaceGui"
	end
	return originalIsa(self, class)
end
local function rot(x, y, degrees)
	local a = math.rad(degrees)
	return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
end
local function ownScale(o)
	local v = 1
	for _, c in ipairs(o:GetChildren()) do
		if c.ClassName == "UIScale" then
			v *= c.Scale
		end
	end
	return v
end
local function totalScale(o)
	local v = 1
	local p = o
	while p and p.ClassName ~= "ScreenGui" do
		v *= ownScale(p)
		p = p.Parent
	end
	return v
end
local function layout(o)
	if o.ClassName == "ScreenGui" then
		return o._props.RootPosition or Vector2.new(0, 0), o._props.ViewportSize or Vector2.new(1100, 800), 0
	end
	local parent = o.Parent
	while parent and parent.ClassName == "Folder" do
		parent = parent.Parent
	end
	if not parent then
		return Vector2.new(0, 0), Vector2.new(0, 0), 0
	end
	local p, s, a = layout(parent)
	local size = o.Size
	local position = o.Position
	local anchor = o.AnchorPoint or Vector2.new(0, 0)
	local ps = totalScale(parent)
	local os = ownScale(o)
	local w, h = (size.X.Scale * s.X + size.X.Offset * ps) * os, (size.Y.Scale * s.Y + size.Y.Offset * ps) * os
	local cx = p.X + position.X.Scale * s.X + position.X.Offset * ps + (0.5 - anchor.X) * w
	local cy = p.Y + position.Y.Scale * s.Y + position.Y.Offset * ps + (0.5 - anchor.Y) * h
	local x, y = rot(cx - (p.X + s.X * 0.5), cy - (p.Y + s.Y * 0.5), a)
	cx, cy = p.X + s.X * 0.5 + x, p.Y + s.Y * 0.5 + y
	return Vector2.new(cx - w * 0.5, cy - h * 0.5), Vector2.new(w, h), a + (o.Rotation or 0)
end
local originalIndex = instMT.__index
instMT.__index = function(o, k)
	if k == "ChildRemoved" then
		o._events[k] = o._events[k] or signal()
		return o._events[k]
	end
	if k == "AbsolutePosition" or k == "AbsoluteSize" or k == "AbsoluteRotation" then
		local p, s, r = layout(o)
		return k == "AbsolutePosition" and p or k == "AbsoluteSize" and s or r
	end
	return originalIndex(o, k)
end
local function newGui(parent, pos, size, anchor, rotation)
	local o = Instance.new("Frame", parent)
	o.Position = pos or UDim2.fromOffset(0, 0)
	o.Size = size or UDim2.fromOffset(100, 50)
	o.AnchorPoint = anchor or Vector2.new(0, 0)
	o.Rotation = rotation or 0
	o.Visible = true
	o.AutomaticSize = Enum.AutomaticSize.None
	return o
end
Rect = {
	new = function(...)
		return { ... }
	end,
}
service.Workspace = { CurrentCamera = { ViewportSize = Vector2.new(1100, 800) } }
workspace = service.Workspace
service.RunService = { RenderStepped = signal() }
service.GuiService = {
	GetGuiInset = function()
		return Vector2.new(0, 36)
	end,
}
local rawPointer = Vector2.new(1, 1)
function service.UserInputService:GetMouseLocation()
	return rawPointer
end
service.UserInputService.MouseIconEnabled = true
service.UserInputService.WindowFocusReleased = signal()
local actions = {}
service.ContextActionService = {
	BindActionAtPriority = function(_, name, fn)
		actions[name] = fn
	end,
	UnbindAction = function(_, name)
		actions[name] = nil
	end,
}
Lib.StudioFont = Enum.Font.BuilderSans
Lib.StudioTooltip = function() end
Main.GetStudioAsset = function(key)
	return key
end
Main.GameInputLocked = false
Main.SetGameInputLocked = function(v)
	Main.GameInputLocked = v
end
Main.IsDexGuiObject = function(o)
	local p = o
	while p do
		if Main.FocusIgnoredGuis and Main.FocusIgnoredGuis[p] then
			return true
		end
		p = p.Parent
	end
	return false
end
Main.IsPointInDexUI = function(x)
	return x > 1000
end
Apps.Explorer = {
	Selection = Lib.Set.new(),
	CaptureHistorySelection = function()
		return {}
	end,
	RestoreHistorySelection = function() end,
	UpdateSelectionVisuals = function() end,
}
Apps.Properties = { Refresh = function() end }
Apps.TransformGizmo = {
	Create = function()
		return {
			Hide = function() end,
			Destroy = function() end,
			HitTest = function()
				return nil
			end,
		}
	end,
}
