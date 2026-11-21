--!strict

do
	local visibility = Apps.ServiceVisibility
	local old = Settings.Explorer.HiddenServices
	Settings.Explorer.HiddenServices = {}
	local fixture = Instance.new("Folder", game)
	fixture.Name = "ServiceVisibilityAudit"
	local child = Instance.new("Folder", fixture)
	child.Name = "HiddenServiceChild"
	assert(visibility.IsVisible(fixture), "ordinary root objects are visible by default")
	local oldClass = API.Classes.Folder
	API.Classes.Folder = { Name = "Folder", Tags = { Service = true } }
	assert(visibility.IsVisible(workspace), "Workspace is visible by default")
	assert(not visibility.IsVisible(fixture), "extra services start hidden")
	assert(table.find(visibility.GetHiddenServices(), "Folder"), "extra services can be shown")
	assert(visibility.SetVisible(fixture, true), "extra services can be enabled")
	assert(Settings.Explorer.HiddenServices.Folder == false, "showing an extra service stores a persistent override")
	Explorer.SyncHistoryObject(fixture)
	Explorer.Expanded[nodes[fixture]] = true
	Explorer.ForceUpdate()
	assert(visibility.IsService(fixture) and not visibility.IsService(child), "only DataModel services can be hidden")
	Explorer.Selection:Set(nodes[fixture])
	Explorer.ShowRightClick(Vector2.new(10, 10))
	local foundShow, foundHide = false, false
	for _, item in ipairs(Explorer.RightClickContext.Items) do
		foundShow = foundShow or item.Name == "Show Services..."
		foundHide = foundHide or item.Name == "Hide Service in Explorer"
	end
	assert(foundShow and foundHide, "service context exposes Studio actions")
	Explorer.RightClickContext:Hide()
	local initialObjectCount = Explorer.InitialObjectCount
	Explorer.InitialObjectCount = 38000
	Explorer.DoSearch("HiddenServiceChild")
	Explorer.Selection:Set(nodes[fixture])
	Explorer.HideSelectedServices()
	assert(fixture.Parent == game and child.Parent == fixture, "hiding never reparents or destroys service objects")
	assert(
		not Explorer.IsNodeVisible(nodes[fixture]) and not Explorer.IsNodeVisible(nodes[child]),
		"hidden root and children disappear from Explorer"
	)
	assert(
		not Explorer.IsNodeVisible(nodes[child]) and #Explorer.Selection.List == 0,
		"hidden ancestry and selection stay consistent"
	)
	assert(#Explorer.MatchList == 0, "hidden subtree does not contribute navigable search matches")
	assert(table.find(visibility.GetHiddenServices(), "Folder"), "hidden service is available to show again")
	local shown = visibility.Show("Folder")
	assert(shown == fixture and visibility.IsVisible(fixture), "show restores same service instance")
	Explorer.ForceUpdate()
	assert(
		Explorer.IsNodeVisible(nodes[fixture]) and Explorer.IsNodeVisible(nodes[child]),
		"show preserves expanded children"
	)
	assert(#Explorer.MatchList == 1, "restoring service restores search navigation without another scan")
	Explorer.DoSearch("")
	Explorer.InitialObjectCount = initialObjectCount
	assert(not visibility.SetVisible(child, false), "ordinary child cannot be hidden as service")
	local original = Lib.Window.new
	Lib.Window.new = function()
		local w = original()
		w.SetSize = function() end
		w.Close = function(self)
			self.Closed = true
		end
		w.Show = function(self)
			self.Closed = false
		end
		return w
	end
	visibility.SetVisible(fixture, false)
	Explorer.ForceUpdate()
	Apps.ServiceVisibilityDialog.Open()
	assert(table.find(Apps.ServiceVisibilityDialog.Entries, "Folder"), "Insert Service dialog lists hidden service")
	Apps.ServiceVisibilityDialog.Insert()
	assert(
		visibility.IsVisible(fixture) and Explorer.IsNodeVisible(nodes[fixture]),
		"Insert action restores service through real dialog"
	)
	local dialog = Apps.ServiceVisibilityDialog
	local originalCatalog = visibility.GetHiddenServices
	visibility.GetHiddenServices = function()
		local names = {}
		for i = 1, 1200 do
			names[i] = string.format("Service%04d", i)
		end
		return names
	end
	dialog.Open()
	local panel = dialog.Window.GuiElems.Content.InsertService
	local field = panel.SearchServices
	local list = panel.Services
	assert(dialog.MountedRows < 30, "service chooser mounts only viewport rows")
	local commits = dialog.Commits
	field.Text = "Service1199"
	field:GetPropertyChangedSignal("Text"):Fire()
	assert(dialog.Entries[1] == "Service1199" and #dialog.Entries == 1, "service search filters catalog")
	assert(
		panel.SearchServices == field and dialog.Commits == commits + 1,
		"search preserves textbox identity and uses one React commit"
	)
	visibility.GetHiddenServices = originalCatalog
	dialog.Open()
	Apps.ServiceVisibilityDialog.Window:Close()
	Lib.Window.new = original
	API.Classes.Folder = oldClass
	Settings.Explorer.HiddenServices = old
	fixture.Parent = nil
	Explorer.SyncHistoryObject(fixture)
	Explorer.CleanDeletedChildren()
	Explorer.ForceUpdate()
	print(
		"PASS: hide/show service menu model, preserved objects/expansion, ancestry, selection and Insert Service dialog"
	)
end
