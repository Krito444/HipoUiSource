-- HipoControls : bibliothèque d’interface client pour Potassium.
-- Charge-la, puis appelle HipoControls.new(options) depuis ton script.
-- Le script appelant fournit le titre, le raccourci et ses propres contrôles.

local function createInterface(options)
    options = options or {}
    assert(type(options) == "table", "[HipoControls] new attend une table d’options")

    local menuTitle = options.Title
    if menuTitle == nil then menuTitle = "HIPO CONTROLS" end
    assert(type(menuTitle) == "string" and menuTitle ~= "", "[HipoControls] Title doit être un texte non vide")

    local initialHideKey = options.Keybind
    if initialHideKey == nil then initialHideKey = Enum.KeyCode.RightControl end
    assert(typeof(initialHideKey) == "EnumItem" and initialHideKey.EnumType == Enum.KeyCode, "[HipoControls] Keybind doit être un Enum.KeyCode")

    local defaultTabPageName, defaultTabSidebarName
    if type(options.DefaultTab) == "string" then
        assert(options.DefaultTab ~= "", "[HipoControls] DefaultTab doit être un nom de page non vide")
        defaultTabPageName = options.DefaultTab
    elseif options.DefaultTab ~= nil then
        assert(type(options.DefaultTab) == "table", "[HipoControls] DefaultTab doit être un nom de page ou une table")
        defaultTabPageName = options.DefaultTab.Page
        defaultTabSidebarName = options.DefaultTab.Sidebar
        assert(
            type(defaultTabPageName) == "string" and defaultTabPageName ~= "",
            "[HipoControls] DefaultTab.Page doit être un nom de page non vide"
        )
        assert(
            defaultTabSidebarName == nil or (type(defaultTabSidebarName) == "string" and defaultTabSidebarName ~= ""),
            "[HipoControls] DefaultTab.Sidebar doit être un nom non vide"
        )
    end

-- ===== Services Roblox et validation du joueur =====
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("[HipoControls] Aucun joueur local. Attache Potassium à un client Roblox avant l’exécution.", 0)
end
local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if not playerGui then
    playerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
end
if not playerGui then
    error("[HipoControls] PlayerGui introuvable. Rejoins une partie puis relance le script.", 0)
end
local sessionConnections = {}
local sessionThreads = {}
local sessionStopped = false

-- SF Pro is not bundled with Roblox. Builder Sans is used as the closest
-- self-contained family, while retaining the existing 400/500/600 hierarchy.
local UI_FONT_FAMILY = "BuilderSans"
local uiFontFaceCache = {}

local function getUiFontFace(legacyFont)
    if legacyFont == Enum.Font.Code then return nil end

    local weight = Enum.FontWeight.Regular
    if legacyFont == Enum.Font.GothamMedium then
        weight = Enum.FontWeight.Medium
    elseif legacyFont == Enum.Font.GothamSemibold or legacyFont == Enum.Font.GothamBold then
        weight = Enum.FontWeight.SemiBold
    end

    local cacheKey = tostring(weight)
    if uiFontFaceCache[cacheKey] ~= nil then
        return uiFontFaceCache[cacheKey] or nil
    end

    local ok, fontFace = pcall(function()
        return Font.fromName(UI_FONT_FAMILY, weight, Enum.FontStyle.Normal)
    end)
    uiFontFaceCache[cacheKey] = ok and fontFace or false
    return ok and fontFace or nil
end

local function applyUiTypography(object)
    if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
        return
    end

    local fontFace = getUiFontFace(object.Font)
    if fontFace then
        object.FontFace = fontFace
    end
end

local function keepSessionConnection(connection)
    if sessionStopped then
        connection:Disconnect()
    else
        table.insert(sessionConnections, connection)
    end
    return connection
end

local function connectToSession(signal, callback)
    return keepSessionConnection(signal:Connect(callback))
end

local function keepSessionThread(thread)
    if sessionStopped then
        pcall(task.cancel, thread)
    else
        table.insert(sessionThreads, thread)
    end
    return thread
end

local function scheduleSessionTask(delaySeconds, callback, ...)
    local arguments = table.pack(...)
    return keepSessionThread(task.delay(delaySeconds, function()
        if sessionStopped then return end
        callback(table.unpack(arguments, 1, arguments.n))
    end))
end

local function spawnSessionTask(callback, ...)
    local arguments = table.pack(...)
    return keepSessionThread(task.spawn(function()
        if sessionStopped then return end
        callback(table.unpack(arguments, 1, arguments.n))
    end))
end

-- Smooth only the visual thumb/fill position; the control value remains immediate.
local SLIDER_SMOOTHING_TIME = 0.035
local function createSliderSmoother(renderAlpha, initialAlpha, isAlive)
    local currentAlpha = math.clamp(initialAlpha or 0, 0, 1)
    local targetAlpha = currentAlpha
    local connection

    local function setTarget(alpha)
        targetAlpha = math.clamp(alpha, 0, 1)
        if math.abs(targetAlpha - currentAlpha) < 0.001 then
            currentAlpha = targetAlpha
            renderAlpha(currentAlpha)
            return
        end
        if connection then return end

        connection = RunService.RenderStepped:Connect(function(deltaTime)
            if isAlive and not isAlive() then
                connection:Disconnect()
                connection = nil
                return
            end

            local blend = 1 - math.exp(-deltaTime / SLIDER_SMOOTHING_TIME)
            currentAlpha += (targetAlpha - currentAlpha) * blend
            if math.abs(targetAlpha - currentAlpha) < 0.001 then
                currentAlpha = targetAlpha
            end
            renderAlpha(currentAlpha)

            if currentAlpha == targetAlpha then
                connection:Disconnect()
                connection = nil
            end
        end)
    end

    return setTarget
end

for _, child in ipairs(playerGui:GetChildren()) do
    if child.Name == "HipoControlsBaseGui" then
        local shutdown = child:FindFirstChild("HipoControlsSessionShutdown")
        if shutdown and shutdown:IsA("BindableFunction") then
            pcall(function() shutdown:Invoke() end)
        end
        if child.Parent then child:Destroy() end
    end
end

-- ===== Composants communs et icônes =====
local ControlLibrary = (function()
-- Reusable controls and interface helpers for HipoControls.
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local LucideIcons = (function()	

-- Lucide Icons used by HipoControls: https://lucide.dev
-- Sprite atlases generated from the official lucide-icons/lucide/icons SVG set (2026-10-17).
-- ISC License
--
-- Copyright (c) 2026 Lucide Icons and Contributors
--
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--	
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
-- ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
-- ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
-- OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
--
-- ---
--
-- The following Lucide icons are derived from the Feather project:
--
-- airplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out
--
-- The MIT License (MIT) (for the icons listed above)
--
-- Copyright (c) 2013-present Cole Bemis
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local ATLAS_IMAGES = {
    "rbxassetid://118769064108991",
    "rbxassetid://83594682933322",
    "rbxassetid://109814917674122",
    "rbxassetid://103314959277932",
    "rbxassetid://122933846683629",
}
local ICON_CELL_SIZE = 32
local ICON_COLUMNS = 20
local ICONS = {
    ["a-arrow-down"] = {1, 0},
    ["a-arrow-up"] = {1, 1},
    ["a-large-small"] = {1, 2},
    ["accessibility"] = {1, 3},
    ["activity"] = {1, 4},
    ["ad"] = {1, 5},
    ["air-vent"] = {1, 6},
    ["airplay"] = {1, 7},
    ["alarm-clock"] = {1, 8},
    ["alarm-clock-check"] = {1, 9},
    ["alarm-clock-minus"] = {1, 10},
    ["alarm-clock-off"] = {1, 11},
    ["alarm-clock-plus"] = {1, 12},
    ["alarm-smoke"] = {1, 13},
    ["align-center-horizontal"] = {1, 14},
    ["align-center-vertical"] = {1, 15},
    ["align-end-horizontal"] = {1, 16},
    ["align-end-vertical"] = {1, 17},
    ["align-horizontal-distribute-center"] = {1, 18},
    ["align-horizontal-distribute-end"] = {1, 19},
    ["align-horizontal-distribute-start"] = {1, 20},
    ["align-horizontal-justify-center"] = {1, 21},
    ["align-horizontal-justify-end"] = {1, 22},
    ["align-horizontal-justify-start"] = {1, 23},
    ["align-horizontal-space-around"] = {1, 24},
    ["align-horizontal-space-between"] = {1, 25},
    ["align-start-horizontal"] = {1, 26},
    ["align-start-vertical"] = {1, 27},
    ["align-vertical-distribute-center"] = {1, 28},
    ["align-vertical-distribute-end"] = {1, 29},
    ["align-vertical-distribute-start"] = {1, 30},
    ["align-vertical-justify-center"] = {1, 31},
    ["align-vertical-justify-end"] = {1, 32},
    ["align-vertical-justify-start"] = {1, 33},
    ["align-vertical-space-around"] = {1, 34},
    ["align-vertical-space-between"] = {1, 35},
    ["ambulance"] = {1, 36},
    ["ampersand"] = {1, 37},
    ["ampersands"] = {1, 38},
    ["amphora"] = {1, 39},
    ["anchor"] = {1, 40},
    ["angle"] = {1, 41},
    ["antenna"] = {1, 42},
    ["anvil"] = {1, 43},
    ["aperture"] = {1, 44},
    ["app-window"] = {1, 45},
    ["app-window-mac"] = {1, 46},
    ["apple"] = {1, 47},
    ["archive"] = {1, 48},
    ["archive-restore"] = {1, 49},
    ["archive-x"] = {1, 50},
    ["armchair"] = {1, 51},
    ["armenian-dram"] = {1, 52},
    ["arrow-big-down"] = {1, 53},
    ["arrow-big-down-dash"] = {1, 54},
    ["arrow-big-left"] = {1, 55},
    ["arrow-big-left-dash"] = {1, 56},
    ["arrow-big-right"] = {1, 57},
    ["arrow-big-right-dash"] = {1, 58},
    ["arrow-big-up"] = {1, 59},
    ["arrow-big-up-dash"] = {1, 60},
    ["arrow-down"] = {1, 61},
    ["arrow-down-0-1"] = {1, 62},
    ["arrow-down-1-0"] = {1, 63},
    ["arrow-down-a-z"] = {1, 64},
    ["arrow-down-from-line"] = {1, 65},
    ["arrow-down-left"] = {1, 66},
    ["arrow-down-narrow-wide"] = {1, 67},
    ["arrow-down-right"] = {1, 68},
    ["arrow-down-to-dot"] = {1, 69},
    ["arrow-down-to-line"] = {1, 70},
    ["arrow-down-up"] = {1, 71},
    ["arrow-down-wide-narrow"] = {1, 72},
    ["arrow-down-z-a"] = {1, 73},
    ["arrow-left"] = {1, 74},
    ["arrow-left-from-line"] = {1, 75},
    ["arrow-left-right"] = {1, 76},
    ["arrow-left-to-line"] = {1, 77},
    ["arrow-right"] = {1, 78},
    ["arrow-right-from-line"] = {1, 79},
    ["arrow-right-left"] = {1, 80},
    ["arrow-right-to-line"] = {1, 81},
    ["arrow-up"] = {1, 82},
    ["arrow-up-0-1"] = {1, 83},
    ["arrow-up-1-0"] = {1, 84},
    ["arrow-up-a-z"] = {1, 85},
    ["arrow-up-down"] = {1, 86},
    ["arrow-up-from-dot"] = {1, 87},
    ["arrow-up-from-line"] = {1, 88},
    ["arrow-up-left"] = {1, 89},
    ["arrow-up-narrow-wide"] = {1, 90},
    ["arrow-up-right"] = {1, 91},
    ["arrow-up-to-line"] = {1, 92},
    ["arrow-up-wide-narrow"] = {1, 93},
    ["arrow-up-z-a"] = {1, 94},
    ["arrows-up-from-line"] = {1, 95},
    ["asterisk"] = {1, 96},
    ["astroid"] = {1, 97},
    ["at-sign"] = {1, 98},
    ["atom"] = {1, 99},
    ["audio-lines"] = {1, 100},
    ["audio-lines-off"] = {1, 101},
    ["audio-lines-x"] = {1, 102},
    ["audio-waveform"] = {1, 103},
    ["award"] = {1, 104},
    ["axe"] = {1, 105},
    ["axis-3d"] = {1, 106},
    ["baby"] = {1, 107},
    ["backpack"] = {1, 108},
    ["badge"] = {1, 109},
    ["badge-alert"] = {1, 110},
    ["badge-cent"] = {1, 111},
    ["badge-check"] = {1, 112},
    ["badge-dollar-sign"] = {1, 113},
    ["badge-euro"] = {1, 114},
    ["badge-indian-rupee"] = {1, 115},
    ["badge-info"] = {1, 116},
    ["badge-japanese-yen"] = {1, 117},
    ["badge-minus"] = {1, 118},
    ["badge-percent"] = {1, 119},
    ["badge-plus"] = {1, 120},
    ["badge-pound-sterling"] = {1, 121},
    ["badge-question-mark"] = {1, 122},
    ["badge-russian-ruble"] = {1, 123},
    ["badge-swiss-franc"] = {1, 124},
    ["badge-turkish-lira"] = {1, 125},
    ["badge-x"] = {1, 126},
    ["baggage-claim"] = {1, 127},
    ["balloon"] = {1, 128},
    ["ban"] = {1, 129},
    ["banana"] = {1, 130},
    ["bandage"] = {1, 131},
    ["bangladeshi-taka"] = {1, 132},
    ["banknote"] = {1, 133},
    ["banknote-arrow-down"] = {1, 134},
    ["banknote-arrow-up"] = {1, 135},
    ["banknote-check"] = {1, 136},
    ["banknote-x"] = {1, 137},
    ["barcode"] = {1, 138},
    ["barrel"] = {1, 139},
    ["baseline"] = {1, 140},
    ["bath"] = {1, 141},
    ["battery"] = {1, 142},
    ["battery-charging"] = {1, 143},
    ["battery-full"] = {1, 144},
    ["battery-low"] = {1, 145},
    ["battery-medium"] = {1, 146},
    ["battery-plus"] = {1, 147},
    ["battery-warning"] = {1, 148},
    ["beaker"] = {1, 149},
    ["bean"] = {1, 150},
    ["bean-off"] = {1, 151},
    ["bed"] = {1, 152},
    ["bed-double"] = {1, 153},
    ["bed-single"] = {1, 154},
    ["beef"] = {1, 155},
    ["beef-off"] = {1, 156},
    ["beer"] = {1, 157},
    ["beer-off"] = {1, 158},
    ["belarusian-ruble"] = {1, 159},
    ["bell"] = {1, 160},
    ["bell-check"] = {1, 161},
    ["bell-dot"] = {1, 162},
    ["bell-electric"] = {1, 163},
    ["bell-minus"] = {1, 164},
    ["bell-off"] = {1, 165},
    ["bell-plus"] = {1, 166},
    ["bell-ring"] = {1, 167},
    ["between-horizontal-end"] = {1, 168},
    ["between-horizontal-start"] = {1, 169},
    ["between-vertical-end"] = {1, 170},
    ["between-vertical-start"] = {1, 171},
    ["biceps-flexed"] = {1, 172},
    ["bike"] = {1, 173},
    ["binary"] = {1, 174},
    ["binoculars"] = {1, 175},
    ["biohazard"] = {1, 176},
    ["bird"] = {1, 177},
    ["birdhouse"] = {1, 178},
    ["bitcoin"] = {1, 179},
    ["blend"] = {1, 180},
    ["blender"] = {1, 181},
    ["blinds"] = {1, 182},
    ["blocks"] = {1, 183},
    ["bluetooth"] = {1, 184},
    ["bluetooth-connected"] = {1, 185},
    ["bluetooth-off"] = {1, 186},
    ["bluetooth-searching"] = {1, 187},
    ["bold"] = {1, 188},
    ["bolt"] = {1, 189},
    ["bomb"] = {1, 190},
    ["bone"] = {1, 191},
    ["bone-fracture"] = {1, 192},
    ["book"] = {1, 193},
    ["book-a"] = {1, 194},
    ["book-alert"] = {1, 195},
    ["book-audio"] = {1, 196},
    ["book-bookmark"] = {1, 197},
    ["book-check"] = {1, 198},
    ["book-copy"] = {1, 199},
    ["book-dashed"] = {1, 200},
    ["book-down"] = {1, 201},
    ["book-headphones"] = {1, 202},
    ["book-heart"] = {1, 203},
    ["book-image"] = {1, 204},
    ["book-key"] = {1, 205},
    ["book-lock"] = {1, 206},
    ["book-minus"] = {1, 207},
    ["book-open"] = {1, 208},
    ["book-open-check"] = {1, 209},
    ["book-open-text"] = {1, 210},
    ["book-plus"] = {1, 211},
    ["book-search"] = {1, 212},
    ["book-text"] = {1, 213},
    ["book-type"] = {1, 214},
    ["book-up"] = {1, 215},
    ["book-up-2"] = {1, 216},
    ["book-user"] = {1, 217},
    ["book-x"] = {1, 218},
    ["bookmark"] = {1, 219},
    ["bookmark-check"] = {1, 220},
    ["bookmark-minus"] = {1, 221},
    ["bookmark-off"] = {1, 222},
    ["bookmark-plus"] = {1, 223},
    ["bookmark-x"] = {1, 224},
    ["boom-box"] = {1, 225},
    ["bot"] = {1, 226},
    ["bot-message-square"] = {1, 227},
    ["bot-off"] = {1, 228},
    ["bottle-wine"] = {1, 229},
    ["bow-arrow"] = {1, 230},
    ["box"] = {1, 231},
    ["boxes"] = {1, 232},
    ["braces"] = {1, 233},
    ["brackets"] = {1, 234},
    ["brain"] = {1, 235},
    ["brain-circuit"] = {1, 236},
    ["brain-cog"] = {1, 237},
    ["brick-wall"] = {1, 238},
    ["brick-wall-fire"] = {1, 239},
    ["brick-wall-shield"] = {1, 240},
    ["bridge"] = {1, 241},
    ["briefcase"] = {1, 242},
    ["briefcase-business"] = {1, 243},
    ["briefcase-conveyor-belt"] = {1, 244},
    ["briefcase-medical"] = {1, 245},
    ["briefcase-plus"] = {1, 246},
    ["bring-to-front"] = {1, 247},
    ["broccoli"] = {1, 248},
    ["broom"] = {1, 249},
    ["broom-sparkles"] = {1, 250},
    ["brush"] = {1, 251},
    ["brush-cleaning"] = {1, 252},
    ["bubbles"] = {1, 253},
    ["bug"] = {1, 254},
    ["bug-off"] = {1, 255},
    ["bug-play"] = {1, 256},
    ["building"] = {1, 257},
    ["building-complex"] = {1, 258},
    ["building-complex-plus"] = {1, 259},
    ["bus"] = {1, 260},
    ["bus-front"] = {1, 261},
    ["cable"] = {1, 262},
    ["cable-car"] = {1, 263},
    ["cake"] = {1, 264},
    ["cake-slice"] = {1, 265},
    ["calculator"] = {1, 266},
    ["calendar"] = {1, 267},
    ["calendar-1"] = {1, 268},
    ["calendar-arrow-down"] = {1, 269},
    ["calendar-arrow-up"] = {1, 270},
    ["calendar-check"] = {1, 271},
    ["calendar-check-2"] = {1, 272},
    ["calendar-chevrons-left"] = {1, 273},
    ["calendar-chevrons-right"] = {1, 274},
    ["calendar-clock"] = {1, 275},
    ["calendar-cog"] = {1, 276},
    ["calendar-days"] = {1, 277},
    ["calendar-fold"] = {1, 278},
    ["calendar-heart"] = {1, 279},
    ["calendar-minus"] = {1, 280},
    ["calendar-minus-2"] = {1, 281},
    ["calendar-off"] = {1, 282},
    ["calendar-plus"] = {1, 283},
    ["calendar-plus-2"] = {1, 284},
    ["calendar-range"] = {1, 285},
    ["calendar-search"] = {1, 286},
    ["calendar-sync"] = {1, 287},
    ["calendar-x"] = {1, 288},
    ["calendar-x-2"] = {1, 289},
    ["calendars"] = {1, 290},
    ["camera"] = {1, 291},
    ["camera-off"] = {1, 292},
    ["can"] = {1, 293},
    ["can-soda"] = {1, 294},
    ["candy"] = {1, 295},
    ["candy-cane"] = {1, 296},
    ["candy-off"] = {1, 297},
    ["cannabis"] = {1, 298},
    ["cannabis-off"] = {1, 299},
    ["captions"] = {1, 300},
    ["captions-off"] = {1, 301},
    ["car"] = {1, 302},
    ["car-battery"] = {1, 303},
    ["car-front"] = {1, 304},
    ["car-taxi-front"] = {1, 305},
    ["caravan"] = {1, 306},
    ["card-sim"] = {1, 307},
    ["carrot"] = {1, 308},
    ["carton"] = {1, 309},
    ["carton-off"] = {1, 310},
    ["case-lower"] = {1, 311},
    ["case-sensitive"] = {1, 312},
    ["case-upper"] = {1, 313},
    ["cassette-tape"] = {1, 314},
    ["cast"] = {1, 315},
    ["castle"] = {1, 316},
    ["cat"] = {1, 317},
    ["cctv"] = {1, 318},
    ["cctv-off"] = {1, 319},
    ["certificate"] = {1, 320},
    ["chart-area"] = {1, 321},
    ["chart-bar"] = {1, 322},
    ["chart-bar-big"] = {1, 323},
    ["chart-bar-decreasing"] = {1, 324},
    ["chart-bar-increasing"] = {1, 325},
    ["chart-bar-stacked"] = {1, 326},
    ["chart-candlestick"] = {1, 327},
    ["chart-column"] = {1, 328},
    ["chart-column-big"] = {1, 329},
    ["chart-column-decreasing"] = {1, 330},
    ["chart-column-increasing"] = {1, 331},
    ["chart-column-stacked"] = {1, 332},
    ["chart-gantt"] = {1, 333},
    ["chart-line"] = {1, 334},
    ["chart-network"] = {1, 335},
    ["chart-no-axes-column"] = {1, 336},
    ["chart-no-axes-column-decreasing"] = {1, 337},
    ["chart-no-axes-column-increasing"] = {1, 338},
    ["chart-no-axes-combined"] = {1, 339},
    ["chart-no-axes-gantt"] = {1, 340},
    ["chart-pie"] = {1, 341},
    ["chart-scatter"] = {1, 342},
    ["chart-spline"] = {1, 343},
    ["check"] = {1, 344},
    ["check-check"] = {1, 345},
    ["check-line"] = {1, 346},
    ["chef-hat"] = {1, 347},
    ["cherry"] = {1, 348},
    ["chess-bishop"] = {1, 349},
    ["chess-king"] = {1, 350},
    ["chess-knight"] = {1, 351},
    ["chess-pawn"] = {1, 352},
    ["chess-queen"] = {1, 353},
    ["chess-rook"] = {1, 354},
    ["chevron-down"] = {1, 355},
    ["chevron-first"] = {1, 356},
    ["chevron-last"] = {1, 357},
    ["chevron-left"] = {1, 358},
    ["chevron-right"] = {1, 359},
    ["chevron-up"] = {1, 360},
    ["chevrons-down"] = {1, 361},
    ["chevrons-down-up"] = {1, 362},
    ["chevrons-left"] = {1, 363},
    ["chevrons-left-right"] = {1, 364},
    ["chevrons-left-right-ellipsis"] = {1, 365},
    ["chevrons-right"] = {1, 366},
    ["chevrons-right-left"] = {1, 367},
    ["chevrons-up"] = {1, 368},
    ["chevrons-up-down"] = {1, 369},
    ["church"] = {1, 370},
    ["cigarette"] = {1, 371},
    ["cigarette-off"] = {1, 372},
    ["circle"] = {1, 373},
    ["circle-alert"] = {1, 374},
    ["circle-arrow-down"] = {1, 375},
    ["circle-arrow-left"] = {1, 376},
    ["circle-arrow-out-down-left"] = {1, 377},
    ["circle-arrow-out-down-right"] = {1, 378},
    ["circle-arrow-out-up-left"] = {1, 379},
    ["circle-arrow-out-up-right"] = {1, 380},
    ["circle-arrow-right"] = {1, 381},
    ["circle-arrow-up"] = {1, 382},
    ["circle-check"] = {1, 383},
    ["circle-check-big"] = {1, 384},
    ["circle-chevron-down"] = {1, 385},
    ["circle-chevron-left"] = {1, 386},
    ["circle-chevron-right"] = {1, 387},
    ["circle-chevron-up"] = {1, 388},
    ["circle-dashed"] = {1, 389},
    ["circle-dashed-check"] = {1, 390},
    ["circle-divide"] = {1, 391},
    ["circle-dollar-sign"] = {1, 392},
    ["circle-dot"] = {1, 393},
    ["circle-dot-dashed"] = {1, 394},
    ["circle-ellipsis"] = {1, 395},
    ["circle-equal"] = {1, 396},
    ["circle-euro"] = {1, 397},
    ["circle-fading-arrow-up"] = {1, 398},
    ["circle-fading-play"] = {1, 399},
    ["circle-fading-plus"] = {2, 0},
    ["circle-gauge"] = {2, 1},
    ["circle-minus"] = {2, 2},
    ["circle-off"] = {2, 3},
    ["circle-parking"] = {2, 4},
    ["circle-parking-off"] = {2, 5},
    ["circle-pause"] = {2, 6},
    ["circle-percent"] = {2, 7},
    ["circle-pile"] = {2, 8},
    ["circle-play"] = {2, 9},
    ["circle-plus"] = {2, 10},
    ["circle-pound-sterling"] = {2, 11},
    ["circle-power"] = {2, 12},
    ["circle-question-mark"] = {2, 13},
    ["circle-slash"] = {2, 14},
    ["circle-slash-2"] = {2, 15},
    ["circle-small"] = {2, 16},
    ["circle-star"] = {2, 17},
    ["circle-stop"] = {2, 18},
    ["circle-user"] = {2, 19},
    ["circle-user-round"] = {2, 20},
    ["circle-x"] = {2, 21},
    ["circuit-board"] = {2, 22},
    ["citrus"] = {2, 23},
    ["clapperboard"] = {2, 24},
    ["clef-alto"] = {2, 25},
    ["clef-bass"] = {2, 26},
    ["clef-treble"] = {2, 27},
    ["clipboard"] = {2, 28},
    ["clipboard-check"] = {2, 29},
    ["clipboard-clock"] = {2, 30},
    ["clipboard-copy"] = {2, 31},
    ["clipboard-list"] = {2, 32},
    ["clipboard-minus"] = {2, 33},
    ["clipboard-paste"] = {2, 34},
    ["clipboard-pen"] = {2, 35},
    ["clipboard-pen-line"] = {2, 36},
    ["clipboard-plus"] = {2, 37},
    ["clipboard-type"] = {2, 38},
    ["clipboard-x"] = {2, 39},
    ["clock"] = {2, 40},
    ["clock-1"] = {2, 41},
    ["clock-10"] = {2, 42},
    ["clock-11"] = {2, 43},
    ["clock-12"] = {2, 44},
    ["clock-2"] = {2, 45},
    ["clock-3"] = {2, 46},
    ["clock-4"] = {2, 47},
    ["clock-5"] = {2, 48},
    ["clock-6"] = {2, 49},
    ["clock-7"] = {2, 50},
    ["clock-8"] = {2, 51},
    ["clock-9"] = {2, 52},
    ["clock-alert"] = {2, 53},
    ["clock-arrow-down"] = {2, 54},
    ["clock-arrow-left"] = {2, 55},
    ["clock-arrow-right"] = {2, 56},
    ["clock-arrow-up"] = {2, 57},
    ["clock-check"] = {2, 58},
    ["clock-fading"] = {2, 59},
    ["clock-plus"] = {2, 60},
    ["closed-caption"] = {2, 61},
    ["cloud"] = {2, 62},
    ["cloud-alert"] = {2, 63},
    ["cloud-backup"] = {2, 64},
    ["cloud-check"] = {2, 65},
    ["cloud-cog"] = {2, 66},
    ["cloud-download"] = {2, 67},
    ["cloud-drizzle"] = {2, 68},
    ["cloud-fog"] = {2, 69},
    ["cloud-hail"] = {2, 70},
    ["cloud-lightning"] = {2, 71},
    ["cloud-moon"] = {2, 72},
    ["cloud-moon-rain"] = {2, 73},
    ["cloud-off"] = {2, 74},
    ["cloud-rain"] = {2, 75},
    ["cloud-rain-wind"] = {2, 76},
    ["cloud-snow"] = {2, 77},
    ["cloud-sun"] = {2, 78},
    ["cloud-sun-rain"] = {2, 79},
    ["cloud-sync"] = {2, 80},
    ["cloud-upload"] = {2, 81},
    ["cloudy"] = {2, 82},
    ["clover"] = {2, 83},
    ["club"] = {2, 84},
    ["code"] = {2, 85},
    ["code-xml"] = {2, 86},
    ["coffee"] = {2, 87},
    ["cog"] = {2, 88},
    ["coins"] = {2, 89},
    ["columns-2"] = {2, 90},
    ["columns-3"] = {2, 91},
    ["columns-3-cog"] = {2, 92},
    ["columns-4"] = {2, 93},
    ["combine"] = {2, 94},
    ["command"] = {2, 95},
    ["compass"] = {2, 96},
    ["component"] = {2, 97},
    ["computer"] = {2, 98},
    ["concierge-bell"] = {2, 99},
    ["cone"] = {2, 100},
    ["construction"] = {2, 101},
    ["contact"] = {2, 102},
    ["contact-round"] = {2, 103},
    ["container"] = {2, 104},
    ["contrast"] = {2, 105},
    ["cookie"] = {2, 106},
    ["cooking-pot"] = {2, 107},
    ["copy"] = {2, 108},
    ["copy-check"] = {2, 109},
    ["copy-minus"] = {2, 110},
    ["copy-plus"] = {2, 111},
    ["copy-slash"] = {2, 112},
    ["copy-x"] = {2, 113},
    ["copyleft"] = {2, 114},
    ["copyright"] = {2, 115},
    ["corner-down-left"] = {2, 116},
    ["corner-down-right"] = {2, 117},
    ["corner-left-down"] = {2, 118},
    ["corner-left-up"] = {2, 119},
    ["corner-right-down"] = {2, 120},
    ["corner-right-up"] = {2, 121},
    ["corner-up-left"] = {2, 122},
    ["corner-up-right"] = {2, 123},
    ["cpu"] = {2, 124},
    ["cpu-ai"] = {2, 125},
    ["creative-commons"] = {2, 126},
    ["credit-card"] = {2, 127},
    ["credit-card-check"] = {2, 128},
    ["credit-card-minus"] = {2, 129},
    ["credit-card-plus"] = {2, 130},
    ["credit-card-reader"] = {2, 131},
    ["credit-card-x"] = {2, 132},
    ["croissant"] = {2, 133},
    ["crop"] = {2, 134},
    ["cross"] = {2, 135},
    ["crosshair"] = {2, 136},
    ["crown"] = {2, 137},
    ["cuboid"] = {2, 138},
    ["cup-soda"] = {2, 139},
    ["cupcake"] = {2, 140},
    ["currency"] = {2, 141},
    ["cylinder"] = {2, 142},
    ["dam"] = {2, 143},
    ["database"] = {2, 144},
    ["database-arrow-down"] = {2, 145},
    ["database-arrow-up"] = {2, 146},
    ["database-backup"] = {2, 147},
    ["database-check"] = {2, 148},
    ["database-minus"] = {2, 149},
    ["database-plus"] = {2, 150},
    ["database-search"] = {2, 151},
    ["database-x"] = {2, 152},
    ["database-zap"] = {2, 153},
    ["decimals-arrow-left"] = {2, 154},
    ["decimals-arrow-right"] = {2, 155},
    ["delete"] = {2, 156},
    ["dessert"] = {2, 157},
    ["diameter"] = {2, 158},
    ["diamond"] = {2, 159},
    ["diamond-minus"] = {2, 160},
    ["diamond-percent"] = {2, 161},
    ["diamond-plus"] = {2, 162},
    ["dice-1"] = {2, 163},
    ["dice-2"] = {2, 164},
    ["dice-3"] = {2, 165},
    ["dice-4"] = {2, 166},
    ["dice-5"] = {2, 167},
    ["dice-6"] = {2, 168},
    ["dices"] = {2, 169},
    ["diff"] = {2, 170},
    ["disc"] = {2, 171},
    ["disc-2"] = {2, 172},
    ["disc-3"] = {2, 173},
    ["disc-album"] = {2, 174},
    ["divide"] = {2, 175},
    ["dna"] = {2, 176},
    ["dna-off"] = {2, 177},
    ["dock"] = {2, 178},
    ["dog"] = {2, 179},
    ["dollar-sign"] = {2, 180},
    ["dome"] = {2, 181},
    ["donut"] = {2, 182},
    ["door-closed"] = {2, 183},
    ["door-closed-cog"] = {2, 184},
    ["door-closed-locked"] = {2, 185},
    ["door-closed-package"] = {2, 186},
    ["door-open"] = {2, 187},
    ["door-stairwell"] = {2, 188},
    ["dot"] = {2, 189},
    ["download"] = {2, 190},
    ["drafting-compass"] = {2, 191},
    ["drama"] = {2, 192},
    ["drill"] = {2, 193},
    ["drone"] = {2, 194},
    ["droplet"] = {2, 195},
    ["droplet-off"] = {2, 196},
    ["droplets"] = {2, 197},
    ["drum"] = {2, 198},
    ["drumstick"] = {2, 199},
    ["dumbbell"] = {2, 200},
    ["ear"] = {2, 201},
    ["ear-off"] = {2, 202},
    ["earth"] = {2, 203},
    ["earth-lock"] = {2, 204},
    ["eclipse"] = {2, 205},
    ["egg"] = {2, 206},
    ["egg-fried"] = {2, 207},
    ["egg-off"] = {2, 208},
    ["eighth-note"] = {2, 209},
    ["eighth-notes"] = {2, 210},
    ["eject"] = {2, 211},
    ["ellipse"] = {2, 212},
    ["ellipsis"] = {2, 213},
    ["ellipsis-vertical"] = {2, 214},
    ["engine"] = {2, 215},
    ["equal"] = {2, 216},
    ["equal-approximately"] = {2, 217},
    ["equal-approximately-not"] = {2, 218},
    ["equal-not"] = {2, 219},
    ["eraser"] = {2, 220},
    ["ethernet-port"] = {2, 221},
    ["euro"] = {2, 222},
    ["ev-charger"] = {2, 223},
    ["expand"] = {2, 224},
    ["external-link"] = {2, 225},
    ["eye"] = {2, 226},
    ["eye-closed"] = {2, 227},
    ["eye-dashed"] = {2, 228},
    ["eye-off"] = {2, 229},
    ["face-angry"] = {2, 230},
    ["face-expressionless"] = {2, 231},
    ["face-grinning"] = {2, 232},
    ["face-neutral"] = {2, 233},
    ["face-slightly-frowning"] = {2, 234},
    ["face-slightly-smiling"] = {2, 235},
    ["face-slightly-smiling-plus"] = {2, 236},
    ["factory"] = {2, 237},
    ["fan"] = {2, 238},
    ["fast-forward"] = {2, 239},
    ["faucet"] = {2, 240},
    ["feather"] = {2, 241},
    ["fence"] = {2, 242},
    ["ferris-wheel"] = {2, 243},
    ["file"] = {2, 244},
    ["file-archive"] = {2, 245},
    ["file-axis-3d"] = {2, 246},
    ["file-badge"] = {2, 247},
    ["file-box"] = {2, 248},
    ["file-braces"] = {2, 249},
    ["file-braces-corner"] = {2, 250},
    ["file-chart-column"] = {2, 251},
    ["file-chart-column-increasing"] = {2, 252},
    ["file-chart-line"] = {2, 253},
    ["file-chart-pie"] = {2, 254},
    ["file-check"] = {2, 255},
    ["file-check-corner"] = {2, 256},
    ["file-clock"] = {2, 257},
    ["file-code"] = {2, 258},
    ["file-code-corner"] = {2, 259},
    ["file-cog"] = {2, 260},
    ["file-diff"] = {2, 261},
    ["file-digit"] = {2, 262},
    ["file-down"] = {2, 263},
    ["file-exclamation-point"] = {2, 264},
    ["file-headphone"] = {2, 265},
    ["file-heart"] = {2, 266},
    ["file-image"] = {2, 267},
    ["file-input"] = {2, 268},
    ["file-key"] = {2, 269},
    ["file-lock"] = {2, 270},
    ["file-minus"] = {2, 271},
    ["file-minus-corner"] = {2, 272},
    ["file-music"] = {2, 273},
    ["file-output"] = {2, 274},
    ["file-pen"] = {2, 275},
    ["file-pen-line"] = {2, 276},
    ["file-play"] = {2, 277},
    ["file-plus"] = {2, 278},
    ["file-plus-corner"] = {2, 279},
    ["file-question-mark"] = {2, 280},
    ["file-scan"] = {2, 281},
    ["file-search"] = {2, 282},
    ["file-search-corner"] = {2, 283},
    ["file-signal"] = {2, 284},
    ["file-sliders"] = {2, 285},
    ["file-spreadsheet"] = {2, 286},
    ["file-stack"] = {2, 287},
    ["file-symlink"] = {2, 288},
    ["file-terminal"] = {2, 289},
    ["file-text"] = {2, 290},
    ["file-type"] = {2, 291},
    ["file-type-corner"] = {2, 292},
    ["file-up"] = {2, 293},
    ["file-user"] = {2, 294},
    ["file-video-camera"] = {2, 295},
    ["file-volume"] = {2, 296},
    ["file-x"] = {2, 297},
    ["file-x-corner"] = {2, 298},
    ["files"] = {2, 299},
    ["film"] = {2, 300},
    ["fingerprint-pattern"] = {2, 301},
    ["fire-extinguisher"] = {2, 302},
    ["fish"] = {2, 303},
    ["fish-off"] = {2, 304},
    ["fish-symbol"] = {2, 305},
    ["fishing-hook"] = {2, 306},
    ["fishing-rod"] = {2, 307},
    ["flag"] = {2, 308},
    ["flag-off"] = {2, 309},
    ["flag-triangle-left"] = {2, 310},
    ["flag-triangle-right"] = {2, 311},
    ["flame"] = {2, 312},
    ["flame-kindling"] = {2, 313},
    ["flashlight"] = {2, 314},
    ["flashlight-off"] = {2, 315},
    ["flask-conical"] = {2, 316},
    ["flask-conical-off"] = {2, 317},
    ["flask-round"] = {2, 318},
    ["flower"] = {2, 319},
    ["flower-2"] = {2, 320},
    ["focus"] = {2, 321},
    ["fold-horizontal"] = {2, 322},
    ["fold-vertical"] = {2, 323},
    ["folder"] = {2, 324},
    ["folder-archive"] = {2, 325},
    ["folder-bookmark"] = {2, 326},
    ["folder-check"] = {2, 327},
    ["folder-clock"] = {2, 328},
    ["folder-closed"] = {2, 329},
    ["folder-code"] = {2, 330},
    ["folder-cog"] = {2, 331},
    ["folder-dot"] = {2, 332},
    ["folder-down"] = {2, 333},
    ["folder-git"] = {2, 334},
    ["folder-git-2"] = {2, 335},
    ["folder-heart"] = {2, 336},
    ["folder-input"] = {2, 337},
    ["folder-kanban"] = {2, 338},
    ["folder-key"] = {2, 339},
    ["folder-lock"] = {2, 340},
    ["folder-minus"] = {2, 341},
    ["folder-open"] = {2, 342},
    ["folder-open-dot"] = {2, 343},
    ["folder-output"] = {2, 344},
    ["folder-pen"] = {2, 345},
    ["folder-plus"] = {2, 346},
    ["folder-root"] = {2, 347},
    ["folder-search"] = {2, 348},
    ["folder-search-2"] = {2, 349},
    ["folder-symlink"] = {2, 350},
    ["folder-sync"] = {2, 351},
    ["folder-tree"] = {2, 352},
    ["folder-up"] = {2, 353},
    ["folder-user"] = {2, 354},
    ["folder-users"] = {2, 355},
    ["folder-x"] = {2, 356},
    ["folders"] = {2, 357},
    ["footprints"] = {2, 358},
    ["forklift"] = {2, 359},
    ["form"] = {2, 360},
    ["forward"] = {2, 361},
    ["frame"] = {2, 362},
    ["fuel"] = {2, 363},
    ["fullscreen"] = {2, 364},
    ["funnel"] = {2, 365},
    ["funnel-plus"] = {2, 366},
    ["funnel-x"] = {2, 367},
    ["galaxy"] = {2, 368},
    ["gallery-horizontal"] = {2, 369},
    ["gallery-horizontal-end"] = {2, 370},
    ["gallery-thumbnails"] = {2, 371},
    ["gallery-vertical"] = {2, 372},
    ["gallery-vertical-end"] = {2, 373},
    ["gamepad"] = {2, 374},
    ["gamepad-2"] = {2, 375},
    ["gamepad-directional"] = {2, 376},
    ["gap-horizontal"] = {2, 377},
    ["gap-vertical"] = {2, 378},
    ["gauge"] = {2, 379},
    ["gavel"] = {2, 380},
    ["gem"] = {2, 381},
    ["georgian-lari"] = {2, 382},
    ["germ"] = {2, 383},
    ["germ-off"] = {2, 384},
    ["ghost"] = {2, 385},
    ["gift"] = {2, 386},
    ["git-branch"] = {2, 387},
    ["git-branch-minus"] = {2, 388},
    ["git-branch-plus"] = {2, 389},
    ["git-commit-horizontal"] = {2, 390},
    ["git-commit-vertical"] = {2, 391},
    ["git-compare"] = {2, 392},
    ["git-compare-arrows"] = {2, 393},
    ["git-fork"] = {2, 394},
    ["git-graph"] = {2, 395},
    ["git-merge"] = {2, 396},
    ["git-merge-conflict"] = {2, 397},
    ["git-pull-request"] = {2, 398},
    ["git-pull-request-arrow"] = {2, 399},
    ["git-pull-request-closed"] = {3, 0},
    ["git-pull-request-create"] = {3, 1},
    ["git-pull-request-create-arrow"] = {3, 2},
    ["git-pull-request-draft"] = {3, 3},
    ["glass-water"] = {3, 4},
    ["glasses"] = {3, 5},
    ["globe"] = {3, 6},
    ["globe-check"] = {3, 7},
    ["globe-code"] = {3, 8},
    ["globe-lock"] = {3, 9},
    ["globe-off"] = {3, 10},
    ["globe-x"] = {3, 11},
    ["goal"] = {3, 12},
    ["gpu"] = {3, 13},
    ["graduation-cap"] = {3, 14},
    ["grape"] = {3, 15},
    ["graph-star"] = {3, 16},
    ["grid-2x2"] = {3, 17},
    ["grid-2x2-check"] = {3, 18},
    ["grid-2x2-plus"] = {3, 19},
    ["grid-2x2-x"] = {3, 20},
    ["grid-3x2"] = {3, 21},
    ["grid-3x3"] = {3, 22},
    ["grip"] = {3, 23},
    ["grip-horizontal"] = {3, 24},
    ["grip-vertical"] = {3, 25},
    ["groceries"] = {3, 26},
    ["group"] = {3, 27},
    ["guitar"] = {3, 28},
    ["guitar-electric"] = {3, 29},
    ["half-note"] = {3, 30},
    ["ham"] = {3, 31},
    ["hamburger"] = {3, 32},
    ["hammer"] = {3, 33},
    ["hand"] = {3, 34},
    ["hand-coins"] = {3, 35},
    ["hand-fist"] = {3, 36},
    ["hand-grab"] = {3, 37},
    ["hand-heart"] = {3, 38},
    ["hand-helping"] = {3, 39},
    ["hand-metal"] = {3, 40},
    ["hand-platter"] = {3, 41},
    ["handbag"] = {3, 42},
    ["handle-bottom-right"] = {3, 43},
    ["handshake"] = {3, 44},
    ["hard-drive"] = {3, 45},
    ["hard-drive-download"] = {3, 46},
    ["hard-drive-upload"] = {3, 47},
    ["hard-hat"] = {3, 48},
    ["hash"] = {3, 49},
    ["hat-glasses"] = {3, 50},
    ["haze"] = {3, 51},
    ["hd"] = {3, 52},
    ["hdmi-port"] = {3, 53},
    ["heading"] = {3, 54},
    ["heading-1"] = {3, 55},
    ["heading-2"] = {3, 56},
    ["heading-3"] = {3, 57},
    ["heading-4"] = {3, 58},
    ["heading-5"] = {3, 59},
    ["heading-6"] = {3, 60},
    ["headphone-off"] = {3, 61},
    ["headphones"] = {3, 62},
    ["headset"] = {3, 63},
    ["heart"] = {3, 64},
    ["heart-crack"] = {3, 65},
    ["heart-handshake"] = {3, 66},
    ["heart-minus"] = {3, 67},
    ["heart-off"] = {3, 68},
    ["heart-plus"] = {3, 69},
    ["heart-pulse"] = {3, 70},
    ["heart-x"] = {3, 71},
    ["heater"] = {3, 72},
    ["helicopter"] = {3, 73},
    ["hexagon"] = {3, 74},
    ["highlighter"] = {3, 75},
    ["hiking-stick"] = {3, 76},
    ["hop"] = {3, 77},
    ["hop-off"] = {3, 78},
    ["hospital"] = {3, 79},
    ["hotel"] = {3, 80},
    ["hourglass"] = {3, 81},
    ["hourglass-cog"] = {3, 82},
    ["house"] = {3, 83},
    ["house-cog"] = {3, 84},
    ["house-heart"] = {3, 85},
    ["house-plug"] = {3, 86},
    ["house-plus"] = {3, 87},
    ["house-wifi"] = {3, 88},
    ["houses"] = {3, 89},
    ["ice-cream-bowl"] = {3, 90},
    ["ice-cream-cone"] = {3, 91},
    ["id-card"] = {3, 92},
    ["id-card-lanyard"] = {3, 93},
    ["image"] = {3, 94},
    ["image-down"] = {3, 95},
    ["image-minus"] = {3, 96},
    ["image-off"] = {3, 97},
    ["image-play"] = {3, 98},
    ["image-plus"] = {3, 99},
    ["image-up"] = {3, 100},
    ["image-upscale"] = {3, 101},
    ["images"] = {3, 102},
    ["import"] = {3, 103},
    ["inbox"] = {3, 104},
    ["indian-rupee"] = {3, 105},
    ["infinity"] = {3, 106},
    ["info"] = {3, 107},
    ["inspection-panel"] = {3, 108},
    ["italic"] = {3, 109},
    ["iteration-ccw"] = {3, 110},
    ["iteration-cw"] = {3, 111},
    ["iv-bag"] = {3, 112},
    ["japanese-yen"] = {3, 113},
    ["joystick"] = {3, 114},
    ["kanban"] = {3, 115},
    ["kayak"] = {3, 116},
    ["kazakh-tenge"] = {3, 117},
    ["key"] = {3, 118},
    ["key-round"] = {3, 119},
    ["key-square"] = {3, 120},
    ["keyboard"] = {3, 121},
    ["keyboard-music"] = {3, 122},
    ["keyboard-off"] = {3, 123},
    ["lambda"] = {3, 124},
    ["lamp"] = {3, 125},
    ["lamp-ceiling"] = {3, 126},
    ["lamp-desk"] = {3, 127},
    ["lamp-floor"] = {3, 128},
    ["lamp-wall-down"] = {3, 129},
    ["lamp-wall-up"] = {3, 130},
    ["land-plot"] = {3, 131},
    ["landmark"] = {3, 132},
    ["languages"] = {3, 133},
    ["laptop"] = {3, 134},
    ["laptop-minimal"] = {3, 135},
    ["laptop-minimal-check"] = {3, 136},
    ["lasso"] = {3, 137},
    ["lasso-select"] = {3, 138},
    ["layer-arrow-down"] = {3, 139},
    ["layer-arrow-up"] = {3, 140},
    ["layers"] = {3, 141},
    ["layers-2"] = {3, 142},
    ["layers-arrow-down"] = {3, 143},
    ["layers-arrow-up"] = {3, 144},
    ["layers-minus"] = {3, 145},
    ["layers-plus"] = {3, 146},
    ["layout-arrow-down"] = {3, 147},
    ["layout-arrow-right"] = {3, 148},
    ["layout-dashboard"] = {3, 149},
    ["layout-freeform"] = {3, 150},
    ["layout-grid"] = {3, 151},
    ["layout-grid-circles"] = {3, 152},
    ["layout-list"] = {3, 153},
    ["layout-panel-left"] = {3, 154},
    ["layout-panel-top"] = {3, 155},
    ["layout-template"] = {3, 156},
    ["leaf"] = {3, 157},
    ["leafy-green"] = {3, 158},
    ["lectern"] = {3, 159},
    ["lens"] = {3, 160},
    ["lens-concave"] = {3, 161},
    ["lens-convex"] = {3, 162},
    ["letters"] = {3, 163},
    ["library"] = {3, 164},
    ["library-big"] = {3, 165},
    ["life-buoy"] = {3, 166},
    ["ligature"] = {3, 167},
    ["lightbulb"] = {3, 168},
    ["lightbulb-off"] = {3, 169},
    ["lighthouse"] = {3, 170},
    ["line-dot-bottom-vertical"] = {3, 171},
    ["line-dot-left-horizontal"] = {3, 172},
    ["line-dot-right-horizontal"] = {3, 173},
    ["line-dot-top-vertical"] = {3, 174},
    ["line-squiggle"] = {3, 175},
    ["line-style"] = {3, 176},
    ["link"] = {3, 177},
    ["link-2"] = {3, 178},
    ["link-2-off"] = {3, 179},
    ["list"] = {3, 180},
    ["list-check"] = {3, 181},
    ["list-checks"] = {3, 182},
    ["list-chevrons-down-up"] = {3, 183},
    ["list-chevrons-up-down"] = {3, 184},
    ["list-clock"] = {3, 185},
    ["list-collapse"] = {3, 186},
    ["list-end"] = {3, 187},
    ["list-filter"] = {3, 188},
    ["list-filter-plus"] = {3, 189},
    ["list-indent-decrease"] = {3, 190},
    ["list-indent-increase"] = {3, 191},
    ["list-minus"] = {3, 192},
    ["list-music"] = {3, 193},
    ["list-ordered"] = {3, 194},
    ["list-plus"] = {3, 195},
    ["list-restart"] = {3, 196},
    ["list-sort-ascending"] = {3, 197},
    ["list-sort-descending"] = {3, 198},
    ["list-start"] = {3, 199},
    ["list-todo"] = {3, 200},
    ["list-tree"] = {3, 201},
    ["list-video"] = {3, 202},
    ["list-x"] = {3, 203},
    ["loader"] = {3, 204},
    ["loader-circle"] = {3, 205},
    ["loader-pinwheel"] = {3, 206},
    ["locate"] = {3, 207},
    ["locate-fixed"] = {3, 208},
    ["locate-off"] = {3, 209},
    ["lock"] = {3, 210},
    ["lock-keyhole"] = {3, 211},
    ["lock-keyhole-open"] = {3, 212},
    ["lock-open"] = {3, 213},
    ["log-in"] = {3, 214},
    ["log-out"] = {3, 215},
    ["logs"] = {3, 216},
    ["lollipop"] = {3, 217},
    ["luggage"] = {3, 218},
    ["magnet"] = {3, 219},
    ["mail"] = {3, 220},
    ["mail-badge"] = {3, 221},
    ["mail-check"] = {3, 222},
    ["mail-clock"] = {3, 223},
    ["mail-dot"] = {3, 224},
    ["mail-minus"] = {3, 225},
    ["mail-open"] = {3, 226},
    ["mail-pen"] = {3, 227},
    ["mail-plus"] = {3, 228},
    ["mail-question-mark"] = {3, 229},
    ["mail-search"] = {3, 230},
    ["mail-warning"] = {3, 231},
    ["mail-x"] = {3, 232},
    ["mailbox"] = {3, 233},
    ["mails"] = {3, 234},
    ["map"] = {3, 235},
    ["map-minus"] = {3, 236},
    ["map-pin"] = {3, 237},
    ["map-pin-check"] = {3, 238},
    ["map-pin-check-inside"] = {3, 239},
    ["map-pin-house"] = {3, 240},
    ["map-pin-minus"] = {3, 241},
    ["map-pin-minus-inside"] = {3, 242},
    ["map-pin-off"] = {3, 243},
    ["map-pin-pen"] = {3, 244},
    ["map-pin-plus"] = {3, 245},
    ["map-pin-plus-inside"] = {3, 246},
    ["map-pin-search"] = {3, 247},
    ["map-pin-x"] = {3, 248},
    ["map-pin-x-inside"] = {3, 249},
    ["map-pinned"] = {3, 250},
    ["map-plus"] = {3, 251},
    ["mars"] = {3, 252},
    ["mars-stroke"] = {3, 253},
    ["martini"] = {3, 254},
    ["maximize"] = {3, 255},
    ["maximize-2"] = {3, 256},
    ["medal"] = {3, 257},
    ["megaphone"] = {3, 258},
    ["megaphone-off"] = {3, 259},
    ["memory-stick"] = {3, 260},
    ["menu"] = {3, 261},
    ["merge"] = {3, 262},
    ["message-circle"] = {3, 263},
    ["message-circle-check"] = {3, 264},
    ["message-circle-code"] = {3, 265},
    ["message-circle-dashed"] = {3, 266},
    ["message-circle-dashed-check"] = {3, 267},
    ["message-circle-heart"] = {3, 268},
    ["message-circle-more"] = {3, 269},
    ["message-circle-off"] = {3, 270},
    ["message-circle-plus"] = {3, 271},
    ["message-circle-question-mark"] = {3, 272},
    ["message-circle-reply"] = {3, 273},
    ["message-circle-text"] = {3, 274},
    ["message-circle-warning"] = {3, 275},
    ["message-circle-x"] = {3, 276},
    ["message-square"] = {3, 277},
    ["message-square-check"] = {3, 278},
    ["message-square-code"] = {3, 279},
    ["message-square-dashed"] = {3, 280},
    ["message-square-diff"] = {3, 281},
    ["message-square-dot"] = {3, 282},
    ["message-square-heart"] = {3, 283},
    ["message-square-lock"] = {3, 284},
    ["message-square-more"] = {3, 285},
    ["message-square-off"] = {3, 286},
    ["message-square-plus"] = {3, 287},
    ["message-square-quote"] = {3, 288},
    ["message-square-reply"] = {3, 289},
    ["message-square-share"] = {3, 290},
    ["message-square-text"] = {3, 291},
    ["message-square-warning"] = {3, 292},
    ["message-square-x"] = {3, 293},
    ["messages-circle"] = {3, 294},
    ["messages-square"] = {3, 295},
    ["metronome"] = {3, 296},
    ["mic"] = {3, 297},
    ["mic-audio-lines"] = {3, 298},
    ["mic-off"] = {3, 299},
    ["mic-signal"] = {3, 300},
    ["mic-vocal"] = {3, 301},
    ["microchip"] = {3, 302},
    ["microscope"] = {3, 303},
    ["microwave"] = {3, 304},
    ["midi-port"] = {3, 305},
    ["milestone"] = {3, 306},
    ["milk"] = {3, 307},
    ["milk-off"] = {3, 308},
    ["minimize"] = {3, 309},
    ["minimize-2"] = {3, 310},
    ["minus"] = {3, 311},
    ["mirror-rectangular"] = {3, 312},
    ["mirror-round"] = {3, 313},
    ["monitor"] = {3, 314},
    ["monitor-check"] = {3, 315},
    ["monitor-cloud"] = {3, 316},
    ["monitor-cog"] = {3, 317},
    ["monitor-dot"] = {3, 318},
    ["monitor-down"] = {3, 319},
    ["monitor-off"] = {3, 320},
    ["monitor-pause"] = {3, 321},
    ["monitor-pc"] = {3, 322},
    ["monitor-play"] = {3, 323},
    ["monitor-smartphone"] = {3, 324},
    ["monitor-speaker"] = {3, 325},
    ["monitor-stop"] = {3, 326},
    ["monitor-up"] = {3, 327},
    ["monitor-x"] = {3, 328},
    ["moon"] = {3, 329},
    ["moon-star"] = {3, 330},
    ["mop"] = {3, 331},
    ["mop-sparkles"] = {3, 332},
    ["mosque"] = {3, 333},
    ["motorbike"] = {3, 334},
    ["mountain"] = {3, 335},
    ["mountain-snow"] = {3, 336},
    ["mouse"] = {3, 337},
    ["mouse-left"] = {3, 338},
    ["mouse-off"] = {3, 339},
    ["mouse-pointer"] = {3, 340},
    ["mouse-pointer-2"] = {3, 341},
    ["mouse-pointer-2-off"] = {3, 342},
    ["mouse-pointer-ban"] = {3, 343},
    ["mouse-pointer-click"] = {3, 344},
    ["mouse-right"] = {3, 345},
    ["mouth"] = {3, 346},
    ["mouth-off"] = {3, 347},
    ["move"] = {3, 348},
    ["move-3d"] = {3, 349},
    ["move-diagonal"] = {3, 350},
    ["move-diagonal-2"] = {3, 351},
    ["move-down"] = {3, 352},
    ["move-down-left"] = {3, 353},
    ["move-down-right"] = {3, 354},
    ["move-horizontal"] = {3, 355},
    ["move-left"] = {3, 356},
    ["move-right"] = {3, 357},
    ["move-up"] = {3, 358},
    ["move-up-left"] = {3, 359},
    ["move-up-right"] = {3, 360},
    ["move-vertical"] = {3, 361},
    ["navigation"] = {3, 362},
    ["navigation-2"] = {3, 363},
    ["navigation-2-off"] = {3, 364},
    ["navigation-off"] = {3, 365},
    ["nepali-rupee"] = {3, 366},
    ["network"] = {3, 367},
    ["newspaper"] = {3, 368},
    ["nfc"] = {3, 369},
    ["non-binary"] = {3, 370},
    ["notebook"] = {3, 371},
    ["notebook-dot"] = {3, 372},
    ["notebook-pen"] = {3, 373},
    ["notebook-tabs"] = {3, 374},
    ["notebook-text"] = {3, 375},
    ["notepad-text"] = {3, 376},
    ["notepad-text-dashed"] = {3, 377},
    ["nut"] = {3, 378},
    ["nut-off"] = {3, 379},
    ["octagon"] = {3, 380},
    ["octagon-alert"] = {3, 381},
    ["octagon-minus"] = {3, 382},
    ["octagon-pause"] = {3, 383},
    ["octagon-x"] = {3, 384},
    ["omega"] = {3, 385},
    ["option"] = {3, 386},
    ["orbit"] = {3, 387},
    ["origami"] = {3, 388},
    ["package"] = {3, 389},
    ["package-2"] = {3, 390},
    ["package-check"] = {3, 391},
    ["package-minus"] = {3, 392},
    ["package-open"] = {3, 393},
    ["package-plus"] = {3, 394},
    ["package-search"] = {3, 395},
    ["package-x"] = {3, 396},
    ["paint-bucket"] = {3, 397},
    ["paint-roller"] = {3, 398},
    ["paintbrush"] = {3, 399},
    ["paintbrush-vertical"] = {4, 0},
    ["palette"] = {4, 1},
    ["panda"] = {4, 2},
    ["panel-bottom"] = {4, 3},
    ["panel-bottom-close"] = {4, 4},
    ["panel-bottom-dashed"] = {4, 5},
    ["panel-bottom-open"] = {4, 6},
    ["panel-left"] = {4, 7},
    ["panel-left-close"] = {4, 8},
    ["panel-left-dashed"] = {4, 9},
    ["panel-left-open"] = {4, 10},
    ["panel-left-right-dashed"] = {4, 11},
    ["panel-right"] = {4, 12},
    ["panel-right-close"] = {4, 13},
    ["panel-right-dashed"] = {4, 14},
    ["panel-right-open"] = {4, 15},
    ["panel-top"] = {4, 16},
    ["panel-top-bottom-dashed"] = {4, 17},
    ["panel-top-close"] = {4, 18},
    ["panel-top-dashed"] = {4, 19},
    ["panel-top-open"] = {4, 20},
    ["panels-left-bottom"] = {4, 21},
    ["panels-right-bottom"] = {4, 22},
    ["panels-top-left"] = {4, 23},
    ["paper-bag"] = {4, 24},
    ["paperclip"] = {4, 25},
    ["parasol"] = {4, 26},
    ["parentheses"] = {4, 27},
    ["park"] = {4, 28},
    ["parking-meter"] = {4, 29},
    ["party-popper"] = {4, 30},
    ["pause"] = {4, 31},
    ["paw-print"] = {4, 32},
    ["pc-case"] = {4, 33},
    ["pen"] = {4, 34},
    ["pen-line"] = {4, 35},
    ["pen-off"] = {4, 36},
    ["pen-tool"] = {4, 37},
    ["pencil"] = {4, 38},
    ["pencil-line"] = {4, 39},
    ["pencil-off"] = {4, 40},
    ["pencil-ruler"] = {4, 41},
    ["pencil-sparkles"] = {4, 42},
    ["pentagon"] = {4, 43},
    ["percent"] = {4, 44},
    ["perfume-bottle"] = {4, 45},
    ["person-standing"] = {4, 46},
    ["phi"] = {4, 47},
    ["philippine-peso"] = {4, 48},
    ["phone"] = {4, 49},
    ["phone-call"] = {4, 50},
    ["phone-forwarded"] = {4, 51},
    ["phone-incoming"] = {4, 52},
    ["phone-log"] = {4, 53},
    ["phone-missed"] = {4, 54},
    ["phone-off"] = {4, 55},
    ["phone-outgoing"] = {4, 56},
    ["pi"] = {4, 57},
    ["piano"] = {4, 58},
    ["pickaxe"] = {4, 59},
    ["picture-in-picture"] = {4, 60},
    ["picture-in-picture-2"] = {4, 61},
    ["piggy-bank"] = {4, 62},
    ["pilcrow"] = {4, 63},
    ["pilcrow-left"] = {4, 64},
    ["pilcrow-right"] = {4, 65},
    ["pill"] = {4, 66},
    ["pill-bottle"] = {4, 67},
    ["pin"] = {4, 68},
    ["pin-off"] = {4, 69},
    ["pipette"] = {4, 70},
    ["pizza"] = {4, 71},
    ["plane"] = {4, 72},
    ["plane-landing"] = {4, 73},
    ["plane-takeoff"] = {4, 74},
    ["plant-pot"] = {4, 75},
    ["play"] = {4, 76},
    ["play-off"] = {4, 77},
    ["playing-card"] = {4, 78},
    ["playing-cards"] = {4, 79},
    ["playing-cards-fan"] = {4, 80},
    ["plug"] = {4, 81},
    ["plug-2"] = {4, 82},
    ["plug-zap"] = {4, 83},
    ["plus"] = {4, 84},
    ["pocket-knife"] = {4, 85},
    ["podium"] = {4, 86},
    ["pointer"] = {4, 87},
    ["pointer-off"] = {4, 88},
    ["popcorn"] = {4, 89},
    ["popsicle"] = {4, 90},
    ["pound-sterling"] = {4, 91},
    ["power"] = {4, 92},
    ["power-off"] = {4, 93},
    ["presentation"] = {4, 94},
    ["printer"] = {4, 95},
    ["printer-3d"] = {4, 96},
    ["printer-check"] = {4, 97},
    ["printer-x"] = {4, 98},
    ["projector"] = {4, 99},
    ["proportions"] = {4, 100},
    ["puzzle"] = {4, 101},
    ["pyramid"] = {4, 102},
    ["qr-code"] = {4, 103},
    ["quote"] = {4, 104},
    ["rabbit"] = {4, 105},
    ["radar"] = {4, 106},
    ["radiation"] = {4, 107},
    ["radical"] = {4, 108},
    ["radio"] = {4, 109},
    ["radio-off"] = {4, 110},
    ["radio-receiver"] = {4, 111},
    ["radio-tower"] = {4, 112},
    ["radius"] = {4, 113},
    ["rainbow"] = {4, 114},
    ["rat"] = {4, 115},
    ["ratio"] = {4, 116},
    ["receipt"] = {4, 117},
    ["receipt-cent"] = {4, 118},
    ["receipt-euro"] = {4, 119},
    ["receipt-indian-rupee"] = {4, 120},
    ["receipt-japanese-yen"] = {4, 121},
    ["receipt-pound-sterling"] = {4, 122},
    ["receipt-russian-ruble"] = {4, 123},
    ["receipt-swiss-franc"] = {4, 124},
    ["receipt-text"] = {4, 125},
    ["receipt-turkish-lira"] = {4, 126},
    ["rectangle-circle"] = {4, 127},
    ["rectangle-ellipsis"] = {4, 128},
    ["rectangle-goggles"] = {4, 129},
    ["rectangle-horizontal"] = {4, 130},
    ["rectangle-vertical"] = {4, 131},
    ["recycle"] = {4, 132},
    ["redo"] = {4, 133},
    ["redo-2"] = {4, 134},
    ["redo-dot"] = {4, 135},
    ["refresh-ccw"] = {4, 136},
    ["refresh-ccw-dot"] = {4, 137},
    ["refresh-cw"] = {4, 138},
    ["refresh-cw-off"] = {4, 139},
    ["refrigerator"] = {4, 140},
    ["regex"] = {4, 141},
    ["remove-formatting"] = {4, 142},
    ["repeat"] = {4, 143},
    ["repeat-1"] = {4, 144},
    ["repeat-2"] = {4, 145},
    ["repeat-off"] = {4, 146},
    ["replace"] = {4, 147},
    ["replace-all"] = {4, 148},
    ["reply"] = {4, 149},
    ["reply-all"] = {4, 150},
    ["rewind"] = {4, 151},
    ["ribbon"] = {4, 152},
    ["road"] = {4, 153},
    ["robot-arm"] = {4, 154},
    ["robot-vacuum"] = {4, 155},
    ["rocket"] = {4, 156},
    ["rocking-chair"] = {4, 157},
    ["roller-coaster"] = {4, 158},
    ["rose"] = {4, 159},
    ["rotate-3d"] = {4, 160},
    ["rotate-ccw"] = {4, 161},
    ["rotate-ccw-clock"] = {4, 162},
    ["rotate-ccw-key"] = {4, 163},
    ["rotate-ccw-square"] = {4, 164},
    ["rotate-cw"] = {4, 165},
    ["rotate-cw-clock"] = {4, 166},
    ["rotate-cw-fading-clock"] = {4, 167},
    ["rotate-cw-square"] = {4, 168},
    ["route"] = {4, 169},
    ["route-off"] = {4, 170},
    ["router"] = {4, 171},
    ["rows-2"] = {4, 172},
    ["rows-3"] = {4, 173},
    ["rows-4"] = {4, 174},
    ["rss"] = {4, 175},
    ["rugby-ball"] = {4, 176},
    ["ruler"] = {4, 177},
    ["ruler-dimension-line"] = {4, 178},
    ["russian-ruble"] = {4, 179},
    ["sailboat"] = {4, 180},
    ["salad"] = {4, 181},
    ["sandwich"] = {4, 182},
    ["satellite"] = {4, 183},
    ["satellite-dish"] = {4, 184},
    ["saudi-riyal"] = {4, 185},
    ["save"] = {4, 186},
    ["save-all"] = {4, 187},
    ["save-check"] = {4, 188},
    ["save-off"] = {4, 189},
    ["save-pen"] = {4, 190},
    ["save-plus"] = {4, 191},
    ["scale"] = {4, 192},
    ["scale-3d"] = {4, 193},
    ["scaling"] = {4, 194},
    ["scan"] = {4, 195},
    ["scan-barcode"] = {4, 196},
    ["scan-box"] = {4, 197},
    ["scan-eye"] = {4, 198},
    ["scan-face"] = {4, 199},
    ["scan-heart"] = {4, 200},
    ["scan-line"] = {4, 201},
    ["scan-qr-code"] = {4, 202},
    ["scan-search"] = {4, 203},
    ["scan-square"] = {4, 204},
    ["scan-text"] = {4, 205},
    ["school"] = {4, 206},
    ["scissors"] = {4, 207},
    ["scissors-line-dashed"] = {4, 208},
    ["scooter"] = {4, 209},
    ["scratch-blocks"] = {4, 210},
    ["screen-share"] = {4, 211},
    ["screen-share-off"] = {4, 212},
    ["screw"] = {4, 213},
    ["scroll"] = {4, 214},
    ["scroll-text"] = {4, 215},
    ["search"] = {4, 216},
    ["search-alert"] = {4, 217},
    ["search-check"] = {4, 218},
    ["search-code"] = {4, 219},
    ["search-slash"] = {4, 220},
    ["search-x"] = {4, 221},
    ["section"] = {4, 222},
    ["send"] = {4, 223},
    ["send-horizontal"] = {4, 224},
    ["send-to-back"] = {4, 225},
    ["separator-horizontal"] = {4, 226},
    ["separator-vertical"] = {4, 227},
    ["server"] = {4, 228},
    ["server-cog"] = {4, 229},
    ["server-crash"] = {4, 230},
    ["server-nas"] = {4, 231},
    ["server-off"] = {4, 232},
    ["server-plus"] = {4, 233},
    ["settings"] = {4, 234},
    ["settings-2"] = {4, 235},
    ["shapes"] = {4, 236},
    ["share"] = {4, 237},
    ["share-2"] = {4, 238},
    ["sheet"] = {4, 239},
    ["shell"] = {4, 240},
    ["shelving-unit"] = {4, 241},
    ["shield"] = {4, 242},
    ["shield-alert"] = {4, 243},
    ["shield-ban"] = {4, 244},
    ["shield-check"] = {4, 245},
    ["shield-cog"] = {4, 246},
    ["shield-cog-corner"] = {4, 247},
    ["shield-ellipsis"] = {4, 248},
    ["shield-half"] = {4, 249},
    ["shield-house"] = {4, 250},
    ["shield-keyhole"] = {4, 251},
    ["shield-lock"] = {4, 252},
    ["shield-minus"] = {4, 253},
    ["shield-off"] = {4, 254},
    ["shield-plus"] = {4, 255},
    ["shield-question-mark"] = {4, 256},
    ["shield-user"] = {4, 257},
    ["shield-x"] = {4, 258},
    ["ship"] = {4, 259},
    ["ship-cargo"] = {4, 260},
    ["ship-wheel"] = {4, 261},
    ["shirt"] = {4, 262},
    ["shopping-bag"] = {4, 263},
    ["shopping-basket"] = {4, 264},
    ["shopping-cart"] = {4, 265},
    ["shopping-cart-minus"] = {4, 266},
    ["shopping-cart-plus"] = {4, 267},
    ["shovel"] = {4, 268},
    ["shower-head"] = {4, 269},
    ["shredder"] = {4, 270},
    ["shrimp"] = {4, 271},
    ["shrimp-off"] = {4, 272},
    ["shrink"] = {4, 273},
    ["shrub"] = {4, 274},
    ["shuffle"] = {4, 275},
    ["sigma"] = {4, 276},
    ["signal"] = {4, 277},
    ["signal-high"] = {4, 278},
    ["signal-low"] = {4, 279},
    ["signal-medium"] = {4, 280},
    ["signal-zero"] = {4, 281},
    ["signature"] = {4, 282},
    ["signpost"] = {4, 283},
    ["signpost-big"] = {4, 284},
    ["siren"] = {4, 285},
    ["sixteenth-notes"] = {4, 286},
    ["skip-back"] = {4, 287},
    ["skip-forward"] = {4, 288},
    ["skull"] = {4, 289},
    ["slash"] = {4, 290},
    ["slice"] = {4, 291},
    ["sliders-horizontal"] = {4, 292},
    ["sliders-vertical"] = {4, 293},
    ["smartphone"] = {4, 294},
    ["smartphone-charging"] = {4, 295},
    ["smartphone-nfc"] = {4, 296},
    ["snail"] = {4, 297},
    ["snowflake"] = {4, 298},
    ["soap-dispenser-droplet"] = {4, 299},
    ["sofa"] = {4, 300},
    ["solar-panel"] = {4, 301},
    ["soup"] = {4, 302},
    ["space"] = {4, 303},
    ["spade"] = {4, 304},
    ["sparkle"] = {4, 305},
    ["sparkles"] = {4, 306},
    ["speaker"] = {4, 307},
    ["speech"] = {4, 308},
    ["spell-check"] = {4, 309},
    ["spell-check-2"] = {4, 310},
    ["spline"] = {4, 311},
    ["spline-pointer"] = {4, 312},
    ["split"] = {4, 313},
    ["spool"] = {4, 314},
    ["sport-shoe"] = {4, 315},
    ["spotlight"] = {4, 316},
    ["spray-can"] = {4, 317},
    ["sprout"] = {4, 318},
    ["square"] = {4, 319},
    ["square-activity"] = {4, 320},
    ["square-arrow-down"] = {4, 321},
    ["square-arrow-down-left"] = {4, 322},
    ["square-arrow-down-right"] = {4, 323},
    ["square-arrow-left"] = {4, 324},
    ["square-arrow-out-down-left"] = {4, 325},
    ["square-arrow-out-down-right"] = {4, 326},
    ["square-arrow-out-up-left"] = {4, 327},
    ["square-arrow-out-up-right"] = {4, 328},
    ["square-arrow-right"] = {4, 329},
    ["square-arrow-right-enter"] = {4, 330},
    ["square-arrow-right-exit"] = {4, 331},
    ["square-arrow-up"] = {4, 332},
    ["square-arrow-up-left"] = {4, 333},
    ["square-arrow-up-right"] = {4, 334},
    ["square-asterisk"] = {4, 335},
    ["square-bookmark"] = {4, 336},
    ["square-bottom-dashed-scissors"] = {4, 337},
    ["square-centerline-dashed-horizontal"] = {4, 338},
    ["square-centerline-dashed-vertical"] = {4, 339},
    ["square-chart-gantt"] = {4, 340},
    ["square-check"] = {4, 341},
    ["square-check-big"] = {4, 342},
    ["square-chevron-down"] = {4, 343},
    ["square-chevron-left"] = {4, 344},
    ["square-chevron-right"] = {4, 345},
    ["square-chevron-up"] = {4, 346},
    ["square-code"] = {4, 347},
    ["square-dashed"] = {4, 348},
    ["square-dashed-bottom"] = {4, 349},
    ["square-dashed-bottom-code"] = {4, 350},
    ["square-dashed-kanban"] = {4, 351},
    ["square-dashed-mouse-pointer"] = {4, 352},
    ["square-dashed-plus"] = {4, 353},
    ["square-dashed-text"] = {4, 354},
    ["square-dashed-top-solid"] = {4, 355},
    ["square-dashed-x"] = {4, 356},
    ["square-dashed-x-corner"] = {4, 357},
    ["square-dimensions"] = {4, 358},
    ["square-divide"] = {4, 359},
    ["square-dot"] = {4, 360},
    ["square-equal"] = {4, 361},
    ["square-exclamation-point"] = {4, 362},
    ["square-function"] = {4, 363},
    ["square-kanban"] = {4, 364},
    ["square-library"] = {4, 365},
    ["square-m"] = {4, 366},
    ["square-menu"] = {4, 367},
    ["square-minus"] = {4, 368},
    ["square-mouse-pointer"] = {4, 369},
    ["square-off"] = {4, 370},
    ["square-parking"] = {4, 371},
    ["square-parking-off"] = {4, 372},
    ["square-pause"] = {4, 373},
    ["square-pen"] = {4, 374},
    ["square-percent"] = {4, 375},
    ["square-pi"] = {4, 376},
    ["square-pilcrow"] = {4, 377},
    ["square-play"] = {4, 378},
    ["square-plus"] = {4, 379},
    ["square-power"] = {4, 380},
    ["square-radical"] = {4, 381},
    ["square-round-corner"] = {4, 382},
    ["square-scissors"] = {4, 383},
    ["square-sigma"] = {4, 384},
    ["square-slash"] = {4, 385},
    ["square-sparkles"] = {4, 386},
    ["square-split-horizontal"] = {4, 387},
    ["square-split-vertical"] = {4, 388},
    ["square-square"] = {4, 389},
    ["square-stack"] = {4, 390},
    ["square-star"] = {4, 391},
    ["square-stop"] = {4, 392},
    ["square-terminal"] = {4, 393},
    ["square-text"] = {4, 394},
    ["square-user"] = {4, 395},
    ["square-user-round"] = {4, 396},
    ["square-x"] = {4, 397},
    ["squares-exclude"] = {4, 398},
    ["squares-intersect"] = {4, 399},
    ["squares-subtract"] = {5, 0},
    ["squares-unite"] = {5, 1},
    ["squircle"] = {5, 2},
    ["squircle-dashed"] = {5, 3},
    ["squirrel"] = {5, 4},
    ["stamp"] = {5, 5},
    ["star"] = {5, 6},
    ["star-check"] = {5, 7},
    ["star-half"] = {5, 8},
    ["star-minus"] = {5, 9},
    ["star-off"] = {5, 10},
    ["star-plus"] = {5, 11},
    ["star-x"] = {5, 12},
    ["step-back"] = {5, 13},
    ["step-forward"] = {5, 14},
    ["stethoscope"] = {5, 15},
    ["sticker"] = {5, 16},
    ["sticky-note"] = {5, 17},
    ["sticky-note-check"] = {5, 18},
    ["sticky-note-minus"] = {5, 19},
    ["sticky-note-off"] = {5, 20},
    ["sticky-note-plus"] = {5, 21},
    ["sticky-note-x"] = {5, 22},
    ["sticky-notes"] = {5, 23},
    ["stone"] = {5, 24},
    ["store"] = {5, 25},
    ["stretch-horizontal"] = {5, 26},
    ["stretch-vertical"] = {5, 27},
    ["strikethrough"] = {5, 28},
    ["subscript"] = {5, 29},
    ["summary"] = {5, 30},
    ["sun"] = {5, 31},
    ["sun-dim"] = {5, 32},
    ["sun-medium"] = {5, 33},
    ["sun-moon"] = {5, 34},
    ["sun-snow"] = {5, 35},
    ["sunrise"] = {5, 36},
    ["sunset"] = {5, 37},
    ["superscript"] = {5, 38},
    ["swatch-book"] = {5, 39},
    ["swiss-franc"] = {5, 40},
    ["switch-camera"] = {5, 41},
    ["sword"] = {5, 42},
    ["swords"] = {5, 43},
    ["syringe"] = {5, 44},
    ["table"] = {5, 45},
    ["table-2"] = {5, 46},
    ["table-cells-merge"] = {5, 47},
    ["table-cells-split"] = {5, 48},
    ["table-columns-split"] = {5, 49},
    ["table-of-contents"] = {5, 50},
    ["table-properties"] = {5, 51},
    ["table-rows-split"] = {5, 52},
    ["tablet"] = {5, 53},
    ["tablet-smartphone"] = {5, 54},
    ["tablets"] = {5, 55},
    ["tag"] = {5, 56},
    ["tag-plus"] = {5, 57},
    ["tag-x"] = {5, 58},
    ["tags"] = {5, 59},
    ["tally-1"] = {5, 60},
    ["tally-2"] = {5, 61},
    ["tally-3"] = {5, 62},
    ["tally-4"] = {5, 63},
    ["tally-5"] = {5, 64},
    ["tangent"] = {5, 65},
    ["target"] = {5, 66},
    ["telescope"] = {5, 67},
    ["tent"] = {5, 68},
    ["tent-tree"] = {5, 69},
    ["terminal"] = {5, 70},
    ["test-tube"] = {5, 71},
    ["test-tube-diagonal"] = {5, 72},
    ["test-tubes"] = {5, 73},
    ["text-align-center"] = {5, 74},
    ["text-align-end"] = {5, 75},
    ["text-align-justify"] = {5, 76},
    ["text-align-justify-center"] = {5, 77},
    ["text-align-justify-end"] = {5, 78},
    ["text-align-justify-start"] = {5, 79},
    ["text-align-start"] = {5, 80},
    ["text-cursor"] = {5, 81},
    ["text-cursor-input"] = {5, 82},
    ["text-initial"] = {5, 83},
    ["text-quote"] = {5, 84},
    ["text-search"] = {5, 85},
    ["text-wrap"] = {5, 86},
    ["theater"] = {5, 87},
    ["thermometer"] = {5, 88},
    ["thermometer-snowflake"] = {5, 89},
    ["thermometer-sun"] = {5, 90},
    ["thumbs-down"] = {5, 91},
    ["thumbs-up"] = {5, 92},
    ["tic-tac-toe"] = {5, 93},
    ["ticket"] = {5, 94},
    ["ticket-check"] = {5, 95},
    ["ticket-minus"] = {5, 96},
    ["ticket-percent"] = {5, 97},
    ["ticket-plus"] = {5, 98},
    ["ticket-slash"] = {5, 99},
    ["ticket-x"] = {5, 100},
    ["tickets"] = {5, 101},
    ["tickets-plane"] = {5, 102},
    ["timeline"] = {5, 103},
    ["timer"] = {5, 104},
    ["timer-off"] = {5, 105},
    ["timer-reset"] = {5, 106},
    ["toggle-left"] = {5, 107},
    ["toggle-right"] = {5, 108},
    ["toilet"] = {5, 109},
    ["tool-case"] = {5, 110},
    ["toolbox"] = {5, 111},
    ["toothbrush"] = {5, 112},
    ["toothbrush-sparkles"] = {5, 113},
    ["tornado"] = {5, 114},
    ["torus"] = {5, 115},
    ["touchpad"] = {5, 116},
    ["touchpad-off"] = {5, 117},
    ["towel-rack"] = {5, 118},
    ["tower-control"] = {5, 119},
    ["toy-brick"] = {5, 120},
    ["tractor"] = {5, 121},
    ["traffic-cone"] = {5, 122},
    ["trailer"] = {5, 123},
    ["train-front"] = {5, 124},
    ["train-front-tunnel"] = {5, 125},
    ["train-track"] = {5, 126},
    ["tram-front"] = {5, 127},
    ["transgender"] = {5, 128},
    ["trash"] = {5, 129},
    ["trash-off"] = {5, 130},
    ["tree-deciduous"] = {5, 131},
    ["tree-palm"] = {5, 132},
    ["tree-pine"] = {5, 133},
    ["trees"] = {5, 134},
    ["trending-down"] = {5, 135},
    ["trending-up"] = {5, 136},
    ["trending-up-down"] = {5, 137},
    ["triangle"] = {5, 138},
    ["triangle-alert"] = {5, 139},
    ["triangle-dashed"] = {5, 140},
    ["triangle-right"] = {5, 141},
    ["triangles-centerline-dashed-horizontal"] = {5, 142},
    ["triangles-centerline-dashed-vertical"] = {5, 143},
    ["trophy"] = {5, 144},
    ["truck"] = {5, 145},
    ["truck-electric"] = {5, 146},
    ["tube-lotion"] = {5, 147},
    ["turkish-lira"] = {5, 148},
    ["turntable"] = {5, 149},
    ["turtle"] = {5, 150},
    ["tv"] = {5, 151},
    ["tv-minimal"] = {5, 152},
    ["tv-minimal-play"] = {5, 153},
    ["type"] = {5, 154},
    ["type-outline"] = {5, 155},
    ["umbrella"] = {5, 156},
    ["umbrella-off"] = {5, 157},
    ["underline"] = {5, 158},
    ["undo"] = {5, 159},
    ["undo-2"] = {5, 160},
    ["undo-dot"] = {5, 161},
    ["unfold-horizontal"] = {5, 162},
    ["unfold-vertical"] = {5, 163},
    ["ungroup"] = {5, 164},
    ["university"] = {5, 165},
    ["unlink"] = {5, 166},
    ["unlink-2"] = {5, 167},
    ["unplug"] = {5, 168},
    ["upload"] = {5, 169},
    ["usb"] = {5, 170},
    ["usb-c-port"] = {5, 171},
    ["user"] = {5, 172},
    ["user-check"] = {5, 173},
    ["user-cog"] = {5, 174},
    ["user-group"] = {5, 175},
    ["user-key"] = {5, 176},
    ["user-lock"] = {5, 177},
    ["user-minus"] = {5, 178},
    ["user-pen"] = {5, 179},
    ["user-plus"] = {5, 180},
    ["user-round"] = {5, 181},
    ["user-round-arrow-left"] = {5, 182},
    ["user-round-check"] = {5, 183},
    ["user-round-cog"] = {5, 184},
    ["user-round-group"] = {5, 185},
    ["user-round-key"] = {5, 186},
    ["user-round-minus"] = {5, 187},
    ["user-round-pen"] = {5, 188},
    ["user-round-plus"] = {5, 189},
    ["user-round-search"] = {5, 190},
    ["user-round-star"] = {5, 191},
    ["user-round-x"] = {5, 192},
    ["user-search"] = {5, 193},
    ["user-shield"] = {5, 194},
    ["user-star"] = {5, 195},
    ["user-x"] = {5, 196},
    ["users"] = {5, 197},
    ["users-collaboration"] = {5, 198},
    ["users-round"] = {5, 199},
    ["users-round-collaboration"] = {5, 200},
    ["utensils"] = {5, 201},
    ["utensils-crossed"] = {5, 202},
    ["utility-pole"] = {5, 203},
    ["van"] = {5, 204},
    ["variable"] = {5, 205},
    ["vault"] = {5, 206},
    ["vector-polygon"] = {5, 207},
    ["vector-square"] = {5, 208},
    ["vegan"] = {5, 209},
    ["venetian-mask"] = {5, 210},
    ["venus"] = {5, 211},
    ["venus-and-mars"] = {5, 212},
    ["vibrate"] = {5, 213},
    ["vibrate-off"] = {5, 214},
    ["video"] = {5, 215},
    ["video-off"] = {5, 216},
    ["videotape"] = {5, 217},
    ["view"] = {5, 218},
    ["virus"] = {5, 219},
    ["virus-off"] = {5, 220},
    ["voicemail"] = {5, 221},
    ["volleyball"] = {5, 222},
    ["volume"] = {5, 223},
    ["volume-1"] = {5, 224},
    ["volume-2"] = {5, 225},
    ["volume-off"] = {5, 226},
    ["volume-x"] = {5, 227},
    ["vote"] = {5, 228},
    ["wallet"] = {5, 229},
    ["wallet-cards"] = {5, 230},
    ["wallet-minimal"] = {5, 231},
    ["wallpaper"] = {5, 232},
    ["wand"] = {5, 233},
    ["wand-sparkles"] = {5, 234},
    ["warehouse"] = {5, 235},
    ["washing-machine"] = {5, 236},
    ["watch"] = {5, 237},
    ["waves-arrow-down"] = {5, 238},
    ["waves-arrow-up"] = {5, 239},
    ["waves-horizontal"] = {5, 240},
    ["waves-ladder"] = {5, 241},
    ["waves-vertical"] = {5, 242},
    ["waypoints"] = {5, 243},
    ["webcam"] = {5, 244},
    ["webcam-off"] = {5, 245},
    ["webhook"] = {5, 246},
    ["webhook-off"] = {5, 247},
    ["weight"] = {5, 248},
    ["weight-tilde"] = {5, 249},
    ["wheat"] = {5, 250},
    ["wheat-off"] = {5, 251},
    ["whistle"] = {5, 252},
    ["whole-word"] = {5, 253},
    ["wifi"] = {5, 254},
    ["wifi-cog"] = {5, 255},
    ["wifi-high"] = {5, 256},
    ["wifi-lock"] = {5, 257},
    ["wifi-low"] = {5, 258},
    ["wifi-off"] = {5, 259},
    ["wifi-pen"] = {5, 260},
    ["wifi-sync"] = {5, 261},
    ["wifi-zero"] = {5, 262},
    ["wind"] = {5, 263},
    ["wind-arrow-down"] = {5, 264},
    ["wind-arrow-up"] = {5, 265},
    ["wine"] = {5, 266},
    ["wine-off"] = {5, 267},
    ["workflow"] = {5, 268},
    ["worm"] = {5, 269},
    ["wrench"] = {5, 270},
    ["wrench-off"] = {5, 271},
    ["x"] = {5, 272},
    ["x-line-top"] = {5, 273},
    ["zap"] = {5, 274},
    ["zap-off"] = {5, 275},
    ["zodiac-aquarius"] = {5, 276},
    ["zodiac-aries"] = {5, 277},
    ["zodiac-cancer"] = {5, 278},
    ["zodiac-capricorn"] = {5, 279},
    ["zodiac-gemini"] = {5, 280},
    ["zodiac-leo"] = {5, 281},
    ["zodiac-libra"] = {5, 282},
    ["zodiac-ophiuchus"] = {5, 283},
    ["zodiac-pisces"] = {5, 284},
    ["zodiac-sagittarius"] = {5, 285},
    ["zodiac-scorpio"] = {5, 286},
    ["zodiac-taurus"] = {5, 287},
    ["zodiac-virgo"] = {5, 288},
    ["zoom-in"] = {5, 289},
    ["zoom-out"] = {5, 290},
}

local LucideIcons = {
    Source = "https://lucide.dev",
    Count = 1891,
}

local function normalizeName(iconName)
    if type(iconName) ~= "string" then return nil end
    local name = string.lower(iconName)
    name = string.gsub(name, "[%s_]+", "-")
    name = string.gsub(name, "%-+", "-")
    name = string.gsub(name, "^%-", "")
    name = string.gsub(name, "%-$", "")
    return name
end

local function getIconData(iconName)
    local normalized = normalizeName(iconName)
    if not normalized then return nil end
    return ICONS[normalized]
end

function LucideIcons.Has(iconName)
    return getIconData(iconName) ~= nil
end

function LucideIcons.Set(image, iconName, color)
    assert(typeof(image) == "Instance" and (image:IsA("ImageLabel") or image:IsA("ImageButton")), "LucideIcons.Set expects an ImageLabel or ImageButton")
    local data = getIconData(iconName)
    if not data then return false end
    image.Image = ATLAS_IMAGES[data[1]]
    image.ImageRectOffset = Vector2.new((data[2] % ICON_COLUMNS) * ICON_CELL_SIZE, math.floor(data[2] / ICON_COLUMNS) * ICON_CELL_SIZE)
    image.ImageRectSize = Vector2.new(ICON_CELL_SIZE, ICON_CELL_SIZE)
    image.ScaleType = Enum.ScaleType.Fit
    if color then image.ImageColor3 = color end
    return true
end

function LucideIcons.Create(parent, iconName, options)
    assert(typeof(parent) == "Instance", "LucideIcons.Create expects a parent Instance")
    options = options or {}
    assert(type(options) == "table", "LucideIcons.Create options must be a table")
    local className = options.ClassName == "ImageButton" and "ImageButton" or "ImageLabel"
    local image = Instance.new(className)
    image.Name = options.Name or ((normalizeName(iconName) or "unknown") .. "Icon")
    image.AnchorPoint = options.AnchorPoint or Vector2.new(0, 0)
    image.Position = options.Position or UDim2.new()
    image.Size = options.Size or UDim2.fromOffset(20, 20)
    image.ZIndex = options.ZIndex or ((parent:IsA("GuiObject") and parent.ZIndex or 1) + 1)
    image.BackgroundTransparency = options.BackgroundTransparency == nil and 1 or options.BackgroundTransparency
    image.ImageTransparency = options.ImageTransparency or 0
    image.ImageColor3 = options.Color or Color3.fromRGB(190, 220, 35)
    if image:IsA("ImageButton") then image.AutoButtonColor = false end
    image.Parent = parent
    if not LucideIcons.Set(image, iconName, options.Color) then
        image:Destroy()
        warn("[LucideIcons] Icon not found: " .. tostring(iconName))
        return nil
    end
    return image
end

function LucideIcons.List()
    local names = {}
    for name in pairs(ICONS) do table.insert(names, name) end
    table.sort(names)
    return names
end

return LucideIcons
end)()

-- ===== Contrôles réutilisables et paramètres par défaut =====
local ControlLibrary = {
    Title = "Controls overview",
    Description = "Examples for the available control types.",
    Icons = LucideIcons,
    Theme = {
        card = Color3.fromRGB(24, 25, 27),
        line = Color3.fromRGB(45, 46, 48),
        text = Color3.fromRGB(242, 243, 244),
        muted = Color3.fromRGB(154, 156, 158),
        lime = Color3.fromRGB(190, 220, 35),
        limeDark = Color3.fromRGB(92, 111, 19),
        control = Color3.fromRGB(39, 40, 42),
        hover = Color3.fromRGB(57, 59, 61),
        danger = Color3.fromRGB(235, 83, 91),
    },
    Examples = {
        {Type = "Button", Label = "Button", Description = "Run a sample action.", Text = "Click me", Notify = true, Icon = "circle-play"},
        {Type = "Toggle", Label = "Toggle", Description = "Switch a setting on or off.", Value = true, Notify = true, Icon = "toggle-right"},
        {Type = "Slider", Label = "Slider", Description = "Adjust a numeric value.", Min = 0, Max = 100, Step = 1, Value = 40, Suffix = "%", Icon = "sliders-horizontal"},
        {Type = "Input", Label = "Input", Description = "Enter a text value.", Placeholder = "Type here...", Value = "", Icon = "text-cursor-input"},
        {Type = "Dropdown", Label = "Dropdown", Description = "Open the list and scroll through options.", Options = {"Nearest", "Lowest HP", "Manual", "Crosshair", "Random", "Lowest Health", "Farthest"}, Value = "Nearest", VisibleOptions = 4, Icon = "list-filter"},
        {Type = "Palette", Label = "Palette", Description = "Select a color swatch.", Value = Color3.fromRGB(190, 220, 35), Colors = {Color3.fromRGB(190, 220, 35), Color3.fromRGB(70, 170, 255), Color3.fromRGB(240, 90, 110), Color3.fromRGB(180, 105, 255), Color3.fromRGB(244, 183, 64)}, Icon = "palette"},
    },
    SettingsExamples = {
        {Type = "Dropdown", Label = "Theme", Description = "Choose a theme preset.", Options = {"Dark", "Light", "Ocean", "Violet", "Sunset", "Sky"}, Value = "Dark", VisibleOptions = 3, ApplyTheme = true, Icon = "palette"},
        {Type = "Keybind", Label = "Hide UI", Description = "Press the key to hide or show the interface.", Value = initialHideKey, Icon = "keyboard"},
        {Type = "ColorPicker", Label = "Accent Color", Description = "Choose the color used by the interface.", Value = Color3.fromRGB(190, 220, 35), Colors = {Color3.fromRGB(190, 220, 35), Color3.fromRGB(70, 170, 255), Color3.fromRGB(240, 90, 110), Color3.fromRGB(180, 105, 255)}, Icon = "pipette"},
    },
}

local themeRefreshers = {}

function ControlLibrary.SetThemePalette(palette, paletteRoles)
    assert(type(palette) == "table", "SetThemePalette expects a palette table")
    paletteRoles = paletteRoles or {}

    for themeRole in pairs(ControlLibrary.Theme) do
        local paletteRole = paletteRoles[themeRole] or themeRole
        local color = palette[paletteRole]
        if typeof(color) == "Color3" then
            ControlLibrary.Theme[themeRole] = color
        end
    end

    for page, refresh in pairs(themeRefreshers) do
        if page.Parent then
            refresh()
        else
            themeRefreshers[page] = nil
        end
    end
end

local function create(className, parent, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do object[key] = value end
    applyUiTypography(object)
    object.Parent = parent
    return object
end

local function round(object, radius)
    create("UICorner", object, {CornerRadius = UDim.new(0, radius or 8)})
end

local glassEnabled = false
local glassSurfaces = {}
local tween

local function applyGlassSurface(frame, radius)
    local theme = ControlLibrary.Theme
    frame:SetAttribute("HipoGlassSurface", true)
    frame.BackgroundTransparency = glassEnabled and 0.02 or 0
    round(frame, radius or 12)
    local gradient = create("UIGradient", frame, {
        Name = "GlassGradient",
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 246, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 225, 242)),
        }),
        Transparency = glassEnabled and NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.04),
            NumberSequenceKeypoint.new(1, 0.08),
        }) or NumberSequence.new(1),
        Rotation = 90,
    })
    local outline = create("UIStroke", frame, {
        Name = "GlassOutline",
        Color = glassEnabled and Color3.fromRGB(190, 205, 224) or theme.line,
        Transparency = glassEnabled and 0.46 or 0.4,
        Thickness = 1,
    })
    frame:SetAttribute("HipoGlassActive", glassEnabled)
    outline:SetAttribute("HipoGlassActive", glassEnabled)
    table.insert(glassSurfaces, {Frame = frame, Gradient = gradient, Outline = outline, Theme = theme})
end

function ControlLibrary.SetGlassEnabled(enabled)
    glassEnabled = enabled == true
    for index = #glassSurfaces, 1, -1 do
        local surface = glassSurfaces[index]
        if not surface.Frame.Parent then
            table.remove(glassSurfaces, index)
        else
            local isGlass = glassEnabled
            surface.Frame:SetAttribute("HipoGlassActive", isGlass)
            surface.Outline:SetAttribute("HipoGlassActive", isGlass)
            surface.Gradient.Transparency = isGlass and NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.04),
                NumberSequenceKeypoint.new(1, 0.08),
            }) or NumberSequence.new(1)
            tween(surface.Frame, {BackgroundTransparency = isGlass and 0.02 or 0})
            tween(surface.Outline, {
                Color = isGlass and Color3.fromRGB(190, 205, 224) or surface.Theme.line,
                Transparency = isGlass and 0.46 or 0.4,
            })
        end
    end
end

tween = function(object, properties)
    local motion = TweenService:Create(object, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
    motion:Play()
end

local notificationSequence = 0
local NOTIFICATION_ENTER_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local NOTIFICATION_EXIT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function showControlNotification(parent, title, message, theme, accentColor)
    local screenGui = parent
    while screenGui and not screenGui:IsA("ScreenGui") do
        screenGui = screenGui.Parent
    end

    title = tostring(title or "Notification")
    message = tostring(message or "")
    theme = theme or ControlLibrary.Theme

    if not screenGui then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = message,
                Duration = 2,
            })
        end)
        return
    end

    local host = screenGui:FindFirstChild("ControlsNotificationHost")
    if not host or not host:IsA("Frame") then
        host = create("Frame", screenGui, {
            Name = "ControlsNotificationHost",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -16, 0, 16),
            Size = UDim2.fromOffset(272, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 50,
        })
        create("UIListLayout", host, {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Top,
        })
    end

    notificationSequence += 1
    local toastItem = create("Frame", host, {
        Name = "ControlNotificationItem",
        LayoutOrder = notificationSequence,
        Size = UDim2.fromOffset(272, 50),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })
    local toast = create("CanvasGroup", toastItem, {
        Name = "ControlNotification",
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = theme.card or Color3.fromRGB(24, 25, 27),
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 51,
    })
    round(toast, 10)
    create("UIStroke", toast, {
        Color = theme.line or Color3.fromRGB(45, 46, 48),
        Transparency = 0.3,
        Thickness = 1,
    })
    local accent = create("Frame", toast, {
        Position = UDim2.fromOffset(0, 8),
        Size = UDim2.new(0, 3, 1, -16),
        BackgroundColor3 = accentColor or theme.lime or Color3.fromRGB(190, 220, 35),
        BorderSizePixel = 0,
        ZIndex = 52,
    })
    round(accent, 2)
    create("TextLabel", toast, {
        Position = UDim2.fromOffset(14, 7),
        Size = UDim2.new(1, -24, 0, 17),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = theme.text or Color3.fromRGB(242, 243, 244),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 52,
    })
    create("TextLabel", toast, {
        Position = UDim2.fromOffset(14, 26),
        Size = UDim2.new(1, -24, 0, 15),
        BackgroundTransparency = 1,
        Text = message,
        TextColor3 = theme.muted or Color3.fromRGB(154, 156, 158),
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 52,
    })
    local scale = create("UIScale", toast, {Scale = 0.96})
    TweenService:Create(toast, NOTIFICATION_ENTER_TWEEN, {
        GroupTransparency = 0,
        Position = UDim2.fromOffset(0, 0),
    }):Play()
    TweenService:Create(scale, NOTIFICATION_ENTER_TWEEN, {Scale = 1}):Play()

    local visibleToastItems = {}
    for _, child in ipairs(host:GetChildren()) do
        if child:IsA("Frame") and child.Name == "ControlNotificationItem" then
            table.insert(visibleToastItems, child)
        end
    end
    table.sort(visibleToastItems, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    while #visibleToastItems > 3 do
        local oldestToast = table.remove(visibleToastItems, 1)
        oldestToast:Destroy()
    end

    scheduleSessionTask(2, function()
        if not toastItem.Parent then return end
        local exitTween = TweenService:Create(toast, NOTIFICATION_EXIT_TWEEN, {
            GroupTransparency = 1,
            Position = UDim2.fromOffset(14, 0),
        })
        local shrinkTween = TweenService:Create(scale, NOTIFICATION_EXIT_TWEEN, {Scale = 0.96})
        exitTween.Completed:Connect(function(playbackState)
            if playbackState == Enum.PlaybackState.Completed and toastItem.Parent then
                toastItem:Destroy()
            end
        end)
        exitTween:Play()
        shrinkTween:Play()
    end)
end

local function makeButton(parent, text, width, bindHover)
    local theme = ControlLibrary.Theme
    local button = create("TextButton", parent, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(width or 132, 30),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        AutoButtonColor = false,
    })
    round(button, 8)
    if bindHover ~= false then
        button.MouseEnter:Connect(function() tween(button, {BackgroundColor3 = theme.hover}) end)
        button.MouseLeave:Connect(function() tween(button, {BackgroundColor3 = theme.control}) end)
    end
    return button
end

local SectionMethods = {}
SectionMethods.__index = SectionMethods

local function controlDefault(config, fallback)
    if config.Default ~= nil then return config.Default end
    if config.Value ~= nil then return config.Value end
    return fallback
end

local function exposeSectionHandle(handle, config)
    function handle:Get() return self:GetValue() end
    function handle:Set(value, silent)
        local before = self:GetValue()
        local result = self:SetValue(value)
        if result == nil then return false end
        local after = self:GetValue()
        if after ~= before and silent ~= true and type(config.Callback) == "function" then
            spawnSessionTask(config.Callback, after)
        end
        return true, after
    end
    return handle
end

-- Creates a reusable section. Example:
-- local window = ControlLibrary.new(parent, {Title = "My controls"})
-- local section = window:Section("General", "settings")
-- section:Toggle({Text = "Enabled", Icon = "toggle-right", Default = false, Callback = function(value) print(value) end})
-- section:Button({Text = "Rejoin server", Icon = "log-in", Callback = function() print("Clicked") end})
-- section:Button({Text = "Refresh data", ButtonText = "Refresh", ButtonIcon = "refresh-cw", Click = {Rotate = 360}, Callback = refresh})
-- section:Button({Text = "Save configuration", ButtonText = "Save", ButtonIcon = "save", Style = "filled", Click = {Icon = "check", Text = "Saved", Hold = 1.4}, Callback = saveConfig})
-- Set Notify = true to show a toast after a button press or toggle change; use NotifyText to customize its message.
-- Styles: outline (default), filled, ghost, soft; Primary = true is shorthand for filled.
-- Danger = true, Disabled, DisabledReason, Tooltip, Hover, HoverColor and HoverFill are also supported.
-- Hover and Click accept Rotate, Scale, Icon, Text and Hold; Rotate, Scale and Icon need ButtonIcon.
-- HoverColor and HoverFill customize outline only. Icon is the row icon; ButtonIcon sits inside the button.
-- Button handles expose SetText, Show, Hide, SetVisible(bool) and Destroy. Keep one primary action per section.
function ControlLibrary:CreateSection(parent, title, options)
    assert(typeof(parent) == "Instance", "CreateSection expects a parent Instance")
    options = type(options) == "table" and options or {}
    local iconName = options.Icon
    local hasIcon = type(iconName) == "string" and LucideIcons.Has(iconName)
    local theme = self.Theme or ControlLibrary.Theme
    local card = create("Frame", parent, {
        Name = (title or "Section") .. "Section",
        Size = UDim2.new(1, -12, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.card,
        BorderSizePixel = 0,
    })
    applyGlassSurface(card, 12)
    create("UIListLayout", card, {
        Padding = UDim.new(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
    })
    local header = create("Frame", card, {
        Name = "SectionHeader",
        LayoutOrder = 0,
        Size = UDim2.new(1, -16, 0, 36),
        BackgroundTransparency = 1,
    })
    create("TextLabel", header, {
        Name = "SectionTitle",
        Position = UDim2.fromOffset(hasIcon and 28 or 0, 0),
        Size = UDim2.new(1, hasIcon and -28 or 0, 1, 0),
        BackgroundTransparency = 1,
        Text = title or "Section",
        TextColor3 = theme.text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    if hasIcon then
        LucideIcons.Create(header, iconName, {
            Name = "SectionIcon",
            Position = UDim2.fromOffset(2, 10),
            Size = UDim2.fromOffset(16, 16),
            Color = theme.lime,
        })
    end
    local content = create("Frame", card, {
        Name = "Controls",
        LayoutOrder = 1,
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    })
    create("UIListLayout", content, {
        Padding = UDim.new(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    return setmetatable({Frame = card, Content = content, Theme = theme, Icon = iconName, _layoutOrder = 0}, SectionMethods)
end

function ControlLibrary:Section(parent, title, options)
    return self:CreateSection(parent, title, options)
end

local WindowMethods = {}
WindowMethods.__index = WindowMethods

local function createSectionColumns(parent, singleColumnBelow)
    local columnsFrame = create("Frame", parent, {
        Name = "SectionColumns",
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
    })
    local columns = {}

    for index, name in ipairs({"LeftColumn", "RightColumn"}) do
        local column = create("Frame", columnsFrame, {
            Name = name,
            Position = index == 1 and UDim2.fromOffset(0, 0) or UDim2.new(0.5, 4, 0, 0),
            Size = UDim2.new(0.5, -4, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        })
        local columnLayout = create("UIListLayout", column, {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        columns[index] = {
            Frame = column,
            Layout = columnLayout,
            Count = 0,
        }
    end

    local sectionLayout = {
        Frame = columnsFrame,
        Columns = columns,
        Items = {},
        SingleColumnBelow = tonumber(singleColumnBelow) or 680,
    }

    local function resizeColumnsFrame()
        local contentHeight = math.max(
            columns[1].Layout.AbsoluteContentSize.Y,
            columns[2].Layout.AbsoluteContentSize.Y
        )
        columnsFrame.Size = UDim2.new(1, 0, 0, contentHeight)
    end

    function sectionLayout:Reflow()
        local left, right = self.Columns[1], self.Columns[2]
        local singleColumn = parent.AbsoluteSize.X < self.SingleColumnBelow
        right.Frame.Visible = not singleColumn
        left.Frame.Position = UDim2.fromOffset(0, 0)
        left.Frame.Size = singleColumn and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -4, 0, 0)
        right.Frame.Position = UDim2.new(0.5, 4, 0, 0)
        right.Frame.Size = UDim2.new(0.5, -4, 0, 0)
        left.Count, right.Count = 0, 0

        for index, item in ipairs(self.Items) do
            local columnIndex = singleColumn and 1 or ((index - 1) % 2 + 1)
            local column = self.Columns[columnIndex]
            column.Count += 1
            item.Frame.Parent = column.Frame
            item.Frame.LayoutOrder = column.Count
        end

        resizeColumnsFrame()
    end

    function sectionLayout:Add(section)
        self.Items[#self.Items + 1] = {Frame = section.Frame}
        self:Reflow()
    end

    for _, column in ipairs(columns) do
        column.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeColumnsFrame)
    end
    parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        sectionLayout:Reflow()
    end)
    sectionLayout:Reflow()

    return sectionLayout
end

-- Creates a controls window inside an existing GuiObject.
function ControlLibrary.new(parent, options)
    assert(typeof(parent) == "Instance", "ControlLibrary.new expects a parent GuiObject")
    options = type(options) == "table" and options or {}
    local theme = ControlLibrary.Theme
    local root = create("ScrollingFrame", parent, {
        Name = options.Name or "ControlsLibrary",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = theme.lime,
        Active = true,
    })
    create("UIListLayout", root, {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder})
    local sectionLayout = createSectionColumns(root, options.SingleColumnBelow)
    local window = setmetatable({
        Frame = root,
        Content = root,
        Sections = {},
        Title = options.Title,
        _SectionLayout = sectionLayout,
    }, WindowMethods)
    if type(options.Title) == "string" and options.Title ~= "" then
        create("TextLabel", root, {
            Name = "WindowTitle",
            LayoutOrder = 0,
            Size = UDim2.new(1, -12, 0, 34),
            BackgroundTransparency = 1,
            Text = options.Title,
            TextColor3 = theme.text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 16,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
    end
    return window
end

function WindowMethods:Section(name, iconName, options)
    if type(iconName) == "table" and options == nil then options, iconName = iconName, nil end
    local sectionOptions = {}
    for key, value in pairs(options or {}) do sectionOptions[key] = value end
    if iconName and sectionOptions.Icon == nil then sectionOptions.Icon = iconName end
    local section = ControlLibrary:CreateSection(self._SectionLayout.Frame, name, sectionOptions)
    section.Window = self
    section.Icon = sectionOptions.Icon
    self._SectionLayout:Add(section)
    table.insert(self.Sections, section)
    return section
end

function WindowMethods:Destroy()
    if self.Frame and self.Frame.Parent then self.Frame:Destroy() end
    self.Sections = {}
end

function SectionMethods:Toggle(config)
    config = config or {}
    assert(type(config) == "table", "Section:Toggle expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    self._layoutOrder = self._layoutOrder + 1

    local hasDescription = type(config.Description) == "string" and config.Description ~= ""
    local hasIcon = type(config.Icon) == "string" and LucideIcons.Has(config.Icon)
    local labelX = hasIcon and 36 or 12
    local labelWidth = hasIcon and -96 or -72
    local row = create("Frame", self.Content, {
        Name = "ToggleRow",
        LayoutOrder = self._layoutOrder,
        Size = UDim2.new(1, 0, 0, hasDescription and 58 or 44),
        BackgroundTransparency = 1,
    })
    create("TextLabel", row, {
        Position = hasDescription and UDim2.fromOffset(labelX, 6) or UDim2.fromOffset(labelX, 0),
        Size = hasDescription and UDim2.new(1, labelWidth, 0, 21) or UDim2.new(1, labelWidth, 1, 0),
        BackgroundTransparency = 1,
        Text = config.Text or "Toggle",
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    if hasDescription then
        create("TextLabel", row, {
            Position = UDim2.fromOffset(labelX, 29),
            Size = UDim2.new(1, labelWidth, 0, 17),
            BackgroundTransparency = 1,
            Text = config.Description,
            TextColor3 = theme.muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
    end
    if hasIcon then
        LucideIcons.Create(row, config.Icon, {
            Name = "ToggleIcon",
            Position = UDim2.fromOffset(12, hasDescription and 8 or 14),
            Size = UDim2.fromOffset(16, 16),
            Color = theme.muted,
        })
    end
    create("Frame", row, {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = theme.line,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
    })

    local enabled = controlDefault(config, false) == true
    local toggle = create("TextButton", row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(38, 21),
        BackgroundColor3 = enabled and theme.limeDark or theme.control,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    })
    round(toggle, 11)
    local function knobPosition(isEnabled, size)
        local centerX = isEnabled and 27 or 11
        return UDim2.new(0, centerX - size / 2, 0.5, -size / 2)
    end
    local knob = create("Frame", toggle, {
        Position = knobPosition(enabled, 14),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = enabled and theme.lime or Color3.fromRGB(235, 236, 237),
        BorderSizePixel = 0,
    })
    round(knob, 7)

    local knobHovered = false
    local function renderToggle()
        local knobSize = knobHovered and 15 or 14
        tween(toggle, {BackgroundColor3 = enabled and theme.limeDark or theme.control})
        tween(knob, {
            Position = knobPosition(enabled, knobSize),
            Size = UDim2.fromOffset(knobSize, knobSize),
            BackgroundColor3 = knobHovered and theme.text
                or (enabled and theme.lime or Color3.fromRGB(235, 236, 237)),
        })
    end
    knob.MouseEnter:Connect(function()
        knobHovered = true
        renderToggle()
    end)
    knob.MouseLeave:Connect(function()
        knobHovered = false
        renderToggle()
    end)
    toggle.Activated:Connect(function()
        enabled = not enabled
        config.Value = enabled
        renderToggle()
        if config.Notify == true then
            showControlNotification(row, config.Text or "Toggle", config.NotifyText or (enabled and "Enabled" or "Disabled"), theme,
                enabled and theme.lime or theme.muted)
        end
        if type(config.Callback) == "function" then
            config.Callback(enabled)
        end
    end)
    renderToggle()

    local handle = {Instance = toggle, Row = row}
    function handle:GetValue()
        return enabled
    end
    function handle:SetValue(value)
        enabled = value == true
        config.Value = enabled
        renderToggle()
        return enabled
    end
    return exposeSectionHandle(handle, config)
end

local function createSectionRow(section, text, controlWidth, name, description, iconName)
    section._layoutOrder = section._layoutOrder + 1
    local hasDescription = type(description) == "string" and description ~= ""
    local hasIcon = type(iconName) == "string" and LucideIcons.Has(iconName)
    local labelX = hasIcon and 36 or 12
    local labelWidth = -(controlWidth + (hasIcon and 60 or 36))
    local row = create("Frame", section.Content, {
        Name = (name or "Control") .. "Row", LayoutOrder = section._layoutOrder,
        Size = UDim2.new(1, 0, 0, hasDescription and 58 or 44), BackgroundTransparency = 1,
    })
    create("TextLabel", row, {
        Position = hasDescription and UDim2.fromOffset(labelX, 6) or UDim2.fromOffset(labelX, 0),
        Size = hasDescription and UDim2.new(1, labelWidth, 0, 21) or UDim2.new(1, labelWidth, 1, 0),
        BackgroundTransparency = 1, Text = text or name or "Control", TextColor3 = section.Theme.text,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    if hasDescription then
        create("TextLabel", row, {
            Position = UDim2.fromOffset(labelX, 29), Size = UDim2.new(1, labelWidth, 0, 17),
            BackgroundTransparency = 1, Text = description, TextColor3 = section.Theme.muted,
            Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
    end
    if hasIcon then
        LucideIcons.Create(row, iconName, {
            Name = (name or "Control") .. "Icon",
            Position = UDim2.fromOffset(12, hasDescription and 8 or 14),
            Size = UDim2.fromOffset(16, 16),
            Color = section.Theme.muted,
        })
    end
    create("Frame", row, {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
        Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = section.Theme.line,
        BackgroundTransparency = 0.45, BorderSizePixel = 0,
    })
    return row
end

local function makeSectionButton(parent, text, width, theme, bindHover)
    local button = create("TextButton", parent, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(width, 29),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = text or "Select...",
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        AutoButtonColor = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    round(button, 8)
    if bindHover ~= false then
        button.MouseEnter:Connect(function() tween(button, {BackgroundColor3 = theme.hover}) end)
        button.MouseLeave:Connect(function() tween(button, {BackgroundColor3 = theme.control}) end)
    end
    return button
end

function SectionMethods:Button(config)
    config = config or {}
    assert(type(config) == "table", "Section:Button expects a config table")
    assert(type(config.Text) == "string", "Section:Button requires Text")
    local theme = self.Theme or ControlLibrary.Theme
    local row = createSectionRow(self, config.Text or "Button", 132, "Button", config.Description, config.Icon)
    local button = makeSectionButton(row, config.ButtonText or "Run", 132, theme, false)
    local style = config.Style
    if style == nil then
        style = config.Primary == true and "filled" or "outline"
    end
    assert(type(style) == "string", "Button Style must be outline, filled, ghost, or soft")
    style = string.lower(style)
    assert(style == "outline" or style == "filled" or style == "ghost" or style == "soft",
        "Button Style must be outline, filled, ghost, or soft")

    local function roleColor(value, fallback)
        if typeof(value) == "Color3" then return value end
        if type(value) ~= "string" then return fallback end
        local role = string.lower(value)
        for name, color in pairs(theme) do
            if string.lower(name) == role and typeof(color) == "Color3" then
                return color
            end
        end
        return fallback
    end

    local accent = config.Danger == true
        and roleColor(theme.danger, Color3.fromRGB(235, 83, 91))
        or roleColor(theme.lime, Color3.fromRGB(190, 220, 35))
    local darkText = roleColor(theme.card, Color3.fromRGB(24, 25, 27))
    local white = Color3.fromRGB(255, 255, 255)
    local outlineHoverColor = roleColor(config.HoverColor, accent)
    local outlineHoverFill = roleColor(config.HoverFill, theme.hover or theme.control)
    local defaultButtonFontFace = getUiFontFace(Enum.Font.GothamMedium)
    local hoverButtonFontFace = getUiFontFace(Enum.Font.Gotham)
    local baseButtonText = tostring(config.ButtonText == nil and "Run" or config.ButtonText)
    local disabled = config.Disabled == true
    local hovered = false
    local clickToken = 0
    local clickActive = false

    if type(config.Hover) ~= "nil" then
        assert(type(config.Hover) == "table", "Button Hover must be a table")
    end
    if type(config.Click) ~= "nil" then
        assert(type(config.Click) == "table", "Button Click must be a table")
    end

    button.Text = baseButtonText
    local buttonIconName = type(config.ButtonIcon) == "string" and LucideIcons.Has(config.ButtonIcon)
        and config.ButtonIcon or nil
    local buttonIcon
    local iconScale
    if buttonIconName then
        button.TextXAlignment = Enum.TextXAlignment.Left
        create("UIPadding", button, {
            PaddingLeft = UDim.new(0, 31),
            PaddingRight = UDim.new(0, 7),
        })
        buttonIcon = LucideIcons.Create(button, buttonIconName, {
            Name = "ButtonIcon",
            Position = UDim2.fromOffset(9, 6),
            Size = UDim2.fromOffset(16, 16),
            Color = theme.text,
            ZIndex = button.ZIndex + 1,
        })
        if buttonIcon then
            iconScale = create("UIScale", buttonIcon, {Scale = 1})
        end
    end

    local outline = create("UIStroke", button, {
        Color = theme.line or theme.muted,
        Thickness = 1,
        Transparency = style == "outline" and 0.2 or 1,
    })

    local function buttonColors(isHovered)
        local background, backgroundTransparency, textColor, borderColor, borderTransparency
        if style == "outline" then
            background = isHovered and outlineHoverFill or theme.control
            backgroundTransparency = isHovered and 0 or 1
            textColor = isHovered and outlineHoverColor or theme.text
            borderColor = isHovered and outlineHoverColor or (theme.line or theme.muted)
            borderTransparency = isHovered and 0 or 0.2
        elseif style == "filled" then
            background = isHovered and accent:Lerp(white, 0.12) or accent
            backgroundTransparency = 0
            textColor = darkText
            borderColor = background
            borderTransparency = 1
        elseif style == "ghost" then
            background = isHovered and (theme.hover or theme.control) or theme.control
            backgroundTransparency = isHovered and 0 or 1
            textColor = accent
            borderColor = accent
            borderTransparency = 1
        else -- soft
            background = accent:Lerp(darkText, isHovered and 0.72 or 0.82)
            backgroundTransparency = 0
            textColor = accent
            borderColor = accent
            borderTransparency = 1
        end

        if disabled then
            background = background:Lerp(darkText, 0.48)
            textColor = textColor:Lerp(theme.muted or theme.text, 0.48)
            borderColor = borderColor:Lerp(theme.muted or theme.text, 0.48)
            backgroundTransparency = math.min(backgroundTransparency, style == "outline" and 0.25 or 0.12)
            borderTransparency = style == "outline" and 0.55 or 1
        end
        return background, backgroundTransparency, textColor, borderColor, borderTransparency
    end

    local function renderStyle()
        local background, backgroundTransparency, textColor, borderColor, borderTransparency = buttonColors(hovered)
        if defaultButtonFontFace and hoverButtonFontFace then
            button.FontFace = hovered and hoverButtonFontFace or defaultButtonFontFace
        else
            button.Font = hovered and Enum.Font.Gotham or Enum.Font.GothamMedium
        end
        tween(button, {
            BackgroundColor3 = background,
            BackgroundTransparency = backgroundTransparency,
            TextColor3 = textColor,
            TextTransparency = disabled and 0.25 or 0,
        })
        tween(outline, {Color = borderColor, Transparency = borderTransparency})
        if buttonIcon then
            tween(buttonIcon, {
                ImageColor3 = textColor,
                ImageTransparency = disabled and 0.35 or 0,
            })
        end
    end

    local function resetButtonAnimation(animated)
        button.Text = baseButtonText
        if not buttonIcon then return end
        local _, _, iconColor = buttonColors(hovered)
        LucideIcons.Set(buttonIcon, buttonIconName, iconColor)
        local scale = animated and iconScale or nil
        if animated then
            TweenService:Create(buttonIcon, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 0}):Play()
            if scale then
                TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
            end
        else
            buttonIcon.Rotation = 0
            if scale then scale.Scale = 1 end
        end
    end

    local function applyAnimation(spec, isClick)
        if type(spec) ~= "table" then return end
        if spec.Text ~= nil then button.Text = tostring(spec.Text) end
        if not buttonIcon then return end
        if type(spec.Icon) == "string" and LucideIcons.Has(spec.Icon) then
            LucideIcons.Set(buttonIcon, spec.Icon)
        end
        local duration = isClick and 0.38 or 0.14
        if tonumber(spec.Scale) then
            TweenService:Create(iconScale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Scale = math.clamp(tonumber(spec.Scale), 0.1, 3),
            }):Play()
        end
        if tonumber(spec.Rotate) then
            local targetRotation = isClick and (buttonIcon.Rotation + tonumber(spec.Rotate)) or tonumber(spec.Rotate)
            TweenService:Create(buttonIcon, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Rotation = targetRotation,
            }):Play()
        end
    end

    local function renderAnimation()
        if hovered then
            resetButtonAnimation(false)
            applyAnimation(config.Hover, false)
        else
            resetButtonAnimation(true)
        end
    end

    renderStyle()

    local tooltipText
    if disabled and type(config.DisabledReason) == "string" and config.DisabledReason ~= "" then
        tooltipText = config.DisabledReason
    elseif type(config.Tooltip) == "string" and config.Tooltip ~= "" then
        tooltipText = config.Tooltip
    end
    local tooltip
    if tooltipText then
        tooltip = create("TextLabel", row, {
            Name = "ButtonTooltip",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -12, 0, 2),
            Size = UDim2.fromOffset(190, 28),
            BackgroundColor3 = theme.control,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Text = tooltipText,
            TextColor3 = theme.text,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            Visible = false,
            ZIndex = button.ZIndex + 5,
        })
        round(tooltip, 6)
        create("UIStroke", tooltip, {Color = theme.line or theme.muted, Thickness = 1, Transparency = 0.25})
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
        row.MouseEnter:Connect(showTooltip)
        row.MouseLeave:Connect(hideTooltip)
    end

    button.Activated:Connect(function()
        if disabled then return end
        if config.Notify == true then
            showControlNotification(row, config.Text, config.NotifyText or (baseButtonText .. " activated"), theme, accent)
        end
        local clickSpec = config.Click
        if type(clickSpec) == "table" then
            clickToken = clickToken + 1
            local token = clickToken
            clickActive = true
            resetButtonAnimation(false)
            applyAnimation(clickSpec, true)
            local hold = math.max(tonumber(clickSpec.Hold) or 0.45, 0)
            scheduleSessionTask(hold, function()
                if row.Parent and token == clickToken then
                    clickActive = false
                    renderAnimation()
                end
            end)
        end
        if type(config.Callback) == "function" then spawnSessionTask(config.Callback) end
    end)
    local handle = {Instance = row, Button = button}
    function handle:SetText(text)
        baseButtonText = tostring(text == nil and "" or text)
        clickToken = clickToken + 1
        clickActive = false
        renderAnimation()
        return self
    end
    function handle:Show()
        row.Visible = true
        return self
    end
    function handle:Hide()
        row.Visible = false
        return self
    end
    function handle:SetVisible(visible)
        row.Visible = visible == true
        return self
    end
    function handle:Destroy()
        row:Destroy()
        return self
    end
    return handle
end

function SectionMethods:Slider(config)
    config = config or {}
    assert(type(config) == "table", "Section:Slider expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local row = createSectionRow(self, config.Text or "Slider", 184, "Slider", config.Description, config.Icon)
    local control = create("Frame", row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(184, 30),
        BackgroundTransparency = 1,
    })
    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    if maxValue <= minValue then maxValue = minValue + 1 end
    local step = math.max(math.abs(tonumber(config.Step) or 1), 0.000001)
    local function snap(raw)
        local snapped = minValue + math.floor((raw - minValue) / step + 0.5) * step
        return math.clamp(tonumber(string.format("%.6f", snapped)), minValue, maxValue)
    end
    local value = snap(math.clamp(tonumber(controlDefault(config, minValue)) or minValue, minValue, maxValue))
    local track = create("TextButton", control, {
        Position = UDim2.fromOffset(0, 3),
        Size = UDim2.new(1, -44, 0, 24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Active = true,
    })
    local visualTrack = create("Frame", track, {
        Position = UDim2.new(0, 0, 0.5, -2),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Active = false,
    })
    round(visualTrack, 3)
    local fill = create("Frame", visualTrack, {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = theme.lime, BorderSizePixel = 0, Active = false})
    round(fill, 3)
    local knob = create("Frame", visualTrack, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = theme.lime,
        BorderSizePixel = 0,
    })
    round(knob, 6)
    local initialAlpha = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
    local function renderVisual(alpha)
        if not (fill.Parent and knob.Parent) then return end
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
    end
    local setVisualAlpha = createSliderSmoother(renderVisual, initialAlpha, function()
        return fill.Parent ~= nil and knob.Parent ~= nil
    end)
    renderVisual(initialAlpha)
    local valueLabel = create("TextLabel", control, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(38, 24),
        BackgroundTransparency = 1,
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local function render(alphaOverride)
        local alpha = math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
        setVisualAlpha(alphaOverride or alpha)
        valueLabel.Text = tostring(value) .. (config.Suffix or "")
        config.Value = value
    end
    local function setValue(newValue, notify)
        local previous = value
        value = snap(math.clamp(tonumber(newValue) or minValue, minValue, maxValue))
        render()
        if notify and previous ~= value and type(config.Callback) == "function" then config.Callback(value) end
    end
    local dragging = false
    local function setAt(x)
        local width = track.AbsoluteSize.X
        if width <= 0 then return end
        local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        setValue(minValue + (maxValue - minValue) * alpha, true)
        setVisualAlpha(alpha)
    end
    local knobHovered = false
    local function renderKnobHover()
        local hovered = knobHovered and not dragging
        tween(knob, {
            Size = UDim2.fromOffset(hovered and 15 or 12, hovered and 15 or 12),
            BackgroundColor3 = hovered and theme.text or theme.lime,
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
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            renderKnobHover()
            setAt(input.Position.X)
        end
    end)
    connectToSession(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setAt(input.Position.X)
        end
    end)
    connectToSession(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            renderKnobHover()
        end
    end)
    render()
    local handle = {Instance = track, Row = row}
    function handle:GetValue() return value end
    function handle:SetValue(newValue) setValue(newValue, false); return value end
    return exposeSectionHandle(handle, config)
end

function SectionMethods:Input(config)
    config = config or {}
    assert(type(config) == "table", "Section:Input expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local row = createSectionRow(self, config.Text or "Input", 174, "Input", config.Description, config.Icon)
    local initial = controlDefault(config, "")
    local value = initial ~= nil and tostring(initial) or ""
    local input = create("TextBox", row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(174, 29),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = value,
        PlaceholderText = config.Placeholder or "Type here...",
        PlaceholderColor3 = theme.muted,
        TextColor3 = theme.text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    round(input, 8)
    input.MouseEnter:Connect(function() tween(input, {BackgroundColor3 = theme.hover}) end)
    input.MouseLeave:Connect(function() tween(input, {BackgroundColor3 = theme.control}) end)
    input.FocusLost:Connect(function()
        value = input.Text
        config.Value = value
        if type(config.Callback) == "function" then config.Callback(value) end
    end)
    local handle = {Instance = input, Row = row}
    function handle:GetValue() return value end
    function handle:SetValue(newValue, submit)
        value = newValue ~= nil and tostring(newValue) or ""
        config.Value = value
        input.Text = value
        if submit and type(config.Callback) == "function" then config.Callback(value) end
        return value
    end
    return exposeSectionHandle(handle, config)
end

local activeSectionDropdownCloser

function SectionMethods:Dropdown(config)
    config = config or {}
    assert(type(config) == "table", "Section:Dropdown expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local options = config.Options or {"Option 1"}
    if #options == 0 then options = {"Option 1"} end
    local index = table.find(options, controlDefault(config, options[1])) or 1
    local row = createSectionRow(self, config.Text or "Dropdown", 156, "Dropdown", config.Description, config.Icon)
    local dropdown = makeSectionButton(row, "", 156, theme, false)
    dropdown.ZIndex = 21
    dropdown.TextXAlignment = Enum.TextXAlignment.Left
    create("UIPadding", dropdown, {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 28)})
    local dropdownIcon = LucideIcons.Create(dropdown, "chevron-down", {
        Name = "DropdownChevron",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        Color = theme.muted,
        ZIndex = dropdown.ZIndex + 1,
    })
    local itemHeight = 27
    local visibleOptions = math.max(1, config.VisibleOptions or 4)
    local menu = create("ScrollingFrame", row, {
        Name = "DropdownOptions",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 1, 2),
        Size = UDim2.fromOffset(156, math.min(#options, visibleOptions) * itemHeight),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.lime,
        Active = true,
        Visible = false,
        ZIndex = 22,
    })
    round(menu, 8)
    local menuStroke = create("UIStroke", menu, {Color = theme.line, Transparency = 0.2, Thickness = 1})
    local menuScale = create("UIScale", menu, {Scale = 1})
    create("UIListLayout", menu, {Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder})
    local open = false
    local optionButtons = {}
    local menuMotionTweens = {}
    local menuMotionToken = 0
    local screenGui = row:FindFirstAncestorOfClass("ScreenGui")
    local menuHome = menu.Parent
    local menuHomePosition = menu.Position
    local originalZIndices = {[menu] = menu.ZIndex}
    local positionConnection
    local function positionPopup()
        if not open or not screenGui or not menu.Parent then return end
        local scale = 1
        for _, child in ipairs(screenGui:GetChildren()) do
            if child:IsA("UIScale") then
                scale = math.max(child.Scale, 0.01)
                break
            end
        end
        local inset = Vector2.zero
        if not screenGui.IgnoreGuiInset then
            inset = GuiService:GetGuiInset()
        end
        local absolute = dropdown.AbsolutePosition
        local size = dropdown.AbsoluteSize
        local right = absolute.X + size.X - inset.X
        local below = absolute.Y + size.Y + 2 - inset.Y
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        local menuHeight = menu.AbsoluteSize.Y
        if below + menuHeight > viewport.Y and absolute.Y - menuHeight >= inset.Y then
            below = absolute.Y - menuHeight - 2 - inset.Y
        end
        menu.Position = UDim2.fromOffset(right / scale, below / scale)
    end
    local function stopMenuMotion()
        for _, activeTween in ipairs(menuMotionTweens) do
            activeTween:Cancel()
        end
        table.clear(menuMotionTweens)
    end
    local function animateMenu(isOpening, onClosed)
        menuMotionToken = menuMotionToken + 1
        local token = menuMotionToken
        stopMenuMotion()
        local duration = isOpening and 0.16 or 0.12
        local motion = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local function play(object, properties)
            if not object or not object.Parent then return nil end
            local activeTween = TweenService:Create(object, motion, properties)
            table.insert(menuMotionTweens, activeTween)
            activeTween:Play()
            return activeTween
        end
        play(menuScale, {Scale = isOpening and 1 or 0.97})
        play(menu, {BackgroundTransparency = isOpening and 0 or 1})
        play(menuStroke, {Transparency = isOpening and 0.2 or 1})
        for _, optionButton in ipairs(optionButtons) do
            play(optionButton, {BackgroundTransparency = isOpening and 0 or 1})
            play(optionButton, {TextTransparency = isOpening and 0 or 1})
        end
        if not isOpening then
            local closingTween = menuMotionTweens[1]
            if closingTween then
                closingTween.Completed:Connect(function(playbackState)
                    if playbackState == Enum.PlaybackState.Completed and token == menuMotionToken and onClosed then
                        onClosed()
                    end
                end)
            elseif onClosed then
                onClosed()
            end
        end
    end
    local function setOpen(isOpen)
        if open == isOpen then return end
        if isOpen then
            if activeSectionDropdownCloser and activeSectionDropdownCloser ~= setOpen then
                activeSectionDropdownCloser(false)
            end
            activeSectionDropdownCloser = setOpen
        elseif activeSectionDropdownCloser == setOpen then
            activeSectionDropdownCloser = nil
        end
        open = isOpen
        if open then
            local wasVisible = menu.Visible
            if screenGui then
                menu.Parent = screenGui
                menu.ZIndex = 10000
                for _, descendant in ipairs(menu:GetDescendants()) do
                    if descendant:IsA("GuiObject") then
                        if originalZIndices[descendant] == nil then originalZIndices[descendant] = descendant.ZIndex end
                        descendant.ZIndex = 10001
                    end
                end
                positionPopup()
                if positionConnection then positionConnection:Disconnect() end
                positionConnection = dropdown:GetPropertyChangedSignal("AbsolutePosition"):Connect(positionPopup)
            end
            if not wasVisible then
                menuScale.Scale = 0.96
                menu.BackgroundTransparency = 1
                menuStroke.Transparency = 1
                for _, optionButton in ipairs(optionButtons) do
                    optionButton.BackgroundTransparency = 1
                    optionButton.TextTransparency = 1
                end
            end
            menu.Visible = true
            row.ZIndex = 20
            dropdown.ZIndex = 21
            if dropdownIcon then dropdownIcon.ZIndex = 22 end
            animateMenu(true)
        else
            animateMenu(false, function()
                menu.Visible = false
                if positionConnection then
                    positionConnection:Disconnect()
                    positionConnection = nil
                end
                if menuHome.Parent and row.Parent then
                    menu.Parent = menuHome
                    menu.Position = menuHomePosition
                elseif menu.Parent then
                    menu:Destroy()
                end
                for object, zIndex in pairs(originalZIndices) do
                    if object.Parent then object.ZIndex = zIndex end
                end
                row.ZIndex = 1
                dropdown.ZIndex = 1
                if dropdownIcon then dropdownIcon.ZIndex = 2 end
            end)
        end
        if dropdownIcon then
            tween(dropdownIcon, {Rotation = open and 180 or 0})
        end
        dropdown.Text = tostring(options[index])
        if open then menu.CanvasPosition = Vector2.new(0, 0) end
    end
    row.Destroying:Connect(function()
        if open then setOpen(false) end
    end)
    for optionIndex, option in ipairs(options) do
        local optionButton = create("TextButton", menu, {
            Name = "Option" .. tostring(optionIndex),
            LayoutOrder = optionIndex,
            Size = UDim2.new(1, -6, 0, 26),
            BackgroundColor3 = theme.control,
            BorderSizePixel = 0,
            Text = tostring(option),
            TextColor3 = theme.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            AutoButtonColor = false,
            ZIndex = 23,
        })
        optionButtons[optionIndex] = optionButton
        round(optionButton, 6)
        optionButton.MouseEnter:Connect(function() tween(optionButton, {BackgroundColor3 = theme.hover}) end)
        optionButton.MouseLeave:Connect(function() tween(optionButton, {BackgroundColor3 = theme.control}) end)
        optionButton.Activated:Connect(function()
            index = optionIndex
            config.Value = option
            setOpen(false)
            if type(config.Callback) == "function" then config.Callback(option) end
        end)
    end
    dropdown.Activated:Connect(function() setOpen(not open) end)
    connectToSession(UserInputService.InputBegan, function(input)
        if not open or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then return end
        local point = input.Position
        local function contains(guiObject)
            local position, size = guiObject.AbsolutePosition, guiObject.AbsoluteSize
            return point.X >= position.X and point.X <= position.X + size.X
                and point.Y >= position.Y and point.Y <= position.Y + size.Y
        end
        if not contains(dropdown) and not contains(menu) then setOpen(false) end
    end)
    local function render() dropdown.Text = tostring(options[index]) end
    render()
    setOpen(false)
    local handle = {Instance = dropdown, Menu = menu, Row = row}
    function handle:GetValue() return options[index] end
    function handle:SetValue(newValue)
        local newIndex = table.find(options, newValue)
        if not newIndex then return nil end
        index = newIndex
        config.Value = options[index]
        render()
        return config.Value
    end
    return exposeSectionHandle(handle, config)
end

-- Both spellings are accepted for convenience.
SectionMethods.DropDown = SectionMethods.Dropdown

function SectionMethods:Keybind(config)
    config = config or {}
    assert(type(config) == "table", "Section:Keybind expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local row = createSectionRow(self, config.Text or "Keybind", 110, "Keybind", config.Description, config.Icon)
    local key = controlDefault(config, Enum.KeyCode.F)
    if typeof(key) ~= "EnumItem" then
        local ok, parsed = pcall(function() return Enum.KeyCode[key or "F"] end)
        key = ok and parsed or Enum.KeyCode.F
    end
    local waiting = false
    local button = makeSectionButton(row, key.Name, 110, theme)
    local function render()
        button.Text = waiting and "Press a key..." or key.Name
        tween(button, {BackgroundColor3 = waiting and theme.limeDark or theme.control})
    end
    button.Activated:Connect(function()
        waiting = true
        button.Text = "Press a key..."
        tween(button, {BackgroundColor3 = theme.limeDark})
    end)
    connectToSession(UserInputService.InputBegan, function(input, gameProcessed)
        if gameProcessed then return end
        if waiting then
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                key = input.KeyCode
                config.Value = key
                waiting = false
                render()
            end
            return
        end
        if input.KeyCode == key and type(config.Callback) == "function" then config.Callback(key) end
    end)
    local handle = {Instance = button, Row = row}
    function handle:GetValue() return key end
    function handle:SetValue(newValue)
        local newKey = newValue
        if typeof(newKey) ~= "EnumItem" then
            local ok, parsed = pcall(function() return Enum.KeyCode[newValue] end)
            if not ok or not parsed then return nil end
            newKey = parsed
        end
        key = newKey
        config.Value = key
        waiting = false
        render()
        return key
    end
    return exposeSectionHandle(handle, config)
end

local function defaultColors(theme)
    return {
        theme.lime,
        Color3.fromRGB(70, 170, 255),
        Color3.fromRGB(240, 90, 110),
        Color3.fromRGB(180, 105, 255),
        Color3.fromRGB(244, 183, 64),
        Color3.fromRGB(235, 236, 237),
    }
end

local activeColorEditor

local function colorToHex(color)
    local red = math.floor(color.R * 255 + 0.5)
    local green = math.floor(color.G * 255 + 0.5)
    local blue = math.floor(color.B * 255 + 0.5)
    return string.format("#%02x%02x%02x", red, green, blue)
end

local function colorToHsl(color)
    local red, green, blue = color.R, color.G, color.B
    local maximum = math.max(red, green, blue)
    local minimum = math.min(red, green, blue)
    local delta = maximum - minimum
    local hue, saturation = 0, 0
    local lightness = (maximum + minimum) / 2
    if delta > 0 then
        saturation = delta / (1 - math.abs(2 * lightness - 1))
        if maximum == red then
            hue = ((green - blue) / delta) % 6
        elseif maximum == green then
            hue = (blue - red) / delta + 2
        else
            hue = (red - green) / delta + 4
        end
        hue = hue / 6
    end
    return string.format("hsl(%d° %d%% %d%%)", math.floor(hue * 360 + 0.5) % 360,
        math.floor(saturation * 100 + 0.5), math.floor(lightness * 100 + 0.5))
end

local function parseHexColor(value)
    local hex = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
    hex = string.gsub(hex, "^#", "")
    if #hex == 3 then
        hex = string.sub(hex, 1, 1) .. string.sub(hex, 1, 1)
            .. string.sub(hex, 2, 2) .. string.sub(hex, 2, 2)
            .. string.sub(hex, 3, 3) .. string.sub(hex, 3, 3)
    end
    if #hex ~= 6 or not string.match(hex, "^%x+$") then return nil end
    return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
end

local function openColorEditor(anchor, theme, initialColor, presets, onChanged)
    local screenGui = anchor:FindFirstAncestorWhichIsA("ScreenGui")
    if not screenGui then return nil end
    if activeColorEditor and activeColorEditor.Close then activeColorEditor:Close() end

    local selectedColor = typeof(initialColor) == "Color3" and initialColor or theme.lime
    local hue, saturation, value = Color3.toHSV(selectedColor)
    local paletteColors = {}
    for _, color in ipairs(presets or {}) do
        if typeof(color) == "Color3" then table.insert(paletteColors, color) end
    end
    if #paletteColors == 0 then paletteColors = defaultColors(theme) end

    local popup = create("Frame", screenGui, {
        Name = "ColorPickerPopup",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(292, 402),
        BackgroundColor3 = theme.card,
        BorderSizePixel = 0,
        ZIndex = 80,
    })
    round(popup, 10)
    create("UIStroke", popup, {Color = theme.line, Thickness = 1})
    local popupScale = create("UIScale", popup, {Scale = 0.94})

    local topBar = create("Frame", popup, {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.hover,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 81,
    })
    round(topBar, 10)
    create("Frame", topBar, {
        Position = UDim2.new(0, 0, 1, -10),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = theme.hover,
        BorderSizePixel = 0,
        ZIndex = 81,
    })
    local statusDot = create("Frame", topBar, {
        Position = UDim2.fromOffset(10, 13),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = theme.danger,
        BorderSizePixel = 0,
        ZIndex = 82,
    })
    round(statusDot, 8)
    create("TextLabel", topBar, {
        Position = UDim2.fromOffset(27, 0),
        Size = UDim2.new(1, -72, 1, 0),
        BackgroundTransparency = 1,
        Text = "Color picker",
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 82,
    })
    local closeButton = create("TextButton", topBar, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -7, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = theme.muted,
        Font = Enum.Font.Gotham,
        TextSize = 19,
        AutoButtonColor = false,
        ZIndex = 83,
    })

    local wheelSize, gridCount = 184, 31
    local wheel = create("Frame", popup, {
        Name = "ColorWheel",
        Position = UDim2.new(0.5, -wheelSize / 2, 0, 43),
        Size = UDim2.fromOffset(wheelSize, wheelSize),
        BackgroundColor3 = Color3.fromRGB(38, 39, 41),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 82,
    })
    round(wheel, wheelSize / 2)
    local wheelCells = {}
    local cellSize = wheelSize / gridCount
    for y = 1, gridCount do
        for x = 1, gridCount do
            local dx = ((x - 0.5) / gridCount) * 2 - 1
            local dy = ((y - 0.5) / gridCount) * 2 - 1
            local radius = math.sqrt(dx * dx + dy * dy)
            if radius <= 1 then
                local cellHue = math.atan2(dy, dx) / (2 * math.pi) % 1
                local cell = create("Frame", wheel, {
                    Position = UDim2.fromOffset((x - 1) * cellSize, (y - 1) * cellSize),
                    Size = UDim2.fromOffset(math.ceil(cellSize + 0.25), math.ceil(cellSize + 0.25)),
                    -- Keep the hue/saturation wheel fully visible; brightness is controlled by the slider below.
                    BackgroundColor3 = Color3.fromHSV(cellHue, radius, 1),
                    BorderSizePixel = 0,
                    ZIndex = 83,
                })
                table.insert(wheelCells, {Instance = cell, Hue = cellHue, Saturation = radius})
            end
        end
    end
    local wheelInput = create("TextButton", wheel, {
        Name = "WheelInput",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 84,
    })
    local selector = create("Frame", wheel, {
        Name = "Selector",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.fromRGB(245, 245, 245),
        BorderSizePixel = 0,
        ZIndex = 85,
    })
    round(selector, 8)
    create("UIStroke", selector, {Color = Color3.fromRGB(20, 21, 22), Thickness = 1.5})

    local valueTrack = create("TextButton", popup, {
        Name = "ValueSlider",
        Position = UDim2.fromOffset(17, 238),
        Size = UDim2.new(1, -34, 0, 11),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 82,
    })
    round(valueTrack, 8)
    local valueGradient = create("UIGradient", valueTrack, {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0, 0, 0)),
    })
    local valueMarker = create("Frame", valueTrack, {
        Name = "ValueMarker",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(value, 0, 0.5, 0),
        Size = UDim2.fromOffset(10, 17),
        BackgroundColor3 = Color3.fromRGB(238, 239, 240),
        BorderSizePixel = 0,
        ZIndex = 84,
    })
    round(valueMarker, 5)
    create("UIStroke", valueMarker, {Color = Color3.fromRGB(30, 31, 33), Thickness = 1})

    local function makeValueField(labelText, y, editable)
        create("TextLabel", popup, {
            Position = UDim2.fromOffset(14, y),
            Size = UDim2.fromOffset(42, 27),
            BackgroundTransparency = 1,
            Text = labelText,
            TextColor3 = theme.muted,
            Font = Enum.Font.GothamMedium,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 82,
        })
        local field = create("TextBox", popup, {
            Position = UDim2.fromOffset(53, y),
            Size = UDim2.new(1, -67, 0, 27),
            BackgroundColor3 = theme.control,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Text = "",
            TextColor3 = theme.text,
            PlaceholderColor3 = theme.muted,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextEditable = editable,
            ZIndex = 82,
        })
        round(field, 6)
        create("UIPadding", field, {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
        return field
    end
    local hexField = makeValueField("HEX", 260, true)
    local hslField = makeValueField("HSL", 291, false)
    local rgbField = makeValueField("RGB", 322, false)

    local palette = create("ScrollingFrame", popup, {
        Name = "PresetColors",
        Position = UDim2.fromOffset(72, 365),
        Size = UDim2.new(1, -86, 0, 25),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        Active = true,
        ZIndex = 82,
    })
    create("UIListLayout", palette, {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local swatchStrokes, presetButtons = {}, {}
    for index, color in ipairs(paletteColors) do
        local swatch = create("TextButton", palette, {
            Name = "Preset" .. tostring(index),
            LayoutOrder = index,
            Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 83,
        })
        round(swatch, 5)
        swatchStrokes[index] = create("UIStroke", swatch, {Color = theme.line, Thickness = 1})
        presetButtons[index] = swatch
    end
    local currentColor = create("Frame", popup, {
        Name = "CurrentColor",
        Position = UDim2.fromOffset(14, 365),
        Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = selectedColor,
        BorderSizePixel = 0,
        ZIndex = 83,
    })
    round(currentColor, 6)
    create("UIStroke", currentColor, {Color = theme.line, Thickness = 1})

    local pipetteButton = create("TextButton", popup, {
        Name = "EyedropperButton",
        Position = UDim2.fromOffset(42, 364),
        Size = UDim2.fromOffset(24, 24),
        BackgroundColor3 = theme.control,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 83,
    })
    round(pipetteButton, 6)
    LucideIcons.Create(pipetteButton, "pipette", {
        Name = "EyedropperIcon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        Color = theme.muted,
        ZIndex = 84,
    })
    pipetteButton.MouseEnter:Connect(function() tween(pipetteButton, {BackgroundColor3 = theme.hover}) end)
    pipetteButton.MouseLeave:Connect(function() tween(pipetteButton, {BackgroundColor3 = theme.control}) end)

    local samplingOverlay = create("TextButton", screenGui, {
        Name = "EyedropperOverlay",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Modal = true,
        Visible = false,
        ZIndex = 1000,
    })
    local samplingHint = create("TextLabel", samplingOverlay, {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 12),
        Size = UDim2.fromOffset(300, 30),
        BackgroundColor3 = theme.card,
        BorderSizePixel = 0,
        Text = "Click a color to sample  ·  Esc to cancel",
        TextColor3 = theme.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        ZIndex = 1001,
    })
    round(samplingHint, 8)
    create("UIStroke", samplingHint, {Color = theme.line, Thickness = 1})

    local connections = {}
    local draggingPopup, draggingWheel, draggingValue = false, false, false
    local popupDragOrigin, popupDragStartPosition
    local isSampling = false
    local editor = {IsOpen = true}

    local function renderWheel()
        for _, cell in ipairs(wheelCells) do
            cell.Instance.BackgroundColor3 = Color3.fromHSV(cell.Hue, cell.Saturation, 1)
        end
        local radius = wheelSize * 0.5 * saturation
        selector.Position = UDim2.fromOffset(wheelSize * 0.5 + math.cos(hue * 2 * math.pi) * radius,
            wheelSize * 0.5 + math.sin(hue * 2 * math.pi) * radius)
        valueMarker.Position = UDim2.new(value, 0, 0.5, 0)
        valueGradient.Color = ColorSequence.new(Color3.fromHSV(hue, saturation, 1), Color3.new(0, 0, 0))
        currentColor.BackgroundColor3 = selectedColor
        hexField.Text = colorToHex(selectedColor)
        hslField.Text = colorToHsl(selectedColor)
        rgbField.Text = string.format("rgb(%d %d %d)", math.floor(selectedColor.R * 255 + 0.5),
            math.floor(selectedColor.G * 255 + 0.5), math.floor(selectedColor.B * 255 + 0.5))
        for index, outline in ipairs(swatchStrokes) do
            outline.Color = paletteColors[index] == selectedColor and theme.text or theme.line
            outline.Thickness = paletteColors[index] == selectedColor and 2 or 1
        end
    end

    local function setColor(color, notify)
        if typeof(color) ~= "Color3" then return end
        selectedColor = color
        local nextHue, nextSaturation, nextValue = Color3.toHSV(color)
        -- Pure black has no HSV hue or saturation. Keep the last chosen wheel point so
        -- moving the brightness slider away from black restores that color instead of gray.
        if nextValue > 0.0001 then
            hue, saturation = nextHue, nextSaturation
        end
        value = nextValue
        renderWheel()
        if notify and type(onChanged) == "function" then onChanged(selectedColor) end
    end

    for index, swatch in ipairs(presetButtons) do
        local color = paletteColors[index]
        swatch.Activated:Connect(function() setColor(color, true) end)
    end

    local function sampleColorAt(point)
        local player = Players.LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        local viewportPoint = Vector2.new(point.X, point.Y)
        local inset = GuiService:GetGuiInset()
        local guiPoint = viewportPoint + Vector2.new(inset.X, inset.Y)
        if playerGui then
            for _, candidate in ipairs(playerGui:GetGuiObjectsAtPosition(guiPoint.X, guiPoint.Y)) do
                if candidate ~= samplingOverlay and not candidate:IsDescendantOf(samplingOverlay)
                    and not candidate:IsDescendantOf(popup) then
                    if (candidate:IsA("ImageLabel") or candidate:IsA("ImageButton")) and candidate.ImageTransparency < 0.98 then
                        local imageTint = candidate.ImageColor3
                        -- Roblox reports the tint, not the pixels of an image. A plain white tint
                        -- is usually the default, so sampling it would incorrectly return white.
                        if imageTint.R < 0.98 or imageTint.G < 0.98 or imageTint.B < 0.98 then
                            return imageTint
                        end
                    end
                    if candidate.BackgroundTransparency < 0.98 then
                        return candidate.BackgroundColor3
                    end
                end
            end
        end

        local camera = workspace.CurrentCamera
        if not camera then return nil end
        -- InputObject.Position is already in viewport coordinates; subtracting GuiInset
        -- here shifts the ray upward and samples a different object (or empty space).
        local ray = camera:ViewportPointToRay(viewportPoint.X, viewportPoint.Y)
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        local character = player and player.Character
        raycastParams.FilterDescendantsInstances = character and {character} or {}
        local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
        if not result then return nil end
        if result.Instance:IsA("BasePart") then return result.Instance.Color end
        if result.Instance == workspace.Terrain then return workspace.Terrain:GetMaterialColor(result.Material) end
        return nil
    end

    local function updateWheelFromPoint(point)
        local position, size = wheel.AbsolutePosition, wheel.AbsoluteSize
        local dx = ((point.X - position.X) / size.X) * 2 - 1
        local dy = ((point.Y - position.Y) / size.Y) * 2 - 1
        local radius = math.min(1, math.sqrt(dx * dx + dy * dy))
        if radius > 0.01 then hue = math.atan2(dy, dx) / (2 * math.pi) % 1 end
        saturation = radius
        setColor(Color3.fromHSV(hue, saturation, value), true)
    end

    local function updateValueFromPoint(point)
        local position, size = valueTrack.AbsolutePosition, valueTrack.AbsoluteSize
        value = math.clamp((point.X - position.X) / size.X, 0, 1)
        setColor(Color3.fromHSV(hue, saturation, value), true)
    end

    function editor:SetColor(color)
        if self.IsOpen then setColor(color, false) end
    end
    function editor:Close()
        if not self.IsOpen then return end
        self.IsOpen = false
        isSampling = false
        samplingOverlay.Visible = false
        samplingOverlay:Destroy()
        if activeColorEditor == self then activeColorEditor = nil end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        TweenService:Create(popupScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.94}):Play()
        TweenService:Create(popup, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
        scheduleSessionTask(0.13, function()
            if popup.Parent then popup:Destroy() end
        end)
    end
    activeColorEditor = editor

    wheelInput.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingWheel = true
            updateWheelFromPoint(input.Position)
        end
    end)
    table.insert(connections, connectToSession(topBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingPopup = true
            popupDragOrigin = input.Position
            popupDragStartPosition = popup.Position
        end
    end))
    valueTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingValue = true
            updateValueFromPoint(input.Position)
        end
    end)
    hexField.FocusLost:Connect(function()
        local parsed = parseHexColor(hexField.Text)
        if parsed then setColor(parsed, true) else hexField.Text = colorToHex(selectedColor) end
    end)
    closeButton.Activated:Connect(function() editor:Close() end)
    pipetteButton.Activated:Connect(function()
        if not editor.IsOpen then return end
        isSampling = true
        samplingHint.Text = "Click a color to sample  ·  Esc to cancel"
        popup.Visible = false
        samplingOverlay.Visible = true
    end)
    samplingOverlay.InputBegan:Connect(function(input)
        if not isSampling or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then return end
        local sampledColor = sampleColorAt(input.Position)
        if sampledColor then
            isSampling = false
            samplingOverlay.Visible = false
            popup.Visible = true
            setColor(sampledColor, true)
        else
            samplingHint.Text = "No color found — click again or press Esc"
        end
    end)
    table.insert(connections, connectToSession(UserInputService.InputChanged, function(input)
        if not editor.IsOpen then return end
        if draggingPopup and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - popupDragOrigin
            popup.Position = UDim2.new(
                popupDragStartPosition.X.Scale,
                popupDragStartPosition.X.Offset + delta.X,
                popupDragStartPosition.Y.Scale,
                popupDragStartPosition.Y.Offset + delta.Y
            )
        elseif draggingWheel and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateWheelFromPoint(input.Position)
        elseif draggingValue and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateValueFromPoint(input.Position)
        end
    end))
    table.insert(connections, connectToSession(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingPopup, draggingWheel, draggingValue = false, false, false
        end
    end))
    table.insert(connections, connectToSession(UserInputService.InputBegan, function(input)
        if isSampling and input.KeyCode == Enum.KeyCode.Escape then
            isSampling = false
            samplingOverlay.Visible = false
            popup.Visible = true
        end
    end))
    renderWheel()
    TweenService:Create(popupScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
    TweenService:Create(popup, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
    return editor
end

function SectionMethods:ColorPicker(config)
    config = config or {}
    assert(type(config) == "table", "Section:ColorPicker expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local colors = config.Colors or defaultColors(theme)
    if #colors == 0 then colors = defaultColors(theme) end
    local selectedColor = typeof(config.Value) == "Color3" and config.Value or colors[1]
    local row = createSectionRow(self, config.Text or "Color picker", 62, "ColorPicker", config.Description, config.Icon)
    local preview = create("TextButton", row, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(58, 25),
        BackgroundColor3 = selectedColor,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 11,
    })
    round(preview, 7)
    create("UIStroke", preview, {Color = theme.line, Thickness = 1})
    local editor
    local function render()
        config.Value = selectedColor
        preview.BackgroundColor3 = selectedColor
    end
    preview.Activated:Connect(function()
        if editor and editor.IsOpen then
            editor:Close()
            editor = nil
            return
        end
        editor = openColorEditor(preview, theme, selectedColor, colors, function(color)
            selectedColor = color
            render()
            if type(config.Callback) == "function" then config.Callback(selectedColor) end
        end)
    end)
    render()
    local handle = {Instance = preview, Row = row}
    function handle:GetValue() return selectedColor end
    function handle:SetValue(newColor)
        if typeof(newColor) ~= "Color3" then return nil end
        selectedColor = newColor
        render()
        if editor and editor.IsOpen then editor:SetColor(newColor) end
        return selectedColor
    end
    function handle:Destroy()
        if editor and editor.IsOpen then editor:Close() end
        row:Destroy()
    end
    return exposeSectionHandle(handle, config)
end

function SectionMethods:Palette(config)
    config = config or {}
    assert(type(config) == "table", "Section:Palette expects a config table")
    local theme = self.Theme or ControlLibrary.Theme
    local colors = config.Colors or defaultColors(theme)
    if #colors == 0 then colors = defaultColors(theme) end
    local selectedColor = typeof(config.Value) == "Color3" and config.Value or colors[1]
    local selectedIndex = table.find(colors, selectedColor)
    local row = createSectionRow(self, config.Text or "Palette", 184, "Palette", config.Description, config.Icon)
    local holder = create("ScrollingFrame", row, {
        Name = "ColorSwatches",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(184, 30),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        Active = true,
    })
    create("UIListLayout", holder, {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local strokes = {}
    local function render()
        config.Value = selectedColor
        for index, outline in ipairs(strokes) do
            outline.Color = index == selectedIndex and theme.lime or theme.line
            outline.Thickness = index == selectedIndex and 2 or 1
        end
    end
    for index, color in ipairs(colors) do
        local swatch = create("TextButton", holder, {
            Name = "Swatch" .. tostring(index),
            LayoutOrder = index,
            Size = UDim2.fromOffset(22, 22),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
        })
        round(swatch, 6)
        strokes[index] = create("UIStroke", swatch, {Color = index == selectedIndex and theme.lime or theme.line, Thickness = index == selectedIndex and 2 or 1})
        swatch.MouseEnter:Connect(function() tween(swatch, {Size = UDim2.fromOffset(25, 25)}) end)
        swatch.MouseLeave:Connect(function() tween(swatch, {Size = UDim2.fromOffset(22, 22)}) end)
        swatch.Activated:Connect(function()
            selectedIndex = index
            selectedColor = color
            render()
            if type(config.Callback) == "function" then config.Callback(selectedColor) end
        end)
    end
    render()
    local handle = {Instance = holder, Row = row}
    function handle:GetValue() return selectedColor end
    function handle:SetValue(newColor)
        if typeof(newColor) ~= "Color3" then return nil end
        selectedColor = newColor
        selectedIndex = table.find(colors, newColor)
        render()
        return selectedColor
    end
    return exposeSectionHandle(handle, config)
end

function ControlLibrary.BuildSettingsPage(parent, callbacks)
    callbacks = callbacks or {}
    assert(type(callbacks) == "table", "ControlLibrary.BuildSettingsPage callbacks must be a table")
    local theme = ControlLibrary.Theme
    local examples = callbacks.Examples or ControlLibrary.Examples
    local page = create("ScrollingFrame", parent, {
        Name = "ControlsOverviewPage",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = theme.lime,
        Visible = false,
    })
    local pageThemeRefreshers = {}
    themeRefreshers[page] = function()
        for _, refresh in ipairs(pageThemeRefreshers) do
            refresh()
        end
    end
    page.Destroying:Connect(function()
        themeRefreshers[page] = nil
    end)

    local layout = create("UIListLayout", page, {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local header = create("Frame", page, {
        Name = "OverviewHeader",
        LayoutOrder = 0,
        Size = UDim2.new(1, -12, 0, 46),
        BackgroundTransparency = 1,
    })
    create("TextLabel", header, {
        Position = UDim2.fromOffset(10, 2),
        Size = UDim2.new(1, -20, 0, 20),
        BackgroundTransparency = 1,
        Text = callbacks.Title or ControlLibrary.Title,
        TextColor3 = theme.text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    create("TextLabel", header, {
        Position = UDim2.fromOffset(10, 24),
        Size = UDim2.new(1, -20, 0, 17),
        BackgroundTransparency = 1,
        Text = callbacks.Description or ControlLibrary.Description,
        TextColor3 = theme.muted,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    local sectionLayout
    if callbacks.ColumnCount == 2 or callbacks.ColumnCount == true then
        local columnsFrame = create("Frame", page, {
            Name = "SectionColumns",
            LayoutOrder = 1,
            Size = UDim2.new(1, -12, 0, 0),
            BackgroundTransparency = 1,
        })
        local columnRecords = {}
        for index, name in ipairs({"LeftColumn", "RightColumn"}) do
            local column = create("Frame", columnsFrame, {
                Name = name,
                Position = index == 1 and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, 4, 0, 0),
                Size = UDim2.new(0.5, -4, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
            })
            local columnLayout = create("UIListLayout", column, {
                Padding = UDim.new(0, 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })
            table.insert(columnRecords, {
                Frame = column,
                Layout = columnLayout,
                Count = 0,
            })
        end

        local function resizeColumnsFrame()
            local contentHeight = math.max(
                columnRecords[1].Layout.AbsoluteContentSize.Y,
                columnRecords[2].Layout.AbsoluteContentSize.Y
            )
            columnsFrame.Size = UDim2.new(1, -12, 0, contentHeight)
        end
        for _, record in ipairs(columnRecords) do
            record.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeColumnsFrame)
        end

        sectionLayout = {
            Frame = columnsFrame,
            Columns = columnRecords,
            Items = {},
            SingleColumnBelow = tonumber(callbacks.SingleColumnBelow) or 680,
        }
        function sectionLayout:Reflow()
            local left, right = self.Columns[1], self.Columns[2]
            local singleColumn = page.AbsoluteSize.X < self.SingleColumnBelow or #self.Items <= 1
            right.Frame.Visible = not singleColumn
            left.Frame.Position = UDim2.fromOffset(0, 0)
            left.Frame.Size = singleColumn and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -4, 0, 0)
            right.Frame.Position = UDim2.new(0.5, 4, 0, 0)
            right.Frame.Size = UDim2.new(0.5, -4, 0, 0)
            left.Count, right.Count = 0, 0

            local heights = {0, 0}
            for _, item in ipairs(self.Items) do
                local targetIndex = 1
                if not singleColumn then
                    targetIndex = heights[1] <= heights[2] and 1 or 2
                end
                local target = self.Columns[targetIndex]
                target.Count += 1
                item.Frame.Parent = target.Frame
                item.Frame.LayoutOrder = target.Count
                item.Frame.Size = UDim2.new(1, 0, item.SizeYScale or 0, item.SizeYOffset or 0)
                heights[targetIndex] += math.max(item.Frame.AbsoluteSize.Y, item.SizeYOffset or 0, 140) + 8
            end
            resizeColumnsFrame()
        end
        function sectionLayout:CreateSection(title, options)
            local section = ControlLibrary:CreateSection(self.Frame, title, options)
            self.Items[#self.Items + 1] = {Frame = section.Frame, SizeYOffset = 0}
            self:Reflow()
            return section
        end
        function sectionLayout:AddCard(card)
            self.Items[#self.Items + 1] = {
                Frame = card,
                SizeYScale = card.Size.Y.Scale,
                SizeYOffset = card.Size.Y.Offset,
            }
            self:Reflow()
        end
        page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            sectionLayout:Reflow()
        end)
    end

    for order, example in ipairs(examples) do
        local hasIcon = type(example.Icon) == "string" and LucideIcons.Has(example.Icon)
        local card = create("Frame", sectionLayout and sectionLayout.Frame or page, {
            Name = example.Type .. "Example",
            LayoutOrder = order,
            Size = UDim2.new(1, sectionLayout and 0 or -12, 0, 66),
            BackgroundColor3 = theme.card,
            BorderSizePixel = 0,
        })
        if sectionLayout then
            sectionLayout:AddCard(card)
        end
        applyGlassSurface(card, 12)
        if hasIcon then
            LucideIcons.Create(card, example.Icon, {
                Name = "ExampleIcon",
                Position = UDim2.fromOffset(14, 25),
                Size = UDim2.fromOffset(16, 16),
                Color = theme.lime,
            })
        end
        create("TextLabel", card, {
            Position = UDim2.fromOffset(hasIcon and 40 or 14, 9),
            Size = UDim2.new(1, hasIcon and -246 or -220, 0, 20),
            BackgroundTransparency = 1,
            Text = example.Label or example.Type,
            TextColor3 = theme.text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        create("TextLabel", card, {
            Position = UDim2.fromOffset(hasIcon and 40 or 14, 32),
            Size = UDim2.new(1, hasIcon and -246 or -220, 0, 18),
            BackgroundTransparency = 1,
            Text = example.Description or "",
            TextColor3 = theme.muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        if example.Type == "Button" then
            local action = makeButton(card, example.Text or "Click", 132)
            local initialText = action.Text
            action.Activated:Connect(function()
                action.Text = "Clicked"
                if example.Notify == true then
                    showControlNotification(card, example.Label or "Button", example.NotifyText or (initialText .. " activated"), theme)
                end
                scheduleSessionTask(0.7, function()
                    if action.Parent then action.Text = initialText end
                end)
            end)
        elseif example.Type == "Toggle" then
            local enabled = example.Value == true
            local toggle = create("TextButton", card, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = UDim2.fromOffset(38, 21),
                BackgroundColor3 = enabled and theme.limeDark or theme.control,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
            })
            round(toggle, 11)
            local function knobPosition(isEnabled, size)
                local centerX = isEnabled and 27 or 11
                return UDim2.new(0, centerX - size / 2, 0.5, -size / 2)
            end
            local knob = create("Frame", toggle, {
                Position = knobPosition(enabled, 14),
                Size = UDim2.fromOffset(14, 14),
                BackgroundColor3 = enabled and theme.lime or Color3.fromRGB(235, 236, 237),
                BorderSizePixel = 0,
            })
            round(knob, 7)
            local hovered = false
            local function renderToggle()
                local background = enabled and (hovered and theme.limeDark:Lerp(theme.lime, 0.2) or theme.limeDark)
                    or (hovered and theme.hover or theme.control)
                local knobSize = hovered and 15 or 14
                tween(toggle, {BackgroundColor3 = background})
                tween(knob, {
                    Position = knobPosition(enabled, knobSize),
                    Size = UDim2.fromOffset(knobSize, knobSize),
                    BackgroundColor3 = enabled and theme.lime or Color3.fromRGB(235, 236, 237),
                })
            end
            table.insert(pageThemeRefreshers, renderToggle)
            toggle.MouseEnter:Connect(function()
                hovered = true
                renderToggle()
            end)
            toggle.MouseLeave:Connect(function()
                hovered = false
                renderToggle()
            end)
            toggle.Activated:Connect(function()
                enabled = not enabled
                example.Value = enabled
                renderToggle()
                if example.ApplyGlass == true and type(callbacks.OnGlassChanged) == "function" then
                    callbacks.OnGlassChanged(enabled)
                end
                if example.Notify == true then
                    showControlNotification(card, example.Label or "Toggle", example.NotifyText or (enabled and "Enabled" or "Disabled"), theme,
                        enabled and theme.lime or theme.muted)
                end
            end)
            renderToggle()
        elseif example.Type == "Slider" then
            local control = create("Frame", card, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(184, 30),
                BackgroundTransparency = 1,
            })
            local track = create("TextButton", control, {
                Position = UDim2.fromOffset(0, 3),
                Size = UDim2.new(1, -44, 0, 24),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                Active = true,
            })
            local visualTrack = create("Frame", track, {
                Position = UDim2.new(0, 0, 0.5, -2),
                Size = UDim2.new(1, 0, 0, 4),
                BackgroundColor3 = theme.control,
                BorderSizePixel = 0,
                Active = false,
            })
            round(visualTrack, 3)
            local fill = create("Frame", visualTrack, {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = theme.lime, BorderSizePixel = 0, Active = false})
            round(fill, 3)
            local knob = create("Frame", visualTrack, {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = theme.lime,
                BorderSizePixel = 0,
            })
            round(knob, 6)
            local valueLabel = create("TextLabel", control, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(38, 24),
                BackgroundTransparency = 1,
                TextColor3 = theme.text,
                Font = Enum.Font.GothamMedium,
                TextSize = 11,
                Text = "",
                TextXAlignment = Enum.TextXAlignment.Right,
            })
            local minValue = example.Min or 0
            local maxValue = example.Max or 100
            local step = example.Step or 1
            local value = math.clamp(example.Value or minValue, minValue, maxValue)
            local initialAlpha = math.clamp((value - minValue) / math.max(maxValue - minValue, 1), 0, 1)
            local function renderSliderVisual(alpha)
                if not (fill.Parent and knob.Parent) then return end
                fill.Size = UDim2.new(alpha, 0, 1, 0)
                knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            end
            local setSliderVisualAlpha = createSliderSmoother(renderSliderVisual, initialAlpha, function()
                return fill.Parent ~= nil and knob.Parent ~= nil
            end)
            renderSliderVisual(initialAlpha)
            local dragging = false
            local sliderHovered = false
            local function renderSliderHover()
                local hovered = sliderHovered and not dragging
                tween(knob, {
                    BackgroundColor3 = hovered and theme.text or theme.lime,
                    Size = UDim2.fromOffset(hovered and 15 or 12, hovered and 15 or 12),
                })
            end
            local function renderSlider(alphaOverride)
                local alpha = math.clamp((value - minValue) / math.max(maxValue - minValue, 1), 0, 1)
                setSliderVisualAlpha(alphaOverride or alpha)
                valueLabel.Text = tostring(value) .. (example.Suffix or "")
                example.Value = value
            end
            local function refreshSliderTheme()
                tween(visualTrack, {BackgroundColor3 = theme.control})
                tween(fill, {BackgroundColor3 = theme.lime})
                renderSliderHover()
                valueLabel.TextColor3 = theme.text
            end
            table.insert(pageThemeRefreshers, refreshSliderTheme)
            local function setAt(x)
                local width = track.AbsoluteSize.X
                if width <= 0 then return end
                local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
                local raw = minValue + (maxValue - minValue) * alpha
                value = math.clamp(minValue + math.floor((raw - minValue) / step + 0.5) * step, minValue, maxValue)
                renderSlider(alpha)
            end
            knob.MouseEnter:Connect(function()
                sliderHovered = true
                renderSliderHover()
            end)
            knob.MouseLeave:Connect(function()
                sliderHovered = false
                renderSliderHover()
            end)
            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    renderSliderHover()
                    setAt(input.Position.X)
                end
            end)
            connectToSession(UserInputService.InputChanged, function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    setAt(input.Position.X)
                end
            end)
            connectToSession(UserInputService.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                    renderSliderHover()
                end
            end)
            renderSlider()
        elseif example.Type == "Input" then
            local input = create("TextBox", card, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(174, 30),
                BackgroundColor3 = theme.control,
                BorderSizePixel = 0,
                Text = example.Value or "",
                PlaceholderText = example.Placeholder or "Enter text...",
                PlaceholderColor3 = theme.muted,
                TextColor3 = theme.text,
                Font = Enum.Font.Gotham,
                TextSize = 11,
                ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
            round(input, 8)
            input.FocusLost:Connect(function()
                example.Value = input.Text
            end)
        elseif example.Type == "Dropdown" then
            local options = example.Options or {"Option 1"}
            if #options == 0 then options = {"Option 1"} end
            local index = table.find(options, example.Value) or 1
            local dropdown = makeButton(card, "", 156, false)
            dropdown.ZIndex = 21
            dropdown.TextXAlignment = Enum.TextXAlignment.Left
            create("UIPadding", dropdown, {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 28)})
            local dropdownIcon = LucideIcons.Create(dropdown, "chevron-down", {
                Name = "DropdownChevron",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                Color = theme.muted,
                ZIndex = dropdown.ZIndex + 1,
            })
            local visibleOptions = math.max(1, example.VisibleOptions or 4)
            local itemHeight = 27
            local menu = create("ScrollingFrame", card, {
                Name = "DropdownOptions",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 50),
                Size = UDim2.fromOffset(156, math.min(#options, visibleOptions) * itemHeight),
                BackgroundColor3 = theme.control,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = theme.lime,
                Active = true,
                Visible = false,
                ZIndex = 22,
            })
            round(menu, 8)
            create("UIStroke", menu, {Color = theme.line, Transparency = 0.2, Thickness = 1})
            create("UIListLayout", menu, {Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder})
            local open = false
            local function setOpen(value)
                open = value
                menu.Visible = open
                card.ZIndex = open and 20 or 1
                dropdown.ZIndex = open and 21 or 1
                if dropdownIcon then
                    dropdownIcon.ZIndex = dropdown.ZIndex + 1
                    dropdownIcon.Rotation = open and 180 or 0
                end
                dropdown.Text = tostring(options[index])
                if open then menu.CanvasPosition = Vector2.new(0, 0) end
            end
            for optionIndex, option in ipairs(options) do
                local optionButton = create("TextButton", menu, {
                    Name = "Option" .. tostring(optionIndex),
                    LayoutOrder = optionIndex,
                    Size = UDim2.new(1, -6, 0, 26),
                    BackgroundColor3 = theme.control,
                    BorderSizePixel = 0,
                    Text = tostring(option),
                    TextColor3 = theme.text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Font = Enum.Font.Gotham,
                    TextSize = 11,
                    AutoButtonColor = false,
                    ZIndex = 23,
                })
                round(optionButton, 6)
                optionButton.MouseEnter:Connect(function() tween(optionButton, {BackgroundColor3 = theme.hover}) end)
                optionButton.MouseLeave:Connect(function() tween(optionButton, {BackgroundColor3 = theme.control}) end)
                optionButton.Activated:Connect(function()
                    index = optionIndex
                    example.Value = option
                    if example.ApplyTheme == true and type(callbacks.OnThemeChanged) == "function" then
                        callbacks.OnThemeChanged(option)
                    end
                    setOpen(false)
                end)
            end
            dropdown.Activated:Connect(function() setOpen(not open) end)
            connectToSession(UserInputService.InputBegan, function(input)
                if not open or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then return end
                local point = input.Position
                local function contains(guiObject)
                    local position = guiObject.AbsolutePosition
                    local size = guiObject.AbsoluteSize
                    return point.X >= position.X and point.X <= position.X + size.X
                        and point.Y >= position.Y and point.Y <= position.Y + size.Y
                end
                if not contains(dropdown) and not contains(menu) then setOpen(false) end
            end)
            setOpen(false)
        elseif example.Type == "Keybind" then
            local key = example.Value or Enum.KeyCode.F
            local waiting = false
            local keyButton = makeButton(card, key.Name, 110, false)
            keyButton.MouseEnter:Connect(function() tween(keyButton, {BackgroundColor3 = waiting and theme.limeDark or theme.hover}) end)
            keyButton.MouseLeave:Connect(function() tween(keyButton, {BackgroundColor3 = waiting and theme.limeDark or theme.control}) end)
            keyButton.Activated:Connect(function()
                waiting = true
                keyButton.Text = "Press a key"
                tween(keyButton, {BackgroundColor3 = theme.limeDark})
            end)
            connectToSession(UserInputService.InputBegan, function(input, gameProcessed)
                if waiting then
                    if not gameProcessed and input.KeyCode ~= Enum.KeyCode.Unknown then
                        key = input.KeyCode
                        example.Value = key
                        waiting = false
                        keyButton.Text = key.Name
                        tween(keyButton, {BackgroundColor3 = theme.control})
                    end
                    return
                end
                if not gameProcessed and input.KeyCode == key and type(callbacks.OnKeybindPressed) == "function" then
                    callbacks.OnKeybindPressed(key)
                end
            end)
        elseif example.Type == "ColorPicker" then
            local colors = example.Colors or defaultColors(theme)
            local selectedColor = typeof(example.Value) == "Color3" and example.Value or colors[1]
            local picker = makeButton(card, "Choose", 132, true)
            picker.TextXAlignment = Enum.TextXAlignment.Left
            create("UIPadding", picker, {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 38)})
            local previewChip = create("Frame", picker, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -7, 0.5, 0),
                Size = UDim2.fromOffset(22, 22),
                BackgroundColor3 = selectedColor,
                BorderSizePixel = 0,
                ZIndex = 12,
            })
            round(previewChip, 6)
            create("UIStroke", previewChip, {Color = theme.line, Thickness = 1})
            local editor
            picker.Activated:Connect(function()
                if editor and editor.IsOpen then
                    editor:Close()
                    editor = nil
                    return
                end
                editor = openColorEditor(picker, theme, selectedColor, colors, function(color)
                    selectedColor = color
                    example.Value = color
                    previewChip.BackgroundColor3 = color
                    if type(callbacks.OnColorChanged) == "function" then
                        callbacks.OnColorChanged(color)
                    end
                end)
            end)
            example.Value = selectedColor
        elseif example.Type == "Palette" then
            local colors = example.Colors or {theme.lime}
            local selected = table.find(colors, example.Value) or 1
            local holder = create("Frame", card, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.fromOffset(184, 30),
                BackgroundTransparency = 1,
            })
            local strokes = {}
            for index, color in ipairs(colors) do
                local swatch = create("TextButton", holder, {
                    Position = UDim2.fromOffset((index - 1) * 29, 4),
                    Size = UDim2.fromOffset(22, 22),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                })
                round(swatch, 6)
                strokes[index] = create("UIStroke", swatch, {Color = theme.line, Thickness = 1})
                swatch.MouseEnter:Connect(function() tween(swatch, {Size = UDim2.fromOffset(25, 25)}) end)
                swatch.MouseLeave:Connect(function() tween(swatch, {Size = UDim2.fromOffset(22, 22)}) end)
                swatch.Activated:Connect(function()
                    selected = index
                    example.Value = color
                    for i, outline in ipairs(strokes) do
                        outline.Color = i == selected and theme.lime or theme.line
                        outline.Thickness = i == selected and 2 or 1
                    end
                end)
            end
            for index, outline in ipairs(strokes) do
                outline.Color = index == selected and theme.lime or theme.line
                outline.Thickness = index == selected and 2 or 1
            end
        end
    end

    return page, sectionLayout
end

return ControlLibrary

end)()
local LucideIcons = ControlLibrary.Icons

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
	applyUiTypography(object)
	object.Parent = parent
	return object
end

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOOLTIP_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TOOLTIP_HIDE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOGGLE_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SELECTION_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local function animateTo(object, properties, tweenInfo)
	local tween = TweenService:Create(object, tweenInfo or HOVER_TWEEN, properties)
	tween:Play()
	return tween
end

local function round(parent, radius)
	make("UICorner", parent, {CornerRadius = UDim.new(0, radius or 10)})
end

local function stroke(parent, color, transparency)
	make("UIStroke", parent, {Color = color or COLORS.line, Transparency = transparency or 0.25, Thickness = 1})
end

local glassEnabled = false

-- ===== Fenêtre principale et cycle de vie =====
local gui = make("ScreenGui", playerGui, {
	Name = "HipoControlsBaseGui",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 2147483647,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
})
local sessionShutdown = make("BindableFunction", gui, {Name = "HipoControlsSessionShutdown"})

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
local VISIBILITY_OPEN_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local VISIBILITY_CLOSE_TWEEN = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local camera = workspace.CurrentCamera
local function updateScale()
	if not camera then return end
		scaler.Scale = math.clamp(math.min(camera.ViewportSize.X / 860, camera.ViewportSize.Y / 560), 0.34, 1)
end
updateScale()
if camera then connectToSession(camera:GetPropertyChangedSignal("ViewportSize"), updateScale) end

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
	local backgroundTween = TweenService:Create(panel, tweenInfo, {
		BackgroundTransparency = glassEnabled and (shouldShow and 0.02 or 0.2) or (shouldShow and 0.04 or 0.2),
	})
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

-- ===== Thèmes et personnalisation visuelle =====
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
local customAccentColor

local THEME_ROLE_ATTRIBUTE_PREFIX = "HipoControlsThemeRole_"

local function applyTheme(themeName)
	local basePalette = THEME_PALETTES[themeName]
	if not basePalette then return false end
	local palette = table.clone(basePalette)
	if customAccentColor then
		palette.lime = customAccentColor
		palette.limeHover = customAccentColor:Lerp(Color3.new(1, 1, 1), 0.22)
		palette.limeDark = customAccentColor:Lerp(palette.panel, 0.64)
		palette.limeDarkHover = customAccentColor:Lerp(palette.panel, 0.48)
	end
	if glassEnabled then
		local frostedTint = Color3.fromRGB(128, 143, 163)
		local tintStrength = {
			panel = 0.18, rail = 0.16, card = 0.26, row = 0.22,
			control = 0.24, hover = 0.25, hoverStrong = 0.28,
		}
		for _, role in ipairs({"panel", "rail", "card", "row", "control", "hover", "hoverStrong"}) do
			local color = palette[role]
			if color then
				local _, _, brightness = Color3.toHSV(color)
				if brightness < 0.58 then
					palette[role] = color:Lerp(frostedTint, tintStrength[role] or 0.22)
				end
			end
		end
		local _, _, panelBrightness = Color3.toHSV(palette.panel)
		if panelBrightness < 0.58 then
			-- Keep secondary labels readable over the frosted surfaces while
			-- preserving a clear contrast with primary text.
			palette.text = palette.text:Lerp(Color3.fromRGB(255, 255, 255), 0.12)
			palette.muted = palette.muted:Lerp(palette.text, 0.64)

			-- Glass icons use the accent role; lift its brightness and saturation
			-- slightly so it stays visible against the pale glass sheen.
			local hue, saturation, value = Color3.toHSV(palette.lime)
			if saturation > 0.08 then
				palette.lime = Color3.fromHSV(hue, math.min(saturation * 1.16, 1), math.min(value * 1.16, 1))
				palette.limeHover = Color3.fromHSV(hue, math.min(saturation * 0.92, 1), 1)
			end
		end
	end

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
	for role, color in pairs(ControlLibrary.Theme) do
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
		elseif object:IsA("UIStroke") and object:GetAttribute("HipoGlassActive") ~= true then
			applyColorProperty(object, "Color")
		end
	end

	for role, color in pairs(palette) do
		if COLORS[role] ~= nil then COLORS[role] = color end
	end
	ControlLibrary.SetThemePalette(palette, overviewRoles)
	activeThemeName = themeName
	return true
end

local mainGlassSurfaces = {}
local navTooltipSurfaces = {}
local navHovered = {}
local globalGlassSurfaces = {}
local globalGlassDescendantConnection
local GLASS_GRADIENT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.04),
	NumberSequenceKeypoint.new(1, 0.08),
})
local GLASS_MODE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function setOptionalAttribute(object, name, value)
	object:SetAttribute(name, value)
end

local function addGlobalGlassToObject(object)
	if not glassEnabled or not object:IsA("GuiObject") or object:GetAttribute("HipoGlassSurface") == true then
		return
	end
	local isSurface = object:IsA("Frame") or object:IsA("TextButton")
		or object:IsA("TextBox") or object:IsA("ScrollingFrame")
	if not isSurface or object.BackgroundTransparency >= 1
		or object.AbsoluteSize.X < 72 or object.AbsoluteSize.Y < 24 then
		return
	end
	if globalGlassSurfaces[object] then return end

	local surface = {
		BackgroundTransparency = object.BackgroundTransparency,
		Gradient = nil,
		Stroke = nil,
		OwnsStroke = false,
	}
	local existingGradient = object:FindFirstChildOfClass("UIGradient")
	if not existingGradient then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "HipoAppleGlassGradient"
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 246, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 225, 242)),
		})
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.04),
			NumberSequenceKeypoint.new(1, 0.08),
		})
		gradient.Rotation = 90
		gradient.Parent = object
		surface.Gradient = gradient
	end

	local outline = object:FindFirstChildOfClass("UIStroke")
	if outline then
		surface.StrokeColor = outline.Color
		surface.StrokeTransparency = outline.Transparency
		surface.StrokeThickness = outline.Thickness
		surface.StrokeGlassActive = outline:GetAttribute("HipoGlassActive")
		surface.StrokeThemeRole = outline:GetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color")
	else
		outline = Instance.new("UIStroke")
		outline.Name = "HipoAppleGlassOutline"
		outline.Thickness = 1
		outline.Parent = object
		surface.OwnsStroke = true
	end
	surface.Stroke = outline
	outline.Color = Color3.fromRGB(190, 205, 224)
	outline.Transparency = 0.46
	outline:SetAttribute("HipoGlassActive", true)
	outline:SetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", nil)

	-- Keep glass subtle so theme colors remain clear over bright game worlds.
	object.BackgroundTransparency = math.max(surface.BackgroundTransparency, 0.02)
	globalGlassSurfaces[object] = surface
end

local function setGlobalGlassEnabled(enabled)
	if enabled then
		if not globalGlassDescendantConnection then
			globalGlassDescendantConnection = gui.DescendantAdded:Connect(function(object)
				scheduleSessionTask(0, addGlobalGlassToObject, object)
			end)
		end
		for _, object in ipairs(gui:GetDescendants()) do
			addGlobalGlassToObject(object)
		end
		return
	end

	if globalGlassDescendantConnection then
		globalGlassDescendantConnection:Disconnect()
		globalGlassDescendantConnection = nil
	end
	for object, surface in pairs(globalGlassSurfaces) do
		if object.Parent then
			object.BackgroundTransparency = surface.BackgroundTransparency
		end
		if surface.Gradient and surface.Gradient.Parent then
			surface.Gradient:Destroy()
		end
		if surface.Stroke and surface.Stroke.Parent then
			if surface.OwnsStroke then
				surface.Stroke:Destroy()
			else
				surface.Stroke.Color = surface.StrokeThemeRole and COLORS[surface.StrokeThemeRole] or surface.StrokeColor
				surface.Stroke.Transparency = surface.StrokeTransparency
				surface.Stroke.Thickness = surface.StrokeThickness
				setOptionalAttribute(surface.Stroke, "HipoGlassActive", surface.StrokeGlassActive)
				setOptionalAttribute(surface.Stroke, THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", surface.StrokeThemeRole)
			end
		end
	end
	table.clear(globalGlassSurfaces)
end

local function navTooltipBackgroundColor(isGlass)
	if isGlass then return COLORS.card:Lerp(COLORS.control, 0.35) end
	return COLORS.control
end

local function setGlassEnabled(enabled)
	glassEnabled = enabled == true
	applyTheme(activeThemeName)
	ControlLibrary.SetGlassEnabled(glassEnabled)
	setGlobalGlassEnabled(glassEnabled)
	animateTo(panel, {
		BackgroundTransparency = glassEnabled and (uiTargetVisible and 0.02 or 0.2)
			or (uiTargetVisible and 0.04 or 0.2),
	}, GLASS_MODE_TWEEN)
	for index = #mainGlassSurfaces, 1, -1 do
		local surface = mainGlassSurfaces[index]
		if not surface.Frame.Parent then
			table.remove(mainGlassSurfaces, index)
		else
			surface.Frame:SetAttribute("HipoGlassActive", glassEnabled)
			surface.Outline:SetAttribute("HipoGlassActive", glassEnabled)
			if glassEnabled then
				surface.Outline:SetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", nil)
			else
				surface.Outline:SetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", "line")
			end
			surface.Gradient.Transparency = glassEnabled and GLASS_GRADIENT or NumberSequence.new(1)
			animateTo(surface.Frame, {BackgroundTransparency = glassEnabled and 0.02 or 0}, GLASS_MODE_TWEEN)
			animateTo(surface.Outline, {
				Color = glassEnabled and Color3.fromRGB(190, 205, 224) or COLORS.line,
				Transparency = glassEnabled and 0.46 or 0.45,
			}, GLASS_MODE_TWEEN)
		end
	end
	for _, surface in ipairs(navTooltipSurfaces) do
		local isGlass = glassEnabled
		local isVisible = navHovered[surface.Index] and surface.Frame.Visible
		local tooltipBackground = navTooltipBackgroundColor(isGlass)
		surface.Frame.BackgroundColor3 = tooltipBackground
		surface.Frame:SetAttribute("HipoGlassActive", isGlass)
		surface.Outline:SetAttribute("HipoGlassActive", isGlass)
		if isGlass then
			surface.Outline:SetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", nil)
		else
			surface.Outline:SetAttribute(THEME_ROLE_ATTRIBUTE_PREFIX .. "Color", "line")
		end
		-- Sidebar tooltips keep a fully opaque fill, including in Apple Glass mode.
		-- A fully transparent UIGradient hides the frame fill itself.
		surface.Gradient.Enabled = false
		if isVisible then
			animateTo(surface.Frame, {
				BackgroundColor3 = tooltipBackground,
				BackgroundTransparency = 0,
			}, GLASS_MODE_TWEEN)
			animateTo(surface.Outline, {
				Color = isGlass and Color3.fromRGB(190, 205, 224) or COLORS.line,
			Transparency = isGlass and 0.62 or 0.5,
			}, GLASS_MODE_TWEEN)
			animateTo(surface.Sheen, {BackgroundTransparency = isGlass and 0.92 or 1}, GLASS_MODE_TWEEN)
		end
	end
end

local function applyAccentColor(color)
	if typeof(color) ~= "Color3" then return end
	customAccentColor = color
	applyTheme(activeThemeName)
end

local rail = make("Frame", panel, {
	Name = "NavigationRail",
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(0, 48, 1, -16),
	BackgroundColor3 = COLORS.rail,
	BorderSizePixel = 0,
	ClipsDescendants = false,
})
round(rail, 13)
stroke(rail, COLORS.line, 0.55)

local navTooltipLayer = make("Frame", gui, {
	Name = "SidebarTooltipLayer",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ClipsDescendants = false,
	ZIndex = 10000,
})

local logo = LucideIcons.Create(rail, "crosshair", {
	Name = "HipoControlsLogo",
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
local navHoverPills = {}
local navLabels = {}
local navOutlines = {}
local navTooltipScales = {}
local navTooltipSheens = {}
local navTooltipWidths = {}
local navContentPositions = {}
local navItems = {}
local settingsNavItem = nil
local selectedNavIndex = 1
local selectSidebarItem
local navContainer
local SidebarGroupMethods = {}
SidebarGroupMethods.__index = SidebarGroupMethods

local NAV_TOOLTIP_HEIGHT = 26

local function getNavTooltipPosition(index)
	local button = navButtons[index]
	if not button then return UDim2.zero end
	local uiScale = math.max(scaler.Scale, 0.01)
	local buttonPosition = button.AbsolutePosition
	local buttonSize = button.AbsoluteSize
	local overlayOrigin = navTooltipLayer.AbsolutePosition
	local x = rail.AbsolutePosition.X + rail.AbsoluteSize.X + 8 - overlayOrigin.X
	local y = buttonPosition.Y + (buttonSize.Y - NAV_TOOLTIP_HEIGHT * uiScale) / 2 - overlayOrigin.Y
	return UDim2.fromOffset(x / uiScale, y / uiScale)
end

local function updateNavButton(index, isSelectionChange)
	local button = navButtons[index]
	if not button then return end
	local selected = index == selectedNavIndex
	local hovered = navHovered[index]
	local background = selected and (hovered and COLORS.limeDarkHover or COLORS.limeDark)
		or (hovered and COLORS.hover or COLORS.rail)
	local textColor = selected and (hovered and COLORS.limeHover or COLORS.lime)
		or (hovered and COLORS.text or COLORS.muted)
	animateTo(button, {
		BackgroundColor3 = background,
		BackgroundTransparency = 0,
		TextColor3 = textColor,
	}, isSelectionChange and SELECTION_TWEEN or nil)
	if navIconImages[index] then
		animateTo(navIconImages[index], {ImageColor3 = textColor}, isSelectionChange and SELECTION_TWEEN or nil)
	end
	local pill = navHoverPills[index]
	if pill then
		local tooltipBackground = navTooltipBackgroundColor(glassEnabled)
		local targetPosition = getNavTooltipPosition(index)
		if hovered then
			if not pill.Visible then
				pill.Position = targetPosition + UDim2.fromOffset(-5, 0)
				pill.BackgroundColor3 = tooltipBackground
				pill.BackgroundTransparency = 0
				navTooltipScales[index].Scale = 0.94
				if navLabels[index] then navLabels[index].TextTransparency = 1 end
				if navOutlines[index] then navOutlines[index].Transparency = 1 end
				if navTooltipSheens[index] then navTooltipSheens[index].BackgroundTransparency = 1 end
			end
			pill.Visible = true
			animateTo(pill, {
				Position = targetPosition,
				BackgroundColor3 = tooltipBackground,
			}, TOOLTIP_TWEEN)
			animateTo(navTooltipScales[index], {Scale = 1}, TOOLTIP_TWEEN)
			if navLabels[index] then
				animateTo(navLabels[index], {
					TextColor3 = COLORS.text,
					TextTransparency = 0,
				}, TOOLTIP_TWEEN)
			end
			if navOutlines[index] then
				animateTo(navOutlines[index], {
					Color = glassEnabled and Color3.fromRGB(190, 205, 224) or COLORS.line,
					Transparency = glassEnabled and 0.62 or 0.5,
				}, TOOLTIP_TWEEN)
			end
			if navTooltipSheens[index] then
				animateTo(navTooltipSheens[index], {
					BackgroundTransparency = glassEnabled and 0.92 or 1,
				}, TOOLTIP_TWEEN)
			end
		else
			local hideTween = animateTo(pill, {
				Position = targetPosition + UDim2.fromOffset(-5, 0),
			}, TOOLTIP_HIDE_TWEEN)
			animateTo(navTooltipScales[index], {Scale = 0.97}, TOOLTIP_HIDE_TWEEN)
			if navLabels[index] then
				animateTo(navLabels[index], {TextColor3 = COLORS.muted, TextTransparency = 1}, TOOLTIP_HIDE_TWEEN)
			end
			if navOutlines[index] then
				animateTo(navOutlines[index], {Transparency = 1}, TOOLTIP_HIDE_TWEEN)
			end
			if navTooltipSheens[index] then
				animateTo(navTooltipSheens[index], {BackgroundTransparency = 1}, TOOLTIP_HIDE_TWEEN)
			end
			hideTween.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and not navHovered[index] then
					pill.Visible = false
				end
			end)
		end
	end
end

navContainer = make("ScrollingFrame", rail, {
	Name = "SidebarTabs",
	Position = UDim2.new(0, 0, 0, 60),
	Size = UDim2.new(1, 0, 1, -68),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ScrollBarThickness = 0,
	ScrollBarImageTransparency = 1,
	Active = true,
})

local activeIndicator = make("Frame", navContainer, {
	Name = "ActiveIndicator",
	Position = UDim2.new(0, 1, 0, 12),
	Size = UDim2.fromOffset(3, 18),
	BackgroundColor3 = COLORS.lime,
	BorderSizePixel = 0,
	Visible = true,
	ZIndex = 2,
})
round(activeIndicator, 2)

local function registerSidebarItem(name, icon)
	local index = #navItems + 1
	local isSettings = name == "Settings"
	local item = setmetatable({Name = name, Icon = icon, Tabs = {}, ActiveTab = nil}, SidebarGroupMethods)
	table.insert(navItems, item)
	local buttonPosition = isSettings
		and UDim2.fromOffset(7, 4 + (#navItems - 1) * 43)
		or UDim2.fromOffset(7, 4 + (index - 2) * 43)
	local button = make("TextButton", navContainer, {
		Name = "SidebarTabButton" .. tostring(index),
		Position = buttonPosition,
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = index == selectedNavIndex and COLORS.limeDark or COLORS.rail,
		BorderSizePixel = 0, Text = "",
		TextColor3 = index == selectedNavIndex and COLORS.lime or COLORS.muted,
		AutoButtonColor = false,
		ClipsDescendants = true,
		ZIndex = 20,
	})
	round(button, 10)
	navContentPositions[index] = button.Position
	item.Button = button
	if isSettings then settingsNavItem = item end
	navButtons[index] = button
	navTooltipWidths[index] = math.clamp(20 + #name * 6.25, 58, 106)
	navIconImages[index] = LucideIcons.Create(button, icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 17, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Color = index == selectedNavIndex and COLORS.lime or COLORS.muted,
	})
	navIconImages[index].ZIndex = 22
	local hoverPill = make("Frame", navTooltipLayer, {
		Name = "SidebarTooltip" .. tostring(index),
		Position = getNavTooltipPosition(index),
		Size = UDim2.fromOffset(navTooltipWidths[index], NAV_TOOLTIP_HEIGHT),
		BackgroundColor3 = navTooltipBackgroundColor(glassEnabled),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		Active = false,
		ZIndex = 10001,
	})
	hoverPill:SetAttribute("HipoGlassSurface", true)
	hoverPill:SetAttribute("HipoGlassActive", glassEnabled)
	round(hoverPill, 8)
	local tooltipGradient = make("UIGradient", hoverPill, {
		Name = "GlassGradient",
		Enabled = false,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 246, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 225, 242)),
		}),
		Transparency = NumberSequence.new(0),
		Rotation = 90,
	})
	local tooltipScale = make("UIScale", hoverPill, {Scale = 1})
	local sheen = make("Frame", hoverPill, {
		Name = "GlassSheen",
		Position = UDim2.new(0, 9, 0, 1),
		Size = UDim2.new(1, -18, 0, 1),
		BackgroundColor3 = Color3.fromRGB(245, 248, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 10002,
	})
	round(sheen, 1)
	local outline = make("UIStroke", hoverPill, {
		Color = glassEnabled and Color3.fromRGB(190, 205, 224) or COLORS.line,
		Transparency = 1,
		Thickness = 1,
	})
	outline:SetAttribute("HipoGlassActive", glassEnabled)
	navHoverPills[index] = hoverPill
	navOutlines[index] = outline
	navTooltipScales[index] = tooltipScale
	navTooltipSheens[index] = sheen
	navTooltipSurfaces[index] = {Index = index, Frame = hoverPill, Gradient = tooltipGradient, Outline = outline, Sheen = sheen}
	local label = make("TextLabel", hoverPill, {
		Name = "HoverName",
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		Text = string.upper(name),
		TextColor3 = COLORS.text,
		TextTransparency = 1,
		TextSize = 10,
		Font = Enum.Font.GothamSemibold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Active = false,
		ZIndex = 10003,
	})
	navLabels[index] = label
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
		if selectSidebarItem then selectSidebarItem(item) end
	end)
	if settingsNavItem and not isSettings then
		local settingsPosition = UDim2.fromOffset(7, 4 + (#navItems - 1) * 43)
		settingsNavItem.Button.Position = settingsPosition
		navContentPositions[1] = settingsPosition
		if selectedNavIndex == 1 then
			activeIndicator.Position = UDim2.new(0, 1, 0, settingsPosition.Y.Offset + 8)
		end
	end
	return item
end

local sidebarTabNames = {}

local top = make("Frame", panel, {
	Position = UDim2.fromOffset(64, 8), Size = UDim2.new(1, -72, 0, 42),
	BackgroundTransparency = 1,
})

local topTabsStrip = make("ScrollingFrame", top, {
	Name = "TopTabsStrip",
	Position = UDim2.new(0, 205, 0, 0),
	Size = UDim2.new(1, -225, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 0,
	ScrollBarImageTransparency = 1,
	Active = true,
})
make("UIListLayout", topTabsStrip, {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
})

local title = make("TextLabel", top, {
	Position = UDim2.fromOffset(12, 3), Size = UDim2.fromOffset(170, 34),
	BackgroundTransparency = 1, Text = menuTitle,
	TextColor3 = COLORS.muted, Font = Enum.Font.GothamMedium, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local tabs = {}
local pages = {}
local sectionPages = {}
local activeTab = "General"
local activeSidebarItem = nil
local firstUserTabSelected = false
local defaultTabSelected = false
local updateTabs
local selectTopTab
local body = make("Frame", panel, {
	Name = "ContentBody",
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

-- ===== Réglages intégrés et navigation =====
local settingsSidebarItem = registerSidebarItem("Settings", "settings")
sidebarTabNames[settingsSidebarItem.Name] = settingsSidebarItem
activeSidebarItem = settingsSidebarItem

local settingsSectionPage = makeSectionPage("SettingsSectionPage", true)
sectionPages.Settings = settingsSectionPage
local settingsPage, sectionLayout = ControlLibrary.BuildSettingsPage(settingsSectionPage, {
	Title = "Settings",
	Description = "Theme, interface shortcut, and accent color.",
	Examples = {},
	ColumnCount = 2,
})
local settingsExamples = ControlLibrary.SettingsExamples
local appearanceSection = sectionLayout:CreateSection("Appearance")

local themeExample = settingsExamples[1]
appearanceSection:Dropdown({
	Text = themeExample.Label,
	Description = themeExample.Description,
	Icon = themeExample.Icon,
	Options = themeExample.Options,
	Default = themeExample.Value,
	VisibleOptions = themeExample.VisibleOptions,
	Callback = applyTheme,
})

local keybindExample = settingsExamples[2]
appearanceSection:Keybind({
	Text = keybindExample.Label,
	Description = keybindExample.Description,
	Icon = keybindExample.Icon,
	Default = keybindExample.Value,
	Callback = function()
		setUIVisible(not uiTargetVisible)
	end,
})

local accentExample = settingsExamples[3]
appearanceSection:ColorPicker({
	Text = accentExample.Label,
	Description = accentExample.Description,
	Icon = accentExample.Icon,
	Colors = accentExample.Colors,
	Value = accentExample.Value,
	Callback = applyAccentColor,
})
settingsPage.Visible = true
local function registerTopTab(sidebarItem, name, page)
	local index = #sidebarItem.Tabs + 1
	local button = make("TextButton", topTabsStrip, {
		Name = "TopTab" .. tostring(#tabs + 1),
		LayoutOrder = index,
		Size = UDim2.fromOffset(math.clamp(18 + #name * 8, 58, 132), 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = name,
		TextColor3 = COLORS.muted,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		AutoButtonColor = false,
		Visible = sidebarItem == activeSidebarItem,
	})
	local underline = make("Frame", button, {
		Position = UDim2.new(0.18, 0, 1, -3),
		Size = UDim2.new(0.64, 0, 0, 2),
		BackgroundColor3 = COLORS.lime,
		BorderSizePixel = 0,
		Visible = false,
	})
	round(underline, 2)

	local entry = {
		Name = name,
		Owner = sidebarItem,
		Page = page,
		button = button,
		underline = underline,
		hovered = false,
	}
	table.insert(tabs, entry)
	table.insert(sidebarItem.Tabs, entry)
	if not sidebarItem.ActiveTab then sidebarItem.ActiveTab = entry end

	button.MouseEnter:Connect(function()
		entry.hovered = true
		if updateTabs then updateTabs() end
	end)
	button.MouseLeave:Connect(function()
		entry.hovered = false
		if updateTabs then updateTabs() end
	end)
	button.Activated:Connect(function()
		if selectTopTab then selectTopTab(entry) end
	end)
	return entry
end

registerTopTab(settingsSidebarItem, "General", settingsSectionPage)
sectionPages.General = settingsSectionPage
-- Les pages utilisateur et les contrôles personnalisés sont ajoutés plus bas.
updateTabs = function()
	for _, entry in ipairs(tabs) do
		local visible = entry.Owner == activeSidebarItem
		local selected = visible and entry.Owner.ActiveTab == entry
		local textColor = selected and COLORS.text
			or (entry.hovered and COLORS.text or COLORS.muted)
		entry.button.Visible = visible
		animateTo(entry.button, {TextColor3 = textColor})
		entry.underline.Visible = selected
	end
end
updateTabs()

local sectionTweens = {}
local sectionTransitionId = 0
local SECTION_ENTER_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SECTION_EXIT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function cancelSectionTweens()
	for _, tween in ipairs(sectionTweens) do
		tween:Cancel()
	end
	table.clear(sectionTweens)
end

local function transitionSection(oldPage, newPage)
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

	leaveTween:Play()
	enterTween:Play()
end

local currentVisiblePage = settingsSectionPage

selectTopTab = function(entry)
	if entry.Owner ~= activeSidebarItem then return end
	if activeSidebarItem.ActiveTab == entry and currentVisiblePage == entry.Page then return end

	local oldPage = currentVisiblePage
	activeSidebarItem.ActiveTab = entry
	activeTab = entry.Name
	currentVisiblePage = entry.Page
	transitionSection(oldPage, entry.Page)
	updateTabs()
end

selectSidebarItem = function(item)
	if item == activeSidebarItem then return end

	for index, registeredItem in ipairs(navItems) do
		if registeredItem == item then
			selectedNavIndex = index
			local contentPosition = navContentPositions[index]
			animateTo(activeIndicator, {
				Position = UDim2.new(0, 1, 0, contentPosition.Y.Offset + 8),
			}, SELECTION_TWEEN)
			for buttonIndex = 1, #navItems do
				updateNavButton(buttonIndex, true)
			end
			break
		end
	end

	local oldPage = currentVisiblePage
	activeSidebarItem = item
	local selectedTab = item.ActiveTab or item.Tabs[1]
	local newPage
	if selectedTab then
		item.ActiveTab = selectedTab
		activeTab = selectedTab.Name
		newPage = selectedTab.Page
	else
		activeTab = ""
		newPage = item.EmptyPage
	end

	if newPage then
		currentVisiblePage = newPage
		transitionSection(oldPage, newPage)
	end
	updateTabs()
end

local function selectSidebarPage(sidebarItem, entry)
	sidebarItem.ActiveTab = entry
	if sidebarItem == activeSidebarItem then
		selectTopTab(entry)
	else
		selectSidebarItem(sidebarItem)
	end
end

local nextSidebarPageId = 0
local function nextSidebarPageKey()
	repeat
		nextSidebarPageId += 1
	until not sectionPages["SidebarTab" .. tostring(nextSidebarPageId)]
	return "SidebarTab" .. tostring(nextSidebarPageId)
end

function SidebarGroupMethods:Tab(name)
	assert(type(name) == "string" and name ~= "", "Tab attend un nom non vide")
	for _, entry in ipairs(self.Tabs) do
		assert(entry.Name ~= name, "Ce Tab existe déjà dans " .. self.Name .. " : " .. name)
	end

	local pageKey = nextSidebarPageKey()
	local page = makeSectionPage(pageKey, false)
	sectionPages[pageKey] = page
	local controls = ControlLibrary.new(page, {
		Name = pageKey .. "Controls",
		Title = name,
	})
	local entry = registerTopTab(self, name, page)
	if #self.Tabs == 1 then
		self.ActiveTab = entry
		if self == activeSidebarItem then
			local oldPage = currentVisiblePage
			activeTab = name
			currentVisiblePage = page
			transitionSection(oldPage, page)
		end
	end

	local isConfiguredDefault = defaultTabPageName
		and entry.Name == defaultTabPageName
		and (defaultTabSidebarName == nil or self.Name == defaultTabSidebarName)
	if isConfiguredDefault and not defaultTabSelected then
		defaultTabSelected = true
		firstUserTabSelected = true
		selectSidebarPage(self, entry)
	elseif not firstUserTabSelected then
		firstUserTabSelected = true
		selectSidebarPage(self, entry)
	end

	updateTabs()
	return controls, entry
end
SidebarGroupMethods.AddTab = SidebarGroupMethods.Tab

-- Récupère ou ajoute un onglet latéral. Les Tabs se créent ensuite avec :Tab("Nom").
local function addSidebarTab(name, iconName)
	assert(type(name) == "string" and name ~= "", "addSidebarTab attend un nom non vide")
	local existingItem = sidebarTabNames[name]
	if iconName == nil and existingItem then iconName = existingItem.Icon end
	assert(type(iconName) == "string" and LucideIcons.Has(iconName), "addSidebarTab attend une icône Lucide valide")

	local item = existingItem or registerSidebarItem(name, iconName)
	if not existingItem then sidebarTabNames[name] = item end
	if not item.EmptyPage then
		local emptyPageKey = nextSidebarPageKey()
		item.EmptyPage = makeSectionPage(emptyPageKey, false)
		sectionPages[emptyPageKey] = item.EmptyPage
	end
	sidebarTabNames[name] = item
	return item
end

local draggingPanel = false
local dragStart, panelStart
local dragTouchInput
local dragZone = top

local function isInteractivePanelControlAt(position)
	for _, object in ipairs(panel:GetDescendants()) do
		if (object:IsA("GuiButton") or object:IsA("TextBox")) and object.Visible then
			local objectPosition, objectSize = object.AbsolutePosition, object.AbsoluteSize
			if position.X >= objectPosition.X and position.X <= objectPosition.X + objectSize.X
				and position.Y >= objectPosition.Y and position.Y <= objectPosition.Y + objectSize.Y then
				return true
			end
		end
	end
	return false
end

-- Listen globally so active children such as the top tab ScrollingFrame do not
-- swallow drag starts in the blank parts of the header.
connectToSession(UserInputService.InputBegan, function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local pointer = input.Position
	local zonePosition, zoneSize = dragZone.AbsolutePosition, dragZone.AbsoluteSize
	if pointer.X < zonePosition.X or pointer.X > zonePosition.X + zoneSize.X
		or pointer.Y < zonePosition.Y or pointer.Y > zonePosition.Y + zoneSize.Y
		or isInteractivePanelControlAt(pointer) then
		return
	end
	draggingPanel = true
	dragStart = pointer
	panelStart = panel.Position
	dragTouchInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
end)
connectToSession(UserInputService.InputChanged, function(input)
	if draggingPanel and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		if dragTouchInput and input.UserInputType == Enum.UserInputType.Touch and input ~= dragTouchInput then return end
		local delta = (input.Position - dragStart) / math.max(scaler.Scale, 0.01)
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local scale = math.max(scaler.Scale, 0.01)
		local viewportWidth, viewportHeight = viewport.X / scale, viewport.Y / scale
		local panelWidth, panelHeight = panel.AbsoluteSize.X / scale, panel.AbsoluteSize.Y / scale
		local minX = panelWidth * 0.5 + 8 - viewportWidth * 0.5
		local maxX = viewportWidth * 0.5 - panelWidth * 0.5 - 8
		local minY = panelHeight * 0.5 + 8 - viewportHeight * 0.5
		local maxY = viewportHeight * 0.5 - panelHeight * 0.5 - 8
		local nextX = panelStart.X.Offset + delta.X
		local nextY = panelStart.Y.Offset + delta.Y
		if minX <= maxX then nextX = math.clamp(nextX, minX, maxX) else nextX = 0 end
		if minY <= maxY then nextY = math.clamp(nextY, minY, maxY) else nextY = 0 end
		panel.Position = UDim2.new(panelStart.X.Scale, nextX, panelStart.Y.Scale, nextY)
	end
end)
connectToSession(UserInputService.InputEnded, function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or (dragTouchInput and input == dragTouchInput) then
		draggingPanel = false
		dragTouchInput = nil
	end
end)

local function shutdownCurrentSession()
	if sessionStopped then return end
	sessionStopped = true

	if glassEnabled then
		pcall(setGlassEnabled, false)
	end
	for _, connection in ipairs(sessionConnections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(sessionConnections)
	for _, thread in ipairs(sessionThreads) do
		pcall(task.cancel, thread)
	end
	table.clear(sessionThreads)
	cancelVisibilityTweens()
	cancelSectionTweens()
	draggingPanel = false
	if sessionShutdown then sessionShutdown.OnInvoke = nil end
	if gui.Parent then
		gui.Enabled = false
		gui:Destroy()
	end
end

sessionShutdown.OnInvoke = shutdownCurrentSession

-- ===== API de l’interface =====
local ui = {}

function ui:AddSidebarTab(name, iconName)
    return addSidebarTab(name, iconName)
end

-- Ajoute une ou plusieurs pages au même onglet latéral.
-- Retourne les contrôles de la première page, son entrée d'onglet, puis les contrôles indexés par nom.
function ui:AddPage(sidebarName, iconName, pageName, ...)
    assert(type(pageName) == "string" and pageName ~= "", "AddPage attend un nom de page non vide")

    local additionalPageNames = {}
    local requestedNames = {[pageName] = true}
    for index = 1, select("#", ...) do
        local additionalPageName = select(index, ...)
        assert(type(additionalPageName) == "string" and additionalPageName ~= "", "AddPage attend des noms de page non vides")
        assert(not requestedNames[additionalPageName], "AddPage a reçu deux fois le même nom de page : " .. additionalPageName)
        requestedNames[additionalPageName] = true
        table.insert(additionalPageNames, additionalPageName)
    end

    local sidebar = self:AddSidebarTab(sidebarName, iconName)
    local controls, entry = sidebar:Tab(pageName)
    local pagesByName = {[pageName] = controls}

    for _, additionalPageName in ipairs(additionalPageNames) do
        pagesByName[additionalPageName] = sidebar:Tab(additionalPageName)
    end

    return controls, entry, pagesByName
end

function ui:Destroy()
    shutdownCurrentSession()
end

applyTheme("Dark")
setUIVisible(true)
print("[HipoControls] Interface lancée dans Potassium.")

return ui
end

-- ===== API publique de la bibliothèque =====
local HipoControls = {}

function HipoControls.new(options)
    return createInterface(options)
end

return HipoControls
