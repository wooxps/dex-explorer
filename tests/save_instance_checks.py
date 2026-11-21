from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[1]
parts=[(root/'tests/roblox_mock.luau').read_text(encoding='utf-8')]
parts.append(r'''local nativeTypeof=typeof
local function typeof(value) if type(value)=="table" and rawget(value,"_props") then return "Instance" end return nativeTypeof(value) end
local cleanup={} Main.AddCleanup=function(fn) cleanup[#cleanup+1]=fn end
Main.Alive=true game.PlaceId=123
local env={loadstring=loadstring}
local deps={Main=Main,Lib=Lib,Apps=Apps,Settings=Settings,env=env,service={HttpService={}}}
local modules={}
Main.LoadModule=function(name) return assert(modules[name],name) end
''')
for name in ['SaveOptions','SaveConfiguration','SaveBackend','SaveInstance']:
 source=(root/f'src/Apps/SaveInstance/{name}.lua').read_text(encoding='utf-8')
 parts.append('do local control=(function()\n'+source+'\nend)() control.InitDeps(deps) modules.'+name+'=control.Main() end\n')
parts.append(r'''
local schema=modules.SaveOptions assert(#schema==50)
local config=modules.SaveConfiguration
local selected=Instance.new("Folder",workspace)
local values=config.Build({Binary=false,CompressionLevel="22",DecompileTimeout="-1",Object="selection[1]",IgnoreList='{CoreGui=false, "Chat"}',Callback="function(data) return data end",CompressionMode="false",FilePath="plain_name"},{selected})
assert(values.Binary==false and values.CompressionLevel==22 and values.Object==selected and values.CompressionMode==false and values.IgnoreList.CoreGui==false and type(values.Callback)=="function" and values.FilePath==nil)
assert(next(config.Build({},{}))==nil,"unset options preserve upstream defaults")
for _,raw in ipairs({{CompressionLevel="23"},{CompressionLevel="1.5"},{DecompileTimeout="-2"},{BytecodeTimeout="no"},{Object="123"},{IgnoreList="true"},{Callback="nil"},{Object="selection["}}) do assert(not pcall(config.Build,raw,{}),"bad option must fail before saving") end
local downloads,compiles,calls=0,0,0 local received
local originalHttp=game.HttpGet
game.HttpGet=function(_,url)
    downloads+=1
    assert(url=="https://raw.githubusercontent.com/rbxlx/UniversalSynSaveInstance/main/saveinstance.luau")
    return "owned fixture"
end
env.loadstring=function(source,name) compiles+=1 return function() return function(options) calls+=1 received=options return "ok" end end end
local backend=modules.SaveBackend
local options={Binary=false,Decompile=false}
assert(backend.Run("Universal",selected,"test",options)=="ok")
assert(received.Object==selected and received.FilePath=="test" and received.Binary==false and options.Object==nil,"provider gets detached options")
backend.Run("Universal",nil,nil,{}) assert(downloads==1 and compiles==1 and received.Object==nil,"USSI loads once and preserves whole-place default mode")
assert(not pcall(backend.Run,"Executor",game,"test",{}))
env.executorSaveInstance=function(object,path,args) assert(object==selected and path=="native" and args.RemovePlayerCharacters==true and args.IgnoreDefaultProps==false) return "native" end
assert(backend.Run("Executor",selected,"native",{SavePlayerCharacters=false,IgnoreDefaultProperties=false})=="native")
-- Real save-window composition and Boolean overrides.
local oldWindow=Lib.Window.new
Lib.Window.new=function() local w=oldWindow() w.Resize=function() end return w end
Lib.StudioTooltip=function() end
Apps.ContextMenu=Lib.ContextMenu
Apps.Explorer={Selection={List={}}}
env.loadstring=loadstring
for _,color in pairs(Settings.Theme) do if type(color)=="table" then color.Lerp=function(self) return self end end end
local save=modules.SaveInstance save.Init()
assert(save.Engine=="Universal" and not save.Busy)
local list=save.Window.GuiElems.Content:FindFirstChild("Options") assert(list)
local binary=list:FindFirstChild("Binary") assert(binary)
local toggle
for _,child in ipairs(binary:GetChildren()) do if child.ClassName=="TextButton" and child:GetAttribute("Checked")~=nil then toggle=child end end
assert(toggle:GetAttribute("Checked")==true) toggle.Activated:Fire() assert(toggle:GetAttribute("Checked")==false) toggle.Activated:Fire() assert(toggle:GetAttribute("Checked")==true)
assert(toggle:FindFirstChildOfClass("ImageLabel").Image:find("prop/checkbox_on",1,true))
local details=binary:FindFirstChild("Details")
assert(not details.Visible) toggle.MouseEnter:Fire() toggle.MouseLeave:Fire() assert(toggle.BackgroundTransparency==0) binary:FindFirstChild("OptionDetails").Activated:Fire() assert(details.Visible and binary.Size.Y.Offset==112) details:FindFirstChild("ResetOption").Activated:Fire() assert(toggle:GetAttribute("Checked")==true)
local fields=0 for _,child in ipairs(list:GetChildren()) do if child.ClassName=="Frame" then fields+=1 end end
local labels={} for _,field in ipairs(schema) do assert(not labels[field.Key]) labels[field.Key]=true end
assert(fields==49,"every upstream option has a control, plus the separate filename field")
local nested=false
modules.SaveBackend={Run=function() local ok=pcall(save.Export,nil,"again",{}) nested=not ok error("fixture failed") end}
assert(not pcall(save.Export,nil,"test",{}) and nested and not save.Busy,"errors release busy state; nested saves are rejected")
game.HttpGet=originalHttp
print("PASS: all 50 USSI options, typed expressions, invalid input, lazy pin/cache, provider dispatch, UI toggles and save-error recovery")
''')
path=root/'.build/save-instance-spec.luau'
path.write_text('\n'.join(parts),encoding='utf-8')
subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
