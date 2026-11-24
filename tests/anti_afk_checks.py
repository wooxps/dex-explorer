"""Check the actual anti-idle module without emitting real input."""
import argparse
from pathlib import Path
import subprocess
import tempfile
parser=argparse.ArgumentParser()
parser.add_argument('--luau',default='luau')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
source=(root/'src/Shared/AntiAFK.lua').read_text(encoding='utf-8')
fixture=r"""
local callbacks,cleanup={},{}
local active,clicks,created,destroyed,warnings,saves,refreshes=0,0,0,0,0,0,0
local reject=false
local Settings={Interface={AntiAFK=false}}
local Main={Alive=true,AddCleanup=function(fn) table.insert(cleanup,fn) end,
 SaveSettings=function() saves+=1 end,RefreshSettings=function() refreshes+=1 end}
local event={Connect=function(_,fn)
 table.insert(callbacks,fn) active+=1
 local connected=true
 return {Disconnect=function() if connected then connected=false active-=1 end end}
end}
local service={}
local game={}
local unavailable=false
local Instance={new=function(class)
 assert(class=='VirtualInputManager')
 if unavailable then error('input unavailable') end
 created+=1
 local pressed=false
 return {SendMouseButtonEvent=function(_,x,y,button,down,target,extra)
  if reject then error('input denied') end
  assert(x==0 and y==0 and button==0 and target==game and extra==0)
  assert(down~=pressed,'mouse press and release stay paired') pressed=down
  if not down then clicks+=1 end
 end,Destroy=function() assert(not pressed) destroyed+=1 end}
end}
local warn=function() warnings+=1 end
local function fire() for _,fn in ipairs(table.clone(callbacks)) do fn() end end
local control=(function()
"""+source+r"""
end)()
if control.InitDeps then control.InitDeps({Main=Main,Settings=Settings,service=service,plr={Idled=event}}) end
local anti=control.Main()
assert(#cleanup==1 and active==0,'disabled feature has no idle connection')
assert(anti.SetEnabled(false) and clicks==0 and active==0)
assert(anti.SetEnabled(true) and active==1 and Settings.Interface.AntiAFK)
assert(clicks==0 and created==0,'enabling does not create virtual input or synthesize input')
fire() assert(clicks==1 and created==1 and destroyed==1,'idle creates input, presses/releases and destroys it')
anti.SetEnabled(true) assert(active==1,'repeated enable replaces rather than duplicates the subscription')
fire() assert(clicks==2,'callbacks from the old generation cannot send input')
anti.SetEnabled(false) fire() assert(active==0 and clicks==2 and not Settings.Interface.AntiAFK)
anti.SetEnabled(true) reject=true fire()
assert(active==0 and not Settings.Interface.AntiAFK and warnings==1 and saves==1 and refreshes==1,'failed input disables, persists and refreshes the toggle')
fire() assert(warnings==1,'failed feature does not spam errors')
reject=false
unavailable=true
assert(anti.SetEnabled(true) and active==1,'virtual input availability is checked lazily')
fire()
assert(active==0 and not Settings.Interface.AntiAFK and warnings==2 and saves==2 and refreshes==2,'creation failure disables and persists the toggle')
unavailable=false
assert(anti.SetEnabled(true))
Main.Alive=false cleanup[1]() fire()
assert(active==0 and clicks==2 and Settings.Interface.AntiAFK,'teardown stops input but preserves the saved preference')
assert(not anti.SetEnabled(true) and active==0,'cannot restart a closed Dex session')
print('PASS: anti-AFK toggle, idle input, duplicate/stale callbacks, permission failure and shutdown')
"""
with tempfile.TemporaryDirectory(prefix='dex-anti-afk-') as directory:
 path=Path(directory)/'test.luau'
 path.write_text(fixture,encoding='utf-8')
 subprocess.run([args.luau,str(path)],check=True)
