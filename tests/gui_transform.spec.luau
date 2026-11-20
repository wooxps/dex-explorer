--!strict

local S = Apps.GuiTransformSession
local screen = Instance.new("ScreenGui", game)
screen.Enabled = true
screen.RootPosition = Vector2.new(0, 0)
local parent = newGui(screen, UDim2.fromOffset(100, 100), UDim2.fromOffset(500, 400))
local child = newGui(parent, UDim2.new(0.2, 10, 0.25, 20), UDim2.new(0.2, 0, 0.25, 0), Vector2.new(0.25, 0.75), 30)
local nested = newGui(child)
assert(#S.Collect({ child, nested, child }) == 1, "GUI root collection deduplicates descendants")
assert(#S.Collect({ parent, child }) == 1, "selected parent suppresses nested double transforms")
local other = Instance.new("SurfaceGui", game)
local spatial = newGui(other)
assert(#S.Collect({ spatial }) == 0, "world-space GUI is not incorrectly treated as screen coordinates")
local before = child.Position
do
	local roots = { child, nested, newGui(screen, UDim2.fromOffset(-21, 460), UDim2.fromOffset(79, 42), nil, -118) }
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, object in roots do
		local g = S.Geometry(object)
		for i, direction in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local x, y = rot(direction[1] * g.Size.X * 0.5, direction[2] * g.Size.Y * 0.5, g.Rotation)
			local corner = Vector2.new(g.Center.X + x, g.Center.Y + y)
			assert(g.Corners[i].X == corner.X and g.Corners[i].Y == corner.Y)
			minX, minY = math.min(minX, corner.X), math.min(minY, corner.Y)
			maxX, maxY = math.max(maxX, corner.X), math.max(maxY, corner.Y)
		end
	end
	local bounds = S.Bounds(roots)
	assert(bounds.Corners[1].X == minX and bounds.Corners[1].Y == minY)
	assert(bounds.Corners[3].X == maxX and bounds.Corners[3].Y == maxY)
	roots[3]:Destroy()
end
local g = S.Geometry(child)
local session = assert(S.Begin({ child }, "Move"))
assert(session:Move(20, -10))
assert(session:Move(30, -15))
assert(
	child.Position.X.Scale == 0.2
		and child.Position.Y.Scale == 0.25
		and child.Position.X.Offset == 40
		and child.Position.Y.Offset == 5,
	"drag previews preserve Scale values and use immutable initial offsets"
)
local count = #Apps.History.Entries
assert(session:Commit())
assert(#Apps.History.Entries == count + 1, "entire GUI gesture produces one history entry")
assert(Apps.History.Undo() and child.Position == before, "GUI history restores Position")
assert(Apps.History.Redo() and child.Position.X.Offset == 40, "GUI history redo restores final Position")
Apps.History.Undo()
session = assert(S.Begin({ child }, "Move"))
session:Move(40, 30)
session:Cancel()
assert(child.Position == before, "Escape restoration uses the original snapshot")
-- The opposite corner remains fixed when resizing a rotated, noncentral anchor.
local old = S.Geometry(child)
local left = old.Corners[1]
session = assert(S.Begin({ child }, "Scale"))
local dx, dy = rot(40, 20, old.Rotation)
assert(session:Resize(1, 1, dx, dy, false, false))
g = S.Geometry(child)
assert(
	math.abs(g.Corners[1].X - left.X) < 1e-6 and math.abs(g.Corners[1].Y - left.Y) < 1e-6,
	"rotated resize fixes the opposite corner with arbitrary AnchorPoint"
)
assert(
	math.abs(g.Size.X - old.Size.X - 40) < 1e-6 and math.abs(g.Size.Y - old.Size.Y - 20) < 1e-6,
	"resize uses object-local axes"
)
session:Cancel()
local pure = newGui(parent, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.2, 0.25))
session = assert(S.Begin({ pure }, "Move"))
session:Move(50, 40)
assert(
	math.abs(pure.Position.X.Scale - 0.6) < 1e-6
		and pure.Position.X.Offset == 0
		and math.abs(pure.Position.Y.Scale - 0.6) < 1e-6,
	"pure Scale positions remain relative instead of gaining pixel offsets"
)
session:Cancel()
session = assert(S.Begin({ pure }, "Scale"))
session:Resize(1, 1, 50, 40, false, false)
assert(
	math.abs(pure.Size.X.Scale - 0.3) < 1e-6 and pure.Size.X.Offset == 0 and math.abs(pure.Size.Y.Scale - 0.35) < 1e-6,
	"pure Scale sizes retain responsive units during resize"
)
session:Cancel()
pure:Destroy()
session = assert(S.Begin({ child }, "Scale"))
session:Resize(1, 1, 80, 20, false, true)
g = S.Geometry(child)
assert(math.abs(g.Size.X / g.Size.Y - old.Size.X / old.Size.Y) < 1e-6, "Shift preserves aspect ratio")
session:Cancel()
session = assert(S.Begin({ child }, "Scale"))
session:Resize(-1, -1, 10000, 10000, false, false)
g = S.Geometry(child)
assert(g.Size.X >= 1 and g.Size.Y >= 1, "resize cannot cross zero size")
session:Cancel()
-- Parent rotation and cumulative UIScale are inverted when converting screen deltas.
parent.Rotation = 90
local zoom = Instance.new("UIScale", parent)
zoom.Scale = 2
local selfZoom = Instance.new("UIScale", child)
selfZoom.Scale = 0.5
local initial = S.Geometry(child)
session = assert(S.Begin({ child }, "Move"))
session:Move(40, 0)
g = S.Geometry(child)
assert(
	math.abs(g.Center.X - initial.Center.X - 40) < 1e-6 and math.abs(g.Center.Y - initial.Center.Y) < 1e-6,
	"screen movement accounts for rotated scaled parent"
)
session:Cancel()
initial = S.Geometry(child)
left = initial.Corners[1]
session = assert(S.Begin({ child }, "Scale"))
dx, dy = rot(30, 20, initial.Rotation)
session:Resize(1, 1, dx, dy, false, false)
g = S.Geometry(child)
assert(
	math.abs(g.Size.X - initial.Size.X - 30) < 1e-6
		and math.abs(g.Corners[1].X - left.X) < 1e-6
		and math.abs(g.Corners[1].Y - left.Y) < 1e-6,
	"resize handles parent rotation plus own/ancestor UIScale without moving opposite corner"
)
session:Cancel()
parent.Rotation = 0
zoom:Destroy()
selfZoom:Destroy()
session = assert(S.Begin({ child }, "Rotate"))
session:Rotate(-390)
assert(child.Rotation == 0, "signed rotation wraps the actual GUI Rotation")
session:Cancel()
local grid = Instance.new("UIListLayout", parent)
assert(
	not S.CanEdit(child, "Move") and not S.CanEdit(child, "Scale") and S.CanEdit(child, "Rotate"),
	"layout-managed position/size are guarded without blocking rotation"
)
grid:Destroy()
child.AutomaticSize = Enum.AutomaticSize.X
assert(
	not S.Begin({ child }, "Scale") and S.Begin({ child }, "Move"),
	"automatic sizing disables resize but permits movement"
)
child.AutomaticSize = Enum.AutomaticSize.None
local constraint = Instance.new("UIAspectRatioConstraint", child)
assert(not S.Begin({ child }, "Scale"), "aspect constraints are not silently overwritten")
constraint:Destroy()
session = assert(S.Begin({ child }, "Move"))
session:Move(30, 30)
child.Parent = screen
assert(
	not session:Move(40, 40) and child.Position == before,
	"reparent during gesture rolls back rather than writing invalid coordinates"
)
child.Parent = parent
local secondGui = newGui(parent, UDim2.fromOffset(300, 200))
assert(not S.Begin({ child, secondGui }, "Rotate"), "GUI rotation follows Studio's single-selection rule")
print(
	"PASS: GUI immutable previews, UDim preservation, rotated anchors, UIScale, layout guards, cancellation, one-entry undo/redo and reparent rollback"
)

-- Actual view/controller interactions, using source-derived 8px and 20px handles.
local actualToolbar = Apps.TransformTools
Apps.TransformTools = {
	Tool = "Select",
	Enabled = true,
	Snapping = false,
	RotateSnap = 15,
	IsToolbarPoint = function()
		return false
	end,
}
local tools = Apps.GuiTransformTools
tools.Init()
Apps.Explorer.Selection:SetTable({ { Obj = child } })
local view = tools.View
local hitChecks = 0
local originalBlock = Main.IsPointInDexUI
Main.IsPointInDexUI = function(...)
	hitChecks += 1
	return originalBlock(...)
end
service.RunService.RenderStepped:Fire()
local idleChecks = hitChecks
for _ = 1, 120 do
	service.RunService.RenderStepped:Fire()
end
assert(hitChecks == idleChecks, "stationary UI selection does not repeat Dex window hit-testing every frame")
Main.IsPointInDexUI = originalBlock
assert(
	tools.IsActive() and view.Visible and #view.Handles == 16,
	"selecting ScreenGui content activates 8 resize and 8 outer rotate targets"
)
assert(
	view.Handles[1].Frame.Size == UDim2.fromOffset(8, 8)
		and view.Handles[1].Frame.Shadow.Image == "native/gui-editor/resizeHandleDropShadow",
	"resize adornment uses installed Studio geometry and original image"
)
assert(
	view.Handles[2].Frame.Size == UDim2.fromOffset(20, 20),
	"outside rotation has the source-sized invisible pick target"
)
local function event(p, kind)
	return { Position = { X = p.X, Y = p.Y }, UserInputType = kind or Enum.UserInputType.MouseButton1 }
end
local origin = S.Geometry(child).Center
view.Body.InputBegan:Fire(event(origin))
assert(
	tools.Dragging and Apps.TransformTools.GuiDragging and Main.GameInputLocked,
	"GUI capture blocks gameplay and signals shared toolbar/history"
)
service.UserInputService.InputChanged:Fire(event(Vector2.new(origin.X + 2, origin.Y), Enum.UserInputType.MouseMovement))
service.RunService.RenderStepped:Fire()
assert(child.Position == before, "click tolerance prevents accidental GUI movement")
service.UserInputService.InputChanged:Fire(
	event(Vector2.new(origin.X + 27, origin.Y + 11), Enum.UserInputType.MouseMovement)
)
service.RunService.RenderStepped:Fire()
assert(child.Position ~= before, "actual overlay gesture moves the selected element")
local previousHistory = Apps.History.Index
service.UserInputService.InputEnded:Fire(event(Vector2.new(origin.X + 27, origin.Y + 11)))
assert(
	not tools.Dragging and not Apps.TransformTools.GuiDragging and Apps.History.Index == previousHistory + 1,
	"release ends GUI capture and commits one history entry"
)
Apps.History.Undo()
Apps.Explorer.Selection.Changed:Fire()
local handle = view.Handles[1]
local hp = handle.Position
assert(view:HitTest(hp).Kind == "Resize", "resize squares win over outer rotation regions")
handle.Frame.InputBegan:Fire(event(hp))
service.UserInputService.InputChanged:Fire(event(Vector2.new(hp.X + 40, hp.Y), Enum.UserInputType.MouseMovement))
service.RunService.RenderStepped:Fire()
service.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Escape })
assert(not tools.Dragging and child.Size == UDim2.new(0.2, 0, 0.25, 0), "Escape cancels real overlay resizing")
local rotateHandle = view.Handles[2]
local rp = rotateHandle.Position
rotateHandle.Frame.InputBegan:Fire(event(rp))
assert(tools.Dragging, "invisible outside rotation grab starts the correct GUI gesture")
local center = S.Geometry(child).Center
local x, y = rot(rp.X - center.X, rp.Y - center.Y, 45)
service.UserInputService.InputChanged:Fire(
	event(Vector2.new(center.X + x, center.Y + y), Enum.UserInputType.MouseMovement)
)
service.RunService.RenderStepped:Fire()
assert(child.Rotation == 75, "GUI rotation is measured around its visual center")
service.UserInputService.WindowFocusReleased:Fire()
assert(child.Rotation == 30 and not tools.Dragging, "losing focus cancels rotation and restores cursor/input")
local align = newGui(screen, UDim2.fromOffset(100, 100), UDim2.fromOffset(100, 100))
local target = newGui(screen, UDim2.fromOffset(300, 100), UDim2.fromOffset(100, 100))
Apps.Explorer.Selection:SetTable({ { Obj = align } })
local start = S.Geometry(align).Center
view.Body.InputBegan:Fire(event(start))
service.UserInputService.InputChanged:Fire(event(Vector2.new(start.X + 99, start.Y), Enum.UserInputType.MouseMovement))
service.RunService.RenderStepped:Fire()
assert(
	align.Position.X.Offset == 200 and view.Guides[1].Visible,
	"five-pixel sibling snapping displays the native-colored alignment guide"
)
tools.Cancel()
tools.Snapping = false
keys.LeftShift = true
view.Body.InputBegan:Fire(event(start))
service.UserInputService.InputChanged:Fire(
	event(Vector2.new(start.X + 21, start.Y + 10), Enum.UserInputType.MouseMovement)
)
service.RunService.RenderStepped:Fire()
assert(
	align.Position.X.Offset == 121 and align.Position.Y.Offset == 100,
	"Shift locks GUI movement to the dominant axis"
)
tools.Cancel()
keys.LeftShift = false
local previous = align.Position
view.Body.InputBegan:Fire(event(start))
local touch = { UserInputType = Enum.UserInputType.Touch, Position = { X = start.X, Y = start.Y } }
tools.Cancel()
view.Body.InputBegan:Fire(touch)
touch.Position = { X = start.X + 30, Y = start.Y + 20 }
service.UserInputService.InputChanged:Fire(touch)
service.RunService.RenderStepped:Fire()
assert(align.Position ~= previous, "same overlay supports touch gestures")
service.UserInputService.InputEnded:Fire(touch)
assert(not tools.Dragging, "matching touch release commits and releases capture")
-- Exercise live Ctrl/Shift changes with the pointer held still. The session
-- already supports centered resize; the controller must actually pass both keys.
tools.Snapping = false
local initial = S.Geometry(align)
local resize = view.Handles[1]
local resizeStart = resize.Position
resize.Frame.InputBegan:Fire(event(resizeStart))
service.UserInputService.InputChanged:Fire(
	event(Vector2.new(resizeStart.X + 20, resizeStart.Y), Enum.UserInputType.MouseMovement)
)
service.RunService.RenderStepped:Fire()
assert(
	math.abs(S.Geometry(align).Center.X - initial.Center.X - 10) < 1e-6,
	"ordinary side resize fixes the opposite edge"
)
keys.LeftControl = true
service.RunService.RenderStepped:Fire()
assert(
	math.abs(S.Geometry(align).Center.X - initial.Center.X) < 1e-6
		and math.abs(S.Geometry(align).Size.X - initial.Size.X - 40) < 1e-6,
	"Ctrl immediately switches an active gesture to centered resize without another pointer event"
)
keys.LeftShift = true
service.RunService.RenderStepped:Fire()
local both = S.Geometry(align)
assert(
	math.abs(both.Size.X / both.Size.Y - initial.Size.X / initial.Size.Y) < 1e-6
		and math.abs(both.Center.Y - initial.Center.Y) < 1e-6,
	"Ctrl+Shift preserves center and aspect together"
)
keys.LeftControl = false
keys.LeftShift = false
service.RunService.RenderStepped:Fire()
assert(
	math.abs(S.Geometry(align).Size.X - initial.Size.X - 20) < 1e-6,
	"releasing modifiers returns to original drag geometry without compounding previews"
)
tools.Cancel()
-- Odd-sized nested UI can require a half-pixel position to center exactly.
local centerScreen = Instance.new("ScreenGui", game)
centerScreen.Enabled = true
local nestedParent = newGui(centerScreen, UDim2.fromOffset(50, 40), UDim2.fromOffset(400, 300))
local odd = newGui(nestedParent, UDim2.fromOffset(40, 30), UDim2.fromOffset(101, 51))
Apps.Explorer.Selection:SetTable({ { Obj = odd } })
tools.Snapping = true
start = S.Geometry(odd).Center
view.Body.InputBegan:Fire(event(start))
service.UserInputService.InputChanged:Fire(event(Vector2.new(548, 398), Enum.UserInputType.MouseMovement))
service.RunService.RenderStepped:Fire()
local centered = S.Geometry(odd)
assert(
	math.abs(centered.Center.X - 550) < 1e-6 and math.abs(centered.Center.Y - 400) < 1e-6,
	"nested odd-sized selection snaps exactly to both screen center axes: "
		.. centered.Center.X
		.. ","
		.. centered.Center.Y
)
local centerX, centerY = false, false
for _, guide in ipairs(view.Guides) do
	if guide.Visible and guide.BackgroundColor3.G == 1 and guide.BackgroundColor3.R == 0 then
		if guide.Size.X.Offset == 1 and guide.Position.X.Offset == 550 then
			centerX = true
		end
		if guide.Size.Y.Offset == 1 and guide.Position.Y.Offset == 400 then
			centerY = true
		end
	end
end
assert(centerX and centerY, "actual GUI controller displays both green screen-center indicators")
tools.Cancel()
Apps.Explorer.Selection:SetTable({ { Obj = align } })
Apps.TransformTools = actualToolbar
actualToolbar.Init()
assert(
	actualToolbar.Toolbar.Visible and actualToolbar.Toolbar.Space.Text == "UI",
	"actual shared toolbar is visible for GUI-only selection"
)
assert(
	actualToolbar.Toolbar.Snapping.MoveSnapUnit.Text == "px" and actualToolbar.Toolbar.Snapping.RotateSnap.Text == "1",
	"UI toolbar shows pixels and native one-degree rotation increments"
)
actualToolbar.SetTool("Rotate")
assert(
	tools.Tool == "Rotate" and actualToolbar.Tool == "Rotate",
	"shared toolbar dispatches tool changes to the GUI controller"
)
local uiSnap = tools.Snapping
actualToolbar.Toolbar.Snap.MouseButton1Click:Fire()
assert(tools.Snapping ~= uiSnap, "UI snap control updates GUI snapping independently of world snapping")
start = S.Geometry(align).Center
view.Body.InputBegan:Fire(event(start))
assert(actualToolbar.GuiDragging and not actualToolbar.Dragging, "GUI gesture integrates with shared transform state")
actualToolbar.SetTool("Move")
assert(actualToolbar.Tool == "Rotate", "tool changes do not cancel an active GUI gesture")
actualToolbar.Cancel()
assert(not tools.Dragging, "shared cancel dispatches to the GUI session")
actualToolbar.SetEnabled(false)
assert(not view.Visible and not actualToolbar.Toolbar.Visible, "shared toggle hides both GUI overlay and toolbar")
actualToolbar.SetEnabled(true)
assert(view.Visible and actualToolbar.Toolbar.Visible, "shared toggle restores GUI editing")
Main.Shutdown()
assert(next(actions) == nil, "reload/shutdown releases GUI action and render connections")
print(
	"PASS: actual GUI overlay input, move/resize/rotate, source handle/assets, drag threshold, release history, Escape, focus cancellation and shutdown"
)
