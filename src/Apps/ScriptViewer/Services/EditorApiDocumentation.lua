--!strict

local Apps, env, service

local function InitDeps(deps)
	Apps, env, service = deps.Apps, deps.env, deps.service
end

local function Main()
	local Documentation = {}
	local sourceUrl =
		"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/api-docs/en-us.json"
	local cachePath = "dex-explorer/cache/studio-api-docs-en-us.json"
	local refreshPeriod = 24 * 60 * 60
	local records, loading, retryAfter = nil, false, -math.huge
	local checkedAt, generation = 0, 0
	local builtins = Apps.EditorBuiltinSignatures
	Documentation.Signature = function(name)
		return builtins.Signatures[name]
	end
	function Documentation.TakesArguments(name)
		local variants = builtins.Overloads[name]
		if variants then
			for _, variant in ipairs(variants) do
				if variant[1] > 0 then
					return true
				end
			end
			return false
		end
		local signature = builtins.Signatures[name]
		return not signature or not signature:match("^[^(]*%(%s*%)")
	end

	local function decode(data)
		if type(data) ~= "string" or #data > 24 * 1024 * 1024 then
			return nil
		end
		local ok, parsed = pcall(service.HttpService.JSONDecode, service.HttpService, data)
		if
			ok
			and type(parsed) == "table"
			and type(parsed["@roblox/globaltype/Instance.IsDescendantOf"]) == "table"
			and type(parsed["@luau/global/math.sqrt"]) == "table"
		then
			return parsed
		end
		return nil
	end

	function Documentation.Load(onReady)
		local now = os.time()
		if loading or os.clock() < retryAfter or (records and now - checkedAt < refreshPeriod) then
			return
		end
		loading = true
		task.defer(function()
			if not records and env.readfile then
				local ok, cached = pcall(env.readfile, cachePath)
				records = ok and decode(cached) or nil
				if records then
					local stamped, stamp = pcall(env.readfile, cachePath .. ".timestamp")
					checkedAt = stamped and math.min(now, tonumber(stamp) or 0) or 0
					generation += 1
					onReady()
				end
			end
			if not records or now - checkedAt >= refreshPeriod then
				local ok, data
				if env.request then
					local sent, response = pcall(env.request, { Url = sourceUrl, Method = "GET" })
					if sent and type(response) == "table" and (response.StatusCode or response.Status) == 200 then
						ok, data = true, response.Body
					end
				end
				if not ok then
					ok, data = pcall(function()
						return (oldgame or game):HttpGet(sourceUrl)
					end)
				end
				local updated = ok and decode(data)
				if updated then
					records, checkedAt = updated, now
					generation += 1
					if env.writefile then
						if env.makefolder then
							pcall(env.makefolder, "dex-explorer")
							pcall(env.makefolder, "dex-explorer/cache")
						end
						if pcall(env.writefile, cachePath, data) then
							pcall(env.writefile, cachePath .. ".timestamp", tostring(now))
						end
					end
					onReady()
				else
					retryAfter = os.clock() + 60
				end
			end
			loading = false
		end)
	end

	local function content(value)
		return type(value) == "string" and value ~= "" and value or nil
	end

	local function addDetails(item, record)
		local description = content(record.documentation)
		if description then
			item.Documentation = description
			item.DocumentationFormat = "html"
			item.CodeExample = content(record.code_sample)
			item.Url = content(record.learn_more_link)
			item.TypeOnly = false
		end
	end

	function Documentation.Apply(item, argument)
		if not (item.DocKey or item.DocGlobal) then
			return item
		end
		if not argument and item.StudioDocumentationVersion == generation then
			return item.StudioDocumentation or item
		end
		if not argument then
			item.StudioDocumentationVersion = generation
			item.StudioDocumentation = nil
		end
		local record = records and item.DocKey and records[item.DocKey]
		if records and item.DocGlobal then
			record = records["@roblox/global/" .. item.DocGlobal] or records["@luau/global/" .. item.DocGlobal]
		end
		local builtin = item.DocCallable and builtins.Signatures[item.DocGlobal]
		if not builtin and type(record) ~= "table" then
			return item
		end
		local source = item
		item = table.clone(source)
		if builtin then
			item.Detail = builtin
			local variants = builtins.Overloads[item.DocGlobal]
			if variants then
				item.Overloads = #variants - 1
				if argument then
					for _, variant in ipairs(variants) do
						if variant[1] >= argument then
							item.Detail = variant[2]
							break
						end
					end
				end
			end
		end
		if type(record) == "table" and type(record.overloads) == "table" then
			local variants = {}
			for signature, reference in pairs(record.overloads) do
				if type(signature) == "string" and type(records[reference]) == "table" then
					variants[#variants + 1] = signature
				end
			end
			table.sort(variants, function(a, b)
				if #a ~= #b then
					return #a < #b
				end
				return a < b
			end)
			local first = variants[1]
			if first then
				item.Overloads = #variants - 1
				if not builtin or not argument then
					local arguments, returns = first:match("^(%b()) %-> (.+)$")
					item.Detail = (item.DocGlobal or item.Name) .. (arguments and arguments .. ": " .. returns or first)
				end
				record = records[record.overloads[first]]
			end
		elseif not builtin and item.DocCallable and type(record) == "table" and type(record.params) == "table" then
			local names = {}
			for _, param in ipairs(record.params) do
				if type(param) == "table" and type(param.name) == "string" then
					names[#names + 1] = param.name
				end
			end
			item.Detail = item.DocGlobal .. "(" .. table.concat(names, ", ") .. ")"
		end
		if type(record) == "table" then
			addDetails(item, record)
		end
		if not argument then
			source.StudioDocumentation = item
		end
		return item
	end

	return Documentation
end

return { InitDeps = InitDeps, Main = Main }
