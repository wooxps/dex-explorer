--!strict

local Main, Settings, service, createSimple

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Settings, service, createSimple = d.Main, d.Settings, d.service, d.createSimple
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Splash = {}
	local function ramp(t: number, start: number, duration: number): number
		local value = math.clamp((t - start) / duration, 0, 1)
		return value * value * (3 - 2 * value)
	end
	function Splash.Create(initStatus: string?)
		local theme = Settings.Theme
		local brand = theme.Brand or theme.Focus
		local text = Color3.fromRGB(246, 247, 249)
		local gui = createSimple("ScreenGui", {
			Name = "DexExplorerLoading",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = Main.DisplayOrders.Menu,
		})
		local panel = createSimple("Frame", {
			Name = "Status",
			Parent = gui,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(28, 29, 32),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -32, 0, 280),
			ClipsDescendants = true,
		})
		createSimple("UISizeConstraint", { Parent = panel, MaxSize = Vector2.new(488, 280) })
		createSimple("UIAspectRatioConstraint", {
			Parent = panel,
			AspectRatio = 488 / 280,
			AspectType = Enum.AspectType.FitWithinMaxSize,
			DominantAxis = Enum.DominantAxis.Width,
		})
		createSimple("UICorner", { Parent = panel, CornerRadius = UDim.new(0, 4) })
		local outline = createSimple("UIStroke", {
			Parent = panel,
			Color = Color3.fromRGB(91, 93, 100),
			Transparency = 1,
			Thickness = 1,
		})
		local slab = createSimple("Frame", {
			Name = "Slab",
			Parent = panel,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(34, 35, 39),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		})
		createSimple("UIGradient", {
			Parent = slab,
			Rotation = 35,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(0.602, 0),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
		createSimple("UICorner", { Parent = slab, CornerRadius = UDim.new(0, 4) })

		local titleMask = createSimple("Frame", {
			Name = "TitleMask",
			Parent = panel,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.096, 0.2),
			Size = UDim2.fromScale(0.43, 0.28),
		})
		local title = createSimple("TextLabel", {
			Name = "Title",
			Parent = titleMask,
			BackgroundTransparency = 1,
			Text = "Dex",
			Font = Enum.Font.BuilderSansBold,
			TextSize = 76,
			TextScaled = true,
			TextColor3 = text,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
		})
		createSimple("UITextSizeConstraint", { Parent = title, MinTextSize = 24, MaxTextSize = 76 })
		local subtitleMask = createSimple("Frame", {
			Name = "SubtitleMask",
			Parent = panel,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.096, 0.43),
			Size = UDim2.fromScale(0.44, 0.125),
		})
		local subtitle = createSimple("TextLabel", {
			Name = "Subtitle",
			Parent = subtitleMask,
			BackgroundTransparency = 1,
			Text = "Explorer",
			Font = Enum.Font.BuilderSansMedium,
			TextSize = 28,
			TextScaled = true,
			TextColor3 = theme.PlaceholderText,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
		})
		createSimple("UITextSizeConstraint", { Parent = subtitle, MinTextSize = 12, MaxTextSize = 28 })

		local mark = createSimple("Frame", {
			Name = "Brand",
			Parent = panel,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.77, 0.405),
			Size = UDim2.fromScale(0.28, 0.49),
		})
		local reveal = createSimple("Frame", {
			Name = "Reveal",
			Parent = mark,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(1, 1),
		})
		local image = Main.GetStudioAsset("branding/dex/toolbar-white-v1")
		local logo
		if image then
			logo = createSimple("ImageLabel", {
				Name = "Logo",
				Parent = reveal,
				BackgroundTransparency = 1,
				Image = image,
				ImageColor3 = text,
				ImageTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(1, 1),
			})
		else
			logo = createSimple("TextLabel", {
				Name = "LogoFallback",
				Parent = reveal,
				BackgroundTransparency = 1,
				Text = "D",
				Font = Enum.Font.BuilderSansBold,
				TextColor3 = text,
				TextSize = 104,
				TextScaled = true,
				TextTransparency = 1,
				Size = UDim2.fromScale(1, 1),
			})
		end

		local message = createSimple("TextLabel", {
			Name = "Message",
			Parent = panel,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.05, 0.76),
			Size = UDim2.fromScale(0.78, 0.08),
			Font = Enum.Font.BuilderSans,
			TextSize = 14,
			TextColor3 = theme.PlaceholderText,
			TextTransparency = 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = initStatus or "Loading Dex Explorer",
		})
		local percent = createSimple("TextLabel", {
			Name = "Percent",
			Parent = panel,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.86, 0.76),
			Size = UDim2.fromScale(0.09, 0.08),
			Font = Enum.Font.BuilderSans,
			TextSize = 14,
			TextColor3 = theme.PlaceholderText,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "0%",
		})
		local track = createSimple("Frame", {
			Name = "Progress",
			Parent = panel,
			BorderSizePixel = 0,
			BackgroundColor3 = theme.Outline2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.05, 0.88),
			Size = UDim2.new(0.9, 0, 0, 3),
			ClipsDescendants = true,
		})
		createSimple("UICorner", { Parent = track, CornerRadius = UDim.new(0, 2) })
		local fill = createSimple("Frame", {
			Name = "Fill",
			Parent = track,
			BorderSizePixel = 0,
			BackgroundColor3 = brand,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 1),
			ClipsDescendants = true,
		})
		createSimple("UICorner", { Parent = fill, CornerRadius = UDim.new(0, 2) })

		local elapsed, exitTime, progress, shown = 0, 0, 0, 0
		local closing, destroyed, connection = false, false, nil
		local function destroy()
			if destroyed then
				return
			end
			destroyed = true
			if connection then
				connection:Disconnect()
				connection = nil
			end
			gui:Destroy()
		end
		local function paint(dt)
			if destroyed then
				return
			end
			if Main.Alive == false then
				destroy()
				return
			end
			if not closing and elapsed >= 0.32 and shown == progress then
				return
			end
			if closing then
				exitTime += dt
			else
				elapsed += dt
			end
			local visible = 1 - ramp(exitTime, 0, 0.22)
			local enter = ramp(elapsed, 0, 0.24) * visible
			panel.BackgroundTransparency = 1 - enter
			outline.Transparency = 1 - 0.65 * enter
			slab.BackgroundTransparency = 1 - enter
			local content = ramp(elapsed, 0.04, 0.28) * visible
			title.TextTransparency = 1 - content
			subtitle.TextTransparency = 1 - content
			if image then
				logo.ImageTransparency = 1 - content
			else
				logo.TextTransparency = 1 - content
			end

			local status = ramp(elapsed, 0.08, 0.2) * visible
			message.TextTransparency = 1 - status
			percent.TextTransparency = 1 - status
			track.BackgroundTransparency = 1 - status
			fill.BackgroundTransparency = 1 - status
			shown += (progress - shown) * (1 - math.exp(-dt * 12))
			if math.abs(progress - shown) < 0.0005 then
				shown = progress
			end
			fill.Size = UDim2.fromScale(shown, 1)
			if closing and exitTime >= 0.22 then
				destroy()
			end
		end
		Main.SecureGui(gui)
		if Main.AddCleanup then
			Main.AddCleanup(destroy)
		end
		local ok, con = pcall(function()
			return service.RunService.RenderStepped:Connect(function(dt)
				if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then
					return
				end
				paint(math.min(dt, 0.25))
			end)
		end)
		if ok and con then
			connection = con
		else
			paint(1)
		end
		return {
			SetProgress = function(value, target)
				if destroyed or closing then
					return
				end
				if type(value) == "string" and value ~= message.Text then
					message.Text = value
				end
				if type(target) == "number" and target == target and target ~= math.huge and target ~= -math.huge then
					progress = math.max(progress, math.clamp(target, 0, 1))
					percent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
					if not connection then
						shown = progress
						fill.Size = UDim2.fromScale(progress, 1)
					end
				end
			end,
			Close = function()
				if destroyed or closing then
					return
				end
				closing = true
				shown = progress
				fill.Size = UDim2.fromScale(shown, 1)
				if not connection then
					destroy()
				end
			end,
		}
	end
	return Splash
end
local control = { InitDeps = InitDeps, Main = CreateModule }
if gethsfuncs then
	_G.moduleData = control
else
	return control
end
