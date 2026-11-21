--!strict

local Main, Apps, Lib, Settings, env, http

local function InitDeps(deps)
	Main, Apps, Lib, Settings, env = deps.Main, deps.Apps, deps.Lib, deps.Settings, deps.env
	http = deps.service.HttpService
end

local maxSource = 512 * 1024
local maxPackage = 2 * 1024 * 1024
local maxStore = 12 * 1024 * 1024
local maxSettings = 64 * 1024
local maxPlugins = 64
local maxButtons = 24
local maxActions = 40
local maxOutputRows = 120
local maxOutputBytes = 1024 * 1024
local surfaces = { Explorer = true, Editor = true, Global = true }
local storePath = "dex-explorer/plugins/installed.json"

local function validId(value)
	return type(value) == "string" and #value <= 80 and value:match("^[a-z0-9][a-z0-9._%-]*$") ~= nil
end

local function label(value, limit, multiline)
	if type(value) ~= "string" or #value > limit or not utf8.len(value) then
		return nil
	end
	if (multiline and value:gsub("[\r\n\t]", "") or value):find("%c") then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$")
	return trimmed ~= "" and trimmed or nil
end

local function icon(value)
	if type(value) == "string" and #value <= 64 then
		local id = value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
		return id and "rbxassetid://" .. id or nil
	end
	return nil
end

local function importPath(value)
	local path = label(value, 260)
	if not path then
		return nil
	end
	path = path:gsub("\\", "/")
	if path:sub(1, 1) == "/" or path:find('[<>:"|?*]') or not path:lower():match("%.dexplugin$") then
		return nil
	end
	for segment in path:gmatch("[^/]+") do
		if segment:match("^[. ]+$") or segment:match("[. ]$") then
			return nil
		end
	end
	return if path:find("/", 1, true) then path else "dex-explorer/plugins/" .. path
end

local function buttonDefinition(id, name, image, tooltip)
	if not validId(id) then
		return nil
	end
	name = label(name, 100)
	if not name then
		return nil
	end
	return table.freeze({ ID = id, Name = name, Icon = icon(image), Tooltip = label(tooltip, 256) })
end

local function decodePackage(data)
	if type(data) ~= "table" or data.schema ~= 1 then
		return nil, "Expected a .dexplugin package with schema 1."
	end
	local name, version = label(data.name, 100), label(data.version, 40)
	if not validId(data.id) or not name or not version then
		return nil, "A plugin needs a lowercase ID, a name, and a version."
	end
	local source = data.source
	if
		type(source) ~= "string"
		or #source == 0
		or #source > maxSource
		or source:sub(1, 1) == "\27"
		or not utf8.len(source)
	then
		return nil, "The package needs UTF-8 Luau source up to 512 KiB."
	end
	local image = icon(data.icon)
	local buttons, ids = {}, {}
	if data.buttons ~= nil then
		if type(data.buttons) ~= "table" or #data.buttons > maxButtons then
			return nil, "A plugin can declare up to 24 buttons."
		end
		for listIndex in pairs(data.buttons) do
			if type(listIndex) ~= "number" or listIndex % 1 ~= 0 or listIndex < 1 or listIndex > #data.buttons then
				return nil, "Expected a list of buttons."
			end
		end
		for _, entry in ipairs(data.buttons) do
			local definition = type(entry) == "table"
				and buttonDefinition(entry.id, entry.name, entry.icon or image, entry.tooltip)
			if not definition or ids[definition.ID] then
				return nil, "Each button needs a unique lowercase ID and a name."
			end
			ids[definition.ID] = true
			table.insert(buttons, definition)
		end
	end
	if #buttons == 0 then
		buttons[1] = buttonDefinition("open", name, image, data.description)
	end
	return {
		ID = data.id,
		Name = name,
		Version = version,
		Author = label(data.author, 100),
		Description = label(data.description, 2000, true),
		Icon = image,
		Startup = data.startup == true,
		Buttons = table.freeze(buttons),
		Source = source,
	}
end

local function encodePackage(package)
	local buttons = {}
	for _, entry in ipairs(package.Buttons) do
		buttons[#buttons + 1] = { id = entry.ID, name = entry.Name, icon = entry.Icon, tooltip = entry.Tooltip }
	end
	return {
		schema = 1,
		id = package.ID,
		name = package.Name,
		version = package.Version,
		author = package.Author,
		description = package.Description,
		icon = package.Icon,
		startup = package.Startup,
		buttons = buttons,
		source = package.Source,
	}
end

local function displayText(value, limit)
	local ok, raw = pcall(tostring, value)
	local text = ok and raw or "Unable to display value."
	if #text > limit then
		local last = limit
		while text:byte(last + 1) and text:byte(last + 1) >= 128 and text:byte(last + 1) < 192 do
			last -= 1
		end
		text = text:sub(1, math.max(0, last)) .. "…"
	end
	if not utf8.len(text) then
		return text:gsub("[\128-\255]", "?")
	end
	return text
end

local function capturedError(problem)
	return {
		Message = displayText(problem, 2000),
		Traceback = displayText(debug.traceback(nil, 2), 6000),
	}
end

local function CreateModule()
	local runtime = { Changed = Lib.Signal.new(), OutputChanged = Lib.Signal.new() }
	local records, sessions = {}, {}
	local output, actionViews = {}, {}
	local outputSequence = 0
	local started, stopped, writing = false, false, false
	local startPlugin

	local function emit(record, level, message, traceback)
		local id = record.ID
		if stopped or not records[id] then
			return
		end
		local bucket = output[id]
		if not bucket then
			bucket = { Entries = {}, Sources = {}, Bytes = 0 }
			output[id] = bucket
		end
		outputSequence += 1
		local line, source
		if level == "Error" then
			local chunk = ("DexExplorer/Plugins/" .. id):gsub("(%W)", "%%%1")
			local location = chunk .. ":(%d+)"
			line = tonumber(message:match(location) or (traceback and traceback:match(location)))
			source = line and record.Source or nil
		end
		local entry = table.freeze({
			Sequence = outputSequence,
			Timestamp = os.time(),
			Level = level,
			Message = message,
			Traceback = traceback,
			Line = line,
			Source = source,
		})
		bucket.Entries[#bucket.Entries + 1] = entry
		bucket.Bytes += #message + (traceback and #traceback or 0)
		if source then
			local uses = bucket.Sources[source] or 0
			bucket.Sources[source] = uses + 1
			if uses == 0 then
				bucket.Bytes += #source
			end
		end
		while #bucket.Entries > maxOutputRows or bucket.Bytes > maxOutputBytes do
			local removed = table.remove(bucket.Entries, 1)
			bucket.Bytes -= #removed.Message + (removed.Traceback and #removed.Traceback or 0)
			local previous = removed.Source
			if previous then
				local remaining = bucket.Sources[previous] - 1
				bucket.Sources[previous] = remaining > 0 and remaining or nil
				if remaining == 0 then
					bucket.Bytes -= #previous
				end
			end
		end
		runtime.OutputChanged:Fire(id)
	end

	local function logError(record, failure, prefix)
		emit(record, "Error", if prefix then prefix .. failure.Message else failure.Message, failure.Traceback)
	end

	function runtime.GetOutput(id)
		local bucket = output[id]
		return bucket and table.clone(bucket.Entries) or {}
	end

	function runtime.ClearOutput(id)
		if not records[id] then
			return false
		end
		output[id] = nil
		runtime.OutputChanged:Fire(id)
		return true
	end

	local function ordered()
		local orderedRecords = {}
		for _, record in pairs(records) do
			orderedRecords[#orderedRecords + 1] = record
		end
		table.sort(orderedRecords, function(a, b)
			if a.Name:lower() == b.Name:lower() then
				return a.ID < b.ID
			end
			return a.Name:lower() < b.Name:lower()
		end)
		return orderedRecords
	end

	local function view(record)
		local details = table.clone(record)
		local session = sessions[record.ID]
		details.Source, details.Settings = nil, nil
		details.Running = session ~= nil and not session.Loading
		details.Loading = session ~= nil and session.Loading
		return details
	end

	function runtime.Get(id)
		local record = records[id]
		return record and view(record)
	end

	function runtime.GetSource(id)
		local record = records[id]
		return record and record.Source
	end

	function runtime.List()
		local result = ordered()
		for index, record in ipairs(result) do
			result[index] = view(record)
		end
		return result
	end

	function runtime.SupportsPersistence()
		return type(env.readfile) == "function" and type(env.writefile) == "function"
	end

	function runtime.Parse(raw)
		if type(raw) ~= "string" or #raw == 0 or #raw > maxPackage then
			return nil, "Choose a .dexplugin package up to 2 MiB."
		end
		local ok, data = pcall(http.JSONDecode, http, raw)
		if not ok then
			return nil, "This file isn't valid .dexplugin JSON."
		end
		local package, problem = decodePackage(data)
		return package and table.freeze(package), problem
	end

	function runtime.ReadImport(value)
		local path = importPath(value)
		if not path then
			return nil, "Enter a .dexplugin path inside the workspace."
		end
		if type(env.readfile) ~= "function" then
			return nil, "Local file access is unavailable. Paste the package instead."
		end
		local ok, raw = pcall(env.readfile, path)
		if not ok then
			return nil, "Couldn't open " .. path .. "."
		end
		local package, problem = runtime.Parse(raw)
		if not package then
			return nil, problem
		end
		local result = table.clone(package)
		result.Path = path
		return table.freeze(result)
	end

	function runtime.LocalPackages()
		local result = {}
		if type(env.listfiles) ~= "function" then
			return result
		end
		local ok, paths = pcall(env.listfiles, "dex-explorer/plugins")
		if not ok or type(paths) ~= "table" then
			return result
		end
		local seen = {}
		for _, path in ipairs(paths) do
			local name = type(path) == "string" and path:match("[^/\\]+$")
			if name and not seen[name] and importPath(name) then
				seen[name] = true
				result[#result + 1] = name
			end
		end
		table.sort(result)
		return result
	end

	function runtime.ReadLink(value)
		local url = label(value, 2048)
		local host = url and url:match("^https://([%w][%w%.%-]*)/[^%s]+$")
		if not host or not host:find("[a-zA-Z]") or not host:find("%.") or url:find("[\\#]") then
			return nil, "Enter a direct HTTPS link to a .dexplugin package."
		end
		if type(env.request) ~= "function" then
			return nil, "Link import is unavailable. Open a file or paste the package instead."
		end
		local ok, response = pcall(env.request, { Url = url, Method = "GET" })
		if not ok or type(response) ~= "table" or tonumber(response.StatusCode or response.Status) ~= 200 then
			return nil, "Couldn’t download the package."
		end
		local package, problem = runtime.Parse(response.Body)
		if not package then
			return nil, problem
		end
		local result = table.clone(package)
		result.Link = url
		return table.freeze(result)
	end

	function runtime.IsInstalledPackage(package)
		local record = records[package.ID]
		if not record then
			return false
		end
		for _, key in ipairs({ "Name", "Version", "Author", "Description", "Icon", "Startup", "Source", "Path", "Link" }) do
			if record[key] ~= package[key] then
				return false
			end
		end
		if #record.Buttons ~= #package.Buttons then
			return false
		end
		for index, button in ipairs(record.Buttons) do
			local candidate = package.Buttons[index]
			if
				button.ID ~= candidate.ID
				or button.Name ~= candidate.Name
				or button.Icon ~= candidate.Icon
				or button.Tooltip ~= candidate.Tooltip
			then
				return false
			end
		end
		return true
	end

	local function persist(id, replacement)
		if stopped or writing then
			return false, "Plugins are busy. Try again."
		end
		if not runtime.SupportsPersistence() then
			return true
		end
		local entries = {}
		local function append(record)
			entries[#entries + 1] = {
				Package = encodePackage(record),
				Path = record.Path,
				Link = record.Link,
				Enabled = record.Enabled,
				Settings = record.Settings,
			}
		end
		for _, record in pairs(records) do
			if record.ID ~= id then
				append(record)
			end
		end
		if replacement then
			append(replacement)
		end
		writing = true
		local encoded, raw = pcall(http.JSONEncode, http, { Schema = 1, Installed = entries })
		local fits = encoded and #raw <= maxStore
		local saved = fits and pcall(env.writefile, storePath, raw)
		writing = false
		if not saved then
			return false, if fits then "Couldn't save plugins to the workspace." else "The plugin store exceeds 12 MiB."
		end
		return true
	end

	local function notify(id)
		if not stopped then
			runtime.Changed:Fire(id)
		end
	end

	local function cleanup(session)
		for index = #session.Cleanup, 1, -1 do
			local ok, problem = xpcall(session.Cleanup[index], capturedError)
			if not ok then
				logError(session.Record, problem, "Cleanup: ")
			end
		end
		table.clear(session.Cleanup)
	end

	local function stop(id)
		local session = sessions[id]
		if session then
			sessions[id] = nil
			table.clear(actionViews)
			if
				session.Initializer
				and session.Initializer ~= coroutine.running()
				and coroutine.status(session.Initializer) == "suspended"
			then
				pcall(task.cancel, session.Initializer)
			end
			cleanup(session)
		end
	end

	local function startLater(record)
		task.defer(function()
			startPlugin(record)
		end)
	end

	function runtime.Start()
		if started or stopped then
			return
		end
		started = true
		if not runtime.SupportsPersistence() then
			return
		end
		local read, raw = pcall(env.readfile, storePath)
		if not read or type(raw) ~= "string" or #raw > maxStore then
			return
		end
		local decoded, store = pcall(http.JSONDecode, http, raw)
		if not decoded or type(store) ~= "table" or store.Schema ~= 1 or type(store.Installed) ~= "table" then
			return
		end
		for index, entry in ipairs(store.Installed) do
			if index > maxPlugins then
				break
			end
			local package = type(entry) == "table" and decodePackage(entry.Package)
			if package and not records[package.ID] then
				local enabled = entry.Enabled == true
				package.Enabled = enabled
				package.Path = importPath(entry.Path)
				package.Link = label(entry.Link, 2048)
				package.Settings = if type(entry.Settings) == "table" then entry.Settings else {}
				records[package.ID] = package
				if enabled and package.Startup then
					startLater(package)
				end
			end
		end
		notify()
	end

	function runtime.Install(package, replace)
		runtime.Start()
		if type(package) ~= "table" or type(package.Buttons) ~= "table" then
			return false, "Review a valid package first."
		end
		local record, problem = decodePackage(encodePackage(package))
		if not record then
			return false, problem
		end
		local id = record.ID
		local previous = records[id]
		if previous and not replace then
			return false, "A plugin with this ID is already installed."
		end
		if not previous and #ordered() >= maxPlugins then
			return false, "Remove a plugin before installing another."
		end
		record.Enabled = false
		record.Path = importPath(package.Path)
		record.Link = label(package.Link, 2048)
		record.Settings = previous and previous.Settings or {}
		local saved, message = persist(id, record)
		if not saved then
			return false, message
		end
		records[id] = record
		stop(id)
		notify(id)
		return true
	end

	local function createContext(record, session)
		local id = record.ID
		local plugin = { ID = id, Name = record.Name, Apps = Apps, Main = Main, Lib = Lib, Settings = Settings }
		local function current()
			return not stopped and sessions[id] == session
		end
		local function outputMessage(level, ...)
			if not current() then
				return
			end
			local values = {}
			for index = 1, math.min(select("#", ...), 30) do
				values[index] = displayText(select(index, ...), 2000)
			end
			emit(record, level, displayText(table.concat(values, "\t"), 2000))
		end
		function plugin:Log(...)
			outputMessage("Info", ...)
		end
		function plugin:Warn(...)
			outputMessage("Warning", ...)
		end
		function plugin:Track(resource)
			local kind = typeof(resource)
			local dispose
			if kind == "function" then
				dispose = resource
			elseif kind == "Instance" then
				dispose = function()
					resource:Destroy()
				end
			elseif kind == "RBXScriptConnection" or (kind == "table" and type(resource.Disconnect) == "function") then
				dispose = function()
					resource:Disconnect()
				end
			else
				error("Track expects a cleanup function, Instance, or connection.", 2)
			end
			if current() then
				table.insert(session.Cleanup, dispose)
			else
				pcall(dispose)
			end
			return resource
		end
		function plugin:CreateWindow(title, width, height)
			assert(current(), "This plugin is no longer running.")
			local window = Lib.Window.new()
			self:Track(function()
				window:Destroy()
			end)
			window:SetTitle(label(title, 100) or record.Name)
			window:Resize(width or 520, height or 340)
			return window, window.GuiElems.Content
		end
		function plugin:RegisterPropertyRow(definition, read)
			assert(current(), "This plugin is no longer running.")
			assert(type(definition) == "table" and validId(definition.ID), "A property row needs a lowercase ID.")
			local name = label(definition.Name, 100)
			assert(name and type(read) == "function", "A property row needs a name and a read callback.")
			local remove, refresh = Apps.Properties.RegisterPluginRow(id, definition.ID, name, read)
			self:Track(remove)
			local function unregister()
				if not current() then return end
				local index = table.find(session.Cleanup, remove)
				if index then
					table.remove(session.Cleanup, index)
					remove()
				end
			end
			return unregister, function()
				if current() and table.find(session.Cleanup, remove) then refresh() end
			end
		end
		function plugin:RegisterButton(definition, callback)
			assert(current(), "This plugin is no longer running.")
			assert(type(callback) == "function", "A button callback is required.")
			local button
			if type(definition) == "string" then
				button = session.Buttons[definition]
			else
				assert(type(definition) == "table", "Expected a button ID or definition.")
				local details =
					buttonDefinition(definition.ID, definition.Name, definition.Icon or record.Icon, definition.Tooltip)
				assert(details, "A button needs a lowercase ID and a name.")
				button = session.Buttons[details.ID]
				if not button then
					assert(#session.Order < maxButtons, "A plugin can register up to 24 buttons.")
					button = { Active = false }
					session.Buttons[details.ID] = button
					table.insert(session.Order, details.ID)
				end
				button.Details = details
			end
			assert(button, "Button is missing from the plugin manifest.")
			button.Callback = callback
			if not session.Loading then
				notify(id)
			end
		end
		function plugin:RegisterAction(definition, callback)
			assert(current(), "This plugin is no longer running.")
			assert(type(definition) == "table" and validId(definition.ID), "An action needs a lowercase ID.")
			local surface = definition.Surface
			local name = label(definition.Name, 100)
			assert(name and surfaces[surface], "An action needs a name and the Explorer, Editor, or Global surface.")
			assert(type(callback) == "function", "An action callback is required.")
			assert(definition.When == nil or type(definition.When) == "function", "When must be a function.")
			local shortcut, keybind, shortcutIssue
			if definition.Shortcut ~= nil then
				shortcut = label(definition.Shortcut, 64)
				if shortcut then
					keybind, shortcutIssue = Apps.PluginActions.ParseShortcut(shortcut)
				end
				assert(keybind, shortcutIssue or "Use a shortcut such as Ctrl+Alt+M or Alt+Shift+F8.")
			end
			assert(surface ~= "Global" or keybind, "A Global action needs a shortcut.")
			local actionId = definition.ID
			if keybind then
				for otherId, otherSession in pairs(sessions) do
					for otherActionId, other in pairs(otherSession.Actions) do
						local details = other.Public
						if
							(otherId ~= id or otherActionId ~= actionId)
							and details.Keybind
							and details.Keybind.Token == keybind.Token
							and (surface == details.Surface or surface == "Global" or details.Surface == "Global")
						then
							error(keybind.Token .. " is already assigned to " .. details.Name .. ".", 2)
						end
					end
				end
			end
			if not session.Actions[actionId] then
				assert(#session.ActionOrder < maxActions, "A plugin can register up to 40 actions.")
				table.insert(session.ActionOrder, actionId)
			end
			local action = {
				Public = table.freeze({
					PluginID = id,
					ID = actionId,
					Name = name,
					Surface = surface,
					Shortcut = keybind and keybind.Token,
					Keybind = keybind,
					Tooltip = label(definition.Tooltip, 256),
				}),
				Callback = callback,
				When = definition.When,
			}
			session.Actions[actionId] = action
			table.clear(actionViews)
			return function()
				if session.Actions[actionId] == action then
					session.Actions[actionId] = nil
					table.remove(session.ActionOrder, assert(table.find(session.ActionOrder, actionId)))
					table.clear(actionViews)
				end
			end
		end
		function plugin:SetButtonActive(buttonId, active)
			local button = current() and session.Buttons[buttonId]
			if button and button.Active ~= (active == true) then
				button.Active = active == true
				if not session.Loading then
					notify(id)
				end
			end
		end
		function plugin:GetSetting(key, fallback)
			local value = current() and records[id].Settings[key]
			if not current() or value == nil then
				return fallback
			end
			if type(value) == "table" then
				return http:JSONDecode(http:JSONEncode(value))
			end
			return value
		end
		function plugin:SetSetting(key, value)
			assert(current(), "This plugin is no longer running.")
			assert(type(key) == "string" and #key > 0 and #key <= 100, "Expected a setting name up to 100 bytes.")
			local active = records[id]
			local settings = table.clone(active.Settings)
			settings[key] = value
			local ok, data = pcall(http.JSONEncode, http, settings)
			if not ok or #data > maxSettings then
				return false, "Plugin settings must be JSON values under 64 KiB."
			end
			local replacement = table.clone(active)
			replacement.Settings = http:JSONDecode(data)
			local saved, problem = persist(id, replacement)
			if saved and current() and records[id] == active then
				active.Settings = replacement.Settings
			end
			return saved, problem
		end
		return table.freeze(plugin)
	end

	startPlugin = function(record)
		local id = record.ID
		if stopped or records[id] ~= record or not record.Enabled then
			return nil, "This plugin is disabled."
		end
		local previous = sessions[id]
		if previous then
			if previous.Loading then
				return nil, "This plugin is loading."
			end
			return previous
		end
		if record.Error then
			return nil, record.Error
		end
		if type(env.loadstring) ~= "function" then
			record.Error = "Luau execution is unavailable in this session."
			emit(record, "Error", record.Error)
			notify(id)
			return nil, record.Error
		end
		local session = {
			Record = record,
			Loading = true,
			Initializer = coroutine.running(),
			Cleanup = {},
			Buttons = {},
			Order = {},
			Actions = {},
			ActionOrder = {},
		}
		for _, button in ipairs(record.Buttons) do
			session.Buttons[button.ID] = { Details = button, Active = false }
			table.insert(session.Order, button.ID)
		end
		sessions[id] = session
		notify(id)
		if stopped or sessions[id] ~= session or records[id] ~= record or not record.Enabled then
			return nil, "This plugin was stopped."
		end
		local plugin = createContext(record, session)
		local ok, result = xpcall(function()
			local chunk, problem = env.loadstring(record.Source, "@DexExplorer/Plugins/" .. id)
			assert(type(chunk) == "function", problem or "Couldn't compile plugin.")
			local globals = getfenv(chunk)
			local nativePrint, nativeWarn = globals.print, globals.warn
			setfenv(
				chunk,
				setmetatable({
					print = function(...)
						plugin:Log(...)
						if nativePrint then
							nativePrint(...)
						end
					end,
					warn = function(...)
						plugin:Warn(...)
						if nativeWarn then
							nativeWarn(...)
						end
					end,
				}, { __index = globals, __newindex = globals })
			)
			return chunk(plugin)
		end, capturedError)
		session.Initializer = nil
		if ok and type(result) == "function" then
			plugin:Track(result)
		end
		if sessions[id] ~= session then
			return nil, "This plugin was stopped."
		end
		if not ok then
			record.Error = displayText(result.Message, 500)
			logError(record, result)
			stop(id)
			notify(id)
			return nil, record.Error
		end
		session.Loading = false
		table.clear(actionViews)
		notify(id)
		return session
	end

	function runtime.SetEnabled(id, enabled)
		local record = records[id]
		if not record then
			return false, "Plugin is no longer installed."
		end
		enabled = enabled == true
		if record.Enabled == enabled then
			return true
		end
		local replacement = table.clone(record)
		replacement.Enabled = enabled
		local saved, problem = persist(id, replacement)
		if not saved then
			return false, problem
		end
		record.Enabled, record.Error = enabled, nil
		if enabled then
			if record.Startup then
				startLater(record)
			end
		else
			stop(id)
		end
		notify(id)
		return true
	end

	function runtime.Remove(id)
		if not records[id] then
			return false, "Plugin is no longer installed."
		end
		local saved, problem = persist(id)
		if not saved then
			return false, problem
		end
		records[id] = nil
		stop(id)
		output[id] = nil
		runtime.OutputChanged:Fire(id)
		notify(id)
		return true
	end

	function runtime.Reload(id)
		local record = records[id]
		if not record or not record.Enabled then
			return false, "Enable the plugin first."
		end
		record.Error = nil
		stop(id)
		local session, problem = startPlugin(record)
		return session ~= nil, problem
	end

	function runtime.GetButtons()
		local result = {}
		local function append(record, definition, state)
			local entry = table.clone(definition)
			entry.PluginID = record.ID
			entry.Enabled = record.Enabled
			entry.Failed = record.Error ~= nil
			entry.Active = state ~= nil and state.Active
			table.insert(result, entry)
		end
		for _, record in ipairs(ordered()) do
			local session = sessions[record.ID]
			if not record.Enabled then
				append(record, { ID = record.Buttons[1].ID, Name = record.Name, Icon = record.Icon }, nil)
			elseif session and not session.Loading then
				for _, id in ipairs(session.Order) do
					local button = session.Buttons[id]
					append(record, button.Details, button)
				end
			else
				for _, definition in ipairs(record.Buttons) do
					append(record, definition, nil)
				end
			end
		end
		return result
	end

	function runtime.Activate(id, buttonId)
		local record = records[id]
		if not record or not record.Enabled then
			return false, "Enable the plugin first."
		end
		local session, problem = startPlugin(record)
		if not session then
			return false, problem
		end
		local button = session.Buttons[buttonId]
		if not button or not button.Callback then
			local message = "The plugin didn't bind button " .. buttonId .. "."
			emit(record, "Error", message)
			return false, message
		end
		if button.Busy then
			return false, "This plugin button is busy."
		end
		button.Busy = true
		local ok, result = xpcall(button.Callback, capturedError)
		button.Busy = false
		if sessions[id] == session then
			record.Error = if ok then nil else displayText(result.Message, 500)
			if not ok then
				logError(record, result, "Button " .. buttonId .. ": ")
			end
			notify(id)
		end
		return ok, if ok then nil else displayText(result.Message, 500)
	end

	function runtime.GetActions(surface)
		local cached = actionViews[surface]
		if cached then
			return cached
		end
		local result = {}
		for _, record in ipairs(ordered()) do
			local session = sessions[record.ID]
			if session and not session.Loading then
				for _, id in ipairs(session.ActionOrder) do
					local details = session.Actions[id].Public
					if details.Surface == surface then
						result[#result + 1] = details
					end
				end
			end
		end
		result = table.freeze(result)
		if surfaces[surface] then
			actionViews[surface] = result
		end
		return result
	end

	local function actionAvailable(session, action, context)
		if
			not action
			or session.Loading
			or action.Busy
			or not session.Record.Enabled
			or (context and context.Surface and context.Surface ~= action.Public.Surface)
		then
			return false
		end
		if not action.When then
			return true
		end
		local thread = coroutine.create(function()
			return xpcall(action.When, capturedError, context)
		end)
		local resumed, ok, result = coroutine.resume(thread)
		if coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
			if not action.PredicateError then
				action.PredicateError = true
				emit(session.Record, "Error", "Action " .. action.Public.ID .. ": When must return without yielding.")
			end
			return false
		end
		if resumed and ok then
			action.PredicateError = nil
			return result == true
		end
		if not action.PredicateError then
			action.PredicateError = true
			logError(session.Record, resumed and result or capturedError(ok), "Action " .. action.Public.ID .. ": ")
		end
		return false
	end

	function runtime.IsActionAvailable(id, actionId, context)
		local session = sessions[id]
		return not stopped and session ~= nil and actionAvailable(session, session.Actions[actionId], context)
	end

	function runtime.InvokeAction(id, actionId, context, expected)
		local session = sessions[id]
		local action = session and session.Actions[actionId]
		if
			stopped
			or not session
			or (expected and (not action or action.Public ~= expected))
			or not actionAvailable(session, action, context)
			or sessions[id] ~= session
			or session.Actions[actionId] ~= action
		then
			return false, "This plugin action is unavailable."
		end
		action.Busy = true
		local ok, result = xpcall(action.Callback, capturedError, context)
		action.Busy = false
		if not ok then
			if sessions[id] == session then
				logError(session.Record, result, "Action " .. actionId .. ": ")
			end
			return false, displayText(result.Message, 500)
		end
		return true, result
	end

	Main.AddCleanup(function()
		stopped = true
		for id in pairs(sessions) do
			stop(id)
		end
		table.clear(output)
	end)

	return runtime
end

return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
