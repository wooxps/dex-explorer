"""Exercise the real global scanner with bounded source/editor adapters."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
program='''local Apps={} local Main={Alive=true,AddCleanup=function() end}
local task={spawn=function(fn) fn() end,wait=function() end}
local function typeof(x) return type(x) end
local hostEnv={decompile=function() error("unexpected native decompile") end}
'''
for name in ['EditorFindModel','EditorGlobalSearch']:
    source=next((root/'src').rglob(name+'.lua')).read_text()
    program+='do local c=(function()\n'+source+'\nend)();if c.InitDeps then c.InitDeps({Apps=Apps,Main=Main,env=hostEnv}) end;Apps.'+name+'=c.Main() end\n'
program+=r'''
local function object(name,source,parent)
 return {Name=name,ClassName="ModuleScript",Source=source,Parent=parent,GetFullName=function(self) return "game."..self.Name end}
end
local a=object("A","foo\nxx foo\nfoox")
local b=object("B","foo")
local c=object("C",nil)
setmetatable(c,{__index=function(_,key) if key=="Source" then error("protected") end end})
local parent={Name="Folder"} b.Parent=parent
local nodes={[a]={},[b]={},[c]={}}
Apps.Explorer={GetNodes=function() return nodes end,Selection={List={{Obj=parent}}}}
local cachedSources={}
Apps.ReferenceSource={Peek=function(object) return cachedSources[object] end,Store=function(object,source) cachedSources[object]={Source=source} end}
local documents={}
local s=Apps.EditorGlobalSearch.Create({GetDocuments=function() return documents end})
s:Start("foo",{WholeWord=true})
assert(not s.State.Searching and s.State.MatchCount==3 and #s.State.Groups==2 and s.State.Unavailable==1)
s:Cancel()
assert(not s.State.Cancelled and s.State.MatchCount==3,"closing a finished search retains its results without claiming cancellation")
assert(s.State.Groups[1].Matches[2].Line==2 and s.State.Groups[1].Matches[2].Column==4)
assert(s.State.Groups[1].Matches[2].Text=="xx foo")
local normalized=object("Normalized","local x = 1\r\n\tfoo")
nodes={[normalized]={}}
local normalizedEdit
local normalizedSearch=Apps.EditorGlobalSearch.Create({NormalizeSource=function(source)
 return (source:gsub("\r\n","\n"):gsub("\t","    "))
end,Apply=function(_, text) normalizedEdit=text end})
normalizedSearch:Start("foo",{})
local normalizedGroup=normalizedSearch.State.Groups[1]
assert(normalizedGroup.Source=="local x = 1\n    foo" and normalizedGroup.Matches[1].Column==5)
assert(normalizedSearch:Replace(normalizedGroup,normalizedGroup.Matches[1],"bar").Count==1)
assert(normalizedEdit=="local x = 1\n    bar","navigation and replacement use editor offsets for CRLF and tabs")
nodes={[a]={},[b]={},[c]={}}
s:Start("foo",{Scope="Selection"}) assert(s.State.MatchCount==1 and s.State.Groups[1].Object==b)
documents={{id=a,title="A",text="Unsaved only",script=a}}
s:Start("Unsaved",{Scope="Open"}) assert(s.State.MatchCount==1 and s.State.Groups[1].SourceKind=="Buffer")
s:Start("foo",{}) assert(s.State.MatchCount==1,"open unsaved text takes precedence over replicated source")
documents={} Apps.EditorGlobalSearch.MaxResults=2
s:Start("foo",{}) assert(s.State.MatchCount==2 and s.State.Truncated)
Apps.EditorGlobalSearch.MaxResults=20000 Apps.EditorGlobalSearch.MaxRetainedBytes=2
s:Start("foo",{}) assert(s.State.Truncated and s.State.MatchCount==0)
Apps.EditorGlobalSearch.MaxRetainedBytes=32*1024*1024
local pending
local delayed=Apps.EditorGlobalSearch.Create({Spawn=function(fn) pending=fn end})
delayed:Start("foo",{}) delayed:Cancel() pending()
assert(delayed.State.Cancelled and delayed.State.Scanned==0)
delayed:Start("foo",{}) delayed:Destroy() pending() assert(#delayed.State.Groups==0)
local edits={} local current={}
local replace=Apps.EditorGlobalSearch.Create({GetDocuments=function() return {} end,ReadCurrent=function(group) return current[group.Object] or group.Source end,Apply=function(group,text) edits[#edits+1]={group,text} current[group.Object]=text return true end})
replace:Start("foo",{WholeWord=true})
local staleGroup=replace.State.Groups[1]
replace:Start("foo",{WholeWord=true})
local freshGroup=replace.State.Groups[1]
assert(replace:Replace(staleGroup,staleGroup.Matches[1],"bar").Error and #edits==0,"a stale group cannot change the current search")
assert(replace:Replace(freshGroup,staleGroup.Matches[1],"bar").Error and #edits==0,"a match must belong to the current group")
assert(replace:ReplaceAll("bar",{freshGroup,staleGroup}).Error and #edits==0,"a mixed replacement cannot partially apply stale groups")
assert(replace:Replace(freshGroup,nil,"bar").Error and #edits==0,"a missing match cannot replace the whole file")
current[b]="Changed elsewhere"
local result=replace:ReplaceAll("bar") assert(result.Error and #edits==0,"all sources validated before any edit")
current[b]=nil
result=replace:ReplaceAll("bar") assert(result.Count==3 and #edits==2)
assert(current[a]=="bar\nxx bar\nfoox" and current[b]=="bar")
assert(replace:ReplaceAll("baz").Error,"old matches cannot be applied twice")
local cached=object("Cached","") nodes={[cached]={}}
Apps.ReferenceSource.Peek=function() return {Source="cached foo"} end
s:Start("foo",{}) assert(s.State.MatchCount==1 and s.State.Groups[1].SourceKind=="Decompiler","cached decompiled text beats empty executor Source")
Apps.ReferenceSource.Peek=function(object) return cachedSources[object] end
local unicode=object("Unicode",string.rep("é",80).."foo"..string.rep("é",120)) nodes={[unicode]={}}
s:Start("foo",{MatchCase=true})
local match=s.State.Groups[1].Matches[1]
assert(utf8.len(match.Text)~=nil and match.Text:sub(match.SnippetColumn,match.SnippetColumn+2)=="foo","snippet clipping preserves UTF-8 and byte offsets")
local dense=object("Dense",string.rep("foo ",30000)) nodes={[dense]={}}
local started=os.clock() s:Start("foo",{})
assert(s.State.MatchCount==20000 and s.State.Truncated and #s.State.Groups[1].Matches==20000)
print("dense single-line 20k matches ms",(os.clock()-started)*1000)
nodes={} for i=1,600 do nodes[object("Snapshot"..i,"foo")]={} end
local changed=false local ticks=0
local snapshot=Apps.EditorGlobalSearch.Create({Clock=function() ticks+=.01 return ticks end,Wait=function() if not changed then changed=true table.clear(nodes) nodes[object("Late","foo")]={} end end})
snapshot:Start("foo",{}) assert(changed and not snapshot.State.Error and snapshot.State.Scanned==600,"hierarchy mutation cannot corrupt a suspended node iterator")
local denied=object("Denied",nil) setmetatable(denied,getmetatable(c))
nodes={[c]={},[denied]={}}
local now,calls=0,0
hostEnv.decompile=function() calls+=1 now+=.03 return "foo" end
local native=Apps.EditorGlobalSearch.Create({Clock=function() return now end,Wait=function() end})
native:Start("foo",{}) assert(calls==0,"native decompilation requires opt-in")
native:Start("foo",{IncludeDecompiled=true}) assert(calls==2 and native.State.Unavailable==0 and native.State.MatchCount==2,"slow reads do not skip later scripts")
native:Start("foo",{IncludeDecompiled=true}) assert(calls==2 and native.State.MatchCount==2,"warm search does not decompile again")
-- Catalog acquisition survives a slow native read, and warm queries never
-- call the reader again for indexed scripts, even after the query changes.
nodes={}
for index=1,30000 do nodes[object("Catalog"..index,nil)]={} end
local reads=0
Apps.ReferenceSource.PeekCompiled=function() return nil end
Apps.ReferenceSource.Read=function(_,check,onRead,pass)
 assert(pass and pass.ParseCheckpoint==check)
 reads+=1
 onRead(reads==19 and .15 or .0001)
 return {Literals={"commonKey","sharedValue"}}
end
local catalog=Apps.EditorGlobalSearch.Create()
catalog:Start("missing",{IncludeCompiled=true})
assert(not catalog.State.Error and catalog.State.BytecodePaused and reads==19)
assert(catalog.State.CompiledChecked==19 and catalog.State.Pending==29981 and catalog.State.Unavailable==0)
catalog:Start("missing",{IncludeCompiled=true})
assert(not catalog.State.Error and catalog.State.CompiledChecked==30000 and reads==30000,"resume acquires remaining scripts once")
local warmStart=os.clock()
catalog:Start("sharedValue",{IncludeCompiled=true,CachedCompiledOnly=true})
assert(not catalog.State.Error and catalog.State.MatchCount==20000 and catalog.State.Truncated and reads==30000)
print("warm catalog 20k capped results ms",(os.clock()-warmStart)*1000)
warmStart=os.clock()
catalog:Start("differentMissingTerm",{IncludeCompiled=true,CachedCompiledOnly=true})
assert(catalog.State.CompiledChecked==30000 and reads==30000 and not catalog.State.Error)
print("warm catalog 30k no-hit query ms",(os.clock()-warmStart)*1000)
catalog:Destroy()
local function runtimeFunction() error("Search must never execute a game function") end
setfenv(runtimeFunction,{script=c})
nodes={[c]={},[denied]={}}
cachedSources[c]=nil cachedSources[denied]=nil
local discoveries=0
hostEnv.filtergc=function(kind,options)
 assert(kind=="function" and options.IgnoreExecutor and options.Constants==nil)
 discoveries+=1
 return {runtimeFunction}
end
hostEnv.getconstants=function(fn) assert(fn==runtimeFunction) return {"FindRuntimeName"} end
local runtime=Apps.EditorGlobalSearch.Create()
runtime:Start("Runtime",{IncludeCompiled=true,CachedCompiledOnly=true,IncludeRuntime=true})
assert(not runtime.State.Error and runtime.State.RuntimeChecked==1 and runtime.State.RuntimeMatches==1 and runtime.State.Pending==1)
assert(runtime.State.Groups[1].Runtime and runtime.State.Groups[1].Object==c and reads==30000)
runtime:Start("Name",{IncludeCompiled=true,CachedCompiledOnly=true})
assert(runtime.State.RuntimeMatches==1 and discoveries==1 and reads==30000,"new terms reuse runtime catalog without native calls")
runtime:Destroy()
Apps.Explorer.GetScriptCandidates=function() return {[a]={Class="ModuleScript"}} end
Apps.Explorer.GetNodes=function() error("the full game must not be scanned when a script registry exists") end
s:Start("foo",{}) assert(s.State.Scanned==1 and s.State.MatchCount==3 and not s.State.Error,"registry supplies all search candidates without classifying unrelated geometry")
Apps.Explorer.GetScriptCandidates=function() return {[a]={Class="ModuleScript"},[b]={Class="ModuleScript"}} end
Apps.Explorer.GetInferenceCandidates=function() return {[b]={Class="ModuleScript"}} end
s:Start("foo",{Scope="Game"})
assert(s.State.TotalScripts==1 and s.State.Groups[1].Object==b,"game scope uses only the game's script registry")
s:Start("foo",{Scope="All"})
assert(s.State.TotalScripts==2 and #s.State.Groups==2,"unrestricted service callers can still inspect platform scripts")
documents={{id=a,script=a,title="Platform",text="foo"},{id=b,script=b,title="Game",text="foo"}}
s:Start("foo",{Scope="Open",ExcludePlatform=true})
assert(s.State.TotalScripts==1 and s.State.Groups[1].Object==b,"Find in Place excludes platform scripts even when open")
documents={}
print("PASS: global search scopes, dirty buffers, exact lines, unavailable code, limits, cancellation/teardown and stale-safe replacements")
'''
explorer=(root/'src/Apps/Explorer/Explorer.lua').read_text()
program+='\ndo\nlocal Explorer={} local game={} local searchTreeVersion=0 local characterSearch={} local dirtyParents={} local nilMap={} local nodes={} local sortedSearchChildren={}\nlocal Apps={History={IsHidden=function() return false end}}\nlocal updateDebounce=true local function markSearchDirty() end\nlocal function moveObject() end\nlocal removeObject\n'
program+='local task={delay=function() end}\n'
program+=explorer[explorer.index('\tlocal cleanupScheduled ='):explorer.index('\tlocal searchGeneration,')]
program+=explorer[explorer.index('\tlocal function changeSearchTree('):explorer.index('\tlocal nilNode =')]
program+=explorer[explorer.index('\tlocal evidenceCandidates ='):explorer.index('\tExplorer.HasReconstructedSelection =')]
program+=explorer[explorer.index('\tremoveObject = function(root)'):explorer.index('\n\tmoveObject = function(obj)')]
program+=r'''
local gameNode={Obj=game}
local core={Obj={Name="CoreGui"},Parent=gameNode}
local user={Obj={Name="ReplicatedStorage"},Parent=gameNode}
local function scriptObject(name,parent)
 return {Name=name,ClassName="ModuleScript",Parent=parent,IsDescendantOf=function(self,ancestor)
  local at=self.Parent while at do if at==ancestor then return true end at=at.Parent end return false
 end}
end
local original=scriptObject("CoreModule",core.Obj) local originalNode={Obj=original,Parent=core} core[1]=originalNode
indexEvidenceCandidate(original,originalNode)
assert(Explorer.GetScriptCandidates()[original]==originalNode and originalNode.Class=="ModuleScript")
assert(not Explorer.GetInferenceCandidates()[original],"script-search registry does not weaken inference's core exclusions")
local detached=scriptObject("NilModule",nil) local detachedNode={Obj=detached,Parent={Obj={Name="Nil Instances"}}}
indexEvidenceCandidate(detached,detachedNode)
assert(Explorer.GetScriptCandidates()[detached]==detachedNode,"nil-instance scripts remain eligible")
local added=scriptObject("Added",user.Obj) local addedNode={Obj=added,Parent=user} user[1]=addedNode nodes[added]=addedNode
local nested=scriptObject("Nested",added) local nestedNode={Obj=nested,Parent=addedNode} addedNode[1]=nestedNode nodes[nested]=nestedNode
indexEvidenceCandidate(added,addedNode) indexEvidenceCandidate(nested,nestedNode)
assert(Explorer.GetScriptCandidates()[added] and Explorer.GetScriptCandidates()[nested],"live additions are indexed")
added.Parent=nil removeObject(added)
assert(not Explorer.GetScriptCandidates()[added] and not Explorer.GetScriptCandidates()[nested],"root and recursive descendant removals clear the script index")
assert(Explorer.GetScriptCandidates()[original] and Explorer.GetScriptCandidates()[detached],"unrelated core and nil entries survive removal")
print("PASS: production Explorer script registry includes core/nil scripts, caches classes and maintains live subtree membership")
end
'''
with tempfile.TemporaryDirectory() as folder:
    path=Path(folder)/'search.luau';path.write_text(program,encoding='utf-8')
    subprocess.run([str(root/'.tools/bin/luau.exe'),str(path)],check=True)
