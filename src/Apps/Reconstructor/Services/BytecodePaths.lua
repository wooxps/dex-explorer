--!strict

------------------------------ Module ------------------------------

local function Main()
	local Paths = {}
	local extract, rshift = bit32.extract, bit32.rshift
	local auxiliary = {}
	for _, op in ipairs({
		7,
		8,
		12,
		15,
		16,
		20,
		27,
		28,
		29,
		30,
		31,
		32,
		53,
		55,
		58,
		60,
		66,
		74,
		75,
		77,
		78,
		79,
		80,
		83,
		84,
		85,
		86,
		87,
		88,
		90,
		91,
	}) do
		auxiliary[op] = true
	end
	local roots = { ServerStorage = true, ServerScriptService = true }
	local properties = {
		Name = true,
		ClassName = true,
		Source = true,
		Value = true,
		Disabled = true,
		Enabled = true,
		Archivable = true,
	}
	local function analyze(bytes, label, emit, checkpoint, seeds)
		if type(bytes) ~= "string" or #bytes > 1024 * 1024 then
			return false, "Size limit"
		end
		local cursor, steps = 1, 0
		local function check()
			steps += 1
			if steps > 1000000 then
				error("Analysis step limit", 0)
			end
			if steps % 128 == 0 and checkpoint and checkpoint() == false then
				error("Cancelled", 0)
			end
		end
		local function skip(count)
			if count < 0 or cursor + count > #bytes + 1 then
				error("Truncated bytecode", 0)
			end
			cursor += count
		end
		local function byte()
			local v = bytes:byte(cursor)
			if not v then
				error("Truncated bytecode", 0)
			end
			cursor += 1
			return v
		end
		local function varint(maximum)
			local value, scale = 0, 1
			for _ = 1, 5 do
				local b = byte()
				value += (b % 128) * scale
				if b < 128 then
					if value > (maximum or 1048576) then
						error("Count limit", 0)
					end
					return value
				end
				scale *= 128
			end
			error("Invalid varint", 0)
		end
		local function stringWord(at)
			local a, b, c, d = bytes:byte(at, at + 3)
			if not d then
				error("Truncated instruction", 0)
			end
			return a + b * 256 + c * 65536 + d * 16777216
		end
		local word = stringWord
		local readNumber
		if buffer then
			local data = buffer.fromstring(bytes)
			word = function(at)
				return buffer.readu32(data, at - 1)
			end
			readNumber = function(at)
				return buffer.readf64(data, at - 1)
			end
		end
		local function parse()
			local version = byte()
			if version < 3 or version > 14 then
				error("Unsupported bytecode version", 0)
			end
			local types = version >= 4 and byte() or 0
			if version >= 4 and (types < 1 or types > 3) then
				error("Unsupported type version", 0)
			end
			local strings = {}
			for i = 1, varint(50000) do
				check()
				local size = varint()
				local start = cursor
				skip(size)
				if size <= 512 then
					strings[i] = bytes:sub(start, cursor - 1)
				end
			end
			if types == 3 then
				local index = byte()
				local entries = 0
				while index ~= 0 do
					entries += 1
					if entries > 255 then
						error("Type remapping limit", 0)
					end
					varint(50000)
					index = byte()
				end
			end
			local protos, total = {}, 0
			for i = 1, varint(10000) do
				check()
				local finish
				if version >= 12 then
					local size = varint()
					finish = cursor + size
					if size == 0 or finish > #bytes + 1 then
						error("Invalid prototype size", 0)
					end
				end
				skip(1)
				local parameterCount = byte()
				local upvalueCount = byte()
				local vararg = byte() ~= 0
				local argumentTypes, argumentNames = {}, {}
				if version >= 4 then
					skip(1)
					local size = varint()
					local endTypes = cursor + size
					if size > 0 then
						local functionSize = size
						if types >= 2 then
							functionSize = varint()
							varint()
							varint()
						end
						if cursor + functionSize > endTypes then
							error("Invalid type metadata", 0)
						end
						local startTypes = cursor
						if
							functionSize == parameterCount + 2
							and bytes:byte(startTypes) == 5
							and bytes:byte(startTypes + 1) == parameterCount
						then
							local primitive = {
								[0] = "nil",
								[1] = "boolean",
								[2] = "number",
								[3] = "string",
								[4] = "table",
								[5] = "function",
								[6] = "thread",
								[9] = "buffer",
								[10] = "number",
							}
							for index = 1, parameterCount do
								local tag = bytes:byte(startTypes + 1 + index)
								local kind = primitive[tag % 128]
								if kind then
									argumentTypes[index] = kind .. (tag >= 128 and "?" or "")
								end
							end
						end
					end
					if cursor > endTypes then
						error("Invalid type metadata", 0)
					end
					skip(endTypes - cursor)
				end
				local count = varint(100000)
				total += count
				if total > 200000 then
					error("Instruction limit", 0)
				end
				local start = cursor
				skip(count * 4)
				local constants = {}
				for k = 0, varint(50000) - 1 do
					check()
					local tag = byte()
					if tag == 0 then
						constants[k] = { KnownType = "nil" }
					elseif tag == 1 then
						constants[k] = byte() ~= 0
					elseif tag == 2 then
						local n = readNumber and readNumber(cursor)
						constants[k] = {
							KnownType = "number",
							NumberValue = n and n == n and math.abs(n) <= 1000000 and n == math.floor(n) and n or nil,
						}
						skip(8)
					elseif tag == 3 then
						constants[k] = strings[varint(50000)]
					elseif tag == 4 then
						skip(4)
					elseif tag == 5 or tag == 8 then
						local shape = {}
						for _ = 1, varint(50000) do
							check()
							local key = varint(50000)
							local value = -1
							if tag == 8 then
								value = word(cursor)
								skip(4)
								if value >= 2147483648 then
									value -= 4294967296
								end
							end
							if #shape < 2048 then
								shape[#shape + 1] = { Key = key, Value = value }
							end
						end
						constants[k] = { Template = shape }
					elseif tag == 6 then
						constants[k] = { ClosureProto = varint(10000) + 1 }
					elseif tag == 7 then
						skip(16)
					elseif tag == 9 then
						constants[k] = { KnownType = "number" }
						skip(1)
						local terminated = false
						for _ = 1, 10 do
							if byte() < 128 then
								terminated = true
								break
							end
						end
						if not terminated then
							error("Invalid integer", 0)
						end
					elseif tag == 10 then
						varint(50000)
						local members = varint(50000) + varint(50000)
						if members > 50000 then
							error("Class member limit", 0)
						end
						for _ = 1, members do
							check()
							varint(50000)
						end
					elseif tag == 11 then
						skip(32)
					else
						error("Unsupported constant tag", 0)
					end
				end
				local children = {}
				for childIndex = 1, varint(10000) do
					check()
					children[childIndex] = varint(10000) + 1
				end
				do
					varint(2147483647)
					varint(50000)
					if byte() ~= 0 then
						local gap = byte()
						if gap > 31 then
							error("Invalid line gap", 0)
						end
						local intervals = count > 0 and math.floor((count - 1) / 2 ^ gap) + 1 or 0
						skip(count + intervals * 4)
					end
					if byte() ~= 0 then
						for _ = 1, varint(50000) do
							check()
							local name = strings[varint(50000)]
							local first = varint(100000)
							varint(100000)
							local register = byte()
							if register < parameterCount and first <= 1 and type(name) == "string" then
								argumentNames[register + 1] = name
							end
						end
						for _ = 1, varint(255) do
							check()
							varint(50000)
						end
					end
					if version >= 11 then
						for _ = 1, varint(100000) do
							check()
							local kind = byte()
							if kind ~= 0 and kind ~= 1 then
								error("Unsupported feedback kind", 0)
							end
							varint(100000)
						end
					end
				end
				if finish then
					if cursor > finish then
						error("Invalid prototype boundary", 0)
					end
					cursor = finish
				end
				protos[i] = {
					ArgumentTypes = argumentTypes,
					ArgumentNames = argumentNames,
					Start = start,
					Count = count,
					Constants = constants,
					Children = children,
					UpvalueCount = upvalueCount,
					ParameterCount = parameterCount,
					Vararg = vararg,
				}
			end
			local entry = varint(10000)
			if entry >= #protos then
				error("Invalid main prototype index", 0)
			end
			local trailerBytes = #bytes - cursor + 1
			local function valid(multiplier)
				for _, proto in ipairs(protos) do
					local pc = 0
					while pc < proto.Count do
						check()
						local op = (bytes:byte(proto.Start + pc * 4) * multiplier) % 256
						if op > 89 then
							return false
						end
						pc += auxiliary[op] and 2 or 1
					end
					if pc ~= proto.Count then
						return false
					end
				end
				return true
			end
			local plain, encoded = valid(1), valid(203)
			if plain == encoded then
				error(plain and "Ambiguous opcode encoding" or "Unsupported opcode encoding", 0)
			end
			return protos, plain and 1 or 203, trailerBytes, entry + 1
		end
		local ok, protos, multiplier, trailerBytes, entry = pcall(parse)
		if not ok then
			return false, tostring(protos)
		end
		local prepared, prepareError = pcall(function()
			for _, proto in ipairs(protos) do
				local targets = {}
				local pc = 0
				while pc < proto.Count do
					check()
					local w = word(proto.Start + pc * 4)
					local op = (w % 256 * multiplier) % 256
					local c, d = rshift(w, 24), rshift(w, 16)
					if
						(op >= 23 and op <= 32)
						or (op >= 56 and op <= 59)
						or op == 61
						or op == 76
						or (op >= 77 and op <= 80)
						or op == 88
					then
						local offset = d >= 32768 and d - 65536 or d
						targets[pc + offset + 1] = true
					elseif op == 67 then
						local offset = math.floor(w / 256)
						if offset >= 8388608 then
							offset -= 16777216
						end
						targets[pc + offset + 1] = true
					elseif op == 3 and c > 0 then
						targets[pc + c + 1] = true
					end
					pc += auxiliary[op] and 2 or 1
				end
				proto.Targets = targets
			end
		end)
		if not prepared then
			return false, tostring(prepareError)
		end
		local claims = {}
		local function publish(path, class, proto, pc, kind, member)
			if #path < 2 then
				return
			end
			claims[#claims + 1] = {
				Path = table.clone(path),
				Evidence = {
					Source = label,
					Kind = kind or "bytecode path reference",
					Class = class,
					Proto = proto,
					Instruction = pc,
					Member = member,
				},
			}
			if #claims > 10000 then
				error("Claim limit", 0)
			end
		end
		local function pathValue(path)
			return { Path = path }
		end
		local function child(base, key, proto, pc)
			if type(base) ~= "table" then
				return
			end
			if type(key) == "table" then
				key = key.NumberValue
			end
			if type(key) == "number" then
				if key ~= math.floor(key) or math.abs(key) > 1000000 or not (base.ModulePath or base.Fields) then
					return
				end
			elseif type(key) ~= "string" or #key == 0 or #key > 512 then
				return
			end
			if base.Fields then
				return base.Fields[key]
			end
			if base.Global == "game" and roots[key] then
				return pathValue({ key })
			end
			if base.ModulePath then
				if type(key) == "string" and #key > 128 then
					return
				end
				local members = table.clone(base.Members or {})
				if #members >= 16 then
					return
				end
				members[#members + 1] = key
				publish(
					base.ModulePath,
					"ModuleScript",
					proto,
					pc,
					"bytecode module field",
					{ Name = key, Path = members, Kind = "field", Type = "unknown" }
				)
				return { ModulePath = base.ModulePath, Member = key, Members = members }
			end
			if type(key) ~= "string" or not base.Path then
				return
			end
			if key == "Parent" then
				if #base.Path <= 1 then
					return
				end
				local path = table.clone(base.Path)
				table.remove(path)
				return pathValue(path)
			end
			if properties[key] or #base.Path >= 64 then
				return
			end
			local path = table.clone(base.Path)
			path[#path + 1] = key
			publish(path, nil, proto, pc)
			return pathValue(path)
		end
		local success, problem = pcall(function()
			local work, contexts = {}, {}
			for i in ipairs(protos) do
				work[#work + 1] = { Index = i, Upvalues = i == entry and (seeds or {}) or {} }
				contexts[tostring(i)] = true
			end
			local jobIndex = 1
			while jobIndex <= #work do
				if #work > 10000 then
					error("Capture context limit", 0)
				end
				local job = work[jobIndex]
				jobIndex += 1
				local protoIndex = job.Index
				local proto = protos[protoIndex]
				local regs, targets = {}, proto.Targets
				local capturedByReference = {}
				local function discard(first)
					for register, value in pairs(regs) do
						if
							register >= first
							or capturedByReference[register]
							or type(value) ~= "table"
							or not value.ModulePath
							or value.Members
						then
							regs[register] = nil
						end
					end
				end
				local function instruction(pc)
					local w = word(proto.Start + pc * 4)
					return (w % 256 * multiplier) % 256,
						extract(w, 8, 8),
						extract(w, 16, 8),
						rshift(w, 24),
						rshift(w, 16)
				end
				local pc = 0
				while pc < proto.Count do
					check()
					if targets[pc] then
						table.clear(regs)
					end
					local op, a, b, c, d = instruction(pc)
					local aux = auxiliary[op] and word(proto.Start + (pc + 1) * 4) or 0
					local constants = proto.Constants
					if op == 2 then
						regs[a] = { KnownType = "nil" }
					elseif op == 3 then
						regs[a] = b ~= 0 and true or false
					elseif op == 4 then
						regs[a] = d >= 32768 and d - 65536 or d
					elseif op == 53 or op == 54 then
						local value = { KnownType = "table", Fields = {}, FieldCount = 0 }
						local template = op == 54 and constants[d]
						if type(template) == "table" and template.Template then
							for _, entry in ipairs(template.Template) do
								local key = constants[entry.Key]
								if type(key) == "table" then
									key = key.NumberValue
								end
								if type(key) == "string" or type(key) == "number" then
									local field
									if entry.Value >= 0 then
										field = constants[entry.Value]
									end
									if field == nil then
										field = { KnownType = "unknown" }
									end
									value.Fields[key] = field
									value.FieldCount += 1
								end
							end
						end
						regs[a] = value
					elseif op == 5 then
						regs[a] = constants[d]
					elseif op == 66 then
						regs[a] = constants[aux]
					elseif op == 6 then
						regs[a] = regs[b]
					elseif op == 9 then
						regs[a] = job.Upvalues[b + 1]
					elseif op == 19 or op == 64 then
						local constant = op == 64 and constants[d]
						local childIndex = op == 19 and proto.Children[d + 1]
							or type(constant) == "table" and constant.ClosureProto
						local nested = childIndex and protos[childIndex]
						regs[a] = nil
						if nested then
							regs[a] = {
								KnownType = "function",
								ParameterCount = nested.ParameterCount,
								Vararg = nested.Vararg,
								ArgumentTypes = nested.ArgumentTypes,
								ArgumentNames = nested.ArgumentNames,
							}
							local captured, key, known = {}, { tostring(childIndex) }, false
							for index = 1, nested.UpvalueCount do
								if pc + index >= proto.Count then
									error("Truncated capture", 0)
								end
								local capture, kind, reg = instruction(pc + index)
								if capture ~= 70 then
									error("Invalid capture", 0)
								end
								if kind == 1 then
									capturedByReference[reg] = true
								end
								local value = kind == 0 and regs[reg] or kind == 2 and job.Upvalues[reg + 1] or nil
								if type(value) == "string" then
									captured[index] = value
									key[#key + 1] = index .. ":s" .. #value .. ":" .. value
									known = true
								elseif type(value) == "table" and (value.Path or value.Global or value.ModulePath) then
									captured[index] = value
									known = true
									local parts = { index .. ":" .. (value.Global or "p") }
									for _, name in ipairs(value.Path or value.ModulePath or {}) do
										parts[#parts + 1] = #name .. ":" .. name
									end
									if value.ModulePath then
										parts[#parts + 1] = "module"
										for _, name in ipairs(value.Members or {}) do
											local text = tostring(name)
											parts[#parts + 1] = type(name) .. ":" .. #text .. ":" .. text
										end
									end
									key[#key + 1] = table.concat(parts, ";")
								end
							end
							local identity = table.concat(key, "|")
							if known and not contexts[identity] then
								contexts[identity] = true
								work[#work + 1] = { Index = childIndex, Upvalues = captured }
							end
						end
					elseif op == 7 then
						local name = constants[aux]
						regs[a] = (name == "game" or name == "require") and { Global = name } or nil
					elseif op == 12 then
						local count = math.floor(aux / 1073741824)
						local indices = { math.floor(aux / 1048576) % 1024, math.floor(aux / 1024) % 1024, aux % 1024 }
						local name = constants[indices[1]]
						local value = (name == "game" or name == "require") and { Global = name } or nil
						for i = 2, count do
							value = child(value, constants[indices[i]], protoIndex, pc)
						end
						regs[a] = value
					elseif op == 15 or op == 83 then
						regs[a] = child(regs[b], constants[op == 83 and aux % 65536 or aux], protoIndex, pc)
					elseif op == 13 or op == 17 then
						regs[a] = child(regs[b], op == 17 and c + 1 or regs[c], protoIndex, pc)
					elseif op == 20 or op == 85 then
						local receiver = regs[b]
						regs[a] = { Method = constants[op == 85 and aux % 65536 or aux], Receiver = receiver }
						regs[a + 1] = receiver
					elseif op == 21 or op == 87 then
						local fn, arg = regs[a], regs[a + 2]
						local result, pure
						if type(fn) == "table" then
							if
								fn.Global == "require"
								and b == 2
								and type(regs[a + 1]) == "table"
								and regs[a + 1].Path
							then
								publish(regs[a + 1].Path, "ModuleScript", protoIndex, pc, "bytecode require target")
								result = { ModulePath = regs[a + 1].Path }
							elseif
								fn.ModulePath
								or fn.Method and type(fn.Receiver) == "table" and fn.Receiver.ModulePath
							then
								local method = fn.Method ~= nil
								local owner = method and fn.Receiver.ModulePath or fn.ModulePath
								local name = method and fn.Method or fn.Member or "__call"
								if b > 0 then
									local arguments = {}
									local count = math.min(32, math.max(0, b - (method and 2 or 1)))
									for index = 1, count do
										local value = regs[a + index + (method and 1 or 0)]
										local kind = type(value)
										arguments[index] = (kind == "string" or kind == "number" or kind == "boolean")
												and kind
											or type(value) == "table" and (value.KnownType or (value.Path and "Instance"))
											or "unknown"
									end
									publish(owner, "ModuleScript", protoIndex, pc, "bytecode module call", {
										Name = name,
										Root = not method and not fn.Member,
										Path = method and (function()
											local path = table.clone(fn.Receiver.Members or {})
											path[#path + 1] = name
											return path
										end)() or fn.Members or {},
										Method = method,
										Arguments = arguments,
										Count = count,
									})
								end
							elseif
								fn.Method == "GetService"
								and b == 3
								and type(fn.Receiver) == "table"
								and fn.Receiver.Global == "game"
								and roots[arg]
							then
								result = pathValue({ arg })
								pure = true
							elseif
								(fn.Method == "WaitForChild" and (b == 3 or b == 4))
								or (fn.Method == "FindFirstChild" and b == 3)
							then
								result = child(fn.Receiver, arg, protoIndex, pc)
								pure = true
							elseif
								fn.Method == "IsA"
								and b == 3
								and type(fn.Receiver) == "table"
								and fn.Receiver.Path
								and type(arg) == "string"
							then
								publish(fn.Receiver.Path, arg, protoIndex, pc, "bytecode conditional IsA constraint")
								pure = true
							end
						end
						if pure then
							for register = a, 254 do
								regs[register] = nil
							end
						else
							discard(a)
						end
						if c == 2 then
							regs[a] = result
						end
					elseif op == 49 then
						local parts = {}
						local valid = true
						for r = b, c do
							if type(regs[r]) ~= "string" then
								valid = false
								break
							end
							parts[#parts + 1] = regs[r]
						end
						local text = valid and table.concat(parts) or nil
						regs[a] = text and #text <= 512 and text or nil
					elseif op == 0 or op == 1 or op == 11 or op == 65 or op == 69 or op == 70 then
					elseif op == 55 then
						local receiver = regs[a]
						if c > 0 and type(receiver) == "table" and receiver.Fields then
							for index = 0, math.min(c - 2, 2047) do
								local key = aux + index
								if (receiver.FieldCount or 0) >= 2048 and receiver.Fields[key] == nil then
									break
								end
								if receiver.Fields[key] == nil then
									receiver.FieldCount = (receiver.FieldCount or 0) + 1
								end
								receiver.Fields[key] = regs[b + index] or { KnownType = "unknown" }
							end
						else
							discard(255)
						end
					elseif op == 16 or op == 84 or op == 14 or op == 18 then
						local receiver = regs[b]
						local key = op == 18 and c + 1
							or op == 14 and regs[c]
							or constants[op == 84 and aux % 65536 or aux]
						if type(key) == "table" then
							key = key.NumberValue
						end
						local validKey = type(key) == "string"
							or (type(key) == "number" and key == math.floor(key) and math.abs(key) <= 1000000)
						if type(receiver) == "table" and receiver.Fields and validKey then
							if receiver.Fields[key] ~= nil or (receiver.FieldCount or 0) < 2048 then
								if receiver.Fields[key] == nil then
									receiver.FieldCount = (receiver.FieldCount or 0) + 1
								end
								receiver.Fields[key] = regs[a] or { KnownType = "unknown" }
							end
						else
							if type(receiver) == "table" and receiver.ModulePath and validKey then
								local members = table.clone(receiver.Members or {})
								members[#members + 1] = key
								local seen = {}
								local remaining = 2048
								local function field(path, value)
									if #path > 16 or remaining <= 0 then
										return
									end
									remaining -= 1
									check()
									local kind = type(value)
									local inferred = (kind == "string" or kind == "number" or kind == "boolean")
											and kind
										or type(value) == "table" and value.KnownType
										or "unknown"
									if type(value) == "table" and value.KnownType == "function" then
										publish(
											receiver.ModulePath,
											"ModuleScript",
											protoIndex,
											pc,
											"bytecode module function write",
											{
												Name = path[#path],
												Path = path,
												Count = value.ParameterCount,
												Vararg = value.Vararg,
												DeclaredArguments = value.ArgumentTypes,
												DeclaredNames = value.ArgumentNames,
												Definition = true,
											}
										)
									else
										publish(
											receiver.ModulePath,
											"ModuleScript",
											protoIndex,
											pc,
											"bytecode module field write",
											{ Name = path[#path], Path = path, Kind = "field", Type = inferred }
										)
									end
									if type(value) == "table" and value.Fields and not seen[value] then
										seen[value] = true
										for name, nested in pairs(value.Fields) do
											local childPath = table.clone(path)
											childPath[#childPath + 1] = name
											field(childPath, nested)
										end
									end
								end
								field(members, regs[a])
							end
							discard(255)
						end
					elseif op == 10 then
						job.Upvalues[b + 1] = nil
						table.clear(regs)
					elseif op == 63 or op == 62 or op == 86 then
						table.clear(regs)
					elseif op == 8 or op == 14 or op == 16 or op == 18 or op == 55 or op == 84 then
						table.clear(regs)
					elseif
						(op >= 23 and op <= 32)
						or (op >= 56 and op <= 61)
						or op == 67
						or op == 76
						or (op >= 77 and op <= 80)
						or op == 88
					then
						table.clear(regs)
					elseif op == 68 or op == 73 or op == 74 or op == 75 or op == 89 then
					else
						regs[a] = nil
					end
					pc += auxiliary[op] and 2 or 1
				end
			end
		end)
		if not success then
			return false, tostring(problem)
		end
		if checkpoint and checkpoint() == false then
			return false, "Cancelled"
		end
		for index, claim in ipairs(claims) do
			if index % 32 == 0 and checkpoint and checkpoint() == false then
				return false, "Cancelled"
			end
			emit(claim.Path, claim.Evidence)
		end
		return true,
			{
				Claims = #claims,
				Prototypes = #protos,
				Encoding = multiplier == 1 and "plain" or "roblox",
				TrailerBytes = trailerBytes,
			}
	end
	local cache, order = {}, {}
	local first, last, total = 1, 0, 0
	local cacheLimit = 16 * 1024 * 1024
	function Paths.Analyze(bytes, label, emit, checkpoint, seeds)
		if seeds ~= nil then
			return analyze(bytes, label, emit, checkpoint, seeds)
		end
		if checkpoint and checkpoint() == false then
			return false, "Cancelled"
		end
		local record = type(bytes) == "string" and cache[bytes]
		local hit = record ~= nil
		if not record then
			local claims, cost = {}, type(bytes) == "string" and #bytes or 0
			local ok, info = analyze(bytes, "", function(path, evidence)
				claims[#claims + 1] = { Path = path, Evidence = evidence }
				cost += 160
				if evidence.Member then
					cost += 256 + #tostring(evidence.Member.Name) + 32 * (evidence.Member.Count or 0)
				end
				for _, name in ipairs(path) do
					cost += #name + 16
				end
			end, checkpoint)
			if not ok then
				return false, info
			end
			record = { Claims = claims, Info = info, Cost = cost }
			if cost <= cacheLimit then
				while first <= last and (total + cost > cacheLimit or last - first >= 255) do
					local key = order[first]
					order[first] = nil
					first += 1
					total -= cache[key].Cost
					cache[key] = nil
				end
				if first > 512 then
					local compact = {}
					for index = first, last do
						compact[#compact + 1] = order[index]
					end
					order, first, last = compact, 1, #compact
				end
				last += 1
				order[last] = bytes
				cache[bytes] = record
				total += cost
			end
		end
		for index, claim in ipairs(record.Claims) do
			if index % 32 == 0 and checkpoint and checkpoint() == false then
				return false, "Cancelled"
			end
			local evidence = table.clone(claim.Evidence)
			evidence.Source = label
			if evidence.Member then
				evidence.Member = table.clone(evidence.Member)
				if evidence.Member.Arguments then
					evidence.Member.Arguments = table.clone(evidence.Member.Arguments)
				end
				if evidence.Member.Path then
					evidence.Member.Path = table.clone(evidence.Member.Path)
				end
			end
			emit(table.clone(claim.Path), evidence)
		end
		local info = table.clone(record.Info)
		info.CacheHit = hit
		return true, info
	end
	return Paths
end
return { Main = Main }
