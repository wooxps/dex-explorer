--!strict

local Main, Lib, service, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, service, env = d.Main, d.Lib, d.service, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Layout = {}
	local function finite(value, min, max)
		return type(value) == "number" and value == value and value >= min and value <= max
	end
	function Layout.Validate(data)
		if
			type(data) ~= "table"
			or data.Version ~= 1
			or type(data.Panels) ~= "table"
			or type(data.Sides) ~= "table"
		then
			return false
		end
		local seen = {}
		for id, panel in pairs(data.Panels) do
			if
				type(id) ~= "string"
				or type(panel) ~= "table"
				or not finite(panel.X, -100000, 100000)
				or not finite(panel.Y, -100000, 100000)
				or not finite(panel.Width, 1, 100000)
				or not finite(panel.Height, 1, 100000)
				or type(panel.Closed) ~= "boolean"
				or type(panel.Minimized) ~= "boolean"
				or (panel.Dock ~= nil and panel.Dock ~= "left" and panel.Dock ~= "right")
				or (panel.Order ~= nil and (not finite(panel.Order, 1, 10000) or panel.Order % 1 ~= 0))
			then
				return false
			end
		end
		for _, name in ipairs({ "left", "right" }) do
			local side = data.Sides[name]
			if
				type(side) ~= "table"
				or not finite(side.Width, 200, 100000)
				or type(side.Hidden) ~= "boolean"
				or type(side.Panels) ~= "table"
			then
				return false
			end
			for index, id in pairs(side.Panels) do
				if
					not finite(index, 1, #side.Panels)
					or index % 1 ~= 0
					or type(id) ~= "string"
					or seen[id]
					or not data.Panels[id]
					or data.Panels[id].Closed
				then
					return false
				end
				seen[id] = true
			end
		end
		return true
	end
	function Layout.Capture(windows, sides)
		local data = { Version = 1, Panels = {}, Sides = {} }
		local ids = {}
		for id, window in pairs(windows) do
			ids[window] = id
			data.Panels[id] = {
				X = window.PosX or 0,
				Y = window.PosY or 0,
				Width = window.SizeX,
				Height = window.SizeY,
				Closed = window.Closed,
				Minimized = window.Minimized,
			}
			local dock = window.Side or window.ClosedSide
			if dock then
				data.Panels[id].Dock = dock == sides.left and "left" or "right"
				data.Panels[id].Order = window.SidePos or 1
			end
		end
		for name, side in pairs(sides) do
			local children = {}
			for _, window in ipairs(side.Windows) do
				if ids[window] then
					children[#children + 1] = ids[window]
				end
			end
			data.Sides[name] = { Width = side.Width, Hidden = side.Hidden, Panels = children }
		end
		return data
	end
	function Layout.Apply(data, windows, sides, update)
		if not Layout.Validate(data) then
			return false
		end
		for id, panel in pairs(data.Panels) do
			local window = windows[id]
			if window then
				window:StopTweens()
				if window.Aligned then
					window:SetAligned(false)
				end
				window.ClosedSide = nil
				if panel.Closed then
					if not window.Closed then
						window:Close()
					end
					window.ClosedSide = panel.Dock and sides[panel.Dock] or nil
					window.SidePos = panel.Order or 1
				else
					if window.Closed then
						window:Show({ Align = false, Silent = true })
					end
					window:StopTweens()
					window:Resize(math.max(window.MinX, panel.Width), math.max(window.MinY, panel.Height))
					window.PosX, window.PosY = math.max(0, panel.X), math.max(0, panel.Y)
					window:MoveInBoundary()
					window:SetMinimized(panel.Minimized, 3)
				end
			end
		end
		for name, side in pairs(sides) do
			local saved = data.Sides[name]
			local camera = service.Workspace and service.Workspace.CurrentCamera
			local screen = camera and camera.ViewportSize
			side.Width = math.clamp(saved.Width, 200, screen and math.max(200, screen.X * 0.45) or saved.Width)
			for _, id in ipairs(saved.Panels) do
				local window = windows[id]
				if window and window.Alignable then
					window:AlignTo(side, #side.Windows + 1, data.Panels[id].Height, true)
				end
			end
			side.Hidden = saved.Hidden
		end
		update(true)
		for _, window in pairs(windows) do
			if not window.Closed then
				if window.Side and window.Side.Hidden then
					window.OnDeactivate:Fire()
				elseif window.Minimized then
					window.OnMinimize:Fire()
				else
					window.OnActivate:Fire()
				end
			end
		end
		return true
	end
	function Layout.Create(windows, sides, update)
		local self = { Path = "dex-explorer/window-layout.json", Restoring = false }
		local previous, scheduled, stopped = nil, false, false
		function self:Save()
			if stopped or self.Restoring or not env.writefile then
				return false
			end
			local data = Layout.Capture(windows, sides)
			if not Layout.Validate(data) then
				return false
			end
			local ok, json = pcall(service.HttpService.JSONEncode, service.HttpService, data)
			if not ok then
				return false
			end
			if json == previous then
				return true
			end
			local written = pcall(env.writefile, self.Path, json)
			if written then
				previous = json
			end
			return written
		end
		function self:Restore()
			if not env.readfile then
				return false
			end
			local ok, json = pcall(env.readfile, self.Path)
			if not ok then
				return false
			end
			local decoded, data = pcall(service.HttpService.JSONDecode, service.HttpService, json)
			if not decoded or not Layout.Validate(data) then
				return false
			end
			self.Restoring = true
			local applied, result = pcall(Layout.Apply, data, windows, sides, update)
			self.Restoring = false
			return applied and result
		end
		function self:Schedule()
			if stopped or self.Restoring or scheduled then
				return
			end
			scheduled = true
			task.delay(0.6, function()
				scheduled = false
				if not stopped then
					self:Save()
				end
			end)
		end
		for _, window in pairs(windows) do
			for _, property in ipairs({ "Position", "Size" }) do
				Main.TrackSignal(window.GuiElems.Main:GetPropertyChangedSignal(property), function()
					self:Schedule()
				end)
			end
			for _, signal in ipairs({ window.OnActivate, window.OnDeactivate, window.OnMinimize, window.OnRestore }) do
				Main.TrackSignal(signal, function()
					self:Schedule()
				end)
			end
		end
		Main.AddCleanup(function()
			self:Save()
			stopped = true
		end)
		return self
	end
	return Layout
end
return { InitDeps = InitDeps, Main = CreateModule }
