-- Shared UI palette and tween presets for the ability HUD and wheel.
-- Charcoal and black surfaces, restrained violet accents, light text.
local Theme = {
	Background = Color3.fromRGB(9, 8, 12), -- near-black, for backdrops and key caps
	Panel = Color3.fromRGB(24, 22, 30), -- charcoal surface for slots and panels
	PanelHover = Color3.fromRGB(40, 36, 50),
	Stroke = Color3.fromRGB(64, 54, 84), -- muted violet outline
	Accent = Color3.fromRGB(146, 110, 204), -- violet accent for selection and cooldown
	Target = Color3.fromRGB(235, 40, 52), -- red border on the slot chosen in edit mode
	AccentSoft =Color3.fromRGB(176, 150, 222), -- hover rim
	Text = Color3.fromRGB(238, 235, 244),
	TextDim = Color3.fromRGB(152, 146, 164),
	Ready = Color3.fromRGB(200, 188, 228),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}

Theme.Tween = {
	Hover = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Open = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

return Theme
