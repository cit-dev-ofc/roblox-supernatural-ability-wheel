--[[
	Server-side ability gatekeeper. Validates every request, enforces
	cooldowns with server timestamps, and tracks one active ability per player.
	Ability modules implement Validate(ctx, request) and Run(ctx, data, finish).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LoadoutService = require(script.Parent.LoadoutService)

local Abilities = {
	VampiricSpeed = require(script.Parent.Abilities.VampiricSpeed),
	TelekineticChoke = require(script.Parent.Abilities.TelekineticChoke),
}

local AbilityService = {}

-- [Player] = { cooldowns = {[id] = expiresAt}, lastRequest = 0, active = token?, connections = {} }
local states = {}

local function respond(player, abilityId, ok, reason, remaining)
	Remotes.Response:FireClient(player, abilityId, ok, reason, remaining)
end

local function cancelActive(state)
	local active = state.active
	if not active then
		return
	end
	state.active = nil
	if active.cancel then
		active.cancel()
	end
end

local function handleRequest(player, abilityId, target, direction)
	local state = states[player]
	if not state then
		return
	end

	-- Type checks on untrusted input.
	if typeof(abilityId) ~= "string" or not Config.Abilities[abilityId] or not Abilities[abilityId] then
		respond(player, tostring(abilityId), false, "unknown_ability")
		return
	end

	local now = os.clock()
	if now - state.lastRequest < Config.Server.MinRequestInterval then
		respond(player, abilityId, false, "too_fast")
		return
	end
	state.lastRequest = now

	-- Only abilities in the player's loadout can run.
	if not LoadoutService.IsEquipped(player, abilityId) then
		respond(player, abilityId, false, "not_equipped")
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) or humanoid.Health <= 0 then
		respond(player, abilityId, false, "dead")
		return
	end
	if state.active then
		respond(player, abilityId, false, "busy")
		return
	end
	if character:GetAttribute(Config.StatusAttribute) then
		respond(player, abilityId, false, "immobilized")
		return
	end

	local remaining = (state.cooldowns[abilityId] or 0) - now
	if remaining > 0 then
		respond(player, abilityId, false, "cooldown", remaining)
		return
	end

	local ctx = { player = player, character = character, humanoid = humanoid, root = root }
	local module = Abilities[abilityId]
	local ok, reason, data = module.Validate(ctx, { target = target, direction = direction })
	if not ok then
		respond(player, abilityId, false, reason)
		return
	end

	-- Commit: cooldown starts only once the ability is actually accepted.
	state.cooldowns[abilityId] = now + Config.Abilities[abilityId].Cooldown
	local token = { abilityId = abilityId }
	state.active = token

	local function finish()
		if state.active == token then
			state.active = nil
		end
	end

	token.cancel = module.Run(ctx, data, finish)
	respond(player, abilityId, true, nil, Config.Abilities[abilityId].Cooldown)
	print(string.format("[Abilities] %s cast %s", player.Name, abilityId))
end

local function watchCharacter(player, state, character)
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	table.clear(state.connections)

	cancelActive(state)
	if not character then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	table.insert(state.connections, humanoid.Died:Connect(function()
		cancelActive(state)
	end))
	table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cancelActive(state)
		end
	end))
end

local function onPlayerAdded(player)
	local state = { cooldowns = {}, lastRequest = 0, active = nil, connections = {} }
	states[player] = state

	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, state, character)
	end)
	player.CharacterRemoving:Connect(function()
		cancelActive(state)
	end)
	if player.Character then
		watchCharacter(player, state, player.Character)
	end
end

function AbilityService.Start()
	Remotes.Request.OnServerEvent:Connect(handleRequest)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			cancelActive(state)
			for _, connection in ipairs(state.connections) do
				connection:Disconnect()
			end
		end
		states[player] = nil
	end)
end

return AbilityService
