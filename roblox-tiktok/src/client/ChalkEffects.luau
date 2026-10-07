--!strict
-- Chalkboard Count's gift animations, played on the board and in the
-- classroom: six for gifts that count up and six for gifts that count down,
-- one per gift tier, each wilder than the last, with its own sounds.
--
-- Counting up:
--   1  CHALK STAR      (1+ coins)       a gold star is chalked beside the number and bursts
--   2  GOLD STARS      (10+ coins)      three gold star stickers fly in and stamp the board
--   3  PAPER PLANES    (100+ coins)     paper planes loop round the room and dive at the number
--   4  CHALK STORM     (500+ coins)     sticks of chalk whirl round the number, then slam in
--   5  FIREWORKS       (1,000+ coins)   rockets shoot up from the floor and burst over the board
--   6  SUPERNOVA       (10,000+ coins)  the room goes dark, a star swells on the board, light
--                                       rays sweep the room and it goes nova in confetti
-- Counting down:
--   1  SPITBALL        a paper ball arcs in and splats on the number
--   2  ERASER TOSS     an eraser tumbles in, bounces off the board in a cloud of dust
--   3  SPONGE SPLASH   a wet sponge splats, water sprays and drips run down the board
--   4  BOARD QUAKE     the board shakes, cracks race over it and the number crumbles
--   5  DUSTER TORNADO  a whirlwind of erasers spins over the board and scrubs it
--   6  BLACK HOLE      a black hole opens in the board and swallows the number
--
-- play() returns when the number should change (the impact), so the board
-- keeps the old number until then. Nothing is physical; every piece is gone
-- a few seconds after its show, and each tier has a part budget.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRush")
local ChalkBoard = require(Shared:WaitForChild("ChalkBoard"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local ChalkEffects = {}

ChalkEffects.UP_TITLES = { "CHALK STAR", "GOLD STARS", "PAPER PLANES", "CHALK STORM", "FIREWORKS", "SUPERNOVA" }
ChalkEffects.DOWN_TITLES = { "SPITBALL", "ERASER TOSS", "SPONGE SPLASH", "BOARD QUAKE", "DUSTER TORNADO", "BLACK HOLE" }
-- When the number changes, seconds into each show.
ChalkEffects.UP_IMPACT = { 0.5, 0.75, 1.3, 2.1, 2.5, 3.4 }
ChalkEffects.DOWN_IMPACT = { 0.55, 0.85, 1, 1.6, 2.2, 3 }
ChalkEffects.PART_LIMITS = { 30, 40, 60, 80, 100, 120 }
ChalkEffects.LIFETIMES = { 3, 3.5, 4.5, 5.5, 6.5, 8 }

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 206, 92)
local PINK = Color3.fromRGB(255, 120, 200)
local CYAN = Color3.fromRGB(110, 225, 255)
local VIOLET = Color3.fromRGB(168, 96, 255)
local RED = Color3.fromRGB(255, 84, 84)
local WATER = Color3.fromRGB(120, 190, 255)
local WOOD = Color3.fromRGB(110, 76, 48)
local FELT = Color3.fromRGB(70, 74, 86)
local SPONGE = Color3.fromRGB(240, 210, 80)
local PAPER = Color3.fromRGB(246, 244, 236)
local CONFETTI = { GOLD, PINK, CYAN, Color3.fromRGB(120, 230, 150), VIOLET, Color3.fromRGB(255, 150, 80) }
local TEXTURES = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}
ChalkEffects.TEXTURES = TEXTURES

local random = Random.new()

-- What a show may use from Chalkboard Count's view.
export type Context = {
	chalk: Color3, -- the theme's chalk colour
	glow: boolean, -- the theme's chalk glows
	digits: () -> { BasePart }, -- the number's chalk strokes on the board now
	drawStroke: (a: Vector3, b: Vector3, width: number, colour: Color3, glow: boolean, start: number, finish: number) -> Part,
	shake: (degrees: number, seconds: number) -> (),
}

local function sequence(...: Color3): ColorSequence
	local colours = { ... }
	if #colours == 1 then return ColorSequence.new(colours[1]) end
	local points = {}
	for i, colour in colours do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colours - 1), colour))
	end
	return ColorSequence.new(points)
end

local function curve(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then return NumberSequence.new(values[1]) end
	local points = {}
	for i, value in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), value))
	end
	return NumberSequence.new(points)
end

-- Plays the show for a gift of `coins` going up (`up`) or down; `tier` is
-- 1 to 6. Returns the seconds until the number should change.
function ChalkEffects.play(tier: number, up: boolean, context: Context): number
	tier = math.clamp(math.floor(tier), 1, 6)
	local folder = Instance.new("Folder")
	folder.Name = "ChalkGiftShow"
	folder.Parent = workspace
	Debris:AddItem(folder, ChalkEffects.LIFETIMES[tier])
	local made = 0
	local function alive(): boolean
		return folder.Parent ~= nil
	end
	local function after(delay: number, callback: () -> ())
		task.delay(delay, function()
			if alive() then callback() end
		end)
	end
	local loudness = 1 + (tier - 1) * 0.12
	local function noise(name: string, at: Vector3?)
		if alive() then Sounds.play(name, at, loudness) end
	end
	-- Board positions: `x` across, `y` up from the floor, `out` towards the room.
	local function board(x: number, y: number, out: number?): Vector3
		return ChalkBoard.onBoard(x, y) + Vector3.new(0, 0, out or 0.3)
	end
	local middle = board(0, ChalkBoard.NUMBER_Y, 0.5)
	local function part(shape: Enum.PartType, size: Vector3, frame: CFrame, colour: Color3, material: Enum.Material?): Part?
		if not alive() or made >= ChalkEffects.PART_LIMITS[tier] then return nil end
		made += 1
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = frame
		p.Color = colour
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		return p
	end
	-- A chalk line drawn by the view, counted towards the show's parts.
	local function stroke(a: Vector3, b: Vector3, width: number, colour: Color3, glow: boolean, start: number, finish: number): Part?
		if not alive() or made >= ChalkEffects.PART_LIMITS[tier] then return nil end
		made += 1
		local line = context.drawStroke(a, b, width, colour, glow, start, finish)
		line.Parent = folder
		return line
	end
	local function tween(p: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		TweenService:Create(p, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
	end
	local function fade(p: Instance, seconds: number, goal: { [string]: any })
		tween(p, seconds, goal)
		Debris:AddItem(p, seconds + 0.05)
	end
	local function motion(seconds: number, update: (number) -> (), finish: (() -> ())?)
		local start = os.clock()
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - start) / seconds, 0, 1)
			if alive() then update(t) end
			if t >= 1 or not alive() then
				if connection then
					connection:Disconnect()
					connection = nil
				end
				if alive() and finish then finish() end
			end
		end)
	end
	local function emit(at: Vector3, spec: { [string]: any })
		if not alive() then return end
		local spot = Instance.new("Attachment")
		spot.Position = at
		spot.Parent = workspace.Terrain
		Debris:AddItem(spot, (spec.lifetime[2] or 1) + 0.3)
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
		particles.Rotation = NumberRange.new(0, 360)
		particles.RotSpeed = NumberRange.new(-(spec.spin or 0), spec.spin or 0)
		particles.EmissionDirection = spec.direction or Enum.NormalId.Top
		if spec.flat then particles.Orientation = Enum.ParticleOrientation.VelocityPerpendicular end
		particles.Enabled = false
		particles.Parent = spot
		particles:Emit(spec.count)
	end
	local function sparks(at: Vector3, colour: Color3, count: number, power: number?)
		local p = power or 1
		emit(at, { texture = TEXTURES.spark, count = count, colour = sequence(WHITE, colour), size = curve(1, 0.5, 0),
			lifetime = { 0.5, 1.2 }, speed = { 8 * p, 20 * p }, drag = 2.5, acceleration = Vector3.new(0, -10, 0), spin = 200 })
	end
	local function dust(at: Vector3, colour: Color3, count: number, size: number?)
		local s = size or 1
		emit(at, { texture = TEXTURES.smoke, count = count, colour = sequence(colour), size = curve(0.6 * s, 2.2 * s),
			transparency = curve(0.3, 1), lifetime = { 0.8, 1.6 }, speed = { 2, 7 }, spread = 80, drag = 2.5, glow = 0.2, spin = 40,
			acceleration = Vector3.new(0, -1.5, 0) })
	end
	local function confetti(at: Vector3, count: number, power: number?)
		local p = power or 1
		for k = 1, 3 do
			emit(at, { texture = TEXTURES.spark, count = math.ceil(count / 3), colour = sequence(CONFETTI[(k * 2 + tier) % #CONFETTI + 1], CONFETTI[(k + tier) % #CONFETTI + 1]),
				size = curve(0.9, 0.6), lifetime = { 1.2, 2.2 }, speed = { 10 * p, 26 * p }, drag = 2, acceleration = Vector3.new(0, -9, 0), spin = 300 })
		end
	end
	-- A ring of light racing out flat over the board.
	local function ring(at: Vector3, radius: number, colour: Color3, seconds: number)
		emit(at, { texture = TEXTURES.ring, count = 1, colour = sequence(WHITE, colour), size = curve(1, radius * 2), transparency = curve(0, 1),
			lifetime = { seconds, seconds }, speed = { 0.01, 0.01 }, spread = 0, flat = true, direction = Enum.NormalId.Back })
	end
	local function flash(at: Vector3, colour: Color3, size: number, seconds: number?)
		local ball = part(Enum.PartType.Ball, Vector3.one * size * 0.25, CFrame.new(at), WHITE, Enum.Material.Neon)
		if ball == nil then return end
		ball.Transparency = 0.1
		fade(ball, seconds or 0.35, { Size = Vector3.one * size, Transparency = 1, Color = colour })
	end
	local function grade(tint: Color3, brightness: number, rise: number, hold: number, fall: number)
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "ChalkGrade"
		effect.Parent = Lighting
		tween(effect, rise, { TintColor = tint, Brightness = brightness })
		task.delay(rise + hold, function()
			if effect.Parent then tween(effect, fall, { TintColor = WHITE, Brightness = 0 }) end
		end)
		Debris:AddItem(effect, rise + hold + fall + 0.1)
	end
	-- A flat star of `size` facing the room, as five chalk-like spokes.
	local function star(at: Vector3, size: number, colour: Color3, material: Enum.Material): { Part }
		local spokes = {}
		for k = 0, 4 do
			local angle = k * math.pi * 2 / 5 + math.pi / 2
			local tip = at + Vector3.new(math.cos(angle) * size / 2, math.sin(angle) * size / 2, 0)
			local spoke = part(Enum.PartType.Block, Vector3.new(size * 0.18, size * 0.18, size / 2), CFrame.lookAt((at + tip) / 2, tip), colour, material)
			if spoke then table.insert(spokes, spoke) end
		end
		return spokes
	end
	local function arc(a: Vector3, b: Vector3, height: number, t: number): Vector3
		return a + (b - a) * t + Vector3.new(0, math.sin(math.pi * t) * height, 0)
	end
	-- Where things fly in from: the room in front of the board, off to a side.
	local function roomPoint(side: number, height: number, out: number): Vector3
		return ChalkBoard.onBoard(side, height) + Vector3.new(0, 0, out)
	end

	local impact = (if up then ChalkEffects.UP_IMPACT else ChalkEffects.DOWN_IMPACT)[tier]
	local chalk = context.chalk

	if up and tier == 1 then
		-- CHALK STAR: a gold star is chalked beside the number, then bursts.
		local centre = Vector2.new(random:NextNumber(-12, -8) * (if random:NextNumber() < 0.5 then -1 else 1), ChalkBoard.NUMBER_Y + 2.4)
		local points = {}
		for k = 0, 5 do
			local angle = math.pi / 2 + k * math.pi * 4 / 5
			table.insert(points, ChalkBoard.onBoard(centre.X + math.cos(angle) * 1.6, centre.Y + math.sin(angle) * 1.6))
		end
		local strokes: { Part } = {}
		for k = 1, 5 do
			local line = stroke(points[k], points[k + 1], 0.2, GOLD, true, (k - 1) * 0.08, k * 0.08)
			if line then table.insert(strokes, line) end
		end
		noise("chalk", points[1])
		after(0.45, function()
			local at = ChalkBoard.onBoard(centre.X, centre.Y) + Vector3.new(0, 0, 0.4)
			sparks(at, GOLD, 30)
			flash(at, GOLD, 4)
			noise("pop", at)
			for _, p in strokes do fade(p, 0.4, { Transparency = 1 }) end
		end)
		after(impact, function() sparks(middle, chalk, 16, 0.7) end)
	elseif up and tier == 2 then
		-- GOLD STARS: three star stickers fly in from the room and stamp the board.
		noise("whoosh", middle)
		for k = 1, 3 do
			local target = board((k - 2) * 8, ChalkBoard.NUMBER_Y + (if k == 2 then 3.6 else 2.4), 0.25)
			local from = roomPoint((k - 2) * 20, 4, 24)
			local spokes = star(from, 2.2, GOLD, Enum.Material.Neon)
			local offsets = {}
			for _, spoke in spokes do table.insert(offsets, CFrame.new(from):ToObjectSpace(spoke.CFrame)) end
			after((k - 1) * 0.12, function()
				motion(0.45, function(t)
					local at = arc(from, target, 4, t)
					local turn = CFrame.new(at) * CFrame.Angles(0, 0, (1 - t) * 8)
					for i, spoke in spokes do spoke.CFrame = turn * offsets[i] end
				end, function()
					noise("pop", target)
					sparks(target, GOLD, 18)
					ring(target, 3, GOLD, 0.5)
					for _, spoke in spokes do
						tween(spoke, 0.12, { Size = spoke.Size * 1.4 }, Enum.EasingStyle.Back)
						after(0.9, function() fade(spoke, 0.5, { Transparency = 1 }) end)
					end
				end)
			end)
		end
		after(impact, function() sparks(middle, chalk, 20) end)
	elseif up and tier == 3 then
		-- PAPER PLANES: planes loop round the room and dive at the number.
		noise("whoosh", middle)
		for k = 1, 5 do
			local plane: { Part } = {}
			local wing = part(Enum.PartType.Block, Vector3.new(1.6, 0.06, 1.2), CFrame.identity, PAPER)
			local body = part(Enum.PartType.Block, Vector3.new(0.18, 0.4, 1.4), CFrame.identity, PAPER)
			if wing then table.insert(plane, wing) end
			if body then table.insert(plane, body) end
			local side = if k % 2 == 0 then 1 else -1
			local loop = roomPoint(side * random:NextNumber(10, 18), random:NextNumber(10, 15), random:NextNumber(10, 18))
			local start = roomPoint(-side * 22, 6, 26)
			local target = board(random:NextNumber(-6, 6), ChalkBoard.NUMBER_Y + random:NextNumber(-1.5, 1.5), 0.3)
			local previous = start
			after((k - 1) * 0.12, function()
				motion(1.05, function(t)
					local a = start:Lerp(loop, t)
					local b = loop:Lerp(target, t)
					local at = a:Lerp(b, t) + Vector3.new(0, math.sin(t * math.pi * 2) * 1.5, 0)
					local heading = if (at - previous).Magnitude > 1e-3 then at - previous else Vector3.new(0, 0, -1)
					previous = at
					local frame = CFrame.lookAt(at, at + heading) * CFrame.Angles(0, 0, math.sin(t * 9) * 0.6)
					if wing then wing.CFrame = frame end
					if body then body.CFrame = frame * CFrame.new(0, -0.2, 0) end
				end, function()
					noise("pop", target)
					sparks(target, if k % 2 == 0 then GOLD else chalk, 14)
					dust(target, chalk, 4)
					for _, p in plane do fade(p, 0.3, { Transparency = 1, Size = p.Size * 0.4 }) end
				end)
			end)
		end
		after(impact, function()
			flash(middle, GOLD, 8)
			ring(middle, 7, GOLD, 0.6)
			noise("boom", middle)
		end)
	elseif up and tier == 4 then
		-- CHALK STORM: sticks of chalk whirl round the number, then slam in.
		noise("deepWhoosh", middle)
		local sticks: { Part } = {}
		for k = 1, 24 do
			local stick = part(Enum.PartType.Cylinder, Vector3.new(1, 0.24, 0.24), CFrame.new(middle), CONFETTI[k % #CONFETTI + 1]:Lerp(chalk, 0.4))
			if stick then table.insert(sticks, stick) end
		end
		local positions: { Vector3 } = {}
		motion(1.7, function(t)
			local spin = t * t * 18
			local reach = 4 + math.sin(t * math.pi) * 9
			for k, stick in sticks do
				local angle = spin + k * math.pi * 2 / #sticks
				local at = middle + Vector3.new(math.cos(angle) * reach * 1.6, math.sin(angle) * reach * 0.6, 1.5 + math.sin(angle * 2) * 1.2)
				positions[k] = at
				stick.CFrame = CFrame.new(at) * CFrame.Angles(angle, angle * 2, 0)
			end
			if math.random() < 0.3 then dust(middle + Vector3.new(random:NextNumber(-8, 8), random:NextNumber(-3, 3), 1), chalk, 2) end
		end, function()
			for k, stick in sticks do
				local from = positions[k] or middle
				motion(0.25, function(t)
					stick.CFrame = CFrame.new(from:Lerp(middle, t * t)) * CFrame.Angles(t * 4, 0, 0)
				end, function() stick:Destroy() end)
			end
		end)
		after(impact - 0.15, function()
			flash(middle, chalk, 12)
			ring(middle, 10, GOLD, 0.7)
			sparks(middle, GOLD, 50, 1.4)
			dust(middle, chalk, 16, 1.5)
			context.shake(1.2, 0.6)
			noise("boom", middle)
		end)
	elseif up and tier == 5 then
		-- FIREWORKS: rockets shoot up from the floor and burst over the board.
		noise("launch", middle)
		for k = 1, 6 do
			local floor = ChalkBoard.ORIGIN + Vector3.new((k - 3.5) * 6, 0.5, ChalkBoard.BOARD_Z + 6)
			local burstAt = board((k - 3.5) * 5.5, ChalkBoard.NUMBER_Y + random:NextNumber(-2, 4), 1.5)
			local colour = CONFETTI[k]
			local rocket = part(Enum.PartType.Ball, Vector3.one * 0.6, CFrame.new(floor), colour, Enum.Material.Neon)
			if rocket == nil then continue end
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.3, 0)
			a0.Parent = rocket
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.3, 0)
			a1.Parent = rocket
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = sequence(WHITE, colour)
			trail.Lifetime = 0.4
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Parent = rocket
			after((k - 1) * 0.22, function()
				noise("whoosh", floor)
				motion(0.7, function(t)
					rocket.CFrame = CFrame.new(arc(floor, burstAt, 2, 1 - (1 - t) ^ 2))
				end, function()
					rocket:Destroy()
					noise("pop", burstAt)
					emit(burstAt, { texture = TEXTURES.spark, count = 45, colour = sequence(WHITE, colour, colour), size = curve(1.2, 0.8, 0),
						lifetime = { 0.8, 1.5 }, speed = { 14, 24 }, drag = 2.5, acceleration = Vector3.new(0, -8, 0), spin = 300 })
					flash(burstAt, colour, 5)
				end)
			end)
		end
		after(impact, function()
			flash(middle, GOLD, 16, 0.5)
			ring(middle, 14, GOLD, 0.8)
			confetti(middle + Vector3.new(0, 4, 2), 90, 1.2)
			context.shake(1.4, 0.7)
			noise("bigBoom", middle)
		end)
	elseif up then
		-- SUPERNOVA: the room goes dark, a star swells on the board, light rays
		-- sweep the room and it goes nova in confetti.
		grade(Color3.fromRGB(170, 160, 220), -0.25, 0.6, impact - 0.6, 1.2)
		noise("rumble", middle)
		after(0.8, function() noise("deepWhoosh", middle) end)
		local core = part(Enum.PartType.Ball, Vector3.one * 0.5, CFrame.new(middle + Vector3.new(0, 0, 0.6)), WHITE, Enum.Material.Neon)
		local halo = part(Enum.PartType.Ball, Vector3.one * 1, CFrame.new(middle + Vector3.new(0, 0, 0.5)), GOLD, Enum.Material.Neon)
		if halo then halo.Transparency = 0.55 end
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 40
		light.Brightness = 0
		light.Shadows = false
		if core then light.Parent = core end
		local rays: { Part } = {}
		for k = 1, 8 do
			local ray = part(Enum.PartType.Block, Vector3.new(0.4, 0.4, 0.1), CFrame.new(middle), if k % 2 == 0 then GOLD else WHITE, Enum.Material.Neon)
			if ray then
				ray.Transparency = 0.35
				table.insert(rays, ray)
			end
		end
		motion(impact, function(t)
			local grow = t * t
			if core then core.Size = Vector3.one * (0.5 + grow * 5) end
			if halo then halo.Size = Vector3.one * (1 + grow * 10 + math.sin(t * 40) * 0.4) end
			light.Brightness = grow * 6
			local length = 4 + grow * 40
			for k, ray in rays do
				local angle = k * math.pi / 4 + t * 3
				local tip = middle + Vector3.new(math.cos(angle) * length, math.sin(angle) * length * 0.5, 6 + length * 0.4)
				ray.Size = Vector3.new(0.3 + grow, 0.3 + grow, (tip - middle).Magnitude)
				ray.CFrame = CFrame.lookAt((middle + tip) / 2, tip)
			end
			if math.random() < 0.25 then sparks(middle + Vector3.new(random:NextNumber(-14, 14), random:NextNumber(-5, 5), 1), GOLD, 6, 0.6) end
		end, function()
			for _, ray in rays do fade(ray, 0.3, { Transparency = 1 }) end
			if core then fade(core, 0.6, { Size = Vector3.one * 40, Transparency = 1 }) end
			if halo then fade(halo, 0.5, { Size = Vector3.one * 30, Transparency = 1 }) end
		end)
		after(impact, function()
			noise("bigBoom", middle)
			flash(middle, GOLD, 30, 0.7)
			ring(middle, 22, GOLD, 1)
			after(0.12, function() ring(middle, 14, WHITE, 0.8) end)
			confetti(middle + Vector3.new(0, 2, 3), 150, 1.5)
			sparks(middle, GOLD, 80, 1.6)
			context.shake(2.2, 1)
		end)
		after(impact + 0.8, function()
			confetti(board(-10, ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT, 3), 60)
			confetti(board(10, ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT, 3), 60)
			noise("pop", middle)
		end)
	elseif tier == 1 then
		-- SPITBALL: a paper ball arcs in and splats on the number.
		local from = roomPoint(18, 5, 20)
		local target = middle + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-1, 1), -0.2)
		local ball = part(Enum.PartType.Ball, Vector3.one * 0.7, CFrame.new(from), PAPER)
		noise("whoosh", target)
		motion(impact, function(t)
			if ball then ball.CFrame = CFrame.new(arc(from, target, 3, t)) * CFrame.Angles(t * 9, t * 6, 0) end
		end, function()
			if ball then ball:Destroy() end
			noise("splat", target)
			local splat = part(Enum.PartType.Cylinder, Vector3.new(0.05, 0.4, 0.4), CFrame.new(target + Vector3.new(0, 0, 0.1)) * CFrame.Angles(0, math.pi / 2, 0), PAPER)
			if splat then
				tween(splat, 0.12, { Size = Vector3.new(0.05, 2.4, 2.4) }, Enum.EasingStyle.Back)
				after(0.8, function() fade(splat, 0.6, { Transparency = 1 }) end)
			end
			dust(target, chalk, 6)
		end)
	elseif tier == 2 then
		-- ERASER TOSS: an eraser tumbles in and bounces off the board in a cloud of dust.
		local from = roomPoint(-20, 6, 22)
		local target = middle + Vector3.new(random:NextNumber(-2, 2), 0, 0.4)
		local back = target + Vector3.new(6, -6, 8)
		local wood = part(Enum.PartType.Block, Vector3.new(2.6, 1, 1), CFrame.new(from), WOOD, Enum.Material.Wood)
		local felt = part(Enum.PartType.Block, Vector3.new(2.6, 0.4, 1), CFrame.new(from), FELT, Enum.Material.Fabric)
		local function place(at: Vector3, spin: number)
			local frame = CFrame.new(at) * CFrame.Angles(spin, spin * 0.7, spin * 0.3)
			if wood then wood.CFrame = frame end
			if felt then felt.CFrame = frame * CFrame.new(0, -0.7, 0) end
		end
		noise("whoosh", target)
		motion(impact, function(t) place(arc(from, target, 4, t), t * 10) end, function()
			noise("thud", target)
			noise("erase", target)
			dust(target, chalk, 18, 1.4)
			context.shake(0.6, 0.3)
			motion(0.6, function(t) place(arc(target, back, 3, t), 10 + t * 8) end, function()
				if wood then fade(wood, 0.3, { Transparency = 1 }) end
				if felt then fade(felt, 0.3, { Transparency = 1 }) end
			end)
		end)
	elseif tier == 3 then
		-- SPONGE SPLASH: a wet sponge splats, water sprays and drips run down the board.
		local from = roomPoint(16, 9, 24)
		local target = middle + Vector3.new(0, 0, 0.6)
		local sponge = part(Enum.PartType.Block, Vector3.new(2.4, 1.4, 1.2), CFrame.new(from), SPONGE, Enum.Material.Sand)
		noise("whoosh", target)
		motion(impact, function(t)
			if sponge then sponge.CFrame = CFrame.new(arc(from, target, 3, t)) * CFrame.Angles(t * 6, t * 4, 0) end
		end, function()
			noise("splash", target)
			if sponge then
				tween(sponge, 0.1, { Size = Vector3.new(3.4, 1.8, 0.5) })
				after(0.5, function()
					fade(sponge, 0.8, { CFrame = sponge.CFrame - Vector3.new(0, 8, -2), Transparency = 1 })
				end)
			end
			emit(target, { texture = TEXTURES.spark, count = 60, colour = sequence(WHITE, WATER), size = curve(0.5, 0.2),
				lifetime = { 0.5, 1 }, speed = { 10, 22 }, drag = 1.5, acceleration = Vector3.new(0, -30, 0), spread = 70, direction = Enum.NormalId.Back })
			emit(target, { texture = TEXTURES.smoke, count = 10, colour = sequence(WHITE), size = curve(1, 3), transparency = curve(0.6, 1),
				lifetime = { 1, 2 }, speed = { 1, 3 }, glow = 0, acceleration = Vector3.new(0, 3, 0) })
			for k = 1, 10 do
				local top = board(random:NextNumber(-7, 7), ChalkBoard.NUMBER_Y + random:NextNumber(-1.5, 2), 0.12)
				local drip = part(Enum.PartType.Block, Vector3.new(0.22, 0.4, 0.06), CFrame.new(top), WATER, Enum.Material.Glass)
				if drip == nil then break end
				drip.Transparency = 0.25
				local fall = random:NextNumber(3, 6)
				after(k * 0.04, function()
					motion(1.6, function(t)
						local length = 0.4 + t * fall
						drip.Size = Vector3.new(0.22, length, 0.06)
						drip.CFrame = CFrame.new(top - Vector3.new(0, length / 2, 0))
					end, function() fade(drip, 0.5, { Transparency = 1 }) end)
				end)
			end
		end)
	elseif tier == 4 then
		-- BOARD QUAKE: the board shakes, cracks race over it and the number crumbles.
		noise("rumble", middle)
		context.shake(1, impact + 0.3)
		for k = 1, 7 do
			local from = Vector2.new(random:NextNumber(-3, 3), ChalkBoard.NUMBER_Y + random:NextNumber(-1, 1))
			local angle = k * math.pi * 2 / 7 + random:NextNumber(-0.3, 0.3)
			local previous = from
			for step = 1, 3 do
				local nextPoint = previous + Vector2.new(math.cos(angle + random:NextNumber(-0.5, 0.5)), math.sin(angle + random:NextNumber(-0.5, 0.5)) * 0.6) * random:NextNumber(2, 4)
				local a, b = ChalkBoard.onBoard(previous.X, previous.Y), ChalkBoard.onBoard(nextPoint.X, nextPoint.Y)
				previous = nextPoint
				after(0.2 + (step - 1) * 0.25 + k * 0.03, function()
					local crack = stroke(a + Vector3.new(0, 0, 0.02), b + Vector3.new(0, 0, 0.02), 0.12, BLACK, false, 0, 0.2)
					if crack then after(1.6, function() fade(crack, 0.6, { Transparency = 1 }) end) end
				end)
			end
		end
		-- Chalk falls off the tray and dust rains from the ceiling.
		for k = 1, 6 do
			local at = ChalkBoard.ORIGIN + Vector3.new((k - 3.5) * 5, ChalkBoard.BOARD_BOTTOM - 0.2, ChalkBoard.BOARD_Z + 1)
			local stick = part(Enum.PartType.Cylinder, Vector3.new(1, 0.22, 0.22), CFrame.new(at), chalk)
			if stick then
				after(0.3 + k * 0.08, function()
					fade(stick, 0.6, { CFrame = CFrame.new(at + Vector3.new(random:NextNumber(-1, 1), -2.2, 1.5)) * CFrame.Angles(1, 2, 3), Transparency = 1 })
				end)
			end
		end
		after(0.4, function() dust(board(0, ChalkBoard.BOARD_BOTTOM + ChalkBoard.BOARD_HEIGHT + 1, 2), Color3.fromRGB(200, 196, 188), 16, 1.6) end)
		after(impact, function()
			noise("boom", middle)
			-- The number crumbles: copies of its strokes fall to the floor.
			for _, piece in context.digits() do
				local copy = part(Enum.PartType.Block, piece.Size, piece.CFrame, piece.Color, piece.Material)
				if copy == nil then break end
				local drop = random:NextNumber(6, 9)
				fade(copy, 0.9, { CFrame = piece.CFrame * CFrame.Angles(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)) - Vector3.new(0, drop, -random:NextNumber(0.5, 2)), Transparency = 1 })
			end
			dust(middle, chalk, 20, 1.6)
			context.shake(1.6, 0.5)
		end)
	elseif tier == 5 then
		-- DUSTER TORNADO: a whirlwind of erasers spins over the board and scrubs it.
		noise("deepWhoosh", middle)
		local erasers: { { Part } } = {}
		for k = 1, 8 do
			local wood = part(Enum.PartType.Block, Vector3.new(2.2, 0.8, 0.8), CFrame.new(middle), WOOD, Enum.Material.Wood)
			local felt = part(Enum.PartType.Block, Vector3.new(2.2, 0.3, 0.8), CFrame.new(middle), FELT, Enum.Material.Fabric)
			if wood and felt then table.insert(erasers, { wood, felt }) end
		end
		motion(impact + 0.5, function(t)
			local sweep = math.sin(t * math.pi * 2) * 9
			local centre = middle + Vector3.new(sweep, 0, 1.2)
			for k, pair in erasers do
				local angle = t * 22 + k * math.pi / 4
				local reach = 3 + k * 0.35
				local at = centre + Vector3.new(math.cos(angle) * reach, (k - 4.5) * 0.7 + math.sin(angle) * 0.5, math.sin(angle) * reach * 0.4)
				local frame = CFrame.new(at) * CFrame.Angles(0, -angle, math.sin(angle) * 0.5)
				pair[1].CFrame = frame
				pair[2].CFrame = frame * CFrame.new(0, -0.55, 0)
			end
			if math.random() < 0.5 then dust(centre + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-3, 3), 0), Color3.fromRGB(200, 196, 188), 2, 1.3) end
			if math.random() < 0.08 then noise("erase", centre) end
		end, function()
			for _, pair in erasers do
				local out = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-0.3, 1), random:NextNumber(0.5, 1)).Unit * 20
				for _, p in pair do fade(p, 0.6, { CFrame = p.CFrame + out, Transparency = 1 }) end
			end
		end)
		after(impact, function()
			dust(middle, chalk, 24, 1.8)
			context.shake(1.2, 0.5)
			noise("thud", middle)
		end)
	else
		-- BLACK HOLE: a black hole opens in the board and swallows the number.
		grade(Color3.fromRGB(190, 160, 255), -0.2, 0.5, impact - 0.3, 1)
		noise("deepWhoosh", middle)
		after(1.2, function() noise("deepWhoosh", middle) end)
		local hole = part(Enum.PartType.Cylinder, Vector3.new(0.1, 0.4, 0.4), CFrame.new(middle + Vector3.new(0, 0, -0.1)) * CFrame.Angles(0, math.pi / 2, 0), BLACK)
		local rim = part(Enum.PartType.Cylinder, Vector3.new(0.08, 0.6, 0.6), CFrame.new(middle + Vector3.new(0, 0, -0.15)) * CFrame.Angles(0, math.pi / 2, 0), VIOLET, Enum.Material.Neon)
		if hole then tween(hole, 0.8, { Size = Vector3.new(0.1, 9, 9) }, Enum.EasingStyle.Back) end
		if rim then tween(rim, 0.8, { Size = Vector3.new(0.08, 10.5, 10.5) }, Enum.EasingStyle.Back) end
		-- The number's strokes (copies) spiral in.
		local pieces: { { part: Part, from: CFrame } } = {}
		after(0.6, function()
			for _, piece in context.digits() do
				local copy = part(Enum.PartType.Block, piece.Size, piece.CFrame, piece.Color, piece.Material)
				if copy == nil then break end
				table.insert(pieces, { part = copy, from = piece.CFrame })
			end
			motion(impact - 0.7, function(t)
				local pull = t * t
				for k, entry in pieces do
					local offset = entry.from.Position - middle
					local angle = pull * 8 + k * 0.1
					local spun = Vector3.new(offset.X * math.cos(angle) - offset.Y * math.sin(angle), offset.X * math.sin(angle) + offset.Y * math.cos(angle), 0)
					entry.part.CFrame = CFrame.new(middle + spun * (1 - pull) + Vector3.new(0, 0, 0.3)) * entry.from.Rotation * CFrame.Angles(0, 0, angle)
					entry.part.Size = entry.part.Size:Lerp(Vector3.new(0.05, 0.05, 0.05), pull * 0.06)
				end
				if math.random() < 0.4 then
					local edge = middle + Vector3.new(random:NextNumber(-14, 14), random:NextNumber(-5, 5), 0.5)
					emit(edge, { texture = TEXTURES.spark, count = 3, colour = sequence(WHITE, VIOLET), size = curve(0.6, 0),
						lifetime = { 0.5, 0.7 }, speed = { 0.5, 1 }, glow = 1 })
				end
			end, function()
				for _, entry in pieces do entry.part:Destroy() end
			end)
		end)
		after(impact, function()
			noise("bigBoom", middle)
			if hole then fade(hole, 0.25, { Size = Vector3.new(0.1, 0.2, 0.2) }) end
			if rim then fade(rim, 0.35, { Size = Vector3.new(0.08, 14, 14), Transparency = 1 }) end
			flash(middle, VIOLET, 20, 0.5)
			ring(middle, 18, VIOLET, 0.8)
			sparks(middle, VIOLET, 60, 1.4)
			context.shake(2, 0.8)
		end)
	end
	return impact
end

return ChalkEffects
