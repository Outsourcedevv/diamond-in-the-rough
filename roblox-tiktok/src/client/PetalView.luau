--!strict
-- Cherry petals drift down around the camera while the map shows the sakura
-- theme and this player is in the game (not the lobby). The petals are local
-- parts in a box that follows the camera: each falls, sways and tumbles on its
-- own path, wrapping round the box, so the air stays full wherever you look
-- for the cost of one BulkMoveTo a frame.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PetalView = {}

local COUNT = 90
local BOX = Vector3.new(80, 40, 80) -- studs round the camera
local PINKS = {
	Color3.fromRGB(255, 228, 236),
	Color3.fromRGB(255, 206, 220),
	Color3.fromRGB(255, 186, 204),
	Color3.fromRGB(249, 163, 187),
}

type Petal = { seed: Vector3, fall: number, sway: number, phase: number, spin: Vector3 }

-- Wraps `value` into [0, size).
local function wrap(value: number, size: number): number
	return value - math.floor(value / size) * size
end

-- Where a petal is at time `t`, inside the box round `centre`. Pure, for tests.
function PetalView.frame(petal: Petal, t: number, centre: Vector3): CFrame
	local drift = petal.seed + Vector3.new(
		math.sin(t * petal.sway + petal.phase) * 2.2 + t * 1.1,
		-t * petal.fall,
		math.cos(t * petal.sway * 0.8 + petal.phase) * 1.6 + t * 0.4
	)
	local corner = centre - BOX / 2
	local at = corner + Vector3.new(wrap(drift.X - corner.X, BOX.X), wrap(drift.Y - corner.Y, BOX.Y), wrap(drift.Z - corner.Z, BOX.Z))
	return CFrame.new(at) * CFrame.Angles(t * petal.spin.X, t * petal.spin.Y, t * petal.spin.Z)
end

function PetalView.start(state: Instance)
	local player = Players.LocalPlayer
	local random = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "SakuraPetals"
	local parts: { BasePart } = {}
	local petals: { Petal } = {}
	local frames: { CFrame } = {}
	for i = 1, COUNT do
		local part = Instance.new("Part")
		part.Name = "Petal"
		part.Size = Vector3.new(0.34, 0.04, 0.26)
		part.Color = PINKS[random:NextInteger(1, #PINKS)]
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
		parts[i] = part
		petals[i] = {
			seed = Vector3.new(random:NextNumber(0, BOX.X), random:NextNumber(0, BOX.Y), random:NextNumber(0, BOX.Z)),
			fall = random:NextNumber(1.6, 3.2),
			sway = random:NextNumber(0.6, 1.4),
			phase = random:NextNumber(0, math.pi * 2),
			spin = Vector3.new(random:NextNumber(-2.5, 2.5), random:NextNumber(-1.5, 1.5), random:NextNumber(-2.5, 2.5)),
		}
		frames[i] = CFrame.identity
	end
	local connection: RBXScriptConnection? = nil
	local function refresh()
		local on = state:GetAttribute("Theme") == "sakura" and player:GetAttribute("InGame") == true
		if on and connection == nil then
			folder.Parent = workspace
			connection = RunService.RenderStepped:Connect(function()
				local camera = workspace.CurrentCamera
				if camera == nil then return end
				local t = os.clock()
				local centre = camera.CFrame.Position
				for i, petal in petals do
					frames[i] = PetalView.frame(petal, t, centre)
				end
				workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			end)
		elseif not on and connection ~= nil then
			(connection :: RBXScriptConnection):Disconnect()
			connection = nil
			folder.Parent = nil
		end
	end
	state:GetAttributeChangedSignal("Theme"):Connect(refresh)
	player:GetAttributeChangedSignal("InGame"):Connect(refresh)
	refresh()
end

return PetalView
