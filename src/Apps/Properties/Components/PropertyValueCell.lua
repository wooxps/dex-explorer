--!strict

local Main, Lib, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(dependencies)
	Main, Lib, Settings = dependencies.Main, dependencies.Lib, dependencies.Settings
end
------------------------------ Module ------------------------------

local function CreateModule()
	local PropertyValueCell = {}
	function PropertyValueCell.PreviewText(text)
		if type(text) ~= "string" then
			return text
		end
		local preview = text:sub(1, 2048)
		local _, invalid = utf8.len(preview)
		if invalid then
			preview = preview:sub(1, invalid - 1)
		end
		preview = preview:gsub("[\r\n\t]+", " ")
		return preview .. (#text > 2048 and "…" or "")
	end
	function PropertyValueCell.Create(options)
		local propEntries = options.Entries
		local checkboxes = assert(options.Checkboxes, "PropertyValueCell requires checkbox controllers")
		local autoUpdateObjs = options.AutoUpdateObjs
		local Colors = options.Colors
		local function renderValue(prop, entryIndex)
			local inputProp = options.GetInputProp()
			local propName = prop.Name
			local typeData = prop.ValueType
			local typeName = typeData.Name
			local tags = prop.Tags
			local gName = prop.Class .. "." .. prop.Name .. (prop.SubName or "")
			local propObj = autoUpdateObjs[gName]
			local entryData = propEntries[entryIndex]
			local UDim2 = UDim2

			local guiElems = entryData.GuiElems
			local valueFrame = guiElems.ValueFrame
			local valueBox = guiElems.ValueBox
			valueFrame.ClipsDescendants = true
			valueBox.TextWrapped = false
			valueBox.TextTruncate = Enum.TextTruncate.AtEnd
			local colorButton = guiElems.ColorButton
			local colorPreview = guiElems.ColorPreview
			local gradient = guiElems.Gradient
			local enumArrow = guiElems.EnumArrow
			local checkbox = guiElems.Checkbox
			local rightButton = guiElems.RightButton
			local soundPreview = guiElems.SoundPreview

			local propVal = options.ReadValue(prop, propObj)
			local inputFullName = inputProp and (inputProp.Class .. "." .. inputProp.Name .. (inputProp.SubName or ""))

			local offset = 4
			local endOffset = 6

			if typeName == "Color3" or typeName == "BrickColor" or typeName == "ColorSequence" then
				colorButton.Visible = true
				enumArrow.Visible = false
				if propVal then
					gradient.Color = (typeName == "Color3" and ColorSequence.new(propVal))
						or (typeName == "BrickColor" and ColorSequence.new(propVal.Color))
						or propVal
				else
					gradient.Color = ColorSequence.new(Color3.new(1, 1, 1))
				end
				colorPreview.BorderColor3 = (typeName == "ColorSequence" and Color3.new(1, 1, 1) or Color3.new(0, 0, 0))
				offset = 22
				endOffset = 24 + (typeName == "ColorSequence" and 20 or 0)
			elseif typeData.Category == "Enum" then
				colorButton.Visible = false
				enumArrow.Visible = not prop.Tags.ReadOnly
				endOffset = 22
			elseif (gName == inputFullName and typeData.Category == "Class") or typeName == "NumberSequence" then
				colorButton.Visible = false
				enumArrow.Visible = false
				endOffset = 26
			else
				colorButton.Visible = false
				enumArrow.Visible = false
			end

			valueBox.Position = UDim2.new(0, offset, 0, 0)
			valueBox.Size = UDim2.new(1, -endOffset, 1, 0)

			local pickingObject = inputFullName == gName and typeData.Category == "Class"
			local sequence = typeName == "NumberSequence" or typeName == "ColorSequence"
			local native = guiElems.RightButtonNative
			if not native or native.Parent ~= rightButton then
				native = rightButton:FindFirstChild("Native")
				if native and not native:IsA("ImageLabel") then
					native:Destroy()
					native = nil
				end
				if not native then
					native = Instance.new("ImageLabel")
					native.Name = "Native"
					native.BackgroundTransparency = 1
					native.Visible = false
					native.AnchorPoint = Vector2.new(0.5, 0.5)
					native.Position = UDim2.fromScale(0.5, 0.5)
					native.Size = UDim2.fromOffset(16, 16)
					native.ScaleType = Enum.ScaleType.Fit
					native.Image = Main.GetStudioAsset and Main.GetStudioAsset("explorer/options") or ""
					native.ImageColor3 = Settings.Theme.Text
					native.ZIndex = rightButton.ZIndex + 1
					native.Parent = rightButton
				end
				guiElems.RightButtonNative = native
			end
			local ellipsis = sequence and not pickingObject
			local hasImage = type(native.Image) == "string" and native.Image ~= ""
			native.Visible = ellipsis and hasImage
			guiElems.RightButtonIcon.Visible = pickingObject
			rightButton.Text = ellipsis and not hasImage and "…" or ""
			if pickingObject then
				Main.MiscIcons:DisplayByKey(guiElems.RightButtonIcon, "Delete")
				rightButton.Visible = true
			elseif sequence then
				rightButton.Visible = true
			else
				rightButton.Visible = false
			end

			if typeName == "bool" or typeName == "PhysicalProperties" then
				valueBox.Visible = false
				checkbox.Visible = true
				soundPreview.Visible = false
				checkboxes[entryIndex].Disabled = tags.ReadOnly
				if typeName == "PhysicalProperties" and autoUpdateObjs[gName] then
					checkboxes[entryIndex]:SetState(propVal and true or false)
				else
					checkboxes[entryIndex]:SetState(propVal)
				end
			elseif typeName == "SoundPlayer" then
				valueBox.Visible = false
				checkbox.Visible = false
				soundPreview.Visible = true
				local playing = options.IsSoundPlaying()
				Main.MiscIcons:DisplayByKey(soundPreview.ControlButton.Icon, playing and "Pause" or "Play")
			else
				valueBox.Visible = true
				checkbox.Visible = false
				soundPreview.Visible = false

				if propVal ~= nil then
					if typeName == "Color3" then
						valueBox.Text = "[" .. Lib.ColorToBytes(propVal) .. "]"
					elseif typeData.Category == "Enum" then
						valueBox.Text = propVal.Name
					elseif options.RoundableTypes[typeName] and Settings.Properties.NumberRounding then
						local rawStr = options.FormatValue(prop, propVal)
						valueBox.Text = rawStr:gsub("-?%d+%.%d+", function(num)
							return tostring(tonumber(("%." .. Settings.Properties.NumberRounding .. "f"):format(num)))
						end)
					else
						local text = options.FormatValue(prop, propVal)
						text = PropertyValueCell.PreviewText(text)
						valueBox.Text = text
					end
				else
					valueBox.Text = ""
				end

				valueBox.TextColor3 = tags.ReadOnly and Colors.ReadOnly or Colors.Text
			end
		end

		return renderValue
	end
	return PropertyValueCell
end
return { InitDeps = InitDeps, Main = CreateModule }
