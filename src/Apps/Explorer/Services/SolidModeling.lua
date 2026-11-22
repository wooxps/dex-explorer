--!strict

type Action = "Union" | "Intersect" | "Negate" | "Separate"
type Node = { Obj: Instance, Inferred: any? }
type Source = { Part: BasePart, Parent: Instance, CFrame: CFrame, Size: Vector3 }
type Origin = { Sources: { Source }, Parent: Instance, CFrame: CFrame, Size: Vector3 }
type NegatedStyle = { Color: Color3, Transparency: number, Name: string, CanCollide: boolean, UsePartColor: boolean? }
local Main: any, Apps: any
local CollectionService: CollectionService
local NegativeTag = "rbxNegate"
local BooleanOptions = table.freeze({ SplitApart = false })
local Origins: { [BasePart]: Origin } = setmetatable({}, { __mode = "k" })
local NegatedStyles: { [BasePart]: NegatedStyle } = setmetatable({}, { __mode = "k" })
local Busy = false
local SolidModeling = {}

local function IsSolid(object: Instance): boolean
	return object:IsA("BasePart") and not object:IsA("Terrain") and object.Parent ~= nil
end

local function IsNegative(part: BasePart): boolean
	return CollectionService:HasTag(part, NegativeTag) or part:IsA("NegateOperation")
end

function SolidModeling.Availability(nodes: { Node }): (boolean, boolean, boolean, boolean)
	if Busy or #nodes == 0 then
		return false, false, false, false
	end
	local positive = 0
	local canNegate, canSeparate = true, true
	for _, node in nodes do
		local object = node.Obj
		if node.Inferred or not IsSolid(object) then
			return false, false, false, false
		end
		local part = object :: BasePart
		if not IsNegative(part) then
			positive += 1
		end
		canNegate = canNegate and not part:IsA("NegateOperation")
		canSeparate = canSeparate and Origins[part] ~= nil
	end
	return #nodes >= 2 and positive > 0, positive >= 2 and positive == #nodes, canNegate, canSeparate
end

local function ParentFor(sources: { Source }, primary: BasePart): Instance
	local parent = assert(primary.Parent)
	for _, source in sources do
		while parent ~= game and source.Parent ~= parent and not source.Parent:IsDescendantOf(parent) do
			parent = assert(parent.Parent, "The selected parts do not share a parent")
		end
	end
	return if parent == game then workspace else parent
end

local function CaptureSources(parts: { BasePart }): { Source }
	local sources: { Source } = table.create(#parts)
	local selected: { [Instance]: boolean } = {}
	for _, part in parts do
		selected[part] = true
	end
	for index, part in parts do
		local parent = assert(part.Parent, "A selected part has been removed")
		local ancestor: Instance? = parent
		while ancestor do
			assert(not selected[ancestor], "Select parts that are not nested inside each other")
			ancestor = ancestor.Parent
		end
		sources[index] = { Part = part, Parent = parent, CFrame = part.CFrame, Size = part.Size }
	end
	return sources
end

local function RunBoolean(action: Action, parts: { BasePart }): ()
	local geometry = game:GetService("GeometryService")
	local sources = CaptureSources(parts)
	local positive: { BasePart } = {}
	local negative: { BasePart } = {}
	for _, part in parts do
		table.insert(if IsNegative(part) then negative else positive, part)
	end
	local primary = assert(table.remove(positive, 1), "Select at least one positive part")
	local parent = ParentFor(sources, primary)
	local generated: { BasePart } = {}
	local committed = false

	local function Take(results: { BasePart }): BasePart
		for _, part in results do
			table.insert(generated, part)
		end
		assert(#results > 0, "The operation produced no geometry")
		assert(#results == 1, "Roblox returned more than one solid")
		return results[1]
	end

	local ok, reason = pcall(function(): ()
		local result: BasePart
		if action == "Intersect" then
			result = Take(geometry:IntersectAsync(primary, positive, BooleanOptions))
		elseif #negative == 0 then
			result = Take(geometry:UnionAsync(primary, positive, BooleanOptions))
		else
			local base = if #positive > 0 then Take(geometry:UnionAsync(primary, positive, BooleanOptions)) else primary
			result = Take(geometry:SubtractAsync(base, negative, BooleanOptions))
		end
		assert(Main.Alive, "Dex closed during the operation")
		for _, source in sources do
			local part = source.Part
			assert(
				part.Parent == source.Parent and part.CFrame == source.CFrame and part.Size == source.Size,
				"A selected part changed during the operation"
			)
		end
		assert(not IsNegative(primary), "A selected part changed during the operation")
		for _, part in positive do
			assert(not IsNegative(part), "A selected part changed during the operation")
		end
		for _, part in negative do
			assert(IsNegative(part), "A selected part changed during the operation")
		end

		Apps.History.Run(action, function(): ()
			Apps.History.Set(result, "Parent", parent)
			for _, source in sources do
				Apps.History.Set(source.Part, "Parent", nil)
			end
			Apps.Explorer.RestoreHistorySelection({ result })
		end)
		Origins[result] = { Sources = sources, Parent = parent, CFrame = result.CFrame, Size = result.Size }
		committed = true
	end)
	for _, part in generated do
		if part.Parent == nil and (not committed or not Origins[part]) then
			part:Destroy()
		end
	end
	if not ok then
		error(reason, 0)
	end
end

local function ToggleNegative(parts: { BasePart }): ()
	Apps.History.Run("Negate", function(): ()
		for _, part in parts do
			local wasNegative = CollectionService:HasTag(part, NegativeTag)
			local style = NegatedStyles[part]
			local operation = if part:IsA("PartOperation") then part else nil
			local nextStyle = if wasNegative
				then nil
				else {
					Color = part.Color,
					Transparency = part.Transparency,
					Name = part.Name,
					CanCollide = part.CanCollide,
					UsePartColor = if operation then operation.UsePartColor else nil,
				}
			Apps.History.Change("Negate", function(): NegatedStyle?
				return NegatedStyles[part]
			end, function(value: NegatedStyle?): ()
				NegatedStyles[part] = value
			end, nextStyle)
			Apps.History.Tag(part, NegativeTag, not wasNegative)
			if not wasNegative then
				Apps.History.Set(part, "Color", Color3.fromRGB(255, 92, 92))
				Apps.History.Set(part, "Transparency", math.max(part.Transparency, 0.5))
				Apps.History.Set(part, "Name", "NegativePart")
				Apps.History.Set(part, "CanCollide", false)
				if operation then
					Apps.History.Set(operation, "UsePartColor", true)
				end
			elseif style then
				Apps.History.Set(part, "Color", style.Color)
				Apps.History.Set(part, "Transparency", style.Transparency)
				if part.Name == "NegativePart" then
					Apps.History.Set(part, "Name", style.Name)
				end
				Apps.History.Set(part, "CanCollide", style.CanCollide)
				if operation and style.UsePartColor ~= nil then
					Apps.History.Set(operation, "UsePartColor", style.UsePartColor)
				end
			end
		end
	end)
end

local function SeparatedTransform(part: BasePart, origin: Origin, source: Source): (CFrame, Vector3)
	local relative = origin.CFrame:ToObjectSpace(source.CFrame)
	if part.Size == origin.Size then
		return part.CFrame * relative, source.Size
	end

	local scale = part.Size / origin.Size
	local x = relative.XVector * scale
	local y = relative.YVector * scale
	local z = relative.ZVector * scale
	local xAxis, yAxis, zAxis = x.Unit, y.Unit, z.Unit
	assert(
		math.abs(xAxis:Dot(yAxis)) < 0.0001
			and math.abs(xAxis:Dot(zAxis)) < 0.0001
			and math.abs(yAxis:Dot(zAxis)) < 0.0001,
		"Non-uniform scaling has sheared the original parts. Restore the solid's proportions before separating it."
	)
	return part.CFrame * CFrame.fromMatrix(relative.Position * scale, xAxis, yAxis, zAxis),
		source.Size * Vector3.new(x.Magnitude, y.Magnitude, z.Magnitude)
end

local function Separate(parts: { BasePart }): ()
	local restored: { Source } = {}
	local selected: { Instance } = {}
	for _, part in parts do
		local origin = assert(Origins[part], "Dex does not have the original parts for this solid")
		local parent = assert(part.Parent)
		for _, source in origin.Sources do
			assert(source.Part.Parent == nil, "An original part is already in the scene")
			local destination = if parent == origin.Parent and source.Parent:IsDescendantOf(game)
				then source.Parent
				else parent
			local cf, size = SeparatedTransform(part, origin, source)
			table.insert(restored, { Part = source.Part, Parent = destination, CFrame = cf, Size = size })
			table.insert(selected, source.Part)
		end
	end
	Apps.History.Run("Separate", function(): ()
		for _, item in restored do
			Apps.History.Set(item.Part, "Size", item.Size)
			Apps.History.Set(item.Part, "CFrame", item.CFrame)
			Apps.History.Set(item.Part, "Parent", item.Parent)
		end
		for _, part in parts do
			Apps.History.Set(part, "Parent", nil)
		end
		Apps.Explorer.RestoreHistorySelection(selected)
	end)
end

local function ShowFailure(action: Action, reason: any): ()
	local message = string.gsub(tostring(reason), "^.-:%d+: ", "")
	warn("[Dex Explorer] " .. action .. " failed: " .. message)
	if Main.Alive then
		local dialog = Apps.StudioPopup.Open(action, 180)
		dialog.label(dialog.panel, action .. " failed", 24, 46, 472, 23, 15, true)
		local explanation = dialog.label(dialog.panel, message, 24, 72, 472, 51, 13)
		explanation.TextWrapped = true
		dialog.formAction("OK", true, dialog.close)
		dialog.hideCancel()
	end
end

function SolidModeling.Run(action: Action, nodes: { Node }): ()
	local union, intersect, negate, separate = SolidModeling.Availability(nodes)
	if not (
		(action == "Union" and union)
		or (action == "Intersect" and intersect)
		or (action == "Negate" and negate)
		or (action == "Separate" and separate)
	) then
		return
	end

	local parts: { BasePart } = table.create(#nodes)
	for index, node in nodes do
		parts[index] = node.Obj :: BasePart
	end
	Busy = true
	local ok, reason = pcall(function(): ()
		if action == "Negate" then
			ToggleNegative(parts)
		elseif action == "Separate" then
			Separate(parts)
		else
			RunBoolean(action, parts)
		end
	end)
	Busy = false
	if not ok then
		ShowFailure(action, reason)
	end
end

return table.freeze({
	InitDeps = function(deps: { Main: any, Apps: any, service: { CollectionService: CollectionService } }): ()
		Main, Apps, CollectionService = deps.Main, deps.Apps, deps.service.CollectionService
	end,
	InitAfterMain = function(): () end,
	Main = function()
		return table.freeze(SolidModeling)
	end,
})
