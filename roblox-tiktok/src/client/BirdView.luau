--!strict
-- Flies the diamond bird (see the server's DiamondBird) smoothly on this
-- client from the times the server gives, beats its wings, and shows the
-- "click the bird" call and the double-gifts countdown on the display.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("DiamondRush")
local BirdBonus = require(Shared:WaitForChild("BirdBonus"))
local Format = require(Shared:WaitForChild("Format"))

local BirdView = {}

type Flyer = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	wings: { number }, -- 0 for the body, -1 / 1 for each wing
	frames: { CFrame },
}

local flyers: { [Model]: Flyer } = {}

local function track(model: Model)
	if flyers[model] or model.Name ~= "DiamondBird" or not model:IsA("Model") then return end
	local root = model.PrimaryPart or model:FindFirstChild("Hitbox")
	if root == nil or not root:IsA("BasePart") then return end
	-- Offsets come from the pose the server built it in, around its hitbox.
	local flyer: Flyer = { model = model, parts = {}, offsets = {}, wings = {}, frames = {} }
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(flyer.parts, part)
			table.insert(flyer.offsets, root.CFrame:ToObjectSpace(part.CFrame))
			local wing = part:GetAttribute("Wing")
			table.insert(flyer.wings, if type(wing) == "number" then wing else 0)
			table.insert(flyer.frames, part.CFrame)
		end
	end
	flyers[model] = flyer
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then flyers[model] = nil end
	end)
end

local function pathOf(model: Model): BirdBonus.Path
	return {
		radius = tonumber(model:GetAttribute("Radius")) or 40,
		height = tonumber(model:GetAttribute("Height")) or 40,
		angle = tonumber(model:GetAttribute("Angle")) or 0,
		direction = tonumber(model:GetAttribute("Direction")) or 1,
	}
end

local function fly(flyer: Flyer, now: number)
	local model = flyer.model
	local start = tonumber(model:GetAttribute("Start")) or now
	local leaveAt = tonumber(model:GetAttribute("LeaveAt")) or 0
	local leaving = if leaveAt > 0 then leaveAt - start else nil
	local path = pathOf(model)
	local t = now - start
	local x, y, z = BirdBonus.position(path, t, leaving)
	local ax, ay, az = BirdBonus.position(path, t + 0.1, leaving)
	local here, ahead = Vector3.new(x, y, z), Vector3.new(ax, ay, az)
	-- Banks into its turn as it circles the mountain.
	local frame = if (ahead - here).Magnitude > 1e-3 then CFrame.lookAt(here, ahead) else CFrame.new(here)
	frame *= CFrame.Angles(0, 0, path.direction * math.rad(14))
	local flap = BirdBonus.flap(t, leaving ~= nil)
	for index, part in flyer.parts do
		local side = flyer.wings[index]
		if side == 0 then
			flyer.frames[index] = frame * flyer.offsets[index]
		else
			local shoulder = CFrame.new(side * 1.0, 0.45, 0)
			flyer.frames[index] = frame * shoulder * CFrame.Angles(0, 0, side * flap) * shoulder:Inverse() * flyer.offsets[index]
		end
	end
	workspace:BulkMoveTo(flyer.parts, flyer.frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function BirdView.start(gui: ScreenGui, State: Instance)
	local call = Instance.new("TextLabel")
	call.Name = "DiamondBird"
	call.AnchorPoint = Vector2.new(0.5, 0)
	call.Position = UDim2.new(0.5, 0, 0, 194)
	call.Size = UDim2.fromOffset(0, 40)
	call.AutomaticSize = Enum.AutomaticSize.X
	call.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	call.BackgroundTransparency = 0.2
	call.Font = Enum.Font.GothamBold
	call.TextSize = 20
	call.TextColor3 = Color3.fromRGB(132, 212, 255)
	call.Text = ""
	call.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = call
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = call
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(132, 212, 255)
	stroke.Parent = call
	call.Parent = gui

	for _, child in workspace:GetChildren() do
		if child:IsA("Model") then track(child) end
	end
	workspace.ChildAdded:Connect(function(child)
		-- Parts can stream in just after the model itself.
		if child:IsA("Model") and child.Name == "DiamondBird" then
			task.defer(track, child)
		end
	end)

	local shown = ""
	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		local waiting = false
		for _, flyer in flyers do
			fly(flyer, now)
			if flyer.model:GetAttribute("LeaveAt") == 0 then waiting = true end
		end
		local boostUntil = tonumber(State:GetAttribute("BirdBoostUntil")) or 0
		local text = ""
		if now < boostUntil then
			text = string.format("2X GIFTS  ·  %s", Format.duration(boostUntil - now))
			call.TextColor3 = Color3.fromRGB(246, 200, 92)
			stroke.Color = Color3.fromRGB(246, 200, 92)
			call.TextTransparency = 0
		elseif waiting then
			text = "DIAMOND BIRD  ·  CLICK IT FOR 2X GIFTS"
			call.TextColor3 = Color3.fromRGB(132, 212, 255)
			stroke.Color = Color3.fromRGB(132, 212, 255)
			call.TextTransparency = 0.2 + 0.2 * math.sin(now * 6)
		end
		if text ~= shown then
			shown = text
			call.Text = text
			call.Visible = text ~= ""
		end
	end)
end

return BirdView
