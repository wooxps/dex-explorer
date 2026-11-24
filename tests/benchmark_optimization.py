"""Compare real module CPU work; synthetic mocks, not live Roblox timings."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', default='1e28cb0')
args = parser.parse_args()
paths = {
    'ActivitySession': 'src/Apps/ActivityViewer/ActivitySession.lua',
    'SearchNameIndex': 'src/Apps/Explorer/Services/SearchNameIndex.lua',
    'ReferenceScan': 'src/Apps/ReferenceFinder/ReferenceScan.lua',
    'ServerReferenceAnalysis': 'src/Apps/Reconstructor/Services/ServerReferenceAnalysis.lua',
}
fixture = r'''
local originalTypeof=typeof
typeof=function(value) return getmetatable(value)==instMT and "Instance" or originalTypeof(value) end
eventNames.AttributeChanged=true eventNames.ChildRemoved=true eventNames.Changed=true
function methods:GetAttributes() local values={} for key,value in pairs(self._props) do if key:sub(1,5)=="attr_" then values[key:sub(6)]=value end end return values end
function methods:GetFullName() return self.Name end
local originalIsA=methods.IsA
function methods:IsA(class) return class=="LuaSourceContainer" and self.ClassName=="LocalScript" or originalIsA(self,class) end
local fields={}
for i=1,16 do fields[i]={Name="Field"..i} end
API.Classes.Part={Name="Part",Properties=fields}
local root=Instance.new("Folder",workspace)
for i=1,1500 do local part=Instance.new("Part",root) for j=1,16 do part["Field"..j]=j end end
local time=0 local recording=Apps.ActivitySession.Create({Clock=function() return time end})
recording:Start(root) while recording.PendingObjects>0 do recording:Step() end
local function measure(name,callback)
 local samples={}
 for run=1,7 do local started=os.clock() callback() samples[run]=os.clock()-started end
 table.sort(samples) print(name.." "..samples[4])
end
measure("activity_idle",function() for i=1,200 do time+=.3 recording:Step() end end)
assert(recording.WatchedObjects==1501 and recording.Count==0,"idle optimization retains full watcher coverage without fabricating events")
local checksumText=string.rep("Dex Explorer startup fixture\000\255",40000)
measure("startup_checksum",function() assert(checksum(checksumText)>0) end)
recording:Stop()
local tree={} local parent={Obj={Name="Container"},Parent=tree} tree[1]=parent
for i=1,12000 do parent[i]={Obj={Name="Part"..i},Parent=parent} end
local revision=1 local index=Apps.SearchNameIndex.Create()
assert(index.Scan({tree},"part",revision,{},{},{},nil,true))
measure("overlapping_search_deltas",function()
 index.MarkDirty(parent,true) for _,child in ipairs(parent) do index.MarkDirty(child,false) end
 revision+=1 assert(index.Scan({tree},"part123",revision,{},{},{},nil,true))
end)
local target=Instance.new("Part") target.Name="Needle"
local objects,sources={},{}
local text=string.rep("local value = workspace.Part -- ordinary code\n",12000)
for i=1,32 do local script=Instance.new("LocalScript") objects[script]=true sources[script]=text end
measure("reference_text_misses",function()
 local results=Apps.ReferenceScan.Run({Target=target,Objects=objects,Sources=sources,MaxTotalBytes=64*1024*1024})
 assert(#results.Scripts==0 and results.Stats.ReadableScripts==32 and not results.Stats.Cancelled)
end)
for object in pairs(sources) do sources[object]=text..'\treturn workspace.Needle\n' end
measure("reference_sparse_hits",function()
 local results=Apps.ReferenceScan.Run({Target=target,Objects=objects,Sources=sources,MaxTotalBytes=64*1024*1024})
 assert(#results.Scripts==32 and results.Scripts[1].Line==12001 and results.Scripts[1].Column==19)
end)
measure("revisited_queries",function()
 for _,term in ipairs({"part999","part234","part345","part456","part567","part678","part789"}) do
  local matches={} assert(index.Scan({tree},term,revision,{},matches,{},nil,true))
 end
end)
local analysisSource=string.rep("local number = 1\n",4000)..'local ss=game.ServerStorage\nrequire(ss.Modules.Inventory)'
measure("server_source_analysis",function()
 local hits=0
 assert(Apps.ServerReferenceAnalysis.Source(analysisSource,"benchmark",function() hits+=1 end))
 assert(hits>0,"source analysis retains the server path")
end)
'''
report = {'baseline': args.baseline, 'kind': 'synthetic Luau CPU median, seven runs', 'seconds': {}}
with tempfile.TemporaryDirectory(prefix='dex-optimization-') as folder:
    for version in ('before', 'after'):
        pieces = [(ROOT/'tests/roblox_mock.luau').read_text(), 'local Apps={}']
        for name, path in paths.items():
            source = subprocess.check_output(['git', 'show', args.baseline+':'+path], cwd=ROOT, text=True) if version=='before' else (ROOT/path).read_text()
            pieces.append('do local control=(function()\n'+source+'\nend)() if control.InitDeps then control.InitDeps({API=API,env={},Main=Main}) end Apps.'+name+'=control.Main() end')
        bootstrap = subprocess.check_output(['git','show',args.baseline+':src/Runtime/Bootstrap.luau'], cwd=ROOT,text=True) if version=='before' else (ROOT/'src/Runtime/Bootstrap.luau').read_text()
        pieces.append(bootstrap[bootstrap.index('local function checksum(data)'):bootstrap.index('if type(makefolder)')])
        pieces.append(fixture)
        harness = Path(folder)/(version+'.luau')
        harness.write_text('\n'.join(pieces), encoding='utf-8')
        output = subprocess.check_output([str(ROOT/'.tools/bin/luau.exe'), str(harness)], text=True)
        report['seconds'][version] = dict((name,float(value)) for name,value in (line.split() for line in output.splitlines()))
report['reductionPercent'] = {key: round(100*(1-report['seconds']['after'][key]/value), 1) for key,value in report['seconds']['before'].items()}
destination=ROOT/'.build/optimization-performance.json'
destination.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
