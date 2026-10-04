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
		table.insert(hands, { side = side, sleeve = sleeve, hand = hand })
	end
	local pickHandle = part("PickHandle", Vector3.new(0.12, 1.6, 0.12), Color3.fromRGB(122, 84, 52), Enum.Material.Wood)
	local pickHead = part("PickHead", Vector3.new(1.1, 0.16, 0.16), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
	pickHandle.Parent = rig
	pickHead.Parent = rig

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

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if camera == nil or character == nil or humanoid == nil or humanoid.Health <= 0 then
			rig.Parent = nil
			return
		end
		rig.Parent = camera
		-- Skin tone from the avatar.
		local colours = character:FindFirstChildOfClass("BodyColors")
		local skin = if colours then colours.RightArmColor3 else SKIN_FALLBACK
		local tool = character:FindFirstChildOfClass("Tool")
		-- Hide the third-person tool; the hands show their own pickaxe.
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
		if held and swing <= 0 then
			swing = 1
			punchSide = -punchSide
		end
		local strike = math.sin(swing * math.pi)
		local base = camera.CFrame * CFrame.new(0, -0.95 + math.abs(math.sin(bob)) * sway, -1.6)
		for _, h in hands do
			local hit = if h.side == punchSide then strike else 0
			local arm = base
				* CFrame.new(h.side * 0.75, hit * 0.25, -hit * 0.4)
				* CFrame.Angles(math.rad(10 + hit * -55), math.rad(-h.side * 8), 0)
			h.sleeve.CFrame = arm * CFrame.new(0, 0, 0.55)
			h.hand.CFrame = arm * CFrame.new(0, 0, -0.35)
			h.hand.Color = skin
		end
		pickHandle.Transparency = 1
		pickHead.Transparency = pickHandle.Transparency
		local grip = hands[2].hand.CFrame * CFrame.Angles(math.rad(-70), 0, 0)
		pickHandle.CFrame = grip * CFrame.new(0, 0.55, 0)
		pickHead.CFrame = pickHandle.CFrame * CFrame.new(0, 0.75, 0)
	end)
end

return FirstPerson
