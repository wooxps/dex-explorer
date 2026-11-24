--!strict

local env, Lib

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	env, Lib = d.env or {}, d.Lib
end
------------------------------ Module ------------------------------

local function Main()
	local View = {}
	function View.Create(parent, ui, actions)
		local controls = {}
		local inset, textX, rowHeight = 20, 61, 116
		local guide = "https://github.com/wooxps/dex-explorer/blob/main/docs/mcp/SETUP.md"
		local steps = {
			{ "Set up Dex MCP", "Add dex-mcp.mjs as a stdio MCP server.", "Copy setup link", guide, 121 },
			{
				"Get a pairing code",
				"Ask your MCP client to run dex_create_pairing.",
				"Copy request",
				"Run dex_create_pairing and show me the pairing code.",
				110,
			},
			{ "Pair Dex", "Paste the code in Connection.", "Open Connection", nil, 134 },
		}
		for index, data in ipairs(steps) do
			local y = 24 + (index - 1) * rowHeight
			if index > 1 then
				local rule = ui:Rule(parent, "StepDivider" .. index, y - 16)
				rule.Position = UDim2.fromOffset(inset, y - 16)
				rule.Size = UDim2.new(1, -2 * inset, 0, 1)
				rule.BackgroundColor3 = ui.Palette.Border
				rule.BackgroundTransparency = 0
			end
			local marker = ui:Node("Frame", {
				Parent = parent,
				Name = "Step" .. index,
				Position = UDim2.fromOffset(inset + 3, y + 1),
				Size = UDim2.fromOffset(24, 24),
				BorderSizePixel = 0,
				BackgroundTransparency = 1,
			})
			ui:Node("UICorner", { Parent = marker, CornerRadius = UDim.new(1, 0) })
			ui:Outline(marker, ui.Theme.PlaceholderText)
			local number =
				ui:Text(marker, "Number", tostring(index), UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), false, 14)
			number.TextXAlignment = Enum.TextXAlignment.Center
			number.TextYAlignment = Enum.TextYAlignment.Center
			local title = ui:Text(
				parent,
				"StepTitle" .. index,
				data[1],
				UDim2.fromOffset(textX, y),
				UDim2.new(1, -textX - inset, 0, 24),
				false,
				17
			)
			title.Font = Lib.StudioBold or Lib.StudioFont
			local description = ui:Text(
				parent,
				"StepDetail" .. index,
				data[2],
				UDim2.fromOffset(textX, y + 26),
				UDim2.new(1, -textX - inset, 0, 30),
				true,
				13
			)
			description.TextWrapped = true
			description.TextTruncate = Enum.TextTruncate.None
			description.TextYAlignment = Enum.TextYAlignment.Top
			local record
			record = ui:Button(
				parent,
				"StepAction" .. index,
				data[3],
				UDim2.fromOffset(textX, y + 57),
				UDim2.fromOffset(data[5], 28),
				function()
					if data[4] then
						local copied = type(env.setclipboard) == "function" and pcall(env.setclipboard, data[4])
						actions.Flash(record, copied and "Copied" or "Copy failed")
					else
						actions.Connect()
					end
				end,
				"outlined"
			)
			ui:Round(record.Gui, 3)
			record.Gui.TextSize = 13
			if data[4] then
				record:SetEnabled(type(env.setclipboard) == "function")
			end
			controls[index] = record
		end
		parent.CanvasSize = UDim2.fromOffset(0, 362)
		return { Controls = controls }
	end
	return View
end
return { InitDeps = InitDeps, Main = Main }
