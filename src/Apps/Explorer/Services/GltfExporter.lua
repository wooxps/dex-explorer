--!strict

local Apps, service
local Exporter = {}
local meters = 0.28

local function matrix(frame)
	local x,y,z, a,b,c, d,e,f, g,h,i = frame:GetComponents()
	return { a,d,g,0, b,e,h,0, c,f,i,0, x*meters,y*meters,z*meters,1 }
end

local function linear(srgb)
	return if srgb <= .04045 then srgb/12.92 else ((srgb+.055)/1.055)^2.4
end

local function add(array, value)
	local index = #array
	array[index + 1] = value
	return index
end

function Exporter.Export(targets)
	local scene = { nodes = {} }
	local doc = { asset = { version = "2.0", generator = "Dex Explorer" }, scene = 0, scenes = { scene },
		nodes = {}, meshes = {}, materials = {}, bufferViews = {}, accessors = {} }
	local chunks, length = {}, 0
	local function view(bytes, target)
		local padding = -length % 4
		if padding > 0 then table.insert(chunks, string.rep("\0", padding)); length += padding end
		local id = add(doc.bufferViews, { buffer = 0, byteOffset = length, byteLength = #bytes, target = target })
		table.insert(chunks, bytes)
		length += #bytes
		return id
	end
	local function accessor(bytes, kind, component, count, target, min, max)
		return add(doc.accessors, { bufferView = view(bytes, target), componentType = component, count = count,
			type = kind, min = min, max = max })
	end
	local function appendNode(parent, data)
		parent.children = parent.children or {}
		table.insert(parent.children, add(doc.nodes, data))
		return data
	end

	local emit = {}
	function emit.Begin(faces, indexed, skinned)
		return { pos = {}, normals = {}, uv = {}, colors = {}, indices = indexed and table.create(faces*3),
			vertices = skinned and {}, min = Vector3.new(math.huge,math.huge,math.huge),
			max = Vector3.new(-math.huge,-math.huge,-math.huge) }
	end
	function emit.Vertex(g, p, n, uv, color, alpha, sourceId)
		p *= meters
		local i = #g.pos + 1
		g.pos[i] = string.pack("<fff", p.X, p.Y, p.Z)
		g.normals[i] = string.pack("<fff", n.X, n.Y, n.Z)
		g.min = g.min:Min(p)
		g.max = g.max:Max(p)
		if g.indices then
			g.uv[i] = if uv then string.pack("<ff", uv.X, uv.Y) else string.rep("\0",8)
			g.hasUV = g.hasUV or uv ~= nil
			g.colors[i] = if color then string.pack("<ffff",linear(color.R),linear(color.G),linear(color.B),alpha or 1)
				else string.pack("<ffff",1,1,1,1)
			g.hasColor = g.hasColor or color ~= nil
			g.blend = g.blend or (alpha ~= nil and alpha < 1)
		end
		if g.vertices then g.vertices[i] = sourceId end
		return i-1
	end
	function emit.Tangent(g, index, tangent, bitangent)
		g.tangents = g.tangents or {}
		local i = index+1
		local sum = g.tangents[i]
		if sum then sum[1] += tangent; sum[2] += bitangent else g.tangents[i] = {tangent,bitangent} end
	end
	function emit.Index(g, index) table.insert(g.indices, index) end
	function emit.Finish(g, mesh, bones)
		local n = #g.pos
		assert(n > 0, "Geometry contains no vertices")
		local attrs = {
			POSITION = accessor(table.concat(g.pos),"VEC3",5126,n,34962,{g.min.X,g.min.Y,g.min.Z},{g.max.X,g.max.Y,g.max.Z}),
			NORMAL = accessor(table.concat(g.normals),"VEC3",5126,n,34962),
		}
		if g.tangents then
			local packed = table.create(n)
			for i, sum in ipairs(g.tangents) do
				local x,y,z = string.unpack("<fff", g.normals[i])
				local normal = Vector3.new(x,y,z)
				local t = sum[1] - normal*normal:Dot(sum[1])
				if t.Magnitude < 1e-8 then
					t = normal:Cross(if math.abs(normal.X) < .9 then Vector3.xAxis else Vector3.yAxis)
				end
				t = t.Unit
				local sign = if normal:Cross(t):Dot(sum[2]) < 0 then -1 else 1
				packed[i] = string.pack("<ffff",t.X,t.Y,t.Z,sign)
			end
			attrs.TANGENT = accessor(table.concat(packed),"VEC4",5126,n,34962)
		end
		if g.hasUV then attrs.TEXCOORD_0 = accessor(table.concat(g.uv),"VEC2",5126,n,34962) end
		if g.hasColor then attrs.COLOR_0 = accessor(table.concat(g.colors),"VEC4",5126,n,34962) end
		local geometry = { attrs = attrs, blend = g.blend }
		if g.indices then
			local small = n <= 65535
			local fmt = if small then "<I2" else "<I4"
			for i, index in ipairs(g.indices) do g.indices[i] = string.pack(fmt, index) end
			geometry.indices = accessor(table.concat(g.indices),"SCALAR",if small then 5123 else 5125,#g.indices,34963)
		end
		if g.vertices then
			local slots, joints, inverses = {}, {}, {}
			for i, id in ipairs(bones) do
				local frame = mesh:GetBoneCFrame(id)
				slots[id] = i-1
				joints[i] = { frame = frame, parent = mesh:GetBoneParent(id), name = mesh:GetBoneName(id) }
				inverses[i] = string.pack("<" .. string.rep("f",16),table.unpack(matrix(frame:Inverse())))
			end
			for _, joint in ipairs(joints) do joint.parent = slots[joint.parent] end
			local weightsByVertex, sets = {}, 1
			for _, id in ipairs(g.vertices) do
				if not weightsByVertex[id] then
					local ids, weights = mesh:GetVertexBones(id), mesh:GetVertexBoneWeights(id)
					local influence, sum = {}, 0
					for i, bone in ipairs(ids) do
						if weights[i] > 0 then
							table.insert(influence, { slots[bone], weights[i] })
							sum += weights[i]
						end
					end
					if sum == 0 then influence = {{0,1}} else
						for _, w in ipairs(influence) do w[2] /= sum end
					end
					weightsByVertex[id] = influence
					sets = math.max(sets, math.ceil(#influence/4))
				end
			end
			for set = 0, sets-1 do
				local ids, weights = {}, {}
				for i, id in ipairs(g.vertices) do
					local influence = weightsByVertex[id]
					local j, w = {0,0,0,0}, {0,0,0,0}
					for k = 1,4 do
						local pair = influence[4*set+k]
						if pair then j[k], w[k] = pair[1], pair[2] end
					end
					ids[i] = string.pack("<I2I2I2I2",table.unpack(j))
					weights[i] = string.pack("<ffff",table.unpack(w))
				end
				attrs["JOINTS_" .. set] = accessor(table.concat(ids),"VEC4",5123,n,34962)
				attrs["WEIGHTS_" .. set] = accessor(table.concat(weights),"VEC4",5126,n,34962)
			end
			geometry.joints = joints
			geometry.inverse = accessor(table.concat(inverses),"MAT4",5126,#joints)
		end
		return geometry
	end

	local texture, packedMaps = Apps.GltfTextures.Create(function(png)
		doc.images, doc.textures = doc.images or {}, doc.textures or {}
		local image = add(doc.images, { bufferView = view(png), mimeType = "image/png" })
		return add(doc.textures, { source = image })
	end)
	local materials, shapes, meshes, primitives = {}, {}, {}, {}
	local function material(part, surface, tex, blend)
		local color = if surface then surface.Color else part.Color
		local alpha = 1 - part.Transparency
		local key = string.pack("<ffff",color.R,color.G,color.B,alpha) .. part.Material.Name .. tostring(blend)
		local bucket = materials[surface or tex or false] or {}
		materials[surface or tex or false] = bucket
		local twoSided = part:IsA("MeshPart") and part.DoubleSided or false
		key ..= tostring(twoSided)
		if surface then key ..= string.pack("<fff", part.Color.R, part.Color.G, part.Color.B) end
		if bucket[key] then return bucket[key] end
		local pbr = { baseColorFactor = {linear(color.R),linear(color.G),linear(color.B),alpha}, metallicFactor = 0, roughnessFactor = 1 }
		local data = { name = part.Material.Name, pbrMetallicRoughness = pbr, doubleSided = twoSided }
		if surface then
			if surface.AlphaMode == Enum.AlphaMode.Overlay and surface.ColorMapContent ~= Content.none then
				pbr.baseColorTexture = texture(surface.ColorMapContent, part.Color, color)
				pbr.baseColorFactor = {1,1,1,alpha}
			else
				pbr.baseColorTexture = texture(surface.ColorMapContent)
			end
			data.normalTexture = texture(surface.NormalMapContent)
			pbr.metallicRoughnessTexture = packedMaps(surface.MetalnessMapContent, surface.RoughnessMapContent)
			if pbr.metallicRoughnessTexture then pbr.metallicFactor = 1 end
			if surface.AlphaMode == Enum.AlphaMode.Transparency then blend = true end
			local emissive = texture(surface.EmissiveMaskContent)
			if emissive then
				local tint = surface.EmissiveTint
				data.emissiveTexture = emissive
				data.emissiveFactor = {linear(tint.R),linear(tint.G),linear(tint.B)}
				if surface.EmissiveStrength ~= 1 then
					data.extensions = { KHR_materials_emissive_strength = { emissiveStrength = surface.EmissiveStrength } }
					doc.extensionsUsed = {"KHR_materials_emissive_strength"}
				end
			end
		elseif tex then
			local texAlpha
			pbr.baseColorTexture, texAlpha = texture(tex)
			blend = blend or texAlpha
		end
		if alpha < 1 or blend then data.alphaMode = "BLEND" end
		bucket[key] = add(doc.materials, data)
		return bucket[key]
	end

	local function attachMesh(node, part, geometry, scale, offset, surface, tex)
		local mat = material(part, surface, tex, geometry.blend)
		local bucket = primitives[geometry] or {}
		primitives[geometry] = bucket
		if not bucket[mat] then
			bucket[mat] = add(doc.meshes, { name = part.Name, primitives = {{
				attributes = geometry.attrs, indices = geometry.indices, material = mat,
			}} })
		end
		local visual = appendNode(node, { name = part.Name .. " geometry",
			scale = {scale.X,scale.Y,scale.Z}, translation = {offset.X*meters,offset.Y*meters,offset.Z*meters} })
		if not geometry.joints then visual.mesh = bucket[mat]; return end
		local ids = {}
		for i, joint in ipairs(geometry.joints) do
			local parent = joint.parent and geometry.joints[joint.parent+1]
			local localFrame = if parent then parent.frame:ToObjectSpace(joint.frame) else joint.frame
			ids[i] = add(doc.nodes, {name = joint.name, matrix = if localFrame ~= CFrame.identity then matrix(localFrame) else nil})
		end
		for i, joint in ipairs(geometry.joints) do
			local parent = if joint.parent then doc.nodes[ids[joint.parent+1]+1] else visual
			parent.children = parent.children or {}
			table.insert(parent.children, ids[i])
		end
		doc.skins = doc.skins or {}
		local skin = add(doc.skins, { joints = ids, inverseBindMatrices = geometry.inverse })
		table.insert(scene.nodes, add(doc.nodes, { name = part.Name .. " skin", mesh = bucket[mat], skin = skin }))
	end

	local function readGeometry(content, surface)
		local tangents = surface ~= nil and surface.NormalMapContent ~= Content.none
		local bucket = meshes[tangents] or {}
		meshes[tangents] = bucket
		if not bucket[content] then bucket[content] = Apps.GltfGeometry.ReadMesh(content, emit, tangents) end
		return bucket[content]
	end
	local function renderScale(part)
		local size, original = part.Size, part.MeshSize
		return Vector3.new(if original.X == 0 then 1 else size.X/original.X,
			if original.Y == 0 then 1 else size.Y/original.Y, if original.Z == 0 then 1 else size.Z/original.Z)
	end
	local function exportPart(node, part)
		local size, offset, shape, meshContent, tex = part.Size, Vector3.zero, nil, nil, nil
		local surface = part:FindFirstChildOfClass("SurfaceAppearance")
		if part:IsA("MeshPart") then
			meshContent, tex = part.MeshContent, part.TextureContent
			size = renderScale(part)
		elseif part:IsA("PartOperation") or part:IsA("TrussPart") then
			local baked = service.GeometryService:BakeToMeshAsync(part, {})
			assert(baked, "This runtime cannot convert " .. part.ClassName .. " to a mesh")
			local ok, err = pcall(function()
				local frame = part.CFrame:ToObjectSpace(baked.CFrame)
				local anchor = if frame == CFrame.identity then node else appendNode(node, {name=part.Name, matrix=matrix(frame)})
				attachMesh(anchor, part, readGeometry(baked.MeshContent, surface), renderScale(baked), Vector3.zero, surface, baked.TextureContent)
			end)
			baked:Destroy()
			if not ok then error(err, 0) end
			return
		else
			local modifier = part:FindFirstChildWhichIsA("DataModelMesh")
			if modifier then
				offset = modifier.Offset
				if modifier:IsA("SpecialMesh") and modifier.MeshType.Name == "FileMesh" then
					meshContent = Content.fromUri(modifier.MeshId)
					if modifier.TextureId ~= "" then tex = Content.fromUri(modifier.TextureId) end
					size = modifier.Scale
				else
					local kind = if modifier:IsA("SpecialMesh") then modifier.MeshType.Name else modifier.ClassName
					shape = ({ Brick = "Block", BlockMesh = "Block", CylinderMesh = "Cylinder", Sphere = "Ball" })[kind] or kind
					size *= modifier.Scale
				end
			elseif part:IsA("WedgePart") then shape = "Wedge"
			elseif part:IsA("CornerWedgePart") then shape = "CornerWedge"
			elseif part:IsA("Part") then shape = part.Shape.Name
			elseif part:IsA("Seat") or part:IsA("VehicleSeat") or part:IsA("SpawnLocation") then shape = "Block"
			else error("Unsupported geometry: " .. part.ClassName, 0) end
		end
		local geometry
		if meshContent then
			geometry = readGeometry(meshContent, surface)
		else
			if not shapes[shape] then shapes[shape] = Apps.GltfGeometry.Primitive(shape, emit) end
			geometry = shapes[shape]
		end
		attachMesh(node, part, geometry, size, offset, surface, tex)
	end

	local selected = {}
	for _, target in ipairs(targets) do selected[target] = true end
	local visited, omitted = 0, {}
	local function omit(kind)
		omitted[kind] = (omitted[kind] or 0) + 1
	end
	local function visit(obj, parent, parentFrame)
		visited += 1
		if visited % 256 == 0 then task.wait() end
		local part = obj:IsA("BasePart")
		if obj:IsA("Terrain") then omit("Terrain"); return end
		local class = obj.ClassName
		if class == "WrapLayer" or class == "WrapTarget" or class == "FaceControls" or class == "Decal" or class == "Texture" then
			omit(class)
		end
		local frame = if part then obj.CFrame elseif obj:IsA("Model") then obj:GetPivot() else parentFrame
		local node = {name = obj.Name}
		if frame ~= parentFrame then node.matrix = matrix(parentFrame:ToObjectSpace(frame)) end
		if part then
			local ok, err = pcall(exportPart, node, obj)
			if not ok then error(obj:GetFullName() .. ": " .. tostring(err), 0) end
		end
		for _, child in ipairs(obj:GetChildren()) do visit(child, node, frame) end
		if node.children then appendNode(parent, node) end
	end
	local root = { children = scene.nodes }
	for _, target in ipairs(targets) do
		local ancestor = target.Parent
		while ancestor and not selected[ancestor] do ancestor = ancestor.Parent end
		if not ancestor then visit(target.Obj, root, CFrame.identity) end
	end
	assert(#doc.meshes > 0, "Select an object containing 3D geometry")
	local bytes = buffer.fromstring(table.concat(chunks))
	doc.buffers = {{ byteLength = length, uri = "data:application/octet-stream;base64,"
		.. buffer.tostring(service.EncodingService:Base64Encode(bytes)) }}
	local skipped = {}
	for kind, count in pairs(omitted) do table.insert(skipped, kind .. " (" .. count .. ")") end
	table.sort(skipped)
	return service.HttpService:JSONEncode(doc), if #skipped > 0 then "Omitted: " .. table.concat(skipped, ", ") else nil
end

return {
	InitDeps = function(d) Apps, service = d.Apps, d.service end,
	InitAfterMain = function() end, Main = function() return Exporter end,
}
