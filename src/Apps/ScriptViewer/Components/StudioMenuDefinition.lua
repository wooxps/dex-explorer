--!strict

-- Adapted from native menu construction at Studio VA 0x1472292b0.
------------------------------ Module ------------------------------

local function Main()
	local Definition = {}
	Definition.Groups = {
		{
			{ Id = "undoAction", Name = "Undo", Shortcut = "Ctrl+Z" },
			{ Id = "redoAction", Name = "Redo", Shortcut = "Ctrl+Y" },
		},
		{
			{ Id = "cutAction", Name = "Cut", Shortcut = "Ctrl+X" },
			{ Id = "copyAction", Name = "Copy", Shortcut = "Ctrl+C" },
			{ Id = "pasteAction", Name = "Paste", Shortcut = "Ctrl+V" },
			{ Id = "deleteSelectedAction", Name = "Delete", Shortcut = "Del" },
		},
		{ { Id = "selectAllAction", Name = "Select All", Shortcut = "Ctrl+A" } },
		{
			{
				Id = "formatContextMenuAction",
				Name = "Format",
				Icon = "native/editor/format",
				Width = 224,
				Submenu = {
					{ Id = "FORMATSEL", Name = "Format Selection" },
					{ Id = "FORMATALL", Name = "Format Document" },
					{ Id = "INDENT", Name = "Indent", Shortcut = "Ctrl+]" },
					{ Id = "UNINDENT", Name = "Unindent", Shortcut = "Ctrl+[" },
				},
			},
		},
		{
			{ Id = "GOTOERR", Name = "Go to Script Error" },
			{ Id = "GOTODECL", Name = "Go to Declaration", Shortcut = "Ctrl+F12" },
			{ Id = "INVOKESYMBOLS", Name = "Open Script Function Filter", Shortcut = "Alt+F" },
			{ Id = "RENAMEDOCSYMBOL", Name = "Rename Symbol" },
		},
		{ { Id = "TOGGLECOMMENT", Name = "Toggle Comment", Shortcut = "Ctrl+/" } },
		{
			{ Id = "UNFOLDALL", Name = "Expand Script Folds", Shortcut = "Ctrl+E" },
			{ Id = "FOLDALL", Name = "Collapse Script Folds", Shortcut = "Ctrl+Shift+E" },
		},
		{
			{ Id = "zoomInAction", Name = "Zoom In", Shortcut = "Ctrl+=" },
			{ Id = "zoomOutAction", Name = "Zoom Out", Shortcut = "Ctrl+-" },
			{ Id = "resetScriptZoomAction", Name = "Reset Script Zoom", Shortcut = "Ctrl+0" },
		},
		{ { Id = "showScriptInExplorerAction", Name = "Show in Explorer", Shortcut = "Ctrl+Alt+K" } },
	}
	function Definition.Build(bindings, wrap, resolveIcon)
		local function bind(action)
			local children
			if action.Submenu then
				children = {}
				for _, child in ipairs(action.Submenu) do
					local entry = bind(child)
					if entry then
						children[#children + 1] = entry
					end
				end
				if #children == 0 then
					return nil
				end
			end
			local binding = bindings[action.Id]
			if not children and (not binding or type(binding.Callback) ~= "function") then
				return nil
			end
			return {
				Name = action.Name,
				Text = action.Name,
				NativeActionId = action.Id,
				Shortcut = action.Shortcut,
				Icon = action.Icon and resolveIcon(action.Icon) or nil,
				Width = action.Width,
				Submenu = children,
				Disabled = binding and binding.Disabled == true or false,
				OnClick = not children and wrap(binding.Callback) or nil,
			}
		end
		local entries = {}
		for _, group in ipairs(Definition.Groups) do
			local retained = {}
			for _, action in ipairs(group) do
				local entry = bind(action)
				if entry then
					retained[#retained + 1] = entry
				end
			end
			if #retained > 0 then
				if #entries > 0 then
					entries[#entries + 1] = { Divider = true }
				end
				for _, entry in ipairs(retained) do
					entries[#entries + 1] = entry
				end
			end
		end
		return entries
	end
	return Definition
end
return { Main = Main }
