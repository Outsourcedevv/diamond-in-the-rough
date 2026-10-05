--!strict
-- First-person view with two hands in front of the camera (like the PC game).
-- The hands follow the camera, bob while walking and alternate reaching,
-- curling around stone and raking rubble back while digging.
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

function FirstPerson.start()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

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
	local skinColour = SKIN_FALLBACK

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
	local gem = DiamondShape.build(GEM_SIZE, "HeldDiamond")
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

	local cycle = 1
	local punchSide = 1
	local bob = 0
	local digBlend = 0
	local lift = 0 -- 0 = digging pose, 1 = diamond raised high

	-- Position the hands after both Roblox's camera and our hold-camera update.
	RunService:BindToRenderStep("DiamondRushHands", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if camera == nil or character == nil or humanoid == nil or humanoid.Health <= 0 then
			rig.Parent = nil
			gem.model.Parent = nil
			sparkles.Enabled = false
			restoreArms()
			hideWorld(false)
			return
		end
		rig.Parent = camera
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
		local sway = if moving then 0.05 else 0.015
		local holding = isHolding()
		local digging = player:GetAttribute("DiggingRock") == true and not holding
		digBlend += ((if digging then 1 else 0) - digBlend) * (1 - math.exp(-dt * 14))
		if holding then
			cycle = 1
		elseif cycle < 1 then
			cycle = math.min(1, cycle + dt / 0.46)
		elseif digging then
			cycle = 0
			punchSide = -punchSide
		end
		-- Wind up, reach quickly into the stone, rake down, then pull the rubble back.
		local wind = smooth(cycle / 0.18) * (1 - smooth((cycle - 0.18) / 0.16))
		local reach = smooth((cycle - 0.18) / 0.20)
		local pull = smooth((cycle - 0.48) / 0.52)
		local extension = reach * (1 - pull) * digBlend
		local scoop = math.sin(math.clamp((cycle - 0.38) / 0.62, 0, 1) * math.pi) * digBlend
		lift += ((if holding then 1 else 0) - lift) * (1 - math.exp(-dt * 8))
		hideWorld(holding)
		local worldLight = worldDiamond:FindFirstChildOfClass("PointLight")
		if worldLight then worldLight.Enabled = State:GetAttribute("Phase") == "Holding" and not holding end
		if holding then
			-- The world gem's sparkles are for everyone else watching.
			local worldSparkles = worldDiamond:FindFirstChild("HeldSparkles", true)
			if worldSparkles and worldSparkles:IsA("ParticleEmitter") then worldSparkles.Enabled = false end
		end

		local index = 0
		local function put(frame: CFrame)
			index += 1
			rigFrames[index] = frame
		end
		local base = camera.CFrame * CFrame.new(math.sin(bob * 0.5) * sway * 0.4, -0.92 + math.sin(bob) * sway * 0.45, -1.6)
		local palm = CFrame.identity
		for _, h in hands do
			local active = if h.side == punchSide then 1 - lift else 0
			local hit = extension * active
			local rake = scoop * active
			local prep = wind * digBlend * active
			local support = if h.side ~= punchSide then extension * (1 - lift) else 0
			local normal = base * CFrame.new(h.side * (0.58 - hit * 0.24), hit * 0.27 - rake * 0.19 + support * 0.05, -hit * 0.62 + prep * 0.12 + rake * 0.16 - support * 0.08)
				* CFrame.Angles(math.rad(10 - hit * 22 + rake * 34 + prep * 12), math.rad(-h.side * (8 + hit * 12)), math.rad(h.side * (rake * 16 - hit * 8)))
			-- The right hand rises to the right of centre, under the countdown;
			-- the left hand drops out of view.
			local raised = if h.side == 1
				then camera.CFrame * CFrame.new(0.5, -0.62, -1.7) * CFrame.Angles(math.rad(34), math.rad(-12), math.rad(-6))
				else normal * CFrame.new(0, -1.6, 0.3)
			local arm = normal:Lerp(raised, smooth(lift))
			put(arm * CFrame.new(0, 0, 0.46))
			local handFrame = arm * CFrame.new(0, 0, -0.35)
			put(handFrame)
			if h.side == 1 then palm = handFrame end
			local grip = math.max(if h.side == 1 then lift else 0, rake * 0.85)
			for fingerIndex, _ in h.fingers do
				local curl = grip * (0.85 + fingerIndex * 0.035)
				local joint = handFrame * CFrame.new((fingerIndex - 2.5) * 0.09, 0, -0.20) * CFrame.Angles(math.rad(-46 * curl), 0, 0)
				put(joint * CFrame.new(0, 0, -0.07))
				put(joint * CFrame.new(0, 0, -0.14) * CFrame.Angles(math.rad(-54 * curl), 0, 0) * CFrame.new(0, 0, -0.065))
			end
			put(handFrame * CFrame.new(-h.side * 0.17, 0.015, -0.08)
				* CFrame.Angles(math.rad(-35 * grip), math.rad(h.side * 20 * grip), math.rad(h.side * (15 + 35 * grip))))
		end
		workspace:BulkMoveTo(rigParts, rigFrames, Enum.BulkMoveMode.FireCFrameChanged)

		if holding then
			local t = os.clock() - holdClock
			-- Upright in the world, crown tipped towards you, slowly turning.
			local spin = t * 0.9
			local seat = palm * CFrame.new(0, 0.17 + GEM_SIZE * 0.6, -0.05)
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
