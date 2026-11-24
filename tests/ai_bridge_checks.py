"""Exercise the real bridge adapters against shared Roblox doubles and Dex services."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
parts = [(root / 'tests' / name).read_text(encoding='utf-8') for name in [
    'roblox_mock.luau', 'transform_session_mock.luau', 'ai_bridge_mock.luau']]
modules = [
    ('History', 'src/Shared/History.lua'),
    ('SelectionService', 'src/Apps/Explorer/Services/SelectionService.lua'),
    ('EditingService', 'src/Apps/Explorer/Services/EditingService.lua'),
    ('ReflectionService', 'src/Apps/Explorer/Services/ReflectionService.lua'),
    ('TransformSession', 'src/Apps/TransformTools/TransformSession.lua'),
    ('BridgeRegistry', 'src/Apps/AIBridge/Services/BridgeRegistry.lua'),
    ('BridgeValueCodec', 'src/Apps/AIBridge/Services/BridgeValueCodec.lua'),
    ('ReferenceScan', 'src/Apps/ReferenceFinder/ReferenceScan.lua'),
    ('ActivitySession', 'src/Apps/ActivityViewer/ActivitySession.lua'),
    ('BridgeExtraCommands', 'src/Apps/AIBridge/Services/BridgeExtraCommands.lua'),
    ('BridgeRemoteCommands', 'src/Apps/AIBridge/Services/BridgeRemoteCommands.lua'),
    ('BridgeLogCommands', 'src/Apps/AIBridge/Services/BridgeLogCommands.lua'),
    ('BridgeCaptureCommands', 'src/Apps/AIBridge/Services/BridgeCaptureCommands.lua'),
    ('BridgeQueryCommands', 'src/Apps/AIBridge/Services/BridgeQueryCommands.lua'),
    ('BridgeSpatialCommands', 'src/Apps/AIBridge/Services/BridgeSpatialCommands.lua'),
    ('BridgeInspectionCommands', 'src/Apps/AIBridge/Services/BridgeInspectionCommands.lua'),
    ('BridgeComparisonCommands', 'src/Apps/AIBridge/Services/BridgeComparisonCommands.lua'),
    ('BridgeUIDiagnostics', 'src/Apps/AIBridge/Services/BridgeUIDiagnostics.lua'),
    ('BridgeRuntimeDiagnostics', 'src/Apps/AIBridge/Services/BridgeRuntimeDiagnostics.lua'),
    ('BridgeConditions', 'src/Apps/AIBridge/Services/BridgeConditions.lua'),
    ('BridgeTestCommands', 'src/Apps/AIBridge/Services/BridgeTestCommands.lua'),
    ('BridgeCommandRouter', 'src/Apps/AIBridge/Services/BridgeCommandRouter.lua'),
]
for name, path in modules:
    parts.append('do local control=(function()\n' + (root/path).read_text(encoding='utf-8') +
                 '\nend)()\nif control.InitDeps then control.InitDeps({Apps=Apps,Main=Main,Lib=Lib,service=service,API=API,RMD=RMD,Settings=Settings}) end Apps.' + name + '=control.Main() end\n')
parts.append((root/'tests/ai_bridge.spec.luau').read_text(encoding='utf-8'))
parts.append((root/'tests/ai_bridge_extras.spec.luau').read_text(encoding='utf-8'))
parts.append((root/'tests/ai_bridge_remotes.spec.luau').read_text(encoding='utf-8'))
parts.append((root/'tests/ai_bridge_captures.spec.luau').read_text(encoding='utf-8'))
parts.append('local StudioImporter=(function()\n'+(root/'mcp/static/StudioCaptureImporter.luau').read_text(encoding='utf-8')+'\nend)()\n')
parts.append((root/'tests/ai_bridge_importer.spec.luau').read_text(encoding='utf-8'))
parts.append((root/'tests/ai_bridge_logs.spec.luau').read_text(encoding='utf-8'))
for suite in ['ai_bridge_queries.spec.luau','ai_bridge_spatial.spec.luau','ai_bridge_inspection.spec.luau','ai_bridge_comparison.spec.luau','ai_bridge_ui_diagnostics.spec.luau','ai_bridge_runtime_diagnostics.spec.luau','ai_bridge_testing.spec.luau']:
    parts.append((root/'tests'/suite).read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory(prefix='dex-ai-bridge-') as folder:
    harness = Path(folder)/'bridge.luau'
    harness.write_text('\n'.join(parts), encoding='utf-8')
    subprocess.run([args.luau, str(harness)], check=True)
