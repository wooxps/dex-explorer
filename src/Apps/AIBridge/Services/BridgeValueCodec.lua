--!strict

------------------------------ Module ------------------------------

local function Main()
	local Codec = {}
	local function number(value)
		assert(
			type(value) == "number" and value == value and math.abs(value) < math.huge,
			"INVALID_VALUE: expected finite number"
		)
		return value
	end
	function Codec.Create(registry)
		local codec = {}
		local function decode(value, depth)
			assert(depth <= 8, "VALUE_LIMIT: nesting exceeds eight levels")
			local kind = type(value)
			if kind == "number" then
				return number(value)
			end
			if kind == "boolean" or kind == "nil" then
				return value
			end
			if kind == "string" then
				assert(#value <= 65536, "VALUE_LIMIT: string exceeds 64 KiB")
				return value
			end
			assert(kind == "table" and type(value.type) == "string", "INVALID_VALUE: typed Roblox value required")
			local t = value.type
			if t == "Table" then
				local entries = value.entries
				assert(type(entries) == "table" and #entries <= 256, "VALUE_LIMIT: Table requires at most 256 entries")
				local result = {}
				local seen = {}
				for _, entry in ipairs(entries) do
					assert(type(entry) == "table", "INVALID_VALUE: table entry required")
					local key = decode(entry.key, depth + 1)
					assert(
						type(key) == "string" or type(key) == "number",
						"INVALID_VALUE: table keys must be strings or numbers"
					)
					if type(key) == "string" then
						assert(#key <= 256, "VALUE_LIMIT: table key exceeds 256 bytes")
					end
					assert(not seen[key], "INVALID_VALUE: duplicate table key")
					seen[key] = true
					result[key] = decode(entry.value, depth + 1)
				end
				return result
			end
			if t == "nil" then
				return nil
			end
			if t == "Instance" then
				return registry:Resolve(value.id)
			end
			if t == "Vector2" then
				return Vector2.new(number(value.x), number(value.y))
			end
			if t == "Vector3" then
				return Vector3.new(number(value.x), number(value.y), number(value.z))
			end
			if t == "Color3" then
				local r, g, b = number(value.r), number(value.g), number(value.b)
				assert(
					r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1,
					"INVALID_VALUE: colors use components between zero and one"
				)
				return Color3.new(r, g, b)
			end
			if t == "UDim" then
				return UDim.new(number(value.scale), number(value.offset))
			end
			if t == "UDim2" then
				return UDim2.new(
					number(value.xScale),
					number(value.xOffset),
					number(value.yScale),
					number(value.yOffset)
				)
			end
			if t == "CFrame" then
				local c = value.components
				assert(type(c) == "table" and #c == 12, "INVALID_VALUE: CFrame requires 12 components")
				for _, v in ipairs(c) do
					number(v)
				end
				return CFrame.new(table.unpack(c))
			end
			if t == "EnumItem" then
				assert(
					type(value.enum) == "string"
						and type(value.name) == "string"
						and #value.enum <= 100
						and #value.name <= 100,
					"INVALID_VALUE: enum name required"
				)
				local item = Enum[value.enum][value.name]
				assert(typeof(item) == "EnumItem", "INVALID_VALUE: unknown enum item")
				return item
			end
			if t == "NumberRange" then
				return NumberRange.new(number(value.min), number(value.max))
			end
			if t == "Rect" then
				return Rect.new(number(value.minX), number(value.minY), number(value.maxX), number(value.maxY))
			end
			if t == "BrickColor" then
				return BrickColor.new(number(value.number))
			end
			if t == "Content" then
				assert(
					type(value.uri) == "string" and #value.uri <= 4096,
					"INVALID_VALUE: bounded content URI required"
				)
				return value.uri == "" and Content.none or Content.fromUri(value.uri)
			end
			if t == "Font" then
				assert(type(value.family) == "string" and #value.family <= 2048, "INVALID_VALUE: font family required")
				return Font.new(value.family, decode(value.weight, depth + 1), decode(value.style, depth + 1))
			end
			if t == "PhysicalProperties" then
				return PhysicalProperties.new(
					number(value.density),
					number(value.friction),
					number(value.elasticity),
					number(value.frictionWeight),
					number(value.elasticityWeight)
				)
			end
			if t == "NumberSequence" or t == "ColorSequence" then
				assert(
					type(value.keypoints) == "table" and #value.keypoints >= 2 and #value.keypoints <= 20,
					"INVALID_VALUE: sequence requires 2 to 20 keypoints"
				)
				local points = {}
				local previous = -1
				for _, point in ipairs(value.keypoints) do
					local time = number(point.time)
					assert(
						time >= 0 and time <= 1 and time > previous,
						"INVALID_VALUE: sequence times must increase between zero and one"
					)
					previous = time
					if t == "NumberSequence" then
						points[#points + 1] =
							NumberSequenceKeypoint.new(time, number(point.value), number(point.envelope or 0))
					else
						local color = decode(point.value, depth + 1)
						assert(typeof(color) == "Color3", "INVALID_VALUE: ColorSequence requires Color3 values")
						points[#points + 1] = ColorSequenceKeypoint.new(time, color)
					end
				end
				assert(points[1].Time == 0 and points[#points].Time == 1, "INVALID_VALUE: sequence endpoints required")
				return t == "NumberSequence" and NumberSequence.new(points) or ColorSequence.new(points)
			end
			error("UNSUPPORTED_VALUE: " .. t, 0)
		end
		function codec:Decode(value)
			return decode(value, 0)
		end
		function codec:Encode(value)
			local seen = {}
			local count, bytes = 0, 0
			local function encode(v, depth)
				assert(depth <= 8, "VALUE_LIMIT: result nesting exceeds eight levels")
				count += 1
				assert(count <= 4096, "VALUE_LIMIT: result exceeds 4096 values")
				local t = typeof(v)
				if t == "nil" then
					return { type = "nil" }
				end
				if t == "boolean" then
					return v
				end
				if t == "number" then
					return number(v)
				end
				if t == "string" then
					bytes += math.min(#v, 65536)
					assert(bytes <= 131072, "VALUE_LIMIT: result strings exceed 128 KiB")
					if #v > 65536 then
						return { type = "TruncatedString", text = string.sub(v, 1, 65536), bytes = #v }
					end
					return v
				end
				if t == "Instance" then
					return { type = "Instance", id = registry:Id(v) }
				end
				if t == "Vector2" then
					return { type = t, x = v.X, y = v.Y }
				end
				if t == "Vector3" then
					return { type = t, x = v.X, y = v.Y, z = v.Z }
				end
				if t == "Color3" then
					return { type = t, r = v.R, g = v.G, b = v.B }
				end
				if t == "CFrame" then
					return { type = t, components = { v:GetComponents() } }
				end
				if t == "UDim" then
					return { type = t, scale = v.Scale, offset = v.Offset }
				end
				if t == "UDim2" then
					return {
						type = t,
						xScale = v.X.Scale,
						xOffset = v.X.Offset,
						yScale = v.Y.Scale,
						yOffset = v.Y.Offset,
					}
				end
				if t == "EnumItem" then
					return { type = t, enum = tostring(v.EnumType):gsub("^Enum%.", ""), name = v.Name }
				end
				if t == "NumberRange" then
					return { type = t, min = v.Min, max = v.Max }
				end
				if t == "Rect" then
					return { type = t, minX = v.Min.X, minY = v.Min.Y, maxX = v.Max.X, maxY = v.Max.Y }
				end
				if t == "BrickColor" then
					return { type = t, number = v.Number }
				end
				if t == "Content" then
					if type(v.Uri) == "string" then
						return { type = t, uri = v.Uri }
					end
					if v.SourceType == Enum.ContentSourceType.None then
						return { type = t, uri = "" }
					end
					return { type = "Unsupported", valueType = "Content." .. tostring(v.SourceType) }
				end
				if t == "Font" then
					return {
						type = t,
						family = tostring(v.Family),
						weight = encode(v.Weight, depth + 1),
						style = encode(v.Style, depth + 1),
					}
				end
				if t == "PhysicalProperties" then
					return {
						type = t,
						density = v.Density,
						friction = v.Friction,
						elasticity = v.Elasticity,
						frictionWeight = v.FrictionWeight,
						elasticityWeight = v.ElasticityWeight,
					}
				end
				if t == "NumberSequence" or t == "ColorSequence" then
					local points = {}
					for _, point in ipairs(v.Keypoints) do
						local item = { time = point.Time, value = encode(point.Value, depth + 1) }
						if t == "NumberSequence" then
							item.envelope = point.Envelope
						end
						points[#points + 1] = item
					end
					return { type = t, keypoints = points }
				end
				if t == "table" then
					assert(not seen[v], "UNSUPPORTED_VALUE: cyclic return value")
					seen[v] = true
					local result = {}
					local entries = 0
					for k, item in pairs(v) do
						entries += 1
						assert(entries <= 256, "VALUE_LIMIT: table exceeds 256 entries")
						assert(
							type(k) == "string" or type(k) == "number" and k >= 1 and k % 1 == 0,
							"UNSUPPORTED_VALUE: unsupported table key"
						)
						assert(type(k) ~= "string" or #k <= 256, "VALUE_LIMIT: table key exceeds 256 bytes")
						result[k] = encode(item, depth + 1)
					end
					seen[v] = nil
					return result
				end
				return { type = "Unsupported", valueType = t }
			end
			return encode(value, 0)
		end
		return codec
	end
	return Codec
end
return { Main = Main }
