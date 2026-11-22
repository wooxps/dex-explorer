--!strict

local Apps, Lib, env, service
local Actions = {}

local function pathFor(input, extensions, addExtension)
	local path = input:match("^%s*(.-)%s*$"):gsub("\\", "/")
	assert(path ~= "" and not path:match("^/") and not path:find('[:%c<>|?*"]') and not path:match("/$"), "Enter a relative workspace path")
	for segment in (path .. "/"):gmatch("(.-)/") do
		assert(segment ~= "" and not segment:match("[%. ]$"), "Invalid workspace path")
	end
	local extension = path:lower():match("([^/%.]+)$")
	if addExtension and not path:match("[^/]+%.[^/]+$") then
		return path .. "." .. addExtension
	end
	assert(path:match("%.[^/]+$") and table.find(extensions, extension), "Expected ." .. table.concat(extensions, " or ."))
	return path
end

local function readModel(path)
	local reason
	if env.readfile and (not env.getcustomasset or path:lower():sub(-5) == ".rbxm") then
		local bytes = env.readfile(path)
		local ok, result = pcall(function()
			return service.SerializationService:DeserializeInstancesAsync(buffer.fromstring(bytes))
		end)
		if ok then return result end
		reason = result
	end
	assert(env.getcustomasset, reason or "This runtime cannot open XML model files")
	return (oldgame or game):GetObjects(env.getcustomasset(path))
end

local function checkTargets(targets)
	assert(#targets > 0, "Select a destination")
	for _, node in ipairs(targets) do
		assert(not node.Del and node.Obj and Apps.Explorer.GetNodes()[node.Obj] == node, "The selected object is no longer in Explorer")
	end
end

function Actions.Insert(input, targets)
	local path = pathFor(input, { "rbxm", "rbxmx" })
	checkTargets(targets)
	local batches = {}
	local ok, err = pcall(function()
		for _ in ipairs(targets) do
			local objects = readModel(path)
			assert(type(objects) == "table" and #objects > 0, "The file contains no objects")
			table.insert(batches, objects)
		end
		checkTargets(targets)
		Apps.History.Run("Insert from File", function()
			local selected = {}
			for i, batch in ipairs(batches) do
				for _, obj in ipairs(batch) do
					Apps.History.Set(obj, "Parent", targets[i].Obj)
					local node = Apps.Explorer.GetNodes()[obj]
					if node then table.insert(selected, node) end
				end
			end
			if #selected > 0 then
				Apps.Explorer.Selection:SetTable(selected)
				Apps.Explorer.ViewNode(selected[1])
			end
		end)
	end)
	if not ok then
		for _, batch in ipairs(batches) do
			for _, obj in ipairs(batch) do
				if not obj.Parent then obj:Destroy() end
			end
		end
		error(err, 0)
	end
end

function Actions.LoadCsv(input, targets)
	local text = input
	if not input:find("[\r\n]") and input:lower():match("%.csv%s*$") then
		assert(env.readfile, "Paste CSV text or use a runtime with workspace file access")
		text = env.readfile(pathFor(input, { "csv" }))
	end
	local entries = Apps.LocalizationCsv.Decode(text)
	checkTargets(targets)
	local obj = targets[1].Obj
	Apps.History.Change("Load from CSV", function() return obj:GetEntries() end, function(value)
		obj:SetEntries(value)
	end, entries)
end

local window, box, status, button, submit
local function prompt(title, hint, initial, verb, multiline, callback)
	if not window then
		window = Lib.Window.new()
		window:SetSize(400, 158)
		box = Lib.ViewportTextBox.new()
		box.Position = UDim2.fromOffset(8, 8)
		box.Size = UDim2.new(1, -16, 0, 48)
		window:Add(box)
		status = Lib.Label.new()
		status.Position = UDim2.fromOffset(8, 60)
		status.Size = UDim2.new(1, -16, 0, 42)
		status.TextWrapped = true
		window:Add(status)
		button = Lib.Button.new()
		button.Position = UDim2.new(1, -92, 1, -28)
		button.Size = UDim2.fromOffset(84, 22)
		button.OnClick:Connect(function() submit() end)
		window:Add(button)
	end
	window:SetTitle(title)
	box.TextBox.MultiLine = multiline
	box.TextBox.ClearTextOnFocus = false
	box.TextBox.PlaceholderText = hint
	box.TextBox.Text = initial
	status.Text = ""
	button.Text = verb
	local busy = false
	local function run()
		if busy then return end
		busy = true
		status.Text = verb .. "..."
		local ok, err = pcall(callback, box.TextBox.Text)
		busy = false
		if submit ~= run then return end
		if not ok then
			status.Text = tostring(err):gsub("^.-:%d+: ", "")
		elseif err then
			status.Text = err
			button.Text = "Done"
			submit = function() window:Close() end
		else
			window:Close()
		end
	end
	submit = run
	window:Show()
	box.TextBox:CaptureFocus()
end

function Actions.Open(action, targets)
	local first = targets[1]
	if not first then return end
	if action == "INSERT_FILE" then
		prompt("Insert from File", "Workspace path (.rbxm or .rbxmx)", "", "Insert", false, function(text)
			Actions.Insert(text, targets)
		end)
	elseif action == "LOAD_CSV" then
		prompt("Load from CSV", "Paste CSV text or enter a .csv workspace path", "", "Load", true, function(text)
			Actions.LoadCsv(text, targets)
		end)
	else
		local csv = action == "SAVE_CSV"
		local extension = csv and "csv" or "gltf"
		local name = #targets == 1 and first.Obj.Name or "Selection"
		name = name:gsub('[<>:"/\\|?*%c]', "_"):gsub("[%. ]+$", "")
		local initial = (name ~= "" and name or "Selection") .. "." .. extension
		local overwrite
		prompt(csv and "Save as CSV" or "Export as glTF", "Workspace path", initial, csv and "Save" or "Export", false, function(input)
			local path = pathFor(input, { extension }, extension)
			if env.isfile and env.isfile(path) and overwrite ~= path then
				overwrite = path
				error("File exists. Click again to replace it.", 0)
			end
			checkTargets(targets)
			local data, details
			if csv then data = Apps.LocalizationCsv.Encode(first.Obj:GetEntries()) else data, details = Apps.GltfExporter.Export(targets) end
			env.writefile(path, data)
			if details then return "Saved. " .. details end
		end)
	end
end

return {
	InitDeps = function(d) Apps, Lib, env, service = d.Apps, d.Lib, d.env, d.service end,
	InitAfterMain = function() end,
	Main = function() return Actions end,
}
