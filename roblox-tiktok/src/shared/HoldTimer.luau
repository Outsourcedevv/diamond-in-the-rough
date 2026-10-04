--!strict
-- The diamond must be held for HoldSeconds of real time, but the screen counts
-- down from HoldCountFrom (10). The count runs quickly at first and slows near
-- the end, so the last numbers hang on screen for longer.
local HoldTimer = {}

-- How much of the on-screen countdown has passed after a fraction p of the real
-- hold time. slowdown 0 is linear; 1 is a full ease-out (4x slower at the end).
function HoldTimer.progress(p: number, slowdown: number): number
	p = math.clamp(p, 0, 1)
	slowdown = math.clamp(slowdown, 0, 1)
	return (1 - slowdown) * p + slowdown * (1 - (1 - p) * (1 - p))
end

-- The whole number to show after `elapsed` real seconds: countFrom at the start,
-- never below 1 until the hold is complete, then 0.
function HoldTimer.display(elapsed: number, holdSeconds: number, countFrom: number, slowdown: number): number
	if elapsed >= holdSeconds then
		return 0
	end
	local shown = countFrom * (1 - HoldTimer.progress(elapsed / holdSeconds, slowdown))
	return math.max(1, math.ceil(shown - 1e-9))
end

return HoldTimer
