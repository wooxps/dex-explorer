--!strict

local Apps, env, service

local function InitDeps(deps)
	Apps, env, service = deps.Apps, deps.env, deps.service
end

local function Main()
	local Hover = {}
	function Hover.Create(content, cf)
		local panel = Instance.new("Frame")
		panel.Name = "EditorHover"
		panel.BackgroundColor3 = Color3.fromRGB(25, 26, 31)
		panel.BorderSizePixel = 0
		panel.ClipsDescendants = true
		panel.ZIndex = 32
		panel.Visible = false
		panel.Parent = content
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new()
		stroke.Thickness = 1
		stroke.LineJoinMode = Enum.LineJoinMode.Miter
		stroke.Parent = panel

		local function label(name, font)
			local object = Instance.new("TextLabel")
			object.Name = name
			object.Font = font
			object.TextSize = 14
			object.TextColor3 = Color3.new(1, 1, 1)
			object.BackgroundTransparency = 1
			object.TextXAlignment = Enum.TextXAlignment.Left
			object.TextYAlignment = Enum.TextYAlignment.Top
			object.RichText = true
			object.TextWrapped = true
			object.ZIndex = 33
			object.Parent = panel
			return object
		end
		local heading = label("Signature", Enum.Font.Code)
		local body = label("Description", Enum.Font.SourceSans)
		local bodyViewport = Instance.new("ScrollingFrame")
		bodyViewport.Name = "DescriptionViewport"
		bodyViewport.BackgroundTransparency = 1
		bodyViewport.BorderSizePixel = 0
		bodyViewport.ClipsDescendants = true
		bodyViewport.ScrollingDirection = Enum.ScrollingDirection.Y
		bodyViewport.ScrollBarThickness = 0
		bodyViewport.CanvasSize = UDim2.new()
		bodyViewport.ZIndex = 33
		bodyViewport.Parent = panel
		body.Parent = bodyViewport
		body.AutomaticSize = Enum.AutomaticSize.Y
		local link = Instance.new("TextButton")
		link.Name = "Link"
		link.Font = Enum.Font.SourceSans
		link.TextSize = 14
		link.TextColor3 = Color3.fromRGB(82, 139, 255)
		link.TextXAlignment = Enum.TextXAlignment.Left
		link.TextYAlignment = Enum.TextYAlignment.Top
		link.BackgroundTransparency = 1
		link.BorderSizePixel = 0
		link.RichText = true
		link.ZIndex = 34
		link.Parent = panel
		local url
		link.Activated:Connect(function()
			if not url or not panel.Visible then
				return
			end
			local opened = pcall(function()
				game:GetService("BrowserService"):OpenBrowserWindow(url)
			end)
			if not opened and type(env.setclipboard) == "function" and pcall(env.setclipboard, url) then
				link.Text = "Link copied"
			end
		end)
		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = Color3.new()
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.ZIndex = 33
		divider.Parent = panel

		local function measure(text, font, size, width)
			return service.TextService:GetTextSize(text, size, font, Vector2.new(width, 10000))
		end
		local view = { Gui = panel }
		local geometry
		local function layoutBody()
			if not geometry then
				return
			end
			local g = geometry
			local bodyHeight = math.max(g.BodyHeight, math.ceil(body.AbsoluteSize.Y))
			local panelHeight = math.min(g.Height - 4, g.TitleHeight + bodyHeight + g.LinkHeight + g.Gap + 14)
			local visibleHeight = math.max(0, panelHeight - g.BodyTop - 7 - (g.Footer and g.LinkHeight + g.Gap or 0))
			bodyViewport.Size = UDim2.new(1, -10 - g.Inset, 0, visibleHeight)
			bodyViewport.CanvasSize = UDim2.fromOffset(0, bodyHeight)
			bodyViewport.ScrollBarThickness = bodyHeight > visibleHeight and 4 or 0
			link.Position = UDim2.fromOffset(5, g.TitleHeight + 7 + (g.Footer and visibleHeight + g.Gap or 0))
			panel.Size = UDim2.fromOffset(g.PanelWidth, panelHeight)
			panel.Position = UDim2.fromOffset(
				math.clamp(math.round(g.X), 2, math.max(2, g.Width - g.PanelWidth - 2)),
				math.clamp(
					math.round(g.Y >= panelHeight and g.Y - panelHeight or g.Y + cf.FontSize),
					2,
					math.max(2, g.Height - panelHeight - 2)
				)
			)
		end
		body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutBody)
		function view:Contains(x, y)
			return panel.Visible and Apps.EditorHitTest.Contains(panel, x, y)
		end
		function view:Show(title, message, row, column, diagnostic, format, learnMore)
			local formatter = Apps.EditorDocumentationText
			local plain, rich = formatter.Format(message or "", format)
			url = if diagnostic
				then "https://create.roblox.com/docs/studio/script-editor#script-analysis"
				elseif type(learnMore) == "string" and learnMore:match("^https://create%.roblox%.com/") then learnMore
				else nil
			local caption = if diagnostic then "Syntax Error:" else "Open Documentation"
			local width = math.max(12, content.AbsoluteSize.X)
			local height = math.max(12, content.AbsoluteSize.Y)
			local linkWidth = url and math.ceil(measure(caption, link.Font, link.TextSize, 10000).X) + 1 or 0
			local inline = diagnostic and width > linkWidth + 60
			local bodyInset = inline and linkWidth + 4 or 0
			local textWidth = math.max(
				measure(title, heading.Font, cf.FontSize, 10000).X,
				measure(plain, body.Font, body.TextSize, 10000).X + bodyInset,
				linkWidth
			)
			local panelWidth = math.min(width - 4, math.min(560, math.max(60, math.ceil(textWidth) + 12)))
			local titleHeight = title ~= ""
					and math.max(cf.FontSize, measure(title, heading.Font, cf.FontSize, panelWidth - 10).Y) + 12
				or 0
			local bodyHeight = plain ~= ""
					and math.max(
						body.TextSize,
						measure(plain, body.Font, body.TextSize, math.max(1, panelWidth - 10 - bodyInset)).Y
					)
				or 0
			local linkHeight = url and not inline and 19 or 0
			local bodyTop = titleHeight + 7 + (diagnostic and linkHeight or 0)
			local lines = cf.GuiElems.LinesFrame or cf.Frame
			local display = cf:SourceToDisplay(row)
			if not display then
				panel.Visible = false
				return
			end
			local x = lines.AbsolutePosition.X
				- content.AbsolutePosition.X
				+ cf:GetColumnPixelX(column, row)
				- Apps.CodeViewport.ScrollPixelX(cf)
			local y = lines.AbsolutePosition.Y - content.AbsolutePosition.Y + (display - cf.ViewY) * cf.FontSize
			geometry = nil
			heading.Text = formatter.Escape(title)
			heading.TextSize = cf.FontSize
			heading.Position = UDim2.fromOffset(5, 6)
			heading.Size = UDim2.new(1, -10, 0, titleHeight)
			heading.Visible = titleHeight > 0
			divider.Position = UDim2.fromOffset(0, titleHeight)
			divider.Visible = heading.Visible and (bodyHeight > 0 or url ~= nil)
			body.Text = rich
			body.Visible = bodyHeight > 0
			bodyViewport.Position = UDim2.fromOffset(5 + bodyInset, bodyTop)
			bodyViewport.CanvasPosition = Vector2.new()
			bodyViewport.Visible = body.Visible
			body.Size = UDim2.fromOffset(math.max(1, panelWidth - 10 - bodyInset - 4), bodyHeight)
			link.Visible = url ~= nil
			link.Text = "<u>" .. caption .. "</u>"
			link.Size = UDim2.fromOffset(math.min(panelWidth - 10, linkWidth), 18)
			local footer = url ~= nil and not diagnostic
			geometry = {
				Width = width,
				Height = height,
				PanelWidth = panelWidth,
				X = x,
				Y = y,
				BodyHeight = bodyHeight,
				BodyTop = bodyTop,
				Inset = bodyInset,
				TitleHeight = titleHeight,
				LinkHeight = linkHeight,
				Footer = footer,
				Gap = footer and bodyHeight > 0 and 5 or 0,
			}
			layoutBody()
			panel.Visible = true
		end
		return view
	end
	return Hover
end

return { InitDeps = InitDeps, Main = Main }
