--!strict

------------------------------ Module ------------------------------

local function Main()
	local Strings = {}
	function Strings.HasServerHint(bytes)
		if type(bytes) ~= "string" then
			return false
		end
		return bytes:find("ServerStorage", 1, true) ~= nil
			or bytes:find("ServerScriptService", 1, true) ~= nil
			or (
				bytes:find("Server", 1, true) ~= nil
				and (bytes:find("Storage", 1, true) ~= nil or bytes:find("ScriptService", 1, true) ~= nil)
			)
	end
	function Strings.Visit(bytes, visit, checkpoint, allStrings, includeLarge)
		if type(bytes) ~= "string" or #bytes > 1024 * 1024 then
			return false, "Bytecode exceeds 1 MiB"
		end
		local version = bytes:byte(1)
		if not version or version < 3 or version > 14 then
			return false, "Unsupported bytecode version"
		end
		local cursor = 2
		if version >= 4 then
			local types = bytes:byte(cursor)
			cursor += 1
			if not types or types < 1 or types > 3 then
				return false, "Unsupported type version"
			end
		end
		local function varint()
			local value, scale = 0, 1
			for _ = 1, 5 do
				local byte = bytes:byte(cursor)
				cursor += 1
				if not byte then
					return
				end
				value += (byte % 128) * scale
				if byte < 128 then
					return value
				end
				scale *= 128
			end
		end
		local count = varint()
		if not count or count > 50000 then
			return false, "Invalid string count"
		end
		local ranges = {}
		for index = 1, count do
			if index % 64 == 0 and checkpoint and checkpoint() == false then
				return false, "Cancelled"
			end
			local length = varint()
			if not length or cursor + length - 1 > #bytes then
				return false, "Truncated string table"
			end
			if length <= 4096 or includeLarge then
				ranges[#ranges + 1] = { cursor, cursor + length - 1 }
			end
			cursor += length
		end
		for index, range in ipairs(ranges) do
			if index % 64 == 0 and checkpoint and checkpoint() == false then
				return false, "Cancelled"
			end
			local text = bytes:sub(range[1], range[2])
			if allStrings or text:find("ServerStorage", 1, true) or text:find("ServerScriptService", 1, true) then
				visit(text)
			end
		end
		return true
	end
	function Strings.VisitAll(bytes, visit, checkpoint, includeLarge)
		return Strings.Visit(bytes, visit, checkpoint, true, includeLarge)
	end
	return Strings
end
return { Main = Main }
