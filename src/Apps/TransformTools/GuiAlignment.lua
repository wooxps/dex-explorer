--!strict

local Apps, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, service = d.Apps, d.service
end
------------------------------ Module ------------------------------

local function Main()
	local A = { Threshold = 5, Overhang = 10 }
	function A.Extents(g, dx, dy)
		local r = math.rad(g.Rotation or 0)
		local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
		local w, h = (g.Size.X * c + g.Size.Y * s) * 0.5, (g.Size.Y * c + g.Size.X * s) * 0.5
		local x, y = g.Center.X + (dx or 0), g.Center.Y + (dy or 0)
		return { Left = x - w, Right = x + w, Top = y - h, Bottom = y + h, X = x, Y = y }
	end
	function A.Features(g, axis, delta)
		local e = A.Extents(g)
		local d = delta or 0
		if axis == "X" then
			return {
				{ Value = e.Left + d, Kind = "Edge" },
				{ Value = e.X + d, Kind = "Center" },
				{
					Value = e.Right + d,
					Kind = "Edge",
				},
			}
		end
		return {
			{ Value = e.Top + d, Kind = "Edge" },
			{ Value = e.Y + d, Kind = "Center" },
			{
				Value = e.Bottom + d,
				Kind = "Edge",
			},
		}
	end
	function A.Collect(roots)
		local targets = { X = {}, Y = {} }
		local selected, screens = {}, {}
		for _, o in ipairs(roots) do
			selected[o] = true
			local p = o.Parent
			while p do
				if p:IsA("ScreenGui") then
					screens[p] = true
					break
				end
				p = p.Parent
			end
		end
		local function addAxis(list, first, center, last, from, to, source)
			local n = #list
			list[n + 1] = { Value = first, Kind = "Edge", From = from, To = to, Source = source }
			list[n + 2] = { Value = center, Kind = "Center", From = from, To = to, Source = source }
			list[n + 3] = { Value = last, Kind = "Edge", From = from, To = to, Source = source }
		end
		local function add(center, size, rotation, source)
			local e = A.Extents({ Center = center, Size = size, Rotation = rotation })
			addAxis(targets.X, e.Left, e.X, e.Right, e.Top, e.Bottom, source)
			addAxis(targets.Y, e.Top, e.Y, e.Bottom, e.Left, e.Right, source)
		end
		local function addObject(o, rotation)
			local p, size = o.AbsolutePosition, o.AbsoluteSize
			add(Vector2.new(p.X + size.X * 0.5, p.Y + size.Y * 0.5), size, rotation, o)
		end
		local viewport = service.Workspace.CurrentCamera and service.Workspace.CurrentCamera.ViewportSize
		if viewport then
			add(Vector2.new(viewport.X * 0.5, viewport.Y * 0.5), viewport, 0, "Screen")
		end
		for screen in pairs(screens) do
			if screen.Enabled then
				addObject(screen, 0)
				local stack = screen:GetChildren()
				local index = 1
				while index <= #stack do
					local o = stack[index]
					index += 1
					if selected[o] or (o:IsA("GuiObject") and not o.Visible) then
						continue
					end
					if o:IsA("GuiObject") and Apps.GuiTransformSession.Visible(o) then
						addObject(o, o.AbsoluteRotation or 0)
					end
					for _, child in ipairs(o:GetChildren()) do
						stack[#stack + 1] = child
					end
				end
			end
		end
		for _, axis in ipairs({ "X", "Y" }) do
			table.sort(targets[axis], function(a, b)
				return a.Value < b.Value
			end)
			targets[axis].Sorted = true
		end
		return targets
	end
	function A.Snap(targets, features)
		local best, found = A.Threshold, {}
		for _, f in ipairs(features) do
			local first = 1
			if targets.Sorted then
				local low, high = 1, #targets + 1
				while low < high do
					local middle = math.floor((low + high) * 0.5)
					if targets[middle].Value < f.Value - A.Threshold then
						low = middle + 1
					else
						high = middle
					end
				end
				first = low
			end
			for index = first, #targets do
				local t = targets[index]
				if targets.Sorted and t.Value > f.Value + A.Threshold then
					break
				end
				if f.Kind == t.Kind then
					local delta = t.Value - f.Value
					local distance = math.abs(delta)
					if distance < math.abs(best) - 1e-6 then
						best = delta
						found = { t }
					elseif #found > 0 and math.abs(delta - best) < 1e-6 then
						found[#found + 1] = t
					end
				end
			end
		end
		return #found > 0 and best or 0, found
	end
	function A.Guides(xMatches, yMatches, bounds)
		local result, indexed = {}, {}
		local e = A.Extents(bounds)
		for _, pair in ipairs({ { "X", xMatches }, { "Y", yMatches } }) do
			local axis = pair[1]
			for _, target in ipairs(pair[2] or {}) do
				local key = axis .. target.Kind .. tostring(target.Value)
				local from = math.min(target.From, axis == "X" and e.Top or e.Left) - A.Overhang
				local to = math.max(target.To, axis == "X" and e.Bottom or e.Right) + A.Overhang
				local line = indexed[key]
				if line then
					line.From = math.min(line.From, from)
					line.To = math.max(line.To, to)
				else
					line = { Kind = target.Kind, Source = target.Source, From = from, To = to }
					line[axis] = target.Value
					result[#result + 1] = line
					indexed[key] = line
				end
			end
		end
		return result
	end
	return A
end
return { InitDeps = InitDeps, Main = Main }
