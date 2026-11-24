"""Exercise the real splash choreography with an owned GUI and frame clock."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
parser.add_argument('--snapshots', type=Path, help='Write sampled motion values as JSON for a local preview')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
mock = (root / 'tests/roblox_mock.luau').read_text(encoding='utf-8')
source = (root / 'src/Shared/LoadingSplash.lua').read_text(encoding='utf-8')
main_source = (root / 'main.lua').read_text(encoding='utf-8')
program = mock + r'''
do
local ColorSequence = {new=function(value) return {Keypoints=value} end}
local ColorSequenceKeypoint = {new=function(time,value) return {Time=time,Value=value} end}
local NumberSequence = {new=function(value) return {Keypoints=value} end}
local NumberSequenceKeypoint = {new=function(time,value) return {Time=time,Value=value} end}
-- Any hidden wait in Create/SetProgress/Close would fail rather than stall tests.
local task = {wait=function() error("splash must not wait") end,delay=function() error("splash must not schedule a detached timer") end}
local control = (function()
''' + source + r'''
end)()
local function fixture(options)
 options=options or {}
 local callbacks,active,disconnects={},0,0
 local frame={Connect=function(_,fn)
  active+=1
  local item={fn=fn,connected=true}
  callbacks[#callbacks+1]=item
  return {Disconnect=function()
   if item.connected then item.connected=false active-=1 disconnects+=1 end
  end}
 end}
 local owned,cleanup
 local main={Alive=true,DisplayOrders={Menu=10},
  GetStudioAsset=function(key)
   assert(key=="branding/dex/toolbar-white-v1")
   if not options.noAsset then return "owned://dex-logo" end
  end,
  SecureGui=function(gui) owned=gui end,
  AddCleanup=function(fn) assert(not cleanup,"one cleanup owner") cleanup=fn end}
 local settings={Theme={
  Brand=Color3.fromRGB(60,100,250),Focus=Color3.fromRGB(51,95,255),
  SelectedText=Color3.fromRGB(238,239,241),Text=Color3.fromRGB(213,215,221),
  Menu=Color3.fromRGB(25,27,31),Outline2=Color3.fromRGB(55,55,55),
  PlaceholderText=Color3.fromRGB(187,188,190)}}
 if control.InitDeps then control.InitDeps({Main=main,Settings=settings,service=options.noFrames and {} or {RunService={RenderStepped=frame}},createSimple=createSimple}) end
 local api=control.Main()
 local splash=api.Create("Loading src/Shared/Lib.lua")
 local function step(dt)
  for _,item in ipairs(table.clone(callbacks)) do if item.connected then item.fn(dt) end end
 end
 local function advance(seconds)
  local remaining=seconds
  while remaining>1e-8 do local dt=math.min(.05,remaining) step(dt) remaining-=dt end
 end
 return {splash=splash,main=main,gui=owned,card=owned.Status,step=step,advance=advance,
  cleanup=function() cleanup() end,active=function() return active end,disconnects=function() return disconnects end}
end

-- Preview sampling reads production-calculated values; no extra production API.
local function jsonValue(value)
 if type(value)=="string" then return string.format("%q",value) end
 if type(value)=="boolean" or type(value)=="number" then return tostring(value) end
 local entries={}
 for key,item in pairs(value) do entries[#entries+1]=string.format("%q",key)..":"..jsonValue(item) end
 table.sort(entries)
 return "{"..table.concat(entries,",").."}"
end
local sample=fixture()
local function layout(object)
 local result={ClassName=object.ClassName,Name=object.Name,Children={}}
 for _,key in ipairs({"Size","Position","AnchorPoint","BackgroundColor3","BackgroundTransparency","Text","TextSize","TextColor3","TextScaled","TextXAlignment","Font","Image","ImageTransparency","ScaleType","MinTextSize","MaxTextSize","CornerRadius","Color","Transparency","Thickness","Rotation","MaxSize","AspectRatio"}) do
  local value=object._props[key]
  if value~=nil then result[key]=value end
 end
 for index,child in ipairs(object:GetChildren()) do result.Children[index]=layout(child) end
 return result
end
local function snapshot(time,closing)
 local card=sample.card
 local title=card.TitleMask.Title
 local subtitle=card.SubtitleMask.Subtitle
 local mark=card.Brand
 local image=mark.Reveal.Logo
 local stroke=card:FindFirstChildOfClass("UIStroke")
 local data={time=time,closing=closing,closed=sample.gui.Destroyed==true,
  panelAlpha=card.BackgroundTransparency,titleAlpha=title.TextTransparency,
  subtitleAlpha=subtitle.TextTransparency,
  reveal=mark.Reveal.Size.X.Scale,logoAlpha=image.ImageTransparency,
  slabAlpha=card.Slab.BackgroundTransparency,
  strokeAlpha=stroke.Transparency,
  statusAlpha=card.Message.TextTransparency,
  percentAlpha=card.Percent.TextTransparency,progressScale=card.Progress.Size.X.Scale,
  progressOffset=card.Progress.Size.X.Offset,progressAlpha=card.Progress.BackgroundTransparency,
  fillAlpha=card.Progress.Fill.BackgroundTransparency,shown=card.Progress.Fill.Size.X.Scale,
  message=card.Message.Text,percent=card.Percent.Text}
 if time==0 then data.layout=layout(card) end
 print("SNAPSHOT\t"..jsonValue(data))
end
for frame=0,96 do
 if frame>0 then sample.step(1/30) end
 if frame==9 then sample.splash.SetProgress("Downloading ReflectionMetadata.xml",.35) end
 if frame==24 then sample.splash.SetProgress("Reading ReflectionMetadata.xml",.55) end
 if frame==36 then sample.splash.SetProgress("Loading src/Apps/Explorer/Explorer.lua",.75) end
 if frame==60 then sample.splash.SetProgress("Initializing src/Apps/Properties/Properties.lua",.91) end
 if frame==78 then sample.splash.SetProgress("Ready",1) sample.splash.Close() end
 snapshot(frame/30,frame>=78)
end

-- Validate opacity and fixed geometry at different frame rates.
for _,fps in ipairs({30,60,144}) do
 local motion=fixture()
 for _=1,fps do
  motion.step(1/fps)
  for _,alpha in ipairs({motion.card.BackgroundTransparency,motion.card.TitleMask.Title.TextTransparency,motion.card.Brand.Reveal.Logo.ImageTransparency,motion.card.Slab.BackgroundTransparency}) do
   assert(alpha==alpha and alpha>=0 and alpha<=1,"motion opacity remains finite and bounded")
  end
 end
 local position=motion.card.Brand.Position
 assert(position==UDim2.fromScale(.77,.405) and motion.card.BackgroundTransparency==0,"entrance settles identically at different frame rates")
 motion.cleanup()
end

local a=fixture()
local card=a.card
assert(a.active()==1 and not a.gui.Destroyed,"Create returns before its entrance finishes and owns one frame connection")
assert(card.AnchorPoint.X==.5 and card.AnchorPoint.Y==.5 and card.Position==UDim2.fromScale(.5,.5),"splash starts centered")
local constraint=card:FindFirstChildOfClass("UISizeConstraint")
assert(constraint.MaxSize.X==488 and constraint.MaxSize.Y==280,"compact original-sized splash")
assert(card.BackgroundTransparency==1 and card.TitleMask.Title.TextTransparency==1 and card.Brand.Reveal.Logo.ImageTransparency==1,"the whole composition is initially hidden")
assert(card:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio==488/280,"native layout preserves the card proportions on small screens")
assert(card:FindFirstChildOfClass("UICorner").CornerRadius.Offset==4,"small reference corners")
assert(not card:FindFirstChildOfClass("UIGradient") and not card:FindFirstChild("Activity"),"only the static diagonal has a background treatment")
assert(not card.Brand:FindFirstChild("Corner1"),"logo has no corner brackets")
assert(not card.Brand.Reveal.Logo:FindFirstChildOfClass("UIGradient") and not card.Progress.Fill:FindFirstChild("Sheen"),"logo and progress have no shimmer effects")
local titlePosition=card.TitleMask.Position
local logoPosition=card.Brand.Position
a.step(.05)
local firstAlpha=card.BackgroundTransparency
assert(firstAlpha>0 and firstAlpha<1 and card.TitleMask.Title.TextTransparency>firstAlpha,"background fades in just before the content")
a.advance(.2)
assert(card.BackgroundTransparency<firstAlpha and card.TitleMask.Title.TextTransparency<1,"card and content progressively fade in")
assert(card.TitleMask.Position==titlePosition and card.Brand.Position==logoPosition,"fade does not shift or resize the layout")
for _,object in ipairs(card:GetDescendants()) do
 if object.ClassName=="Frame" then assert((object.Rotation or 0)==0,"native masks cannot depend on rotated clipping being enabled") end
end
a.advance(.55)
assert(card.TitleMask.Title.TextTransparency==0 and card.BackgroundTransparency==0,"entrance settles the card and title")
assert(card.Brand.Reveal.Size.X.Scale==1 and card.Brand.Reveal.Logo.ImageTransparency==0,"existing Dex mark finishes revealing")
assert(card.Progress.Size.X.Scale==.9 and card.Message.TextTransparency==0,"status and track are fully visible")
a.advance(.4)
assert(card.TitleMask.Position==titlePosition and card.Brand.Position==logoPosition and card.Slab.BackgroundTransparency==0,"settled background and logo stay still")

a.splash.SetProgress("Loading src/Apps/Explorer/Explorer.lua",.75)
assert(card.Message.Text=="Loading src/Apps/Explorer/Explorer.lua" and card.Percent.Text=="75%","actual module and percentage update immediately")
for index=1,40 do a.splash.SetProgress("Loading src/Shared/Module"..index..".lua") end
assert(card.Message.TextTransparency==0 and card.Message.Text=="Loading src/Shared/Module40.lua","rapid status changes stay readable without restarting the fade")
assert(card.Progress.Fill.Size.X.Scale<.75,"bar does not jump to its target")
a.step(.05)
local partial=card.Progress.Fill.Size.X.Scale
assert(partial>0 and partial<.75,"bar smoothly approaches progress")
a.splash.SetProgress(nil,.2)
a.splash.SetProgress(nil,0/0)
a.splash.SetProgress(nil,math.huge)
a.splash.SetProgress(nil,-math.huge)
assert(card.Percent.Text=="75%","older and non-finite values do not replace progress")
a.advance(1)
assert(card.Progress.Fill.Size.X.Scale==.75,"bar settles at the actual target")
a.splash.SetProgress("Ready",2)
assert(card.Percent.Text=="100%","progress is clamped")
a.splash.Close() a.splash.Close()
a.splash.SetProgress("Late message",0)
assert(card.Message.Text=="Ready","late updates are ignored while closing")
a.step(.1)
assert(not a.gui.Destroyed and a.active()==1,"exit runs asynchronously")
assert(card.TitleMask.Title.TextTransparency>0 and card.Progress.BackgroundTransparency>0 and card.BackgroundTransparency>0,"exit fades the whole composition")
assert(card.Position==UDim2.fromScale(.5,.5) and card.Brand.Position==logoPosition,"fade out keeps the card centered and geometry fixed")
a.step(.1)
assert(not a.gui.Destroyed,"exit remains until its 0.22-second duration")
a.step(.03)
assert(a.gui.Destroyed and a.active()==0 and a.disconnects()==1,"exit destroys GUI and disconnects its frame listener")
a.splash.Close() a.cleanup() a.splash.SetProgress("Too late",0)
assert(a.disconnects()==1 and card.Message.Text=="Ready","repeated close/cleanup is safe")

for _,duringExit in ipairs({false,true}) do
 local b=fixture()
 b.step(.05)
 if duringExit then b.splash.Close() b.step(.05) end
 b.main.Alive=false b.cleanup()
 assert(b.gui.Destroyed and b.active()==0 and b.disconnects()==1,"shutdown immediately stops entrance or exit")
 b.step(.1) b.cleanup() b.splash.Close()
 assert(b.disconnects()==1,"shutdown leaves no live callbacks")
end
for _,closeAt in ipairs({0,.02,.1,.2,.5}) do
 local early=fixture()
 early.advance(closeAt)
 local opacity=early.card.TitleMask.Title.TextTransparency
 local background=early.card.BackgroundTransparency
 early.splash.Close()
 for _=1,15 do
  early.step(.016)
  assert(early.card.TitleMask.Title.TextTransparency>=opacity and early.card.BackgroundTransparency>=background,"closing during the entrance never flashes brighter")
  opacity=early.card.TitleMask.Title.TextTransparency
  background=early.card.BackgroundTransparency
 end
 assert(early.gui.Destroyed and early.active()==0,"fast startup does not delay closing or leave an invisible GUI alive")
end
local invalid=fixture()
for _,dt in ipairs({0,-1,0/0,math.huge,-math.huge}) do invalid.step(dt) end
assert(invalid.card.BackgroundTransparency==1,"invalid frame times cannot corrupt the fade")
invalid.cleanup()

for _,width in ipairs({240,320,375,488}) do
 local height=width*280/488
 local messageRight=(card.Message.Position.X.Scale+card.Message.Size.X.Scale)*width
 local percentLeft=card.Percent.Position.X.Scale*width
 assert(percentLeft-messageRight>=7,"module path and percentage never overlap at small widths")
 assert((card.Progress.Position.Y.Scale*height)+card.Progress.Size.Y.Offset<height,"progress stays inside the card")
 assert((card.TitleMask.Position.X.Scale+card.TitleMask.Size.X.Scale)*width<(card.Brand.Position.X.Scale-card.Brand.Size.X.Scale*.5)*width,"title and logo keep separate bounds on narrow screens")
end
local c=fixture()
c.main.Alive=false c.step(.016)
assert(c.gui.Destroyed and c.active()==0,"frame guard stops work if the owner dies")

local d=fixture({noAsset=true,noFrames=true})
assert(d.active()==0 and d.card.Brand.Reveal.LogoFallback and not d.card.Brand.Reveal:FindFirstChild("Logo"),"missing assets use the text mark")
assert(d.card.TitleMask.Title.TextTransparency==0 and d.card.Brand.Reveal.Size.X.Scale==1,"missing RunService falls back to a visible static splash")
d.splash.SetProgress("Ready",1)
assert(d.card.Progress.Fill.Size.X.Scale==1 and d.card.Percent.Text=="100%","static fallback still reports real progress")
d.splash.Close() d.splash.Close() d.cleanup()
assert(d.gui.Destroyed,"static fallback closes immediately")
print("PASS: splash layout, staged fades, readable dynamic status, frame-rate bounds, smooth progress, early close, fallback and teardown")
end
'''
metadata_start = main_source.index('\t\tintro.SetProgress("Loading API-Dump.json", 0.35)')
metadata_end = main_source.index('\n\t\tfinishPhase("metadata")', metadata_start)
program += r'''
do
local function scenario(reverse,fail)
 local reports,jobs={},{}
 local Main,API,RMD={}
 local function load(name,onProgress)
  onProgress("Downloading "..name)
  coroutine.yield()
  if fail==name then error("metadata download failed") end
  onProgress("Reading "..name)
  return {Name=name}
 end
 Main.FetchAPI=function(_,_,_,onProgress) return load("API-Dump.json",onProgress) end
 Main.FetchRMD=function(onProgress) return load("ReflectionMetadata.xml",onProgress) end
 local task={spawn=function(fn)
  local co=coroutine.create(fn)
  jobs[#jobs+1]=co
  assert(coroutine.resume(co))
 end,wait=function()
  local index=reverse and #jobs or 1
  local co=table.remove(jobs,index)
  assert(co and coroutine.resume(co),"pending metadata jobs can finish in either order")
 end}
 local intro={SetProgress=function(message,progress)
  reports[#reports+1]={message=message,progress=progress}
 end}
''' + main_source[metadata_start:metadata_end] + r'''
 assert(completed==2 and API.Name=="API-Dump.json" and RMD.Name=="ReflectionMetadata.xml","both metadata resources finish")
 local expected=reverse and "API-Dump.json" or "ReflectionMetadata.xml"
 local halfway
 for _,report in ipairs(reports) do
  if report.progress==.55 then
   assert(report.message and report.message:find(expected,1,true),"every partial-completion status identifies the pending file")
   halfway=report.message
  end
 end
 assert(halfway,"completion never hides the other pending file")
end
scenario(false)
scenario(true)
for _,name in ipairs({"API-Dump.json","ReflectionMetadata.xml"}) do
 local ok,problem=pcall(scenario,false,name)
 assert(not ok and tostring(problem):find(name,1,true),"download errors retain the failing resource")
end
print("PASS: startup status follows pending downloads in either completion order and preserves resource errors")
end
'''
with tempfile.TemporaryDirectory(prefix='dex-loading-splash-') as directory:
    path = Path(directory) / 'test.luau'
    path.write_text(program, encoding='utf-8')
    try:
        result = subprocess.run([args.luau, str(path)], check=True, capture_output=True, text=True)
        snapshots = []
        for line in result.stdout.splitlines():
            if line.startswith('SNAPSHOT\t'):
                snapshots.append(json.loads(line.split('\t', 1)[1]))
            else:
                print(line)
        if args.snapshots:
            args.snapshots.parent.mkdir(parents=True, exist_ok=True)
            args.snapshots.write_text(json.dumps(snapshots, indent=2), encoding='utf-8')
            print(f'Motion samples written to {args.snapshots}')
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, end='')
        if error.stderr:
            print(error.stderr, end='')
        saved = root / '.build/loading_splash_failed.luau'
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_text(program, encoding='utf-8')
        print(f'Failed fixture saved to {saved}', flush=True)
        raise
