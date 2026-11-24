--!strict

local Main, Apps

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps = d.Main, d.Apps
end
------------------------------ Module ------------------------------

local function CreateModule()
	local View = {}
	function View.Create(parent)
		local React, ReactRoblox = Apps.React.React, Apps.React.ReactRoblox
		local mount = Instance.new("Frame")
		mount.Name = "ReactViewport"
		mount.BorderSizePixel = 0
		mount.BackgroundTransparency = 1
		mount.Size = UDim2.fromScale(1, 1)
		mount.Parent = parent
		local root = ReactRoblox.createRoot(mount)
		local slots, byGui, portals = {}, {}, {}
		local destroyed = false
		local renderer = { RootCount = 1, Commits = 0, Renderer = "React" }
		renderer.Layer = mount
		local canvasIndex = 0
		local nextSlotId = 0
		local function alignCanvas()
			mount.Position = UDim2.fromOffset(0, canvasIndex * 20)
		end
		function renderer:SetCanvasIndex(index)
			canvasIndex = index
		end
		local dirty = false
		local function sameState(a, b)
			for key, value in pairs(a) do
				if b[key] ~= value then
					return false
				end
			end
			for key, value in pairs(b) do
				if a[key] ~= value then
					return false
				end
			end
			return true
		end
		local Row = React.memo(Apps.ExplorerNodeRow.Render, function(a, b)
			return sameState(a.state, b.state)
		end)
		local function commit()
			if not dirty then
				return
			end
			local children = {}
			for index, slot in pairs(slots) do
				children["Row" .. slot.id] = React.createElement(Row, { state = slot.state, rowRef = slot.ref })
			end
			for key, portal in pairs(portals) do
				children[key] = ReactRoblox.createPortal(portal.element, portal.parent)
			end
			ReactRoblox.flushSync(function()
				root:render(React.createElement(React.Fragment, nil, children))
			end)
			dirty = false
			renderer.Commits += 1
		end
		function renderer:BeginFrame(count)
			for index = count + 1, #slots do
				local slot = slots[index]
				if slot and slot.ref.current then
					byGui[slot.ref.current] = nil
				end
				slots[index] = nil
				dirty = true
			end
			for index = 1, count do
				if not slots[index] then
					nextSlotId += 1
					slots[index] = {
						id = nextSlotId,
						ref = React.createRef(),
						state = {
							position = UDim2.fromOffset(0, (index - 1) * 20),
							size = UDim2.new(1, 0, 0, 20),
							depth = 12,
							height = 20,
							guideCount = 0,
							BackgroundColor = Color3.new(),
							BackgroundTransparency = 1,
							TextColor = Color3.new(1, 1, 1),
							name = "",
							labelWidth = 0,
							hasChildren = false,
							expanded = false,
							insertX = 0,
							insertVisible = false,
						},
					}
					dirty = true
				end
			end
			commit()
		end
		function renderer:BindNodes(keys)
			local changed = false
			for index, slot in ipairs(slots) do
				if slot.node ~= keys[index] then
					changed = true
					break
				end
			end
			if not changed then
				return
			end
			local previous = table.clone(slots)
			local retained, used = {}, {}
			for index, slot in ipairs(previous) do
				if slot.node then
					retained[slot.node] = slot
				end
			end
			for index = 1, #slots do
				local slot = keys[index] and retained[keys[index]]
				if slot then
					slots[index] = slot
					used[slot] = true
				else
					slots[index] = false
				end
			end
			local freeIndex = 1
			for index = 1, #previous do
				if not slots[index] then
					while used[previous[freeIndex]] do
						freeIndex += 1
					end
					local slot = previous[freeIndex]
					freeIndex += 1
					slots[index] = slot
					used[slot] = true
				end
				slots[index].node = keys[index]
			end
		end
		function renderer:NewRow(index)
			if not slots[index] then
				self:BeginFrame(index)
			end
			local slot = slots[index]
			local gui = assert(slot.ref.current, "React Explorer row did not mount")
			byGui[gui] = slot
			return gui
		end
		function renderer:UpdateRow(gui, state)
			local slot = assert(byGui[gui], "Unknown React viewport slot")
			if sameState(slot.state, state) then
				return
			end
			slot.state = table.clone(state)
			dirty = true
		end
		function renderer:EndFrame()
			commit()
			alignCanvas()
		end
		function renderer:ResizeViewport(count, width, viewportWidth, scrollX)
			if count ~= #slots then
				return false
			end
			for _, slot in ipairs(slots) do
				local gui = slot.ref.current
				if not gui then
					return false
				end
			end
			for _, slot in ipairs(slots) do
				if not slot.node then
					continue
				end
				local gui = slot.ref.current
				local s = table.clone(slot.state)
				s.size = UDim2.fromOffset(width, s.height)
				s.backgroundX = scrollX
				s.backgroundWidth = math.max(0, viewportWidth - 2)
				s.insertX = math.max(
					0,
					math.min(s.depth + 21 + s.labelWidth + (s.statusAsset and 24 or 0), viewportWidth - 22 + scrollX)
				)
				gui.Size = s.size
				for _, name in ipairs({
					"Background",
					"HoverOverlay",
					"SelectionTop",
					"SelectionBottom",
					"SelectionWithin",
				}) do
					local part = gui:FindFirstChild(name)
					if part then
						local within = name == "SelectionWithin"
						local strip = name == "SelectionTop" or name == "SelectionBottom"
						part.Size = UDim2.fromOffset(
							math.max(0, s.backgroundWidth - (within and 5 or 0)),
							strip and 6 or s.height - (within and 5 or 0)
						)
						part.Position = UDim2.fromOffset(
							scrollX + (within and 2.5 or 0),
							name == "SelectionBottom" and s.height - 6 or within and 2.5 or 0
						)
					end
				end
				if gui:FindFirstChild("Insert") then
					gui.Insert.Position = UDim2.fromOffset(s.insertX, math.floor((s.height - 20) / 2))
				end
				slot.state = s
			end
			return true
		end
		function renderer:Portal(key, element, parent)
			portals[key] = { element = element, parent = parent }
			dirty = true
			commit()
		end
		function renderer:ClearPortalsUnder(parent)
			for key, portal in pairs(portals) do
				if portal.parent == parent or portal.parent:IsDescendantOf(parent) then
					portals[key] = nil
					dirty = true
				end
			end
			commit()
		end
		function renderer:RemovePortal(key)
			if destroyed then
				return
			end
			if portals[key] then
				portals[key] = nil
				dirty = true
				commit()
			end
		end
		function renderer:DestroyRow(gui)
			local slot = byGui[gui]
			if slot then
				for index, value in pairs(slots) do
					if value == slot then
						slots[index] = nil
						break
					end
				end
				byGui[gui] = nil
				dirty = true
			end
		end
		function renderer:Destroy()
			if destroyed then
				return
			end
			destroyed = true
			ReactRoblox.flushSync(function()
				root:unmount()
			end)
			mount:Destroy()
			table.clear(slots)
			table.clear(byGui)
			table.clear(portals)
		end
		if Main.AddCleanup then
			Main.AddCleanup(function()
				renderer:Destroy()
			end)
		end
		return renderer
	end
	return View
end
return { InitDeps = InitDeps, Main = CreateModule }
