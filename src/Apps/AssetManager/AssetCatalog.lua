--!strict

local API

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	API = d.API
end
------------------------------ Module ------------------------------

local function Main()
	local Catalog = {}
	local known = {
		Sound = { SoundId = "Sounds" },
		AudioPlayer = { Asset = "Sounds", AssetId = "Sounds" },
		Animation = { AnimationId = "Animations" },
		ImageLabel = { Image = "Images" },
		ImageButton = { Image = "Images" },
		Decal = { Texture = "Images", TextureContent = "Images" },
		Texture = { Texture = "Images" },
		MeshPart = { MeshId = "Meshes", MeshContent = "Meshes", TextureID = "Images", TextureContent = "Images" },
		SpecialMesh = { MeshId = "Meshes", TextureId = "Images" },
		SurfaceAppearance = {
			ColorMap = "Images",
			NormalMap = "Images",
			MetalnessMap = "Images",
			RoughnessMap = "Images",
		},
		MaterialVariant = {
			ColorMap = "Images",
			NormalMap = "Images",
			MetalnessMap = "Images",
			RoughnessMap = "Images",
		},
		ParticleEmitter = { Texture = "Images" },
		Beam = { Texture = "Images" },
		Trail = { Texture = "Images" },
		Shirt = { ShirtTemplate = "Images" },
		Pants = { PantsTemplate = "Images" },
		ShirtGraphic = { Graphic = "Images" },
		Sky = {
			SkyboxBk = "Images",
			SkyboxDn = "Images",
			SkyboxFt = "Images",
			SkyboxLf = "Images",
			SkyboxRt = "Images",
			SkyboxUp = "Images",
			SunTextureId = "Images",
			MoonTextureId = "Images",
		},
		CharacterMesh = { MeshId = "Meshes", BaseTextureId = "Images", OverlayTextureId = "Images" },
		WrapLayer = { ReferenceMeshId = "Meshes", CageMeshId = "Meshes" },
		WrapTarget = { CageMeshId = "Meshes" },
	}
	local function readProperty(object, property)
		return object[property]
	end

	function Catalog.Normalize(value)
		if typeof(value) == "Content" then
			local ok, uri = pcall(readProperty, value, "Uri")
			if not ok then
				return
			end
			value = uri
		end
		if type(value) == "number" then
			if value <= 0 or value % 1 ~= 0 then
				return
			end
			value = string.format("%.0f", value)
		end
		if type(value) ~= "string" then
			return
		end
		local id = value:match("^rbxassetid://(%d+)$")
		if not id then
			value = value:match("^%s*(.-)%s*$")
			id = value:match("^rbxassetid://(%d+)$") or value:match("^(%d+)$")
			if not id then
				local host = value:match("^https?://([^/]+)")
				if host and (host == "roblox.com" or host:sub(-11) == ".roblox.com") then
					id = value:match("[?&]id=(%d+)")
				end
			end
		end
		if id then
			id = id:gsub("^0+", "")
			if id == "" then
				return
			end
			return "rbxassetid://" .. id, id
		end
		if value:match("^rbxasset://") or value:match("^rbxgameasset://") or value:match("^rbxtemp://") then
			return value
		end
	end
	local fields = {}
	local function properties(class)
		if fields[class] then
			return fields[class]
		end
		local result = {}
		local visited = {}
		local current = class
		while current and not visited[current] do
			visited[current] = true
			for key, kind in pairs(known[current] or {}) do
				result[key] = kind
			end
			local meta = API and API.Classes and API.Classes[current]
			if not meta then
				break
			end
			for _, prop in pairs(meta.Properties or {}) do
				local typ = prop.ValueType and prop.ValueType.Name
				local key = prop.Name
				if key and (typ == "Content" or typ == "ContentId") and not result[key] then
					local lower = key:lower()
					result[key] = lower:find("mesh", 1, true) and "Meshes"
						or lower:find("animation", 1, true) and "Animations"
						or lower:find("sound", 1, true) and "Sounds"
						or (lower:find("texture", 1, true) or lower:find("image", 1, true) or lower:find("map", 1, true)) and "Images"
						or nil
				end
			end
			current = type(meta.Superclass) == "table" and meta.Superclass.Name or meta.Superclass
		end
		fields[class] = result
		return result
	end
	function Catalog.Scan(objects, checkpoint)
		local records, index = {}, {}
		local checked = 0
		local unreadable = 0
		local snapshot = table.clone(objects)
		for object in pairs(snapshot) do
			if checkpoint and not checkpoint(checked, #records) then
				return nil, "Cancelled"
			end
			checked += 1
			local ok, class = pcall(readProperty, object, "ClassName")
			if not ok or type(class) ~= "string" then
				continue
			end
			local name
			for property, kind in pairs(properties(class)) do
				local good, value = pcall(readProperty, object, property)
				if not good then
					unreadable += 1
					continue
				end
				local uri, id = Catalog.Normalize(value)
				if uri then
					if not name then
						local named, value = pcall(readProperty, object, "Name")
						name = named and type(value) == "string" and value or class
					end
					local key = kind .. ":" .. uri
					local record = index[key]
					if not record then
						record = {
							Key = key,
							Kind = kind,
							URI = uri,
							Id = id,
							Uses = {},
							Name = name,
							Names = {},
							SeenNames = {},
						}
						index[key] = record
						records[#records + 1] = record
					end
					if not record.SeenNames[name] then
						record.SeenNames[name] = true
						record.Names[#record.Names + 1] = name
					end
					record.Uses[#record.Uses + 1] = { Object = object, Property = property }
				end
			end
		end
		for _, record in ipairs(records) do
			record.Search = (table.concat(record.Names, " ") .. " " .. record.URI):lower()
			record.Names = nil
			record.SeenNames = nil
		end
		table.sort(records, function(a, b)
			if a.Kind ~= b.Kind then
				return a.Kind < b.Kind
			end
			return a.URI < b.URI
		end)
		return records, { Objects = checked, Unreadable = unreadable }
	end
	function Catalog.IsCurrent(record, use)
		local ok, value = pcall(readProperty, use.Object, use.Property)
		return ok and Catalog.Normalize(value) == record.URI
	end
	return Catalog
end
return { InitDeps = InitDeps, Main = Main }
