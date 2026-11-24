--!strict

------------------------------ Module ------------------------------

local function Main()
	local Diagnostics = {}
	local MAX_BYTES = 48 * 1024
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local total = 2
		for key, item in pairs(value) do
			total += size(key) + size(item) + 2
		end
		return total
	end
	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	local function prefix(value, maximum)
		local count = math.min(#value, maximum)
		if count < #value then
			while count > 0 do
				local byte = value:byte(count + 1)
				if byte < 128 or byte >= 192 then
					break
				end
				count -= 1
			end
		end
		return value:sub(1, count)
	end
	local layouts = { UIListLayout = true, UIGridLayout = true, UIPageLayout = true, UITableLayout = true }
	local componentKeys = {
		UIListLayout = {
			"FillDirection",
			"HorizontalAlignment",
			"VerticalAlignment",
			"SortOrder",
			"Padding",
			"AbsoluteContentSize",
			"ItemLineAlignment",
			"HorizontalFlex",
			"VerticalFlex",
			"Wraps",
		},
		UIGridLayout = {
			"CellPadding",
			"CellSize",
			"FillDirection",
			"FillDirectionMaxCells",
			"HorizontalAlignment",
			"VerticalAlignment",
			"SortOrder",
			"StartCorner",
			"AbsoluteCellCount",
			"AbsoluteCellSize",
			"AbsoluteContentSize",
		},
		UIPageLayout = {
			"CurrentPage",
			"Circular",
			"Animated",
			"EasingDirection",
			"EasingStyle",
			"TweenTime",
			"FillDirection",
			"Padding",
			"GamepadInputEnabled",
			"ScrollWheelInputEnabled",
			"TouchInputEnabled",
		},
		UITableLayout = {
			"FillDirection",
			"HorizontalAlignment",
			"VerticalAlignment",
			"SortOrder",
			"Padding",
			"FillEmptySpaceColumns",
			"FillEmptySpaceRows",
			"MajorAxis",
			"AbsoluteContentSize",
		},
		UIPadding = { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" },
		UISizeConstraint = { "MinSize", "MaxSize" },
		UIAspectRatioConstraint = { "AspectRatio", "AspectType", "DominantAxis" },
		UITextSizeConstraint = { "MinTextSize", "MaxTextSize" },
		UIScale = { "Scale" },
		UICorner = { "CornerRadius" },
		UIStroke = {
			"Enabled",
			"ApplyStrokeMode",
			"BorderStrokePosition",
			"Color",
			"Thickness",
			"Transparency",
			"LineJoinMode",
			"StrokeSizingMode",
			"ZIndex",
		},
	}
	local guiKeys = {
		"AbsolutePosition",
		"AbsoluteSize",
		"AbsoluteRotation",
		"Visible",
		"ClipsDescendants",
		"Position",
		"Size",
		"AnchorPoint",
		"Rotation",
		"AutomaticSize",
		"LayoutOrder",
		"ZIndex",
		"Active",
		"Interactable",
	}
	local ancestorGuiKeys =
		{ "AbsolutePosition", "AbsoluteSize", "AbsoluteRotation", "Visible", "ClipsDescendants", "Rotation", "ZIndex" }
	local layerKeys =
		{ "Enabled", "IgnoreGuiInset", "DisplayOrder", "ZIndexBehavior", "ScreenInsets", "ClipToDeviceSafeArea" }
	local function rect(position, extent)
		if
			not position
			or not extent
			or not finite(position.X)
			or not finite(position.Y)
			or not finite(extent.X)
			or not finite(extent.Y)
		then
			return nil
		end
		return { x = position.X, y = position.Y, width = math.max(0, extent.X), height = math.max(0, extent.Y) }
	end
	local function intersect(a, b)
		local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
		return {
			x = x,
			y = y,
			width = math.max(0, math.min(a.x + a.width, b.x + b.width) - x),
			height = math.max(0, math.min(a.y + a.height, b.y + b.height) - y),
		}
	end
	function Diagnostics.Create(c)
		local registry, codec = c.Registry, c.Codec
		local dead = false
		local result = { Commands = {} }
		local function alive()
			assert(not dead, "DISCONNECTED: UI diagnostics ended")
		end
		local function target(args)
			alive()
			assert(type(args) == "table" and type(args.instanceId) == "string", "INVALID_ARGUMENT: instanceId required")
			for key in pairs(args) do
				assert(key == "instanceId", "INVALID_ARGUMENT: unknown UI diagnostic argument")
			end
			return registry:Resolve(args.instanceId)
		end
		local function identity(object)
			local name = object.Name
			return {
				id = registry:Id(object),
				name = prefix(name, 256),
				nameTruncated = #name > 256,
				className = object.ClassName,
			}
		end
		local function read(object, keys)
			local properties, errors, raw = {}, {}, {}
			for _, key in ipairs(keys) do
				local ok, value = pcall(function()
					return object[key]
				end)
				if not ok then
					errors[key] = prefix(tostring(value), 160)
				else
					raw[key] = value
					if type(value) == "string" and #value > 2048 then
						errors[key] = "property_string_limit"
					elseif typeof(value) == "Instance" and not registry:Allowed(value) then
						errors[key] = "INSTANCE_UNAVAILABLE: reference outside client hierarchy"
					else
						local good, encoded = pcall(codec.Encode, codec, value)
						if not good then
							errors[key] = prefix(tostring(encoded), 160)
						elseif
							type(encoded) == "table"
							and (encoded.type == "Unsupported" or encoded.type == "TruncatedString")
						then
							errors[key] = "unsupported_value"
						elseif size(encoded) > 4096 then
							errors[key] = "property_size_limit"
						else
							properties[key] = encoded
						end
					end
				end
			end
			return properties, errors, raw
		end
		local function append(out, rows, row)
			if size(out) + size(row) > MAX_BYTES - 2048 then
				out.coverage.truncated = true
				out.coverage.reason = "result_byte_limit"
				return false
			end
			rows[#rows + 1] = row
			return true
		end
		local function warn(out, code, object, message)
			if #out.warnings >= 80 then
				out.coverage.truncated = true
				return false
			end
			return append(out, out.warnings, { code = code, instanceId = registry:Id(object), message = message })
		end
		local function layer(object)
			return object:IsA("LayerCollector")
				or object.ClassName == "ScreenGui"
				or object.ClassName == "BillboardGui"
				or object.ClassName == "SurfaceGui"
		end
		result.Commands[#result.Commands + 1] = {
			Name = "dex_get_ui_diagnostics",
			Grant = "inspect",
			Run = function(args)
				local object = target(args)
				assert(object:IsA("GuiObject"), "INVALID_TARGET: GuiObject required")
				local properties, errors, raw = read(object, guiKeys)
				local out = {
					scope = "client",
					instance = identity(object),
					properties = properties,
					errors = errors,
					ancestors = {},
					components = {},
					warnings = {},
					coverage = {
						ancestorLimit = 64,
						componentLimit = 32,
						componentExaminationLimit = 512,
						resultByteLimit = MAX_BYTES,
						truncated = false,
						nonAtomic = true,
					},
					visibilityEvidence = {
						hiddenByVisible = false,
						disabledLayer = false,
						transparentCanvasGroup = false,
						zeroSize = false,
					},
					note = "Visibility/layout evidence, not a guarantee of rendered pixels, occlusion, or clickability. Clip intersections are axis-aligned estimates when rotation is present.",
				}
				local ownRect = rect(raw.AbsolutePosition, raw.AbsoluteSize)
				local clipped = ownRect
				out.rect = ownRect
				local rotated = finite(raw.AbsoluteRotation) and math.abs(raw.AbsoluteRotation) % 360 > 0.0001 or false
				local clippingParents = 0
				local clipUnavailable = not finite(raw.AbsoluteRotation)
				if object.ClassName == "CanvasGroup" then
					local values, problems, state = read(object, { "GroupTransparency", "GroupColor3" })
					for key, value in pairs(values) do
						out.properties[key] = value
					end
					for key, value in pairs(problems) do
						out.errors[key] = value
					end
					if state.GroupTransparency == 1 then
						out.visibilityEvidence.transparentCanvasGroup = true
						warn(out, "TRANSPARENT_CANVAS_GROUP", object, "Selected CanvasGroup has GroupTransparency=1.")
					end
				end
				if raw.Visible == false then
					out.visibilityEvidence.hiddenByVisible = true
					warn(out, "HIDDEN_BY_VISIBLE", object, "Selected GUI has Visible=false.")
				end
				if ownRect and (ownRect.width == 0 or ownRect.height == 0) then
					out.visibilityEvidence.zeroSize = true
					warn(out, "ZERO_SIZE", object, "Selected GUI has a zero resolved width or height.")
				end
				local current = object.Parent
				local count = 0
				while current and current ~= c.Game and count < 64 do
					if not registry:Allowed(current) then
						out.coverage.ancestorUnavailable = true
						break
					end
					count += 1
					local row = { instance = identity(current) }
					local relevant = false
					if current:IsA("GuiObject") or current.ClassName == "CanvasGroup" then
						relevant = true
						local values, problems, state = read(current, ancestorGuiKeys)
						row.properties = values
						row.errors = problems
						if state.Visible == false then
							out.visibilityEvidence.hiddenByVisible = true
							warn(out, "HIDDEN_BY_ANCESTOR", current, "Ancestor has Visible=false.")
						end
						if finite(state.AbsoluteRotation) and math.abs(state.AbsoluteRotation) % 360 > 0.0001 then
							rotated = true
						elseif not finite(state.AbsoluteRotation) then
							clipUnavailable = true
						end
						if state.ClipsDescendants == true then
							clippingParents += 1
							local bounds = rect(state.AbsolutePosition, state.AbsoluteSize)
							if clipped and bounds then
								clipped = intersect(clipped, bounds)
							else
								clipUnavailable = true
							end
						end
						if current.ClassName == "CanvasGroup" then
							local values, problems, state = read(current, { "GroupTransparency", "GroupColor3" })
							for key, value in pairs(values) do
								row.properties[key] = value
							end
							for key, value in pairs(problems) do
								row.errors[key] = value
							end
							if state.GroupTransparency == 1 then
								out.visibilityEvidence.transparentCanvasGroup = true
								warn(
									out,
									"TRANSPARENT_CANVAS_GROUP",
									current,
									"Ancestor CanvasGroup has GroupTransparency=1."
								)
							end
						end
					elseif layer(current) then
						relevant = true
						row.properties, row.errors = read(current, layerKeys)
						if row.properties.Enabled == false then
							out.visibilityEvidence.disabledLayer = true
							warn(out, "DISABLED_LAYER", current, "Ancestor GUI layer has Enabled=false.")
						end
					end
					if relevant and not append(out, out.ancestors, row) then
						out.coverage.ancestorTruncated = true
						break
					end
					current = current.Parent
				end
				out.coverage.ancestorsExamined = count
				if current and current ~= c.Game then
					out.coverage.ancestorTruncated = true
					out.coverage.truncated = true
				end
				clipUnavailable = clipUnavailable
					or out.coverage.ancestorTruncated == true
					or out.coverage.ancestorUnavailable == true
				out.clipAnalysis = {
					clippingAncestors = clippingParents,
					rotationPresent = rotated,
					approximate = rotated or clipUnavailable,
					intersection = clipped,
					status = clipUnavailable and "bounds_unavailable"
						or rotated and "axis_aligned_estimate"
						or "axis_aligned",
				}
				if clipped and ownRect then
					local area = ownRect.width * ownRect.height
					local inside = clipped.width * clipped.height
					out.clipAnalysis.visibleAreaFraction = area > 0 and math.min(1, inside / area) or 0
					if inside < area and not rotated and not clipUnavailable then
						warn(
							out,
							inside == 0 and "FULLY_CLIPPED" or "PARTIALLY_CLIPPED",
							object,
							"Axis-aligned ancestor clipping reduces the selected GUI rectangle."
						)
					end
				end
				if rotated and clippingParents > 0 then
					warn(
						out,
						"ROTATED_CLIP_ESTIMATE",
						object,
						"Rotation and the current clipping rollout can change actual clipping; this rectangle intersection is only an estimate."
					)
				end
				local owners = { { object = object, relationship = "child" } }
				if object.Parent and registry:Allowed(object.Parent) then
					owners[#owners + 1] = { object = object.Parent, relationship = "parent_layout" }
				end
				local examined = 0
				for _, owner in ipairs(owners) do
					local good, children = pcall(owner.object.GetChildren, owner.object)
					if not good then
						append(out, out.warnings, {
							code = "COMPONENTS_UNAVAILABLE",
							instanceId = registry:Id(owner.object),
							message = prefix(tostring(children), 160),
						})
					else
						for index = 1, math.min(#children, 256) do
							examined += 1
							local child = children[index]
							local keys = componentKeys[child.ClassName]
							if
								keys
								and (owner.relationship == "child" or layouts[child.ClassName])
								and registry:Allowed(child)
							then
								if #out.components >= 32 then
									out.coverage.componentTruncated = true
									out.coverage.truncated = true
									break
								end
								local values, problems = read(child, keys)
								if
									not append(out, out.components, {
										instance = identity(child),
										owner = identity(owner.object),
										affectsTarget = owner.relationship == "parent_layout"
											or not layouts[child.ClassName],
										relationship = owner.relationship,
										properties = values,
										errors = problems,
									})
								then
									out.coverage.componentTruncated = true
									break
								end
								if owner.relationship == "parent_layout" then
									warn(
										out,
										"PARENT_LAYOUT",
										owner.object,
										"A parent layout component can determine child positions or sizes."
									)
								end
							end
						end
						if #children > 256 then
							out.coverage.componentTruncated = true
							out.coverage.truncated = true
						end
					end
				end
				out.coverage.componentsExamined = examined
				out.coverage.estimatedBytes = size(out)
				return out
			end,
		}
		local textKeys = {
			"Text",
			"ContentText",
			"Font",
			"FontFace",
			"TextSize",
			"TextBounds",
			"TextFits",
			"AbsoluteSize",
			"TextScaled",
			"RichText",
			"TextWrapped",
			"TextTruncate",
			"LineHeight",
			"MaxVisibleGraphemes",
			"TextXAlignment",
			"TextYAlignment",
			"TextDirection",
			"TextTransparency",
			"AutomaticSize",
		}
		result.Commands[#result.Commands + 1] = {
			Name = "dex_get_text_metrics",
			Grant = "inspect",
			Run = function(args)
				local object = target(args)
				assert(
					object.ClassName == "TextLabel" or object.ClassName == "TextButton" or object.ClassName == "TextBox",
					"INVALID_TARGET: TextLabel, TextButton or TextBox required"
				)
				local properties, errors, raw = read(object, textKeys)
				local out = {
					scope = "client",
					instance = identity(object),
					properties = properties,
					errors = errors,
					coverage = { resultByteLimit = MAX_BYTES, truncated = false, nonAtomic = true },
					measurement = {
						available = false,
						method = "TextService.GetTextSize",
						accuracy = "approximate_plain_text_legacy_font",
					},
					note = "TextBounds/TextFits are current engine evidence. Optional measurement does not reproduce font loading, custom FontFace, rich text, scaling, LineHeight, accessibility offsets, padding or truncation.",
				}
				if type(raw.Text) == "string" then
					out.text = {
						bytes = #raw.Text,
						preview = prefix(raw.Text, 2048),
						previewTruncated = #raw.Text > 2048,
					}
				end
				local reason
				if type(raw.Text) ~= "string" then
					reason = "text_unavailable"
				elseif #raw.Text > 4096 then
					reason = "text_measurement_limit"
				elseif raw.RichText ~= false then
					reason = raw.RichText == true and "rich_text_not_measured" or "rich_text_state_unavailable"
				elseif raw.TextScaled ~= false then
					reason = raw.TextScaled == true and "scaled_text_not_measured" or "text_scale_state_unavailable"
				elseif raw.LineHeight ~= nil and (not finite(raw.LineHeight) or raw.LineHeight ~= 1) then
					reason = "custom_line_height_not_measured"
				elseif not finite(raw.TextSize) or raw.TextSize <= 0 then
					reason = "text_size_unavailable"
				elseif raw.Font == nil or tostring(raw.Font):match("Unknown$") then
					reason = "custom_or_unknown_font_not_measured"
				elseif raw.TextWrapped ~= true and raw.TextWrapped ~= false then
					reason = "wrap_state_unavailable"
				elseif
					raw.TextWrapped
					and (not raw.AbsoluteSize or not finite(raw.AbsoluteSize.X) or raw.AbsoluteSize.X <= 0)
				then
					reason = "wrap_width_unavailable"
				end
				if reason then
					out.measurement.reason = reason
				else
					local width = raw.TextWrapped and math.min(raw.AbsoluteSize.X, 1000000) or 1000000
					out.measurement.widthClamped = raw.TextWrapped and raw.AbsoluteSize.X > 1000000 or false
					local good, value = pcall(function()
						return c.service.TextService:GetTextSize(
							raw.Text,
							raw.TextSize,
							raw.Font,
							Vector2.new(width, 1000000)
						)
					end)
					if good and value and finite(value.X) and finite(value.Y) then
						out.measurement.available = true
						out.measurement.bounds = { x = value.X, y = value.Y }
						out.measurement.constraint = { width = width, height = 1000000 }
					else
						out.measurement.error = good and "non_finite_measurement" or prefix(tostring(value), 200)
					end
				end
				if size(out) > MAX_BYTES - 1024 then
					out.coverage.truncated = true
					out.coverage.reason = "result_byte_limit"
					out.properties.Text = nil
					out.properties.ContentText = nil
					out.properties.FontFace = nil
				end
				out.coverage.estimatedBytes = size(out)
				return out
			end,
		}
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Diagnostics
end
return { Main = Main }
