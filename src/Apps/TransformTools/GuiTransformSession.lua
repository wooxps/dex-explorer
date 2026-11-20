--!strict

local Apps, Main

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Main = d.Apps, d.Main
end
------------------------------ Module ------------------------------

local function CreateModule()
	local T = { MinimumSize = 1 }
	local function finite(n)
		return type(n) == "number" and n == n and math.abs(n) < 1e8
	end
	local function rotate(x, y, degrees)
		local r = math.rad(degrees)
		local c, s = math.cos(r), math.sin(r)
		return x * c - y * s, x * s + y * c
	end
	T.RotateVector = rotate
	local function screen(object)
		local p = object
		while p do
			if p:IsA("ScreenGui") then
				return p
			end
			if p:IsA("LayerCollector") then
				return nil
			end
			p = p.Parent
		end
	end
	local function eligible(object)
		return typeof(object) == "Instance"
			and object:IsA("GuiObject")
			and screen(object) ~= nil
			and not (Main.IsDexGuiObject and Main.IsDexGuiObject(object))
			and not (
				Apps.Explorer
				and Apps.Explorer.IsReadOnlyInferenceObject
				and Apps.Explorer.IsReadOnlyInferenceObject(object)
			)
	end
	function T.Collect(objects)
		local list, seen = {}, {}
		for _, value in ipairs(objects or {}) do
			local o = typeof(value) == "Instance" and value or type(value) == "table" and value.Obj
			if o and not seen[o] and eligible(o) then
				seen[o] = true
				list[#list + 1] = o
			end
		end
		local roots = {}
		for _, o in ipairs(list) do
			local p = o.Parent
			while p and not seen[p] do
				p = p.Parent
			end
			if not p then
				roots[#roots + 1] = o
			end
		end
		return roots
	end
	local function hierarchyVisible(p)
		while p do
			if p:IsA("GuiObject") and not p.Visible then
				return false
			end
			if p:IsA("ScreenGui") then
				return p.Enabled
			end
			p = p.Parent
		end
		return false
	end
	function T.Visible(object)
		if not hierarchyVisible(object) then return false end
		local size = object.AbsoluteSize
		return size.X > 0 and size.Y > 0
	end
	function T.Geometry(object)
		local p, s = object.AbsolutePosition, object.AbsoluteSize
		local center = Vector2.new(p.X + s.X * 0.5, p.Y + s.Y * 0.5)
		local angle = object.AbsoluteRotation or 0
		local r = math.rad(angle)
		local c, sine = math.cos(r), math.sin(r)
		local halfWidth, halfHeight = s.X * 0.5, s.Y * 0.5
		local wx, wy = halfWidth * c, halfWidth * sine
		local hx, hy = -halfHeight * sine, halfHeight * c
		local corners = {
			Vector2.new(center.X + (-wx - hx), center.Y + (-wy - hy)),
			Vector2.new(center.X + (wx - hx), center.Y + (wy - hy)),
			Vector2.new(center.X + (wx + hx), center.Y + (wy + hy)),
			Vector2.new(center.X + (-wx + hx), center.Y + (-wy + hy)),
		}
		return { Center = center, Size = s, Rotation = angle, Corners = corners }
	end
	function T.Bounds(roots, visibleOnly)
		if #roots == 0 then
			return nil
		end
		if #roots == 1 then
			if visibleOnly and not T.Visible(roots[1]) then return nil end
			return T.Geometry(roots[1])
		end
		local parents = visibleOnly and {} or nil
		local x, y, X, Y = math.huge, math.huge, -math.huge, -math.huge
		for _, o in ipairs(roots) do
			local size = o.AbsoluteSize
			if parents then
				local parent = o.Parent
				if not parent or not o.Visible or not (size.X > 0 and size.Y > 0) then return nil end
				local shown = parents[parent]
				if shown == nil then
					shown = hierarchyVisible(parent)
					parents[parent] = shown
				end
				if not shown then return nil end
			end
			local p = o.AbsolutePosition
			local w, h = size.X * 0.5, size.Y * 0.5
			local center = Vector2.new(p.X + w, p.Y + h)
			local angle = o.AbsoluteRotation or 0
			local dx, dy = math.abs(w), math.abs(h)
			if angle ~= 0 then
				local r = math.rad(angle)
				local c, s = math.cos(r), math.sin(r)
				dx, dy = math.abs(w * c) + math.abs(h * s), math.abs(w * s) + math.abs(h * c)
			end
			x, y = math.min(x, center.X - dx), math.min(y, center.Y - dy)
			X, Y = math.max(X, center.X + dx), math.max(Y, center.Y + dy)
		end
		local first, last = Vector2.new(x, y), Vector2.new(X, Y)
		x, y, X, Y = first.X, first.Y, last.X, last.Y
		return {
			Center = Vector2.new((x + X) * 0.5, (y + Y) * 0.5),
			Size = Vector2.new(X - x, Y - y),
			Rotation = 0,
			Corners = { first, Vector2.new(X, y), last, Vector2.new(x, Y) },
		}
	end
	local function parentLayout(parent)
		for _, child in parent:GetChildren() do
			if child:IsA("UIGridStyleLayout") or child:IsA("UIListLayout") or child:IsA("UIGridLayout")
				or child:IsA("UIPageLayout") or child:IsA("UITableLayout") then
				return child.ClassName
			end
		end
		return false
	end
	function T.CanEdit(object, tool, layouts)
		if not eligible(object) then
			return false, "Select a GUI object inside a ScreenGui."
		end
		local p = object.Parent
		while p and p:IsA("Folder") do
			p = p.Parent
		end
		if tool ~= "Rotate" and p then
			local layout
			if layouts then layout = layouts[p] end
			if layout == nil then
				layout = parentLayout(p)
				if layouts then layouts[p] = layout end
			end
			if layout then return false, "Position and size are controlled by " .. layout .. "." end
		end
		if tool == "Scale" then
			if object.AutomaticSize and object.AutomaticSize ~= Enum.AutomaticSize.None then
				return false, "Size is controlled by AutomaticSize."
			end
			for _, c in ipairs(object:GetChildren()) do
				if c:IsA("UIAspectRatioConstraint") or c:IsA("UISizeConstraint") then
					return false, "Size is controlled by " .. c.ClassName .. "."
				end
			end
		end
		return true
	end
	local function parentMetrics(parent)
		local factors, positionScale = {}, 1
		local ancestor = parent
		while ancestor and not ancestor:IsA("ScreenGui") do
			for _, c in ancestor:GetChildren() do
				if c:IsA("UIScale") then
					local factor = c.Scale
					factors[#factors + 1] = factor
					positionScale *= factor
				end
			end
			ancestor = ancestor.Parent
		end
		local p = parent
		while p and p:IsA("Folder") do
			p = p.Parent
		end
		local parentSize = p.AbsoluteSize
		local pw, ph = parentSize.X / positionScale, parentSize.Y / positionScale
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("UIPadding") then
				pw = pw * (1 - c.PaddingLeft.Scale - c.PaddingRight.Scale)
					- c.PaddingLeft.Offset
					- c.PaddingRight.Offset
				ph = ph * (1 - c.PaddingTop.Scale - c.PaddingBottom.Scale)
					- c.PaddingTop.Offset
					- c.PaddingBottom.Offset
			end
		end
		return { Factors = factors, PositionScale = positionScale, Width = pw, Height = ph,
			Rotation = p:IsA("GuiObject") and p.AbsoluteRotation or 0 }
	end
	local function snapshot(o, metrics)
		local sizeScale = 1
		for _, c in o:GetChildren() do
			if c:IsA("UIScale") then sizeScale *= c.Scale end
		end
		for _, factor in metrics.Factors do sizeScale *= factor end
		return {
			Position = o.Position,
			Size = o.Size,
			Rotation = o.Rotation,
			Parent = o.Parent,
			Anchor = o.AnchorPoint,
			Geometry = T.Geometry(o),
			ParentRotation = metrics.Rotation,
			ParentWidth = metrics.Width,
			ParentHeight = metrics.Height,
			PositionScale = metrics.PositionScale,
			SizeScale = sizeScale,
		}
	end
	local function state(o)
		return { Position = o.Position, Size = o.Size, Rotation = o.Rotation }
	end
	local function write(o, s)
		o.Position = s.Position
		o.Size = s.Size
		o.Rotation = s.Rotation
	end
	local function shifted(value, dx, dy, b)
		local function axis(v, delta, dimension)
			if v.Offset == 0 and v.Scale ~= 0 and dimension > 0 then
				return v.Scale + delta / dimension, 0
			end
			return v.Scale, v.Offset + delta
		end
		local x, X = axis(value.X, dx, b.ParentWidth)
		local y, Y = axis(value.Y, dy, b.ParentHeight)
		return UDim2.new(x, X, y, Y)
	end
	function T.Begin(objects, tool)
		local roots = T.Collect(objects)
		if #roots == 0 then
			return nil, "Select a GUI object inside a ScreenGui."
		end
		if tool == "Rotate" and #roots ~= 1 then
			return nil, "Rotate one GUI object at a time."
		end
		local records, layouts, parents = {}, {}, {}
		for _, o in ipairs(roots) do
			local ok, reason = T.CanEdit(o, tool, layouts)
			if not ok then
				return nil, reason
			end
			local metrics = parents[o.Parent]
			if not metrics then
				metrics = parentMetrics(o.Parent)
				parents[o.Parent] = metrics
			end
			local before = snapshot(o, metrics)
			if before.PositionScale <= 0 or before.SizeScale <= 0 then
				return nil, "A UIScale must be greater than zero."
			end
			records[#records + 1] = { Object = o, Before = before }
		end
		local bounds = T.Bounds(roots)
		local S = { Active = true, Roots = roots, Bounds = bounds, Records = records }
		local minimumUniformFactor = 0
		for _, r in ipairs(records) do
			local size = r.Before.Geometry.Size
			minimumUniformFactor = math.max(
				minimumUniformFactor,
				T.MinimumSize / math.max(size.X, 1e-7),
				T.MinimumSize / math.max(size.Y, 1e-7)
			)
		end
		local function restore()
			for _, r in ipairs(records) do
				pcall(write, r.Object, r.Before)
			end
		end
		local function preview(callback)
			if not S.Active then
				return false, "Gesture has ended."
			end
			local ok, problem = pcall(function()
				for _, r in ipairs(records) do
					if r.Object.Parent ~= r.Before.Parent or not eligible(r.Object) then
						error("A selected GUI object moved to another parent.", 0)
					end
					callback(r.Object, r.Before)
				end
			end)
			if not ok then
				restore()
				S.Active = false
				return false, tostring(problem)
			end
			return true
		end
		local function move(o, b, dx, dy)
			local x, y = rotate(dx, dy, -b.ParentRotation)
			o.Position = shifted(b.Position, x / b.PositionScale, y / b.PositionScale, b)
		end
		function S:Move(dx, dy)
			if not finite(dx) or not finite(dy) then
				return false, "Invalid GUI movement."
			end
			return preview(function(o, b)
				move(o, b, dx, dy)
			end)
		end
		function S:Resize(sx, sy, dx, dy, centered, uniform)
			if not finite(dx) or not finite(dy) then
				return false, "Invalid GUI size."
			end
			local x, y = rotate(dx, dy, -bounds.Rotation)
			local factor = centered and 2 or 1
			local width, height = math.max(1, bounds.Size.X), math.max(1, bounds.Size.Y)
			local fx = sx ~= 0 and math.max(1 / width, 1 + x * sx * factor / width) or 1
			local fy = sy ~= 0 and math.max(1 / height, 1 + y * sy * factor / height) or 1
			if uniform or #roots > 1 then
				local f = sx == 0 and fy or sy == 0 and fx or math.abs(fx - 1) > math.abs(fy - 1) and fx or fy
				f = math.max(f, minimumUniformFactor)
				fx, fy = f, f
			end
			return preview(function(o, b)
				local old = b.Geometry
				local w, h = old.Size.X * fx, old.Size.Y * fy
				local dcx, dcy
				if #roots == 1 then
					dcx, dcy = rotate(
						centered and 0 or sx * (w - old.Size.X) * 0.5,
						centered and 0 or sy * (h - old.Size.Y) * 0.5,
						bounds.Rotation
					)
				else
					local ax = centered and bounds.Center.X or bounds.Center.X - sx * width * 0.5
					local ay = centered and bounds.Center.Y or bounds.Center.Y - sy * height * 0.5
					dcx = (old.Center.X - ax) * (fx - 1)
					dcy = (old.Center.Y - ay) * (fy - 1)
				end
				local px, py = rotate(dcx, dcy, -b.ParentRotation)
				px += (b.Anchor.X - 0.5) * (w - old.Size.X)
				py += (b.Anchor.Y - 0.5) * (h - old.Size.Y)
				o.Position = shifted(b.Position, px / b.PositionScale, py / b.PositionScale, b)
				o.Size = shifted(b.Size, (w - old.Size.X) / b.SizeScale, (h - old.Size.Y) / b.SizeScale, b)
			end)
		end
		function S:Rotate(degrees)
			if not finite(degrees) then
				return false, "Invalid GUI rotation."
			end
			return preview(function(o, b)
				o.Rotation = (b.Rotation + degrees) % 360
			end)
		end
		function S:Cancel()
			restore()
			self.Active = false
			return true
		end
		function S:Commit()
			if not self.Active then
				return false, "Gesture has ended."
			end
			for _, r in ipairs(records) do
				if r.Object.Parent ~= r.Before.Parent then
					self:Cancel()
					return false, "A selected GUI object moved to another parent."
				end
			end
			local ok, problem = pcall(function()
				Apps.History.Run(tool .. " UI", function()
					for _, r in ipairs(records) do
						local o, b = r.Object, r.Before
						local after = state(o)
						if b.Position ~= after.Position or b.Size ~= after.Size or b.Rotation ~= after.Rotation then
							Apps.History.Record(function()
								return state(o)
							end, function(s)
								write(o, s)
							end, { Position = b.Position, Size = b.Size, Rotation = b.Rotation }, after)
						end
					end
				end)
			end)
			self.Active = false
			if not ok then
				restore()
				return false, tostring(problem)
			end
			if Apps.Properties and Apps.Properties.Refresh then
				pcall(Apps.Properties.Refresh)
			end
			return true
		end
		return S
	end
	return T
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
