--!strict

local Main, Lib, API

------------------------------ Initialization ------------------------------

local function InitDeps(dependencies)
	Main, Lib, API = dependencies.Main, dependencies.Lib, dependencies.API
end

local function closeWidget(widget)
	if widget.Window then
		widget.Window:Close()
	elseif widget.Hide then
		widget:Hide()
	elseif widget.Close then
		widget:Close()
	end
end

------------------------------ Module ------------------------------

local function CreateModule()
	local ValueEditors = {}

	function ValueEditors.Create(options)
		local widgets, connections = {}, {}
		local active
		local initializing = false
		local destroyed = false
		local editors = {}
		local factories = options.Factories
			or {
				Enum = function()
					return Lib.ContextMenu.new()
				end,
				BrickColor = function()
					return Lib.BrickColorPicker.new()
				end,
				Color = function()
					return Lib.ColorPicker.new()
				end,
				NumberSequence = function()
					return Lib.NumberSequenceEditor.new()
				end,
				ColorSequence = function()
					return Lib.ColorSequenceEditor.new()
				end,
			}

		local function isCurrent(binding)
			local input = options.GetInputProp()
			return not destroyed and active == binding and (input == nil or input == binding.Property)
		end

		local function commit(binding, value)
			if initializing or not isCurrent(binding) then
				return
			end
			options.SetInputProp(nil)
			options.Commit(binding.Property, value)
		end

		local function getWidget(kind)
			if widgets[kind] then
				return widgets[kind]
			end
			local widget = factories[kind]()
			widgets[kind] = widget
			if kind ~= "Enum" then
				table.insert(
					connections,
					widget.OnSelect:Connect(function(value)
						local binding = active
						if not binding or binding.Kind ~= kind then
							return
						end
						if kind == "BrickColor" then
							value = BrickColor.new(value)
						elseif kind == "Color" and binding.Property.ValueType.Name == "BrickColor" then
							value = BrickColor.new(value)
						end
						commit(binding, value)
					end)
				)
			end
			if kind == "BrickColor" then
				widget.Gui.DisplayOrder = Main.DisplayOrders.Menu
				widget.ReverseYOffset = 22
				table.insert(
					connections,
					widget.OnMoreColors:Connect(function()
						local binding = active
						if not binding or binding.Kind ~= kind or not isCurrent(binding) or not binding.Color then
							return
						end
						local property = binding.Property
						if property.Class == "BasePart" and property.Name == "BrickColor" then
							for _, candidate in ipairs(API.Classes.BasePart.Properties) do
								if candidate.Name == "Color" then
									property = candidate
									break
								end
							end
						end
						local color = binding.Color.Color
						editors.Cancel()
						options.SetInputProp(property)
						editors.ShowColor(property, color)
					end)
				)
			end
			return widget
		end

		function editors.Cancel()
			active = nil
			for _, widget in pairs(widgets) do
				closeWidget(widget)
			end
		end

		local function beginEdit(kind, property)
			assert(not destroyed, "Property editor controller is destroyed")
			editors.Cancel()
			active = { Kind = kind, Property = property }
			return active, getWidget(kind)
		end

		function editors.ShowEnum(entryIndex)
			local property = options.GetInputProp()
			if not property or property.ValueType.Category ~= "Enum" then
				return
			end
			local enum = Enum[property.ValueType.Name]
			if not enum then
				return
			end
			local binding, menu = beginEdit("Enum", property)
			menu.Iconless, menu.MaxHeight, menu.ReverseYOffset = true, 200, 22
			menu:Clear()
			local items = enum:GetEnumItems()
			table.sort(items, function(left, right)
				return left.Name < right.Name
			end)
			for _, item in ipairs(items) do
				menu:Add({
					Name = item.Name,
					OnClick = function()
						commit(binding, item)
					end,
				})
			end
			local frame = options.Entries[entryIndex].GuiElems.ValueFrame
			menu.Width = frame.AbsoluteSize.X
			menu:Show(frame.AbsolutePosition.X, frame.AbsolutePosition.Y + 22)
		end

		function editors.ShowBrickColor(property, entryIndex, color)
			color = color or options.ReadFirst(property)
			if not color then
				return
			end
			local binding, picker = beginEdit("BrickColor", property)
			binding.Color = color
			picker:SetMoreColorsVisible(true)
			local frame = options.Entries[entryIndex].GuiElems.ValueFrame
			picker:Show(frame.AbsolutePosition.X, frame.AbsolutePosition.Y + 22, color.Color)
		end

		local function showValue(kind, property, value, setter)
			local _, widget = beginEdit(kind, property)
			if value == nil then
				value = options.ReadFirst(property)
			end
			initializing = true
			local success, problem = pcall(function()
				if value ~= nil then
					widget[setter](widget, value)
				end
			end)
			initializing = false
			if not success then
				editors.Cancel()
				error(problem, 0)
			end
			widget:Show()
		end

		function editors.ShowColor(property, value)
			showValue("Color", property, value, "SetColor")
		end

		function editors.ShowNumberSequence(property, value)
			showValue("NumberSequence", property, value, "SetSequence")
		end

		function editors.ShowColorSequence(property, value)
			showValue("ColorSequence", property, value, "SetSequence")
		end

		function editors.Destroy()
			if destroyed then
				return
			end
			destroyed = true
			editors.Cancel()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			for _, widget in pairs(widgets) do
				local gui = widget.Gui or (widget.Window and widget.Window.Gui)
				if gui then
					gui:Destroy()
				end
			end
			table.clear(connections)
			table.clear(widgets)
		end

		if Main.AddCleanup then
			Main.AddCleanup(editors.Destroy)
		end
		return editors
	end

	return ValueEditors
end

return { InitDeps = InitDeps, Main = CreateModule }
