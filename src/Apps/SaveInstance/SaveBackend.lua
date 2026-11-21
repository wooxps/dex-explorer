--!strict

local Main, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, env = d.Main, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Backend = {}
	local universal
	Backend.SourceURL = "https://raw.githubusercontent.com/rbxlx/UniversalSynSaveInstance/main/saveinstance.luau"
	function Backend.Run(engine, object, path, options)
		local args = table.clone(options or {})
		if path and path ~= "" then
			args.FilePath = path
		end
		if object then
			args.Object = object
		end
		if engine == "Executor" then
			assert(
				type(env.executorSaveInstance) == "function",
				"This executor has no built-in saveinstance. Choose Universal."
			)
			if args.IgnoreDefaultProperties ~= nil then
				args.IgnoreDefaultProps = args.IgnoreDefaultProperties
			end
			if args.SavePlayerCharacters ~= nil then
				args.RemovePlayerCharacters = not args.SavePlayerCharacters
			end
			if args.IsolatePlayers ~= nil then
				args.SavePlayers = args.IsolatePlayers
			end
			local target = typeof(args.Object) == "Instance" and args.Object or object
			if not target and type(args.ExtraInstances) == "table" then
				assert(#args.ExtraInstances <= 1, "Use Universal to save multiple roots")
				target = args.ExtraInstances[1]
			end
			return env.executorSaveInstance(
				target or game,
				path or args.FilePath or ("Place_" .. game.PlaceId .. "_" .. os.date("%Y-%m-%d_%H-%M-%S")),
				args
			)
		end
		assert(engine == "Universal", "Unknown save provider")
		assert(type(env.loadstring) == "function", "Universal requires loadstring support")
		if not universal then
			local source = (oldgame or game):HttpGet(Backend.SourceURL)
			assert(type(source) == "string" and #source > 0, "Universal download returned no source")
			local chunk, problem = env.loadstring(source, "@UniversalSynSaveInstance")
			assert(chunk, "Universal could not compile: " .. tostring(problem))
			local result = chunk()
			assert(type(result) == "function", "Universal did not return a save function")
			universal = result
		end
		return universal(args)
	end
	return Backend
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
