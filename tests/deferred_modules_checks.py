from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'main.lua').read_text(encoding='utf-8')
a=s.index('\tlocal moduleAppTable');b=s.index('\tMain.LoadModules = function()',a)
code='local Main={AppControls={}} local loads,after=0,0 local api={Value=42,Run=function() return 7 end}\n'+s[a:b]+r'''
moduleAppTable={Explorer={}}
Main.LoadModule=function(name) loads+=1 Main.AppControls[name]={InitAfterMain=function(deps) assert(deps==moduleAppTable) after+=1 end} return api end
local deferred=Main.DeferModule("Tool") assert(loads==0)
assert(deferred.Value==42 and deferred.Run()==7 and loads==1 and after==1)
deferred.Value=9 assert(api.Value==9 and loads==1)
local second=Main.DeferModule("Other") second.Value=10 assert(loads==2 and after==2 and api.Value==10)
Main.LoadModule=function(name) Main.AppControls[name]={} return api end
assert(Main.DeferModule("NoHooks").Value==10)
local attempts=0 Main.LoadModule=function() attempts+=1 error("fixture failure") end
local broken=Main.DeferModule("Broken") assert(not pcall(function() return broken.Run end)) assert(not pcall(function() return broken.Run end)) assert(attempts==1)
print("PASS: deferred modules initialize once on demand, preserve API reads/writes and retain failures")
'''
start=s.index('\tMain.LoadModules = function()');end=s.index('\n\tMain.InitEnv = function()',start)
code+='\nlocal Apps={}\nMain.AppControls.Lib={InitAfterMain=function() end}\nMain.ModuleList={"Explorer","Properties","ScriptViewer","Console","SaveInstance","ModelViewer","EditorDocument","EditorBuffer","CodeViewport","StudioEditorSkin","PreviewCamera","ReferenceScan","ActivitySession"}\nMain.Error=error\nMain.LoadModule=function(name) local result={Name=name,Run=function() return name end} Apps[name]=result Main.AppControls[name]={InitAfterMain=function() end} return result end\n'+s[start:end]+r'''
Main.LoadModules()
assert(Main.AppControls.Explorer and Main.AppControls.Properties,"required panels load at startup")
assert(not Main.AppControls.EditorDocument and not Main.AppControls.EditorBuffer and not Main.AppControls.CodeViewport,"editor dependencies stay dormant until used")
assert(Apps.EditorDocument.Run()=="EditorDocument" and Main.AppControls.EditorDocument,"first editor use initializes through the actual module loader")
assert(not Main.AppControls.PreviewCamera and not Main.AppControls.ReferenceScan and not Main.AppControls.ActivitySession,"unused tool services remain deferred")
print("PASS: production module policy defers editor, preview and optional analysis services")
'''
load_module=s[s.index('\tMain.LoadModule = function('):s.index('\n\tlocal moduleAppTable')]
refresh=s[s.index('Main.AppControls.Lib.InitDeps(Main.GetInitDeps())'):].splitlines()[0]
code+='\ndo local Main={AppControls={}} local Apps={} local EmbeddedModules local metadata local require=function(control) return control end\n'
code+=r"""
local received={}
Main.GetInitDeps=function() return {API=metadata} end
local lib={InitDeps=function(d) table.insert(received,d.API or false) end, Main=function() return {} end}
local tool={Main=function(apps) assert(apps.Lib) return {Ready=true} end}
local script={WaitForChild=function() return {WaitForChild=function(_,name) return tool end} end}
EmbeddedModules={Lib=function() return lib end}
"""+load_module+r"""
assert(Main.LoadModule("Lib")==Apps.Lib and received[1]==false)
metadata={Classes={}}
"""+refresh+r"""
assert(received[2]==metadata)
EmbeddedModules=nil
assert(Main.LoadModule("Tool")==Apps.Tool and Apps.Tool.Ready)
end
"""
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp)/'check.luau';p.write_text(code,encoding='utf-8');subprocess.run([str(root/'.tools/bin/luau.exe'),str(p)],check=True)
