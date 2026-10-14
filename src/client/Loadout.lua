--[[
	Client mirror of the server loadouts (see server/LoadoutService.lua), one slot list per
	wheel. The server is the only place that changes slots: the UI sends requests and
	displays the state it receives.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Loadout = {}
Loadout.__index = Loadout

local function emptySlots()
	local slots = {}
	for index = 1, Config.Loadout.SlotCount do
		slots[index] = false
	end
	return slots
end

function Loadout.new()
	local self = setmetatable({}, Loadout)
	self._wheels = {}
	for _, key in ipairs(Config.Loadout.Wheels) do
		self._wheels[key] = emptySlots()
	end
	return self
end

-- Replaces the mirror with the server's state, wheel by wheel.
function Loadout:Apply(wheels)
	for _, key in ipairs(Config.Loadout.Wheels) do
		local source = wheels[key] or {}
		local slots = self._wheels[key]
		for index = 1, Config.Loadout.SlotCount do
			local id = source[index]
			slots[index] = (typeof(id) == "string" and Config.Abilities[id]) and id or false
		end
	end
end

-- Returns a copy of one wheel's slots.
function Loadout:Get(wheelKey)
	return table.clone(self._wheels[wheelKey])
end

-- The wheel and slot an ability is in, across both wheels. Returns nil if it is not equipped.
function Loadout:Locate(abilityId)
	for _, key in ipairs(Config.Loadout.Wheels) do
		for index, id in ipairs(self._wheels[key]) do
			if id == abilityId then
				return key, index
			end
		end
	end
	return nil
end

-- The first equipped ability: wheels in config order, slots in ascending order.
function Loadout:FirstEquipped()
	for _, key in ipairs(Config.Loadout.Wheels) do
		for _, id in ipairs(self._wheels[key]) do
			if id then
				return id
			end
		end
	end
	return nil
end

-- Every ability the player can equip, in the order the config lists them.
function Loadout.Catalog()
	local catalog = {}
	for _, id in ipairs(Config.AbilityOrder) do
		table.insert(catalog, id)
	end
	for id in pairs(Config.Abilities) do
		if not table.find(catalog, id) then
			table.insert(catalog, id)
		end
	end
	return catalog
end

return Loadout
