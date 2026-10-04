--!strict
-- Local, non-physical spectacle. At most two sequences / 80 parts at once.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("DiamondRush")
local GiftTier = require(Shared:WaitForChild("GiftTier"))
local Format = require(Shared:WaitForChild("Format"))
local GiftEffects = {}
local colours = { Color3.fromRGB(255, 208, 112), Color3.fromRGB(255, 137, 55), Color3.fromRGB(255, 80, 66), Color3.fromRGB(126, 116, 255), Color3.fromRGB(91, 240, 255) }
local titles = { "SPARK BURST", "SHOCKWAVE", "METEOR STRIKE", "METEOR SHOWER", "COSMIC BURST" }
local active: { { folder: Folder, tier: number } } = {}
local label: TextLabel? = nil
local bannerSerial = 0
local bannerTier = 0
local bannerTween: Tween? = nil
local random = Random.new()

function GiftEffects.start(parent: Instance)
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
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextStrokeTransparency = 0.35
	text.TextTransparency = 1
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = 23
	limit.Parent = text
	text.Parent = gui
	label = text
end

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
	Debris:AddItem(folder, 8)
	local colour = colours[tier]
	local centre: Vector3 = data.position
	local allocated = 0
	local function piece(shape: Enum.PartType, size: Vector3, frame: CFrame): Part?
		if folder.Parent == nil or allocated >= 40 then return nil end
		allocated += 1
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.CFrame = frame
		p.Color = colour
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = folder
		p.Destroying:Connect(function() allocated -= 1 end)
		return p
	end
	local function animate(p: Part, seconds: number, goal: any)
		TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		Debris:AddItem(p, seconds + 0.05)
	end
	-- Each moving element owns one connection, released immediately on cleanup.
	local function motion(p: Part, duration: number, update: (number) -> ())
		local elapsed = 0
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)
			update(t)
			if t >= 1 then p:Destroy() end
		end)
		p.Destroying:Connect(function()
			if connection then connection:Disconnect(); connection = nil end
		end)
	end
	local function ring(at: Vector3, radius: number, delay: number)
		task.delay(delay, function()
			local root = piece(Enum.PartType.Block, Vector3.one * 0.1, CFrame.new(at + Vector3.new(0, 0.15, 0)))
			if root == nil then return end
			root.Transparency = 1
			local points = {}
			local beams = {}
			for i = 1, 16 do
				local point = Instance.new("Attachment")
				point.Parent = root
				table.insert(points, point)
			end
			for i, point in points do
				local beam = Instance.new("Beam")
				beam.Attachment0 = point
				beam.Attachment1 = points[i % #points + 1]
				beam.FaceCamera = true
				beam.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.4))
				beam.LightEmission = 1
				beam.Parent = root
				table.insert(beams, beam)
			end
			for i, point in points do
				local angle = i * math.pi * 2 / #points
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				point.Position = direction * 0.5
				TweenService:Create(point, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = direction * radius }):Play()
			end
			for _, beam in beams do
				beam.Width0 = 0.3 + tier * 0.08
				beam.Width1 = beam.Width0
				TweenService:Create(beam, TweenInfo.new(0.8), { Width0 = 0, Width1 = 0 }):Play()
			end
			Debris:AddItem(root, 0.85)
		end)
	end
	local function pulse(at: Vector3, radius: number)
		ring(at, radius, 0)
		if tier >= 2 then ring(at, radius * 0.8, 0.13) end
		local orb = piece(Enum.PartType.Ball, Vector3.one, CFrame.new(at))
		if orb then
			orb.Color = Color3.new(1, 0.94, 0.8)
			orb.Transparency = 0.35
			animate(orb, 0.3, { Size = Vector3.one * math.min(radius, 10), Transparency = 1 })
		end
		for i = 1, 4 + tier do
			local angle = i * math.pi * 2 / (4 + tier)
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local shard = piece(Enum.PartType.Block, Vector3.new(0.16, 0.16, 0.55), CFrame.new(at))
			if shard then
				local height = random:NextNumber(2, 6 + tier)
				local spin = random:NextNumber(-8, 8)
				motion(shard, random:NextNumber(0.6, 1.1), function(t)
					local position = at + direction * radius * t + Vector3.new(0, height * 4 * t * (1 - t), 0)
					shard.CFrame = CFrame.new(position) * CFrame.Angles(t * spin, angle, t * spin * 0.7)
					shard.Transparency = t * t
				end)
			end
		end
	end
	local function meteor(at: Vector3, delay: number)
		task.delay(delay, function()
			if folder.Parent == nil then return end
			local approach = random:NextNumber(0, math.pi * 2)
			local start = at + Vector3.new(math.cos(approach) * 28, 40 + tier * 5, math.sin(approach) * 28)
			local control = start:Lerp(at, 0.45) + Vector3.new(0, 14, 0)
			local rock = piece(Enum.PartType.Ball, Vector3.one * (1 + tier * 0.35), CFrame.new(start))
			if rock == nil then return end
			rock.Color = colour:Lerp(Color3.new(1, 1, 1), 0.6)
			local light = Instance.new("PointLight")
			light.Color = colour
			light.Range = 16
			light.Brightness = 2
			light.Parent = rock
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(-0.6, 0, 0)
			a.Parent = rock
			local b = Instance.new("Attachment")
			b.Position = Vector3.new(0.6, 0, 0)
			b.Parent = rock
			local trail = Instance.new("Trail")
			trail.Attachment0 = a
			trail.Attachment1 = b
			trail.Color = ColorSequence.new(Color3.new(1, 0.97, 0.8), colour)
			trail.Lifetime = 0.45
			trail.LightEmission = 1
			trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
			trail.Transparency = NumberSequence.new(0.05, 1)
			trail.Parent = rock
			ring(at, 2.5, 0) -- Brief impact warning, followed by the main shockwave.
			motion(rock, 0.9, function(t)
				local u = t * t
				local position = start * (1 - u) ^ 2 + control * (2 * (1 - u) * u) + at * u ^ 2
				rock.CFrame = CFrame.lookAt(position, at + Vector3.new(0, -0.01, 0))
				if t >= 1 then pulse(at, 5 + tier * 2) end
			end)
		end)
	end
	if tier <= 2 then
		pulse(centre, 3 + tier * 3)
		for _ = 1, tier * 3 do
			local spark = piece(Enum.PartType.Ball, Vector3.one * 0.22, CFrame.new(centre))
			if spark then animate(spark, random:NextNumber(0.5, 1.2), { Position = centre + Vector3.new(random:NextNumber(-7, 7), random:NextNumber(3, 12), random:NextNumber(-7, 7)), Transparency = 1 }) end
		end
	else
		local count = if tier == 3 then 1 elseif tier == 4 then 2 else 3
		for i = 1, count do
			local offset = if i == 1 then Vector3.zero else Vector3.new(random:NextNumber(-10, 10), 0, random:NextNumber(-10, 10))
			meteor(centre + offset, (i - 1) * 0.3)
		end
		if tier == 5 then
			task.delay(2.3, function()
				if folder.Parent == nil then return end
				pulse(centre, 32)
				local pillar = piece(Enum.PartType.Cylinder, Vector3.new(65, 0.5, 0.5), CFrame.new(centre + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2))
				if pillar then
					pillar.Transparency = 0.35
					animate(pillar, 1.5, { Size = Vector3.new(80, 5, 5), Transparency = 1 })
				end
				ring(centre + Vector3.new(0, 3, 0), 24, 0.18)
				ring(centre + Vector3.new(0, 6, 0), 18, 0.32)
			end)
		end
	end
	local text = label
	if text and tier >= bannerTier then
		bannerTier = tier
		bannerSerial += 1
		local serial = bannerSerial
		text.Text = titles[tier] .. "  •  " .. Format.commas(data.coins) .. " COINS\n" .. tostring(data.name or "Someone") .. " sent " .. tostring(data.gift or "a gift")
		text.TextColor3 = colour
		if bannerTween then bannerTween:Cancel() end
		text.TextTransparency = 0
		text.TextStrokeTransparency = 0.35
		text.Position = UDim2.fromScale(0.5, 0.32)
		TweenService:Create(text, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.30) }):Play()
		task.delay(1.5 + tier * 0.35, function()
			if serial ~= bannerSerial then return end
			bannerTween = TweenService:Create(text, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 })
			bannerTween:Play()
			bannerTier = 0
		end)
	end
end
return GiftEffects
