"""Exercise the real hosted bootstrap in Luau with an in-memory HTTP/filesystem.

Checks cold/warm startup, cross-release reuse, damaged cache, failed downloads,
and shared selection state across separately compiled modules.
"""
from pathlib import Path
import importlib.util
import json
import shutil
import subprocess
import zlib
import hashlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_runtime', ROOT/'scripts/package_runtime.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
manifest = package.package()
compiler = ROOT/'.tools/bin/luau-compile.exe'
luau = ROOT/'.tools/bin/luau.exe'
if not compiler.exists():
    compiler = shutil.which('luau-compile')
    luau = shutil.which('luau')
assert compiler and luau, 'Install the official Luau CLI with python build.py setup'
for path in manifest['files']:
    subprocess.run([str(compiler), str(package.OUT/path)], stdout=subprocess.DEVNULL, check=True)
subprocess.run([str(compiler),str(ROOT/'src/Runtime/Bootstrap.luau')],stdout=subprocess.DEVNULL,check=True)

def quote(value):
    return json.dumps(value, ensure_ascii=False)

sources = {
 'A.lua': 'nodes.shared={Name="Workspace"} selection={nodes.shared} return {value=nodes.shared}',
 'B.lua': 'assert(selection[1]==nodes.shared) return nodes.shared',
 'assets.lua': 'return {files={},version="test"}',
 'entry.lua': '''local paths={}
DexRuntime.OnModuleLoading=function(path) paths[#paths+1]=path end
assert(DexRuntime.ModulePaths.A=="A.lua")
local a=EmbeddedModules.A()
local b=EmbeddedModules.B()
assert(a.value==b,"separate chunks share the same nodes/selection")
assert(EmbeddedModules.A()==a,"require executes each module only once")
assert(table.concat(paths,",")=="A.lua,entry.lua,B.lua,entry.lua","module status reports exact paths, restores parent, and skips cached modules")
DexRuntime.OnModuleLoading=nil
return b''',
}
files = {p:{'bytes':len(s.encode()),'checksum':zlib.adler32(s.encode()),'sha256':hashlib.sha256(s.encode()).hexdigest()} for p,s in sources.items()}
sha256_by_source = {source: files[path]['sha256'] for path, source in sources.items()}
def table(value):
    if isinstance(value, dict):
        return '{'+','.join('['+quote(k)+']='+table(v) for k,v in value.items())+'}'
    if isinstance(value, str): return quote(value)
    return str(value)
fixture = {'schema':1,'release':'fixture1','files':files,'modules':{'A':'A.lua','B':'B.lua'},'entry':'entry.lua','assets':'assets.lua'}
program = '''local run=(function()\n'''+(ROOT/'src/Runtime/Bootstrap.luau').read_text(encoding='utf-8')+'''\nend)()
local manifest='''+table(fixture)+'''
local network='''+table(sources)+'''
local cache,requests={},{}
local total=0
workspace={Parent={}}
local decodedPacket,decodedPackets
game={GetService=function() return {JSONDecode=function(_,source) return decodedPackets and decodedPackets[source] or (source=="packet" and decodedPacket or manifest) end} end}
local broken
function game:HttpGet(url)
 total+=1
 local path=url:sub(#"https://fixture/"+1)
 requests[path]=(requests[path] or 0)+1
 if path=="manifest.json" then return "{}" end
 if path==broken then error("simulated HTTP outage") end
 return assert(network[path],"unknown URL: "..path)
end
readfile=function(path) return assert(cache[path],"missing") end
writefile=function(path,data) cache[path]=data end
makefolder=function() end
task={spawn=function(fn) fn() end,wait=function() error("fixture should complete synchronously") end}
local runtimeGlobals={}
getgenv=function() return runtimeGlobals end
local first=run("https://fixture/")
assert(first.Name=="Workspace" and total==5,"cold boot downloads manifest and four files")
local before=total
assert(run("https://fixture/").Name=="Workspace")
assert(total==before+1,"warm boot only fetches manifest")
assert(runtimeGlobals.DexPlusRuntimeStats.CacheHits==4 and runtimeGlobals.DexPlusRuntimeStats.NetworkRequests==1)
manifest.release="fixture2"
before=total run("https://fixture/")
assert(total==before+1,"unchanged modules survive a release change")
local hashes='''+table(sha256_by_source)+'''
local probe="Dex Explorer\\226\\128\\148Luau"
local knownDigest="aa7b41355423929a52aec49bf1691136112f9a3aa0dde532217e55fc5b256d6b"
local nullInputs=0
crypt={hash=function(source,algorithm)
 assert(algorithm=="sha256")
 if source:find("\\0",1,true) then
  nullInputs+=1
  return string.rep("0",64)
 end
 if source==probe then return knownDigest:upper() end
 local hash=hashes[source]
 if not hash then error("unsupported input") end
 return hash:upper()
end}
before=total run("https://fixture/")
assert(total==before+1 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==4,"native SHA-256 validates every cached file")
local bEntry=manifest.files["B.lua"]
local bDigest=bEntry.sha256
local originalB, originalBytes, originalChecksum=network["B.lua"],bEntry.bytes,bEntry.checksum
local binarySource=originalB.." -- \\0"
network["B.lua"]=binarySource
bEntry.bytes=#binarySource
bEntry.sha256=string.rep("a",64)
local a,b=1,0
for i=1,#binarySource do
 a=(a+binarySource:byte(i))%65521
 b=(b+a)%65521
end
bEntry.checksum=b*65536+a
before=total run("https://fixture/")
assert(total==before+2 and nullInputs==0 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==3,
 "text uses native SHA-256 while sources containing null bytes go straight to Adler-32")
network["B.lua"],bEntry.bytes,bEntry.checksum=originalB,originalBytes,originalChecksum
bEntry.sha256=nil
before=total run("https://fixture/")
assert(total==before+2 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==3,"entries without a cache identity still use Adler-32")
bEntry.sha256=bDigest
local native=crypt.hash
crypt.hash=function(source,algorithm)
 if source==network["B.lua"] then error("provider failure") end
 return native(source,algorithm)
end
before=total run("https://fixture/")
assert(total==before+1 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==3,"a native provider failure falls back per entry")
crypt.hash=native
for path in pairs(cache) do
 if path:find(bEntry.sha256,1,true) then cache[path]=string.rep("x",bEntry.bytes) end
end
before=total run("https://fixture/")
assert(total==before+2 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==4,"same-size corrupted cache is repaired")
crypt.hash=function() return string.rep("0",64) end
before=total run("https://fixture/")
assert(total==before+1 and runtimeGlobals.DexPlusRuntimeStats.NativeIntegrityChecks==0,"unverified hash providers never replace Adler-32")
crypt=nil
print("PASS: verified native SHA-256, uppercase digests, same-size cache damage and legacy/error fallbacks")
for path in pairs(cache) do if path:find(manifest.files["A.lua"].sha256,1,true) then cache[path]="damaged" end end
before=total run("https://fixture/")
assert(total==before+2,"damaged cache refetches only the affected module")
cache={} broken="B.lua"
local ok,problem=pcall(run,"https://fixture/")
assert(not ok and tostring(problem):find("B.lua",1,true),"download failure identifies module and aborts boot")
broken=nil network["B.lua"]="return {}"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and tostring(problem):find("match release",1,true),"wrong release bytes cannot execute")
print("PASS: hosted cold/warm cache, release reuse, damaged-cache repair, shared state, memoized modules and failed-download rejection")
-- The same bootstrap consumes batch transport without changing module factories.
network["B.lua"]="assert(selection[1]==nodes.shared) return nodes.shared"
manifest.bundle={path="runtime.json",bytes=6,checksum=144048761}
decodedPacket={release=manifest.release,files=network}
network["runtime.json"]="packet"
cache={} before=total
assert(run("https://fixture/").Name=="Workspace")
assert(total==before+2,"batch cold boot uses manifest and one packet")
assert(runtimeGlobals.DexPlusRuntimeStats.BundleRequests==1)
before=total run("https://fixture/")
assert(total==before+1 and runtimeGlobals.DexPlusRuntimeStats.BundleRequests==0,"warm cache never downloads the packet")
for path in pairs(cache) do if path:find(manifest.files["A.lua"].sha256,1,true) then cache[path]="damaged" end end
before=total run("https://fixture/")
assert(total==before+2 and runtimeGlobals.DexPlusRuntimeStats.BundleRequests==0,"one corrupt file is repaired selectively")
local packetBytes=manifest.bundle.bytes
manifest.bundle.bytes=100000
for path in pairs(cache) do
 if path:find(manifest.files["A.lua"].sha256,1,true) or path:find(manifest.files["B.lua"].sha256,1,true) then cache[path]="damaged" end
end
before=total run("https://fixture/")
assert(total==before+3 and runtimeGlobals.DexPlusRuntimeStats.BundleRequests==0,"small updates avoid downloading a much larger packet")
manifest.bundle.bytes=packetBytes
cache={} decodedPacket.release="wrong"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and tostring(problem):find("release packet",1,true),"wrong packet release rejected")
decodedPacket.release=manifest.release
decodedPacket.files["B.lua"]="return {}"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and tostring(problem):find("batch entry",1,true),"wrong packet module bytes rejected")
assert(next(cache)==nil,"invalid packet writes no partial cache")
network["runtime.json"]="damage"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and tostring(problem):find("batch download",1,true),"damaged transport rejected")
print("PASS: cold batch transport, warm reuse, selective repair and atomic rejection of damaged/wrong-release packets")
network["B.lua"]="assert(selection[1]==nodes.shared) return nodes.shared"
network["runtime-0.json"],network["runtime-1.json"]="part-0","part-1"
manifest.bundles={
 {path="runtime-0.json",paths={"A.lua","assets.lua"},bytes=6,checksum=137953813},
 {path="runtime-1.json",paths={"B.lua","entry.lua"},bytes=6,checksum=138019350},
}
decodedPackets={
 ["part-0"]={release=manifest.release,files={["A.lua"]=network["A.lua"],["assets.lua"]=network["assets.lua"]}},
 ["part-1"]={release=manifest.release,files={["B.lua"]=network["B.lua"],["entry.lua"]=network["entry.lua"]}},
}
cache={} before=total
assert(run("https://fixture/").Name=="Workspace")
assert(total==before+3 and runtimeGlobals.DexPlusRuntimeStats.BundleRequests==2,"balanced packets merge into one validated source set")
before=total run("https://fixture/")
assert(total==before+1,"warm load never requests balanced packets")
cache={} decodedPackets["part-1"].files["B.lua"]="return {}"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and next(cache)==nil,"one invalid part rejects every uncommitted part")
decodedPackets["part-1"].files["B.lua"]=network["B.lua"]
broken="runtime-1.json"
ok,problem=pcall(run,"https://fixture/")
assert(not ok and next(cache)==nil,"one failed request rejects partial packet state")
print("PASS: balanced-packet merge, warm reuse and atomic rejection across concurrent requests")


'''
target = ROOT/'.build/runtime-checks.luau'
target.parent.mkdir(exist_ok=True)
target.write_text(program,encoding='utf-8')
subprocess.run([str(luau),str(target)],check=True)
print(f"PASS: all {len(manifest['files'])} hosted source files compile independently")

editor_modules = ["EditorParserCore", "EditorParser", "EditorSymbols", "EditorFolding"]
editor_runner = ["local Apps = {}"]
for module in editor_modules:
    module_path = manifest["modules"][module].removesuffix(".lua")
    editor_runner.append(f'Apps.{module} = require("../dist/github/{module_path}").Main(Apps)')
editor_runner.append((ROOT / "tests/editor_parser.spec.luau").read_text(encoding="utf-8"))
editor_target = ROOT / ".build/packaged-editor-parser.luau"
editor_target.write_text("\n".join(editor_runner), encoding="utf-8")
subprocess.run([str(luau), str(editor_target)], check=True)
print("PASS: parser integration against hosted modules named in the release manifest")

# Missing readfile() may return nil successfully on some executor hosts.
# Exercise the generated public entry, not only its downstream bootstrap.
entry_source = package.loader('0'*40)
cases = {
    'nil': 'return nil',
    'false': 'return false',
    'table': 'return {}',
    'empty': 'return ""',
    'invalid': 'return "this is invalid luau"',
    'throw': 'error("missing file")',
    'valid': 'return "return function(base) return base end"',
}
for label, body in cases.items():
    program = 'local downloads=0\nreadfile=function() '+body+' end\n'
    program += 'game={HttpGet=function() downloads+=1 return "return function(base) return base end" end}\n'
    program += 'local result=(function()\n'+entry_source+'\nend)()\n'
    program += 'assert(type(result)=="string" and result:find("raw.githubusercontent.com",1,true))\n'
    program += 'assert(downloads=='+str(0 if label=='valid' else 1)+',"cache case: '+label+'")\n'
    target.write_text(program,encoding='utf-8')
    subprocess.run([str(luau),str(target)],check=True)
print('PASS: public loader handles nil/false/table/empty/invalid/missing cache and reuses valid cached source')

# Test the production package loader, separately from the optional offline bundle.
packet_sources={path:(package.OUT/path).read_text(encoding='utf-8') for path in manifest['files'] if path.startswith('src/Packages/React/') and not path.endswith('/Loader.luau')}
program=(ROOT/'tests/roblox_mock.luau').read_text(encoding='utf-8')+'\n'+(ROOT/'tests/react_host_mock.luau').read_text(encoding='utf-8')
program+='\nlocal packetSources='+table(packet_sources)+'\nlocal packetLoads={}\nlocal DexRuntime={}\n'
program+='function DexRuntime.Require(path) packetLoads[path]=(packetLoads[path] or 0)+1 return assert(loadstring(assert(packetSources[path],path)))() end\n'
program+='local ReactVendor=(function()\n'+(ROOT/'src/Packages/React/Loader.luau').read_text(encoding='utf-8')+'\nend)()\n'
program+='local React=ReactVendor.require("react") local Roblox=ReactVendor.require("react-roblox")\n'
program+='local parent=Instance.new("Frame",game) local root=Roblox.createRoot(parent)\n'
program+='Roblox.flushSync(function() root:render(React.createElement("TextLabel",{Name="PackageTest",Text="Pinned packages work"})) end)\n'
program+='assert(parent.PackageTest.Text=="Pinned packages work")\nfor path,count in pairs(packetLoads) do assert(count==1,"package loaded twice: "..path) end\n'
program+='Roblox.flushSync(function() root:unmount() end)\nprint("PASS: production modular React graph, aliases, single package execution and real ReactRoblox host mount")\n'
target.write_text(program,encoding='utf-8')
subprocess.run([str(luau),str(target)],check=True)
