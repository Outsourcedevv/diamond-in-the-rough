--!strict
-- First-person view with two hands in front of the camera (like the PC game).
-- The hands follow the camera, bob while walking and take turns digging: each
-- swing draws back, drives forward into the rock with the fingers clawed, and
-- rakes the rubble down and back. The rock breaks when a hand lands (see
-- FirstPerson.onStrike), so what you see and what you dig stay in step.
--
-- The hands are drawn small and close to the camera, so they never sink into
-- the rock when you stand right against it, and they are refitted to the
-- field of view (FirstPerson.setFieldOfView), so they look the same at any FOV.
--
-- Picking up the diamond: the gem flies from where it lay into your right hand,
-- the hand lifts it up and the camera eases upward so the gem is framed
-- against the sky and the mountain. The server freezes the holder in place
-- until a rebuild cancels the hold or the countdown is won.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FirstPerson = {}

local SKIN_FALLBACK = Color3.fromRGB(234, 184, 146)
local SLEEVE = Color3.fromRGB(70, 82, 70)
local GEM_SIZE = 1.05 -- studs across: about a third of the screen in the raised hand
local FLY_SECONDS = 0.45 -- world position to hand
local CAMERA_EASE = 0.7
local HOLD_PITCH = math.rad(28) -- looking up, but still showing the peak below the gem
local SWING_SECONDS = 0.25 -- one hand's swing; the server digs DigPerSecond / 4 rocks per strike
local IMPACT = 0.5 -- how far through a swing the hand lands
local VIEW_SCALE = 0.5 -- the hands are built at half size, half as far away: the same on screen
local BASE_FOV = 70 -- the field of view the hands were framed for
local PIVOT = Vector3.new(0, -0.92, -1.6) -- the hands' resting point in front of the camera

FirstPerson.SWING_SECONDS = SWING_SECONDS
FirstPerson.IMPACT = IMPACT
FirstPerson.FOV_MIN = 50
FirstPerson.FOV_MAX = 100
FirstPerson.FOV_DEFAULT = BASE_FOV

local function part(name: string, size: Vector3, colour: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function smooth(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end

-- One hand's pose through a swing (0 to 1), as offsets from its resting pose:
-- `inward` towards the middle of the screen, `up`, `back` towards the camera,
-- the hand's pitch (radians, positive tips the fingers up) and how far the
-- fingers curl (0 to 1). The pose starts and ends at rest, so swings chain
-- without a jump. Pure, for tests.
export type Pose = { inward: number, up: number, back: number, pitch: number, curl: number }
local KEYS: { { at: number, pose: Pose } } = {
	{ at = 0, pose = { inward = 0, up = 0, back = 0, pitch = 0, curl = 0.15 } },
	-- Draw back and up, wrist cocked.
	{ at = 0.34, pose = { inward = 0.03, up = 0.15, back = 0.16, pitch = math.rad(26), curl = 0.35 } },
	-- Drive forward and a little down into the rock, fingers clawed.
	{ at = IMPACT, pose = { inward = 0.2, up = -0.03, back = -0.6, pitch = math.rad(-16), curl = 0.92 } },
	-- Rake the rubble down and back.
	{ at = 0.8, pose = { inward = 0.13, up = -0.24, back = -0.18, pitch = math.rad(18), curl = 1 } },
	{ at = 1, pose = { inward = 0, up = 0, back = 0, pitch = 0, curl = 0.15 } },
}
function FirstPerson.pose(t: number): Pose
	t = math.clamp(t, 0, 1)
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if t <= b.at then
			local u = (t - a.at) / (b.at - a.at)
			-- The drive into the rock speeds up to the impact; everything else eases.
			u = if b.at == IMPACT then u * u else smooth(u)
			local p, q = a.pose, b.pose
			return {
				inward = p.inward + (q.inward - p.inward) * u,
				up = p.up + (q.up - p.up) * u,
				back = p.back + (q.back - p.back) * u,
				pitch = p.pitch + (q.pitch - p.pitch) * u,
				curl = p.curl + (q.curl - p.curl) * u,
			}
		end
	end
	return KEYS[#KEYS].pose
end

-- How much bigger the hands must be drawn at `fov` to look the same on screen
-- as at the field of view they were framed for.
function FirstPerson.fovScale(fov: number): number
	return math.tan(math.rad(fov) / 2) / math.tan(math.rad(BASE_FOV) / 2)
end

-- Where a point framed at the base field of view goes, in camera space, at a
-- field of view `scale` times wider (see fovScale): the hands grow about their
-- resting point, which moves out with the edge of the screen. Pure, for tests.
function FirstPerson.fit(frame: CFrame, scale: number): CFrame
	local p = frame.Position
	local fitted = Vector3.new(p.X * scale, p.Y * scale, PIVOT.Z + (p.Z - PIVOT.Z) * scale) * VIEW_SCALE
	return CFrame.new(fitted) * frame.Rotation
end

-- In the lobby the view is a normal third-person camera and the hands hide.
local enabled = true
local fieldOfView = BASE_FOV
local function applyCamera()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	if enabled then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 24
		player.CameraMinZoomDistance = 8
	end
	if camera then camera.FieldOfView = if enabled then fieldOfView else BASE_FOV end
end

function FirstPerson.setEnabled(on: boolean)
	enabled = on
	applyCamera()
end

-- The player's field of view in the game (the lobby keeps the default).
function FirstPerson.setFieldOfView(fov: number)
	fieldOfView = math.clamp(math.floor(fov + 0.5), FirstPerson.FOV_MIN, FirstPerson.FOV_MAX)
	-- Only the field of view: the zoom limits belong to whichever game is on.
	local camera = workspace.CurrentCamera
	if camera then camera.FieldOfView = if enabled then fieldOfView else BASE_FOV end
end

function FirstPerson.fieldOfView(): number
	return fieldOfView
end

-- `callback` runs each time a digging hand lands on the rock.
local strikeListeners: { () -> () } = {}
function FirstPerson.onStrike(callback: () -> ())
	table.insert(strikeListeners, callback)
end

function FirstPerson.start()
	local player = Players.LocalPlayer
	applyCamera()

	local rig = Instance.new("Model")
	rig.Name = "FirstPersonHands"
	local hands = {}
	local rigParts: { BasePart } = {}
	local skinParts: { BasePart } = {}
	local function add(p: BasePart, skin: boolean)
		p.Parent = rig
		table.insert(rigParts, p)
		if skin then table.insert(skinParts, p) end
	end
	for _, side in { -1, 1 } do
		local sleeve = part("Sleeve", Vector3.new(0.42, 0.42, 1.5), SLEEVE, Enum.Material.Fabric)
		local hand = part("Hand", Vector3.new(0.4, 0.34, 0.45), SKIN_FALLBACK)
		add(sleeve, false)
		add(hand, true)
		local fingers = {}
		for _ = 1, 4 do
			local finger = part("FingerBase", Vector3.new(0.075, 0.11, 0.14), SKIN_FALLBACK)
			local tip = part("FingerTip", Vector3.new(0.072, 0.10, 0.13), SKIN_FALLBACK)
			add(finger, true)
			add(tip, true)
			table.insert(fingers, { base = finger, tip = tip })
		end
		local thumb = part("Thumb", Vector3.new(0.12, 0.16, 0.21), SKIN_FALLBACK)
		add(thumb, true)
		table.insert(hands, { side = side, sleeve = sleeve, hand = hand, fingers = fingers, thumb = thumb })
	end
	local rigFrames: { CFrame } = table.create(#rigParts, CFrame.identity)
	local baseSizes: { Vector3 } = {}
	for i, p in rigParts do baseSizes[i] = p.Size end
	local skinColour = SKIN_FALLBACK
	-- The hands are resized only when the field of view changes.
	local fitScale = -1
	local function refit(scale: number)
		if math.abs(scale - fitScale) < 1e-4 then return end
		fitScale = scale
		for i, p in rigParts do p.Size = baseSizes[i] * (scale * VIEW_SCALE) end
	end

	local State = ReplicatedStorage:WaitForChild("DiamondRushState")
	local DiamondShape = require(ReplicatedStorage:WaitForChild("DiamondRush"):WaitForChild("DiamondShape"))
	local worldDiamond = workspace:WaitForChild("Diamond") :: BasePart

	-- The server rebuilds the world gem's facets whenever it changes size, so
	-- the facet folder is looked up again rather than cached.
	local hiddenFacets: Instance? = nil
	local function hideWorld(hidden: boolean)
		local facets = worldDiamond:FindFirstChild("Facets")
		local target = if hidden then facets else nil
		if target == hiddenFacets then return end
		if hiddenFacets and hiddenFacets.Parent then
			for _, face in hiddenFacets:GetChildren() do
				if face:IsA("BasePart") then face.LocalTransparencyModifier = 0 end
			end
		end
		hiddenFacets = target
		if target then
			for _, face in target:GetChildren() do
				if face:IsA("BasePart") then face.LocalTransparencyModifier = 1 end
			end
		end
	end

	-- The held gem: anchored facets moved in one call each frame (no welds).
	-- In the haystack skin it is a needle (see Skin).
	local gemKind = if State:GetAttribute("Skin") == "hay" then "needle" else "diamond"
	local gemScale = VIEW_SCALE
	local gem = DiamondShape.build(GEM_SIZE * gemScale, "HeldDiamond", gemKind)
	local core = part("Core", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1))
	core.Transparency = 1
	core.Parent = gem.model
	local shine = Instance.new("PointLight")
	shine.Color = Color3.fromRGB(160, 235, 255)
	shine.Range = 6
	shine.Brightness = 1.2
	shine.Shadows = false
	shine.Parent = core
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 235, 255))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0, 1)
	sparkles.Lifetime = NumberRange.new(0.3, 0.7)
	sparkles.Rate = 10
	sparkles.Speed = NumberRange.new(0.3, 0.9)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.LockedToPart = true
	sparkles.Enabled = false
	sparkles.Parent = core
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.OutlineTransparency = 0.35
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = gem.model
	-- A reskin, or a new field of view, rebuilds the held gem, carrying its
	-- light, sparkles and outline over.
	local function rebuildGem(kind: string, scale: number)
		if kind == gemKind and math.abs(scale - gemScale) < 1e-4 then return end
		gemKind = kind
		gemScale = scale
		local old = gem
		gem = DiamondShape.build(GEM_SIZE * scale, "HeldDiamond", kind)
		core.Parent = gem.model
		outline.Parent = gem.model
		gem.model.Parent = old.model.Parent
		old.model:Destroy()
	end
	State:GetAttributeChangedSignal("Skin"):Connect(function()
		rebuildGem(if State:GetAttribute("Skin") == "hay" then "needle" else "diamond", gemScale)
	end)

	local hiddenArms: { [BasePart]: number } = {}
	local armNames = { RightHand = true, RightLowerArm = true, RightUpperArm = true, LeftHand = true, LeftLowerArm = true, LeftUpperArm = true, ["Right Arm"] = true, ["Left Arm"] = true }
	local function restoreArms()
		for limb, transparency in hiddenArms do
			if limb.Parent then limb.LocalTransparencyModifier = transparency end
		end
		table.clear(hiddenArms)
	end
	player.CharacterRemoving:Connect(restoreArms)

	local function isHolding(): boolean
		-- Display names are not unique: only the actual holder gets this view.
		return State:GetAttribute("Phase") == "Holding" and State:GetAttribute("HolderUserId") == player.UserId
	end

	-- Hold state, set when the hold begins.
	local holdClock = 0
	local holdYaw = 0
	local startPitch = 0
	local gemFrom: CFrame? = nil
	local lastWorldGem: CFrame? = nil
	local wasHolding = false

	-- While you hold the diamond the camera is locked, easing up towards it.
	RunService:BindToRenderStep("DiamondRushHoldCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local holding = isHolding() and humanoid ~= nil and humanoid.Health > 0
		if not holding and State:GetAttribute("Phase") == "Revealed" then
			lastWorldGem = worldDiamond.CFrame
		end
		if holding and camera and head and head:IsA("BasePart") then
			if not wasHolding then
				wasHolding = true
				holdClock = os.clock()
				local look = camera.CFrame.LookVector
				holdYaw = math.atan2(-look.X, -look.Z)
				startPitch = math.asin(math.clamp(look.Y, -1, 1))
				gemFrom = lastWorldGem
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local t = os.clock() - holdClock
			local pitch = startPitch + (HOLD_PITCH - startPitch) * smooth(t / CAMERA_EASE)
			local breathe = math.sin(t * 1.6) * math.rad(0.6)
			camera.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.6, 0))
				* CFrame.Angles(0, holdYaw + breathe * 0.5, 0) * CFrame.Angles(pitch + breathe, 0, 0)
		elseif wasHolding then
			wasHolding = false
			gemFrom = nil
			if camera then
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end)

	local cycle = 1 -- how far through the current swing (1 = at rest)
	local swingSide = 1 -- the hand swinging now; the hands take turns
	local struck = true -- whether this swing has landed yet
	local kick = 0 -- a small jolt through both hands as one lands
	local bob = 0
	local lift = 0 -- 0 = digging pose, 1 = diamond raised high

	-- Position the hands after both Roblox's camera and our hold-camera update.
	RunService:BindToRenderStep("DiamondRushHands", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not enabled or camera == nil or character == nil or humanoid == nil or humanoid.Health <= 0 then
			rig.Parent = nil
			gem.model.Parent = nil
			sparkles.Enabled = false
			restoreArms()
			hideWorld(false)
			cycle, struck = 1, true
			return
		end
		rig.Parent = camera
		if camera.FieldOfView ~= fieldOfView then camera.FieldOfView = fieldOfView end
		local scale = FirstPerson.fovScale(camera.FieldOfView)
		refit(scale)
		-- Scriptable cameras bypass the normal first-person transparency controller.
		-- Hide the real limbs so they cannot float above the custom hands.
		for _, limb in character:GetChildren() do
			if limb:IsA("BasePart") and armNames[limb.Name] and hiddenArms[limb] == nil then
				hiddenArms[limb] = limb.LocalTransparencyModifier
				limb.LocalTransparencyModifier = 1
			end
		end
		-- Skin tone from the avatar, applied only when it changes.
		local colours = character:FindFirstChildOfClass("BodyColors")
		local skin = if colours then colours.RightArmColor3 else SKIN_FALLBACK
		if skin ~= skinColour then
			skinColour = skin
			for _, p in skinParts do p.Color = skin end
		end
		local tool = character:FindFirstChildOfClass("Tool")
		-- Keep any third-person tool from obscuring the local hand and diamond.
		if tool then
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 end
			end
		end
		local moving = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
		bob += dt * (if moving then 9 else 2)
		-- Walking sways the hands; digging steadies them.
		local sway = if moving then 0.04 else 0.012
		local holding = isHolding()
		local digging = player:GetAttribute("DiggingRock") == true and not holding
		-- A swing always finishes once begun, so letting go never snaps the
		-- hand back; the next one starts, with the other hand, while you dig.
		if holding then
			cycle, struck = 1, true
		else
			if cycle >= 1 and digging then
				cycle, struck = 0, false
				swingSide = -swingSide
			end
			if cycle < 1 then
				cycle = math.min(1, cycle + dt / SWING_SECONDS)
				if not struck and cycle >= IMPACT then
					struck = true
					kick = 1
					if digging then
						for _, callback in strikeListeners do task.spawn(callback) end
					end
				end
			end
		end
		kick = math.max(0, kick - dt * 9)
		lift += ((if holding then 1 else 0) - lift) * (1 - math.exp(-dt * 8))
		hideWorld(holding)
		local worldLight = worldDiamond:FindFirstChildOfClass("PointLight")
		if worldLight then worldLight.Enabled = State:GetAttribute("Phase") == "Holding" and not holding end
		if holding then
			-- The world gem's sparkles are for everyone else watching.
			local worldSparkles = worldDiamond:FindFirstChild("HeldSparkles", true)
			if worldSparkles and worldSparkles:IsA("ParticleEmitter") then worldSparkles.Enabled = false end
		end

		-- Everything below is framed in camera space at the base field of view,
		-- then fitted to the camera (see FirstPerson.fit).
		local index = 0
		local function put(frame: CFrame)
			index += 1
			rigFrames[index] = camera.CFrame * FirstPerson.fit(frame, scale)
		end
		local jolt = kick * kick * 0.035
		local base = CFrame.new(PIVOT + Vector3.new(math.sin(bob * 0.5) * sway * 0.4, math.sin(bob) * sway * 0.45 - jolt, jolt))
		local swing = FirstPerson.pose(cycle)
		-- The resting hand braces a little while the other one drives in.
		local brace = math.sin(math.clamp(cycle / 0.8, 0, 1) * math.pi)
		local palm = CFrame.identity
		for _, h in hands do
			local active = h.side == swingSide
			local p = if active then swing else nil
			local inward = if p then p.inward else 0
			local up = if p then p.up else -0.04 * brace
			local back = if p then p.back else 0.07 * brace
			local pitch = if p then p.pitch else math.rad(-4) * brace
			local normal = base * CFrame.new(h.side * (0.58 - inward * (1 - lift)), up * (1 - lift), back * (1 - lift))
				* CFrame.Angles(math.rad(10) + pitch * (1 - lift), math.rad(-h.side * (8 + inward * 50)), math.rad(-h.side * inward * 30))
			-- The right hand rises to the right of centre, under the countdown;
			-- the left hand drops out of view.
			local raised = if h.side == 1
				then CFrame.new(0.5, -0.62, -1.7) * CFrame.Angles(math.rad(34), math.rad(-12), math.rad(-6))
				else normal * CFrame.new(0, -1.6, 0.3)
			local arm = normal:Lerp(raised, smooth(lift))
			put(arm * CFrame.new(0, 0, 0.46))
			local handFrame = arm * CFrame.new(0, 0, -0.35)
			put(handFrame)
			if h.side == 1 then palm = handFrame end
			local curl = if p then p.curl else 0.15
			local grip = math.max(if h.side == 1 then lift else 0, curl * (1 - lift))
			for fingerIndex, _ in h.fingers do
				local bend = grip * (0.85 + fingerIndex * 0.035)
				local joint = handFrame * CFrame.new((fingerIndex - 2.5) * 0.09, 0, -0.20) * CFrame.Angles(math.rad(-46 * bend), 0, 0)
				put(joint * CFrame.new(0, 0, -0.07))
				put(joint * CFrame.new(0, 0, -0.14) * CFrame.Angles(math.rad(-54 * bend), 0, 0) * CFrame.new(0, 0, -0.065))
			end
			put(handFrame * CFrame.new(-h.side * 0.17, 0.015, -0.08)
				* CFrame.Angles(math.rad(-35 * grip), math.rad(h.side * 20 * grip), math.rad(h.side * (15 + 35 * grip))))
		end
		workspace:BulkMoveTo(rigParts, rigFrames, Enum.BulkMoveMode.FireCFrameChanged)

		if holding then
			rebuildGem(gemKind, scale * VIEW_SCALE)
			local t = os.clock() - holdClock
			-- Upright in the world, crown tipped towards you, slowly turning.
			local spin = t * 0.9
			local seat = camera.CFrame * FirstPerson.fit(palm * CFrame.new(0, 0.17 + GEM_SIZE * 0.6, -0.05), scale)
			local target = CFrame.new(seat.Position) * CFrame.Angles(0, holdYaw, 0) * CFrame.Angles(math.rad(20), 0, 0) * CFrame.Angles(0, spin, 0)
			local frame = target
			local from = gemFrom
			if from and t < FLY_SECONDS then
				-- Arc from where the gem lay into the hand.
				local u = smooth(t / FLY_SECONDS)
				frame = from:Lerp(target, u) + Vector3.new(0, math.sin(u * math.pi) * 0.9, 0)
			end
			gem.model.Parent = camera
			DiamondShape.place(gem, frame)
			core.CFrame = frame
			-- A bright flash as it lands, settling to a steady glow.
			shine.Brightness = 1.2 + 3 * math.max(0, 1 - math.abs(t - FLY_SECONDS) / 0.35)
			sparkles.Enabled = t >= FLY_SECONDS * 0.5
		else
			sparkles.Enabled = false
			gem.model.Parent = nil
		end
	end)
end

return FirstPerson
