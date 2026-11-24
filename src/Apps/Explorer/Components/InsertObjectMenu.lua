--!strict

local Apps, Settings, RMD

------------------------------ Initialization ------------------------------

local function InitDeps(dependencies)
	Apps, Settings, RMD = dependencies.Apps, dependencies.Settings, dependencies.RMD
end

------------------------------ Module ------------------------------

local function Main()
	local InsertObjectMenu = {}

	function InsertObjectMenu.Create(options)
		local menu = Apps.ContextMenu.new()
		menu.SearchEnabled = true
		menu.MaxHeight = 400
		menu.Width = 280
		menu:ApplyTheme({
			ContentColor = Settings.Theme.Main2,
			OutlineColor = Settings.Theme.Outline1,
			DividerColor = Settings.Theme.Outline1,
			TextColor = Settings.Theme.Text,
			HighlightColor = Settings.Theme.ButtonHover,
		})

		local function insert(className)
			local target = options.GetTarget()
			local targets = if target then { target } else table.clone(options.GetSelection())
			return Apps.InsertionService.Insert(className, targets, {
				DefaultProperties = options.DefaultProperties,
				GetName = options.GetName,
				Reveal = options.Reveal,
			})
		end

		local iconData = options.GetIconData()
		local lastCategory
		for _, entry in ipairs(Apps.ReflectionService.GetCreatableClasses()) do
			local class, category = entry[1], entry[2]
			if category ~= lastCategory then
				menu:AddDivider(category)
				lastCategory = category
			end

			local metadata = RMD.Classes[class.Name]
			local icon = metadata and tonumber(metadata.ExplorerImageIndex) or 0
			if iconData then
				icon = iconData.Icons[class.Name] or iconData.Icons.Placeholder
			end
			menu:Add({
				Name = class.Name,
				Description = Apps.ReflectionService.GetSummary(class.Name),
				IconMap = options.ClassIcons,
				Icon = icon,
				OnClick = insert,
			})
		end

		local hide = menu.Hide
		function menu:Hide()
			hide(self)
			options.OnClosed()
		end
		return menu
	end

	return InsertObjectMenu
end

return { InitDeps = InitDeps, Main = Main }
