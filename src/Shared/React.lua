--!strict

------------------------------ Module ------------------------------

local function Main()
	assert(type(ReactVendor) == "table", "React package runtime was not loaded")
	return {
		React = ReactVendor.require("react"),
		ReactRoblox = ReactVendor.require("react-roblox"),
		Version = "17.2.1",
	}
end
return { Main = Main }
