--!strict

------------------------------ Module ------------------------------

local function Main()
	local Skin = { TabHeight = 26, FooterHeight = 22, FindWidth = 280, FindHeight = 51, ReplaceHeight = 73 }
	Skin.Chrome = Color3.fromRGB(33, 34, 39)
	Skin.Inactive = Color3.fromRGB(25, 26, 31)
	Skin.Border = Color3.fromRGB(55, 57, 64)
	Skin.Text = Color3.fromRGB(204, 204, 204)
	function Skin.Apply(cf)
		cf.FontSize = 14
		cf.GutterWidthMinimum = 54
		cf.GutterColor = Color3.fromRGB(39, 42, 49)
		cf.ShowIndentGuides = true
		cf.HighlightOccurrences = true
		cf.ScrollBarThickness = 14
		for _, bar in ipairs({ cf.ScrollV, cf.ScrollH }) do
			if bar and bar.GuiElems then
				bar.ThumbInset = 2
				bar.ThumbThickness = 10
				bar.Gui.BackgroundTransparency = 0
				bar.Gui.BackgroundColor3 = Skin.Chrome
				bar.Gui.ZIndex = 12
				bar.GuiElems.ScrollThumbFrame.ZIndex = 13
				bar.GuiElems.MarkerFrame.ZIndex = 15
				local thumb = bar.GuiElems.ScrollThumb
				thumb.ZIndex = 14
				thumb.BackgroundTransparency = 0
				thumb.BackgroundColor3 = Color3.fromRGB(112, 112, 116)
				for _, child in ipairs(thumb:GetChildren()) do
					if child:IsA("UICorner") then
						child:Destroy()
					end
				end
			end
		end
		cf.Colors = table.clone(cf.Colors)
		cf.Colors.Background = Color3.fromRGB(37, 37, 37)
		cf.Frame.BackgroundColor3 = cf.Colors.Background
		cf.Colors.CurrentLine = Color3.fromRGB(53, 55, 67)
		cf.Colors.MatchingWord = Color3.fromRGB(85, 85, 85)
		cf.Colors.Comment = Color3.fromRGB(102, 102, 102)
		cf:MakeRichTemplates()
	end
	return Skin
end
return { Main = Main }
