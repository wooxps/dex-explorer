--!strict

local Main, Apps, env, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, env, service = d.Main, d.Apps, d.env, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Workspace = {}
	function Workspace.Attach(viewer, remember)
		local path = "dex-explorer/editor-workspace-" .. tostring(game.PlaceId) .. ".json"
		local pending, stopped, previous, saving = false, false, nil, false
		local function save()
			if stopped or not env.writefile then
				return
			end
			saving = true
			remember()
			saving = false
			local data = { Version = 1, Documents = {}, Active = 1 }
			local bytes = 0
			for index, doc in ipairs(viewer.Documents) do
				bytes += #doc.text
				if bytes > 16 * 1024 * 1024 or index > 100 then
					return
				end
				local item = {
					Title = doc.title,
					Text = doc.text,
					X = doc.x,
					Y = doc.y,
					VX = doc.vx,
					VY = doc.vy,
					Dirty = doc.dirty,
				}
				data.Documents[index] = item
				if viewer.ActiveDocument == doc then
					data.Active = index
				end
			end
			local ok, json = pcall(service.HttpService.JSONEncode, service.HttpService, data)
			if ok and #json <= 20 * 1024 * 1024 and json ~= previous then
				if pcall(env.writefile, path, json) then
					previous = json
				end
			end
		end
		function viewer.ScheduleWorkspaceSave()
			if stopped or pending or saving then
				return
			end
			pending = true
			task.delay(2, function()
				pending = false
				if not stopped then
					save()
				end
			end)
		end
		if env.readfile then
			local ok, json = pcall(env.readfile, path)
			if ok and type(json) == "string" and #json <= 20 * 1024 * 1024 then
				local good, data = pcall(service.HttpService.JSONDecode, service.HttpService, json)
				if
					good
					and type(data) == "table"
					and data.Version == 1
					and type(data.Documents) == "table"
					and #data.Documents <= 100
				then
					local valid = true
					local bytes = 0
					for _, item in ipairs(data.Documents) do
						if type(item) ~= "table" or type(item.Title) ~= "string" or type(item.Text) ~= "string" then
							valid = false
							break
						end
						bytes += #item.Text
					end
					if valid and bytes <= 16 * 1024 * 1024 and #data.Documents > 0 then
						table.clear(viewer.Documents)
						local restored = {}
						local function number(value)
							return type(value) == "number"
									and value == value
									and value >= 0
									and value < 100000000
									and value
								or 0
						end
						for _, item in ipairs(data.Documents) do
							local doc = viewer.OpenDocument({}, item.Title, item.Text, nil, {
								x = number(item.X),
								y = number(item.Y),
								vx = number(item.VX),
								vy = number(item.VY),
								dirty = item.Dirty == true,
								deferSelection = true,
							})
							restored[#restored + 1] = doc
						end
						viewer.SelectDocument(restored[math.clamp(math.floor(number(data.Active)), 1, #restored)])
					end
				end
			end
		end
		Main.AddCleanup(function()
			save()
			stopped = true
		end)
	end
	return Workspace
end
return { InitDeps = InitDeps, Main = CreateModule }
