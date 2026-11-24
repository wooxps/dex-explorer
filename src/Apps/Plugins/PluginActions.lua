--!strict

local Apps, Main, Lib, user

local function InitDeps(deps)
	Apps, Main, Lib, user = deps.Apps, deps.Main, deps.Lib, deps.service.UserInputService
end

local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
local reservedKeys = { F2 = true, F3 = true, F9 = true, F10 = true, F11 = true, F12 = true, F = true, R = true }
local reservedControl = {
	A = true,
	C = true,
	D = true,
	E = true,
	G = true,
	H = true,
	I = true,
	K = true,
	L = true,
	N = true,
	P = true,
	T = true,
	U = true,
	V = true,
	W = true,
	X = true,
	Y = true,
	Z = true,
	["0"] = true,
}

local function CreateModule()
	local actions = {}
	local initialized = false
	local globalContext = table.freeze({ Surface = "Global" })

	function actions.ParseShortcut(value)
		if type(value) ~= "string" or #value > 32 then
			return nil, "Use a shortcut such as Ctrl+Alt+M or Alt+Shift+F8."
		end
		local modifiers, key = {}, nil
		local parts = string.split(value, "+")
		for index, part in ipairs(parts) do
			local token = part:match("^%s*(.-)%s*$"):upper()
			if token == "CTRL" or token == "ALT" or token == "SHIFT" then
				if modifiers[token] or index == #parts then
					return nil, "List each modifier once, followed by the key."
				end
				modifiers[token] = true
			elseif index == #parts then
				key = token
			else
				return nil, "List the modifiers first, followed by the key."
			end
		end
		if not key or not modifiers.ALT or not (modifiers.CTRL or modifiers.SHIFT) then
			return nil, "Use Ctrl+Alt or Alt+Shift with a letter, number, or function key."
		end
		local number = key:match("^%d$") and tonumber(key)
		local functionNumber = tonumber(key:match("^F([1-9]%d?)$"))
		if not number and not key:match("^[A-Z]$") and not (functionNumber and functionNumber <= 12) then
			return nil, "Use a letter, number, or function key."
		end
		if
			reservedKeys[key]
			or (modifiers.CTRL and reservedControl[key])
			or (not modifiers.CTRL and (key == "L" or key == "I" or (number and number >= 1 and number <= 4)))
		then
			return nil, "That shortcut is reserved by Dex or Roblox."
		end
		local keyName = number and digits[number + 1] or key
		return table.freeze({
			Key = Enum.KeyCode[keyName],
			Ctrl = modifiers.CTRL == true,
			Alt = true,
			Shift = modifiers.SHIFT == true,
			Token = (modifiers.CTRL and "Ctrl+" or "") .. "Alt+" .. (modifiers.SHIFT and "Shift+" or "") .. key,
		})
	end

	function actions.ExplorerContext(nodes, target)
		local selection = {}
		for _, node in ipairs(nodes) do
			if not node.Del then
				selection[#selection + 1] = node.Obj
			end
		end
		return table.freeze({
			Surface = "Explorer",
			Selection = table.freeze(selection),
			Target = target or selection[1],
		})
	end

	function actions.EditorContext(viewer, codeFrame)
		local ranges = viewer.GetSelections()
		for _, range in ipairs(ranges) do
			table.freeze(range)
		end
		return table.freeze({
			Surface = "Editor",
			Editor = viewer,
			Document = viewer.ActiveDocument,
			Script = viewer.ActiveScript,
			Selection = table.freeze(viewer.GetSelectionState()),
			Selections = table.freeze(ranges),
			Editable = codeFrame.Editable ~= false,
		})
	end

	function actions.AddMenu(menu, surface, makeContext, wrap)
		local runtime = Apps.PluginRuntime
		local all = runtime.GetActions(surface)
		if #all == 0 then
			return
		end
		local context = makeContext()
		local items = {}
		for _, action in ipairs(all) do
			if runtime.IsActionAvailable(action.PluginID, action.ID, context) then
				local function invoke()
					runtime.InvokeAction(action.PluginID, action.ID, context, action)
				end
				items[#items + 1] = {
					Name = action.Name,
					Description = action.Tooltip,
					Shortcut = action.Shortcut,
					OnClick = wrap and wrap(invoke) or invoke,
				}
			end
		end
		if #items > 0 then
			menu:AddDivider()
			menu:Add({ Name = "Plugins", Submenu = items })
		end
	end

	function actions.HandleShortcut(surface, input, makeContext)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return false
		end
		local leftAlt = user:IsKeyDown(Enum.KeyCode.LeftAlt)
		local alt = leftAlt or user:IsKeyDown(Enum.KeyCode.RightAlt)
		if not alt or user:IsKeyDown(Enum.KeyCode.LeftMeta) or user:IsKeyDown(Enum.KeyCode.RightMeta) then
			return false
		end
		local ctrl, shift = Lib.IsCtrlDown() == true, Lib.IsShiftDown() == true
		if
			not (ctrl or shift)
			or (ctrl and not leftAlt)
			or (Apps.ContextMenu.IsAnyShown and Apps.ContextMenu.IsAnyShown())
		then
			return false
		end
		local runtime = Apps.PluginRuntime
		for _, action in ipairs(runtime.GetActions(surface)) do
			local keybind = action.Keybind
			if keybind and keybind.Key == input.KeyCode and keybind.Ctrl == ctrl and keybind.Shift == shift then
				local context = makeContext and makeContext() or globalContext
				if not runtime.IsActionAvailable(action.PluginID, action.ID, context) then
					return false
				end
				task.defer(function()
					if Main.Alive and (surface ~= "Editor" or context.Editor.ActiveDocument == context.Document) then
						runtime.InvokeAction(action.PluginID, action.ID, context, action)
					end
				end)
				return true
			end
		end
		return false
	end

	function actions.Init()
		if initialized then
			return
		end
		initialized = true
		Main.TrackSignal(user.InputBegan, function(input, processed)
			if (processed and not Main.GameInputLocked) or user:GetFocusedTextBox() then
				return
			end
			actions.HandleShortcut("Global", input)
		end)
	end

	return actions
end

return { InitDeps = InitDeps, Main = CreateModule }
