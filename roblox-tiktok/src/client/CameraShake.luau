--!strict
-- Camera shake that never builds up. Roblox's camera works out each frame's
-- view from the last frame's camera.CFrame, so a shake added on top would
-- leak into where the player looks. `apply` shakes this frame's view, and
-- just before the camera's next update the view is put back as it was.
local RunService = game:GetService("RunService")

local CameraShake = {}

local before: CFrame? = nil
local shaken: CFrame? = nil
local bound = false

-- Turns this frame's view by `offset` (call it after the camera has moved).
function CameraShake.apply(camera: Camera, offset: CFrame)
	if not bound then
		bound = true
		RunService:BindToRenderStep("CameraShakeUndo", Enum.RenderPriority.Camera.Value - 1, function()
			local current = workspace.CurrentCamera
			if shaken == nil then
				-- Nothing shook last frame: done until the next shake.
				bound = false
				RunService:UnbindFromRenderStep("CameraShakeUndo")
				return
			end
			if current and before and current.CFrame == shaken then current.CFrame = before end
			before, shaken = nil, nil
		end)
	end
	-- Two shakes in one frame stack on the same unshaken view.
	if shaken == nil or camera.CFrame ~= shaken then before = camera.CFrame end
	camera.CFrame = camera.CFrame * offset
	shaken = camera.CFrame
end

return CameraShake
