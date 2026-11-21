from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
lib=(ROOT/'src/Shared/Lib.lua').read_text();props=(ROOT/'src/Apps/Properties/Properties.lua').read_text()
prefix=lib[lib.index('\tLib.StudioFont ='):lib.index('\n\tlocal renderStepped')]
search=props[props.index('\tProperties.InitSearch = function()'):props.index('\n\tProperties.InitEntryStuff')]
fixture=(ROOT/'tests/roblox_mock.luau').read_text()+"""
function methods:IsFocused() return service.UserInputService.Focus==self end
local Colors={Outline=Color3.fromRGB(53,55,65),Surface=Color3.fromRGB(25,26,31)}
local propertyFont=Enum.Font.SourceSans
local View={ToolbarHeight=25,FilterHeight=21}
local toolbar=Instance.new("Frame") toolbar.Size=UDim2.fromOffset(340,26)
local field=Instance.new("Frame",toolbar) field.Name="SearchFrame"
Instance.new("UICorner",field)
local box=Instance.new("TextBox",field) box.Name="SearchBox" box.Text=""
local reset=Instance.new("TextButton",field) reset.Name="Reset"
local icon=Instance.new("ImageLabel",reset) icon.Name="ImageLabel"
local window={IsVisible=function() return true end}
local Properties={GuiElems={ToolBar=toolbar},InitObjectPicker=function() end,Update=function() end,Refresh=function() end}
"""+prefix+search+"""
Properties.InitSearch()
assert(not field:FindFirstChildOfClass("UICorner"),"pixel border must not retain a UICorner that suppresses native border rendering")
local stroke=field:FindFirstChildOfClass("UIStroke")
assert(not stroke.Enabled and field.BorderSizePixel==1 and field.BorderMode==Enum.BorderMode.Inset and field.BorderColor3.R==40/255,"solid inset border preserves the latest reference RGB without a blended UIStroke")
field.MouseEnter:Fire() assert(not stroke.Enabled and field.BorderColor3.R==102/255,"filter hover brightens pixel border")
field.MouseLeave:Fire() assert(not stroke.Enabled and field.BorderColor3.R==40/255,"filter leave restores pixel border")
assert(field.BackgroundColor3==Colors.Surface and box.Font==Enum.Font.SourceSans and box.TextSize==14,"filter uses local Properties text styling")
field.MouseEnter:Fire() assert(field.BackgroundColor3==Colors.Surface,"filter hover changes only the border")
field.MouseLeave:Fire() assert(field.BackgroundColor3==Colors.Surface,"filter surface restores on exit")
Properties.GuiElems.FilterDropdown.Activated:Fire()
assert(box:IsFocused() and field.BorderColor3==Settings.Theme.Focus,"chevron focuses field without altering search")
field.MouseEnter:Fire() field.MouseLeave:Fire() assert(field.BorderColor3==Settings.Theme.Focus,"focus takes precedence over hover")
box:ReleaseFocus() assert(not stroke.Enabled and field.BorderColor3.R==40/255,"blur restores persistent pixel border")
assert(field.Position.X.Offset==1 and field.Position.Y.Offset==0 and toolbar.Size.Y.Offset==25 and field.Size.X.Offset==-2 and field.Size.Y.Offset==21,"Properties filter follows the reference 1px side insets and 4px grid spacing")
local button=Properties.GuiElems.FilterDropdown
assert(button.Size.X.Offset==16 and button.ImageLabel.Size.X.Offset==12 and button.ImageLabel.Position.X.Offset==2 and button.ImageLabel.Image:find("native/panel-v2/dropdown",1,true),"smaller centered dropdown keeps its full focus hit area")
button.MouseEnter:Fire() assert(button.BackgroundTransparency==0)
button.MouseLeave:Fire() assert(button.BackgroundTransparency==1,"button hover clears on exit")
button.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1}) button.MouseLeave:Fire()
assert(button.BackgroundTransparency==1,"leaving while pressed never sticks")
local anim=Lib.PanelButtonHover(button) anim.Disable() button.MouseEnter:Fire() assert(button.BackgroundTransparency==1) anim.Enable() button.MouseLeave:Fire() assert(button.BackgroundTransparency==1)
local guiMain={TopBar={ZIndex=1}} for _,name in ipairs({"Close","Minimize"}) do local b=Instance.new("TextButton") local im=Instance.new("ImageLabel",b) im.Name="ImageLabel" guiMain.TopBar[name]=b end
"""
a=lib.index('\t\t\tfor i, name in ipairs({ "Close", "Minimize" })');b=lib.index('\n\t\t\tguiMain.Outlines',a)
fixture+=lib[a:b]+"""
for _,name in ipairs({"Close","Minimize"}) do local b=guiMain.TopBar[name] assert(b.Size.X.Offset==16 and b.ImageLabel.Size.X.Offset==16 and b.ImageLabel.ZIndex>b.ZIndex,"native titlebar button geometry and layering") end
print("PASS: native filter border/hover/focus/chevron, compact geometry, non-sticky square buttons and titlebar sizing/layers")
"""
fixture+='local plr=service.Players.LocalPlayer\n'+lib[lib.index('\tLib.ScrollBar = (function()'):lib.index('\n\tLib.Window = (function()')]+"""
for _,horizontal in ipairs({false,true}) do
 local bar=Lib.ScrollBar.new(horizontal) bar:UseLegacyStudioStyle()
 local rail,thumb=bar.GuiElems.ScrollThumbFrame,bar.GuiElems.ScrollThumb
 assert(rail.AutoButtonColor==false and rail.BackgroundTransparency==0)
 local railColor=rail.BackgroundColor3
 thumb.MouseEnter:Fire()
 assert(thumb.BackgroundColor3==bar.LegacyHoverColor)
 thumb.InputBegan:Fire({UserInputType=Enum.UserInputType.MouseButton1})
 assert(thumb.BackgroundColor3==bar.LegacyHoverColor)
 thumb.MouseLeave:Fire()
 assert(thumb.BackgroundColor3==bar.ThumbColor and rail.BackgroundColor3==railColor)
 thumb.MouseEnter:Fire()
 assert(thumb.BackgroundColor3==bar.LegacyHoverColor and rail.BackgroundColor3==railColor)
 service.UserInputService.InputEnded:Fire({UserInputType=Enum.UserInputType.MouseButton1})
 bar.TotalSpace=100 bar.VisibleSpace=10
 local up,down=bar.GuiElems.Button1.StudioArrow,bar.GuiElems.Button2.StudioArrow
 for _,length in ipairs({200,80,300}) do
  bar.Gui.Size=horizontal and UDim2.fromOffset(length,16) or UDim2.fromOffset(16,length)
  local track=bar.GuiElems.ScrollThumbFrame
  local along=horizontal and "X" or "Y" local across=horizontal and "Y" or "X"
  bar:ScrollTo(90) track:GetPropertyChangedSignal("AbsoluteSize"):Fire()
  assert(not bar:CanScrollDown() and up.ImageTransparency==0 and down.ImageTransparency==0,"end of track keeps arrows at full opacity")
  assert(track.AbsoluteSize[across]==14 and track.Position[across].Offset==1,"14px rail centered inside 16px allocation")
  local thumb=bar.GuiElems.ScrollThumb
  assert(thumb.Size[across].Offset==12 and thumb.Position[across].Offset==1,"thumb leaves 2px total from each outer edge")
  assert(thumb.Position[along].Offset+thumb.Size[along].Offset==length-32,"bottom endpoint remains between arrow buttons")
  bar:ScrollTo(0) assert(thumb.Position[along].Offset==0)
  assert(not bar:CanScrollUp() and up.ImageTransparency==0 and down.ImageTransparency==0,"start of track keeps arrows at full opacity")
  for _,b in ipairs({bar.GuiElems.Button1,bar.GuiElems.Button2}) do
   assert(b.Size[across].Offset==14 and b.Position[across].Offset==1,"arrow controls follow same inset")
  end
 end
end
print("PASS: horizontal/vertical legacy rail insets, arrow alignment and resized thumb endpoints")
"""
row=(ROOT/'src/Apps/Properties/Components/PropertyRow.lua').read_text()
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'check.luau';p.write_text(fixture)
 subprocess.run([str(ROOT/'.tools/bin/luau.exe'),str(p)],check=True)
