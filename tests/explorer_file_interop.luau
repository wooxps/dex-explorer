-- Run from the repository root with Lune 0.8.9. Writes glTF validation fixtures to .build.
local fs = require("@lune/fs")
local r = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")
local base = "src/Apps/Explorer/Services/"
local globals = {game = {GetObjects=function(_,path) return r.deserializeModel(fs.readFile(path)) end}, Vector3=r.Vector3, Vector2=r.Vector2, Color3=r.Color3, CFrame=r.CFrame, Enum=r.Enum, task=task, Content={none="none"}}
local service, apps, env = {}, {}, {}
local function loadModule(name)
	local fn = require("@lune/luau").load(fs.readFile(base .. name .. ".lua"), {debugName=name, environment=globals, injectGlobals=true})
	local control = fn()
	control.InitDeps({service=service,Apps=apps,env=env})
	apps[name] = control.Main()
end
for _, name in {"GltfGeometry","GltfTextures","GltfExporter","ExplorerFileActions","LocalizationCsv"} do loadModule(name) end
local function base64(s)
	local characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local chars = {}
	for i=1,#s,3 do
		local a,b,c = s:byte(i,i+2)
		local n = a*65536 + (b or 0)*256 + (c or 0)
		for j=0,3 do
			local v=bit32.extract(n,18-6*j,6)+1
			table.insert(chars, if j>1 and i+j-1>#s then "=" else characters:sub(v,v))
		end
	end
	return table.concat(chars)
end
service.HttpService = {JSONEncode=function(_,v) return serde.encode("json",v) end}
service.EncodingService = {Base64Encode=function(_,b) return buffer.fromstring(base64(buffer.tostring(b))) end}
local folder=r.Instance.new("Folder")
folder.Name="Scene"
local objects={}
for i,shape in {"Block","Ball","Cylinder","Wedge","CornerWedge"} do
	local part=r.Instance.new("Part")
	part.Name=shape
	part.Shape=r.Enum.PartType[shape]
	part.Size=r.Vector3.new(4,6,2)
	part.Color=r.Color3.fromRGB(200,80,25)
	part.Transparency=.2
	part.CFrame=r.CFrame.new(i*3,2,1)*r.CFrame.Angles(0,1,0)
	part.Parent=folder
	table.insert(objects,part)
end
local root={Obj=folder}
local doc=apps.GltfExporter.Export({root,{Obj=objects[1],Parent=root}})
local scene = serde.decode("json",doc)
assert(#scene.scenes[1].nodes == 1 and #scene.meshes == 5)
fs.writeFile(".build/fixture-primitives.gltf",doc)
local mesh = {}
local v3=r.Vector3.new
function mesh:GetFaces() return {123} end
function mesh:GetBones() return {21,43} end
function mesh:GetFaceVertices() return {4,8,12,16} end
function mesh:GetPosition(v) return ({[4]=v3(0,0,0),[8]=v3(1,0,0),[12]=v3(1,1,0),[16]=v3(0,1,0)})[v] end
function mesh:GetFaceNormals() return {1,1,1,1} end
function mesh:GetFaceUVs() return {1,2,3,4} end
function mesh:GetFaceColors() return {1,1,1,1} end
function mesh:GetNormal() return v3(0,0,1) end
function mesh:GetUV(id) return ({r.Vector2.new(0,0),r.Vector2.new(1,0),r.Vector2.new(1,1),r.Vector2.new(0,1)})[id] end
function mesh:GetColor() return r.Color3.new(1,1,1) end
function mesh:GetColorAlpha() return 1 end
function mesh:GetBoneCFrame(id) return r.CFrame.new(0,id==43 and 1 or 0,0) end
function mesh:GetBoneParent(id) return id==43 and 21 or 0 end
function mesh:GetBoneName(id) return "Bone"..id end
function mesh:GetVertexBones() return {21,43} end
function mesh:GetVertexBoneWeights() return {.6,.4} end
function mesh:Destroy() end
local pixels=buffer.fromstring(string.char(255,0,0,255, 0,255,0,128))
local image = {Size=r.Vector2.new(2,1),ReadPixelsBuffer=function() return pixels end, Destroy=function() end}
service.AssetService={CreateEditableMeshAsync=function() return mesh end, CreateEditableImageAsync=function() return image end}
local part = {
	Name="Skinned",CFrame=r.CFrame.new(1,2,3),Size=v3(2,2,2),MeshSize=v3(1,1,1),
	MeshContent="mesh",TextureContent="image",Color=r.Color3.new(1,1,1),Transparency=.1,DoubleSided=true,Material=r.Enum.Material.Plastic,
	FindFirstChildOfClass=function() end, GetChildren=function() return {} end,GetFullName=function() return "Skinned" end,
	IsA=function(_,class) return class=="MeshPart" or class=="BasePart" end,
}
local skin = apps.GltfExporter.Export({{Obj=part}})
fs.writeFile(".build/fixture-skin.gltf",skin)
local parsed = serde.decode("json",skin)
assert(#parsed.skins == 1 and #parsed.skins[1].joints == 2 and #parsed.images == 1)
assert(parsed.accessors[parsed.meshes[1].primitives[1].indices+1].count == 6)

local a,b=r.Instance.new("Folder"),r.Instance.new("ObjectValue")
a.Name="Root A"; b.Name="Root B"; b.Value=a
local nodes={}
local function node(obj)
	if not nodes[obj] then nodes[obj]={Obj=obj} end
	return nodes[obj]
end
local selected
local history = {}
apps.Explorer={GetNodes=function() return nodes end,Selection={SetTable=function(_,rows) selected=rows end},ViewNode=function() end}
apps.History={Run=function(_,f) return f() end,Set=function(o,k,v) o[k]=v;node(o);table.insert(history,o) end}
env.readfile=fs.readFile
service.SerializationService={DeserializeInstancesAsync=function(_,data) return r.deserializeModel(buffer.tostring(data)) end}
env.getcustomasset=function(path) return path end
for _,ext in {"rbxm","rbxmx"} do
	local path=".build/file-fixture."..ext
	fs.writeFile(path,r.serializeModel({a,b},ext=="rbxmx"))
	apps.ExplorerFileActions.Insert(path,{node(folder),node(objects[1])})
	assert(#selected==4 and selected[2].Obj.Value==selected[1].Obj and selected[4].Obj.Value==selected[3].Obj)
	assert(selected[1].Obj.Parent==folder and selected[3].Obj.Parent==objects[1])
end
print("File import preserves both roots, cross-root references, and independent copies for both destinations.")

local surface = {Color=r.Color3.fromRGB(128,255,255), AlphaMode=r.Enum.AlphaMode.Overlay, ColorMapContent="color", NormalMapContent="normal",MetalnessMapContent="metal",RoughnessMapContent="rough", EmissiveMaskContent="emissive",EmissiveTint=r.Color3.new(1,.5,.2),EmissiveStrength=1.2}
part.FindFirstChildOfClass=function() return surface end
local pbr = apps.GltfExporter.Export({{Obj=part}})
fs.writeFile(".build/fixture-pbr.gltf",pbr)

local attachment = {Name="Mount",ClassName="Attachment",WorldCFrame=r.CFrame.new(1,4,3),
	IsA=function() return false end, GetChildren=function() return {} end}
local wrap = {Name="Wrap",ClassName="WrapLayer",Parent=part,CageOrigin=r.CFrame.new(0,1,0),
	ReferenceOrigin=r.CFrame.new(0,-1,0),CageMeshContent="outer",ReferenceMeshContent="inner",
	IsA=function() return false end,GetChildren=function() return {} end}
part.GetChildren=function() return {attachment,wrap} end
local function output(opts)
	local bytes = apps.GltfExporter.Export({{Obj=part}},opts)
	return serde.decode("json",bytes),bytes
end
local function named(doc,name)
	for _,n in ipairs(doc.nodes) do if n.name==name then return n end end
end
local default = output()
assert(default.skins and default.images and named(default,"Mount") and not named(default,"Skinned_OuterCage"))
local lean = output({Skinning=false,Textures=false,Attachments=false})
assert(not lean.skins and not lean.images and not named(lean,"Mount") and not named(lean,"Skinned_OuterCage"))
assert(not lean.meshes[1].primitives[1].attributes.JOINTS_0 and not lean.meshes[1].primitives[1].attributes.TANGENT)
local caged, data = output({Cages=true})
assert(named(caged,"Skinned_OuterCage").mesh and named(caged,"Skinned_InnerCage").mesh)
fs.writeFile(".build/fixture-cages.gltf",data)
local marker = serde.decode("json", apps.GltfExporter.Export({{Obj=attachment}}))
assert(#marker.nodes==1 and marker.nodes[1].name=="Mount" and not marker.buffers)
print("Export options include and omit skins, images, attachments and both cage meshes.")
