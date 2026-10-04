--!strict
-- First-person view with two hands in front of the camera (like the PC game).
-- The hands follow the camera, bob while walking and swing when you click.
-- You dig with your hands: each click punches with the other hand.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FirstPerson = {}

local SKIN_FALLBACK = Color3.fromRGB(234, 184, 146)
local SLEEVE = Color3.fromRGB(70, 82, 70)

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

function FirstPerson.start()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	local rig = Instance.new("Model")
	rig.Name = "FirstPersonHands"
	local hands = {}
	for _, side in { -1, 1 } do
		local sleeve = part("Sleeve", Vector3.new(0.42, 0.42, 1.5), SLEEVE, Enum.Material.Fabric)
		local hand = part("Hand", Vector3.new(0.4, 0.34, 0.45), SKIN_FALLBACK)
		sleeve.Parent = rig
		hand.Parent = rig
		local fingers = {}
		for index = 1, 4 do
			local finger = part("Finger", Vector3.new(0.075, 0.11, 0.19), SKIN_FALLBACK)
			finger.Parent = rig
			table.insert(fingers, finger)
		end
		local thumb = part("Thumb", Vector3.new(0.12, 0.16, 0.21), SKIN_FALLBACK)
		thumb.Parent = rig
		table.insert(hands, { side = side, sleeve = sleeve, hand = hand, fingers = fingers, thumb = thumb })
	end

	local State = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRushState")
	local worldDiamond = workspace:WaitForChild("Diamond") :: BasePart
	local gem = part("HeldDiamond", worldDiamond.Size, worldDiamond.Color, Enum.Material.Glass)
	gem.Reflectance = 0.35
	gem.Transparency = 1
	local shine = Instance.new("PointLight")
	shine.Color = Color3.fromRGB(150, 235, 255)
	shine.Range = 4
	shine.Brightness = 0.7
	shine.Enabled = false
	shine.Parent = gem
	gem.Parent = rig
	local lift = 0 -- 0 = digging pose, 1 = diamond raised to the sky
	local function isHolding(): boolean
		-- Display names are not unique: only the actual holder gets this view.
		return State:GetAttribute("Phase") == "Holding" and State:GetAttribute("HolderUserId") == player.UserId
	end

	-- While you hold the diamond the camera is locked, tilted up towards it.
	local lockedYaw: number? = nil
	RunService:BindToRenderStep("DiamondRushHoldCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local holding = isHolding() and humanoid ~= nil and humanoid.Health > 0
		if holding and camera and head and head:IsA("BasePart") then
			if lockedYaw == nil then
				local look = camera.CFrame.LookVector
				lockedYaw = math.atan2(-look.X, -look.Z)
				camera.CameraType = Enum.CameraType.Scriptable
			end
			camera.CFrame = CFrame.new(head.Position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, lockedYaw :: number, 0) * CFrame.Angles(math.rad(62), 0, 0)
		elseif lockedYaw ~= nil then
			lockedYaw = nil
			if camera then
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end)
	local swing = 0
	local punchSide = 1
	local bob = 0
	local held = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			held = true
			swing = 1
			punchSide = -punchSide
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			held = false
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
	end)

	-- Position the hands after both Roblox's camera and our hold-camera update.
	RunService:BindToRenderStep("DiamondRushHands", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if camera == nil or character == nil or humanoid == nil or humanoid.Health <= 0 then
			rig.Parent = nil
			worldDiamond.LocalTransparencyModifier = 0
			return
		end
		rig.Parent = camera
		-- Skin tone from the avatar.
		local colours = character:FindFirstChildOfClass("BodyColors")
		local skin = if colours then colours.RightArmColor3 else SKIN_FALLBACK
		local tool = character:FindFirstChildOfClass("Tool")
		-- Keep any third-person tool from obscuring the local hand and diamond.
		if tool then
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
				end
			end
		end
		local moving = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
		bob += dt * (if moving then 9 else 2)
		local sway = if moving then 0.05 else 0.015
		swing = math.max(0, swing - dt * 7)
		-- Holding dig keeps both hands tearing at the rock in turn.
		local holding = isHolding()
		if holding then held = false end
		if held and swing <= 0 then
			swing = 1
			punchSide = -punchSide
		end
		local strike = math.sin(swing * math.pi)
		-- While you hold the diamond your right hand lifts it to the sky.
		lift += ((if holding then 1 else 0) - lift) * math.min(1, dt * 8)
		worldDiamond.LocalTransparencyModifier = if holding then 1 else 0
		local worldLight = worldDiamond:FindFirstChildOfClass("PointLight")
		if worldLight then worldLight.Enabled = State:GetAttribute("Phase") == "Holding" and not holding end
		if lift > 0.01 then
			strike = 0
		end
		local base = camera.CFrame * CFrame.new(0, -0.95 + math.abs(math.sin(bob)) * sway, -1.6)
		for _, h in hands do
			local hit = if h.side == punchSide then strike else 0
			local normal = base * CFrame.new(h.side * 0.75, hit * 0.25, -hit * 0.4)
				* CFrame.Angles(math.rad(10 + hit * -55), math.rad(-h.side * 8), 0)
			-- Camera-relative grip stays below the countdown, well inside the lens.
			-- 62-degree camera tilt + 28-degree arm tilt still points up at the sky.
			local raised = if h.side == 1
				then camera.CFrame * CFrame.new(0.30, -0.56, -1.65) * CFrame.Angles(math.rad(28), math.rad(-8), math.rad(-10))
				else normal * CFrame.new(0, -1.6, 0.3)
			local arm = normal:Lerp(raised, lift)
			h.sleeve.CFrame = arm * CFrame.new(0, 0, 0.55)
			h.hand.CFrame = arm * CFrame.new(0, 0, -0.35)
			h.hand.Color = skin
			h.hand.LocalTransparencyModifier = 0
			local grip = if h.side == 1 then lift else 0
			for index, finger in h.fingers do
				finger.Color = skin
				finger.CFrame = h.hand.CFrame * CFrame.new((index - 2.5) * 0.09, grip * 0.16, -0.27 + grip * 0.16)
					* CFrame.Angles(math.rad(-45 * grip), 0, 0)
			end
			h.thumb.Color = skin
			h.thumb.CFrame = h.hand.CFrame * CFrame.new(-h.side * 0.21, grip * 0.16, -0.08)
				* CFrame.Angles(math.rad(-25 * grip), 0, math.rad(h.side * 22))
		end
		gem.Transparency = if holding and lift > 0.3 then 0.1 else 1
		shine.Enabled = holding and lift > 0.3
		local palm = hands[2].hand.CFrame
		gem.CFrame = palm * CFrame.new(0, 0.34, -0.08) * CFrame.Angles(math.rad(45), 0, math.rad(35))
	end)
end

return FirstPerson
