--[[
	Always-visible HUD: the selected ability, its state, a cast button, and short
	status messages. On touch devices it also shows an ABILITIES button, since
	there is no Q key.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local AbilityHud = {}
AbilityHud.__index = AbilityHud

local function make(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function round(parent, scale)
	return make("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

function AbilityHud.new(screenGui, options)
	local self = setmetatable({}, AbilityHud)
	self._selected = nil
	self._tweens = {}
	self._connections = {}

	local frame = make("Frame", {
		Name = "AbilityHud",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0.32, 0, 0, 60),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, screenGui)
	round(frame, 0.2)
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, frame)
	make("UISizeConstraint", { MinSize = Vector2.new(250, 60), MaxSize = Vector2.new(360, 60) }, frame)
	self._frame = frame

	-- Ability icon in a round well on the left.
	local well = make("Frame", {
		Name = "IconWell",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, frame)
	round(well, 0.5)
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, well)
	self._iconWell = well

	local nameLabel = make("TextLabel", {
		Name = "AbilityName",
		Position = UDim2.new(0, 62, 0, 10),
		Size = UDim2.new(1, -170, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	make("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 10 }, nameLabel)
	self._name = nameLabel

	local status = make("TextLabel", {
		Name = "Status",
		Position = UDim2.new(0, 62, 0, 32),
		Size = UDim2.new(1, -170, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextColor3 = Theme.Ready,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, status)
	self._status = status

	local castButton = make("TextButton", {
		Name = "CastButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(92, 34),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.25,
		AutoButtonColor = true,
		Font = Theme.FontBold,
		Text = "USE",
		TextColor3 = Theme.Text,
		TextScaled = true,
		BorderSizePixel = 0,
	}, frame)
	round(castButton, 0.25)
	make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 9 }, castButton)
	table.insert(self._connections, castButton.Activated:Connect(function()
		if options.onCast then
			options.onCast()
		end
	end))
	self._castButton = castButton

	-- Recharge progress along the bottom edge.
	local barBack = make("Frame", {
		Name = "ProgressBack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -24, 0, 2),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, frame)
	self._barFill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
	}, barBack)

	-- Short message above the HUD (e.g. "Still recovering").
	local message = make("TextLabel", {
		Name = "Message",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0.3, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextColor3 = Theme.Text,
		TextTransparency = 1,
		TextScaled = true,
	}, screenGui)
	make("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10 }, message)
	self._message = message

	-- Touch fallback for opening the wheel.
	if UserInputService.TouchEnabled then
		local wheelButton = make("TextButton", {
			Name = "WheelButton",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -96),
			Size = UDim2.fromOffset(120, 44),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.05,
			AutoButtonColor = true,
			Font = Theme.FontBold,
			Text = "ABILITIES",
			TextColor3 = Theme.Text,
			TextScaled = true,
			BorderSizePixel = 0,
		}, screenGui)
		round(wheelButton, 0.25)
		make("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, wheelButton)
		table.insert(self._connections, wheelButton.Activated:Connect(function()
			if options.onToggleWheel then
				options.onToggleWheel()
			end
		end))
		self._wheelButton = wheelButton
	end

	-- On-screen cue for the keys, sitting just above the HUD panel.
	self._keyCue = make("TextLabel", {
		Name = "KeyCue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -88),
		Size = UDim2.new(0.32, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "[Q] Abilities     [R] Spells",
		TextColor3 = Theme.TextDim,
		TextScaled = true,
	}, screenGui)
	make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, self._keyCue)

	-- Feitiços: opens the loadout editor in the wheel. Shown on both PC and touch.
	local spellsButton = make("TextButton", {
		Name = "SpellsButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -24),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		AutoButtonColor = true,
		Font = Theme.FontBold,
		Text = "SPELLS",
		TextColor3 = Theme.Text,
		TextScaled = true,
		BorderSizePixel = 0,
	}, screenGui)
	round(spellsButton, 0.25)
	make("UIStroke", { Color = Theme.Stroke, Thickness = 1 }, spellsButton)
	make("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9 }, spellsButton)
	table.insert(self._connections, spellsButton.Activated:Connect(function()
		if options.onOpenSpells then
			options.onOpenSpells()
		end
	end))
	self._spellsButton = spellsButton

	return self
end

-- Shows the icon and name of the selected ability, or an empty state when nothing is equipped.
function AbilityHud:SetSelected(definition)
	self._selected = definition and definition.Id or nil
	local previous = self._iconWell:FindFirstChild("IconHolder")
	if previous then
		previous:Destroy()
	end
	if not definition then
		self._name.Text = "No ability"
		self._status.Text = "Open Spells to equip one"
		self._status.TextColor3 = Theme.TextDim
		self._barFill.Size = UDim2.fromScale(0, 1)
		self._castButton.BackgroundTransparency = 0.6
		return
	end
	self._name.Text = definition.DisplayName
	local holder = make("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundTransparency = 1,
	}, self._iconWell)
	Icons.Build(holder, definition.Icon, Theme.Text, definition.Symbol)
end

-- Hides the panel while the wheel is open, since the wheel already shows the active ability.
function AbilityHud:SetHidden(hidden)
	self._frame.Visible = not hidden
	self._spellsButton.Visible = not hidden
	self._keyCue.Visible = not hidden
end

function AbilityHud:ShowMessage(text)
	self._message.Text = text
	if self._messageTween then
		self._messageTween:Cancel()
	end
	self._message.TextTransparency = 0
	self._messageTween = TweenService:Create(self._message, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4), {
		TextTransparency = 1,
	})
	self._messageTween:Play()
end

-- Called every frame by the controller with a function that returns seconds remaining.
function AbilityHud:Update(getRemaining)
	local id = self._selected
	if not id then
		return
	end
	local cooldown = Config.Abilities[id].Cooldown
	local remaining = getRemaining(id)
	if remaining > 0 then
		self._status.Text = string.format("Recharging  %.1fs", remaining)
		self._status.TextColor3 = Theme.TextDim
		self._barFill.Size = UDim2.fromScale(math.clamp(1 - remaining / cooldown, 0, 1), 1)
		self._barFill.BackgroundColor3 = Theme.Accent
		self._castButton.BackgroundTransparency = 0.6
	else
		self._status.Text = "Ready"
		self._status.TextColor3 = Theme.Ready
		self._barFill.Size = UDim2.fromScale(1, 1)
		self._barFill.BackgroundColor3 = Theme.AccentSoft
		self._castButton.BackgroundTransparency = 0.25
	end
end

function AbilityHud:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._messageTween then
		self._messageTween:Cancel()
	end
	self._frame:Destroy()
	self._message:Destroy()
	self._spellsButton:Destroy()
	self._keyCue:Destroy()
	if self._wheelButton then
		self._wheelButton:Destroy()
	end
end

return AbilityHud
