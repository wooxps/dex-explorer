--!strict

local Main, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, service = d.Main, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local V = { HandleSize = 8, RotateHitSize = 20 }
	local directions = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
	local function node(class, p)
		local o = Instance.new(class)
		for k, v in pairs(p) do
			o[k] = v
		end
		return o
	end
	local function transform(x, y, g)
		local r = math.rad(g.Rotation)
		local c, s = math.cos(r), math.sin(r)
		return Vector2.new(g.Center.X + x * c - y * s, g.Center.Y + x * s + y * c)
	end
	local function localPoint(p, g)
		local r = math.rad(-g.Rotation)
		local c, s = math.cos(r), math.sin(r)
		local x, y = p.X - g.Center.X, p.Y - g.Center.Y
		return x * c - y * s, x * s + y * c
	end
	function V.Create(gui, onPress)
		local view = { Handles = {}, Visible = false, Instances = {} }
		local root = node("Frame", {
			Name = "GuiSelection",
			Parent = gui,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			Active = false,
		})
		local body = node("TextButton", {
			Name = "MoveSurface",
			Parent = root,
			Size = UDim2.fromScale(1, 1),
			Text = "",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Selectable = false,
			Active = true,
			ZIndex = 1,
		})
		view.Body = body
		view.Root = root
		local outline = node("Frame", {
			Name = "Outline",
			Parent = root,
			Position = UDim2.fromOffset(-2, -2),
			Size = UDim2.new(1, 4, 1, 4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 2,
		})
		for _, edge in ipairs({
			{ "Top", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1) },
			{ "Bottom", UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1) },
			{ "Left", UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0) },
			{ "Right", UDim2.new(1, -1, 0, 0), UDim2.new(0, 1, 1, 0) },
		}) do
			node("Frame", {
				Name = edge[1],
				Parent = outline,
				Position = edge[2],
				Size = edge[3],
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Active = false,
				ZIndex = 2,
			})
		end
		view.Outline = outline
		local move = { Kind = "Move", X = 0, Y = 0 }
		if onPress then
			body.InputBegan:Connect(function(e)
				onPress(move, e)
			end)
		end
		for i, d in ipairs(directions) do
			local h = { Kind = "Resize", X = d[1], Y = d[2], Index = i }
			local f = node("TextButton", {
				Name = "Resize" .. i,
				Parent = gui,
				Size = UDim2.fromOffset(8, 8),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = "",
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderColor3 = Color3.fromRGB(136, 136, 136),
				BorderSizePixel = 1,
				Active = true,
				Selectable = false,
				AutoButtonColor = false,
				Visible = false,
				ZIndex = 4,
			})
			node("ImageLabel", {
				Name = "Shadow",
				Parent = f,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(-4, -3),
				BackgroundTransparency = 1,
				Image = Main.GetStudioAsset("native/gui-editor/resizeHandleDropShadow") or "",
				ImageColor3 = Color3.new(0, 0, 0),
				ImageTransparency = 0.6,
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(4, 4, 12, 12),
				ZIndex = 3,
				Active = false,
			})
			h.Frame = f
			view.Handles[#view.Handles + 1] = h
			if onPress then
				f.InputBegan:Connect(function(e)
					onPress(h, e)
				end)
			end
			local t = { Kind = "Rotate", X = d[1], Y = d[2], Index = i }
			t.Frame = node("TextButton", {
				Name = "Rotate" .. i,
				Parent = gui,
				Size = UDim2.fromOffset(20, 20),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = "",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				Selectable = false,
				Visible = false,
				ZIndex = 3,
			})
			view.Handles[#view.Handles + 1] = t
			if onPress then
				t.Frame.InputBegan:Connect(function(e)
					onPress(t, e)
				end)
			end
		end
		local guides = {}
		local edgeColor, centerColor = Color3.fromRGB(255, 8, 103), Color3.new(0, 1, 0)
		local function guideFrame(index)
			local f = guides[index]
			if not f then
				f = node("Frame", {
					Name = "AlignmentGuide" .. index,
					Parent = gui,
					Visible = false,
					BorderSizePixel = 0,
					BackgroundColor3 = edgeColor,
					Active = false,
					ZIndex = 1,
				})
				guides[index] = f
			end
			return f
		end
		guideFrame(1)
		guideFrame(2)
		view.Guides = guides
		local label = node("TextLabel", {
			Name = "Measurement",
			Parent = gui,
			BackgroundColor3 = Color3.fromRGB(35, 35, 35),
			BorderSizePixel = 0,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 12,
			Font = Enum.Font.BuilderSans,
			Visible = false,
			Size = UDim2.fromOffset(110, 22),
			ZIndex = 6,
			Active = false,
		})
		view.Measurement = label
		function view:SetReadout(text, p)
			label.Visible = text ~= nil
			if text then
				label.Text = text
				label.Position = UDim2.fromOffset(math.floor(p.X + 12), math.floor(p.Y + 18))
			end
		end
		function view:SetGuides(lines)
			local viewport = gui.AbsoluteSize
			local count = 0
			local function finite(value)
				return type(value) == "number" and value == value and math.abs(value) < math.huge
			end
			for _, line in ipairs(lines or {}) do
				local vertical = line.X ~= nil
				local axis = vertical and line.X or line.Y
				local from = line.From or 0
				local to = line.To or (vertical and viewport.Y or viewport.X)
				if finite(axis) and finite(from) and finite(to) then
					count += 1
					local f = guideFrame(count)
					local start, finish = math.min(from, to), math.max(from, to)
					f.BackgroundColor3 = line.Color or (line.Kind == "Center" and centerColor or edgeColor)
					f.Position = vertical and UDim2.fromOffset(axis, start) or UDim2.fromOffset(start, axis)
					f.Size = vertical and UDim2.fromOffset(1, math.max(1, finish - start))
						or UDim2.fromOffset(math.max(1, finish - start), 1)
					f.Visible = true
				end
			end
			for i = count + 1, #guides do
				guides[i].Visible = false
			end
		end
		function view:Update(g, tool, hover, active, capabilities)
			local old = self.Geometry
			local c = capabilities or { Move = true, Scale = true, Rotate = true }
			local signature = tostring(c.Move) .. tostring(c.Scale) .. tostring(c.Rotate)
			if
				self.Visible
				and g
				and old
				and old.Center.X == g.Center.X
				and old.Center.Y == g.Center.Y
				and old.Size.X == g.Size.X
				and old.Size.Y == g.Size.Y
				and old.Rotation == g.Rotation
				and self.Hover == hover
				and self.Active == active
				and self.CapabilitySignature == signature
			then
				return
			end
			self.Hover, self.Active, self.CapabilitySignature = hover, active, signature
			self.Geometry = g
			self.Capabilities = c
			self.Visible = g ~= nil
			if not g then
				self:Hide()
				return
			end
			root.Visible = true
			root.Position = UDim2.fromOffset(g.Center.X, g.Center.Y)
			root.Size = UDim2.fromOffset(g.Size.X, g.Size.Y)
			root.Rotation = g.Rotation
			body.Active = self.Capabilities.Move == true
			body.Visible = body.Active
			for _, h in ipairs(self.Handles) do
				local resize = h.Kind == "Resize"
				local enabled = resize and self.Capabilities.Scale or not resize and self.Capabilities.Rotate
				h.Visible = enabled == true
				h.Frame.Visible = h.Visible
				local extra = resize and 2 or 10
				h.Position = transform(h.X * (g.Size.X * 0.5 + extra), h.Y * (g.Size.Y * 0.5 + extra), g)
				h.Frame.Position = UDim2.fromOffset(h.Position.X, h.Position.Y)
				h.Frame.Rotation = g.Rotation
				if resize then
					h.Frame.BackgroundColor3 = (h == hover or h == active) and Color3.fromRGB(222, 222, 222)
						or Color3.new(1, 1, 1)
				end
			end
		end
		function view:HitTest(p)
			if not self.Visible or not self.Geometry then
				return nil
			end
			for _, kind in ipairs({ "Resize", "Rotate" }) do
				for _, h in ipairs(self.Handles) do
					if h.Visible and h.Kind == kind then
						local x, y = localPoint(p, { Center = h.Position, Rotation = self.Geometry.Rotation })
						local radius = kind == "Resize" and 6 or 10
						if math.abs(x) <= radius and math.abs(y) <= radius then
							return h
						end
					end
				end
			end
			local x, y = localPoint(p, self.Geometry)
			if
				self.Capabilities.Move
				and math.abs(x) <= self.Geometry.Size.X * 0.5
				and math.abs(y) <= self.Geometry.Size.Y * 0.5
			then
				return move
			end
			return nil
		end
		function view:Hide()
			self.Visible = false
			root.Visible = false
			for _, h in ipairs(self.Handles) do
				h.Frame.Visible = false
				h.Visible = false
			end
			self:SetGuides(nil)
			self:SetReadout(nil)
		end
		function view:Destroy()
			self:Hide()
			root:Destroy()
			for _, h in ipairs(self.Handles) do
				h.Frame:Destroy()
			end
			for _, f in ipairs(guides) do
				f:Destroy()
			end
			label:Destroy()
		end
		return view
	end
	return V
end
return { InitDeps = InitDeps, Main = CreateModule }
