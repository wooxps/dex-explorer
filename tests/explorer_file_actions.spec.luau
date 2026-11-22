--!strict
do
	local history = Apps.History
	local oldEntries, oldIndex, oldFocus = table.clone(history.Entries), history.Index, history.Focused
	local csv, files = Apps.LocalizationCsv, Apps.ExplorerFileActions
	local entry = {Key = "greeting", Context = "Shop", Example = 'He said "hi", twice', Source = "first\r\nsecond", Values = {fr = "salut", ja = "ようこそ"}}
	local encoded = csv.Encode({entry})
	local decoded = csv.Decode(encoded)
	assert(#decoded == 1 and decoded[1].Example == entry.Example and decoded[1].Source == entry.Source)
	assert(decoded[1].Values.ja == entry.Values.ja and encoded:find("Source,fr,ja",1,true))
	local shuffled = csv.Decode("fr,SOURCE,Key\nbonjour, Hello ,one\n")
	assert(shuffled[1].Values.fr == "bonjour" and shuffled[1].Source == " Hello ")
	assert(#csv.Decode(csv.Encode({})) == 0)
	for _, malformed in ipairs({
		"", "Context,fr\nX,Y", "key,KEY\none,two", 'Key,Source\none,"unclosed',
		"Key,Source\none,source,extra", 'Key,Source\none,bad"quote',
		'Key,Source\none,"ok"bad', "Key,Source\none,hello\none,duplicate",
		"Source,Context\none,here\none,here",
	}) do assert(not pcall(csv.Decode, malformed), malformed) end

	local obj = Instance.new("LocalizationTable", workspace)
	local entries = {entry}
	obj.GetEntries = function() return entries end
	obj.SetEntries = function(_, value) entries = value end
	Explorer.SyncHistoryObject(obj)
	local targets = {Explorer.GetNodes()[obj]}
	local readfile, serializer = deps.env.readfile, service.SerializationService
	deps.env.readfile = function(path)
		assert(path == "locales/fr.csv")
		return "Key,Source,fr\nnew,Hello,Bonjour"
	end
	files.LoadCsv("locales/fr.csv", targets)
	assert(entries[1].Values.fr == "Bonjour" and Apps.History.Undo() and entries[1] == entry)
	assert(Apps.History.Redo() and entries[1].Key == "new")
	local before, historyIndex = entries, Apps.History.Index
	assert(not pcall(files.LoadCsv, 'Key,Source\nwrong,"', targets))
	assert(entries == before and Apps.History.Index == historyIndex)
	files.LoadCsv("Key,Source,fr", targets)
	assert(#entries == 0 and Apps.History.Undo() and entries[1].Key == "new")
	for _, invalid in ipairs({"../file.rbxm","C:/file.rbxm","/file.rbxm","dir//file.rbxm","https://example/file.rbxm","file.txt"}) do
		assert(not pcall(files.Insert, invalid, targets))
	end

	local first, second = Instance.new("Folder", workspace), Instance.new("Folder", workspace)
	Explorer.SyncHistoryObject(first)
	Explorer.SyncHistoryObject(second)
	local destinations = {Explorer.GetNodes()[first], Explorer.GetNodes()[second]}
	-- Exercise the actual menu callbacks. The mock supplies one-dimensional
	-- frames and recomputes WorldCFrame when a cloned attachment is parented.
	local frames = {}
	frames.__index = frames
	local function frame(x) return setmetatable({x=x}, frames) end
	frames.__mul = function(a,b) return frame(a.x+b.x) end
	function frames:Inverse() return frame(-self.x) end
	function frames:ToObjectSpace(other) return self:Inverse()*other end
	local attachment = Instance.new("Attachment", first)
	first.CFrame, second.CFrame = frame(12), frame(55)
	attachment.CFrame, attachment.WorldCFrame = frame(3), frame(15)
	Explorer.SyncHistoryObject(attachment)
	local plainSet = Apps.History.Set
	Apps.History.Set = function(obj, key, value)
		plainSet(obj,key,value)
		if key=="Parent" and value and obj:IsA("Attachment") then obj.WorldCFrame = value.CFrame * obj.CFrame end
	end
	local actions = Explorer.RightClickContext.Registered
	Explorer.Selection:Set(Explorer.GetNodes()[attachment])
	actions.COPY.OnClick()
	attachment.WorldCFrame = frame(99)
	Explorer.Selection:Set(destinations[2])
	actions.PASTE_ORIGINAL.OnClick()
	local pasted = Explorer.Selection.List[1].Obj
	assert(pasted.Parent == second and pasted.CFrame.x == -40, "restores copy-time world frame under new parent")
	assert(Apps.History.Undo() and not pasted.Parent and Apps.History.Redo() and pasted.Parent == second and pasted.CFrame.x == -40)
	Explorer.Selection:Set(destinations[2])
	actions.PASTE.OnClick()
	assert(Explorer.Selection.List[1].Obj.CFrame.x == 3, "ordinary paste preserves the attachment's local frame")
	Apps.History.Set = plainSet
	local firstCount, secondCount = #first:GetChildren(), #second:GetChildren()
	local batches = {}
	deps.env.readfile = function(path) assert(path == "models/input.rbxm"); return "fixture" end
	service.SerializationService = {DeserializeInstancesAsync = function(_, bytes)
		assert(buffer.tostring(bytes) == "fixture")
		local batch = {Instance.new("Folder"), Instance.new("Folder")}
		table.insert(batches, batch)
		return batch
	end}
	files.Insert("models\\input.rbxm", destinations)
	assert(#Explorer.Selection.List == 4 and batches[1][2].Parent == first and batches[2][2].Parent == second)
	assert(Apps.History.Undo() and not batches[1][1].Parent and not batches[2][2].Parent)
	assert(Apps.History.Redo() and batches[1][1].Parent == first and batches[2][2].Parent == second)
	local reads = 0
	deps.env.readfile = function()
		reads += 1
		assert(reads == 1, "Read failed on second destination")
		return "fixture"
	end
	historyIndex = Apps.History.Index
	assert(not pcall(files.Insert, "models/input.rbxm", destinations))
	assert(#first:GetChildren() == firstCount+2 and #second:GetChildren() == secondCount+2 and Apps.History.Index == historyIndex)
	deps.env.readfile, service.SerializationService = readfile, serializer
	Explorer.Selection:Clear()
	for _, object in ipairs({obj, first, second}) do
		object:Destroy()
		Explorer.SyncHistoryObject(object)
	end
	history.Entries, history.Index, history.Focused = oldEntries, oldIndex, oldFocus
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	print("PASS: CSV round trips, parser errors, empty imports, undo/redo, multi-root file insertion and failed batch cleanup")
end
