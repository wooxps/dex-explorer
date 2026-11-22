--!strict

local Main, Apps, Lib, env, service
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

function Actions.Insert(input, targets, cancelled)
	local path = pathFor(input, { "rbxm", "rbxmx" })
	checkTargets(targets)
	local batches = {}
	local ok, err = pcall(function()
		for _ in ipairs(targets) do
			if cancelled and cancelled() then error("Insert cancelled",0) end
			local objects = readModel(path)
			assert(type(objects) == "table" and #objects > 0, "The file contains no objects")
			table.insert(batches, objects)
		end
		if cancelled and cancelled() then error("Insert cancelled",0) end
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

function Actions.LoadCsv(input, targets, paste, cancelled)
	local text = input
	if paste == false or (paste == nil and not input:find("[\r\n]") and input:lower():match("%.csv%s*$")) then
		assert(env.readfile, "Paste CSV text or use a runtime with workspace file access")
		text = env.readfile(pathFor(input, { "csv" }))
	end
	if cancelled and cancelled() then return end
	local entries = Apps.LocalizationCsv.Decode(text)
	checkTargets(targets)
	local obj = targets[1].Obj
	Apps.History.Change("Load from CSV", function() return obj:GetEntries() end, function(value)
		obj:SetEntries(value)
	end, entries)
end

local rgb = Color3.fromRGB

local function configuration(targets, onReady)
	local d = Apps.StudioPopup.Open("Export Configuration",320)
	if d.sprite then
		d.sprite(d.panel,"Information",22,52,32,32,50)
	else
		local icon = d.frame(d.panel,22,52,32,32,rgb(120,169,255))
		d.round(icon,16)
		local glyph = d.label(icon,"!",0,-1,32,34,24,true,rgb(39,41,48))
		glyph.TextXAlignment = Enum.TextXAlignment.Center
	end
	d.label(d.panel,"Customize your export",64,48,410,24,15,true)
	d.label(d.panel,"Pick the components to include in your file",64,74,430,24,15)
	d.label(d.panel,"Include",64,106,380,24,15,true)
	local options = {Skinning=true,Textures=true,Attachments=true,Cages=false}
	-- One worker owns mesh/image allocations. Changes invalidate the in-flight result
	-- and coalesce while Roblox yields to read an asset.
	local revision, running = 0, false
	local function prepare()
		revision += 1
		d.setPrimary("Processing...",nil)
		if running then return end
		running = true
		task.defer(function()
			task.wait()
			while d.isOpen() do
				local generation, snapshot = revision, table.clone(options)
				local function cancelled() return not d.isOpen() or generation ~= revision end
				local ok, data, details = pcall(function()
					checkTargets(targets)
					return Apps.GltfExporter.Export(targets,snapshot,cancelled)
				end)
				if not cancelled() then
					running = false
					if ok then
						d.setPrimary("Export",function() onReady(data,details) end)
					else
						d.setPrimary("Retry",prepare,tostring(data):gsub("^.-:%d+: ", ""))
					end
					return
				end
			end
			running = false
		end)
	end
	for i, name in ipairs({"Skinning","Textures","Attachments","Cages"}) do
		local row = d.make("TextButton",d.panel,{Name=name,Text="",BackgroundTransparency=1,AutoButtonColor=false,
			Position=UDim2.fromOffset(64,130+(i-1)*29),Size=UDim2.fromOffset(300,29)})
		local fill, opacity
		if d.sprite then
			d.sprite(row,"Unchecked",1,5,19,19,26)
			fill = d.sprite(row,"Checked",1,5,19,19,2)
			opacity = "ImageTransparency"
		else
			local border = d.frame(row,1,5,19,19,rgb(215,217,222))
			d.round(border,3)
			d.round(d.frame(border,1,1,17,17,rgb(39,41,48)),2)
			fill = d.make("CanvasGroup",row,{Position=border.Position,Size=border.Size,
				BorderSizePixel=0,BackgroundColor3=rgb(247,247,248)})
			d.round(fill,3)
			local short = d.frame(fill,4,10,6,2,rgb(32,34,40))
			short.Rotation = 45
			local long = d.frame(fill,7,9,9,2,rgb(32,34,40))
			long.Rotation = -45
			opacity = "GroupTransparency"
		end
		fill[opacity] = if options[name] then 0 else 1
		d.label(row,name,32,0,240,29,13,false,rgb(240,240,241))
		row.Activated:Connect(function()
			if d.busy then return end
			options[name] = not options[name]
			local fade = if options[name] then 0 else 1
			local timing = TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
			service.TweenService:Create(fill,timing,{[opacity]=fade}):Play()
			prepare()
		end)
	end
	prepare()
end

local function browse(d, extensions, choose)
	local page = d.frame(d.panel,0,30,520,d.panel.Size.Y.Offset-30,rgb(39,41,48))
	page.ZIndex, page.Active = 5,true
	local location = d.label(page,"Workspace",24,10,360,25,14,true)
	location.TextTruncate = Enum.TextTruncate.AtEnd
	local directory, entries, offset = "", {}, 1
	local slots = if page.Size.Y.Offset < 240 then 3 else 5
	local rows = {}
	local refresh
	local function render()
		for i, row in ipairs(rows) do
			local entry = entries[offset+i-1]
			row.Visible = entry ~= nil
			if entry then row.Text = (if entry.folder then "▸  " else "") .. entry.name end
		end
	end
	for i = 1, slots do
		local row = d.button(page,"",24,42+30*(i-1),472,26,rgb(59,62,72),function()
			local entry = entries[offset+i-1]
			if not entry then return end
			if entry.folder then refresh(entry.path) else choose(entry.path); page:Destroy() end
		end)
		row.TextTruncate = Enum.TextTruncate.AtEnd
		table.insert(rows,row)
	end
	local request = 0
	refresh = function(path)
		request += 1
		local id = request
		location.Text = "Loading..."
		entries, offset = {}, 1
		render()
		local ok, result = pcall(function()
			local files = env.listfiles(if path == "" then "." else path)
			local found = {}
			for _, file in ipairs(files) do
				local name = file:gsub("\\","/"):match("([^/]+)/?$")
				if name and name ~= "." and name ~= ".." then
					local full = if path=="" then name else path .. "/" .. name
					local folder = env.isfolder and env.isfolder(full)
					if folder or table.find(extensions, name:lower():match("%.([^%.]+)$") or "") then
						table.insert(found,{name=name,path=full,folder=folder == true})
					end
				end
			end
			table.sort(found,function(a,b)
				if a.folder ~= b.folder then return a.folder end
				return a.name:lower() < b.name:lower()
			end)
			return found
		end)
		if not page.Parent or id ~= request then return end
		if not ok then location.Text = tostring(result); return end
		directory, entries = path,result
		location.Text = (if path=="" then "Workspace" else path) .. (if #entries==0 then "  (empty)" else "")
		render()
	end
	d.button(page,"Up",430,10,66,26,rgb(59,62,72),function() refresh(directory:match("^(.*)/") or "") end)
	local y = page.Size.Y.Offset-45
	d.button(page,"Previous",24,y,72,28,rgb(59,62,72),function()
		offset=math.max(1,offset-slots); render()
	end)
	d.button(page,"Next",104,y,55,28,rgb(59,62,72),function()
		if offset+slots<=#entries then offset+=slots; render() end
	end)
	d.button(page,"Back",430,y,66,28,rgb(59,62,72),function() page:Destroy() end)
	refresh("")
end

local function filePrompt(title, verb, subject, initial, loadCsv, callback)
	local d = Apps.StudioPopup.Open(title, if loadCsv then 324 else 238)
	d.label(d.panel,subject,24,44,472,24,15,true)
	local fieldY = if loadCsv then 116 else 100
	local caption = d.label(d.panel,"Workspace path",24,fieldY-26,460,22,13)
	local box = d.make("TextBox",d.panel,{Name="FileInput",Position=UDim2.fromOffset(24,fieldY),
		Size=UDim2.fromOffset(472,34),Text=initial,TextColor3=rgb(247,247,248),ClearTextOnFocus=false,
		BackgroundColor3=rgb(29,30,36),BorderSizePixel=0,Font=Enum.Font.BuilderSans,TextSize=14,
		TextXAlignment=Enum.TextXAlignment.Left,PlaceholderColor3=rgb(155,158,170)})
	d.round(box,5)
	d.make("UIStroke",box,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Color=rgb(76,79,91)})
	d.make("UIPadding",box,{PaddingLeft=UDim.new(0,9),PaddingRight=UDim.new(0,9),PaddingTop=UDim.new(0,5),PaddingBottom=UDim.new(0,5)})
	box.PlaceholderText = if verb=="Save" then initial elseif verb=="Insert" then "models/example.rbxm or models/example.rbxmx" else "locales/translations.csv"
	local browseButton
	if env.listfiles and (verb=="Insert" or loadCsv) then
		browseButton = d.button(d.panel,"Browse...",419,if loadCsv then 138 else fieldY,77,34,rgb(59,62,72),function()
			if not d.busy then
				browse(d,if loadCsv then {"csv"} else {"rbxm","rbxmx"},function(path) box.Text = path end)
			end
		end)
		box.Size = UDim2.fromOffset(387,34)
	end
	local paste = false
	if loadCsv then
		local setFileColor, setPasteColor
		local saved = { [false]=initial, [true]="" }
		local function mode(value)
			if d.busy then return end
			saved[paste], paste = box.Text, value
			box.Text, box.MultiLine, box.TextWrapped = saved[value], value, value
			box.TextYAlignment = if value then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
			if browseButton then browseButton.Visible = not value end
			box.Size = UDim2.fromOffset(if not value and browseButton then 387 else 472,if value then 100 else 34)
			caption.Text = if value then "CSV text" else "Workspace path"
			box.PlaceholderText = if value then "Key,Context,Example,Source,fr" else "locales/translations.csv"
			setFileColor(if value then rgb(59,62,72) else rgb(52,83,162))
			setPasteColor(if value then rgb(52,83,162) else rgb(59,62,72))
		end
		local unused
		unused, setFileColor = d.button(d.panel,"From file",24,74,80,27,rgb(59,62,72),function() mode(false) end)
		unused, setPasteColor = d.button(d.panel,"Paste CSV",112,74,85,27,rgb(59,62,72),function() mode(true) end)
		fieldY = 138
		caption.Position, box.Position = UDim2.fromOffset(24,111), UDim2.fromOffset(24,fieldY)
		mode(not env.readfile)
	end
	d.action(verb,64,function(cancelled)
		return callback(box.Text,paste,cancelled)
	end)
end

function Actions.Open(action, targets)
	local first = targets[1]
	if not first then return end
	local name = if #targets == 1 then first.Obj.Name else "Selection"
	local function save(extension, data, details)
		local stem = name:gsub('[<>:"/\\|?*%c]', "_"):gsub("[%. ]+$", "")
		local overwrite
		filePrompt(if extension=="csv" then "Save as CSV" else "Save glTF",
			"Save","File name",(stem ~= "" and stem or "Selection") .. "." .. extension,false,function(input,_,cancelled)
				local path = pathFor(input,{extension},extension)
				if env.isfile and env.isfile(path) and overwrite ~= path then
					overwrite = path
					error("File exists. Click Save again to replace it.",0)
				end
				if extension=="csv" then
					checkTargets(targets)
					data = Apps.LocalizationCsv.Encode(first.Obj:GetEntries())
				end
				if cancelled() then return end
				env.writefile(path,data)
				if details then return "Saved. " .. details end
			end)
	end
	if action == "INSERT_FILE" then
		filePrompt("Insert from File","Insert","Insert into " .. name,"",false,function(input,_,cancelled)
			Actions.Insert(input,targets,cancelled)
		end)
	elseif action == "LOAD_CSV" then
		filePrompt("Load from CSV","Load","Replace entries in " .. name,"",true,function(input,paste,cancelled)
			Actions.LoadCsv(input,targets,paste,cancelled)
		end)
	elseif action == "SAVE_CSV" then save("csv")
	else configuration(targets,function(data, details) save("gltf",data,details) end) end
end

return {
	InitDeps = function(d)
		Main, Apps, Lib, env, service = d.Main, d.Apps, d.Lib, d.env, d.service
	end,
	InitAfterMain = function() end,
	Main = function() return Actions end,
}
