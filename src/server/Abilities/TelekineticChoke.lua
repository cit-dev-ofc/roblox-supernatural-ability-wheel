--[[
	Telekinetic Choke: validates a single target on the server, lifts it with
	an AlignPosition, immobilizes it by changing humanoid values, and applies
	damage in ticks. Original values are stored and restored exactly once.
	Visuals: a ring of purple flame around the target, a beam from the caster,
	and a burst of smoke at the start.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local definition = Config.Abilities.TelekineticChoke
local settings = definition.Choke
local visuals = Config.Visuals
local STATUS = Config.StatusAttribute

-- Textures that ship with Roblox, so no external assets are needed.
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local RING_POINTS = 10 -- flame emitters around the target
local RING_RADIUS = 2.4 -- studs from the target's root
local RING_HEIGHT = -2.6 -- studs relative to the root (near the feet)

local TelekineticChoke = {}

local FACING_COS = math.cos(math.rad(settings.FacingHalfAngle))

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

function TelekineticChoke.Validate(ctx, request)
	local target = request.target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return false, "no_target"
	end
	if target == ctx.character or not target:IsDescendantOf(workspace) then
		return false, "invalid_target"
	end

	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not (humanoid and targetRoot and targetRoot:IsA("BasePart")) then
		return false, "invalid_target"
	end
	if humanoid.Health <= 0 then
		return false, "invalid_target"
	end
	if target:GetAttribute(STATUS) then
		return false, "target_busy"
	end

	local casterPosition = ctx.root.Position
	local offset = targetRoot.Position - casterPosition
	if offset.Magnitude > settings.Range then
		return false, "out_of_range"
	end

	local toTarget = flat(offset)
	local look = flat(ctx.root.CFrame.LookVector)
	if toTarget.Magnitude > 0.5 and look.Magnitude > 0.1 then
		if look.Unit:Dot(toTarget.Unit) < FACING_COS then
			return false, "not_in_front"
		end
	end

	-- Line of sight: the first thing hit must belong to the target.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.character }
	local origin = ctx.root.Position
	local result = workspace:Raycast(origin, targetRoot.Position - origin, params)
	if result and not result.Instance:IsDescendantOf(target) then
		return false, "no_line_of_sight"
	end

	return true, nil, { target = target, targetHumanoid = humanoid, targetRoot = targetRoot }
end

-- Flame ring around the target. Each emitter sits on an attachment welded to the root,
-- so the ring moves with the target while it is lifted.
local function addFlameRing(targetRoot, instances)
	for i = 1, RING_POINTS do
		local angle = (i - 1) / RING_POINTS * math.pi * 2
		local attachment = Instance.new("Attachment")
		attachment.Name = "ChokeRingPoint"
		attachment.Position = Vector3.new(math.cos(angle) * RING_RADIUS, RING_HEIGHT, math.sin(angle) * RING_RADIUS)
		attachment.Parent = targetRoot
		table.insert(instances, attachment)

		local flame = Instance.new("ParticleEmitter")
		flame.Texture = FIRE_TEXTURE
		flame.Color = ColorSequence.new(visuals.Purple, visuals.DarkPurple)
		flame.LightEmission = 0.8
		flame.LightInfluence = 0
		flame.Lifetime = NumberRange.new(0.5, 0.9)
		flame.Rate = 45
		flame.Speed = NumberRange.new(2, 4)
		flame.SpreadAngle = Vector2.new(12, 12)
		flame.Acceleration = Vector3.new(0, 4, 0)
		flame.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(0.6, 2.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		flame.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		flame.Parent = attachment
		table.insert(instances, flame)
	end

	-- Dark smoke rising from the ring.
	local smokeAnchor = Instance.new("Attachment")
	smokeAnchor.Name = "ChokeSmokeAnchor"
	smokeAnchor.Position = Vector3.new(0, RING_HEIGHT, 0)
	smokeAnchor.Parent = targetRoot
	table.insert(instances, smokeAnchor)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(visuals.DarkPurple)
	smoke.Lifetime = NumberRange.new(1.2, 1.8)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(1, 2)
	smoke.SpreadAngle = Vector2.new(30, 30)
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = smokeAnchor
	table.insert(instances, smoke)
end

function TelekineticChoke.Run(ctx, data, finish)
	local casterCharacter, casterRoot, casterHumanoid = ctx.character, ctx.root, ctx.humanoid
	local target, targetHumanoid, targetRoot = data.target, data.targetHumanoid, data.targetRoot
	local finished = false
	local instances = {}
	local connections = {}

	-- Store original humanoid values so they can be restored exactly.
	local original = {
		WalkSpeed = targetHumanoid.WalkSpeed,
		JumpPower = targetHumanoid.JumpPower,
		JumpHeight = targetHumanoid.JumpHeight,
		AutoRotate = targetHumanoid.AutoRotate,
	}

	local function restore()
		if targetHumanoid.Parent then
			targetHumanoid.WalkSpeed = original.WalkSpeed
			targetHumanoid.JumpPower = original.JumpPower
			targetHumanoid.JumpHeight = original.JumpHeight
			targetHumanoid.AutoRotate = original.AutoRotate
		end
		if target.Parent then
			target:SetAttribute(STATUS, nil)
		end
	end

	local function cleanup()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		restore()
		for _, instance in ipairs(instances) do
			instance:Destroy()
		end
		table.clear(instances)
	end

	-- Single exit point: runs cleanup and releases the caster once.
	local function end_()
		if finished then
			return
		end
		finished = true
		cleanup()
		finish()
	end

	-- Immobilize: no walking, jumping, or turning while held.
	target:SetAttribute(STATUS, true)
	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.JumpHeight = 0
	targetHumanoid.AutoRotate = false

	-- Lift: a server-created AlignPosition on the target's own root. Ownership is untouched.
	local targetAnchor = Instance.new("Attachment")
	targetAnchor.Name = "ChokeTargetAnchor"
	targetAnchor.Parent = targetRoot
	table.insert(instances, targetAnchor)

	local hold = Instance.new("AlignPosition")
	hold.Name = "ChokeLift"
	hold.Mode = Enum.PositionAlignmentMode.OneAttachment
	hold.Attachment0 = targetAnchor
	hold.Position = targetRoot.Position + Vector3.new(0, settings.LiftHeight, 0)
	hold.RigidityEnabled = false
	hold.MaxForce = settings.HoldForce
	hold.Responsiveness = 30
	hold.Parent = targetRoot
	table.insert(instances, hold)

	-- Beam from the caster to the target.
	local casterAnchor = Instance.new("Attachment")
	casterAnchor.Name = "ChokeCasterAnchor"
	casterAnchor.Parent = casterRoot
	table.insert(instances, casterAnchor)

	local beam = Instance.new("Beam")
	beam.Name = "ChokeBeam"
	beam.Attachment0 = casterAnchor
	beam.Attachment1 = targetAnchor
	beam.Texture = FIRE_TEXTURE
	beam.TextureSpeed = 2
	beam.TextureLength = 4
	beam.LightEmission = 0.8
	beam.Color = ColorSequence.new(visuals.Purple, visuals.DarkPurple)
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.Transparency = NumberSequence.new(0.2)
	beam.FaceCamera = true
	beam.Parent = casterRoot
	table.insert(instances, beam)

	-- Outline on the target so it reads clearly.
	local highlight = Instance.new("Highlight")
	highlight.Name = "ChokeHighlight"
	highlight.FillColor = visuals.DarkPurple
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = visuals.Purple
	highlight.OutlineTransparency = 0.2
	highlight.Parent = target
	table.insert(instances, highlight)

	addFlameRing(targetRoot, instances)

	-- Burst on the caster when the choke starts.
	local burstAnchor = Instance.new("Attachment")
	burstAnchor.Name = "ChokeBurstAnchor"
	burstAnchor.Parent = casterRoot
	table.insert(instances, burstAnchor)

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = SPARKLE_TEXTURE
	burst.Color = ColorSequence.new(visuals.Purple)
	burst.LightEmission = 0.9
	burst.Lifetime = NumberRange.new(0.4, 0.7)
	burst.Speed = NumberRange.new(4, 8)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new(0.8, 0)
	burst.Rate = 0
	burst.Parent = burstAnchor
	burst:Emit(24)
	task.delay(1, function()
		burst:Destroy()
	end)

	-- Interruptions: target or caster death, or either character leaving the workspace.
	table.insert(connections, targetHumanoid.Died:Connect(end_))
	table.insert(connections, casterHumanoid.Died:Connect(end_))
	table.insert(connections, target.AncestryChanged:Connect(function(_, parent)
		if not parent then
			end_()
		end
	end))
	table.insert(connections, casterCharacter.AncestryChanged:Connect(function(_, parent)
		if not parent then
			end_()
		end
	end))

	-- Damage ticks drive the effect timing. The loop ends the effect after the last tick.
	local tickInterval = definition.EffectDuration / settings.DamageTicks
	local tickDamage = settings.Damage / settings.DamageTicks
	task.spawn(function()
		for _ = 1, settings.DamageTicks do
			task.wait(tickInterval)
			if finished then
				return
			end
			if targetHumanoid.Health > 0 then
				targetHumanoid:TakeDamage(tickDamage)
			end
		end
		end_()
	end)

	return function()
		if finished then
			return
		end
		finished = true
		cleanup()
	end
end

return TelekineticChoke
