from pathlib import Path
import subprocess,json,re,hashlib,struct
root=Path(__file__).resolve().parents[1]
asset_source=(root/'studio_assets.lua').read_text(encoding='utf-8')
for key,record in json.loads((root/'tests/fixtures/asset-manager-assets.json').read_text(encoding='utf-8'))['assets'].items():
    match=re.search(r'\["'+re.escape(key)+r'"\] = "([^"\n]*)"',asset_source)
    assert match,key
    data=bytes(int(n) for n in re.findall(r'\\(\d{3})',match[1]))
    assert hashlib.sha256(data).hexdigest()==record['sha256'],key
    assert list(struct.unpack('>II',data[16:24]))==record['size'],key
import xml.etree.ElementTree as ET
rig_source=(root/'src/Apps/AssetManager/AssetRigData.lua').read_text(encoding='utf-8')
for kind in ['R6','R15']:
    xml = re.search(r'\b' + re.escape(kind) + r'\b\s*=\s*\[(=*)\[(.*?)\]\1\]', rig_source, re.S)[2]
    items=ET.fromstring(xml).findall('.//Item')
    classes=[i.get('class') for i in items]
    assert not any(c in classes for c in ['Script','LocalScript','ModuleScript'])
    assert sum(c in ['Part','MeshPart'] for c in classes)==(7 if kind=='R6' else 16)
    assert classes.count('Motor6D')==(6 if kind=='R6' else 15)
parts=[(root/'tests/roblox_mock.luau').read_text(encoding='utf-8'),r'''local env={} local services={HttpService={}} local modules={}
local nativeTypeof=typeof
local function typeof(value) if type(value)=="table" and rawget(value,"_props") then return "Instance" end return nativeTypeof(value) end
Main.Alive=true
local cleanup={} Main.AddCleanup=function(fn) cleanup[#cleanup+1]=fn end
local deps={Main=Main,Apps=Apps,Lib=Lib,Settings=Settings,env=env,service=services,API={Classes={}}}
''']
for name in ['AssetQuery','AssetCatalog','AssetDownload','AssetRig','AssetPlayback','AssetPreview','AssetRows','AssetManager']:
 source=(root/f'src/Apps/AssetManager/{name}.lua').read_text(encoding='utf-8')
 parts.append('do local control=(function()\n'+source+'\nend)() if control.InitDeps then control.InitDeps(deps) end modules.'+name+'=control.Main() Apps.'+name+'=modules.'+name+' end\n')
parts.append(r'''
local originalIsA=methods.IsA
methods.IsA=function(self,class) return class=="LuaSourceContainer" and (self.ClassName=="Script" or self.ClassName=="LocalScript" or self.ClassName=="ModuleScript") or originalIsA(self,class) end
local loads=0 local fallback=false
function game:GetObjects(uri)
 if fallback and uri:find("rbxasset://avatar",1,true) then error("missing builtin") end
 loads+=1 local rig=Instance.new("Model") Instance.new("Humanoid",rig) Instance.new("Script",rig)
 return {rig}
end
Main.LoadModule=function(name) assert(name=="AssetRigData") return {R15="<roblox/>"} end
env.writefile=function() end env.getcustomasset=function() return "owned://rig" end
local r6=modules.AssetRig.Create("R6") assert(not r6:FindFirstChildOfClass("Script")) r6:Destroy()
modules.AssetRig.Create("R6"):Destroy() assert(loads==1,"cached templates are cloned")
fallback=true modules.AssetRig.Create("R15"):Destroy() assert(loads==2,"missing builtin loads the bundled canonical model")
local function frame(value)
 return setmetatable({Value=value},{__mul=function(a,b) return frame(a.Value+b.Value) end,__index={Inverse=function(self) return frame(-self.Value) end}})
end
services.RunService={RenderStepped=Lib.Signal.new()}
local model=Instance.new("Model") local rootPart=Instance.new("Part",model) rootPart.CFrame=frame(10)
local limb=Instance.new("Part",model) limb.CFrame=frame(0)
local motor=Instance.new("Motor6D",rootPart) motor.Part0=rootPart motor.Part1=limb motor.C0=frame(1) motor.C1=frame(3) motor.Transform=frame(0)
local track={IsPlaying=true,Speed=1,Length=10,TimePosition=0} local stepped=0
local animator={StepAnimations=function(_,dt) stepped+=1 track.TimePosition+=dt motor.Transform=frame(track.TimePosition*2) end}
local playback=modules.AssetPlayback.Start(model,animator,track,function() error("unexpected failure") end)
for _=1,10 do services.RunService.RenderStepped:Fire(.1) end
assert(track.TimePosition>0 and limb.CFrame.Value>8,"stalled tracks advance and apply poses")
local before=stepped track.TimePosition+=.1 services.RunService.RenderStepped:Fire(.1) assert(stepped==before,"native advancement is not double-stepped")
track.Speed=0 services.RunService.RenderStepped:Fire(1) assert(stepped==before,"paused tracks remain paused")
playback:Destroy() services.RunService.RenderStepped:Fire(1) assert(stepped==before)
local denied=0 track.Speed=1 track.TimePosition=0
playback=modules.AssetPlayback.Start(model,{StepAnimations=function() error("denied") end},track,function() denied+=1 end)
for _=1,20 do services.RunService.RenderStepped:Fire(.1) end assert(denied==1,"denied stepping does not retry or flood errors") playback:Destroy()
local catalog=modules.AssetCatalog
assert(select(2,catalog.Normalize("rbxassetid://000123"))=="123")
assert(select(2,catalog.Normalize("https://www.roblox.com/asset/?id=123"))=="123")
assert(not catalog.Normalize("https://evil.example/?id=123") and not catalog.Normalize("0") and not catalog.Normalize("rbxassetid://0"))
assert(catalog.Normalize("rbxasset://textures/a.png"))
local a=Instance.new("Sound",workspace) a.Name="Music" a.SoundId="rbxassetid://123"
local b=Instance.new("Sound",workspace) b.Name="Other" b.SoundId="https://www.roblox.com/asset/?id=123"
local image=Instance.new("ImageLabel",workspace) image.Image="rbxassetid://123"
local mesh=Instance.new("MeshPart",workspace) mesh.MeshId="rbxassetid://456" mesh.TextureID="rbxassetid://789"
local anim=Instance.new("Animation",workspace) anim.AnimationId="rbxassetid://555"
local objects={[a]=true,[b]=true,[image]=true,[mesh]=true,[anim]=true}
local records,stats=catalog.Scan(objects) assert(#records==5 and stats.Objects==5)
local sound for _,record in ipairs(records) do if record.Kind=="Sounds" then sound=record end end
assert(#sound.Uses==2 and sound.Search:find("other",1,true) and sound.Search:find("music",1,true))
assert(catalog.IsCurrent(sound,sound.Uses[1])) sound.Uses[1].Object.SoundId="rbxassetid://999" assert(not catalog.IsCurrent(sound,sound.Uses[1]))
assert(catalog.Scan(objects,function() return false end)==nil)
local live=table.clone(objects)
local snapshotRecords,snapshotStats=catalog.Scan(live,function(count)
 if count==0 then table.clear(live) end
 return true
end)
assert(snapshotStats.Objects==5 and #snapshotRecords>=5,"live registry removals do not interrupt an asset scan")
local download=modules.AssetDownload local calls,writes=0,0 local saved
local png="\137PNG\13\10\26\10data"
services.HttpService.JSONDecode=function(_,body) if body=="packet" then return {locations={{location="https://test.rbxcdn.com/bytes"}}} end error("not json") end
env.request=function(args) calls+=1 assert(args.Headers==nil,"no credentials are forwarded") return {StatusCode=200,Body=calls%2==1 and "packet" or png} end
env.writefile=function(path,body) writes+=1 saved=path assert(body==png) end
local path,size=download.Save({Id="123",Kind="Images"}) assert(calls==2 and writes==1 and path:sub(-4)==".png" and size==#png)
assert(download.Extension("OggSxxx")==".ogg" and download.Extension("version 4.00")==".mesh" and download.Extension("<roblox!data")==".rbxm")
env.request=function() return {StatusCode=403,Body="denied"} end
assert(not pcall(download.Save,{Id="123",Kind="Sounds"}) and writes==1)
env.request=function() return {StatusCode=200,Body="<!doctype html>error"} end
assert(not pcall(download.Save,{Id="123",Kind="Images"}) and writes==1)
services.HttpService.JSONDecode=function() return {locations={{location="https://evil.example/file"}}} end
env.request=function() return {StatusCode=200,Body="packet"} end
assert(not pcall(download.Save,{Id="123",Kind="Images"}) and writes==1)
assert(not pcall(download.Save,{URI="rbxasset://textures/a.png",Kind="Images"}))
-- Owned sound is stopped/destroyed; source sound is not modified.
local viewport=Instance.new("ViewportFrame") local img=Instance.new("ImageLabel")
services.SoundService=Instance.new("Folder")
local originalNew=Instance.new
Instance.new=function(class,parent) local object=originalNew(class,parent)
 if class=="TextButton" then
  local meta=table.clone(getmetatable(object)) local write=meta.__newindex
  meta.__newindex=function(self,key,value) assert(key~="Item","Item is not a Roblox property") return write(self,key,value) end
  setmetatable(object,meta)
 end
 if class=="Sound" then object.Play=function() end object.Stop=function() end object.Pause=function() end object.Resume=function() end end return object end
local player=modules.AssetPreview.Create(viewport,img,function() end)
local oldTask=task task={delay=function() end,spawn=function(fn) fn() end}
player:Show({Kind="Sounds",URI="rbxassetid://123"}) assert(#services.SoundService:GetChildren()==1)
player:SetVolume(.2) player:SetLoop(false) player:SetSpeed(2)
player:Stop() assert(#services.SoundService:GetChildren()==0)

local rig=Instance.new("Model")
local folder=Instance.new("Folder",rig)
local controller=Instance.new("AnimationController",folder)
local animator=Instance.new("Animator",controller)
local rootPart=Instance.new("Part",rig)
function rig:FindFirstChildWhichIsA(class)
 for _,item in ipairs(self:GetDescendants()) do
  if item:IsA(class) then return item end
 end
end
local zero=setmetatable({},{
 __mul=function(value) return value end,
 __add=function(value) return value end,
})
local oldVector3,oldCFrame=Vector3,CFrame
Vector3={new=function() return zero end}
CFrame={lookAt=function() return zero end}
function rig:GetBoundingBox() return {Position=zero} end
Apps.PreviewScene={Build=function()
 return {Model=rig,World=Instance.new("WorldModel"),Radius=1,SetGrid=function() end,Destroy=function() end}
end}
local originalRig=Apps.AssetRig
Apps.AssetRig={Create=function() return Instance.new("Model") end}
local originalPlayback=Apps.AssetPlayback
Apps.AssetPlayback={Start=function() return {Destroy=function() end} end}
local animationTrack={IsPlaying=false,Speed=1,Length=1,TimePosition=0,plays=0}
function animationTrack:Play() self.IsPlaying=true self.plays+=1 end
function animationTrack:Stop() self.IsPlaying=false end
function animationTrack:Destroy() end
function animationTrack:AdjustSpeed(speed) self.Speed=speed end
function animator:LoadAnimation() return animationTrack end
player:Show({Kind="Animations",URI="rbxassetid://456"})
assert(animationTrack.plays==1 and rootPart.Anchored,"controllers nested under a folder can preview")
player:Toggle()
assert(animationTrack.Speed==0)
player:SetSpeed(2)
assert(animationTrack.Speed==0,"changing speed must keep a paused animation paused")
player:Toggle()
assert(animationTrack.Speed==2)
animationTrack.IsPlaying=false
player:Toggle()
assert(animationTrack.plays==2 and animationTrack.Speed==2,"finished animations can play again")
player:Stop()
Apps.AssetRig,Apps.AssetPlayback=originalRig,originalPlayback
Vector3,CFrame=oldVector3,oldCFrame
task=oldTask
-- Construct the real lazy window using an owned preview adapter.
services.UserInputService=service.UserInputService
services.RunService={Heartbeat=Lib.Signal.new()}
Lib.StudioTooltip=function() end
local windowFactory=Lib.Window.new
Lib.Window.new=function()
 local w=windowFactory() w.Resize=function(self,width,height) self.GuiElems.Main.Size=UDim2.fromOffset(width,height) end
 w.Show=function(self) self.Closed=false self.OnActivate:Fire() end
 w.Close=function(self) self.Closed=true self.OnDeactivate:Fire() end
 return w
end
local stopped=0 local shown=0
Apps.AssetPreview={Create=function() return {Stop=function() stopped+=1 end,Show=function() shown+=1 end,Time=function() return 0,0 end} end}
Apps.Explorer={GetNodes=function() return objects end,DisplayClassIcon=function() end,Selection={List={}}}
task={spawn=function(fn) fn() end,wait=function() end}
modules.AssetManager.Open() assert(modules.AssetManager.Window)
local root=modules.AssetManager.Window.GuiElems.Content
local browser=root:FindFirstChild("Browser")
local oldWidth=browser.Size.X.Offset
root:FindFirstChild("Toolbar"):FindFirstChild("ToggleSidebar").Activated:Fire()
assert(not root:FindFirstChild("Sidebar").Visible and browser.Size.X.Offset>oldWidth)
root:FindFirstChild("Toolbar"):FindFirstChild("ToggleSidebar").Activated:Fire()
assert(root:FindFirstChild("Sidebar").Visible and browser.Size.X.Offset==oldWidth)
assert(not root.Inspector.Visible,"empty selection does not reserve a blank inspector column")
local assets=browser:FindFirstChild("Assets")
local rendered=0 local first
for _,child in ipairs(assets:GetChildren()) do
 if child.ClassName=="TextButton" and child.Visible then rendered+=1 first=first or child end
end
assert(rendered==#catalog.Scan(objects),"all scanned assets must produce visible real row bindings")
first.Activated:Fire() assert(shown==1,"asset row activation uses its Lua binding")
modules.AssetManager.Refresh()
assert(shown==1,"refreshing references for the same asset must preserve its running preview")
local inspector=root:FindFirstChild("Inspector") assert(inspector.Visible,"selection opens the inspector")
modules.AssetManager.Window:Resize(400,500) root:GetPropertyChangedSignal("AbsoluteSize"):Fire()
assert(not browser.Visible and inspector.Visible and inspector.Size.X.Offset==384,"narrow selection reserves one full-width inspector")
root.Toolbar.ToggleSidebar.Activated:Fire() assert(browser.Visible and not inspector.Visible,"back returns to browser")
root.Toolbar.ToggleSidebar.Activated:Fire() assert(root.Sidebar.Visible,"narrow sidebar can still be opened")
root.Toolbar.ToggleSidebar.Activated:Fire() assert(not root.Sidebar.Visible)
modules.AssetManager.Window:Resize(1040,620) root:GetPropertyChangedSignal("AbsoluteSize"):Fire()
first.Activated:Fire()

for _,row in ipairs(assets:GetChildren()) do
 if row.ClassName=="TextButton" and row.Visible then
  row.Activated:Fire()
  local name=row.Caption.Text local media=name=="Music" or name=="Other" or name==anim.Name
  assert(inspector.Playback.Visible==media and inspector.Speed.Visible==media)
  if name=="Music" or name=="Other" then assert(inspector.Volume.Visible and not inspector.RigPicker.Visible and not inspector.PreviewStage.Visible)
  elseif name==anim.Name then assert(inspector.RigPicker.Visible and not inspector.Volume.Visible and inspector.PreviewStage.Visible)
  else assert(not inspector.Volume.Visible and not inspector.RigPicker.Visible) end
 end
end
for _,child in ipairs(root:FindFirstChild("Toolbar"):GetChildren()) do if child.ClassName=="TextButton" and child.Name=="ViewMode" then child.Activated:Fire() end end
assert(first.Icon.Size.Y.Offset==96,"grid mode recycles existing rows as tiles")
for _,row in ipairs(assets:GetChildren()) do if row.ClassName=="TextButton" and row.Visible and row.Caption.Text==anim.Name then row.Activated:Fire() break end end
for _,item in ipairs(root.Sidebar:GetChildren()) do if item.ClassName=="TextButton" and item.Text=="Images" then item.Activated:Fire() break end end
assert(not inspector.Playback.Visible and not inspector.RigPicker.Visible,"type filters clear an incompatible media preview")
assert(root.Toolbar.ViewMode.Size.X.Offset==root.Toolbar.ViewMode.Size.Y.Offset,"view button is square")
for _,item in ipairs(root:GetDescendants()) do assert(item.Text~="IN THIS GAME") end
local beforeClose=stopped modules.AssetManager.Hide() assert(stopped==beforeClose+1,"closing stops owned preview")
modules.AssetManager.Open() assert(not modules.AssetManager.Window.Closed)
first.Activated:Fire()
local beforeRestore=shown
modules.AssetManager.Window.OnMinimize:Fire()
modules.AssetManager.Window.OnRestore:Fire()
assert(shown==beforeRestore+1,"restoring a minimized asset manager rebuilds its selected preview")
local jobs={} task.spawn=function(fn) jobs[#jobs+1]=fn end
modules.AssetManager.Refresh()
modules.AssetManager.Hide()
local queued=#jobs
modules.AssetManager.Open()
assert(#jobs>=queued+1,"reopening restarts an interrupted refresh even when old results exist")
for _,job in ipairs(jobs) do job() end
local function entry(id)
 return {Key=id,Id=id,Name=id,URI="rbxassetid://"..id,Kind="Images",Uses={}}
end
local ids={entry("10"),entry("9"),entry("9007199254740993"),entry("9007199254740992")}
local idQuery=modules.AssetQuery.Create()
local sorted=idQuery.Filter(ids,"All","","ID",false)
assert(sorted[1].Id=="9" and sorted[2].Id=="10" and sorted[3].Id=="9007199254740992","IDs sort numerically without rounding large values")
sorted=idQuery.Filter(ids,"All","","ID",true)
assert(sorted[1].Id=="9007199254740993" and sorted[4].Id=="9","descending order uses exact IDs")
task=oldTask
-- Large lists recycle a bounded pool and rebind click targets after scrolling.
local recycled=Instance.new("ScrollingFrame") recycled.Size=UDim2.fromOffset(400,300) recycled.CanvasPosition=Vector2.new(0,0)
local paints=0 local picked local list=modules.AssetRows.Create(recycled,function(item) picked=item end,function(row,item) if item then paints+=1 row.Caption.Text=tostring(item) end end)
local many={} for index=1,10000 do many[index]=index end
list:Set(many) assert(#recycled:GetChildren()<30)
local initialPaints=paints
for y=1,29 do recycled.CanvasPosition=Vector2.new(0,y) recycled:GetPropertyChangedSignal("CanvasPosition"):Fire() end
assert(paints==initialPaints,"pixel scrolling within a row must not repaint or rebind")
list:Paint() assert(paints>initialPaints,"selection repaint remains explicit")
recycled.CanvasPosition=Vector2.new(0,297000) recycled:GetPropertyChangedSignal("CanvasPosition"):Fire()
local firstRow=recycled:GetChildren()[1] firstRow.Activated:Fire() assert(picked==9901)
list:SetGrid(true) assert(#recycled:GetChildren()<30)
list:Set({}) for _,row in ipairs(recycled:GetChildren()) do assert(not row.Visible) end
print("PASS: asset deduplication, shared-object names, reference invalidation, cancellation, download formats/denials/host confinement and preview teardown")
''')
path=root/'.build/asset-manager-spec.luau'
path.write_text('\n'.join(parts),encoding='utf-8')
subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
