--!strict

------------------------------ Module ------------------------------

local function Main()
	local Spatial = {}
	local function integer(value, default, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum,
			"INVALID_ARGUMENT: bounded positive integer required"
		)
		return value
	end
	local function finite(value, maximum)
		assert(
			type(value) == "number" and value == value and math.abs(value) <= maximum,
			"INVALID_ARGUMENT: finite coordinate outside supported range"
		)
		return value
	end
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local bytes = 2
		for key, item in pairs(value) do
			bytes += size(key) + size(item) + 2
		end
		return bytes
	end
	function Spatial.Create(c)
		local registry, codec, service = c.Registry, c.Codec, c.service
		local result = { Commands = {} }
		local dead = false
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		local function prefix(text, maximum)
			local length = math.min(#text, maximum)
			if length < #text then
				while length > 0 do
					local byte = text:byte(length + 1)
					if byte < 128 or byte >= 192 then
						break
					end
					length -= 1
				end
			end
			return text:sub(1, length)
		end
		local function identity(object)
			local name = object.Name
			return {
				id = registry:Id(object),
				name = prefix(name, 256),
				nameTruncated = #name > 256,
				className = object.ClassName,
				parentId = object.Parent and registry:Allowed(object.Parent) and registry:Id(object.Parent) or nil,
			}
		end
		local function fields(object, keys)
			local values, errors = {}, {}
			for _, key in ipairs(keys) do
				local ok, value = pcall(function()
					local raw = object[key]
					if typeof(raw) == "Instance" and not registry:Allowed(raw) then
						return { type = "UnavailableInstance" }
					end
					local encoded = codec:Encode(raw)
					assert(size(encoded) <= 4096, "value exceeds field budget")
					return encoded
				end)
				if ok then
					values[key] = value
				else
					errors[key] = tostring(value):sub(1, 160)
				end
			end
			return values, errors
		end
		local function append(rows, row, budget)
			local bytes = size(row)
			if budget.bytes + bytes > 47104 then
				budget.truncated = true
				return false
			end
			rows[#rows + 1] = row
			budget.bytes += bytes
			return true
		end
		local function inset()
			local ok, a, b = pcall(function()
				return service.GuiService:GetGuiInset()
			end)
			if ok then
				return { topLeft = { x = a.X, y = a.Y }, bottomRight = { x = b.X, y = b.Y }, available = true }
			end
			return {
				topLeft = { x = 0, y = 0 },
				bottomRight = { x = 0, y = 0 },
				available = false,
				error = "GUI inset unavailable",
			}
		end
		local function cameraInfo(args)
			local space = args.coordinateSpace or "screen"
			assert(
				space == "screen" or space == "viewport",
				"INVALID_ARGUMENT: coordinateSpace must be screen or viewport"
			)
			local camera = service.Workspace.CurrentCamera
			assert(camera, "CAMERA_UNAVAILABLE: no current client camera")
			local viewport = camera.ViewportSize
			return camera,
				{
					scope = "client",
					coordinateSpace = space,
					units = "roblox_ui_offset_pixels",
					viewport = { x = viewport.X, y = viewport.Y },
					guiInset = inset(),
					cameraCFrame = codec:Encode(camera.CFrame),
				}
		end
		add("world_to_screen", function(args)
			assert(
				type(args.positions) == "table" and #args.positions >= 1 and #args.positions <= 64,
				"INVALID_ARGUMENT: provide 1 to 64 positions"
			)
			local camera, output = cameraInfo(args)
			output.points = {}
			for index, value in ipairs(args.positions) do
				local position = codec:Decode(value)
				assert(typeof(position) == "Vector3", "INVALID_VALUE: positions require typed Vector3 values")
				local point, visible
				if output.coordinateSpace == "screen" then
					point, visible = camera:WorldToScreenPoint(position)
				else
					point, visible = camera:WorldToViewportPoint(position)
				end
				assert(
					point.X == point.X
						and point.Y == point.Y
						and point.Z == point.Z
						and math.max(math.abs(point.X), math.abs(point.Y), math.abs(point.Z)) < math.huge,
					"INVALID_VALUE: camera projection returned a non-finite coordinate"
				)
				output.points[index] = { x = point.X, y = point.Y, depth = point.Z, onScreen = visible }
			end
			output.note = "Projection visibility is a viewport/frustum result, not an occlusion or clickability test."
			return output
		end)
		add("screen_to_ray", function(args)
			local x, y = finite(args.x, 100000), finite(args.y, 100000)
			local camera, output = cameraInfo(args)
			local ray
			if output.coordinateSpace == "screen" then
				ray = camera:ScreenPointToRay(x, y)
			else
				ray = camera:ViewportPointToRay(x, y)
			end
			assert(ray.Direction.Magnitude > 0, "CAMERA_UNAVAILABLE: camera returned a zero ray")
			output.origin = codec:Encode(ray.Origin)
			output.direction = codec:Encode(ray.Direction.Unit)
			output.unitDirection = true
			output.inputPoint = { x = x, y = y }
			return output
		end)
		add("get_ui_at_point", function(args)
			local x, y = finite(args.x, 100000), finite(args.y, 100000)
			local limit = integer(args.limit, 25, 50)
			assert(
				args.includeCoreGui == nil or type(args.includeCoreGui) == "boolean",
				"INVALID_ARGUMENT: includeCoreGui must be boolean"
			)
			local guiInset = inset()
			assert(guiInset.available, "UNSUPPORTED: GUI inset is required to convert screen coordinates")
			local qx, qy = x - guiInset.topLeft.x, y - guiInset.topLeft.y
			local output = {
				scope = "client",
				coordinateSpace = "client_viewport_pixels",
				queryCoordinateSpace = "gui_inset_adjusted_pixels",
				inputPoint = { x = x, y = y },
				queryPoint = { x = qx, y = qy },
				guiInset = guiInset,
				containers = {},
				truncated = false,
				note = "Ranks are top-to-bottom within each container. Containers are not globally sorted; a hit does not guarantee semantic clickability.",
			}
			local containers = {
				{
					name = "PlayerGui",
					get = function()
						local player = service.Players.LocalPlayer
						return player and player:FindFirstChildOfClass("PlayerGui")
					end,
				},
			}
			if args.includeCoreGui then
				containers[#containers + 1] = {
					name = "CoreGui",
					get = function()
						return service.CoreGui
					end,
				}
			end
			local total, budget = 0, { bytes = 0 }
			for _, source in ipairs(containers) do
				local item = { container = source.name, entries = {}, truncated = false }
				output.containers[#output.containers + 1] = item
				local ok, hits = pcall(function()
					local owner = source.get()
					assert(owner, "container unavailable")
					return owner:GetGuiObjectsAtPosition(qx, qy)
				end)
				if not ok then
					item.error = tostring(hits):sub(1, 200)
				else
					item.nativeHits = #hits
					item.examined = math.min(#hits, 512)
					if #hits > 512 then
						item.truncated = true
						output.truncated = true
					end
					for rank = 1, math.min(#hits, 512) do
						local object = hits[rank]
						if object:IsA("GuiObject") and registry:Allowed(object) then
							if total >= limit then
								item.truncated = true
								output.truncated = true
								break
							end
							local values, errors = fields(object, {
								"AbsolutePosition",
								"AbsoluteSize",
								"AbsoluteRotation",
								"Visible",
								"Active",
								"Interactable",
								"ZIndex",
								"ClipsDescendants",
							})
							if
								not append(
									item.entries,
									{ instance = identity(object), rank = rank, properties = values, errors = errors },
									budget
								)
							then
								item.truncated = true
								output.truncated = true
								break
							end
							total += 1
						end
					end
				end
			end
			output.returned = total
			return output
		end)
		add("query_parts", function(args)
			local limit = integer(args.limit, 50, 100)
			assert(args.shape == "box" or args.shape == "radius", "INVALID_ARGUMENT: shape must be box or radius")
			local excluded = {}
			local seen = {}
			assert(
				args.excludeIds == nil or type(args.excludeIds) == "table" and #args.excludeIds <= 100,
				"INVALID_ARGUMENT: at most 100 excludeIds"
			)
			for _, key in ipairs(args.excludeIds or {}) do
				local object = registry:Resolve(key)
				if not seen[object] then
					seen[object] = true
					excluded[#excluded + 1] = object
				end
			end
			local ignored = 0
			for object in pairs(c.Main.SelectionGeometryRoots or {}) do
				ignored += 1
				if ignored > 256 then
					break
				end
				if not seen[object] then
					seen[object] = true
					excluded[#excluded + 1] = object
				end
			end
			assert(OverlapParams and OverlapParams.new, "UNSUPPORTED: overlap queries unavailable")
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = excluded
			params.MaxParts = limit + 1
			local hits
			if args.shape == "box" then
				local cf, extent = codec:Decode(args.cframe), codec:Decode(args.size)
				assert(
					typeof(cf) == "CFrame"
						and typeof(extent) == "Vector3"
						and extent.X > 0
						and extent.Y > 0
						and extent.Z > 0
						and math.max(extent.X, extent.Y, extent.Z) <= 20000,
					"INVALID_VALUE: box requires CFrame and positive size up to 20000 per axis"
				)
				hits = service.Workspace:GetPartBoundsInBox(cf, extent, params)
			else
				local center = codec:Decode(args.center)
				local radius = finite(args.radius, 10000)
				assert(
					typeof(center) == "Vector3" and radius > 0,
					"INVALID_VALUE: radius requires typed center Vector3 and positive radius"
				)
				hits = service.Workspace:GetPartBoundsInRadius(center, radius, params)
			end
			local output = {
				scope = "client",
				shape = args.shape,
				parts = {},
				truncated = #hits >= params.MaxParts,
				nativeCandidates = #hits,
				query = "bounding_volume_overlap",
				internalExclusionsTruncated = ignored > 256,
				note = "Broad-phase bounding-volume candidates, not exact mesh intersections. Native filtering uses current client physics/query settings.",
			}
			local budget = { bytes = 0 }
			for _, part in ipairs(hits) do
				if registry:Allowed(part) then
					if #output.parts >= limit or not append(output.parts, identity(part), budget) then
						output.truncated = true
						break
					end
				end
			end
			return output
		end)
		add("get_assembly", function(args)
			local target = registry:Resolve(args.instanceId)
			local limit = integer(args.limit, 50, 100)
			assert(
				target:IsA("BasePart") and target:IsDescendantOf(service.Workspace),
				"INVALID_TARGET: Workspace BasePart required"
			)
			assert(c.StartJob, "UNSUPPORTED: cooperative jobs unavailable")
			return c.StartJob(function(check)
				local output = {
					scope = "client",
					root = identity(target),
					parts = {},
					joints = {},
					errors = {},
					truncated = false,
					note = "Bounded graph of direct native connections. Native GetConnectedParts(false)/GetJoints allocate their immediate result lists before Lua caps them; no full recursive native assembly query is used.",
				}
				local queue = { target }
				local seen = { [target] = true }
				local jointSeen = {}
				local cursor = 1
				local edges = 0
				local budget = { bytes = 0 }
				while cursor <= #queue do
					assert(not dead and check(), "CANCELLED: spatial query ended")
					local part = queue[cursor]
					cursor += 1
					if registry:Allowed(part) then
						local values, errors = fields(part, {
							"Anchored",
							"CanCollide",
							"CanQuery",
							"Massless",
							"AssemblyMass",
							"AssemblyRootPart",
							"AssemblyLinearVelocity",
							"AssemblyAngularVelocity",
							"RootPriority",
							"CollisionGroup",
						})
						if
							not append(
								output.parts,
								{ instance = identity(part), properties = values, errors = errors },
								budget
							)
						then
							output.truncated = true
							break
						end
						local ok, neighbors = pcall(part.GetConnectedParts, part, false)
						if not ok then
							if
								not append(output.errors, {
									instanceId = registry:Id(part),
									operation = "GetConnectedParts",
									error = prefix(tostring(neighbors), 160),
								}, budget)
							then
								output.truncated = true
								break
							end
						else
							for index = 1, math.min(#neighbors, 201) do
								edges += 1
								if edges > 1000 then
									output.truncated = true
									break
								end
								local neighbor = neighbors[index]
								if registry:Allowed(neighbor) and not seen[neighbor] then
									if #queue >= limit then
										output.truncated = true
									else
										seen[neighbor] = true
										queue[#queue + 1] = neighbor
									end
								end
							end
							if #neighbors > 201 then
								output.truncated = true
							end
						end
						local good, joints = pcall(part.GetJoints, part)
						if not good then
							if
								not append(output.errors, {
									instanceId = registry:Id(part),
									operation = "GetJoints",
									error = prefix(tostring(joints), 160),
								}, budget)
							then
								output.truncated = true
								break
							end
						else
							for index = 1, math.min(#joints, 101) do
								local joint = joints[index]
								if registry:Allowed(joint) and not jointSeen[joint] then
									jointSeen[joint] = true
									if #output.joints >= 100 then
										output.truncated = true
										break
									end
									local properties, problems = fields(
										joint,
										{ "Part0", "Part1", "Attachment0", "Attachment1", "Enabled", "Active" }
									)
									if
										not append(
											output.joints,
											{ instance = identity(joint), properties = properties, errors = problems },
											budget
										)
									then
										output.truncated = true
										break
									end
								end
							end
							if #joints > 101 then
								output.truncated = true
							end
						end
					end
					if edges > 1000 or budget.truncated then
						break
					end
				end
				output.visited = #output.parts
				output.examinedEdges = edges
				return output
			end)
		end)
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Spatial
end
return { Main = Main }
