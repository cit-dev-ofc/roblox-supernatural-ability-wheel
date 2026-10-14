--[[
	Client controller: input (Q hold for the wheel, E to cast, Esc/right-click to
	cancel), target hints for the choke, and display of server responses. The
	client never decides availability; the server's response is the truth.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RadialWheel = require(script.Parent.RadialWheel)
local AbilityHud = require(script.Parent.AbilityHud)
local AbilityAnimations = require(script.Parent.AbilityAnimations)
local AbilityVisuals = require(script.Parent.AbilityVisuals)
local Loadout = require(script.Parent.Loadout)
local SpellBook = require(script.Parent.SpellBook)

local player = Players.LocalPlayer
local loadout = Loadout.new()
-- Which wheel is on screen: "Q" (hold Q) or "R" (press R, or click the center badge).
local currentView = "Q"
-- Edit mode: an empty slot the player marked. The next ability goes there; nil means "first empty".
local targetSlot = nil
local chokeConfig = Config.Abilities.TelekineticChoke.Choke

local REASON_TEXT = {
	cooldown = "Still recovering",
	dead = "You can't use abilities right now",
	busy = "Already using an ability",
	immobilized = "You are held in place",
	no_target = "No target in sight",
	invalid_target = "Invalid target",
	target_busy = "Target is already held",
	out_of_range = "Target is too far away",
	not_in_front = "Target must be in front of you",
	no_line_of_sight = "Target is out of sight",
	unknown_ability = "Unknown ability",
	not_equipped = "Equip this ability in Spells first",
}

local cooldownEnds = {}
local pending = false
local pendingDeadline = 0
local qKeyHeld = false -- Q is held: the Q wheel closes when it is released
local rKeyHeld = false -- R is held: the R wheel closes when it is released
local characterConnections = {}

local function getRemaining(id)
	return math.max(0, (cooldownEnds[id] or 0) - os.clock())
end

local function isAlive()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function findModelWithHumanoid(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function isValidChokeCandidate(model, root)
	if model == player.Character then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local targetRoot = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and targetRoot and humanoid.Health > 0) then
		return false
	end
	local offset = targetRoot.Position - root.Position
	if offset.Magnitude > chokeConfig.Range then
		return false
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > 0.5 and look.Magnitude > 0.1 then
		return look.Unit:Dot(flat.Unit) >= math.cos(math.rad(chokeConfig.FacingHalfAngle))
	end
	return true
end

-- Prefers the model under the cursor; falls back to the nearest valid target in front.
-- This is only a hint. The server validates distance, facing and line of sight.
local function findChokeTarget(character, root)
	local camera = workspace.CurrentCamera
	if camera then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(ray.Origin, ray.Direction * chokeConfig.Range * 2, params)
		if result then
			local model = findModelWithHumanoid(result.Instance)
			if model and isValidChokeCandidate(model, root) then
				return model
			end
		end
	end

	local best, bestDistance = nil, math.huge
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			local model = descendant.Parent
			if model:IsA("Model") and isValidChokeCandidate(model, root) then
				local distance = (model.HumanoidRootPart.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = model, distance
				end
			end
		end
	end
	return best
end

local wheel, hud, spellBook

-- id may be nil when nothing is equipped; the wheel and HUD both show an empty state then.
local function selectAbility(id)
	wheel:SetSelected(id)
	hud:SetSelected(id and Config.Abilities[id] or nil)
end

local function refreshLoadout()
	wheel:SetLoadout(loadout:Get(currentView))
	if spellBook then
		local equipped = {}
		for _, key in ipairs(Config.Loadout.Wheels) do
			for _, id in ipairs(loadout:Get(key)) do
				if id then
					table.insert(equipped, id)
				end
			end
		end
		spellBook:SetEquipped(equipped)
	end
	local selected = wheel:GetSelected()
	if not selected or loadout:Locate(selected) == nil then
		selectAbility(loadout:FirstEquipped())
	end
end

local function requestAbility(id)
	if pending and os.clock() < pendingDeadline then
		return
	end
	if not id then
		hud:ShowMessage("Equip an ability in Spells first")
		return
	end
	if not Config.Abilities[id] then
		return
	end
	if not isAlive() then
		hud:ShowMessage(REASON_TEXT.dead)
		return
	end
	if getRemaining(id) > 0 then
		hud:ShowMessage(REASON_TEXT.cooldown)
		return
	end

	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	local target, direction
	if id == "VampiricSpeed" then
		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude > 0.1 then
			direction = moveDirection
		end
	elseif id == "TelekineticChoke" then
		target = findChokeTarget(character, root)
		if not target then
			hud:ShowMessage(REASON_TEXT.no_target)
			return
		end
	end

	pending = true
	pendingDeadline = os.clock() + Config.Client.RequestTimeout
	Remotes.Request:FireServer(id, target, direction)
end

local function closeWheel()
	qKeyHeld = false
	rKeyHeld = false
	targetSlot = nil
	if wheel:IsOpen() then
		wheel:Close()
	end
end

local function toggleWheel()
	if wheel:IsOpen() then
		closeWheel()
	elseif isAlive() then
		wheel:Open()
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "AbilityGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Clicks send requests to the server, which decides and replies with LoadoutState.
local function onEditSlot(index)
	if loadout:Get(currentView)[index] then
		Remotes.Loadout:FireServer("unequip", currentView, index)
		targetSlot = nil
	else
		targetSlot = (targetSlot ~= index) and index or nil
	end
	wheel:SetTarget(targetSlot)
end

-- Clicking an ability in the Spells panel asks the server to toggle it in the wheel on screen:
-- removed if it is there, equipped into the marked slot (or the first empty one) if it is not.
local function onPickAbility(id)
	Remotes.Loadout:FireServer("toggle", currentView, id, targetSlot)
	targetSlot = nil
	wheel:SetTarget(nil)
	spellBook:SetPicked(nil)
end

local function openSpells()
	if wheel:IsOpen() then
		closeWheel()
		return
	end
	wheel:Open()
	wheel:SetEditing(true)
	spellBook:SetPicked(nil)
end

-- Switches the wheel on screen between Q and R. Pending marks belong to one wheel, so they reset.
local function setView(view)
	if currentView == view then
		return
	end
	currentView = view
	targetSlot = nil
	wheel:SetTarget(nil)
	wheel:SetView(view)
	refreshLoadout()
end

local function toggleView()
	setView(currentView == "Q" and "R" or "Q")
end

wheel = RadialWheel.new(gui, {
	catalog = Loadout.Catalog(),
	onSelect = selectAbility,
	onEditSlot = onEditSlot,
	onPickAbility = onPickAbility,
	onClose = closeWheel,
	onToggleView = toggleView,
})
wheel:SetView(currentView)

hud = AbilityHud.new(gui, {
	onCast = function()
		requestAbility(wheel:GetSelected())
	end,
	onToggleWheel = toggleWheel,
	onOpenSpells = openSpells,
})

spellBook = SpellBook.new(gui, {
	catalog = Loadout.Catalog(),
	onPick = onPickAbility,
})

refreshLoadout()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Config.Input.WheelKey then
		if UserInputService:GetFocusedTextBox() then
			return
		end
		qKeyHeld = true
		if isAlive() then
			setView("Q")
			wheel:Open()
		end
	elseif input.KeyCode == Config.Input.SpellsKey then
		if UserInputService:GetFocusedTextBox() then
			return
		end
		rKeyHeld = true
		if isAlive() then
			setView("R")
			wheel:Open()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Left click casts the selected ability. Clicks on GUI (slots, the CAST button) are
		-- handled by those elements, so they are skipped here.
		if gameProcessed or wheel:IsOpen() then
			return
		end
		requestAbility(wheel:GetSelected())
	elseif input.KeyCode == Config.Input.CancelKey or input.UserInputType == Enum.UserInputType.MouseButton2 then
		if wheel:IsOpen() then
			closeWheel()
		end
	end
end)

-- Releasing Q or R selects the hovered slot and closes the wheel, but only once both keys are up.
-- So holding Q, pressing R and releasing Q keeps the wheel open until R is released too.
local function releaseWheelKey(keyName)
	if keyName == "Q" then
		qKeyHeld = false
	else
		rKeyHeld = false
	end
	if qKeyHeld or rKeyHeld then
		return
	end
	if wheel:IsOpen() and not wheel:IsEditing() then
		local hovered = wheel:GetHovered()
		if hovered then
			selectAbility(hovered)
		end
		wheel:Close()
	end
end

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.Input.WheelKey and qKeyHeld then
		releaseWheelKey("Q")
	elseif input.KeyCode == Config.Input.SpellsKey and rKeyHeld then
		releaseWheelKey("R")
	end
end)

Remotes.Response.OnClientEvent:Connect(function(abilityId, ok, reason, remaining)
	pending = false
	if typeof(abilityId) ~= "string" or not Config.Abilities[abilityId] then
		return
	end
	if typeof(remaining) == "number" and remaining > 0 then
		cooldownEnds[abilityId] = os.clock() + remaining
	end
	if ok then
		AbilityAnimations.Play(player.Character, abilityId, Config.Abilities[abilityId].EffectDuration)
	elseif reason and REASON_TEXT[reason] then
		hud:ShowMessage(REASON_TEXT[reason])
	end
end)

-- Loadout state from the server: the full slot list, plus a reason when a request was refused.
local LOADOUT_REASON = {
	full = "All slots are full. Click an equipped slot to remove one.",
	already_equipped = "That ability is already equipped.",
	in_other_wheel = "That ability is already in the other wheel.",
	slot_taken = "That slot is already filled.",
	invalid_slot = "That slot does not exist.",
	unknown_ability = "Unknown ability.",
}

Remotes.LoadoutState.OnClientEvent:Connect(function(wheels, reason)
	if typeof(wheels) ~= "table" then
		return
	end
	loadout:Apply(wheels)
	-- A marked slot that is now filled (by this player or the server) is no longer a valid target.
	if targetSlot and loadout:Get(currentView)[targetSlot] then
		targetSlot = nil
		wheel:SetTarget(nil)
	end
	refreshLoadout()
	if reason and LOADOUT_REASON[reason] then
		hud:ShowMessage(LOADOUT_REASON[reason])
	end
end)

Remotes.Visual.OnClientEvent:Connect(function(abilityId, character)
	AbilityVisuals.Play(abilityId, character)
end)

local function onCharacterAdded(character)
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	pending = false
	closeWheel()
	AbilityAnimations.StopAll()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		table.insert(characterConnections, humanoid.Died:Connect(function()
			closeWheel()
			AbilityAnimations.StopAll()
		end))
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function()
	pending = false
	closeWheel()
	AbilityAnimations.StopAll()
end)
if player.Character then
	onCharacterAdded(player.Character)
end

RunService.RenderStepped:Connect(function()
	wheel:Update(getRemaining)
	hud:Update(getRemaining)
	hud:SetHidden(wheel:IsOpen())
	spellBook:SetVisible(wheel:IsEditing())
end)

Remotes.Loadout:FireServer("sync")
