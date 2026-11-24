"""Exercise real bridge transport and composed UI against Roblox doubles."""
import argparse
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
parts = [(root/'tests/roblox_mock.luau').read_text(encoding='utf-8')]
parts.append('local exported=(function()\n'+(root/'src/Apps/AIBridge/Services/BridgeClient.lua').read_text(encoding='utf-8')+'\nend)()\nexported.InitDeps({Apps={},Main={},service=service,env={}})\nlocal Client=exported.Main()\n')
parts.append((root/'tests/bridge_client.spec.luau').read_text(encoding='utf-8'))
parts.append("local copiedText, clipboardText\nlocal viewEnv={setclipboard=function(value) copiedText=value end,getclipboard=function() return clipboardText end}\n")
for name in ['BridgeUI','BridgeConnectionView','BridgeSetupView','BridgeActivityView','BridgeCommandCatalog','BridgeCommandsView','AIBridge']:
    path=next((root/'src/Apps/AIBridge').rglob(name+'.lua'))
    parts.append('do local control=(function()\n'+path.read_text(encoding='utf-8')+'\nend)()\nif control.InitDeps then control.InitDeps({Apps=Apps,Main=Main,Lib=Lib,Settings=Settings,service=service,env=viewEnv,createSimple=createSimple}) end Apps.'+name+'=control.Main() end\n')
parts.append((root/'tests/bridge_ui.spec.luau').read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory(prefix='dex-bridge-client-') as folder:
    harness=Path(folder)/'bridge-client.luau'
    harness.write_text('\n'.join(parts),encoding='utf-8')
    subprocess.run([args.luau,str(harness)],check=True)
