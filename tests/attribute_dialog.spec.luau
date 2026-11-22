do
	local gui
	local show = Lib.ShowGui
	Lib.ShowGui = function(value) gui = value end
	local function find(text)
		for _,child in ipairs(gui:GetDescendants()) do
			if child.Name==text or child.Text==text then return child end
		end
	end
	local function typeName(name)
		local box = find("NameBox")
		box.Text = name
		box:GetPropertyChangedSignal("Text"):Fire()
		return box
	end
	Properties.DisplayAddAttributeWindow()
	assert(not find("Save").Interactable and find("0/100") and find("Shadow"))
	assert(service.UserInputService.Focus == find("NameBox"))
	assert(find("NameBox").Parent.Size==UDim2.fromOffset(252,182))
	assert(find("Save").Position.X.Offset < find("Cancel").Position.X.Offset)
	assert(find("NameBox").Size == UDim2.fromOffset(156,21))
	typeName("RBXReserved")
	find("Save").Activated:Fire()
	assert(#writes==0 and find("Names cannot begin with 'RBX'."))
	Properties.AttributeTypeChooser:SetSelected("number")
	typeName("Health").FocusLost:Fire(true)
	assert(#writes==1 and writes[1][1].AttributeName=="Health" and writes[1][2]==0)
	assert(Properties.AttributeTypeChooser.Context.Hidden and not Properties.AttributeTypeChooser.Gui.Parent)
	local previous = {AttributeName="Enabled",ValueType={Name="bool"}}
	Properties.DisplayAddAttributeWindow(previous)
	assert(find("NameBox").Text=="Enabled" and not find("Type"))
	typeName("Visible").FocusLost:Fire(true)
	assert(writes[2][4]==previous and writes[2][1].ValueType.Name=="bool")
	Properties.DisplayAddAttributeWindow()
	assert(Properties.AttributeTypeChooser.Selected=="string" and find("0/100"))
	typeName(string.rep("x",101))
	assert(find("101/100") and not find("Save").Interactable)
	find("Cancel").Activated:Fire()
	Lib.ShowGui = show
	print("PASS: shared attribute dialog, validation, type selection, rename and Enter submission")
end
