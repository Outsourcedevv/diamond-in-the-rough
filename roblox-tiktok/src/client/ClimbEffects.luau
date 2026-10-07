--!strict
-- Diamond Climb's gift animations: a TikTok gift picks the climber up and
-- flies them up the tower (gifts that would break the mountain) or smashes
-- them down it (gifts that add stone), with a show for each gift tier. From
-- 100 coins they take over the camera, and each tier is wilder than the last.
--
-- Sent up:
--   1  BOUNCE PAD          (1+ coins)       a gold pad springs them up in a flip
--   2  SPRING LAUNCH       (10+ coins)      a giant spring coils and boings them up, spinning
--   3  ROCKET BOOST        (100+ coins)     a rocket ignites under them and corkscrews up the
--                                           tower in fire and smoke, then bursts into fireworks
--   4  DIAMOND CANNON      (500+ coins)     a gold cannon charges, fires them round the tower on
--                                           a rainbow trail through portals, and lands in a
--                                           shower of crystal
--   5  STARLIGHT ASCENT    (1,000+ coins)   night falls, a beam of starlight lifts them, stars
--                                           orbit them, every platform lights up as they fly
--                                           past, and they arrive in a supernova
--   6  GALACTIC ASCENSION  (10,000+ coins)  the sky goes black, a galaxy spins under them,
--                                           planets orbit, a big bang hurls them up at warp
--                                           speed through giant portals, fireworks all round
--                                           the tower and a galaxy nova at the top
-- Sent down:
--   1  BANANA SLIP         a banana peel, a backflip and a dizzy landing
--   2  SPIKE BOUNCE        spikes shoot out of the platform and bounce them off
--   3  ANVIL SMASH         an anvil falls on them, CLANG, and drives them down the tower
--   4  METEOR STRIKE       the sky burns, a meteor hits and blasts them off in flames
--   5  THUNDER HAMMER      a storm, lightning strikes, a giant hammer slams them down with
--                          lightning chasing them all the way
--   6  BLACK HOLE PLUNGE   a black hole opens, swallows the light and the climber, and spits
--                          them out far below in a nova
--
-- The climber's character is held (anchored on this computer) and carried
-- along a spiral round the tower to their new platform, then let go there.
-- Built like GiftEffects: Roblox's own particle textures, neon parts, trails
-- and lights, nothing physical, capped per tier, everything gone afterwards.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRush")
local GiftTier = require(Shared:WaitForChild("GiftTier"))
local ClimbPath = require(Shared:WaitForChild("ClimbPath"))
local Format = require(Shared:WaitForChild("Format"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local ClimbEffects = {}

local TEXTURES = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	ember = "rbxasset://textures/particles/fire_sparks_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
}
ClimbEffects.TEXTURES = TEXTURES
ClimbEffects.UP_TITLES = ClimbPath.UP_TITLES
ClimbEffects.DOWN_TITLES = ClimbPath.DOWN_TITLES
-- Per tier: parts, lights and particles one show may create (checked by the tests).
ClimbEffects.PART_LIMITS = { 40, 60, 130, 170, 210, 260 }
ClimbEffects.LIGHT_LIMITS = { 2, 3, 4, 5, 6, 7 }
ClimbEffects.PARTICLE_BUDGETS = { 300, 450, 1400, 1800, 2200, 2800 }
-- Each show's own sounds: { seconds in, cue } (see Sounds).
ClimbEffects.UP_SOUNDS = {
	{ { 0.22, "boing" } },
	{ { 0.3, "boing" }, { 0.45, "whoosh" } },
	{ { 0, "launch" }, { 0.6, "whoosh" } },
	{ { 0, "rumble" }, { 0.8, "launch" } },
	{ { 0, "chime" }, { 0.5, "deepWhoosh" } },
	{ { 0, "rumble" }, { 0.6, "deepWhoosh" }, { 1.2, "launch" } },
}
ClimbEffects.DOWN_SOUNDS = {
	{ { 0.3, "slip" } },
	{ { 0.15, "zap" }, { 0.35, "falling" } },
	{ { 0.1, "falling" }, { 0.75, "clang" } },
	{ { 0, "deepWhoosh" }, { 0.8, "falling" } },
	{ { 0, "rumble" }, { 0.9, "falling" } },
	{ { 0, "deepWhoosh" }, { 0.7, "deepWhoosh" }, { 1.4, "falling" } },
}
-- From this tier up the show takes over the camera.
ClimbEffects.CINEMATIC_TIER = 3

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 206, 92)
local ORANGE = Color3.fromRGB(255, 132, 48)
local RED = Color3.fromRGB(255, 64, 72)
local CYAN = Color3.fromRGB(110, 235, 255)
local BLUE = Color3.fromRGB(80, 150, 255)
local VIOLET = Color3.fromRGB(168, 96, 255)
local PINK = Color3.fromRGB(255, 110, 200)
local GREEN = Color3.fromRGB(110, 240, 150)
local YELLOW = Color3.fromRGB(255, 232, 80)
local IRON = Color3.fromRGB(58, 60, 68)
local SMOKE = Color3.fromRGB(96, 90, 86)
-- Banner colours: gold and sky for up, red and violet for down.
local UP_COLOURS = { GOLD, Color3.fromRGB(255, 180, 90), ORANGE, CYAN, Color3.fromRGB(200, 220, 255), PINK }
local DOWN_COLOURS = { YELLOW, RED, Color3.fromRGB(200, 205, 220), ORANGE, CYAN, VIOLET }
local RAINBOW = { RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, VIOLET, PINK }

local random = Random.new()
local label: TextLabel? = nil
local subLabel: TextLabel? = nil
local bannerScale: UIScale? = nil
local bannerSerial = 0
local current: { folder: Folder, finish: () -> () }? = nil
-- True while a show is stopped because the climber left the climb: the server
-- is moving them elsewhere, so the ride lets go of them where they are.
local leaving = false
local shownIndex: number? = nil

local function sequence(...: Color3): ColorSequence
	local colours = { ... }
	if #colours == 1 then return ColorSequence.new(colours[1]) end
	local keys = {}
	for i, colour in colours do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colours - 1), colour))
	end
	return ColorSequence.new(keys)
end

local function curve(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then return NumberSequence.new(values[1]) end
	local keys = {}
	for i, value in values do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#values - 1), value))
	end
	return NumberSequence.new(keys)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end
local function easeIn(t: number): number
	return t * t * t
end
local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end
local function easeOutQuart(t: number): number
	return 1 - (1 - t) ^ 4
end
ClimbEffects.ease = { smooth = smooth, easeIn = easeIn, easeOut = easeOut }

-- Camera shake, added after the show's camera moves.
local shake = 0
local shaking = false
local shakeTime = 0
local function addShake(degrees: number)
	shake = math.max(shake, degrees)
	if shaking then return end
	shaking = true
	RunService:BindToRenderStep("DiamondClimbShake", Enum.RenderPriority.Camera.Value + 4, function(dt: number)
		local camera = workspace.CurrentCamera
		if shake < 0.01 or camera == nil then
			shake = 0
			shaking = false
			RunService:UnbindFromRenderStep("DiamondClimbShake")
			return
		end
		shakeTime += dt
		local t = shakeTime * 19
		local a = math.rad(shake) * 1.5
		CameraShake.apply(camera, CFrame.Angles(math.noise(t, 0.3) * a, math.noise(t, 7.1) * a, math.noise(t, 13.7) * a * 0.5))
		shake *= math.exp(-dt * 3)
	end)
end
ClimbEffects.shaking = function(): boolean return shaking end

-- The banner: the show's name, big, and who sent what, under it.
function ClimbEffects.start(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClimbEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = parent
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.27)
	holder.Size = UDim2.new(0.9, 0, 0, 110)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = holder
	bannerScale = scale
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 70)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextStrokeTransparency = 0.2
	title.TextTransparency = 1
	title.TextStrokeColor3 = BLACK
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = 64
	limit.Parent = title
	title.Parent = holder
	label = title
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromOffset(0, 72)
	sub.Size = UDim2.new(1, 0, 0, 30)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextStrokeTransparency = 0.3
	sub.TextTransparency = 1
	sub.TextColor3 = WHITE
	local subLimit = Instance.new("UITextSizeConstraint")
	subLimit.MinTextSize = 12
	subLimit.MaxTextSize = 26
	subLimit.Parent = sub
	sub.Parent = holder
	subLabel = sub
end

local function showBanner(title: string, sub: string, colour: Color3, tier: number, seconds: number)
	local text, small, scale = label, subLabel, bannerScale
	if text == nil or small == nil or scale == nil then return end
	bannerSerial += 1
	local serial = bannerSerial
	text.Text = title
	text.TextColor3 = colour
	text.TextTransparency = 0
	small.Text = sub
	small.TextTransparency = 0
	-- Bigger gifts slam in harder.
	scale.Scale = 1 + tier * 0.35
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(seconds, function()
		if serial ~= bannerSerial then return end
		TweenService:Create(text, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(small, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end)
end

-- The platform number the climber is passing during a ride, for the HUD; nil
-- when nothing is playing.
function ClimbEffects.shownIndex(): number?
	return shownIndex
end

function ClimbEffects.playing(): boolean
	return current ~= nil
end

-- Ends the show playing now at once (the climber is let go on their new platform).
-- Ends the show now. `inPlace` (the climber left the climb) lets go of them
-- where they are instead of putting them on the ride's platform.
function ClimbEffects.stop(inPlace: boolean?)
	local show = current
	if show then
		leaving = inPlace == true
		show.finish()
		leaving = false
	end
end

export type Particles = {
	texture: string,
	count: number,
	colour: ColorSequence,
	size: NumberSequence,
	transparency: NumberSequence?,
	lifetime: { number },
	speed: { number },
	spread: number?,
	drag: number?,
	acceleration: Vector3?,
	glow: number?,
	spin: number?,
	flat: boolean?,
}

-- Plays a climb gift: data = { up, from, to, coins, name, gift, platforms }.
-- `root` is the climber's HumanoidRootPart when it is this player riding.
-- `pace` above 1 plays it faster (gifts are queuing up). `onDone` runs when
-- the climber is let go. Returns how long it takes, in seconds.
function ClimbEffects.play(data: any, root: BasePart?, pace: number?, onDone: (() -> ())?): number
	ClimbEffects.stop()
	local speed = math.max(1, pace or 1)
	local coins = math.max(1, tonumber(data.coins) or 1)
	local tier = GiftTier.forCoins(coins)
	local up = data.up == true
	local from = math.clamp(math.floor(tonumber(data.from) or 0), 0, ClimbPath.TOP)
	local to = math.clamp(math.floor(tonumber(data.to) or from), 0, ClimbPath.TOP)
	local total = ClimbPath.GIFT_SECONDS[tier]
	local seconds = total / speed
	local colour = (if up then UP_COLOURS else DOWN_COLOURS)[tier]
	local title = (if up then ClimbPath.UP_TITLES else ClimbPath.DOWN_TITLES)[tier]
	local moved = math.abs(to - from)
	showBanner(title, string.format("%s sent %s (%s)  ·  %s %s PLATFORM%s", tostring(data.name or "Someone"), tostring(data.gift or "a gift"),
		Format.commas(coins), if up then "UP" else "DOWN", Format.commas(moved), if moved == 1 then "" else "S"), colour, tier, math.max(1.6, seconds * 0.8))

	local folder = Instance.new("Folder")
	folder.Name = "ClimbGiftShow"
	folder.Parent = workspace
	-- The landing's sparks and rings outlast the ride a little.
	Debris:AddItem(folder, seconds + 3)
	local made, lights, emitted = 0, 0, 0
	local finished = false
	local released = false
	local function alive(): boolean
		return folder.Parent ~= nil and not finished
	end
	-- Script seconds to real seconds.
	local function S(t: number): number
		return t / speed
	end
	local function after(delay: number, callback: () -> ())
		task.delay(S(delay), function()
			if alive() then callback() end
		end)
	end
	-- The climber hears their own ride, wherever the camera is.
	local loudness = 1 + (tier - 1) * 0.15
	local function noise(name: string)
		if alive() then Sounds.play(name, nil, loudness) end
	end
	-- Each show's own sounds, on top of its bangs and sparkles.
	for _, cue in (if up then ClimbEffects.UP_SOUNDS else ClimbEffects.DOWN_SOUNDS)[tier] do
		after(cue[1], function() noise(cue[2]) end)
	end
	local function part(shape: Enum.PartType, size: Vector3, frame: CFrame, tint: Color3, material: Enum.Material?): Part?
		if not alive() or made >= ClimbEffects.PART_LIMITS[tier] then return nil end
		made += 1
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = frame
		p.Color = tint
		p.Material = material or Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	local fovTween: Tween? = nil
	local function animate(p: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		local tween = TweenService:Create(p, TweenInfo.new(S(duration), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
		if goal.FieldOfView ~= nil then fovTween = tween end
		tween:Play()
	end
	local function fade(p: Instance, duration: number, goal: { [string]: any })
		animate(p, duration, goal)
		Debris:AddItem(p, S(duration) + 0.05)
	end
	local connections: { [any]: boolean } = {}
	local function motion(duration: number, update: (number) -> (), finish: (() -> ())?)
		local elapsed = 0
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function(dt: number)
			elapsed += dt
			local t = math.clamp(elapsed / S(duration), 0, 1)
			if alive() then update(t) end
			if t >= 1 or not alive() then
				if connection then
					connections[connection] = nil
					connection:Disconnect()
					connection = nil
				end
				if alive() and finish then finish() end
			end
		end)
		connections[connection] = true
	end
	local function light(holder: Instance, tint: Color3, range: number, brightness: number, duration: number)
		if lights >= ClimbEffects.LIGHT_LIMITS[tier] then return end
		lights += 1
		local glow = Instance.new("PointLight")
		glow.Color = tint
		glow.Range = range
		glow.Brightness = brightness
		glow.Shadows = false
		glow.Parent = holder
		animate(glow, duration, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	local anchor = part(Enum.PartType.Block, Vector3.one * 0.2, CFrame.identity, WHITE) :: Part
	anchor.Transparency = 1
	local function point(at: Vector3, duration: number): Attachment
		local spot = Instance.new("Attachment")
		spot.Position = at
		spot.Parent = anchor
		Debris:AddItem(spot, duration)
		return spot
	end
	local function burst(at: Vector3, spec: Particles)
		if not alive() then return end
		local budget = ClimbEffects.PARTICLE_BUDGETS[tier]
		local count = math.min(spec.count, budget - emitted)
		if count <= 0 then return end
		emitted += count
		local particles = Instance.new("ParticleEmitter")
		particles.Texture = spec.texture
		particles.Color = spec.colour
		particles.Size = spec.size
		particles.Transparency = spec.transparency or curve(0, 1)
		particles.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
		particles.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
		local spread = spec.spread or 180
		particles.SpreadAngle = Vector2.new(spread, spread)
		particles.Drag = spec.drag or 0
		particles.Acceleration = spec.acceleration or Vector3.zero
		particles.LightEmission = spec.glow or 1
		particles.LightInfluence = if (spec.glow or 1) > 0 then 0 else 1
		particles.Rotation = NumberRange.new(0, 360)
		local spin = spec.spin or 0
		particles.RotSpeed = NumberRange.new(-spin, spin)
		particles.EmissionDirection = Enum.NormalId.Top
		if spec.flat then particles.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
		particles.Enabled = false
		particles.Parent = point(at, spec.lifetime[2] + 0.2)
		particles:Emit(count)
	end
	-- The colour grade over the whole screen: up to `peak` and back.
	local function grade(peak: { [string]: any }, rise: number, hold: number, fall: number)
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "ClimbGrade"
		effect.Parent = Lighting
		animate(effect, rise, peak)
		after(rise + hold, function()
			animate(effect, fall, { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end)
		Debris:AddItem(effect, S(rise + hold + fall) + 0.1)
		-- Cleared with the show if it ends early.
		task.delay(seconds + 0.5, function() if effect.Parent then effect:Destroy() end end)
	end

	-- Effects ---------------------------------------------------------------------------
	local function sparkles(at: Vector3, tint: Color3, count: number, speedRange: { number }, size: number?)
		noise("sparkle")
		burst(at, { texture = TEXTURES.spark, count = count, colour = sequence(WHITE, tint), size = curve(size or 1.2, (size or 1.2) * 0.4, 0),
			lifetime = { 0.5, 1.2 }, speed = speedRange, drag = 3, spin = 200 })
	end
	local function shockwave(at: Vector3, radius: number, tint: Color3, duration: number)
		noise(if radius >= 18 then "bigBoom" elseif radius >= 7 then "boom" else "thud")
		burst(at, { texture = TEXTURES.ring, count = 1, colour = sequence(WHITE, tint),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, radius * 1.5), NumberSequenceKeypoint.new(1, radius * 2) }),
			transparency = curve(0, 0.2, 1), lifetime = { duration, duration }, speed = { 0.01, 0.01 }, spread = 0, flat = true })
	end
	local function fireball(at: Vector3, size: number, count: number)
		noise("boom")
		burst(at, { texture = TEXTURES.fire, count = count, colour = sequence(YELLOW, ORANGE, RED), size = curve(size * 0.6, size, size * 0.3),
			lifetime = { 0.4, 0.9 }, speed = { size * 1.5, size * 4 }, drag = 4, spin = 90 })
		burst(at, { texture = TEXTURES.smoke, count = math.ceil(count / 2), colour = sequence(SMOKE, Color3.fromRGB(60, 56, 54)), size = curve(size * 0.8, size * 1.8),
			transparency = curve(0.3, 1), lifetime = { 1, 2 }, speed = { size, size * 2.5 }, drag = 2, glow = 0, acceleration = Vector3.new(0, 4, 0) })
	end
	local function firework(at: Vector3, tint: Color3, count: number)
		noise("pop")
		burst(at, { texture = TEXTURES.spark, count = count, colour = sequence(WHITE, tint, tint), size = curve(1.6, 1, 0),
			lifetime = { 0.8, 1.6 }, speed = { 18, 34 }, drag = 2.5, acceleration = Vector3.new(0, -10, 0), spin = 300 })
		burst(at, { texture = TEXTURES.glow, count = 2, colour = sequence(tint), size = curve(6, 14, 0), lifetime = { 0.4, 0.5 }, speed = { 0, 0.1 } })
	end
	local function nova(at: Vector3, tint: Color3, radius: number, duration: number)
		noise("bigBoom")
		local ball = part(Enum.PartType.Ball, Vector3.one * 2, CFrame.new(at), WHITE)
		if ball then
			ball.Transparency = 0.05
			animate(ball, duration * 0.3, { Color = tint })
			fade(ball, duration, { Size = Vector3.one * radius * 2, Transparency = 1 })
			light(ball, tint, math.min(60, radius * 3), 8, duration)
		end
	end
	local function flash(at: Vector3, tint: Color3, size: number)
		local glow = part(Enum.PartType.Ball, Vector3.one * size * 0.3, CFrame.new(at), tint)
		if glow then
			glow.Transparency = 0.1
			fade(glow, 0.35, { Size = Vector3.one * size, Transparency = 1 })
		end
	end
	-- A ring of light round platform `index` (the platforms flash as riders pass).
	local function flashPlatform(index: number, tint: Color3)
		local top = ClimbPath.top(index)
		local size = ClimbPath.size(index) + 1.5
		local ring = part(Enum.PartType.Cylinder, Vector3.new(0.4, size, size), CFrame.new(top) * CFrame.Angles(0, 0, math.pi / 2), tint)
		if ring then
			ring.Transparency = 0.15
			fade(ring, 0.7, { Size = Vector3.new(0.1, size * 2.2, size * 2.2), Transparency = 1 })
		end
	end
	-- A jagged bolt of lightning from `a` to `b`.
	local function bolt(a: Vector3, b: Vector3, tint: Color3, width: number)
		noise("zap")
		local steps = 6
		local last = a
		for i = 1, steps do
			local t = i / steps
			local target = a + (b - a) * t
			if i < steps then
				target += Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.4, 0.4), random:NextNumber(-1, 1)) * (b - a).Magnitude * 0.07
			end
			local length = (target - last).Magnitude
			if length > 0.05 then
				local segment = part(Enum.PartType.Block, Vector3.new(width, width, length), CFrame.lookAt((last + target) / 2, target), WHITE)
				if segment then
					animate(segment, 0.1, { Color = tint })
					fade(segment, 0.35, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
				end
			end
			last = target
		end
		sparkles(b, tint, 16, { 10, 24 })
	end

	-- The ride ------------------------------------------------------------------------------
	local O = ClimbPath.ORIGIN
	local startFrame = ClimbPath.standFrame(from)
	local endFrame = ClimbPath.standFrame(to)
	local A, B = startFrame.Position, endFrame.Position
	local function reach(p: Vector3): number
		return Vector3.new(p.X - O.X, 0, p.Z - O.Z).Magnitude
	end
	local angleA, angleB = ClimbPath.angle(from), ClimbPath.angle(to)
	local reachA, reachB = reach(A), reach(B)
	-- A point on the spiral from the start to the new platform: `u` from 0 to 1,
	-- `bulge` studs further out from the tower mid-way, `lift` studs higher.
	local function spiral(u: number, bulge: number, lift: number): Vector3
		local angle = lerp(angleA, angleB, u)
		local r = lerp(reachA, reachB, u) + bulge * math.sin(math.pi * u)
		return Vector3.new(O.X + math.cos(angle) * r, lerp(A.Y, B.Y, u) + lift, O.Z + math.sin(angle) * r)
	end
	local riderPos = A
	local riderLook = startFrame.LookVector
	local riding = root ~= nil and root.Parent ~= nil
	if riding and root then
		root.Anchored = true
	end
	shownIndex = from
	local function place(at: Vector3, spinX: number, spinY: number, spinZ: number)
		local step = Vector3.new(at.X - riderPos.X, 0, at.Z - riderPos.Z)
		if step.Magnitude > 0.05 then riderLook = step.Unit end
		riderPos = at
		if riding and not released and root and root.Parent then
			root.CFrame = CFrame.lookAt(at, at + riderLook) * CFrame.Angles(spinX, spinY, spinZ)
		end
	end
	-- Rides the spiral over `length` seconds from `start`, eased; `lift(u)` is the
	-- extra height along the way, `flips`/`spins`/`rolls` whole turns.
	local function ride(start: number, length: number, spec: { [string]: any })
		after(start, function()
			local ease = spec.ease or smooth
			local bulge = spec.bulge or 0
			local lift = spec.lift or function(_u: number): number return 0 end
			local flips, spins, rolls = spec.flips or 0, spec.spins or 0, spec.rolls or 0
			motion(length, function(t: number)
				local u = ease(t)
				place(spiral(u, bulge, lift(u)), u * flips * 2 * math.pi, u * spins * 2 * math.pi, u * rolls * 2 * math.pi)
				if not released then shownIndex = lerp(from, to, u) end
			end)
		end)
	end
	-- Holds the rider at the start, offset by `offset(t)` (a hover or a wobble).
	local function hover(start: number, length: number, offset: (number) -> Vector3, spins: number?)
		after(start, function()
			motion(length, function(t: number)
				place(A + offset(t), 0, t * (spins or 0) * 2 * math.pi, 0)
			end)
		end)
	end
	-- An invisible tracer that follows the rider, carrying trails.
	local tracer = part(Enum.PartType.Ball, Vector3.one * 0.3, CFrame.new(A), WHITE)
	if tracer then
		tracer.Transparency = 1
		motion(total, function()
			tracer.CFrame = CFrame.new(riderPos)
		end)
	end
	local function trail(colours: ColorSequence, width: number, life: number)
		if tracer == nil then return end
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, width / 2, 0)
		a0.Parent = tracer
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -width / 2, 0)
		a1.Parent = tracer
		local streak = Instance.new("Trail")
		streak.Attachment0 = a0
		streak.Attachment1 = a1
		streak.Color = colours
		streak.Lifetime = life
		streak.LightEmission = 1
		streak.FaceCamera = true
		streak.Transparency = curve(0, 1)
		streak.WidthScale = curve(1, 0.1)
		streak.Parent = tracer
	end
	-- Something every `every` seconds while the rider moves from `start` for `length`.
	local function along(start: number, length: number, every: number, callback: (number) -> ())
		local steps = math.max(1, math.floor(length / every))
		for i = 0, steps - 1 do
			after(start + i * every, function() callback(i / steps) end)
		end
	end
	-- The platforms between here and there flash as the rider goes by.
	local function flashPassed(start: number, length: number, tint: Color3, flashes: number)
		if moved < 2 then return end
		local count = math.min(flashes, moved)
		for i = 1, count do
			local u = i / (count + 1)
			after(start + length * u, function()
				flashPlatform(math.floor(lerp(from, to, u) + 0.5), tint)
			end)
		end
	end

	-- The camera: from 100 coins the show films the rider from outside the tower.
	local camera = workspace.CurrentCamera
	local filming = tier >= ClimbEffects.CINEMATIC_TIER and riding and camera ~= nil
	local savedType = if camera then camera.CameraType else nil
	local savedFov = if camera then camera.FieldOfView else 70
	if filming and camera then
		local distance = 26 + tier * 5
		local height = 6 + tier * 1.5
		local camPos = camera.CFrame.Position
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep("DiamondClimbCamera", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
			local around = Vector3.new(riderPos.X - O.X, 0, riderPos.Z - O.Z)
			local out = if around.Magnitude > 0.1 then around.Unit else Vector3.new(1, 0, 0)
			local want = riderPos + out * distance + Vector3.new(0, height, 0)
			camPos += (want - camPos) * math.min(1, dt * 5)
			camera.CFrame = CFrame.lookAt(camPos, riderPos)
		end)
	end
	local function punch(fov: number, rise: number, hold: number, fall: number)
		if not filming or camera == nil then return end
		animate(camera, rise, { FieldOfView = fov })
		after(rise + hold, function() animate(camera, fall, { FieldOfView = savedFov }) end)
	end

	-- At the end of the ride the climber is let go on their new platform and
	-- gets their camera back, while the landing's effects fade.
	local function release()
		if released then return end
		released = true
		if current and current.folder == folder then current = nil end
		shownIndex = nil
		if filming then RunService:UnbindFromRenderStep("DiamondClimbCamera") end
		if camera and filming then
			-- A zoom still tweening would undo the reset.
			if fovTween then fovTween:Cancel() end
			camera.CameraType = savedType or Enum.CameraType.Custom
			camera.FieldOfView = savedFov
		end
		if riding and root and root.Parent then
			if not leaving then root.CFrame = endFrame end
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = false
		end
		if onDone then onDone() end
	end
	-- Cut short (the next gift is here, or the climber left): everything goes now.
	local function abort()
		release()
		if finished then return end
		finished = true
		for connection in connections do connection:Disconnect() end
		table.clear(connections)
		folder:Destroy()
		for _, child in Lighting:GetChildren() do
			if child.Name == "ClimbGrade" then child:Destroy() end
		end
	end
	current = { folder = folder, finish = abort }
	task.delay(seconds, release)

	-- The shows ------------------------------------------------------------------------------
	local feet = A - Vector3.new(0, 3, 0)
	local landing = B - Vector3.new(0, 3, 0)
	local function arrive(at: number, tint: Color3, size: number)
		after(at, function()
			shockwave(landing + Vector3.new(0, 0.3, 0), size, tint, 0.8)
			sparkles(landing + Vector3.new(0, 1, 0), tint, 14 + size * 2, { 8, 18 + size })
			flashPlatform(to, tint)
		end)
	end

	if up and tier == 1 then
		-- BOUNCE PAD: a gold pad squashes and springs them up in a flip.
		local pad = part(Enum.PartType.Cylinder, Vector3.new(0.5, 4, 4), CFrame.new(feet + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD)
		if pad then
			animate(pad, 0.2, { Size = Vector3.new(0.2, 5, 5) })
			after(0.22, function() animate(pad, 0.15, { Size = Vector3.new(1, 4, 4) }, Enum.EasingStyle.Back) end)
			after(0.6, function() fade(pad, 0.4, { Transparency = 1 }) end)
			light(pad, GOLD, 12, 3, 1)
		end
		after(0.22, function() sparkles(feet, GOLD, 24, { 6, 14 }) end)
		ride(0.25, 0.95, { ease = smooth, bulge = 2, lift = function(u) return math.sin(math.pi * u) * 6 end, flips = 1 })
		arrive(1.2, GOLD, 4)
	elseif up and tier == 2 then
		-- SPRING LAUNCH: a big spring coils under them, then boings them up spinning.
		local coils: { Part } = {}
		for i = 1, 6 do
			local coil = part(Enum.PartType.Cylinder, Vector3.new(0.35, 4.5, 4.5), CFrame.new(feet + Vector3.new(0, i * 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				if i % 2 == 0 then WHITE else Color3.fromRGB(255, 170, 90))
			if coil then
				coil.Transparency = 1
				animate(coil, 0.15, { Transparency = 0.1 })
				table.insert(coils, coil)
			end
		end
		hover(0, 0.45, function(t) return Vector3.new(0, -t * 1.2, 0) end)
		for i, coil in coils do
			animate(coil, 0.4, { CFrame = CFrame.new(feet + Vector3.new(0, i * 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2) })
		end
		after(0.45, function()
			for i, coil in coils do
				animate(coil, 0.18, { CFrame = CFrame.new(feet + Vector3.new(0, i * 1.6, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, Enum.EasingStyle.Back)
				after(0.5, function() fade(coil, 0.4, { Transparency = 1 }) end)
			end
			sparkles(feet + Vector3.new(0, 2, 0), Color3.fromRGB(255, 170, 90), 40, { 10, 22 })
			shockwave(feet + Vector3.new(0, 0.3, 0), 7, GOLD, 0.6)
			if tracer then light(tracer, GOLD, 16, 3, 1.4) end
			addShake(0.5)
		end)
		trail(sequence(GOLD, PINK, CYAN), 1.6, 0.5)
		ride(0.45, 1.3, { ease = smooth, bulge = 5, lift = function(u) return math.sin(math.pi * u) * 12 end, spins = 2, flips = 1 })
		along(0.5, 1.2, 0.12, function() sparkles(riderPos, PINK, 6, { 2, 6 }, 0.8) end)
		after(1.75, function() firework(landing + Vector3.new(0, 4, 0), PINK, 30) end)
		arrive(1.75, GOLD, 7)
	elseif up and tier == 3 then
		-- ROCKET BOOST: a rocket ignites under them and corkscrews up the tower.
		-- The rocket's pieces and where each sits under the climber.
		local pieces = {
			{ Enum.PartType.Cylinder, Vector3.new(4.5, 2.2, 2.2), CFrame.new(0, -4.6, 0) * CFrame.Angles(0, 0, math.pi / 2), WHITE },
			{ Enum.PartType.Ball, Vector3.one * 2.2, CFrame.new(0, -2.4, 0), RED },
		}
		for k = 0, 2 do
			local angle = k * math.pi * 2 / 3
			table.insert(pieces, { Enum.PartType.Block, Vector3.new(0.3, 1.6, 1.4), CFrame.new(math.cos(angle) * 1.4, -6.4, math.sin(angle) * 1.4) * CFrame.Angles(0, -angle, 0), RED })
		end
		local rocket: { Part } = {}
		local offsets: { CFrame } = {}
		for _, piece in pieces do
			local p = part(piece[1], piece[2], CFrame.new(A) * piece[3], piece[4], Enum.Material.SmoothPlastic)
			if p then
				table.insert(rocket, p)
				table.insert(offsets, piece[3])
			end
		end
		-- The rocket rides along under the climber.
		motion(2.9, function()
			for i, p in rocket do p.CFrame = CFrame.new(riderPos) * offsets[i] end
		end)
		after(0.2, function()
			fireball(feet - Vector3.new(0, 4, 0), 2.5, 30)
			shockwave(feet + Vector3.new(0, 0.3, 0), 10, ORANGE, 0.8)
			flash(feet, ORANGE, 12)
			addShake(1.2)
			grade({ Brightness = 0.08, Contrast = 0.15, TintColor = Color3.fromRGB(255, 225, 200) }, 0.2, 2.2, 0.8)
			if tracer then light(tracer, ORANGE, 24, 5, 3) end
		end)
		hover(0.2, 0.45, function(t) return Vector3.new(random:NextNumber(-0.15, 0.15), t * 1.5, random:NextNumber(-0.15, 0.15)) end)
		trail(sequence(YELLOW, ORANGE, RED, SMOKE), 2.4, 0.9)
		ride(0.65, 2.15, { ease = function(t) return smooth(easeIn(t) * 0.35 + t * 0.65) end, bulge = 14, lift = function(u) return math.sin(math.pi * u) * 10 end, rolls = 3 })
		punch(92, 0.4, 1.6, 0.8)
		along(0.2, 2.6, 0.06, function()
			burst(riderPos - Vector3.new(0, 6.5, 0), { texture = TEXTURES.fire, count = 6, colour = sequence(YELLOW, ORANGE, RED), size = curve(1.6, 2.4, 0.4),
				lifetime = { 0.25, 0.5 }, speed = { 8, 16 }, spread = 18, drag = 2, acceleration = Vector3.new(0, -30, 0) })
			burst(riderPos - Vector3.new(0, 7, 0), { texture = TEXTURES.smoke, count = 3, colour = sequence(Color3.fromRGB(200, 196, 190), SMOKE), size = curve(2, 5),
				transparency = curve(0.4, 1), lifetime = { 0.8, 1.5 }, speed = { 1, 4 }, glow = 0 })
		end)
		along(0.9, 1.8, 0.45, function() addShake(0.8) end)
		flashPassed(0.65, 2.15, ORANGE, 12)
		after(2.8, function()
			-- The rocket bursts into fireworks.
			for _, p in rocket do
				local fling = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.3, 1), random:NextNumber(-1, 1)).Unit * 14
				fade(p, 0.6, { CFrame = p.CFrame + fling, Transparency = 1 })
			end
			fireball(B + Vector3.new(0, 1, 0), 3, 26)
			for k = 1, 3 do
				local angle = k * math.pi * 2 / 3
				firework(B + Vector3.new(math.cos(angle) * 8, 8 + k * 2, math.sin(angle) * 8), RAINBOW[k * 2], 40)
			end
			flash(B, WHITE, 16)
			addShake(1.4)
		end)
		arrive(2.85, ORANGE, 10)
	elseif up and tier == 4 then
		-- DIAMOND CANNON: a gold cannon charges up and fires them round the tower.
		local out = Vector3.new(A.X - O.X, 0, A.Z - O.Z).Unit
		local base = feet + out * 1.5
		local aim = (Vector3.new(0, 1, 0) + riderLook * 0.6).Unit
		local mouth = base + aim * 6.5
		local barrel = part(Enum.PartType.Cylinder, Vector3.new(9, 3.6, 3.6), CFrame.lookAt(base + aim * 2, base + aim * 3) * CFrame.Angles(0, math.pi / 2, 0), GOLD, Enum.Material.Foil)
		local ring1 = part(Enum.PartType.Cylinder, Vector3.new(0.8, 4.4, 4.4), CFrame.lookAt(mouth, mouth + aim) * CFrame.Angles(0, math.pi / 2, 0), CYAN)
		local wheelL = part(Enum.PartType.Cylinder, Vector3.new(0.8, 4, 4), CFrame.lookAt(base, base + riderLook) * CFrame.new(-2.4, 0, 0), IRON, Enum.Material.Metal)
		local wheelR = part(Enum.PartType.Cylinder, Vector3.new(0.8, 4, 4), CFrame.lookAt(base, base + riderLook) * CFrame.new(2.4, 0, 0), IRON, Enum.Material.Metal)
		local gem = part(Enum.PartType.Block, Vector3.one * 2.4, CFrame.new(base - aim * 2.5) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), CYAN, Enum.Material.Glass)
		local cannon: { Part } = {}
		for _, p in { barrel, ring1, wheelL, wheelR, gem } do
			if p then
				local size = p.Size
				p.Size = size * 0.05
				animate(p, 0.35, { Size = size }, Enum.EasingStyle.Back)
				table.insert(cannon, p)
			end
		end
		sparkles(base, CYAN, 30, { 6, 14 })
		-- Pulled into the barrel's mouth.
		hover(0.3, 0.5, function(t) return (mouth - A) * smooth(t) end, 1)
		-- Charging: energy rushes in from all round.
		after(0.8, function()
			if ring1 then light(ring1, CYAN, 22, 1, 0.1) end
			for k = 1, 10 do
				local angle = k * math.pi * 2 / 10
				local start = mouth + Vector3.new(math.cos(angle) * 14, random:NextNumber(-4, 6), math.sin(angle) * 14)
				local orb = part(Enum.PartType.Ball, Vector3.one * 0.9, CFrame.new(start), RAINBOW[(k - 1) % #RAINBOW + 1])
				if orb then
					after(k * 0.05, function() fade(orb, 0.6, { CFrame = CFrame.new(mouth), Size = Vector3.one * 0.2 }) end)
				end
			end
		end)
		along(0.8, 0.8, 0.2, function(t) addShake(0.3 + t); sparkles(mouth, CYAN, 8, { 1, 4 }) end)
		after(1.6, function()
			-- FIRE.
			flash(mouth, WHITE, 26)
			shockwave(mouth, 14, CYAN, 0.9)
			shockwave(feet + Vector3.new(0, 0.3, 0), 18, GOLD, 1.1)
			fireball(mouth, 3, 24)
			for k = 1, 14 do
				local dir = (aim + Vector3.new(random:NextNumber(-0.8, 0.8), random:NextNumber(-0.3, 0.8), random:NextNumber(-0.8, 0.8))).Unit
				local shard = part(Enum.PartType.Block, Vector3.new(0.6, 0.6, 1.6), CFrame.lookAt(mouth, mouth + dir), RAINBOW[(k - 1) % #RAINBOW + 1], Enum.Material.Glass)
				if shard then fade(shard, 0.8, { CFrame = CFrame.lookAt(mouth + dir * 22, mouth + dir * 23), Transparency = 1 }) end
			end
			addShake(2.2)
			grade({ Brightness = 0.25, Contrast = 0.2, Saturation = 0.3 }, 0.08, 0.3, 0.9)
			for _, p in cannon do
				after(0.8, function() fade(p, 0.6, { Transparency = 1, Size = p.Size * 0.3 }) end)
			end
		end)
		trail(sequence(RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, VIOLET), 2.6, 1.1)
		ride(1.6, 2.4, { ease = easeOutQuart, bulge = 24, lift = function(u) return math.sin(math.pi * u) * 20 end, spins = 3, flips = 2 })
		punch(100, 0.12, 1.6, 1)
		-- Portals along the way, and diamond sparkles.
		for k = 1, 4 do
			local u = k / 5
			local at = spiral(easeOutQuart(lerp(0, 1, u)), 24, math.sin(math.pi * easeOutQuart(u)) * 20)
			local portal = part(Enum.PartType.Cylinder, Vector3.new(0.4, 1, 1), CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), RAINBOW[k * 2])
			if portal then
				portal.Transparency = 0.45
				animate(portal, 0.4, { Size = Vector3.new(0.4, 12, 12) }, Enum.EasingStyle.Back)
				after(1.6 + 2.4 * u * 0.55, function()
					shockwave(at, 10, RAINBOW[k * 2], 0.6)
					fade(portal, 0.4, { Size = Vector3.new(0.2, 20, 20), Transparency = 1 })
				end)
			end
		end
		along(1.7, 2.2, 0.08, function() sparkles(riderPos, CYAN, 6, { 3, 8 }, 1) end)
		flashPassed(1.6, 2.4, CYAN, 16)
		after(4.0, function()
			-- A shower of crystal at the top.
			nova(B, CYAN, 10, 0.8)
			shockwave(landing + Vector3.new(0, 0.3, 0), 16, CYAN, 1)
			shockwave(landing + Vector3.new(0, 2, 0), 10, GOLD, 0.8)
			for k = 1, 12 do
				local dir = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.2, 1), random:NextNumber(-1, 1)).Unit
				local shard = part(Enum.PartType.Block, Vector3.new(0.7, 0.7, 1.4), CFrame.lookAt(B, B + dir), RAINBOW[(k - 1) % #RAINBOW + 1], Enum.Material.Glass)
				if shard then fade(shard, 1, { CFrame = CFrame.lookAt(B + dir * 18 - Vector3.new(0, 6, 0), B + dir * 19), Transparency = 1 }) end
			end
			sparkles(B, WHITE, 60, { 10, 28 }, 1.6)
			addShake(1.6)
		end)
		arrive(4.0, CYAN, 12)
	elseif up and tier == 5 then
		-- STARLIGHT ASCENT: night falls and a beam of starlight carries them up.
		grade({ Brightness = -0.18, Contrast = 0.25, Saturation = -0.2, TintColor = Color3.fromRGB(170, 190, 255) }, 0.5, 4.4, 1)
		for k = 1, 8 do
			local angle = k * math.pi / 4
			sparkles(A + Vector3.new(math.cos(angle) * 20, random:NextNumber(0, 18), math.sin(angle) * 20), WHITE, 10, { 0.5, 2 }, 1.4)
		end
		local beam = part(Enum.PartType.Cylinder, Vector3.new(160, 1, 1), CFrame.new(A + Vector3.new(0, 76, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(220, 235, 255))
		if beam then
			beam.Transparency = 0.35
			animate(beam, 0.4, { Size = Vector3.new(160, 9, 9) }, Enum.EasingStyle.Back)
			light(beam, Color3.fromRGB(200, 220, 255), 30, 4, 2)
			after(1.6, function() fade(beam, 0.8, { Size = Vector3.new(160, 0.2, 0.2), Transparency = 1 }) end)
		end
		after(0.3, function() shockwave(feet + Vector3.new(0, 0.3, 0), 12, WHITE, 0.9) end)
		hover(0.4, 1.0, function(t) return Vector3.new(0, smooth(t) * 5, 0) end, 1)
		-- Stars orbit the climber the whole way.
		local orbiters: { Part } = {}
		for k = 1, 6 do
			local orb = part(Enum.PartType.Ball, Vector3.one * 0.9, CFrame.new(A), if k % 2 == 0 then CYAN else WHITE)
			if orb then table.insert(orbiters, orb) end
		end
		motion(5.2, function(t)
			for k, orb in orbiters do
				local angle = t * 26 + k * math.pi / 3
				orb.CFrame = CFrame.new(riderPos + Vector3.new(math.cos(angle) * 4.5, math.sin(t * 13 + k) * 1.5, math.sin(angle) * 4.5))
			end
		end, function()
			for _, orb in orbiters do fade(orb, 0.3, { Transparency = 1 }) end
		end)
		after(1.4, function()
			flash(riderPos, WHITE, 22)
			shockwave(riderPos, 16, CYAN, 0.9)
			sparkles(riderPos, CYAN, 70, { 14, 30 }, 1.6)
			addShake(1.8)
			if tracer then light(tracer, CYAN, 26, 4, 4) end
		end)
		trail(sequence(WHITE, CYAN, BLUE, VIOLET), 2.4, 1.2)
		ride(1.4, 3.6, { ease = smooth, bulge = 18, lift = function(u) return 5 * (1 - u) + math.sin(math.pi * u) * 24 end, spins = 4 })
		punch(100, 0.5, 2.6, 1)
		along(1.5, 3.4, 0.07, function() sparkles(riderPos, WHITE, 5, { 2, 6 }, 1.1) end)
		along(1.8, 3, 0.7, function(t)
			local side = Vector3.new(math.cos(t * 9) * 10, 4, math.sin(t * 9) * 10)
			firework(riderPos + side, if t < 0.5 then CYAN else VIOLET, 30)
		end)
		flashPassed(1.4, 3.6, Color3.fromRGB(200, 225, 255), 24)
		after(5.0, function()
			-- SUPERNOVA.
			nova(B, Color3.fromRGB(200, 230, 255), 16, 1)
			shockwave(landing + Vector3.new(0, 0.3, 0), 22, CYAN, 1.2)
			shockwave(B + Vector3.new(0, 3, 0), 14, WHITE, 0.9)
			shockwave(B + Vector3.new(0, 6, 0), 9, VIOLET, 0.7)
			sparkles(B, WHITE, 120, { 14, 40 }, 1.8)
			grade({ Brightness = 0.3, Contrast = 0.1 }, 0.06, 0.15, 0.6)
			addShake(2.2)
		end)
		arrive(5.0, CYAN, 14)
	elseif up and tier == 6 then
		-- GALACTIC ASCENSION: a galaxy spins under them, a big bang hurls them up at warp speed.
		grade({ Brightness = -0.3, Contrast = 0.35, Saturation = 0.25, TintColor = Color3.fromRGB(205, 170, 255) }, 0.6, 6, 1.2)
		local arms: { Part } = {}
		for k = 1, 3 do
			local disc = part(Enum.PartType.Cylinder, Vector3.new(0.2, 4 + k * 7, 4 + k * 7), CFrame.new(feet - Vector3.new(0, k * 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), ({ PINK, VIOLET, BLUE })[k])
			if disc then
				disc.Transparency = 1
				animate(disc, 0.6, { Transparency = 0.45 + k * 0.1 })
				table.insert(arms, disc)
			end
		end
		local stars: { Part } = {}
		for k = 1, 16 do
			local star = part(Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(feet), RAINBOW[(k - 1) % #RAINBOW + 1])
			if star then table.insert(stars, star) end
		end
		-- The galaxy turns, faster and faster, until the big bang flings it out.
		motion(1.9, function(t)
			for k, star in stars do
				local arm = k % 2
				local r = 2 + (k / #stars) * 12
				local angle = t * t * 30 + arm * math.pi + r * 0.5
				star.CFrame = CFrame.new(feet + Vector3.new(math.cos(angle) * r, 0.5, math.sin(angle) * r))
			end
			for k, disc in arms do
				disc.CFrame = CFrame.new(feet - Vector3.new(0, k * 0.6, 0)) * CFrame.Angles(t * t * 12 * (if k % 2 == 0 then -1 else 1), 0, math.pi / 2)
			end
		end)
		-- Planets orbit the climber.
		local planets: { Part } = {}
		for k = 1, 3 do
			local planet = part(Enum.PartType.Ball, Vector3.one * (1 + k * 0.4), CFrame.new(A), ({ ORANGE, CYAN, PINK })[k], Enum.Material.SmoothPlastic)
			if planet then table.insert(planets, planet) end
		end
		motion(7, function(t)
			for k, planet in planets do
				local angle = t * (14 + k * 4) + k * 2
				planet.CFrame = CFrame.new(riderPos + Vector3.new(math.cos(angle) * (4 + k * 2), math.sin(angle * 0.7) * 2, math.sin(angle) * (4 + k * 2)))
			end
		end, function()
			for _, planet in planets do fade(planet, 0.3, { Transparency = 1 }) end
		end)
		hover(0.4, 1.4, function(t) return Vector3.new(random:NextNumber(-0.1, 0.1) * t, smooth(t) * 6, random:NextNumber(-0.1, 0.1) * t) end, 3)
		along(0.4, 1.4, 0.25, function(t) addShake(0.4 + t * 1.2); sparkles(feet, PINK, 10, { 2, 8 }) end)
		after(1.8, function()
			-- BIG BANG.
			flash(riderPos, WHITE, 40)
			nova(feet, PINK, 18, 0.9)
			shockwave(feet + Vector3.new(0, 0.3, 0), 30, PINK, 1.2)
			shockwave(feet + Vector3.new(0, 2, 0), 20, VIOLET, 1)
			shockwave(riderPos, 14, WHITE, 0.8)
			for _, star in stars do
				local dir = Vector3.new(star.Position.X - feet.X, random:NextNumber(-0.2, 0.6), star.Position.Z - feet.Z)
				if dir.Magnitude < 0.01 then dir = Vector3.new(1, 0, 0) end
				fade(star, 0.9, { CFrame = star.CFrame + dir.Unit * 40, Transparency = 1 })
			end
			for _, disc in arms do fade(disc, 0.6, { Size = disc.Size * 3, Transparency = 1 }) end
			sparkles(feet, WHITE, 120, { 20, 50 }, 2)
			grade({ Brightness = 0.4, Contrast = 0.2 }, 0.05, 0.1, 0.5)
			addShake(2.6)
			if tracer then light(tracer, PINK, 30, 5, 5) end
		end)
		trail(sequence(RED, ORANGE, YELLOW, GREEN, CYAN, BLUE, VIOLET, PINK), 3.2, 1.4)
		ride(1.8, 5, { ease = function(t) return easeOutQuart(t) * 0.7 + smooth(t) * 0.3 end, bulge = 30,
			lift = function(u) return 6 * (1 - u) + math.sin(math.pi * u) * 30 end, spins = 6, flips = 2 })
		punch(110, 0.1, 4, 1.4)
		-- Warp streaks rush past.
		along(1.9, 4.6, 0.06, function()
			local offset = Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
			local streak = part(Enum.PartType.Block, Vector3.new(0.18, 9, 0.18), CFrame.new(riderPos + offset + Vector3.new(0, 18, 0)), RAINBOW[random:NextInteger(1, #RAINBOW)])
			if streak then fade(streak, 0.35, { CFrame = CFrame.new(riderPos + offset - Vector3.new(0, 26, 0)), Transparency = 1 }) end
		end)
		-- Giant portals to fly through.
		for k = 1, 6 do
			local u = k / 7
			local eased = easeOutQuart(u) * 0.7 + smooth(u) * 0.3
			local at = spiral(eased, 30, 6 * (1 - eased) + math.sin(math.pi * eased) * 30)
			local portal = part(Enum.PartType.Cylinder, Vector3.new(0.5, 1, 1), CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), RAINBOW[k + 1])
			if portal then
				portal.Transparency = 1
				after(1.8, function()
					animate(portal, 0.4, { Size = Vector3.new(0.5, 16, 16), Transparency = 0.4 }, Enum.EasingStyle.Back)
				end)
				after(1.8 + 5 * u * 0.92, function()
					shockwave(at, 14, RAINBOW[k + 1], 0.7)
					sparkles(at, RAINBOW[k + 1], 20, { 10, 24 })
					fade(portal, 0.4, { Size = Vector3.new(0.2, 28, 28), Transparency = 1 })
				end)
			end
		end
		along(2.2, 4.4, 0.55, function(t)
			local side = Vector3.new(math.cos(t * 14) * 14, 6, math.sin(t * 14) * 14)
			firework(riderPos + side, RAINBOW[math.floor(t * #RAINBOW) + 1], 34)
		end)
		flashPassed(1.8, 5, WHITE, 30)
		after(6.8, function()
			-- GALAXY NOVA, with fireworks all round the tower.
			nova(B, PINK, 22, 1.1)
			shockwave(landing + Vector3.new(0, 0.3, 0), 30, PINK, 1.3)
			shockwave(B + Vector3.new(0, 3, 0), 20, CYAN, 1.1)
			shockwave(B + Vector3.new(0, 6, 0), 14, GOLD, 0.9)
			shockwave(B + Vector3.new(0, 9, 0), 9, WHITE, 0.7)
			for k = 1, 6 do
				local angle = k * math.pi / 3
				firework(Vector3.new(O.X + math.cos(angle) * 40, B.Y + 10 + (k % 2) * 6, O.Z + math.sin(angle) * 40), RAINBOW[k + 1], 40)
			end
			sparkles(B, WHITE, 140, { 16, 46 }, 2)
			grade({ Brightness = 0.35, Contrast = 0.15, Saturation = 0.4 }, 0.05, 0.2, 0.7)
			addShake(2.4)
		end)
		arrive(6.8, PINK, 18)
	elseif tier == 1 then
		-- BANANA SLIP: a peel, a backflip and a dizzy landing.
		local peel = part(Enum.PartType.Block, Vector3.new(1.4, 0.3, 0.7), CFrame.new(feet + riderLook * 0.6 + Vector3.new(0, 0.2, 0)), YELLOW, Enum.Material.SmoothPlastic)
		if peel then
			light(peel, YELLOW, 10, 2, 0.8)
			after(0.3, function() fade(peel, 0.5, { CFrame = peel.CFrame + riderLook * 4 + Vector3.new(0, 2, 0), Transparency = 1 }) end)
		end
		ride(0.3, 0.9, { ease = smooth, bulge = 3, lift = function(u) return math.sin(math.pi * u) * 4 end, flips = -1.25 })
		after(1.15, function()
			burst(landing, { texture = TEXTURES.smoke, count = 10, colour = sequence(Color3.fromRGB(200, 196, 188)), size = curve(1, 3),
				transparency = curve(0.4, 1), lifetime = { 0.5, 1 }, speed = { 3, 7 }, glow = 0 })
		end)
		-- Dizzy stars.
		local dizzy: { Part } = {}
		for k = 1, 3 do
			local star = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(B), YELLOW)
			if star then table.insert(dizzy, star) end
		end
		after(1.2, function()
			motion(0.4, function(t)
				for k, star in dizzy do
					local angle = t * 14 + k * math.pi * 2 / 3
					star.CFrame = CFrame.new(B + Vector3.new(math.cos(angle) * 1.4, 2.6, math.sin(angle) * 1.4))
				end
			end)
		end)
		arrive(1.2, YELLOW, 4)
	elseif tier == 2 then
		-- SPIKE BOUNCE: spikes shoot out of the platform and bounce them off.
		local spikes: { Part } = {}
		for k = 1, 8 do
			local angle = k * math.pi / 4
			local at = feet + Vector3.new(math.cos(angle) * 2.4, -1.5, math.sin(angle) * 2.4)
			local spike = part(Enum.PartType.Block, Vector3.new(0.5, 3, 0.5), CFrame.new(at) * CFrame.Angles(0, angle, 0.25), RED, Enum.Material.Metal)
			if spike then
				animate(spike, 0.15, { CFrame = CFrame.new(at + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, angle, 0.25) }, Enum.EasingStyle.Back)
				after(0.9, function() fade(spike, 0.4, { CFrame = CFrame.new(at) * CFrame.Angles(0, angle, 0.25), Transparency = 1 }) end)
				table.insert(spikes, spike)
			end
		end
		after(0.15, function()
			sparkles(feet + Vector3.new(0, 1, 0), RED, 30, { 8, 18 })
			addShake(0.6)
			if spikes[1] then light(spikes[1], RED, 14, 3, 0.8) end
		end)
		trail(sequence(RED, Color3.fromRGB(120, 20, 30)), 1.4, 0.4)
		ride(0.35, 1.4, { ease = smooth, bulge = 6, lift = function(u) return math.sin(math.pi * u) * 9 end, flips = -2 })
		after(1.75, function()
			burst(landing, { texture = TEXTURES.smoke, count = 14, colour = sequence(SMOKE), size = curve(1.5, 4),
				transparency = curve(0.3, 1), lifetime = { 0.6, 1.2 }, speed = { 4, 9 }, glow = 0 })
		end)
		arrive(1.75, RED, 7)
	elseif tier == 3 then
		-- ANVIL SMASH: an anvil falls on them, CLANG, and drives them down the tower.
		local shadow = part(Enum.PartType.Cylinder, Vector3.new(0.1, 1, 1), CFrame.new(feet + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), BLACK, Enum.Material.SmoothPlastic)
		if shadow then
			shadow.Transparency = 0.6
			animate(shadow, 0.7, { Size = Vector3.new(0.1, 6, 6), Transparency = 0.25 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			after(0.75, function() fade(shadow, 0.2, { Transparency = 1 }) end)
		end
		local high = A + Vector3.new(0, 70, 0)
		local anvil: { Part } = {}
		local pieces = {
			{ Vector3.new(5, 1.6, 3), Vector3.new(0, 0.8, 0) },
			{ Vector3.new(2.4, 1.6, 2), Vector3.new(0, 2.4, 0) },
			{ Vector3.new(6.5, 1.6, 3), Vector3.new(0.6, 4, 0) },
			{ Vector3.new(2, 1.2, 1.6), Vector3.new(4.4, 4.2, 0) },
		}
		local offsets: { Vector3 } = {}
		for _, piece in pieces do
			local p = part(Enum.PartType.Block, piece[1], CFrame.new(high + piece[2]), IRON, Enum.Material.Metal)
			if p then
				table.insert(anvil, p)
				table.insert(offsets, piece[2] + Vector3.new(0, 2.6, 0))
			end
		end
		local anvilAt = high
		local function moveAnvil(at: Vector3)
			anvilAt = at
			for i, p in anvil do p.CFrame = CFrame.lookAt(at + offsets[i], at + offsets[i] + riderLook) end
		end
		motion(0.75, function(t) moveAnvil(high + (A - high) * easeIn(t)) end)
		after(0.75, function()
			-- CLANG.
			flash(A + Vector3.new(0, 3, 0), WHITE, 18)
			burst(A + Vector3.new(0, 3, 0), { texture = TEXTURES.ember, count = 60, colour = sequence(WHITE, YELLOW, ORANGE), size = curve(0.6, 0.2),
				lifetime = { 0.4, 0.9 }, speed = { 18, 40 }, drag = 2, acceleration = Vector3.new(0, -40, 0) })
			shockwave(feet + Vector3.new(0, 0.3, 0), 14, WHITE, 0.8)
			addShake(2)
			grade({ Brightness = 0.2, Contrast = 0.3, Saturation = -0.4 }, 0.04, 0.15, 0.5)
			if anvil[1] then light(anvil[1], YELLOW, 22, 6, 0.6) end
		end)
		-- Squashed, then driven down with the anvil on top.
		hover(0.75, 0.2, function(t) return Vector3.new(0, -t * 0.8, 0) end)
		motion(3, function()
			if anvilAt ~= high and riderPos ~= A then moveAnvil(riderPos) end
		end)
		trail(sequence(YELLOW, ORANGE, IRON), 2, 0.6)
		ride(0.95, 1.95, { ease = easeIn, bulge = 6, lift = function(u) return math.sin(math.pi * u) * 3 end, rolls = 1.5 })
		punch(90, 0.6, 1.2, 0.6)
		along(1, 1.9, 0.07, function()
			burst(riderPos + Vector3.new(0, 4, 0), { texture = TEXTURES.ember, count = 5, colour = sequence(YELLOW, ORANGE), size = curve(0.5, 0.1),
				lifetime = { 0.3, 0.6 }, speed = { 10, 20 }, drag = 2, acceleration = Vector3.new(0, 20, 0) })
		end)
		along(1.2, 1.6, 0.4, function() addShake(0.9) end)
		flashPassed(0.95, 1.95, RED, 12)
		after(2.9, function()
			-- THUD.
			fireball(landing + Vector3.new(0, 1, 0), 2, 16)
			shockwave(landing + Vector3.new(0, 0.3, 0), 16, ORANGE, 1)
			shockwave(landing + Vector3.new(0, 1.5, 0), 10, WHITE, 0.7)
			for k = 1, 8 do
				local dir = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.4, 1), random:NextNumber(-1, 1)).Unit
				local chunk = part(Enum.PartType.Block, Vector3.one * random:NextNumber(0.5, 1.1), CFrame.new(landing + Vector3.new(0, 1, 0)), ClimbPath.colour(to), Enum.Material.SmoothPlastic)
				if chunk then fade(chunk, 0.8, { CFrame = CFrame.new(landing + dir * 12 - Vector3.new(0, 4, 0)) * CFrame.Angles(3, 2, 1), Transparency = 1 }) end
			end
			for _, p in anvil do
				fade(p, 0.7, { CFrame = p.CFrame + Vector3.new(0, 8, 0) + riderLook * 10, Transparency = 1 })
			end
			addShake(2.2)
		end)
		arrive(2.9, RED, 10)
	elseif tier == 4 then
		-- METEOR STRIKE: the sky burns, a meteor hits and blasts them off in flames.
		grade({ Brightness = -0.05, Contrast = 0.3, Saturation = 0.3, TintColor = Color3.fromRGB(255, 190, 150) }, 0.4, 3.4, 0.8)
		local out = Vector3.new(A.X - O.X, 0, A.Z - O.Z).Unit
		local sky = A + out * 90 + Vector3.new(0, 110, 0)
		local meteor = part(Enum.PartType.Ball, Vector3.one * 7, CFrame.new(sky), Color3.fromRGB(70, 50, 40), Enum.Material.Basalt)
		local core = part(Enum.PartType.Ball, Vector3.one * 5.2, CFrame.new(sky), ORANGE)
		local meteorAt = sky
		if meteor then
			light(meteor, ORANGE, 40, 6, 1.4)
			motion(1.2, function(t)
				meteorAt = sky + (A - sky) * easeIn(t)
				meteor.CFrame = CFrame.new(meteorAt) * CFrame.Angles(t * 8, t * 5, 0)
				if core then core.CFrame = CFrame.new(meteorAt) end
			end, function()
				fade(meteor, 0.2, { Transparency = 1 })
				if core then fade(core, 0.2, { Transparency = 1, Size = Vector3.one * 14 }) end
			end)
		end
		along(0, 1.2, 0.05, function()
			burst(meteorAt, { texture = TEXTURES.fire, count = 6, colour = sequence(YELLOW, ORANGE, RED), size = curve(4, 6, 1),
				lifetime = { 0.3, 0.6 }, speed = { 1, 4 }, drag = 1 })
			burst(meteorAt, { texture = TEXTURES.smoke, count = 3, colour = sequence(SMOKE, Color3.fromRGB(40, 36, 34)), size = curve(4, 9),
				transparency = curve(0.3, 1), lifetime = { 1, 2 }, speed = { 0.5, 2 }, glow = 0 })
		end)
		along(0.3, 0.9, 0.3, function(t) addShake(0.4 + t) end)
		after(1.2, function()
			-- Impact.
			flash(A, YELLOW, 34)
			fireball(A, 4, 40)
			shockwave(feet + Vector3.new(0, 0.3, 0), 22, ORANGE, 1.1)
			shockwave(feet + Vector3.new(0, 3, 0), 14, RED, 0.9)
			shockwave(feet + Vector3.new(0, 6, 0), 9, YELLOW, 0.7)
			burst(A, { texture = TEXTURES.ember, count = 80, colour = sequence(YELLOW, ORANGE, RED), size = curve(0.8, 0.2),
				lifetime = { 0.6, 1.4 }, speed = { 20, 46 }, drag = 1.5, acceleration = Vector3.new(0, -30, 0) })
			addShake(2.5)
			grade({ Brightness = 0.3, Contrast = 0.2 }, 0.05, 0.12, 0.5)
			if tracer then light(tracer, ORANGE, 24, 4, 3) end
		end)
		trail(sequence(YELLOW, ORANGE, RED, SMOKE), 2.6, 1)
		ride(1.3, 2.7, { ease = smooth, bulge = 22, lift = function(u) return math.sin(math.pi * math.min(1, u * 1.6)) * 9 * (1 - u) end, flips = -3, spins = 2 })
		punch(98, 0.15, 2, 0.8)
		along(1.35, 2.6, 0.06, function()
			burst(riderPos, { texture = TEXTURES.fire, count = 4, colour = sequence(YELLOW, ORANGE, RED), size = curve(1.6, 2.4, 0.3),
				lifetime = { 0.3, 0.6 }, speed = { 1, 4 } })
			burst(riderPos, { texture = TEXTURES.smoke, count = 2, colour = sequence(SMOKE), size = curve(2, 5),
				transparency = curve(0.4, 1), lifetime = { 0.8, 1.6 }, speed = { 0.5, 2 }, glow = 0 })
		end)
		-- Burning rocks fall alongside.
		along(1.5, 2.2, 0.3, function()
			local start = riderPos + Vector3.new(random:NextNumber(-10, 10), 14, random:NextNumber(-10, 10))
			local rock = part(Enum.PartType.Ball, Vector3.one * random:NextNumber(1, 2), CFrame.new(start), ORANGE)
			if rock then fade(rock, 0.8, { CFrame = CFrame.new(start - Vector3.new(0, 40, 0)), Transparency = 1 }) end
		end)
		flashPassed(1.3, 2.7, ORANGE, 16)
		after(4.0, function()
			fireball(landing + Vector3.new(0, 1, 0), 3, 30)
			burst(landing, { texture = TEXTURES.smoke, count = 20, colour = sequence(SMOKE, Color3.fromRGB(50, 46, 44)), size = curve(3, 8),
				transparency = curve(0.2, 1), lifetime = { 1.5, 2.5 }, speed = { 2, 6 }, spread = 25, glow = 0, acceleration = Vector3.new(0, 6, 0) })
			shockwave(landing + Vector3.new(0, 0.3, 0), 18, ORANGE, 1)
			addShake(2)
		end)
		arrive(4.0, ORANGE, 12)
	elseif tier == 5 then
		-- THUNDER HAMMER: a storm, lightning, and a giant hammer slams them down.
		grade({ Brightness = -0.25, Contrast = 0.4, Saturation = -0.5, TintColor = Color3.fromRGB(170, 190, 230) }, 0.4, 4.6, 1)
		local cloud = A + Vector3.new(0, 36, 0)
		along(0, 2, 0.25, function()
			burst(cloud + Vector3.new(random:NextNumber(-14, 14), random:NextNumber(-2, 2), random:NextNumber(-14, 14)), { texture = TEXTURES.smoke, count = 6,
				colour = sequence(Color3.fromRGB(60, 62, 76), Color3.fromRGB(30, 30, 40)), size = curve(8, 14), transparency = curve(0.3, 1),
				lifetime = { 1.5, 2.5 }, speed = { 0.5, 2 }, glow = 0 })
		end)
		for k = 1, 5 do
			after(0.2 + k * 0.22, function()
				local angle = random:NextNumber(0, math.pi * 2)
				local ground = feet + Vector3.new(math.cos(angle) * random:NextNumber(4, 12), 0, math.sin(angle) * random:NextNumber(4, 12))
				bolt(cloud + Vector3.new(random:NextNumber(-6, 6), 0, random:NextNumber(-6, 6)), ground, CYAN, 0.5)
				flash(ground, CYAN, 8)
				addShake(0.7)
			end)
		end
		-- The hammer swings down from overhead.
		local pivot = A + Vector3.new(0, 4, 0) - riderLook * 9
		local handle = part(Enum.PartType.Block, Vector3.new(1, 1, 12), CFrame.new(pivot), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
		local head = part(Enum.PartType.Block, Vector3.new(6, 4.5, 4.5), CFrame.new(pivot), Color3.fromRGB(150, 160, 180), Enum.Material.Metal)
		local runes = part(Enum.PartType.Block, Vector3.new(6.2, 1, 4.7), CFrame.new(pivot), CYAN)
		local function swing(angle: number)
			local frame = CFrame.lookAt(pivot, pivot + riderLook) * CFrame.fromAxisAngle(Vector3.new(1, 0, 0), angle)
			if handle then handle.CFrame = frame * CFrame.new(0, 0, -6) end
			if head then head.CFrame = frame * CFrame.new(0, 0, -12.5) end
			if runes then runes.CFrame = frame * CFrame.new(0, 0, -12.5) end
		end
		swing(math.rad(80))
		motion(1.4, function(t) swing(math.rad(80 + 40 * smooth(t))) end)
		after(1.4, function()
			motion(0.6, function(t) swing(math.rad(120 - 125 * easeIn(t))) end)
		end)
		after(2.0, function()
			-- SMASH.
			bolt(cloud, A, WHITE, 1.2)
			bolt(cloud + Vector3.new(4, 0, 0), A, CYAN, 0.8)
			flash(A, WHITE, 36)
			nova(A, CYAN, 12, 0.6)
			shockwave(feet + Vector3.new(0, 0.3, 0), 24, CYAN, 1.1)
			shockwave(feet + Vector3.new(0, 2, 0), 16, WHITE, 0.9)
			shockwave(feet + Vector3.new(0, 4, 0), 10, BLUE, 0.7)
			sparkles(A, CYAN, 80, { 16, 40 }, 1.6)
			addShake(2.6)
			grade({ Brightness = 0.5, Contrast = 0.2 }, 0.03, 0.08, 0.4)
			for _, p in { handle, head, runes } do
				if p then after(0.4, function() fade(p, 0.5, { Transparency = 1 }) end) end
			end
			if tracer then light(tracer, CYAN, 26, 5, 3.4) end
		end)
		trail(sequence(WHITE, CYAN, BLUE), 2.4, 0.8)
		ride(2.1, 3.1, { ease = easeIn, bulge = 16, lift = function(u) return math.sin(math.pi * u) * 4 end, flips = -4, spins = 1 })
		punch(100, 0.15, 2.4, 0.8)
		-- Lightning chases them all the way down.
		along(2.3, 2.9, 0.3, function()
			bolt(riderPos + Vector3.new(random:NextNumber(-8, 8), 34, random:NextNumber(-8, 8)), riderPos, if random:NextNumber() < 0.5 then CYAN else WHITE, 0.45)
			addShake(0.6)
		end)
		along(2.2, 2.9, 0.08, function() sparkles(riderPos, CYAN, 4, { 3, 8 }, 0.9) end)
		flashPassed(2.1, 3.1, CYAN, 20)
		after(5.2, function()
			-- Thunder clap.
			bolt(landing + Vector3.new(0, 40, 0), landing, WHITE, 1.2)
			flash(landing, CYAN, 24)
			shockwave(landing + Vector3.new(0, 0.3, 0), 18, CYAN, 1)
			shockwave(landing + Vector3.new(0, 2, 0), 11, WHITE, 0.8)
			sparkles(landing, CYAN, 50, { 12, 30 }, 1.4)
			addShake(2)
		end)
		arrive(5.2, CYAN, 12)
	else
		-- BLACK HOLE PLUNGE: a black hole swallows the light and the climber.
		grade({ Brightness = -0.35, Contrast = 0.4, Saturation = -0.3, TintColor = Color3.fromRGB(190, 160, 255) }, 0.8, 6, 1.2)
		local out = Vector3.new(A.X - O.X, 0, A.Z - O.Z).Unit
		local holeAt = A + out * 14 - Vector3.new(0, 6, 0)
		local hole = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(holeAt), BLACK, Enum.Material.SmoothPlastic)
		local disks: { Part } = {}
		for k = 1, 3 do
			local disk = part(Enum.PartType.Cylinder, Vector3.new(0.2, 1, 1), CFrame.new(holeAt) * CFrame.Angles(0.3, 0, math.pi / 2), ({ ORANGE, PINK, VIOLET })[k])
			if disk then
				disk.Transparency = 0.35 + k * 0.12
				table.insert(disks, disk)
			end
		end
		if hole then
			animate(hole, 1.2, { Size = Vector3.one * 9 }, Enum.EasingStyle.Back)
			light(hole, VIOLET, 40, 6, 7)
		end
		for k, disk in disks do
			animate(disk, 1.2, { Size = Vector3.new(0.2, 14 + k * 6, 14 + k * 6) }, Enum.EasingStyle.Back)
		end
		-- The hole and its disks turn, and follow the climber down later.
		local spinning = true
		motion(7.4, function(t)
			if not spinning then return end
			for k, disk in disks do
				disk.CFrame = CFrame.new(holeAt) * CFrame.Angles(0.3, t * 40 * (if k % 2 == 0 then -1 else 1), math.pi / 2)
			end
			if hole then hole.CFrame = CFrame.new(holeAt) end
		end)
		-- Everything near is pulled in: sparks and broken gems spiral into it.
		along(0.3, 2, 0.08, function(t)
			local angle = random:NextNumber(0, math.pi * 2)
			local start = holeAt + Vector3.new(math.cos(angle) * 26, random:NextNumber(-8, 12), math.sin(angle) * 26)
			local bit = part(Enum.PartType.Block, Vector3.one * random:NextNumber(0.4, 1), CFrame.new(start), RAINBOW[random:NextInteger(1, #RAINBOW)])
			if bit then
				local spinFrom = angle
				motion(0.9, function(s)
					local r = 26 * (1 - easeIn(s))
					local a = spinFrom + s * 6
					bit.CFrame = CFrame.new(holeAt + Vector3.new(math.cos(a) * r, (start.Y - holeAt.Y) * (1 - s), math.sin(a) * r)) * CFrame.Angles(s * 9, s * 7, 0)
				end, function() bit:Destroy() end)
			end
			if t > 0.5 then addShake(0.3 + t * 0.6) end
		end)
		hover(0.4, 2, function(t)
			local pull = holeAt + Vector3.new(0, 4, 0) - A
			return pull * easeIn(t) * 0.55 + Vector3.new(0, math.sin(t * 20) * 0.3, 0)
		end, 3)
		after(2.4, function()
			-- Swallowed.
			grade({ Brightness = -0.5, Contrast = 0.5 }, 0.15, 0.25, 0.6)
			shockwave(holeAt, 22, VIOLET, 1)
			burst(holeAt, { texture = TEXTURES.glow, count = 3, colour = sequence(VIOLET, BLACK), size = curve(20, 2), lifetime = { 0.5, 0.6 }, speed = { 0, 0.1 } })
			addShake(2.2)
			if tracer then light(tracer, VIOLET, 22, 4, 4) end
			spinning = false
		end)
		-- The hole plunges with them.
		after(2.4, function()
			motion(4.2, function(t)
				local below = riderPos - Vector3.new(0, 7, 0)
				holeAt = holeAt + (below - holeAt) * math.min(1, t * 4)
				if hole then hole.CFrame = CFrame.new(holeAt) end
				for k, disk in disks do
					disk.CFrame = CFrame.new(holeAt) * CFrame.Angles(0.3, t * 60 * (if k % 2 == 0 then -1 else 1), math.pi / 2)
				end
			end)
		end)
		trail(sequence(PINK, VIOLET, BLACK), 2.8, 1.2)
		ride(2.4, 4.2, { ease = function(t) return easeIn(t) * 0.5 + smooth(t) * 0.5 end, bulge = 20, lift = function(u) return (1 - u) * -2 end, spins = -5, rolls = 3 })
		punch(112, 0.3, 3.4, 1)
		-- Warped light streaks upward as they fall.
		along(2.5, 4, 0.06, function()
			local offset = Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
			local streak = part(Enum.PartType.Block, Vector3.new(0.18, 8, 0.18), CFrame.new(riderPos + offset - Vector3.new(0, 18, 0)), if random:NextNumber() < 0.5 then VIOLET else PINK)
			if streak then fade(streak, 0.35, { CFrame = CFrame.new(riderPos + offset + Vector3.new(0, 26, 0)), Transparency = 1 }) end
		end)
		along(2.6, 3.8, 0.5, function() addShake(0.9) end)
		flashPassed(2.4, 4.2, VIOLET, 30)
		after(6.6, function()
			-- Spat out in a nova.
			if hole then fade(hole, 0.3, { Size = Vector3.one * 0.2 }) end
			for _, disk in disks do fade(disk, 0.4, { Size = Vector3.new(0.2, 40, 40), Transparency = 1 }) end
			nova(B, WHITE, 20, 1)
			shockwave(landing + Vector3.new(0, 0.3, 0), 28, VIOLET, 1.2)
			shockwave(B + Vector3.new(0, 3, 0), 18, PINK, 1)
			shockwave(B + Vector3.new(0, 6, 0), 12, WHITE, 0.8)
			shockwave(B + Vector3.new(0, 9, 0), 8, ORANGE, 0.6)
			sparkles(B, VIOLET, 140, { 16, 44 }, 2)
			grade({ Brightness = 0.4, Contrast = 0.2 }, 0.04, 0.15, 0.6)
			addShake(2.6)
		end)
		arrive(6.6, VIOLET, 16)
	end
	return seconds
end

return ClimbEffects
