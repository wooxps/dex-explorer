do
	local gui, deferred, written
	local obj = Instance.new("Part")
	obj.Name = "Preview"
	local node = {Obj=obj}
	local show, defer, wait = Lib.ShowGui, task.defer, task.wait
	local getNodes, export = Apps.Explorer.GetNodes, Apps.GltfExporter.Export
	local read, write, list, folder = deps.env.readfile, deps.env.writefile, deps.env.listfiles, deps.env.isfolder
	Lib.ShowGui = function(value) gui = value end
	task.defer = function(callback) deferred = callback end
	task.wait = function() end
	Apps.Explorer.GetNodes = function() return {[obj]=node} end
	deps.env.readfile = function() return "" end
	deps.env.writefile = function(path, data) written = {path,data} end
	deps.env.listfiles = function(path) return if path=="." then {"models","skip.png"} else {"models/a.rbxmx"} end
	deps.env.isfolder = function(path) return path=="models" end
	local function find(key)
		for _, child in ipairs(gui:GetDescendants()) do
			if child.Name == key or child.Text == key then return child end
		end
		error("Missing dialog control " .. key)
	end
	local function click(key) find(key).Activated:Fire() end
	local generated = 0
	local config = function() Apps.ExplorerFileActions.Open("EXPORT_GLTF",{node}) end
	config()
	assert(find("DexIcon").Image == Main.GetStudioAsset("branding/dex/caption-12-v1"))
	assert(find("DexIcon").Size.X.Offset == 12 and find("WindowBorder").Thickness == 1)
	local checked = find("Checked")
	assert(checked.Size.X.Offset == 19 and checked.ImageRectSize.X == 19)
	local closeButton, closeIcon = find("Close"), find("CloseIcon")
	local hover = closeButton:GetChildren()[1]
	assert(not hover.Visible and not closeButton.AutoButtonColor)
	assert(hover.Size.Y.Offset == closeButton.Size.Y.Offset-1)
	local cancel = find("Cancel")
	cancel.MouseEnter:Fire()
	assert(math.round(cancel.BackgroundColor3.R*255)==71 and math.round(cancel.BackgroundColor3.G*255)==74 and math.round(cancel.BackgroundColor3.B*255)==86)
	cancel.MouseLeave:Fire()
	assert(math.round(cancel.BackgroundColor3.R*255)==59)
	assert(find("Shadow").BackgroundTransparency < 1)
	closeButton.MouseEnter:Fire()
	assert(hover.Visible and closeIcon.ImageColor3.R == 1)
	closeButton.MouseLeave:Fire()
	assert(not hover.Visible and closeIcon.ImageColor3.R < .2)
	assert(find("Processing...").Interactable == false)
	click("Cancel")
	deferred()
	assert(generated == 0 and not written)
	local fail = false
	Apps.GltfExporter.Export = function(_, options, cancelled)
		generated += 1
		if fail then error("Asset unavailable",0) end
		if generated == 1 then
			assert(options.Textures and not options.Cages)
			click("Textures")
			click("Cages")
			assert(cancelled() and options.Textures and not options.Cages)
			return "stale"
		end
		assert(not cancelled())
		return "glTF fixture " .. generated
	end
	config()
	deferred()
	assert(generated == 2 and find("Export").Interactable and not written)
	local primaryPosition, primarySize, cancelPosition = find("Export").Position, find("Export").Size, find("Cancel").Position
	click("Skinning")
	assert(find("Processing...").Position == primaryPosition and find("Processing...").Size == primarySize)
	assert(find("Cancel").Position == cancelPosition)
	assert(find("Processing...").Interactable == false)
	fail = true
	deferred()
	assert(find("Asset unavailable") and find("Retry").Interactable)
	fail = false
	click("Retry")
	deferred()
	local prepared = generated
	click("Export")
	assert(generated == prepared and find("FileInput").Text == "Preview.gltf" and not written)
	find("FileInput").Text = "Renamed.gltf"
	click("Save")
	deferred()
	assert(written[1]=="Renamed.gltf" and written[2]=="glTF fixture " .. prepared)
	assert(find("Export Complete") and find("Renamed.gltf") and not find("Cancel").Visible)
	click("Done")
	Apps.ExplorerFileActions.Open("LOAD_CSV",{node})
	local input = find("FileInput")
	input.Text = "locales/test.csv"
	click("Paste CSV")
	assert(input.MultiLine and input.Text=="")
	input.Text = "Source,en\nHello,Hi"
	click("From file")
	assert(input.Text=="locales/test.csv")
	click("Paste CSV")
	assert(input.Text=="Source,en\nHello,Hi")
	click("Cancel")
	Apps.ExplorerFileActions.Open("INSERT_FILE",{node})
	assert(not pcall(find,"Browse..."))
	assert(find("FileInput").PlaceholderText=="model.rbxm")
	click("Cancel")
	local serialization = service.SerializationService
	service.SerializationService = {SerializeInstancesAsync=function(_,roots)
		assert(#roots==1 and roots[1]==obj)
		return buffer.fromstring("<roblox!binary")
	end}
	Apps.ExplorerFileActions.Open("SAVE_MODEL",{node})
	find("FileInput").Text = "Named.rbxmx"
	click("Save")
	deferred()
	assert(written[1]=="Named.rbxm" and written[2]=="<roblox!binary")
	service.SerializationService = serialization
	Lib.SaveAsPrompt("Original.lua","source","lua")
	local fileName = find("NameBox")
	fileName.Text = "folder.v1/Renamed.txt"
	fileName.FocusLost:Fire(true)
	assert(written[1]=="folder.v1/Renamed.lua" and written[2]=="source")
	local called
	Lib.SaveAsPrompt("",function(path) called=path end)
	assert(not find("Save").Interactable)
	fileName = find("NameBox")
	fileName.Text = "My model.rbxm"
	fileName:GetPropertyChangedSignal("Text"):Fire()
	click("Save")
	assert(called=="My model.rbxm")
	Apps.Explorer.GetNodes, Apps.GltfExporter.Export = getNodes, export
	Lib.ShowGui, task.defer, task.wait = show, defer, wait
	deps.env.readfile, deps.env.writefile, deps.env.listfiles, deps.env.isfolder = read, write, list, folder
	obj:Destroy()
	print("PASS: glTF configuration, cancellable processing, deferred naming, CSV input tabs and model browsing")
end
