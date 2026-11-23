from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'src/Apps/Console/Console.lua').read_text(encoding='utf-8')
fixture = (ROOT / 'tests/console_performance_fixture.luau').read_text(encoding='utf-8')
lib_source = (ROOT / 'src/Shared/Lib.lua').read_text(encoding='utf-8')
helpers = lib_source[lib_source.index('\tfunction Lib.NumberEnd'):lib_source.index('\tLib.CodeFrame =')]
fixture = fixture.replace('module.InitDeps(', 'do local Lib = lib\n' + helpers + 'end\nmodule.InitDeps(')
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / 'check.luau'
    script.write_text(fixture.replace('-- PRODUCTION', source), encoding='utf-8')
    subprocess.run([str(ROOT / '.tools/bin/luau.exe'), str(script)], check=True)
