"""Compare search and syntax coloring with the original Dex in the Luau CLI."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
DEX_COMMIT = 'd6286cf27c77af749ad515d517d2500330f63ff2'
MODULES = ('SearchBits', 'SearchPostings', 'SearchSnapshot', 'SearchResults',
           'SearchTreeResults', 'ExplorerSearch')

DRIVER = r'''
local Apps = {}
__MODULES__
local lower, find, lowerQuery = string.lower, string.find, ''
local searchResults, expandTable = {}, {}
local expanded = expandTable
__OLD_SEARCH__
local oldColors, newColors = {}, {}
do
 local funcs, tick = oldColors, os.clock
 __OLD_COLORS__
end
do
 local funcs = newColors
 __NEW_COLORS__
end
local root = {Obj = {Name = 'game'}}
local names = {__tostring = function(object) return object.Name end}
local group = {Obj = setmetatable({Name = 'Workspace', ClassName = 'Workspace'}, names), Parent = root}
root[1] = group
for i = 1, 70000 do
 group[i] = {Obj = setmetatable({Name = 'Part' .. i, ClassName = 'Part'}, names), Parent = group, Key = i}
end
local engine = Apps.ExplorerSearch.Create({
 Roots = function() return {root} end,
 Sorting = function() return false end,
 Scope = function() return 1 end,
 Alive = function() return true end,
 Wait = function() end,
 Visible = function() return true end,
 Read = function(node) return node.Obj.Name, node.Obj.ClassName, 0, node.Key or 0 end,
})
local function valid() return true end
local warmed, warmError = engine:Search(nil, nil, valid, true)
assert(warmed, tostring(warmError))
local queries = {}
for i = 1, __RUNS__ do queries[i] = 'part' .. (1200 + i) end
local oldEditor = {Text = string.rep('local n=1 -- comment\n', 10000)}
oldColors.MapNewLines(oldEditor)
local newEditor = {Lines = oldEditor.Text:split('\n')}
newColors.PreHighlight(newEditor)
local oldTexts, newLines = {}, {}
for i = 1, 10 do
 newLines[i] = 'local n=' .. (i % 10) .. ' -- comment'
 oldTexts[i] = string.rep('local n=1 -- comment\n', 4) .. newLines[i] .. '\n'
  .. string.rep('local n=1 -- comment\n', 9995)
end
local samples = {originalSearch = {}, currentSearch = {}, originalRepeat = {}, currentRepeat = {},
 originalColors = {}, currentColors = {}}
local function originalSearch(query)
 table.clear(searchResults)
 table.clear(expandTable)
 lowerQuery = query
 local started = os.clock()
 defaultSearch(root)
 local elapsed = (os.clock() - started) * 1000
 local matches = {}
 for node, state in expandTable do if state == 0 then matches[node] = true end end
 return elapsed, matches
end
local function currentSearch(query)
 local started = os.clock()
 local result = assert(engine:Search(nil, {query}, valid))
 return (os.clock() - started) * 1000, result
end
local function originalColors()
 local started = os.clock()
 for i = 1, 10 do oldEditor.Text = oldTexts[i] oldColors.PreHighlight(oldEditor) end
 return (os.clock() - started) * 1000 / 10
end
local function currentColors()
 local started = os.clock()
 for i = 1, 10 do newEditor.Lines[5] = newLines[i] newColors.PreHighlight(newEditor, 5) end
 return (os.clock() - started) * 1000 / 10
end
local function repeatedSearch(original)
 local total = 0
 local repeats = if original then 3 else 200
 for _ = 1, repeats do
  local elapsed = if original then originalSearch('part') else currentSearch('part')
  total += elapsed
 end
 return total / repeats
end
for i, query in queries do
 local oldTime, newTime, matches, result
 if i % 2 == 1 then
  oldTime, matches = originalSearch(query)
  newTime, result = currentSearch(query)
  samples.originalColors[i] = originalColors()
  samples.currentColors[i] = currentColors()
 else
  newTime, result = currentSearch(query)
  oldTime, matches = originalSearch(query)
  samples.currentColors[i] = currentColors()
  samples.originalColors[i] = originalColors()
 end
 samples.originalSearch[i], samples.currentSearch[i] = oldTime, newTime
 local count = 0
 for node in matches do assert(result.Matches[node]) count += 1 end
 assert(count == #result.MatchList and count > 0, 'search results differ')
 for index = 1, #result.MatchList do assert(matches[result.MatchList[index]]) end
 assert(oldEditor.PreHighlights[5] and newEditor.PreHighlights[5], 'edited line lost its colors')
 assert(oldEditor.PreHighlights[10000] and newEditor.PreHighlights[10000], 'other lines lost their colors')
 local repeated = assert(engine:Search(nil, {'part'}, valid))
 assert(#repeated.MatchList == 70000)
 if i % 2 == 1 then
  samples.originalRepeat[i] = repeatedSearch(true)
  samples.currentRepeat[i] = repeatedSearch(false)
 else
  samples.currentRepeat[i] = repeatedSearch(false)
  samples.originalRepeat[i] = repeatedSearch(true)
 end
 local repeatedCount = 0
 for _, state in expandTable do if state == 0 then repeatedCount += 1 end end
 assert(repeatedCount == 70000, 'repeat search results differ')
end
for _, key in {'originalSearch', 'currentSearch', 'originalRepeat', 'currentRepeat', 'originalColors', 'currentColors'} do
 local values = {}
 for i, value in samples[key] do values[i] = string.format('%.9f', value) end
 print(table.concat(values, ','))
end
'''


def original_source(name):
    path = ROOT / '.build/original-dex' / DEX_COMMIT / name
    if not path.is_file():
        url = f'https://raw.githubusercontent.com/LorekeeperZinnia/Dex/{DEX_COMMIT}/modules/{name}'
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return path.read_text(encoding='utf-8')


def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs', type=int, default=9)
    parser.add_argument('--luau', type=Path)
    args = parser.parse_args()
    if not 1 <= args.runs <= 1000:
        parser.error('--runs must be between 1 and 1000')
    luau = args.luau or next(
        (path for path in (ROOT / '.tools/bin/luau.exe', ROOT / '.tools/bin/luau') if path.is_file()),
        shutil.which('luau'),
    )
    if not luau:
        parser.error('Luau is missing. Run python build.py setup --tools luau or pass --luau.')
    sources = {}
    modules = []
    for name in MODULES:
        path = f'src/Apps/Explorer/Services/{name}.lua'
        source = (ROOT / path).read_text(encoding='utf-8')
        sources[path] = hashlib.sha256(source.encode()).hexdigest()
        modules.append(f'do local control = (function()\n{source}\nend)() '
                       f'control.InitDeps({{Apps = Apps}}) Apps.{name} = control.Main() end')
    explorer = original_source('Explorer.lua')
    old_lib = original_source('Lib.lua')
    new_lib = (ROOT / 'src/Shared/Lib.lua').read_text(encoding='utf-8')
    sources['src/Shared/Lib.lua'] = hashlib.sha256(new_lib.encode()).hexdigest()
    replacements = {
        '__MODULES__': '\n'.join(modules),
        '__OLD_SEARCH__': section(explorer, 'local function defaultSearch(root)', '\n\t\t\tif Main.Elevated'),
        '__OLD_COLORS__': section(old_lib, 'funcs.MapNewLines =', '\n\t\tfuncs.HighlightLine ='),
        '__NEW_COLORS__': 'local Lib={}\n' + section(new_lib, 'function Lib.NumberEnd', '\tLib.CodeFrame =') + section(new_lib, 'local function lexLine(', '\n\t\tfuncs.HighlightLine ='),
        '__RUNS__': str(args.runs),
    }
    source = DRIVER
    for marker, value in replacements.items():
        source = source.replace(marker, value)
    with tempfile.TemporaryDirectory(prefix='dex-comparison-') as folder:
        path = Path(folder) / 'benchmark.luau'
        path.write_text(source, encoding='utf-8')
        completed = subprocess.run([str(luau), str(path)], cwd=ROOT, text=True, capture_output=True)
        if completed.returncode:
            failed = ROOT / '.build/failed-dex-benchmark.luau'
            failed.write_text(source, encoding='utf-8')
            raise RuntimeError(completed.stdout + completed.stderr)
        lines = completed.stdout.splitlines()
    labels = ('originalSearch', 'currentSearch', 'originalRepeat', 'currentRepeat', 'originalColors', 'currentColors')
    assert len(lines) == len(labels), 'Unexpected benchmark output'
    report = {
        'originalDexCommit': DEX_COMMIT,
        'dexExplorerCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'sourceSha256': sources,
        'runs': args.runs,
        'measurement': 'Luau CLI elapsed time for isolated search and syntax-coloring functions',
        'search': {'objects': 70001, 'queries': [f'part{1200 + i}' for i in range(1, args.runs + 1)],
                   'indexBuildIncluded': False, 'repeatedQueries': False},
        'repeat': {'query': 'part', 'matches': 70000, 'originalBatchSize': 3, 'currentBatchSize': 200},
        'colors': {'lines': 10000, 'editedLine': 5, 'editsPerRun': 10, 'timeUnit': 'ms per edit'},
        'measurements': {},
    }
    for label, line in zip(labels, lines):
        samples = [float(value) for value in line.split(',')]
        assert len(samples) == args.runs
        report['measurements'][label] = {'medianMs': statistics.median(samples), 'samplesMs': samples}
    report['speedup'] = {
        label: report['measurements'][before]['medianMs'] / report['measurements'][after]['medianMs']
        for label, before, after in (('search', 'originalSearch', 'currentSearch'),
                                     ('repeat', 'originalRepeat', 'currentRepeat'),
                                     ('colors', 'originalColors', 'currentColors'))
    }
    output = ROOT / '.build/original-dex-benchmark.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
