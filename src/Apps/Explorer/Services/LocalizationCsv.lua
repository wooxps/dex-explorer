--!strict

local metadata = { key = "Key", context = "Context", example = "Example", source = "Source" }
local bom = "\239\187\191"
local Csv = {}

local function encodeField(value)
	value = value or ""
	if value:find('[",\r\n]') then return '"' .. value:gsub('"', '""') .. '"' end
	return value
end

function Csv.Encode(entries)
	local locales, seen = {}, {}
	for _, entry in ipairs(entries) do
		for locale in pairs(entry.Values or {}) do
			if not seen[locale] then
				seen[locale] = true
				table.insert(locales, locale)
			end
		end
	end
	table.sort(locales)
	local header = { "Key", "Context", "Example", "Source" }
	for _, locale in ipairs(locales) do table.insert(header, encodeField(locale)) end
	local lines = { bom .. table.concat(header, ",") }
	for _, entry in ipairs(entries) do
		local row = { encodeField(entry.Key), encodeField(entry.Context), encodeField(entry.Example), encodeField(entry.Source) }
		for _, locale in ipairs(locales) do table.insert(row, encodeField((entry.Values or {})[locale])) end
		table.insert(lines, table.concat(row, ","))
	end
	return table.concat(lines, "\r\n") .. "\r\n"
end

function Csv.Decode(text)
	if text:sub(1, 3) == bom then text = text:sub(4) end
	assert(utf8.len(text), "Expected UTF-8 CSV")
	local entries, keys, contexts = {}, {}, {}
	local header, rowNumber = nil, 0
	local function accept(row)
		rowNumber += 1
		if not header then
			local seen = {}
			for i, label in ipairs(row) do
				local name = label:match("^%s*(.-)%s*$"):lower()
				assert(name ~= "" and not seen[name], "Empty or duplicate CSV column " .. i)
				seen[name] = true
				assert(metadata[name] or name:match("^%a%a%a?$") or name:match("^%a%a%a?%-[%w%-]+$"), "Invalid locale column " .. label)
				row[i] = metadata[name] or name
			end
			assert(seen.key or seen.source, "CSV needs a Key or Source column")
			header = row
			return
		end
		assert(#row == #header, "Wrong column count in CSV record " .. rowNumber)
		local entry = { Key = "", Context = "", Example = "", Source = "", Values = {} }
		for i, name in ipairs(header) do
			if metadata[name:lower()] then
				entry[name] = row[i]
			elseif row[i] ~= "" then
				entry.Values[name] = row[i]
			end
		end
		assert(entry.Key ~= "" or entry.Source ~= "", "Missing Key or Source in CSV record " .. rowNumber)
		if entry.Key ~= "" then
			assert(not keys[entry.Key], "Duplicate localization key in CSV record " .. rowNumber)
			keys[entry.Key] = true
		else
			local byContext = contexts[entry.Source] or {}
			assert(not byContext[entry.Context], "Duplicate source and context in CSV record " .. rowNumber)
			byContext[entry.Context] = true
			contexts[entry.Source] = byContext
		end
		table.insert(entries, entry)
	end

	local pos, length = 1, #text
	while pos <= length do
		local row, start = {}, pos
		while true do
			local value
			if text:byte(pos) == 34 then
				local pieces = {}
				pos += 1
				while true do
					local quote = text:find('"', pos, true)
					assert(quote, "Unclosed quote in CSV record " .. (rowNumber + 1))
					table.insert(pieces, text:sub(pos, quote - 1))
					pos = quote + 1
					if text:byte(pos) ~= 34 then break end
					table.insert(pieces, '"')
					pos += 1
				end
				value = table.concat(pieces)
			else
				local delimiter = text:find('[",\r\n]', pos) or length + 1
				value = text:sub(pos, delimiter - 1)
				pos = delimiter
			end
			table.insert(row, value)
			local delimiter = text:byte(pos)
			if delimiter ~= 44 then
				assert(not delimiter or delimiter == 10 or delimiter == 13, "Unexpected character in CSV record " .. (rowNumber + 1))
				if pos > start then accept(row) end
				if delimiter == 13 and text:byte(pos + 1) == 10 then pos += 1 end
				pos += 1
				break
			end
			pos += 1
		end
	end
	assert(header, "CSV is empty")
	return entries
end

return { Main = function() return Csv end }
