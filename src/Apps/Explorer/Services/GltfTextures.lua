--!strict

local service
local Textures = {}
local crcTable

-- PNG stores RGBA scanlines in a zlib stream. Stored DEFLATE blocks need no
-- compression library and are readable by standard glTF image decoders.
function Textures.Png(width, height, rgba)
	assert(width > 0 and height > 0 and buffer.len(rgba) == width * height * 4, "Invalid RGBA image")
	if not crcTable then
		crcTable = {}
		for byte = 0, 255 do
			local crc = byte
			for _ = 1, 8 do
				local mask = if bit32.btest(crc, 1) then 0xedb88320 else 0
				crc = bit32.bxor(bit32.rshift(crc, 1), mask)
			end
			crcTable[byte] = crc
		end
	end
	local function chunk(kind, data)
		local body, crc = kind .. data, 0xffffffff
		for i = 1, #body do
			crc = bit32.bxor(bit32.rshift(crc, 8), crcTable[bit32.band(bit32.bxor(crc, body:byte(i)), 255)])
			if i % 262144 == 0 then task.wait() end
		end
		return string.pack(">I4", #data) .. body .. string.pack(">I4", bit32.bnot(crc))
	end
	local stride = width * 4
	local scan = buffer.create(height * (stride + 1))
	for y = 0, height - 1 do buffer.copy(scan, y * (stride + 1) + 1, rgba, y * stride, stride) end
	local raw = buffer.tostring(scan)
	local deflate, a, b = { "\120\001" }, 1, 0
	for offset = 1, #raw, 65535 do
		local last = math.min(#raw, offset + 65534)
		local length = last - offset + 1
		table.insert(deflate, string.pack("<BI2I2", if last == #raw then 1 else 0, length, 65535 - length))
		table.insert(deflate, raw:sub(offset, last))
		for i = offset, last do a += raw:byte(i); b += a end
		a, b = a % 65521, b % 65521
		if offset > 1 then task.wait() end
	end
	table.insert(deflate, string.pack(">I4", b * 65536 + a))
	return "\137PNG\r\n\26\n"
		.. chunk("IHDR", string.pack(">I4I4BBBBB", width, height, 8, 6, 0, 0, 0))
		.. chunk("IDAT", table.concat(deflate)) .. chunk("IEND", "")
end

local function read(content)
	local image = service.AssetService:CreateEditableImageAsync(content)
	assert(image, "Editable image memory budget exceeded")
	local ok, size, pixels = pcall(function()
		return image.Size, image:ReadPixelsBuffer(Vector2.zero, image.Size)
	end)
	image:Destroy()
	if not ok then error(size, 0) end
	return size, pixels
end

local function assetKey(content)
	-- Separate Roblox Content values can point to the same asset.
	if typeof(content) == "Content" then
		return content.Uri or content.Object or content
	end
	return content
end

function Textures.Create(addImage)
	local images, packedMaps = {}, {}
	local function texture(content, base, tint)
		if not content or content == Content.none then return nil, false end
		local asset = assetKey(content)
		local bucket = images[asset] or {}
		images[asset] = bucket
		local key = if base then string.pack("<ffffff",base.R,base.G,base.B,tint.R,tint.G,tint.B) else ""
		if not bucket[key] then
			local size, pixels = read(content)
			local hasAlpha = false
			for pos = 0, buffer.len(pixels)-4, 4 do
				local alpha = buffer.readu8(pixels, pos+3)
				if base then
					local opacity = alpha/255
					local function composite(channel, background, foreground)
						local value = buffer.readu8(pixels,pos+channel)*foreground*opacity + 255*background*(1-opacity)
						buffer.writeu8(pixels,pos+channel,math.clamp(math.round(value),0,255))
					end
					composite(0,base.R,tint.R)
					composite(1,base.G,tint.G)
					composite(2,base.B,tint.B)
					buffer.writeu8(pixels,pos+3,255)
				elseif alpha < 255 then
					hasAlpha = true
					break
				end
				if pos % 1048576 == 1048572 then task.wait() end
			end
			bucket[key] = { info = { index = addImage(Textures.Png(size.X, size.Y, pixels)) }, alpha = hasAlpha }
		end
		return bucket[key].info, bucket[key].alpha
	end
	local function metallicRoughness(metal, rough)
		if metal == Content.none and rough == Content.none then return nil end
		local group = packedMaps[metal] or {}
		packedMaps[metal] = group
		if group[rough] then return group[rough] end
		local ms, mp, rs, rp
		if metal ~= Content.none then ms, mp = read(metal) end
		if rough ~= Content.none then rs, rp = read(rough) end
		local width = math.max(ms and ms.X or 1, rs and rs.X or 1)
		local height = math.max(ms and ms.Y or 1, rs and rs.Y or 1)
		local function sample(pixels, size, x, y)
			return buffer.readu8(pixels, 4 * (math.floor((y+.5)*size.Y/height)*size.X + math.floor((x+.5)*size.X/width)))
		end
		local output = buffer.create(width * height * 4)
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				local g = if rp then sample(rp, rs, x, y) else 255
				local b = if mp then sample(mp, ms, x, y) else 0
				buffer.writeu32(output, 4 * (y*width+x), bit32.bor(0xff0000ff, bit32.lshift(g,8), bit32.lshift(b,16)))
			end
			if y % 128 == 127 then task.wait() end
		end
		group[rough] = { index = addImage(Textures.Png(width, height, output)) }
		return group[rough]
	end
	return texture, metallicRoughness
end

return {
	InitDeps = function(d) service = d.service end, InitAfterMain = function() end,
	Main = function() return Textures end,
}
