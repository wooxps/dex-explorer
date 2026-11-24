"""Exercise the plugin action host with the standard mock Roblox host."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--luau", default="luau")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
mock = (root / "tests/roblox_mock.luau").read_text(encoding="utf-8")
source = (root / "src/Apps/Plugins/PluginActions.lua").read_text(encoding="utf-8")
spec = (root / "tests/plugin_actions.spec.luau").read_text(encoding="utf-8")
with tempfile.TemporaryDirectory(prefix="dex-plugin-actions-") as temp:
    script = Path(temp) / "check.luau"
    script.write_text(
        f"{mock}\nlocal control = (function()\n{source}\nend)()\n"
        "if control.InitDeps then control.InitDeps({ Apps = Apps, Main = Main, Lib = Lib, service = service }) end\n"
        f"Apps.PluginActions = control.Main()\n{spec}",
        encoding="utf-8",
    )
    subprocess.run([args.luau, str(script)], check=True)
