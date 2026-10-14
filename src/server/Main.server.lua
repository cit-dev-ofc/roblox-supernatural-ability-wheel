-- Server entry point. Creates remotes and starts the ability service.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes)
require(script.Parent.LoadoutService).Start()
require(script.Parent.AbilityService).Start()
require(script.Parent.TrainingDummies).Start()
