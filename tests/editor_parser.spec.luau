do
	local parser = Apps.EditorParser
	local text = "local s = 'é'; local 42 = 1\r\nlocal 37 = 2\nlocal validAfter = 9"
	local recovered = parser.Parse(text)
	assert(recovered.Root and not recovered.Diagnostics.Passed)
	local errors = recovered.Diagnostics.Errors
	local first, second = errors[1], errors[3]
	assert(first and second and first.Line == 1 and first.Column == text:find("42", 1, true))
	assert(first.EndColumn == first.Column + 2 and second.Line == 2 and second.Column == 7)
	local symbols = Apps.EditorSymbols.New()
	symbols:Index(text)
	assert(symbols:Find("validAfter"), "symbols survive earlier syntax errors")
	assert(parser.Peek(text) == recovered and parser.Parse(text) == recovered)
	local generic = "type F<T, U...> = (T, U...) -> T\nlocal function id<T>(x: T): T\n return x\nend\nreturn `x={id(1)}`"
	local record = parser.Parse(generic)
	assert(record.Diagnostics.Passed and record.Root and not record.Cst)
	local cst = parser.Parse(generic, nil, true)
	assert(cst.Cst and cst.Root.body[2].func.cstNode and cst ~= record)
	assert(Apps.EditorFolding.Ranges(generic)[2] == 4)
	local repeated = string.rep("local v = 1\n", 600)
	local document = {Text = repeated, Revision = 1, GetText = function(self) return self.Text end}
	local firstJob = coroutine.create(function()
		return parser.ParseDocument(document, function() coroutine.yield() return true end)
	end)
	assert(coroutine.resume(firstJob) and coroutine.status(firstJob) == "suspended")
	document.Revision += 1
	document.Text = "return 2"
	local updated = parser.ParseDocument(document)
	while coroutine.status(firstJob) ~= "dead" do
		local ok, stale = coroutine.resume(firstJob)
		assert(ok and stale == nil, "superseded revision must not publish")
	end
	assert(parser.ParseDocument(document) == updated and not parser.Peek(repeated))
	local cancelled = repeated .. "-- aborted"
	assert(parser.Parse(cancelled, function() return false end) == nil and parser.Peek(cancelled) == nil)
	local running = coroutine.create(function()
		return parser.Parse(repeated .. "--first", function() coroutine.yield() return true end)
	end)
	assert(coroutine.resume(running))
	assert(parser.Parse("local x = { nested = true }").Diagnostics.Passed)
	local finished
	repeat
		local ok, result = coroutine.resume(running)
		assert(ok, result)
		finished = result
	until coroutine.status(running) == "dead"
	assert(finished.Diagnostics.Passed and #finished.Root.body == 600)
	for i = 1, 5 do parser.Parse("return " .. i .. " + 10") end
	assert(not parser.Peek("return 1 + 10") and parser.Peek("return 5 + 10"))
	local sharedText = repeated .. "-- shared job"
	local entered = 0
	local suspended = coroutine.create(function()
		return parser.Parse(sharedText, function()
			entered += 1
			if entered == 3 then coroutine.yield() end
			return true
		end)
	end)
	assert(coroutine.resume(suspended) and coroutine.status(suspended) == "suspended")
	local same = parser.Parse(sharedText)
	local resumed, sameAgain = coroutine.resume(suspended)
	assert(resumed and same == sameAgain and coroutine.status(suspended) == "dead")
	local nested = "local name = 0\ndo\n local name = 1\n print(name)\nend\nprint(name)"
	symbols:Index(nested)
	assert(symbols:Find("name", nested:find("print", 1, true)).Position == nested:find("name = 1", 1, true))
	assert(symbols:Find("name", #nested).Position == nested:find("name = 0", 1, true))
	local longLiteral = "return [=[" .. string.rep("x", 200000) .. "]=]"
	local checkpoints = 0
	assert(not parser.Parse(longLiteral, function() checkpoints += 1 return checkpoints < 3 end))
	assert(checkpoints == 3 and not parser.Peek(longLiteral))
	local many = parser.Parse(repeated .. "-- indexed")
	for _ in parser.Nodes(many, function() return false end) do error("partial AST index") end
	assert(not many.Nodes)
	for _ in parser.Nodes(many) do break end
	assert(many.Nodes and #many.Nodes > 600)
	print("PASS: parser recovery, UTF-8 byte ranges, CST, folding, revision reuse, cancellation, interleaved jobs and bounded history")
end
