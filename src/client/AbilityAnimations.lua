--[[
	Plays an ability's upper-body animation on the local character. This is a
	purely visual layer: it starts when the server accepts an ability and stops
	when the effect ends, is interrupted, or the character is removed.

	Animation IDs and fade times come from Config.Abilities[id].Animation. The IDs
	are the default R15 ones this project's character already uses (read from its
	Animate script), so they are Roblox-provided, not third-party assets.

	The default Animate script keeps running. Our tracks use the Action priority, so
	they override the locomotion tracks while playing and fade back to them after.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AbilityAnimations = {}

local animationCache = {}
local playing = {} -- [abilityId] = track

local function animationFor(abilityId)
	local animation = animationCache[abilityId]
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = Config.Abilities[abilityId].Animation.Id
		animationCache[abilityId] = animation
	end
	return animation
end

-- Stops one ability's animation, blending out over its configured FadeOut time.
function AbilityAnimations.Stop(abilityId)
	local track = playing[abilityId]
	if track then
		playing[abilityId] = nil
		track:Stop(Config.Abilities[abilityId].Animation.FadeOut)
	end
end

-- Stops every ability animation. Used on death, respawn, or when the character is removed.
function AbilityAnimations.StopAll()
	for abilityId in pairs(playing) do
		AbilityAnimations.Stop(abilityId)
	end
end

-- Plays the animation for abilityId and stops it after `duration` seconds.
-- A new call for the same ability replaces the previous one.
function AbilityAnimations.Play(character, abilityId, duration)
	local definition = Config.Abilities[abilityId]
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (definition and animator) or humanoid.Health <= 0 then
		return
	end

	AbilityAnimations.Stop(abilityId)
	local track = animator:LoadAnimation(animationFor(abilityId))
	track.Priority = Enum.AnimationPriority.Action
	playing[abilityId] = track
	track:Play(definition.Animation.FadeIn)

	task.delay(duration, function()
		if playing[abilityId] == track then
			AbilityAnimations.Stop(abilityId)
		end
	end)
end

return AbilityAnimations
