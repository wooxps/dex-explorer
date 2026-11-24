--!strict

local env, service

local function InitDeps(deps)
	env, service = deps.env, deps.service
end

local function Main()
	local Engine = {
		MaxEvents = 20000,
		MaxDuration = 600,
		MinSpeed = 0.25,
		MaxSpeed = 4,
	}

	local mouseTypes = {
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.MouseButton3,
	}
	local buttons = {}
	for index, inputType in ipairs(mouseTypes) do
		buttons[inputType] = index
	end

	local keyItems
	local function getKeys()
		if not keyItems then
			keyItems = {}
			for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
				if item ~= Enum.KeyCode.Unknown then
					keyItems[item.Name] = item
				end
			end
		end
		return keyItems
	end

	local function finite(value, low, high)
		return type(value) == "number" and value >= low and value <= high
	end
	local function isKey(event)
		return event.Kind == "KeyDown" or event.Kind == "KeyUp"
	end
	local function isButton(event)
		return event.Kind == "ButtonDown" or event.Kind == "ButtonUp"
	end
	local function validEvent(event, previous)
		if type(event) ~= "table" or not finite(event.Time, previous, Engine.MaxDuration) then
			return false
		end
		if isKey(event) then
			return type(event.Key) == "string" and getKeys()[event.Key] ~= nil
		elseif event.Kind == "RelativeMove" then
			return finite(event.DeltaX, -65536, 65536) and finite(event.DeltaY, -65536, 65536)
		end
		if not finite(event.X, 0, 1) or not finite(event.Y, 0, 1) then
			return false
		end
		if isButton(event) then
			return mouseTypes[event.Button] ~= nil
		elseif event.Kind == "Wheel" then
			return finite(event.Delta, -256, 256) and event.Delta ~= 0
		end
		return event.Kind == "Move"
	end

	function Engine.Validate(events)
		if type(events) ~= "table" or #events > Engine.MaxEvents then
			return false, "Invalid event list"
		end
		local count = #events
		for index in pairs(events) do
			if not finite(index, 1, count) or index % 1 ~= 0 then
				return false, "Invalid event list"
			end
		end
		local previous = 0
		for i = 1, count do
			local event = events[i]
			if not validEvent(event, previous) then
				return false, "Invalid event at row " .. i
			end
			previous = event.Time
		end
		return true
	end

	local virtualKeys = {
		Backspace = 0x08,
		Tab = 0x09,
		Clear = 0x0C,
		Return = 0x0D,
		KeypadEnter = 0x0D,
		Pause = 0x13,
		CapsLock = 0x14,
		Escape = 0x1B,
		Space = 0x20,
		PageUp = 0x21,
		PageDown = 0x22,
		End = 0x23,
		Home = 0x24,
		Left = 0x25,
		Up = 0x26,
		Right = 0x27,
		Down = 0x28,
		Print = 0x2C,
		Insert = 0x2D,
		Delete = 0x2E,
		LeftSuper = 0x5B,
		RightSuper = 0x5C,
		LeftMeta = 0x5B,
		RightMeta = 0x5C,
		Menu = 0x5D,
		KeypadMultiply = 0x6A,
		KeypadPlus = 0x6B,
		KeypadMinus = 0x6D,
		KeypadPeriod = 0x6E,
		KeypadDivide = 0x6F,
		NumLock = 0x90,
		ScrollLock = 0x91,
		LeftShift = 0xA0,
		RightShift = 0xA1,
		LeftControl = 0xA2,
		RightControl = 0xA3,
		LeftAlt = 0xA4,
		RightAlt = 0xA5,
		Semicolon = 0xBA,
		Equals = 0xBB,
		Comma = 0xBC,
		Minus = 0xBD,
		Period = 0xBE,
		Slash = 0xBF,
		Backquote = 0xC0,
		LeftBracket = 0xDB,
		BackSlash = 0xDC,
		RightBracket = 0xDD,
		Quote = 0xDE,
	}
	for letter = string.byte("A"), string.byte("Z") do
		virtualKeys[string.char(letter)] = letter
	end
	for i, name in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
		virtualKeys[name] = 0x2F + i
		virtualKeys["Keypad" .. (i - 1)] = 0x5F + i
	end
	for i = 1, 24 do
		virtualKeys["F" .. i] = 0x6F + i
	end

	local function tryCreate(create)
		local ok, result = pcall(create)
		return if ok then result else nil
	end

	local function openBackend(input, events)
		local inputFunctions = (env and env.MacroInput) or {}
		local virtual = tryCreate(function()
			return input:CreateVirtualInput()
		end)
		local manager = if not virtual or type(inputFunctions.mousescroll) ~= "function"
			then tryCreate(function()
				return Instance.new("VirtualInputManager")
			end)
			else nil
		local backend = {}
		local keyDown = inputFunctions.keypress
		local keyUp = inputFunctions.keyrelease
		local absolute = inputFunctions.mousemoveabs
		local relative = inputFunctions.mousemoverel
		local wheel = inputFunctions.mousescroll
		local mouseDown = { inputFunctions.mouse1press, inputFunctions.mouse2press, inputFunctions.mouse3press }
		local mouseUp = { inputFunctions.mouse1release, inputFunctions.mouse2release, inputFunctions.mouse3release }
		local function hasMouseFunctions(button)
			return type(mouseDown[button]) == "function" and type(mouseUp[button]) == "function"
		end
		local executorMouse = type(absolute) == "function" or type(relative) == "function"
		if events then
			local canPosition = executorMouse
			executorMouse = true
			for _, event in ipairs(events) do
				if isButton(event) and (not hasMouseFunctions(event.Button) or not canPosition) then
					executorMouse = false
				elseif event.Kind == "Move" and not canPosition then
					executorMouse = false
				elseif event.Kind == "RelativeMove" and type(relative) ~= "function" then
					executorMouse = false
				elseif event.Kind == "Wheel" and type(wheel) ~= "function" then
					executorMouse = false
				end
			end
		else
			executorMouse = executorMouse and hasMouseFunctions(1)
		end
		local mouseVirtual = not executorMouse and virtual
		local mouseManager = not executorMouse and not virtual and manager

		local hasExecutorKeys = type(keyDown) == "function" and type(keyUp) == "function"
		if hasExecutorKeys or virtual or manager then
			function backend.Key(key, down)
				local code = virtualKeys[key]
				if hasExecutorKeys and code then
					(if down then keyDown else keyUp)(code)
				elseif virtual then
					virtual:SendKey(down, getKeys()[key], false)
				elseif manager then
					manager:SendKeyEvent(down, getKeys()[key], false, game)
				end
			end
		end
		function backend.HasKey(key)
			return (hasExecutorKeys and virtualKeys[key] ~= nil) or virtual ~= nil or not not manager
		end

		if executorMouse and type(absolute) == "function" then
			backend.Move = absolute
		elseif executorMouse and type(relative) == "function" then
			function backend.Move(x, y)
				local current = input:GetMouseLocation()
				relative(x - current.X, y - current.Y)
			end
		elseif mouseVirtual then
			function backend.Move(x, y)
				virtual:SendMousePosition(Vector2.new(x, y))
			end
		elseif mouseManager then
			function backend.Move(x, y)
				manager:SendMouseMoveEvent(x, y, game)
			end
		end

		if executorMouse and type(relative) == "function" then
			backend.RelativeMove = relative
		elseif mouseVirtual then
			function backend.RelativeMove(x, y)
				local delta = Vector2.new(x, y)
				if input.MouseBehavior == Enum.MouseBehavior.Default then
					virtual:SendMousePosition(input:GetMouseLocation() + delta)
				else
					virtual:SendMouseDelta(delta)
				end
			end
		end

		if executorMouse and type(wheel) == "function" then
			function backend.Wheel(x, y, delta)
				if backend.Move and input.MouseBehavior == Enum.MouseBehavior.Default then
					backend.Move(x, y)
				end
				wheel(math.round(delta * 120))
			end
		elseif mouseVirtual then
			function backend.Wheel(x, y, delta)
				virtual:SendPointerAction(Vector2.new(x, y), { Wheel = delta })
			end
		elseif mouseManager then
			function backend.Wheel(x, y, delta)
				for _ = 1, math.max(1, math.round(math.abs(delta))) do
					manager:SendMouseWheelEvent(x, y, delta > 0, game)
				end
			end
		end

		function backend.HasButton(button)
			return not not ((executorMouse and backend.Move and hasMouseFunctions(button)) or mouseVirtual or mouseManager)
		end
		function backend.Button(button, down, x, y, reposition)
			if executorMouse then
				if reposition and input.MouseBehavior == Enum.MouseBehavior.Default then
					backend.Move(x, y)
				end
				(if down then mouseDown[button] else mouseUp[button])()
			else
				if input.MouseBehavior ~= Enum.MouseBehavior.Default then
					local current = input:GetMouseLocation()
					x, y = current.X, current.Y
				end
				if mouseVirtual then
					virtual:SendMouseButton(Vector2.new(x, y), mouseTypes[button], down, 0)
				else
					manager:SendMouseButtonEvent(x, y, button - 1, down, game, 0)
				end
			end
		end

		function backend.Close()
			if virtual then
				pcall(function()
					virtual:Destroy()
				end)
			end
			if manager then
				pcall(function()
					manager:Destroy()
				end)
			end
		end
		return backend
	end

	local function canSend(backend, events)
		for _, event in ipairs(events) do
			local supported
			if isKey(event) then
				supported = backend.HasKey(event.Key)
			elseif isButton(event) then
				supported = backend.HasButton(event.Button)
			else
				supported = backend[event.Kind] ~= nil
			end
			if not supported then
				return false, "This executor cannot replay " .. (event.Key or event.Kind)
			end
		end
		return true
	end

	function Engine.Create(config)
		config = config or {}
		local input = service.UserInputService
		local engine = { State = "Idle" }
		local connections = {}
		local recording, playback
		local capabilities
		local destroyed

		local function callback(fn, ...)
			if fn then
				local ok, reason = pcall(fn, ...)
				if not ok then
					warn("[Dex Explorer] Input Macros: " .. tostring(reason))
				end
			end
		end
		local function connect(signal, fn)
			connections[#connections + 1] = signal:Connect(fn)
		end
		local function state(value, reason, events)
			engine.State = value
			callback(config.OnState, value, reason, events)
		end
		local function viewport()
			local camera = service.Workspace.CurrentCamera
			return if camera then camera.ViewportSize else Vector2.new(0, 0)
		end
		local function eventPosition(event)
			local position = event.Position
			if not position then
				return input:GetMouseLocation()
			end
			local inset = service.GuiService:GetGuiInset()
			return Vector2.new(position.X + inset.X, position.Y + inset.Y)
		end
		local function normalizedPosition(_position)
			local size = viewport()
			if size.X <= 0 or size.Y <= 0 then
				return 0, 0
			end
			local position = _position or input:GetMouseLocation()
			return math.clamp(position.X / size.X, 0, 1), math.clamp(position.Y / size.Y, 0, 1)
		end
		local function pixels(event)
			local size = viewport()
			local x = math.clamp(math.round(event.X * size.X), 0, math.max(0, size.X - 1))
			local y = math.clamp(math.round(event.Y * size.Y), 0, math.max(0, size.Y - 1))
			return x, y
		end
		local function releasePlayback(run)
			local backend = run.Backend
			local success = true
			for key in pairs(run.Keys) do
				if not pcall(backend.Key, key, false) then
					success = false
				end
			end
			local mouse = next(run.Buttons) and tryCreate(function()
				return input:GetMouseLocation()
			end)
			for button, position in pairs(run.Buttons) do
				local point = mouse or position
				if not pcall(backend.Button, button, false, point.X, point.Y, false) then
					success = false
				end
			end
			table.clear(run.Keys)
			table.clear(run.Buttons)
			return success
		end

		function engine:Stop(reason)
			local previous = self.State
			if previous == "Idle" then
				return
			end
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
			reason = reason or "Stopped"
			local events
			if recording then
				local capture = recording
				recording = nil
				events = capture.Events
				local time = math.min(os.clock() - capture.Started, Engine.MaxDuration)
				for key in pairs(capture.Keys) do
					if #events >= Engine.MaxEvents then
						break
					end
					events[#events + 1] = { Time = time, Kind = "KeyUp", Key = key }
				end
				for button, event in pairs(capture.Buttons) do
					if #events >= Engine.MaxEvents then
						break
					end
					events[#events + 1] = {
						Time = time,
						Kind = "ButtonUp",
						Button = button,
						X = capture.X or event.X,
						Y = capture.Y or event.Y,
					}
				end
			end
			if playback then
				local run = playback
				playback = nil
				if not releasePlayback(run) then
					reason ..= ". Some inputs could not be released"
				end
				run.Backend.Close()
			end
			state("Idle", reason, events)
			return events
		end

		local function watchSession()
			connect(input.WindowFocusReleased, function()
				engine:Stop("Window lost focus")
			end)
		end
		local function isStop(event)
			return config.IsStopInput and config.IsStopInput(event)
		end
		local function append(capture, event)
			event.Time = math.min(os.clock() - capture.Started, Engine.MaxDuration)
			local events = capture.Events
			events[#events + 1] = event
			callback(config.OnEvent, event)
			if #events >= Engine.MaxEvents and recording == capture then
				engine:Stop("Recording limit reached")
			end
		end
		local function canRecord(event, processed, position)
			return not config.ShouldRecord or config.ShouldRecord(event, processed, position)
		end

		function engine:StartRecording()
			if destroyed or self.State ~= "Idle" then
				return false, "Input Macros is busy"
			end
			local capture = {
				Started = os.clock(),
				Events = {},
				Keys = {},
				Buttons = {},
				ObservedButtons = {},
			}
			local initialButtons = {}
			local initialPosition = input:GetMouseLocation()
			for _, event in ipairs(input:GetMouseButtonsPressed()) do
				initialButtons[#initialButtons + 1] = { Event = event, Allowed = canRecord(event, false, initialPosition) }
			end
			recording = capture
			engine.State = "Recording"
			watchSession()
			local function endButton(button, position)
				capture.ObservedButtons[button] = nil
				if capture.Buttons[button] then
					capture.Buttons[button] = nil
					local x, y = normalizedPosition(position)
					capture.X, capture.Y = x, y
					append(capture, { Kind = "ButtonUp", Button = button, X = x, Y = y })
				end
			end
			local function beginInput(event, processed, allowed, _position)
				if recording ~= capture then
					return
				end
				if isStop(event) then
					self:Stop()
					return
				end
				local button = buttons[event.UserInputType]
				local position = _position or eventPosition(event)
				if button then
					local previous = capture.ObservedButtons[button]
					if previous == event then
						return
					elseif previous then
						endButton(button, position)
						if recording ~= capture then
							return
						end
					end
					capture.ObservedButtons[button] = event
				end
				if allowed == false or (allowed == nil and not canRecord(event, processed, position)) then
					return
				end
				if event.UserInputType == Enum.UserInputType.Keyboard then
					local key = event.KeyCode.Name
					if getKeys()[key] and not capture.Keys[key] then
						capture.Keys[key] = true
						append(capture, { Kind = "KeyDown", Key = key })
					end
				elseif button and not capture.Buttons[button] then
					local x, y = normalizedPosition(position)
					capture.X, capture.Y = x, y
					local entry = { Kind = "ButtonDown", Button = button, X = x, Y = y }
					capture.Buttons[button] = entry
					append(capture, entry)
				end
			end
			connect(input.InputBegan, beginInput)
			connect(input.InputEnded, function(event)
				if recording ~= capture then
					return
				end
				local button = buttons[event.UserInputType]
				if event.UserInputType == Enum.UserInputType.Keyboard then
					local key = event.KeyCode.Name
					if capture.Keys[key] then
						capture.Keys[key] = nil
						append(capture, { Kind = "KeyUp", Key = key })
					end
				elseif button then
					local observed = capture.ObservedButtons[button]
					if observed and (
						observed == event
						or observed.UserInputState == Enum.UserInputState.End
						or observed.UserInputState == Enum.UserInputState.Cancel
					) then
						endButton(button, eventPosition(event))
					end
				end
			end)
			connect(input.InputChanged, function(event, processed)
				if recording ~= capture then
					return
				end
				local kind = event.UserInputType
				if kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.MouseWheel then
					return
				end
				local dragging = kind == Enum.UserInputType.MouseMovement and next(capture.Buttons) ~= nil
				local pointer = if kind == Enum.UserInputType.MouseWheel then input:GetMouseLocation() else nil
				if not dragging and not canRecord(event, processed, pointer) then
					return
				end
				if kind == Enum.UserInputType.MouseMovement and input.MouseBehavior ~= Enum.MouseBehavior.Default then
					local x, y = event.Delta.X, event.Delta.Y
					if x ~= 0 or y ~= 0 then
						append(capture, { Kind = "RelativeMove", DeltaX = x, DeltaY = y })
					end
				else
					local x, y = normalizedPosition(if kind == Enum.UserInputType.MouseMovement then eventPosition(event) else nil)
					if kind == Enum.UserInputType.MouseWheel then
						if event.Position.Z ~= 0 then
							append(capture, { Kind = "Wheel", X = x, Y = y, Delta = event.Position.Z })
						end
					elseif x ~= capture.X or y ~= capture.Y then
						capture.X, capture.Y = x, y
						append(capture, { Kind = "Move", X = x, Y = y })
					end
				end
			end)
			connect(service.RunService.Heartbeat, function()
				if recording ~= capture then
					return
				end
				if os.clock() - capture.Started >= Engine.MaxDuration then
					self:Stop("Recording limit reached")
					return
				end
				local position = input:GetMouseLocation()
				for _, event in ipairs(input:GetMouseButtonsPressed()) do
					local button = buttons[event.UserInputType]
					local state = event.UserInputState
					if button and state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel then
						beginInput(event, false, nil, position)
					end
				end
				for button = 1, #mouseTypes do
					if recording ~= capture then
						break
					end
					local observed = capture.ObservedButtons[button]
					if observed then
						local state = observed.UserInputState
						if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
							endButton(button)
						end
					end
				end
			end)
			for _, initial in ipairs(initialButtons) do
				if recording ~= capture then
					break
				end
				beginInput(initial.Event, false, initial.Allowed, initialPosition)
			end
			if recording == capture then
				state("Recording")
			end
			return true
		end

		function engine:GetCapabilities()
			if not capabilities then
				local backend = openBackend(input)
				capabilities = {
					Keyboard = backend.Key ~= nil,
					Mouse = backend.HasButton(1),
					Movement = backend.Move ~= nil,
					RelativeMovement = backend.RelativeMove ~= nil,
					Wheel = backend.Wheel ~= nil,
				}
				capabilities.Playback = capabilities.Keyboard
					or capabilities.Mouse
					or capabilities.Movement
					or capabilities.RelativeMovement
					or capabilities.Wheel
				backend.Close()
			end
			return table.clone(capabilities)
		end

		function engine:CanPlay(events)
			local valid, reason = Engine.Validate(events)
			if not valid then
				return false, reason
			elseif #events == 0 then
				return false, "This macro has no inputs"
			end
			local backend = openBackend(input, events)
			local supported, issue = canSend(backend, events)
			backend.Close()
			return supported, issue
		end

		local function dispatch(run, event)
			local backend = run.Backend
			if isKey(event) then
				local down = event.Kind == "KeyDown"
				if down then
					run.Keys[event.Key] = true
				elseif not run.Keys[event.Key] then
					return
				end
				backend.Key(event.Key, down)
				if not down then
					run.Keys[event.Key] = nil
				end
			elseif isButton(event) then
				local x, y = pixels(event)
				local down = event.Kind == "ButtonDown"
				if down then
					run.Buttons[event.Button] = Vector2.new(x, y)
				elseif not run.Buttons[event.Button] then
					return
				end
				backend.Button(event.Button, down, x, y, down or x ~= run.X or y ~= run.Y)
				run.X, run.Y = x, y
				if not down then
					run.Buttons[event.Button] = nil
				end
			elseif event.Kind == "RelativeMove" then
				backend.RelativeMove(event.DeltaX, event.DeltaY)
				run.X, run.Y = nil, nil
			else
				local x, y = pixels(event)
				backend[event.Kind](x, y, event.Delta)
				if event.Kind == "Move" then
					run.X, run.Y = x, y
				else
					run.X, run.Y = nil, nil
				end
			end
		end

		function engine:Play(events, options)
			if destroyed or self.State ~= "Idle" then
				return false, "Input Macros is busy"
			end
			local valid, reason = Engine.Validate(events)
			if not valid then
				return false, reason
			elseif #events == 0 then
				return false, "This macro has no inputs"
			end
			options = options or {}
			local speed = options.Speed or 1
			if not finite(speed, Engine.MinSpeed, Engine.MaxSpeed) then
				return false, "Invalid playback speed"
			end
			local backend = openBackend(input, events)
			local supported, problem = canSend(backend, events)
			if not supported then
				backend.Close()
				return false, problem
			end

			local eventsCopy = table.create(#events)
			for index, event in ipairs(events) do
				eventsCopy[index] = table.clone(event)
			end
			local loop = options.Loop == true
			local run = { Backend = backend, Keys = {}, Buttons = {}, MouseTransitions = {} }
			local started, index = os.clock(), 1
			local busy = false
			playback = run
			watchSession()
			connect(input.InputBegan, function(event)
				if isStop(event) then
					self:Stop()
				end
			end)
			connect(service.RunService.Heartbeat, function()
				if busy or playback ~= run then
					return
				end
				busy = true
				local now = os.clock()
				local elapsed = (now - started) * speed
				local deadline = now + 0.002
				local lastIndex = index
				local transitions = run.MouseTransitions
				table.clear(transitions)
				while index <= #eventsCopy and eventsCopy[index].Time <= elapsed do
					local event = eventsCopy[index]
					if isButton(event) then
						local down = event.Kind == "ButtonDown"
						if transitions[event.Button] ~= nil and transitions[event.Button] ~= down then
							break
						end
						transitions[event.Button] = down
					end
					local ok, problem = pcall(dispatch, run, event)
					if playback ~= run then
						return
					elseif not ok then
						self:Stop("Playback failed: " .. tostring(problem))
						return
					end
					index += 1
					if index - lastIndex >= 128 or os.clock() >= deadline then
						break
					end
				end
				if index ~= lastIndex then
					callback(config.OnProgress, index - 1, #eventsCopy)
				end
				if playback == run and index > #eventsCopy then
					local pressedThisFrame = false
					for button in pairs(run.Buttons) do
						pressedThisFrame = pressedThisFrame or transitions[button] == true
					end
					if pressedThisFrame then
						busy = false
						return
					elseif not loop then
						self:Stop("Finished")
					elseif not releasePlayback(run) then
						self:Stop("Could not release inputs between loops")
					else
						started, index = os.clock(), 1
					end
				end
				busy = false
			end)
			state("Playing")
			return true
		end

		function engine:Destroy()
			destroyed = true
			self:Stop()
		end
		return engine
	end

	return Engine
end

return { InitDeps = InitDeps, Main = Main }
