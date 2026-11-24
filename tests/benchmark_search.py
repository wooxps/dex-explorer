"""Reproducible synthetic search benchmark; results are not Roblox frame timings."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', default='a319e7e')
parser.add_argument('--nodes', type=int, default=60000)
parser.add_argument('--multiword', action='store_true')
args = parser.parse_args()
assert 0 < args.nodes <= 1000000
queries=['part 12','part 123','part 1','part 999','part 12'] if args.multiword else ['pa','par','part','part1','part123']
baseline = subprocess.check_output(['git','show',args.baseline+':src/Shared/SearchQuery.lua'],cwd=ROOT,text=True)
current = (ROOT/'src/Shared/SearchQuery.lua').read_text(encoding='utf-8')
index = (ROOT/'src/Apps/Explorer/Services/SearchNameIndex.lua').read_text(encoding='utf-8')
template = '''
local indexControl=(function()
INDEX
end)()
local apps={SearchNameIndex=indexControl.Main()}
local control=(function()
SOURCE
end)()
if control.InitDeps then control.InitDeps({API={Classes={}},service={},Apps=apps}) end
local search=control.Main()
local root={}
for i=1,NODES do root[i]={Obj={Name="Part"..i},Parent=root} end
local queries=QUERIES
local function run()
 local started=os.clock()
 for _,query in ipairs(queries) do
  local predicate=assert(search.Compile(query))
  assert(search.Scan({root},predicate,{},{},{},nil,{Revision=1}))
 end
 return os.clock()-started
end
print(run())
local samples={}
for i=1,7 do samples[i]=run() end
table.sort(samples)
print(samples[4])
'''
report={'nodes':args.nodes,'queries':queries,'warmSamples':7,'baseline':args.baseline}
with tempfile.TemporaryDirectory(prefix='dex-benchmark-') as directory:
    script=Path(directory)/'benchmark.luau'
    for label, source in [('before',baseline),('after',current)]:
        script.write_text(template.replace('INDEX',index).replace('SOURCE',source).replace('NODES',str(args.nodes)).replace('QUERIES','{'+','.join(json.dumps(q) for q in queries)+'}'),encoding='utf-8')
        values=subprocess.check_output([str(ROOT/'.tools/bin/luau.exe'),str(script)],text=True).splitlines()
        report[label]={'firstSeconds':float(values[0]),'warmMedianSeconds':float(values[1])}
report['warmReductionPercent']=100*(1-report['after']['warmMedianSeconds']/report['before']['warmMedianSeconds'])
output=ROOT/'.build/search-performance.json'
output.parent.mkdir(exist_ok=True)
output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
