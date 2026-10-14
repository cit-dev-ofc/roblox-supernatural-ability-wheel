--[[
	Vampiric Speed: a short horizontal dash driven by a server-owned
	LinearVelocity. Collisions still apply, so the dash stops at walls.
	The afterimages and flame wisps are cosmetic and run on each client, which
	is told to start them with one event instead of replicating server instances.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local definition = Config.Abilities.VampiricSpeed
local settings = definition.Dash

local VampiricSpeed = {}

local FALLBACK_DIRECTION = Vector3.new(0, 0, -1)

local function sanitizeDirection(root, direction)
	if typeof(direction) == "Vector3" and direction.X == direction.X and direction.Z == direction.Z then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 0.1 and flat.Magnitude < 1e6 then
			return flat.Unit
		end
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.1 then
		return flatLook.Unit
	end
	return FALLBACK_DIRECTION
end

function VampiricSpeed.Validate(ctx, request)
	return true, nil, { direction = sanitizeDirection(ctx.root, request.direction) }
end

function VampiricSpeed.Run(ctx, data, finish)
	local root, humanoid, character = ctx.root, ctx.humanoid, ctx.character
	local finished = false
	local instances = {}
	local connections = {}

	local function cleanup()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, instance in ipairs(instances) do
			instance:Destroy()
		end
		table.clear(instances)
	end

	local function end_()
		if finished then
			return
		end
		finished = true
		cleanup()
		finish()
	end

	-- Movement: server-created LinearVelocity, horizontal only so gravity still applies.
	local attachment = Instance.new("Attachment")
	attachment.Name = "VampiricDashAttachment"
	attachment.Parent = root
	table.insert(instances, attachment)

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "VampiricDashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = data.direction * settings.Speed
	velocity.ForceLimitsEnabled = true
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(settings.MaxForce, 0, settings.MaxForce)
	velocity.Parent = root
	table.insert(instances, velocity)

	-- One small event tells every client to play the cosmetic dash on this character.
	Remotes.Visual:FireAllClients(definition.Id, character)

	table.insert(connections, humanoid.Died:Connect(end_))
	table.insert(connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			end_()
		end
	end))

	task.delay(definition.EffectDuration, end_)

	-- Cancel handler for AbilityService (death, respawn, or player leaving).
	return function()
		if finished then
			return
		end
		finished = true
		cleanup()
	end
end

return VampiricSpeed
