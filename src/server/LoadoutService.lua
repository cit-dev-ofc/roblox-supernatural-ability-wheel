--[[
	Server-side loadouts: two wheels ("Q" and "R") per player, each with numbered slots.
	Loadouts are saved to a DataStore keyed by player, so they come back on rejoin and
	after respawn (a respawn never touches this data).

	Rules, all enforced here:
	- Slots have fixed numbers. Empty slots keep their position; other slots never move.
	- An ability can be in at most one slot across both wheels.
	- "equip" puts the ability in the slot the player chose, if one is sent (it must be empty).
	  Without a chosen slot it goes to the first empty slot in ascending order. A full wheel
	  replies "full" and replaces nothing.
	- "toggle" removes the ability if it is in this wheel; otherwise it equips it here.
	- "unequip" empties the slot with that number.
	- AbilityService only runs abilities that are equipped in one of the two wheels.

	Saving: changes are saved right after they happen, and again when the player
	leaves or the server shuts down. If loading fails, the player keeps defaults for the
	session and nothing is saved, so a failed load can never overwrite stored data.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LoadoutService = {}

local SLOT_COUNT = Config.Loadout.SlotCount
local MIN_REQUEST_INTERVAL = 0.1 -- seconds between loadout requests per player
local DATA_VERSION = 1
local store = DataStoreService:GetDataStore("SupernaturalLoadouts")

-- [Player] = { wheels = {...}, lastRequest = number, canSave = bool, savedKey = string? }
local loadouts = {}

local function isWheel(key)
	for _, name in ipairs(Config.Loadout.Wheels) do
		if name == key then
			return true
		end
	end
	return false
end

local function emptySlots()
	local slots = {}
	for index = 1, SLOT_COUNT do
		slots[index] = false
	end
	return slots
end

-- The first wheel gets the config defaults; the others start empty.
local function defaultWheels()
	local wheels = {}
	for position, key in ipairs(Config.Loadout.Wheels) do
		local slots = emptySlots()
		if position == 1 then
			for index = 1, SLOT_COUNT do
				slots[index] = Config.AbilityOrder[index] or false
			end
		end
		wheels[key] = slots
	end
	return wheels
end

local function indexOf(slots, abilityId)
	for index, id in ipairs(slots) do
		if id == abilityId then
			return index
		end
	end
	return nil
end

-- Which wheel and slot an ability sits in, across all wheels. Returns nil if it is not equipped.
local function locate(wheels, abilityId)
	for _, key in ipairs(Config.Loadout.Wheels) do
		local index = indexOf(wheels[key], abilityId)
		if index then
			return key, index
		end
	end
	return nil
end

local function firstEmpty(slots)
	for index, id in ipairs(slots) do
		if not id then
			return index
		end
	end
	return nil
end

-- A stable text form of the wheels, used to tell whether anything changed since the last save.
local function serialize(wheels)
	local parts = {}
	for _, key in ipairs(Config.Loadout.Wheels) do
		local slots = {}
		for index = 1, SLOT_COUNT do
			slots[index] = wheels[key][index] or "-"
		end
		table.insert(parts, key .. "=" .. table.concat(slots, ","))
	end
	return table.concat(parts, ";")
end

-- Checks loaded data before using it: right shape, known abilities, no duplicates.
-- Anything invalid becomes an empty slot instead of breaking the loadout.
local function sanitize(data)
	local wheels = {}
	local used = {}
	local source = type(data) == "table" and data.version == DATA_VERSION and data.wheels or {}
	for _, key in ipairs(Config.Loadout.Wheels) do
		local slots = emptySlots()
		local stored = type(source) == "table" and source[key] or {}
		for index = 1, SLOT_COUNT do
			local id = type(stored) == "table" and stored[index]
			if typeof(id) == "string" and Config.Abilities[id] and not used[id] then
				slots[index] = id
				used[id] = true
			end
		end
		wheels[key] = slots
	end
	return wheels
end

-- Sends every wheel to one player. `reason` explains a refused request.
local function send(player, reason)
	local state = loadouts[player]
	if state then
		local copy = {}
		for key, slots in pairs(state.wheels) do
			copy[key] = table.clone(slots)
		end
		Remotes.LoadoutState:FireClient(player, copy, reason)
	end
end

-- Writes the player's loadout if it changed since the last write. Never writes when the load failed.
local function save(player)
	local state = loadouts[player]
	if not state or not state.canSave then
		return
	end
	local key = serialize(state.wheels)
	if key == state.savedKey then
		return
	end
	local payload = { version = DATA_VERSION, wheels = state.wheels }
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, payload)
	end)
	if ok then
		state.savedKey = key
	else
		warn("[Loadout] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Saves right after each change. A delayed save could be lost if the session stops first
-- (for example, stopping a playtest in Studio), so the write happens immediately instead.
local function scheduleSave(player)
	task.spawn(save, player)
end

-- Puts abilityId in `wheelKey`. `chosen` is an optional slot number.
local function equipInto(state, player, wheelKey, abilityId, chosen)
	local slots = state.wheels[wheelKey]
	local whereKey = locate(state.wheels, abilityId)
	if whereKey == wheelKey then
		return send(player, "already_equipped")
	elseif whereKey then
		return send(player, "in_other_wheel")
	end

	if chosen ~= nil then
		if typeof(chosen) ~= "number" or chosen % 1 ~= 0 or chosen < 1 or chosen > SLOT_COUNT then
			return send(player, "invalid_slot")
		elseif slots[chosen] then
			return send(player, "slot_taken")
		end
		slots[chosen] = abilityId
		scheduleSave(player)
		return send(player)
	end

	local slot = firstEmpty(slots)
	if not slot then
		return send(player, "full")
	end
	slots[slot] = abilityId
	scheduleSave(player)
	send(player)
end

local function handleRequest(player, action, wheelKey, value, extra)
	local state = loadouts[player]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.lastRequest < MIN_REQUEST_INTERVAL then
		return
	end
	state.lastRequest = now

	if action == "sync" then
		return send(player)
	end

	if not isWheel(wheelKey) then
		return send(player, "invalid_request")
	end

	if action == "toggle" then
		if typeof(value) ~= "string" or not Config.Abilities[value] then
			return send(player, "unknown_ability")
		end
		local index = indexOf(state.wheels[wheelKey], value)
		if index then
			state.wheels[wheelKey][index] = false
			scheduleSave(player)
			return send(player)
		end
		return equipInto(state, player, wheelKey, value, extra)
	elseif action == "equip" then
		if typeof(value) ~= "string" or not Config.Abilities[value] then
			return send(player, "unknown_ability")
		end
		return equipInto(state, player, wheelKey, value, extra)
	elseif action == "unequip" then
		local slots = state.wheels[wheelKey]
		if typeof(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > SLOT_COUNT then
			return send(player, "invalid_slot")
		end
		slots[value] = false
		scheduleSave(player)
		return send(player)
	end

	send(player, "invalid_request")
end

-- True if the player has this ability equipped in either wheel. AbilityService uses it to gate casts.
function LoadoutService.IsEquipped(player, abilityId)
	local state = loadouts[player]
	return state ~= nil and locate(state.wheels, abilityId) ~= nil
end

-- Loads the saved loadout, then tells the client. Runs in its own thread, so joining never waits on it.
local function loadPlayer(player, state)
	local ok, data = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if not loadouts[player] then
		return -- the player left while loading
	end
	if ok then
		state.wheels = sanitize(data)
		state.canSave = true
		state.savedKey = serialize(state.wheels)
	else
		warn("[Loadout] load failed for " .. player.Name .. ", using defaults this session: " .. tostring(data))
		state.canSave = false
	end
	send(player)
end

local function onPlayerAdded(player)
	local state = { wheels = defaultWheels(), lastRequest = 0, canSave = false }
	loadouts[player] = state
	task.spawn(loadPlayer, player, state)
end

function LoadoutService.Start()
	Remotes.Loadout.OnServerEvent:Connect(handleRequest)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loadouts[player] = nil
	end)

	game:BindToClose(function()
		for player in pairs(loadouts) do
			save(player)
		end
	end)
end

return LoadoutService
