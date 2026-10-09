--!nocheck
-- A stand-in Roblox world for play-testing the game under the Luau CLI (see
-- tests/play.py): the
-- server script and the client script run in one VM over the same objects,
-- with a simulated clock, a task scheduler, signals, attributes, remotes
-- that pass straight through, JSON, and enough of each service and class for
-- the game. Anything that errors in a thread is logged (World.errors).
local World = {}
World.errors = {}
World.log = {}
local now = 1000

-- Scheduler ------------------------------------------------------------------
local queue = {}
local cancelled = setmetatable({}, { __mode = "k" })
local function report(where, message, co)
	local text = where .. ": " .. tostring(message)
	if co then text ..= "\n" .. debug.traceback(co) end
	table.insert(World.errors, text)
end
local function resume(co, ...)
	if cancelled[co] or coroutine.status(co) == "dead" then return end
	local ok, problem = coroutine.resume(co, ...)
	if not ok then report("thread", problem, co) end
end
local function spawnFn(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	resume(co, ...)
	return co
end
local task = {}
task.spawn = spawnFn
function task.defer(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	table.insert(queue, { at = now, co = co, args = table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	table.insert(queue, { at = now + (t or 0), co = co, args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = now
	table.insert(queue, { at = now + math.max(t or 0, 1 / 60), co = co, start = start })
	return coroutine.yield()
end
function task.cancel(co) cancelled[co] = true end
function task.synchronize() end
function task.desynchronize() end

-- Signals ----------------------------------------------------------------------
local SignalMT = { __type = "RBXScriptSignal" }
SignalMT.__index = SignalMT
local function Signal()
	return setmetatable({ handlers = {}, waiting = {} }, SignalMT)
end
function SignalMT:Connect(f)
	local connection = { Connected = true }
	function connection.Disconnect() connection.Connected = false end
	connection.disconnect = connection.Disconnect
	table.insert(self.handlers, { f = f, c = connection })
	return setmetatable(connection, { __type = "RBXScriptConnection", __index = { Disconnect = function(c) c.Connected = false end } })
end
SignalMT.connect = SignalMT.Connect
function SignalMT:Once(f)
	local c
	c = self:Connect(function(...) c.Connected = false; f(...) end)
	return c
end
function SignalMT:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function SignalMT:Fire(...)
	for _, h in table.clone(self.handlers) do
		if h.c.Connected then spawnFn(h.f, ...) end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in waiting do resume(co, ...) end
end
World.Signal = Signal

-- Data types --------------------------------------------------------------------
local V3MT = { __type = "Vector3" }
local function V3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3MT) end
V3MT.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); if m == 0 then return V3(0, 0, 0) end return V3(v.X / m, v.Y / m, v.Z / m) end
	if k == "x" then return v.X elseif k == "y" then return v.Y elseif k == "z" then return v.Z end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t) return V3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
	if k == "Min" then return function(a, b) return V3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end end
	if k == "Max" then return function(a, b) return V3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end end
	if k == "Abs" then return function(a) return V3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end end
	if k == "Floor" then return function(a) return V3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z)) end end
	if k == "Ceil" then return function(a) return V3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z)) end end
	if k == "FuzzyEq" then return function(a, b, e) return (a - b).Magnitude <= (e or 1e-5) end end
	if k == "Angle" then return function(a, b) local d = a.Unit:Dot(b.Unit); return math.acos(math.clamp(d, -1, 1)) end end
	return nil
end
V3MT.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
	return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end
	return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3MT.__idiv = function(a, b) return V3(a.X // b, a.Y // b, a.Z // b) end
V3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3MT.__tostring = function(v) return string.format("%g, %g, %g", v.X, v.Y, v.Z) end
local Vector3 = { new = V3, zero = V3(0, 0, 0), one = V3(1, 1, 1), xAxis = V3(1, 0, 0), yAxis = V3(0, 1, 0), zAxis = V3(0, 0, 1),
	FromNormalId = function() return V3(0, 1, 0) end, FromAxis = function() return V3(0, 1, 0) end }

local V2MT = { __type = "Vector2" }
local function V2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2MT) end
V2MT.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y); if m == 0 then return V2(0, 0) end return V2(v.X / m, v.Y / m) end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y end end
	if k == "Lerp" then return function(a, b, t) return V2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end end
	if k == "Cross" then return function(a, b) return a.X * b.Y - a.Y * b.X end end
	return nil
end
V2MT.__add = function(a, b) return V2(a.X + b.X, a.Y + b.Y) end
V2MT.__sub = function(a, b) return V2(a.X - b.X, a.Y - b.Y) end
V2MT.__unm = function(a) return V2(-a.X, -a.Y) end
V2MT.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return V2(a.X * b, a.Y * b) end
	return V2(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b) if type(b) == "number" then return V2(a.X / b, a.Y / b) end return V2(a.X / b.X, a.Y / b.Y) end
V2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
local Vector2 = { new = V2, zero = V2(0, 0), one = V2(1, 1), xAxis = V2(1, 0), yAxis = V2(0, 1) }

-- CFrame: a position and a rotation (rows r[1..9]).
local CFMT = { __type = "CFrame" }
local function CF(p, r) return setmetatable({ p = p, r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CFMT) end
local function rotate(r, v) return V3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z) end
local function mmul(a, b)
	local out = {}
	for i = 0, 2 do for j = 0, 2 do
		out[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[j + 4] + a[i * 3 + 3] * b[j + 7]
	end end
	return out
end
local function transpose(r) return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] } end
local function inverse(c) local t = transpose(c.r); return CF(rotate(t, c.p) * -1, t) end
local function anglesX(t) return { 1, 0, 0, 0, math.cos(t), -math.sin(t), 0, math.sin(t), math.cos(t) } end
local function anglesY(t) return { math.cos(t), 0, math.sin(t), 0, 1, 0, -math.sin(t), 0, math.cos(t) } end
local function anglesZ(t) return { math.cos(t), -math.sin(t), 0, math.sin(t), math.cos(t), 0, 0, 0, 1 } end
local cfMethods = {
	Inverse = inverse,
	ToObjectSpace = function(a, b) return inverse(a) * b end,
	ToWorldSpace = function(a, b) return a * b end,
	PointToObjectSpace = function(a, v) return inverse(a) * v end,
	PointToWorldSpace = function(a, v) return a * v end,
	VectorToObjectSpace = function(a, v) return rotate(transpose(a.r), v) end,
	VectorToWorldSpace = function(a, v) return rotate(a.r, v) end,
	Lerp = function(a, b, t) return CF(a.p:Lerp(b.p, t), if t < 0.5 then a.r else b.r) end,
	GetComponents = function(c) local r = c.r; return c.p.X, c.p.Y, c.p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] end,
	ToEulerAnglesXYZ = function(c) local r = c.r; return math.atan2(-r[6], r[9]), math.asin(math.clamp(r[3], -1, 1)), math.atan2(-r[2], r[1]) end,
	ToEulerAnglesYXZ = function(c) local r = c.r; return math.asin(-math.clamp(r[6], -1, 1)), math.atan2(r[3], r[9]), math.atan2(r[4], r[5]) end,
	ToOrientation = function(c) local r = c.r; return math.asin(-math.clamp(r[6], -1, 1)), math.atan2(r[3], r[9]), math.atan2(r[4], r[5]) end,
	ToAxisAngle = function() return V3(0, 1, 0), 0 end,
	Orthonormalize = function(c) return c end,
	FuzzyEq = function(a, b) return (a.p - b.p).Magnitude < 1e-4 end,
}
CFMT.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X elseif k == "Y" then return c.p.Y elseif k == "Z" then return c.p.Z end
	if k == "Rotation" then return CF(V3(), c.r) end
	if k == "LookVector" then return V3(-c.r[3], -c.r[6], -c.r[9]) end
	if k == "RightVector" or k == "XVector" then return V3(c.r[1], c.r[4], c.r[7]) end
	if k == "UpVector" or k == "YVector" then return V3(c.r[2], c.r[5], c.r[8]) end
	if k == "ZVector" then return V3(c.r[3], c.r[6], c.r[9]) end
	return cfMethods[k]
end
CFMT.__mul = function(a, b)
	if getmetatable(b) == CFMT then return CF(a.p + rotate(a.r, b.p), mmul(a.r, b.r)) end
	return a.p + rotate(a.r, b)
end
CFMT.__add = function(a, v) return CF(a.p + v, a.r) end
CFMT.__sub = function(a, v) return CF(a.p - v, a.r) end
CFMT.__eq = function(a, b) return a.p == b.p end
local function lookAt(at, target, up)
	local look = (target - at)
	if look.Magnitude < 1e-9 then return CF(at) end
	look = look.Unit
	local back = -look
	local right = (up or V3(0, 1, 0)):Cross(back)
	if right.Magnitude < 1e-6 then right = V3(1, 0, 0) end
	right = right.Unit
	local upv = back:Cross(right)
	return CF(at, { right.X, upv.X, back.X, right.Y, upv.Y, back.Y, right.Z, upv.Z, back.Z })
end
local CFrame = {
	identity = CF(V3()),
	new = function(x, y, z, ...)
		if type(x) == "table" and y ~= nil and getmetatable(y) == V3MT then return lookAt(x, y) end
		if type(x) == "table" then return CF(x) end
		local rest = { ... }
		if #rest == 9 then return CF(V3(x, y, z), rest) end
		return CF(V3(x or 0, y or 0, z or 0))
	end,
	Angles = function(rx, ry, rz) return CF(V3(), mmul(mmul(anglesX(rx), anglesY(ry)), anglesZ(rz))) end,
	fromEulerAnglesXYZ = function(rx, ry, rz) return CF(V3(), mmul(mmul(anglesX(rx), anglesY(ry)), anglesZ(rz))) end,
	fromEulerAnglesYXZ = function(rx, ry, rz) return CF(V3(), mmul(mmul(anglesY(ry), anglesX(rx)), anglesZ(rz))) end,
	fromOrientation = function(rx, ry, rz) return CF(V3(), mmul(mmul(anglesY(ry), anglesX(rx)), anglesZ(rz))) end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
		return CF(V3(), {
			t * u.X * u.X + c, t * u.X * u.Y - s * u.Z, t * u.X * u.Z + s * u.Y,
			t * u.X * u.Y + s * u.Z, t * u.Y * u.Y + c, t * u.Y * u.Z - s * u.X,
			t * u.X * u.Z - s * u.Y, t * u.Y * u.Z + s * u.X, t * u.Z * u.Z + c,
		})
	end,
	fromMatrix = function(position, x, y, z)
		z = z or x:Cross(y)
		return CF(position, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
	end,
	lookAt = lookAt,
	lookAlong = function(at, direction) return lookAt(at, at + direction) end,
}

local C3MT = { __type = "Color3" }
local function C3(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3MT) end
C3MT.__index = {
	Lerp = function(a, b, t) return C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end,
	ToHSV = function(c)
		local max, min = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
		local h = 0
		local d = max - min
		if d > 0 then
			if max == c.R then h = ((c.G - c.B) / d) % 6 elseif max == c.G then h = (c.B - c.R) / d + 2 else h = (c.R - c.G) / d + 4 end
			h /= 6
		end
		return h, if max == 0 then 0 else d / max, max
	end,
	ToHex = function(c) return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end,
}
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
local Color3 = {
	new = C3,
	fromRGB = function(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6) % 6
		local f = h * 6 - math.floor(h * 6)
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local list = { { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } }
		local c = list[i + 1]
		return C3(c[1], c[2], c[3])
	end,
	fromHex = function(hex)
		hex = string.gsub(hex, "#", "")
		return C3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
	end,
}

local UDimMT = { __type = "UDim" }
local function UD(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDimMT) end
UDimMT.__add = function(a, b) return UD(a.Scale + b.Scale, a.Offset + b.Offset) end
UDimMT.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
local UDim = { new = UD }
local UDim2MT = { __type = "UDim2" }
local function U2(xs, xo, ys, yo) return setmetatable({ X = UD(xs, xo), Y = UD(ys, yo), Width = UD(xs, xo), Height = UD(ys, yo) }, UDim2MT) end
UDim2MT.__index = { Lerp = function(a, b, t) return U2(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t) end }
UDim2MT.__add = function(a, b) return U2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2MT.__sub = function(a, b) return U2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
UDim2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
local UDim2 = {
	new = function(xs, xo, ys, yo)
		if type(xs) == "table" then return U2(xs.Scale, xs.Offset, xo.Scale, xo.Offset) end
		return U2(xs, xo, ys, yo)
	end,
	fromScale = function(x, y) return U2(x, 0, y, 0) end,
	fromOffset = function(x, y) return U2(0, x, 0, y) end,
}

local function record(kind) return function(...) return setmetatable({ ... }, { __type = kind }) end end
local NumberRange = { new = function(a, b) return setmetatable({ Min = a, Max = b or a }, { __type = "NumberRange" }) end }
local NumberSequenceKeypoint = { new = function(t, v, e) return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, { __type = "NumberSequenceKeypoint" }) end }
local ColorSequenceKeypoint = { new = function(t, v) return setmetatable({ Time = t, Value = v }, { __type = "ColorSequenceKeypoint" }) end }
local NumberSequence = { new = function(a, b)
	if type(a) == "table" then return setmetatable({ Keypoints = a }, { __type = "NumberSequence" }) end
	return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, { __type = "NumberSequence" })
end }
local ColorSequence = { new = function(a, b)
	if type(a) == "table" and getmetatable(a) ~= C3MT then return setmetatable({ Keypoints = a }, { __type = "ColorSequence" }) end
	return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, { __type = "ColorSequence" })
end }
local TweenInfo = { new = function(time, style, direction, repeats, reverses, delay)
	return setmetatable({ Time = time or 1, EasingStyle = style, EasingDirection = direction, RepeatCount = repeats or 0, Reverses = reverses or false, DelayTime = delay or 0 }, { __type = "TweenInfo" })
end }
local Rect = { new = record("Rect") }
local Region3 = { new = function(a, b) return setmetatable({ CFrame = CF((a + b) / 2), Size = b - a }, { __type = "Region3" }) end }
local Content = { fromObject = function(o) return setmetatable({ Object = o }, { __type = "Content" }) end, fromUri = function(u) return setmetatable({ Uri = u }, { __type = "Content" }) end }
local Ray = { new = function(o, d) return setmetatable({ Origin = o, Direction = d, Unit = { Origin = o, Direction = d.Unit } }, { __type = "Ray" }) end }
local function paramsMT(kind)
	return { new = function() return setmetatable({ FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false, CollisionGroup = "Default",
		AddToFilter = function(self, x) table.insert(self.FilterDescendantsInstances, x) end }, { __type = kind }) end }
end
local RaycastParams = paramsMT("RaycastParams")
local OverlapParams = paramsMT("OverlapParams")
local PhysicalProperties = { new = record("PhysicalProperties") }
local BrickColor = { new = function(n) return setmetatable({ Name = tostring(n), Color = C3(0.5, 0.5, 0.5) }, { __type = "BrickColor" }) end,
	random = function() return setmetatable({ Name = "random", Color = C3(0.5, 0.5, 0.5) }, { __type = "BrickColor" }) end }
local Font = { new = record("Font"), fromEnum = record("Font"), fromName = record("Font") }
local Axes = { new = record("Axes") }
local Faces = { new = record("Faces") }
local DateTime = { now = function() return { UnixTimestamp = math.floor(now), UnixTimestampMillis = math.floor(now * 1000), FormatLocalTime = function() return "" end } end }
local Random = { new = function(seed)
	local state = (seed or 12345) % 2147483647
	if state <= 0 then state += 2147483646 end
	local function unit() state = (state * 16807) % 2147483647; return state / 2147483647 end
	return {
		NextNumber = function(_, a, b) return if a then a + unit() * (b - a) else unit() end,
		NextInteger = function(_, a, b) return a + math.floor(unit() * (b - a + 1)) end,
		NextUnitVector = function() local v = V3(unit() - 0.5, unit() - 0.5, unit() - 0.5); return v.Unit end,
		Shuffle = function() end,
		Clone = function(self) return self end,
	}
end }

-- Enums: Enum.Group.Item, one object per item.
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = { IsA = function(e, name) return e.EnumType == name end }
EnumItemMT.__tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end
local enumGroups = {}
local Enum = setmetatable({}, { __index = function(_, group)
	local items = enumGroups[group]
	if items == nil then
		local list = {}
		items = setmetatable({}, { __index = function(t, name)
			if name == "GetEnumItems" then return function() return table.clone(list) end end
			local item = setmetatable({ Name = name, Value = #list, EnumType = group }, EnumItemMT)
			rawset(t, name, item)
			table.insert(list, item)
			return item
		end })
		enumGroups[group] = items
	end
	return items
end })
-- Enum.ContextActionPriority.High.Value and the like.
Enum.ContextActionPriority.High.Value = 2000
Enum.ContextActionPriority.Default.Value = 1000

-- JSON (HttpService) -----------------------------------------------------------
local function encode(value)
	local kind = type(value)
	if kind == "nil" then return "null" end
	if kind == "boolean" then return tostring(value) end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then return "null" end
		if value == math.floor(value) and math.abs(value) < 1e15 then return string.format("%d", value) end
		return string.format("%.14g", value)
	end
	if kind == "string" then
		return '"' .. string.gsub(value, '[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end) .. '"'
	end
	if kind == "table" then
		if next(value) == nil then return "[]" end
		if #value > 0 then
			local parts = {}
			for _, v in ipairs(value) do table.insert(parts, encode(v)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, v in pairs(value) do table.insert(parts, encode(tostring(k)) .. ":" .. encode(v)) end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("can't encode " .. kind)
end
local function decode(text)
	local i = 1
	local function space() i = string.find(text, "[^%s]", i) or #text + 1 end
	local value
	local function str()
		i += 1
		local out = {}
		while true do
			local c = string.sub(text, i, i)
			if c == "" then error("bad json string") end
			if c == '"' then i += 1; break end
			if c == "\\" then
				local n = string.sub(text, i + 1, i + 1)
				local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if n == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(text, i + 2, i + 5), 16)))
					i += 6
				else
					table.insert(out, map[n] or n)
					i += 2
				end
			else
				table.insert(out, c)
				i += 1
			end
		end
		return table.concat(out)
	end
	function value()
		space()
		local c = string.sub(text, i, i)
		if c == "{" then
			i += 1
			local t = {}
			space()
			if string.sub(text, i, i) == "}" then i += 1; return t end
			while true do
				space()
				local k = str()
				space()
				assert(string.sub(text, i, i) == ":", "bad json object")
				i += 1
				t[k] = value()
				space()
				local d = string.sub(text, i, i)
				i += 1
				if d == "}" then return t end
				assert(d == ",", "bad json object")
			end
		elseif c == "[" then
			i += 1
			local t = {}
			space()
			if string.sub(text, i, i) == "]" then i += 1; return t end
			while true do
				table.insert(t, value())
				space()
				local d = string.sub(text, i, i)
				i += 1
				if d == "]" then return t end
				assert(d == ",", "bad json array")
			end
		elseif c == '"' then
			return str()
		elseif string.sub(text, i, i + 3) == "true" then i += 4; return true
		elseif string.sub(text, i, i + 4) == "false" then i += 5; return false
		elseif string.sub(text, i, i + 3) == "null" then i += 4; return nil
		else
			local s, e = string.find(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			if not s then error("bad json at " .. i .. ": " .. string.sub(text, i, i + 20)) end
			i = e + 1
			return tonumber(string.sub(text, s, e))
		end
	end
	if type(text) ~= "string" then error("JSONDecode needs text") end
	local result = value()
	return result
end
World.json = { encode = encode, decode = decode }

-- Instances ------------------------------------------------------------------------
local SUPER = {
	Part = "BasePart", WedgePart = "BasePart", CornerWedgePart = "BasePart", MeshPart = "BasePart", TrussPart = "BasePart",
	SpawnLocation = "Part", UnionOperation = "BasePart", Terrain = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", Workspace = "Model", PVInstance = "Instance",
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton", GuiButton = "GuiObject",
	TextBox = "GuiObject", ImageLabel = "GuiObject", ScrollingFrame = "GuiObject", ViewportFrame = "GuiObject", CanvasGroup = "GuiObject",
	GuiObject = "GuiBase2d", ScreenGui = "LayerCollector", SurfaceGui = "LayerCollector", BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d", GuiBase2d = "Instance",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light", Light = "Instance",
	LocalScript = "BaseScript", Script = "BaseScript", BaseScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer", LuaSourceContainer = "Instance",
	Motor6D = "JointInstance", Weld = "JointInstance", JointInstance = "Instance", WeldConstraint = "Instance",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIPadding = "UIComponent", UIScale = "UIComponent", UIGradient = "UIComponent",
	UIListLayout = "UIGridStyleLayout", UIGridLayout = "UIGridStyleLayout", UIGridStyleLayout = "UIComponent", UISizeConstraint = "UIComponent",
	UITextSizeConstraint = "UIComponent", UIAspectRatioConstraint = "UIComponent", UIComponent = "Instance",
	Atmosphere = "Instance", ColorCorrectionEffect = "PostEffect", BloomEffect = "PostEffect", SunRaysEffect = "PostEffect", BlurEffect = "PostEffect", DepthOfFieldEffect = "PostEffect", PostEffect = "Instance",
}
local function isA(className, name)
	local c = className
	while c do
		if c == name then return true end
		c = SUPER[c]
	end
	return name == "Instance"
end

local EVENTS = {}
for _, name in {
	"Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying",
	"Touched", "TouchEnded", "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click",
	"MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelForward", "MouseWheelBackward", "InputBegan", "InputChanged", "InputEnded",
	"FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard", "SelectionGained", "SelectionLost",
	"PlayerAdded", "PlayerRemoving", "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Died", "HealthChanged",
	"StateChanged", "Running", "Jumping", "FreeFalling", "MoveToFinished", "Seated",
	"MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave", "Triggered", "TriggerEnded", "PromptShown", "PromptHidden",
	"Completed", "Ended", "Played", "Paused", "Resumed", "Stopped", "Loaded", "DidLoop",
	"OnClientEvent", "OnServerEvent", "Event", "OnInvoke",
	"Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "Idle", "WheelForward", "WheelBackward", "KeyDown", "KeyUp",
} do EVENTS[name] = true end

local InstanceMT = { __type = "Instance" }
local methods = {}
local nextId = 0
local allInstances = setmetatable({}, { __mode = "k" })
World.created = 0

local function data(self) return rawget(self, "_d") end
local function children(self) return rawget(self, "_c") end

local DEFAULTS = {}
local function defaultsFor(className)
	local d = {}
	if isA(className, "BasePart") then
		d.Size = V3(4, 1, 2); d.CFrame = CF(V3()); d.Anchored = false; d.CanCollide = true; d.CanQuery = true; d.CanTouch = true
		d.Transparency = 0; d.Reflectance = 0; d.Color = C3(0.64, 0.64, 0.64); d.Material = Enum.Material.Plastic; d.Massless = false
		d.CastShadow = true; d.Locked = false; d.Shape = Enum.PartType.Block; d.AssemblyLinearVelocity = V3(); d.AssemblyAngularVelocity = V3()
		d.Velocity = V3(); d.LocalTransparencyModifier = 0; d.CollisionGroup = "Default"
	end
	if isA(className, "GuiObject") then
		d.Size = U2(0, 100, 0, 100); d.Position = U2(0, 0, 0, 0); d.AnchorPoint = V2(0, 0); d.Visible = true; d.BackgroundTransparency = 0
		d.BackgroundColor3 = C3(1, 1, 1); d.BorderSizePixel = 1; d.ZIndex = 1; d.LayoutOrder = 0; d.Rotation = 0; d.AbsoluteSize = V2(100, 30)
		d.AbsolutePosition = V2(0, 0); d.AbsoluteRotation = 0; d.Text = ""; d.TextColor3 = C3(0, 0, 0); d.TextSize = 14; d.TextTransparency = 0
		d.TextBounds = V2(40, 14); d.ImageTransparency = 0; d.Image = ""; d.ClipsDescendants = false; d.Active = false; d.AutoButtonColor = true
		d.Selectable = false; d.CanvasPosition = V2(0, 0); d.AbsoluteCanvasSize = V2(100, 300); d.AbsoluteWindowSize = V2(100, 100); d.CanvasSize = U2(0, 0, 0, 0)
		d.TextFits = true; d.ContentText = ""; d.GroupTransparency = 0; d.Interactable = true
	end
	if isA(className, "LayerCollector") then d.Enabled = true; d.ResetOnSpawn = true; d.AbsoluteSize = V2(1280, 720) end
	if className == "Humanoid" then
		d.WalkSpeed = 16; d.JumpPower = 50; d.JumpHeight = 7.2; d.UseJumpPower = false; d.Health = 100; d.MaxHealth = 100; d.HipHeight = 2
		d.RigType = Enum.HumanoidRigType.R15; d.MoveDirection = V3(); d.AutoRotate = true; d.FloorMaterial = Enum.Material.Plastic; d.CameraOffset = V3()
		d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer; d.Sit = false; d.PlatformStand = false; d.WalkToPoint = V3()
	end
	if className == "Sound" then d.Volume = 0.5; d.PlaybackSpeed = 1; d.TimeLength = 1; d.TimePosition = 0; d.IsPlaying = false; d.Looped = false; d.SoundId = ""; d.IsLoaded = true end
	if className == "Camera" then d.CFrame = CF(V3(0, 10, 20)); d.ViewportSize = V2(1280, 720); d.FieldOfView = 70; d.Focus = CF(V3()); d.CameraType = Enum.CameraType.Custom; d.NearPlaneZ = -0.1 end
	if isA(className, "Light") then d.Enabled = true; d.Brightness = 1; d.Range = 8; d.Color = C3(1, 1, 1); d.Shadows = false end
	if className == "ParticleEmitter" or className == "Trail" or className == "Beam" or className == "Highlight" or className == "Fire" or className == "Smoke" then d.Enabled = true end
	if className == "Attachment" then d.CFrame = CF(V3()); d.Position = V3(); d.WorldPosition = V3(); d.WorldCFrame = CF(V3()) end
	if className == "UIListLayout" or className == "UIGridLayout" then d.AbsoluteContentSize = V2(100, 400) end
	if className == "Model" or className == "Workspace" then d.PrimaryPart = nil; d.WorldPivot = CF(V3()) end
	if className == "ProximityPrompt" then d.Enabled = true; d.MaxActivationDistance = 10; d.HoldDuration = 0 end
	if className == "ClickDetector" then d.MaxActivationDistance = 32 end
	if className == "Configuration" or className == "Folder" then end
	if className == "TextChatCommand" then d.Enabled = true end
	return d
end

local function newInstance(className)
	nextId += 1
	World.created += 1
	local d = defaultsFor(className)
	d.ClassName = className
	d.Name = className
	local self = setmetatable({ _d = d, _c = {}, _attrs = {}, _changed = {}, _attrChanged = {}, _id = nextId, _class = className }, InstanceMT)
	allInstances[self] = true
	return self
end

local function fireChanged(self, key)
	local s = rawget(self, "_changed")[key]
	if s then s:Fire() end
	local d = data(self)
	if rawget(d, "Changed") then d.Changed:Fire(key) end
end

local waiters = {} -- [parent][name] = { co, ... }
local function setParent(self, parent)
	local d = data(self)
	local old = d.Parent
	if old == parent then return end
	if old then
		local list = children(old)
		for i, c in list do if c == self then table.remove(list, i); break end end
		local ev = rawget(data(old), "ChildRemoved")
		if ev then ev:Fire(self) end
	end
	d.Parent = parent
	if parent then
		table.insert(children(parent), self)
		local ev = rawget(data(parent), "ChildAdded")
		if ev then ev:Fire(self) end
		local a = parent
		while a do
			local dv = rawget(data(a), "DescendantAdded")
			if dv then dv:Fire(self) end
			a = data(a).Parent
		end
		local w = waiters[parent]
		if w and w[d.Name] then
			local list = w[d.Name]
			w[d.Name] = nil
			for _, co in list do resume(co, self) end
		end
	end
	fireChanged(self, "Parent")
	local ac = rawget(d, "AncestryChanged")
	if ac then ac:Fire(self, parent) end
end

local function findChild(self, name)
	for _, c in children(self) do if data(c).Name == name then return c end end
	return nil
end

InstanceMT.__index = function(self, key)
	local d = rawget(self, "_d")
	local v = d[key]
	if v ~= nil then return v end
	local class = rawget(self, "_class")
	local m = methods[class] and methods[class][key]
	if m then return m end
	local c = class
	while c do
		m = methods[c] and methods[c][key]
		if m then return m end
		c = SUPER[c]
	end
	m = methods.Instance[key]
	if m then return m end
	if key == "Position" and isA(class, "BasePart") then return d.CFrame.Position end
	if key == "Orientation" and isA(class, "BasePart") then return V3() end
	if key == "AssemblyMass" or key == "Mass" then return 1 end
	if key == "AssemblyRootPart" then return self end
	if EVENTS[key] then local s = Signal(); d[key] = s; return s end
	local child = findChild(self, key)
	if child then return child end
	return nil
end
InstanceMT.__newindex = function(self, key, value)
	local d = rawget(self, "_d")
	if key == "Parent" then setParent(self, value); return end
	local class = rawget(self, "_class")
	if key == "Position" and isA(class, "BasePart") then
		d.CFrame = CF(value, d.CFrame.r); fireChanged(self, "CFrame"); fireChanged(self, "Position"); return
	end
	if key == "Orientation" and isA(class, "BasePart") then
		d.CFrame = CF(d.CFrame.p) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z)); return
	end
	if key == "Name" and d.Parent then
		-- move waiter registration lookups by name
	end
	local old = d[key]
	d[key] = value
	if old ~= value then fireChanged(self, key) end
end
InstanceMT.__tostring = function(self) return rawget(self, "_d").Name end
World.isInstance = function(v) return getmetatable(v) == InstanceMT end

methods.Instance = {
	IsA = function(self, name) return isA(rawget(self, "_class"), name) end,
	GetChildren = function(self) return table.clone(children(self)) end,
	GetDescendants = function(self)
		local out = {}
		local function walk(o) for _, c in children(o) do table.insert(out, c); walk(c) end end
		walk(self)
		return out
	end,
	FindFirstChild = function(self, name, recursive)
		if recursive then
			for _, c in methods.Instance.GetDescendants(self) do if data(c).Name == name then return c end end
			return nil
		end
		return findChild(self, name)
	end,
	FindFirstChildOfClass = function(self, className) for _, c in children(self) do if rawget(c, "_class") == className then return c end end return nil end,
	FindFirstChildWhichIsA = function(self, className, recursive)
		local list = if recursive then methods.Instance.GetDescendants(self) else children(self)
		for _, c in list do if isA(rawget(c, "_class"), className) then return c end end
		return nil
	end,
	FindFirstAncestor = function(self, name) local p = data(self).Parent; while p do if data(p).Name == name then return p end p = data(p).Parent end return nil end,
	FindFirstAncestorOfClass = function(self, className) local p = data(self).Parent; while p do if rawget(p, "_class") == className then return p end p = data(p).Parent end return nil end,
	FindFirstAncestorWhichIsA = function(self, className) local p = data(self).Parent; while p do if isA(rawget(p, "_class"), className) then return p end p = data(p).Parent end return nil end,
	IsDescendantOf = function(self, ancestor) local p = data(self).Parent; while p do if p == ancestor then return true end p = data(p).Parent end return false end,
	IsAncestorOf = function(self, other) return methods.Instance.IsDescendantOf(other, self) end,
	WaitForChild = function(self, name, timeout)
		local child = findChild(self, name)
		if child then return child end
		local co = coroutine.running()
		if co == World.mainThread then error("WaitForChild(" .. tostring(name) .. ") on the main thread would hang", 2) end
		waiters[self] = waiters[self] or {}
		waiters[self][name] = waiters[self][name] or {}
		table.insert(waiters[self][name], co)
		if timeout and timeout < math.huge then
			table.insert(queue, { at = now + timeout, co = co, timeoutFor = { self, name } })
		end
		table.insert(World.log, "waiting for " .. methods.Instance.GetFullName(self) .. "." .. tostring(name))
		return coroutine.yield()
	end,
	Destroy = function(self)
		local destroying = rawget(data(self), "Destroying")
		if destroying then destroying:Fire() end
		for _, c in table.clone(children(self)) do methods.Instance.Destroy(c) end
		setParent(self, nil)
		rawset(self, "_destroyed", true)
	end,
	Remove = function(self) setParent(self, nil) end,
	ClearAllChildren = function(self) for _, c in table.clone(children(self)) do methods.Instance.Destroy(c) end end,
	Clone = function(self)
		local copy = newInstance(rawget(self, "_class"))
		for k, v in data(self) do
			if k ~= "Parent" and getmetatable(v) ~= SignalMT then data(copy)[k] = v end
		end
		for k, v in rawget(self, "_attrs") do rawget(copy, "_attrs")[k] = v end
		for _, c in children(self) do methods.Instance.Clone(c).Parent = copy end
		return copy
	end,
	GetAttribute = function(self, name) return rawget(self, "_attrs")[name] end,
	SetAttribute = function(self, name, value)
		local attrs = rawget(self, "_attrs")
		local old = attrs[name]
		attrs[name] = value
		if old ~= value then
			local s = rawget(self, "_attrChanged")[name]
			if s then s:Fire() end
		end
	end,
	GetAttributes = function(self) return table.clone(rawget(self, "_attrs")) end,
	GetAttributeChangedSignal = function(self, name)
		local list = rawget(self, "_attrChanged")
		list[name] = list[name] or Signal()
		return list[name]
	end,
	GetPropertyChangedSignal = function(self, name)
		local list = rawget(self, "_changed")
		list[name] = list[name] or Signal()
		return list[name]
	end,
	GetFullName = function(self)
		local names = {}
		local o = self
		while o do table.insert(names, 1, data(o).Name); o = data(o).Parent end
		return table.concat(names, ".")
	end,
	AddTag = function() end, RemoveTag = function() end, HasTag = function() return false end, GetTags = function() return {} end,
	GetActor = function() return nil end,
}

local function partsOf(model)
	local out = {}
	for _, c in methods.Instance.GetDescendants(model) do if isA(rawget(c, "_class"), "BasePart") then table.insert(out, c) end end
	return out
end
methods.PVInstance = {
	GetPivot = function(self)
		if isA(rawget(self, "_class"), "BasePart") then return data(self).CFrame end
		local primary = data(self).PrimaryPart
		if primary then return data(primary).CFrame end
		local list = partsOf(self)
		if #list > 0 then return CF(data(list[1]).CFrame.p) end
		return data(self).WorldPivot or CF(V3())
	end,
	PivotTo = function(self, target)
		if isA(rawget(self, "_class"), "BasePart") then self.CFrame = target; return end
		local pivot = methods.PVInstance.GetPivot(self)
		local delta = target * inverse(pivot)
		for _, p in partsOf(self) do p.CFrame = delta * data(p).CFrame end
		data(self).WorldPivot = target
	end,
}
methods.Model = {
	GetBoundingBox = function(self) return methods.PVInstance.GetPivot(self), V3(4, 4, 4) end,
	GetExtentsSize = function() return V3(4, 4, 4) end,
	GetScale = function(self) return data(self).Scale or 1 end,
	ScaleTo = function(self, s) data(self).Scale = s end,
	SetPrimaryPartCFrame = function(self, c) methods.PVInstance.PivotTo(self, c) end,
	GetPrimaryPartCFrame = function(self) return methods.PVInstance.GetPivot(self) end,
	MoveTo = function(self, v) methods.PVInstance.PivotTo(self, CF(v)) end,
	TranslateBy = function(self, v) methods.PVInstance.PivotTo(self, methods.PVInstance.GetPivot(self) + v) end,
	BreakJoints = function() end, MakeJoints = function() end,
}
methods.BasePart = {
	GetMass = function() return 1 end,
	ApplyImpulse = function() end, ApplyAngularImpulse = function() end,
	SetNetworkOwner = function() end, SetNetworkOwnershipAuto = function() end, GetNetworkOwner = function() return nil end,
	GetTouchingParts = function() return {} end, GetConnectedParts = function() return {} end,
	CanSetNetworkOwnership = function() return true end,
	BreakJoints = function() end,
	GetClosestPointOnSurface = function(self, v) return v end,
}
methods.Humanoid = {
	GetState = function() return Enum.HumanoidStateType.Running end,
	ChangeState = function() end, SetStateEnabled = function() end, GetStateEnabled = function() return true end,
	MoveTo = function() end, Move = function() end, TakeDamage = function(self, n) self.Health -= n end,
	LoadAnimation = function() return setmetatable({ Play = function() end, Stop = function() end, AdjustSpeed = function() end, Stopped = Signal(), Length = 1, IsPlaying = false }, {}) end,
	GetPlayingAnimationTracks = function() return {} end,
	GetAppliedDescription = function() return newInstance("HumanoidDescription") end,
	ApplyDescription = function() end, UnequipTools = function() end, EquipTool = function() end,
	GetLimb = function() return Enum.Limb.Unknown end, GetMoveVelocity = function() return V3() end, BuildRigFromAttachments = function() end,
}
methods.Animator = { LoadAnimation = methods.Humanoid.LoadAnimation, GetPlayingAnimationTracks = function() return {} end }
methods.Sound = {
	Play = function(self) data(self).IsPlaying = true; local d = data(self); local ended = d.Ended or Signal(); d.Ended = ended
		if not d.Looped then task.delay(d.TimeLength / math.max(d.PlaybackSpeed, 0.01), function() d.IsPlaying = false; ended:Fire(d.SoundId) end) end end,
	Stop = function(self) data(self).IsPlaying = false end,
	Pause = function(self) data(self).IsPlaying = false end,
	Resume = function(self) data(self).IsPlaying = true end,
}
methods.RemoteEvent = {
	FireServer = function(self, ...) self.OnServerEvent:Fire(World.player, ...) end,
	FireClient = function(self, _player, ...) self.OnClientEvent:Fire(...) end,
	FireAllClients = function(self, ...) self.OnClientEvent:Fire(...) end,
}
methods.UnreliableRemoteEvent = methods.RemoteEvent
methods.RemoteFunction = {
	InvokeServer = function(self, ...) local f = data(self).OnServerInvoke; return if f then f(World.player, ...) else nil end,
}
methods.BindableEvent = { Fire = function(self, ...) self.Event:Fire(...) end }
methods.ParticleEmitter = { Emit = function() end, Clear = function() end }
methods.TextBox = { CaptureFocus = function() end, ReleaseFocus = function() end, IsFocused = function() return false end }
methods.GuiObject = {
	TweenPosition = function(self, p) self.Position = p; return true end,
	TweenSize = function(self, s) self.Size = s; return true end,
	TweenSizeAndPosition = function(self, s, p) self.Size = s; self.Position = p; return true end,
}
methods.Camera = {
	WorldToViewportPoint = function(self, v) local c = data(self).CFrame; local rel = inverse(c) * v; return V3(640 + rel.X * 10, 360 - rel.Y * 10, -rel.Z), rel.Z < 0 end,
	WorldToScreenPoint = function(self, v) local c = data(self).CFrame; local rel = inverse(c) * v; return V3(640 + rel.X * 10, 360 - rel.Y * 10, -rel.Z), rel.Z < 0 end,
	ViewportPointToRay = function(self, x, y) local c = data(self).CFrame; return Ray.new(c.p, c.LookVector) end,
	ScreenPointToRay = function(self, x, y) local c = data(self).CFrame; return Ray.new(c.p, c.LookVector) end,
	ZoomToExtents = function() end,
	GetPartsObscuringTarget = function() return {} end,
}
methods.Player = {
	GetMouse = function(self)
		local d = data(self)
		if not d._mouse then
			d._mouse = setmetatable({ Hit = CF(V3()), Origin = CF(V3()), Target = nil, X = 640, Y = 360, Icon = "", UnitRay = Ray.new(V3(), V3(0, 0, -1)),
				TargetFilter = nil, ViewSizeX = 1280, ViewSizeY = 720 }, { __index = function(_, k) if EVENTS[k] then return Signal() end end })
		end
		return d._mouse
	end,
	LoadCharacter = function(self) World.spawnCharacter(self) end,
	Kick = function() end,
	GetRankInGroupAsync = function() return 0 end, GetRoleInGroup = function() return "Guest" end, IsInGroup = function() return false end, IsInGroupAsync = function() return false end,
	GetNetworkPing = function() return 0.05 end, HasAppearanceLoaded = function() return true end,
	ClearCharacterAppearance = function() end, GetFriendsOnline = function() return {} end, IsFriendsWith = function() return false end,
	RequestStreamAroundAsync = function() end,
}
methods.Players = {
	GetPlayers = function(self) local out = {}; for _, c in children(self) do if rawget(c, "_class") == "Player" then table.insert(out, c) end end return out end,
	GetPlayerFromCharacter = function(self, character)
		for _, c in children(self) do if rawget(c, "_class") == "Player" and data(c).Character == character and character ~= nil then return c end end
		return nil
	end,
	GetPlayerByUserId = function(self, id) for _, c in children(self) do if data(c).UserId == id then return c end end return nil end,
	GetUserIdFromNameAsync = function() return 1 end, GetNameFromUserIdAsync = function() return "Player1" end,
	GetUserThumbnailAsync = function() return "rbxassetid://0", true end,
	GetHumanoidDescriptionFromUserId = function() return newInstance("HumanoidDescription") end,
	CreateHumanoidModelFromDescription = function() return newInstance("Model") end,
}
methods.Workspace = {
	Raycast = function() return nil end, Spherecast = function() return nil end, Blockcast = function() return nil end, Shapecast = function() return nil end,
	GetPartBoundsInBox = function() return {} end, GetPartBoundsInRadius = function() return {} end, GetPartsInPart = function() return {} end,
	GetServerTimeNow = function() return now + 1.7e9 end,
	BulkMoveTo = function(_, parts, frames) for i, p in parts do data(p).CFrame = frames[i] end end,
	FindPartOnRay = function() return nil, V3() end, FindPartOnRayWithIgnoreList = function() return nil, V3() end,
	GetRealPhysicsFPS = function() return 60 end,
}
methods.Terrain = setmetatable({}, { __index = function(_, k)
	if k == "ReadVoxels" then return function() return {}, {} end end
	if k == "GetMaterialColor" then return function() return C3(0.5, 0.5, 0.5) end end
	if k == "WorldToCell" or k == "WorldToCellPreferSolid" or k == "WorldToCellPreferEmpty" then return function() return V3() end end
	if k == "CellCenterToWorld" or k == "CellCornerToWorld" then return function() return V3() end end
	if k == "CopyRegion" then return function() return {} end end
	return function() end -- FillBlock, FillBall, Clear, SetMaterialColor, WriteVoxels, ...
end })

-- Services ------------------------------------------------------------------------------
local game = newInstance("DataModel")
data(game).Name = "Game"
local services = {}
local function service(name, className)
	local s = newInstance(className or name)
	data(s).Name = name
	s.Parent = game
	services[name] = s
	return s
end
methods.DataModel = {
	GetService = function(_, name)
		local s = services[name]
		if s == nil then error("no stand-in for service " .. tostring(name), 2) end
		return s
	end,
	BindToClose = function(_, f) World.onClose = f end,
	IsLoaded = function() return true end,
}
methods.DataModel.FindService = methods.DataModel.GetService

local workspace = service("Workspace")
workspace.Gravity = 196.2
local camera = newInstance("Camera")
camera.Name = "Camera"
camera.Parent = workspace
workspace.CurrentCamera = camera
local terrain = newInstance("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
service("Players")
service("ReplicatedStorage")
service("ReplicatedFirst")
data(game).Loaded = Signal()
service("ServerStorage")
service("ServerScriptService")
service("StarterPack")
service("StarterGui")
local starterPlayer = service("StarterPlayer")
starterPlayer.CharacterWalkSpeed = 16; starterPlayer.CharacterJumpPower = 50; starterPlayer.CharacterJumpHeight = 7.2; starterPlayer.CharacterUseJumpPower = false
local sps = newInstance("StarterPlayerScripts"); sps.Name = "StarterPlayerScripts"; sps.Parent = starterPlayer
service("Lighting")
service("SoundService")
service("MaterialService")
service("Teams")
service("Chat")
service("CollectionService")
service("PhysicsService")
service("ProximityPromptService")
service("Debris")
service("TweenService")
service("RunService")
service("UserInputService")
service("ContextActionService")
service("GuiService")
service("HttpService")
service("TextService")
service("TextChatService")
service("MarketplaceService")
service("DataStoreService")
service("AssetService")
service("LocalizationService")
service("BadgeService")
service("SocialService")
service("PolicyService")
service("AvatarEditorService")
services.TextChatService.ChatVersion = Enum.ChatVersion.TextChatService
services.HttpService.HttpEnabled = false

methods.CollectionService = { GetTagged = function() return {} end, GetInstanceAddedSignal = function() return Signal() end, GetInstanceRemovedSignal = function() return Signal() end,
	AddTag = function() end, RemoveTag = function() end, HasTag = function() return false end }
methods.PhysicsService = { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end, CreateCollisionGroup = function() end,
	SetPartCollisionGroup = function() end, IsCollisionGroupRegistered = function() return false end }
methods.Debris = { AddItem = function(_, item, t) task.delay(t or 10, function() if data(item).Parent then methods.Instance.Destroy(item) end end) end }
local tweenCount = 0
methods.TweenService = {
	Create = function(_, object, info, goal)
		tweenCount += 1
		local tween = { Completed = Signal(), PlaybackState = Enum.PlaybackState.Begin, Instance = object, TweenInfo = info }
		local cancelledTween = false
		function tween.Play(t)
			cancelledTween = false
			t.PlaybackState = Enum.PlaybackState.Playing
			local duration = (info and info.Time or 1) + (info and info.DelayTime or 0)
			task.delay(duration, function()
				if cancelledTween then return end
				for k, v in goal do object[k] = v end
				t.PlaybackState = Enum.PlaybackState.Completed
				t.Completed:Fire(Enum.PlaybackState.Completed)
			end)
		end
		function tween.Cancel(t) cancelledTween = true; t.PlaybackState = Enum.PlaybackState.Cancelled end
		function tween.Pause(t) cancelledTween = true; t.PlaybackState = Enum.PlaybackState.Paused end
		function tween.Destroy() end
		return setmetatable(tween, { __type = "Instance" })
	end,
	GetValue = function(_, alpha) return alpha end,
	SmoothDamp = function(_, current, target) return target, 0 end,
}
local runService = services.RunService
for _, name in { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation", "PreAnimation" } do
	data(runService)[name] = Signal()
end
methods.RunService = {
	IsStudio = function() return true end, IsClient = function() return World.side ~= "server" end, IsServer = function() return World.side ~= "client" end,
	IsRunning = function() return true end, IsRunMode = function() return false end, IsEdit = function() return false end,
	BindToRenderStep = function(_, name, _priority, f) World.renderSteps = World.renderSteps or {}; World.renderSteps[name] = f end,
	UnbindFromRenderStep = function(_, name) if World.renderSteps then World.renderSteps[name] = nil end end,
}
local uis = services.UserInputService
for k, v in { MouseBehavior = Enum.MouseBehavior.Default, MouseIconEnabled = true, TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true,
	GamepadEnabled = false, VREnabled = false, AccelerometerEnabled = false, GyroscopeEnabled = false, MouseDeltaSensitivity = 1, ModalEnabled = false } do data(uis)[k] = v end
for _, name in { "WindowFocused", "WindowFocusReleased", "JumpRequest", "LastInputTypeChanged", "TouchStarted", "TouchEnded", "TouchMoved", "TouchTap", "GamepadConnected", "GamepadDisconnected", "TextBoxFocused", "TextBoxFocusReleased", "PointerAction" } do
	data(uis)[name] = Signal()
end
World.held = {}
World.focused = nil
methods.UserInputService = {
	GetMouseLocation = function() return V2(640, 360) end,
	GetFocusedTextBox = function() return World.focused end,
	IsKeyDown = function(_, key) return World.held[key] == true end,
	IsMouseButtonPressed = function() return false end,
	GetMouseDelta = function() return V2(0, 0) end,
	GetLastInputType = function() return Enum.UserInputType.Keyboard end,
	GetKeysPressed = function() return {} end,
	GetMouseButtonsPressed = function() return {} end,
	GetGamepadConnected = function() return false end,
	GetConnectedGamepads = function() return {} end,
	GetNavigationGamepads = function() return {} end,
	GetStringForKeyCode = function(_, k) return k.Name end,
	GetImageForKeyCode = function() return "" end,
	IsGamepadButtonDown = function() return false end,
	GetSupportedGamepadKeyCodes = function() return {} end,
}
World.actions = {}
methods.ContextActionService = {
	BindAction = function(_, name, f, touch, ...) World.actions[name] = { f = f, keys = { ... }, touch = touch } end,
	BindActionAtPriority = function(_, name, f, touch, _priority, ...) World.actions[name] = { f = f, keys = { ... }, touch = touch } end,
	UnbindAction = function(_, name) World.actions[name] = nil end,
	SetTitle = function() end, SetImage = function() end, SetPosition = function() end, SetDescription = function() end,
	GetButton = function() return nil end, GetAllBoundActionInfo = function() return {} end,
	BindCoreAction = function() end, UnbindCoreAction = function() end,
}
methods.GuiService = {
	GetGuiInset = function() return V2(0, 36), V2(0, 0) end,
	IsTenFootInterface = function() return false end,
	GetScreenResolution = function() return V2(1280, 720) end,
}
services.GuiService.SelectedObject = nil
methods.StarterGui = {
	SetCoreGuiEnabled = function(_, kind, on) World.coreGui = World.coreGui or {}; World.coreGui[tostring(kind)] = on end,
	GetCoreGuiEnabled = function() return true end,
	SetCore = function() end, GetCore = function() return nil end,
}
methods.SoundService = { PlayLocalSound = function() end, SetListener = function() end }
methods.HttpService = {
	JSONEncode = function(_, v) return encode(v) end,
	JSONDecode = function(_, t) return decode(t) end,
	GenerateGUID = function() nextId += 1; return "guid-" .. nextId end,
	UrlEncode = function(_, s) return s end,
	GetAsync = function() error("HTTP requests are off") end,
	PostAsync = function() error("HTTP requests are off") end,
	RequestAsync = function() error("HTTP requests are off") end,
}
methods.TextService = {
	FilterStringAsync = function(_, text)
		return { GetNonChatStringForBroadcastAsync = function() return text end, GetNonChatStringForUserAsync = function() return text end,
			GetChatForUserAsync = function() return text end }
	end,
	GetTextSize = function(_, text, size) return V2(#tostring(text) * (size or 14) * 0.55, size or 14) end,
	GetTextBoundsAsync = function() return V2(100, 14) end,
	FilterAndTranslateStringAsync = function(_, text) return { GetNonChatStringForBroadcastAsync = function() return text end } end,
}
World.purchases = {}
World.ownedPasses = {}
data(services.MarketplaceService).PromptGamePassPurchaseFinished = Signal()
data(services.MarketplaceService).PromptProductPurchaseFinished = Signal()
data(services.MarketplaceService).PromptPurchaseFinished = Signal()
methods.MarketplaceService = {
	PromptGamePassPurchase = function(_, player, id) table.insert(World.purchases, { player = player, pass = id }) end,
	PromptProductPurchase = function(_, player, id) table.insert(World.purchases, { player = player, product = id }) end,
	UserOwnsGamePassAsync = function(_, _user, id) return World.ownedPasses[id] == true end,
	GetProductInfo = function(_, id) return { PriceInRobux = 99, Name = "Pass " .. tostring(id), IsForSale = true } end,
	PlayerOwnsAsset = function() return false end,
}
World.saves = {}
methods.DataStoreService = {
	GetDataStore = function(_, name)
		World.saves[name] = World.saves[name] or {}
		local store = World.saves[name]
		return {
			GetAsync = function(_, key) return store[key] end,
			SetAsync = function(_, key, value) store[key] = decode(encode(value)); World.saveCount = (World.saveCount or 0) + 1 end,
			UpdateAsync = function(_, key, f) store[key] = f(store[key]) return store[key] end,
			RemoveAsync = function(_, key) store[key] = nil end,
			IncrementAsync = function(_, key, n) store[key] = (store[key] or 0) + (n or 1); return store[key] end,
		}
	end,
	GetOrderedDataStore = function() return { GetSortedAsync = function() return { GetCurrentPage = function() return {} end, IsFinished = true } end, SetAsync = function() end } end,
	GetRequestBudgetForRequestType = function() return 100 end,
}
-- EditableMesh is out of reach here, as in a published game without the
-- Mesh / Image APIs: the game falls back to its built-in scenery.
methods.AssetService = {
	CreateEditableMesh = function() error("EditableMesh isn't available here") end,
	CreateMeshPartAsync = function() error("EditableMesh isn't available here") end,
	CreateEditableImage = function() error("EditableImage isn't available here") end,
}
methods.ReplicatedFirst = { RemoveDefaultLoadingScreen = function() World.defaultLoadingRemoved = true end }
methods.LocalizationService = { GetCountryRegionForPlayerAsync = function() return "US" end }
methods.PolicyService = { GetPolicyInfoForPlayerAsync = function() return { AreAdsAllowed = true, ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {} } end }
methods.BadgeService = { AwardBadge = function() return true end, UserHasBadgeAsync = function() return false end }
data(services.ProximityPromptService).PromptTriggered = Signal()
data(services.ProximityPromptService).PromptButtonHoldBegan = Signal()
data(services.ProximityPromptService).PromptButtonHoldEnded = Signal()
data(services.ProximityPromptService).PromptShown = Signal()
data(services.ProximityPromptService).PromptHidden = Signal()

-- Characters -------------------------------------------------------------------------------
function World.spawnCharacter(player)
	local old = data(player).Character
	if old then methods.Instance.Destroy(old) end
	local character = newInstance("Model")
	character.Name = data(player).Name
	local function part(name, size, offset)
		local p = newInstance("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CF(V3(0, 5, 0) + offset)
		p.Parent = character
		return p
	end
	local root = part("HumanoidRootPart", V3(2, 2, 1), V3())
	character.PrimaryPart = root
	part("Head", V3(1.2, 1.2, 1.2), V3(0, 2, 0))
	part("UpperTorso", V3(2, 1.6, 1), V3(0, 0.4, 0))
	part("LowerTorso", V3(2, 0.4, 1), V3(0, -0.6, 0))
	local rightUpper = part("RightUpperArm", V3(1, 1.2, 1), V3(1.5, 0.5, 0))
	local shoulder = newInstance("Motor6D"); shoulder.Name = "RightShoulder"; shoulder.C0 = CF(V3()); shoulder.C1 = CF(V3()); shoulder.Parent = rightUpper
	part("RightLowerArm", V3(1, 1, 1), V3(1.5, -0.6, 0))
	part("RightHand", V3(1, 0.4, 1), V3(1.5, -1.3, 0))
	part("LeftUpperArm", V3(1, 1.2, 1), V3(-1.5, 0.5, 0))
	part("LeftLowerArm", V3(1, 1, 1), V3(-1.5, -0.6, 0))
	part("LeftHand", V3(1, 0.4, 1), V3(-1.5, -1.3, 0))
	part("RightUpperLeg", V3(1, 1, 1), V3(0.5, -1.4, 0))
	part("LeftUpperLeg", V3(1, 1, 1), V3(-0.5, -1.4, 0))
	part("RightFoot", V3(1, 0.4, 1), V3(0.5, -2.8, 0))
	part("LeftFoot", V3(1, 0.4, 1), V3(-0.5, -2.8, 0))
	local humanoid = newInstance("Humanoid")
	humanoid.Name = "Humanoid"
	local animator = newInstance("Animator"); animator.Name = "Animator"; animator.Parent = humanoid
	humanoid.Parent = character
	local spawnAt = data(player).RespawnLocation
	if spawnAt then methods.PVInstance.PivotTo(character, data(spawnAt).CFrame + V3(0, 4, 0)) end
	data(player).Character = character
	character.Parent = workspace
	fireChanged(player, "Character")
	player.CharacterAdded:Fire(character)
	camera.CameraSubject = humanoid
	return character
end

function World.addPlayer(name, userId)
	local player = newInstance("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.AccountAge = 100
	player.MembershipType = Enum.MembershipType.None
	local gui = newInstance("PlayerGui"); gui.Name = "PlayerGui"; gui.Parent = player
	local scripts = newInstance("PlayerScripts"); scripts.Name = "PlayerScripts"; scripts.Parent = player
	local backpack = newInstance("Backpack"); backpack.Name = "Backpack"; backpack.Parent = player
	World.player = player
	services.Players.LocalPlayer = player
	player.Parent = services.Players
	services.Players.PlayerAdded:Fire(player)
	return player
end

-- Modules and scripts ------------------------------------------------------------------------
local moduleResults = {}
local env -- the globals every script sees
local function run(container, source)
	local chunk, problem = loadstring(source, "=" .. methods.Instance.GetFullName(container))
	if not chunk then error("compile " .. methods.Instance.GetFullName(container) .. ": " .. tostring(problem)) end
	setfenv(chunk, setmetatable({ script = container }, { __index = env }))
	return chunk
end
local function require(target)
	if type(target) ~= "table" or getmetatable(target) ~= InstanceMT then error("require needs a ModuleScript here: " .. tostring(target), 2) end
	local cached = moduleResults[target]
	if cached then return cached.value end
	local source = rawget(target, "_source")
	if not source then error("not a module: " .. methods.Instance.GetFullName(target), 2) end
	local value = run(target, source)()
	moduleResults[target] = { value = value }
	return value
end
function World.addScript(parent, name, className, source)
	local container = newInstance(className)
	container.Name = name
	rawset(container, "_source", source)
	container.Parent = parent
	return container
end
function World.start(container)
	local chunk = run(container, rawget(container, "_source"))
	return spawnFn(chunk)
end

local function typeOf(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and rawget(mt, "__type") then return mt.__type end
	return type(v)
end
local realOs = os
env = {
	game = game, Game = game, workspace = workspace, Workspace = workspace, script = nil,
	Instance = { new = function(className, parent) local i = newInstance(className); if parent then i.Parent = parent end return i end, fromExisting = function(i) return methods.Instance.Clone(i) end },
	Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, UDim = UDim, UDim2 = UDim2, Enum = Enum,
	NumberRange = NumberRange, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, TweenInfo = TweenInfo, Rect = Rect, Ray = Ray,
	RaycastParams = RaycastParams, OverlapParams = OverlapParams, PhysicalProperties = PhysicalProperties, BrickColor = BrickColor,
	Font = Font, Axes = Axes, Faces = Faces, DateTime = DateTime, Random = Random, Region3 = Region3, Content = Content,
	task = task, wait = task.wait, delay = task.delay, spawn = task.spawn,
	tick = function() return now end, time = function() return now end, elapsedTime = function() return now end,
	os = setmetatable({ clock = function() return now end, time = function() return math.floor(now) end }, { __index = realOs }),
	typeof = typeOf, require = require,
	print = function(...) local parts = {}; for i = 1, select("#", ...) do table.insert(parts, tostring((select(i, ...)))) end table.insert(World.log, "print: " .. table.concat(parts, " ")) end,
	warn = function(...) local parts = {}; for i = 1, select("#", ...) do table.insert(parts, tostring((select(i, ...)))) end table.insert(World.log, "WARN: " .. table.concat(parts, " ")) end,
	settings = function() return { Rendering = { QualityLevel = 10 } } end,
	UserSettings = function() return { GetService = function() return { SavedQualityLevel = Enum.SavedQualitySetting.Automatic } end } end,
	shared = {}, _G = {},
}
setmetatable(env, { __index = getfenv(0) })

-- The clock --------------------------------------------------------------------------------------
function World.now() return now end
function World.step(dt)
	now += dt
	for _, name in { "PreSimulation", "Stepped", "PostSimulation", "Heartbeat", "PreRender", "RenderStepped" } do
		local s = data(runService)[name]
		if name == "Stepped" then s:Fire(now, dt) else s:Fire(dt) end
	end
	if World.renderSteps then for _, f in World.renderSteps do spawnFn(f, dt) end end
	local guard = 0
	while true do
		guard += 1
		if guard > 20000 then report("scheduler", "too many threads due at once") break end
		local index = nil
		for i, item in queue do
			if item.at <= now and (index == nil or item.at < queue[index].at) then index = i end
		end
		if index == nil then break end
		local item = table.remove(queue, index)
		if item.timeoutFor then
			local w = waiters[item.timeoutFor[1]]
			local list = w and w[item.timeoutFor[2]]
			if list then
				for i, co in list do if co == item.co then table.remove(list, i); resume(item.co, nil); break end end
			end
		elseif item.start then
			resume(item.co, now - item.start)
		elseif item.args then
			resume(item.co, table.unpack(item.args, 1, item.args.n))
		else
			resume(item.co)
		end
	end
end
function World.run(seconds, dt)
	dt = dt or 1 / 20
	local steps = math.ceil(seconds / dt)
	for _ = 1, steps do World.step(dt) end
end

World.game = game
World.services = services
World.workspace = workspace
World.camera = camera
World.V3, World.V2, World.CF, World.C3 = V3, V2, CF, C3
World.lookAt = lookAt
World.Enum = Enum
World.newInstance = newInstance
World.data = data
World.children = children
World.fire = fireChanged
World.queueLength = function() return #queue end
function World.input(key, began)
	local input = { KeyCode = Enum.KeyCode[key], UserInputType = Enum.UserInputType.Keyboard, UserInputState = if began then Enum.UserInputState.Begin else Enum.UserInputState.End,
		Position = V3(640, 360, 0), Delta = V3() }
	if began then World.held[Enum.KeyCode[key]] = true; uis.InputBegan:Fire(input, false)
	else World.held[Enum.KeyCode[key]] = nil; uis.InputEnded:Fire(input, false) end
	-- Bound actions see it too.
	for name, action in World.actions do
		for _, k in action.keys do
			if k == Enum.KeyCode[key] then spawnFn(action.f, name, input.UserInputState, input) end
		end
	end
end
function World.press(key)
	World.input(key, true)
	World.input(key, false)
end
function World.find(root, predicate)
	for _, c in methods.Instance.GetDescendants(root) do if predicate(c) then return c end end
	return nil
end
function World.findAll(root, predicate)
	local out = {}
	for _, c in methods.Instance.GetDescendants(root) do if predicate(c) then table.insert(out, c) end end
	return out
end
World.require = require
World.mainThread = coroutine.running()

return World
