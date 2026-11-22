from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
def literal(raw): return '"'+''.join('\\'+str(b).zfill(3) for b in raw)+'"'
harness=['local P=require("../src/Apps/Reconstructor/Services/BytecodePaths").Main()', 'local R=require("../src/Apps/Reconstructor/Services/ModuleReconstruction").Main()']
with tempfile.TemporaryDirectory() as temp:
 for method in [False,True]:
  p=Path(temp)/'fixture.luau'
  p.write_text('local api=require(game.ServerStorage.Modules.Inventory); api'+(':' if method else '.')+'Give("Sword",42,true)',encoding='utf-8')
  for optimize in range(3):
   raw=subprocess.check_output([str(root/'.tools/bin/luau-compile.exe'),'--binary','-O'+str(optimize),str(p)])
   harness.append('do local node={} local found=false; assert(P.Analyze('+literal(raw)+',"fixture",function(path,e) if e.Member and e.Member.Kind~="field" then assert(table.concat(path,".")=="ServerStorage.Modules.Inventory");assert(e.Member.Name=="Give" and e.Member.Method=='+str(method).lower()+');assert(e.Member.Count==3 and e.Member.Arguments[1]=="string" and e.Member.Arguments[2]=="number" and e.Member.Arguments[3]=="boolean");R.Merge(node,e.Member);found=true end end));assert(found);local source=R.Generate(node);assert(source:find("arg1: string",1,true));assert(source:find("-- Reconstructed by Dex",1,true)==1); end')
 # Nested literals retain structure and actual closure arity without running them.
 p=Path(temp)/'tables.luau'
 p.write_text('local api=require(game.ServerStorage.M); api.Config={Enabled=true, Nested={Max=42}, Run=function(a,b,...) return a end}',encoding='utf-8')
 raw=subprocess.check_output([str(root/'.tools/bin/luau-compile.exe'),'--binary','-O1',str(p)])
 harness.append('do local node={};assert(P.Analyze('+literal(raw)+',\"table fixture\",function(_,e) if e.Member then R.Merge(node,e.Member) end end));local source=R.Generate(node);assert(source:find(\"nil :: (boolean)\",1,true));assert(source:find(\"nil :: (number)\",1,true));assert(source:find(\"arg2: unknown, ...: unknown\",1,true));end')
 harness.append('''
local A=require("../src/Apps/Reconstructor/Services/ServerReferenceAnalysis").Main()
local node={} local count=0
assert(A.Source([[local api=require(game.ServerStorage.Inventory); api.Config.Limits.Max=42; api.Config.Apply("test", true)]],"source",function(_,e) if e.Member then R.Merge(node,e.Member);count+=1 end end))
assert(count==2,"source module contract count")
local indexed={}
A.Source([[local api=require(game.ServerStorage.Numeric); api.Values[1]=true; api.Values["1"]="x"; api.Values[2].Open()]],"numeric source",function(_,e) if e.Member then R.Merge(indexed,e.Member) end end)
local indexedSource=R.Generate(indexed)
assert(indexedSource:find('["Values"][1]',1,true) and indexedSource:find('["Values"]["1"]',1,true) and indexedSource:find('["Values"][2]["Open"]',1,true))
local source=R.Generate(node)
assert(source:find('module["Config"] = {}',1,true))
assert(source:find('["Limits"] = {}',1,true))
assert(source:find('nil :: (number)',1,true))
assert(source:find('arg2: boolean',1,true))
print("GENERATED_BEGIN") print(source) print("GENERATED_END")
local node={}
assert(R.Merge(node,{Name="x",Count=2,Arguments={"string","number"}}))
assert(not R.Merge(node,{Name="x",Count=2,Arguments={"string","number"}}))
assert(R.Merge(node,{Name="x",Count=1,Arguments={"boolean"}}))
local source=R.Generate(node)
assert(source:find("boolean | string",1,true) and source:find("nil | number",1,true))
local object={} R.Bind(object,node)
assert(object.Source==source and R.GetSource(object)==source)
assert(R.GetSource({Source="real"})==nil)
local shadowed=0
A.Source([[local api=require(game.ServerStorage.M); local function f(api) api.NotEvidence() end]],"shadow",function(_,e) if e.Member then shadowed+=1 end end)
assert(shadowed==0)
local exports={}
assert(A.Source([[local api=require(game.ServerStorage.Exports)
function api:Configure(label: string, count: number?) return label end
api.Build=function(enabled: boolean, ...) return enabled end
api("start")
api.Build.Metadata.Version=1
]],"exports",function(_,e) if e.Member then R.Merge(exports,e.Member) end end))
local exportSource=R.Generate(exports)
assert(exportSource:find('self: unknown, label: string, count: number?',1,true))
assert(exportSource:find('setmetatable(module["Build"]',1,true))
assert(exportSource:find('enabled: boolean, ...: unknown',1,true))
assert(exportSource:find('setmetatable(module,',1,true))
local many={}
for index=1,300 do assert(R.Merge(many,{Name="Member"..index,Count=0})) end
assert(many.ModuleMemberCount==300 and R.Generate(many):find('Member300',1,true))
local ReaderModule=require("../src/Apps/Reconstructor/Services/ScriptEvidenceReader")
local cached=string.rep("do local padding=0 end\\n",4000)..'local api=require(game.ServerStorage.Cached); api.Present()'
ReaderModule.InitDeps({env={getscriptbytecode=function() error("cached source must avoid native reads") end},Apps={ReferenceSource={Store=function() end,Peek=function() return {Source=cached} end}}})
local reader=ReaderModule.Main().Create({Wait=function() end})
local object={}
local outcome=reader:Read(object)
assert(outcome.Status=="Source" and #outcome.Source>65536)
local cachedMembers={}
assert(A.Source(outcome.Source,"cached source",function(_,e) if e.Member then R.Merge(cachedMembers,e.Member) end end,nil,200000))
assert(R.Generate(cachedMembers):find('Present',1,true))
reader:Commit(object,cached)
assert(reader:Read(object).Status=="Cached")
local Cell=require("../src/Apps/Properties/Components/PropertyValueCell").Main()
local original=string.rep("x",2047)..utf8.char(0x1F600).."\\nmore"
local preview=Cell.PreviewText(original)
assert(utf8.len(preview) and #preview<=2051 and not preview:find("\\n",1,true))
assert(Cell.PreviewText("first\\nsecond\\tthird")=="first second third")
print("PASS module source/bytecode contracts, nested tables, field writes, argument types, shadowing, merging and cache")
''')
 for source,checks in [
  ('local api=require(game.ServerStorage.M); api.Configure=function(label: string, count: number, enabled: boolean, ...) return label end', ['label: string','count: number','enabled: boolean','...: unknown']),
  ('local api=require(game.ServerStorage.M); return function() api.Nested.Action("x") end', ['["Nested"] = {}','arg1: string'])]:
  p=Path(temp)/'metadata.luau';p.write_text(source,encoding='utf-8')
  raw=subprocess.check_output([str(root/'.tools/bin/luau-compile.exe'),'--binary','-g2','-O1','-t1',str(p)])
  harness.append('do local node={};assert(P.Analyze('+literal(raw)+',"metadata",function(_,e) if e.Member then R.Merge(node,e.Member) end end));local source=R.Generate(node);'+''.join('assert(source:find('+literal(check.encode())+',1,true),'+literal(check.encode())+');' for check in checks)+'end')
 for source,checks,excluded in [
  ('local api=require(game.ServerStorage.M); api.First(); unknown(); api.Second(42); api.Third("x")', ['["First"]','["Second"]','["Third"]'], []),
  ('local api=require(game.ServerStorage.M); local function change() api={} end; unknown(change); api.MustNotAppear()', [], ['MustNotAppear']),
  ('local api=require(game.ServerStorage.M); api.List={"x",{Enabled=true},function(amount: number) return amount end}; api.Indexed[1]=true; api.Indexed[2]="x"', ['["List"][1]','["List"][2]["Enabled"]','["List"][3] = function(amount: number)','["Indexed"][1]','["Indexed"][2]'], []),
  ('local api=require(game.ServerStorage.M); api.Items[1].Open("x"); api.Items[2].Close()', ['["Items"][1]["Open"]','["Items"][2]["Close"]'], [])]:
  p=Path(temp)/'coverage.luau';p.write_text(source,encoding='utf-8')
  for optimize in range(3):
   raw=subprocess.check_output([str(root/'.tools/bin/luau-compile.exe'),'--binary','-g2','-O'+str(optimize),'-t1',str(p)])
   harness.append('do local node={};assert(P.Analyze('+literal(raw)+',"coverage",function(_,e) if e.Member then R.Merge(node,e.Member) end end));local source=R.Generate(node);'+''.join('assert(source:find('+literal(check.encode())+',1,true),'+literal(check.encode())+');' for check in checks)+''.join('assert(not source:find('+literal(check.encode())+',1,true),"fabricated mutable reference");' for check in excluded)+'end')
 p=Path(temp)/'large-export.luau'
 p.write_text('local api=require(game.ServerStorage.Many); api.Values={'+','.join('Field'+str(i)+'='+str(i) for i in range(300))+'}',encoding='utf-8')
 raw=subprocess.check_output([str(root/'.tools/bin/luau-compile.exe'),'--binary','-O1',str(p)])
 harness.append('do local node={};assert(P.Analyze('+literal(raw)+',"large export",function(_,e) if e.Member then R.Merge(node,e.Member) end end));assert((node.ModuleMemberCount or 0)>=301);assert(R.Generate(node):find("Field299",1,true));local budget={Count=0,Limit=1,Dropped=0};local limited={};assert(R.Merge(limited,{Name="one",Count=0},budget));local merged,reason=R.Merge(limited,{Name="two",Count=0},budget);assert(not merged and reason and budget.Dropped==1 and budget.Count==1);end')
 viewer=(root/'src/Apps/ScriptViewer/ScriptViewer.lua').read_text(encoding='utf-8')
 method=viewer.split('ScriptViewer.ViewScript = function(scr, shouldOpen)',1)[1].split('\n\treturn ScriptViewer',1)[0]
 harness += ['do local object={};local opened,shown=0,0;local ScriptViewer={Documents={},OpenDocument=function(id,name,source,backing) assert(id==object and source=="generated" and backing==nil);opened+=1 end};local Apps={ModuleReconstruction={GetSource=function(o) return o==object and "generated" end}};local window={Show=function() shown+=1 end};local env={decompile=function() error("must not decompile synthetic module") end};ScriptViewer.ViewScript=function(scr,shouldOpen)'+method+';ScriptViewer.ViewScript(object);assert(opened==1 and shown==1);end']
 refresh=viewer.split('ScriptViewer.RefreshGeneratedDocument = function(doc, source)',1)[1].split('ScriptViewer.OpenDocument = function',1)[0]
 harness += ['do local restored,foldResets=0,0;local active;local boundary=function() end;local historyAliases=function() end;local restore=function() restored+=1 end;local renderTabs=function() end;local codeFrame={ResetFolds=function() foldResets+=1 end};local ScriptViewer={};ScriptViewer.RefreshGeneratedDocument=function(doc,source)'+refresh+';local resets=0;local doc={text="old",folds={[1]=true},undoStack={reset=function() resets+=1 end}};active=doc;assert(ScriptViewer.RefreshGeneratedDocument(doc,"new") and doc.text=="new" and resets==1 and restored==1 and foldResets==1 and doc.folds==nil);doc.dirty=true;assert(not ScriptViewer.RefreshGeneratedDocument(doc,"replacement") and doc.text=="new");end']
 explorer=(root/'src/Apps/Explorer/Explorer.lua').read_text(encoding='utf-8')
 compact_explorer = ''.join(explorer.split())
 assert 'context:AddRegistered("VIEW_SCRIPT",firstOpenableScript()==nil)' in compact_explorer
 assert 'Apps.ModuleReconstruction.GetSource(object)thenreturnobject' in compact_explorer
 assert '(notnode.Inferredor(Apps.ModuleReconstructionandApps.ModuleReconstruction.GetSource(node.Obj)))' in compact_explorer
 target=root/'tests/.module-reconstruction.luau'
 try:
  target.write_text('\n'.join(harness),encoding='utf-8')
  result=subprocess.check_output([str(root/'.tools/bin/luau.exe'),str(target)],cwd=root,text=True)
  generated=result.split('GENERATED_BEGIN\n',1)[1].split('GENERATED_END',1)[0]
  generated_path=Path(temp)/'generated.luau';generated_path.write_text(generated,encoding='utf-8')
  subprocess.run([str(root/'.tools/bin/luau-compile.exe'),str(generated_path)],check=True,stdout=subprocess.DEVNULL)
  print(result.split('GENERATED_END',1)[1].strip())
 finally:target.unlink(missing_ok=True)
