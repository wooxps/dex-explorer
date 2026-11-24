"""Run reference scan and result-window integration without a game client."""
import argparse
from pathlib import Path
import subprocess
import tempfile

cli = argparse.ArgumentParser()
cli.add_argument('--luau', default='luau')
cli.add_argument('--compiler', default='luau-compile')
cli.add_argument('--benchmark', action='store_true')
args = cli.parse_args()
root = Path(__file__).resolve().parents[1]
# Reuse the numerical/lifecycle harness's window and input doubles.
parts = [(root / 'tests/roblox_mock.luau').read_text(), (root / 'tests/preview_mock.luau').read_text(), 'local referenceEnv={} local referenceClock=os.clock task.spawn=function(fn) fn() end']
for name in ['BytecodeStrings', 'ReferenceSource', 'ReferenceScan', 'ReferenceFinder']:
    source = next((root / 'src').rglob(name + '.lua')).read_text()
    parts.append('do local control=(function()\n' + source + '\nend)()\n'
                 'if control.InitDeps then control.InitDeps({API=API,Main=Main,Lib=Lib,Apps=Apps,service=service,env=referenceEnv,Clock=function() return referenceClock() end}) end\n'
                 'Apps.' + name + '=control.Main() end\n')
with tempfile.TemporaryDirectory(prefix='dex-references-') as folder:
    fixture = Path(folder) / 'fixture.luau'
    fixture.write_text('return workspace:WaitForChild("Door")', encoding='utf-8')
    bytecode = subprocess.run([args.compiler, '--binary', str(fixture)], capture_output=True, check=True).stdout
    parts.append('local referenceBytecode="'+''.join('\\%03d' % value for value in bytecode)+'"')
    parts.append((root / ('tests/reference_performance.spec.luau' if args.benchmark else 'tests/reference_finder.spec.luau')).read_text())
    harness = Path(folder) / 'references.luau'
    harness.write_text('\n'.join(parts), encoding='utf-8')
    subprocess.run([args.luau, str(harness)], check=True)
