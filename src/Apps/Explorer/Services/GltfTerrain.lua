--!strict

local Terrain = {}
local resolution = 4
local chunkSize = 24
local corners = {
	{0,0,0}, {1,0,0}, {1,1,0}, {0,1,0},
	{0,0,1}, {1,0,1}, {1,1,1}, {0,1,1},
}
local tetrahedra = {{1,2,3,7},{1,3,4,7},{1,4,8,7},{1,8,5,7},{1,5,6,7},{1,6,2,7}}

function Terrain.Bounds(minimum, maximum)
	assert(minimum and maximum, "Enter the terrain bounds in studs")
	for _, axis in ipairs({"X","Y","Z"}) do
		assert(math.abs(minimum[axis]) < 131072 and math.abs(maximum[axis]) < 131072
			and minimum[axis] < maximum[axis], "Terrain bounds need a smaller, finite minimum on each axis")
	end
	local lo = Vector3.new(math.floor(minimum.X/4), math.floor(minimum.Y/4), math.floor(minimum.Z/4))
	local hi = Vector3.new(math.ceil(maximum.X/4), math.ceil(maximum.Y/4), math.ceil(maximum.Z/4))
	local size = hi-lo
	assert(size.X*size.Y*size.Z <= 2097152, "Terrain bounds are too large. Select a smaller region.")
	return lo,hi
end

function Terrain.Read(terrain, bounds, emit, accept, checkCancelled)
	local lo, hi = Terrain.Bounds(bounds.Min,bounds.Max)
	local water = Enum.Material.Water
	local colors = {[water]=terrain.WaterColor}
	local totalTriangles, step = 0, 0
	for x0 = lo.X-1, hi.X-1, chunkSize do
		for y0 = lo.Y-1, hi.Y-1, chunkSize do
			for z0 = lo.Z-1, hi.Z-1, chunkSize do
				checkCancelled()
				local x1, y1, z1 = math.min(x0+chunkSize,hi.X), math.min(y0+chunkSize,hi.Y), math.min(z0+chunkSize,hi.Z)
				local ax,ay,az = math.max(x0,lo.X),math.max(y0,lo.Y),math.max(z0,lo.Z)
				local region = Region3.new(Vector3.new(ax,ay,az)*resolution,
					Vector3.new(math.min(x1+1,hi.X),math.min(y1+1,hi.Y),math.min(z1+1,hi.Z))*resolution)
				local materials, occupancy = terrain:ReadVoxels(region,resolution)
				local solidGeometry, waterGeometry
				local function triangle(a,b,c,outside,material)
					local normal = (b-a):Cross(c-a)
					if normal.Magnitude < 1e-8 then return end
					if normal:Dot(outside-a) < 0 then b,c,normal = c,b,-normal end
					normal = normal.Unit
					local color = colors[material]
					if not color then
						color = terrain:GetMaterialColor(material)
						colors[material] = color
					end
					local geometry
					if material == water then
						waterGeometry = waterGeometry or emit.Begin(0,false,false)
						geometry = waterGeometry
					else
						solidGeometry = solidGeometry or emit.Begin(0,false,false)
						geometry = solidGeometry
					end
					totalTriangles += 1
					assert(totalTriangles <= 600000, "Terrain mesh is too large. Select a smaller region.")
					emit.Vertex(geometry,a,normal,nil,color)
					emit.Vertex(geometry,b,normal,nil,color)
					emit.Vertex(geometry,c,normal,nil,color)
				end
				local density, wet, mat, points = {}, {}, {}, {}
				for x = x0,x1-1 do
					for y = y0,y1-1 do
						for z = z0,z1-1 do
							step += 1
							if step % 1024 == 0 then checkCancelled() end
							local solids, liquids = 0, 0
							for i, offset in ipairs(corners) do
								local cx,cy,cz = x+offset[1]-ax+1,y+offset[2]-ay+1,z+offset[3]-az+1
								local column = occupancy[cx] and occupancy[cx][cy]
								local amount = column and column[cz] or 0
								local material = if amount > 0 then materials[cx][cy][cz] else nil
								density[i] = if material and material ~= water and material ~= Enum.Material.Air then amount else 0
								wet[i] = if material == water then amount else 0
								if density[i] >= .5 then solids += 1 end
								if wet[i] >= .5 then liquids += 1 end
								mat[i] = material
							end
							if (solids == 0 or solids == 8) and (liquids == 0 or liquids == 8) then continue end
							for i,offset in ipairs(corners) do
								points[i] = Vector3.new(x+offset[1]+.5,y+offset[2]+.5,z+offset[3]+.5)*resolution
							end
							local function tessellate(field, liquid)
								local function edge(a,b)
									local weight = (.5-field[a])/(field[b]-field[a])
									return points[a]:Lerp(points[b],weight)
								end
								local inside, outside = {}, {}
								for _, tetra in ipairs(tetrahedra) do
									table.clear(inside)
									table.clear(outside)
									for _, i in ipairs(tetra) do
										table.insert(if field[i] >= .5 then inside else outside,i)
									end
									local a,b,c = inside[1],inside[2],inside[3]
									local p,q,r = outside[1],outside[2],outside[3]
									if not a or not p then continue end
									local material = if liquid then water else mat[a]
									if not b then
										triangle(edge(a,p),edge(a,q),edge(a,r),points[p],material)
									elseif not c then
										local ap, aq, bp, bq = edge(a,p),edge(a,q),edge(b,p),edge(b,q)
										triangle(ap,aq,bp,points[p],material)
										triangle(aq,bq,bp,points[q],material)
									else
										triangle(edge(a,p),edge(b,p),edge(c,p),points[p],material)
									end
								end
							end
							if solids > 0 and solids < 8 then tessellate(density,false) end
							if liquids > 0 and liquids < 8 then tessellate(wet,true) end
						end
					end
				end
				if solidGeometry then accept(emit.Finish(solidGeometry),false,1) end
				if waterGeometry then accept(emit.Finish(waterGeometry),true,1-terrain.WaterTransparency) end
			end
		end
	end
end

return {InitDeps=function() end, InitAfterMain=function() end, Main=function() return Terrain end}
