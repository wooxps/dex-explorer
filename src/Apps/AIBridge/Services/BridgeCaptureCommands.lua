--!strict

------------------------------ Module ------------------------------

local function Main()
	local Capture = {}
	local sections = {
		nodes = true,
		scripts = true,
		assets = true,
		relationships = true,
		changes = true,
		events = true,
		markers = true,
	}
	local excluded = {
		Parent = true,
		ClassName = true,
		Source = true,
		UniqueId = true,
		HistoryId = true,
		ScriptGuid = true,
		RobloxLocked = true,
		Capabilities = true,
		Sandboxed = true,
	}
	local assetKeys = {
		MeshId = true,
		MeshContent = true,
		TextureID = true,
		TextureId = true,
		Texture = true,
		TextureContent = true,
		Image = true,
		ImageContent = true,
		SoundId = true,
		AnimationId = true,
		Video = true,
		ColorMap = true,
		ColorMapContent = true,
		MetalnessMap = true,
		MetalnessMapContent = true,
		NormalMap = true,
		NormalMapContent = true,
		RoughnessMap = true,
		RoughnessMapContent = true,
		FontFace = true,
		ShirtTemplate = true,
		PantsTemplate = true,
		Graphic = true,
		SkyboxBk = true,
		SkyboxDn = true,
		SkyboxFt = true,
		SkyboxLf = true,
		SkyboxRt = true,
		SkyboxUp = true,
	}
	local function size(value)
		local kind = type(value)
		if kind == "string" then
			return #value * 6 + 2
		end
		if kind ~= "table" then
			return 32
		end
		local bytes = 2
		for key, item in pairs(value) do
			bytes += size(key) + size(item) + 2
		end
		return bytes
	end
	local function equal(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for key, value in pairs(a) do
			if not equal(value, b[key]) then
				return false
			end
		end
		for key in pairs(b) do
			if a[key] == nil then
				return false
			end
		end
		return true
	end
	local function int(value, default, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum,
			"INVALID_ARGUMENT: integer outside supported range"
		)
		return value
	end
	local function text(value, maximum)
		assert(type(value) == "string" and #value > 0 and #value <= maximum, "INVALID_ARGUMENT: bounded text required")
		return value
	end
	function Capture.Create(c)
		local Apps, registry, codec = c.Apps, c.Registry, c.Codec
		local api = Apps.ReflectionService
		local result = { Commands = {} }
		local saved, order, recordings = {}, {}, {}
		local counter, totalBytes, dead = 0, 0, false
		local classCache = {}
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		local function nextId(prefix)
			counter += 1
			return prefix .. counter
		end
		local function checkpoint(check)
			assert(not dead and check(), "CANCELLED: analysis ended")
		end
		local function get(key)
			local item = saved[key]
			assert(item, "CAPTURE_UNAVAILABLE: unknown, deleted or evicted capture")
			return item
		end
		local function summary(item)
			local counts = {}
			for key in pairs(sections) do
				counts[key] = #(item[key] or {})
			end
			return {
				captureId = item.captureId,
				name = item.name,
				kind = item.kind,
				createdAt = item.createdAt,
				startedClock = item.startedClock,
				duration = item.duration,
				scope = "client",
				roots = item.roots,
				counts = counts,
				coverage = item.coverage,
				estimatedBytes = item.estimatedBytes,
				camera = item.camera,
				game = item.game,
				beforeId = item.beforeId,
				afterId = item.afterId,
			}
		end
		local function store(item)
			item.estimatedBytes = size(item)
			assert(
				item.estimatedBytes <= 8 * 1024 * 1024,
				"CAPTURE_LIMIT: capture exceeds 8 MiB; choose a smaller subtree"
			)
			while #order >= 8 or totalBytes + item.estimatedBytes > 16 * 1024 * 1024 do
				local key = table.remove(order, 1)
				local old = saved[key]
				if old then
					totalBytes -= old.estimatedBytes
					saved[key] = nil
				end
			end
			item.captureId = nextId("capture")
			saved[item.captureId] = item
			order[#order + 1] = item.captureId
			totalBytes += item.estimatedBytes
			return summary(item)
		end
		local function roots(args)
			local values = {}
			if args.instanceIds then
				assert(
					type(args.instanceIds) == "table" and #args.instanceIds > 0 and #args.instanceIds <= 20,
					"INVALID_ARGUMENT: choose 1 to 20 roots"
				)
				for _, key in ipairs(args.instanceIds) do
					values[#values + 1] = registry:Resolve(key)
				end
			else
				values = Apps.Explorer.Services.Selection:Get()
			end
			assert(#values > 0 and #values <= 20, "INVALID_TARGET: select objects or provide instanceIds")
			local selected = {}
			for _, object in ipairs(values) do
				selected[object] = true
			end
			local output, seen = {}, {}
			for _, object in ipairs(values) do
				assert(registry:Allowed(object), "INSTANCE_UNAVAILABLE")
				local parent = object.Parent
				local covered = false
				while parent do
					if selected[parent] then
						covered = true
						break
					end
					parent = parent.Parent
				end
				if not covered and not seen[object] then
					seen[object] = true
					output[#output + 1] = object
				end
			end
			return output
		end
		local function walk(values, maximum, check, visit)
			local stack = {}
			for index = #values, 1, -1 do
				stack[#stack + 1] = values[index]
			end
			local count = 0
			local truncated = false
			while #stack > 0 do
				local object = table.remove(stack)
				if registry:Allowed(object) then
					count += 1
					if count > maximum then
						return maximum, true
					end
					checkpoint(check)
					if visit(object, count) == false then
						return count, true
					end
					local children = object:GetChildren()
					local room = maximum - count - #stack + 1
					for index = math.min(#children, math.max(0, room)), 1, -1 do
						stack[#stack + 1] = children[index]
					end
					if #children > room then
						truncated = true
					end
				end
			end
			return count, truncated
		end
		local function properties(className)
			if classCache[className] then
				return classCache[className]
			end
			local map, seen = {}, {}
			local class = api.GetClass(className)
			while class and not seen[class.Name] do
				seen[class.Name] = true
				for _, member in pairs(class.Properties or {}) do
					local name = member.Name
					local tags = member.Tags or {}
					if
						type(name) == "string"
						and name:match("^%u")
						and not excluded[name]
						and not tags.Deprecated
						and not map[name]
					then
						map[name] = member
					end
				end
				class = type(class.Superclass) == "table" and class.Superclass or api.GetClass(class.Superclass)
			end
			local list = {}
			for _, member in pairs(map) do
				list[#list + 1] = member
			end
			table.sort(list, function(a, b)
				local first = assetKeys[a.Name] and 0 or a.Tags and a.Tags.ReadOnly and 2 or 1
				local last = assetKeys[b.Name] and 0 or b.Tags and b.Tags.ReadOnly and 2 or 1
				return first == last and a.Name < b.Name or first < last
			end)
			classCache[className] = list
			return list
		end
		local function encode(value)
			local ok, encoded = pcall(codec.Encode, codec, value)
			if not ok then
				return nil, "serialization_limit"
			end
			if type(encoded) == "table" and (encoded.type == "Unsupported" or encoded.type == "TruncatedString") then
				return nil, encoded.type
			end
			if type(encoded) == "string" and #encoded > 4096 then
				return nil, "string_limit"
			end
			return encoded
		end
		local function path(object)
			local segments = {}
			local current = object
			while current and current ~= c.Game and #segments < 64 do
				table.insert(segments, 1, current.Name)
				current = current.Parent
			end
			return segments
		end
		local function source(object, decompile)
			local ok, value = pcall(function()
				return object.Source
			end)
			if ok and type(value) == "string" and value ~= "" then
				return value, "readable"
			end
			local cached = Apps.ReferenceSource and Apps.ReferenceSource.Peek and Apps.ReferenceSource.Peek(object)
			if cached and type(cached.Source) == "string" then
				return cached.Source, "cached_approximate"
			end
			if decompile and type(c.env.decompile) == "function" then
				local good, output = pcall(c.env.decompile, object)
				if good and type(output) == "string" and output ~= "" then
					return output, "decompiled_approximate", true
				end
				return nil, "unavailable", true
			end
			return nil, "unavailable"
		end
		local function camera()
			local output = c.Handlers.dex_get_camera and c.Handlers.dex_get_camera() or {}
			local current = c.service.Workspace.CurrentCamera
			if current then
				output.viewport = codec:Encode(current.ViewportSize)
				for _, key in ipairs({ "FieldOfViewMode", "NearPlaneZ" }) do
					local ok, value = pcall(function()
						return codec:Encode(current[key])
					end)
					if ok then
						output[key] = value
					end
				end
			end
			if c.service.GuiService then
				local ok, a, b = pcall(c.service.GuiService.GetGuiInset, c.service.GuiService)
				if ok then
					output.guiInset = { topLeft = codec:Encode(a), bottomRight = codec:Encode(b) }
				end
			end
			return output
		end
		local function measure(object)
			local values = {}
			if object:IsA("GuiObject") then
				for _, key in ipairs({
					"AbsolutePosition",
					"AbsoluteSize",
					"AbsoluteRotation",
					"Position",
					"Size",
					"AnchorPoint",
					"Rotation",
					"Visible",
					"ZIndex",
					"LayoutOrder",
					"ClipsDescendants",
					"AutomaticSize",
				}) do
					local ok, value = pcall(function()
						return codec:Encode(object[key])
					end)
					if ok then
						values[key] = value
					end
				end
				values.coordinateSpace = "gui_absolute_pixels"
				values.ancestorState = {}
				local parent = object.Parent
				while parent and parent ~= c.Game and #values.ancestorState < 32 do
					if parent:IsA("GuiObject") or parent:IsA("LayerCollector") then
						local row = { id = registry:Id(parent), className = parent.ClassName }
						for _, key in ipairs({
							"Visible",
							"Enabled",
							"ClipsDescendants",
							"IgnoreGuiInset",
							"DisplayOrder",
						}) do
							local ok, value = pcall(function()
								return codec:Encode(parent[key])
							end)
							if ok then
								row[key] = value
							end
						end
						values.ancestorState[#values.ancestorState + 1] = row
					end
					parent = parent.Parent
				end
			elseif object:IsA("BasePart") or object:IsA("Model") then
				local ok, cf, extent, pivot = pcall(Apps.TransformSession.Bounds, { object }, "Local")
				if ok and cf then
					values.boundsCFrame = codec:Encode(cf)
					values.boundsSize = codec:Encode(extent)
					values.pivot = codec:Encode(pivot)
					local current = c.service.Workspace.CurrentCamera
					if current then
						local projected = {}
						for x = -1, 1, 2 do
							for y = -1, 1, 2 do
								for z = -1, 1, 2 do
									local good, point, visible = pcall(
										current.WorldToViewportPoint,
										current,
										cf:PointToWorldSpace(
											Vector3.new(extent.X * x / 2, extent.Y * y / 2, extent.Z * z / 2)
										)
									)
									if good then
										projected[#projected + 1] =
											{ x = point.X, y = point.Y, depth = point.Z, onScreen = visible }
									end
								end
							end
						end
						values.viewportCorners = projected
						values.projectionNote =
							"Viewport pixels; points behind the camera are not clipped to the near plane."
					end
				end
			end
			return values
		end
		local function capture(args, check)
			local started = os.clock()
			local values = roots(args)
			local maximum = int(args.maxNodes, 2000, 5000)
			local item = {
				kind = "system",
				name = args.name and text(args.name, 120) or "Selection",
				createdAt = os.time(),
				nodes = {},
				scripts = {},
				assets = {},
				relationships = {},
				roots = {},
				camera = camera(),
				game = c.Handlers.dex_get_session(),
				coverage = {
					nodeLimit = maximum,
					propertyLimit = 128,
					sourceLimit = 262144,
					unavailableScripts = 0,
					omittedProperties = 0,
					nonAtomic = true,
				},
			}
			item.startedClock = started
			for _, object in ipairs(values) do
				item.roots[#item.roots + 1] = registry:Id(object)
			end
			local inside, bytes, sourceBytes = {}, 0, 0
			local decompileCalls = 0
			local _, truncated = walk(values, maximum, check, function(object)
				local identity = registry:Describe(object)
				local key = identity.id
				inside[key] = true
				local class = api.GetClass(object.ClassName)
				local row = {
					id = key,
					name = object.Name,
					className = object.ClassName,
					parentId = identity.parentId,
					provenance = identity.provenance,
					path = path(object),
					isService = class and class.Tags and class.Tags.Service == true or false,
					properties = {},
					readOnly = {},
					writeRestricted = {},
					errors = {},
					attributes = {},
					tags = {},
					measurements = measure(object),
				}
				for index, member in ipairs(properties(object.ClassName)) do
					checkpoint(check)
					if index > 128 then
						row.errors._limit = "property_limit"
						item.coverage.omittedProperties += 1
						break
					end
					local ok, value = pcall(function()
						return object[member.Name]
					end)
					if ok then
						local encoded, why = encode(value)
						if encoded ~= nil and size(row.properties) + size(encoded) > 96 * 1024 then
							encoded = nil
							why = "node_size_limit"
						end
						if encoded ~= nil then
							row.properties[member.Name] = encoded
							if member.Tags and member.Tags.ReadOnly then
								row.readOnly[member.Name] = true
							end
							local security = member.Security
							local write = type(security) == "table" and security.Write
								or type(security) == "string" and security
								or nil
							if member.Tags and member.Tags.NotScriptable then
								row.writeRestricted[member.Name] = "NotScriptable"
							elseif write and write ~= "None" and write ~= "PluginSecurity" then
								row.writeRestricted[member.Name] = write
							end
							if typeof(value) == "Instance" then
								item.relationships[#item.relationships + 1] = {
									fromId = key,
									property = member.Name,
									toId = registry:Id(value),
									target = registry:Describe(value),
								}
							end
							if assetKeys[member.Name] and value ~= nil and value ~= "" then
								local uri = type(value) == "string" and value
									or type(encoded) == "table" and (encoded.uri or encoded.family)
								item.assets[#item.assets + 1] = {
									instanceId = key,
									property = member.Name,
									value = encoded,
									assetId = type(uri) == "string" and (uri:match("rbxassetid://(%d+)") or uri:match(
										"[?&]id=(%d+)"
									)) or nil,
								}
							end
						else
							row.errors[member.Name] = why
							item.coverage.omittedProperties += 1
						end
					else
						row.errors[member.Name] = "read_unavailable"
						item.coverage.omittedProperties += 1
					end
				end
				local ok, attributes = pcall(object.GetAttributes, object)
				if ok then
					for keyName, value in pairs(attributes) do
						local encoded, why = encode(value)
						if encoded ~= nil and size(row.attributes) + size(encoded) < 16 * 1024 then
							row.attributes[keyName] = encoded
						else
							row.errors["attribute:" .. keyName] = why or "attribute_size_limit"
						end
					end
				end
				local good, tags = pcall(c.service.CollectionService.GetTags, c.service.CollectionService, object)
				if good then
					row.tags = tags
				end
				if object:IsA("LuaSourceContainer") then
					if args.includeSource ~= false then
						local allow = args.decompile == true and decompileCalls < 8
						local contents, kind, called = source(object, allow)
						if called then
							decompileCalls += 1
						end
						row.sourceKind = kind
						if contents and #contents <= 262144 and sourceBytes + #contents <= 2 * 1024 * 1024 then
							sourceBytes += #contents
							local offset = 1
							while offset <= #contents do
								checkpoint(check)
								local last = math.min(offset + 7999, #contents)
								while
									last < #contents
									and contents:byte(last + 1) >= 128
									and contents:byte(last + 1) < 192
								do
									last -= 1
								end
								item.scripts[#item.scripts + 1] = {
									instanceId = key,
									offset = offset,
									totalBytes = #contents,
									sourceKind = kind,
									source = contents:sub(offset, last),
								}
								offset = last + 1
							end
						else
							row.sourceKind = contents and "source_limit" or kind
							item.coverage.unavailableScripts += 1
						end
					else
						row.sourceKind = "not_requested"
					end
				end
				item.nodes[#item.nodes + 1] = row
				bytes += size(row)
				assert(bytes <= 7 * 1024 * 1024, "CAPTURE_LIMIT: choose fewer roots or a smaller subtree")
			end)
			for _, edge in ipairs(item.relationships) do
				edge.internal = inside[edge.toId] == true
			end
			item.coverage.truncated = truncated
			item.coverage.decompileCalls = decompileCalls
			item.coverage.sourceBytes = sourceBytes
			item.duration = os.clock() - started
			return store(item)
		end
		local function compare(before, after, check, name, recording)
			assert(before.kind == "system" and after.kind == "system", "INVALID_TARGET: compare system captures")
			local rootSet = {}
			for _, key in ipairs(before.roots) do
				rootSet[key] = true
			end
			assert(#before.roots == #after.roots, "CAPTURE_MISMATCH: captures must have the same roots in this session")
			for _, key in ipairs(after.roots) do
				assert(rootSet[key], "CAPTURE_MISMATCH: captures must have the same roots in this session")
			end
			local item = {
				kind = "comparison",
				name = name or before.name .. " changes",
				createdAt = os.time(),
				beforeId = before.captureId,
				afterId = after.captureId,
				changes = {},
				coverage = { before = before.coverage, after = after.coverage, nonAtomic = true },
			}
			local old, new = {}, {}
			for _, row in ipairs(before.nodes) do
				old[row.id] = row
			end
			for _, row in ipairs(after.nodes) do
				new[row.id] = row
			end
			for _, row in ipairs(before.nodes) do
				checkpoint(check)
				local nextRow = new[row.id]
				if not nextRow then
					item.changes[#item.changes + 1] = {
						kind = "removed",
						instanceId = row.id,
						before = { name = row.name, className = row.className, parentId = row.parentId },
					}
				else
					for _, key in ipairs({
						"name",
						"parentId",
						"properties",
						"attributes",
						"tags",
						"measurements",
						"sourceKind",
					}) do
						if not equal(row[key], nextRow[key]) then
							if key == "properties" or key == "attributes" or key == "measurements" then
								local keys = {}
								for field in pairs(row[key] or {}) do
									keys[field] = true
								end
								for field in pairs(nextRow[key] or {}) do
									keys[field] = true
								end
								local sorted = {}
								for field in pairs(keys) do
									sorted[#sorted + 1] = field
								end
								table.sort(sorted)
								for _, field in ipairs(sorted) do
									if not equal(row[key][field], nextRow[key][field]) then
										local first, last = row[key][field], nextRow[key][field]
										item.changes[#item.changes + 1] = {
											kind = key,
											instanceId = row.id,
											property = field,
											before = first == nil and { type = "nil" } or first,
											after = last == nil and { type = "nil" } or last,
										}
									end
								end
							else
								item.changes[#item.changes + 1] =
									{ kind = key, instanceId = row.id, before = row[key], after = nextRow[key] }
							end
						end
					end
				end
			end
			for _, row in ipairs(after.nodes) do
				checkpoint(check)
				if not old[row.id] then
					item.changes[#item.changes + 1] = {
						kind = "added",
						instanceId = row.id,
						after = { name = row.name, className = row.className, parentId = row.parentId },
					}
				end
			end
			local oldSource, newSource = {}, {}
			for _, part in ipairs(before.scripts) do
				oldSource[part.instanceId] = oldSource[part.instanceId] or {}
				table.insert(oldSource[part.instanceId], part)
			end
			for _, part in ipairs(after.scripts) do
				newSource[part.instanceId] = newSource[part.instanceId] or {}
				table.insert(newSource[part.instanceId], part)
			end
			for key, parts in pairs(oldSource) do
				checkpoint(check)
				if new[key] and not equal(parts, newSource[key]) then
					item.changes[#item.changes + 1] = {
						kind = "source",
						instanceId = key,
						beforeCaptureId = before.captureId,
						afterCaptureId = after.captureId,
					}
				end
			end
			for key in pairs(newSource) do
				if old[key] and not oldSource[key] then
					item.changes[#item.changes + 1] = {
						kind = "source",
						instanceId = key,
						beforeCaptureId = before.captureId,
						afterCaptureId = after.captureId,
					}
				end
			end
			if recording then
				item.events = recording.events
				item.markers = recording.markers
				item.coverage.eventsDropped = recording.dropped
				item.coverage.watchId = recording.watchId
				item.coverage.eventClock = "ActivitySession relative time; capture interval is non-atomic"
			end
			item.duration = math.max(
				0,
				(after.startedClock or after.createdAt or 0) - (before.startedClock or before.createdAt or 0)
			)
			return store(item)
		end
		add("capture_system", function(args)
			return c.StartJob(function(check)
				return capture(args, check)
			end)
		end)
		add("list_captures", function()
			local rows = {}
			for _, key in ipairs(order) do
				rows[#rows + 1] = summary(saved[key])
			end
			return { captures = rows, estimatedBytes = totalBytes, limit = 8 }
		end)
		add("get_capture", function(args)
			return summary(get(args.captureId))
		end)
		add("delete_capture", function(args)
			local item = get(args.captureId)
			totalBytes -= item.estimatedBytes
			saved[args.captureId] = nil
			table.remove(order, table.find(order, args.captureId))
			return { deleted = true }
		end)
		local function read(args, section)
			local item = get(args.captureId)
			section = section or args.section
			assert(sections[section], "INVALID_ARGUMENT: unknown capture section")
			local rows = item[section] or {}
			local offset = int(args.offset, 1, 1000000)
			local limit = int(args.limit, 25, 100)
			local output = {}
			local bytes = 0
			for index = offset, math.min(#rows, offset + limit - 1) do
				local row = rows[index]
				local count = size(row)
				if bytes + count > 160 * 1024 then
					break
				end
				output[#output + 1] = row
				bytes += count
			end
			assert(#output > 0 or offset > #rows, "RESULT_LIMIT: capture row exceeds page size")
			return {
				captureId = item.captureId,
				section = section,
				items = output,
				total = #rows,
				offset = offset,
				nextOffset = offset + #output <= #rows and offset + #output or nil,
			}
		end
		add("read_capture", function(args)
			return read(args)
		end)
		add("get_capture_assets", function(args)
			return read(args, "assets")
		end)
		add("get_capture_relationships", function(args)
			return read(args, "relationships")
		end)
		add("compare_captures", function(args)
			local before, after = get(args.beforeId), get(args.afterId)
			return c.StartJob(function(check)
				return compare(before, after, check, args.name)
			end)
		end)
		add("measure_instances", function(args)
			local output = {}
			for _, object in ipairs(roots(args)) do
				output[#output + 1] = { instance = registry:Describe(object), measurements = measure(object) }
			end
			return { instances = output, camera = camera(), scope = "client", nonAtomic = true }
		end)
		local function scan(args, trace)
			local root = args.rootId and registry:Resolve(args.rootId) or c.Game
			local query = not trace and text(args.query, 200)
			local needle = query and (args.caseSensitive and query or query:lower())
			local maximum = int(args.maxScripts, 2000, 10000)
			local limit = int(args.limit, 100, 200)
			return c.StartJob(function(check)
				local rows = {}
				local checked, unavailable, bytes, decompiles = 0, 0, 0, 0
				local hitLimit = false
				local _, truncated = walk({ root }, 20000, check, function(object)
					if checked >= maximum or hitLimit then
						return false
					end
					if not object:IsA("LuaSourceContainer") then
						return
					end
					checked += 1
					local allow = args.decompile == true and decompiles < 8
					local contents, kind, called = source(object, allow)
					if called then
						decompiles += 1
					end
					if not contents or #contents > 1024 * 1024 or bytes + #contents > 8 * 1024 * 1024 then
						unavailable += 1
						return
					end
					bytes += #contents
					local line = 0
					local offset = 1
					for value in (contents .. "\n"):gmatch("(.-)\n") do
						line += 1
						if line % 64 == 0 then
							checkpoint(check)
						end
						if trace then
							for _, pattern in ipairs({
								{ kind = "require", pattern = "require%s*%((.-)%)" },
								{ kind = "service", pattern = "GetService%s*%([\"']([^\"']+)[\"']%s*%)" },
								{ kind = "child_lookup", pattern = "WaitForChild%s*%([\"']([^\"']+)[\"']" },
								{ kind = "remote_call", pattern = "([%w_%.]+)%s*:%s*(FireServer)%s*%((.-)%)" },
								{ kind = "remote_call", pattern = "([%w_%.]+)%s*:%s*(InvokeServer)%s*%((.-)%)" },
							}) do
								local start, _, a, b = string.find(value, pattern.pattern)
								if start then
									rows[#rows + 1] = {
										instance = registry:Describe(object),
										line = line,
										column = start,
										kind = pattern.kind,
										expression = (a or ""):sub(1, 300),
										operation = b,
										sourceKind = kind,
										snippet = value:sub(1, 400),
										evidence = "text_candidate",
									}
								end
								if #rows >= limit then
									hitLimit = true
									break
								end
							end
						else
							local hay = args.caseSensitive and value or value:lower()
							local start = 1
							while #rows < limit do
								local first, last = hay:find(needle, start, true)
								if not first then
									break
								end
								rows[#rows + 1] = {
									instance = registry:Describe(object),
									line = line,
									column = first,
									endColumn = last + 1,
									byteOffset = offset + first - 1,
									sourceKind = kind,
									snippet = value:sub(math.max(1, first - 80), math.min(#value, last + 160)),
									evidence = "text_match",
								}
								start = last + 1
							end
							if #rows >= limit then
								hitLimit = true
							end
						end
						offset += #value + 1
						if hitLimit then
							break
						end
					end
				end)
				return {
					matches = rows,
					scriptsChecked = checked,
					scriptsUnavailable = unavailable,
					sourceBytes = bytes,
					decompileCalls = decompiles,
					truncated = truncated or checked >= maximum or hitLimit,
					note = trace
							and "Text candidates may include comments, strings and dynamic expressions. No requires, game functions or remotes were executed."
						or "Literal source search; line/column offsets are bytes. Cached or decompiled source may differ from original source.",
				}
			end)
		end
		add("search_scripts", function(args)
			return scan(args, false)
		end)
		add("trace_scripts", function(args)
			return scan(args, true)
		end)
		add("start_recording", function(args)
			local object = registry:Resolve(args.instanceId)
			local count = 0
			for _, record in pairs(recordings) do
				if record.State == "starting" or record.State == "recording" or record.State == "stopping" then
					count += 1
				end
			end
			assert(count < 2, "RECORDING_LIMIT: finish a recording first")
			local retained = 0
			for key, record in pairs(recordings) do
				retained += 1
				if retained > 16 and (record.State == "completed" or record.State == "failed") then
					recordings[key] = nil
				end
			end
			local watched = c.Handlers.dex_watch_instance({ instanceId = args.instanceId })
			local key = nextId("recording")
			local record = {
				Id = key,
				Target = object,
				RootId = args.instanceId,
				WatchId = watched.watchId,
				Started = os.clock(),
				Markers = {},
				State = "starting",
				Name = args.name and text(args.name, 120) or object.Name,
			}
			recordings[key] = record
			local scheduled, job = pcall(c.StartJob, function(check)
				local ok, value = pcall(
					capture,
					{ instanceIds = { record.RootId }, name = record.Name .. " before", includeSource = false },
					check
				)
				if not ok then
					pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
					record.State = "failed"
					error(value, 0)
				end
				record.Before = value.captureId
				record.State = "recording"
				return {
					recordingId = key,
					beforeCaptureId = record.Before,
					watchId = record.WatchId,
					status = record.State,
				}
			end, function(status)
				if status ~= "completed" then
					pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
					record.State = "failed"
				end
			end)
			if not scheduled then
				pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
				recordings[key] = nil
				error(job, 0)
			end
			record.StartJob = job
			return { recordingId = key, job = record.StartJob, status = record.State }
		end)
		add("get_recording", function(args)
			local record = recordings[args.recordingId]
			assert(record, "RECORDING_UNAVAILABLE")
			return {
				recordingId = record.Id,
				status = record.State,
				beforeCaptureId = record.Before,
				afterCaptureId = record.After,
				comparisonId = record.Diff,
				watchId = record.WatchId,
				duration = (record.Ended or os.clock()) - record.Started,
				markers = record.Markers,
			}
		end)
		add("mark_recording", function(args)
			local record = recordings[args.recordingId]
			assert(record and record.State == "recording", "RECORDING_UNAVAILABLE: recording not active")
			assert(#record.Markers < 32, "MARKER_LIMIT")
			record.Markers[#record.Markers + 1] = { label = text(args.label, 120), time = os.clock() - record.Started }
			return { recordingId = record.Id, markers = record.Markers }
		end)
		add("stop_recording", function(args)
			local record = recordings[args.recordingId]
			assert(
				record and record.State == "recording",
				"RECORDING_UNAVAILABLE: recording not ready or already stopped"
			)
			record.State = "stopping"
			local scheduled, job = pcall(c.StartJob, function(check)
				local ok, value = pcall(function()
					local before = get(record.Before)
					local after = capture(
						{ instanceIds = { record.RootId }, name = record.Name .. " after", includeSource = false },
						check
					)
					record.After = after.captureId
					local events = c.Handlers.dex_get_events({ watchId = record.WatchId, limit = 100 })
					local rest =
						c.Handlers.dex_get_events({ watchId = record.WatchId, afterId = events.nextId, limit = 100 })
					for _, event in ipairs(rest.events) do
						events.events[#events.events + 1] = event
					end
					local diff = compare(before, get(record.After), check, record.Name .. " interaction", {
						events = events.events,
						markers = record.Markers,
						dropped = rest.dropped,
						watchId = record.WatchId,
					})
					record.Diff = diff.captureId
					return {
						recordingId = record.Id,
						beforeCaptureId = record.Before,
						afterCaptureId = record.After,
						comparison = diff,
					}
				end)
				pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
				record.State = ok and "completed" or "failed"
				if not ok then
					error(value, 0)
				end
				return value
			end, function(status)
				pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
				record.Ended = os.clock()
				if status ~= "completed" then
					record.State = "failed"
				end
			end)
			if not scheduled then
				record.State = "recording"
				error(job, 0)
			end
			return job
		end)
		add("cancel_recording", function(args)
			local record = recordings[args.recordingId]
			assert(record, "RECORDING_UNAVAILABLE")
			assert(record.State ~= "stopping", "BUSY: wait for the final capture job")
			if record.State == "starting" then
				c.Handlers.dex_cancel_job({ jobId = record.StartJob.jobId })
			end
			pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
			recordings[args.recordingId] = nil
			return { cancelled = true }
		end)
		function result:Destroy()
			dead = true
			for _, record in pairs(recordings) do
				pcall(c.Handlers.dex_stop_watch, { watchId = record.WatchId })
			end
			table.clear(recordings)
			table.clear(saved)
			table.clear(order)
			table.clear(classCache)
			totalBytes = 0
		end
		return result
	end
	return Capture
end
return { Main = Main }
