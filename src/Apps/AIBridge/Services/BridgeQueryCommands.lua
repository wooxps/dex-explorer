--!strict

------------------------------ Module ------------------------------

local function Main()
	local Query = {}
	local function integer(value, default, maximum)
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
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local total = 2
		for key, item in pairs(value) do
			total += size(key) + size(item) + 2
		end
		return total
	end
	function Query.Create(c)
		local registry, codec = c.Registry, c.Codec
		local result = { Commands = {} }
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		add("inspect_instances", function(args)
			assert(
				type(args.instanceIds) == "table" and #args.instanceIds >= 1 and #args.instanceIds <= 20,
				"INVALID_ARGUMENT: choose 1 to 20 instance IDs"
			)
			local wanted = args.properties
			if wanted == nil then
				wanted = { "Name", "ClassName", "Parent" }
			end
			assert(
				type(wanted) == "table" and #wanted >= 1 and #wanted <= 16,
				"INVALID_ARGUMENT: choose 1 to 16 properties"
			)
			for _, key in ipairs(wanted) do
				text(key, 128)
			end
			for _, key in ipairs({ "includeAttributes", "includeTags" }) do
				assert(args[key] == nil or type(args[key]) == "boolean", "INVALID_ARGUMENT: boolean required")
			end
			local output = {
				scope = "client",
				instances = {},
				requested = #args.instanceIds,
				processed = 0,
				truncated = false,
				omittedFields = 0,
			}
			local bytes = 1024
			for _, id in ipairs(args.instanceIds) do
				text(id, 160)
				local row = { instanceId = id, properties = {}, errors = {} }
				local ok, object = pcall(registry.Resolve, registry, id)
				if not ok then
					row.error = tostring(object):sub(1, 200)
				else
					local good, description = pcall(registry.Describe, registry, object)
					if good then
						row.instance = description
					else
						row.error = tostring(description):sub(1, 200)
					end
					local function read(key, callback, target)
						if bytes + size(row) > 47000 then
							output.truncated = true
							output.omittedFields += 1
							return
						end
						local success, value = pcall(callback)
						if success and size(value) <= 8192 and bytes + size(row) + size(key) + size(value) <= 48000 then
							target[key] = value
						else
							row.errors[key] = success and "RESULT_LIMIT: field omitted" or tostring(value):sub(1, 200)
							output.omittedFields += 1
							if success then
								output.truncated = true
							end
						end
					end
					for _, key in ipairs(wanted) do
						read(key, function()
							assert(
								c.Apps.ReflectionService.GetProperty(object.ClassName, key),
								"INVALID_PROPERTY: " .. key
							)
							return codec:Encode(object[key])
						end, row.properties)
					end
					if args.includeAttributes then
						read("attributes", function()
							return codec:Encode(object:GetAttributes())
						end, row)
					end
					if args.includeTags then
						read("tags", function()
							return codec:Encode(c.service.CollectionService:GetTags(object))
						end, row)
					end
				end
				local cost = size(row)
				if bytes + cost > 48000 then
					output.truncated = true
					break
				end
				bytes += cost
				output.instances[#output.instances + 1] = row
				output.processed += 1
			end
			return output
		end)
		add("query_instances", function(args)
			local root = c.Game
			if args.rootId ~= nil then
				root = registry:Resolve(args.rootId)
			end
			local maximum = integer(args.maxNodes, 2000, 5000)
			local limit = integer(args.limit, 50, 100)
			local name, class
			if args.name ~= nil then
				name = text(args.name, 256)
			end
			if args.className ~= nil then
				class = text(args.className, 128)
			end
			assert(
				args.caseSensitive == nil or type(args.caseSensitive) == "boolean",
				"INVALID_ARGUMENT: caseSensitive must be boolean"
			)
			if name and not args.caseSensitive then
				name = name:lower()
			end
			local tags = args.tags
			if tags == nil then
				tags = {}
			end
			assert(type(tags) == "table" and #tags <= 8, "INVALID_ARGUMENT: at most 8 required tags")
			for _, tag in ipairs(tags) do
				text(tag, 128)
			end
			local function predicates(values)
				if values == nil then
					values = {}
				end
				assert(type(values) == "table", "INVALID_ARGUMENT: predicate map required")
				local rows = {}
				local count = 0
				for key, value in pairs(values) do
					count += 1
					assert(count <= 8, "INVALID_ARGUMENT: at most 8 predicates")
					text(key, 128)
					rows[#rows + 1] = { Key = key, Value = codec:Decode(value) }
				end
				return rows
			end
			local attributes, properties = predicates(args.attributes), predicates(args.properties)
			assert(c.StartJob, "UNSUPPORTED: analysis jobs unavailable")
			return c.StartJob(function(check)
				local stack = { root }
				local rows = {}
				local scanned, unavailable, bytes = 0, 0, 1024
				local truncated = false
				while #stack > 0 do
					assert(check(), "CANCELLED: query ended")
					local object = table.remove(stack)
					if registry:Allowed(object) then
						scanned += 1
						local matches = (
							not name
							or (args.caseSensitive and object.Name or object.Name:lower()):find(name, 1, true)
								~= nil
						) and (not class or object:IsA(class))
						if matches then
							local ok, match = pcall(function()
								for _, tag in ipairs(tags) do
									if not c.service.CollectionService:HasTag(object, tag) then
										return false
									end
								end
								for _, predicate in ipairs(attributes) do
									if object:GetAttribute(predicate.Key) ~= predicate.Value then
										return false
									end
								end
								for _, predicate in ipairs(properties) do
									if not c.Apps.ReflectionService.GetProperty(object.ClassName, predicate.Key) then
										return false
									end
									if object[predicate.Key] ~= predicate.Value then
										return false
									end
								end
								return true
							end)
							if not ok then
								unavailable += 1
								matches = false
							else
								matches = match
							end
						end
						if matches then
							local ok, row = pcall(registry.Describe, registry, object)
							if ok then
								local cost = size(row)
								if #rows >= limit or bytes + cost > 48000 then
									truncated = true
									break
								end
								bytes += cost
								rows[#rows + 1] = row
							else
								unavailable += 1
							end
						end
						if scanned >= maximum then
							if #stack > 0 or #object:GetChildren() > 0 then
								truncated = true
							end
							break
						end
						local children = object:GetChildren()
						local room = maximum - scanned - #stack
						if #children > room then
							truncated = true
						end
						for index = math.min(#children, math.max(0, room)), 1, -1 do
							stack[#stack + 1] = children[index]
						end
					end
				end
				return {
					scope = "client",
					instances = rows,
					scanned = scanned,
					maxNodes = maximum,
					truncated = truncated,
					unavailableReads = unavailable,
					includesRoot = true,
					matching = "literal_name_and_exact_typed_values",
				}
			end)
		end)
		function result:Destroy() end
		return result
	end
	return Query
end
return { Main = Main }
