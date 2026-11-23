"""Exercise the production prehighlighter against string-boundary regressions."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'src/Shared/Lib.lua').read_text()
start=source.index('\t\tlocal function lexLine(')
end=source.index('\n\t\tfuncs.HighlightLine =',start)
program='local Lib={} local funcs={} local tick=os.clock\n'+source[source.index('\tfunction Lib.NumberEnd'):source.index('\tLib.CodeFrame =')]+source[start:end]+'''
local function highlight(text)
 local cf={Lines=text:split("\\n")}
 funcs.PreHighlight(cf)
 return cf.PreHighlights
end
local h=highlight("warn(`couldn't register {result}`)\\nlocal after = true")
assert(h[1] and not h[2],"apostrophe in backticks must not color subsequent code")
local line = "`Score: {score + {bonus=3}.bonus}!`"
local interp=highlight(line)[1]
assert(interp[1][1]==18 and interp[9][1]==5 and not interp[10] and interp[#line-1][1]==18)
local nested=highlight("`{`inner {value}`} tail`")[1]
assert(nested[3][1]==18 and nested[10][1]==5 and not nested[11])
for _, literal in {"3.14",".25","1e-3","2E+5","0b1010_0101","0xFF_A0"} do
 assert(Lib.NumberEnd(literal.." + 2",1)==#literal)
end
assert(Lib.NumberEnd("1..2",1)==1)
local h2=highlight('local a = "unfinished\\nlocal b = true')
assert(h2[1] and not h2[2],"unfinished short strings recover at newline")
local h3=highlight("local a = [=[multiline\\ntext]=]\\nlocal b=true")
assert(h3[1] and h3[2] and not h3[3],"long string remains colored through its exact terminator")
local h4=highlight("-- `not a string\\nlocal b=true")
assert(h4[1] and not h4[2],"backticks inside comments cannot open a string")
local cf={PreHighlights={},ColoredLines={}}
local function same(a,b) for k,v in pairs(a) do if type(v)=="table" then assert(type(b[k])=="table") same(v,b[k]) else assert(v==b[k],"incremental token differs") end end for k in pairs(b) do assert(a[k]~=nil) end end
local variants={"local a=1\\n-- hello\\nreturn a", "local a=1\\n-- world\\nreturn a", "local a=1\\n--[=[hello\\nreturn a", "local a=1\\n--[=[hello]=]\\nreturn a", "local a=1\\nlocal s=`hi\\nthere`\\nreturn a", "local a=1\\nlocal s=`hi\\nnew`\\nreturn a", "local a=1\\nreturn a", "", "-- test"}
for _,text in ipairs(variants) do cf.Lines=text:split("\\n") funcs.PreHighlight(cf) same(cf.PreHighlights,highlight(text)) end
local function updateColors(edited, text)
 edited.Lines=text:split("\\n")
 funcs.PreHighlight(edited,2)
end
cf.Lines={"local plain = 1","return 2"}
funcs.PreHighlight(cf)
local prefixColor, changedColor = {}, {}
cf.ColoredLines[1], cf.ColoredLines[2] = prefixColor, changedColor
updateColors(cf, "local plain = 1\\nreturn 3")
assert(cf.ColoredLines[1] == prefixColor and cf.ColoredLines[2] == nil, "edits preserve ordinary prefix colors only")
updateColors(cf, "local plain = 1\\nreturn " .. string.char(92, 92))
cf.ColoredLines[2] = changedColor
updateColors(cf, "local plain = 1\\nreturn " .. string.rep(" ", 2))
assert(cf.ColoredLines[2] == nil, "different raw text invalidates colors even when normalized lexing text matches")
local edit={Lines={"local prefix = 1","local middle = 2","return 'tail'"},ColoredLines={}}
funcs.PreHighlight(edit)
for _,row in ipairs({ 2, 3, 1 }) do
 edit.Lines[row]..=" -- ÃƒÂ©"
 funcs.PreHighlight(edit,row)
 same(edit.PreHighlights,highlight(table.concat(edit.Lines,"\\n")))
end
local retained={"local start = 1","local change = 0", "return 'tail'"}
local tail={Lines=retained}
funcs.PreHighlight(tail)
local tailPaint={}
tail.ColoredLines[3]=tailPaint
retained[2]="local change = 2"
funcs.PreHighlight(tail,2)
assert(tail.ColoredLines[3]==tailPaint,"single-line edit preserves unaffected suffix colors")
retained[2]="local change = [=["
funcs.PreHighlight(tail,2)
assert(tail.ColoredLines[3]==nil,"opening a multiline string invalidates its continuation")
same(tail.PreHighlights,highlight(table.concat(retained,"\\n")))
retained[2]="local change = [=[ended]=]"
funcs.PreHighlight(tail,2)
same(tail.PreHighlights,highlight(table.concat(retained,"\\n")))
math.randomseed(4721)
local text="local v = [=[hello]=]\\n-- note\\nprint(`hi {v}`)\\nreturn v"
local inserts={"'",'"',"--","[=[", "]=]", "`", "\\n", "\\\\", "x", ""}
for step=1,500 do
 local at=math.random(1,#text+1) local remove=math.random(0,3)
 text=text:sub(1,at-1)..inserts[math.random(1,#inserts)]..text:sub(at+remove)
 cf.Lines=text:split("\\n")
 funcs.PreHighlight(cf) local ok,problem=pcall(same,cf.PreHighlights,highlight(text)) if not ok then print("FAIL STEP",step,string.format("%q",text)) error(problem) end
end
local fuzz={Lines=("local n = 1\\nreturn n -- [=[note\\ncontinuation]=]\\nreturn 'tail'"):split("\\n")}
funcs.PreHighlight(fuzz)
for step=1,500 do
 local row=math.random(1,#fuzz.Lines)
 local line=fuzz.Lines[row]
 local at=math.random(1,#line+1)
 local insert=inserts[math.random(1,#inserts)]:gsub("\\n","")
 fuzz.Lines[row]=line:sub(1,at-1)..insert..line:sub(at+math.random(0,3))
 funcs.PreHighlight(fuzz,row)
 same(fuzz.PreHighlights,highlight(table.concat(fuzz.Lines,"\\n")))
end
local large=string.rep("local n=1 -- comment\\n",10000)
local edited={Lines=(large.."return 0"):split("\\n")}
funcs.PreHighlight(edited)
local started=os.clock()
for i=1,10 do edited.Lines[5]="local n="..i.." -- comment" funcs.PreHighlight(edited,5) end
local incremental=os.clock()-started
started=os.clock() for i=1,10 do highlight(large.."return "..i) end local cold=os.clock()-started
print(string.format("10 near-top edits, 10k lines: fresh %.1f ms, incremental %.3f ms",cold*1000,incremental*1000))
print("PASS: production highlighter backticks/apostrophes, malformed short strings, long strings and comments")
'''
with tempfile.TemporaryDirectory(prefix='dex-highlight-') as folder:
 path=Path(folder)/'highlight.luau';path.write_text(program,encoding='utf-8')
 subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
