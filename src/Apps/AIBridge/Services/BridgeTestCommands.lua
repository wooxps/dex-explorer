--!strict

------------------------------ Module ------------------------------

local function Main()
	local Testing = {}
	local readable = {
		["dex_get_session"] = true,
		["dex_get_capabilities"] = true,
		["dex_get_tree"] = true,
		["dex_find_instances"] = true,
		["dex_get_instance"] = true,
		["dex_get_selection"] = true,
		["dex_get_properties"] = true,
		["dex_get_attributes"] = true,
		["dex_get_tags"] = true,
		["dex_get_history"] = true,
		["dex_list_players"] = true,
		["dex_get_player"] = true,
		["dex_get_camera"] = true,
		["dex_get_run"] = true,
		["dex_resolve_path"] = true,
		["dex_get_ancestors"] = true,
		["dex_get_class_schema"] = true,
		["dex_get_bounds"] = true,
		["dex_get_ui_layout"] = true,
		["dex_raycast"] = true,
		["dex_get_job"] = true,
		["dex_list_watches"] = true,
		["dex_get_remote_info"] = true,
		["dex_list_remotes"] = true,
		["dex_get_call"] = true,
		["dex_list_calls"] = true,
		["dex_list_remote_watches"] = true,
		["dex_list_captures"] = true,
		["dex_get_capture"] = true,
		["dex_read_capture"] = true,
		["dex_get_capture_assets"] = true,
		["dex_get_capture_relationships"] = true,
		["dex_inspect_instances"] = true,
		["dex_get_ui_at_point"] = true,
		["dex_world_to_screen"] = true,
		["dex_screen_to_ray"] = true,
		["dex_query_parts"] = true,
		["dex_get_lighting"] = true,
		["dex_compare_instances"] = true,
		["dex_get_ui_diagnostics"] = true,
		["dex_get_text_metrics"] = true,
		["dex_get_character_state"] = true,
		["dex_get_input_state"] = true,
		["dex_get_runtime_stats"] = true,
		["dex_get_logs"] = true,
	}
	local function prefix(value)
		local text = tostring(value)
		local length = math.min(#text, 240)
		if length < #text then
			while length > 0 do
				local byte = text:byte(length + 1)
				if byte < 128 or byte >= 192 then
					break
				end
				length -= 1
			end
		end
		return text:sub(1, length)
	end
	local function finite(value, default, minimum, maximum)
		if value == nil then
			return default
		end
		assert(
			type(value) == "number" and value == value and value >= minimum and value <= maximum,
			"INVALID_ARGUMENT: number outside supported range"
		)
		return value
	end
	local function fields(args, allowed)
		assert(type(args) == "table", "INVALID_ARGUMENT: arguments required")
		for key in pairs(args) do
			assert(allowed[key], "INVALID_ARGUMENT: unsupported testing argument")
		end
	end
	function Testing.Create(c)
		local result = { Commands = {} }
		local dead = false
		local conditions = c.Apps.BridgeConditions.Create(c)
		local size = c.Apps.BridgeConditions.Size
		local clock, wait = c.Clock or os.clock, c.Wait or task.wait
		local function alive(check)
			assert(not dead and (not check or check()), "CANCELLED: test helper ended")
		end
		local function add(name, run)
			result.Commands[#result.Commands + 1] = { Name = "dex_" .. name, Grant = "inspect", Run = run }
		end
		add("wait_for_condition", function(args)
			alive()
			fields(args, { condition = true, timeoutSeconds = true, pollIntervalSeconds = true })
			local condition = conditions:Prepare(args.condition)
			local timeout = finite(args.timeoutSeconds, 5, 0, 20)
			local interval = finite(args.pollIntervalSeconds, 0.1, 0.05, 1)
			assert(type(c.StartJob) == "function", "UNSUPPORTED: analysis jobs unavailable")
			return c.StartJob(function(check)
				local started = clock()
				local attempts = 0
				local last
				local function outcome(satisfied)
					return {
						scope = "client",
						status = satisfied and "satisfied" or "timed_out",
						satisfied = satisfied,
						timedOut = not satisfied,
						elapsed = clock() - started,
						attempts = attempts,
						lastObservation = last,
						pollIntervalSeconds = interval,
					}
				end
				while true do
					alive(check)
					if attempts > 0 and clock() - started > timeout then
						return outcome(false)
					end
					attempts += 1
					last = conditions:Evaluate(condition)
					local elapsed = clock() - started
					local satisfied = last.passed and (timeout == 0 or elapsed <= timeout)
					if satisfied or elapsed >= timeout then
						return outcome(satisfied)
					end
					wait(math.min(interval, math.max(0, timeout - elapsed)))
				end
			end)
		end)
		add("assert_conditions", function(args)
			alive()
			fields(args, { checks = true })
			assert(
				type(args.checks) == "table" and #args.checks >= 1 and #args.checks <= 32,
				"INVALID_ARGUMENT: choose 1 to 32 checks"
			)
			assert(size(args.checks) <= 32768, "VALUE_LIMIT: assertion request exceeds 32 KiB conservative budget")
			local checks = {}
			for _, item in ipairs(args.checks) do
				fields(item, { label = true, condition = true })
				assert(
					item.label == nil or type(item.label) == "string" and #item.label <= 100,
					"INVALID_ARGUMENT: label exceeds 100 bytes"
				)
				checks[#checks + 1] = { label = item.label, condition = conditions:Prepare(item.condition) }
			end
			local out = {
				scope = "client",
				nonAtomic = true,
				checks = {},
				requested = #checks,
				passed = true,
				counts = { passed = 0, failed = 0, unavailable = 0 },
				truncated = false,
				omittedChecks = 0,
			}
			local work = { remaining = 8192 }
			for index, item in ipairs(checks) do
				alive()
				local row = conditions:Evaluate(item.condition, work)
				row.index = index
				row.label = item.label
				if size(out) + size(row) > 47000 then
					out.truncated = true
					out.omittedChecks = #checks - index + 1
					out.passed = false
					break
				end
				out.checks[#out.checks + 1] = row
				out.counts[row.outcome] += 1
				if not row.passed then
					out.passed = false
				end
			end
			out.evaluated = #out.checks
			out.candidateWorkLimit = 8192
			out.candidatesExamined = 8192 - work.remaining
			return out
		end)
		add("batch_read", function(args)
			alive()
			fields(args, { requests = true, stopOnError = true, timeoutSeconds = true })
			assert(
				type(args.requests) == "table" and #args.requests >= 1 and #args.requests <= 8,
				"INVALID_ARGUMENT: choose 1 to 8 reads"
			)
			assert(
				args.stopOnError == nil or type(args.stopOnError) == "boolean",
				"INVALID_ARGUMENT: stopOnError must be boolean"
			)
			local timeout = finite(args.timeoutSeconds, 5, 0.05, 10)
			for _, item in ipairs(args.requests) do
				fields(item, { command = true, args = true })
				assert(readable[item.command], "PERMISSION_DENIED: command is not an allowlisted batch read")
				assert(
					item.args == nil or type(item.args) == "table",
					"INVALID_ARGUMENT: nested args must be an object"
				)
				assert(
					not item.args or item.args.sessionId == nil and item.args.commandId == nil,
					"INVALID_ARGUMENT: nested session/command IDs are not supported"
				)
			end
			assert(type(c.Read) == "function", "UNSUPPORTED: read dispatcher unavailable")
			local out = {
				scope = "client",
				nonAtomic = true,
				results = {},
				requested = #args.requests,
				executed = 0,
				failed = 0,
				skipped = 0,
				truncated = false,
			}
			local started = clock()
			local stopped
			for index, item in ipairs(args.requests) do
				alive()
				local row = { index = index, command = item.command, ok = false }
				if stopped or clock() - started >= timeout then
					row.error = { code = "NOT_EXECUTED", message = stopped or "Batch cooperative time budget reached" }
					out.skipped += 1
				else
					local ok, value = pcall(c.Read, item.command, item.args or {})
					out.executed += 1
					if ok then
						row.ok = true
						row.result = value
					else
						row.error = { code = "COMMAND_FAILED", message = prefix(value) }
					end
					if size(out) + size(row) > 48000 - 1024 * (#args.requests - index + 1) then
						row.ok = false
						row.result = nil
						row.error =
							{ code = "RESULT_LIMIT", message = "Read result omitted; request this read separately" }
						out.truncated = true
					end
					if not row.ok then
						out.failed += 1
						if args.stopOnError then
							stopped = "Stopped after a failed read"
						end
					end
				end
				out.results[#out.results + 1] = row
			end
			out.duration = clock() - started
			out.timeBudgetExceeded = out.duration >= timeout
			return out
		end)
		function result:Destroy()
			dead = true
		end
		return result
	end
	return Testing
end
return { Main = Main }
