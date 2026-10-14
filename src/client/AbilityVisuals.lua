--[[
	Cosmetic ability effects, created locally on each client. The server only sends
	a notice (Remotes.Visual) saying which ability started on which character, so
	the afterimages and particles are never replicated as server instances.

	Gameplay is unaffected: nothing here changes character state, and the server
	does not depend on any of it.
]]
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local visuals = Config.Visuals

local AbilityVisuals = {}

local AFTERIMAGE_INTERVAL = 0.05 -- seconds between afterimages
local AFTERIMAGE_FADE = 0.4 -- seconds for an afterimage to fade out
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"

-- Character.Clone() returns nil on a replicated character, because Archivable is false there.
-- Each BasePart can still be cloned, so the afterimage is built from copies of the parts.
local function spawnAfterimage(character)
	local ghost = Instance.new("Model")
	ghost.Name = "VampiricAfterimage"
	local parts = {}

	for _, original in ipairs(character:GetDescendants()) do
		if original:IsA("BasePart") then
			local copy = original:Clone()
			if copy then
				-- Drop welds, constraints, scripts and emitters: the copy is only for looks.
				for _, child in ipairs(copy:GetChildren()) do
					if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("Script")
						or child:IsA("LocalScript") or child:IsA("ParticleEmitter") then
						child:Destroy()
					elseif child:IsA("Decal") or child:IsA("Texture") then
						child.Transparency = 0.7
					end
				end
				copy.Anchored = true
				copy.CanCollide = false
				copy.CanQuery = false
				copy.CanTouch = false
				copy.Material = Enum.Material.ForceField
				copy.Color = visuals.Purple
				copy.Transparency = 0.45
				copy.Parent = ghost
				table.insert(parts, copy)
			end
		end
	end

	if #parts == 0 then
		ghost:Destroy()
		return
	end

	ghost.Parent = workspace

	local info = TweenInfo.new(AFTERIMAGE_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ipairs(parts) do
		TweenService:Create(part, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(ghost, AFTERIMAGE_FADE)
end

local function makeEmitter(parent, props)
	local emitter = Instance.new("ParticleEmitter")
	for key, value in pairs(props) do
		emitter[key] = value
	end
	emitter.Parent = parent
	return emitter
end

local function playDash(character, duration)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local anchor = Instance.new("Attachment")
	anchor.Name = "VampiricVisualAnchor"
	anchor.Parent = root

	local burst = makeEmitter(anchor, {
		Texture = FIRE_TEXTURE,
		Color = ColorSequence.new(visuals.Purple, visuals.MutedRed),
		LightEmission = 0.7,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.6, 0),
		Transparency = NumberSequence.new(0.2, 1),
		Rate = 0,
	})
	burst:Emit(18)

	local wisp = makeEmitter(anchor, {
		Texture = FIRE_TEXTURE,
		Color = ColorSequence.new(visuals.Purple, visuals.DarkPurple),
		LightEmission = 0.8,
		LightInfluence = 0,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(0, 2),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rate = 0,
	})

	-- Afterimages and wisps for the length of the dash. Stops early if the character goes away.
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local elapsed = 0
		while elapsed < duration and character.Parent and humanoid and humanoid.Health > 0 do
			spawnAfterimage(character)
			wisp:Emit(8)
			task.wait(AFTERIMAGE_INTERVAL)
			elapsed += AFTERIMAGE_INTERVAL
		end
		wisp.Enabled = false
		task.delay(1, function()
			anchor:Destroy()
		end)
	end)
end

local handlers = {
	VampiricSpeed = playDash,
}

-- Called for every server Visual notice. Unknown abilities are ignored.
function AbilityVisuals.Play(abilityId, character)
	local definition = Config.Abilities[abilityId]
	local handler = handlers[abilityId]
	if handler and definition and typeof(character) == "Instance" and character:IsA("Model") then
		handler(character, definition.EffectDuration)
	end
end

return AbilityVisuals
