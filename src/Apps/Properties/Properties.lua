--!strict


------------------------------ Variables ------------------------------

local Main, Lib, Apps, Settings
local Explorer, Properties, ScriptViewer, Notebook
local API, RMD, env, service, plr, create, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings

	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function InitAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

------------------------------ Module ------------------------------

local function CreateModule()
	local Properties = {}
	local View = Apps.StudioPropertiesView
	local propertyFont = Enum.Font.SourceSans
	local propertyBold = Enum.Font.SourceSansSemibold
	local Colors = {
		Surface = Color3.fromRGB(25, 26, 31),
		Category = Color3.fromRGB(32, 34, 39),
		Grid = Color3.fromRGB(32, 34, 39),
		Outline = Color3.fromRGB(53, 55, 65),
		Text = Color3.fromRGB(188, 190, 200),
		ReadOnly = Color3.fromRGB(73, 77, 90),
	}

	local window, toolBar, propsFrame, columnSplitter
	local scrollV, scrollH
	local viewportWidth, viewportHeight
	local viewWindowWidth, viewWindowHeight
	local categoryOrder
	local props, viewList, expanded, indexableProps, propEntries, autoUpdateObjs = {}, {}, {}, {}, {}, {}
	local inputBox, inputTextBox, inputProp, inputSelection
	local valueEditors
	local checkboxes = {}
	local table, string = table, string
	local getPropChangedSignal = game.GetPropertyChangedSignal
	local getAttributeChangedSignal = game.GetAttributeChangedSignal
	local isa = game.IsA
	local getAttribute = game.GetAttribute
	local setAttribute = game.SetAttribute

	Properties.GuiElems = {}
	Properties.Index = 0
	Properties.ViewWidth = 0
	Properties.MinInputWidth = 100
	Properties.EntryIndent = View.Indent
	Properties.EntryOffset = 4
	Properties.NameWidthCache = {}
	Properties.SubPropCache = {}
	Properties.ClassLists = {}
	Properties.SearchText = ""
	Properties.ScrollOffset = 0
	Properties.ColumnRatio = 0.5
	Properties.ViewLayout = View.Layout(viewList)

	Properties.SoundPreviewProp =
		{ Category = "Data", ValueType = { Name = "SoundPlayer" }, Class = "Sound", Name = "Preview", Tags = {} }

	Properties.IgnoreProps = {
		["DataModel"] = {
			["PrivateServerId"] = true,
			["PrivateServerOwnerId"] = true,
			["VIPServerId"] = true,
			["VIPServerOwnerId"] = true,
		},
	}

	Properties.ExpandableTypes = {
		["Vector2"] = true,
		["Vector3"] = true,
		["UDim"] = true,
		["UDim2"] = true,
		["CFrame"] = true,
		["Rect"] = true,
		["PhysicalProperties"] = true,
		["Ray"] = true,
		["NumberRange"] = true,
		["Faces"] = true,
		["Axes"] = true,
	}

	Properties.ExpandableProps = {
		["Sound.SoundId"] = true,
	}

	Properties.CollapsedCategories = {
		["Surface Inputs"] = true,
		["Surface"] = true,
	}

	Properties.ConflictSubProps = {
		["Vector2"] = { "X", "Y" },
		["Vector3"] = { "X", "Y", "Z" },
		["UDim"] = { "Scale", "Offset" },
		["UDim2"] = { "X", "X.Scale", "X.Offset", "Y", "Y.Scale", "Y.Offset" },
		["CFrame"] = {
			"Position",
			"Position.X",
			"Position.Y",
			"Position.Z",
			"RightVector",
			"RightVector.X",
			"RightVector.Y",
			"RightVector.Z",
			"UpVector",
			"UpVector.X",
			"UpVector.Y",
			"UpVector.Z",
			"LookVector",
			"LookVector.X",
			"LookVector.Y",
			"LookVector.Z",
		},
		["Rect"] = { "Min.X", "Min.Y", "Max.X", "Max.Y" },
		["PhysicalProperties"] = { "Density", "Elasticity", "ElasticityWeight", "Friction", "FrictionWeight" },
		["Ray"] = {
			"Origin",
			"Origin.X",
			"Origin.Y",
			"Origin.Z",
			"Direction",
			"Direction.X",
			"Direction.Y",
			"Direction.Z",
		},
		["NumberRange"] = { "Min", "Max" },
		["Faces"] = { "Back", "Bottom", "Front", "Left", "Right", "Top" },
		["Axes"] = { "X", "Y", "Z" },
	}

	Properties.ConflictIgnore = {
		["BasePart"] = {
			["ResizableFaces"] = true,
		},
	}

	Properties.RoundableTypes = {
		["float"] = true,
		["double"] = true,
		["Color3"] = true,
		["UDim"] = true,
		["UDim2"] = true,
		["Vector2"] = true,
		["Vector3"] = true,
		["NumberRange"] = true,
		["Rect"] = true,
		["NumberSequence"] = true,
		["ColorSequence"] = true,
		["Ray"] = true,
		["CFrame"] = true,
	}

	Properties.TypeNameConvert = {
		["number"] = "double",
		["boolean"] = "bool",
	}

	Properties.ToNumberTypes = {
		["int"] = true,
		["int64"] = true,
		["float"] = true,
		["double"] = true,
	}

	Properties.DefaultPropValue = {
		string = "",
		bool = false,
		double = 0,
		UDim = UDim.new(0, 0),
		UDim2 = UDim2.new(0, 0, 0, 0),
		BrickColor = BrickColor.new("Medium stone grey"),
		Color3 = Color3.new(1, 1, 1),
		Vector2 = Vector2.new(0, 0),
		Vector3 = Vector3.new(0, 0, 0),
		NumberSequence = NumberSequence.new(1),
		ColorSequence = ColorSequence.new(Color3.new(1, 1, 1)),
		NumberRange = NumberRange.new(0),
		Rect = Rect.new(0, 0, 0, 0),
		CFrame = CFrame.new(),
		Font = Font.fromEnum(Enum.Font.SourceSans),
	}

	Properties.AllowedAttributeTypes = {
		"string",
		"boolean",
		"number",
		"UDim",
		"UDim2",
		"BrickColor",
		"Color3",
		"Vector2",
		"Vector3",
		"CFrame",
		"NumberSequence",
		"ColorSequence",
		"NumberRange",
		"Rect",
		"Font",
	}

	Properties.StringToValue = function(prop, text)
		return Apps.PropertyValueCodec.Parse(prop.ValueType.Name, text)
	end
	Properties.ValueToString = function(prop, value)
		return Apps.PropertyValueCodec.Format(prop.ValueType.Name, value)
	end

	Properties.GetIndexableProps = function(object, classData)
		return Apps.PropertySchema.GetReadableProperties(
			object,
			classData,
			Properties.IgnoreProps[classData.Name] or {}
		)
	end

	Properties.FindFirstObjWhichIsA = function(class)
		local classList = Properties.ClassLists[class] or {}
		if classList and #classList > 0 then
			return classList[1]
		end

		return nil
	end

	Properties.ComputeConflicts = function(p)
		local maxConflictCheck = Settings.Properties.MaxConflictCheck
		local sList = Explorer.Selection.List
		local classLists = Properties.ClassLists
		local stringSplit = string.split
		local t_clear = table.clear
		local conflictIgnore = Properties.ConflictIgnore
		local conflictMap = {}
		local propList = p and { p } or props

		if p then
			local gName = p.Class .. "." .. p.Name
			autoUpdateObjs[gName] = nil
			local subProps = Properties.ConflictSubProps[p.ValueType.Name] or {}
			for i = 1, #subProps do
				autoUpdateObjs[gName .. "." .. subProps[i]] = nil
			end
		else
			table.clear(autoUpdateObjs)
		end

		if #sList > 0 then
			for i = 1, #propList do
				local prop = propList[i]
				local propName, propClass = prop.Name, prop.Class
				local typeData = prop.RootType or prop.ValueType
				local typeName = typeData.Name
				local attributeName = prop.AttributeName
				local gName = propClass .. "." .. propName

				local checked = 0
				local subProps = Properties.ConflictSubProps[typeName] or {}
				local subPropCount = #subProps
				local toCheck = subPropCount + 1
				local conflictsFound = 0
				local indexNames, firstComponents = {}, {}
				local ignored = conflictIgnore[propClass] and conflictIgnore[propClass][propName]
				local truthyCheck = (typeName == "PhysicalProperties")
				local isAttribute = prop.IsAttribute
				local isMultiType = prop.MultiType

				t_clear(conflictMap)

				if not isMultiType then
					local firstVal, firstObj, firstSet
					local classList = classLists[prop.Class] or {}
					for c = 1, #classList do
						local obj = classList[c]
						if not firstSet then
							if isAttribute then
								firstVal = getAttribute(obj, attributeName)
								if firstVal ~= nil then
									firstObj = obj
									firstSet = true
								end
							else
								firstVal = obj[propName]
								firstObj = obj
								firstSet = true
							end
							if ignored then
								break
							end
						else
							local propVal, skip
							if isAttribute then
								propVal = getAttribute(obj, attributeName)
								if propVal == nil then
									skip = true
								end
							else
								propVal = obj[propName]
							end

							if not skip then
								if not conflictMap[1] then
									if truthyCheck then
										if (firstVal and true or false) ~= (propVal and true or false) then
											conflictMap[1] = true
											conflictsFound = conflictsFound + 1
										end
									elseif firstVal ~= propVal then
										conflictMap[1] = true
										conflictsFound = conflictsFound + 1
									end
								end

								if subPropCount > 0 and firstVal ~= propVal then
									for sPropInd = 1, subPropCount do
										local mapInd = sPropInd + 1
										if conflictMap[mapInd] then continue end
										local indexes = indexNames[sPropInd]
										if not indexes then
											indexes = stringSplit(subProps[sPropInd], ".")
											indexNames[sPropInd] = indexes
											local component = firstVal
											for _, name in indexes do
												if not component then break end
												component = component[name]
											end
											firstComponents[sPropInd] = component
										end

										local component = propVal
										for _, name in indexes do
											if not component then break end
											component = component[name]
										end
										if firstComponents[sPropInd] ~= component then
											conflictMap[mapInd] = true
											conflictsFound = conflictsFound + 1
										end
									end
								end

								if conflictsFound == toCheck then
									break
								end
							end
						end

						checked = checked + 1
						if checked == maxConflictCheck then
							break
						end
					end

					if not conflictMap[1] then
						autoUpdateObjs[gName] = firstObj
					end
					for sPropInd = 1, subPropCount do
						if not conflictMap[sPropInd + 1] then
							autoUpdateObjs[gName .. "." .. subProps[sPropInd]] = firstObj
						end
					end
				end
			end
		end

		if p then
			Properties.Refresh()
		end
	end

	local pluginRows = {}
	local pluginRefreshPending = false
	local function refreshPluginRows()
		if not window or pluginRefreshPending then return end
		pluginRefreshPending = true
		task.defer(function()
			pluginRefreshPending = false
			if Main.Alive then Properties.ShowExplorerProps() end
		end)
	end

	function Properties.RegisterPluginRow(owner, id, name, read)
		for _, row in ipairs(pluginRows) do
			assert(row.Owner ~= owner or row.ID ~= id, "Duplicate property row ID.")
		end
		local row = { Owner = owner, ID = id, Name = name, Read = read }
		table.insert(pluginRows, row)
		refreshPluginRows()
		return function()
			local index = table.find(pluginRows, row)
			if index then
				table.remove(pluginRows, index)
				row.Read = nil
				refreshPluginRows()
			end
		end, refreshPluginRows
	end

	local function appendPluginRows(selection)
		if #pluginRows == 0 or #selection == 0 then return end
		local objects = table.create(#selection)
		for i, node in ipairs(selection) do objects[i] = node.Obj end
		table.freeze(objects)
		for _, row in ipairs(table.clone(pluginRows)) do
			if not row.Read then continue end
			local thread = coroutine.create(row.Read)
			local ok, value = coroutine.resume(thread, objects)
			if coroutine.status(thread) ~= "dead" then
				coroutine.close(thread)
			elseif ok and row.Read and type(value) == "string" then
				props[#props + 1] = {
					Class = "Plugin/" .. row.Owner, Name = row.Name, Category = "Plugins",
					SpecialRow = "Plugin", PluginText = row.Name .. ": " .. value, Tags = {},
				}
			end
		end
	end

	local emptyAttributes = {}
	local tagWitnesses = setmetatable({}, { __mode = "v" })
	local attributeJob, signalProbe, probeValue, probeSeen
	local function clearAttributeCache()
		attributeJob = nil
		for node, connection in emptyAttributes do
			connection:Disconnect()
			emptyAttributes[node] = nil
		end
	end
	local function prepareAttributeCache(list, enabled)
		if not enabled or #list < 512 or not Explorer.Selection.Map then
			if next(emptyAttributes) or attributeJob then clearAttributeCache() end
			return
		end
		if not signalProbe then
			signalProbe = Instance.new("Folder")
			signalProbe.AttributeChanged:Connect(function() probeSeen = probeValue end)
			Main.AddCleanup(function()
				clearAttributeCache()
				signalProbe:Destroy()
			end)
		end
		probeValue = not probeValue
		probeSeen = nil
		signalProbe:SetAttribute("Immediate", probeValue)
		if probeSeen ~= probeValue then
			clearAttributeCache()
			return
		end
		local job = {}
		attributeJob = job
		task.defer(function()
			if attributeJob ~= job then return end
			local members = Explorer.Selection.Map
			local deadline = os.clock() + 0.001
			local function current(i)
				if i % 64 == 0 and os.clock() >= deadline then
					task.wait()
					deadline = os.clock() + 0.001
				end
				return attributeJob == job
			end
			local count = 0
			for node, connection in emptyAttributes do
				if not members[node] then
					connection:Disconnect()
					emptyAttributes[node] = nil
				end
				count += 1
				if not current(count) then return end
			end
			for i, node in job do
				if not current(i) then return end
				if not emptyAttributes[node] and members[node] and not next(node.Obj:GetAttributes()) then
					emptyAttributes[node] = node.Obj.AttributeChanged:Once(function()
						emptyAttributes[node] = nil
					end)
				end
			end
			attributeJob = nil
		end)
		return emptyAttributes, job
	end

	Properties.ShowExplorerProps = function()
		if Properties.CancelAttributeRename then
			Properties.CancelAttributeRename()
		end
		local sList = Explorer.Selection.List
		if inputProp and inputSelection ~= sList then
			inputProp = nil
			inputSelection = nil
			if inputTextBox and inputTextBox:IsFocused() then
				inputTextBox:ReleaseFocus()
			end
		end
		if Explorer.HasInferredSelection and Explorer.HasInferredSelection() then
			clearAttributeCache()
			table.clear(props)
			local objects = {}
			for _, node in ipairs(sList) do
				if node.Inferred then
					objects[#objects + 1] = node.Obj
				end
			end
			for _, name in ipairs({ "Inferred", "ServerPath", "ClassHint", "ClassStatus", "Evidence" }) do
				props[#props + 1] = {
					IsAttribute = true,
					Name = "ATTR_" .. name,
					AttributeName = name,
					DisplayName = name,
					Class = "Instance",
					Category = "Inference",
					Tags = { ReadOnly = true },
					ValueType = { Name = name == "Inferred" and "bool" or "string", Category = "Other" },
				}
			end
			Properties.ClassLists = { Instance = objects }
			if window then
				local obj = #objects == 1 and objects[1]
				window:SetTitle(obj and ("Properties - " .. obj.ClassName .. ' "' .. obj.Name .. '"') or "Properties")
			end
			Properties.ComputeConflicts()
			Properties.Update()
			Properties.Refresh()
			return
		end
		if window then
			local obj = #sList == 1 and sList[1].Obj
			window:SetTitle(obj and ("Properties - " .. obj.ClassName .. ' "' .. obj.Name .. '"') or "Properties")
		end
		local classesByType = {}
		local typeCounts, totals = {}, {}
		local objects = table.create(#sList)
		local propCount = 1
		local showDeprecated, showHidden = Settings.Properties.ShowDeprecated, Settings.Properties.ShowHidden
		local Classes = API.Classes
		local classLists = {}
		local lower = string.lower
		local RMDCustomOrders = RMD.PropertyOrders
		local getAttributes = game.GetAttributes
		local maxAttrs = Settings.Properties.MaxAttributes
		local showingAttrs = Settings.Properties.ShowAttributes
		local noAttributes, warming = prepareAttributeCache(sList, showingAttrs and maxAttrs > 0)
		local foundAttrs = {}
		local collection = service.CollectionService
		local getTags = collection.GetTags
		local foundTags, tagNames = {}, {}
		local selected = Explorer.Selection.Map
		local indexedTags = #sList >= 512 and selected and Explorer.GetNodes and collection:GetAllTags()
		local indexedNodes
		if indexedTags and #indexedTags <= math.min(64, #sList // 32) then
			indexedNodes = Explorer.GetNodes()
			local previousWitnesses = tagWitnesses
			tagWitnesses = setmetatable({}, { __mode = "v" })
			for _, tag in indexedTags do
				local witness = previousWitnesses[tag]
				if witness and selected[indexedNodes[witness]] and witness:HasTag(tag) then
					tagWitnesses[tag] = witness
					foundTags[tag] = true
					tagNames[#tagNames + 1] = tag
					continue
				end
				for _, obj in collection:GetTagged(tag) do
					if selected[indexedNodes[obj]] then
						tagWitnesses[tag] = obj
						foundTags[tag] = true
						tagNames[#tagNames + 1] = tag
						break
					end
				end
			end
		else
			indexedTags = nil
		end
		local lastParent, parentInGame
		local attrCount = 0
		local typeof = typeof
		local typeNameConvert = Properties.TypeNameConvert

		table.clear(props)

		local function collectClass(class, obj)
			local ancestors = {}
			classesByType[class] = ancestors
			local apiClass = Classes[class]
			while apiClass do
				local APIClassName = apiClass.Name
				if not totals[APIClassName] then
					totals[APIClassName] = 0
					local apiProps = indexableProps[APIClassName]
					if not apiProps then
						apiProps = Properties.GetIndexableProps(obj, apiClass)
						indexableProps[APIClassName] = apiProps
					end

					for i = 1, #apiProps do
						local prop = apiProps[i]
						local tags = prop.Tags
						if
							(not tags.Deprecated or showDeprecated)
							and (not tags.Hidden or showHidden)
							and Apps.ReflectionService.IsVisible(APIClassName, prop.Name, showHidden, showDeprecated)
						then
							props[propCount] = prop
							propCount = propCount + 1
						end
					end
				end
				ancestors[#ancestors + 1] = APIClassName
				apiClass = apiClass.Superclass
			end
		end

		for i = 1, #sList do
			local node = sList[i]
			local obj = node.Obj
			local class = node.Class
			if not class then
				class = obj.ClassName
				node.Class = class
			end

			objects[i] = obj
			if not typeCounts[class] then
				collectClass(class, obj)
				typeCounts[class] = 1
			else
				typeCounts[class] += 1
			end

			if indexedTags then
				local parent = obj.Parent
				if parent ~= lastParent then
					lastParent = parent
					parentInGame = parent and (parent == game or parent:IsDescendantOf(game))
				end
			end
			if not parentInGame or indexedNodes[obj] ~= node then
				for _, tag in getTags(collection, obj) do
					if not foundTags[tag] then
						foundTags[tag] = true
						tagNames[#tagNames + 1] = tag
					end
				end
			end

			local empty = noAttributes and noAttributes[node]
			if showingAttrs and attrCount < maxAttrs and not (empty and (parentInGame or empty.Connected)) then
				local attrs = getAttributes(obj)
				if warming and not next(attrs) then warming[#warming + 1] = node end
				for name, val in pairs(attrs) do
					local typ = typeof(val)
					if not foundAttrs[name] then
						local category = (typ == "Instance" and "Class") or (typ == "EnumItem" and "Enum") or "Other"
						local valType = { Name = typeNameConvert[typ] or typ, Category = category }
						local attrProp = {
							IsAttribute = true,
							Name = "ATTR_" .. name,
							AttributeName = name,
							DisplayName = name,
							Class = "Instance",
							ValueType = valType,
							Category = "Attributes",
							Tags = {},
						}
						props[propCount] = attrProp
						propCount = propCount + 1
						attrCount = attrCount + 1
						foundAttrs[name] = { typ, attrProp }
						if attrCount == maxAttrs then
							break
						end
					elseif foundAttrs[name][1] ~= typ then
						foundAttrs[name][2].MultiType = true
						foundAttrs[name][2].Tags.ReadOnly = true
						foundAttrs[name][2].ValueType = { Name = "string" }
					end
				end
			end
		end

		for class, count in typeCounts do
			for _, name in classesByType[class] do
				totals[name] += count
			end
		end

		local listsByType = {}
		local needsLists = false
		for class, ancestors in classesByType do
			local lists = {}
			local parentList, parentCount
			for i = #ancestors, 1, -1 do
				local name = ancestors[i]
				local count = totals[name]
				if count == #objects then
					parentList = objects
				elseif count ~= parentCount then
					local list = classLists[name]
					if not list then list = table.create(count) end
					parentList = list
					lists[#lists + 1] = list
					needsLists = true
				end
				classLists[name] = parentList
				parentCount = count
			end
			listsByType[class] = lists
		end
		if needsLists then
			for i = 1, #objects do
				local obj = objects[i]
				for _, list in listsByType[sList[i].Class] do
					list[#list + 1] = obj
				end
			end
		end

		table.sort(props, function(a, b)
			if a.Category ~= b.Category then
				return (categoryOrder[a.Category] or 9999) < (categoryOrder[b.Category] or 9999)
			else
				local aOrder = (RMDCustomOrders[a.Class] and RMDCustomOrders[a.Class][a.Name]) or 9999999
				local bOrder = (RMDCustomOrders[b.Class] and RMDCustomOrders[b.Class][b.Name]) or 9999999
				if aOrder ~= bOrder then
					return aOrder < bOrder
				else
					return lower(a.Name) < lower(b.Name)
				end
			end
		end)

		Properties.ClassLists = classLists
		Properties.ComputeConflicts()
		if #sList > 0 and attrCount == 0 then
			props[#props + 1] =
				{ Category = "Attributes", Class = "", Name = "", SpecialRow = "EmptyAttributes", Tags = {} }
		end

		if #sList > 0 then
			table.sort(tagNames)
			local insertAt = #props + 1
			for i, prop in ipairs(props) do
				if prop.Category == "Attributes" then
					insertAt = i
					break
				end
			end
			if #tagNames == 0 then
				table.insert(
					props,
					insertAt,
					{ Category = "Tags", Class = "", Name = "", SpecialRow = "EmptyTags", Tags = {} }
				)
			else
				for i, tag in ipairs(tagNames) do
					table.insert(
						props,
						insertAt + i - 1,
						{ Category = "Tags", Class = "", Name = tag, TagName = tag, SpecialRow = "Tag", Tags = {} }
					)
				end
			end
		end
		appendPluginRows(sList)
		Properties.Update()
		Properties.Refresh()
	end

	local function getWindowSize()
		local main = window.GuiElems.Main
		local size = main.Size
		if size.X.Scale == 0 and size.Y.Scale == 0 then
			return size.X.Offset, size.Y.Offset
		end
		local absolute = main.AbsoluteSize
		return absolute.X, absolute.Y
	end
	Properties.UpdateView = function(width, height)
		if width == nil then
			width, height = getWindowSize()
		end
		viewWindowWidth, viewWindowHeight = width, height
		local rail = View.ScrollRail
		local totalWidth = Properties.ViewWidth + Properties.MinInputWidth
		local vertical, horizontal
		viewportWidth, viewportHeight, vertical, horizontal = View.Viewport(
			width,
			math.max(0, height - (window.TitleBarHeight or View.HeaderHeight) - View.ToolbarHeight),
			totalWidth,
			Properties.ViewLayout.Total,
			Settings.Properties.ScaleType == 0
		)

		local xInset, yInset = vertical and rail or 0, horizontal and rail or 0
		scrollV.VisibleSpace = viewportHeight
		scrollV.TotalSpace = Properties.ViewLayout.Total
		scrollH.VisibleSpace = viewportWidth
		scrollH.TotalSpace = totalWidth
		scrollV.TrackLength = math.max(0, viewportHeight - 2 * rail)
		scrollH.TrackLength = math.max(0, viewportWidth - 2 * rail)
		propsFrame.Size = UDim2.new(1, -xInset, 1, -View.ToolbarHeight - yInset)
		scrollV.Gui.Size = UDim2.new(0, rail, 1, -View.ToolbarHeight - yInset)
		scrollH.Gui.Size = UDim2.new(1, -xInset, 0, rail)
		scrollV.Gui.Visible, scrollH.Gui.Visible = vertical, horizontal
		window.GuiElems.Content.ScrollCorner.Visible = vertical and horizontal
		scrollV:Update()
		scrollH:Update()
		Properties.ScrollOffset = scrollV.Index
	end

	Properties.MakeSubProp = function(prop, subName, valueType, displayName)
		local subProp = {}
		for i, v in pairs(prop) do
			subProp[i] = v
		end
		subProp.RootType = subProp.RootType or subProp.ValueType
		subProp.ValueType = valueType
		subProp.SubName = subProp.SubName and (subProp.SubName .. subName) or subName
		subProp.DisplayName = displayName

		return subProp
	end

	Properties.GetExpandedProps = function(prop)
		local result = {}
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local makeSubProp = Properties.MakeSubProp

		if typeName == "Vector2" then
			result[1] = makeSubProp(prop, ".X", { Name = "float" })
			result[2] = makeSubProp(prop, ".Y", { Name = "float" })
		elseif typeName == "Vector3" then
			result[1] = makeSubProp(prop, ".X", { Name = "float" })
			result[2] = makeSubProp(prop, ".Y", { Name = "float" })
			result[3] = makeSubProp(prop, ".Z", { Name = "float" })
		elseif typeName == "CFrame" then
			result[1] = makeSubProp(prop, ".Position", { Name = "Vector3" })
			result[2] = makeSubProp(prop, ".RightVector", { Name = "Vector3" })
			result[3] = makeSubProp(prop, ".UpVector", { Name = "Vector3" })
			result[4] = makeSubProp(prop, ".LookVector", { Name = "Vector3" })
		elseif typeName == "UDim" then
			result[1] = makeSubProp(prop, ".Scale", { Name = "float" })
			result[2] = makeSubProp(prop, ".Offset", { Name = "int" })
		elseif typeName == "UDim2" then
			result[1] = makeSubProp(prop, ".X", { Name = "UDim" })
			result[2] = makeSubProp(prop, ".Y", { Name = "UDim" })
		elseif typeName == "Rect" then
			result[1] = makeSubProp(prop, ".Min.X", { Name = "float" }, "X0")
			result[2] = makeSubProp(prop, ".Min.Y", { Name = "float" }, "Y0")
			result[3] = makeSubProp(prop, ".Max.X", { Name = "float" }, "X1")
			result[4] = makeSubProp(prop, ".Max.Y", { Name = "float" }, "Y1")
		elseif typeName == "PhysicalProperties" then
			result[1] = makeSubProp(prop, ".Density", { Name = "float" })
			result[2] = makeSubProp(prop, ".Elasticity", { Name = "float" })
			result[3] = makeSubProp(prop, ".ElasticityWeight", { Name = "float" })
			result[4] = makeSubProp(prop, ".Friction", { Name = "float" })
			result[5] = makeSubProp(prop, ".FrictionWeight", { Name = "float" })
		elseif typeName == "Ray" then
			result[1] = makeSubProp(prop, ".Origin", { Name = "Vector3" })
			result[2] = makeSubProp(prop, ".Direction", { Name = "Vector3" })
		elseif typeName == "NumberRange" then
			result[1] = makeSubProp(prop, ".Min", { Name = "float" })
			result[2] = makeSubProp(prop, ".Max", { Name = "float" })
		elseif typeName == "Faces" then
			result[1] = makeSubProp(prop, ".Back", { Name = "bool" })
			result[2] = makeSubProp(prop, ".Bottom", { Name = "bool" })
			result[3] = makeSubProp(prop, ".Front", { Name = "bool" })
			result[4] = makeSubProp(prop, ".Left", { Name = "bool" })
			result[5] = makeSubProp(prop, ".Right", { Name = "bool" })
			result[6] = makeSubProp(prop, ".Top", { Name = "bool" })
		elseif typeName == "Axes" then
			result[1] = makeSubProp(prop, ".X", { Name = "bool" })
			result[2] = makeSubProp(prop, ".Y", { Name = "bool" })
			result[3] = makeSubProp(prop, ".Z", { Name = "bool" })
		end

		if prop.Name == "SoundId" and prop.Class == "Sound" then
			result[1] = Properties.SoundPreviewProp
		end

		return result
	end

	local createPropertyRow = Apps.PropertyRow.Create(Properties, {
		ViewList = viewList,
		Expanded = expanded,
		Checkboxes = checkboxes,
		GetFrame = function()
			return propsFrame
		end,
		GetInputProp = function()
			return inputProp
		end,
		SetInputProp = function(value)
			inputProp = value
		end,
	})

	Properties.Update = function()
		if valueEditors then
			valueEditors.Cancel()
		end
		table.clear(viewList)

		local nameWidthCache = Properties.NameWidthCache
		local lastCategory
		local count = 1
		local maxWidth, maxDepth = 0, 1

		local textServ = service.TextService
		local getTextSize = textServ.GetTextSize
		local font = propertyFont
		local size = Vector2.new(math.huge, 20)
		local stringSplit = string.split
		local entryIndent = Properties.EntryIndent
		local isFirstScaleType = Settings.Properties.ScaleType == 0
		local find, lower = string.find, string.lower
		local searchText = (#Properties.SearchText > 0 and lower(Properties.SearchText))

		local function recur(props, depth)
			for i = 1, #props do
				local prop = props[i]
				local propName = prop.Name
				local subName = prop.SubName
				local category = prop.Category

				local visible
				if searchText and depth == 1 then
					if find(lower(propName), searchText, 1, true) then
						visible = true
					end
				else
					visible = true
				end

				if visible and propName == "UniqueId" and not prop.IsAttribute and not prop.SpecialRow then
					local objects = Properties.ClassLists[prop.Class] or {}
					if #objects == 0 then
						visible = false
					end
					for _, obj in ipairs(objects) do
						if Properties.GetPropVal(prop, obj) == nil then
							visible = false
							break
						end
					end
				end

				if visible and lastCategory ~= category then
					viewList[count] = { CategoryName = category }
					count = count + 1
					lastCategory = category
				end

				if expanded["CAT_" .. category] and visible then
					if depth > 1 then
						prop.Depth = depth
						if depth > maxDepth then
							maxDepth = depth
						end
					end

					if isFirstScaleType then
						local nameArr = subName and stringSplit(subName, ".")
						local displayName = prop.DisplayName or (nameArr and nameArr[#nameArr]) or propName

						local nameWidth = nameWidthCache[displayName]
						if not nameWidth then
							nameWidth = getTextSize(textServ, displayName, 14, font, size).X
							nameWidthCache[displayName] = nameWidth
						end

						local totalWidth = nameWidth + entryIndent * depth
						if totalWidth > maxWidth then
							maxWidth = totalWidth
						end
					end

					viewList[count] = prop
					count = count + 1

					local fullName = prop.Class .. "." .. prop.Name .. (prop.SubName or "")
					if not prop.SpecialRow and expanded[fullName] then
						local nextDepth = depth + 1
						local expandedProps = Properties.GetExpandedProps(prop)
						if #expandedProps > 0 then
							recur(expandedProps, nextDepth)
						end
					end
				end
			end
		end
		recur(props, 1)
		Properties.ViewLayout = View.Layout(viewList)

		inputProp = nil
		Properties.ViewWidth = maxWidth + 9 + Properties.EntryOffset
		Properties.UpdateView()
	end

	Properties.NewPropEntry = function(index)
		return createPropertyRow(index)
	end

	Properties.GetSoundPreviewEntry = function()
		for i = 1, #viewList do
			if viewList[i] == Properties.SoundPreviewProp then
				return propEntries[i - Properties.Index]
			end
		end
	end

	Properties.SetSoundPreview = function(soundObj, noplay)
		local sound = Properties.PreviewSound
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "Preview"
			sound.Paused:Connect(function()
				local entry = Properties.GetSoundPreviewEntry()
				if entry then
					Main.MiscIcons:DisplayByKey(entry.GuiElems.SoundPreview.ControlButton.Icon, "Play")
				end
			end)
			sound.Resumed:Connect(function()
				Properties.Refresh()
			end)
			sound.Ended:Connect(function()
				local entry = Properties.GetSoundPreviewEntry()
				if entry then
					entry.GuiElems.SoundPreviewSlider.Position = UDim2.new(0, -4, 0, -8)
				end
				Properties.Refresh()
			end)
			sound.Parent = window.Gui
			Properties.PreviewSound = sound
		end

		if not soundObj then
			sound:Pause()
		else
			local newId = sound.SoundId ~= soundObj.SoundId
			sound.SoundId = soundObj.SoundId
			sound.PlaybackSpeed = soundObj.PlaybackSpeed
			sound.Volume = soundObj.Volume
			if newId then
				sound.TimePosition = 0
			end
			if not noplay then
				sound:Resume()
			end

			coroutine.wrap(function()
				local previewTime = tick()
				Properties.SoundPreviewTime = previewTime
				while previewTime == Properties.SoundPreviewTime and sound.Playing do
					local entry = Properties.GetSoundPreviewEntry()
					if entry then
						local tl = sound.TimeLength
						local perc = sound.TimePosition / (tl == 0 and 1 or tl)
						entry.GuiElems.SoundPreviewSlider.Position = UDim2.new(perc, -4, 0, -8)
					end
					Lib.FastWait()
				end
			end)()
			Properties.Refresh()
		end
	end

	Properties.DisplayTagMenu = function(anchor)
		local menu = Properties.TagMenu
		if not menu then
			menu = Lib.ContextMenu.new()
			menu.Iconless = true
			menu.SearchEnabled = true
			menu.Width = 240
			menu.MaxHeight = 260
			menu.GuiElems.SearchBar.PlaceholderText = "Add a tag"
			Properties.TagMenu = menu
			local function addTag(tag)
				if not tag or tag:match("^%s*$") then
					return
				end
				Apps.History.Run("Add tag", function()
					for _, node in ipairs(menu.Targets or {}) do
						Apps.History.Tag(node.Obj, tag, true)
					end
				end)
				menu:Hide()
				Properties.ShowExplorerProps()
			end
			menu.AddTag = addTag
			menu.GuiElems.SearchBar.FocusLost:Connect(function(enter)
				if enter then
					addTag(menu.GuiElems.SearchBar.Text)
				end
			end)
		end
		menu.Targets = table.clone(Explorer.Selection.List)
		menu:Clear()
		local tags = service.CollectionService:GetAllTags()
		table.sort(tags)
		for _, tag in ipairs(tags) do
			menu:Add({
				Name = tag,
				OnClick = function()
					menu.AddTag(tag)
				end,
			})
		end
		if #tags == 0 then
			menu:Add({ Name = "Type a tag and press Enter", Disabled = true })
		end
		menu:Show(
			anchor.AbsolutePosition.X + anchor.AbsoluteSize.X - menu.Width,
			anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y
		)
	end

	Properties.CancelAttributeRename = function()
		local state = Properties.AttributeRename
		if not state then
			return
		end
		Properties.AttributeRename = nil
		state.Label.Visible = true
		state.Box:Destroy()
	end

	Properties.BeginAttributeRename = function(prop)
		Properties.CancelAttributeRename()
		local index = table.find(viewList, prop)
		local rowIndex = index and index - Properties.Index
		local row = rowIndex and propEntries[rowIndex]
		if not row or not prop.IsAttribute then
			return
		end
		local label = row.GuiElems.PropName
		local box = createSimple("TextBox", {
			Name = "AttributeNameEditor",
			Parent = label.Parent,
			Position = label.Position,
			Size = label.Size,
			BackgroundColor3 = Settings.Theme.TextBox,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = prop.AttributeName,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		})
		Lib.StudioText(box)
		box.TextSize = 12
		label.Visible = false
		local state = { Prop = prop, RowIndex = rowIndex, Label = label, Box = box }
		Properties.AttributeRename = state
		box.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				Properties.CancelAttributeRename()
			end
		end)
		box.FocusLost:Connect(function()
			if Properties.AttributeRename ~= state then
				return
			end
			local name = box.Text
			local count = utf8.len(name) or #name
			local valid = count > 0 and count <= 100 and name:sub(1, 3) ~= "RBX"
			if name ~= prop.AttributeName then
				for _, node in ipairs(Explorer.Selection.List) do
					if node.Obj:GetAttribute(name) ~= nil then
						valid = false
						break
					end
				end
			end
			if not valid then
				box.TextColor3 = Color3.fromRGB(255, 155, 145)
				task.defer(function()
					if Properties.AttributeRename == state then
						box:CaptureFocus()
					end
				end)
				return
			end
			Properties.CancelAttributeRename()
			if name == prop.AttributeName then
				return
			end
			local renamed = table.clone(prop)
			renamed.Name = "ATTR_" .. name
			renamed.AttributeName = name
			renamed.DisplayName = name
			Properties.SetProp(renamed, Properties.DefaultPropValue[prop.ValueType.Name], true, prop)
			Properties.ShowExplorerProps()
		end)
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end

	Properties.DisplayAttributeContext = function(prop, anchor)
		local context = Properties.AttributeContext
		if not context then
			context = Lib.ContextMenu.new()
			context.Iconless = true
			context.Width = 100
			Properties.AttributeContext = context
			context.GuiElems.Entry.Size = UDim2.new(1, 0, 0, 22)
		end
		context:Clear()

		context:Add({
			Name = "Rename",
			OnClick = function()
				Properties.BeginAttributeRename(prop)
			end,
		})
		context:Add({
			Name = "Delete",
			OnClick = function()
				Properties.SetProp(prop, nil, true)
				Properties.ShowExplorerProps()
			end,
		})

		if anchor then
			context:Show(
				anchor.AbsolutePosition.X + anchor.AbsoluteSize.X - context.Width,
				anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y
			)
		else
			context:Show()
		end
	end

	Properties.DisplayAddAttributeWindow = function(editAttr)
		local d = Apps.StudioPopup.Open(if editAttr then "Rename Attribute" else "Add Attribute",182,true)
		d.label(d.panel,"Name",30,46,36,21,12,false)
		local box = d.make("TextBox",d.panel,{Name="NameBox",Position=UDim2.fromOffset(66,46),Size=UDim2.fromOffset(156,21),
			Text=if editAttr then editAttr.AttributeName else "",TextSize=12,Font=Enum.Font.BuilderSans,
			TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false,BorderSizePixel=0,
			TextColor3=Color3.fromRGB(220,222,228),BackgroundColor3=Color3.fromRGB(40,41,49)})
		d.make("UIPadding",box,{PaddingLeft=UDim.new(0,4)})
		local stroke = d.make("UIStroke",box,{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Thickness=1,Color=Settings.Theme.Outline2})
		box.Focused:Connect(function() stroke.Color = Settings.Theme.Focus end)
		box.FocusLost:Connect(function() stroke.Color = Settings.Theme.Outline2 end)
		local count = d.label(d.panel,"",66,70,156,20,12,false)
		local chooser
		if not editAttr then
			d.label(d.panel,"Type",30,94,36,21,12,false)
			chooser = Properties.AttributeTypeChooser
			if not chooser then
				chooser = Lib.DropDown.new()
				chooser.CanBeEmpty = false
				chooser:SetOptions(Properties.AllowedAttributeTypes)
				Properties.AttributeTypeChooser = chooser
				chooser.Gui.BorderSizePixel = 0
				chooser.Gui.BackgroundColor3 = Color3.fromRGB(40,41,49)
				chooser.GuiElems.Label.TextSize = 12
				chooser.GuiElems.Label.Position = UDim2.fromOffset(4,0)
				chooser.GuiElems.Label.Size = UDim2.new(1,-38,1,0)
			end
			chooser:SetSelected(1)
			chooser.Gui.Position = UDim2.fromOffset(66,94)
			chooser.Gui.Size = UDim2.fromOffset(156,21)
			chooser.Gui.Parent = d.panel
			d.onClose = function()
				chooser.Context:Hide()
				chooser.Gui.Parent = nil
			end
		end
		d.bindForm(box,"Save",function()
			local n = utf8.len(box.Text) or #box.Text
			count.Text = tostring(n) .. "/100"
			return n > 0 and n <= 100
		end,function()
			local name = box.Text
			assert(name:sub(1,3) ~= "RBX","Names cannot begin with 'RBX'.")
			local typ = chooser and chooser.Selected
			local valType = if editAttr then editAttr.ValueType else {Name=Properties.TypeNameConvert[typ] or typ,Category="DataType"}
			local prop = {IsAttribute=true,Name="ATTR_" .. name,AttributeName=name,DisplayName=name,
				Class="Instance",ValueType=valType,Category="Attributes",Tags={}}
			Settings.Properties.ShowAttributes = true
			Properties.SetProp(prop,Properties.DefaultPropValue[valType.Name],true,editAttr)
			Properties.ShowExplorerProps()
		end)
		box:CaptureFocus()
	end

	Properties.IsTextEditable = function(prop)
		local typeData = prop.ValueType
		local typeName = typeData.Name

		return typeName ~= "bool"
			and typeData.Category ~= "Enum"
			and typeData.Category ~= "Class"
			and typeName ~= "BrickColor"
	end

	local propertyReader = Apps.PropertyReader.Create({
		TypeNames = Properties.TypeNameConvert,
		ReadHiddenProperty = type(gethiddenproperty) == "function" and gethiddenproperty or nil,
	})
	Properties.GetPropVal = propertyReader.Read
	Properties.GetFirstPropVal = function(property)
		return propertyReader.Read(property, Properties.FindFirstObjWhichIsA(property.Class))
	end
	valueEditors = Apps.PropertyValueEditors.Create({
		Entries = propEntries,
		GetInputProp = function()
			return inputProp
		end,
		SetInputProp = function(property)
			inputProp = property
		end,
		ReadFirst = Properties.GetFirstPropVal,
		Commit = function(property, value)
			Properties.SetProp(property, value)
		end,
	})
	Properties.DisplayEnumDropdown = valueEditors.ShowEnum
	Properties.DisplayBrickColorEditor = valueEditors.ShowBrickColor
	Properties.DisplayColorEditor = valueEditors.ShowColor
	Properties.DisplayNumberSequenceEditor = valueEditors.ShowNumberSequence
	Properties.DisplayColorSequenceEditor = valueEditors.ShowColorSequence

	Properties.SelectObject = function(obj)
		if inputProp and inputSelection ~= Explorer.Selection.List then
			return false
		end
		if
			inputProp
			and inputProp.ValueType.Category == "Class"
			and Explorer.IsReadOnlyInferenceObject
			and Explorer.IsReadOnlyInferenceObject(obj)
		then
			Properties.CancelObjectSelection()
			return true
		end
		if inputProp and inputProp.ValueType.Category == "Class" then
			local prop = inputProp
			inputProp = nil

			if isa(obj, prop.ValueType.Name) then
				Properties.SetProp(prop, obj)
			else
				Properties.Refresh()
			end

			return true
		end

		return false
	end

	Properties.DisplayProp = Apps.PropertyValueCell.Create({
		Entries = propEntries,
		Checkboxes = checkboxes,
		AutoUpdateObjs = autoUpdateObjs,
		Colors = Colors,
		GetInputProp = function()
			return inputProp
		end,
		ReadValue = Properties.GetPropVal,
		FormatValue = Properties.ValueToString,
		RoundableTypes = Properties.RoundableTypes,
		IsSoundPlaying = function()
			return Properties.PreviewSound and Properties.PreviewSound.Playing
		end,
	})

	local function disconnectPropertyRow(entry)
		if entry.ValueConnection then
			entry.ValueConnection:Disconnect()
			entry.ValueConnection = nil
		end
		if entry.ValueUpdate then
			entry.ValueUpdate:Cancel()
			entry.ValueUpdate = nil
		end
	end
	Properties.Refresh = function(layoutOnly)
		local first, last, offset =
			Properties.ViewLayout:Visible(Properties.ScrollOffset, viewportHeight or math.max(0, propsFrame.AbsoluteSize.Y))
		Properties.Index = first - 1
		Properties.ScrollOffset = offset
		local rename = Properties.AttributeRename
		if rename and viewList[rename.RowIndex + Properties.Index] ~= rename.Prop then
			Properties.CancelAttributeRename()
		end
		local maxEntries = math.max(0, last - first + 1)
		local maxX = viewportWidth or propsFrame.AbsoluteSize.X
		local valueWidth = math.max(Properties.MinInputWidth, maxX - Properties.ViewWidth)
		local inputPropVisible = false
		local isa = game.IsA
		local UDim2 = UDim2
		local stringSplit = string.split
		local scaleType = Settings.Properties.ScaleType
		local column = math.clamp(
			math.floor(maxX * Properties.ColumnRatio + 0.5),
			math.min(80, maxX / 2),
			math.max(maxX / 2, maxX - 80)
		)
		if columnSplitter then
			columnSplitter:Layout(scaleType == 0 and Properties.ViewWidth - scrollH.Index or column, #viewList > 0)
		end
		local function bindingObject(prop)
			if not prop or prop.CategoryName or prop.SpecialRow then
				return nil
			end
			return autoUpdateObjs[prop.Class .. "." .. prop.Name .. (prop.SubName or "")]
		end
		Properties.FullNameFrame.Visible = false
		Properties.FullNameFrameAttach.Disable()

		for i = 1, maxEntries do
			local entryData = propEntries[i]
			if not propEntries[i] then
				entryData = Properties.NewPropEntry(i)
				propEntries[i] = entryData
			end

			local entry = entryData.Gui
			local guiElems = entryData.GuiElems
			local nameFrame = guiElems.NameFrame
			local propNameLabel = guiElems.PropName
			local valueFrame = guiElems.ValueFrame
			local expand = guiElems.Expand
			local valueBox = guiElems.ValueBox
			local propNameBox = guiElems.PropName
			local rightButton = guiElems.RightButton
			local editAttributeButton = guiElems.EditAttributeButton
			local toggleAttributes = guiElems.ToggleAttributes

			local prop = viewList[i + Properties.Index]
			local boundObject = bindingObject(prop)
			local reuse = layoutOnly == true and entryData.BoundProperty == prop and entryData.BoundObject == boundObject
			if not reuse then
				disconnectPropertyRow(entryData)
			end
			entryData.BoundProperty = prop
			entryData.BoundObject = boundObject
			if prop then
				local entryXOffset = (scaleType == 0 and scrollH.Index or 0)
				entry.Visible = true
				local rowHeight = View.RowHeight(prop)
				expand.Position = UDim2.new(0, -20, 0, math.floor((rowHeight - 20) / 2))
				entry.Position =
					UDim2.new(0, -entryXOffset, 0, Properties.ViewLayout.Offsets[i + Properties.Index] - offset)
				entry.Size = UDim2.new(
					scaleType == 0 and 0 or 1,
					scaleType == 0 and Properties.ViewWidth + valueWidth or 0,
					0,
					rowHeight
				)

				if prop.SpecialRow then
					if
						prop.SpecialRow == "EmptyAttributes"
						or prop.SpecialRow == "EmptyTags"
						or prop.SpecialRow == "Tag"
						or prop.SpecialRow == "Plugin"
					then
						nameFrame.Visible = false
						valueFrame.Visible = false
						guiElems.RowButton.Visible = false
						editAttributeButton.Visible = false
						toggleAttributes.Visible = false
						guiElems.EmptyAttributes.Visible = true
						guiElems.EmptyAttributes.Text = prop.PluginText or prop.TagName
							or (
								prop.SpecialRow == "EmptyTags" and "No Tags have been added yet"
								or "No Attributes have been added yet"
							)
						guiElems.EmptyAttributes.TextColor3 = (prop.PluginText or prop.TagName) and Colors.Text or Colors.ReadOnly
						guiElems.TagRemove.Visible = prop.TagName ~= nil
						entry.BackgroundColor3 = Colors.Surface
					end
				else
					guiElems.EmptyAttributes.Visible = false
					guiElems.TagRemove.Visible = false
					nameFrame.Visible = true
					guiElems.RowButton.Visible = false

					local depth = Properties.EntryIndent * (prop.Depth or 1)
					local leftOffset = depth + Properties.EntryOffset
					nameFrame.Position = UDim2.new(0, leftOffset, 0, 0)
					propNameLabel.Size = UDim2.new(1, -2 - (scaleType == 0 and 0 or 6), 1, 0)

					local gName = (prop.CategoryName and "CAT_" .. prop.CategoryName)
						or prop.Class .. "." .. prop.Name .. (prop.SubName or "")

					if prop.CategoryName then
						entry.BackgroundColor3 = Colors.Category
						valueFrame.Visible = false

						propNameBox.Text = prop.CategoryName
						propNameBox.Font = propertyBold
						propNameBox.TextSize = 14
						expand.Visible = true
						propNameBox.TextColor3 = Colors.Text
						nameFrame.BackgroundTransparency = 1
						nameFrame.Size = UDim2.new(1, -leftOffset, 1, 0)
						propNameLabel.Size = UDim2.new(1, -24, 1, 0)
						editAttributeButton.Visible = false

						local showingAttrs = Settings.Properties.ShowAttributes
						toggleAttributes.Position = UDim2.new(1, -20, 0.5, -8)
						toggleAttributes.Size = UDim2.fromOffset(16, 16)
						toggleAttributes.Text = ""
						toggleAttributes.TextColor3 = Colors.Text
						toggleAttributes.Visible = (prop.CategoryName == "Attributes" or prop.CategoryName == "Tags")
					else
						local propName = prop.Name
						local typeData = prop.ValueType
						local typeName = typeData.Name
						local tags = prop.Tags
						local propObj = boundObject

						local editingValue = inputProp
							and prop.IsAttribute
							and inputProp.Name == prop.Name
							and inputProp.Class == prop.Class
							and (inputProp.SubName or "") == (prop.SubName or "")
							and Properties.IsTextEditable(prop)
						local attributeOffset = (prop.IsAttribute and not editingValue and 20 or 0)
						editAttributeButton.Visible = (prop.IsAttribute and not prop.RootType and not editingValue)
						toggleAttributes.Visible = false

						if scaleType == 0 then
							nameFrame.Size = UDim2.new(0, Properties.ViewWidth - leftOffset - 1, 1, 0)
							valueFrame.Position = UDim2.new(0, Properties.ViewWidth, 0, 0)
							valueFrame.Size = UDim2.new(0, valueWidth - attributeOffset, 1, 0)
						else
							nameFrame.Size = UDim2.new(0, column - leftOffset - 1, 1, 0)
							valueFrame.Position = UDim2.fromOffset(column, 0)
							valueFrame.Size = UDim2.new(1, -column - attributeOffset, 1, 0)
						end

						local nameArr = stringSplit(gName, ".")
						propNameBox.Text = prop.DisplayName or nameArr[#nameArr]
						propNameBox.Font = propertyFont
						propNameBox.TextSize = 14
						valueBox.Font = propertyFont
						valueBox.TextSize = 14
						entry.BackgroundColor3 = Colors.Surface
						valueFrame.Visible = true

						expand.Visible = typeData.Category == "DataType" and Properties.ExpandableTypes[typeName]
							or Properties.ExpandableProps[gName]
						propNameBox.TextColor3 = tags.ReadOnly and Colors.ReadOnly or Colors.Text

						if not reuse then
							Properties.DisplayProp(prop, i)
						end
						if propObj and not reuse then
							local frameUpdate = Lib.FrameTask
								and service.RunService
								and service.RunService.RenderStepped
								and Lib.FrameTask(function()
									if window and not window:IsContentVisible() then
										return
									end
									local row = propEntries[i]
									if row and row.BoundProperty == prop and row.BoundObject == propObj then
										Properties.DisplayProp(prop, i)
									end
								end)
							local function changed()
								if frameUpdate then
									frameUpdate:Push(true)
								else
									Properties.DisplayProp(prop, i)
								end
							end
							local signal = prop.IsAttribute and getAttributeChangedSignal(propObj, prop.AttributeName)
								or getPropChangedSignal(propObj, propName)
							entryData.ValueConnection = signal:Connect(changed)
							entryData.ValueUpdate = frameUpdate
						end

						local beforeVisible = valueBox.Visible
						local inputFullName = inputProp
							and (inputProp.Class .. "." .. inputProp.Name .. (inputProp.SubName or ""))
						if gName == inputFullName then
							entry.BackgroundColor3 = Color3.fromRGB(24, 40, 98)
							nameFrame.BackgroundColor3 = Color3.fromRGB(24, 40, 98)
							nameFrame.BackgroundTransparency = 0
							if
								typeData.Category == "Class"
								or typeData.Category == "Enum"
								or typeName == "BrickColor"
							then
								valueFrame.BackgroundColor3 = Settings.Theme.TextBox
								valueFrame.BackgroundTransparency = 0
								valueBox.Visible = true
							else
								inputPropVisible = true
								local scale = 0
								local offset = (scaleType == 0 and Properties.ViewWidth - scrollH.Index or column)
								local endOffset = 0

								if typeName == "Color3" or typeName == "ColorSequence" then
									offset = offset + 22
								end

								if typeName == "NumberSequence" or typeName == "ColorSequence" then
									endOffset = 20
								end

								inputBox.Position = UDim2.new(scale, offset, 0, entry.Position.Y.Offset)
								inputBox.Size =
									UDim2.new(1 - scale, -offset - endOffset - attributeOffset, 0, rowHeight)
								inputBox.Visible = true
								valueBox.Visible = false
							end
						else
							nameFrame.BackgroundColor3 = Colors.Surface
							nameFrame.BackgroundTransparency = 1
							valueFrame.BackgroundColor3 = Colors.Surface
							valueFrame.BackgroundTransparency = 1
							valueBox.Visible = beforeVisible
						end
					end

					if
						prop.CategoryName
						or Properties.ExpandableTypes[prop.ValueType and prop.ValueType.Name]
						or Properties.ExpandableProps[gName]
					then
						Lib.StudioChevron(expand, expanded[gName], Lib.CheckMouseInGui(expand))
						expand.Visible = true
					else
						expand.Visible = false
					end
				end
				entryData.BaseColor = entry.BackgroundColor3
				entryData.Editing = not prop.CategoryName
					and not prop.SpecialRow
					and nameFrame.BackgroundTransparency == 0
				if entryData.PaintHover then
					entryData.PaintHover()
				end
				entry.Visible = true
			else
				entry.Visible = false
			end
		end

		if not inputPropVisible then
			inputBox.Visible = false
		end

		for i = maxEntries + 1, #propEntries do
			disconnectPropertyRow(propEntries[i])
			propEntries[i].Gui:Destroy()
			propEntries[i] = nil
			checkboxes[i] = nil
		end
	end

	Properties.SetProp = function(prop, val, noupdate, prevAttribute)
		if Explorer.HasInferredSelection and Explorer.HasInferredSelection() then
			return
		end
		return Apps.History.Run("Change " .. (prop.DisplayName or prop.Name), function()
			local sList = Explorer.Selection.List
			local propName = prop.Name
			local subName = prop.SubName
			local propClass = prop.Class
			local typeData = prop.ValueType
			local typeName = typeData.Name
			local attributeName = prop.AttributeName
			local rootTypeData = prop.RootType
			local rootTypeName = rootTypeData and rootTypeData.Name
			local fullName = prop.Class .. "." .. prop.Name .. (prop.SubName or "")
			local Vector3 = Vector3

			for i = 1, #sList do
				local node = sList[i]
				local obj = node.Obj

				if isa(obj, propClass) then
					pcall(function()
						local setVal = val
						local root
						if prop.IsAttribute then
							root = getAttribute(obj, attributeName)
						else
							root = obj[propName]
						end

						if prevAttribute then
							local previousValue = getAttribute(obj, prevAttribute.AttributeName)
							if previousValue == nil then
								return
							end
							if prevAttribute.MultiType or prevAttribute.ValueType.Name == typeName then
								setVal = previousValue
							end
						end

						if rootTypeName then
							if rootTypeName == "Vector2" then
								setVal = Vector2.new(
									(subName == ".X" and setVal) or root.X,
									(subName == ".Y" and setVal) or root.Y
								)
							elseif rootTypeName == "Vector3" then
								setVal = Vector3.new(
									(subName == ".X" and setVal) or root.X,
									(subName == ".Y" and setVal) or root.Y,
									(subName == ".Z" and setVal) or root.Z
								)
							elseif rootTypeName == "UDim" then
								setVal = UDim.new(
									(subName == ".Scale" and setVal) or root.Scale,
									(subName == ".Offset" and setVal) or root.Offset
								)
							elseif rootTypeName == "UDim2" then
								local rootX, rootY = root.X, root.Y
								local X_UDim = (subName == ".X" and setVal)
									or UDim.new(
										(subName == ".X.Scale" and setVal) or rootX.Scale,
										(subName == ".X.Offset" and setVal) or rootX.Offset
									)
								local Y_UDim = (subName == ".Y" and setVal)
									or UDim.new(
										(subName == ".Y.Scale" and setVal) or rootY.Scale,
										(subName == ".Y.Offset" and setVal) or rootY.Offset
									)
								setVal = UDim2.new(X_UDim, Y_UDim)
							elseif rootTypeName == "CFrame" then
								local rootPos, rootRight, rootUp, rootLook =
									root.Position, root.RightVector, root.UpVector, root.LookVector
								local pos = (subName == ".Position" and setVal)
									or Vector3.new(
										(subName == ".Position.X" and setVal) or rootPos.X,
										(subName == ".Position.Y" and setVal) or rootPos.Y,
										(subName == ".Position.Z" and setVal) or rootPos.Z
									)
								local rightV = (subName == ".RightVector" and setVal)
									or Vector3.new(
										(subName == ".RightVector.X" and setVal) or rootRight.X,
										(subName == ".RightVector.Y" and setVal) or rootRight.Y,
										(subName == ".RightVector.Z" and setVal) or rootRight.Z
									)
								local upV = (subName == ".UpVector" and setVal)
									or Vector3.new(
										(subName == ".UpVector.X" and setVal) or rootUp.X,
										(subName == ".UpVector.Y" and setVal) or rootUp.Y,
										(subName == ".UpVector.Z" and setVal) or rootUp.Z
									)
								local lookV = (subName == ".LookVector" and setVal)
									or Vector3.new(
										(subName == ".LookVector.X" and setVal) or rootLook.X,
										(subName == ".LookVector.Y" and setVal) or rootLook.Y,
										(subName == ".LookVector.Z" and setVal) or rootLook.Z
									)
								setVal = CFrame.fromMatrix(pos, rightV, upV, -lookV)
							elseif rootTypeName == "Rect" then
								local rootMin, rootMax = root.Min, root.Max
								local min = Vector2.new(
									(subName == ".Min.X" and setVal) or rootMin.X,
									(subName == ".Min.Y" and setVal) or rootMin.Y
								)
								local max = Vector2.new(
									(subName == ".Max.X" and setVal) or rootMax.X,
									(subName == ".Max.Y" and setVal) or rootMax.Y
								)
								setVal = Rect.new(min, max)
							elseif rootTypeName == "PhysicalProperties" then
								local rootProps = PhysicalProperties.new(obj.Material)
								local density = (subName == ".Density" and setVal)
									or (root and root.Density)
									or rootProps.Density
								local friction = (subName == ".Friction" and setVal)
									or (root and root.Friction)
									or rootProps.Friction
								local elasticity = (subName == ".Elasticity" and setVal)
									or (root and root.Elasticity)
									or rootProps.Elasticity
								local frictionWeight = (subName == ".FrictionWeight" and setVal)
									or (root and root.FrictionWeight)
									or rootProps.FrictionWeight
								local elasticityWeight = (subName == ".ElasticityWeight" and setVal)
									or (root and root.ElasticityWeight)
									or rootProps.ElasticityWeight
								setVal = PhysicalProperties.new(
									density,
									friction,
									elasticity,
									frictionWeight,
									elasticityWeight
								)
							elseif rootTypeName == "Ray" then
								local rootOrigin, rootDirection = root.Origin, root.Direction
								local origin = (subName == ".Origin" and setVal)
									or Vector3.new(
										(subName == ".Origin.X" and setVal) or rootOrigin.X,
										(subName == ".Origin.Y" and setVal) or rootOrigin.Y,
										(subName == ".Origin.Z" and setVal) or rootOrigin.Z
									)
								local direction = (subName == ".Direction" and setVal)
									or Vector3.new(
										(subName == ".Direction.X" and setVal) or rootDirection.X,
										(subName == ".Direction.Y" and setVal) or rootDirection.Y,
										(subName == ".Direction.Z" and setVal) or rootDirection.Z
									)
								setVal = Ray.new(origin, direction)
							elseif rootTypeName == "Faces" then
								local faces = {}
								local faceList = { "Back", "Bottom", "Front", "Left", "Right", "Top" }
								for _, face in pairs(faceList) do
									local val
									if subName == "." .. face then
										val = setVal
									else
										val = root[face]
									end
									if val then
										faces[#faces + 1] = Enum.NormalId[face]
									end
								end
								setVal = Faces.new(unpack(faces))
							elseif rootTypeName == "Axes" then
								local axes = {}
								local axesList = { "X", "Y", "Z" }
								for _, axe in pairs(axesList) do
									local val
									if subName == "." .. axe then
										val = setVal
									else
										val = root[axe]
									end
									if val then
										axes[#axes + 1] = Enum.Axis[axe]
									end
								end
								setVal = Axes.new(unpack(axes))
							elseif rootTypeName == "NumberRange" then
								setVal = NumberRange.new(
									subName == ".Min" and setVal or root.Min,
									subName == ".Max" and setVal or root.Max
								)
							end
						end

						if typeName == "PhysicalProperties" and setVal then
							setVal = root or PhysicalProperties.new(obj.Material)
						end

						if prop.IsAttribute then
							Apps.History.Attribute(obj, attributeName, setVal)
							if prevAttribute and prevAttribute.AttributeName ~= attributeName then
								Apps.History.Attribute(obj, prevAttribute.AttributeName, nil)
							end
						else
							Apps.History.Set(obj, propName, setVal)
						end
					end)
				end
			end

			if not noupdate then
				Properties.ComputeConflicts(prop)
			end
		end)
	end

	Properties.InitInputBox = function()
		inputBox = create({
			{
				1,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
					BorderSizePixel = 0,
					Name = "InputBox",
					Size = UDim2.new(0, 200, 0, 22),
					Visible = false,
					ZIndex = 2,
				},
			},
			{
				2,
				"TextBox",
				{
					BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
					BackgroundTransparency = 1,
					BorderColor3 = Color3.new(0.062745101749897, 0.51764708757401, 1),
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Font = 3,
					Parent = { 1 },
					PlaceholderColor3 = Color3.new(0.69803923368454, 0.69803923368454, 0.69803923368454),
					Position = UDim2.new(0, 3, 0, 0),
					Size = UDim2.new(1, -6, 1, 0),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextXAlignment = 0,
					ZIndex = 2,
				},
			},
		})
		inputBox.ClipsDescendants = true
		inputTextBox = inputBox.TextBox
		Lib.StudioText(inputTextBox)
		inputTextBox.Font = propertyFont
		inputTextBox.TextSize = 14
		inputBox.BackgroundColor3 = Settings.Theme.TextBox
		createSimple("UIStroke", {
			Parent = inputBox,
			Color = Settings.Theme.Focus,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
		inputBox.Parent = Properties.Window.GuiElems.Content.List

		inputTextBox.FocusLost:Connect(function()
			if not inputProp then
				return
			end

			local prop = inputProp
			inputProp = nil
			if inputSelection ~= Explorer.Selection.List then
				Properties.Refresh()
				return
			end
			local val = Properties.StringToValue(prop, inputTextBox.Text)
			if val ~= nil then
				Properties.SetProp(prop, val)
			else
				Properties.Refresh()
			end
		end)

		inputTextBox.Focused:Connect(function()
			inputTextBox.SelectionStart = 1
			inputTextBox.CursorPosition = #inputTextBox.Text + 1
		end)

		Lib.ViewportTextBox.convert(inputTextBox)
	end

	Properties.SetInputProp = function(prop, entryIndex, special)
		if Explorer.HasInferredSelection and Explorer.HasInferredSelection() then
			return
		end
		local typeData = prop.ValueType
		local typeName = typeData.Name
		local fullName = prop.Class .. "." .. prop.Name .. (prop.SubName or "")
		local propObj = autoUpdateObjs[fullName]
		local propVal = Properties.GetPropVal(prop, propObj)

		if prop.Tags.ReadOnly then
			return
		end

		valueEditors.Cancel()
		inputProp, inputSelection = prop, Explorer.Selection.List
		if special then
			if special == "color" then
				if typeName == "Color3" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop, propVal) or ""
					Properties.DisplayColorEditor(prop, propVal)
				elseif typeName == "BrickColor" then
					Properties.DisplayBrickColorEditor(prop, entryIndex, propVal)
				elseif typeName == "ColorSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop, propVal) or ""
					Properties.DisplayColorSequenceEditor(prop, propVal)
				end
			elseif special == "right" then
				if typeName == "NumberSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop, propVal) or ""
					Properties.DisplayNumberSequenceEditor(prop, propVal)
				elseif typeName == "ColorSequence" then
					inputTextBox.Text = propVal and Properties.ValueToString(prop, propVal) or ""
					Properties.DisplayColorSequenceEditor(prop, propVal)
				end
			end
		else
			if Properties.IsTextEditable(prop) then
				inputTextBox.Text = propVal and Properties.ValueToString(prop, propVal) or ""
				inputTextBox:CaptureFocus()
			elseif typeData.Category == "Enum" then
				Properties.DisplayEnumDropdown(entryIndex)
			elseif typeName == "BrickColor" then
				Properties.DisplayBrickColorEditor(prop, entryIndex, propVal)
			end
		end
		Properties.Refresh()
	end

	Properties.CancelObjectSelection = function()
		if not inputProp or inputProp.ValueType.Category ~= "Class" then
			return
		end
		inputProp = nil
		Properties.Refresh()
	end

	Properties.InitObjectPicker = function()
		local pendingClick, pendingProperty
		local window = Properties.Window
		window.OnDeactivate:Connect(function()
			if window.Closed then
				Properties.CancelObjectSelection()
			end
		end)
		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if not inputProp or inputProp.ValueType.Category ~= "Class" then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				Properties.CancelObjectSelection()
				return
			end
			local kind = input.UserInputType
			if
				kind ~= Enum.UserInputType.MouseButton1
				and kind ~= Enum.UserInputType.MouseButton2
				and kind ~= Enum.UserInputType.Touch
			then
				return
			end
			for index, entry in ipairs(propEntries) do
				if viewList[index + Properties.Index] == inputProp and entry.Gui.Visible then
					local frame = entry.GuiElems.ValueFrame
					local point, position, size = input.Position, frame.AbsolutePosition, frame.AbsoluteSize
					if
						point.X >= position.X
						and point.X < position.X + size.X
						and point.Y >= position.Y
						and point.Y < position.Y + size.Y
					then
						return
					end
				end
			end
			pendingClick, pendingProperty = input, inputProp
		end)
		Main.TrackSignal(service.UserInputService.InputEnded, function(input)
			if input ~= pendingClick then
				return
			end
			local property = pendingProperty
			pendingClick, pendingProperty = nil, nil
			if inputProp == property then
				Properties.CancelObjectSelection()
			end
		end)
	end

	Properties.InitSearch = function()
		Properties.InitObjectPicker()
		local searchBox = Lib.StudioSearch(Properties.GuiElems.ToolBar, "Filter Properties (Ctrl+Shift+P)", nil, {
			PersistentBorder = true,
			PixelBorder = true,
			BorderColor = Color3.fromRGB(40, 41, 49),
			HoverBorderColor = Color3.fromRGB(102, 104, 114),
		})
		local toolbar = Properties.GuiElems.ToolBar
		toolbar.Size = UDim2.new(1, 0, 0, View.ToolbarHeight)
		toolbar.SearchFrame.Position = UDim2.fromOffset(1, 0)
		toolbar.SearchFrame.Size = UDim2.new(1, -2, 0, View.FilterHeight)
		toolbar.SearchFrame.BackgroundColor3 = Colors.Surface
		searchBox.Font = propertyFont
		searchBox.TextSize = 14
		local field = toolbar.SearchFrame
		field.Reset.Position = UDim2.new(1, -36, 0, 2)
		field.Reset.Size = UDim2.fromOffset(16, 16)
		field.Reset.ZIndex = (field.ZIndex or 1) + 2
		local clear = field.Reset:FindFirstChild("ImageLabel")
		if clear then
			clear.ZIndex = field.Reset.ZIndex + 1
			clear.Image = Lib.PanelAsset("close") or clear.Image
			clear.Position = UDim2.fromOffset(0, 0)
			clear.Size = UDim2.fromOffset(16, 16)
			clear.ImageTransparency = 0
			clear.ImageColor3 = Color3.new(1, 1, 1)
		end
		Lib.PanelButtonHover(field.Reset)
		searchBox.Position = UDim2.fromOffset(4, 0)
		searchBox.Size = UDim2.new(1, -42, 1, 0)
		local dropdown = createSimple("ImageButton", {
			Name = "FilterDropdown",
			Parent = field,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Position = UDim2.new(1, -18, 0, 2),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = (field.ZIndex or 1) + 2,
		})
		createSimple("ImageLabel", {
			Name = "ImageLabel",
			Parent = dropdown,
			BackgroundTransparency = 1,
			Image = Lib.PanelAsset("dropdown") or "",
			ImageColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.fromOffset(12, 12),
			ZIndex = dropdown.ZIndex + 1,
		})
		Lib.PanelButtonHover(dropdown)
		dropdown.Activated:Connect(function()
			searchBox:CaptureFocus()
		end)
		Properties.GuiElems.FilterDropdown = dropdown

		Main.TrackSignal(service.UserInputService.InputBegan, function(input)
			if input.KeyCode == Enum.KeyCode.P and Lib.IsCtrlDown() and Lib.IsShiftDown() and window:IsVisible() then
				searchBox:CaptureFocus()
			end
		end)
		Properties.GuiElems.ToolBar.SearchFrame.Reset.Activated:Connect(function()
			searchBox.Text = ""
		end)

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			Properties.SearchText = searchBox.Text
			Properties.Update()
			Properties.Refresh()
		end)
	end

	Properties.InitEntryStuff = function()
		Properties.EntryTemplate = create({
			{
				1,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.17647059261799, 0.17647059261799, 0.17647059261799),
					BorderColor3 = Color3.new(0.1294117718935, 0.1294117718935, 0.1294117718935),
					Font = 3,
					Name = "Entry",
					Position = UDim2.new(0, 1, 0, 1),
					Size = UDim2.new(0, 250, 0, 22),
					Text = "",
					TextSize = 14,
				},
			},
			{
				2,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.04313725605607, 0.35294118523598, 0.68627452850342),
					BackgroundTransparency = 1,
					BorderColor3 = Color3.new(0.33725491166115, 0.49019610881805, 0.73725491762161),
					BorderSizePixel = 0,
					Name = "NameFrame",
					Parent = { 1 },
					Position = UDim2.new(0, 20, 0, 0),
					Size = UDim2.new(1, -40, 1, 0),
				},
			},
			{
				3,
				"TextLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Font = 3,
					Name = "PropName",
					Parent = { 2 },
					Position = UDim2.new(0, 2, 0, 0),
					Size = UDim2.new(1, -2, 1, 0),
					Text = "Anchored",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextTransparency = 0.10000000149012,
					TextTruncate = 1,
					TextXAlignment = 0,
				},
			},
			{
				4,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Font = 3,
					Name = "Expand",
					Parent = { 2 },
					Position = UDim2.new(0, -20, 0, 1),
					Size = UDim2.new(0, 20, 0, 20),
					Text = "",
					TextSize = 14,
					Visible = false,
				},
			},
			{
				5,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5642383285",
					ImageRectOffset = Vector2.new(144, 16),
					ImageRectSize = Vector2.new(16, 16),
					Name = "Icon",
					Parent = { 4 },
					Position = UDim2.new(0, 2, 0, 2),
					ScaleType = 4,
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				6,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 4,
					Name = "ToggleAttributes",
					Parent = { 2 },
					Position = UDim2.new(1, -85, 0, 0),
					Size = UDim2.new(0, 85, 0, 22),
					Text = "Off",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextTransparency = 0.10000000149012,
					Visible = false,
				},
			},
			{
				7,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.04313725605607, 0.35294118523598, 0.68627452850342),
					BackgroundTransparency = 1,
					BorderColor3 = Color3.new(0.33725491166115, 0.49019607901573, 0.73725491762161),
					BorderSizePixel = 0,
					Name = "ValueFrame",
					Parent = { 1 },
					Position = UDim2.new(1, -100, 0, 0),
					Size = UDim2.new(0, 80, 1, 0),
				},
			},
			{
				8,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.14117647707462, 0.14117647707462, 0.14117647707462),
					BorderColor3 = Color3.new(0.33725491166115, 0.49019610881805, 0.73725491762161),
					BorderSizePixel = 0,
					Name = "Line",
					Parent = { 7 },
					Position = UDim2.new(0, -1, 0, 0),
					Size = UDim2.new(0, 1, 1, 0),
				},
			},
			{
				9,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "ColorButton",
					Parent = { 7 },
					Size = UDim2.new(0, 20, 0, 22),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					Visible = false,
				},
			},
			{
				10,
				"Frame",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderColor3 = Color3.new(0, 0, 0),
					Name = "ColorPreview",
					Parent = { 9 },
					Position = UDim2.new(0, 5, 0, 6),
					Size = UDim2.new(0, 10, 0, 10),
				},
			},
			{ 11, "UIGradient", { Parent = { 10 } } },
			{
				12,
				"Frame",
				{
					BackgroundTransparency = 1,
					Name = "EnumArrow",
					Parent = { 7 },
					Position = UDim2.new(1, -16, 0, 3),
					Size = UDim2.new(0, 16, 0, 16),
					Visible = false,
				},
			},
			{
				13,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
					BorderSizePixel = 0,
					Parent = { 12 },
					Position = UDim2.new(0, 8, 0, 9),
					Size = UDim2.new(0, 1, 0, 1),
				},
			},
			{
				14,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
					BorderSizePixel = 0,
					Parent = { 12 },
					Position = UDim2.new(0, 7, 0, 8),
					Size = UDim2.new(0, 3, 0, 1),
				},
			},
			{
				15,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.86274510622025, 0.86274510622025, 0.86274510622025),
					BorderSizePixel = 0,
					Parent = { 12 },
					Position = UDim2.new(0, 6, 0, 7),
					Size = UDim2.new(0, 5, 0, 1),
				},
			},
			{
				16,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Font = 3,
					Name = "ValueBox",
					Parent = { 7 },
					Position = UDim2.new(0, 4, 0, 0),
					Size = UDim2.new(1, -8, 1, 0),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextTransparency = 0.10000000149012,
					TextTruncate = 1,
					TextXAlignment = 0,
				},
			},
			{
				17,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "RightButton",
					Parent = { 7 },
					Position = UDim2.new(1, -20, 0, 0),
					Size = UDim2.new(0, 20, 0, 22),
					Text = "...",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					Visible = false,
				},
			},
			{
				18,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "SettingsButton",
					Parent = { 7 },
					Position = UDim2.new(1, -20, 0, 0),
					Size = UDim2.new(0, 20, 0, 22),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					Visible = false,
				},
			},
			{
				19,
				"Frame",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Name = "SoundPreview",
					Parent = { 7 },
					Size = UDim2.new(1, 0, 1, 0),
					Visible = false,
				},
			},
			{
				20,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "ControlButton",
					Parent = { 19 },
					Size = UDim2.new(0, 20, 0, 22),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				21,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5642383285",
					ImageRectOffset = Vector2.new(144, 16),
					ImageRectSize = Vector2.new(16, 16),
					Name = "Icon",
					Parent = { 20 },
					Position = UDim2.new(0, 2, 0, 3),
					ScaleType = 4,
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				22,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.3137255012989, 0.3137255012989, 0.3137255012989),
					BorderSizePixel = 0,
					Name = "TimeLine",
					Parent = { 19 },
					Position = UDim2.new(0, 26, 0.5, -1),
					Size = UDim2.new(1, -34, 0, 2),
				},
			},
			{
				23,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
					BorderColor3 = Color3.new(0.1294117718935, 0.1294117718935, 0.1294117718935),
					Name = "Slider",
					Parent = { 22 },
					Position = UDim2.new(0, -4, 0, -8),
					Size = UDim2.new(0, 8, 0, 18),
				},
			},
			{
				24,
				"TextButton",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "EditAttributeButton",
					Parent = { 1 },
					Position = UDim2.new(1, -20, 0, 0),
					Size = UDim2.new(0, 20, 0, 22),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				25,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5034718180",
					ImageTransparency = 0.20000000298023,
					Name = "Icon",
					Parent = { 24 },
					Position = UDim2.new(0, 2, 0, 3),
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				26,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.2352941185236, 0.2352941185236, 0.2352941185236),
					BorderSizePixel = 0,
					Font = 3,
					Name = "RowButton",
					Parent = { 1 },
					Size = UDim2.new(1, 0, 1, 0),
					Text = "Add Attribute",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextTransparency = 0.10000000149012,
					Visible = false,
				},
			},
		})

		Properties.EntryTemplate.BorderSizePixel = 0
		Properties.EntryTemplate.BackgroundColor3 = Colors.Surface
		Properties.EntryTemplate.ValueFrame.Line.BackgroundColor3 = Colors.Grid
		Properties.EntryTemplate.ValueFrame.Line.Position = UDim2.fromOffset(0, 0)
		Properties.EntryTemplate.ValueFrame.Line.ZIndex = 2
		Properties.EntryTemplate.NameFrame.PropName.TextTransparency = 0
		Properties.EntryTemplate.ValueFrame.ValueBox.TextTransparency = 0
		Properties.EntryTemplate.NameFrame.PropName.Font = propertyFont
		Properties.EntryTemplate.ValueFrame.ValueBox.Font = propertyFont
		createSimple("Frame", {
			Name = "RowDivider",
			Parent = Properties.EntryTemplate,
			BackgroundColor3 = Colors.Grid,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -1),
			ZIndex = 3,
			Size = UDim2.new(1, 0, 0, 1),
		})
		local add = Properties.EntryTemplate.NameFrame.ToggleAttributes
		add.Text = ""
		add.AutoButtonColor = false
		add.TextScaled = false
		for _, size in ipairs({ Vector2.new(8, 2), Vector2.new(2, 8) }) do
			createSimple("Frame", {
				Parent = add,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size.X, size.Y),
				BorderSizePixel = 0,
				BackgroundColor3 = Settings.Theme.Text,
			})
		end
		local emptyAttributes = createSimple("TextLabel", {
			Name = "EmptyAttributes",
			Parent = Properties.EntryTemplate,
			Visible = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(1, -44, 1, 0),
			Text = "No Attributes have been added yet",
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Lib.StudioText(emptyAttributes)
		emptyAttributes.Font = propertyFont
		emptyAttributes.TextSize = 14
		emptyAttributes.TextColor3 = Colors.ReadOnly
		local removeTag = createSimple("TextButton", {
			Name = "TagRemove",
			Parent = Properties.EntryTemplate,
			Visible = false,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -22, 0, 0),
			Size = UDim2.fromOffset(20, 22),
			Text = "×",
		})
		Lib.StudioText(removeTag)
		removeTag.TextSize = 18
		Lib.SetNativeIcon(removeTag, "nav/close")
		local gear = Properties.EntryTemplate.EditAttributeButton.Icon
		gear.Image = Main.GetStudioAsset("nav/settings") or gear.Image
		gear.ScaleType = Enum.ScaleType.Fit
		Lib.StudioChevron(Properties.EntryTemplate.NameFrame.Expand, false, false)
		local enumArrow = Properties.EntryTemplate.ValueFrame.EnumArrow
		for _, child in ipairs(enumArrow:GetChildren()) do
			child:Destroy()
		end
		createSimple("ImageLabel", {
			Name = "Native",
			Parent = enumArrow,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = Main.GetStudioAsset("nav/dropdown") or "",
			ScaleType = Enum.ScaleType.Fit,
		})
		local rightButton = Properties.EntryTemplate.ValueFrame.RightButton
		rightButton.Text = ""
		createSimple("ImageLabel", {
			Name = "Native",
			Parent = rightButton,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			Image = Main.GetStudioAsset("explorer/options") or "",
			ScaleType = Enum.ScaleType.Fit,
		})
		local settingsButton = Properties.EntryTemplate.ValueFrame.SettingsButton
		createSimple("ImageLabel", {
			Name = "Native",
			Parent = settingsButton,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			Image = Main.GetStudioAsset("nav/settings") or "",
			ScaleType = Enum.ScaleType.Fit,
		})

		local fullNameFrame = Lib.Frame.new()
		local label = Lib.Label.new()
		label.Parent = fullNameFrame.Gui
		label.Position = UDim2.new(0, 2, 0, 0)
		label.Size = UDim2.new(1, -4, 1, 0)
		fullNameFrame.Visible = false
		fullNameFrame.Parent = window.Gui

		Properties.EntryTemplate.BackgroundTransparency = 0

		Properties.FullNameFrame = fullNameFrame
		Properties.FullNameFrameAttach = Lib.AttachTo(fullNameFrame)
	end

	Properties.Init = function()
		local guiItems = create({
			{ 1, "Folder", { Name = "Items" } },
			{
				2,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.20392157137394, 0.20392157137394, 0.20392157137394),
					BorderSizePixel = 0,
					Name = "ToolBar",
					Parent = { 1 },
					Size = UDim2.new(1, 0, 0, 22),
				},
			},
			{
				3,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.14901961386204, 0.14901961386204, 0.14901961386204),
					BorderColor3 = Color3.new(0.1176470592618, 0.1176470592618, 0.1176470592618),
					BorderSizePixel = 0,
					Name = "SearchFrame",
					Parent = { 2 },
					Position = UDim2.new(0, 3, 0, 1),
					Size = UDim2.new(1, -6, 0, 18),
				},
			},
			{
				4,
				"TextBox",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					Font = 3,
					Name = "SearchBox",
					Parent = { 3 },
					PlaceholderColor3 = Color3.new(0.39215689897537, 0.39215689897537, 0.39215689897537),
					PlaceholderText = "Search properties",
					Position = UDim2.new(0, 4, 0, 0),
					Size = UDim2.new(1, -24, 0, 18),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					TextXAlignment = 0,
				},
			},
			{ 5, "UICorner", { CornerRadius = UDim.new(0, 2), Parent = { 3 } } },
			{
				6,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "Reset",
					Parent = { 3 },
					Position = UDim2.new(1, -17, 0, 1),
					Size = UDim2.new(0, 16, 0, 16),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
				},
			},
			{
				7,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5034718129",
					ImageColor3 = Color3.new(0.39215686917305, 0.39215686917305, 0.39215686917305),
					Parent = { 6 },
					Size = UDim2.new(0, 16, 0, 16),
				},
			},
			{
				8,
				"TextButton",
				{
					AutoButtonColor = false,
					BackgroundColor3 = Color3.new(0.12549020349979, 0.12549020349979, 0.12549020349979),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = 3,
					Name = "Refresh",
					Parent = { 2 },
					Position = UDim2.new(1, -20, 0, 1),
					Size = UDim2.new(0, 18, 0, 18),
					Text = "",
					TextColor3 = Color3.new(1, 1, 1),
					TextSize = 14,
					Visible = false,
				},
			},
			{
				9,
				"ImageLabel",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					Image = "rbxassetid://5642310344",
					Parent = { 8 },
					Position = UDim2.new(0, 3, 0, 3),
					Size = UDim2.new(0, 12, 0, 12),
				},
			},
			{
				10,
				"Frame",
				{
					BackgroundColor3 = Color3.new(0.15686275064945, 0.15686275064945, 0.15686275064945),
					BorderSizePixel = 0,
					Name = "ScrollCorner",
					Parent = { 1 },
					Position = UDim2.new(1, -16, 1, -16),
					Size = UDim2.new(0, 16, 0, 16),
					Visible = false,
				},
			},
			{
				11,
				"Frame",
				{
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					Name = "List",
					Parent = { 1 },
					Position = UDim2.new(0, 0, 0, 23),
					Size = UDim2.new(1, 0, 1, -23),
				},
			},
		})

		categoryOrder = API.CategoryOrder
		for category, _ in next, categoryOrder do
			if not Properties.CollapsedCategories[category] then
				expanded["CAT_" .. category] = true
			end
		end
		expanded["Sound.SoundId"] = true
		expanded["CAT_Attributes"] = true
		expanded["CAT_Tags"] = true
		expanded["CAT_Plugins"] = true

		window = Lib.Window.new()
		window:SetTitleBarHeight(View.HeaderHeight)
		Properties.Window = window
		window:SetTitle("Properties")
		window.GuiElems.Content.BackgroundColor3 = Colors.Surface
		window.GuiElems.Content.BackgroundTransparency = 0
		window.GuiElems.TopBar.BackgroundColor3 = Colors.Category
		window.GuiElems.Title.Font = propertyFont
		window.GuiElems.Title.TextSize = 14

		toolBar = guiItems.ToolBar
		toolBar.BackgroundColor3 = Colors.Surface
		propsFrame = guiItems.List
		propsFrame.BorderSizePixel = 0
		propsFrame.BackgroundColor3 = Colors.Surface
		propsFrame.BackgroundTransparency = 0
		propsFrame.Position = UDim2.fromOffset(0, View.ToolbarHeight)

		Properties.GuiElems.ToolBar = toolBar
		Properties.GuiElems.PropsFrame = propsFrame

		Properties.InitEntryStuff()

		local function resizeProperties()
			if Properties.Window:IsContentVisible() then
				local width, height = getWindowSize()
				if width ~= viewWindowWidth or height ~= viewWindowHeight then
					Properties.UpdateView(width, height)
					Properties.Refresh(true)
				end
			end
		end
		window.OnResizeApplied = resizeProperties
		local resizeView = Lib.FrameTask(resizeProperties)
		Main.AddCleanup(function()
			resizeView:Cancel()
			window.OnResizeApplied = nil
			for _, entry in ipairs(propEntries) do
				disconnectPropertyRow(entry)
			end
		end)
		window.GuiElems.Main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if Properties.Window:IsContentVisible() then
				resizeView:Push(true)
			end
		end)
		window.OnActivate:Connect(function()
			Properties.UpdateView()
			Properties.Update()
			Properties.Refresh()
		end)
		window.OnRestore:Connect(function()
			Properties.UpdateView()
			Properties.Update()
			Properties.Refresh()
		end)

		scrollV = Lib.ScrollBar.new()
		scrollV:UseLegacyStudioStyle()
		scrollV.WheelIncrement = 63
		scrollV.Increment = 21
		scrollV.Gui.Position = UDim2.new(1, -16, 0, View.ToolbarHeight)
		scrollV:SetScrollFrame(propsFrame)
		scrollV.Scrolled:Connect(function()
			Properties.ScrollOffset = scrollV.Index
			Properties.Refresh(true)
		end)

		scrollH = Lib.ScrollBar.new(true)
		scrollH:UseLegacyStudioStyle()
		scrollH.Increment = 5
		scrollH.WheelIncrement = 20
		scrollH.Gui.Position = UDim2.new(0, 0, 1, -16)
		scrollH.Scrolled:Connect(function()
			Properties.Refresh(true)
		end)

		window.GuiElems.Line.Visible = false
		toolBar.Parent = window.GuiElems.Content
		propsFrame.Parent = window.GuiElems.Content
		guiItems.ScrollCorner.Parent = window.GuiElems.Content
		scrollV.Gui.Parent = window.GuiElems.Content
		scrollH.Gui.Parent = window.GuiElems.Content
		Properties.InitInputBox()
		window.OnDeactivate:Connect(Properties.CancelAttributeRename)
		window.OnDeactivate:Connect(function()
			if Properties.TagMenu then
				Properties.TagMenu:Hide()
			end
		end)
		window.OnMinimize:Connect(Properties.CancelAttributeRename)
		window.OnMinimize:Connect(Properties.CancelObjectSelection)
		Properties.InitSearch()
		local field = toolBar.SearchFrame
		field.BackgroundColor3 = Colors.Surface
		toolBar.BackgroundColor3 = Colors.Surface
		field.SearchBox.TextColor3 = Colors.Text
		field.SearchBox.PlaceholderColor3 = Colors.Text
	end

	return Properties
end

if gethsfuncs then
	_G.moduleData = { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
else
	return { InitDeps = InitDeps, InitAfterMain = InitAfterMain, Main = CreateModule }
end
