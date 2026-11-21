"""Exercise production transform session calculations and existing History."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
parts = [(root/'tests/roblox_mock.luau').read_text(), (root/'tests/transform_session_mock.luau').read_text()]
for name, path in [('PropertyChanges', 'src/Shared/PropertyChanges.lua'), ('History', 'src/Shared/History.lua'), ('TransformSession', 'src/Apps/TransformTools/TransformSession.lua')]:
    parts.append('do local control=(function()\n'+(root/path).read_text()+'\nend)()\n'
                 'control.InitDeps({Apps=Apps,Main=Main,Lib=Lib,service=service}) Apps.'+name+'=control.Main() end\n')
parts.append((root/'tests/transform_session.spec.luau').read_text())
for name in ['TransformGizmo','TransformTools']:
    parts.append('do local control=(function()\n'+(root/'src/Apps/TransformTools'/f'{name}.lua').read_text()+'\nend)()\n'
                 'control.InitDeps({Apps=Apps,Main=Main,Lib=Lib,service=service,Settings=Settings}) Apps.'+name+'=control.Main() end\n')
parts.append((root/'tests/transform_controller.spec.luau').read_text())
with tempfile.TemporaryDirectory(prefix='dex-transform-') as folder:
    harness=Path(folder)/'transform.luau'
    harness.write_text('\n'.join(parts), encoding='utf-8')
    subprocess.run([args.luau,str(harness)],check=True)
