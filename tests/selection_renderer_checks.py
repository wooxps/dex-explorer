"""Exercise selection ownership and live reconciliation; no GPU rendering claims."""
import argparse
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
parts = [(root/'tests/roblox_mock.luau').read_text(encoding='utf-8'),
         (root/'tests/selection_renderer_mock.luau').read_text(encoding='utf-8')]
parts.append('Apps.PropertyChanges=(function()\n'+(root/'src/Shared/PropertyChanges.lua').read_text(encoding='utf-8')+'\nend)().Main()\n')
parts.append('local module=(function()\n'+(root/'src/Apps/Explorer/Rendering/SelectionRenderer.lua').read_text(encoding='utf-8')+'\nend)()\nmodule.InitDeps({Main=Main,Apps=Apps,service=service})\nlocal Renderer=module.Main()\n')
parts.append((root/'tests/selection_renderer.spec.luau').read_text(encoding='utf-8'))
parts.append('local MaskModule=(function()\n'+(root/'src/Apps/Explorer/Rendering/SelectionGeometryMask.lua').read_text(encoding='utf-8')+'\nend)()\nMaskModule.InitDeps({Main=Main,service=service})\n')
parts.append((root/'tests/selection_geometry_mask.spec.luau').read_text(encoding='utf-8'))
parts.append((root/'tests/transform_session_mock.luau').read_text(encoding='utf-8'))
parts.append('local transformModule=(function()\n'+(root/'src/Apps/TransformTools/TransformSession.lua').read_text(encoding='utf-8')+'\nend)()\ntransformModule.InitDeps({Apps=Apps,Main=Main})\nlocal Transform=transformModule.Main()\n')
parts.append((root/'tests/selection_group_bounds.spec.luau').read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory(prefix='dex-selection-renderer-') as folder:
    harness=Path(folder)/'selection-renderer.luau'
    harness.write_text('\n'.join(parts),encoding='utf-8')
    subprocess.run([args.luau,str(harness)],check=True)
