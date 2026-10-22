-- Target Hunter: owner-only Studio/debug combat panel for this experience.
-- All player targeting, teleporting, following, and damage are validated here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "TargetHunterRemote"
local DAMAGE_PER_HIT = 12
local MIN_ATTACK_INTERVAL = 0.35
local MAX_ATTACK_INTERVAL = 2
local MAX_ATTACK_RANGE = 40
local MAX_LATCH_DISTANCE = 20

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteEvent") then
    warn(REMOTE_NAME .. " exists but is not a RemoteEvent")
    return
end
if not remote then
    remote = Instance.new("RemoteEvent")
    remote.Name = REMOTE_NAME
    remote.Parent = ReplicatedStorage
end

local states = {}
local access = {}
local combatWorkers = {}
local followWorkers = {}

local function isAuthorized(player)
    if RunService:IsStudio() then
        return true
    end
    if game.CreatorType == Enum.CreatorType.User then
        return player.UserId == game.CreatorId
    end
    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        return ok and rank >= 200
    end
    return false
end

local function getState(player)
    if not states[player] then
        states[player] = {
            targetUserId = 0,
            stickyLock = true,
            follow = false,
            autoKill = false,
            killAura = false,
            latchDistance = 3,
            attackRange = 40,
            attackInterval = 0.75,
            targetMethod = "Nearest",
            priorityCriteria = "Distance",
            attackMethod = "Nearest",
        }
    end
    return states[player]
end

local function getCharacterParts(player)
    local character = player.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return nil, nil, nil end
    return character, humanoid, root
end

local function isValidEnemy(attacker, target)
    if not target or target == attacker or not target.Parent then return false end
    if attacker.Team ~= nil and target.Team == attacker.Team then return false end
    local _, humanoid = getCharacterParts(target)
    return humanoid ~= nil
end

local function getTargetById(player, userId)
    local id = tonumber(userId)
    if not id or id <= 0 then return nil end
    local target = Players:GetPlayerByUserId(id)
    if isValidEnemy(player, target) then return target end
    return nil
end

local function distanceBetween(a, b)
    local _, _, rootA = getCharacterParts(a)
    local _, _, rootB = getCharacterParts(b)
    if not rootA or not rootB then return math.huge end
    return (rootA.Position - rootB.Position).Magnitude
end

local function getCandidates(player, method)
    local candidates = {}
    for _, target in ipairs(Players:GetPlayers()) do
        if isValidEnemy(player, target) then
            table.insert(candidates, target)
        end
    end
    table.sort(candidates, function(a, b)
        if method == "Lowest HP" then
            local _, humA = getCharacterParts(a)
            local _, humB = getCharacterParts(b)
            if humA and humB and humA.Health ~= humB.Health then
                return humA.Health < humB.Health
            end
        end
        return distanceBetween(player, a) < distanceBetween(player, b)
    end)
    return candidates
end

local function getSelectedTarget(player)
    local state = getState(player)
    local target = getTargetById(player, state.targetUserId)
    if target then return target end
    if state.stickyLock then
        state.targetUserId = 0
    end
    local method = state.targetMethod == "Lowest HP" and "Lowest HP" or state.priorityCriteria == "Health" and "Lowest HP" or "Nearest"
    return getCandidates(player, method)[1]
end

local function sendTargets(player)
    local targets = {}
    for _, target in ipairs(Players:GetPlayers()) do
        if isValidEnemy(player, target) then
            table.insert(targets, {
                userId = target.UserId,
                name = target.Name,
                displayName = target.DisplayName,
            })
        end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.displayName) < string.lower(b.displayName)
    end)
    remote:FireClient(player, "Targets", targets)
end

local function tryAttack(attacker, target, state)
    if not isValidEnemy(attacker, target) then return end
    local _, targetHumanoid = getCharacterParts(target)
    if not targetHumanoid then return end
    if target.Character and target.Character:FindFirstChildOfClass("ForceField") then return end
    if distanceBetween(attacker, target) > math.clamp(state.attackRange, 1, MAX_ATTACK_RANGE) then return end
    targetHumanoid:TakeDamage(DAMAGE_PER_HIT)
end

local function startCombatWorker(player)
    if combatWorkers[player] then return end
    combatWorkers[player] = true
    task.spawn(function()
        while player.Parent and states[player] do
            local state = getState(player)
            if state.autoKill or state.killAura then
                local target
                if state.killAura then
                    local method = state.attackMethod == "Lowest HP" and "Lowest HP" or "Nearest"
                    target = getCandidates(player, method)[1]
                else
                    target = getSelectedTarget(player)
                end
                if target then tryAttack(player, target, state) end
                task.wait(math.clamp(state.attackInterval, MIN_ATTACK_INTERVAL, MAX_ATTACK_INTERVAL))
            else
                task.wait(0.15)
            end
        end
        combatWorkers[player] = nil
    end)
end

local function startFollowWorker(player)
    if followWorkers[player] then return end
    followWorkers[player] = true
    task.spawn(function()
        while player.Parent and states[player] do
            local state = getState(player)
            if state.follow then
                local target = getSelectedTarget(player)
                local _, _, root = getCharacterParts(player)
                local targetRoot = nil
                if target then
                    local _, _, resolvedRoot = getCharacterParts(target)
                    targetRoot = resolvedRoot
                end
                if root and targetRoot then
                    local goal = targetRoot.CFrame * CFrame.new(0, 0, math.clamp(state.latchDistance, 1, MAX_LATCH_DISTANCE))
                    local delta = goal.Position - root.Position
                    if delta.Magnitude > 1.5 then
                        root.CFrame = root.CFrame:Lerp(CFrame.lookAt(goal.Position, targetRoot.Position), 0.18)
                    end
                end
                task.wait(0.1)
            else
                task.wait(0.15)
            end
        end
        followWorkers[player] = nil
    end)
end

local function setOption(player, key, value)
    local state = getState(player)
    if key == "stickyLock" or key == "follow" or key == "autoKill" or key == "killAura" then
        if typeof(value) ~= "boolean" then return end
        state[key] = value
    elseif key == "latchDistance" then
        state.latchDistance = math.clamp(tonumber(value) or 3, 1, MAX_LATCH_DISTANCE)
    elseif key == "attackRange" then
        state.attackRange = math.clamp(tonumber(value) or 40, 1, MAX_ATTACK_RANGE)
    elseif key == "attackInterval" then
        state.attackInterval = math.clamp(tonumber(value) or 0.75, MIN_ATTACK_INTERVAL, MAX_ATTACK_INTERVAL)
    elseif key == "targetMethod" then
        if value ~= "Nearest" and value ~= "Lowest HP" then return end
        state.targetMethod = value
    elseif key == "priorityCriteria" then
        if value ~= "Distance" and value ~= "Health" then return end
        state.priorityCriteria = value
    elseif key == "attackMethod" then
        if value ~= "Nearest" and value ~= "Lowest HP" then return end
        state.attackMethod = value
    else
        return
    end
    remote:FireClient(player, "Setting", key, state[key])
    startCombatWorker(player)
    startFollowWorker(player)
end

remote.OnServerEvent:Connect(function(player, action, value)
    if typeof(action) ~= "string" then return end
    if action == "Ready" then
        local allowed = isAuthorized(player)
        access[player] = allowed
        remote:FireClient(player, "Access", allowed)
        if allowed then
            getState(player)
            sendTargets(player)
        end
        return
    end
    if access[player] ~= true then return end

    local state = getState(player)
    if action == "RefreshPlayers" then
        sendTargets(player)
    elseif action == "SetTarget" then
        local target = getTargetById(player, value)
        if not target then
            state.targetUserId = 0
            remote:FireClient(player, "TargetChanged", 0, "Select...")
            return
        end
        state.targetUserId = target.UserId
        remote:FireClient(player, "TargetChanged", target.UserId, target.DisplayName)
    elseif action == "SwitchTarget" then
        local method = state.priorityCriteria == "Health" and "Lowest HP" or state.targetMethod == "Lowest HP" and "Lowest HP" or "Nearest"
        local candidates = getCandidates(player, method)
        if #candidates == 0 then return end
        local currentIndex = 0
        for index, target in ipairs(candidates) do
            if target.UserId == state.targetUserId then currentIndex = index break end
        end
        local nextTarget = candidates[(currentIndex % #candidates) + 1]
        state.targetUserId = nextTarget.UserId
        remote:FireClient(player, "TargetChanged", nextTarget.UserId, nextTarget.DisplayName)
    elseif action == "TeleportToTarget" then
        local target = getSelectedTarget(player)
        local character = player.Character
        local targetRoot = nil
        if target then
            local _, _, resolvedRoot = getCharacterParts(target)
            targetRoot = resolvedRoot
        end
        if character and targetRoot then
            character:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 3))
        end
    elseif action == "SetOption" then
        if typeof(value) ~= "table" then return end
        setOption(player, value.key, value.value)
    end
end)

Players.PlayerRemoving:Connect(function(leaving)
    states[leaving] = nil
    access[leaving] = nil
    combatWorkers[leaving] = nil
    followWorkers[leaving] = nil
    for player, state in pairs(states) do
        if state.targetUserId == leaving.UserId then
            state.targetUserId = 0
            if access[player] then
                remote:FireClient(player, "TargetChanged", 0, "Select...")
            end
        end
        if access[player] then sendTargets(player) end
    end
end)
