--!strict

local originalTypeof = typeof
typeof = function(value)
	return getmetatable(value) == instMT and "Instance" or originalTypeof(value)
end
eventNames.AttributeChanged = true
eventNames.ChildRemoved = true
eventNames.Changed = true
function methods:GetFullName()
	local names = { self.Name }
	local parent = self.Parent
	while parent do
		table.insert(names, 1, parent.Name)
		parent = parent.Parent
	end
	return table.concat(names, ".")
end
-- Bridge legacy explicit property-signal fixtures to Instance.Changed as Roblox does.
local originalPropertySignal = methods.GetPropertyChangedSignal
function methods:GetPropertyChangedSignal(name)
	local result = originalPropertySignal(self, name)
	if not result.ActivityBridge then
		result.ActivityBridge = true
		local originalFire = result.Fire
		local object = self
		result.Fire = function(signal, ...)
			originalFire(signal, ...)
			object.Changed:Fire(name)
		end
	end
	return result
end
function methods:GetAttributes()
	local result = {}
	for key, value in pairs(self._props) do
		if key:sub(1, 5) == "attr_" then
			result[key:sub(6)] = value
		end
	end
	return result
end
API.Classes.Part = {
	Name = "Part",
	Properties = {
		{ Name = "Name" },
		{ Name = "Anchored" },
		{ Name = "Transparency" },
		{ Name = "transparency" },
		{
			Name = "Parent",
		},
	},
}
local object = Instance.new("Part", workspace)
object.Name = "ActivityTarget"
object.Anchored = false
object.Transparency = 0.25
object.transparency = 0.25
object:SetAttribute("Health", 100)
local now = 0
local recording = Apps.ActivitySession.Create({
	Clock = function()
		return now
	end,
	Capacity = 3,
})
recording:Start(object)
assert(recording.ReadableProperties == 3, "readable properties snapshot excludes aliases and Parent")
object.Transparency = 0.5
object:GetPropertyChangedSignal("Transparency"):Fire()
now = 0.02
object.Transparency = 0.75
object:GetPropertyChangedSignal("Transparency"):Fire()
recording:Flush()
local events = recording:Events()
assert(
	#events == 1 and events[1].Before == "0.25" and events[1].After == "0.75" and events[1].Changes == 2,
	"rapid property changes coalesce with correct before and latest after"
)
object.Transparency = 0.8
local restored, reason = Apps.ActivitySession.Restore(events[1])
assert(
	not restored and reason:find("changed again", 1, true) and object.Transparency == 0.8,
	"restore refuses to overwrite a newer value"
)
object.Transparency = 0.75
assert(
	Apps.ActivitySession.Restore(events[1]) and object.Transparency == 0.25,
	"coalesced property restore retains the original typed value"
)
object:SetAttribute("Health", nil)
object.AttributeChanged:Fire("Health")
recording:Flush()
assert(
	recording:Events()[2].Before == "100" and recording:Events()[2].After == "nil",
	"attribute deletion keeps its previous value"
)
assert(
	Apps.ActivitySession.Restore(recording:Events()[2]) and object:GetAttribute("Health") == 100,
	"attribute deletion restores its typed value"
)
local child = Instance.new("Folder", object)
child.Name = "NewChild"
object.ChildAdded:Fire(child)
child.Parent = nil
object.ChildRemoved:Fire(child)
recording:Flush()
events = recording:Events()
assert(
	#events == 3 and recording.Dropped == 1 and events[2].Kind == "Child added" and events[3].Kind == "Child removed",
	"ring order and separate add/remove events survive overflow"
)
recording:Clear()
local destination = Instance.new("Folder", workspace)
destination.Name = "Destination"
child.Parent = object
object.ChildRemoved:Fire(child)
child.Parent = destination
recording:Flush()
local moved = recording:Events()[1]
assert(
	moved.Kind == "Child moved"
		and moved.Before:find("ActivityTarget", 1, true)
		and moved.After:find("Destination", 1, true),
	"child movement reads the settled parent rather than assuming nil"
)
recording:Clear()
child.Parent = object
object.ChildAdded:Fire(child)
recording:Flush()
local incoming = recording:Events()[1]
assert(
	incoming.Kind == "Child added"
		and incoming.BeforeKnown == false
		and incoming.Before ~= "nil"
		and incoming.After:find("ActivityTarget", 1, true),
	"incoming reparent never invents nil as its prior parent"
)
recording:Clear()
child.Parent = object
object.ChildRemoved:Fire(child)
child.Parent = nil
recording:Flush()
assert(
	recording:Events()[1].Kind == "Child removed" and recording:Events()[1].After == "nil",
	"genuine nil parenting is still recorded accurately"
)
recording:Clear()
recording:Pause(true)
object.Transparency = 0.1
object:GetPropertyChangedSignal("Transparency"):Fire()
recording:Flush()
assert(recording.Count == 1 and recording:Events()[1].Kind == "Paused", "paused listeners do not record changes")
recording:Pause(false)
object.Transparency = 0.9
object:GetPropertyChangedSignal("Transparency"):Fire()
recording:Flush()
assert(recording:Events()[3].Before == "0.1", "resume takes a new baseline instead of fabricating missed history")
recording:Clear()
object.Parent = nil
object.AncestryChanged:Fire(object, nil)
recording:Flush()
assert(recording:Events()[1].Kind == "Parent" and recording:Events()[1].After == "nil", "parent change is readable")
object.Destroying:Fire()
assert(not recording.Running and recording:Events()[2].Kind == "Stopped", "destruction stops safely")
recording:Clear()
object.Transparency = 0.4
object:GetPropertyChangedSignal("Transparency"):Fire()
recording:Flush()
assert(recording.Count == 0, "destroying disconnects property listeners")
object.Parent = workspace
local viewer = Apps.ActivityViewer
viewer.Open(object)
child.Parent = object
object.ChildAdded:Fire(child)
service.RunService.Heartbeat:Fire(0.2)
assert(
	viewer.Rows[1].Text.Text:find("added to", 1, true) and not viewer.Rows[1].Text.Text:find("nil", 1, true),
	"incoming child row describes membership instead of a fake nil-to-parent move"
)
viewer.Session:Clear()
object.Anchored = true
object:GetPropertyChangedSignal("Anchored"):Fire()
service.RunService.Heartbeat:Fire(0.2)
assert(
	viewer.Session.Count == 1 and viewer.Rows[1].Text.Text:find("false", 1, true),
	"timeline shows captured property values"
)
viewer.Filter.Text = "missing"
viewer.Filter:GetPropertyChangedSignal("Text"):Fire()
assert(not viewer.Rows[1].Gui.Visible, "filter hides recycled non-matching rows")
viewer.Filter.Text = "Anchored"
viewer.Filter:GetPropertyChangedSignal("Text"):Fire()
assert(viewer.Rows[1].Gui.Visible, "filter matches event names")
local node = { Obj = object }
Apps.Explorer.GetNodes()[object] = node
viewer.Rows[1].Gui.MouseButton1Click:Fire()
assert(Apps.Explorer.LastViewed == object, "event selects its object in Explorer")
local originalMenu = Apps.ContextMenu.new
local openedMenu
Apps.ContextMenu.new = function()
	openedMenu = originalMenu()
	return openedMenu
end
service.UserInputService.GetMouseLocation = function()
	return Vector2.new(20, 20)
end
local copied
activityEnv.setclipboard = function(text)
	copied = text
end
viewer.Rows[1].Gui.MouseButton2Click:Fire()
local previousMenu = openedMenu
viewer.Rows[1].Gui.InputBegan:Fire({UserInputType=Enum.UserInputType.Touch})
viewer.Rows[1].Gui.TouchLongPress:Fire({Vector2.new(22,34)}, Enum.UserInputState.Begin)
assert(openedMenu ~= previousMenu, "holding an activity entry opens its actions")
viewer.Rows[1].Gui.MouseButton1Click:Fire()
local actions = {}
for _, item in ipairs(openedMenu.Items) do
	actions[item.Name] = item
end
assert(
	actions["Watch this object"] and actions["Restore previous value"],
	"event menu exposes object navigation and typed restoration"
)
actions["Copy event"].OnClick()
assert(
	copied:find("Before: false", 1, true) and copied:find("After: true", 1, true),
	"copy exports the captured values"
)
actions["Restore previous value"].OnClick()
assert(
	object.Anchored == false and viewer.Status.Text:find("restored", 1, true),
	"menu restores the selected property and reports the result"
)
Apps.ContextMenu.new = originalMenu
viewer.Window:Close()
local count = viewer.Session.Count
object.Anchored = false
object:GetPropertyChangedSignal("Anchored"):Fire()
service.RunService.Heartbeat:Fire(0.2)
assert(not viewer.Session.Running and viewer.Session.Count == count, "closing stops event capture")
viewer.Open(object)
assert(viewer.Session.Count == 0 and viewer.Session.Running, "new watch clears old history and reconnects")
viewer.Session:Stop()
API.Classes.Part.Properties[#API.Classes.Part.Properties + 1] = { Name = "HiddenValue" }
local hidden = 4
local calls = 0
local oldIndex = instMT.__index
instMT.__index = function(instance, key)
	if instance == object and key == "HiddenValue" then
		error("protected")
	end
	return oldIndex(instance, key)
end
activityEnv.gethiddenproperty = function(instance, key)
	assert(instance == object and key == "HiddenValue")
	calls += 1
	return hidden, true
end
recording:Start(object)
hidden = 9
object:GetPropertyChangedSignal("HiddenValue"):Fire()
recording:Flush()
assert(
	calls >= 2 and recording:Events()[1].Before == "4" and recording:Events()[1].After == "9",
	"optional hidden-property reader supplies baseline and changed values"
)
recording:Stop()
activityEnv.gethiddenproperty = nil
instMT.__index = oldIndex
recording:Start(object)
object:SetAttribute("Toggle", false)
object.AttributeChanged:Fire("Toggle")
recording:Flush()
local toggle = recording:Events()[1]
assert(
	Apps.ActivitySession.Restore(toggle) and object:GetAttribute("Toggle") == nil,
	"restoring an added false attribute removes it rather than losing the boolean"
)
assert(not Apps.ActivitySession.Restore({ Kind = "Child added" }), "membership events cannot be blindly undone")
recording:Stop()
-- Exercise native event contracts through a nested subtree, not just hand-fired
-- per-property signals on the root. Production API superclass links are tables.
local instanceMetadata = { Name = "Instance", Properties = { { Name = "Name" }, { Name = "Parent" } } }
local baseMetadata = {
	Name = "BasePart",
	Superclass = instanceMetadata,
	Properties = {
		{ Name = "Anchored" },
		{ Name = "Transparency" },
	},
}
API.Classes.Part = { Name = "Part", Superclass = baseMetadata, Properties = { { Name = "Source" } } }
API.Classes.Folder = { Name = "Folder", Superclass = instanceMetadata, Properties = {} }
local root = Instance.new("Folder", workspace)
root.Name = "Subtree"
local branch = Instance.new("Folder", root)
branch.Name = "Branch"
local leaf = Instance.new("Part", branch)
leaf.Name = "Leaf"
leaf.Anchored = false
leaf.Transparency = 0.1
local sibling = Instance.new("Part", branch)
sibling.Name = "Sibling"
sibling.Anchored = false
sibling.Transparency = 0.2
leaf:SetAttribute("Enabled", true)
local subtree = Apps.ActivitySession.Create()
subtree:Start(root)
while subtree.PendingObjects > 0 do
	subtree:Step()
end
assert(subtree.WatchedObjects == 4, "existing descendants receive listeners")
leaf.Anchored = true
leaf.Changed:Fire("Anchored")
sibling.Anchored = true
sibling.Changed:Fire("Anchored")
leaf:SetAttribute("Enabled", false)
leaf.AttributeChanged:Fire("Enabled")
leaf:SetAttribute("NewAttribute", 12)
leaf.AttributeChanged:Fire("NewAttribute")
subtree:Flush()
local nested = subtree:Events()
assert(
	#nested == 4 and nested[1].Object[1] == leaf and nested[2].Object[1] == sibling,
	"same-named properties on different descendants remain separate"
)
assert(
	nested[1].Before == "false" and nested[1].After == "true" and nested[1].BeforeKnown,
	"inherited descendant property captures a typed baseline"
)
assert(
	nested[3].Before == "true" and nested[3].After == "false" and nested[4].Before == "nil",
	"descendant attributes include false values and newly created names"
)
assert(nested[1].ObjectPath:find("Branch.Leaf", 1, true), "events retain the changed object's path")
assert(
	Apps.ActivitySession.Restore(nested[3]) and leaf:GetAttribute("Enabled") == true,
	"restoration acts on the event's descendant rather than the watch root"
)
subtree:Clear()
local fresh = Instance.new("Part", branch)
fresh.Name = "NewLeaf"
fresh.Anchored = false
root.DescendantAdded:Fire(fresh)
subtree:Flush()
assert(
	subtree:Events()[1].Kind == "Descendant added" and subtree.WatchedObjects == 5,
	"new nested descendants are attached automatically"
)
fresh.Anchored = true
fresh.Changed:Fire("Anchored")
subtree:Flush()
assert(
	subtree:Events()[2].Kind == "Property" and subtree:Events()[2].Before == "false",
	"new descendants record property changes after setup"
)
subtree:Clear()
root.DescendantRemoving:Fire(fresh)
fresh.Parent = workspace
fresh.AncestryChanged:Fire(fresh, workspace)
subtree:Flush()
assert(
	subtree.WatchedObjects == 4 and #subtree:Events() == 1 and subtree:Events()[1].Kind == "Descendant moved",
	"departing descendants detach without duplicate ancestry noise"
)
fresh.Anchored = false
fresh.Changed:Fire("Anchored")
fresh:SetAttribute("Outside", 1)
fresh.AttributeChanged:Fire("Outside")
subtree:Flush()
assert(#subtree:Events() == 1, "property and attribute listeners stop when a descendant leaves")
fresh.Parent = branch
root.DescendantAdded:Fire(fresh)
subtree:Flush()
fresh.Anchored = true
fresh.Changed:Fire("Anchored")
subtree:Flush()
assert(subtree:Events()[3].Before == "false", "returning descendants take a fresh baseline")
subtree:Clear()
local direct = Instance.new("Folder", root)
direct.Name = "Direct"
root.DescendantAdded:Fire(direct)
root.ChildAdded:Fire(direct)
subtree:Flush()
assert(
	#subtree:Events() == 1 and subtree:Events()[1].Kind == "Child added",
	"native descendant/child addition signals do not duplicate membership rows"
)
subtree:Clear()
root.DescendantRemoving:Fire(direct)
direct.Parent = workspace
root.ChildRemoved:Fire(direct)
subtree:Flush()
assert(
	#subtree:Events() == 1 and subtree:Events()[1].Kind == "Child moved",
	"native descendant/child removal signals do not duplicate membership rows"
)
local oldIsA = methods.IsA
methods.IsA = function(instance, class)
	if instance.ClassName == "StringValue" and class == "ValueBase" then
		return true
	end
	return oldIsA(instance, class)
end
API.Classes.StringValue = { Name = "StringValue", Superclass = instanceMetadata, Properties = { { Name = "Value" } } }
local valueObject = Instance.new("StringValue", branch)
valueObject.Value = "before"
root.DescendantAdded:Fire(valueObject)
subtree:Flush()
subtree:Clear()
valueObject.Value = "after"
valueObject:GetPropertyChangedSignal("Value"):Fire()
valueObject.Name = "RenamedValue"
valueObject:GetPropertyChangedSignal("Name"):Fire()
subtree:Flush()
assert(
	#subtree:Events() == 2 and subtree:Events()[1].Before == '"before"' and subtree:Events()[2].Name == "Name",
	"ValueBase's special Changed signature does not hide Value or Name changes"
)
methods.IsA = oldIsA
subtree:Stop()
-- Starting a large subtree must not install its listeners in one frame.
local large = Instance.new("Folder", workspace)
for index = 1, 120 do
	Instance.new("Folder", large).Name = "Item" .. index
end
local setup = Apps.ActivitySession.Create()
setup:Start(large)
assert(
	setup.WatchedObjects == 1 and setup.PendingObjects == 120,
	"large subtree setup is queued rather than blocking Start"
)
setup:Step()
assert(setup.WatchedObjects <= 25 and setup.PendingObjects >= 96, "setup has a bounded per-frame object budget")
while setup.PendingObjects > 0 do
	setup:Step()
end
assert(setup.WatchedObjects == 121, "bounded setup still covers the complete subtree")
setup:Stop()
local sampleTime = 0
local catchup = Apps.ActivitySession.Create({
	Clock = function()
		return sampleTime
	end,
})
catchup:Start(root)
while catchup.PendingObjects > 0 do
	catchup:Step()
end
leaf.Transparency = 0.8
leaf:SetAttribute("SilentChange", false)
sampleTime = 0.3
catchup:Flush()
local sampled = catchup:Events()
local sawProperty, sawAttribute = false, false
for _, event in ipairs(sampled) do
	if event.Object[1] == leaf and event.Name == "Transparency" and event.Before == "0.1" and event.After == "0.8" then
		sawProperty = true
	end
	if event.Object[1] == leaf and event.Name == "SilentChange" and event.After == "false" then
		sawAttribute = true
	end
end
assert(
	sawProperty and sawAttribute,
	"bounded sampling catches property and attribute writes even without emitted signals"
)
catchup:Stop()
local oldDexCheck = Main.IsDexGuiObject
local own = Instance.new("Folder", root)
own.Name = "Own UI"
local ownChild = Instance.new("Part", own)
Main.IsDexGuiObject = function(object)
	return object == own or object:IsDescendantOf(own)
end
local excluded = Apps.ActivitySession.Create()
excluded:Start(root)
while excluded.PendingObjects > 0 do
	excluded:Step()
end
local beforeExcluded = excluded.Count
ownChild.Changed:Fire("Name")
excluded:Flush()
assert(
	excluded.Count == beforeExcluded and excluded.WatchedObjects == 6,
	"Dex UI subtrees are excluded to avoid redraw feedback"
)
excluded:Stop()
Main.IsDexGuiObject = oldDexCheck
viewer.Open(root)
while viewer.Session.PendingObjects > 0 do
	viewer.Session:Step()
end
leaf.Anchored = false
leaf.Changed:Fire("Anchored")
service.RunService.Heartbeat:Fire(0.2)
assert(
	viewer.Rows[1].Object.Text == "Leaf" and viewer.Status.Text:find("objects", 1, true),
	"timeline identifies the descendant and reports subtree coverage"
)
local content = viewer.Window.GuiElems.Content
local panel = content:FindFirstChild("EventDetails")
assert(
	not panel.Visible and viewer.List.Size.Y.Offset == -76,
	"unselected events do not reserve an empty details block"
)
viewer.Rows[1].Gui.MouseButton1Click:Fire()
assert(panel.Visible and viewer.List.Size.Y.Offset == -170, "selection opens a separate aligned values panel")
leaf.Name = "Leaf.with.dots"
leaf.Anchored = true
leaf.Changed:Fire("Anchored")
service.RunService.Heartbeat:Fire(0.2)
assert(
	viewer.Rows[2].Object.Text == "Leaf.with.dots",
	"object labels preserve literal dots rather than splitting names as paths"
)
local countBeforeAlias = viewer.Session.Count
leaf.Transparency = 0.4
leaf.Changed:Fire("Transparency")
leaf.Changed:Fire("transparency")
service.RunService.Heartbeat:Fire(0.2)
local aliasEvent = viewer.Session:Events()[viewer.Session.Count]
assert(
	viewer.Session.Count == countBeforeAlias + 1 and aliasEvent.Name == "Transparency" and aliasEvent.Changes == 1,
	"property aliases reuse the canonical snapshot without duplicate records"
)
viewer.Window:Close()
print(
	"PASS: activity snapshots, coalescing, attributes, child events, bounded history, pause baseline, destruction, filtering and close cleanup"
)
