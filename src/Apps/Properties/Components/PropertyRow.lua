--!strict

local Main, Lib, Apps, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Lib, Apps, service = d.Main, d.Lib, d.Apps, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Module = {}
	function Module.Create(Properties, ctx)
		local viewList, expanded, checkboxes = ctx.ViewList, ctx.Expanded, ctx.Checkboxes
		local function createRow(index)
			local newEntry = Properties.EntryTemplate:Clone()
			local nameFrame = newEntry.NameFrame
			local valueFrame = newEntry.ValueFrame
			local row = { Gui = newEntry }
			local hovered = false
			function row.PaintHover()
				local base = row.BaseColor
				if base then
					newEntry.BackgroundColor3 = hovered
							and not row.Editing
							and Color3.new(
								base.R + (1 - base.R) * 0.045,
								base.G + (1 - base.G) * 0.045,
								base.B + (1 - base.B) * 0.045
							)
						or base
				end
			end
			newEntry.MouseEnter:Connect(function()
				hovered = true
				row.PaintHover()
			end)
			newEntry.MouseLeave:Connect(function()
				hovered = false
				row.PaintHover()
			end)
			newEntry:GetPropertyChangedSignal("Visible"):Connect(function()
				if not newEntry.Visible then
					hovered = false
				end
			end)
			Lib.StudioTooltip(nameFrame, function()
				local prop = viewList[index + Properties.Index]
				if not prop or prop.CategoryName or prop.TagName or prop.Attribute then
					return nil
				end
				return Apps.ReflectionService.GetSummary(prop.Class, prop.Name)
			end)
			local newCheckbox = Lib.Checkbox.new(1)
			newCheckbox.Gui.AnchorPoint = Vector2.new(0, 0.5)
			newCheckbox.Gui.Position = UDim2.new(0, 5, 0.5, 0)
			newCheckbox.Gui.Parent = valueFrame
			newCheckbox.OnInput:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end

				if prop.ValueType.Name == "PhysicalProperties" then
					Properties.SetProp(prop, newCheckbox.Toggled and true or nil)
				else
					Properties.SetProp(prop, newCheckbox.Toggled)
				end
			end)
			checkboxes[index] = newCheckbox

			local iconFrame = Main.MiscIcons:GetLabel()
			iconFrame.Position = UDim2.new(0, 2, 0, 3)
			iconFrame.Parent = newEntry.ValueFrame.RightButton

			newEntry.Position = UDim2.fromOffset(0, 0)

			nameFrame.Expand.InputBegan:Connect(function(input)
				local prop = viewList[index + Properties.Index]
				if not prop or input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end

				local fullName = (prop.CategoryName and "CAT_" .. prop.CategoryName)
					or prop.Class .. "." .. prop.Name .. (prop.SubName or "")

				Lib.StudioChevron(newEntry.NameFrame.Expand, expanded[fullName], true)
			end)

			nameFrame.Expand.InputEnded:Connect(function(input)
				local prop = viewList[index + Properties.Index]
				if not prop or input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end

				local fullName = (prop.CategoryName and "CAT_" .. prop.CategoryName)
					or prop.Class .. "." .. prop.Name .. (prop.SubName or "")

				Lib.StudioChevron(newEntry.NameFrame.Expand, expanded[fullName], false)
			end)

			nameFrame.Expand.MouseButton1Down:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end

				local fullName = (prop.CategoryName and "CAT_" .. prop.CategoryName)
					or prop.Class .. "." .. prop.Name .. (prop.SubName or "")
				if
					not prop.CategoryName
					and not Properties.ExpandableTypes[prop.ValueType and prop.ValueType.Name]
					and not Properties.ExpandableProps[fullName]
				then
					return
				end

				expanded[fullName] = not expanded[fullName]
				Properties.Update()
				Properties.Refresh()
			end)

			nameFrame.PropName.InputBegan:Connect(function(input)
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseMovement and not nameFrame.PropName.TextFits then
					local fullNameFrame = Properties.FullNameFrame
					local nameArr = string.split(prop.Class .. "." .. prop.Name .. (prop.SubName or ""), ".")
					local dispName = prop.DisplayName or nameArr[#nameArr]
					local sizeX =
						service.TextService:GetTextSize(dispName, 14, Lib.StudioFont, Vector2.new(math.huge, 20)).X

					fullNameFrame.TextLabel.Text = dispName
					fullNameFrame.Size = UDim2.new(0, sizeX + 4, 0, 22)
					fullNameFrame.Visible = true
					Properties.FullNameFrameIndex = index
					Properties.FullNameFrameAttach.SetData(fullNameFrame, { Target = nameFrame })
					Properties.FullNameFrameAttach.Enable()
				end
			end)

			nameFrame.PropName.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					and Properties.FullNameFrameIndex == index
				then
					Properties.FullNameFrame.Visible = false
					Properties.FullNameFrameAttach.Disable()
				end
			end)

			valueFrame.ValueBox.MouseButton1Down:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end
				if prop.Name == "Source" and Apps.ScriptViewer then
					local selected = Apps.Explorer.Selection.List[1]
					if selected and selected.Obj:IsA("LuaSourceContainer") then
						Apps.ScriptViewer.ViewScript(selected.Obj)
						return
					end
				end
				Properties.SetInputProp(prop, index)
			end)

			valueFrame.ColorButton.MouseButton1Down:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end

				Properties.SetInputProp(prop, index, "color")
			end)

			valueFrame.RightButton.MouseButton1Click:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end

				local fullName = prop.Class .. "." .. prop.Name .. (prop.SubName or "")
				local inputFullName = ctx.GetInputProp()
					and (
						ctx.GetInputProp().Class
						.. "."
						.. ctx.GetInputProp().Name
						.. (ctx.GetInputProp().SubName or "")
					)

				if fullName == inputFullName and ctx.GetInputProp().ValueType.Category == "Class" then
					ctx.SetInputProp(nil)
					Properties.SetProp(prop, nil)
				else
					Properties.SetInputProp(prop, index, "right")
				end
			end)

			Lib.StudioTooltip(nameFrame.ToggleAttributes, "Add")
			nameFrame.ToggleAttributes.Activated:Connect(function()
				local prop = viewList[index + Properties.Index]
				if prop and prop.CategoryName == "Tags" then
					Properties.DisplayTagMenu(nameFrame.ToggleAttributes)
					return
				end
				Properties.DisplayAddAttributeWindow()
			end)

			newEntry.TagRemove.Activated:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop or not prop.TagName then
					return
				end
				Apps.History.Run("Remove tag", function()
					for _, node in ipairs(Apps.Explorer.Selection.List) do
						Apps.History.Tag(node.Obj, prop.TagName, false)
					end
				end)
				Properties.ShowExplorerProps()
			end)

			newEntry.EditAttributeButton.Activated:Connect(function()
				local prop = viewList[index + Properties.Index]
				if not prop then
					return
				end

				Properties.DisplayAttributeContext(prop, newEntry.EditAttributeButton)
			end)

			valueFrame.SoundPreview.ControlButton.MouseButton1Click:Connect(function()
				if Properties.PreviewSound and Properties.PreviewSound.Playing then
					Properties.SetSoundPreview(false)
				else
					local soundObj = Properties.FindFirstObjWhichIsA("Sound")
					if soundObj then
						Properties.SetSoundPreview(soundObj)
					end
				end
			end)

			valueFrame.SoundPreview.InputBegan:Connect(function(input)
				local touch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
				if not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
					return
				end

				local releaseEvent, mouseEvent
				releaseEvent = Main.TrackSignal(service.UserInputService.InputEnded, function(input)
					if (touch and input ~= touch) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
						return
					end
					releaseEvent:Disconnect()
					mouseEvent:Disconnect()
				end)

				local timeLine = newEntry.ValueFrame.SoundPreview.TimeLine
				local soundObj = Properties.FindFirstObjWhichIsA("Sound")
				if soundObj then
					Properties.SetSoundPreview(soundObj, true)
				end

				local function update(input)
					local sound = Properties.PreviewSound
					if not sound or sound.TimeLength == 0 then
						return
					end

					local mouseX = input.Position.X
					local timeLineSize = timeLine.AbsoluteSize
					local relaX = mouseX - timeLine.AbsolutePosition.X

					if timeLineSize.X <= 1 then
						return
					end
					if relaX < 0 then
						relaX = 0
					elseif relaX >= timeLineSize.X then
						relaX = timeLineSize.X - 1
					end

					local perc = (relaX / (timeLineSize.X - 1))
					sound.TimePosition = perc * sound.TimeLength
					timeLine.Slider.Position = UDim2.new(perc, -4, 0, -8)
				end
				update(input)

				mouseEvent = Main.TrackSignal(service.UserInputService.InputChanged, function(input)
					if input == touch or not touch and input.UserInputType == Enum.UserInputType.MouseMovement then
						update(input)
					end
				end)
			end)

			newEntry.Parent = ctx.GetFrame()

			row.GuiElems = {
				NameFrame = nameFrame,
				ValueFrame = valueFrame,
				PropName = nameFrame.PropName,
				ValueBox = valueFrame.ValueBox,
				Expand = nameFrame.Expand,
				ColorButton = valueFrame.ColorButton,
				ColorPreview = valueFrame.ColorButton.ColorPreview,
				Gradient = valueFrame.ColorButton.ColorPreview.UIGradient,
				EnumArrow = valueFrame.EnumArrow,
				Checkbox = valueFrame.Checkbox,
				RightButton = valueFrame.RightButton,
				RightButtonIcon = iconFrame,
				RowButton = newEntry.RowButton,
				EmptyAttributes = newEntry.EmptyAttributes,
				TagRemove = newEntry.TagRemove,
				EditAttributeButton = newEntry.EditAttributeButton,
				ToggleAttributes = nameFrame.ToggleAttributes,
				SoundPreview = valueFrame.SoundPreview,
				SoundPreviewSlider = valueFrame.SoundPreview.TimeLine.Slider,
			}
			return row
		end

		return createRow
	end
	return Module
end
return { InitDeps = InitDeps, Main = CreateModule }
