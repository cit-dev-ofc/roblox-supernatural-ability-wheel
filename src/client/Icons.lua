--[[
	Procedural ability icons, drawn with UI frames. No image assets are used, so
	there are no asset IDs to keep valid. Unknown kinds fall back to a text symbol.
]]
local Icons = {}

local function corner(parent, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
	return c
end

local function bar(parent, props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	for key, value in pairs(props) do
		frame[key] = value
	end
	frame.Parent = parent
	return frame
end

-- Three slanted streaks that fade out behind the leading one.
local function buildSpeed(container, color)
	for i = 0, 2 do
		local streak = bar(container, {
			Position = UDim2.fromScale(0.36 + i * 0.16, 0.5),
			Size = UDim2.fromScale(0.1, 0.56),
			Rotation = 18,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.1 + (2 - i) * 0.3,
		})
		corner(streak, 0.5)
	end
end

-- A ring with a focal dot: a hand held out in front, reduced to a sigil.
local function buildChoke(container, color)
	local ring = bar(container, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		BackgroundTransparency = 1,
	})
	corner(ring, 0.5)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = ring

	local dot = bar(container, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.2, 0.2),
		BackgroundColor3 = color,
	})
	corner(dot, 0.5)
end

-- Builds the icon of the given kind inside parent. Returns the container frame.
function Icons.Build(parent, kind, color, fallbackSymbol)
	local container = Instance.new("Frame")
	container.Name = "Icon"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = parent

	if kind == "speed" then
		buildSpeed(container, color)
	elseif kind == "choke" then
		buildChoke(container, color)
	else
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = fallbackSymbol or "?"
		label.TextColor3 = color
		label.TextScaled = true
		label.Parent = container
	end
	return container
end

-- A plus sign for empty slots, drawn as two thin bars.
function Icons.BuildPlus(parent, color)
	local container = Instance.new("Frame")
	container.Name = "Plus"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = parent

	bar(container, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.36, 0.05),
		BackgroundColor3 = color,
	})
	bar(container, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.05, 0.36),
		BackgroundColor3 = color,
	})
	return container
end

return Icons
