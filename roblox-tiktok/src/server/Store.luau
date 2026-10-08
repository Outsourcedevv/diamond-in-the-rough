--!strict
-- Saves the win counter, its look, the best round time and the starting stone,
-- the statues, leaderboards, theme, skin and keybinds. In single player each
-- player has their own save (useKey); otherwise the game shares one.
-- DataStores need the game to be published (and, in Studio, "Enable Studio
-- Access to API Services"). Without them everything still works; it just is
-- not remembered between sessions.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Store = {}

Store.SHARED_KEY = "settings"
local KEY = Store.SHARED_KEY
local store: DataStore? = nil
local pending: { [string]: any }? = nil
local saving = false
-- True when the save could not be read: saving then stays off, so a passing
-- DataStore problem never replaces the real save with the defaults.
local blocked = false

local function open(): DataStore?
	if store == nil then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "DiamondRushTikTok_v1")
		if ok then
			store = result
		end
	end
	return store
end

-- Where saves go from now on, e.g. "player_123" for one player's own save.
function Store.useKey(key: string)
	KEY = key
end

-- The save under `key` (the current one by default), and whether it could be
-- read: nil and true means there is no save there yet.
function Store.load(key: string?): ({ [string]: any }?, boolean)
	local target = open()
	if target == nil then
		return nil, false
	end
	local ok, data = pcall(target.GetAsync, target, key or KEY)
	-- A passing DataStore hiccup gets two more tries; Studio without API
	-- access fails the same way every time, so it doesn't wait for nothing.
	for _ = 1, if RunService:IsStudio() then 0 else 2 do
		if ok then break end
		task.wait(2)
		ok, data = pcall(target.GetAsync, target, key or KEY)
	end
	if ok and type(data) == "table" then
		return data, true
	end
	if not ok then
		warn("[DiamondRush] Could not read the save, so nothing is saved this session (your old save is kept): " .. tostring(data))
		if key == nil or key == KEY then blocked = true end
	end
	return nil, ok
end

-- Seconds between writes. Roblox allows one write to the same save about
-- every 6 seconds; writing faster (a busy stream) fills its queue until saves
-- fail.
Store.WRITE_EVERY = 6

-- Saves a few seconds after the last change, so quick edits make one write,
-- and one write at a time: changes made while writing go in the next one.
function Store.save(data: { [string]: any })
	if blocked then return end
	pending = table.clone(data)
	if saving then
		return
	end
	saving = true
	task.delay(Store.WRITE_EVERY, function()
		local target = open()
		local snapshot = pending
		pending = nil
		if target ~= nil and snapshot ~= nil then
			local ok, problem = pcall(target.SetAsync, target, KEY, snapshot)
			if not ok then
				warn("[DiamondRush] Could not save settings: " .. tostring(problem))
			end
		end
		saving = false
		local later = pending
		if later ~= nil then Store.save(later) end
	end)
end

-- Writes immediately (used when the server shuts down).
function Store.flush(data: { [string]: any })
	pending = nil
	if blocked then return end
	local target = open()
	if target ~= nil then
		pcall(target.SetAsync, target, KEY, data)
	end
end

return Store
