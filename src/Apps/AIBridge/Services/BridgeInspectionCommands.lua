--!strict

------------------------------ Module ------------------------------

local function Main()
	local Inspection = {}
	local MAX_BYTES = 48 * 1024
	local function size(value)
		if type(value) == "string" then
			return #value * 6 + 2
		end
		if type(value) ~= "table" then
			return 32
		end
		local bytes = 2
		for key, item in pairs(value) do
			bytes += size(key) + size(item) + 2
		end
		return bytes
	end
	local function integer(value, default, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum,
			"INVALID_ARGUMENT: integer outside supported range"
		)
		return value
	end
	local function prefix(text, maximum)
		local length = math.min(#text, maximum)
		if length < #text then
			while length > 0 do
				local byte = text:byte(length + 1)
				if byte < 128 or byte >= 192 then
					break
				end
				length -= 1
			end
		end
		return text:sub(1, length)
	end
	local function failure(why)
		return tostring(why):sub(1, 160)
	end
	function Inspection.Create(c)
		local registry, codec = c.Registry, c.Codec
		local dead = false
		local result = { Commands = {} }
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		local function checkAlive(check)
			assert(not dead and (not check or check()), "CANCELLED: inspection ended")
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
			local properties, errors = {}, {}
			for _, key in ipairs(keys) do
				local ok, value = pcall(function()
					return object[key]
				end)
				if not ok then
					errors[key] = failure(value)
				elseif type(value) == "string" and #value > 2048 then
					errors[key] = "property_string_limit"
				else
					local good, encoded = pcall(codec.Encode, codec, value)
					if not good then
						errors[key] = failure(encoded)
					elseif
						type(encoded) == "table"
						and (encoded.type == "Unsupported" or encoded.type == "TruncatedString")
					then
						errors[key] = "unsupported_value: " .. tostring(encoded.valueType or encoded.type)
					elseif size(encoded) > 4096 then
						errors[key] = "property_size_limit"
					else
						properties[key] = encoded
					end
				end
			end
			return properties, errors
		end
		local function output(kind)
			return {
				scope = "client",
				kind = kind,
				items = {},
				errors = {},
				coverage = { nodesVisited = 0, truncated = false, resultByteLimit = MAX_BYTES, nonAtomic = true },
			}
		end
		local function append(out, row)
			if size(out) + size(row) > MAX_BYTES - 1024 then
				out.coverage.truncated = true
				out.coverage.reason = "result_byte_limit"
				return false
			end
			out.items[#out.items + 1] = row
			return true
		end
		local function problem(out, row)
			if size(out) + size(row) > MAX_BYTES - 1024 then
				out.coverage.truncated = true
				out.coverage.reason = "result_byte_limit"
				return false
			end
			out.errors[#out.errors + 1] = row
			return true
		end
		local function walk(root, maximum, check, out, visit)
			local queue = { root }
			local first, last = 1, 1
			while first <= last do
				checkAlive(check)
				local object = queue[first]
				queue[first] = nil
				first += 1
				if registry:Allowed(object) then
					out.coverage.nodesVisited += 1
					if visit(object) == false then
						return
					end
					if not registry:Allowed(object) then
						continue
					end
					local ok, children = pcall(object.GetChildren, object)
					if not ok then
						if
							not problem(
								out,
								{ instance = identity(object), operation = "GetChildren", error = failure(children) }
							)
						then
							return
						end
					else
						local room = maximum - out.coverage.nodesVisited - (last - first + 1)
						for index = 1, math.min(#children, math.max(0, room)) do
							checkAlive(check)
							local child = children[index]
							if registry:Allowed(child) then
								last += 1
								queue[last] = child
							end
						end
						if #children > math.max(0, room) then
							out.coverage.truncated = true
							out.coverage.nodeLimitReached = true
						end
					end
				end
			end
		end
		local function job(run)
			assert(type(c.StartJob) == "function", "UNSUPPORTED: inspection jobs unavailable")
			return c.StartJob(function(check)
				checkAlive(check)
				return run(check)
			end)
		end
		local trackKeys = {
			"Name",
			"IsPlaying",
			"Length",
			"Speed",
			"TimePosition",
			"WeightCurrent",
			"WeightTarget",
			"Priority",
			"Looped",
		}
		add("get_playing_animations", function(args)
			local root = registry:Resolve(args.instanceId)
			local limit = integer(args.limit, 50, 50)
			local maximum = integer(args.maxNodes, 1000, 5000)
			return job(function(check)
				local out = output("playing_animations")
				out.root = identity(root)
				out.coverage.nodeLimit = maximum
				out.coverage.animatorLimit = 16
				out.coverage.trackLimit = limit
				out.coverage.animatorsVisited = 0
				out.trackIdentity = "snapshot_descriptor"
				walk(root, maximum, check, out, function(object)
					if not object:IsA("Animator") then
						return
					end
					if out.coverage.animatorsVisited >= 16 then
						out.coverage.truncated = true
						out.coverage.reason = "animator_limit"
						return false
					end
					out.coverage.animatorsVisited += 1
					local animatorIdentity = identity(object)
					local ok, tracks = pcall(object.GetPlayingAnimationTracks, object)
					if not ok then
						return problem(out, {
							instance = animatorIdentity,
							operation = "GetPlayingAnimationTracks",
							error = failure(tracks),
						})
					end
					if type(tracks) ~= "table" then
						return problem(out, {
							instance = animatorIdentity,
							operation = "GetPlayingAnimationTracks",
							error = "invalid_engine_result",
						})
					end
					for index = 1, #tracks do
						checkAlive(check)
						if not registry:Allowed(object) then
							out.coverage.truncated = true
							out.coverage.reason = "stale_animator"
							problem(out, {
								instance = animatorIdentity,
								operation = "GetPlayingAnimationTracks",
								error = "STALE_INSTANCE: animator left this client during inspection",
							})
							return
						end
						if #out.items >= limit then
							out.coverage.truncated = true
							out.coverage.reason = "track_limit"
							return false
						end
						local track = tracks[index]
						local properties, errors = read(track, trackKeys)
						local animationOk, animation = pcall(function()
							return track.Animation
						end)
						if not animationOk then
							errors.Animation = failure(animation)
						elseif animation then
							local source, sourceErrors = read(animation, { "AnimationId" })
							properties.AnimationId = source.AnimationId
							if sourceErrors.AnimationId then
								errors.AnimationId = sourceErrors.AnimationId
							end
						else
							properties.AnimationId = { type = "nil" }
						end
						if
							not append(out, {
								animator = animatorIdentity,
								trackIndex = index,
								properties = properties,
								errors = errors,
							})
						then
							return false
						end
					end
				end)
				out.coverage.estimatedBytes = size(out)
				return out
			end)
		end)
		local soundKeys = {
			"SoundId",
			"Playing",
			"IsPaused",
			"IsLoaded",
			"TimePosition",
			"TimeLength",
			"PlaybackSpeed",
			"Volume",
			"Looped",
			"PlaybackLoudness",
			"RollOffMode",
			"RollOffMinDistance",
			"RollOffMaxDistance",
			"EmitterSize",
			"SoundGroup",
			"PlayOnRemove",
			"PlaybackRegionsEnabled",
			"PlaybackRegion",
			"LoopRegion",
		}
		local audioKeys = {
			"Asset",
			"AudioContent",
			"AutoLoad",
			"AutoPlay",
			"IsPlaying",
			"IsReady",
			"TimePosition",
			"TimeLength",
			"PlaybackSpeed",
			"Volume",
			"Looping",
			"LoopRegion",
			"PlaybackRegion",
		}
		add("get_sound_state", function(args)
			local root = registry:Resolve(args.rootId)
			local limit = integer(args.limit, 50, 100)
			local maximum = integer(args.maxNodes, 2000, 5000)
			assert(
				args.playingOnly == nil or type(args.playingOnly) == "boolean",
				"INVALID_ARGUMENT: playingOnly must be boolean"
			)
			return job(function(check)
				local out = output("sound_state")
				out.root = identity(root)
				out.coverage.nodeLimit = maximum
				out.coverage.itemLimit = limit
				out.coverage.playbackFilterUnavailable = 0
				walk(root, maximum, check, out, function(object)
					local classic = object:IsA("Sound")
					local modern = not classic and object:IsA("AudioPlayer")
					if not classic and not modern then
						return
					end
					local properties, errors = read(object, classic and soundKeys or audioKeys)
					local key = classic and "Playing" or "IsPlaying"
					local playing = properties[key]
					if args.playingOnly and playing ~= true then
						if errors[key] then
							out.coverage.playbackFilterUnavailable += 1
							if
								not problem(out, { instance = identity(object), property = key, error = errors[key] })
							then
								return false
							end
						end
						return
					end
					if #out.items >= limit then
						out.coverage.truncated = true
						out.coverage.reason = "item_limit"
						return false
					end
					local row = {
						instance = identity(object),
						properties = properties,
						errors = errors,
						spatialMode = classic and "parent_based" or "audio_graph_not_resolved",
					}
					if classic then
						local parent = object.Parent
						if parent and registry:Allowed(parent) then
							row.parent = identity(parent)
							if parent:IsA("BasePart") or parent:IsA("Attachment") then
								row.spatialProperties, row.spatialErrors = read(
									parent,
									parent:IsA("Attachment") and { "WorldPosition", "WorldCFrame" }
										or { "Position", "CFrame" }
								)
							end
						end
					end
					if not append(out, row) then
						return false
					end
				end)
				out.coverage.estimatedBytes = size(out)
				return out
			end)
		end)
		local lightingKeys = {
			"Ambient",
			"OutdoorAmbient",
			"Brightness",
			"ClockTime",
			"TimeOfDay",
			"GeographicLatitude",
			"GlobalShadows",
			"ShadowSoftness",
			"ColorShift_Bottom",
			"ColorShift_Top",
			"EnvironmentDiffuseScale",
			"EnvironmentSpecularScale",
			"ExposureCompensation",
			"FogColor",
			"FogStart",
			"FogEnd",
			"LightingStyle",
			"PrioritizeLightingQuality",
			"Technology",
		}
		local effectKeys = {
			Sky = {
				"SkyboxBk",
				"SkyboxDn",
				"SkyboxFt",
				"SkyboxLf",
				"SkyboxRt",
				"SkyboxUp",
				"CelestialBodiesShown",
				"MoonAngularSize",
				"MoonTextureId",
				"StarCount",
				"SunAngularSize",
				"SunTextureId",
				"SkyboxOrientation",
			},
			Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
			BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
			BlurEffect = { "Enabled", "Size" },
			ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
			DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
			SunRaysEffect = { "Enabled", "Intensity", "Spread" },
			ColorGradingEffect = { "Enabled", "TonemapperPreset" },
		}
		add("get_lighting", function()
			checkAlive()
			local lighting = c.service.Lighting
			if not lighting then
				local ok, value = pcall(function()
					return c.Game:GetService("Lighting")
				end)
				assert(ok and value, "UNSUPPORTED: Lighting service unavailable")
				lighting = value
			end
			local out = output("lighting")
			out.lighting = identity(lighting)
			out.properties, out.propertyErrors = read(lighting, lightingKeys)
			out.coverage.effectLimit = 32
			local children = lighting:GetChildren()
			local inspected = 0
			local visited = 0
			for index = 1, math.min(#children, 256) do
				checkAlive()
				visited += 1
				local child = children[index]
				if registry:Allowed(child) and (effectKeys[child.ClassName] or child:IsA("PostEffect")) then
					if inspected >= 32 then
						out.coverage.truncated = true
						out.coverage.reason = "effect_limit"
						break
					end
					inspected += 1
					local properties, errors = read(child, effectKeys[child.ClassName] or { "Enabled" })
					if not append(out, { instance = identity(child), properties = properties, errors = errors }) then
						break
					end
				end
			end
			out.coverage.nodesVisited = visited + 1
			if #children > 256 then
				out.coverage.truncated = true
				out.coverage.nodeLimitReached = true
			end
			out.coverage.estimatedBytes = size(out)
			return out
		end)
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Inspection
end
return { Main = Main }
