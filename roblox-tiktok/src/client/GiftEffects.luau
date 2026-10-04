--!strict
-- Local, non-physical spectacle. At most three sequences / 180 parts at once.
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
	if #active >= 3 then
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
	Debris:AddItem(folder, 6)
	local colour = colours[tier]
	local centre: Vector3 = data.position
	local allocated = 0
	local function piece(shape: Enum.PartType, size: Vector3, frame: CFrame): Part?
		if folder.Parent == nil or allocated >= 60 then return nil end
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
		return p
	end
	local function animate(p: Part, seconds: number, goal: any)
		TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		Debris:AddItem(p, seconds + 0.05)
	end
	local function pulse(at: Vector3, radius: number)
		local orb = piece(Enum.PartType.Ball, Vector3.one, CFrame.new(at))
		if orb then
			orb.Transparency = 0.65
			animate(orb, 0.75, { Size = Vector3.one * radius * 2, Transparency = 1 })
		end
		-- Radial light streaks form an expanding crown around the crater.
		for i = 1, 8 do
			local angle = i * math.pi / 4
			local direction = Vector3.new(math.cos(angle), 0.15, math.sin(angle))
			local shard = piece(Enum.PartType.Block, Vector3.new(0.15, 0.15, 1.5), CFrame.lookAt(at + direction, at + direction * 2))
			if shard then animate(shard, 0.65, { CFrame = CFrame.lookAt(at + direction * radius, at + direction * (radius + 1)), Size = Vector3.new(0.05, 0.05, 4), Transparency = 1 }) end
		end
	end
	local function meteor(at: Vector3, delay: number)
		task.delay(delay, function()
			if folder.Parent == nil then return end
			local start = at + Vector3.new(18, 40 + tier * 5, -12)
			local rock = piece(Enum.PartType.Ball, Vector3.one * (1 + tier * 0.4), CFrame.new(start))
			if rock == nil then return end
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(-0.7, 0, 0)
			a.Parent = rock
			local b = Instance.new("Attachment")
			b.Position = Vector3.new(0.7, 0, 0)
			b.Parent = rock
			local trail = Instance.new("Trail")
			trail.Attachment0 = a
			trail.Attachment1 = b
			trail.Color = ColorSequence.new(colour, Color3.new(1, 1, 1))
			trail.Lifetime = 0.35
			trail.Transparency = NumberSequence.new(0.15, 1)
			trail.Parent = rock
			TweenService:Create(rock, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = at }):Play()
			task.delay(0.65, function()
				if folder.Parent == nil then return end
				rock:Destroy()
				pulse(at, 5 + tier * 2)
			end)
		end)
	end
	if tier <= 2 then
		pulse(centre, 3 + tier * 3)
		for _ = 1, tier * 7 do
			local spark = piece(Enum.PartType.Ball, Vector3.one * 0.22, CFrame.new(centre))
			if spark then animate(spark, random:NextNumber(0.5, 1.2), { Position = centre + Vector3.new(random:NextNumber(-7, 7), random:NextNumber(3, 12), random:NextNumber(-7, 7)), Transparency = 1 }) end
		end
	else
		local count = if tier == 3 then 1 elseif tier == 4 then 3 else 4
		for i = 1, count do
			local offset = if i == 1 then Vector3.zero else Vector3.new(random:NextNumber(-10, 10), 0, random:NextNumber(-10, 10))
			meteor(centre + offset, (i - 1) * 0.3)
		end
		if tier == 5 then
			task.delay(2.1, function()
				if folder.Parent == nil then return end
				pulse(centre, 32)
				local pillar = piece(Enum.PartType.Cylinder, Vector3.new(65, 2, 2), CFrame.new(centre + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.pi / 2))
				if pillar then animate(pillar, 1.2, { Size = Vector3.new(80, 12, 12), Transparency = 1 }) end
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
		text.TextTransparency = 0
		text.Position = UDim2.fromScale(0.5, 0.32)
		TweenService:Create(text, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.30) }):Play()
		task.delay(1.5 + tier * 0.35, function()
			if serial ~= bannerSerial then return end
			text.TextTransparency = 1
			bannerTier = 0
		end)
	end
end
return GiftEffects
