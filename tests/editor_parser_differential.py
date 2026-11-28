"""Compare default-dialect acceptance with luau-compile on official parser fixtures and Dex sources."""
import argparse
import ast
import re
import subprocess
import tempfile
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
arguments = argparse.ArgumentParser()
arguments.add_argument("official_tests", type=Path, help="Path to official Luau tests/Parser.test.cpp")
arguments.add_argument("--luau", type=Path, required=True)
arguments.add_argument("--compiler", type=Path, required=True)
options = arguments.parse_args()
text = options.official_tests.read_text(encoding="utf-8")
cases = {}
for match in re.finditer(r'R"\((.*?)\)"|\bparse\(\s*("(?:\\.|[^"\\])*")\s*\)', text, re.S):
    source = match[1] if match[1] is not None else ast.literal_eval(match[2])
    cases[f"official:{text.count(chr(10), 0, match.start()) + 1}"] = source
for path in [ROOT / "main.lua", *sorted((ROOT / "src").rglob("*.lua"))]:
    cases[path.relative_to(ROOT).as_posix()] = path.read_text(encoding="utf-8")
build = ROOT / ".build"
build.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=build) as scratch:
    work = Path(scratch)
    runner = [
        'local core = require("../../src/Packages/LuauParser/EditorParserCore").Main()',
        'local parser = require("../../src/Apps/ScriptViewer/Services/EditorParser").Main({EditorParserCore = core})',
        'local function check(index, source)',
        '    local result = parser.Parse(source).Diagnostics',
        '    print(index, result.Passed)',
        '    for _, err in result.Errors do print("E", index, err.Line, err.Column) end',
        'end',
    ]
    paths = []
    for index, source in enumerate(cases.values()):
        path = work / f"case{index}.luau"
        path.write_bytes(source.encode())
        paths.append(path.name)
        # Quoted byte escapes preserve initial newlines and arbitrary bytes in fixtures.
        quoted = '"' + "".join(chr(b) if 32 <= b < 127 and b not in (34, 92) else f"\\{b:03d}" for b in source.encode()) + '"'
        runner.append(f"check({index}, {quoted})")
    script = work / "cases.luau"
    script.write_text("\n".join(runner), encoding="utf-8")
    actual = subprocess.run([options.luau.resolve(), script], capture_output=True, text=True, check=True)
    positions = defaultdict(list)
    expected_positions = defaultdict(list)
    verdicts = {}
    for row in actual.stdout.splitlines():
        fields = row.split()
        if fields[0] == "E":
            positions[int(fields[1])].append((int(fields[2]), int(fields[3])))
        else:
            verdicts[int(fields[0])] = fields[1] == "true"
    assert len(verdicts) == len(paths)
    failures = set()
    for start in range(0, len(paths), 80):
        chunk = paths[start:start + 80]
        oracle = subprocess.run([options.compiler.resolve(), "--only-parse", *chunk], cwd=work, capture_output=True)
        errors = set(re.findall(rb"case(\d+)\.luau\(", oracle.stderr))
        if oracle.returncode and not errors:
            raise RuntimeError(oracle.stderr.decode(errors="replace"))
        failures.update(map(int, errors))
        for index, line, column in re.findall(rb"case(\d+)\.luau\((\d+),(\d+)\): SyntaxError:", oracle.stderr):
            expected_positions[int(index)].append((int(line), int(column)))
    mismatches = [name for i, name in enumerate(cases) if verdicts[i] != (i not in failures)]
    print(f"{len(cases)} cases, {len(failures)} rejected by compiler, {len(mismatches)} differences")
    for name in mismatches:
        print(name, repr(cases[name][:150]))
    range_mismatches = [name for i, name in enumerate(cases) if positions[i] != expected_positions[i]]
    print(f"{sum(map(len, expected_positions.values()))} official diagnostic starts; {len(range_mismatches)} cases differ")
    for i, name in enumerate(cases):
        if name in range_mismatches:
            print(name, positions[i][:6], expected_positions[i][:6])
    raise SystemExit(bool(mismatches or range_mismatches))
