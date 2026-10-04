--!strict
local Format = {}

-- 250000 -> "250,000"
function Format.commas(n: number): string
	local whole = math.floor(math.abs(n) + 0.5)
	local digits = tostring(whole)
	local out = ""
	while #digits > 3 do
		out = "," .. string.sub(digits, -3) .. out
		digits = string.sub(digits, 1, -4)
	end
	return (if n < 0 and whole > 0 then "-" else "") .. digits .. out
end

-- 83.46 -> "1:23.5"; an hour or more -> "1:02:03.0"
function Format.duration(seconds: number): string
	local tenths = math.floor(math.max(0, seconds) * 10 + 0.5)
	local hours = tenths // 36000
	local minutes = (tenths // 600) % 60
	local secs = (tenths % 600) / 10
	if hours > 0 then
		return string.format("%d:%02d:%04.1f", hours, minutes, secs)
	end
	return string.format("%d:%04.1f", minutes, secs)
end

-- "#FF8800" or "FF8800" -> 255, 136, 0 (nil if it is not a colour)
function Format.parseHex(text: string): (number?, number?, number?)
	local hex = string.match(string.upper(text), "^%s*#?(%x%x%x%x%x%x)%s*$")
	if hex == nil then
		return nil, nil, nil
	end
	return tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
end

-- The win counter text: "WINS: 3" or "WINS: 3/10" when a goal is set.
function Format.wins(title: string, wins: number, goal: number): string
	local label = if title == "" then "" else title .. ": "
	if goal > 0 then
		return label .. tostring(wins) .. "/" .. tostring(goal)
	end
	return label .. tostring(wins)
end

return Format
