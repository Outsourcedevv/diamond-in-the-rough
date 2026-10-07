-- A small stand-in for the Roblox API, enough to run the mountain server and
-- client modules under the Luau CLI. Inlined by the Python test wrappers.
local vector = {}
local function V(x: number?, y: number?, z: number?): any
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vector)
end
vector.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return V(v.X / m, v.Y / m, v.Z / m)
	end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return V(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t) return V(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
	return nil
end
vector.__add = function(a, b) return V(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vector.__sub = function(a, b) return V(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vector.__unm = function(a) return V(-a.X, -a.Y, -a.Z) end
vector.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return V(a.X * b, a.Y * b, a.Z * b) end
	return V(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
vector.__div = function(a, b) return V(a.X / b, a.Y / b, a.Z / b) end
vector.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local Vector3 = { new = V, zero = V(0, 0, 0), one = V(1, 1, 1) }

-- CFrame: a position and a 3x3 rotation, rows r[1..9].
local cframe = {}
local function CF(p: any, r: { number }?): any
	return setmetatable({ p = p, r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, cframe)
end
local function rotate(r: { number }, v: any): any
	return V(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function multiply(a: { number }, b: { number }): { number }
	local out = {}
	for i = 0, 2 do
		for j = 0, 2 do
			out[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[j + 4] + a[i * 3 + 3] * b[j + 7]
		end
	end
	return out
end
cframe.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "Rotation" then return CF(V(), c.r) end
	if k == "LookVector" then return V(-c.r[3], -c.r[6], -c.r[9]) end
	if k == "RightVector" then return V(c.r[1], c.r[4], c.r[7]) end
	if k == "UpVector" then return V(c.r[2], c.r[5], c.r[8]) end
	if k == "VectorToWorldSpace" then return function(self, v) return rotate(self.r, v) end end
	if k == "Inverse" or k == "ToObjectSpace" then
		local function inverse(self)
			local r = self.r
			local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
			return CF(rotate(t, self.p) * -1, t)
		end
		if k == "Inverse" then return inverse end
		return function(self, other) return inverse(self) * other end
	end
	return nil
end
cframe.__mul = function(a, b)
	if getmetatable(b) == cframe then return CF(a.p + rotate(a.r, b.p), multiply(a.r, b.r)) end
	return a.p + rotate(a.r, b)
end
cframe.__add = function(a, v) return CF(a.p + v, a.r) end
cframe.__sub = function(a, v) return CF(a.p - v, a.r) end
local function anglesX(t: number) return { 1, 0, 0, 0, math.cos(t), -math.sin(t), 0, math.sin(t), math.cos(t) } end
local function anglesY(t: number) return { math.cos(t), 0, math.sin(t), 0, 1, 0, -math.sin(t), 0, math.cos(t) } end
local function anglesZ(t: number) return { math.cos(t), -math.sin(t), 0, math.sin(t), math.cos(t), 0, 0, 0, 1 } end
local CFrame = {
	identity = CF(V()),
	new = function(x: any, y: number?, z: number?)
		if type(x) == "table" then return CF(x) end
		return CF(V(x or 0, y or 0, z or 0))
	end,
	Angles = function(rx: number, ry: number, rz: number)
		return CF(V(), multiply(multiply(anglesX(rx), anglesY(ry)), anglesZ(rz)))
	end,
	fromAxisAngle = function(axis: any, angle: number)
		local u = axis.Unit
		local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
		return CF(V(), {
			t * u.X * u.X + c, t * u.X * u.Y - s * u.Z, t * u.X * u.Z + s * u.Y,
			t * u.X * u.Y + s * u.Z, t * u.Y * u.Y + c, t * u.Y * u.Z - s * u.X,
			t * u.X * u.Z - s * u.Y, t * u.Y * u.Z + s * u.X, t * u.Z * u.Z + c,
		})
	end,
	fromMatrix = function(position: any, x: any, y: any, z: any)
		z = z or x:Cross(y)
		return CF(position, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
	end,
	lookAt = function(at: any, target: any)
		local look = (target - at).Unit
		local back = -look
		local right = V(0, 1, 0):Cross(back)
		if right.Magnitude < 1e-6 then right = V(1, 0, 0) end
		right = right.Unit
		local up = back:Cross(right)
		return CF(at, { right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z })
	end,
}

local colour = {}
colour.__index = {
	Lerp = function(a, b, t) return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, colour) end,
}
colour.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
local Color3 = {
	new = function(r: number, g: number, b: number) return setmetatable({ R = r, G = g, B = b }, colour) end,
	fromRGB = function(r: number, g: number, b: number) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, colour) end,
}
local function sequence(...) return { ... } end
local ColorSequence = { new = sequence }
local NumberSequence = { new = sequence }
local NumberSequenceKeypoint = { new = sequence }
local NumberRange = { new = sequence }
local vector2 = {}
local function V2(x: number?, y: number?): any return setmetatable({ X = x or 0, Y = y or 0 }, vector2) end
vector2.__add = function(a, b) return V2(a.X + b.X, a.Y + b.Y) end
vector2.__sub = function(a, b) return V2(a.X - b.X, a.Y - b.Y) end
vector2.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return V2(a.X * b, a.Y * b) end
	return V2(a.X * b.X, a.Y * b.Y)
end
vector2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
local Vector2 = { new = V2, zero = V2(0, 0), one = V2(1, 1) }
local UDim = { new = function(scale: number, offset: number) return { Scale = scale, Offset = offset } end }
local Enum = setmetatable({}, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })

local instances = {}
local baseParts = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true }
local newInstance
newInstance = function(className: string): any
	local attributes = {}
	local object = { ClassName = className, destroyed = false }
	object.IsA = function(self, name) return self.ClassName == name or (name == "BasePart" and baseParts[self.ClassName] == true) end
	object.Destroy = function(self) self.destroyed = true; self.Parent = nil end
	object.Clone = function(self)
		local copy = newInstance(self.ClassName)
		for key, value in self do
			if type(value) ~= "function" and key ~= "destroyed" and key ~= "Parent" then copy[key] = value end
		end
		return copy
	end
	object.FindFirstChild = function(self, name)
		for _, other in instances do
			if other.Parent == self and other.Name == name then return other end
		end
		return nil
	end
	object.FindFirstChildOfClass = function(self, className)
		for _, other in instances do
			if other.Parent == self and other.ClassName == className then return other end
		end
		return nil
	end
	object.GetChildren = function(self)
		local children = {}
		for _, other in instances do
			if other.Parent == self then table.insert(children, other) end
		end
		return children
	end
	object.IsDescendantOf = function(self, ancestor)
		local parent = self.Parent
		while parent ~= nil do
			if parent == ancestor then return true end
			parent = if type(parent) == "table" then rawget(parent, "Parent") else nil
		end
		return false
	end
	object.GetDescendants = function(self)
		local out = {}
		for _, other in instances do
			if other ~= self and other.IsDescendantOf and other:IsDescendantOf(self) then table.insert(out, other) end
		end
		return out
	end
	object.ClearAllChildren = function(self)
		for _, other in instances do
			if other.Parent == self then other:Destroy() end
		end
	end
	object.GetAttribute = function(_, key) return attributes[key] end
	object.SetAttribute = function(_, key, value) attributes[key] = value end
	setmetatable(object, { __index = function(self, key)
		if key == "Position" then return rawget(self, "CFrame").Position end
		return nil
	end })
	table.insert(instances, object)
	return object
end
local Instance = { new = newInstance }
local connection = { Disconnect = function() end }
local RunService = { RenderStepped = { Connect = function() return connection end }, Heartbeat = { Connect = function() return connection end } }
local Shared = {}
local game = { GetService = function(_, name)
	if name == "RunService" then return RunService end
	return { WaitForChild = function() return Shared end }
end }
local workspace = {
	Raycast = function() return nil end,
	Spherecast = function() return nil end,
	GetServerTimeNow = function() return os.clock() end,
	BulkMoveTo = function() end,
}
local task = { wait = function() end, defer = function(f, ...) f(...) end, spawn = function(f, ...) f(...) end }
local RaycastParams = { new = function() return {} end }
local Random = { new = function(seed: number?)
	local state = seed or 12345
	local function unit()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		NextNumber = function(_, a, b) return if a then a + unit() * (b - a) else unit() end,
		NextInteger = function(_, a, b) return a + math.floor(unit() * (b - a + 1)) end,
	}
end }
local warn = function(...) print("WARN", ...) end
local UDim2 = {
	new = function(...) return { ... } end,
	fromScale = function(x: number, y: number) return { x, 0, y, 0 } end,
	fromOffset = function(x: number, y: number) return { 0, x, 0, y } end,
}
