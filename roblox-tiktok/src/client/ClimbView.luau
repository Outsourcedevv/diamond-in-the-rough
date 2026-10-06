--!strict
-- Diamond Climb on this computer: the climb's display (platform, best and
-- climbs), the speed and jump sliders, the landing animation each time the
-- climber lands on a platform (a bigger one every hundred), sending each new
-- platform to the server as the checkpoint, putting the climber back on
-- their checkpoint when they fall, the gift rides (one after another, see
-- ClimbEffects) and the win at the top. Also turns the climb's diamond.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local ClimbPath = require(Shared:WaitForChild("ClimbPath"))
local Format = require(Shared:WaitForChild("Format"))
local ClimbEffects = require(script.Parent:WaitForChild("ClimbEffects"))

local ClimbView = {}

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(246, 200, 92)
local MUTED = Color3.fromRGB(168, 174, 190)
local PANEL = Color3.fromRGB(16, 18, 26)
local SELECTED = Color3.fromRGB(64, 128, 236)
local BUTTON = Color3.fromRGB(46, 50, 68)
local FONT = Enum.Font.GothamBold
local FONT_MEDIUM = Enum.Font.GothamMedium
local FONT_HEAVY = Enum.Font.GothamBlack
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
-- A short chime that ships with Roblox; it rises in pitch through each ten platforms.
ClimbView.LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"
-- Falling this far below the checkpoint puts the climber back on it.
ClimbView.FALL_DISTANCE = 24
-- Landing this many platforms below the checkpoint does too (falling a turn down).
ClimbView.FALL_PLATFORMS = 3

-- The pitch of the landing chime on platform `index`: up a step each
-- platform, starting again every ten.
function ClimbView.pitch(index: number): number
	return 0.8 + (index % 10) * 0.07
end

-- What the climb's display says.
function ClimbView.platformText(index: number): string
	return string.format("PLATFORM %s / %s", Format.commas(math.floor(index + 0.5)), Format.commas(ClimbPath.TOP))
end

-- The gift rides play faster while more are waiting.
function ClimbView.pace(waiting: number): number
	return math.min(3, 1 + math.max(0, waiting) * 0.5)
end

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent ~= nil then instance.Parent = parent end
	return instance
end

local function rounded(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function glass(instance: GuiObject, radius: number)
	instance.BackgroundColor3 = PANEL
	instance.BackgroundTransparency = 0.28
	rounded(instance, radius)
	make("UIStroke", { Thickness = 1, Color = WHITE, Transparency = 0.88, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, instance)
end

-- `request` sends climbLand and setClimbMove; `state` carries the climb's
-- progress (ClimbCheckpoint, ClimbBest, ClimbWins, ClimbSpeed, ClimbJump).
-- Returns setActive(climbing) and the gift and win handlers.
function ClimbView.start(request: RemoteEvent, state: Instance)
	local player = Players.LocalPlayer
	local active = false
	local function attr(name: string, fallback: number): number
		local value = state:GetAttribute(name)
		return if type(value) == "number" then value else fallback
	end

	local gui = make("ScreenGui", {
		Name = "DiamondClimbHud",
		ResetOnSpawn = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	ClimbEffects.start(player:WaitForChild("PlayerGui"))

	-- The display, top centre: the platform, a progress bar, best and climbs.
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(330, 92),
	}, gui)
	glass(card, 14)
	local cardScale = make("UIScale", { Scale = 1 }, card)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		TextColor3 = MUTED,
		Text = "DIAMOND CLIMB",
	}, card)
	local platformLabel = make("TextLabel", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = FONT_HEAVY,
		TextSize = 26,
		TextColor3 = WHITE,
		Text = ClimbView.platformText(0),
	}, card)
	local bar = make("Frame", {
		Position = UDim2.new(0, 16, 0, 58),
		Size = UDim2.new(1, -32, 0, 6),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, card)
	rounded(bar, 3)
	local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, bar)
	rounded(barFill, 3)
	local barGradient = make("UIGradient", { Color = ColorSequence.new(ClimbPath.GEMS[1], ClimbPath.GEMS[1]) }, barFill)
	local statsLabel = make("TextLabel", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT_MEDIUM,
		TextSize = 13,
		TextColor3 = MUTED,
		RichText = true,
		Text = "",
	}, card)
	-- A big line under the display for milestones and the win.
	local shout = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(600, 46),
		BackgroundTransparency = 1,
		Font = FONT_HEAVY,
		TextSize = 38,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		Text = "",
	}, gui)
	local shoutScale = make("UIScale", { Scale = 1 }, shout)
	local shoutSerial = 0
	local function showShout(text: string, colour: Color3, seconds: number)
		shoutSerial += 1
		local serial = shoutSerial
		shout.Text = text
		shout.TextColor3 = colour
		shout.TextTransparency = 0
		shoutScale.Scale = 1.8
		TweenService:Create(shoutScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(seconds, function()
			if serial == shoutSerial then
				TweenService:Create(shout, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			end
		end)
	end

	-- The speed and jump sliders, bottom right.
	local moveCard = make("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -36),
		Size = UDim2.fromOffset(280, 136),
	}, gui)
	glass(moveCard, 14)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10) }, moveCard)
	make("TextLabel", {
		Size = UDim2.new(1, -70, 0, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MUTED,
		Text = "MOVEMENT",
	}, moveCard)
	local resetButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(60, 20),
		BackgroundColor3 = BUTTON,
		Font = FONT,
		TextSize = 11,
		TextColor3 = WHITE,
		Text = "Reset",
	}, moveCard)
	rounded(resetButton, 6)

	type Slider = { set: (number) -> (), value: () -> number }
	local dragging: { [any]: boolean } = {}
	local function slider(y: number, name: string, range: { min: number, max: number, default: number }, step: number, onChange: (number, boolean) -> ()): Slider
		local current = range.default
		make("TextLabel", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, -60, 0, 18),
			BackgroundTransparency = 1,
			Font = FONT_MEDIUM,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = WHITE,
			Text = name,
		}, moveCard)
		local valueLabel = make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, y),
			Size = UDim2.fromOffset(60, 18),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = WHITE,
			Text = "",
		}, moveCard)
		local hit = make("TextButton", {
			Position = UDim2.fromOffset(0, y + 20),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
		}, moveCard)
		local track = make("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
		}, hit)
		rounded(track, 3)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = SELECTED, BorderSizePixel = 0 }, track)
		rounded(fill, 3)
		local knob = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, track)
		rounded(knob, 9)
		local function show()
			local fraction = (current - range.min) / (range.max - range.min)
			fill.Size = UDim2.fromScale(fraction, 1)
			knob.Position = UDim2.fromScale(fraction, 0.5)
			valueLabel.Text = if step < 1 then string.format("%.1f", current) else tostring(math.floor(current + 0.5))
		end
		local function set(value: number)
			current = math.clamp(math.floor(value / step + 0.5) * step, range.min, range.max)
			show()
		end
		local function fromScreen(x: number, done: boolean)
			local left, width = track.AbsolutePosition.X, math.max(1, track.AbsoluteSize.X)
			set(range.min + math.clamp((x - left) / width, 0, 1) * (range.max - range.min))
			onChange(current, done)
		end
		local key = {}
		hit.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging[key] = true
				fromScreen(input.Position.X, false)
			end
		end)
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging[key] and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				fromScreen(input.Position.X, false)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragging[key] and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				dragging[key] = nil
				fromScreen(input.Position.X, true)
			end
		end)
		show()
		return { set = set, value = function() return current end }
	end

	local function humanoid(): Humanoid?
		local character = player.Character
		return if character then character:FindFirstChildOfClass("Humanoid") else nil
	end
	-- The sliders change the character straight away; the server keeps them.
	local lastSent = 0
	local speedSlider: Slider, jumpSlider: Slider
	local function moved(_value: number, done: boolean)
		local walker = humanoid()
		if walker and active then
			walker.UseJumpPower = false
			walker.WalkSpeed = speedSlider.value()
			walker.JumpHeight = jumpSlider.value()
		end
		local now = os.clock()
		if done or now - lastSent > 0.25 then
			lastSent = now
			request:FireServer("setClimbMove", { speed = speedSlider.value(), jump = jumpSlider.value() })
		end
	end
	speedSlider = slider(22, "Speed", ClimbPath.SPEED, 0.5, moved)
	jumpSlider = slider(72, "Jump height", ClimbPath.JUMP, 0.1, moved)
	resetButton.Activated:Connect(function()
		speedSlider.set(ClimbPath.SPEED.default)
		jumpSlider.set(ClimbPath.JUMP.default)
		moved(0, true)
	end)
	local function refreshMove()
		if next(dragging) ~= nil then return end
		speedSlider.set(attr("ClimbSpeed", ClimbPath.SPEED.default))
		jumpSlider.set(attr("ClimbJump", ClimbPath.JUMP.default))
	end
	state:GetAttributeChangedSignal("ClimbSpeed"):Connect(refreshMove)
	state:GetAttributeChangedSignal("ClimbJump"):Connect(refreshMove)
	refreshMove()

	-- The display follows the checkpoint, or the ride while a gift carries the climber.
	local shownPlatform = attr("ClimbCheckpoint", 0)
	local function refreshStats()
		statsLabel.Text = string.format('BEST <font color="#FFFFFF">%s</font>    CLIMBS <font color="#F6C85C">%s</font>',
			Format.commas(attr("ClimbBest", 0)), Format.commas(attr("ClimbWins", 0)))
	end
	state:GetAttributeChangedSignal("ClimbBest"):Connect(refreshStats)
	state:GetAttributeChangedSignal("ClimbWins"):Connect(refreshStats)
	refreshStats()
	local lastWhole = -1
	RunService.RenderStepped:Connect(function(dt: number)
		if not active then return end
		local target = ClimbEffects.shownIndex() or attr("ClimbCheckpoint", 0)
		shownPlatform += (target - shownPlatform) * math.min(1, dt * 12)
		if math.abs(target - shownPlatform) < 0.5 then shownPlatform = target end
		local whole = math.floor(shownPlatform + 0.5)
		if whole ~= lastWhole then
			lastWhole = whole
			platformLabel.Text = ClimbView.platformText(whole)
			barFill.Size = UDim2.fromScale(whole / ClimbPath.TOP, 1)
			local gem = ClimbPath.colour(math.max(1, whole))
			barGradient.Color = ColorSequence.new(gem:Lerp(WHITE, 0.4), gem)
			platformLabel.TextColor3 = WHITE:Lerp(gem, 0.35)
		end
	end)
	local function pop(scale: number)
		cardScale.Scale = scale
		TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- The tower's platforms by number, for the landing animation.
	local platforms: { [number]: BasePart } = {}
	local tower: Instance? = nil
	task.spawn(function()
		local model = workspace:WaitForChild("DiamondClimb", math.huge)
		tower = model
		local function add(item: Instance)
			local index = item:GetAttribute("ClimbIndex")
			if type(index) == "number" and item:IsA("BasePart") then platforms[index] = item end
		end
		for _, item in model:GetDescendants() do add(item) end
		model.DescendantAdded:Connect(add)
	end)

	-- The landing animation: the platform bounces and flashes, a ring of light
	-- races out, sparkles fly up and a chime rings, rising through each ten.
	-- Every hundredth platform gets fireworks and a gold shout.
	local effects = make("Folder", { Name = "ClimbLandings" }, workspace)
	local function landed(index: number, fresh: boolean)
		local platform = platforms[index]
		local top = ClimbPath.top(index)
		local colour = if index == 0 then WHITE else ClimbPath.colour(index)
		local size = ClimbPath.size(index)
		-- The rim swells and flashes white, then settles.
		local rim = if platform then platform:FindFirstChild("Rim") else nil
		if rim and rim:IsA("BasePart") then
			local base = ClimbPath.size(index) + (if index % ClimbPath.MILESTONE == 0 then 1.4 else 0.7)
			local thick = rim.Size.X
			-- Its own colour, remembered the first time (a flash may still be fading).
			local tint = rim:GetAttribute("Tint")
			if typeof(tint) ~= "Color3" then
				tint = rim.Color
				rim:SetAttribute("Tint", tint)
			end
			rim.Size = Vector3.new(thick, base * 1.25, base * 1.25)
			rim.Color = WHITE
			TweenService:Create(rim, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Size = Vector3.new(thick, base, base) }):Play()
			TweenService:Create(rim, TweenInfo.new(0.5), { Color = tint }):Play()
		end
		-- A ring of light.
		local ring = make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, size, size),
			CFrame = CFrame.new(top + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = colour,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, effects)
		local reach = if fresh then size * 2.6 else size * 1.7
		TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, reach, reach), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.6)
		-- Sparkles and a flat shockwave.
		-- Terrain sits at the world's origin, so these positions are world positions.
		local spot = make("Attachment", { Position = top + Vector3.new(0, 0.6, 0) }, workspace.Terrain)
		Debris:AddItem(spot, 1.6)
		local sparkles = make("ParticleEmitter", {
			Texture = SPARK,
			Color = ColorSequence.new(WHITE, colour),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new(0),
			Lifetime = NumberRange.new(0.4, 0.9),
			Speed = NumberRange.new(6, 14),
			SpreadAngle = Vector2.new(70, 70),
			Drag = 3,
			LightEmission = 1,
			Enabled = false,
		}, spot)
		sparkles:Emit(if fresh then 22 else 10)
		if fresh then
			local wave = make("ParticleEmitter", {
				Texture = RING,
				Color = ColorSequence.new(colour),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, size * 1.6) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.5, 0.5),
				Speed = NumberRange.new(0.01, 0.01),
				Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
				LightEmission = 1,
				Enabled = false,
			}, spot)
			wave:Emit(1)
			local chime = make("Sound", {
				SoundId = ClimbView.LAND_SOUND,
				Volume = 0.45,
				PlaybackSpeed = ClimbView.pitch(index),
			}, spot)
			chime:Play()
			pop(1.08)
		end
		if fresh and index > 0 and index % ClimbPath.MILESTONE == 0 and index < ClimbPath.TOP then
			-- A hundred more: fireworks round the platform and a gold shout.
			local fireworks = make("ParticleEmitter", {
				Texture = SPARK,
				Color = ColorSequence.new(GOLD, colour),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(0.8, 1.5),
				Speed = NumberRange.new(16, 30),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 2,
				Acceleration = Vector3.new(0, -12, 0),
				LightEmission = 1,
				Enabled = false,
			}, spot)
			fireworks:Emit(90)
			showShout(string.format("PLATFORM %d!", index), GOLD, 2.2)
			pop(1.3)
		end
	end

	-- Landing, checkpoints and falls.
	local riding = false
	local rides: { any } = {} -- gift rides waiting their turn
	local lastLanded = attr("ClimbCheckpoint", 0)
	-- A new platform the server has not taken as the checkpoint yet (it sees
	-- players a moment late), sent again while the climber stands on it.
	local pending: number? = nil
	local pendingSent = 0
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local function backToCheckpoint()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then return end
		local checkpoint = attr("ClimbCheckpoint", 0)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = ClimbPath.standFrame(checkpoint)
		lastLanded = checkpoint
		pending = nil
		landed(checkpoint, false)
	end
	RunService.Heartbeat:Connect(function()
		if not active or riding or #rides > 0 or ClimbEffects.playing() then return end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local walker = humanoid()
		if root == nil or not root:IsA("BasePart") or walker == nil or walker.Health <= 0 then return end
		local checkpoint = attr("ClimbCheckpoint", 0)
		-- Fell off: measured from the platform they were last on (a gift may
		-- have moved the checkpoint a long way up already, ahead of its ride).
		if root.Position.Y < ClimbPath.top(math.min(lastLanded, checkpoint)).Y - ClimbView.FALL_DISTANCE then
			backToCheckpoint()
			return
		end
		if walker.FloorMaterial == Enum.Material.Air or tower == nil then return end
		rayParams.FilterDescendantsInstances = { tower :: Instance }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(walker.HipHeight + root.Size.Y / 2 + 1.5), 0), rayParams)
		local index = if hit then hit.Instance:GetAttribute("ClimbIndex") else nil
		if type(index) ~= "number" then return end
		if index ~= lastLanded then
			lastLanded = index
			pending = nil
			if index < checkpoint - ClimbView.FALL_PLATFORMS then
				backToCheckpoint()
				return
			end
			local fresh = index > checkpoint
			landed(index, fresh)
			if fresh then
				pending = index
				pendingSent = 0
			end
		end
		if pending ~= nil and pending == index and pending > checkpoint and os.clock() - pendingSent > 0.4 then
			pendingSent = os.clock()
			request:FireServer("climbLand", pending)
		elseif pending ~= nil and pending <= checkpoint then
			pending = nil
		end
	end)

	-- Gift rides, one after another.
	local winWaiting: any = nil
	local function celebrate()
		showShout("YOU REACHED THE DIAMOND!", GOLD, 6)
		pop(1.4)
		local finish = ClimbPath.top(ClimbPath.TOP)
		for k = 1, 6 do
			task.delay(k * 0.45, function()
				local angle = k * math.pi / 3
				local spot = make("Attachment", { Position = finish + Vector3.new(math.cos(angle) * 14, 10 + (k % 3) * 4, math.sin(angle) * 14) }, workspace.Terrain)
				Debris:AddItem(spot, 2)
				local burst = make("ParticleEmitter", {
					Texture = SPARK,
					Color = ColorSequence.new(WHITE, ClimbPath.GEMS[(k * 3) % #ClimbPath.GEMS + 1]),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0) }),
					Lifetime = NumberRange.new(0.9, 1.6),
					Speed = NumberRange.new(18, 34),
					SpreadAngle = Vector2.new(180, 180),
					Drag = 2,
					Acceleration = Vector3.new(0, -10, 0),
					LightEmission = 1,
					Enabled = false,
				}, spot)
				burst:Emit(80)
			end)
		end
	end
	RunService.Heartbeat:Connect(function()
		if riding then return end
		if not active then
			table.clear(rides)
			winWaiting = nil
			return
		end
		local data = table.remove(rides, 1)
		if data == nil then
			if winWaiting then
				winWaiting = nil
				celebrate()
			end
			return
		end
		riding = true
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		ClimbEffects.play(data, if root and root:IsA("BasePart") then root else nil, ClimbView.pace(#rides), function()
			riding = false
			lastLanded = data.to
			landed(data.to, false)
		end)
	end)

	local function onGift(data: any)
		if active and type(data) == "table" then
			-- The gift decides the checkpoint now, not a landing still on its way.
			pending = nil
			table.insert(rides, data)
		end
	end
	local function onWin(data: any)
		if active then winWaiting = data end
	end
	local function onRestart()
		if not active then return end
		table.clear(rides)
		ClimbEffects.stop()
		task.delay(0.2, backToCheckpoint)
	end

	local function setActive(on: boolean)
		if on == active then return end
		active = on
		gui.Enabled = on
		if not on then
			ClimbEffects.stop()
			riding = false
		else
			lastLanded = attr("ClimbCheckpoint", 0)
			shownPlatform = lastLanded
			lastWhole = -1
			-- A wider view for platforming.
			player.CameraMaxZoomDistance = 40
		end
	end

	-- The diamond at the top turns slowly and bobs (only when near).
	task.spawn(function()
		local model = workspace:WaitForChild("DiamondClimb", math.huge)
		local gem = model:WaitForChild("ClimbDiamond", math.huge)
		local centre = gem:GetAttribute("Centre")
		if typeof(centre) ~= "Vector3" then return end
		local origin = CFrame.new(centre)
		local parts: { BasePart } = {}
		local offsets: { CFrame } = {}
		for _, item in gem:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(parts, item)
				table.insert(offsets, origin:ToObjectSpace(item.CFrame))
			end
		end
		local frames: { CFrame } = table.create(#parts, CFrame.identity)
		RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera == nil or (camera.CFrame.Position - centre).Magnitude > 300 then return end
			local t = os.clock()
			local turn = CFrame.new(centre + Vector3.new(0, math.sin(t * 1.3) * 0.6, 0)) * CFrame.Angles(0, t * 0.8, 0)
			for i, offset in offsets do frames[i] = turn * offset end
			workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end)

	return {
		setActive = setActive,
		onGift = onGift,
		onWin = onWin,
		onRestart = onRestart,
	}
end

return ClimbView
