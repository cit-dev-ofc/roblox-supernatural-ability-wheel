--[[
	Spells panel: shown beside the wheel in edit mode. All abilities sit in one
	two-column grid. Each card shows its category in the category color, and the
	picked card shows details below. Clicking a card asks the server to equip or
	remove it; this panel only displays the state it receives.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local SpellBook = {}
SpellBook.__index = SpellBook

local CARD_HEIGHT = 96
local CARD_BLEND = 0.18 -- how much of the category color tints a card's background

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

-- Category order first, then catalog order inside a category.
local function sortedCatalog(catalog)
	local categoryRank = {}
	for index, key in ipairs(Config.CategoryOrder) do
		categoryRank[key] = index
	end
	local catalogRank = {}
	for index, id in ipairs(catalog) do
		catalogRank[id] = index
	end
	local ids = table.clone(catalog)
	table.sort(ids, function(a, b)
		local ca = categoryRank[Config.Abilities[a].Category] or math.huge
		local cb = categoryRank[Config.Abilities[b].Category] or math.huge
		if ca ~= cb then
			return ca < cb
		end
		return catalogRank[a] < catalogRank[b]
	end)
	return ids
end

function SpellBook.new(screenGui, options)
	local self = setmetatable({}, SpellBook)
	self._cards = {}
	self._connections = {}
	self._onPick = options.onPick

	local panel = make("Frame", {
		Name = "SpellBook",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.new(0.3, 0, 0.7, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
	}, screenGui)
	round(panel, 0.05)
	make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Theme.Stroke, Thickness = 1 }, panel)
	make("UISizeConstraint", { MinSize = Vector2.new(240, 360), MaxSize = Vector2.new(340, 560) }, panel)
	self._panel = panel

	make("TextLabel", {
		Name = "Title",
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.08),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "Spells",
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)

	-- One scrolling two-column grid for every ability.
	local grid = make("ScrollingFrame", {
		Name = "Cards",
		Position = UDim2.fromScale(0.05, 0.13),
		Size = UDim2.fromScale(0.9, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Stroke,
	}, panel)
	make("UIGridLayout", {
		CellSize = UDim2.new(0.48, 0, 0, CARD_HEIGHT),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	-- A little room inside the scroll area, so card outlines are not cut off at the edges.
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 2),
	}, grid)

	for order, id in ipairs(sortedCatalog(options.catalog)) do
		self:_buildCard(grid, id, order)
	end

	-- Details of the picked ability.
	local detail = make("Frame", {
		Name = "Detail",
		Position = UDim2.fromScale(0.05, 0.66),
		Size = UDim2.fromScale(0.9, 0.3),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, panel)
	round(detail, 0.08)

	self._detailName = make("TextLabel", {
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = "Pick a spell",
		TextColor3 = Theme.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, detail)
	self._detailDesc = make("TextLabel", {
		Position = UDim2.fromScale(0.05, 0.3),
		Size = UDim2.fromScale(0.9, 0.4),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextColor3 = Theme.TextDim,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, detail)
	self._detailStats = make("TextLabel", {
		Position = UDim2.fromScale(0.05, 0.76),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextColor3 = Theme.Ready,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, detail)

	self:SetPicked(nil)
	return self
end

function SpellBook:_buildCard(parent, id, order)
	local definition = Config.Abilities[id]
	local category = Config.Categories[definition.Category] or { Name = "", Color = Theme.Stroke }
	local card = make("TextButton", {
		Name = id,
		LayoutOrder = order,
		BackgroundColor3 = Theme.Background:Lerp(category.Color, CARD_BLEND),
		BackgroundTransparency = 0.1,
		AutoButtonColor = true,
		Text = "",
		BorderSizePixel = 0,
	}, parent)
	round(card, 0.1)
	local stroke = make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = category.Color,
		Thickness = 1,
		Transparency = 0.4,
	}, card)

	-- Category label in the top-left, in the category color.
	make("TextLabel", {
		Position = UDim2.fromScale(0.08, 0.06),
		Size = UDim2.fromScale(0.6, 0.14),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = string.upper(category.Name),
		TextColor3 = category.Color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)

	local iconHolder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromScale(0.45, 0.45),
		BackgroundTransparency = 1,
	}, card)
	Icons.Build(iconHolder, definition.Icon, Theme.Text, definition.Symbol)

	make("TextLabel", {
		Position = UDim2.fromScale(0.04, 0.72),
		Size = UDim2.fromScale(0.92, 0.2),
		BackgroundTransparency = 1,
		Font = Theme.FontBold,
		Text = definition.ShortName or definition.DisplayName,
		TextColor3 = Theme.Text,
		TextScaled = true,
	}, card)

	-- Mark for abilities already on the wheel.
	local equippedTag = make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(18, 14),
		BackgroundColor3 = category.Color,
		BackgroundTransparency = 0.1,
		Font = Theme.FontBold,
		Text = "✓",
		TextColor3 = Theme.Text,
		TextSize = 10,
		Visible = false,
	}, card)
	round(equippedTag, 0.5)

	self._cards[id] = { card = card, stroke = stroke, equippedTag = equippedTag, category = category }
	table.insert(self._connections, card.Activated:Connect(function()
		if self._onPick then
			self._onPick(id)
		end
	end))
end

-- Highlights the picked card and shows its details. nil clears both.
function SpellBook:SetPicked(id)
	for cardId, data in pairs(self._cards) do
		local picked = cardId == id
		data.stroke.Thickness = picked and 2 or 1
		data.stroke.Transparency = picked and 0 or 0.4
	end
	local definition = id and Config.Abilities[id]
	if not definition then
		self._detailName.Text = "Pick a spell"
		self._detailName.TextColor3 = Theme.Text
		self._detailDesc.Text = "Then click a wheel slot to equip it."
		self._detailStats.Text = ""
		return
	end
	local category = Config.Categories[definition.Category]
	self._detailName.Text = definition.DisplayName
	self._detailName.TextColor3 = category and category.Color or Theme.Text
	self._detailDesc.Text = definition.Description
	self._detailStats.Text = string.format("%s  ·  Cooldown %ds  ·  Duration %.1fs",
		category and category.Name or "", definition.Cooldown, definition.EffectDuration)
end

-- Marks the cards whose ability is currently equipped. `equipped` is a list of ids.
function SpellBook:SetEquipped(equipped)
	local set = {}
	for _, id in ipairs(equipped) do
		set[id] = true
	end
	for cardId, data in pairs(self._cards) do
		data.equippedTag.Visible = set[cardId] == true
	end
end

function SpellBook:SetVisible(visible)
	self._panel.Visible = visible
end

function SpellBook:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._panel:Destroy()
end

return SpellBook
