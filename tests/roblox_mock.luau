--!strict

-- Minimal Roblox model for exercising the real Explorer initialization/renderer.
-- Does not claim to reproduce Roblox rendering, hit-testing, or font metrics.
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local active = true
		self.handlers[#self.handlers + 1] = function(...)
			if active then
				fn(...)
			end
		end
		return {
			Disconnect = function()
				active = false
			end,
		}
	end
	function s:Fire(...)
		for _, fn in ipairs(self.handlers) do
			fn(...)
		end
	end
	return s
end
local enumMT = {
	__index = function(t, k)
		rawset(t, k, k)
		return k
	end,
}
Enum = setmetatable({}, {
	__index = function(t, k)
		local v = setmetatable({}, enumMT)
		rawset(t, k, v)
		return v
	end,
})
local dimMT = {
	__eq = function(a, b)
		return a.X.Scale == b.X.Scale
			and a.X.Offset == b.X.Offset
			and a.Y.Scale == b.Y.Scale
			and a.Y.Offset == b.Y.Offset
	end,
}
UDim = {
	new = function(s, o)
		return { Scale = s, Offset = o }
	end,
}
UDim2 = {
	new = function(x, xo, y, yo)
		return setmetatable({ X = UDim.new(x, xo), Y = UDim.new(y, yo) }, dimMT)
	end,
}
UDim2.fromOffset = function(x, y)
	return UDim2.new(0, x, 0, y)
end
UDim2.fromScale = function(x, y)
	return UDim2.new(x, 0, y, 0)
end
Vector2 = {
	new = function(x, y)
		return { X = x, Y = y }
	end,
}
Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}
Color3 = {
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
}
Rect = {
	new = function(...)
		return { ... }
	end,
}
NumberSequence = {
	new = function(first, last)
		return { Keypoints = { { Time = 0, Value = first }, { Time = 1, Value = last or first } } }
	end,
}
TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
local methods = {}
local instMT
local function isGui(class)
	return class == "ScrollingFrame"
		or class == "Frame"
		or class == "TextButton"
		or class == "TextLabel"
		or class == "TextBox"
		or class == "ImageLabel"
		or class == "ImageButton"
end
function methods:GetChildren()
	local r = {}
	for _, c in ipairs(self._children) do
		r[#r + 1] = c
	end
	return r
end
function methods:FindFirstChild(n)
	for _, c in ipairs(self._children) do
		if c.Name == n then
			return c
		end
	end
end
function methods:FindFirstChildOfClass(n)
	for _, c in ipairs(self._children) do
		if c.ClassName == n then
			return c
		end
	end
end
function methods:GetFullName()
	local parent = self.Parent
	return parent and parent ~= game and parent:GetFullName() .. "." .. self.Name or self.Name
end
function methods:IsA(c)
	return self.ClassName == c
		or c == "Instance"
		or (c == "GuiObject" and isGui(self.ClassName))
		or (c == "BasePart" and self.ClassName == "Part")
		or (c == "LuaSourceContainer" and (self.ClassName == "LocalScript" or self.ClassName == "ModuleScript" or self.ClassName == "Script"))
end
function methods:GetDescendants()
	local r = {}
	local function visit(n)
		for _, c in ipairs(n._children) do
			r[#r + 1] = c
			visit(c)
		end
	end
	visit(self)
	return r
end
function methods:FindFirstAncestorWhichIsA(c)
	local p = self.Parent
	while p do
		if p:IsA(c) then
			return p
		end
		p = p.Parent
	end
end
function methods:IsDescendantOf(n)
	local p = self.Parent
	while p do
		if p == n then
			return true
		end
		p = p.Parent
	end
	return false
end
function methods:GetPropertyChangedSignal(n)
	self._signals[n] = self._signals[n] or signal()
	return self._signals[n]
end
function methods:SetAttribute(k, v)
	self._props["attr_" .. k] = v
end
function methods:GetAttribute(k)
	return self._props["attr_" .. k]
end
function methods:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end
function methods:Destroy()
	self.Parent = nil
	self.Destroyed = true
end
function methods:CaptureFocus()
	service.UserInputService.Focus = self
	self.Focused:Fire()
end
function methods:ReleaseFocus()
	service.UserInputService.Focus = nil
	self.FocusLost:Fire(false)
end
function methods:Clone()
	local n = Instance.new(self.ClassName)
	for k, v in pairs(self._props) do
		if k ~= "Parent" then
			n[k] = v
		end
	end
	for _, c in ipairs(self._children) do
		c:Clone().Parent = n
	end
	return n
end
local eventNames = {
	Destroying = true,
	MouseWheelForward = true,
	MouseWheelBackward = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton1Click = true,
	MouseButton2Down = true,
	MouseButton2Click = true,
	TouchLongPress = true,
	TouchTap = true,
	Activated = true,
	Focused = true,
	FocusLost = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	ItemChanged = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
}
instMT = {
	__tostring = function(t)
		return t.Name
	end,
	__index = function(t, k)
		if methods[k] then
			return methods[k]
		end
		if eventNames[k] then
			if not t._events[k] then
				t._events[k] = signal()
			end
			return t._events[k]
		end
		if k == "TextBounds" then
			return Vector2.new(#(t._props.Text or "") * 7, t._props.TextSize or 14)
		end
		if k == "AbsoluteSize" or k == "AbsolutePosition" then
			if t.ClassName == "ScreenGui" then
				return k == "AbsoluteSize" and (t._props.ViewportSize or Vector2.new(1100, 800)) or Vector2.new(0, 0)
			end
			local par = t.Parent
			while par and not isGui(par.ClassName) and par.ClassName ~= "ScreenGui" do
				par = par.Parent
			end
			local sz = par and par.AbsoluteSize or Vector2.new(340, 600)
			local dim = t._props[k == "AbsoluteSize" and "Size" or "Position"] or UDim2.fromOffset(0, 0)
			local offset = k == "AbsolutePosition" and par and par.AbsolutePosition or Vector2.new(0, 0)
			return Vector2.new(
				sz.X * dim.X.Scale + dim.X.Offset + offset.X,
				sz.Y * dim.Y.Scale + dim.Y.Offset + offset.Y
			)
		end
		if t._props[k] ~= nil then
			return t._props[k]
		end
		return methods.FindFirstChild(t, k)
	end,
	__newindex = function(t, k, v)
		if k == "Parent" then
			local old = t._props.Parent
			if old then
				local i = table.find(old._children, t)
				if i then
					table.remove(old._children, i)
				end
			end
			if v then
				v._children[#v._children + 1] = t
			end
		end
		t._props[k] = v
	end,
}
Instance = {
	new = function(c, parent)
		local t = setmetatable({
			_props = {
				ClassName = c,
				Name = c,
				ZIndex = 1,
				Visible = true,
				Size = UDim2.fromOffset(0, 0),
				Position = UDim2.fromOffset(0, 0),
				Text = "",
			},
			_children = {},
			_signals = {},
			_events = {},
		}, instMT)
		t.Parent = parent
		return t
	end,
}
function create(data)
	local insts = {}
	for _, v in ipairs(data) do
		insts[v[1]] = Instance.new(v[2])
	end
	for _, v in ipairs(data) do
		for k, val in pairs(v[3]) do
			if k == "Parent" then
				insts[v[1]][k] = insts[val[1]]
			else
				insts[v[1]][k] = val
			end
		end
	end
	return insts[1]
end
function createSimple(c, props)
	local n = Instance.new(c)
	for k, v in pairs(props) do
		n[k] = v
	end
	return n
end
function tick()
	return 0
end
local tasks = {}
task = {
	delay = function(_, fn)
		tasks[#tasks + 1] = fn
	end,
	defer = function(fn)
		tasks[#tasks + 1] = fn
	end,
}
function flushTasks()
	local queue = tasks
	tasks = {}
	for _, fn in ipairs(queue) do
		fn()
	end
end
Settings = {
	Explorer = {
		RowHeight = 22,
		Sorting = true,
		IndentGuides = true,
		AutoUpdateSearch = true,
		PartSelectionBox = false,
		GuiSelectionBox = false,
		ShowNilInstances = true,
		ExpandHierarchy = true,
	},
	Interface = { FocusGameInput = true, FocusIndicator = true },
	ClassIcon = "Old",
	Theme = {},
	Window = {},
}
for _, key in ipairs({
	"Text",
	"Main1",
	"Main2",
	"TextBox",
	"Outline1",
	"Outline2",
	"PlaceholderText",
	"Focus",
	"Button",
	"ButtonHover",
	"ListSelection",
	"SelectionContext",
	"Guide",
	"Menu",
}) do
	Settings.Theme[key] = Color3.fromRGB(50, 50, 50)
end
Settings.Theme.ListSelection = Color3.fromRGB(49, 60, 96)
Settings.Theme.SelectionContext = Color3.fromRGB(47, 49, 61)
local keys = {}
service = {
	TextService = {
		GetTextSize = function(_, s)
			return Vector2.new(#s * 7, 14)
		end,
	},
	UserInputService = {
		TouchLongPress = signal(),
		WindowFocusReleased = signal(),
		InputBegan = signal(),
		InputEnded = signal(),
		InputChanged = signal(),
		TouchEnabled = false,
		IsKeyDown = function(_, k)
			return keys[k]
		end,
		GetFocusedTextBox = function(self)
			return self.Focus
		end,
	},
	CollectionService = {
		HasTag = function()
			return false
		end,
	},
}
service.TweenService = {
	Create = function(_, object, _, properties)
		return {
			Play = function()
				for key, value in pairs(properties) do
					object[key] = value
				end
			end,
			Cancel = function() end,
		}
	end,
}

game = Instance.new("DataModel")
game.Name = "Game"
local workspace = Instance.new("Workspace", game)
workspace.Name = "Workspace"
local folder = Instance.new("Folder", workspace)
folder.Name = "Buildings"
local model = Instance.new("Model", folder)
model.Name = "Cabin"
local part = Instance.new("Part", model)
part.Name = "Front Door"
part.Anchored = true
local second = Instance.new("Part", model)
second.Name = "Back Door"
second.Anchored = false
service.Players = { LocalPlayer = {
	GetMouse = function()
		return Main.Mouse
	end,
} }
Main = {
	Elevated = false,
	Mouse = { X = -100, Y = -100, ViewSizeX = 1100, ViewSizeY = 800 },
	DisplayOrders = { Menu = 10, Core = 1 },
	Alive = true,
	GlobalConnections = {},
	CleanupCallbacks = {},
}
function Main.TrackSignal(sig, callback)
	if not Main.Alive then
		return { Disconnect = function() end }
	end
	local con = sig:Connect(callback)
	Main.GlobalConnections[#Main.GlobalConnections + 1] = con
	return con
end
function Main.AddCleanup(callback)
	if type(callback) == "function" then
		Main.CleanupCallbacks[#Main.CleanupCallbacks + 1] = callback
	end
end
function Main.Shutdown()
	if not Main.Alive then
		return
	end
	Main.Alive = false
	for i = #Main.CleanupCallbacks, 1, -1 do
		pcall(Main.CleanupCallbacks[i])
	end
	table.clear(Main.CleanupCallbacks)
	for i = #Main.GlobalConnections, 1, -1 do
		local con = Main.GlobalConnections[i]
		pcall(function()
			con:Disconnect()
		end)
	end
	table.clear(Main.GlobalConnections)
end
function Main.ExportSettings()
	return "{}"
end
local classes = {}
for _, name in ipairs({ "Workspace", "Folder", "Model", "Part" }) do
	classes[name] =
		{ Name = name, Tags = {}, Properties = { Anchored = { Name = "Anchored", ValueType = { Name = "bool" } } } }
end
API = { Classes = classes }
RMD = { Classes = {} }
Lib = {}
function Lib.CheckMouseInGui(obj)
	return false
end
function Lib.IsShiftDown()
	return keys.LeftShift
end
function Lib.IsCtrlDown()
	return keys.LeftControl
end
function Lib.FastWait() end
function Lib.ShowGui(gui)
	gui.Parent = game
end
function Lib.DeferFunc(fn)
	fn()
end
Lib.Signal = { new = signal }
Lib.IconMap = {
	new = function()
		return { DisplayByKey = function() end, DisplayExplorerIcons = function() end, SetDict = function() end }
	end,
	newLinear = function()
		return {}
	end,
}
Main.MiscIcons = Lib.IconMap.new()
Lib.Set = {
	new = function()
		local s = { List = {}, Map = {}, Changed = signal() }
		function s:SetTable(t)
			self.List = table.clone(t)
			self.Map = {}
			for _, n in ipairs(t) do
				self.Map[n] = true
			end
			self.Changed:Fire()
		end
		function s:Set(n)
			self:SetTable({ n })
		end
		function s:Add(n)
			if not self.Map[n] then
				local t = table.clone(self.List)
				t[#t + 1] = n
				self:SetTable(t)
			end
		end
		function s:Clear()
			self:SetTable({})
		end
		return s
	end,
}
Lib.ClickSystem = {
	new = function()
		return { OnDown = signal(), OnRelease = signal(), ComboTime = 0.5, Add = function() end, Remove = function() end }
	end,
}
Lib.ScrollBar = {
	new = function()
		local s = { Index = 0, VisibleSpace = 0, TotalSpace = 0, Gui = Instance.new("Frame"), Scrolled = signal() }
		function s:Update()
			self.Index = math.clamp(self.Index, 0, math.max(0, self.TotalSpace - self.VisibleSpace))
		end
		function s:SetScrollFrame() end
		return s
	end,
}
Lib.Window = {
	new = function()
		local gui = Instance.new("ScreenGui")
		local main = Instance.new("Frame", gui)
		main.Name = "Main"
		main.Size = UDim2.fromOffset(340, 600)
		local content = Instance.new("Frame", main)
		content.Name = "Content"
		content.Size = UDim2.new(1, 0, 1, -28)
		content.Position = UDim2.fromOffset(0, 28)
		local line = Instance.new("Frame", content)
		local w = {
			Gui = gui,
			GuiElems = { Main = main, Content = content, Line = line },
			OnActivate = signal(),
			OnRestore = signal(),
			OnDeactivate = signal(),
			OnMinimize = signal(),
		}
		function w:SetTitle() end
		function w:IsVisible()
			return true
		end
		return w
	end,
}
Lib.ContextMenu = {
	new = function()
		local m = { Items = {}, Registered = {}, GuiElems = { SearchBar = Instance.new("TextBox") } }
		function m:Register(key, data)
			self.Registered[key] = data
		end
		function m:ApplyTheme() end
		function m:Add(data)
			self.Items[#self.Items + 1] = data
		end
		function m:AddDivider(text)
			self.Items[#self.Items + 1] = { Divider = true, Text = text }
		end
		function m:Clear()
			self.Items = {}
		end
		function m:Show(x, y)
			self.Shown = true
			self.X = x
			self.Y = y
		end
		function m:Hide()
			self.Shown = false
		end
		return m
	end,
}
Apps = {
	Properties = {
		ShowExplorerProps = function() end,
		SelectObject = function()
			return false
		end,
	},
	ScriptViewer = {},
	ModelViewer = {},
}
-- Real Studio primitives and module source are inserted by the runner below.

function Main.GetStudioAsset(key)
	return "mockasset://" .. key
end
function Lib.CreateArrow()
	local f = Instance.new("Frame")
	f.Name = "Arrow"
	return f
end
