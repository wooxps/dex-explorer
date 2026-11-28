--!strict

do
	local types = Apps.EditorHoverTypes
	local function analyze(source, marker)
		local options
		if marker then
			local at = assert(source:find(marker, 1, true))
			source = source:sub(1, at - 1) .. source:sub(at + #marker)
			options = { ExpectedPosition = at }
		end
		local symbols = Apps.EditorSymbols.New()
		symbols:Index(source)
		return assert(types.Analyze(source, symbols, function() end, nil, options)), source
	end
	local defaults = Apps.EditorSymbols.New()
	defaults:Index("type Pair<A = string, B = A> = { left: A, right: B }")
	local defaultType = types.ParseAnnotation("Pair<number>", defaults)
	assert(types.FieldType(defaultType, "left") == "number" and types.FieldType(defaultType, "right") == "number")
	assert(types.Describe(types.ParseAnnotation("false")) == "false")
	local chainSource = "local n = " .. string.rep("1 + ", 90) .. "2 * 3\nlocal result = n"
	local chain = analyze(chainSource)
	assert(types.TypeAt(chain.Entries[chainSource:find("result", 1, true)]) == "number")
	local union = types.ParseAnnotation("{ Count: number, Fast: boolean } | { Count: string, Slow: boolean } | nil")
	local shared = types.Members(union)
	assert(shared.Count and not shared.Fast and not shared.Slow, "only shared union members are offered")
	assert(types.Describe(types.FieldType(union, "Count")) == "number | string")
	assert(types.FieldType(union, "Fast") == nil)
	local intersection = types.ParseAnnotation("{ Count: number } & { Name: string }")
	assert(types.Members(intersection).Count and types.Members(intersection).Name)
	local call = analyze(
		[[local function pick(mode: "fast" | "slow", options: { Size: number }) end
pick("fast", { $ } )]],
		"$"
	)
	assert(call.ExpectedKind == "TableKey" and types.Members(call.Expected).Size)
	local nested = analyze(
		[[type Settings = { Mode: "fast" | "slow" }
local options: Settings = { Mode = "$" }]],
		"$"
	)
	assert(nested.ExpectedKind == "Value" and types.Describe(nested.Expected) == '"fast" | "slow"')
	local emptyCall = analyze(
		[[local function pick(mode: "fast" | "slow") end
pick($]],
		"$"
	)
	assert(emptyCall.ExpectedKind == "Value" and types.Describe(emptyCall.Expected) == '"fast" | "slow"')
	local assignment = analyze(
		[[type Flags = { Enabled: boolean }
local flags: Flags = { Enabled = true }
flags = {$]],
		"$"
	)
	assert(assignment.ExpectedKind == "TableKey" and types.Members(assignment.Expected).Enabled)
	local state, src = analyze([[local function values<T>(value: T): (T, { Result: T })
	return value, { Result = value }
end
local first, second = values(1)
local firstUse = first
local secondUse = second.Result
local function choose(value: string | number, optional: { Name: string }?)
	if type(value) == "string" then
		local fromString = value
	else
		local fromNumber = value
	end
	if optional ~= nil then
		local fromOptional = optional.Name
	end
end]])
	for name, expected in pairs({
		firstUse = "number",
		secondUse = "number",
		fromString = "string",
		fromNumber = "number",
		fromOptional = "string",
	}) do
		local at = assert(src:find(name, 1, true))
		assert(types.Describe(types.TypeAt(state.Entries[at])) == expected, "wrong inferred type for " .. name)
	end
	local scope = analyze(
		[[local outer = 1
do
	local outer = "inner"
	local removed = true
end
local another = $
local later = 3]],
		"$"
	)
	assert(scope.Visible.outer.Type == "number" and not scope.Visible.removed and not scope.Visible.later)
	print(
		"PASS: shared union members, intersection members, expected table and call types, generic type packs, branch refinements and lexical scope"
	)
end
