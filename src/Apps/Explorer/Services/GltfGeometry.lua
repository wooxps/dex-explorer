--!strict

local Geometry = {}
local service

-- Keep authored vertex IDs separate from face-corner IDs. Hard edges and UV
-- seams share positions in Roblox, but require separate vertices in glTF.
function Geometry.ReadMesh(content, emit, tangents, skinning, checkCancelled)
	local mesh = service.AssetService:CreateEditableMeshAsync(content)
	assert(mesh, "Editable mesh memory budget exceeded")
	local ok, result = pcall(function()
		local faces, bones = mesh:GetFaces(), if skinning ~= false then mesh:GetBones() else {}
		assert(#faces > 0, "Mesh contains no faces")
		local geometry = emit.Begin(#faces, true, #bones > 0)
		local cache = {}
		for n, face in ipairs(faces) do
			local vertices = mesh:GetFaceVertices(face)
			local normals, uvs, colors = mesh:GetFaceNormals(face), mesh:GetFaceUVs(face), mesh:GetFaceColors(face)
			local p1, p2, p3 = mesh:GetPosition(vertices[1]), mesh:GetPosition(vertices[2]), mesh:GetPosition(vertices[3])
			local cross = (p2 - p1):Cross(p3 - p1)
			local flat = if cross.Magnitude > 0 then cross.Unit else Vector3.yAxis
			local function corner(i, orientation, tangent, bitangent)
				local vertex, ni, ui, ci = vertices[i], normals[i], uvs[i], colors[i]
				local normal = ni and mesh:GetNormal(ni)
				local key = string.format("%s/%s/%s/%s/%d", vertex, normal and normal.Magnitude > 0 and ni or ("f" .. face), ui or "", ci or "", orientation)
				local index = cache[key]
				if not index then
					local uv = ui and mesh:GetUV(ui)
					local color = ci and mesh:GetColor(ci)
					index = emit.Vertex(geometry, mesh:GetPosition(vertex), if normal and normal.Magnitude > 0 then normal.Unit else flat,
						uv, color, ci and mesh:GetColorAlpha(ci), vertex)
					cache[key] = index
				end
				if tangent then emit.Tangent(geometry, index, tangent, bitangent) end
				emit.Index(geometry, index)
			end
			for i = 2, #vertices - 1 do
				local orientation, tangent, bitangent = 0, nil, nil
				if tangents then
					assert(uvs[1] and uvs[i] and uvs[i+1], "Normal-mapped mesh is missing texture coordinates")
					local uv = mesh:GetUV(uvs[1])
					local u, v = mesh:GetUV(uvs[i])-uv, mesh:GetUV(uvs[i+1])-uv
					local det = u.X*v.Y-u.Y*v.X
					tangent, bitangent = Vector3.zero, Vector3.zero
					if math.abs(det) > 1e-12 then
						local e1, e2 = mesh:GetPosition(vertices[i])-p1, mesh:GetPosition(vertices[i+1])-p1
						tangent, bitangent = (e1*v.Y-e2*u.Y)/det, (e2*u.X-e1*v.X)/det
						orientation = if det < 0 then -1 else 1
					end
				end
				corner(1, orientation, tangent, bitangent)
				corner(i, orientation, tangent, bitangent)
				corner(i+1, orientation, tangent, bitangent)
			end
			if n % 2048 == 0 then
				task.wait()
				if checkCancelled then checkCancelled() end
			end
		end
		return emit.Finish(geometry, mesh, bones)
	end)
	mesh:Destroy()
	if not ok then error(result, 0) end
	return result
end

function Geometry.Primitive(shape, emit)
	local new = Vector3.new
	local geometry = emit.Begin(0, false, false)
	local function triangle(a, b, c, interior, na, nb, nc)
		local normal = (b - a):Cross(c - a)
		if normal.Magnitude < 1e-7 then return end
		if normal:Dot(a - interior) < 0 then
			b, c, nb, nc = c, b, nc, nb
			normal = -normal
		end
		normal = normal.Unit
		emit.Vertex(geometry, a, na or normal)
		emit.Vertex(geometry, b, nb or normal)
		emit.Vertex(geometry, c, nc or normal)
	end
	if shape == "Ball" or shape == "Cylinder" then
		local segments = 32
		for i = 0, segments - 1 do
			local a, b = i * 2 * math.pi / segments, (i + 1) * 2 * math.pi / segments
			if shape == "Cylinder" then
				local na, nb = new(0, math.cos(a), math.sin(a)), new(0, math.cos(b), math.sin(b))
				local p, q = (na - Vector3.xAxis) / 2, (nb - Vector3.xAxis) / 2
				local r, s = p + Vector3.xAxis, q + Vector3.xAxis
				triangle(p, r, s, Vector3.zero, na, na, nb)
				triangle(p, s, q, Vector3.zero, na, nb, nb)
				triangle(-Vector3.xAxis / 2, p, q, Vector3.zero)
				triangle(Vector3.xAxis / 2, s, r, Vector3.zero)
			else
				local function sphere(angle, j)
					local phi = j * math.pi / 16
					return new(math.sin(phi) * math.cos(angle), math.cos(phi), math.sin(phi) * math.sin(angle))
				end
				for j = 0, 15 do
					local p, q, r, s = sphere(a,j), sphere(b,j), sphere(b,j+1), sphere(a,j+1)
					triangle(p/2, q/2, r/2, Vector3.zero, p, q, r)
					triangle(p/2, r/2, s/2, Vector3.zero, p, r, s)
				end
			end
		end
	else
		local points = {
			new(-.5,-.5,-.5), new(.5,-.5,-.5), new(.5,-.5,.5), new(-.5,-.5,.5),
			new(-.5,.5,-.5), new(.5,.5,-.5), new(.5,.5,.5), new(-.5,.5,.5),
		}
		local faces, interior
		if shape == "Wedge" then
			faces = {{1,2,3,4},{1,2,7,8},{4,3,7,8},{1,4,8},{2,3,7}}
			interior = new(0,-.25,.25)
		elseif shape == "CornerWedge" then
			-- The tall corner of a Roblox CornerWedgePart is on +X, -Z.
			faces = {{1,2,3,4},{1,2,6},{2,3,6},{3,4,6},{4,1,6}}
			interior = new(.1,-.3,-.1)
		else
			assert(shape == "Block", "Unsupported part shape " .. shape)
			faces = {{1,2,3,4},{5,6,7,8},{1,2,6,5},{3,4,8,7},{1,4,8,5},{2,3,7,6}}
			interior = Vector3.zero
		end
		for _, face in ipairs(faces) do
			for i = 2, #face - 1 do triangle(points[face[1]], points[face[i]], points[face[i+1]], interior) end
		end
	end
	return emit.Finish(geometry)
end

-- Face axes as seen looking toward each face, with V pointing down.
function Geometry.ProjectFace(source, size, offset, decal, emit, layer, checkCancelled)
	local x,y,z = Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
	local axes = ({
		Front={-z,x,-y}, Back={z,-x,-y}, Right={x,z,-y}, Left={-x,-z,-y},
		Top={y,x,-z}, Bottom={-y,x,z},
	})[decal.Face.Name]
	if not axes then return nil end
	local face, uAxis, vAxis = table.unpack(axes)
	local extents = (source.max-source.min)*size
	local center = (source.min+source.max)*size/2+offset
	local uSize,vSize = math.abs(uAxis:Dot(extents)),math.abs(vAxis:Dot(extents))
	if uSize <= 0 or vSize <= 0 then return nil end
	local tiled = decal.ClassName == "Texture"
	local uTile = if tiled then math.max(.001,decal.StudsPerTileU) else uSize
	local vTile = if tiled then math.max(.001,decal.StudsPerTileV) else vSize
	local uOffset = if tiled then decal.OffsetStudsU else 0
	local vOffset = if tiled then decal.OffsetStudsV else 0
	local uvScale, uvOffset = decal.UVScale or Vector2.one, decal.UVOffset or Vector2.zero
	local angle = math.rad(decal.Rotation or 0)
	local cosine, sine = math.cos(angle),math.sin(angle)
	local function uv(point)
		local u = ((point-center):Dot(uAxis)+uSize/2-uOffset)/uTile
		local v = ((point-center):Dot(vAxis)+vSize/2-vOffset)/vTile
		u,v = u*uvScale.X-.5,v*uvScale.Y-.5
		return Vector2.new(u*cosine+v*sine+.5+uvOffset.X,-u*sine+v*cosine+.5+uvOffset.Y)
	end
	local function point(index)
		local px,py,pz = string.unpack("<fff",source.positions,index*12+1)
		return Vector3.new(px,py,pz)*size+offset
	end
	local function vertexIndex(index)
		if not source.indexBytes then return index end
		return (string.unpack(source.indexFormat,source.indexBytes,index*source.indexStride+1))
	end
	local geometry
	local depth = .002+.0005*layer
	for start = 0,source.cornerCount-1,3 do
		if start % 12288 == 0 and start > 0 then task.wait(); checkCancelled() end
		local a,b,c = point(vertexIndex(start)),point(vertexIndex(start+1)),point(vertexIndex(start+2))
		local normal = (b-a):Cross(c-a)
		if normal.Magnitude > 1e-8 then
			normal = normal.Unit
			local facing = face:Dot(normal)
			if facing > 0 and facing >= math.max(math.abs(normal.X),math.abs(normal.Y),math.abs(normal.Z))-.0001 then
				geometry = geometry or emit.Begin(0,false,false)
				local lift = normal*depth
				emit.Vertex(geometry,a+lift,normal,uv(a))
				emit.Vertex(geometry,b+lift,normal,uv(b))
				emit.Vertex(geometry,c+lift,normal,uv(c))
			end
		end
	end
	return geometry and emit.Finish(geometry)
end

return {
	InitDeps = function(d) service = d.service end, InitAfterMain = function() end,
	Main = function() return Geometry end,
}
