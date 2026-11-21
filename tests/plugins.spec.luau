--!strict

local stored, written, failWrite
local files, encoded = {}, {}
local function encode(_, value)
	table.insert(encoded, value)
	return "json-" .. #encoded
end
local function decode(_, source)
	return assert(encoded[tonumber(source:match("^json%-(%d+)$")) or 0])
end
local http = { JSONEncode = encode, JSONDecode = decode }
local ran, cleaned, clicked = 0, 0, 0
local activeRows = 0
Apps.Properties.RegisterPluginRow = function(owner, id, name, read)
	assert(owner and id == "count" and name == "Count" and read({1,2}) == "2")
	activeRows += 1
	return function() activeRows -= 1 end, function() end
end
local fixture = { schema = 1, id = "example.test", name = "Test Plugin", version = "1.0", source = "fixture" }
local packageText = encode(http, fixture)
local listed = { "dex-explorer/plugins/installed.json", "dex-explorer/plugins/example.dexplugin" }
local scans = 0
local env = {
	listfiles = function()
		scans += 1
		return listed
	end,
	readfile = function(path)
		return assert(files[path])
	end,
	writefile = function(path, content)
		assert(not failWrite)
		written = path
		files[path] = content
		stored = content
	end,
	request = function(args)
		assert(args.Url == "https://example.com/my.dexplugin" and args.Method == "GET")
		return { StatusCode = 200, Body = packageText }
	end,
	loadstring = function(source)
		assert(source == "fixture")
		return function(plugin)
			ran += 1
			plugin:RegisterPropertyRow({ID="count", Name="Count"}, function(selection)
				return tostring(#selection)
			end)
			plugin:RegisterButton("open", function()
				clicked += 1
				plugin:SetButtonActive("open", true)
				assert(plugin:SetSetting("checked", false))
				assert(plugin:GetSetting("checked", true) == false)
			end)
			plugin:Track(function()
				cleaned += 1
			end)
		end
	end,
}
local pluginDeps = {
	Apps = Apps,
	Main = Main,
	Lib = Lib,
	Settings = Settings,
	createSimple = createSimple,
	service = { HttpService = http, UserInputService = service.UserInputService },
	env = env,
}
pluginRuntimeControl.InitDeps(pluginDeps)
local runtime = pluginRuntimeControl.Main()
Apps.PluginRuntime = runtime
pluginActionsControl.InitDeps(pluginDeps)
Apps.PluginActions = pluginActionsControl.Main()
pluginToolbarControl.InitDeps(pluginDeps)
Apps.PluginToolbar = pluginToolbarControl.Main()
pluginUIControl.InitDeps(pluginDeps)
local oldBridgeUI = Apps.BridgeUI
Apps.BridgeUI = pluginUIControl.Main()
pluginManagerControl.InitDeps(pluginDeps)
Apps.PluginManager = pluginManagerControl.Main()

local function verifyPlugins()
	local oldNew = Lib.Window.new
	Lib.Window.new = function()
		local window = oldNew()
		function window:Resize(w, h)
			self.GuiElems.Main.Size = UDim2.fromOffset(w, h)
		end
		function window:Show()
			self.Closed = false
		end
		function window:Close()
			self.Closed = true
		end
		function window:Destroy()
			self.Gui:Destroy()
		end
		return window
	end
	local toolbar = Main.AppsFrame.Plugins
	assert(toolbar.Title.Text == "Plugins")
	local add = toolbar.AddPlugin
	assert(add.NativeIcon.Image == "mockasset://native/plugins/add")
	files["dex-explorer/plugins/example.dexplugin"] = packageText
	assert(not runtime.ReadImport("../example.dexplugin"))
	assert(not runtime.ReadLink("http://example.com/my.dexplugin"))
	local linked = assert(runtime.ReadLink("https://example.com/my.dexplugin"))
	assert(linked.Link and ran == 0)
	add.MouseButton1Click:Fire()
	local manager = Apps.PluginManager.Window
	local content = manager.GuiElems.Content
	local footer = content.Actions
	local makeContext = Apps.ContextMenu.new
	local importMenu
	Apps.ContextMenu.new = function()
		importMenu = makeContext()
		return importMenu
	end
	local function chooseSource(text)
		content.Body.PluginPage.FileToolbar.ImportFrom.Activated:Fire()
		assert(importMenu.Shown and importMenu.Theme.Compact)
		for _, item in ipairs(importMenu.Items) do
			if item.Text == text then
				item.OnClick()
				assert(not importMenu.Shown, "switching forms closes the menu")
				return
			end
		end
		error("Missing import source: " .. text)
	end
	assert(content.Body.PluginPage.FileToolbar.ImportFrom and footer.Buttons.Review.Selectable == false)
	assert(content.Body.PluginPage.FileHeading.NameLabel.Text == "Name")
	assert(
		content.Body.PluginPage.LocalPackages.ClassName == "ScrollingFrame"
			and content.Body.PluginPage.LocalPackages.Size.Y.Scale == 1
	)
	footer.FilesInput.Text = "example.dexplugin"
	chooseSource("Paste Plugin…")
	local paste = content.Body.PluginPage.ImportForm.PasteInput
	assert(paste.MultiLine and paste.TextWrapped and paste.Font == Lib.StudioFont and paste.TextSize == 14)
	assert(not content.Body.PluginPage:FindFirstChild("FileToolbar") and footer.Back, "paste has its own form")
	paste.Text = "pasted draft"
	footer.Back.Activated:Fire()
	chooseSource("Paste Plugin…")
	assert(content.Body.PluginPage.ImportForm.PasteInput.Text == "pasted draft")
	footer.Back.Activated:Fire()
	chooseSource("From Link…")
	content.Body.PluginPage.ImportForm.LinkInput.Text = "https://example.com/my.dexplugin"
	content.Body.PluginPage.ImportForm.LinkInput:GetPropertyChangedSignal("Text"):Fire()
	footer.Review.Activated:Fire()
	assert(footer.Install and ran == 0)
	footer.Back.Activated:Fire()
	assert(content.Body.PluginPage.ImportForm.LinkInput.Text == "https://example.com/my.dexplugin")
	footer.Back.Activated:Fire()
	Apps.ContextMenu.new = makeContext
	assert(footer.FilesInput.Text == "example.dexplugin")
	local fileInput = footer.FilesInput
	fileInput.Text = ""
	fileInput:GetPropertyChangedSignal("Text"):Fire()
	local entries = content.Body.PluginPage.LocalPackages.Entries
	entries.File1.Package.Activated:Fire()
	assert(fileInput.Text == "example.dexplugin" and not footer:FindFirstChild("Install"))
	fileInput:GetPropertyChangedSignal("Text"):Fire()
	assert(entries.File1.Package.BackgroundColor3 == Settings.Theme.Focus)
	local original = entries.File1
	flushTasks()
	assert(entries.File1 == original, "unchanged directory retains file rows")
	listed = { "dex-explorer/plugins/example.dexplugin", "dex-explorer/plugins/new.dexplugin" }
	flushTasks()
	assert(entries.File2.Package.Text == "new.dexplugin" and fileInput.Text == "example.dexplugin")
	assert(entries.File1.Package.BackgroundColor3 == Settings.Theme.Focus)
	listed = { "dex-explorer/plugins/example.dexplugin", "dex-explorer/plugins/renamed.dexplugin" }
	flushTasks()
	assert(entries.File2.Package.Text == "renamed.dexplugin", "same-count rename updates the list")
	listed = { "dex-explorer/plugins/example.dexplugin" }
	flushTasks()
	assert(not entries:FindFirstChild("File2"))
	footer.Buttons.Review.Activated:Fire()
	local reviewScans = scans
	flushTasks()
	assert(scans == reviewScans, "review stops workspace polling")
	assert(content.Body.PluginPage.PluginHeader.Name == "PluginHeader" and ran == 0)
	footer.Install.Activated:Fire()
	assert(footer.Enable and footer.Cancel.Text == "Keep Disabled")
	assert(runtime.Get(fixture.id).Enabled == false and ran == 0)
	assert(written == "dex-explorer/plugins/installed.json" and stored ~= packageText)
	flushTasks()
	local button = toolbar.Buttons:FindFirstChild("example.test/open")
	assert(button and button.Icon.ImageTransparency > 0)
	button.MouseButton2Click:Fire()
	assert(Apps.PluginToolbar.IsMenuOpen())
	Apps.PluginToolbar.HideMenu()
	assert(not Apps.PluginToolbar.IsMenuOpen())
	footer.Enable.Activated:Fire()
	assert(runtime.Get(fixture.id).Enabled and ran == 0)
	flushTasks()
	button.MouseButton1Click:Fire()
	assert(ran == 1 and clicked == 1 and runtime.GetButtons()[1].Active)
	local restored = pluginRuntimeControl.Main()
	restored.Start()
	assert(restored.Get(fixture.id).Enabled and not restored.Get(fixture.id).Running and ran == 1)
	failWrite = true
	assert(not runtime.SetEnabled(fixture.id, false) and runtime.Get(fixture.id).Enabled and cleaned == 0)
	failWrite = false
	assert(runtime.Reload(fixture.id) and ran == 2 and cleaned == 1)
	assert(activeRows == 1)
	assert(runtime.SetEnabled(fixture.id, false) and cleaned == 2)
	assert(activeRows == 0)
	assert(runtime.IsInstalledPackage(assert(runtime.ReadImport("example.dexplugin"))))
	assert(runtime.Install(linked, true) and runtime.Get(fixture.id).Link and not runtime.Get(fixture.id).Enabled)
	assert(runtime.Remove(fixture.id))
	flushTasks()
	assert(not toolbar.Buttons:FindFirstChild("example.test/open"), "uninstall removes the toolbar button")
	local startup = table.clone(fixture)
	startup.id, startup.startup = "example.startup", true
	assert(runtime.Install(assert(runtime.Parse(encode(http, startup)))))
	flushTasks()
	assert(ran == 2, "startup packages also wait for explicit enable")
	assert(runtime.SetEnabled(startup.id, true))
	flushTasks()
	flushTasks()
	assert(runtime.Get(startup.id).Running and ran == 3)
	assert(runtime.Remove(startup.id) and cleaned == 3)
	flushTasks()

	assert(runtime.Install(assert(runtime.Parse(packageText))))
	assert(runtime.SetEnabled(fixture.id, true))
	local disabledDuringStart = false
	local listener = runtime.Changed:Connect(function(id)
		local info = id == fixture.id and runtime.Get(id)
		if info and info.Loading then
			disabledDuringStart = runtime.SetEnabled(id, false)
		end
	end)
	assert(not runtime.Activate(fixture.id, "open"))
	assert(disabledDuringStart and ran == 3, "a plugin disabled by a loading listener must not execute")
	listener:Disconnect()
	assert(runtime.Remove(fixture.id))
	Lib.Window.new = oldNew
	Apps.BridgeUI = oldBridgeUI
	print(
		"PASS: main-menu plugin import/review/enable, link validation, stored snapshots, click activation, cleanup, failed writes and uninstall"
	)
end

local function verifyPluginActionsAndOutput()
	local source = [[local plugin = ...
print("ready", plugin.ID)
plugin:Warn("setup warning")
plugin:RegisterButton("open", function()
	error("broken button")
end)
local remove = plugin:RegisterAction({ ID = "inspect", Name = "Inspect", Surface = "Explorer", When = function(context)
	return context.Target == "example"
end }, function(context)
	plugin:Log(context.Target)
	return context.Target
end)
plugin:RegisterAction({ ID = "broken", Name = "Broken", Surface = "Editor" }, function()
	error("broken action")
end)
plugin:RegisterAction({ ID = "remove", Name = "Remove", Surface = "Global", Shortcut = "Ctrl+Alt+M" }, function()
	remove()
end)
plugin:RegisterAction({ ID = "flood", Name = "Flood", Surface = "Global", Shortcut = "Ctrl+Alt+Q" }, function()
	for index = 1, 125 do
		plugin:Log(index)
	end
end)
assert(not pcall(function()
	plugin:RegisterAction({ ID = "duplicate", Name = "Duplicate", Surface = "Editor", Shortcut = "alt+ctrl+m" }, function() end)
end))
]]
	local originalLoad = env.loadstring
	env.loadstring = function(code, name)
		local fn, problem = loadstring(code, name)
		if fn then
			setfenv(fn, setmetatable({ print = function() end }, { __index = getfenv() }))
		end
		return fn, problem
	end
	local id = "test.actions"
	local package =
		assert(runtime.Parse(encode(http, { schema = 1, id = id, name = "Actions", version = "1", source = source })))
	assert(runtime.Install(package) and runtime.SetEnabled(id, true))
	assert(#runtime.GetActions("Explorer") == 0, "actions stay inactive until the plugin starts")
	local updates = 0
	local connection = runtime.OutputChanged:Connect(function(pluginId)
		if pluginId == id then
			updates += 1
		end
	end)
	assert(not runtime.Activate(id, "open"))
	local lines = runtime.GetOutput(id)
	assert(#lines == 3 and lines[1].Level == "Info" and lines[1].Message == "ready\ttest.actions")
	assert(lines[2].Level == "Warning" and lines[3].Level == "Error" and lines[3].Line == 5)
	assert(lines[3].Source == source and lines[3].Traceback:find("DexExplorer/Plugins/test.actions", 1, true))
	local action = assert(runtime.GetActions("Explorer")[1])
	local context = { Surface = "Explorer", Target = "example" }
	assert(runtime.IsActionAvailable(id, action.ID, context))
	assert(not runtime.InvokeAction(id, action.ID, { Surface = "Editor", Target = "example" }))
	assert(not runtime.InvokeAction(id, action.ID, { Surface = "Explorer", Target = "different" }))
	local ok, result = runtime.InvokeAction(id, action.ID, context, action)
	assert(ok and result == "example")
	assert(not runtime.InvokeAction(id, "broken", { Surface = "Editor" }))
	local errorRow = runtime.GetOutput(id)[5]
	assert(errorRow.Level == "Error" and errorRow.Line == 14 and errorRow.Sequence > lines[3].Sequence)
	assert(runtime.InvokeAction(id, "remove", { Surface = "Global" }) and #runtime.GetActions("Explorer") == 0)
	assert(runtime.Reload(id))
	assert(
		not runtime.InvokeAction(id, action.ID, context, action),
		"stale action records cannot invoke a reloaded action"
	)
	assert(runtime.SetEnabled(id, false) and #runtime.GetActions("Editor") == 0 and #runtime.GetOutput(id) == 7)
	assert(runtime.ClearOutput(id) and #runtime.GetOutput(id) == 0 and updates == 8)
	assert(runtime.SetEnabled(id, true) and runtime.Reload(id))
	assert(runtime.InvokeAction(id, "flood", { Surface = "Global" }))
	local bounded = runtime.GetOutput(id)
	assert(#bounded == 120 and bounded[1].Message == "6" and bounded[120].Message == "125")
	assert(runtime.Remove(id))
	assert(#runtime.GetOutput(id) == 0 and #runtime.GetActions("Global") == 0)
	connection:Disconnect()
	env.loadstring = originalLoad
	print("PASS: plugin action registration, guards, cleanup, captured print, warnings, errors, and source lines")
end
