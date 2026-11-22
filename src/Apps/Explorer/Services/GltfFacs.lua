--!strict

local Facs = {}

local function packedVector(value)
	return string.pack("<fff",value.X,value.Y,value.Z)
end

-- Roblox exposes each pose's bind-to-posed transforms in mesh space. Apply
-- those transforms with the same skin weights that drive the neutral mesh.
function Facs.Bake(mesh, basePoses, vertices, normals, influences, bones, units, sparseAccessor, checkCancelled)
	local poses = {}
	for _, action in ipairs(basePoses) do
		local ids, frames = mesh:GetFacsPose(action)
		table.insert(poses,{name=action.Name,ids=ids,frames=frames})
	end
	for _, actions in ipairs(mesh:GetFacsCorrectivePoses()) do
		local ids, frames = mesh:GetFacsCorrectivePose(actions)
		local names = {}
		for i, action in ipairs(actions) do names[i] = action.Name end
		table.sort(names)
		table.insert(poses,{name="Corrective_" .. table.concat(names,"_"),ids=ids,frames=frames})
	end
	table.sort(poses,function(a,b) return a.name < b.name end)

	local targets, names = {}, {}
	local positions = {}
	for _, pose in ipairs(poses) do
		checkCancelled()
		local deltas = {}
		for i, id in ipairs(pose.ids) do deltas[id] = pose.frames[i] end
		local indices, positionValues, normalValues = {}, {}, {}
		local minimum, maximum = Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
		local shifts = {}
		for i, id in ipairs(vertices) do
			local shift = shifts[id]
			local weights = influences[id]
			if shift == nil then
				local point = positions[id]
				if not point then
					point = mesh:GetPosition(id)
					positions[id] = point
				end
				for _, weight in ipairs(weights) do
					local delta = deltas[bones[weight[1]+1]]
					if delta then
						shift = (shift or Vector3.zero) + (delta:PointToWorldSpace(point)-point)*weight[2]
					end
				end
				shifts[id] = shift or false
			end
			if shift then
				local x,y,z = string.unpack("<fff",normals[i])
				local normal = Vector3.new(x,y,z)
				local posedNormal = normal
				for _, weight in ipairs(weights) do
					local delta = deltas[bones[weight[1]+1]]
					if delta then
						posedNormal += (delta:VectorToWorldSpace(normal)-normal)*weight[2]
					end
				end
				local normalDelta = if posedNormal.Magnitude > 1e-8 then posedNormal.Unit-normal else Vector3.zero
				shift *= units
				if shift.Magnitude > 1e-8 or normalDelta.Magnitude > 1e-8 then
					table.insert(indices,i-1)
					table.insert(positionValues,packedVector(shift))
					table.insert(normalValues,packedVector(normalDelta))
					minimum, maximum = minimum:Min(shift), maximum:Max(shift)
				end
			end
			if i % 1024 == 0 then checkCancelled() end
		end
		if #indices > 0 then
			local position, normal = sparseAccessor(#vertices,indices,positionValues,normalValues,minimum,maximum)
			table.insert(targets,{POSITION=position,NORMAL=normal})
			table.insert(names,pose.name)
		end
	end
	return targets, names
end

return {InitDeps=function() end,InitAfterMain=function() end,Main=function() return Facs end}
