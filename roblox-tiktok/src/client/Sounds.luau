--!strict
-- Sound effects for every game: digging, the gift shows (Diamond in the
-- Rough's blasts and rebuilds, Diamond Climb's rides, Chalkboard Count's
-- gifts) and the chalk being written. Every sound is one that ships with the
-- Roblox client (rbxasset://sounds), so nothing has to be uploaded or made
-- public; each cue layers a few of them at different pitches to make the
-- sound. To use your own uploads instead, change the ids in FILES.
--
-- Sounds.play(cue, at?, scale?, pitch?) plays a cue: at a point in the world
-- (it fades with distance) or, without one, straight to the player. `scale`
-- (default 1) makes it louder and deeper for bigger gifts; `pitch` (default 1)
-- raises or lowers every layer (digging climbs a little with each hit). The same cue is
-- not started again within a few hundredths of a second, and only so many
-- sounds play at once, so a hundred sparks never make a hundred sounds.
local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.FILES = {
	crunch = "rbxasset://sounds/collide.wav",
	hit = "rbxasset://sounds/hit.wav",
	snap = "rbxasset://sounds/snap.wav",
	click = "rbxasset://sounds/clickfast.wav",
	button = "rbxasset://sounds/button.wav",
	boom = "rbxasset://sounds/impact_explosion_03.mp3",
	whoosh = "rbxasset://sounds/swoosh.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	glass = "rbxasset://sounds/glassbreak.wav",
	splash = "rbxasset://sounds/impact_water.mp3",
	splat = "rbxasset://sounds/splat.wav",
	land = "rbxasset://sounds/action_jump_land.mp3",
	jump = "rbxasset://sounds/action_jump.mp3",
	fall = "rbxasset://sounds/action_falling.mp3",
	victory = "rbxasset://sounds/victory.wav",
	plunk = "rbxasset://sounds/Kerplunk.wav",
	rocket = "rbxasset://sounds/Rocket shot.wav",
	page = "rbxasset://sounds/pageturn.wav",
}

-- A layer: which file, how loud, its pitch (a range picks one at random),
-- and how long after the cue starts it plays.
export type Layer = { file: string, volume: number, pitch: { number }, delay: number? }

Sounds.CUES = {
	-- Digging: a light, crisp crunch as the hand bites into the rock, a
	-- small crack and a tiny patter of pebbles. Quiet and short, with no
	-- explosion in it, so holding dig never sounds like a blast.
	dig = {
		{ file = "crunch", volume = 0.2, pitch = { 1.0, 1.15 } },
		{ file = "snap", volume = 0.13, pitch = { 1.45, 1.75 } },
		{ file = "land", volume = 0.1, pitch = { 1.15, 1.3 } },
		{ file = "click", volume = 0.06, pitch = { 1.5, 1.9 }, delay = 0.04 },
		{ file = "click", volume = 0.045, pitch = { 1.15, 1.35 }, delay = 0.09 },
	},
	-- Every fourth hit a chunk breaks away: a slightly deeper crunch and
	-- pebbles tumbling down.
	crumble = {
		{ file = "crunch", volume = 0.24, pitch = { 0.8, 0.9 } },
		{ file = "snap", volume = 0.1, pitch = { 1.05, 1.2 }, delay = 0.02 },
		{ file = "click", volume = 0.06, pitch = { 1.2, 1.35 }, delay = 0.08 },
		{ file = "click", volume = 0.05, pitch = { 1.4, 1.55 }, delay = 0.15 },
		{ file = "click", volume = 0.04, pitch = { 1.6, 1.85 }, delay = 0.22 },
	},
	-- Gift shows.
	pop = {
		{ file = "snap", volume = 0.5, pitch = { 1.1, 1.3 } },
		{ file = "ping", volume = 0.25, pitch = { 1.6, 1.9 }, delay = 0.02 },
	},
	sparkle = { { file = "ping", volume = 0.3, pitch = { 2, 2.6 } } },
	rubble = {
		{ file = "crunch", volume = 0.45, pitch = { 0.5, 0.65 } },
		{ file = "click", volume = 0.18, pitch = { 0.5, 0.7 }, delay = 0.06 },
		{ file = "click", volume = 0.14, pitch = { 0.7, 0.9 }, delay = 0.14 },
	},
	boom = {
		{ file = "boom", volume = 0.7, pitch = { 0.85, 1.05 } },
		{ file = "crunch", volume = 0.45, pitch = { 0.4, 0.5 } },
	},
	bigBoom = {
		{ file = "boom", volume = 1, pitch = { 0.5, 0.6 } },
		{ file = "boom", volume = 0.6, pitch = { 0.8, 0.9 }, delay = 0.08 },
		{ file = "crunch", volume = 0.6, pitch = { 0.3, 0.38 } },
	},
	thud = {
		{ file = "land", volume = 0.6, pitch = { 0.6, 0.8 } },
		{ file = "crunch", volume = 0.35, pitch = { 0.55, 0.7 } },
	},
	rumble = {
		{ file = "boom", volume = 0.45, pitch = { 0.3, 0.36 } },
		{ file = "boom", volume = 0.35, pitch = { 0.34, 0.4 }, delay = 0.35 },
	},
	whoosh = { { file = "whoosh", volume = 0.5, pitch = { 0.8, 1.1 } } },
	deepWhoosh = { { file = "whoosh", volume = 0.7, pitch = { 0.4, 0.55 } } },
	shatter = {
		{ file = "glass", volume = 0.55, pitch = { 0.9, 1.15 } },
		{ file = "ping", volume = 0.2, pitch = { 2.4, 2.8 }, delay = 0.05 },
	},
	beam = {
		{ file = "rocket", volume = 0.4, pitch = { 0.6, 0.75 } },
		{ file = "ping", volume = 0.25, pitch = { 0.5, 0.6 } },
	},
	zap = {
		{ file = "snap", volume = 0.6, pitch = { 0.5, 0.6 } },
		{ file = "boom", volume = 0.4, pitch = { 1.4, 1.6 } },
	},
	clang = {
		{ file = "hit", volume = 0.8, pitch = { 0.45, 0.55 } },
		{ file = "hit", volume = 0.5, pitch = { 0.9, 1 }, delay = 0.03 },
	},
	boing = {
		{ file = "jump", volume = 0.7, pitch = { 0.7, 0.8 } },
		{ file = "whoosh", volume = 0.35, pitch = { 1.3, 1.5 }, delay = 0.05 },
	},
	launch = {
		{ file = "rocket", volume = 0.7, pitch = { 0.9, 1.05 } },
		{ file = "whoosh", volume = 0.45, pitch = { 0.7, 0.8 }, delay = 0.1 },
	},
	slip = {
		{ file = "whoosh", volume = 0.5, pitch = { 1.4, 1.6 } },
		{ file = "plunk", volume = 0.45, pitch = { 1, 1.1 }, delay = 0.25 },
	},
	falling = { { file = "fall", volume = 0.55, pitch = { 0.9, 1.1 } } },
	splash = {
		{ file = "splash", volume = 0.6, pitch = { 0.9, 1.1 } },
		{ file = "splat", volume = 0.4, pitch = { 0.8, 1 } },
	},
	splat = { { file = "splat", volume = 0.6, pitch = { 0.9, 1.15 } } },
	cheer = {
		{ file = "victory", volume = 0.6, pitch = { 1, 1 } },
	},
	-- Chalk on the board: a short scratch per stroke, a tap per number.
	chalk = {
		{ file = "whoosh", volume = 0.12, pitch = { 2.6, 3.2 } },
		{ file = "click", volume = 0.05, pitch = { 1.6, 2 } },
	},
	erase = {
		{ file = "whoosh", volume = 0.35, pitch = { 0.6, 0.75 } },
		{ file = "page", volume = 0.2, pitch = { 0.7, 0.9 } },
	},
	-- The hold countdowns: a tick each number, and a rising chime at the end.
	tick = { { file = "click", volume = 0.35, pitch = { 1.2, 1.2 } } },
	chime = {
		{ file = "ping", volume = 0.4, pitch = { 1, 1 } },
		{ file = "ping", volume = 0.4, pitch = { 1.26, 1.26 }, delay = 0.12 },
		{ file = "ping", volume = 0.4, pitch = { 1.5, 1.5 }, delay = 0.24 },
	},
} :: { [string]: { Layer } }

Sounds.MAX_PLAYING = 24 -- sounds at once
Sounds.REPEAT_SECONDS = 0.045 -- the same cue is not restarted sooner than this
Sounds.HEARD_FROM = 260 -- studs: a cue in the world fades out by this far away
Sounds.LONGEST_SECONDS = 4 -- the longest file, at normal speed

local playing = 0
local lastPlayed: { [string]: number } = {}
local muted = false

-- The pitch of the `streak`th hit in a row: up a small step each hit, eight
-- steps, then round again.
function Sounds.digPitch(streak: number): number
	return 1 + ((math.max(1, math.floor(streak)) - 1) % 8) * 0.025
end

-- How many sounds are playing now.
function Sounds.playingCount(): number
	return playing
end

-- Turns every sound off (or back on).
function Sounds.setMuted(value: boolean)
	muted = value
end

local function startLayer(layer: Layer, at: Vector3?, scale: number, shift: number)
	if playing >= Sounds.MAX_PLAYING then return end
	local file = Sounds.FILES[layer.file]
	if file == nil then return end
	local low, high = layer.pitch[1], layer.pitch[2] or layer.pitch[1]
	local pitch = (low + (high - low) * math.random()) / math.sqrt(math.max(scale, 0.25)) * shift
	local sound = Instance.new("Sound")
	sound.SoundId = file
	sound.Volume = math.min(2, layer.volume * math.sqrt(scale))
	sound.PlaybackSpeed = math.clamp(pitch, 0.2, 4)
	local holder: Instance
	if at then
		local spot = Instance.new("Attachment")
		spot.Position = at
		spot.Parent = workspace.Terrain
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 30 * scale
		sound.RollOffMaxDistance = Sounds.HEARD_FROM * math.max(1, scale)
		holder = spot
	else
		holder = SoundService
	end
	sound.Parent = holder
	playing += 1
	-- Its place is free again the moment it finishes, so holding dig (a dozen
	-- short sounds a second) never fills every place and cuts sounds out. A
	-- sound that never finishes (it failed to load) goes after the longest a
	-- file could take.
	local done = false
	local function finish()
		if done then return end
		done = true
		playing -= 1
		if holder ~= SoundService then holder:Destroy() else sound:Destroy() end
	end
	sound.Ended:Connect(finish)
	sound:Play()
	task.delay(Sounds.LONGEST_SECONDS / sound.PlaybackSpeed + 0.5, finish)
end

-- Plays cue `name`: at `at` in the world, or to the player when `at` is nil.
function Sounds.play(name: string, at: Vector3?, scale: number?, pitch: number?)
	if muted then return end
	local cue = Sounds.CUES[name]
	if cue == nil then return end
	local now = os.clock()
	if now - (lastPlayed[name] or -math.huge) < Sounds.REPEAT_SECONDS then return end
	lastPlayed[name] = now
	local size = scale or 1
	local shift = math.clamp(pitch or 1, 0.25, 4)
	for _, layer in cue do
		if layer.delay and layer.delay > 0 then
			task.delay(layer.delay, function()
				pcall(startLayer, layer, at, size, shift)
			end)
		else
			pcall(startLayer, layer, at, size, shift)
		end
	end
end

return Sounds
