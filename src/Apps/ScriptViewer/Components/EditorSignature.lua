--!strict

local Apps, Lib, service

local function InitDeps(deps)
	Apps, Lib, service = deps.Apps, deps.Lib, deps.service
end

local function Main()
	local Signature = {}
	local opens = { [40] = true, [91] = true, [123] = true }
	local closes = { [41] = 40, [93] = 91, [125] = 123 }
	local black = Color3.new()
	local padding = 5
	local docsSize = 14

	local function findCalls(source, position, checkpoint)
		local stack = {}
		local index = 1
		local nextCheck = 1
		while true do
			index = source:find("[%(%)%[%]{},]", index)
			if not index or index >= position then
				break
			end
			if checkpoint and index >= nextCheck then
				if not checkpoint() then
					return nil
				end
				nextCheck = index + 4096
			end
			local byte = source:byte(index)
			if opens[byte] then
				stack[#stack + 1] = { Open = byte, Position = index, Argument = 1 }
			elseif stack[#stack] then
				local current = stack[#stack]
				if closes[byte] == current.Open then
					stack[#stack] = nil
				elseif byte == 44 then
					current.Argument += 1
				end
			end
			index += 1
		end
		return stack
	end

	local function parsedCalls(symbols, position, checkpoint)
		local record = symbols.Record
		if not record or not record.Diagnostics.Passed then
			local stack = findCalls(symbols.Masked, position, checkpoint)
			if not stack or #stack == 0 then return stack, 0 end
			return stack, Apps.EditorDocument.OpenFunctionAt(symbols.Source, position, checkpoint)
		end
		local stack, boundary = {}, 0
		local function offset(point)
			return record.Starts[point.x + 1] + point.y
		end
		for index, call in record.Calls do
			if checkpoint and index % 128 == 0 and not checkpoint() then return nil end
			local first = offset(call.argLocation.begin)
			local last = offset(call.argLocation.end_)
			if first <= position and position < last and symbols.Source:byte(first - 1) == 40 then
				local argument = 1
				for i, arg in call.args do
					local finish = offset(arg.location.end_)
					argument = i
					if position <= finish then break end
					local nextArg = call.args[i + 1]
					if nextArg and position <= offset(nextArg.location.begin) then
						local comma = symbols.Masked:find(",", finish, true)
						if comma and comma < position then argument += 1 end
						break
					end
				end
				stack[#stack + 1] = {Open = 40, Position = first - 1, Argument = argument}
			end
		end
		table.sort(stack, function(left, right) return left.Position < right.Position end)
		for _, fn in symbols.FunctionScopes do
			if fn.HeaderEnd and position >= fn.HeaderEnd and position < fn.BodyEnd then
				boundary = math.max(boundary, fn.HeaderEnd - 1)
			end
		end
		return stack, boundary
	end

	local function activeSignature(source, active)
		local escape = Apps.EditorDocumentationText.Escape
		local closing = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }
		local stack, argument, first = {}, 1, nil
		for _, token in Apps.EditorDefinitions.Tokenize(source) do
			if token.Kind ~= "symbol" then
				continue
			end
			local value = token.Value
			local depth = #stack
			if first and depth == 1 and (value == "," or value == ")") then
				local parameter = source:sub(first, token.First - 1)
				local leading, trimmed = parameter:match("^(%s*)(.-)%s*$")
				if trimmed ~= "" and (argument == active or trimmed:match("^%.%.%.")) then
					local start = first + #leading
					return escape(source:sub(1, start - 1))
						.. "<b>"
						.. escape(trimmed)
						.. "</b>"
						.. escape(source:sub(start + #trimmed))
				end
				if value == ")" then
					break
				end
				argument += 1
				first = token.Last
			elseif closing[value] then
				if depth == 0 and value == "(" then
					first = token.Last
				end
				stack[depth + 1] = closing[value]
			elseif value == stack[depth] then
				stack[depth] = nil
			end
		end
		return escape(source)
	end

	local function resolveSignature(language, source, call, context, checkpoint)
		local symbols = language.Symbols
		local prefixStart = math.max(1, call.Position - 512)
		local prefix = symbols.Masked:sub(prefixStart, call.Position - 1)
		local token, member = prefix:match("()(%f[%w_][%a_][%w_]*)%s*$")
		if not token then
			return
		end
		local receiverStart, receiver, separator = prefix:sub(1, token - 1):match("()([%a_][%w_%.:]*)%s*([.:])%s*$")
		separator = separator or prefix:sub(1, token - 1):match("([.:])%s*$")
		local name = receiver and receiver .. separator .. member or member
		local first = receiverStart or token
		local before = prefix:sub(1, first - 1)
		if before:match("%f[%w_]function%s*$") or before:match("%f[%w_]typeof%s*$") then
			return
		end
		local declaration = symbols:Find(name, call.Position)
		if declaration and declaration.Position == prefixStart + first - 1 then
			return
		end
		if declaration and declaration.Kind == "Function" and declaration.Signature:find(":", 1, true) then
			return declaration.Signature, declaration.Documentation
		end
		local method = separator and member
		local className
		if receiver then
			local _, class = symbols:Resolve(receiver, context, call.Position)
			local alias = symbols:Find(receiver, call.Position)
			className = class or (alias and alias.Annotation)
		end
		local detail, owner = Apps.EditorLanguage.MemberSignature(className, method, separator == ".")
		if not detail and (declaration or separator or not Apps.EditorApiDocumentation.Signature(name)) then
			local at = prefixStart + token - 1
			local item = language:Hover(source, at, context, checkpoint)
			if checkpoint and not checkpoint() then
				return
			end
			local occurrence = language.HoverAnalysis and language.HoverAnalysis.Entries[at]
			local types = Apps.EditorHoverTypes
			local inferred = types.Resolve(types.TypeAt(occurrence))
			if type(inferred) == "table" and inferred.Kind == "function" then
				local params = inferred.Params
				local args = table.clone(params)
				if inferred.Method and separator == "." then
					table.insert(args, 1, { Name = "self", Type = occurrence and occurrence.Owner or "unknown" })
				elseif not inferred.Method and separator == ":" and #params > 0 then
					table.remove(args, 1)
				end
				local callable = table.clone(inferred)
				callable.Params = args
				return member .. types.Describe(callable):sub(#"function" + 1),
					item and item.Documentation,
					item and item.DocumentationFormat
			elseif item and (item.Kind == "Method" or item.Kind == "Function") then
				local signature = item.HoverDetail or item.Detail
				if signature and signature:find("(", 1, true) then
					return signature:gsub("^.*[.:]([%w_]+)(%()", "%1%2", 1),
						item.Documentation,
						item.DocumentationFormat
				end
			end
			if declaration then
				if declaration.Kind == "Function" then
					return declaration.Signature, declaration.Documentation
				end
				return
			end
		end
		local record = Apps.EditorApiDocumentation.Apply({
			Name = method or name,
			Detail = detail or name,
			DocKey = owner and "@roblox/globaltype/" .. owner .. "." .. method,
			DocGlobal = not owner and (not receiver or not className) and name or nil,
			DocCallable = detail == nil,
		}, call.Argument)
		local signature = receiver and record.Detail:gsub("^" .. receiver:gsub("(%W)", "%%%1") .. "%.", "", 1)
			or record.Detail
		return signature, record.Documentation, record.DocumentationFormat
	end

	local function label(name, parent, font, size)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Font = font
		item.TextSize = size
		item.TextColor3 = Color3.new(1, 1, 1)
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.TextYAlignment = Enum.TextYAlignment.Center
		item.TextWrapped = true
		item.RichText = true
		item.ZIndex = 20
		item.Parent = parent
		return item
	end

	function Signature.Create(content, cf, language, context, replaceColor)
		local frame = Instance.new("ScrollingFrame")
		frame.Name = "SignatureHelp"
		frame.Visible = false
		frame.ZIndex = 19
		frame.BackgroundColor3 = Color3.fromRGB(25, 27, 31)
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		frame.ScrollingDirection = Enum.ScrollingDirection.Y
		frame.ScrollBarThickness = 0
		frame.ScrollBarImageColor3 = Color3.fromRGB(179, 179, 179)
		frame.CanvasSize = UDim2.new()
		frame.Parent = content
		local outline = Instance.new("UIStroke")
		outline.Name = "Outline"
		outline.Color = black
		outline.Thickness = 1
		outline.Parent = frame
		local signature = label("Signature", frame, Enum.Font.Code, cf.FontSize)
		local description = label("Description", frame, Enum.Font.SourceSans, docsSize)
		description.LineHeight = 1.2
		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = black
		divider.BorderSizePixel = 0
		divider.ZIndex = 20
		divider.Parent = frame
		local self = { Gui = frame }
		local swatch = Instance.new("TextButton")
		swatch.Name = "ColorSwatch"
		swatch.Text = ""
		swatch.Size = UDim2.fromOffset(16, 16)
		swatch.BorderSizePixel = 1
		swatch.BorderColor3 = black
		swatch.ZIndex = 21
		swatch.Visible = false
		swatch.Parent = content
		self.Swatch = swatch
		local picker, binding, selected
		function self:ContainsSwatch(x, y)
			return Apps.EditorHitTest.Contains(swatch, x, y)
		end
		function self:Hide()
			frame.Visible = false
			swatch.Visible = false
			binding = nil
		end
		function self:Destroy()
			if picker then
				picker.Window:Close()
				picker.Window.Gui:Destroy()
			end
			swatch:Destroy()
			frame:Destroy()
		end
		swatch.MouseButton1Click:Connect(function()
			if not binding or not replaceColor or not Lib.ColorPicker then
				return
			end
			if not picker then
				picker = Lib.ColorPicker.new()
				picker.OnSelect:Connect(function(color)
					local target = selected
					selected = nil
					if not target then
						return
					end
					local value
					if target.Method == "fromRGB" then
						value = string.format(
							"%d, %d, %d",
							math.round(color.R * 255),
							math.round(color.G * 255),
							math.round(color.B * 255)
						)
					elseif target.Method == "fromHSV" then
						local h, s, v = color:ToHSV()
						value = string.format("%.6g, %.6g, %.6g", h, s, v)
					else
						value = string.format("%.6g, %.6g, %.6g", color.R, color.G, color.B)
					end
					replaceColor(target, value)
				end)
			end
			selected = binding
			picker:SetColor(binding.Color)
			picker:Show()
		end)

		local function updateSwatch(call, source, masked, scope, x, y, above)
			binding = nil
			swatch.Visible = false
			local method =
				masked:sub(math.max(1, call.Position - 24), call.Position - 1):match("%f[%w_]Color3%.([%w_]+)%s*$")
			if method ~= "new" and method ~= "fromRGB" and method ~= "fromHSV" then
				return
			end
			local finish = source:find(")", call.Position + 1, true)
			if not finish then
				return
			end
			local args = source:sub(call.Position + 1, finish - 1)
			local components = args:split(",")
			if #components < 1 or #components > 3 or (method == "fromHSV" and #components ~= 3) then
				return
			end
			local values = { 0, 0, 0 }
			for index, value in ipairs(components) do
				local n = tonumber(value)
				if not n or n ~= n or math.abs(n) == math.huge then
					return
				end
				values[index] = n
			end
			local constructor = Color3[method]
			if type(constructor) ~= "function" then
				return
			end
			local ok, color = pcall(constructor, table.unpack(values))
			if not ok then
				return
			end
			binding = {
				Method = method,
				Color = color,
				Source = source,
				Document = scope.Document,
				First = call.Position + 1,
				Last = finish,
			}
			swatch.BackgroundColor3 = color
			local swatchSize = swatch.Size.X.Offset
			local maxX = content.AbsoluteSize.X - swatchSize - 1
			local maxY = content.AbsoluteSize.Y - swatchSize - 1
			if maxX < 1 or maxY < 1 then
				return
			end
			local swatchY = if above then y + cf.FontSize + 2 else y - swatchSize - 2
			if swatchY < 1 or swatchY > maxY then
				x += 4
				swatchY = if above then y else y + cf.FontSize - swatchSize
			end
			swatch.Position =
				UDim2.fromOffset(math.clamp(math.round(x), 1, maxX), math.clamp(math.round(swatchY), 1, maxY))
			swatch.Visible = true
		end

		local function measure(text, size, font, width)
			return service.TextService:GetTextSize(text, size, font, Vector2.new(width, 10000))
		end
		function self:Update(position, checkpoint)
			local source = cf:GetText()
			if #source > 1000000 or #cf.Lines > 5000 then
				self:Hide()
				return
			end
			if not language:Index(source, checkpoint) then
				return
			end
			local symbols = language.Symbols
			local stack, boundary = parsedCalls(symbols, position, checkpoint)
			if not stack then
				return
			end
			if #stack == 0 then
				self:Hide()
				return
			end
			if boundary == nil then
				return
			end
			local scope = context()
			local call, detail, body, format
			for index = #stack, 1, -1 do
				local candidate = stack[index]
				if candidate.Position <= boundary then
					break
				end
				if candidate.Open == 40 then
					detail, body, format = resolveSignature(language, source, candidate, scope, checkpoint)
					if checkpoint and not checkpoint() then
						return
					end
					if detail and detail:find("(", 1, true) then
						call = candidate
						break
					end
				end
			end
			if not call then
				self:Hide()
				return
			end
			local text, rich = Apps.EditorDocumentationText.Format(body or "", format)
			local hasDescription = text ~= ""
			local fontSize = cf.FontSize
			local maximumWidth = math.max(1, math.min(50 * fontSize, content.AbsoluteSize.X - 2))
			local width = math.clamp(
				math.ceil(
					math.max(
						measure(detail, fontSize, Enum.Font.Code, 10000).X,
						hasDescription and measure(text, docsSize, Enum.Font.SourceSans, 10000).X or 0
					)
				) + 2 * padding,
				1,
				maximumWidth
			)
			local innerWidth = math.max(1, width - 2 * padding)
			local headerHeight = math.max(fontSize + 16, measure(detail, fontSize, Enum.Font.Code, innerWidth).Y + 12)
			local bodyHeight = 0
			if hasDescription then
				local measured = measure(text, docsSize, Enum.Font.SourceSans, innerWidth).Y
				bodyHeight = math.max(26, math.ceil(measured + math.max(0, measured - docsSize) * 0.2 + 10))
			end
			local height = headerHeight + (hasDescription and bodyHeight + 1 or 0)
			signature.Text = activeSignature(detail, call.Argument)
			signature.TextSize = fontSize
			signature.Position = UDim2.fromOffset(padding, 0)
			signature.Size = UDim2.fromOffset(innerWidth, headerHeight)
			divider.Visible = hasDescription
			divider.Position = UDim2.fromOffset(0, headerHeight)
			divider.Size = UDim2.new(1, 0, 0, 1)
			description.Visible = hasDescription
			description.Text = rich
			description.Position = UDim2.fromOffset(padding, headerHeight + 1)
			description.Size = UDim2.fromOffset(innerWidth, bodyHeight)

			local lines = cf.GuiElems.LinesFrame or cf.Frame
			local x = lines.AbsolutePosition.X
				- content.AbsolutePosition.X
				+ cf:GetColumnPixelX(cf.CursorX, cf.CursorY)
				- Apps.CodeViewport.ScrollPixelX(cf)
			local y = lines.AbsolutePosition.Y
				- content.AbsolutePosition.Y
				+ ((cf:SourceToDisplay(cf.CursorY) or cf.CursorY) - cf.ViewY) * fontSize
			local aboveRoom = math.max(0, math.floor(y) - 2)
			local belowRoom = math.max(0, math.floor(content.AbsoluteSize.Y - y - fontSize) - 2)
			local above = height <= aboveRoom or aboveRoom >= belowRoom
			local visible = math.min(height, above and aboveRoom or belowRoom)
			if visible < math.min(headerHeight, fontSize + 4) then
				self:Hide()
				return
			end
			frame.Size = UDim2.fromOffset(width, visible)
			frame.CanvasSize = UDim2.fromOffset(0, height)
			frame.CanvasPosition = Vector2.new()
			frame.ScrollBarThickness = visible < height and 4 or 0
			frame.Position = UDim2.fromOffset(
				math.clamp(math.round(x), 1, math.max(1, content.AbsoluteSize.X - width - 1)),
				if above then math.round(y) - visible - 1 else math.round(y + fontSize) + 1
			)
			frame.Visible = true
			updateSwatch(call, source, symbols.Masked, scope, x, y, above)
		end
		return self
	end
	return Signature
end

return { InitDeps = InitDeps, Main = Main }
