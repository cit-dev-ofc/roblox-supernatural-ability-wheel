--[[
	Radial ability wheel. Layout is one column: title band, ring, hint row.
	The ring places the slots at evenly spaced angles around one shared center,
	with the Q badge in the middle. Every size is a fraction of the panel.

	Two modes:
	- Play: hovering a slot highlights it, and releasing Q (or clicking) selects it.
	- Edit (Feitiços): the title band lists the catalog; clicking a catalog entry picks it,
	  clicking a slot equips the picked ability there, and clicking an equipped slot
	  removes it.

	The wheel never decides availability; the server does.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local RadialWheel = {}
RadialWheel.__index = RadialWheel

local SLOT_COUNT = Config.Loadout.SlotCount
local SLOT_SIZE = 0.18 -- slot diameter / ring width
local RING_RADIUS = 0.38 -- distance from the ring center to each slot center / ring width
local BADGE_SIZE = 0.2 -- Q badge diameter / ring width
local FIRST_ANGLE = 90 -- degrees; slot 1 at the top, the rest clockwise
local PANEL_HEIGHT = 0.9 -- panel height as a fraction of the screen
local TITLE_BAND = 0.13 -- title band height / panel height
local RING_BAND = 0.75 -- ring height / panel height (equals the panel width, so the ring is square)
local HINT_BAND = 0.1 -- hint row height / panel height
local DEAD_ZONE = 0.1 -- cursor within this fraction of the ring width from the center selects nothing
local POINTER_RADIUS = 0.26 -- direction dot's distance from the center, inside the slot ring
local POINTER_SIZE = 0.035 -- direction dot diameter / ring width

local PLAY_HINT = "Release Q to select · Click to use · Esc to cancel"
local EDIT_HINT = "Click a slot to equip · click an equipped slot to remove"

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

local function slotCenter(index)
	local angle = math.rad(FIRST_ANGLE - (index - 1) * 360 / SLOT_COUNT)
	return UDim2.fromScale(0.5 + RING_RADIUS * math.cos(angle), 0.5 - RING_RADIUS * math.sin(angle))
end

local function categoryColor(id)
	local category = Config.Categories[Config.Abilities[id].Category]
	return category and category.Color or Theme.Stroke
end

local function setTween(store, key, instance, info, goal)
	if store[key] then
		store[key]:Cancel()
	end
	local tween = TweenService:Create(instance, info, goal)
	store[key] = tween
	tween:Play()
	return tween
end

function RadialWheel.new(screenGui, options)
	local self = setmetatable({}, RadialWheel)
	self._onSelect = options.onSelect
	self._onEditSlot = options.onEditSlot
	self._onPickAbility = options.onPickAbility
	self._onClose = options.onClose
	self._onToggleView = options.onToggleView
	self._target = nil -- edit mode: the empty slot the next ability will be placed in
	self._catalog = options.catalog
	self._open = false
	self._editing = false
	self._pick = nil
	self._hoverIndex = nil
	self._selected = nil
	self._slots = {}
	self._connections = {}
	self._tweens = {}
	self._closeToken = 0
	self._chips = {}

	local panel = make("Frame", {
		Name = "RadialWheel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 0, PANEL_HEIGHT, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, screenGui)
	make("UIAspectRatioConstraint", {
		AspectRatio = 0.75,
		DominantAxis = Enum.DominantAxis.Height,
	}, panel)
	make("UISizeConstraint", { MinSize = Vector2.new(340, 453), MaxSize = Vector2.new(520, 693) }, panel)
	self._scale = make("UIScale", { Scale = 1 }, panel)
	self._root = panel

	local titleBand = make("Frame", {
		Name = "TitleBand",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, TITLE_BAND, 0),
		BackgroundTransparency = 1,
	}, panel)
	self._titleBand = titleBand

	self._titleName = make("TextLabel", {
		Name = "Name",
		Position = UDim2.fromScale(0.04, 0.08),
		Size = UDim2.new(0.8, 0, 0.46, 0),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBand)
	make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 11 }, self._titleName)

	self._titleDesc = make("TextLabel", {
		Name = "Description",
		Position = UDim2.fromScale(0.04, 0.56),
		Size = UDim2.new(0.92, 0, 0.32, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextColor3 = Theme.TextDim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBand)
	make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8 }, self._titleDesc)

	self._activeTag = make("TextLabel", {
		Name = "ActiveTag",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.1),
		Size = UDim2.fromOffset(58, 16),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.3,
		Font = Theme.FontBold,
		Text = "ACTIVE",
		TextColor3 = Theme.Text,
		TextSize = 10,
		Visible = false,
	}, titleBand)
	round(self._activeTag, 0.5)

	local chipRow = make("Frame", {
		Name = "CatalogChips",
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.6),
		BackgroundTransparency = 1,
		Visible = false,
	}, titleBand)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chipRow)
	self._chipRow = chipRow

	for order, id in ipairs(self._catalog) do
		local chip = make("TextButton", {
			Name = id,
			LayoutOrder = order,
			Size = UDim2.new(1 / math.max(#self._catalog, 1), -6, 1, 0),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			AutoButtonColor = true,
			Font = Theme.FontBold,
			Text = Config.Abilities[id].ShortName or Config.Abilities[id].DisplayName,
			TextColor3 = Theme.Text,
			TextScaled = true,
			BorderSizePixel = 0,
		}, chipRow)
		round(chip, 0.3)
		make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Stroke, Thickness = 1 }, chip)
		make("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8 }, chip)
		self._chips[id] = chip
		table.insert(self._connections, chip.Activated:Connect(function()
			if self._editing and self._onPickAbility then
				self._onPickAbility(id)
			end
		end))
	end

	local ring = make("Frame", {
		Name = "Ring",
		Position = UDim2.new(0, 0, TITLE_BAND, 0),
		Size = UDim2.new(1, 0, RING_BAND, 0),
		BackgroundTransparency = 1,
	}, panel)
	self._ring = ring

	local track = make("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(RING_RADIUS * 2, RING_RADIUS * 2),
		BackgroundTransparency = 1,
	}, ring)
	round(track, 0.5)
	make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Stroke, Thickness = 1, Transparency = 0.6 }, track)

	-- Direction marker: a small dot on an inner track, placed toward the cursor. It sits inside the
	-- slot circle, so it never covers a slot.
	self._pointer = make("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(POINTER_SIZE, POINTER_SIZE),
		BackgroundColor3 = Theme.AccentSoft,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
	}, ring)
	round(self._pointer, 0.5)

	local badge = make("TextButton", {
		Name = "KeyBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(BADGE_SIZE, BADGE_SIZE),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
	}, ring)
	round(badge, 0.5)
	make("UIAspectRatioConstraint", {}, badge)
	make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Accent, Thickness = 1.5 }, badge)
	self._keyLabel = make("TextLabel", {
		Name = "Key",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "Q",
		TextColor3 = Theme.Text,
		TextScaled = true,
	}, badge)
	table.insert(self._connections, badge.Activated:Connect(function()
		if self._onToggleView then
			self._onToggleView()
		end
	end))

	local hintRow = make("Frame", {
		Name = "Hints",
		Position = UDim2.new(0, 0, TITLE_BAND + RING_BAND + HINT_BAND * 0.55, 0),
		Size = UDim2.new(1, 0, HINT_BAND * 0.45, 0),
		BackgroundTransparency = 1,
	}, panel)
	self._hintRow = hintRow
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, hintRow)
	self._keyHints = {}

	local closeButton = make("TextButton", {
		Name = "CloseButton",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(64, 20),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Font = Theme.FontBold,
		Text = "CLOSE",
		TextColor3 = Theme.Text,
		TextSize = 11,
		BorderSizePixel = 0,
	}, hintRow)
	round(closeButton, 0.3)
	make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Stroke, Thickness = 1 }, closeButton)
	table.insert(self._connections, closeButton.Activated:Connect(function()
		if self._onClose then
			self._onClose()
		end
	end))

	-- The hint band sits outside the row's layout, so the CLOSE button stays centered.
	-- Edit mode shows the click instructions here.
	self._editHint = make("TextLabel", {
		Name = "EditHint",
		Position = UDim2.new(0.04, 0, TITLE_BAND + RING_BAND, 0),
		Size = UDim2.new(0.92, 0, HINT_BAND * 0.55, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = EDIT_HINT,
		TextColor3 = Theme.TextDim,
		TextScaled = true,
		Visible = false,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, self._editHint)

	-- Play mode: a short notice when the wheel opens, so the player knows releasing Q selects.
	self._notice = make("TextLabel", {
		Name = "ReleaseNotice",
		Position = UDim2.new(0.04, 0, TITLE_BAND + RING_BAND, 0),
		Size = UDim2.new(0.92, 0, HINT_BAND * 0.55, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "Release Q to select",
		TextColor3 = Theme.TextDim,
		TextScaled = true,
		TextTransparency = 1,
	}, panel)
	make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, self._notice)

	for index = 1, SLOT_COUNT do
		self._slots[index] = self:_buildSlot(index)
	end

	self:_refresh()
	return self
end

function RadialWheel:_buildSlot(index)
	local slot = make("TextButton", {
		Name = "Slot" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = slotCenter(index),
		Size = UDim2.fromScale(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.6,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, self._ring)
	round(slot, 0.5)
	make("UIAspectRatioConstraint", {}, slot)
	local scale = make("UIScale", { Scale = 0 }, slot)
	local stroke = make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Stroke, Thickness = 1.5, Transparency = 0.6 }, slot)

	local iconHolder = make("Frame", {
		Name = "IconHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
	}, slot)

	local overlay = make("Frame", {
		Name = "CooldownOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, slot)
	round(overlay, 0.5)

	local countdown = make("TextLabel", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.3),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "",
		TextColor3 = Theme.Text,
		TextScaled = true,
		ZIndex = 3,
		Visible = false,
	}, slot)

	local barBack = make("Frame", {
		Name = "CooldownBarBack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.56, 0.07),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ZIndex = 3,
		Visible = false,
	}, slot)
	round(barBack, 0.5)
	local barFill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, barBack)
	round(barFill, 0.5)

	local activeDot = make("Frame", {
		Name = "ActiveDot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1.12),
		Size = UDim2.fromScale(0.07, 0.07),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Visible = false,
	}, slot)
	round(activeDot, 0.5)

	local slotData = {
		index = index,
		id = nil,
		button = slot,
		scale = scale,
		stroke = stroke,
		iconHolder = iconHolder,
		overlay = overlay,
		countdown = countdown,
		barBack = barBack,
		barFill = barFill,
		activeDot = activeDot,
	}

	-- The circle under the cursor comes from the button's own enter/leave events, so it always
	-- matches what a click on that circle selects, whatever the mouse coordinates are.
	table.insert(self._connections, slot.MouseEnter:Connect(function()
		self._circleHover = index
	end))
	table.insert(self._connections, slot.MouseLeave:Connect(function()
		if self._circleHover == index then
			self._circleHover = nil
		end
	end))

	table.insert(self._connections, slot.Activated:Connect(function()
		if not self._open then
			return
		end
		if self._editing then
			if self._onEditSlot then
				self._onEditSlot(index)
			end
		elseif slotData.id and self._onSelect then
			self._onSelect(slotData.id)
			self:Close()
		end
	end))

	return slotData
end

function RadialWheel:SetLoadout(slots)
	for index, slot in ipairs(self._slots) do
		local id = slots[index] or nil
		slot.id = id
		slot.iconHolder:ClearAllChildren()
		if id then
			Icons.Build(slot.iconHolder, Config.Abilities[id].Icon, Theme.Text, Config.Abilities[id].Symbol)
			slot.button.BackgroundColor3 = Theme.Panel
			slot.button.BackgroundTransparency = 0.3
			slot.stroke.Transparency = 0
		else
			-- Empty slots show their fixed number: the number identifies the slot, not the ability.
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.FontBold,
				Text = tostring(index),
				TextColor3 = Theme.TextDim,
				TextScaled = true,
			}, slot.iconHolder)
			slot.button.BackgroundColor3 = Theme.Background
			slot.button.BackgroundTransparency = 0.6
			slot.stroke.Transparency = 0.6
		end
	end
	self:_refresh()
end

function RadialWheel:SetSelected(id)
	self._selected = id
	self:_refresh()
end

function RadialWheel:GetSelected()
	return self._selected
end

function RadialWheel:SetView(letter)
	self._keyLabel.Text = letter
end

function RadialWheel:SetEditing(editing)
	self._editing = editing
	self._target = nil
	self:SetPick(nil)
	self._chipRow.Visible = false
	self._titleName.Visible = true
	self._titleName.TextXAlignment = editing and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	self._titleDesc.Visible = true
	if editing then
		self._titleName.Text = "Equip or unequip abilities"
		self._titleDesc.Text = ""
	end
	self._editHint.Visible = editing
	self._notice.Visible = not editing
	if editing then
		self._activeTag.Visible = false
	end
	self:_refresh()
end

function RadialWheel:IsEditing()
	return self._editing
end


function RadialWheel:SetTarget(index)
	self._target = index
	self:_refresh()
end

function RadialWheel:SetPick(id)
	self._pick = id
	for chipId, chip in pairs(self._chips) do
		chip.BackgroundColor3 = chipId == id and Theme.Accent or Theme.Panel
	end
end

function RadialWheel:_refresh()
	for _, slot in ipairs(self._slots) do
		local hovered = slot.index == self._hoverIndex
		local selected = slot.id ~= nil and slot.id == self._selected
		slot.activeDot.Visible = selected and not self._editing
		if slot.index == self._target then
			slot.stroke.Color = Theme.Target
			slot.stroke.Thickness = 3
			slot.stroke.Transparency = 0
		elseif hovered then
			slot.stroke.Color = Theme.AccentSoft
			slot.stroke.Thickness = 2
			slot.stroke.Transparency = 0
		elseif selected then
			slot.stroke.Color = Theme.Accent
			slot.stroke.Thickness = 2
			slot.stroke.Transparency = 0
		else
			slot.stroke.Color = slot.id and categoryColor(slot.id) or Theme.Stroke
			slot.stroke.Thickness = 1.5
			slot.stroke.Transparency = slot.id and 0 or 0.6
		end
	end
	self:_refreshTitle()
end

function RadialWheel:_refreshTitle()
	if self._editing then
		return
	end
	local id = self:GetHovered() or self._selected
	local definition = id and Config.Abilities[id]
	if not definition then
		self._titleName.Text = self._selected == nil and "No ability equipped" or ""
		self._titleDesc.Text = self._selected == nil and "Open Spells to equip one." or ""
		self._activeTag.Visible = false
		return
	end
	self._titleName.Text = definition.DisplayName
	self._titleDesc.Text = definition.Description
	self._activeTag.Visible = id == self._selected
end

function RadialWheel:GetHovered()
	if not self._hoverIndex then
		return nil
	end
	return self._slots[self._hoverIndex].id
end

-- Which slot the cursor points at. The highlight and the click always agree:
-- 1. If the cursor is over a slot circle, that slot is the one (empty slots only in edit mode).
--    Over an empty slot in play mode, nothing is highlighted.
-- 2. Between the slots, the slot closest in angle from the ring center is used. This is the
--    selection Q-release makes. Inside the dead zone around the Q badge nothing is selected.
function RadialWheel:_findHoverIndex()
	local mouse = UserInputService:GetMouseLocation()
	local ring = self._ring
	local center = ring.AbsolutePosition + ring.AbsoluteSize / 2

	if self._circleHover then
		local slot = self._slots[self._circleHover]
		return (self._editing or slot.id) and slot.index or nil
	end

	if self._editing then
		return nil
	end
	local offset = mouse - center
	if offset.Magnitude < ring.AbsoluteSize.X * DEAD_ZONE then
		return nil
	end
	local best, bestCos = nil, -math.huge
	for _, slot in ipairs(self._slots) do
		if slot.id then
			local button = slot.button
			local toSlot = button.AbsolutePosition + button.AbsoluteSize / 2 - center
			local cos = offset:Dot(toSlot) / (offset.Magnitude * toSlot.Magnitude)
			if cos > bestCos then
				best, bestCos = slot.index, cos
			end
		end
	end
	return best
end

-- Moves the direction dot to the cursor's angle on the inner track. Hidden in edit mode
-- and inside the dead zone.
function RadialWheel:_updatePointer()
	local ring = self._ring
	local center = ring.AbsolutePosition + ring.AbsoluteSize / 2
	local offset = UserInputService:GetMouseLocation() - center
	local visible = self._open and not self._editing and offset.Magnitude >= ring.AbsoluteSize.X * DEAD_ZONE
	self._pointer.Visible = visible
	if visible then
		local angle = math.atan2(-offset.Y, offset.X) -- screen Y points down, so flip it
		self._pointer.Position = UDim2.fromScale(
			0.5 + POINTER_RADIUS * math.cos(angle),
			0.5 - POINTER_RADIUS * math.sin(angle)
		)
	end
end

function RadialWheel:_setHoverIndex(index)
	if index == self._hoverIndex then
		return
	end
	local previous = self._hoverIndex and self._slots[self._hoverIndex]
	if previous then
		setTween(self._tweens, "grow" .. previous.index, previous.scale, Theme.Tween.Hover, { Scale = 1 })
	end
	self._hoverIndex = index
	local current = index and self._slots[index]
	if current then
		setTween(self._tweens, "grow" .. index, current.scale, Theme.Tween.Hover, { Scale = 1.08 })
	end
	self:_refresh()
end

function RadialWheel:IsOpen()
	return self._open
end

function RadialWheel:Open()
	if self._open then
		return
	end
	self._open = true
	self._closeToken += 1
	self._root.Visible = true
	self._scale.Scale = 0.94
	self._notice.TextTransparency = 0
	setTween(self._tweens, "notice", self._notice, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), { TextTransparency = 1 })
	setTween(self._tweens, "rootScale", self._scale, Theme.Tween.Open, { Scale = 1 })

	for _, slot in ipairs(self._slots) do
		local info = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, (slot.index - 1) * 0.02)
		slot.scale.Scale = 0
		setTween(self._tweens, "pop" .. slot.index, slot.scale, info, { Scale = 1 })
	end
	self:_refresh()
end

function RadialWheel:Close()
	if not self._open then
		return
	end
	self._open = false
	self._circleHover = nil
	if self._editing then
		self:SetEditing(false)
	end
	self:_setHoverIndex(nil)
	self._closeToken += 1
	local token = self._closeToken

	local fade = setTween(self._tweens, "rootScale", self._scale, Theme.Tween.Close, { Scale = 0.96 })
	fade.Completed:Once(function()
		-- Ignore if the wheel was reopened while closing.
		if token == self._closeToken and not self._open then
			self._root.Visible = false
		end
	end)
end

function RadialWheel:Update(getRemaining)
	if self._open then
		self:_setHoverIndex(self:_findHoverIndex())
		self:_updatePointer()
	else
		self._pointer.Visible = false
	end

	for _, slot in ipairs(self._slots) do
		if slot.id then
			local cooldown = Config.Abilities[slot.id].Cooldown
			local remaining = getRemaining(slot.id)
			local onCooldown = remaining > 0
			slot.overlay.BackgroundTransparency = onCooldown and 0.45 or 1
			slot.iconHolder.Visible = not onCooldown
			slot.countdown.Visible = onCooldown
			slot.barBack.Visible = onCooldown
			if onCooldown then
				slot.countdown.Text = string.format("%.1f", remaining)
				slot.barFill.Size = UDim2.fromScale(math.clamp(remaining / cooldown, 0, 1), 1)
			end
		else
			-- Empty slot: show its number again. A cooldown on the same slot in the other wheel
			-- must not hide it, so the holder is restored here.
			slot.overlay.BackgroundTransparency = 1
			slot.iconHolder.Visible = true
			slot.countdown.Visible = false
			slot.barBack.Visible = false
		end
	end
end

function RadialWheel:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, tween in pairs(self._tweens) do
		tween:Cancel()
	end
	table.clear(self._tweens)
	self._root:Destroy()
end

return RadialWheel
