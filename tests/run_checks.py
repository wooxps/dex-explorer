"""Run checks with official Luau CLI binaries (no Roblox installation required)."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--luau', default='luau')
parser.add_argument('--compiler', default='luau-compile')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'tests/panel_chrome_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/properties_view_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/ui_hit_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/search_cache_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/global_search_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/reflection_cache_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/console_performance_checks.py')],check=True)
subprocess.run([sys.executable,str(root/'tests/module_reconstruction_checks.py')],check=True)
subprocess.run([sys.executable, str(root/'tests/asset_manager_checks.py')], check=True)
subprocess.run([sys.executable, str(root/'tests/save_instance_checks.py')], check=True)
subprocess.run([sys.executable,str(root/'tests/anti_afk_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/loading_splash_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/ai_bridge_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/plugin_output_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/plugin_actions_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/bridge_client_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/hosted_compaction_checks.py'),'--compiler',args.compiler],check=True)
subprocess.run([sys.executable,str(root/'tests/resize_performance_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/transform_session_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/quick_actions_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/gui_transform_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable,str(root/'tests/selection_renderer_checks.py'),'--luau',args.luau],check=True)
subprocess.run([sys.executable, str(root / 'tests/native_assets_checks.py')], check=True)
subprocess.run([sys.executable, str(root / 'tests/resize_cursors_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/preview_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/macro_engine_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/macro_store_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/macro_ui_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/activity_checks.py'), '--luau', args.luau], check=True)
subprocess.run([sys.executable, str(root / 'tests/reference_checks.py'), '--luau', args.luau, '--compiler', args.compiler], check=True)
subprocess.run([sys.executable, str(root / 'tests/runtime_reload_checks.py')], check=True)
subprocess.run([sys.executable, str(root / 'tests/editor_highlight_checks.py')], check=True)
subprocess.run([sys.executable, str(root / 'tests/api_metadata_checks.py'), '--luau', args.luau], check=True)
sys.path.insert(0,str(root))
from build import offline_react_source
def module_file(name):
    return next((root / "src").rglob(name+".lua"))
subprocess.run([sys.executable, str(root / 'build.py'), 'build'], check=True)
for source in sorted(root.rglob('*.lua')):
    if source.relative_to(root).parts[0] in {'.build','.tools','dist','.git'}: continue
    subprocess.run([args.compiler, str(source)], stdout=subprocess.DEVNULL, check=True)
print('PASS: all source files and out.lua compile', flush=True)
subprocess.run([args.luau, str(root / 'tests/search.spec.lua')], check=True)
subprocess.run([args.luau,str(root/'tests/performance_infrastructure.spec.luau')],check=True)
subprocess.run([args.luau,str(root/'tests/projection.spec.luau')],check=True)
subprocess.run([args.luau,str(root/'tests/search_engine.spec.luau')],check=True)
subprocess.run([args.luau, str(root / 'tests/asset_query.spec.luau')], check=True)
subprocess.run([args.luau, str(root / 'tests/reconstructor.spec.luau')], check=True)
subprocess.run([args.luau, str(root / 'tests/reconstructor_session.spec.luau')], check=True)
subprocess.run([args.luau, str(root / 'tests/script_evidence_reader.spec.luau')], check=True)
subprocess.run([args.luau, str(root / 'tests/retained_function_evidence.spec.luau')], check=True)
subprocess.run([sys.executable, str(root/'tests/bytecode_paths_checks.py'), '--luau', args.luau, '--compiler', args.compiler],check=True)
subprocess.run([args.luau, str(root / 'tests/history.spec.lua')], check=True)
subprocess.run([args.luau, str(root / 'tests/editor_document.spec.luau')], check=True)
subprocess.run([args.luau, str(root / 'tests/editor_undo_stack.spec.luau')], check=True)
lib = (root / 'src/Shared/Lib.lua').read_text(encoding='utf-8')
start = lib.index('\tLib.StudioFont =')
end = lib.index('\n\tlocal renderStepped', start)
parts = [(root / 'tests/roblox_mock.luau').read_text(encoding='utf-8'), (root/'tests/react_host_mock.luau').read_text(encoding='utf-8'), offline_react_source(), lib[start:end],
         'local deps={Main=Main,Lib=Lib,Apps=Apps,Settings=Settings,API=API,RMD=RMD,env={},service=service,plr=service.Players.LocalPlayer,create=create,createSimple=createSimple}\n']
parts += ['do\nlocal Lib={}\n', lib[lib.index('\tLib.Signal ='):lib.index('\tLib.Set =')], r'''
local signal = Lib.Signal.new()
local first, skipped
local calls = {}
first = signal:Connect(function()
 first:Disconnect()
 skipped:Disconnect()
 signal:Connect(function() calls[#calls+1]="late" end)
end)
skipped = signal:Connect(function() error("disconnected handler ran") end)
signal:Connect(function() calls[#calls+1]="remaining" end)
signal:Fire()
assert(table.concat(calls, ",")=="remaining", "disconnecting during dispatch preserves the remaining listeners")
signal:Fire()
assert(table.concat(calls, ",")=="remaining,remaining,late", "new listeners start on the next dispatch")
end
''']
parts.append('local plr=service.Players.LocalPlayer\n' + lib[lib.index('\tLib.ScrollBar = (function()'):lib.index('\n\tLib.Window = (function()')])
parts.append(lib[lib.index('\tLib.Set = (function()'):lib.index('\tLib.IconMap = (function()')])
parts.append('do\n' + lib[lib.index('\tlocal PH = newproxy()'):lib.index('\tlocal function getGuiMT')] + lib[lib.index('\tLib.ClickSystem = (function()'):lib.index('\n\treturn Lib\nend')] + '\nend\n')
parts.append('do local control=(function()\n'+module_file('StudioPropertiesView').read_text(encoding='utf-8')+'\nend)() Apps.StudioPropertiesView=control.Main() end\n')
for name in ["ServiceVisibility", "ServiceVisibilityDialog", "RowStatus", "GradualEdgeScroll", "IconAppearance", "WindowLayout", 'React', 'Signal', 'PropertyChanges', 'History', 'SelectionService', 'LocalizationCsv', 'GltfGeometry', 'GltfTerrain', 'GltfFacs', 'GltfTextures', 'GltfExporter', 'ObjExporter', 'StudioPopup', 'ExplorerFileActions', 'SolidModeling', 'ReflectionService', 'EditingService', 'InsertionService', 'SearchNameIndex', 'SearchQuery', 'ExplorerPolicy', 'ExplorerProjection', 'SearchBits', 'SearchPostings', 'SearchSnapshot', 'SearchResults', 'SearchTreeResults', 'ExplorerSearch', 'InsertObjectOverlay', 'IndentGuides', 'NodeDetailsPlaceholder', 'UnderlaysRow', 'RenameBox', 'BoxSelectIndicator', 'DragDropIndicator', 'ExplorerNodeRow', 'SearchBar', 'Dropdown', 'SearchBrowserButton', 'TooltipActions', 'SearchBox', 'ContextMenu', 'ScrollingView', 'SessionView', 'InstancePath', 'InsertObjectMenu', 'SelectionGeometryMask', 'SelectionRenderer', 'PropertyValueCodec', 'PropertySchema', 'PropertyReader', 'PropertyValueEditors', 'PropertyValueCell', 'PropertyRow', 'EditorHitTest', 'EditorTabs', 'StudioMenuDefinition', 'EditorContextMenu', 'EditorFolding', 'StudioEditorSkin', 'CodeViewport', 'EditorUndoStack', 'EditorDocument', 'EditorSelectionSet', 'EditorRegex', 'EditorGlobalSearch', 'EditorGlobalSearchWidget', 'EditorFindModel', 'EditorFindWidget', 'EditorSymbols', 'EditorHoverTypes', 'EditorModuleTypes', 'EditorBuiltinSignatures', 'EditorApiDocumentation', 'EditorDocumentationText', 'EditorHover', 'EditorCompletion', 'EditorSignature', 'EditorLanguage', 'EditorDefinitions', 'EditorFormatter', 'EditorNavigation', 'EditorController', 'ExplorerInferenceOverlay', 'Explorer', 'ReconstructorEvidence', 'ServerReferenceAnalysis', 'BytecodeStrings', 'BytecodePaths', 'RetainedFunctionEvidence', 'ScriptEvidenceReader', 'ReconstructorSession', 'Reconstructor']:
    source = (module_file(name)).read_text(encoding='utf-8')
    parts.append(f'do local control=(function()\n{source}\nend)()\ncontrol.InitDeps(deps)\nApps.{name}=control.Main()\nassert(type(Apps.{name})=="table", "{name} must return its API table")\ncontrol.InitAfterMain() end\n')
parts.append('do local control=(function()\n'+module_file('EditorNewScript').read_text(encoding='utf-8')+'\nend)() control.InitDeps(deps) Apps.EditorNewScript=control.Main() end\n')
for name in ['ReferenceSource', 'ReferenceScan', 'ReferenceFinder', 'ActivitySession', 'ActivityViewer']:
    parts.append('do local control=(function()\n'+module_file(name).read_text(encoding='utf-8')+'\nend)() control.InitDeps(deps) Apps.'+name+'=control.Main() end\n')
parts.append('local function newApiDocumentation() local control=(function()\n'+module_file('EditorApiDocumentation').read_text(encoding='utf-8')+'\nend)() control.InitDeps(deps) return control.Main() end\n')
parts += [(root / 'tests/editor_find_model.spec.luau').read_text(encoding='utf-8'), (root / 'tests/editor_definitions.spec.luau').read_text(encoding='utf-8'), (root / 'tests/editor_types.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/editor_type_inference.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/property_modules.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/search_index.spec.luau').read_text(encoding='utf-8')]
parts += ['Explorer=Apps.Explorer\nlocal productionSelectionVisuals=Explorer.UpdateSelectionVisuals\n', (root / 'tests/explorer_smoke.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/reference_registry.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/search_insert_fidelity.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/history_explorer.spec.luau').read_text(), (root / 'tests/history_races.spec.luau').read_text()]
parts += [(root / 'tests/performance.spec.luau').read_text()]
parts += [(root / 'tests/incremental_explorer.spec.luau').read_text()]
parts += [(root / 'tests/virtual_search.spec.luau').read_text()]
parts += [(root / 'tests/nil_instances.spec.luau').read_text()]
parts += [(root / 'tests/studio_parity.spec.luau').read_text()]
parts += [(root / 'tests/selection_outline.spec.luau').read_text()]
parts += [(root / 'tests/explorer_interactions.spec.luau').read_text()]
parts += [(root / 'tests/runtime_parity.spec.luau').read_text()]
parts += [(root / 'tests/session_services.spec.luau').read_text()]
parts += [(root / 'tests/studio_discovery.spec.luau').read_text()]
parts += [(root / 'tests/icon_appearance.spec.luau').read_text()]
parts += [(root / 'tests/row_status.spec.luau').read_text()]
parts += [(root / 'tests/service_visibility.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/context_menu.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/explorer_file_actions.spec.luau').read_text(encoding='utf-8')]
parts += ['do local env=deps.env\n' + lib[lib.index('\tLib.SaveAsPrompt ='):lib.index('\tLib.Signal =')] + '\nend']
parts += [(root / 'tests/explorer_file_dialogs.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/explorer_presentation.spec.luau').read_text(encoding='utf-8')]
contracts=json.loads((root/'tests/fixtures/studio-ui-contracts.json').read_text(encoding='utf-8'))['values']
parts += ['local sourceUIContracts={'+','.join('['+json.dumps(k)+']='+str(v) for k,v in contracts.items())+'}\n',
          (root/'tests/source_ui_contracts.spec.luau').read_text(encoding='utf-8')]

parts += [(root/'tests/reconstructor_ui.spec.luau').read_text(encoding='utf-8')]
parts += [(root/'tests/reconstructor_explorer.spec.luau').read_text(encoding='utf-8')]

properties = (root / 'src/Apps/Properties/Properties.lua').read_text(encoding='utf-8')
parts += ['do\n',(root/'tests/property_resize.spec.luau').read_text(),
          properties[properties.index('\tlocal function disconnectPropertyRow('):properties.index('\n\tProperties.SetProp = function')],
          (root/'tests/property_resize_assertions.spec.luau').read_text(),'end\n']
parts += ['do\nlocal inputProp\nlocal propEntries, viewList = {}, {}\nlocal Properties = {Index=0}\nlocal refreshes=0\nProperties.Refresh=function() refreshes+=1 end\n',
          properties[properties.index('\tProperties.CancelObjectSelection ='):properties.index('\n\tProperties.InitSearch =')],
          (root/'tests/object_picker.spec.luau').read_text(encoding='utf-8'), 'end']
parts += ['''do
local savedBrickColor,savedNumberSequence,savedColorSequence,savedNumberRange=BrickColor,NumberSequence,ColorSequence,NumberRange
BrickColor={new=function(name) return {Name=name} end}
NumberSequence={new=function(value) return {Value=value} end}
ColorSequence={new=function(value) return {Value=value} end}
NumberRange={new=function(value) return {Min=value,Max=value} end}
local CFrame = {new=function() return {} end}
local Font = {fromEnum=function() return {} end}
local propertyControl=(function()
''', properties, '''
end)()
propertyControl.InitDeps(deps)
local propertyApi=propertyControl.Main()
assert(type(propertyApi)=="table", "Properties main returns an API")
assert(table.find(propertyApi.AllowedAttributeTypes,"CFrame") and propertyApi.DefaultPropValue.CFrame)
assert(table.find(propertyApi.AllowedAttributeTypes,"Font") and propertyApi.DefaultPropValue.Font)
assert(type(propertyApi.DisplayProp)=="function", "Properties wires the value-cell factory")
assert(type(propertyApi.DisplayEnumDropdown)=="function", "Properties wires owned editors")
assert(type(propertyApi.NewPropEntry)=="function", "Properties wires row creation")
assert(propertyApi.StringToValue({ValueType={Name="int"}},"42")==42)
assert(propertyApi.GetPropVal({Name="Enabled",ValueType={Name="bool"}},{Enabled=false})==false)
BrickColor,NumberSequence,ColorSequence,NumberRange=savedBrickColor,savedNumberSequence,savedColorSequence,savedNumberRange
print("PASS: complete Properties controller loads and wires its real component APIs")
end
''']
parts += [(root / 'tests/attribute_dialog_mock.luau').read_text(encoding='utf-8'),
          properties[properties.index('\tProperties.DisplayAddAttributeWindow ='):properties.index('\n\tProperties.IsTextEditable')],
          (root / 'tests/attribute_dialog.spec.luau').read_text(encoding='utf-8')]
parts += ["""
do
local props={{Category="Attributes",Class="",Name="",SpecialRow="EmptyAttributes",Tags={}}}
local viewList, expanded = {}, {CAT_Attributes=true}
local View=Apps.StudioPropertiesView
local inputProp
Properties.NameWidthCache={} Properties.SearchText="" Properties.EntryIndent=16 Properties.EntryOffset=0
Settings.Properties.ScaleType=1
Properties.UpdateView=function() end
""", properties[properties.index('\tProperties.Update = function()'):properties.index('\n\tProperties.NewPropEntry = function')], """
Properties.Update()
assert(#viewList==2 and viewList[1].CategoryName=="Attributes" and viewList[2].SpecialRow=="EmptyAttributes","empty Attributes keeps header and hint")
expanded.CAT_Attributes=false Properties.Update()
assert(#viewList==1 and viewList[1].CategoryName=="Attributes","collapsed Attributes keeps header")
props[1]={Category="Attributes",Class="Instance",Name="ATTR_Enabled",DisplayName="Enabled",IsAttribute=true,Tags={},ValueType={Name="bool"}}
expanded.CAT_Attributes=true Properties.Update()
assert(#viewList==2 and viewList[2].IsAttribute and not viewList[2].SpecialRow,"populated Attributes has no extra Add row")
print("PASS: real Properties view builder with empty, collapsed and populated Attributes")
end
"""]
parts += ["""
do
local values={Enabled=false}
local object={}
local Explorer={Selection={List={{Obj=object}}}}
local isa=function() return true end
local getAttribute=function(_,name) return values[name] end
local setAttribute=function(_,name,value) if name=="Reject" then error("invalid target") end values[name]=value end
""", properties[properties.index('\tProperties.SetProp = function'):properties.index('\n\tProperties.InitInputBox = function')], """
object.GetAttribute=function(_,name) return values[name] end
object.SetAttribute=setAttribute
local old={AttributeName="Enabled",ValueType={Name="bool"}}
local renamed={Class="Instance",Name="ATTR_Visible",AttributeName="Visible",IsAttribute=true,ValueType={Name="bool"}}
Properties.SetProp(renamed,true,true,old)
assert(values.Visible==false and values.Enabled==nil,"rename preserves false")
renamed.AttributeName="Reject"
Properties.SetProp(renamed,true,true,{AttributeName="Visible",ValueType={Name="bool"}})
assert(values.Visible==false,"failed destination write does not delete original")
renamed.AttributeName="Visible"
Properties.SetProp(renamed,true,true,{AttributeName="Visible",ValueType={Name="bool"}})
assert(values.Visible==false,"same-name save does not delete attribute")
print("PASS: actual attribute writes preserve false and original data on rename failure")
end
"""]
parts += ["""
do
local prop={IsAttribute=true,AttributeName="Enabled",Name="ATTR_Enabled",ValueType={Name="bool"}}
local viewList={prop}
local frame=Instance.new("Frame") local label=Instance.new("TextLabel",frame)
label.Size=UDim2.new(1,-4,1,0)
local propEntries={{GuiElems={PropName=label}}}
local Explorer={Selection={List={}}}
Properties.Index=0
local saved
Properties.SetProp=function(new,value,flag,old) saved={new,old} end
Properties.ShowExplorerProps=function() end
""", properties[properties.index('\tProperties.CancelAttributeRename ='):properties.index('\tProperties.DisplayAttributeContext =')], """
Properties.BeginAttributeRename(prop)
local editor=Properties.AttributeRename.Box
assert(editor.Parent==frame and not label.Visible and editor.Text=="Enabled","rename edits actual name cell")
editor.Text="Visible" editor.FocusLost:Fire(true)
assert(saved[1].AttributeName=="Visible" and saved[2]==prop and label.Visible,"inline rename commits and restores label")
saved=nil Properties.BeginAttributeRename(prop)
editor=Properties.AttributeRename.Box editor.Text="Cancelled"
editor.InputBegan:Fire({KeyCode=Enum.KeyCode.Escape}) editor.FocusLost:Fire(false)
assert(not saved and not Properties.AttributeRename and label.Visible,"Escape cancels without saving")
Properties.BeginAttributeRename(prop) editor=Properties.AttributeRename.Box editor.Text=""
editor.FocusLost:Fire(true)
assert(Properties.AttributeRename and not saved,"invalid name remains editable")
Properties.CancelAttributeRename()
print("PASS: actual inline name editor, commit, Escape and invalid-name handling")
end
"""]
parts += ["""
do
local savedFactory=Lib.ContextMenu.new
Lib.ContextMenu.new=function()
 local menu=savedFactory()
 function menu:Hide() self.Hidden=true end
 return menu
end
local first,second={},{}
local Explorer={Selection={List={{Obj=first}}}}
local applied={}
service.CollectionService={GetAllTags=function() return {"IceBrick","Enemy"} end,AddTag=function(_,obj,tag) applied[#applied+1]={obj,tag} end}
service.CollectionService.HasTag=function() return false end
Properties.ShowExplorerProps=function() end
""", properties[properties.index('\tProperties.DisplayTagMenu ='):properties.index('\tProperties.CancelAttributeRename =')], """
local anchor=Instance.new("Frame")
Properties.DisplayTagMenu(anchor)
local menu=Properties.TagMenu
assert(menu.Items[1].Name=="Enemy" and menu.Items[2].Name=="IceBrick","known tags sorted")
Explorer.Selection.List={{Obj=second}}
menu.Items[1].OnClick()
assert(applied[1][1]==first and applied[1][2]=="Enemy","tag choice uses captured target")
Properties.DisplayTagMenu(anchor)
menu.GuiElems.SearchBar.Text="NewTag"
menu.GuiElems.SearchBar.FocusLost:Fire(true)
assert(applied[2][1]==second and applied[2][2]=="NewTag" and menu.Hidden,"Enter adds new tag and closes")
Lib.ContextMenu.new=savedFactory
print("PASS: actual tag menu suggestions, target capture and new-tag entry")
end
"""]
parts += [(root / 'tests/color_picker_mock.luau').read_text(), lib[lib.index('\tLib.ColorPicker ='):lib.index('\n\tLib.NumberSequenceEditor')], (root / 'tests/color_picker.spec.luau').read_text()]
parts += ["""
BrickColor={new=function() return {Name="Medium stone grey"} end,palette=function(i) assert(i<128,"palette index resets for each picker") return {Color=Color3.fromRGB(i,i,i)} end}
""",lib[lib.index('\tLib.BrickColorPicker ='):lib.index('\n\tLib.ColorPicker =')],"""
local legacy=Lib.BrickColorPicker.new()
local another=Lib.BrickColorPicker.new()
assert(#legacy.Swatches==139 and #another.Swatches==139,"complete honeycomb and neutral strip")
legacy:Show(10,10,Color3.fromRGB(50,50,50))
local function findOutline(name) for _,child in ipairs(legacy.Gui:GetDescendants()) do if child.Name==name then return child end end end
assert(findOutline("SelectedOutline").Visible,"current color outlined")
legacy.Hover(legacy.Swatches[1],Color3.fromRGB(50,50,50))
assert(findOutline("HoverOutline").Visible and legacy.Gui.Frame.ColorName.Text=="Medium stone grey","hover outline and color name")
assert(not legacy.Gui.Frame.ColorName.Visible,"tooltip waits before showing")
flushTasks()
assert(legacy.Gui.Frame.ColorName.Visible,"tooltip appears after delay")
legacy.Hover(nil)
assert(not findOutline("HoverOutline").Visible and not legacy.Gui.Frame.ColorName.Visible,"hover cleanup")
assert(findOutline("SelectedOutline").Position==UDim2.fromOffset(0,0),"outline is anchored to swatch origin")
assert(findOutline("SelectedOutline").Size==UDim2.fromScale(1,1),"outline follows exact swatch size")
local more=false
legacy.OnMoreColors:Connect(function() more=true assert(legacy.Gui.Parent==nil,"legacy closes before opening full selector") end)
legacy.Gui.Frame.MoreColors.MouseButton1Click:Fire()
assert(more,"More Colors callback")
print("PASS: actual legacy picker palettes, repeated construction, selection outline and More Colors handoff")
"""]
parts += ['local function makeActualEditorInput(frame)\n',
          lib[lib.index('\t\t\tlocal editBox = Instance.new("TextBox")',lib.index('Lib.CodeFrame =')):lib.index('\n\t\t\tlineTweens.Invis =',lib.index('Lib.CodeFrame ='))],
          'return editBox\nend\n']
parts += [(root / 'tests/editor_mock.luau').read_text(),
          lib[lib.index('\t\tfuncs.ResetSelection ='):lib.index('\t\tfuncs.ScrollDelta =')],
          lib[lib.index('\t\tfuncs.ProcessTextChange ='):lib.index('\t\tfuncs.MakeRichTemplates =')],
          lib[lib.index('\t\tfuncs.GetColumnPixelX ='):lib.index('\t\tfuncs.DisplayToSource =')], """
function funcs:ResetFolds() end
function funcs:RevealSourceLine() end
function funcs:SourceToDisplay(y) return y end
function funcs:DisplayToSource(y) return y end
function funcs:UpdateView() end
function funcs:MakeRichTemplates() end
function funcs:PreHighlight() self.HighlightCount=(self.HighlightCount or 0)+1 end
function funcs:Refresh() end
function funcs:UpdateCursor() self.CursorY=math.clamp(self.CursorY,0,#self.Lines-1) self.CursorX=math.clamp(self.CursorX,0,#self.Lines[self.CursorY+1]) end
function funcs:MoveCursor(x,y) self.CursorX=x self.CursorY=y self:UpdateCursor() end
function funcs:SetCopyableSelection() end
function funcs:GetSelectionText() return "" end
Lib.CodeFrame={new=function()
 local cf=setmetatable({Frame=Instance.new("Frame"),GuiElems={},Colors={},Lines={""},Text="",CursorX=0,CursorY=0,ViewX=0,ViewY=0,SelectionRange={{0,0},{0,0}}},{__index=funcs})
 cf.GuiElems.EditBox=makeActualEditorInput(cf.Frame)
 cf.ScrollV={ScrollTo=function(_,n) cf.ViewY=n end} cf.ScrollH={ScrollTo=function(_,n) cf.ViewX=n end}
 return cf
end}
"""]
source=(root / 'src/Apps/ScriptViewer/ScriptViewer.lua').read_text()
parts += [f'local editorControl=(function()\n{source}\nend)()\neditorControl.InitDeps(deps)\nApps.ScriptViewer=editorControl.Main()\neditorControl.InitAfterMain()\n',
          (root / 'tests/editor.spec.luau').read_text(), (root/'tests/editor_find_widget.spec.luau').read_text(encoding='utf-8'), (root / 'tests/editor_reconstruction.spec.luau').read_text(), (root / 'tests/editor_reference.spec.luau').read_text(), (root / 'tests/editor_menu_tabs.spec.luau').read_text(), (root / 'tests/editor_undo_integration.spec.luau').read_text(encoding='utf-8'), (root/'tests/editor_native_operations.spec.luau').read_text(encoding='utf-8'), (root/'tests/editor_selection_lines.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/editor_reference_results.spec.luau').read_text(encoding='utf-8')]
parts += [(root / 'tests/editor_global_search_integration.spec.luau').read_text(encoding='utf-8')]

def luau_fixture(value):
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(k) + "]=" + luau_fixture(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(luau_fixture(v) for v in value) + "}"
    return json.dumps(value)

native_menu_fixture=json.loads((root/'tests/fixtures/studio-editor-menu.json').read_text(encoding='utf-8'))
parts += ['do\n(function()\nlocal nativeMenuFixture='+luau_fixture(native_menu_fixture)+'\n',
          (root/'tests/studio_editor_menu.spec.luau').read_text(encoding='utf-8'), 'end)()\nend\n']
parts += ['do\n(function()\nlocal funcs={}\n',
          lib[lib.index('\t\tlocal function setupEditBox(obj)'):lib.index('\n\t\tlocal function makeFrame(obj)',lib.index('\t\tlocal function setupMouseSelection(obj)'))],
          lib[lib.index('\t\tfuncs.GetSelectionText = function(self)'):lib.index('\t\tfuncs.ResetSelection = function(self, norefresh)')],
          lib[lib.index('\t\tfuncs.SetEditing = function(self, on, input)'):lib.index('\t\tfuncs.CursorAnim = function(self, on)')],
          (root / 'tests/editor_clipboard.spec.luau').read_text(), 'end)()\nend\n']
parts += ['do\nlocal static, inputService = {}, service.UserInputService\nlocal resizeCursorOwner, resizeDragOwner\n', """
local assetRequests = 0
local Main = { GetStudioAsset = function() assetRequests += 1 return 'mock://text' end }
""", lib[lib.index('		local cursorOwner, cursorKey'):lib.index('\n		local function registerResizeTarget')], """
local previous, previousEnabled = inputService.MouseIcon, inputService.MouseIconEnabled
local code, other = Instance.new("Frame"), Instance.new("Frame")
inputService.MouseIcon = "custom://previous"
inputService.MouseIconEnabled = true
static.SetTextCursor(code, true)
for _ = 1, 1000 do static.SetTextCursor(code, true) end
assert(assetRequests == 0 and inputService.MouseIcon == "rbxasset://textures/Cursors/KeyboardMouse/IBeamCursor.png" and inputService.MouseIconEnabled)
static.SetTextCursor(other, false)
assert(code:FindFirstChildOfClass("UIDragDetector").CursorIcon == inputService.MouseIcon and inputService.MouseIconEnabled)
resizeCursorOwner = other
static.SetTextCursor(code, true)
assert(inputService.MouseIconEnabled and inputService.MouseIcon == "custom://previous")
resizeCursorOwner = nil
static.SetTextCursor(code, true)
inputService.MouseIcon = "custom://game"
static.SetTextCursor(code, false)
assert(inputService.MouseIcon == "custom://game")
inputService.MouseIconEnabled = false
static.SetTextCursor(code, true)
assert(inputService.MouseIconEnabled)
static.SetTextCursor(code, false)
assert(not inputService.MouseIconEnabled and inputService.MouseIcon == "custom://game")
local knob = Instance.new("Frame")
static.SetHandleCursor(knob, "native/gui-editor/icon_resize1", knob)
local count = assetRequests
for _ = 1, 1000 do static.SetHandleCursor(knob, "native/gui-editor/icon_resize1", knob) end
assert(count == assetRequests and inputService.MouseIconEnabled)
static.SetHandleCursor(knob, "native/gui-editor/icon_rotate1", knob)
assert(count + 1 == assetRequests)
static.SetHandleCursor(knob, nil)
assert(inputService.MouseIcon == "custom://game" and not inputService.MouseIconEnabled)
inputService.MouseIcon, inputService.MouseIconEnabled = previous, previousEnabled
end
"""]
parts += [(root / 'tests/docking_mock.luau').read_text(),
          lib[lib.index('\t\tlocal function measureSide'):lib.index('\t\tlocal function focusInput')],
          lib[lib.index('\t\tfuncs.AlignTo ='):lib.index('\t\tfuncs.Close =')],
          'local function installDrag(self) local guiTopBar=self.GuiElems.TopBar local guiMain=self.GuiElems.Main\n',
          lib[lib.index('\t\t\tguiTopBar.InputBegan:Connect'):lib.index('\t\t\tguiTopBar.Close.MouseButton1Click:Connect')],
          'end\n', lib[lib.index('\t\tlocal function updateSide(side, noTween)'):lib.index('\n\t\tupdateWindows =')], (root / 'tests/docking.spec.luau').read_text()]
parts += ['do\nlocal updates=0\nlocal leftSide={Hidden=false,Windows={}} local rightSide={Hidden=false,Windows={}}\nlocal static={BeforeSideVisibilityChange=Lib.Signal.new()}\nlocal function updateWindows() updates+=1 end\n',
          lib[lib.index('\t\tstatic.ToggleSide ='):lib.index('\t\tstatic.Init =')],
          (root/'tests/docking_visibility.spec.luau').read_text(), 'end']
parts += [(root/'tests/editor_new_script.spec.luau').read_text(encoding='utf-8')]
viewport=(root/'src/Apps/ScriptViewer/Components/CodeViewport.lua').read_text()
parts += ['do\nlocal viewportModule=(function()\n'+viewport+'\nend)()\nviewportModule.InitDeps(deps)\nlocal funcs=viewportModule.Main()\n',
          lib[lib.index('\t\tfuncs.ConnectEditBoxEvent = function(self)',lib.index('Lib.CodeFrame =')):lib.index('\t\tfuncs.DisconnectEditBoxEvent = function(self)')],
          lib[lib.index('\t\tfuncs.UpdateCursor = function(self, input)',lib.index('Lib.CodeFrame =')):lib.index('\t\tlocal function lexLine(')],
          (root / 'tests/editor_viewport.spec.luau').read_text(), (root/'tests/editor_geometry.spec.luau').read_text(encoding='utf-8'), (root/'tests/editor_find_render.spec.luau').read_text(encoding='utf-8'), 'end\n']
parts += ['do local Explorer=Apps.Explorer local Properties={ComputeConflicts=function() end} local isa=game.IsA local getAttribute=game.GetAttribute local setAttribute=game.SetAttribute\n',
          properties[properties.index('\tProperties.SetProp = function'):properties.index('\n\tProperties.InitInputBox = function')],
          (root / 'tests/history_properties.spec.luau').read_text(), 'end\n']
main_source=(root / 'main.lua').read_text(encoding='utf-8')
parts += ['do\n', (root / 'tests/main_menu.spec.luau').read_text(),
          'local pluginToolbarControl=(function()\n'+module_file('PluginToolbar').read_text(encoding='utf-8')+'\nend)()\n',
          'local pluginRuntimeControl=(function()\n'+module_file('PluginRuntime').read_text(encoding='utf-8')+'\nend)()\n',
          'local pluginActionsControl=(function()\n'+module_file('PluginActions').read_text(encoding='utf-8')+'\nend)()\n',
          'local pluginManagerControl=(function()\n'+module_file('PluginManager').read_text(encoding='utf-8')+'\nend)()\n',
          'local pluginUIControl=(function()\n'+module_file('BridgeUI').read_text(encoding='utf-8')+'\nend)()\n',
          (root / 'tests/plugins.spec.luau').read_text(encoding='utf-8'),
          main_source[main_source.index('\tlocal menuTools ='):main_source.index('\tMain.StudioAssets =')], """
Main.Version="2.2 · Studio UI"
Main.CreateMainGui()
verifyPlugins()
verifyPluginActionsAndOutput()
local menu=Main.MainGui.OpenButton.MainFrame
assert(Main.AppsContainerGrid.CellSize==UDim2.fromOffset(44,42) and Main.AppsContainerGrid.FillDirectionMaxCells==5,"five-column tool grid")
Main.SetMainGuiOpen(true)
assert(menu.Visible and menu.Size.X.Offset==268,"menu opens at the compact desktop width")
assert(Main.AppsContainerGrid.AbsoluteContentSize.Y==142,"fifteen tools fit in three desktop rows")
local screen=Main.MainGui
screen.ViewportSize=Vector2.new(224,320)
screen:GetPropertyChangedSignal("AbsoluteSize"):Fire()
Main.AppsContainerGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Fire()
assert(menu.Size.X.Offset==208 and menu.Size.Y.Offset<=264,"narrow and short viewports keep the launcher in view")
assert(Main.AppsContainerGrid.AbsoluteContentSize.Y==242 and Main.AppsFrame.CanvasSize.Y.Offset>Main.AppsFrame.AbsoluteSize.Y,"tool rows wrap and remain scrollable")
screen.ViewportSize=nil
screen:GetPropertyChangedSignal("AbsoluteSize"):Fire()
Main.AppsContainerGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Fire()
assert(menu.Size.X.Offset==268 and Main.AppsContainerGrid.AbsoluteContentSize.Y==142,"wider viewports restore the shorter grid")
assert(Main.MainGui.OpenButton.Text=="" and not Main.MainGui.OpenButton:FindFirstChild("Caption") and not Main.MainGui.OpenButton:FindFirstChild("Chevron"),"compact launcher has no caption or arrow")
assert(Main.MainGui.OpenButton.Size==UDim2.fromOffset(32,32) and Main.MainGui.OpenButton.DexIcon.Image=="mockasset://branding/dex/toolbar-white-v1","square launcher uses its monochrome toolbar mark")
service.UserInputService.InputBegan:Fire({KeyCode=Enum.KeyCode.Escape,UserInputType=Enum.UserInputType.Keyboard})
assert(not Main.MainGuiOpen and not menu.Visible,"Escape closes main menu")
Main.SetMainGuiOpen(true)
service.UserInputService.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton2,Position=Vector2.new(1090,790)})
assert(not Main.MainGuiOpen,"outside right-click closes")
Main.SetMainGuiOpen(true)
local found=false
for _,row in ipairs(Main.AppsContainer:GetChildren()) do
 if row.ClassName=="Frame" and row.Name=="Explorer" then
  assert(row.Main.State.Text=="Open","initial window indicator")
  assert(not row.Main:FindFirstChild("AppName") and not row.Main.State.Visible,"built-in tools have no captions")
  assert(row.Main.Icon.Position==UDim2.new(.5,0,.5,-2),"tool icons are centered above the active marker")
  row.Main.MouseButton1Click:Fire()
  assert(row.Main.State.Text=="Show" and Main.MainGuiOpen,"row toggles window without closing launcher")
  found=true
 end
end
assert(found,"Explorer launcher preserved")
assert(Main.AppsContainer["Script Editor"].LayoutOrder < Main.AppsContainer["Console"].LayoutOrder,"script tools are grouped in order")
local expectedIcons={
 ["Explorer"]="menu/tool/explorer",["Properties"]="menu/tool/properties",["Click part to select"]="native/transform/ribbon/select",["Click UI to select"]="menu/tool/ui_select",
 ["Input Macros"]="macro/play",["Script Editor"]="menu/tool/script",["Console"]="menu/tool/console",["Save Instance"]="menu/tool/save",["3D Viewer"]="menu/tool/viewer",
}
local iconCount=0
for _,row in ipairs(Main.AppsContainer:GetChildren()) do
 if row.ClassName=="Frame" and expectedIcons[row.Name] then
  iconCount+=1
  assert(row.Main.Icon.Image=="mockasset://"..expectedIcons[row.Name],"native tool icon: "..row.Name)
  assert(row.Main.Icon.Size==UDim2.fromOffset(32,32),"consistent native-sized tool icons with integer downsampling")
  assert(row.Main.Icon.ImageRectSize.X==0 and row.Main.Icon.ImageRectSize.Y==0,"tool icon is not cropped as a legacy sprite")
 end
end
assert(iconCount==9,"every main-menu tool uses the Studio icon set")
local macroOpened=0
Apps.InputMacros={
 Open=function()
  macroOpened+=1
  Apps.InputMacros.Window=Apps.InputMacros.Window or {OnActivate=Lib.Signal.new(),OnDeactivate=Lib.Signal.new()}
 end,
 Hide=function() Apps.InputMacros.Window.OnDeactivate:Fire() end,
}
local macroTile=Main.AppsContainer["Input Macros"].Main
macroTile.MouseButton1Click:Fire()
assert(macroOpened==1 and not Main.MainGuiOpen and macroTile.Highlight.Visible,"macros opens from the launcher and closes the launcher")
Apps.InputMacros.Hide()
assert(not macroTile.Highlight.Visible,"closing the macro window resets the launcher indicator")
Main.SetMainGuiOpen(true)

assert(not menu:FindFirstChild("Heading"),"no Workspace tools heading")
local footer=menu.BottomFrame
assert(footer.Information.Text=="Credits","Credits label")
assert(footer.Undo.Icon.Image=="mockasset://menu/undo" and footer.Redo.Icon.Image=="mockasset://menu/redo","native history icons")
assert(footer.Undo.Text=="" and footer.Redo.Text=="","history actions are icon-only")
assert(footer.Settings.Visible and footer.Settings.Icon.Image=="mockasset://menu/settings","native settings button")
assert(footer.Shutdown.Icon.Image==Lib.PanelAsset("close-launcher") and footer.Shutdown.Icon.Size==UDim2.fromOffset(26,26),"launcher paints the Studio close glyph at its native texture size")
footer.Settings.MouseButton1Click:Fire()
assert(menu.SettingsPage.Visible and not Main.AppsFrame.Visible and Main.MainGuiOpen,"settings page opens inline")
assert(footer.Information.Text=="Back","settings page exposes Back action")
footer.Information.MouseButton1Click:Fire()
assert(not menu.SettingsPage.Visible and not menu.Credits.Visible and Main.AppsFrame.Visible,"Back returns from settings to tools")
footer.Settings.MouseButton1Click:Fire()
footer.Settings.MouseButton1Click:Fire()
assert(not menu.SettingsPage.Visible and Main.AppsFrame.Visible,"settings button also returns to tools")
footer.Information.MouseButton1Click:Fire()
assert(menu.Credits.Visible and not Main.AppsFrame.Visible and Main.MainGuiOpen,"inline credits keep menu open")
local credits=menu.Credits
assert(credits.Logo.Image=="mockasset://branding/dex/toolbar-white-v1" and credits.ProductName.Text=="Dex Explorer")
assert(credits.Version.Text=="2.2")
for _,name in ipairs({"Wooxps","Toon","Moon","Cazan"}) do
 assert(credits.Contributors[name].ContributorName.Text==name and credits.Contributors[name].Contribution.Text~="")
end
assert(credits.Contributors.Position.Y.Offset+credits.Contributors.Size.Y.Offset<=credits.CanvasSize.Y.Offset)
screen.ViewportSize=Vector2.new(244,250)
screen:GetPropertyChangedSignal("AbsoluteSize"):Fire()
assert(credits.CanvasSize.Y.Offset>credits.AbsoluteSize.Y,"credits remain scrollable in short viewports")
screen.ViewportSize=nil
screen:GetPropertyChangedSignal("AbsoluteSize"):Fire()
footer.Information.MouseButton1Click:Fire()
assert(not menu.Credits.Visible and Main.AppsFrame.Visible,"Back returns to tools")
instMT.__index=originalIndex
print("PASS: actual main-menu construction, icon grid, window state, persistent toggles, native history icons, inline credits, Escape and outside right-click")
end
"""]
main_source=(root / 'main.lua').read_text(encoding='utf-8')
parts += ['do\nlocal writes,handles=0,0\nlocal disk={}\nlocal env={makefolder=function() end,isfile=function(p) return disk[p]~=nil end,writefile=function(p,d) disk[p]=d writes+=1 end,getcustomasset=function(p) handles+=1 return "asset://"..p end}\nlocal StudioAssetData={version="fixture",files={used="png",other="png2",unused="png3"}}\nlocal securedGui,cleanup\nlocal ColorSequence={new=function(a,b) return {a,b} end}\nlocal ColorSequenceKeypoint={new=function(a,b) return {a,b} end}\nlocal NumberSequence={new=function(a) return a end}\nlocal NumberSequenceKeypoint={new=function(a,b) return {a,b} end}\nlocal Main={DisplayOrders={Menu=10},SecureGui=function(gui) securedGui=gui end,AddCleanup=function(fn) cleanup=fn end}\n',
 main_source[main_source.index('\tMain.StudioAssets = {}'):main_source.index('\n\tMain.SetupFilesystem')],
 'local splashControl=(function()\n'+module_file('LoadingSplash').read_text(encoding='utf-8')+'\nend)()\nsplashControl.InitDeps({Main=Main,Settings=Settings,service={},createSimple=createSimple})\nlocal splash=splashControl.Main()\nMain.LoadModule=function(name) assert(name=="LoadingSplash") return splash end\n',
 main_source[main_source.index('\tMain.CreateIntro = function'):main_source.index('\n\tMain.CreateApp')],
 'Main.SetupStudioAssets()\nassert(writes==0 and handles==0,"asset setup does no eager file or handle work")\nassert(Main.GetStudioAsset("used"))\nassert(Main.GetStudioAsset("used"))\nassert(writes==1 and handles==1,"requested asset materializes once")\nMain.GetStudioAsset("other")\nassert(writes==2 and handles==2,"unused assets remain untouched")\nlocal status=Main.CreateIntro("Loading")\nlocal card=securedGui.Status\nassert(card.AnchorPoint.X==.5 and card.AnchorPoint.Y==.5 and card.Position==UDim2.fromScale(.5,.5),"splash is centered")\nlocal constraint=card:FindFirstChildOfClass("UISizeConstraint")\nassert(constraint.MaxSize.X==488 and constraint.MaxSize.Y==280 and card.Size.X.Scale==1 and card.Size.X.Offset==-32,"compact card fits narrow screens")\nassert(card.Brand.Reveal.LogoFallback and card.Message.Text=="Loading","branding fallback works without asset APIs")\nstatus.SetProgress("Loading tools",.75)\nassert(card.Message.Text=="Loading tools" and card.Percent.Text=="75%" and card.Progress.Fill.Size.X.Scale==.75,"real stages update progress")\nstatus.SetProgress(nil,.2) status.SetProgress(nil,0/0) status.SetProgress(nil,math.huge)\nassert(card.Percent.Text=="75%","invalid or older values cannot reverse progress")\nstatus.SetProgress("Ready",2)\nassert(card.Percent.Text=="100%" and card.Progress.Fill.Size.X.Scale==1,"progress is clamped")\nstatus.Close() status.Close() status.SetProgress("Late",0)\nassert(securedGui.Destroyed and card.Message.Text=="Ready","close is idempotent and late updates are ignored")\nStudioAssetData.files["branding/dex/toolbar-white-v1"]="logo"\nlocal again=Main.CreateIntro("Loading")\nassert(securedGui.Status.Brand.Reveal.Logo and not securedGui.Status.Brand.Reveal:FindFirstChild("LogoFallback"),"existing Dex mark is used when available")\ncleanup() again.Close()\nassert(securedGui.Destroyed,"shutdown owns splash cleanup")\nprint("PASS: lazy assets, centered compact splash, branding fallback, real bounded progress and close/shutdown cleanup")\nend']
parts += [r'''
do
local Main = {}
local DefaultSettings = { StudioThemeVersion = 4, Properties = { _Recurse = true, ShowAttributes = true } }
local Settings = { StudioThemeVersion = 4, Properties = { ShowAttributes = true } }
local legacy = "DexSettings.json"
local current = "dex-explorer/settings.json"
local files = { [legacy] = "legacy settings" }
local decoded
local service = { HttpService = {
    JSONDecode = function(_, raw) assert(raw == files[current]) return decoded end,
} }
local env = {
    readfile = function(path) assert(path == current) return files[path] end,
    writefile = function(path, value) assert(path == current) files[path] = value end,
}
local function deserialize(value) return value end
local function copySettings(value) return table.clone(value) end
Main.ExportSettings = function() return "new settings" end
''',
 main_source[main_source.index('\tlocal settingsPath = '):main_source.index('\n\tMain.FetchAPI = function')],
 r'''
Main.LoadSettings()
assert(Settings.Properties.ShowAttributes and files[legacy] == "legacy settings")
assert(Main.SaveSettings() and files[current] == "new settings" and files[legacy] == "legacy settings")
decoded = { StudioThemeVersion = 4, Properties = false }
Main.LoadSettings()
assert(Settings.Properties.ShowAttributes, "bad settings cannot replace the Properties table")
decoded = { StudioThemeVersion = 4, Properties = { ShowAttributes = false } }
Main.LoadSettings()
assert(Settings.Properties.ShowAttributes == false, "isolated settings still load saved preferences")
end
''']
with tempfile.TemporaryDirectory(prefix='dex-checks-') as temp:
    harness = Path(temp) / 'smoke.luau'
    harness.write_text('\n'.join(parts), encoding='utf-8')
    try:
        subprocess.run([args.luau, str(harness)], check=True)
    except subprocess.CalledProcessError:
        debug_dir = root / '.build'
        debug_dir.mkdir(parents=True, exist_ok=True)
        saved = debug_dir / 'last_failed_smoke.luau'
        saved.write_text(harness.read_text(encoding='utf-8'), encoding='utf-8')
        print(f'FAILED SMOKE SAVED: {saved}', flush=True)
        raise
