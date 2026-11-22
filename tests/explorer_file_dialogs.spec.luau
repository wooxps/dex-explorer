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
	Apps.GltfExporter.Export = function(_, options)
		assert(options.Skinning and not options.Textures and options.Attachments and options.Cages)
		generated += 1
		return "glTF fixture"
	end
	local function config()
		Apps.ExplorerFileActions.Open("EXPORT_GLTF",{node})
		click("Textures")
		click("Cages")
		click("Export")
		assert(find("Processing...").Interactable == false)
	end
	config()
	click("Cancel")
	deferred()
	assert(generated == 0 and not written)
	config()
	deferred()
	assert(generated == 1 and find("FileInput").Text == "Preview.gltf" and not written)
	find("FileInput").Text = "Renamed.gltf"
	click("Save")
	deferred()
	assert(written[1]=="Renamed.gltf" and written[2]=="glTF fixture")
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
