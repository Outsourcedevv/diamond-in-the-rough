--!strict
-- The hold countdown for Diamond Climb (standing at the top) and Chalkboard
-- Count (the count at the goal): like the diamond's, the hold lasts
-- Config.HoldSeconds of real time (15) but the screen counts down from
-- Config.HoldCountFrom (10), quickly at first and slower near the end. Each
-- new number pops in with a tick. A gift that sends the player down ends it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))
local HoldTimer = require(Shared:WaitForChild("HoldTimer"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local HoldCountdown = {}

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(246, 200, 92)

-- The number on screen `elapsed` real seconds into the hold.
function HoldCountdown.shown(elapsed: number): number
	return HoldTimer.display(elapsed, Config.HoldSeconds, Config.HoldCountFrom, Config.HoldSlowdown)
end

export type Countdown = { update: (holdStart: number, now: number) -> (), frame: Frame }

-- A countdown under the top of `parent`, `y` pixels down, with `title`
-- (such as "HOLD THE TOP") over the number.
function HoldCountdown.new(parent: Instance, y: number, title: string): Countdown
	local frame = Instance.new("Frame")
	frame.Name = "HoldCountdown"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, y)
	frame.Size = UDim2.fromOffset(320, 140)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 30)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = WHITE
	label.TextStrokeTransparency = 0.35
	label.Text = title
	label.Parent = frame
	local number = Instance.new("TextLabel")
	number.Position = UDim2.fromOffset(0, 30)
	number.Size = UDim2.new(1, 0, 0, 100)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBlack
	number.TextSize = 88
	number.TextColor3 = WHITE
	number.TextStrokeTransparency = 0.2
	number.Text = tostring(Config.HoldCountFrom)
	number.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = number

	local last = -1
	local function update(holdStart: number, now: number)
		if holdStart <= 0 then
			frame.Visible = false
			last = -1
			return
		end
		frame.Visible = true
		local shown = HoldCountdown.shown(now - holdStart)
		if shown ~= last then
			last = shown
			number.Text = tostring(shown)
			number.TextColor3 = WHITE:Lerp(GOLD, 1 - shown / Config.HoldCountFrom)
			scale.Scale = 1.35
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sounds.play("tick")
		end
	end
	return { update = update, frame = frame }
end

return HoldCountdown
