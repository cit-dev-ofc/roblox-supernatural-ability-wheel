--[[
	Training dummies: simple rigs with a Humanoid, a health bar above the head, and
	a respawn after they die. They are ordinary targets: the ability validation
	treats them like any other Humanoid, so this is a real test of the targeting code.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local settings = Config.Training
local theme = Config.Visuals

local TrainingDummies = {}

local function part(parent, name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A bar above the head that shows the current health.
local function buildHealthBar(head, humanoid)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(120, 18)
	gui.StudsOffset = Vector3.new(0, 1.8, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	gui.Parent = head

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(12, 8, 16)
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = theme.MutedRed
	fill.BorderSizePixel = 0
	fill.Parent = back

	local function refresh()
		local ratio = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
		fill.Size = UDim2.fromScale(ratio, 1)
	end
	refresh()
	humanoid.HealthChanged:Connect(refresh)
end

local function build(position)
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"

	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), theme.DarkPurple)
	root.Transparency = 1
	root.CanCollide = false
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), theme.DarkPurple)
	local head = part(model, "Head", Vector3.new(1.2, 1.2, 1.2), theme.Purple)
	head.Shape = Enum.PartType.Ball

	for _, child in ipairs({ torso, head }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = child
		weld.Parent = child
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = settings.MaxHealth
	humanoid.Health = settings.MaxHealth
	humanoid.DisplayName = "Training Dummy"
	humanoid.Parent = model

	model.PrimaryPart = root
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace

	buildHealthBar(head, humanoid)

	humanoid.Died:Connect(function()
		task.delay(settings.RespawnDelay, function()
			if model.Parent then
				model:Destroy()
			end
			build(position)
		end)
	end)
end

function TrainingDummies.Start()
	for _, position in ipairs(settings.Positions) do
		build(position)
	end
end

return TrainingDummies
