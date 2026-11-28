--!strict

local TokenBytes = 10

local function TokenAt(record, index: number): (number, number, number)
	local offset = (index - 1) * TokenBytes
	local raw = record.RawTokens
	return buffer.readu16(raw, offset), buffer.readu32(raw, offset + 2), buffer.readu32(raw, offset + 6)
end

local function Main(apps)
	local recent = {}
	local cachedBytes = 0
	local activeDocument, activeRevision, activeRecord
	local large = setmetatable({}, {__mode = "v"})
	local pending = setmetatable({}, {__mode = "v"})
	local pendingCst = setmetatable({}, {__mode = "v"})

	local function build(source: string, checkpoint, withCst: boolean?, newReader)
		local starts = {1}
		for at in string.gmatch(source, "\n()") do
			table.insert(starts, at)
			if checkpoint and #starts % 256 == 0 then checkpoint() end
		end
		local raw = buffer.create(math.max(80, math.min(#source * 2, 65536)))
		local count, used = 0, 0
		local function observe(kind, first, last)
			if used + TokenBytes > buffer.len(raw) then
				local larger = buffer.create(buffer.len(raw) * 2)
				buffer.copy(larger, 0, raw, 0, used)
				raw = larger
			end
			buffer.writeu16(raw, used, kind)
			buffer.writeu32(raw, used + 2, first)
			buffer.writeu32(raw, used + 6, last)
			count += 1
			used += TokenBytes
			if checkpoint and count % 128 == 0 then checkpoint() end
		end
		local reader = newReader()
		local valid, result = reader.parse(source, {captureComments = true, storeCstData = withCst == true}, observe, checkpoint)
		local diagnostics = {}
		for _, err in result.errors do
			local first, last = err.location.begin, err.location.end_
			table.insert(diagnostics, {
				Line = first.x + 1, Column = first.y + 1, EndLine = last.x + 1, EndColumn = last.y + 1,
				Message = err.message,
			})
		end
		local first = diagnostics[1]
		local record = {
			Source = source, Root = result.root, Starts = starts, RawTokens = raw, TokenCount = count, Cst = withCst == true,
			Diagnostics = { Available = valid or first ~= nil, Passed = valid, Errors = diagnostics,
				Line = first and first.Line, Column = first and first.Column,
				Message = if first then first.Message elseif valid then "No syntax errors" else "Parser could not finish" },
		}
		if #source <= 262144 then
			while #recent >= 4 or cachedBytes + #source > 262144 do
				cachedBytes -= #table.remove(recent, 1).Source
			end
			table.insert(recent, record)
			cachedBytes += #source
		else
			large[1] = record
		end
		return record
	end
	local function parse(source: string, checkpoint, withCst: boolean?)
		if activeRecord and activeRecord.Source == source and (not withCst or activeRecord.Cst) then
			return activeRecord
		end
		local previous = large[1]
		if previous and previous.Source == source and (not withCst or previous.Cst) then return previous end
		for index, record in recent do
			if record.Source == source and (not withCst or record.Cst) then
				table.remove(recent, index)
				table.insert(recent, record)
				return record
			end
		end
		local jobs = if withCst then pendingCst else pending
		local job = pendingCst[source] or jobs[source]
		if not job then
			local newReader = apps.EditorParserCore.New
			if not checkpoint then return build(source, nil, withCst, newReader) end
			job = {
				Thread = coroutine.create(function()
					return build(source, coroutine.yield, withCst, newReader)
				end),
			}
			jobs[source] = job
		end
		while not job.Record do
			if checkpoint and checkpoint() == false then return nil end
			if job.Error then error(job.Error, 0) end
			if job.Record then break end
			local ok, result = coroutine.resume(job.Thread)
			if not ok then
				job.Error = result
				if jobs[source] == job then jobs[source] = nil end
				error(result, 0)
			end
			if result then
				job.Record = result
				job.Thread = nil
				if pending[source] == job then pending[source] = nil end
				if pendingCst[source] == job then pendingCst[source] = nil end
			end
		end
		return job.Record
	end

	local function parseDocument(document, checkpoint, withCst: boolean?)
		local revision = document.Revision
		if activeDocument == document and activeRevision == revision and activeRecord and (not withCst or activeRecord.Cst) then
			return activeRecord
		end
		local function current()
			if document.Revision ~= revision then return false end
			if checkpoint and checkpoint() == false then return false end
			return document.Revision == revision
		end
		local record = parse(document:GetText(), current, withCst)
		if not record or document.Revision ~= revision then return nil end
		if activeDocument == document and activeRecord ~= record and activeRecord then
			local previous = table.find(recent, activeRecord)
			if previous then cachedBytes -= #table.remove(recent, previous).Source end
		end
		activeDocument, activeRevision, activeRecord = document, revision, record
		return record
	end
	local function nextNode(record, index)
		index += 1
		local node = record.Nodes[index]
		if node then return index, node, record.Parents[index], record.Scopes[index] end
	end
	local function nodes(record, checkpoint)
		if record.Nodes then return nextNode, record, 0 end
		local output, parents, scopes, calls = {}, {}, {}, {}
		local seen = {}
		local values, owners, blocks, keys = {}, {}, {}, {}
		local depth = 0
		local function push(value, parent, scope)
			seen[value] = true
			local kind = value.kind
			if kind then
				local index = #output + 1
				output[index], parents[index], scopes[index] = value, parent, scope
				if kind == "ExprCall" then calls[#calls + 1] = value end
				parent = value
				if kind == "StatBlock" then scope = value end
			end
			depth += 1
			values[depth], owners[depth], blocks[depth], keys[depth] = value, parent, scope, nil
		end
		if record.Root then push(record.Root, nil, nil) end
		local steps = 0
		while depth > 0 do
			local key, child = next(values[depth], keys[depth])
			if key == nil then
				depth -= 1
			else
				keys[depth] = key
				if type(child) == "table" and not seen[child] and not child.begin and key ~= "location"
					and key ~= "shadow" and key ~= "local" and key ~= "prefixLocal" and key ~= "cstNode" then
					push(child, owners[depth], blocks[depth])
				end
			end
			steps += 1
			if checkpoint and steps % 512 == 0 and checkpoint() == false then
				return function() return nil end, record, 0
			end
		end
		record.Nodes, record.Parents, record.Scopes, record.Calls = output, parents, scopes, calls
		return nextNode, record, 0
	end
	local function expressionIndex(record, checkpoint)
		if record.ExpressionIndex then return record.ExpressionIndex end
		local expressions, typeEnds = {}, {}
		for index, node in nodes(record, checkpoint) do
			if checkpoint and index % 256 == 0 and checkpoint() == false then return nil end
			local location = node.location
			local kind = node.kind
			if location then
				local first = record.Starts[location.begin.x + 1] + location.begin.y
				if kind:sub(1, 4) == "Expr" then
					local previous = expressions[first]
					local finish = location.end_
					if not previous or finish.x > previous.location.end_.x
						or finish.x == previous.location.end_.x and finish.y > previous.location.end_.y then
						expressions[first] = node
					end
				elseif kind:sub(1, 4) == "Type" then
					local last = record.Starts[location.end_.x + 1] + location.end_.y
					typeEnds[first] = math.max(typeEnds[first] or 0, last)
				end
			end
		end
		if not record.Nodes then return nil end
		record.ExpressionIndex = {Expressions = expressions, TypeEnds = typeEnds}
		return record.ExpressionIndex
	end
	local function mask(record, checkpoint)
		if record.Masked then return record.Masked end
		local source = record.Source
		local pieces, from = {}, 1
		for i = 1, record.TokenCount do
			if checkpoint and i % 256 == 0 then checkpoint() end
			local kind, first, last = TokenAt(record, i)
			if kind >= 266 and kind <= 269 or kind == 278 or kind == 279 or kind == 282 or kind == 283
				or kind == 286 or kind == 287 or kind == 289 then
				pieces[#pieces+1] = source:sub(from, first-1)
				pieces[#pieces+1] = source:sub(first, last-1):gsub("[^\n]", " ")
				from = last
			end
		end
		pieces[#pieces+1] = source:sub(from)
		record.Masked = table.concat(pieces)
		return record.Masked
	end
	local function peek(source)
		if activeRecord and activeRecord.Source == source then return activeRecord end
		local previous = large[1]
		if previous and previous.Source == source then return previous end
		for index = #recent, 1, -1 do
			local record = recent[index]
			if record.Source == source then return record end
		end
		return nil
	end
	return table.freeze({Parse = parse, ParseDocument = parseDocument, TokenAt = TokenAt, ExpressionIndex = expressionIndex, Peek = peek, Nodes = nodes, Mask = mask})
end
return { Main = Main }
