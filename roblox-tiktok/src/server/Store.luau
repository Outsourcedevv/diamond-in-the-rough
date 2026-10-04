--!strict
-- Saves the win counter, its look, the best round time and the starting stone.
-- DataStores need the game to be published (and, in Studio, "Enable Studio
-- Access to API Services"). Without them everything still works; it just is
-- not remembered between sessions.
local DataStoreService = game:GetService("DataStoreService")

local Store = {}

local KEY = "settings"
local store: DataStore? = nil
local pending: { [string]: any }? = nil
local saving = false

local function open(): DataStore?
	if store == nil then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "DiamondRushTikTok_v1")
		if ok then
			store = result
		end
	end
	return store
end

function Store.load(): { [string]: any }?
	local target = open()
	if target == nil then
		return nil
	end
	local ok, data = pcall(target.GetAsync, target, KEY)
	if ok and type(data) == "table" then
		return data
	end
	if not ok then
		warn("[DiamondRush] Settings are not saved between sessions: " .. tostring(data))
	end
	return nil
end

-- Saves a few seconds after the last change, so quick edits make one write.
function Store.save(data: { [string]: any })
	pending = table.clone(data)
	if saving then
		return
	end
	saving = true
	task.delay(4, function()
		local target = open()
		local snapshot = pending
		pending = nil
		saving = false
		if target ~= nil and snapshot ~= nil then
			local ok, problem = pcall(target.SetAsync, target, KEY, snapshot)
			if not ok then
				warn("[DiamondRush] Could not save settings: " .. tostring(problem))
			end
		end
	end)
end

-- Writes immediately (used when the server shuts down).
function Store.flush(data: { [string]: any })
	pending = nil
	local target = open()
	if target ~= nil then
		pcall(target.SetAsync, target, KEY, data)
	end
end

return Store
