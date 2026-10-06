--!strict
-- The diamond bird: every 5 to 7½ minutes a sparkling bird made of diamond
-- circles the mountain. Click it and every gift counts double (blasting and
-- adding stone alike) for 30 seconds. If nobody catches it, it flies off when
-- the next bird arrives. Each client flies its own copy smoothly (BirdView);
-- the server only says when it arrived and when it left.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local BirdBonus = require(Shared:WaitForChild("BirdBonus"))
local DiamondShape = require(Shared:WaitForChild("DiamondShape"))

local DiamondBird = {}

local ICE = Color3.fromRGB(135, 222, 255)
local PALE = Color3.fromRGB(215, 248, 255)
local GOLD = Color3.fromRGB(255, 200, 70)

local function piece(model: Model, name: string, class: string, size: Vector3, at: CFrame, colour: Color3, material: Enum.Material, wing: number?): BasePart
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Color = colour
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if material == Enum.Material.Glass then
		part.Transparency = 0.15
		part.Reflectance = 0.25
	end
	-- Wing pieces beat about the shoulder on that side (-1 left, 1 right).
	if wing then part:SetAttribute("Wing", wing) end
	part.Parent = model
	return part
end

-- Gem facets are posed directly: the bird is not in the workspace yet, where
-- DiamondShape.place would move them.
local function gem(model: Model, size: number, name: string, at: CFrame)
	local built = DiamondShape.build(size, name)
	for index, facet in built.parts do
		facet.CFrame = at * built.offsets[index]
		facet.Parent = model
	end
end

-- About 6 studs long with a 10-stud wingspan, facing -Z with its centre at the origin.
local function build(): Model
	local model = Instance.new("Model")
	model.Name = "DiamondBird"
	-- An invisible box around the whole bird takes the clicks, so a bird in
	-- flight is easy to hit; the diamond facets themselves cannot be clicked.
	local hitbox = piece(model, "Hitbox", "Part", Vector3.new(11, 4.5, 7.5), CFrame.new(), ICE, Enum.Material.SmoothPlastic)
	hitbox.Transparency = 1
	hitbox.CanQuery = true
	model.PrimaryPart = hitbox

	-- The body is a brilliant-cut diamond lying on its side: the crown faces
	-- forward into the head and the long point makes the tail.
	gem(model, 3.4, "Body", CFrame.Angles(-math.pi / 2, 0, 0))
	-- A smaller gem rides on its head like a crest.
	gem(model, 0.9, "Crest", CFrame.new(0, 1.55, -2.05))

	local head = piece(model, "Head", "Part", Vector3.new(1.5, 1.5, 1.5), CFrame.new(0, 0.55, -2.05), ICE, Enum.Material.Glass);
	(head :: Part).Shape = Enum.PartType.Ball
	-- A wedge's thin edge is at its front, so it points the way the bird flies.
	piece(model, "Beak", "WedgePart", Vector3.new(0.45, 0.4, 0.9), CFrame.new(0, 0.4, -3.15), GOLD, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		local eye = piece(model, "Eye", "Part", Vector3.new(0.3, 0.3, 0.3), CFrame.new(side * 0.55, 0.8, -2.6), Color3.fromRGB(20, 24, 40), Enum.Material.SmoothPlastic);
		(eye :: Part).Shape = Enum.PartType.Ball
		local glint = piece(model, "Glint", "Part", Vector3.new(0.1, 0.1, 0.1), CFrame.new(side * 0.6, 0.88, -2.74), PALE, Enum.Material.Neon);
		(glint :: Part).Shape = Enum.PartType.Ball

		-- Three stepped panes of ice-blue glass sweep back from the shoulder,
		-- each edged with a bright strip, so the wing reads as feathers.
		local panes = {
			{ length = 2.4, depth = 2.0, out = 1.0, back = 0.1 },
			{ length = 2.0, depth = 1.5, out = 3.0, back = 0.35 },
			{ length = 1.7, depth = 1.0, out = 4.6, back = 0.7 },
		}
		for index, pane in panes do
			local x = side * (pane.out + pane.length / 2)
			local sweep = CFrame.new(x, 0.45, pane.back) * CFrame.Angles(0, -side * math.rad(8 * index), 0)
			piece(model, "Feather", "Part", Vector3.new(pane.length, 0.14, pane.depth), sweep, if index % 2 == 0 then PALE else ICE, Enum.Material.Glass, side)
			piece(model, "FeatherEdge", "Part", Vector3.new(pane.length, 0.18, 0.18), sweep * CFrame.new(0, 0, -pane.depth / 2), PALE, Enum.Material.Neon, side)
		end
	end
	-- A fan of tail feathers behind the gem's point.
	for index = -1, 1 do
		local fan = CFrame.new(index * 0.45, 0.15, 2.6) * CFrame.Angles(0, index * math.rad(22), 0)
		piece(model, "Tail", "Part", Vector3.new(0.5, 0.12, 2.3), fan, ICE, Enum.Material.Glass)
		piece(model, "TailTip", "Part", Vector3.new(0.55, 0.16, 0.3), fan * CFrame.new(0, 0, 1.15), PALE, Enum.Material.Neon)
	end

	local light = Instance.new("PointLight")
	light.Color = ICE
	light.Range = 16
	light.Brightness = 2.5
	light.Parent = hitbox
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(PALE, ICE)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = 18
	sparkles.Speed = NumberRange.new(0.5, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = hitbox
	-- A white outline keeps it easy to spot on stream, even against snow or sky.
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.OutlineTransparency = 0.3
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	return model
end

export type Options = {
	state: Configuration,
	notify: RemoteEvent,
	radius: number, -- the circuit round the mountain
	height: () -> number, -- cruising height, read as each bird arrives
	random: Random?,
}
export type Bird = {
	multiplier: () -> number,
	spawn: () -> (),
	catch: (player: Player) -> boolean,
}

-- How far from the bird a catch may be: the bird is flown by each client, so
-- the server checks the player is roughly in sight of where it should be.
DiamondBird.CATCH_RANGE = 300

function DiamondBird.start(options: Options): Bird
	local random = options.random or Random.new()
	local state = options.state
	local current: Model? = nil
	local boostUntil = 0
	local boostId = 0
	state:SetAttribute("BirdBoostUntil", 0)
	state:SetAttribute("BirdCatcher", "")

	local function leave(bird: Model)
		if bird:GetAttribute("LeaveAt") ~= 0 then return end
		bird:SetAttribute("LeaveAt", workspace:GetServerTimeNow())
		local click = bird:FindFirstChildOfClass("ClickDetector")
		if click then click.MaxActivationDistance = 0 end
		if current == bird then current = nil end
		task.delay(BirdBonus.LEAVE_SECONDS + 0.5, function() bird:Destroy() end)
	end

	local function caught(player: Player, bird: Model): boolean
		if bird ~= current or bird:GetAttribute("LeaveAt") ~= 0 or player:GetAttribute("InGame") ~= true then return false end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then return false end
		leave(bird)
		-- Catching another bird while the bonus runs restarts the 30 seconds.
		boostUntil = workspace:GetServerTimeNow() + Config.BirdBoostSeconds
		boostId += 1
		local id = boostId
		state:SetAttribute("BirdBoostUntil", boostUntil)
		state:SetAttribute("BirdCatcher", player.DisplayName)
		options.notify:FireAllClients("feed", {
			text = string.format("%s caught the diamond bird! Gifts x%d for %d s", player.DisplayName, Config.BirdMultiplier, Config.BirdBoostSeconds),
			stone = 0,
			kind = "gift",
		})
		task.delay(Config.BirdBoostSeconds, function()
			if boostId ~= id then return end
			options.notify:FireAllClients("feed", { text = "Double gifts are over", stone = 0, kind = "notice" })
		end)
		return true
	end

	-- A click the client aimed at the bird it flies (see BirdView). Clicks in
	-- first person don't always reach the ClickDetector, so this is the main way
	-- to catch it; the server checks the bird is still circling and that the
	-- player is within range of where the shared flight path puts it now.
	local function catch(player: Player): boolean
		local bird = current
		if bird == nil or bird:GetAttribute("LeaveAt") ~= 0 then return false end
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if head == nil or not head:IsA("BasePart") then return false end
		local path: BirdBonus.Path = {
			radius = tonumber(bird:GetAttribute("Radius")) or options.radius,
			height = tonumber(bird:GetAttribute("Height")) or 0,
			angle = tonumber(bird:GetAttribute("Angle")) or 0,
			direction = tonumber(bird:GetAttribute("Direction")) or 1,
		}
		local start = tonumber(bird:GetAttribute("Start")) or workspace:GetServerTimeNow()
		local x, y, z = BirdBonus.position(path, workspace:GetServerTimeNow() - start)
		if (head.Position - Vector3.new(x, y, z)).Magnitude > DiamondBird.CATCH_RANGE then return false end
		return caught(player, bird)
	end

	local function spawn()
		local previous = current
		if previous then leave(previous) end
		local bird = build()
		local path: BirdBonus.Path = {
			radius = options.radius,
			height = options.height(),
			-- It arrives on the camp's side of the mountain (+Z), where the streamer looks.
			angle = math.pi / 2 + random:NextNumber(-0.7, 0.7),
			direction = if random:NextNumber() < 0.5 then 1 else -1,
		}
		bird:SetAttribute("Start", workspace:GetServerTimeNow())
		bird:SetAttribute("LeaveAt", 0)
		bird:SetAttribute("Radius", path.radius)
		bird:SetAttribute("Height", path.height)
		bird:SetAttribute("Angle", path.angle)
		bird:SetAttribute("Direction", path.direction)
		local x, y, z = BirdBonus.position(path, BirdBonus.ARRIVE_SECONDS)
		bird:PivotTo(CFrame.new(x, y, z))
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 400
		click.Parent = bird
		click.MouseClick:Connect(function(player: Player) caught(player, bird) end)
		bird.Parent = workspace
		current = bird
		options.notify:FireAllClients("feed", { text = "A diamond bird appeared! Click it for double gifts", stone = 0, kind = "notice" })
	end

	task.spawn(function()
		while true do
			task.wait(BirdBonus.nextDelay(random:NextNumber(), Config.BirdMinSeconds, Config.BirdMaxSeconds))
			local ok, problem = pcall(spawn)
			if not ok then warn("[DiamondRush] diamond bird failed: " .. tostring(problem)) end
		end
	end)

	return {
		multiplier = function(): number
			return BirdBonus.multiplier(workspace:GetServerTimeNow(), boostUntil, Config.BirdMultiplier)
		end,
		spawn = spawn,
		catch = catch,
	}
end

return DiamondBird
