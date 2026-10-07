--!strict
-- Gift effects: a hand-made sequence for each gift tier, played on every
-- client and never physical (nothing collides, is touched or blocks a click).
--
--   1  SPARK BURST       (1+ coins)       a crisp golden pop and a puff of dust
--   2  SHOCKWAVE         (10+ coins)      a ground shockwave, sparks and flying rock
--   3  DIAMOND FRACTURE  (100+ coins)     glowing cracks, then crystals burst out and shatter
--   4  ORBITAL STRIKE    (500+ coins)     a target locks on, a beam fires from the sky, then a
--                                         barrage walks round the crater and a wider beam ends it
--   5  GALAXY COLLAPSE   (1,000+ coins)   a swirling black hole pulls in stars, goes nova, flings
--                                         out spiral arms, then pulses again with a starlight beam
--   6  COSMIC BURST      (10,000+ coins)  the sky darkens, a meteor storm falls, a comet hits,
--                                         fire geysers erupt, more meteors, then a cosmic shock
--
-- Built from Roblox's own particle textures (sparkles, fire, smoke, embers and
-- shockwave rings), neon parts, trails, lights, a gentle camera shake and a
-- brief colour grade. At most two sequences play at once, each with a capped
-- number of parts, lights and particles. The small tiers are over in a second
-- or two; the big ones run for 4 to 8 seconds. Every piece is gone soon after.
--
-- Gifts that add stone have their own six, in greens, aimed at the summit:
--   1  PEBBLE DROP       pebbles fall onto the peak with puffs of dust
--   2  ROCKSLIDE         a ring of rocks rises out of the slopes and tumbles in
--   3  STONE SURGE       green veins converge, stone pillars thrust up and sink in
--   4  BOULDER BARRAGE   a dozen boulders are hurled in from far away and crash home
--   5  STONE CYCLONE     rocks from the valley spiral up into a towering cyclone,
--                        then slam down, and the peak blasts out a second ring
--   6  MOUNTAIN RISING   the ground rumbles, a colossal boulder descends, pulling
--                        rock up from all round, lands with a blast of light, and
--                        a ring of green pillars erupts round the mountain
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRush")
local GiftTier = require(Shared:WaitForChild("GiftTier"))
local Format = require(Shared:WaitForChild("Format"))
local CameraShake = require(script.Parent:WaitForChild("CameraShake"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local GiftEffects = {}

-- Particle textures that ship with every Roblox client.
local TEXTURES = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	ember = "rbxasset://textures/particles/fire_sparks_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
}
GiftEffects.TEXTURES = TEXTURES
GiftEffects.TITLES = { "SPARK BURST", "SHOCKWAVE", "DIAMOND FRACTURE", "ORBITAL STRIKE", "GALAXY COLLAPSE", "COSMIC BURST" }
-- Per tier: the big gifts get longer, wilder shows with room for more pieces.
GiftEffects.PART_LIMITS = { 70, 70, 70, 110, 130, 160 } -- parts one sequence may create
GiftEffects.LIGHT_LIMITS = { 3, 3, 3, 3, 4, 4 } -- lights one sequence may create
GiftEffects.LIFETIMES = { 9, 9, 9, 10, 11, 12 } -- seconds before a sequence is cleared, whatever happens
GiftEffects.PARTICLE_BUDGETS = { 400, 400, 400, 600, 700, 900 } -- particles one sequence may emit at once (checked by the tests)
-- How long the banner stays up for each tier.
local BANNER_SECONDS = { 1.85, 2.2, 2.55, 4.4, 5.6, 7.4 }

local COLOURS = {
	Color3.fromRGB(255, 208, 112), -- gold
	Color3.fromRGB(255, 140, 60), -- orange
	Color3.fromRGB(110, 235, 255), -- ice blue
	Color3.fromRGB(90, 190, 255), -- sky blue
	Color3.fromRGB(168, 96, 255), -- violet
	Color3.fromRGB(255, 220, 130), -- white gold
}
local GREEN = Color3.fromRGB(90, 235, 170)
-- Gifts that add stone (the griefers' gifts) get their own six sequences, in greens.
GiftEffects.ADD_TITLES = { "PEBBLE DROP", "ROCKSLIDE", "STONE SURGE", "BOULDER BARRAGE", "STONE CYCLONE", "MOUNTAIN RISING" }
local ADD_COLOURS = {
	Color3.fromRGB(150, 255, 200), -- mint
	Color3.fromRGB(90, 235, 170), -- green
	Color3.fromRGB(60, 225, 140), -- emerald
	Color3.fromRGB(120, 230, 90), -- moss
	Color3.fromRGB(70, 235, 200), -- jade
	Color3.fromRGB(140, 255, 120), -- bright green
}
local WHITE = Color3.new(1, 1, 1)
local PINK = Color3.fromRGB(255, 120, 210)
local SMOKE_DARK = Color3.fromRGB(70, 64, 60)
local SMOKE_LIGHT = Color3.fromRGB(150, 142, 134)
-- Flying rock and dust match the mountain's skin.
local ROCK = {
	stone = { colour = Color3.fromRGB(118, 114, 108), dust = Color3.fromRGB(160, 152, 142), material = Enum.Material.Slate },
	hay = { colour = Color3.fromRGB(214, 178, 92), dust = Color3.fromRGB(226, 202, 140), material = Enum.Material.Fabric },
}

local active: { { folder: Folder, tier: number } } = {}
local label: TextLabel? = nil
local state: Instance? = nil
local bannerSerial = 0
local bannerTier = 0
local bannerTween: Tween? = nil
local random = Random.new()

-- Camera shake: a small decaying wobble added after the camera has moved, so
-- it never builds up and the first-person hands follow it.
local shake = 0
local shaking = false
local shakeTime = 0
local function addShake(degrees: number)
	shake = math.max(shake, degrees)
	if shaking then return end
	shaking = true
	RunService:BindToRenderStep("DiamondRushGiftShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = workspace.CurrentCamera
		if shake < 0.01 or camera == nil then
			shake = 0
			shaking = false
			RunService:UnbindFromRenderStep("DiamondRushGiftShake")
			return
		end
		shakeTime += dt
		local t = shakeTime * 17
		local a = math.rad(shake) * 1.5 -- math.noise stays within about ±0.5
		CameraShake.apply(camera, CFrame.Angles(math.noise(t, 0.3) * a, math.noise(t, 7.1) * a, math.noise(t, 13.7) * a * 0.5))
		shake *= math.exp(-dt * 3.5)
	end)
end
GiftEffects.shaking = function(): boolean return shaking end

-- A brief colour grade over the whole screen: up to `peak` and back.
local function grade(peak: { [string]: any }, rise: number, hold: number, fall: number)
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "GiftGrade"
	effect.Parent = Lighting
	TweenService:Create(effect, TweenInfo.new(rise, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), peak):Play()
	task.delay(rise + hold, function()
		TweenService:Create(effect, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE,
		}):Play()
	end)
	Debris:AddItem(effect, rise + hold + fall + 0.1)
end

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

function GiftEffects.start(parent: Instance, gameState: Instance?)
	state = gameState
	local gui = Instance.new("ScreenGui")
	gui.Name = "GiftEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = parent
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.30)
	text.Size = UDim2.new(0.82, 0, 0, 64)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextStrokeTransparency = 0.35
	text.TextTransparency = 1
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = 24
	limit.Parent = text
	text.Parent = gui
	label = text
end

-- A craggy lump of rock: its parts and where each sits in the lump.
type Lump = { parts: { Part }, offsets: { CFrame } }

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
	glow: number?, -- light emission, 0 to 1
	spin: number?, -- degrees a second
	flat: boolean?, -- lies flat on the ground (shockwave rings)
}

function GiftEffects.play(data: any)
	if typeof(data.position) ~= "Vector3" or type(data.coins) ~= "number" then return end
	local tier = GiftTier.forCoins(data.coins)
	for i = #active, 1, -1 do
		if active[i].folder.Parent == nil then table.remove(active, i) end
	end
	if #active >= 2 then
		local weakest = 1
		for i, entry in active do
			if entry.tier < active[weakest].tier then weakest = i end
		end
		if active[weakest].tier > tier then return end
		table.remove(active, weakest).folder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GiftBurst"
	folder.Parent = workspace
	table.insert(active, { folder = folder, tier = tier })
	Debris:AddItem(folder, GiftEffects.LIFETIMES[tier])
	local colour = if data.adding then ADD_COLOURS[tier] else COLOURS[tier]
	local centre: Vector3 = data.position
	local skin = if state then state:GetAttribute("Skin") else nil
	local rock = ROCK[if type(skin) == "string" and ROCK[skin] then skin else "stone"]

	local made, lights = 0, 0
	local function alive(): boolean
		return folder.Parent ~= nil
	end
	-- Sounds grow deeper and louder with the tier.
	local loudness = 1 + (tier - 1) * 0.15
	local function noise(name: string, at: Vector3?)
		if alive() then Sounds.play(name, at, loudness) end
	end
	local function after(delay: number, callback: () -> ())
		task.delay(delay, function()
			if alive() then callback() end
		end)
	end
	local function part(shape: Enum.PartType, size: Vector3, frame: CFrame, tint: Color3, material: Enum.Material?): Part?
		if not alive() or made >= GiftEffects.PART_LIMITS[tier] then return nil end
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
	local function animate(p: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		TweenService:Create(p, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
	end
	local function fade(p: Instance, seconds: number, goal: { [string]: any })
		animate(p, seconds, goal)
		Debris:AddItem(p, seconds + 0.05)
	end
	-- One connection per moving piece, released when it ends or the sequence is cleared.
	local function motion(duration: number, update: (number) -> (), finish: (() -> ())?)
		local elapsed = 0
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function(dt: number)
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)
			if alive() then update(t) end
			if t >= 1 or not alive() then
				if connection then connection:Disconnect(); connection = nil end
				if alive() and finish then finish() end
			end
		end)
	end
	local function light(holder: Instance, tint: Color3, range: number, brightness: number, seconds: number)
		if lights >= GiftEffects.LIGHT_LIMITS[tier] then return end
		lights += 1
		local glow = Instance.new("PointLight")
		glow.Color = tint
		glow.Range = range
		glow.Brightness = brightness
		glow.Shadows = false
		glow.Parent = holder
		animate(glow, seconds, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	-- Particles come from attachments on one invisible anchor at the origin.
	local anchor = part(Enum.PartType.Block, Vector3.one * 0.2, CFrame.identity, WHITE) :: Part
	anchor.Transparency = 1
	local function emitter(spec: Particles, holder: Instance): ParticleEmitter
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
		particles.Parent = holder
		return particles
	end
	-- A point in the world to hang particles or a light on.
	local function point(at: Vector3, seconds: number): Attachment
		local spot = Instance.new("Attachment")
		spot.Position = at
		spot.Parent = anchor
		Debris:AddItem(spot, seconds)
		return spot
	end
	local function burst(at: Vector3, spec: Particles)
		if not alive() then return end
		emitter(spec, point(at, spec.lifetime[2] + 0.2)):Emit(spec.count)
	end
	-- A shockwave ring that races out flat across the ground.
	local function shockwave(at: Vector3, radius: number, tint: Color3, seconds: number)
		noise(if radius >= 18 then "bigBoom" elseif radius >= 6 then "boom" else "thud", at)
		burst(at + Vector3.new(0, 0.4, 0), {
			texture = TEXTURES.ring, count = 1, colour = sequence(WHITE, tint),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, radius * 1.5), NumberSequenceKeypoint.new(1, radius * 2) }),
			transparency = curve(0, 0.2, 1), lifetime = { seconds, seconds }, speed = { 0.01, 0.01 }, spread = 0, flat = true,
		})
	end
	local function flash(at: Vector3, size: number, tint: Color3, seconds: number)
		if size < 6 then noise("pop", at) end
		local orb = part(Enum.PartType.Ball, Vector3.one * 0.4, CFrame.new(at), WHITE)
		if orb == nil then return end
		orb.Transparency = 0.05
		fade(orb, seconds, { Size = Vector3.one * size, Transparency = 1, Color = tint })
	end
	local function sparks(at: Vector3, count: number, tint: Color3, power: number)
		noise("sparkle", at)
		burst(at, {
			texture = TEXTURES.spark, count = count, colour = sequence(WHITE, tint), size = curve(0.55, 0.35, 0),
			lifetime = { 0.45, 1 }, speed = { 6 * power, 14 * power }, drag = 3.5, acceleration = Vector3.new(0, -14, 0), spin = 200,
		})
	end
	local function dust(at: Vector3, count: number, size: number)
		burst(at, {
			texture = TEXTURES.smoke, count = count, colour = sequence(rock.dust), size = curve(size, size * 2.6),
			transparency = curve(0.35, 0.6, 1), lifetime = { 0.9, 1.5 }, speed = { 3, 7 }, spread = 80, drag = 2.5,
			acceleration = Vector3.new(0, 1.5, 0), glow = 0, spin = 40,
		})
	end
	local function embers(at: Vector3, count: number, power: number)
		burst(at, {
			texture = TEXTURES.ember, count = count, colour = sequence(Color3.fromRGB(255, 240, 200), Color3.fromRGB(255, 150, 60), Color3.fromRGB(200, 60, 20)),
			size = curve(0.45, 0.3, 0), lifetime = { 0.8, 1.6 }, speed = { 10 * power, 22 * power }, spread = 55, drag = 1.5,
			acceleration = Vector3.new(0, -22, 0), spin = 120,
		})
	end
	local function fireball(at: Vector3, count: number, size: number, tint: Color3)
		burst(at, {
			texture = TEXTURES.fire, count = count, colour = sequence(WHITE, tint, Color3.fromRGB(255, 110, 40)), size = curve(size, size * 2.2, size * 1.6),
			transparency = curve(0.1, 0.35, 1), lifetime = { 0.45, 0.9 }, speed = { size * 3, size * 6 }, drag = 5, glow = 0.85, spin = 90,
		})
	end
	local function smokeColumn(at: Vector3, count: number, size: number, seconds: number)
		burst(at, {
			texture = TEXTURES.smoke, count = count, colour = sequence(SMOKE_DARK, SMOKE_LIGHT), size = curve(size, size * 2.4),
			transparency = curve(0.25, 0.5, 1), lifetime = { seconds * 0.7, seconds }, speed = { size * 1.4, size * 2.6 }, spread = 32,
			drag = 1.4, acceleration = Vector3.new(0, 2, 0), glow = 0, spin = 25,
		})
	end
	-- Chunks of rock (or hay) thrown out of the crater, tumbling as they fall.
	local function chunks(at: Vector3, count: number, power: number)
		noise("rubble", at)
		for _ = 1, count do
			local size = random:NextNumber(0.35, 0.75) * math.sqrt(power)
			local chunk = part(Enum.PartType.Block, Vector3.new(size, size * random:NextNumber(0.6, 1), size), CFrame.new(at), rock.colour:Lerp(rock.dust, random:NextNumber(0, 0.5)), rock.material)
			if chunk == nil then return end
			local angle = random:NextNumber(0, math.pi * 2)
			local velocity = Vector3.new(math.cos(angle) * random:NextNumber(5, 11) * power, random:NextNumber(10, 18) * math.sqrt(power), math.sin(angle) * random:NextNumber(5, 11) * power)
			local spin = Vector3.new(random:NextNumber(-12, 12), random:NextNumber(-12, 12), random:NextNumber(-12, 12))
			local duration = random:NextNumber(0.9, 1.3)
			motion(duration, function(t)
				local s = t * duration
				local position = at + velocity * s + Vector3.new(0, -30 * s * s, 0)
				chunk.CFrame = CFrame.new(position) * CFrame.Angles(spin.X * s, spin.Y * s, spin.Z * s)
				chunk.Transparency = math.clamp((t - 0.7) / 0.3, 0, 1)
			end, function() chunk:Destroy() end)
		end
	end
	-- A vertical column of light from `top` down to `bottom`.
	local function column(bottom: Vector3, height: number, width: number, tint: Color3, seconds: number, material: Enum.Material?): Part?
		noise("beam", bottom)
		local beam = part(Enum.PartType.Cylinder, Vector3.new(height, width * 0.2, width * 0.2), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), tint, material)
		if beam == nil then return nil end
		animate(beam, 0.08, { Size = Vector3.new(height, width, width) })
		task.delay(0.08, function()
			if beam.Parent then fade(beam, seconds, { Size = Vector3.new(height, width * 0.1, width * 0.1), Transparency = 1 }) end
		end)
		return beam
	end
	-- A glowing ball streaking along a curve from the sky to `target`, with a
	-- trail and fire behind it. `land` runs when it hits.
	local function streak(from: Vector3, target: Vector3, size: number, seconds: number, tint: Color3, withLight: boolean, land: () -> ())
		noise("whoosh", target)
		local ball = part(Enum.PartType.Ball, Vector3.one * size, CFrame.new(from), tint:Lerp(WHITE, 0.6))
		if ball == nil then return end
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, size * 0.45, 0)
		a.Parent = ball
		local b = Instance.new("Attachment")
		b.Position = Vector3.new(0, -size * 0.45, 0)
		b.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = a
		trail.Attachment1 = b
		trail.Color = sequence(WHITE, tint, Color3.fromRGB(255, 90, 40))
		trail.Lifetime = 0.35 + size * 0.06
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.WidthScale = curve(1, 0)
		trail.Transparency = curve(0, 1)
		trail.Parent = ball
		local fire = emitter({
			texture = TEXTURES.fire, count = 0, colour = sequence(WHITE, tint, Color3.fromRGB(255, 100, 40)), size = curve(size * 0.9, 0),
			transparency = curve(0.1, 1), lifetime = { 0.25, 0.45 }, speed = { 0.5, 1.5 }, glow = 0.9, spin = 120,
		}, a)
		fire.Rate = 30 + size * 20
		fire.Enabled = true
		if withLight then light(ball, tint, 10 + size * 4, 3, seconds + 0.3) end
		local bend = (from + target) / 2 + Vector3.new(0, (from - target).Magnitude * 0.12, 0)
		motion(seconds, function(t)
			local u = t * t
			local position = from * ((1 - u) ^ 2) + bend * (2 * (1 - u) * u) + target * (u * u)
			ball.CFrame = CFrame.new(position)
		end, function()
			ball:Destroy()
			land()
		end)
	end
	local function skyPoint(at: Vector3, height: number, reach: number): Vector3
		local angle = random:NextNumber(0, math.pi * 2)
		return at + Vector3.new(math.cos(angle) * reach, height, math.sin(angle) * reach)
	end

	-- Where the rock surface is under a point (glowing veins and cracks lie on it).
	local mountain = workspace:FindFirstChild("Mountain", true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if mountain then { mountain } else {}
	local function surface(at: Vector3): Vector3?
		if mountain == nil then return nil end
		local hit = workspace:Raycast(at + Vector3.new(0, 100, 0), Vector3.new(0, -220, 0), params)
		return if hit then hit.Position + hit.Normal * 0.09 else nil
	end
	-- A craggy lump of rock (or hay): one block, or three for big ones, moved together.
	local LUMP_PIECES = {
		{ Vector3.new(1, 0.8, 0.9), CFrame.identity },
		{ Vector3.new(0.7, 0.6, 0.75), CFrame.new(0.25, 0.2, -0.1) * CFrame.Angles(0.5, 0.3, 0.2) },
		{ Vector3.new(0.6, 0.55, 0.6), CFrame.new(-0.25, -0.1, 0.2) * CFrame.Angles(-0.3, 0.8, 0.4) },
	}
	local function lump(size: number, frame: CFrame): Lump?
		local rocks: Lump = { parts = {}, offsets = {} }
		for index, piece in LUMP_PIECES do
			if index > 1 and size < 1.4 then break end
			local offset = CFrame.new(piece[2].Position * size) * piece[2].Rotation
			local chunk = part(Enum.PartType.Block, piece[1] * size, frame * offset, rock.colour:Lerp(rock.dust, random:NextNumber(0, 0.4)), rock.material)
			if chunk == nil then break end
			table.insert(rocks.parts, chunk)
			table.insert(rocks.offsets, offset)
		end
		return if #rocks.parts > 0 then rocks else nil
	end
	local function place(rocks: Lump, frame: CFrame)
		for index, chunk in rocks.parts do chunk.CFrame = frame * rocks.offsets[index] end
	end
	local function vanish(rocks: Lump)
		for _, chunk in rocks.parts do chunk:Destroy() end
	end
	-- Green motes rising where rock has landed.
	local function motes(at: Vector3, count: number, power: number)
		burst(at, {
			texture = TEXTURES.spark, count = count, colour = sequence(WHITE, colour), size = curve(0.5, 0.3, 0),
			lifetime = { 0.8, 1.5 }, speed = { 3 * power, 9 * power }, spread = 45, drag = 1.5, acceleration = Vector3.new(0, 4, 0), spin = 120,
		})
	end
	-- Rock arriving at `at`: a puff of dust, a green glint and a small ring.
	local function settle(at: Vector3, power: number)
		dust(at, math.ceil(2 * power), 0.6 * power)
		motes(at, math.ceil(5 * power), 0.7)
		shockwave(at, 2.5 * power, colour, 0.4)
	end
	-- Glowing veins along the rock from `radius` out, racing in to the centre
	-- (inward) or out from it.
	local function veins(origin: Vector3, branches: number, radius: number, inward: boolean, width: number, seconds: number)
		noise("zap", origin)
		local rotation = random:NextNumber(0, math.pi * 2)
		for branch = 1, branches do
			local angle = rotation + branch * math.pi * 2 / branches
			local previous = origin
			for step = 1, 3 do
				local bend = angle + random:NextNumber(-0.3, 0.3)
				local flatTarget = centre + Vector3.new(math.cos(bend), 0, math.sin(bend)) * radius * step / 3
				local target = surface(flatTarget) or Vector3.new(flatTarget.X, origin.Y, flatTarget.Z)
				local start = previous
				previous = target
				local delta = target - start
				if delta.Magnitude < 0.05 or delta.Magnitude > radius * 0.6 then continue end
				local delay = (if inward then 3 - step else step - 1) * seconds / 3 + branch * 0.015
				after(delay, function()
					local frame = if inward then CFrame.lookAt(target, start) else CFrame.lookAt(start, target)
					local vein = part(Enum.PartType.Block, Vector3.new(width, width, 0.05), frame, colour)
					if vein == nil then return end
					animate(vein, seconds / 3, { Size = Vector3.new(width, width, delta.Magnitude), CFrame = frame * CFrame.new(0, 0, -delta.Magnitude / 2) }, Enum.EasingStyle.Linear)
					task.delay(seconds + 0.25 - delay, function()
						if vein.Parent then fade(vein, 0.3, { Color = WHITE, Transparency = 1 }) end
					end)
				end)
			end
		end
	end
	local function towards(a: Vector3, b: Vector3, t: number): Vector3
		return a + (b - a) * t
	end

	if data.adding then
		-- Rock coming back.
		local summit = surface(centre) or centre
		if tier == 1 then
			-- PEBBLE DROP: pebbles fall onto the peak, each with a puff of dust.
			light(point(summit + Vector3.new(0, 2, 0), 1), colour, 10, 2, 0.8)
			for i = 1, 5 do
				after((i - 1) * 0.08, function()
					local angle = random:NextNumber(0, math.pi * 2)
					local landing = summit + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(0, 2.5)
					local from = landing + Vector3.new(0, random:NextNumber(9, 12), 0)
					local rocks = lump(random:NextNumber(0.5, 0.8), CFrame.new(from))
					if rocks == nil then return end
					local spin = random:NextNumber(4, 9)
					motion(0.45, function(t)
						place(rocks, CFrame.new(towards(from, landing, t * t)) * CFrame.Angles(spin * t, spin * t * 0.6, 0))
					end, function()
						vanish(rocks)
						settle(landing, 1)
					end)
				end)
			end
			after(0.55, function() shockwave(summit, 5, colour, 0.5) end)
		elseif tier == 2 then
			-- ROCKSLIDE: a ring of rocks rises out of the slopes and tumbles in.
			light(point(summit + Vector3.new(0, 2, 0), 1.4), colour, 16, 3, 1.2)
			local rotation = random:NextNumber(0, math.pi * 2)
			for i = 1, 10 do
				local angle = rotation + i * math.pi / 5
				local flat = summit + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 9
				local rise = (surface(flat) or (flat - Vector3.new(0, 4, 0)))
				local rocks = lump(random:NextNumber(0.7, 1.1), CFrame.new(rise))
				if rocks == nil then break end
				dust(rise, 2, 0.8)
				local lifted = rise + Vector3.new(0, 3, 0)
				local spin = random:NextNumber(5, 10)
				motion(0.35, function(t)
					place(rocks, CFrame.new(towards(rise, lifted, 1 - (1 - t) ^ 3)) * CFrame.Angles(0, t * 2, 0))
				end)
				after(0.35 + i * 0.03, function()
					local apex = towards(lifted, summit, 0.5) + Vector3.new(0, 3, 0)
					motion(0.45, function(t)
						local u = t * t
						local position = lifted * ((1 - u) ^ 2) + apex * (2 * (1 - u) * u) + summit * (u * u)
						place(rocks, CFrame.new(position) * CFrame.Angles(spin * t, 2 + spin * t * 0.5, 0))
					end, function()
						vanish(rocks)
						settle(summit, 0.8)
					end)
				end)
			end
			after(0.95, function()
				shockwave(summit, 11, colour, 0.6)
				motes(summit, 20, 1)
				addShake(0.35)
			end)
		elseif tier == 3 then
			-- STONE SURGE: green veins race in from all round, stone pillars
			-- thrust up in a ring, lean in and sink into the peak.
			veins(summit, 6, 11, true, 0.14, 0.5)
			light(point(summit + Vector3.new(0, 2, 0), 1.6), colour, 14, 2, 1.4)
			after(0.5, function()
				local rotation = random:NextNumber(0, math.pi * 2)
				for i = 1, 6 do
					local angle = rotation + i * math.pi / 3
					local flat = summit + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 4.5
					local base = surface(flat) or (flat - Vector3.new(0, 1, 0))
					local height = random:NextNumber(4, 6)
					local column = part(Enum.PartType.Cylinder, Vector3.new(0.1, 1.5, 1.5), CFrame.new(base) * CFrame.Angles(0, 0, math.pi / 2), rock.colour, rock.material)
					if column == nil then break end
					dust(base, 2, 1)
					animate(column, 0.22, { Size = Vector3.new(height, 1.5, 1.5), CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, Enum.EasingStyle.Back)
					after(0.5, function()
						-- Lean the top in towards the peak while sliding into it.
						local top = base + Vector3.new(0, height / 2, 0)
						local inward = Vector3.new(summit.X - base.X, 0, summit.Z - base.Z).Unit
						local axis = Vector3.new(0, 1, 0):Cross(inward)
						motion(0.3, function(t)
							local position = towards(top, summit + Vector3.new(0, 0.5, 0), t * t)
							column.CFrame = CFrame.new(position) * CFrame.fromAxisAngle(axis, 1.1 * t) * CFrame.Angles(0, 0, math.pi / 2)
							column.Size = Vector3.new(height * (1 - 0.7 * t), 1.5 * (1 - 0.5 * t), 1.5 * (1 - 0.5 * t))
						end, function() column:Destroy() end)
					end)
				end
			end)
			after(1.32, function()
				flash(summit + Vector3.new(0, 1, 0), 8, colour, 0.35)
				shockwave(summit, 14, colour, 0.6)
				dust(summit, 12, 1.5)
				motes(summit, 30, 1.2)
				addShake(0.5)
			end)
		elseif tier == 4 then
			-- BOULDER BARRAGE: a dozen boulders hurled in from far away crash home
			-- one after another, trailing dust, then the peak heaves with a ring
			-- of light.
			local rotation = random:NextNumber(0, math.pi * 2)
			light(point(summit + Vector3.new(0, 4, 0), 3.6), colour, 20, 1.5, 3.4)
			for i = 1, 12 do
				after((i - 1) * 0.22, function()
					local angle = rotation + i * 1.1
					local from = summit + Vector3.new(math.cos(angle) * 75, random:NextNumber(4, 12), math.sin(angle) * 75)
					local landing = summit + Vector3.new(random:NextNumber(-5, 5), 0, random:NextNumber(-5, 5))
					landing = surface(landing) or landing
					local apex = towards(from, landing, 0.5) + Vector3.new(0, random:NextNumber(28, 42), 0)
					local rocks = lump(random:NextNumber(1.6, 2.3), CFrame.new(from))
					if rocks == nil then return end
					noise("whoosh", landing)
					local trail = Instance.new("Attachment")
					trail.Parent = rocks.parts[1]
					local dustTrail = emitter({
						texture = TEXTURES.smoke, count = 0, colour = sequence(rock.dust), size = curve(1.2, 2.6), transparency = curve(0.4, 1),
						lifetime = { 0.5, 0.8 }, speed = { 0.2, 0.8 }, glow = 0, spin = 40,
					}, trail)
					dustTrail.Rate = 30
					dustTrail.Enabled = true
					local spin = random:NextNumber(3, 6)
					motion(0.95, function(t)
						local position = from * ((1 - t) ^ 2) + apex * (2 * (1 - t) * t) + landing * (t * t)
						place(rocks, CFrame.new(position) * CFrame.Angles(spin * t, spin * t * 0.7, spin * t * 0.3))
					end, function()
						vanish(rocks)
						settle(landing, 1.6)
						chunks(landing, 1, 0.8)
						addShake(0.35)
					end)
				end)
			end
			after(3.45, function()
				flash(summit + Vector3.new(0, 1, 0), 12, colour, 0.4)
				grade({ Brightness = 0.15, Contrast = 0.08, TintColor = colour:Lerp(WHITE, 0.7) }, 0.05, 0.1, 0.5)
				addShake(0.8)
				shockwave(summit, 20, colour, 0.75)
				after(0.12, function() shockwave(summit, 13, WHITE, 0.6) end)
				column(summit, 40, 3, colour, 0.8)
				motes(summit, 50, 1.5)
				dust(summit, 12, 2)
				light(point(summit + Vector3.new(0, 3, 0), 1.3), colour, 24, 3, 1.1)
			end)
		elseif tier == 5 then
			-- STONE CYCLONE: rocks from the valley spiral up into a towering,
			-- whirling cyclone over the peak with a pulsing green core, then
			-- slam down into it, and the peak blasts out a second ring.
			light(point(summit + Vector3.new(0, 10, 0), 4.4), colour, 28, 3, 4.2)
			local count = 32
			local spinUp = 3.2
			local stones: { Lump } = {}
			local seeds: { { number } } = {}
			for i = 1, count do
				local angle = i / count * math.pi * 2
				local reach = random:NextNumber(22, 34)
				local rocks = lump(random:NextNumber(0.6, 1.2), CFrame.new(summit))
				if rocks == nil then break end
				table.insert(stones, rocks)
				-- angle, reach, start height, end height, end reach, spin speed
				table.insert(seeds, { angle, reach, summit.Y - random:NextNumber(8, 14), summit.Y + 7 + (i % 8) * 2.4, 2.5 + (i % 5) * 1.3, 4 + (i % 3) })
			end
			local whirl: { Attachment } = {}
			for i = 1, 4 do
				local spot = point(summit, spinUp + 0.8)
				local cloud = emitter({
					texture = TEXTURES.smoke, count = 0, colour = sequence(rock.dust, colour:Lerp(rock.dust, 0.6)), size = curve(1.5, 3.8),
					transparency = curve(0.45, 1), lifetime = { 0.6, 1 }, speed = { 0.5, 1.5 }, glow = 0, spin = 60,
				}, spot)
				cloud.Rate = 24
				cloud.Enabled = true
				table.insert(whirl, spot)
			end
			-- The eye of the storm pulses brighter as it spins up.
			local eye = part(Enum.PartType.Cylinder, Vector3.new(26, 0.8, 0.8), CFrame.new(summit + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.pi / 2), colour, Enum.Material.ForceField)
			local positions: { Vector3 } = {}
			motion(spinUp, function(t)
				local ease = 1 - (1 - t) ^ 2
				for i, rocks in stones do
					local seed = seeds[i]
					local angle = seed[1] + t * seed[6] * 4
					local reach = seed[2] + (seed[5] - seed[2]) * ease
					local position = Vector3.new(summit.X + math.cos(angle) * reach, seed[3] + (seed[4] - seed[3]) * ease, summit.Z + math.sin(angle) * reach)
					positions[i] = position
					place(rocks, CFrame.new(position) * CFrame.Angles(angle * 2, angle, 0))
				end
				for i, spot in whirl do
					local angle = t * 16 + i * math.pi / 2
					spot.Position = summit + Vector3.new(math.cos(angle) * 4.5, 4 + i * 3 + t * 6, math.sin(angle) * 4.5)
				end
				if eye then
					local pulse = 0.8 + t * 2.4 + math.sin(t * 40) * 0.3
					eye.Size = Vector3.new(26, pulse, pulse)
				end
			end, function()
				if eye then fade(eye, 0.2, { Size = Vector3.new(26, 0.1, 0.1), Transparency = 1 }) end
				for i, rocks in stones do
					local from = positions[i] or summit
					local delay = (i % 6) * 0.03
					after(delay, function()
						motion(0.3, function(t)
							place(rocks, CFrame.new(towards(from, summit, t * t)) * CFrame.Angles(t * 6, t * 3, 0))
						end, function() vanish(rocks) end)
					end)
				end
			end)
			after(spinUp + 0.38, function()
				flash(summit + Vector3.new(0, 1, 0), 16, colour, 0.45)
				grade({ Brightness = 0.22, Contrast = 0.12, TintColor = colour:Lerp(WHITE, 0.65) }, 0.05, 0.12, 0.6)
				addShake(1.1)
				shockwave(summit, 24, colour, 0.8)
				after(0.1, function() shockwave(summit, 16, WHITE, 0.6) end)
				dust(summit, 18, 2.4)
				motes(summit, 50, 1.6)
			end)
			after(spinUp + 1.1, function()
				shockwave(summit, 32, colour:Lerp(rock.dust, 0.3), 1)
				column(summit, 50, 3.5, colour, 0.9)
				motes(summit, 40, 2)
				addShake(0.6)
			end)
		else
			-- MOUNTAIN RISING: the sky turns, the ground rumbles and green light
			-- cracks outward, a colossal boulder descends slowly, pulling rock
			-- up from all round, lands on the peak with a blast of light, and a
			-- ring of green pillars erupts round the mountain.
			local descent = 2.8
			noise("rumble", summit)
			after(1.2, function() noise("rumble", summit) end)
			after(descent - 0.5, function() noise("deepWhoosh", summit) end)
			grade({ Brightness = -0.12, Contrast = 0.2, Saturation = -0.05, TintColor = Color3.fromRGB(205, 255, 220) }, 0.6, 3.4, 1.4)
			for i = 0, 9 do
				after(i * 0.3, function() addShake(0.45) end)
			end
			veins(summit, 8, 20, false, 0.2, 1.2)
			local sky = summit + Vector3.new(0, 85, 0)
			local land = summit + Vector3.new(0, 5, 0)
			local colossus = lump(9, CFrame.new(sky))
			local carried = Vector3.zero
			if colossus then
				local core = colossus.parts[1]
				light(core, colour, 40, 4, descent + 0.8)
				local halo = Instance.new("Attachment")
				halo.Parent = core
				local rings = emitter({
					texture = TEXTURES.ring, count = 0, colour = sequence(WHITE, colour), size = curve(9, 18),
					transparency = curve(0.3, 1), lifetime = { 0.6, 0.6 }, speed = { 0.01, 0.01 }, spread = 0, flat = true,
				}, halo)
				rings.Rate = 5
				rings.Enabled = true
				motion(descent, function(t)
					local u = t * t * (3 - 2 * t)
					carried = towards(sky, land, u)
					place(colossus, CFrame.new(carried) * CFrame.Angles(0.15, t * 2.4, 0.1))
				end)
				after(0.4, function()
					-- Rock is pulled up off the slopes into it.
					for i = 1, 26 do
						local angle = i / 26 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
						local flat = summit + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(18, 32)
						local from = surface(flat) or (flat - Vector3.new(0, 8, 0))
						local rocks = lump(random:NextNumber(0.7, 1.3), CFrame.new(from))
						if rocks == nil then break end
						if i % 3 == 0 then dust(from, 2, 1) end
						local spin = random:NextNumber(4, 8)
						after(i * 0.06, function()
							motion(1.4, function(t)
								local target = if carried.Magnitude > 0 then carried else land
								place(rocks, CFrame.new(towards(from, target, t * t) + Vector3.new(0, math.sin(t * math.pi) * 8, 0)) * CFrame.Angles(spin * t, spin * t, 0))
							end, function()
								vanish(rocks)
								motes(carried, 3, 0.6)
							end)
						end)
					end
				end)
			end
			after(descent + 0.02, function()
				if colossus then
					for _, chunk in colossus.parts do fade(chunk, 0.12, { Size = chunk.Size * 0.6, Transparency = 1 }) end
				end
				grade({ Brightness = 0.45, Contrast = 0.12, TintColor = Color3.fromRGB(230, 255, 236) }, 0.04, 0.1, 0.7)
				addShake(1.5)
				flash(summit + Vector3.new(0, 2, 0), 28, colour, 0.55)
				shockwave(summit, 32, colour, 0.9)
				after(0.12, function() shockwave(summit, 22, WHITE, 0.7) end)
				after(0.3, function() shockwave(summit, 44, colour:Lerp(rock.dust, 0.4), 1.1) end)
				dust(summit, 24, 3.5)
				motes(summit, 60, 2)
				column(summit, 90, 6, colour, 1.6)
				chunks(summit, 10, 1.6)
				light(point(summit + Vector3.new(0, 4, 0), 1.8), colour, 36, 4, 1.6)
			end)
			-- Aftershock: green pillars burst up in a ring round the mountain,
			-- one after another, then the whole peak pulses once more.
			local ringTurn = random:NextNumber(0, math.pi * 2)
			for i = 1, 8 do
				after(descent + 0.5 + i * 0.16, function()
					local angle = ringTurn + i * math.pi / 4
					local flat = summit + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 16
					local foot = surface(flat) or (flat - Vector3.new(0, 6, 0))
					column(foot, 34, 2.2, colour, 0.9)
					settle(foot, 1.5)
					addShake(0.4)
				end)
			end
			after(descent + 2.2, function()
				flash(summit + Vector3.new(0, 2, 0), 18, colour, 0.5)
				shockwave(summit, 50, colour, 1.2)
				after(0.15, function() shockwave(summit, 36, WHITE, 0.9) end)
				motes(summit, 70, 2.4)
				grade({ Brightness = 0.25, Contrast = 0.08, TintColor = Color3.fromRGB(225, 255, 235) }, 0.05, 0.1, 0.8)
				addShake(0.9)
			end)
		end
	elseif tier == 1 then
		-- SPARK BURST: a crisp golden pop, sparks and a puff of dust.
		flash(centre, 3, colour, 0.25)
		light(point(centre + Vector3.new(0, 2, 0), 0.6), colour, 10, 2, 0.4)
		sparks(centre, 22, colour, 0.9)
		dust(centre, 5, 1)
		shockwave(centre, 5, colour, 0.45)
		chunks(centre, 3, 0.8)
	elseif tier == 2 then
		-- SHOCKWAVE: a double ring tears across the ground, rock and sparks fly.
		flash(centre, 5, colour, 0.3)
		light(point(centre + Vector3.new(0, 2, 0), 0.8), colour, 16, 3, 0.6)
		shockwave(centre, 12, colour, 0.6)
		after(0.09, function() shockwave(centre, 8, WHITE, 0.5) end)
		sparks(centre, 30, colour, 1.2)
		embers(centre, 10, 0.8)
		dust(centre, 12, 1.4)
		chunks(centre, 7, 1)
		addShake(0.35)
	elseif tier == 3 then
		-- DIAMOND FRACTURE: glowing cracks race over the rock, crystals burst up
		-- out of them, then shatter into glittering shards.
		local origin = surface(centre) or centre
		local radius = 7 + math.clamp((data.coins - 100) / 399, 0, 1) * 5
		local rotation = random:NextNumber(0, math.pi * 2)
		local tips: { Vector3 } = {}
		for branch = 1, 6 do
			local angle = rotation + branch * math.pi / 3
			local previous = origin
			for step = 1, 3 do
				local bend = angle + random:NextNumber(-0.3, 0.3)
				local flatTarget = centre + Vector3.new(math.cos(bend), 0, math.sin(bend)) * radius * step / 3
				local target = surface(flatTarget) or Vector3.new(flatTarget.X, origin.Y, flatTarget.Z)
				local start = previous
				previous = target
				local delta = target - start
				-- No glowing bridges across a dug-out gap.
				if delta.Magnitude < 0.05 or delta.Magnitude > 6 then continue end
				if step == 3 then table.insert(tips, target) end
				after((step - 1) * 0.12 + branch * 0.02, function()
					local frame = CFrame.lookAt(start, target)
					local crack = part(Enum.PartType.Block, Vector3.new(0.12, 0.12, 0.05), frame, colour)
					if crack == nil then return end
					animate(crack, 0.14, { Size = Vector3.new(0.14, 0.14, delta.Magnitude), CFrame = frame * CFrame.new(0, 0, -delta.Magnitude / 2) }, Enum.EasingStyle.Linear)
					task.delay(0.62 - (step - 1) * 0.12, function()
						if crack.Parent then fade(crack, 0.25, { Color = WHITE, Transparency = 1, Size = Vector3.new(0.3, 0.3, delta.Magnitude) }) end
					end)
				end)
			end
		end
		light(point(origin + Vector3.new(0, 2, 0), 1.2), colour, 12, 1.5, 0.9)
		burst(origin, {
			texture = TEXTURES.glow, count = 2, colour = sequence(colour), size = curve(1, radius * 0.9), transparency = curve(0.5, 1),
			lifetime = { 0.7, 0.7 }, speed = { 0.01, 0.01 }, spread = 0,
		})
		-- Crystals grow out of the crack tips and the centre.
		after(0.62, function()
			table.insert(tips, origin)
			local crystals: { Part } = {}
			for index, tip in tips do
				local height = if index == #tips then 4.2 else random:NextNumber(2, 3.2)
				local tilt = CFrame.Angles(random:NextNumber(-0.35, 0.35), random:NextNumber(0, math.pi), random:NextNumber(-0.35, 0.35))
				local base = CFrame.new(tip) * tilt * CFrame.Angles(0, math.pi / 4, 0)
				local crystal = part(Enum.PartType.Block, Vector3.new(0.7, 0.1, 0.7), base, colour:Lerp(WHITE, 0.35), Enum.Material.Glass)
				if crystal == nil then break end
				crystal.Transparency = 0.25
				crystal.Reflectance = 0.25
				table.insert(crystals, crystal)
				animate(crystal, 0.16, { Size = Vector3.new(0.7, height, 0.7), CFrame = base * CFrame.new(0, height / 2, 0) }, Enum.EasingStyle.Back)
			end
			-- Then they shatter.
			after(0.42, function()
				noise("shatter", origin)
				flash(origin + Vector3.new(0, 1.5, 0), radius * 0.9, colour, 0.35)
				shockwave(origin, radius * 1.4, colour, 0.6)
				sparks(origin + Vector3.new(0, 1.5, 0), 45, colour, 1.3)
				addShake(0.5)
				for _, crystal in crystals do
					local from = crystal.CFrame
					local fromSize = crystal.Size
					local away = Vector3.new(from.Position.X - origin.X, 0, from.Position.Z - origin.Z)
					if away.Magnitude < 0.1 then away = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) end
					local velocity = away.Unit * random:NextNumber(6, 12) + Vector3.new(0, random:NextNumber(8, 14), 0)
					local spin = random:NextNumber(6, 14)
					motion(0.9, function(t)
						local s = t * 0.9
						crystal.CFrame = CFrame.new(from.Position + velocity * s + Vector3.new(0, -26 * s * s, 0)) * from.Rotation * CFrame.Angles(spin * s, spin * s * 0.6, 0)
						crystal.Size = fromSize:Lerp(Vector3.new(0.3, 0.6, 0.3), t)
						crystal.Transparency = 0.25 + 0.75 * t * t
					end, function() crystal:Destroy() end)
				end
			end)
		end)
	elseif tier == 4 then
		-- ORBITAL STRIKE: a target ring locks on while a charge gathers high in
		-- the sky, a beam slams down and the ground erupts, then a barrage of
		-- strikes walks round the crater and a last, wider beam finishes it.
		burst(centre + Vector3.new(0, 0.3, 0), {
			texture = TEXTURES.ring, count = 1, colour = sequence(colour), size = curve(16, 3), transparency = curve(0.6, 0.1),
			lifetime = { 0.65, 0.65 }, speed = { 0.01, 0.01 }, spread = 0, flat = true,
		})
		local marks: { Part } = {}
		for _ = 1, 4 do
			local mark = part(Enum.PartType.Block, Vector3.new(0.25, 0.12, 1.6), CFrame.new(centre), colour)
			if mark then table.insert(marks, mark) end
		end
		motion(0.65, function(t)
			local reach = 8 - 5.5 * t * t
			for i, mark in marks do
				local angle = i * math.pi / 2 + t * 2.2
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				mark.CFrame = CFrame.lookAt(centre + direction * reach + Vector3.new(0, 0.3, 0), centre + Vector3.new(0, 0.3, 0))
			end
		end, function()
			for _, mark in marks do fade(mark, 0.15, { Transparency = 1 }) end
		end)
		local sky = centre + Vector3.new(0, 70, 0)
		local charge = part(Enum.PartType.Ball, Vector3.one * 0.3, CFrame.new(sky), colour:Lerp(WHITE, 0.5))
		if charge then
			animate(charge, 0.6, { Size = Vector3.one * 4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			light(charge, colour, 30, 4, 1.2)
			burst(sky, {
				texture = TEXTURES.glow, count = 3, colour = sequence(colour, WHITE), size = curve(12, 2), transparency = curve(0.7, 0.2),
				lifetime = { 0.6, 0.6 }, speed = { 0.01, 0.01 }, spread = 0,
			})
		end
		after(0.65, function()
			if charge then fade(charge, 0.2, { Size = Vector3.one * 0.5, Transparency = 1 }) end
			column(centre, 70, 3.2, WHITE, 0.55)
			column(centre, 70, 7, colour, 0.7, Enum.Material.ForceField)
			flash(centre, 9, colour, 0.35)
			grade({ Brightness = 0.25, Contrast = 0.1, TintColor = colour:Lerp(WHITE, 0.7) }, 0.04, 0.05, 0.45)
			addShake(0.8)
			fireball(centre, 22, 2, colour)
			smokeColumn(centre, 10, 2.5, 3)
			embers(centre, 30, 1.1)
			shockwave(centre, 20, colour, 0.7)
			after(0.12, function() shockwave(centre, 13, WHITE, 0.55) end)
			chunks(centre, 8, 1.4)
			light(point(centre + Vector3.new(0, 3, 0), 1.2), colour, 26, 4, 1)
		end)
		-- The barrage: four more strikes walk round the crater.
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 1, 4 do
			local angle = turn + i * math.pi / 2 + random:NextNumber(-0.3, 0.3)
			local spot = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(6, 10)
			spot = surface(spot) or spot
			after(1.0 + i * 0.5, function()
				burst(spot + Vector3.new(0, 0.3, 0), {
					texture = TEXTURES.ring, count = 1, colour = sequence(colour), size = curve(7, 1.5), transparency = curve(0.6, 0.1),
					lifetime = { 0.3, 0.3 }, speed = { 0.01, 0.01 }, spread = 0, flat = true,
				})
			end)
			after(1.3 + i * 0.5, function()
				column(spot, 70, 1.8, WHITE, 0.4)
				column(spot, 70, 4, colour, 0.5, Enum.Material.ForceField)
				flash(spot, 5, colour, 0.3)
				fireball(spot, 10, 1.4, colour)
				sparks(spot, 16, colour, 1.1)
				shockwave(spot, 10, colour, 0.55)
				chunks(spot, 3, 1)
				addShake(0.5)
			end)
		end
		-- The last word: a wider beam and three rings.
		after(3.6, function()
			column(centre, 80, 5, WHITE, 0.7)
			column(centre, 80, 11, colour, 0.9, Enum.Material.ForceField)
			flash(centre, 14, colour, 0.45)
			grade({ Brightness = 0.32, Contrast = 0.12, TintColor = colour:Lerp(WHITE, 0.65) }, 0.04, 0.1, 0.6)
			addShake(1.1)
			fireball(centre, 26, 2.6, colour)
			smokeColumn(centre, 14, 3, 3.4)
			embers(centre, 40, 1.3)
			shockwave(centre, 26, colour, 0.8)
			after(0.12, function() shockwave(centre, 18, WHITE, 0.6) end)
			after(0.3, function() shockwave(centre, 34, Color3.fromRGB(255, 150, 70), 1) end)
			chunks(centre, 8, 1.6)
			light(point(centre + Vector3.new(0, 3, 0), 1.5), colour, 32, 4, 1.3)
		end)
	elseif tier == 5 then
		-- GALAXY COLLAPSE: a black hole opens over the rock with a spinning
		-- ring of stars, pulls in light from all round, then goes nova. The
		-- stars fling out in spiral arms, the hole flickers back for a second
		-- pulse, and a beam of starlight drives into the mountain.
		local core = centre + Vector3.new(0, 11, 0)
		local gather = 1.8
		noise("deepWhoosh", core)
		after(0.9, function() noise("deepWhoosh", core) end)
		local hole = part(Enum.PartType.Ball, Vector3.one * 0.2, CFrame.new(core), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		local halo = part(Enum.PartType.Ball, Vector3.one * 0.3, CFrame.new(core), colour)
		if hole then animate(hole, 0.8, { Size = Vector3.one * 3.8 }, Enum.EasingStyle.Back) end
		if halo then
			halo.Transparency = 0.55
			animate(halo, 0.8, { Size = Vector3.one * 6 }, Enum.EasingStyle.Back)
			light(halo, colour, 26, 3, gather + 0.3)
		end
		grade({ Brightness = -0.08, Contrast = 0.15, Saturation = 0.15, TintColor = Color3.fromRGB(225, 210, 255) }, 0.5, gather - 0.5, 0.4)
		-- The accretion ring: stars with short trails orbiting on a tilted plane.
		local function star(size: number, at: CFrame, tint: Color3): Part?
			local ball = part(Enum.PartType.Ball, Vector3.one * size, at, tint)
			if ball == nil then return nil end
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(0, 0.2, 0)
			a.Parent = ball
			local b = Instance.new("Attachment")
			b.Position = Vector3.new(0, -0.2, 0)
			b.Parent = ball
			local trail = Instance.new("Trail")
			trail.Attachment0 = a
			trail.Attachment1 = b
			trail.Color = sequence(WHITE, tint)
			trail.Lifetime = 0.3
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.WidthScale = curve(1, 0)
			trail.Transparency = curve(0.1, 1)
			trail.Parent = ball
			return ball
		end
		local function starColour(i: number): Color3
			return (if i % 3 == 0 then PINK elseif i % 3 == 1 then colour else Color3.fromRGB(120, 170, 255)):Lerp(WHITE, 0.3)
		end
		local stars: { Part } = {}
		local tilt = CFrame.new(core) * CFrame.Angles(math.rad(18), random:NextNumber(0, math.pi), math.rad(-10))
		for i = 1, 24 do
			local ball = star(random:NextNumber(0.3, 0.6), tilt, starColour(i))
			if ball == nil then break end
			table.insert(stars, ball)
		end
		local phases: { number } = {}
		local orbits: { number } = {}
		for i = 1, #stars do
			phases[i] = i / #stars * math.pi * 2
			orbits[i] = random:NextNumber(4.5, 9)
		end
		motion(gather, function(t)
			for i, ball in stars do
				local spin = phases[i] + t * (9 + 4 / orbits[i] * 9)
				local reach = orbits[i] * (1 - 0.5 * t * t)
				ball.CFrame = tilt * CFrame.new(math.cos(spin) * reach, math.sin(spin * 3 + i) * 0.25, math.sin(spin) * reach)
			end
		end)
		-- Light pulled in from a sphere round the hole.
		local well = part(Enum.PartType.Ball, Vector3.one * 30, CFrame.new(core), WHITE)
		if well then
			well.Transparency = 1
			local inward = emitter({
				texture = TEXTURES.spark, count = 0, colour = sequence(WHITE, colour, PINK), size = curve(0.2, 0.6, 0.1),
				transparency = curve(0.6, 0, 0.4), lifetime = { 0.45, 0.45 }, speed = { 30, 32 }, spread = 0, spin = 180,
			}, well)
			inward.Shape = Enum.ParticleEmitterShape.Sphere
			inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
			inward.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			inward.Rate = 120
			inward.Enabled = true
			after(gather - 0.1, function() inward.Enabled = false end)
		end
		for i = 1, 3 do
			after(i * 0.45, function() addShake(0.25 + i * 0.1) end)
		end
		-- Collapse, then nova.
		after(gather, function()
			if hole then fade(hole, 0.12, { Size = Vector3.one * 0.1 }) end
			if halo then fade(halo, 0.12, { Size = Vector3.one * 0.1, Transparency = 1 }) end
			for _, ball in stars do fade(ball, 0.12, { Size = Vector3.one * 0.05 }) end
		end)
		after(gather + 0.13, function()
			flash(core, 18, colour, 0.5)
			grade({ Brightness = 0.32, Contrast = 0.15, Saturation = 0.2, TintColor = colour:Lerp(WHITE, 0.6) }, 0.05, 0.1, 0.6)
			addShake(1)
			shockwave(core, 26, colour, 0.8)
			after(0.1, function() shockwave(core, 18, PINK, 0.7) end)
			burst(core, {
				texture = TEXTURES.spark, count = 70, colour = sequence(WHITE, colour, PINK), size = curve(0.7, 0.45, 0),
				lifetime = { 0.7, 1.4 }, speed = { 14, 30 }, drag = 3, spin = 200,
			})
			column(centre, 11, 2.6, colour, 0.45)
			shockwave(centre, 22, colour, 0.7)
			dust(centre, 14, 2)
			fireball(centre, 14, 1.6, colour)
			chunks(centre, 8, 1.4)
			light(point(core, 1.6), colour, 30, 4, 1.4)
			-- Spiral arms: new stars fling out from the core and fade.
			for i = 1, 18 do
				local arm = (i % 2) * math.pi
				local ball = star(random:NextNumber(0.35, 0.7), CFrame.new(core), starColour(i))
				if ball == nil then break end
				local reachOut = 8 + (i // 2) * 2.2
				local twist = random:NextNumber(2.2, 3)
				motion(1.6, function(t)
					local ease = 1 - (1 - t) ^ 3
					local angle = arm + ease * twist + (i // 2) * 0.12
					ball.CFrame = tilt * CFrame.new(math.cos(angle) * reachOut * ease, math.sin(i + t * 4) * 0.6, math.sin(angle) * reachOut * ease)
					ball.Transparency = math.clamp((t - 0.6) / 0.4, 0, 1)
				end, function() ball:Destroy() end)
			end
		end)
		-- The second pulse: the hole flickers back, then starlight pours down.
		local pulseAt = gather + 1.6
		after(pulseAt, function()
			flash(core, 9, PINK, 0.4)
			shockwave(core, 20, PINK, 0.7)
			after(0.1, function() shockwave(core, 14, colour, 0.6) end)
			addShake(0.6)
		end)
		after(pulseAt + 0.4, function()
			column(centre, 60, 3.4, WHITE, 0.6)
			column(centre, 60, 7.5, colour, 0.8, Enum.Material.ForceField)
			burst(core + Vector3.new(0, 6, 0), {
				texture = TEXTURES.spark, count = 60, colour = sequence(WHITE, PINK, colour), size = curve(0.6, 0.4, 0),
				lifetime = { 1, 1.8 }, speed = { 4, 12 }, spread = 70, drag = 1, acceleration = Vector3.new(0, -18, 0), spin = 160,
			})
			flash(centre, 14, colour, 0.45)
			grade({ Brightness = 0.28, Contrast = 0.12, Saturation = 0.2, TintColor = colour:Lerp(WHITE, 0.6) }, 0.04, 0.1, 0.7)
			addShake(1.1)
			shockwave(centre, 30, colour, 0.9)
			after(0.12, function() shockwave(centre, 20, WHITE, 0.7) end)
			after(0.3, function() shockwave(centre, 38, PINK, 1.1) end)
			fireball(centre, 20, 2, colour)
			dust(centre, 18, 2.4)
			chunks(centre, 8, 1.6)
			light(point(centre + Vector3.new(0, 4, 0), 1.6), colour, 34, 4, 1.4)
		end)
	else
		-- COSMIC BURST: the sky darkens, a meteor storm rains down round the
		-- target, a blazing comet strikes with a mushroom of fire and smoke,
		-- fire geysers erupt in a ring, more meteors fall, and a final cosmic
		-- shock rolls out across the whole valley.
		grade({ Brightness = -0.15, Contrast = 0.22, Saturation = 0.1, TintColor = Color3.fromRGB(255, 205, 190) }, 0.5, 5.6, 1.5)
		noise("rumble", centre)
		local function meteor(delay: number, spread: number, size: number)
			after(delay, function()
				local target = centre + Vector3.new(random:NextNumber(-spread, spread), 0, random:NextNumber(-spread, spread))
				target = surface(target) or target
				streak(skyPoint(target, 60, 30), target, size, 0.6, colour, false, function()
					flash(target, 3.5 * size, colour, 0.3)
					shockwave(target, 6 * size, colour, 0.5)
					sparks(target, 12, colour, 1)
					chunks(target, 1, 0.9)
					addShake(0.3)
				end)
			end)
		end
		for i = 1, 12 do
			meteor(0.15 + (i - 1) * 0.2, 16, random:NextNumber(0.9, 1.4))
		end
		local impact = 2.9
		after(impact - 0.75, function()
			streak(skyPoint(centre, 100, 60), centre, 5, 0.75, colour, true, function()
				grade({ Brightness = 0.5, Contrast = 0.1, TintColor = Color3.fromRGB(255, 244, 220) }, 0.04, 0.1, 0.7)
				addShake(1.5)
				flash(centre, 30, colour, 0.55)
				shockwave(centre, 36, colour, 0.9)
				after(0.12, function() shockwave(centre, 26, WHITE, 0.7) end)
				after(0.3, function() shockwave(centre, 46, Color3.fromRGB(255, 150, 70), 1.1) end)
				fireball(centre, 36, 3.8, colour)
				smokeColumn(centre, 22, 4.8, 4.5)
				embers(centre, 60, 1.5)
				burst(centre + Vector3.new(0, 3, 0), {
					texture = TEXTURES.spark, count = 45, colour = sequence(WHITE, colour), size = curve(0.8, 0.5, 0),
					lifetime = { 0.8, 1.6 }, speed = { 16, 34 }, drag = 2.5, spin = 200,
				})
				column(centre, 110, 7, colour, 1.6)
				chunks(centre, 12, 1.8)
				light(point(centre + Vector3.new(0, 4, 0), 2), colour, 42, 5, 1.8)
			end)
		end)
		-- Fire geysers burst up in a ring, one after another, while the ground rumbles.
		local turn = random:NextNumber(0, math.pi * 2)
		for i = 1, 6 do
			after(impact + 0.6 + i * 0.22, function()
				local angle = turn + i * math.pi / 3
				local flat = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 13
				local foot = surface(flat) or flat
				column(foot, 26, 2.4, Color3.fromRGB(255, 150, 70), 0.8)
				fireball(foot, 9, 1.8, colour)
				smokeColumn(foot, 4, 2, 2.4)
				shockwave(foot, 7, colour, 0.5)
				addShake(0.45)
			end)
		end
		-- A second, smaller wave of meteors.
		for i = 1, 6 do
			meteor(impact + 1.7 + i * 0.18, 20, random:NextNumber(0.8, 1.2))
		end
		-- The cosmic shock: the sky flashes white and rings roll out across the valley.
		after(impact + 3.6, function()
			grade({ Brightness = 0.4, Contrast = 0.12, Saturation = 0.15, TintColor = Color3.fromRGB(255, 236, 225) }, 0.05, 0.12, 0.8)
			addShake(1.2)
			flash(centre + Vector3.new(0, 4, 0), 22, WHITE, 0.5)
			shockwave(centre, 50, colour, 1.2)
			after(0.15, function() shockwave(centre, 38, WHITE, 1) end)
			after(0.35, function() shockwave(centre, 62, Color3.fromRGB(255, 150, 70), 1.4) end)
			embers(centre, 40, 1.6)
			burst(centre + Vector3.new(0, 6, 0), {
				texture = TEXTURES.spark, count = 50, colour = sequence(WHITE, colour, PINK), size = curve(0.8, 0.5, 0),
				lifetime = { 1, 1.8 }, speed = { 18, 36 }, drag = 2.5, spin = 200,
			})
			light(point(centre + Vector3.new(0, 6, 0), 1.6), colour, 40, 4, 1.4)
		end)
	end

	local text = label
	if text and tier >= bannerTier then
		bannerTier = tier
		bannerSerial += 1
		local serial = bannerSerial
		local title = if data.adding then (if data.blocks == 0 then "MOUNTAIN FULL" elseif data.blocks == nil then "REBUILDING" else GiftEffects.ADD_TITLES[tier]) else GiftEffects.TITLES[tier]
		text.Text = title .. "  ·  " .. Format.commas(data.coins) .. " COINS\n" .. tostring(data.name or "Someone") .. " sent " .. tostring(data.gift or "a gift")
		text.TextColor3 = colour
		if bannerTween then bannerTween:Cancel() end
		text.TextTransparency = 0
		text.TextStrokeTransparency = 0.35
		text.Position = UDim2.fromScale(0.5, 0.33)
		local grow = text:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		grow.Scale = 0.8
		grow.Parent = text
		TweenService:Create(text, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.30) }):Play()
		TweenService:Create(grow, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(BANNER_SECONDS[tier], function()
			if serial ~= bannerSerial then return end
			bannerTween = TweenService:Create(text, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 })
			bannerTween:Play()
			bannerTier = 0
		end)
	end
end

return GiftEffects
