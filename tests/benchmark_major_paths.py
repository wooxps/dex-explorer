"""Cold first-query/sort and real hosted-source compilation benchmarks.

CPU uses Luau CLI and synthetic nodes; packet byte counts are actual artifacts.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
cli=argparse.ArgumentParser()
cli.add_argument('--baseline',default='6982425')
cli.add_argument('--nodes',type=int,default=60000)
args=cli.parse_args()
def prior(path):
 return subprocess.check_output(['git','show',args.baseline+':'+path],cwd=ROOT,text=True)
def literal(text):
 equals='===='
 while ']'+equals+']' in text: equals+='='
 return '['+equals+'[\n'+text+']'+equals+']'
report={'baseline':args.baseline,'nodes':args.nodes,'kind':'cold Luau CPU; synthetic nodes and real hosted source'}
old=json.loads(prior('manifest.json'))
new=json.loads((ROOT/'manifest.json').read_text())
report['packetBytes']={'before':sum(p['bytes'] for p in old['bundles']),'after':sum(p['bytes'] for p in new['bundles'])}
report['sourceBytes']={'before':sum(p['bytes'] for p in old['files'].values()),'after':sum(p['bytes'] for p in new['files'].values())}
with tempfile.TemporaryDirectory(prefix='dex-major-paths-') as folder:
 for version in ('before','after'):
  def source(path): return prior(path) if version=='before' else (ROOT/path).read_text()
  pieces=['local Apps={} local RMD={Classes={}} local Explorer={} local explorerOrders={} local idCounter=0\n']
  for name,path in [('SearchNameIndex','src/Apps/Explorer/Services/SearchNameIndex.lua'),('SearchQuery','src/Shared/SearchQuery.lua')]:
   pieces.append('do local c=(function()\n'+source(path)+'\nend)() if c.InitDeps then c.InitDeps({Apps=Apps,API={Classes={}},service={}}) end Apps.'+name+'=c.Main() end')
  explorer=source('src/Apps/Explorer/Explorer.lua')
  if version == 'before':
   pieces.append('local sortingNames\n'+explorer[explorer.index('\tExplorer.NodeSorter = function'):explorer.index('\n\tExplorer.Update = function')])
  else:
   pieces.append('local control=(function()\n'+source('src/Apps/Explorer/Services/ExplorerSiblingSort.lua')+'\nend)() local siblingSort=control.Main().Create(RMD.Classes,explorerOrders) Explorer.NodeSorter=siblingSort.DefaultSorter')

  pieces.append('local size='+str(args.nodes)+r'''
local root={} local nativeNames=0
local mt={__tostring=function(o) nativeNames+=1 return o.Name end}
for i=1,size do local name="Part"..((i*7919)%size) root[i]={Obj=setmetatable({Name=name,ClassName="Part"},mt)} root[i].Parent=root end
local function run(query)
 local samples={} local reads=0 local matchCount
 for iteration=1,5 do
  Apps.SearchQuery.NameIndex.Clear()
  local predicate=assert(Apps.SearchQuery.Compile(query)) local matches={} local results={} local expanded={}
  local started=os.clock()
  assert(Apps.SearchQuery.Scan({root},predicate,results,matches,expanded,nil,{Revision=iteration,Incremental=true}))
  local order=table.clone(root) nativeNames=0
  SORT_START
  table.sort(order,Explorer.NodeSorter)
  sortingNames=nil
  samples[iteration]=os.clock()-started reads=nativeNames
  matchCount=0 for _ in pairs(matches) do matchCount+=1 end
  assert(matchCount>0)
 end
 table.sort(samples)
 print("QUERY "..query.."|"..samples[3].."|"..reads.."|"..matchCount)
end
run("part123") run("name:Part123") run('"Part123"')
'''.replace('SORT_START','siblingSort.Names={}' if version=='after' else ''))
  manifest=old if version=='before' else new
  pieces.append('local sources={'+','.join('['+json.dumps(path)+']='+literal(prior(path) if version=='before' else (ROOT/'dist/github'/path).read_text()) for path in manifest['files'])+'}')
  pieces.append('local times={} for iteration=1,5 do local chunks={} local started=os.clock() for path,text in pairs(sources) do chunks[#chunks+1]=assert(loadstring(text,"@DexExplorer/"..path)) end times[iteration]=os.clock()-started end table.sort(times) print("COMPILE "..times[3])')
  harness=Path(folder)/(version+'.luau')
  harness.write_text('\n'.join(pieces),encoding='utf-8')
  output=subprocess.check_output([str(ROOT/'.tools/bin/luau.exe'),str(harness)],text=True)
  values={}
  for line in output.splitlines():
   if line.startswith('QUERY '):
    query,seconds,reads,matches=line[6:].split('|')
    values[query]={'seconds':float(seconds),'sortNameReads':int(reads),'matches':int(matches)}
   elif line.startswith('COMPILE '): values['hostedCompileSeconds']=float(line[8:])
  report[version]=values
(ROOT/'.build/major-path-performance.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
