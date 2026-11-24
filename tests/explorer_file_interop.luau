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
	if control.InitDeps then control.InitDeps({service=service,Apps=apps,env=env}) end
	apps[name] = control.Main()
end
for _, name in {"GltfGeometry","GltfTerrain","GltfFacs","GltfTextures","GltfExporter","ObjExporter","ExplorerFileActions","LocalizationCsv"} do loadModule(name) end
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
local image = {Size=r.Vector2.new(2,1),ReadPixelsBuffer=function() return buffer.fromstring(buffer.tostring(pixels)) end, Destroy=function() end}
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


globals.Region3 = {new=function(min,max) return {Min=min,Max=max} end}
loadModule("GltfTerrain")
local terrain = {Name="Terrain",ClassName="Terrain",WaterColor=r.Color3.fromRGB(30,80,255),WaterTransparency=.25}
function terrain:IsA(class) return class == "Terrain" or class == "BasePart" end
function terrain:GetMaterialColor() return r.Color3.fromRGB(100,150,55) end
local reads = 0
function terrain:ReadVoxels(region,resolution)
	assert(resolution==4 and region.Min.X >= 0 and region.Max.X <= 108)
	reads += 1
	local materials, occupancies = {}, {}
	for x=region.Min.X/4,region.Max.X/4-1 do
		local xi = #materials+1
		materials[xi],occupancies[xi] = {},{}
		for y=region.Min.Y/4,region.Max.Y/4-1 do
			local yi = #materials[xi]+1
			materials[xi][yi],occupancies[xi][yi] = {},{}
			for z=region.Min.Z/4,region.Max.Z/4-1 do
				local water = y==1 and z==2 and x==25
				local solid = y==0 and z<2 and x>=20 and x<=25
				local m = if water then r.Enum.Material.Water elseif solid then r.Enum.Material.Grass else r.Enum.Material.Air
				table.insert(materials[xi][yi],m)
				table.insert(occupancies[xi][yi],if solid then (if x%2==0 then .8 else 1) elseif water then 1 else 0)
			end
		end
	end
	return materials,occupancies
end
local terrainExport, warning = apps.GltfExporter.Export({{Obj=terrain}},{
	TerrainBounds={Min=v3(0,0,0),Max=v3(108,8,12)},
})
assert(reads==2 and not warning)
local terrainDoc = serde.decode("json",terrainExport)
assert(#terrainDoc.meshes==3 and #terrainDoc.materials==2)
for _, item in ipairs(terrainDoc.meshes) do
	assert(item.primitives[1].attributes.COLOR_0)
end
fs.writeFile(".build/fixture-terrain.gltf",terrainExport)
assert(not pcall(apps.GltfTerrain.Bounds,v3(0,0,0),v3(5000,5000,5000)))

local function overlay(name,class,face)
	return {Name=name,ClassName=class,Face=face,Transparency=.15,Color3=r.Color3.fromRGB(100,200,240),
		ColorMapContent="image",ZIndex=0,StudsPerTileU=2,StudsPerTileV=3,OffsetStudsU=.5,OffsetStudsV=1,
		IsA=function() return false end,GetChildren=function() return {} end}
end
local decal = overlay("Front sticker","Decal",r.Enum.NormalId.Front)
local tile = overlay("Right tiles","Texture",r.Enum.NormalId.Right)
local cube = {
	Name="Printed box",ClassName="Part",CFrame=r.CFrame.identity,Size=v3(8,6,4),Color=r.Color3.new(1,1,1),
	Shape=r.Enum.PartType.Block,Transparency=0,Material=r.Enum.Material.Plastic,
	IsA=function(_,class) return class=="Part" or class=="BasePart" end,
	FindFirstChildOfClass=function() end,FindFirstChildWhichIsA=function() end,GetFullName=function() return "Printed box" end,
	GetChildren=function() return {decal,tile} end,
}
local projectFace = apps.GltfGeometry.ProjectFace
local minU,minV = math.huge,math.huge
apps.GltfGeometry.ProjectFace = function(source, size, offset, decal, emit, layer, cancel)
	if decal == tile then
		emit = table.clone(emit)
		local vertex = emit.Vertex
		emit.Vertex = function(g,p,n,uv,...)
			minU,minV = math.min(minU,uv.X),math.min(minV,uv.Y)
			return vertex(g,p,n,uv,...)
		end
	end
	return projectFace(source,size,offset,decal,emit,layer,cancel)
end
local projected, skipped = apps.GltfExporter.Export({{Obj=cube}})
apps.GltfGeometry.ProjectFace = projectFace
assert(math.abs(minU-.25)<1e-6 and math.abs(minV-1/3)<1e-6)

assert(not skipped)
local projectedDoc = serde.decode("json",projected)
assert(#projectedDoc.meshes==3 and #projectedDoc.images==1)
assert(projectedDoc.meshes[2].name=="Front sticker" and projectedDoc.meshes[3].name=="Right tiles")
assert(projectedDoc.accessors[projectedDoc.meshes[3].primitives[1].attributes.TEXCOORD_0+1].count==6)
tile.ResampleMode = {Name="Pixelated"}
local pixelDoc = serde.decode("json",apps.GltfExporter.Export({{Obj=cube}}))
local pixelIndex = pixelDoc.materials[3].pbrMetallicRoughness.baseColorTexture.index
assert(pixelDoc.samplers[1].magFilter==9728 and pixelDoc.textures[pixelIndex+1].sampler==0 and #pixelDoc.images==1)
tile.ResampleMode = nil
fs.writeFile(".build/fixture-overlays.gltf",projected)
local solidOnly = serde.decode("json",apps.GltfExporter.Export({{Obj=cube}},{Textures=false}))
assert(#solidOnly.meshes==1 and not solidOnly.images)
local imageReader = service.AssetService.CreateEditableImageAsync
service.AssetService.CreateEditableImageAsync = function() error("Permission denied") end
local unreadable, omissions = apps.GltfExporter.Export({{Obj=cube}})
assert(#serde.decode("json",unreadable).meshes==1 and omissions:find("Decal image unavailable",1,true))
service.AssetService.CreateEditableImageAsync = imageReader

local jaw, smile = {Name="JawDrop"}, {Name="LeftLipCornerPuller"}
function mesh:GetFacsPoses() return {jaw} end
function mesh:GetFacsPose() return {43},{r.CFrame.new(0,2,0)} end
function mesh:GetFacsCorrectivePoses() return {{smile,jaw}} end
function mesh:GetFacsCorrectivePose() return {43},{r.CFrame.Angles(0,math.pi/4,0)} end
function mesh:GetVertexBones(id) return if id==4 or id==8 then {21,43} else {21} end
function mesh:GetVertexBoneWeights(id) return if id==4 or id==8 then {.6,.4} else {1} end
local facs, facsWarnings = apps.GltfExporter.Export({{Obj=part}},{Textures=false})
assert(not facsWarnings)
local face = serde.decode("json",facs)
local faceMesh = face.meshes[1]
assert(faceMesh.extras.targetNames[1]=="Corrective_JawDrop_LeftLipCornerPuller" and faceMesh.extras.targetNames[2]=="JawDrop")
local direct = face.accessors[faceMesh.primitives[1].targets[2].POSITION+1]
assert(direct.sparse.count==2 and math.abs(direct.max[2]-.224)<1e-5 and direct.min[2]==0)
assert(#face.skins[1].joints==2)
fs.writeFile(".build/fixture-facs.gltf",facs)
local neutral = serde.decode("json",apps.GltfExporter.Export({{Obj=part}},{Skinning=false,Textures=false}))
assert(not neutral.meshes[1].extras and not neutral.skins)
print("Terrain chunk seams and water, tiled face overlays, permissions, and weighted FACS targets exported.")

local objTargets = {root,{Obj=objects[1],Parent=root},{Obj=cube},{Obj=part}}
local files, warnings = apps.ObjExporter.Export(objTargets,".build/fixture export.obj")
assert(not warnings and #files==4)
local obj, mtl = files[#files].data, files[#files-1].data
assert(obj:find("mtllib fixture export.mtl",1,true))
assert(mtl:find("map_Kd fixture export_texture_1.png",1,true))
assert(mtl:find("map_d -imfchan m",1,true) and mtl:find("map_Kd fixture export_texture_2.png",1,true))
assert(obj:find("o Printed box",1,true) and obj:find("o Skinned",1,true))
assert(not obj:find("Bone21",1,true) and not obj:find("OuterCage",1,true))
for _, file in ipairs(files) do fs.writeFile(file.path,file.data) end
local terrainFiles, terrainWarnings = apps.ObjExporter.Export({{Obj=terrain}},".build/fixture terrain.obj",{
	Min=v3(0,0,0),Max=v3(108,8,12),
})
assert(not terrainWarnings and #terrainFiles==2 and terrainFiles[2].data:find("o Water",1,true))
for _, file in ipairs(terrainFiles) do fs.writeFile(file.path,file.data) end
print("OBJ exports static geometry, textured materials and bounded terrain.")
