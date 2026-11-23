--!strict

local Main

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main = d.Main
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Hit = {}
	function Hit.Pointer(input)
		if Main.Mouse and type(Main.Mouse.X) == "number" and type(Main.Mouse.Y) == "number" then
			return Main.Mouse.X, Main.Mouse.Y
		end
		if input and input.Position then
			return input.Position.X, input.Position.Y
		end
	end
	function Hit.Descendant(object, ancestor)
		while object do
			if object == ancestor then
				return true
			end
			object = object.Parent
		end
		return false
	end
	local function rect(gui, x, y)
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return x >= p.X and y >= p.Y and x < p.X + s.X and y < p.Y + s.Y
	end
	function Hit.Contains(gui, x, y)
		if not gui or not gui:IsA("GuiObject") or not rect(gui, x, y) then
			return false
		end
		local current = gui
		while current do
			if current:IsA("GuiObject") then
				if not current.Visible then
					return false
				end
				if current.ClipsDescendants and not rect(current, x, y) then
					return false
				end
			elseif current:IsA("LayerCollector") and not current.Enabled then
				return false
			end
			current = current.Parent
		end
		return true
	end
	local function layer(object)
		while object do
			if object:IsA("ScreenGui") then
				return object
			end
			object = object.Parent
		end
	end
	local function meaningful(object)
		return not (
			object.ClassName == "Frame"
			and (object.BackgroundTransparency or 0) >= 0.995
			and not object.Active
		)
	end
	local function subtreeBlocks(parent, x, y)
		for _, object in ipairs(parent:GetChildren()) do
			if object:IsA("GuiObject") then
				if not object.Visible then continue end
				local inside = rect(object, x, y)
				if inside and meaningful(object) and Hit.Contains(object, x, y) then return true end
				if not inside and object.ClipsDescendants then continue end
			elseif object:IsA("LayerCollector") and not object.Enabled then
				continue
			end
			if subtreeBlocks(object, x, y) then return true end
		end
		return false
	end
	function Hit.OwnsPoint(window, target, x, y, insideTarget)
		if not insideTarget and (not window:IsVisible() or not Hit.Contains(target, x, y)) then
			return false
		end
		local own = window.Gui
		local order = own.DisplayOrder or 0
		local root = window.Gui.Parent
		if root then
			local ok, objects = pcall(function()
				return root:GetGuiObjectsAtPosition(x, y)
			end)
			if ok and type(objects) == "table" then
				for _, object in ipairs(objects) do
					if meaningful(object) and Hit.Contains(object, x, y) then
						local screen = layer(object)
						if screen == own then
							return true
						end
						if
							screen
							and not screen:GetAttribute("DexCursorOverlay")
							and (screen.DisplayOrder or 0) >= order
						then
							return false
						end
					end
				end
			end
		end
		for gui in pairs(Main.InternalGuis or {}) do
			if
				gui ~= own
				and gui.Parent
				and gui:IsA("ScreenGui")
				and gui.Enabled
				and not gui:GetAttribute("DexCursorOverlay")
				and (gui.DisplayOrder or 0) > order
			then
				if subtreeBlocks(gui, x, y) then return false end
			end
		end
		return true
	end
	return Hit
end
return { InitDeps = InitDeps, InitAfterMain = function() end, Main = CreateModule }
