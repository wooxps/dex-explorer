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
	local delay, showTip = task.delay, nil
	task.delay = function(_, callback) showTip=callback end
	closeButton.MouseEnter:Fire()
	assert(not find("CloseTooltip").Visible)
	showTip()
	assert(find("CloseTooltip").Visible)
	assert(hover.Visible and closeIcon.ImageColor3.R == 1)
	closeButton.MouseLeave:Fire()
	showTip()
	assert(not find("CloseTooltip").Visible)
	task.delay = delay
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
	click("Browse...")
	click("▸  models")
	click("a.rbxmx")
	assert(find("FileInput").Text=="models/a.rbxmx")
	click("Cancel")
	Apps.Explorer.GetNodes, Apps.GltfExporter.Export = getNodes, export
	Lib.ShowGui, task.defer, task.wait = show, defer, wait
	deps.env.readfile, deps.env.writefile, deps.env.listfiles, deps.env.isfolder = read, write, list, folder
	obj:Destroy()
	print("PASS: glTF configuration, cancellable processing, deferred naming, CSV input tabs and model browsing")
end
