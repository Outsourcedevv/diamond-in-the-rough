--!strict
-- Sprinting: hold Shift (or press the left stick on a controller, or hold the
-- Run button on a phone) to move Config.SprintMultiplier times faster.
--
-- The server sets each character's walking speed (the usual 16, Diamond
-- Climb's speed slider, 0 while holding the diamond or writing on the
-- chalkboard), so sprinting multiplies whatever that speed is rather than
-- replacing it: any change this module didn't make itself becomes the new
-- walking speed. Changes are recognised by their value, not by a "this was
-- me" flag, because Roblox may deliver the change signal after the change
-- (deferred signals), when such a flag would already be cleared.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local Config = require(Shared:WaitForChild("Config"))

local Sprint = {}

Sprint.MULTIPLIER = Config.SprintMultiplier
Sprint.ACTION = "DiamondRushSprint"

-- The speed to move at: the walking speed, or faster while sprinting.
function Sprint.speed(walking: number, sprinting: boolean): number
	return if sprinting then walking * Sprint.MULTIPLIER else walking
end

export type Walker = { WalkSpeed: number }
export type Controller = {
	attach: (walker: Walker?) -> (),
	setHeld: (held: boolean) -> (),
	changed: () -> (),
	walking: () -> number,
	held: () -> boolean,
}

-- Keeps one character's speed: `attach` a new humanoid, `setHeld` as the
-- sprint key goes down and up, and `changed` whenever its WalkSpeed changes.
function Sprint.controller(): Controller
	local walker: Walker? = nil
	local walking = 16
	local held = false
	local self = {} :: Controller

	local function apply()
		local current = walker
		if current == nil then return end
		local want = Sprint.speed(walking, held)
		if math.abs(current.WalkSpeed - want) > 1e-3 then current.WalkSpeed = want end
	end

	function self.attach(next: Walker?)
		walker = next
		if next then walking = next.WalkSpeed end
		apply()
	end

	function self.setHeld(value: boolean)
		if value == held then return end
		held = value
		apply()
	end

	function self.changed()
		local current = walker
		if current == nil then return end
		-- The speed this module set itself: nothing to do.
		if math.abs(current.WalkSpeed - Sprint.speed(walking, held)) <= 1e-3 then return end
		-- Someone else set it (the server, or Diamond Climb's slider): that's
		-- the walking speed now, and sprinting goes on from there.
		walking = current.WalkSpeed
		apply()
	end

	function self.walking(): number return walking end
	function self.held(): boolean return held end
	return self
end

function Sprint.start()
	local player = Players.LocalPlayer
	local control = Sprint.controller()
	local watching: RBXScriptConnection? = nil

	local function onCharacter(character: Model)
		if watching then watching:Disconnect() end
		watching = nil
		control.attach(nil)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") or character.Parent == nil then return end
		control.attach(humanoid :: any) -- a Humanoid has the WalkSpeed a Walker needs
		watching = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(control.changed)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end

	-- Shift (either one), the left stick's click, or the on-screen Run button.
	-- The keys still reach everything else (Pass), so Shift Lock and Shift
	-- gift keys keep working.
	ContextActionService:BindAction(Sprint.ACTION, function(_name: string, state: Enum.UserInputState, _input: InputObject)
		if state == Enum.UserInputState.Begin then
			control.setHeld(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			control.setHeld(false)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle(Sprint.ACTION, "Run")
	ContextActionService:SetPosition(Sprint.ACTION, UDim2.new(1, -170, 1, -90))
	-- Letting go while the window wasn't focused never reaches the action.
	UserInputService.WindowFocusReleased:Connect(function() control.setHeld(false) end)
end

return Sprint
