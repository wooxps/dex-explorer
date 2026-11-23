from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'main.lua').read_text()
code=(root/'tests/roblox_mock.luau').read_text()+r'''
Main.InternalGuis={} Main.FocusIgnoredGuis={}
local cleanups={}
Main.AddCleanup=function(fn) cleanups[#cleanups+1]=fn end
Main.TrackSignal=function(event,fn) return event:Connect(fn) end
Main.FocusOwnerForObject=function(object) return object end
local gui=Instance.new("ScreenGui",game) gui.Enabled=true
Main.InternalGuis[gui]=true
local button=Instance.new("TextButton",gui)
button.Position=UDim2.fromOffset(100,100) button.Size=UDim2.fromOffset(40,40)
local hidden=Instance.new("Frame",gui) hidden.Visible=false
local child=Instance.new("TextButton",hidden) child.Size=UDim2.fromOffset(100,100)
local calls=0 local getDescendants=methods.GetDescendants
methods.GetDescendants=function(self) calls+=1 return getDescendants(self) end
'''+source[source.index('\tMain.IsDexGuiObject ='):source.index('\n\tlocal function unbindGameInputLock')]+r'''
assert(Main.IsPointInDexUI(110,110))
local baseline=calls
for i=1,1000 do assert(not Main.IsPointInDexUI(500,500)) end
assert(calls==baseline,"stable pointer checks never allocate another descendant snapshot")
assert(not Main.IsPointInDexUI(10,10),"hidden ancestors cannot claim focus")
button.Visible=false assert(not Main.IsPointInDexUI(110,110),"visibility remains live without rebuilding the snapshot")
button.Visible=true Main.FocusIgnoredGuis[gui]=true assert(not Main.IsPointInDexUI(110,110)) Main.FocusIgnoredGuis[gui]=nil
local added=Instance.new("TextButton",gui) added.Position=UDim2.fromOffset(200,200) added.Size=UDim2.fromOffset(40,40)
gui.DescendantAdded:Fire(added)
assert(Main.IsPointInDexUI(210,210) and calls==baseline+1,"new widgets invalidate exactly one snapshot")
gui.DescendantRemoving:Fire(added) added:Destroy()
assert(not Main.IsPointInDexUI(210,210) and calls==baseline+2,"removed widgets cannot leave stale hit targets")
local detached=Instance.new("Folder",game) button.Parent=detached
assert(not Main.IsPointInDexUI(110,110),"live ownership checks reject reparented widgets before deferred events")
local clip=Instance.new("Frame",gui) clip.Position=UDim2.fromOffset(300,300) clip.Size=UDim2.fromOffset(20,20)
clip.BackgroundTransparency=1 clip.BorderSizePixel=0 clip.ClipsDescendants=false
local overflow=Instance.new("TextButton",clip) overflow.Position=UDim2.fromOffset(40,0) overflow.Size=UDim2.fromOffset(20,20)
gui.DescendantAdded:Fire(clip)
assert(Main.IsPointInDexUI(345,305),"menus outside non-clipping containers remain hittable")
clip.ClipsDescendants=true
assert(not Main.IsPointInDexUI(345,305),"clipped descendants cannot claim pointer focus outside their viewport")
clip.ClipsDescendants=false clip.Visible=false
assert(not Main.IsPointInDexUI(345,305),"whole hidden branches are excluded")
clip.Visible=true assert(Main.IsPointInDexUI(345,305),"showing a window takes effect without rebuilding its topology")
local savedCoreGui=service.CoreGui
service.CoreGui={GetGuiObjectsAtPosition=function() return {overflow} end}
assert(Main.IsPointInDexUI(345,305),"native GUI hits remain supported")
gui.Parent=nil
assert(not Main.IsPointInDexUI(345,305),"closed windows cannot reject gameplay clicks through either native hits or cached rectangles")
gui.Parent=game
assert(Main.IsPointInDexUI(345,305),"reopening the same window restores hit testing immediately")
gui.Enabled=false
assert(not Main.IsPointInDexUI(345,305),"disabled roots cannot claim native hits")
gui.Enabled=true clip.Visible=false
assert(not Main.IsPointInDexUI(345,305),"native hits under hidden ancestors cannot claim focus")
clip.Visible=true
service.CoreGui=savedCoreGui
for _,cleanup in cleanups do cleanup() end
print("PASS: pointer broad phase, stable widget snapshots, visibility, ignored roots, insertion/removal and live ownership")
'''
code+=source[source.index('\tMain.TrackSignal ='):source.index('\n\tMain.AddCleanup =')]+r'''
Main.Alive=true Main.GlobalConnections={} Main.ConnectionSweepAt=nil
local event={Connect=function() local c={Connected=true} function c:Disconnect() self.Connected=false end return c end}
local persistent=Main.TrackSignal(event,function() end)
for i=1,2000 do local gesture=Main.TrackSignal(event,function() end) gesture:Disconnect() end
assert(#Main.GlobalConnections<256 and persistent.Connected,"completed gestures do not grow the cleanup registry indefinitely or discard active subscriptions")
local found=false for _,c in Main.GlobalConnections do if c==persistent then found=true end end assert(found)
print("PASS: gesture listener compaction retains active subscriptions and bounds disconnected records")
'''
lib=(root/'src/Shared/Lib.lua').read_text()
code+='\nlocal inputService={GetMouseLocation=function() return Vector2.new(412,366) end}\nlocal mouse={X=412,Y=308}\nlocal resizeCursorImage=Instance.new("ImageLabel") resizeCursorImage.Visible=true\n'+lib[lib.index('\t\tlocal function currentMousePosition('):lib.index('\n\t\tlocal function ensureResizeCursorGui(')]+lib[lib.index('\t\tlocal function moveResizeCursor('):lib.index('\n\t\tstatic.SetTextCursor =')]+r'''
moveResizeCursor(Vector2.new(412,308))
assert(resizeCursorImage.Position==UDim2.fromOffset(412,366),"cursor overlay uses absolute pointer coordinates rather than inset-relative hover input")
print("PASS: resize cursor remains aligned across a 58px client inset")
'''
with tempfile.TemporaryDirectory() as temp:
    path=Path(temp)/'hit.luau';path.write_text(code)
    subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
