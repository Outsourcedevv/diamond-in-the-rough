--!strict
-- A bounded stream of flying stones accompanies the server's layer reveal.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RebuildEffects = {}
local current: Folder? = nil
local connection: RBXScriptConnection? = nil
function RebuildEffects.play(data: any)
	if connection then connection:Disconnect(); connection = nil end
	if current then current:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "RebuildingStones"
	folder.Parent = workspace
	current = folder
	local tracks = {}
	for index, stone in data.stones do
		if index > 80 then break end
		local angle = index * 2.39996
		local destination = stone.frame.Position
		local start = destination + Vector3.new(math.cos(angle) * 10, -6, math.sin(angle) * 10)
		table.insert(tracks, { stone = stone, start = CFrame.new(start) * CFrame.Angles(angle, angle, 0), arrive = data.start + stone.layer * 0.15, part = nil, done = false })
	end
	connection = RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		local done = 0
		for _, track in tracks do
			local t = (now - (track.arrive - 0.55)) / 0.55
			if t >= 1 then
				if track.part then track.part:Destroy(); track.part = nil end
				track.done = true
				done += 1
			elseif t >= 0 and not track.done then
				if track.part == nil then
					local p = Instance.new("WedgePart")
					p.Size = track.stone.size * 1.8
					p.Color = track.stone.colour
					p.Material = Enum.Material.Slate
					p.Anchored = true
					p.CanCollide = false
					p.CanQuery = false
					p.CanTouch = false
					p.CastShadow = false
					p.Parent = folder
					track.part = p
				end
				local eased = 1 - (1 - t) ^ 3
				track.part.CFrame = track.start:Lerp(track.stone.frame, eased) + Vector3.new(0, math.sin(t * math.pi) * 2, 0)
				track.part.Size = track.stone.size * (1 + 0.8 * (1 - eased))
				track.part.Transparency = math.max(0, 1 - t * 8)
			end
		end
		if done == #tracks then
			if connection then connection:Disconnect(); connection = nil end
			-- A short finishing glint travels upward from the completed peak.
			local peak = Vector3.zero
			for _, track in tracks do
				if track.stone.frame.Position.Y > peak.Y then peak = track.stone.frame.Position end
			end
			for i = 1, 12 do
				local p = Instance.new("Part")
				p.Size = Vector3.new(0.08, 0.08, 0.45)
				p.Anchored = true
				p.CanQuery = false
				p.CanCollide = false
				p.CanTouch = false
				p.Material = Enum.Material.Neon
				p.Color = Color3.fromRGB(170, 240, 255)
				p.Position = peak
				p.Parent = folder
				local angle = i * math.pi / 6
				TweenService:Create(p, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = peak + Vector3.new(math.cos(angle) * 5, 3, math.sin(angle) * 5), Transparency = 1 }):Play()
			end
			Debris:AddItem(folder, 0.7)
		end
	end)
end
return RebuildEffects
