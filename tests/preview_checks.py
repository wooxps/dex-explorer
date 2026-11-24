"""Exercise production preview modules with numerical/lifecycle Roblox doubles."""
import argparse
from pathlib import Path
import subprocess
import tempfile

cli = argparse.ArgumentParser()
cli.add_argument('--luau', default='luau')
args = cli.parse_args()
root = Path(__file__).resolve().parents[1]
parts = [(root / 'tests/roblox_mock.luau').read_text(), (root / 'tests/preview_mock.luau').read_text()]
for name in ['PreviewCamera', 'PreviewScene', 'ModelViewer']:
    source = next((root / 'src').rglob(name + '.lua')).read_text()
    parts.append('do local control=(function()\n' + source + '\nend)()\n'
                 'if control.InitDeps then control.InitDeps({Main=Main,Lib=Lib,Apps=Apps,Settings=Settings,env={},service=service}) end\n'
                 'Apps.' + name + '=control.Main() end\n')
parts.append((root / 'tests/preview.spec.luau').read_text())
with tempfile.TemporaryDirectory(prefix='dex-preview-') as folder:
    harness = Path(folder) / 'preview.luau'
    harness.write_text('\n'.join(parts), encoding='utf-8')
    subprocess.run([args.luau, str(harness)], check=True)
