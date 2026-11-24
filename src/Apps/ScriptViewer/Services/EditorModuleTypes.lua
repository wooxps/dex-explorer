--!strict

local Apps, env, Runtime

local function InitDeps(deps)
	Apps, env, Runtime = deps.Apps, deps.env, deps.Main
end

local function copyExport(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	local copies = { [value] = copy }
	local queue = { value }
	local cursor, remaining = 1, 2048
	while cursor <= #queue do
		local original = queue[cursor]
		local target = copies[original]
		for key, member in original do
			remaining -= 1
			if remaining < 0 then
				return nil
			end
			if type(member) == "table" then
				if not copies[member] then
					copies[member] = {}
					queue[#queue + 1] = member
				end
				member = copies[member]
			end
			target[key] = member
		end
		cursor += 1
	end
	return copy
end

local function Main()
	local Modules = {}
	local pending = {}
	local retryAfter = setmetatable({}, { __mode = "k" })
	local indexed = setmetatable({}, { __mode = "k" })
	local order = {}
	local queue = {}
	local running = false
	local resumeAt = 0
	local drain
	local function readNext()
		while Runtime.Alive ~= false and #queue > 0 do
			local object = table.remove(queue, 1)
			local request = pending[object]
			if request and request.Valid() then
				local cached = Apps.ReferenceSource.Peek(object)
				if not cached then
					local started = os.clock()
					local ok, source = pcall(env.decompile, object)
					local elapsed = os.clock() - started
					if Runtime.Performance then
						Runtime.Performance.Record("editor/module-decompile", elapsed)
					end
					retryAfter[object] = os.clock() + 30
					resumeAt = os.clock() + (elapsed > 0.04 and 2 or 0)
					if
						Runtime.Alive ~= false
						and ok
						and type(source) == "string"
						and #source > 0
						and #source <= 65536
					then
						Apps.ReferenceSource.Store(object, source, "Cached decompiled source")
						cached = Apps.ReferenceSource.Peek(object)
					end
				end
				request = pending[object]
				pending[object] = nil
				running = false
				drain()
				if cached and request and Runtime.Alive ~= false and request.Valid() then
					task.defer(request.Ready)
				end
				return
			end
			pending[object] = nil
		end
		table.clear(queue)
		table.clear(pending)
		running = false
	end
	drain = function()
		if not running and #queue > 0 then
			running = true
			task.delay(math.max(0.08, resumeAt - os.clock()), readNext)
		end
	end
	local function requestSource(object, context)
		if not context.OnModuleReady or type(env.decompile) ~= "function" then
			return
		end
		local valid = context.ModuleRequestValid
		if not valid or not valid() then
			return
		end
		local request = pending[object]
		if request then
			request.Valid, request.Ready = valid, context.OnModuleReady
		elseif #queue < 4 and (retryAfter[object] or 0) <= os.clock() then
			pending[object] = { Valid = valid, Ready = context.OnModuleReady }
			queue[#queue + 1] = object
			drain()
		end
	end
	function Modules.RequestMissing(missing, context)
		for object in missing do
			requestSource(object, context)
		end
	end

	function Modules.Resolver(source, context, resolveMember, checkpoint)
		local cache, resolving = {}, {}
		local missing = {}
		if context.Script then
			resolving[context.Script] = true
		end
		local remainingModules, remainingBytes = 12, 128 * 1024
		local analyze
		local cancelled = {}
		local function indexCheckpoint()
			if not checkpoint() then
				error(cancelled, 0)
			end
		end
		local function bindResolver(text, scriptObject, depth, entry, tokens)
			local definitions
			return function(position)
				if not position or depth >= 6 or #text > 65536 then
					return nil
				end
				definitions = definitions or entry and entry.Definitions or Apps.EditorDefinitions.New()
				if not definitions.Prime(text, checkpoint, tokens) then
					return nil
				end
				if entry and entry.Tokens then
					entry.Definitions = definitions
				end
				local reference = definitions.Resolve(text, position, scriptObject, context.Game, context.Workspace)
				local module = reference and reference.Object
				if not module or module.ClassName ~= "ModuleScript" or resolving[module] then
					return nil
				end
				if cache[module] == nil then
					cache[module] = analyze(module, depth + 1) or false
				end
				local result = cache[module]
				if result then
					return result.Export, result.Types
				end
				return nil
			end
		end
		function analyze(object, depth)
			if remainingModules <= 0 or remainingBytes <= 0 or checkpoint and not checkpoint() then
				return nil
			end
			remainingModules -= 1
			local text = context.ModuleSource and context.ModuleSource(object)
			if text == nil then
				local ok, raw = pcall(function()
					return object.Source
				end)
				local cached = Apps.ReferenceSource.Peek(object)
				text = ok and type(raw) == "string" and raw ~= "" and raw or cached and cached.Source
			end
			if type(text) ~= "string" then
				missing[object] = true
				return nil
			end
			if #text > math.min(65536, remainingBytes) then
				return nil
			end
			remainingBytes -= #text
			resolving[object] = true
			local entry = indexed[object]
			if not entry or entry.Source ~= text then
				local symbols = Apps.EditorSymbols.New()
				if checkpoint then
					local ok, failure = pcall(symbols.Index, symbols, text, indexCheckpoint)
					if not ok then
						resolving[object] = nil
						if failure ~= cancelled then
							error(failure, 0)
						end
						return nil
					end
				else
					symbols:Index(text)
				end
				local exportedTypes = {}
				for name, alias in symbols.Types do
					if alias.Exported then
						exportedTypes[name] = alias
					end
				end
				if not indexed[object] then
					if #order >= 16 then
						indexed[table.remove(order, 1)] = nil
					end
					order[#order + 1] = object
				end
				entry = {
					Source = text,
					Symbols = symbols,
					Types = exportedTypes,
					CanReuseExport = not text:find("require", 1, true),
				}
				indexed[object] = entry
			end
			if entry.Export and entry.MemberResolver == resolveMember then
				resolving[object] = nil
				return { Export = copyExport(entry.Export), Types = entry.Types }
			end
			local tokens = entry.Tokens or Apps.EditorDefinitions.Tokenize(text, checkpoint)
			if not tokens then
				resolving[object] = nil
				return nil
			end
			if #tokens <= 4096 then
				entry.Tokens = tokens
			end
			local result = Apps.EditorHoverTypes.Analyze(text, entry.Symbols, resolveMember, checkpoint, {
				Require = bindResolver(text, object, depth, entry, tokens),
				Tokens = tokens,
				ExportOnly = true,
			})
			local export = result and Apps.EditorHoverTypes.Resolve(result.Export)
			if entry.CanReuseExport and export and (not checkpoint or checkpoint()) then
				local exportCopy = copyExport(export)
				if exportCopy then
					entry.Export, entry.MemberResolver = exportCopy, resolveMember
				end
			end
			resolving[object] = nil
			return { Export = export, Types = entry.Types }
		end
		return bindResolver(source, context.Script, 0), missing
	end
	return Modules
end

return { InitDeps = InitDeps, Main = Main }
