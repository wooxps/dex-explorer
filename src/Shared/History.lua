--!strict

local Main, Apps, Lib, service

------------------------------ Initialization ------------------------------

local function InitDeps(data)
	Main, Apps, Lib, service = data.Main, data.Apps, data.Lib, data.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local H = { Entries = {}, Index = 0, Limit = 100, Replaying = false, Focused = false }
	local active
	local detached = setmetatable({}, { __mode = "k" })
	function H.IsHidden(obj)
		if
			Apps.Explorer
			and Apps.Explorer.IsInferredObject
			and Apps.Explorer.IsInferredObject(obj)
			and (
				not obj.Parent
				or (Apps.Explorer.IsReadOnlyInferenceObject and Apps.Explorer.IsReadOnlyInferenceObject(obj))
			)
		then
			return true
		end
		local current = obj
		while current do
			if detached[current] and current.Parent == nil then
				return true
			end
			current = current.Parent
		end
		return false
	end
	local function capture()
		return Apps.Explorer and Apps.Explorer.CaptureHistorySelection and Apps.Explorer.CaptureHistorySelection() or {}
	end
	function H.Record(get, set, before, after, last)
		if H.Replaying or before == after then
			return
		end
		if not active then
			error("History change outside transaction")
		end
		active.Changes[#active.Changes + 1] = { Get = get, Set = set, Before = before, After = after, Last = last }
	end
	local function rollback(changes)
		local succeeded = true
		local delayed = {}
		local function restore(change)
			if not pcall(change.Set, change.Before) then
				succeeded = false
			end
		end
		for i = #changes, 1, -1 do
			local change = changes[i]
			if change.Last then
				delayed[#delayed + 1] = change
			else
				restore(change)
			end
		end
		for _, change in ipairs(delayed) do
			restore(change)
		end
		return succeeded
	end
	function H.Run(name, callback, ...)
		if H.Replaying or active then
			return callback(...)
		end
		local entry = { Name = name, Changes = {}, BeforeSelection = capture() }
		active = entry
		local result = table.pack(pcall(callback, ...))
		active = nil
		if not result[1] and #entry.Changes > 0 then
			H.Replaying = true
			local rollbackOK = rollback(entry.Changes)
			H.Replaying = false
			if rollbackOK then
				table.clear(entry.Changes)
			end
			if Apps.Explorer and Apps.Explorer.RestoreHistorySelection then
				pcall(Apps.Explorer.RestoreHistorySelection, entry.BeforeSelection)
			end
		end
		if #entry.Changes > 0 then
			entry.AfterSelection = capture()
			for i = #H.Entries, H.Index + 1, -1 do
				H.Entries[i] = nil
			end
			H.Entries[#H.Entries + 1] = entry
			if #H.Entries > H.Limit then
				table.remove(H.Entries, 1)
			end
			H.Index = #H.Entries
			H.Focused = true
		end
		if not result[1] then
			error(result[2], 0)
		end
		return table.unpack(result, 2, result.n)
	end
	function H.Change(name, get, set, value)
		return H.Run(name, function()
			local before = get()
			if before == value then
				return
			end
			set(value)
			H.Record(get, set, before, get())
		end)
	end
	function H.Set(obj, key, value)
		if
			Apps.Explorer
			and Apps.Explorer.IsReadOnlyInferenceObject
			and (
				Apps.Explorer.IsReadOnlyInferenceObject(obj)
				or (key == "Parent" and Apps.Explorer.IsReadOnlyInferenceObject(value))
			)
		then
			error("Inferred server entries are read-only", 0)
		end
		local oldParent = obj.Parent
		local oldOrder = key == "Parent"
			and Apps.Explorer
			and Apps.Explorer.GetHistoryOrder
			and Apps.Explorer.GetHistoryOrder(obj)
		return H.Change(key == "Parent" and "Move object" or "Change " .. key, function()
			return obj[key]
		end, function(v)
			local wasDetached = detached[obj]
			if key == "Parent" then
				detached[obj] = v == nil or nil
			end
			local ok, err = pcall(function()
				obj[key] = v
			end)
			if not ok then
				detached[obj] = wasDetached
				error(err, 0)
			end
			if key == "Parent" and Apps.Explorer and Apps.Explorer.SyncHistoryObject then
				pcall(Apps.Explorer.SyncHistoryObject, obj)
				if Apps.Explorer.SetHistoryOrder then
					local order = nil
					if v == oldParent then
						order = oldOrder
					end
					pcall(Apps.Explorer.SetHistoryOrder, obj, order)
				end
			end
		end, value)
	end
	function H.Attribute(obj, name, value)
		if
			Apps.Explorer
			and Apps.Explorer.IsReadOnlyInferenceObject
			and Apps.Explorer.IsReadOnlyInferenceObject(obj)
		then
			error("Inferred server entries are read-only", 0)
		end
		return H.Change("Change attribute " .. name, function()
			return obj:GetAttribute(name)
		end, function(v)
			obj:SetAttribute(name, v)
		end, value)
	end
	function H.Tag(obj, tag, present)
		if
			Apps.Explorer
			and Apps.Explorer.IsReadOnlyInferenceObject
			and Apps.Explorer.IsReadOnlyInferenceObject(obj)
		then
			error("Inferred server entries are read-only", 0)
		end
		return H.Change((present and "Add tag " or "Remove tag ") .. tag, function()
			return service.CollectionService:HasTag(obj, tag)
		end, function(v)
			if v then
				service.CollectionService:AddTag(obj, tag)
			else
				service.CollectionService:RemoveTag(obj, tag)
			end
		end, present)
	end
	function H.CanUndo()
		return H.Index > 0
	end
	function H.CanRedo()
		return H.Index < #H.Entries
	end
	local function replay(redo)
		if H.Replaying or active then
			return false
		end
		local index = redo and H.Index + 1 or H.Index
		local entry = H.Entries[index]
		if not entry then
			return false
		end
		H.Replaying = true
		local applied = {}
		local ok, err = pcall(function()
			local first, last, step = 1, #entry.Changes, 1
			if not redo then
				first, last, step = #entry.Changes, 1, -1
			end
			local delayed = {}
			local function apply(change)
				local previous = change.Get()
				local target = change.Before
				if redo then
					target = change.After
				end
				applied[#applied + 1] = { Set = change.Set, Before = previous, Last = change.Last }
				change.Set(target)
			end
			for i = first, last, step do
				local change = entry.Changes[i]
				if change.Last then
					delayed[#delayed + 1] = change
				else
					apply(change)
				end
			end
			for _, change in ipairs(delayed) do
				apply(change)
			end
		end)
		if not ok then
			rollback(applied)
			H.LastError = tostring(err)
			local report = warn or print
			report("DeX " .. (redo and "redo" or "undo") .. " failed: " .. H.LastError)
		else
			H.Index += redo and 1 or -1
			H.LastError = nil
		end
		H.Replaying = false
		if Apps.Explorer and Apps.Explorer.RestoreHistorySelection then
			Apps.Explorer.RestoreHistorySelection(
				ok and (redo and entry.AfterSelection or entry.BeforeSelection) or capture()
			)
		end
		if Apps.Properties and Apps.Properties.ShowExplorerProps then
			Apps.Properties.ShowExplorerProps()
		end
		return ok, err
	end
	function H.Undo()
		return replay(false)
	end
	function H.Redo()
		return replay(true)
	end
	function H.Bind()
		if H.Bound then
			return
		end
		H.Bound = true
		local inputService = service.UserInputService
		Main.TrackSignal(inputService.InputBegan, function(input, processed)
			local kind = input.UserInputType
			if
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.Touch
			then
				local owner, order = nil, -math.huge
				for name, app in pairs(Apps) do
					local win = type(app) == "table" and app.Window
					if
						type(win) == "table"
						and type(win.IsVisible) == "function"
						and win.Gui
						and win.GuiElems
						and win.GuiElems.Main
						and win:IsVisible()
					then
						local frame = win.GuiElems.Main
						local p, s = frame.AbsolutePosition, frame.AbsoluteSize
						if
							input.Position.X >= p.X
							and input.Position.X < p.X + s.X
							and input.Position.Y >= p.Y
							and input.Position.Y < p.Y + s.Y
						then
							local z = win.Gui.DisplayOrder or 0
							if z >= order then
								owner, order = name, z
							end
						end
					end
				end
				H.Focused = owner == "Explorer" or owner == "Properties"
				return
			end
			if
				kind ~= Enum.UserInputType.Keyboard
				or (processed and not (Main and Main.GameInputLocked))
				or inputService:GetFocusedTextBox()
				or not H.Focused
			then
				return
			end
			local ex, props = Apps.Explorer, Apps.Properties
			if
				not (
					(ex and ex.Window and ex.Window:IsVisible())
					or (props and props.Window and props.Window:IsVisible())
				)
			then
				return
			end
			if
				Lib.IsCtrlDown()
				or inputService:IsKeyDown(Enum.KeyCode.LeftMeta)
				or inputService:IsKeyDown(Enum.KeyCode.RightMeta)
			then
				if
					input.KeyCode == Enum.KeyCode.Z
					and Apps.TransformTools
					and (Apps.TransformTools.Dragging or Apps.TransformTools.GuiDragging)
				then
					Apps.TransformTools.Cancel()
					return
				end
				if input.KeyCode == Enum.KeyCode.Z then
					H.Undo()
				elseif input.KeyCode == Enum.KeyCode.Y then
					H.Redo()
				end
			end
		end)
	end
	return H
end
local control = { InitDeps = InitDeps, Main = CreateModule }
if gethsfuncs then
	_G.moduleData = control
else
	return control
end
