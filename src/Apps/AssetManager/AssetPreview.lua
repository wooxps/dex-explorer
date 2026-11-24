--!strict

local Main, Apps, service

------------------------------ Initialization ------------------------------

local function InitDeps(d)
	Main, Apps, service = d.Main, d.Apps, d.service
end
------------------------------ Module ------------------------------

local function CreateModule()
	local Preview = {}
	function Preview.Create(viewport, image, report)
		local self = { Generation = 0, Looped = true, Volume = 0.5, Speed = 1, Rig = "R15" }
		local scene, sound, track, animation, camera, playback
		local yaw, pitch, distance = 0, 0.12, 12
		function self:Stop()
			self.Generation += 1
			self.Loading = false
			if playback then
				playback:Destroy()
				playback = nil
			end
			if track then
				track:Stop()
				track:Destroy()
				track = nil
			end
			if animation then
				animation:Destroy()
				animation = nil
			end
			if sound then
				sound:Stop()
				sound:Destroy()
				sound = nil
			end
			if scene then
				scene:Destroy()
				scene = nil
			end
			if camera then
				camera:Destroy()
				camera = nil
			end
			image.Visible = false
			image.Image = ""
			viewport.Visible = false
		end
		function self:Camera()
			if not camera or not scene then
				return
			end
			local center = scene.Model:GetBoundingBox()
			camera.CFrame = CFrame.lookAt(
				center.Position
					+ Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
						* distance,
				center.Position
			)
		end
		function self:Orbit(dx, dy)
			yaw -= dx * 0.01
			pitch = math.clamp(pitch + dy * 0.01, -1.4, 1.4)
			self:Camera()
		end
		function self:Zoom(delta)
			distance = math.clamp(distance * math.exp(-delta * 0.15), 0.2, 10000)
			self:Camera()
		end
		function self:SetLoop(value)
			self.Looped = value
			if sound then
				sound.Looped = value
			end
			if track then
				track.Looped = value
			end
		end
		function self:SetVolume(value)
			self.Volume = math.clamp(value, 0, 1)
			if sound then
				sound.Volume = self.Volume
			end
		end
		function self:SetSpeed(value)
			self.Speed = math.clamp(value, 0.1, 3)
			if track and track.IsPlaying and track.Speed ~= 0 then
				track:AdjustSpeed(self.Speed)
			end
			if sound then
				sound.PlaybackSpeed = self.Speed
			end
		end
		function self:Seek(seconds)
			local media = sound or track
			if media then
				media.TimePosition = math.clamp(seconds, 0, sound and sound.TimeLength or track.Length)
			end
		end
		function self:Time()
			local media = sound or track
			return media and media.TimePosition or 0, sound and sound.TimeLength or track and track.Length or 0
		end
		function self:ResetPlayback()
			if sound then
				sound:Pause()
				sound.TimePosition = 0
			end
			if track then
				track:AdjustSpeed(0)
				track.TimePosition = 0
			end
		end
		function self:Toggle()
			if sound then
				if sound.IsPlaying then
					sound:Pause()
				else
					sound:Resume()
				end
			elseif track then
				if not track.IsPlaying then
					track:Play(0)
					track:AdjustSpeed(self.Speed)
				elseif track.Speed == 0 then
					track:AdjustSpeed(self.Speed)
				else
					track:AdjustSpeed(0)
				end
			end
		end
		function self:Show(record)
			self:Stop()
			self.Loading = true
			local generation = self.Generation
			task.delay(12, function()
				if generation == self.Generation and self.Loading then
					report("Preview is taking longer than expected. Try another rig.")
				end
			end)
			report("Loading...")
			if record.Kind == "Images" then
				image.Image = record.URI
				image.Visible = true
				task.spawn(function()
					local failed = false
					local ok, problem = pcall(function()
						service.ContentProvider:PreloadAsync({ record.URI }, function(_, state)
							if state == Enum.AssetFetchStatus.Failure then
								failed = true
							end
						end)
					end)
					if failed then
						ok = false
						problem = "Image could not load"
					end
					if generation == self.Generation and Main.Alive ~= false then
						self.Loading = false
						report(ok and "Ready" or "Image unavailable: " .. tostring(problem))
					end
				end)
				return
			end
			if record.Kind == "Sounds" then
				sound = Instance.new("Sound")
				sound.SoundId = record.URI
				sound.Volume = self.Volume
				sound.Looped = self.Looped
				sound.PlaybackSpeed = self.Speed
				sound.Parent = service.SoundService
				sound:Play()
				task.delay(8, function()
					if generation == self.Generation and sound and not sound.IsLoaded then
						report("Sound has not loaded. It may be restricted.")
					end
				end)
				self.Loading = false
				report("Ready")
				return
			end
			task.spawn(function()
				local source, temporary
				local ok, problem = pcall(function()
					if record.Kind == "Meshes" then
						for _, use in ipairs(record.Uses) do
							if Apps.AssetCatalog.IsCurrent(record, use) then
								if use.Object:IsA("MeshPart") then
									source = use.Object
									break
								end
								if
									use.Object:IsA("SpecialMesh")
									and use.Object.Parent
									and use.Object.Parent:IsA("BasePart")
								then
									source = use.Object.Parent
									break
								end
							end
						end
						if not source then
							source = service.AssetService:CreateMeshPartAsync(Content.fromUri(record.URI))
							temporary = source
						end
					else
						if self.Rig == "Selection" then
							local selected = Apps.Explorer.Selection.List[1]
							assert(selected and selected.Obj:IsA("Model"), "Select a rig Model in Explorer first.")
							source = selected.Obj
						else
							source = Apps.AssetRig.Create(self.Rig)
							temporary = source
						end
					end
					if generation ~= self.Generation then
						return
					end
					local built = Apps.PreviewScene.Build(source)
					if generation ~= self.Generation then
						built:Destroy()
						return
					end
					scene = built
					scene:SetGrid(false)
					scene.World.Parent = viewport
					viewport.Visible = true
					camera = Instance.new("Camera")
					camera.FieldOfView = 40
					camera.Parent = viewport
					viewport.CurrentCamera = camera
					yaw, pitch, distance = 0.35, 0.15, math.max(1, scene.Radius / math.tan(math.rad(20)) * 1.25)
					self:Camera()
					if record.Kind == "Animations" then
						local humanoid = scene.Model:FindFirstChildWhichIsA("Humanoid", true)
						local controller = humanoid or scene.Model:FindFirstChildWhichIsA("AnimationController", true)
						assert(controller, "The selected Model has no Humanoid or AnimationController.")
						local rig = controller:FindFirstAncestorWhichIsA("Model")
						local root = humanoid and humanoid.RootPart
							or rig and rig.PrimaryPart
							or scene.Model:FindFirstChild("HumanoidRootPart", true)
						root = root or scene.Model:FindFirstChildWhichIsA("BasePart", true)
						for _, part in ipairs(scene.Model:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Anchored = part == root
							end
						end
						local animator = controller:FindFirstChildOfClass("Animator")
							or Instance.new("Animator", controller)
						animation = Instance.new("Animation")
						animation.AnimationId = record.URI
						local loaded = animator:LoadAnimation(animation)
						if generation ~= self.Generation then
							loaded:Destroy()
							return
						end
						track = loaded
						track.Looped = self.Looped
						track:Play(0)
						track:AdjustSpeed(self.Speed)
						playback = Apps.AssetPlayback.Start(scene.Model, animator, track, report)
						task.delay(8, function()
							if generation == self.Generation and track and track.Length == 0 then
								report("Animation has not loaded. Check permissions and rig type.")
							end
						end)
					end
				end)
				if temporary then
					temporary:Destroy()
				end
				if generation == self.Generation and Main.Alive ~= false then
					self.Loading = false
					report(ok and "Ready" or "Preview failed: " .. tostring(problem))
				end
			end)
		end
		return self
	end
	return Preview
end
return { InitDeps = InitDeps, Main = CreateModule }
