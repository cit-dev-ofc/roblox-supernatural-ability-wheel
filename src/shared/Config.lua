--[[
	Shared configuration. Single source of truth for ability definitions,
	cooldowns, ranges and input bindings. The server is authoritative; the
	client reads this only for display and input.
]]
local Config = {}

Config.Remotes = {
	FolderName = "SupernaturalRemotes",
	Request = "AbilityRequest", -- client -> server: (abilityId, target?, direction?)
	Response = "AbilityResponse", -- server -> client: (abilityId, ok, reason?, cooldownRemaining?)
	Visual = "AbilityVisual", -- server -> all clients: (abilityId, character); purely cosmetic
	Loadout = "LoadoutRequest", -- client -> server: ("toggle", abilityId, slot?) or ("equip", abilityId, slot?) or ("unequip", slotIndex) or ("sync")
	LoadoutState = "LoadoutState", -- server -> client: (slots, reason?)
}

Config.Input = {
	WheelKey = Enum.KeyCode.Q, -- hold to open the ability wheel
	SpellsKey = Enum.KeyCode.R, -- opens the Spells editor wheel
	CancelKey = Enum.KeyCode.Escape,
}

-- Default loadout: these abilities start equipped in the first slots. The player can change it
-- in the Feitiços editor. The server saves each player's loadout to a DataStore (see server/LoadoutService.lua).
Config.AbilityOrder = { "VampiricSpeed", "TelekineticChoke" }

-- Number of slots on the wheel. Slots are filled in order from the top, clockwise.
Config.Loadout = {
	SlotCount = 8,
	-- Two wheels with the same catalog. An ability can sit in only one of them at a time.
	Wheels = { "Q", "R" },
}

--[[
	Everything about an ability lives here, in one entry:
	- Display: DisplayName, Description, Icon (drawn by client/Icons.lua), Symbol (fallback text).
	- Timing: Cooldown (server-enforced) and EffectDuration (how long the effect lasts).
	  The server ends the effect after EffectDuration; the client uses the same value to end
	  the animation and visuals.
	- Animation: the default R15 animation played locally (client/AbilityAnimations.lua).
	- Gameplay settings: a sub-table read only by the server module.
	Adding an ability means adding an entry here, a module in server/Abilities, and registering it in AbilityService.
]]
-- Ability categories. Each ability sets Category to one of these keys. The color marks the
-- group in the Feitiços panel and on the wheel.
Config.CategoryOrder = { "Vampire", "Witch" }
Config.Categories = {
	Vampire = { Name = "Vampire", Color = Color3.fromRGB(214, 164, 74) }, -- amber gold, distinct from the red selection border
	Witch = { Name = "Witch", Color = Color3.fromRGB(70, 180, 170) }, -- teal
}

Config.Abilities = {
	VampiricSpeed = {
		Id = "VampiricSpeed",
		DisplayName = "Vampiric Speed",
		Description = "A supernatural burst of speed in the direction you are moving.",
		ShortName = "Vampiric",
		Category = "Vampire",
		Icon = "speed",
		Symbol = "V",
		Cooldown = 6,
		EffectDuration = 0.3, -- seconds
		Animation = {
			Id = "rbxassetid://522638767", -- toollunge: forward lunge, suits the dash
			FadeIn = 0.06,
			FadeOut = 0.18,
		},
		Dash = {
			Speed = 90, -- studs per second
			MaxForce = 1e5, -- horizontal force limit for the LinearVelocity
		},
	},
	TelekineticChoke = {
		Id = "TelekineticChoke",
		DisplayName = "Telekinetic Choke",
		Description = "Lifts and pins a target in front of you, choking them from a distance.",
		ShortName = "Telekinetic",
		Category = "Witch",
		Icon = "choke",
		Symbol = "T",
		Cooldown = 12,
		EffectDuration = 2, -- seconds the target is held
		Animation = {
			Id = "rbxassetid://507770453", -- point: arm extended toward the target
			FadeIn = 0.15,
			FadeOut = 0.25,
		},
		Choke = {
			Range = 22, -- studs, caster root to target root
			FacingHalfAngle = 55, -- degrees either side of caster look direction
			LiftHeight = 3, -- studs above the target's position when activated
			HoldForce = 2e5, -- AlignPosition force limit
			Damage = 12, -- total damage over the effect
			DamageTicks = 4, -- damage is applied in evenly spaced ticks
		},
	},
}

-- Status attribute set on characters that cannot use or be targeted by abilities.
Config.StatusAttribute = "Immobilized"

-- Training dummies: valid targets for testing abilities. Created by the server at startup.
Config.Training = {
	Positions = { Vector3.new(-12, 4, -22), Vector3.new(12, 4, -22) },
	MaxHealth = 500,
	RespawnDelay = 3, -- seconds before a destroyed dummy is replaced
}

Config.Server = {
	MinRequestInterval = 0.15, -- seconds between accepted requests per player
}

Config.Client = {
	RequestTimeout = 2, -- seconds before a pending request is considered lost
}

Config.Visuals = {
	DarkPurple = Color3.fromRGB(62, 16, 92),
	Purple = Color3.fromRGB(110, 40, 150),
	MutedRed = Color3.fromRGB(128, 38, 52),
}

return Config
