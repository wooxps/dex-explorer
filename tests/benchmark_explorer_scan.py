"""Reproduce the README scan benchmarks with simulated objects in the Luau CLI."""

import argparse
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
RESULTS_PATH = 'src/Apps/Explorer/Services/SearchResults.lua'
BITS_PATH = 'src/Apps/Explorer/Services/SearchBits.lua'

DRIVER = r'''
local bits = (function()
__BITS__
end)().Main()
local before = (function()
__BEFORE__
end)()
local after = (function()
__AFTER__
end)()
local versions = {}
for _, control in {before, after} do
 if control.InitDeps then control.InitDeps({Apps = {SearchBits = bits}}) end
 versions[#versions + 1] = {api = control.Main({SearchBits=bits}), cold = {}, existing = {}, filtered = {}}
end
local root = {}
for group = 1, 600 do
 local parent = {Obj = {Name = 'Group' .. group}, Parent = root, Visible = group <= 200}
 root[group] = parent
 for i = 1, 100 do
  local id = (group - 1) * 100 + i
  parent[i] = {Obj = {Name = id % 3 == 0 and 'Part' .. id or 'Piece' .. (id % 500)}, Parent = parent}
 end
end
local context = {
 Name = function(node) return node.Obj.Name end,
 Children = function(node) return node end,
 Visible = function() return true end,
 Estimate = 60600,
}
local function checkpoint() end
local scoped = {
 Name = context.Name, Children = context.Children, VisibleOnly = true,
 Visible = function(node) return node.Visible end,
}
local function measure(version)
 local results = version.api
 local start = os.clock()
 local view = results.CreateCold({root}, {'e'}, context, checkpoint)
 version.cold[#version.cold + 1] = (os.clock() - start) * 1000
 assert(#view.MatchList == 40000 and #view.Rows == 40600, 'cold scan changed results')
 start = os.clock()
 local nextView = results.CreateCold({root}, {'piece'}, context, checkpoint, view.ColdLayout)
 version.existing[#version.existing + 1] = (os.clock() - start) * 1000
 assert(#nextView.MatchList == 40000 and #nextView.Rows == 40600, 'existing-tree scan changed results')
 start = os.clock()
 view = results.CreatePredicate(nil, function(object)
  return object.Name:find('Part', 1, true) ~= nil
 end, scoped, checkpoint, {root})
 version.filtered[#version.filtered + 1] = (os.clock() - start) * 1000
 assert(#view.MatchList == 6666 and #view.Rows == 6866, 'filtered scan changed results')
end
for i = 1, __RUNS__ do
 if i % 2 == 1 then measure(versions[1]) measure(versions[2])
 else measure(versions[2]) measure(versions[1]) end
end
for _, version in versions do
 for _, samples in {version.cold, version.existing, version.filtered} do
  local values = {}
  for i, value in samples do values[i] = string.format('%.9f', value) end
  print(table.concat(values, ','))
 end
end
'''


def git_source(ref, path):
    return subprocess.check_output(
        ['git', 'show', f'{ref}:{path}'], cwd=ROOT, encoding='utf-8'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', default='7bf94c1')
    parser.add_argument('--after', default='7293899')
    parser.add_argument('--runs', type=int, default=9)
    parser.add_argument('--luau', type=Path)
    args = parser.parse_args()
    if not 1 <= args.runs <= 1000:
        parser.error('--runs must be between 1 and 1000')

    luau = args.luau
    if luau is None:
        luau = next((p for p in (ROOT / '.tools/bin/luau.exe', ROOT / '.tools/bin/luau') if p.is_file()), None)
        luau = luau or shutil.which('luau')
    if not luau:
        parser.error('Luau is missing. Run python build.py setup --tools luau or pass --luau.')

    bits = git_source(args.after, BITS_PATH)
    report = {
        'objects': 60600,
        'runs': args.runs,
        'order': 'alternating versions within one Luau process',
        'measurement': 'Luau CLI elapsed scan time; excludes sorting, frame waits and UI rendering',
        'hiddenBranches': {'hidden': 400, 'total': 600},
        'matchingObjects': {'cold': 40000, 'existingTree': 40000, 'filtered': 6666},
    }
    metrics = ('cold', 'existingTree', 'filtered')
    with tempfile.TemporaryDirectory(prefix='dex-scan-benchmark-') as directory:
        path = Path(directory) / 'benchmark.luau'
        source = DRIVER.replace('__BITS__', bits).replace('__BEFORE__', git_source(args.before, RESULTS_PATH))
        source = source.replace('__AFTER__', git_source(args.after, RESULTS_PATH))
        path.write_text(source.replace('__RUNS__', str(args.runs)), encoding='utf-8')
        lines = subprocess.check_output([str(luau), str(path)], cwd=ROOT, text=True).splitlines()
        assert len(lines) == len(metrics) * 2, 'Unexpected benchmark output'
        for offset, (label, ref) in enumerate((('before', args.before), ('after', args.after))):
            measurements = {}
            for metric, line in zip(metrics, lines[offset * 3:offset * 3 + 3]):
                samples = [float(value) for value in line.split(',')]
                assert len(samples) == args.runs
                measurements[metric] = {'medianMs': statistics.median(samples), 'samplesMs': samples}
            report[label] = {'commit': ref, 'measurements': measurements}

    report['lessCpuPercent'] = {}
    for metric in metrics:
        before = report['before']['measurements'][metric]['medianMs']
        after = report['after']['measurements'][metric]['medianMs']
        report['lessCpuPercent'][metric] = 100 * (1 - after / before) if before else None
    output = ROOT / '.build/explorer-scan-benchmark.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
