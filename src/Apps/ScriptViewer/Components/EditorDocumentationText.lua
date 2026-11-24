--!strict

local function Main()
	local Text = {}
	local richEntities = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }
	local htmlStyles = {
		code = { '<font face="Code">', "</font>" },
		kbd = { '<font face="Code">', "</font>" },
		pre = { '<font face="Code">', "</font>" },
		strong = { "<b>", "</b>" },
		b = { "<b>", "</b>" },
		em = { "<i>", "</i>" },
		i = { "<i>", "</i>" },
		a = { '<font color="#00B8FF"><u>', "</u></font>" },
	}
	local entities = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }
	function Text.Escape(text)
		return (text:gsub("[&<>]", richEntities))
	end
	function Text.Format(body, format)
		if format ~= "html" then
			return body:gsub("`([^`\n]+)`", "%1"), Text.Escape(body):gsub("`([^`\n]+)`", '<font face="Code">%1</font>')
		end
		local plain, rich, stack = {}, {}, {}
		local function addText(text)
			text = text:gsub("&([%w#]+);", function(entity)
				if entities[entity] then
					return entities[entity]
				end
				local decimal = entity:match("^#(%d+)$")
				local hex = entity:match("^#[xX](%x+)$")
				local point = decimal and tonumber(decimal) or hex and tonumber(hex, 16)
				if point and point > 0 and point <= 0x10FFFF and (point < 0xD800 or point > 0xDFFF) then
					return utf8.char(point)
				end
				return nil
			end)
			plain[#plain + 1] = text
			rich[#rich + 1] = Text.Escape(text)
		end
		local cursor = 1
		for first, close, name, last in body:gmatch("()<(/?)([%a][%w]*)[^<>]*>()") do
			addText(body:sub(cursor, first - 1))
			cursor = last
			name = name:lower()
			local style = htmlStyles[name]
			if style then
				if close == "" then
					stack[#stack + 1] = name
					rich[#rich + 1] = style[1]
				elseif stack[#stack] == name then
					stack[#stack] = nil
					rich[#rich + 1] = style[2]
				end
			elseif name == "br" or (close ~= "" and (name == "p" or name == "li" or name == "tr")) then
				addText("\n")
			elseif name == "li" then
				addText("• ")
			elseif name == "td" and close ~= "" then
				addText("  ")
			end
		end
		addText(body:sub(cursor))
		for index = #stack, 1, -1 do
			rich[#rich + 1] = htmlStyles[stack[index]][2]
		end
		return table.concat(plain), table.concat(rich)
	end
	return Text
end

return { Main = Main }
