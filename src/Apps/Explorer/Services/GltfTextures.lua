--!strict

local service
local Textures = {}
local crcTables

function Textures.Png(width, height, rgba, checkpoint)
	assert(width > 0 and height > 0 and buffer.len(rgba) == width * height * 4, "Invalid RGBA image")
	if not crcTables then
		local first = {}
		for byte = 0, 255 do
			local crc = byte
			for _ = 1, 8 do
				local mask = if bit32.btest(crc, 1) then 0xedb88320 else 0
				crc = bit32.bxor(bit32.rshift(crc, 1), mask)
			end
			first[byte] = crc
		end
		crcTables = {first, {}, {}, {}}
		for i = 2, 4 do
			for byte = 0, 255 do
				local previous = crcTables[i-1][byte]
				crcTables[i][byte] = bit32.bxor(bit32.rshift(previous,8), first[bit32.band(previous,255)])
			end
		end
	end
	local first, second, third, fourth = table.unpack(crcTables)
	local function chunk(kind, data)
		local body, crc = kind .. data, 0xffffffff
		local length = #body
		local lastWord = length - length%4
		local bytes = buffer.fromstring(body)
		for start = 0,lastWord-1,32768 do
			for i = start,math.min(start+32768,lastWord)-4,4 do
				crc = bit32.bxor(crc,buffer.readu32(bytes,i))
				crc = bit32.bxor(fourth[bit32.band(crc,255)],third[bit32.extract(crc,8,8)],
					second[bit32.extract(crc,16,8)],first[bit32.rshift(crc,24)])
			end
			if checkpoint then checkpoint() end
		end
		for i = lastWord+1,length do
			crc = bit32.bxor(bit32.rshift(crc, 8), first[bit32.band(bit32.bxor(crc, body:byte(i)), 255)])
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
		local tail = last - length % 8
		for i = offset, tail, 8 do
			local p1,p2,p3,p4,p5,p6,p7,p8 = raw:byte(i,i+7)
			b += 8*a+8*p1+7*p2+6*p3+5*p4+4*p5+3*p6+2*p7+p8
			a += p1+p2+p3+p4+p5+p6+p7+p8
		end
		for i = tail+1,last do a += raw:byte(i); b += a end
		a, b = a % 65521, b % 65521
		if checkpoint then checkpoint() end
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

function Textures.AssetKey(content)
	if typeof(content) == "Content" then
		return content.Uri or content.Object or content
	end
	return content
end

function Textures.Create(addImage, checkpoint)
	local images, packedMaps = {}, {}
	local pixelCache, pixelBytes = {}, 0
	local cacheLimit = 16*1024*1024
	local function pixelsFor(content)
		local key = Textures.AssetKey(content)
		local cached = pixelCache[key]
		if cached then return cached.size, cached.pixels end
		local size, pixels = read(content)
		local length = buffer.len(pixels)
		if pixelBytes+length <= cacheLimit then
			pixelCache[key] = {size=size,pixels=pixels}
			pixelBytes += length
		end
		return size,pixels
	end
	local function texture(content, base, tint)
		if not content or content == Content.none then return nil, false end
		local asset = Textures.AssetKey(content)
		local bucket = images[asset] or {}
		images[asset] = bucket
		local key = if base then string.pack("<ffffff",base.R,base.G,base.B,tint.R,tint.G,tint.B) else ""
		if not bucket[key] then
			local size, pixels = pixelsFor(content)
			local hasAlpha = false
			if base then
				local original = pixels
				pixels = buffer.create(buffer.len(original))
				for pos = 0, buffer.len(pixels)-4, 4 do
					local rgba = buffer.readu32(original,pos)
					local opacity = bit32.rshift(rgba,24)/255
					local uncovered = 1-opacity
					local r = math.clamp(math.round(bit32.band(rgba,255)*tint.R*opacity + 255*base.R*uncovered),0,255)
					local g = math.clamp(math.round(bit32.extract(rgba,8,8)*tint.G*opacity + 255*base.G*uncovered),0,255)
					local b = math.clamp(math.round(bit32.extract(rgba,16,8)*tint.B*opacity + 255*base.B*uncovered),0,255)
					buffer.writeu32(pixels,pos,bit32.bor(0xff000000,r,bit32.lshift(g,8),bit32.lshift(b,16)))
					if checkpoint and pos % 32768 == 32764 then checkpoint() end
				end
			else
				for pos = 3, buffer.len(pixels)-1, 4 do
					if buffer.readu8(pixels,pos) < 255 then hasAlpha = true; break end
					if checkpoint and pos % 32768 == 32767 then checkpoint() end
				end
			end
			bucket[key] = { info = { index = addImage(Textures.Png(size.X, size.Y, pixels, checkpoint)) }, alpha = hasAlpha }
		end
		return bucket[key].info, bucket[key].alpha
	end
	local function metallicRoughness(metal, rough)
		if metal == Content.none and rough == Content.none then return nil end
		local metalKey, roughKey = Textures.AssetKey(metal), Textures.AssetKey(rough)
		local group = packedMaps[metalKey] or {}
		packedMaps[metalKey] = group
		if group[roughKey] then return group[roughKey] end
		local ms, mp, rs, rp
		if metal ~= Content.none then ms, mp = pixelsFor(metal) end
		if rough ~= Content.none then rs, rp = pixelsFor(rough) end
		local width = math.max(ms and ms.X or 1, rs and rs.X or 1)
		local height = math.max(ms and ms.Y or 1, rs and rs.Y or 1)
		local function columns(size)
			if not size then return nil end
			local column = table.create(width)
			for x = 0,width-1 do column[x+1] = 4*math.floor((x+.5)*size.X/width) end
			return column
		end
		local metalColumns, roughColumns = columns(ms), columns(rs)
		local output = buffer.create(width * height * 4)
		for y = 0, height - 1 do
			local metalRow = if ms then 4*math.floor((y+.5)*ms.Y/height)*ms.X else 0
			local roughRow = if rs then 4*math.floor((y+.5)*rs.Y/height)*rs.X else 0
			for x = 1,width do
				local g = if rp then buffer.readu8(rp,roughRow+roughColumns[x]) else 255
				local b = if mp then buffer.readu8(mp,metalRow+metalColumns[x]) else 0
				buffer.writeu32(output, 4*(y*width+x-1), bit32.bor(0xff0000ff,bit32.lshift(g,8),bit32.lshift(b,16)))
			end
			if checkpoint and y % 8 == 7 then checkpoint() end
		end
		group[roughKey] = { index = addImage(Textures.Png(width, height, output, checkpoint)) }
		return group[roughKey]
	end
	return texture, metallicRoughness
end

return {
	InitDeps = function(d) service = d.service end,
	Main = function() return Textures end,
}
