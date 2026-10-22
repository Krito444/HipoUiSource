-- Target Hunter interface for the current experience.
-- Controls call the server; the server applies owner/admin checks and validates combat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("TargetHunterRemote", 20)
if not remote then return end
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControlsOverview = require(Shared:WaitForChild("HipoControls"))
local LucideIcons = ControlsOverview.Icons

local COLORS = {
	panel = Color3.fromRGB(19, 20, 21),
	rail = Color3.fromRGB(15, 16, 17),
	card = Color3.fromRGB(24, 25, 27),
	row = Color3.fromRGB(27, 28, 30),
	line = Color3.fromRGB(45, 46, 48),
	text = Color3.fromRGB(242, 243, 244),
	muted = Color3.fromRGB(154, 156, 158),
	lime = Color3.fromRGB(190, 220, 35),
	limeHover = Color3.fromRGB(215, 239, 68),
	limeDark = Color3.fromRGB(92, 111, 19),
	limeDarkHover = Color3.fromRGB(112, 132, 24),
	hover = Color3.fromRGB(47, 49, 51),
	hoverStrong = Color3.fromRGB(57, 59, 61),
	control = Color3.fromRGB(39, 40, 42),
	danger = Color3.fromRGB(235, 83, 91),
	dangerHover = Color3.fromRGB(255, 112, 120),
}

local function make(className, parent, properties)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do object[key] = value end
	object.Parent = parent
	return object
end

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOGGLE_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SELECTION_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function animateTo(object, properties, tweenInfo)
	local tween = TweenService:Create(object, tweenInfo or HOVER_TWEEN, properties)
	tween:Play()
end

local function round(parent, radius)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius or 10)})
end

local function stroke(parent, color, transparency)
	make("UIStroke", parent, {Color = color or COLORS.line, Transparency = transparency or 0.25, Thickness = 1})
end

local gui = make("ScreenGui", LocalPlayer:WaitForChild("PlayerGui"), {
	Name = "TargetHunterGui",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
})

local scaler = make("UIScale", gui, {Scale = 1})
local panel = make("Frame", gui, {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(820, 520),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
})
round(panel, 16)
stroke(panel, Color3.fromRGB(78, 80, 83), 0.25)
make("UISizeConstraint", panel, {MinSize = Vector2.new(360, 300), MaxSize = Vector2.new(1000, 650)})
local visibilityScale = make("UIScale", panel, {Scale = 0.94})
local uiTargetVisible = false
local visibilityAnimationId = 0
local activeVisibilityTweens = {}
local VISIBILITY_OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local VISIBILITY_CLOSE_TWEEN = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local camera = workspace.CurrentCamera
local function updateScale()
	if not camera then return end
	scaler.Scale = math.clamp(math.min(camera.ViewportSize.X / 860, camera.ViewportSize.Y / 560), 0.45, 1)
end
updateScale()
if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

local function cancelVisibilityTweens()
	for _, tween in ipairs(activeVisibilityTweens) do
		tween:Cancel()
	end
	table.clear(activeVisibilityTweens)
end

local function setUIVisible(isVisible)
	if not gui.Parent then return end
	local shouldShow = isVisible == true
	if shouldShow == uiTargetVisible then return end

	uiTargetVisible = shouldShow
	visibilityAnimationId += 1
	local animationId = visibilityAnimationId
	cancelVisibilityTweens()

	if shouldShow then
		gui.Enabled = true
	end

	local tweenInfo = shouldShow and VISIBILITY_OPEN_TWEEN or VISIBILITY_CLOSE_TWEEN
	local scaleTween = TweenService:Create(visibilityScale, tweenInfo, {Scale = shouldShow and 1 or 0.94})
	local backgroundTween = TweenService:Create(panel, tweenInfo, {BackgroundTransparency = shouldShow and 0.04 or 0.2})
	activeVisibilityTweens = {scaleTween, backgroundTween}

	scaleTween.Completed:Connect(function(playbackState)
		if animationId ~= visibilityAnimationId then return end
		if not shouldShow and playbackState == Enum.PlaybackState.Completed and gui.Parent then
			gui.Enabled = false
		end
		if playbackState ~= Enum.PlaybackState.Cancelled then
			table.clear(activeVisibilityTweens)
		end
	end)

	scaleTween:Play()
	backgroundTween:Play()
end

local THEME_PALETTES = {
	Dark = {
		panel = Color3.fromRGB(19, 20, 21), rail = Color3.fromRGB(15, 16, 17),
		card = Color3.fromRGB(24, 25, 27), row = Color3.fromRGB(27, 28, 30),
		line = Color3.fromRGB(45, 46, 48), text = Color3.fromRGB(255, 255, 255),
		muted = Color3.fromRGB(154, 156, 158), lime = Color3.fromRGB(255, 255, 255),
		limeHover = Color3.fromRGB(255, 255, 255), limeDark = Color3.fromRGB(70, 72, 75),
		limeDarkHover = Color3.fromRGB(89, 91, 95), hover = Color3.fromRGB(47, 49, 51),
		hoverStrong = Color3.fromRGB(57, 59, 61), danger = Color3.fromRGB(235, 83, 91),
		dangerHover = Color3.fromRGB(255, 112, 120), control = Color3.fromRGB(39, 40, 42),
	},
	Light = {
		panel = Color3.fromRGB(238, 240, 243), rail = Color3.fromRGB(246, 247, 249),
		card = Color3.fromRGB(255, 255, 255), row = Color3.fromRGB(245, 247, 249),
		line = Color3.fromRGB(213, 217, 222), text = Color3.fromRGB(34, 37, 41),
		muted = Color3.fromRGB(105, 112, 120), lime = Color3.fromRGB(135, 170, 20),
		limeHover = Color3.fromRGB(156, 188, 34), limeDark = Color3.fromRGB(91, 116, 14),
		limeDarkHover = Color3.fromRGB(107, 134, 18), hover = Color3.fromRGB(226, 230, 234),
		hoverStrong = Color3.fromRGB(216, 220, 225), danger = Color3.fromRGB(200, 54, 64),
		dangerHover = Color3.fromRGB(219, 71, 81), control = Color3.fromRGB(238, 241, 244),
	},
	Ocean = {
		panel = Color3.fromRGB(13, 20, 27), rail = Color3.fromRGB(10, 16, 22),
		card = Color3.fromRGB(20, 30, 40), row = Color3.fromRGB(25, 38, 50),
		line = Color3.fromRGB(46, 62, 76), text = Color3.fromRGB(228, 240, 246),
		muted = Color3.fromRGB(146, 169, 182), lime = Color3.fromRGB(46, 190, 210),
		limeHover = Color3.fromRGB(88, 213, 228), limeDark = Color3.fromRGB(17, 80, 91),
		limeDarkHover = Color3.fromRGB(27, 100, 114), hover = Color3.fromRGB(35, 50, 62),
		hoverStrong = Color3.fromRGB(46, 62, 75), danger = Color3.fromRGB(235, 83, 91),
		dangerHover = Color3.fromRGB(255, 112, 120), control = Color3.fromRGB(31, 44, 56),
	},
	Violet = {
		panel = Color3.fromRGB(20, 18, 27), rail = Color3.fromRGB(15, 13, 21),
		card = Color3.fromRGB(29, 26, 38), row = Color3.fromRGB(35, 31, 46),
		line = Color3.fromRGB(60, 53, 75), text = Color3.fromRGB(243, 240, 249),
		muted = Color3.fromRGB(164, 155, 180), lime = Color3.fromRGB(178, 124, 255),
		limeHover = Color3.fromRGB(203, 165, 255), limeDark = Color3.fromRGB(82, 55, 121),
		limeDarkHover = Color3.fromRGB(102, 69, 145), hover = Color3.fromRGB(47, 42, 60),
		hoverStrong = Color3.fromRGB(60, 54, 74), danger = Color3.fromRGB(235, 83, 91),
		dangerHover = Color3.fromRGB(255, 112, 120), control = Color3.fromRGB(43, 39, 55),
	},
	Sunset = {
		panel = Color3.fromRGB(28, 19, 20), rail = Color3.fromRGB(21, 14, 15),
		card = Color3.fromRGB(38, 25, 25), row = Color3.fromRGB(46, 30, 29),
		line = Color3.fromRGB(79, 50, 45), text = Color3.fromRGB(250, 239, 233),
		muted = Color3.fromRGB(190, 155, 143), lime = Color3.fromRGB(255, 145, 80),
		limeHover = Color3.fromRGB(255, 174, 121), limeDark = Color3.fromRGB(130, 61, 31),
		limeDarkHover = Color3.fromRGB(153, 75, 37), hover = Color3.fromRGB(63, 39, 37),
		hoverStrong = Color3.fromRGB(78, 47, 42), danger = Color3.fromRGB(235, 83, 91),
		dangerHover = Color3.fromRGB(255, 112, 120), control = Color3.fromRGB(52, 34, 33),
	},
	Sky = {
		panel = Color3.fromRGB(8, 27, 56), rail = Color3.fromRGB(5, 17, 39),
		card = Color3.fromRGB(13, 43, 83), row = Color3.fromRGB(18, 59, 111),
		line = Color3.fromRGB(33, 90, 148), text = Color3.fromRGB(228, 240, 246),
		muted = Color3.fromRGB(146, 169, 182), lime = Color3.fromRGB(0, 158, 255),
		limeHover = Color3.fromRGB(51, 181, 255), limeDark = Color3.fromRGB(7, 86, 179),
		limeDarkHover = Color3.fromRGB(6, 116, 220), hover = Color3.fromRGB(25, 74, 126),
		hoverStrong = Color3.fromRGB(35, 94, 153), danger = Color3.fromRGB(235, 83, 91),
		dangerHover = Color3.fromRGB(255, 112, 120), control = Color3.fromRGB(16, 54, 102),
	},
}

local activeThemeName = "Dark"

local THEME_ROLE_ATTRIBUTE_PREFIX = "TargetHunterThemeRole_"

local function applyTheme(themeName)
	local palette = THEME_PALETTES[themeName]
	if not palette then return false end

	local overviewRoles = {
		card = "card", line = "line", text = "text", muted = "muted", lime = "lime",
		limeDark = "limeDark", control = "control", hover = "hoverStrong", danger = "danger",
	}
	local colorRoles = {}
	local function addColorRole(color, role)
		if typeof(color) ~= "Color3" then return end
		for _, entry in ipairs(colorRoles) do
			if entry.color == color then return end
		end
		table.insert(colorRoles, {color = color, role = role})
	end
	for role, color in pairs(COLORS) do
		addColorRole(color, role)
	end
	for role, color in pairs(ControlsOverview.Theme) do
		addColorRole(color, overviewRoles[role] or role)
	end
	local function roleForColor(color)
		for _, entry in ipairs(colorRoles) do
			if entry.color == color then return entry.role end
		end
	end

	local function applyColorProperty(object, property)
		local currentColor = object[property]
		if typeof(currentColor) ~= "Color3" then return end

		local attributeName = THEME_ROLE_ATTRIBUTE_PREFIX .. property
		local role = object:GetAttribute(attributeName)
		if type(role) ~= "string" or palette[role] == nil then
			role = roleForColor(currentColor)
			if not role or palette[role] == nil then return end
			object:SetAttribute(attributeName, role)
		end
		object[property] = palette[role]
	end

	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("GuiObject") then
			applyColorProperty(object, "BackgroundColor3")
		end
		if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
			applyColorProperty(object, "TextColor3")
			applyColorProperty(object, "TextStrokeColor3")
			if object:IsA("TextBox") then applyColorProperty(object, "PlaceholderColor3") end
		end
		if object:IsA("ImageLabel") or object:IsA("ImageButton") then
			applyColorProperty(object, "ImageColor3")
		elseif object:IsA("ScrollingFrame") then
			applyColorProperty(object, "ScrollBarImageColor3")
		elseif object:IsA("UIStroke") then
			applyColorProperty(object, "Color")
		end
	end

	for role, color in pairs(palette) do
		if COLORS[role] ~= nil then COLORS[role] = color end
	end
	ControlsOverview.SetThemePalette(palette, overviewRoles)
	activeThemeName = themeName
	return true
end

local rail = make("Frame", panel, {
	Name = "NavigationRail",
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(0, 48, 1, -16),
	BackgroundColor3 = COLORS.rail,
	BorderSizePixel = 0,
})
round(rail, 13)
stroke(rail, COLORS.line, 0.55)

local logo = LucideIcons.Create(rail, "crosshair", {
	Name = "TargetHunterLogo",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.fromOffset(20, 20),
	Color = COLORS.lime,
})

make("Frame", rail, {
	Name = "NavDivider",
	Position = UDim2.new(0, 5, 0, 50),
	Size = UDim2.new(1, -10, 0, 1),
	BackgroundColor3 = COLORS.line,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
})

local navButtons = {}
local navIconImages = {}
local navHovered = {}
local navIcons = {"swords", "wind", "target", "search", "settings"}
local selectedNavIndex = 1

local function updateNavButton(index, isSelectionChange)
	local button = navButtons[index]
	if not button then return end
	local selected = index == selectedNavIndex
	local hovered = navHovered[index]
	local background = selected and (hovered and COLORS.limeDarkHover or COLORS.limeDark)
		or (hovered and COLORS.hover or COLORS.rail)
	local textColor = selected and (hovered and COLORS.limeHover or COLORS.lime)
		or (hovered and COLORS.text or COLORS.muted)
	animateTo(button, {BackgroundColor3 = background, TextColor3 = textColor}, isSelectionChange and SELECTION_TWEEN or nil)
	if navIconImages[index] then
		animateTo(navIconImages[index], {ImageColor3 = textColor}, isSelectionChange and SELECTION_TWEEN or nil)
	end
end

local activeIndicator = make("Frame", rail, {
	Name = "ActiveIndicator",
	Position = UDim2.new(0, 1, 0, 64 + 8),
	Size = UDim2.fromOffset(3, 18),
	BackgroundColor3 = COLORS.lime,
	BorderSizePixel = 0,
	ZIndex = 2,
})
round(activeIndicator, 2)

for index, icon in ipairs(navIcons) do
	local button = make("TextButton", rail, {
		Position = UDim2.fromOffset(7, 64 + (index - 1) * 43),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = index == selectedNavIndex and COLORS.limeDark or COLORS.rail,
		BorderSizePixel = 0, Text = "",
		TextColor3 = index == selectedNavIndex and COLORS.lime or COLORS.muted,
		AutoButtonColor = false,
	})
	round(button, 10)
	navButtons[index] = button
	navIconImages[index] = LucideIcons.Create(button, icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		Color = index == selectedNavIndex and COLORS.lime or COLORS.muted,
	})
	navHovered[index] = false
	button.MouseEnter:Connect(function()
		navHovered[index] = true
		updateNavButton(index)
	end)
	button.MouseLeave:Connect(function()
		navHovered[index] = false
		updateNavButton(index)
	end)
	button.Activated:Connect(function()
		selectedNavIndex = index
		animateTo(activeIndicator, {
			Position = UDim2.new(0, 1, 0, 64 + (index - 1) * 43 + 8),
		}, SELECTION_TWEEN)
		for n = 1, #navIcons do updateNavButton(n, true) end
	end)
end

local top = make("Frame", panel, {
	Position = UDim2.fromOffset(64, 8), Size = UDim2.new(1, -72, 0, 42),
	BackgroundTransparency = 1,
})

local title = make("TextLabel", top, {
	Position = UDim2.fromOffset(12, 3), Size = UDim2.fromOffset(170, 34),
	BackgroundTransparency = 1, Text = "TARGET HUNTER",
	TextColor3 = COLORS.muted, Font = Enum.Font.GothamMedium, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local tabs = {}
local pages = {}
local activeTab = "Rage"
local tabNames = {"Rage", "Legit", "Skill", "Controls"}
for index, name in ipairs(tabNames) do
	local x = 280 + (index - 1) * 62
	local button = make("TextButton", top, {
		Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(58, 34),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Text = name, TextColor3 = name == activeTab and COLORS.lime or COLORS.muted,
		Font = Enum.Font.GothamMedium, TextSize = 14, AutoButtonColor = false,
	})
	local underline = make("Frame", button, {
		Position = UDim2.new(0.18, 0, 1, -3), Size = UDim2.new(0.64, 0, 0, 2),
		BackgroundColor3 = COLORS.lime, BorderSizePixel = 0,
		Visible = name == activeTab,
	})
	round(underline, 2)
	tabs[name] = {button = button, underline = underline}
end

local body = make("Frame", panel, {
	Position = UDim2.fromOffset(64, 54), Size = UDim2.new(1, -76, 1, -64),
	BackgroundTransparency = 1,
})

local function makeSectionPage(name, visible)
	return make("CanvasGroup", body, {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = visible and 0 or 1,
		Visible = visible,
	})
end

local ragePage = makeSectionPage("RagePage", true)
local legitPage = makeSectionPage("LegitPage", false)
local skillPage = makeSectionPage("SkillPage", false)
local controlsSectionPage = makeSectionPage("ControlsSectionPage", false)
local controlsPage = ControlsOverview.Build(controlsSectionPage, {
	OnKeybindPressed = function()
		setUIVisible(not uiTargetVisible)
	end,
	OnThemeChanged = applyTheme,
})
controlsPage.Visible = true

local function card(parent, name, position, size)
	local frame = make("Frame", parent, {
		Name = name, Position = position, Size = size,
		BackgroundColor3 = COLORS.card, BorderSizePixel = 0,
	})
	round(frame, 15)
	stroke(frame, COLORS.line, 0.45)
	return frame
end

local leftCard = card(ragePage, "TargetHunterCard", UDim2.fromOffset(0, 0), UDim2.new(0.49, -6, 1, 0))
local rightX = UDim2.new(0.49, 6, 0, 0)
local rightWidth = UDim2.new(0.51, -6, 0, 0)
local latchCard = card(ragePage, "LatchCard", rightX, UDim2.new(rightWidth.X.Scale, rightWidth.X.Offset, 0, 190))
local auraCard = card(ragePage, "AuraCard", UDim2.new(rightX.X.Scale, rightX.X.Offset, 0, 202), UDim2.new(rightWidth.X.Scale, rightWidth.X.Offset, 1, -202))

local function cardTitle(parent, text)
	return make("TextLabel", parent, {
		Position = UDim2.fromOffset(14, 7), Size = UDim2.new(1, -28, 0, 18),
		BackgroundTransparency = 1, Text = text,
		TextColor3 = COLORS.muted, Font = Enum.Font.GothamMedium, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end
cardTitle(leftCard, "TARGET HUNTER")
cardTitle(latchCard, "PLAYER LATCH & AUTO KILL")
cardTitle(auraCard, "KILL AURA")

local localSettings = {
	stickyLock = true, follow = false, autoKill = false, killAura = false,
	latchDistance = 3, attackRange = 40, attackInterval = 0.75,
	targetMethod = "Nearest", priorityCriteria = "Distance", attackMethod = "Nearest",
}
local targets = {}
local selectedTargetId = 0
local selectedTargetText = "Select..."

local function sendOption(key, value)
	localSettings[key] = value
	remote:FireServer("SetOption", {key = key, value = value})
end

local function row(parent, y, height, labelText, detailText)
	local holder = make("Frame", parent, {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
	})
	make("TextLabel", holder, {
		Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -150, 0, 20),
		BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if detailText then
		make("TextLabel", holder, {
			Position = UDim2.fromOffset(14, 27), Size = UDim2.new(1, -150, 0, 18),
			BackgroundTransparency = 1, Text = detailText, TextColor3 = COLORS.muted,
			Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if height > 38 then
		make("Frame", holder, {
			Position = UDim2.new(0, 12, 1, -1), Size = UDim2.new(1, -24, 0, 1),
			BackgroundColor3 = COLORS.line, BackgroundTransparency = 0.45, BorderSizePixel = 0,
		})
	end
	return holder
end

local function pillButton(parent, text, options)
	options = options or {}
	local style = options.Style or (options.Primary == true and "filled" or "outline")
	assert(type(style) == "string", "Button Style must be outline, filled, ghost, or soft")
	style = string.lower(style)
	assert(style == "outline" or style == "filled" or style == "ghost" or style == "soft",
		"Button Style must be outline, filled, ghost, or soft")

	local function resolveColor(value, fallback)
		if typeof(value) == "Color3" then return value end
		if type(value) == "string" then
			local role = string.lower(value)
			for name, color in pairs(COLORS) do
				if string.lower(name) == role then return color end
			end
		end
		return fallback
	end

	local function getAccent()
		return options.Danger == true and COLORS.danger or COLORS.lime
	end
	local function getHoverAccent()
		return options.Danger == true and COLORS.dangerHover or COLORS.limeHover
	end
	local buttonText = tostring(text == nil and "Run" or text)
	local disabled = options.Disabled == true
	local hovered = false
	local clickActive = false
	local clickToken = 0
	if options.Hover ~= nil then assert(type(options.Hover) == "table", "Button Hover must be a table") end
	if options.Click ~= nil then assert(type(options.Click) == "table", "Button Click must be a table") end

	local button = make("TextButton", parent, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(116, 30), BackgroundColor3 = COLORS.control,
		BorderSizePixel = 0, Text = "", TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium, TextSize = 11, AutoButtonColor = false,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = options.ZIndex or 1,
	})
	round(button, 9)
	local iconName = type(options.ButtonIcon) == "string" and LucideIcons.Has(options.ButtonIcon)
		and options.ButtonIcon or nil
	local buttonLabel = make("TextLabel", button, {
		Name = "ButtonLabel",
		Position = iconName and UDim2.fromOffset(30, 0) or UDim2.fromOffset(0, 0),
		Size = iconName and UDim2.new(1, -37, 1, 0) or UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = buttonText,
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = iconName and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Active = false,
		Selectable = false,
		ZIndex = button.ZIndex + 1,
	})
	local buttonIcon
	local iconScale
	if iconName then
		buttonIcon = LucideIcons.Create(button, iconName, {
			Name = "ButtonIcon",
			Position = UDim2.fromOffset(8, 7),
			Size = UDim2.fromOffset(16, 16),
			Color = COLORS.text,
			ZIndex = button.ZIndex + 1,
		})
		if buttonIcon then iconScale = make("UIScale", buttonIcon, {Scale = 1}) end
	end

	local outline = make("UIStroke", button, {
		Color = COLORS.line,
		Thickness = 1,
		Transparency = style == "outline" and 0.18 or 1,
	})

	local function getColors(isHovered)
		local accent = getAccent()
		local hoverAccent = getHoverAccent()
		local outlineHoverColor = resolveColor(options.HoverColor, accent)
		local outlineHoverFill = resolveColor(options.HoverFill, COLORS.hoverStrong)
		local background, backgroundTransparency, textColor, borderColor, borderTransparency
		if style == "outline" then
			background = isHovered and outlineHoverFill or COLORS.control
			backgroundTransparency = isHovered and 0 or 1
			textColor = isHovered and activeThemeName ~= "Dark" and outlineHoverColor or COLORS.text
			borderColor = isHovered and outlineHoverColor or COLORS.line
			borderTransparency = isHovered and 0 or 0.18
		elseif style == "filled" then
			background = isHovered and hoverAccent or accent
			backgroundTransparency = 0
			textColor = COLORS.panel
			borderColor = background
			borderTransparency = 1
		elseif style == "ghost" then
			background = isHovered and COLORS.hoverStrong or COLORS.control
			backgroundTransparency = isHovered and 0 or 1
			textColor = isHovered and hoverAccent or accent
			borderColor = accent
			borderTransparency = 1
		else
			background = accent:Lerp(COLORS.panel, isHovered and 0.72 or 0.82)
			backgroundTransparency = 0
			textColor = isHovered and hoverAccent or accent
			borderColor = accent
			borderTransparency = 1
		end
		if disabled then
			background = background:Lerp(COLORS.panel, 0.48)
			textColor = textColor:Lerp(COLORS.muted, 0.48)
			borderColor = borderColor:Lerp(COLORS.muted, 0.48)
			backgroundTransparency = math.min(backgroundTransparency, style == "outline" and 0.25 or 0.12)
			borderTransparency = style == "outline" and 0.55 or 1
		end
		return background, backgroundTransparency, textColor, borderColor, borderTransparency
	end

	local function getIconColor(isHovered, textColor)
		if style == "outline" and activeThemeName == "Dark" and isHovered and options.HoverColor == nil then
			return getAccent()
		end
		return textColor
	end

	local function renderStyle()
		local background, backgroundTransparency, textColor, borderColor, borderTransparency = getColors(hovered)
		local iconColor = getIconColor(hovered, textColor)
		animateTo(button, {
			BackgroundColor3 = background,
			BackgroundTransparency = backgroundTransparency,
		})
		animateTo(buttonLabel, {
			TextColor3 = textColor,
			TextTransparency = disabled and 0.25 or 0,
		})
		animateTo(outline, {Color = borderColor, Transparency = borderTransparency})
		if buttonIcon then
			animateTo(buttonIcon, {ImageColor3 = iconColor, ImageTransparency = disabled and 0.35 or 0})
		end
	end

	local function resetAnimation(animated)
		buttonLabel.Text = buttonText
		if not buttonIcon then return end
		local _, _, textColor = getColors(hovered)
		local iconColor = getIconColor(hovered, textColor)
		LucideIcons.Set(buttonIcon, iconName, iconColor)
		if animated then
			animateTo(buttonIcon, {Rotation = 0})
			animateTo(iconScale, {Scale = 1})
		else
			buttonIcon.Rotation = 0
			iconScale.Scale = 1
		end
	end

	local function applyAnimation(spec, isClick)
		if type(spec) ~= "table" then return end
		if spec.Text ~= nil then buttonLabel.Text = tostring(spec.Text) end
		if not buttonIcon then return end
		if type(spec.Icon) == "string" and LucideIcons.Has(spec.Icon) then
			LucideIcons.Set(buttonIcon, spec.Icon)
		end
		local duration = isClick and 0.38 or 0.14
		if tonumber(spec.Scale) then
			animateTo(iconScale, {Scale = math.clamp(tonumber(spec.Scale), 0.1, 3)}, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end
		if tonumber(spec.Rotate) then
			local rotation = isClick and buttonIcon.Rotation + tonumber(spec.Rotate) or tonumber(spec.Rotate)
			animateTo(buttonIcon, {Rotation = rotation}, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end
	end

	local function renderAnimation()
		if hovered then
			resetAnimation(false)
			applyAnimation(options.Hover, false)
		else
			resetAnimation(true)
		end
	end

	renderStyle()
	local tooltipText = disabled and options.DisabledReason or options.Tooltip
	local tooltip
	if type(tooltipText) == "string" and tooltipText ~= "" then
		tooltip = make("TextLabel", parent, {
			Name = "ButtonTooltip",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -14, 0, 1),
			Size = UDim2.fromOffset(190, 28),
			BackgroundColor3 = Color3.fromRGB(39, 40, 42),
			BorderSizePixel = 0,
			Text = tooltipText,
			TextColor3 = COLORS.text,
			Font = Enum.Font.Gotham,
			TextSize = 10,
			TextWrapped = true,
			Visible = false,
			ZIndex = button.ZIndex + 5,
		})
		round(tooltip, 6)
		stroke(tooltip, COLORS.line, 0.2)
	end
	local function showTooltip()
		if tooltip then tooltip.Visible = true end
	end
	local function hideTooltip()
		if tooltip then tooltip.Visible = false end
	end

	button.Active = not disabled
	button.Selectable = not disabled
	button.MouseEnter:Connect(function()
		hovered = true
		renderStyle()
		showTooltip()
		if not clickActive then renderAnimation() end
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		renderStyle()
		hideTooltip()
		if not clickActive then renderAnimation() end
	end)
	if disabled and tooltip then
		parent.MouseEnter:Connect(showTooltip)
		parent.MouseLeave:Connect(hideTooltip)
	end
	button.Activated:Connect(function()
		if disabled then return end
		if type(options.Click) == "table" then
			clickToken = clickToken + 1
			local token = clickToken
			clickActive = true
			resetAnimation(false)
			applyAnimation(options.Click, true)
			task.delay(math.max(tonumber(options.Click.Hold) or 0.45, 0), function()
				if button.Parent and token == clickToken then
					clickActive = false
					renderAnimation()
				end
			end)
		end
		if type(options.Callback) == "function" then task.spawn(options.Callback) end
	end)

	local function setText(newText)
		buttonText = tostring(newText == nil and "" or newText)
		clickToken = clickToken + 1
		clickActive = false
		renderAnimation()
		return buttonText
	end
	return button, setText
end

local activeDropdownCloser

local function optionRow(parent, y, labelText, detailText, options, key, initial)
	local holder = row(parent, y, 58, labelText, detailText)
	assert(type(options) == "table" and #options > 0, "Dropdown options must be a non-empty array")
	local index = table.find(options, initial) or 1
	local button, setButtonText = pillButton(holder, options[index], {
		ButtonIcon = "chevron-down",
		ZIndex = 12,
		Hover = {Scale = 1.06},
		Click = {Scale = 0.94},
	})

	local menu = make("ScrollingFrame", holder, {
		Name = "DropdownOptions",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 58),
		Size = UDim2.fromOffset(116, math.min(#options, 4) * 28 + 8),
		BackgroundColor3 = COLORS.row,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = COLORS.lime,
		Active = true,
		Visible = false,
		ZIndex = 14,
	})
	round(menu, 8)
	stroke(menu, COLORS.line, 0.2)
	make("UIListLayout", menu, {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local open = false
	local optionButtons = {}
	local originalZIndices = {}
	local holderZIndex = holder.ZIndex
	local function setDropdownLayer(enabled)
		holder.ZIndex = enabled and 20 or holderZIndex
		for _, descendant in ipairs(holder:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				if originalZIndices[descendant] == nil then
					originalZIndices[descendant] = descendant.ZIndex
				end
				local originalZIndex = originalZIndices[descendant]
				descendant.ZIndex = enabled and originalZIndex + 20 or originalZIndex
			end
		end
	end
	local function renderOptions()
		for optionIndex, optionButton in ipairs(optionButtons) do
			optionButton.BackgroundColor3 = optionIndex == index and COLORS.limeDark or COLORS.row
			optionButton.TextColor3 = optionIndex == index and COLORS.lime or COLORS.text
		end
	end
	local function setOpen(value)
		local shouldOpen = value == true
		if shouldOpen then
			if activeDropdownCloser and activeDropdownCloser ~= setOpen then
				activeDropdownCloser(false)
			end
			activeDropdownCloser = setOpen
		elseif activeDropdownCloser == setOpen then
			activeDropdownCloser = nil
		end
		open = shouldOpen
		menu.Visible = open
		if open then
			menu.CanvasPosition = Vector2.zero
		end
		setDropdownLayer(open)
	end

	for optionIndex, option in ipairs(options) do
		local thisIndex = optionIndex
		local optionButton = make("TextButton", menu, {
			Name = "Option" .. tostring(optionIndex),
			LayoutOrder = optionIndex,
			Size = UDim2.new(1, -6, 0, 26),
			BackgroundColor3 = optionIndex == index and COLORS.limeDark or COLORS.row,
			BorderSizePixel = 0,
			Text = tostring(option),
			TextColor3 = optionIndex == index and COLORS.lime or COLORS.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutoButtonColor = false,
			ZIndex = 15,
		})
		optionButtons[thisIndex] = optionButton
		round(optionButton, 6)
		optionButton.MouseEnter:Connect(function()
			animateTo(optionButton, {BackgroundColor3 = thisIndex == index and COLORS.limeDarkHover or COLORS.hoverStrong})
		end)
		optionButton.MouseLeave:Connect(function()
			animateTo(optionButton, {BackgroundColor3 = thisIndex == index and COLORS.limeDark or COLORS.row})
		end)
		optionButton.Activated:Connect(function()
			index = thisIndex
			setButtonText(options[index])
			renderOptions()
			setOpen(false)
			sendOption(key, options[index])
		end)
	end
	button.Activated:Connect(function() setOpen(not open) end)

	local function contains(guiObject, point)
		local position, size = guiObject.AbsolutePosition, guiObject.AbsoluteSize
		return point.X >= position.X and point.X <= position.X + size.X
			and point.Y >= position.Y and point.Y <= position.Y + size.Y
	end
	UserInputService.InputBegan:Connect(function(input)
		if not open or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		if not contains(button, input.Position) and not contains(menu, input.Position) then
			setOpen(false)
		end
	end)
	return holder
end

local function actionRow(parent, y, labelText, detailText, buttonText, action, buttonIcon, clickAnimation)
	local holder = row(parent, y, detailText and 55 or 48, labelText, detailText)
	local button = pillButton(holder, buttonText, {
		ButtonIcon = buttonIcon,
		Hover = {Scale = 1.06},
		Click = clickAnimation or {Scale = 0.94},
	})
	button.Activated:Connect(function() remote:FireServer(action) end)
	return holder
end

local function toggleRow(parent, y, labelText, detailText, key, initial)
	local holder = row(parent, y, 48, labelText, detailText)
	local toggle = make("TextButton", holder, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(38, 21), BackgroundColor3 = initial and COLORS.limeDark or Color3.fromRGB(51, 52, 54),
		BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	})
	round(toggle, 11)
	local function knobPosition(isEnabled, size)
		local centerX = isEnabled and 27 or 11
		return UDim2.new(0, centerX - size / 2, 0.5, -size / 2)
	end
	local knob = make("Frame", toggle, {
		Position = knobPosition(initial, 14),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = initial and COLORS.lime or Color3.fromRGB(235, 236, 237),
		BorderSizePixel = 0,
	})
	round(knob, 7)
	local hovered = false
	local function updateToggle()
		local background = initial and (hovered and COLORS.limeDarkHover or COLORS.limeDark)
			or (hovered and COLORS.hoverStrong or Color3.fromRGB(51, 52, 54))
		local knobSize = hovered and 16 or 14
		TweenService:Create(toggle, TOGGLE_TWEEN, {BackgroundColor3 = background}):Play()
		TweenService:Create(knob, TOGGLE_TWEEN, {
			Position = knobPosition(initial, knobSize),
			Size = UDim2.fromOffset(knobSize, knobSize),
			BackgroundColor3 = initial and COLORS.limeHover or Color3.fromRGB(235, 236, 237),
		}):Play()
	end
	toggle.MouseEnter:Connect(function()
		hovered = true
		updateToggle()
	end)
	toggle.MouseLeave:Connect(function()
		hovered = false
		updateToggle()
	end)
	toggle.Activated:Connect(function()
		initial = not initial
		updateToggle()
		sendOption(key, initial)
	end)
	return holder
end

local function sliderRow(parent, y, labelText, minValue, maxValue, step, initial, suffix, key)
	local holder = make("Frame", parent, {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
	})
	make("TextLabel", holder, {
		Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -116, 0, 20),
		BackgroundTransparency = 1, Text = labelText, TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local valueLabel = make("TextLabel", holder, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 4),
		Size = UDim2.fromOffset(82, 23), BackgroundColor3 = Color3.fromRGB(39, 40, 42),
		BorderSizePixel = 0, TextColor3 = COLORS.text, Font = Enum.Font.GothamMedium,
		TextSize = 11, Text = "", TextXAlignment = Enum.TextXAlignment.Center,
	})
	round(valueLabel, 8)
	local track = make("TextButton", holder, {
		Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 0, 4),
		BackgroundColor3 = Color3.fromRGB(48, 49, 51), BorderSizePixel = 0,
		Text = "", AutoButtonColor = false,
	})
	round(track, 3)
	local fill = make("Frame", track, {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COLORS.lime, BorderSizePixel = 0})
	round(fill, 3)
	local knob = make("Frame", track, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = COLORS.lime, BorderSizePixel = 0,
	})
	round(knob, 7)
	local knobHovered = false
	local dragging = false
	local function renderKnobHover()
		local enlarged = knobHovered and not dragging
		animateTo(knob, {
			Size = UDim2.fromOffset(enlarged and 17 or 14, enlarged and 17 or 14),
			BackgroundColor3 = enlarged and COLORS.limeHover or COLORS.lime,
		})
	end
	knob.MouseEnter:Connect(function()
		knobHovered = true
		renderKnobHover()
	end)
	knob.MouseLeave:Connect(function()
		knobHovered = false
		renderKnobHover()
	end)
	local value = initial
	local function formatValue(v)
		if step < 1 then return string.format("%.2f%s", v, suffix) end
		return tostring(math.floor(v + 0.5)) .. suffix
	end
	local function render()
		local alpha = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = formatValue(value)
	end
	local function setAt(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local raw = minValue + (maxValue - minValue) * alpha
		value = minValue + math.floor((raw - minValue) / step + 0.5) * step
		value = math.clamp(value, minValue, maxValue)
		render()
		sendOption(key, value)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			renderKnobHover()
			setAt(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setAt(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			renderKnobHover()
		end
	end)
	render()
	return holder
end

optionRow(leftCard, 25, "Target Selection Method", "How targets are selected for attack.", {"Nearest", "Lowest HP"}, "targetMethod", localSettings.targetMethod)
optionRow(leftCard, 83, "Priority Criteria", "Filter priority: distance or health.", {"Distance", "Health"}, "priorityCriteria", localSettings.priorityCriteria)
toggleRow(leftCard, 141, "Sticky Target Lock (Lock Until Dead)", "Keep the selected target while they are alive.", "stickyLock", true)
actionRow(leftCard, 189, "Switch to Next Target", "Cycle to the next eligible target.", "Next", "SwitchTarget", "skip-forward", {Scale = 0.9})
local selectRow = row(leftCard, 244, 55, "Select Target Player", "Choose a player in this server.")
local targetButton, setTargetButtonText = pillButton(selectRow, selectedTargetText, {
	ButtonIcon = "chevron-down",
	Hover = {Scale = 1.06},
	Click = {Scale = 0.94},
})
targetButton.Activated:Connect(function()
	if #targets == 0 then
		remote:FireServer("RefreshPlayers")
		setTargetButtonText("No players")
		return
	end
	local index = 0
	for i, target in ipairs(targets) do if target.userId == selectedTargetId then index = i break end end
	local nextTarget = targets[(index % #targets) + 1]
	selectedTargetId = nextTarget.userId
	selectedTargetText = nextTarget.displayName or nextTarget.name
	setTargetButtonText(selectedTargetText)
	remote:FireServer("SetTarget", selectedTargetId)
end)
actionRow(leftCard, 299, "Refresh Target Player List", "Refresh player list in server.", "Refresh", "RefreshPlayers", "refresh-cw", {Rotate = 360})
actionRow(leftCard, 347, "Teleport to Target", "Move to the selected player.", "Teleport", "TeleportToTarget", "map-pin", {Scale = 0.9})
make("TextLabel", leftCard, {
	Position = UDim2.new(0, 14, 1, -28), Size = UDim2.new(1, -28, 0, 16),
	BackgroundTransparency = 1, Text = "OWNER / ADMIN TEST PANEL",
	TextColor3 = COLORS.muted, Font = Enum.Font.GothamMedium, TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
})

toggleRow(latchCard, 25, "Smooth Follow & Latch to Player", "Smoothly follow and stay behind target.", "follow", false)
toggleRow(latchCard, 73, "Auto Kill Target", "Repeatedly attack the selected target.", "autoKill", false)
sliderRow(latchCard, 121, "Latch Distance", 1, 20, 1, 3, " studs", "latchDistance")

toggleRow(auraCard, 25, "Kill Aura", "Attack eligible enemies in range.", "killAura", false)
optionRow(auraCard, 73, "Attack Method", "Choose the next target by priority.", {"Nearest", "Lowest HP"}, "attackMethod", localSettings.attackMethod)
sliderRow(auraCard, 131, "Attack Range", 1, 40, 1, 40, " studs", "attackRange")
sliderRow(auraCard, 195, "Attack Speed (Interval)", 0.35, 2, 0.05, 0.75, " s", "attackInterval")

local function addPlaceholderLabel(parent)
	make("TextLabel", parent, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 70), BackgroundTransparency = 1,
		Text = "Mode de test prêt à être configuré.", TextColor3 = COLORS.muted,
		Font = Enum.Font.Gotham, TextSize = 15, TextWrapped = true,
	})
end
addPlaceholderLabel(legitPage)
addPlaceholderLabel(skillPage)

local function updateTabs()
	for name, entry in pairs(tabs) do
		local selected = name == activeTab
		local textColor = selected and (entry.hovered and COLORS.limeHover or COLORS.lime)
			or (entry.hovered and COLORS.text or COLORS.muted)
		animateTo(entry.button, {TextColor3 = textColor})
		entry.underline.Visible = selected
	end
end

local sectionPages = {
	Rage = ragePage,
	Legit = legitPage,
	Skill = skillPage,
	Controls = controlsSectionPage,
}
local sectionTweens = {}
local sectionTransitionId = 0
local SECTION_ENTER_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local SECTION_EXIT_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

local function cancelSectionTweens()
	for _, tween in ipairs(sectionTweens) do
		tween:Cancel()
	end
	table.clear(sectionTweens)
end

local function selectSection(name)
	if name == activeTab then return end
	local oldPage = sectionPages[activeTab]
	local newPage = sectionPages[name]
	if not oldPage or not newPage then return end

	sectionTransitionId += 1
	local transitionId = sectionTransitionId
	cancelSectionTweens()

	for _, page in pairs(sectionPages) do
		if page ~= oldPage and page ~= newPage then
			page.Visible = false
			page.GroupTransparency = 1
			page.Position = UDim2.fromOffset(0, 0)
		end
	end

	activeTab = name
	oldPage.Visible = true
	oldPage.GroupTransparency = 0
	oldPage.Position = UDim2.fromOffset(0, 0)
	newPage.Visible = true
	newPage.GroupTransparency = 1
	newPage.Position = UDim2.fromOffset(0, 8)

	local leaveTween = TweenService:Create(oldPage, SECTION_EXIT_TWEEN, {
		GroupTransparency = 1,
		Position = UDim2.fromOffset(0, -6),
	})
	local enterTween = TweenService:Create(newPage, SECTION_ENTER_TWEEN, {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(0, 0),
	})
	sectionTweens = {leaveTween, enterTween}

	leaveTween.Completed:Connect(function(playbackState)
		if transitionId ~= sectionTransitionId then return end
		if playbackState == Enum.PlaybackState.Completed then
			oldPage.Visible = false
			oldPage.Position = UDim2.fromOffset(0, 0)
		end
	end)
	enterTween.Completed:Connect(function(playbackState)
		if transitionId ~= sectionTransitionId then return end
		if playbackState == Enum.PlaybackState.Completed then
			newPage.Position = UDim2.fromOffset(0, 0)
			table.clear(sectionTweens)
		end
	end)

	updateTabs()
	leaveTween:Play()
	enterTween:Play()
end

for name, entry in pairs(tabs) do
	entry.hovered = false
	entry.button.MouseEnter:Connect(function()
		entry.hovered = true
		updateTabs()
	end)
	entry.button.MouseLeave:Connect(function()
		entry.hovered = false
		updateTabs()
	end)
	entry.button.Activated:Connect(function()
		selectSection(name)
	end)
end

local draggingPanel = false
local dragStart, panelStart
local dragZone = top
dragZone.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingPanel = true
		dragStart = input.Position
		panelStart = panel.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingPanel and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X, panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then draggingPanel = false end
end)

remote.OnClientEvent:Connect(function(message, first, second)
	if message == "Access" then
		if first == true then
			setUIVisible(true)
			remote:FireServer("RefreshPlayers")
		else
			visibilityAnimationId += 1
			cancelVisibilityTweens()
			gui:Destroy()
		end
	elseif message == "Targets" then
		targets = first or {}
		local found = false
		for _, target in ipairs(targets) do if target.userId == selectedTargetId then found = true break end end
		if not found then
			selectedTargetId = 0
			selectedTargetText = "Select..."
			setTargetButtonText(selectedTargetText)
		end
	elseif message == "TargetChanged" then
		selectedTargetId = tonumber(first) or 0
		selectedTargetText = second or "Select..."
		setTargetButtonText(selectedTargetText)
	elseif message == "Setting" then
		localSettings[first] = second
	end
end)
applyTheme("Dark")
remote:FireServer("Ready")

