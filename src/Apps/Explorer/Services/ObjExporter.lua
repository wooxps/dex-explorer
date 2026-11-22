--!strict

local Apps
local Exporter = {}

local function direction(frame, vector)
	return frame.x*vector.X + frame.y*vector.Y + frame.z*vector.Z
end

local function transformed(parent, node)
	local m, t, s = node.matrix, node.translation, node.scale
	local vec = Vector3.new
	local x,y,z = Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
	local position = Vector3.zero
	if m then
		x,y,z = vec(m[1],m[2],m[3]),vec(m[5],m[6],m[7]),vec(m[9],m[10],m[11])
		position = vec(m[13],m[14],m[15])
	else
		if s then x,y,z = x*s[1],y*s[2],z*s[3] end
		if t then position = vec(t[1],t[2],t[3]) end
	end
	return {x=direction(parent,x),y=direction(parent,y),z=direction(parent,z),
		position=parent.position+direction(parent,position)}
end

local function safeName(name)
	return (name:gsub("[%c#\\]", "_"))
end

function Exporter.Export(targets, path, terrainBounds, cancelled)
	local function checkCancelled()
		if cancelled and cancelled() then error("Export cancelled",0) end
	end
	local scene, data, details = Apps.GltfExporter.Build(targets,{
		Skinning=false, Attachments=false, Cages=false, ClassicMaterials=true, TerrainBounds=terrainBounds,
	},cancelled)
	assert(scene.meshes and #scene.meshes > 0, "Select an object containing geometry")
	local metersPerStud = Apps.GltfExporter.MetersPerStud
	local folder, name = path:match("^(.-)([^/]+)$")
	local stem = name:sub(1,-5)
	local model = {"# Dex Explorer", "mtllib " .. stem .. ".mtl"}
	local materials, files, imageNames = {}, {}, {}
	local writtenGroups = {}
	local vertices, texcoords, normals, count = 0,0,0,0

	local function viewOf(index)
		return scene.bufferViews[index+1]
	end

	local function elements(index)
		if index == nil then return nil end
		local accessor = scene.accessors[index+1]
		return (viewOf(accessor.bufferView).byteOffset or 0) + (accessor.byteOffset or 0), accessor.count
	end

	local function imageFile(texture)
		local source = scene.textures[texture.index+1].source
		if not imageNames[source] then
			local view = viewOf(scene.images[source+1].bufferView)
			local filename = stem .. "_texture_" .. (source+1) .. ".png"
			imageNames[source] = filename
			table.insert(files,{path=folder .. filename,data=buffer.readstring(data,view.byteOffset or 0,view.byteLength)})
		end
		return imageNames[source]
	end

	local function materialFor(index, objectName)
		local material = scene.materials and scene.materials[(index or -1)+1]
		local pbr = material and material.pbrMetallicRoughness
		local rgb = pbr and pbr.baseColorFactor or {1,1,1,1}
		local name = "material_" .. tostring(count) .. "_" .. objectName:gsub("[^%w_-]","_")
		table.insert(materials,"newmtl " .. name)
		table.insert(materials,string.format("Kd %.9g %.9g %.9g",rgb[1],rgb[2],rgb[3]))
		table.insert(materials,string.format("d %.9g",rgb[4]))
		table.insert(materials,"illum 1")
		if pbr and pbr.baseColorTexture then
			local image = imageFile(pbr.baseColorTexture)
			table.insert(materials,"map_Kd " .. image)
			if material.alphaMode == "BLEND" then table.insert(materials,"map_d -imfchan m " .. image) end
		end
		table.insert(materials,"")
		return name
	end

	local function vectorAt(offset)
		return Vector3.new(buffer.readf32(data,offset),buffer.readf32(data,offset+4),buffer.readf32(data,offset+8))
	end

	local function writePrimitive(primitive, frame, objectName)
		count += 1
		table.insert(model,"usemtl " .. materialFor(primitive.material,objectName))
		local attributes = primitive.attributes
		local position, vertexCount = elements(attributes.POSITION)
		local normal = elements(attributes.NORMAL)
		local uv = elements(attributes.TEXCOORD_0)
		local color = elements(attributes.COLOR_0)
		local nx,ny,nz = frame.y:Cross(frame.z), frame.z:Cross(frame.x), frame.x:Cross(frame.y)
		local sign = if frame.x:Dot(nx) < 0 then -1 else 1
		local normalFrame = {x=nx*sign,y=ny*sign,z=nz*sign}
		for i = 0,vertexCount-1 do
			local p = (frame.position+direction(frame,vectorAt(position+i*12)))/metersPerStud
			if color then
				local c = vectorAt(color+i*16)
				table.insert(model,string.format("v %.9g %.9g %.9g %.9g %.9g %.9g",p.X,p.Y,p.Z,c.X,c.Y,c.Z))
			else
				table.insert(model,string.format("v %.9g %.9g %.9g",p.X,p.Y,p.Z))
			end
			if uv then
				local offset = uv+i*8
				table.insert(model,string.format("vt %.9g %.9g",buffer.readf32(data,offset),1-buffer.readf32(data,offset+4)))
			end
			if normal then
				local n = direction(normalFrame,vectorAt(normal+i*12))
				n = if n.Magnitude > 0 then n.Unit else Vector3.yAxis
				table.insert(model,string.format("vn %.9g %.9g %.9g",n.X,n.Y,n.Z))
			end
			if i % 8192 == 8191 then task.wait(); checkCancelled() end
		end

		local readIndex, index, stride, faceCorners
		if primitive.indices ~= nil then
			local accessor = scene.accessors[primitive.indices+1]
			stride = if accessor.componentType == 5123 then 2 else 4
			readIndex = if stride == 2 then buffer.readu16 else buffer.readu32
			index, faceCorners = elements(primitive.indices)
		else
			faceCorners = vertexCount
		end
		local function corner(i)
			local v = if readIndex then readIndex(data,index+i*stride)+1 else i+1
			if uv and normal then return string.format("%d/%d/%d",vertices+v,texcoords+v,normals+v) end
			if normal then return string.format("%d//%d",vertices+v,normals+v) end
			if uv then return string.format("%d/%d",vertices+v,texcoords+v) end
			return tostring(vertices+v)
		end
		for i = 0,faceCorners-1,3 do
			local b,c = i+1,i+2
			if sign < 0 then b,c = c,b end
			table.insert(model,"f " .. corner(i) .. " " .. corner(b) .. " " .. corner(c))
			if i % 24576 == 24573 then task.wait(); checkCancelled() end
		end
		vertices += vertexCount
		if uv then texcoords += vertexCount end
		if normal then normals += vertexCount end
	end

	local function visit(index, parent)
		checkCancelled()
		local node = scene.nodes[index+1]
		local frame = transformed(parent,node)
		if node.mesh ~= nil then
			local mesh = scene.meshes[node.mesh+1]
			local label = safeName((node.name or mesh.name or "Object"):gsub(" geometry$",""))
			local base = if label == "" then "Object" else label
			local unique, suffix = base, 1
			while writtenGroups[unique] do suffix += 1; unique = base .. "_" .. suffix end
			writtenGroups[unique] = true
			table.insert(model,"o " .. unique)
			for _, primitive in ipairs(mesh.primitives) do writePrimitive(primitive,frame,unique) end
		end
		for _, child in ipairs(node.children or {}) do visit(child,frame) end
	end

	local identity = {x=Vector3.xAxis,y=Vector3.yAxis,z=Vector3.zAxis,position=Vector3.zero}
	for _, index in ipairs(scene.scenes[scene.scene+1].nodes) do visit(index,identity) end
	table.insert(files,{path=folder .. stem .. ".mtl",data=table.concat(materials,"\n") .. "\n"})
	table.insert(files,{path=path,data=table.concat(model,"\n") .. "\n"})
	return files, details
end

return {
	InitDeps=function(d) Apps = d.Apps end, InitAfterMain=function() end,
	Main=function() return Exporter end,
}
