--!strict

local env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	env, service = d.env, d.service
end
------------------------------ Module ------------------------------

local function Main()
	local Download = {}
	function Download.Extension(data)
		if data:sub(1, 8) == "\137PNG\13\10\26\10" then
			return ".png"
		end
		if data:sub(1, 3) == "\255\216\255" then
			return ".jpg"
		end
		if data:sub(1, 3) == "GIF" then
			return ".gif"
		end
		if data:sub(1, 4) == "OggS" then
			return ".ogg"
		end
		if data:sub(1, 4) == "fLaC" then
			return ".flac"
		end
		if data:sub(1, 3) == "ID3" or data:byte(1) == 255 and data:byte(2) and data:byte(2) >= 224 then
			return ".mp3"
		end
		if data:sub(1, 4) == "RIFF" then
			return data:sub(9, 12) == "WEBP" and ".webp" or ".wav"
		end
		if data:sub(1, 7) == "version" then
			return ".mesh"
		end
		if data:sub(1, 8) == "<roblox!" then
			return ".rbxm"
		end
		if data:find("<roblox", 1, true) then
			return ".rbxmx"
		end
		return ".bin"
	end
	local function allowed(url)
		local host = url:match("^https://([^/:?#]+)")
		return host
			and (host == "assetdelivery.roblox.com" or host:sub(-11) == ".rbxcdn.com" or host:sub(-11) == ".roblox.com")
	end
	function Download.Save(record)
		assert(
			record.Id and record.Id:match("^%d+$"),
			"This asset has no downloadable Roblox ID. Copy its URI instead."
		)
		assert(
			type(env.request) == "function" and type(env.writefile) == "function",
			"Downloads need request and writefile support."
		)
		local url = "https://assetdelivery.roblox.com/v2/assetId/" .. record.Id
		local function fetch(address)
			assert(allowed(address), "Asset delivery returned an unsupported host.")
			local response = env.request({ Url = address, Method = "GET" })
			assert(
				type(response) == "table" and (response.StatusCode or response.Status) == 200,
				"Asset download denied or unavailable (HTTP "
					.. tostring(type(response) == "table" and (response.StatusCode or response.Status) or "?")
					.. ")."
			)
			local data = response.Body
			assert(
				type(data) == "string" and #data > 0 and #data <= 64 * 1024 * 1024,
				"Asset is empty or exceeds the 64 MB download limit."
			)
			return data
		end
		local body = fetch(url)
		local ok, packet = pcall(service.HttpService.JSONDecode, service.HttpService, body)
		if ok and type(packet) == "table" then
			local location = packet.locations and packet.locations[1] and packet.locations[1].location
			assert(
				type(location) == "string",
				"Roblox did not provide a download location. The asset may be private or unavailable."
			)
			body = fetch(location)
		end
		local prefix = body:sub(1, 256):lower():match("^%s*(.*)")
		assert(
			not prefix:match("^<!doctype html")
				and not prefix:match("^<html")
				and not prefix:match("^[{[]")
				and not prefix:match("^<error"),
			"Asset endpoint returned an error instead of a file."
		)
		local extension = Download.Extension(body)
		if env.makefolder then
			pcall(env.makefolder, "dex-explorer")
			pcall(env.makefolder, "dex-explorer/assets")
		end
		local path = "dex-explorer/assets/" .. record.Kind .. "_" .. record.Id .. "_" .. os.date("%Y%m%d_%H%M%S") .. extension
		if env.isfile then
			local base = path
			local suffix = 1
			while env.isfile(path) do
				path = base:sub(1, -#extension - 1) .. "_" .. suffix .. extension
				suffix += 1
			end
		end
		env.writefile(path, body)
		return path, #body
	end
	return Download
end
return { InitDeps = InitDeps, Main = Main }
