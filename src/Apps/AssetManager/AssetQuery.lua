--!strict

------------------------------ Module ------------------------------

local function Main()
	local Query = {}
	function Query.Create()
		local snapshot, prepared, orders = nil, {}, {}
		local previous
		local stats = { Sorts = 0, Candidates = 0, Normalizations = 0 }
		local query = { Stats = stats }
		function query.Filter(records, category, term, key, descending, checkpoint)
			if snapshot ~= records then
				local nextPrepared = {}
				for i, r in ipairs(records) do
					nextPrepared[i] = {
						Record = r,
						Search = r.Search or (r.Name .. " " .. r.URI):lower(),
						Name = r.Name:lower(),
						ID = r.Id or r.URI,
						References = #r.Uses,
					}
					stats.Normalizations += 1
					if checkpoint and i % 256 == 0 and not checkpoint() then
						return nil
					end
				end
				snapshot, prepared, orders, previous = records, nextPrepared, {}, nil
			end
			local orderKey = key .. (descending and ":desc" or ":asc")
			local ordered = orders[orderKey]
			if not ordered then
				ordered = table.clone(prepared)
				table.sort(ordered, function(a, b)
					local av, bv = a[key], b[key]
					if av == bv then
						return a.Record.Key < b.Record.Key
					end
					if key == "ID" then
						local aId, bId = a.Record.Id, b.Record.Id
						if (aId ~= nil) ~= (bId ~= nil) then
							return aId ~= nil
						end
						if aId and bId and #aId ~= #bId then
							if descending then
								return #aId > #bId
							end
							return #aId < #bId
						end
					end
					if descending then
						return av > bv
					end
					return av < bv
				end)
				orders[orderKey] = ordered
				stats.Sorts += 1
			end
			local candidates = ordered
			if
				previous
				and previous.Category == category
				and previous.Order == orderKey
				and term:sub(1, #previous.Term) == previous.Term
			then
				candidates = previous.Rows
			end
			local rows, result = {}, {}
			for i, item in ipairs(candidates) do
				stats.Candidates += 1
				local r = item.Record
				if (category == "All" or r.Kind == category) and item.Search:find(term, 1, true) then
					rows[#rows + 1] = item
					result[#result + 1] = r
				end
				if checkpoint and i % 256 == 0 and not checkpoint() then
					return nil
				end
			end
			if checkpoint and not checkpoint() then
				return nil
			end
			previous = { Category = category, Order = orderKey, Term = term, Rows = rows }
			return result
		end
		return query
	end
	return Query
end
return { Main = Main }
