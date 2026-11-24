"""Exercise production GUI transform session/view/controller with layout doubles."""
import argparse,subprocess,tempfile
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('--luau',default='luau')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
parts=[(root/'tests/roblox_mock.luau').read_text(),(root/'tests/gui_transform_mock.luau').read_text()]
for name,path in [('PropertyChanges','src/Shared/PropertyChanges.lua'),('History','src/Shared/History.lua')]+[(n,f'src/Apps/TransformTools/{n}.lua') for n in ('TransformSession','GuiTransformSession','GuiAlignment','GuiTransformView','GuiTransformTools','TransformTools')]:
    parts.append('do local m=(function()\n'+(root/path).read_text()+'\nend)() if m.InitDeps then m.InitDeps({Apps=Apps,Main=Main,Lib=Lib,service=service,Settings=Settings}) end Apps.'+name+'=m.Main() end\n')
parts.append((root/'tests/gui_alignment.spec.luau').read_text())
parts.append((root/'tests/gui_transform_modifiers.spec.luau').read_text())
parts.append((root/'tests/gui_transform_view.spec.luau').read_text())
parts.append((root/'tests/gui_transform.spec.luau').read_text())
with tempfile.TemporaryDirectory(prefix='dex-gui-transform-') as folder:
    harness=Path(folder)/'gui-transform.luau'
    harness.write_text('\n'.join(parts),encoding='utf-8')
    subprocess.run([args.luau,str(harness)],check=True)
