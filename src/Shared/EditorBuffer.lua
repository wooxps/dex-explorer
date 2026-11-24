--!strict

------------------------------ Module ------------------------------

local function Main()
	local Buffer = {}
	function Buffer.Create(text)
		local self = { Pieces = {}, Length = 0, Version = 0, Stats = { Materializations = 0, Edits = 0 } }
		function self:SetText(value)
			assert(type(value) == "string")
			if self.Cached == value then
				return false
			end
			self.Pieces = #value > 0 and { { Text = value, Start = 1, Length = #value } } or {}
			self.Length = #value
			self.Cached = value
			self.Version += 1
			return true
		end
		function self:Replace(first, last, value)
			assert(type(value) == "string" and first >= 1 and last >= first and last <= self.Length + 1)
			local result = {}
			local at = 1
			local inserted = false
			local function append(piece, start, length)
				if length > 0 then
					result[#result + 1] = { Text = piece.Text, Start = start, Length = length }
				end
			end
			for _, piece in ipairs(self.Pieces) do
				local finish = at + piece.Length
				if finish <= first then
					result[#result + 1] = piece
				elseif at >= last then
					if not inserted then
						if #value > 0 then
							result[#result + 1] = { Text = value, Start = 1, Length = #value }
						end
						inserted = true
					end
					result[#result + 1] = piece
				else
					append(piece, piece.Start, math.max(0, first - at))
					if not inserted then
						if #value > 0 then
							result[#result + 1] = { Text = value, Start = 1, Length = #value }
						end
						inserted = true
					end
					if finish > last then
						append(piece, piece.Start + last - at, finish - last)
					end
				end
				at = finish
			end
			if not inserted and #value > 0 then
				result[#result + 1] = { Text = value, Start = 1, Length = #value }
			end
			self.Length += #value - (last - first)
			self.Pieces = result
			self.Cached = nil
			self.Version += 1
			self.Stats.Edits += 1
			if #result > 256 then
				local value = self:GetText()
				self:SetText(value)
				self.Pieces = { { Text = value, Start = 1, Length = #value } }
			end
		end
		function self:GetText()
			if self.Cached == nil then
				local chunks = {}
				for i, p in ipairs(self.Pieces) do
					chunks[i] = p.Text:sub(p.Start, p.Start + p.Length - 1)
				end
				self.Cached = table.concat(chunks)
				self.Stats.Materializations += 1
			end
			return self.Cached
		end
		self:SetText(text or "")
		return self
	end
	return Buffer
end
return { Main = Main }
