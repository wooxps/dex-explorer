"""Measure a fresh editor index and a same-revision read using the local Luau VM."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--base", default="68ccc00")
parser.add_argument("--luau", type=Path, required=True)
args = parser.parse_args()
build = ROOT / ".build"
build.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=build) as directory:
    work = Path(directory)
    names = ("EditorDefinitions", "EditorSymbols")
    for name in names:
        path = f"src/Apps/ScriptViewer/Services/{name}.lua"
        (work / f"{name}.luau").write_bytes(subprocess.check_output(["git", "show", f"{args.base}:{path}"], cwd=ROOT))
    for label in ("before", "after"):
        prefix = "./" if label == "before" else "../../src/Apps/ScriptViewer/Services/"
        setup = 'local apps = {}\n'
        if label == "after":
            setup += 'local service = require("../../src/Apps/ScriptViewer/Services/EditorParser")\n'
            setup += 'local core = require("../../src/Packages/LuauParser/EditorParserCore").Main()\n'
        for name in names:
            setup += f'local {name} = require("{prefix}{name}")\n'
        body = r"""
for _, count in {200, 2000} do
    local lines = table.create(count)
    for i = 1, count do lines[i] = ("local value%d: number = %d"):format(i,i) end
    local source = table.concat(lines, "\n")
    local times, memory, warm, slices = {}, {}, {}, {}
    for sample = 1, 13 do
        RESET
        local symbols = EditorSymbols.Main(apps).New()
        local defs = EditorDefinitions.Main(apps)
        collectgarbage()
        local baseline = gcinfo()
        local started = os.clock()
        local latest, longest = started, 0
        local function checkpoint()
            local now = os.clock()
            longest = math.max(longest, now - latest)
            latest = now
            return true
        end
        symbols:Index(source, checkpoint)
        local tokens = defs.Tokenize(source, checkpoint)
        checkpoint()
        times[sample] = (latest - started) * 1000
        slices[sample] = longest * 1000
        collectgarbage()
        memory[sample] = gcinfo() - baseline
        assert(#symbols.Declarations == count and #tokens > count)
        started = os.clock()
        symbols:Index(source)
        local again = defs.Tokenize(source)
        warm[sample] = (os.clock() - started) * 1000
        assert(#again == #tokens)
    end
    for _, values in {times, memory, warm, slices} do table.sort(values) end
    print(string.format("%s %d lines | cold %.2f ms | retained %.0f KiB | warm %.3f ms | longest checkpoint gap %.2f ms (median run)",
        "LABEL", count, times[7], memory[7], warm[7], slices[7]))
end
"""
        reset = 'apps.EditorParserCore = core\napps.EditorParser = service.Main(apps)' if label == "after" else ""
        script = work / "bench.luau"
        script.write_text(setup + body.replace("RESET", reset).replace("LABEL", label), encoding="utf8")
        subprocess.run([args.luau.resolve(), script], check=True)
