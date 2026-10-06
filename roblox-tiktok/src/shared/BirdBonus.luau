--!strict
-- The diamond bird: when it turns up, how it flies and how long its bonus
-- lasts. Plain maths so the server, every client and the tests agree.
local BirdBonus = {}

BirdBonus.ARRIVE_SECONDS = 4 -- swooping down from the sky into its circuit
BirdBonus.LEAVE_SECONDS = 4 -- climbing away after a click, or when the next bird arrives
local ORBIT_SPEED = 0.13 -- radians a second: about 48 seconds a lap

-- Seconds until the next bird, for `roll` in [0, 1).
function BirdBonus.nextDelay(roll: number, minSeconds: number, maxSeconds: number): number
	return minSeconds + math.clamp(roll, 0, 1) * (maxSeconds - minSeconds)
end

-- Gifts arriving before `boostUntil` (server time) count `multiplier` times.
function BirdBonus.multiplier(now: number, boostUntil: number, multiplier: number): number
	return if now < boostUntil then multiplier else 1
end

export type Path = {
	radius: number, -- circuit radius around the mountain's centre (x = z = 0)
	height: number, -- cruising height
	angle: number, -- where on the circuit it arrives
	direction: number, -- 1 anticlockwise, -1 clockwise
}

-- Where the bird is `t` seconds after it appeared. `leaveAt` is when it set
-- off (seconds after it appeared), or nil while it is still circling.
function BirdBonus.position(path: Path, t: number, leaveAt: number?): (number, number, number)
	local angle = path.angle + path.direction * ORBIT_SPEED * t
	-- It swings in and out and rises and dips as it circles, so it passes close
	-- to the camp and never looks like it is on a rail.
	local reach = path.radius * (1 + 0.18 * math.sin(t * 0.37))
	local x, y, z = math.cos(angle) * reach, path.height + 2.5 * math.sin(t * 0.8), math.sin(angle) * reach
	if t < BirdBonus.ARRIVE_SECONDS then
		local away = 1 - t / BirdBonus.ARRIVE_SECONDS
		away *= away
		x, z = x * (1 + 2.5 * away), z * (1 + 2.5 * away)
		y += 60 * away
	end
	if leaveAt ~= nil and t > leaveAt then
		local gone = (t - leaveAt) / BirdBonus.LEAVE_SECONDS
		gone *= gone
		x, z = x * (1 + 3 * gone), z * (1 + 3 * gone)
		y += 80 * gone
	end
	return x, y, z
end

-- Wing angle in radians: steady beats with a glide every so often.
function BirdBonus.flap(t: number, leaving: boolean): number
	local beat = math.sin(t * (if leaving then 14 else 8))
	local gliding = not leaving and math.sin(t * 0.5) > 0.6
	return beat * (if gliding then 0.08 else 0.6) + 0.1
end

return BirdBonus
