--!strict

local Main, env

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, env = d.Main, d.env
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Config = {}
	function Config.Build(raw, selection)
		local result = {}
		for _, field in ipairs(Main.LoadModule("SaveOptions")) do
			if field.Key == "FilePath" then
				continue
			end
			local value = raw[field.Key]
			if value == nil or value == "" then
				continue
			end
			assert(type(value) ~= "string" or #value <= 65536, field.Key .. ": value is too long")
			if field.Kind == "boolean" then
				assert(type(value) == "boolean", field.Key .. ": choose On, Off or Default")
			elseif field.Kind == "number" then
				value = tonumber(value)
				assert(value and value == value and math.abs(value) < math.huge, field.Key .. ": enter a finite number")
				if field.Key == "CompressionLevel" then
					assert(
						value >= -7 and value <= 22 and value % 1 == 0,
						"CompressionLevel: use an integer from -7 to 22"
					)
				end
				if field.Key == "DecompileTimeout" or field.Key == "BytecodeTimeout" then
					assert(value == -1 or value >= 0, field.Key .. ": use -1 or a nonnegative number")
				end
				if field.Key == "SaveCacheInterval" then
					assert(value >= 1 and value % 1 == 0, "SaveCacheInterval: use a positive integer")
				end
			elseif field.Kind == "expression" then
				assert(type(env.loadstring) == "function", field.Key .. ": Luau expressions require loadstring")
				local chunk, problem = env.loadstring("return " .. value, "@DexExplorer/SaveOptions/" .. field.Key)
				assert(chunk, field.Key .. ": " .. tostring(problem))
				setfenv(
					chunk,
					setmetatable({ selection = selection, game = game, workspace = workspace }, { __index = getfenv() })
				)
				local ok, evaluated = pcall(chunk)
				assert(ok, field.Key .. ": " .. tostring(evaluated))
				value = evaluated
				assert(value ~= nil, field.Key .. ": expression returned nil; clear the field to use Default")
				local kind = typeof(value)
				local key = field.Key
				local accepted
				if key == "Object" then
					accepted = kind == "Instance" or value == false
				elseif key == "CompressionMode" then
					accepted = kind == "string" or kind == "boolean"
				elseif key == "Callback" then
					accepted = kind == "function" or value == false
				elseif key == "__DEBUG_MODE" then
					accepted = kind == "function" or kind == "boolean"
				elseif key == "Anonymous" then
					accepted = kind == "table" or kind == "boolean"
				elseif key == "SourceCache" then
					accepted = kind == "table" or value == false
				else
					accepted = kind == "table"
				end
				assert(accepted, field.Key .. ": expected " .. field.Type)
			end
			result[field.Key] = value
		end
		return result
	end
	return Config
end
return { InitDeps = InitDeps, Main = CreateModule }
