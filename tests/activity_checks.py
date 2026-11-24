import argparse
from pathlib import Path
import subprocess
import tempfile
cli=argparse.ArgumentParser()
cli.add_argument('--luau',default='luau')
args=cli.parse_args()
root=Path(__file__).resolve().parents[1]
parts=[(root/'tests/roblox_mock.luau').read_text(),(root/'tests/preview_mock.luau').read_text(),'service.RunService.Heartbeat=signal() local activityEnv={}']
for name in ['ActivitySession','ActivityViewer']:
 source=next((root/'src').rglob(name+'.lua')).read_text()
 parts.append('do local control=(function()\n'+source+'\nend)() if control.InitDeps then control.InitDeps({Main=Main,Lib=Lib,Apps=Apps,API=API,service=service,env=activityEnv}) end Apps.'+name+'=control.Main() end')
parts.append((root/'tests/activity.spec.luau').read_text())
with tempfile.TemporaryDirectory() as folder:
 path=Path(folder)/'activity.luau'
 path.write_text('\n'.join(parts),encoding='utf-8')
 subprocess.run([args.luau,str(path)],check=True)
