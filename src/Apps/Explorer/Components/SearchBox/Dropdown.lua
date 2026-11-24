--!strict

local Apps, Settings

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Apps, Settings = d.Apps, d.Settings
end
------------------------------ Module ------------------------------

local function Main()
	local Dropdown = {}
	local nextId = 0
	function Dropdown.Create(renderer, class, properties)
		if not properties.Parent then
			local instance = Instance.new(class)
			for name, value in pairs(properties) do
				instance[name] = value
			end
			return instance
		end
		local React = Apps.React.React
		local ref = React.createRef()
		local props = { ref = ref }
		for name, value in pairs(properties) do
			if name ~= "Parent" then
				props[name] = value
			end
		end
		if
			(
				class == "Frame"
				or class == "TextLabel"
				or class == "TextButton"
				or class == "ImageLabel"
				or class == "ImageButton"
				or class == "TextBox"
			) and props.BorderSizePixel == nil
		then
			props.BorderSizePixel = 0
		end
		nextId += 1
		renderer:Portal("SearchWidget" .. nextId, React.createElement(class, props), properties.Parent)
		return assert(ref.current, "Search widget failed to mount")
	end
	function Dropdown.Clear(renderer, list)
		renderer:ClearPortalsUnder(list)
		list:ClearAllChildren()
	end
	function Dropdown.StyleText(object)
		object.Font = Enum.Font.BuilderSans
		object.TextSize = 14
		object.TextColor3 = Settings.Theme.Text
	end
	function Dropdown.Corner(renderer, object, radius)
		local corner = object:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, radius)
		else
			Dropdown.Create(renderer, "UICorner", { Parent = object, CornerRadius = UDim.new(0, radius) })
		end
	end
	return Dropdown
end
return { InitDeps = InitDeps, Main = Main }
