--!strict
-- The loading screen: runs first (ReplicatedFirst), in place of Roblox's own,
-- and covers the screen until the game is ready to play: the place has
-- loaded, the palace stands, the player's character is in it and the game's
-- display has started (it says so with the player's DiamondRushHudReady
-- attribute). A royal blue card with the title, a turning diamond, a gold
-- progress bar that fills as each of those is done, and tips. It shows for
-- at least MIN_SECONDS so it never flashes, never stays past MAX_SECONDS, and
-- fades away at the end.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MIN_SECONDS = 2.5
local MAX_SECONDS = 45

local ROYAL = Color3.fromRGB(34, 52, 140)
local ROYAL_DEEP = Color3.fromRGB(12, 18, 64)
local GOLD = Color3.fromRGB(246, 200, 92)
local ICE = Color3.fromRGB(176, 230, 255)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(190, 200, 236)

local TIPS = {
	"Hold Shift to sprint.",
	"Walk into a room's glowing portal to join its game.",
	"Press G for the games menu, P for settings and H for how to play.",
	"Dig into the mountain, find the diamond, and hold it for 15 seconds to win.",
	"Catch the diamond bird: every gift counts double for 30 seconds.",
	"Streamers: set up your gifts in Gifts, on the sidebar.",
	"Pick the map's look in Themes, on the sidebar.",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function make(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	if parent then instance.Parent = parent end
	return instance
end
local function corner(parent: Instance, radius: UDim)
	make("UICorner", { CornerRadius = radius }, parent)
end

local gui = make("ScreenGui", {
	Name = "DiamondRushLoading",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)

-- One group, so the whole screen fades as one.
local screen = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, gui)
make("UIGradient", { Color = ColorSequence.new(ROYAL, ROYAL_DEEP), Rotation = 90 }, screen)

-- Sparkles drifting up the screen.
local sparkles = {}
local random = Random.new()
for k = 1, 24 do
	local size = random:NextInteger(3, 7)
	local dot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(random:NextNumber(), random:NextNumber()),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = if k % 3 == 0 then GOLD else ICE,
		BackgroundTransparency = random:NextNumber(0.3, 0.7),
		BorderSizePixel = 0,
	}, screen)
	table.insert(sparkles, { frame = dot, speed = random:NextNumber(0.015, 0.05), x = dot.Position.X.Scale, y = dot.Position.Y.Scale })
end

local middle = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 380),
	BackgroundTransparency = 1,
}, screen)
-- Shrinks to fit small screens (phones).
local fit = make("UIScale", { Scale = 1 }, middle)
local function refit()
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	fit.Scale = math.clamp(math.min(size.X / 560, size.Y / 420), 0.5, 1.2)
end
refit()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end

-- The diamond: a gem on its corner with a gold edge and a lighter heart,
-- turning gently and pulsing, with a glint sweeping across it.
local gemHolder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(260, 80), Size = UDim2.fromOffset(110, 110), BackgroundTransparency = 1 }, middle)
local glow = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.45, 1.45), BackgroundColor3 = ICE, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, gemHolder)
corner(glow, UDim.new(1, 0))
local gem = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.72), Rotation = 45, BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true }, gemHolder)
corner(gem, UDim.new(0.12, 0))
make("UIGradient", { Color = ColorSequence.new(WHITE, ICE), Rotation = -45 }, gem)
make("UIStroke", { Color = GOLD, Thickness = 4 }, gem)
local heart = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.46, 0.46), BackgroundColor3 = Color3.fromRGB(120, 200, 255), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, gem)
corner(heart, UDim.new(0.15, 0))
local glint = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.5, 0.5), Size = UDim2.new(0.18, 0, 2, 0), Rotation = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, gem)
local pulse = make("UIScale", { Scale = 1 }, gemHolder)

local title = make("TextLabel", {
	Position = UDim2.fromOffset(0, 176),
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 40,
	TextColor3 = WHITE,
	Text = "DIAMOND IN THE ROUGH",
}, middle)
make("UIStroke", { Color = ROYAL_DEEP, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
local status = make("TextLabel", {
	Position = UDim2.fromOffset(0, 226),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = GOLD,
	Text = "Loading…",
}, middle)

-- The progress bar.
local track = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 258), Size = UDim2.fromOffset(380, 14), BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, middle)
corner(track, UDim.new(1, 0))
local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
corner(fill, UDim.new(1, 0))
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), GOLD) }, fill)
local percent = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 278), Size = UDim2.fromOffset(120, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = MUTED, Text = "0%" }, middle)

local tip = make("TextLabel", {
	Position = UDim2.fromOffset(0, 326),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 15,
	TextWrapped = true,
	TextColor3 = MUTED,
	Text = TIPS[random:NextInteger(1, #TIPS)],
}, middle)

-- What's left to wait for, in order, with how full the bar is once each is done.
local target = 0.05
local stage = "Loading…"
local done = false
local started = os.clock()
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	target, stage = 0.35, "Building the palace…"
	workspace:WaitForChild("Lobby", MAX_SECONDS)
	target, stage = 0.6, "Getting your character ready…"
	local character = player.Character or player.CharacterAdded:Wait()
	character:WaitForChild("HumanoidRootPart", MAX_SECONDS)
	target, stage = 0.85, "Almost there…"
	while player:GetAttribute("DiamondRushHudReady") ~= true do
		player:GetAttributeChangedSignal("DiamondRushHudReady"):Wait()
	end
	target, stage = 1, "Ready!"
	done = true
end)

local shown = 0
local tipAt = os.clock()
local tipIndex = 1
local beat: RBXScriptConnection
beat = RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock() - started
	-- The bar eases towards where loading is up to.
	shown += (target - shown) * math.min(1, dt * 6)
	if target >= 1 and shown > 0.995 then shown = 1 end
	fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	percent.Text = tostring(math.floor(shown * 100 + 0.5)) .. "%"
	status.Text = stage
	-- The diamond turns a little either way, pulses, and a glint sweeps across.
	gem.Rotation = 45 + math.sin(t * 1.6) * 10
	pulse.Scale = 1 + math.sin(t * 3) * 0.04
	glow.BackgroundTransparency = 0.82 + math.sin(t * 3) * 0.05
	glint.Position = UDim2.fromScale(-0.5 + ((t * 0.6) % 1.6), 0.5)
	for _, sparkle in sparkles do
		sparkle.y -= sparkle.speed * dt
		if sparkle.y < -0.05 then sparkle.y = 1.05 end
		sparkle.frame.Position = UDim2.fromScale(sparkle.x, sparkle.y)
	end
	-- A new tip every few seconds.
	if os.clock() - tipAt > 3.5 then
		tipAt = os.clock()
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = TIPS[tipIndex]
	end
end)

-- Wait until it's all done (and the screen has shown a moment), or give up
-- waiting, then fade away.
while not (done and os.clock() - started >= MIN_SECONDS and shown >= 1) and os.clock() - started < MAX_SECONDS do
	task.wait(0.1)
end
target = 1
task.wait(0.3)
local fade = TweenService:Create(screen, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
fade:Play()
fade.Completed:Wait()
beat:Disconnect()
gui:Destroy()
