from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
source=(root/'src/Shared/EditorWorkspace.lua').read_text(encoding='utf-8')
program='local control=(function()\n'+source+'\nend)()\n'+r'''
local cleanup,timers={},{} local disk={} local encoded local writes=0
game={PlaceId=123}
task={delay=function(_,fn) timers[#timers+1]=fn end}
local deps={Main={AddCleanup=function(fn) cleanup[#cleanup+1]=fn end},env={
 writefile=function(path,json) disk[path]=json writes+=1 end,
 readfile=function(path) return assert(disk[path]) end},service={HttpService={
 JSONEncode=function(_,data) encoded=data return "snapshot" end,
 JSONDecode=function() return encoded end}}}
if control.InitDeps then control.InitDeps(deps) end local workspace=control.Main()
local viewer={Documents={{title="Unsaved",text="return 42",x=3,y=7,vx=2,vy=5,dirty=true}}}
viewer.ActiveDocument=viewer.Documents[1]
workspace.Attach(viewer,function() if viewer.ScheduleWorkspaceSave then viewer.ScheduleWorkspaceSave() end end)
viewer.ScheduleWorkspaceSave() viewer.ScheduleWorkspaceSave() assert(#timers==1)
table.remove(timers,1)() assert(writes==1 and #timers==0,"saving must not reschedule itself")
assert(encoded.Documents[1].Text=="return 42" and encoded.Active==1)
local restored={Documents={}}
restored.OpenDocument=function(id,title,text,object,state)
 local doc={title=title,text=text,x=state.x,y=state.y,vx=state.vx,vy=state.vy,dirty=state.dirty}
 restored.Documents[#restored.Documents+1]=doc return doc
end
restored.SelectDocument=function(doc) restored.ActiveDocument=doc end
workspace.Attach(restored,function() end)
assert(restored.ActiveDocument.text=="return 42" and restored.ActiveDocument.y==7 and restored.ActiveDocument.vy==5 and restored.ActiveDocument.dirty)
viewer.ScheduleWorkspaceSave() cleanup[1]() local before=writes table.remove(timers,1)() assert(writes==before,"teardown cancels pending writes")
print("PASS: per-place workspace, unsaved buffers, cursor/scroll, debounce and teardown")
'''
path=root/'.build/workspace-spec.luau'
path.write_text(program,encoding='utf-8')
subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
