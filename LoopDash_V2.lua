--[[
    LoopDash v2 / Rework - Full Advanced Luau Script
    Archived & hosted version
]]

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CONFIG = {
    loopReworkAnimDetectId = "10503381238",
    loopReworkBlockAnimId = "10471478869",
}

local STATE = {
    loopRework = false,
    loopReworkUnloaded = false,
    loopReworkDebounce = false,
    loopReworkBlocked = false,
    loopReworkWaitDetect = 3,
    loopReworkWaitJump = 0,
    loopReworkWaitRemote = 1,
    loopReworkLockDuration = 15,
    loopReworkTargetRadius = 50,
    loopReworkCooldown = 10,
    loopReworkResponsiveness = 600,
    ForceJumpEnabled = false,
    ForceJumpUpwardVelocity = 52,
    ForceJumpDebounceTime = 18,
}

local Win = WindUI:CreateWindow({
    Title = "Dovi's Hub v1.2",
    Icon = "rbxassetid://88536674439005",
    Author = "Auto Tech",
    Folder = "DoviHub",
    Size = UDim2.fromOffset(650, 550),
    Theme = "Dark",
    HideSearchBar = false,
    NewElements = true,
    SideBarWidth = 200,
    HidePanelBackground = false,
})

local Tabs = {
    LoopDashv2 = Win:Tab({
        Title = "Loop Dash v2",
        Icon = "lucide:refresh-ccw-dot",
        Opened = true
    }),
}

Tabs.LoopDashv2:Paragraph({
    Title = "Loop Dash v2 / Rework",
    Desc = "Just better loop dash, can also be used for oreo tech !",
    Image = "lucide:refresh-ccw-dot",
    ImageSize = 20,
    Color = Color3.fromHex("#4ecdc4")
})

Tabs.LoopDashv2:Toggle({
    Title = "LoopDash v2 Enabled",
    Flag = "Save23",
    Value = STATE.loopRework,
    Callback = function(state)
        STATE.loopRework = state
        loopReworkSetupLoopRework()
        WindUI:Notify({
            Title = "LoopDash v2",
            Content = state and "ENABLED" or "DISABLED",
            Icon = state and "lucide:check" or "lucide:x",
            Duration = 2
        })
    end
})

Tabs.LoopDashv2:Toggle({
    Title = "Jump Assist",
    Flag = "Save24",
    Desc = "Use this for oreo tech !",
    Value = STATE.ForceJumpEnabled,
    Callback = function(state)
        STATE.ForceJumpEnabled = state
        if state then
            loopReworkForceJumpSetup()
            loopReworkForceJumpUpdateCharacter(player.Character)
        else
            loopReworkForceJumpUnload()
        end
    end
})

Tabs.LoopDashv2:Slider({
    Title = "Jump hight",
    Flag = "Save25",
    Value = { Min = 10, Max = 100, Default = STATE.ForceJumpUpwardVelocity or 52 },
    Callback = function(value)
        STATE.ForceJumpUpwardVelocity = value
    end
})

Tabs.LoopDashv2:Slider({
    Title = "Delay ",
    Flag = "Save26",
    Value = {Min = 0, Max = 10, Default = STATE.loopReworkWaitDetect},
    Callback = function(value)
        STATE.loopReworkWaitDetect = value
    end
})

Tabs.LoopDashv2:Slider({
    Title = "First Flick Delay",
    Flag = "Save27",
    Value = {Min = 0, Max = 10, Default = STATE.loopReworkWaitRemote},
    Callback = function(value)
        STATE.loopReworkWaitRemote = value
    end
})

Tabs.LoopDashv2:Slider({
    Title = "Smoothness",
    Flag = "Save28",
    Value = {Min = 1, Max = 1000, Default = STATE.loopReworkResponsiveness},
    Callback = function(value)
        STATE.loopReworkResponsiveness = value
    end
})

local loopReworkConnections = {}
local loopReworkActiveLockCleanup = nil

local loopReworkForceJumpConnections = {}
local loopReworkForceJumpCanUse = true
local loopReworkForceJumpCharacter = nil
local loopReworkForceJumpHumanoid = nil
local loopReworkForceJumpHRP = nil

function loopReworkSafeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

function loopReworkGetCharParts()
    local char = player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if humanoid and hrp then
        return char, humanoid, hrp
    end
    return nil
end

function loopReworkFireDashQW()
    local char = player.Character
    if not char then return end
    local comm = char:FindFirstChild("Communicate")
    if comm and typeof(comm.FireServer) == "function" then
        local args = {
            {
                Dash = Enum.KeyCode.W,
                Key = Enum.KeyCode.Q,
                Goal = "KeyPress"
            }
        }
        pcall(function() comm:FireServer(unpack(args)) end)
    end
end

function loopReworkFindBestTarget(maxRadius)
    maxRadius = maxRadius or STATE.loopReworkTargetRadius
    local live = Workspace:FindFirstChild("Live")
    if not live then return nil end
    local _, _, hrp = loopReworkGetCharParts()
    if not hrp then return nil end

    local bestRoot = nil
    local bestDist = maxRadius
    for _, model in ipairs(live:GetChildren()) do
        if model and model:IsA("Model") and model ~= player.Character then
            local root = model:FindFirstChild("HumanoidRootPart")
            local hum = model:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local nameOK = (model.Name == "Weakest Dummy") or (Players:GetPlayerFromCharacter(model) ~= nil)
                if nameOK then
                    local dist = (root.Position - hrp.Position).Magnitude
                    if dist <= bestDist then
                        bestDist = dist
                        bestRoot = root
                    end
                end
            end
        end
    end
    return bestRoot
end

function loopReworkModelHasBlockingAnim(model)
    if not model or not model.Parent then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local ok, tracks = pcall(function() return hum:GetPlayingAnimationTracks() end)
    if ok and tracks then
        for _, t in ipairs(tracks) do
            if t and t.Animation then
                local aid = tostring(t.Animation.AnimationId or "")
                if aid:find(CONFIG.loopReworkBlockAnimId, 1, true) then
                    return true
                end
            end
        end
    else
        for _, child in ipairs(hum:GetChildren()) do
            if child:IsA("Animation") then
                local aid = tostring(child.AnimationId or "")
                if aid:find(CONFIG.loopReworkBlockAnimId, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function loopReworkScanForBlockingAnim()
    local live = Workspace:FindFirstChild("Live")
    if not live then
        return false
    end
    for _, model in ipairs(live:GetChildren()) do
        if model and model:IsA("Model") and model ~= player.Character then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if loopReworkModelHasBlockingAnim(model) then
                    return true, model
                end
            end
        end
    end
    return false
end

function loopReworkStartHorizontalLockLerp(targetRoot, duration)
    if not targetRoot or not targetRoot.Parent then return nil end
    local char, humanoid, hrp = loopReworkGetCharParts()
    if not hrp or not humanoid then return nil end
    if duration <= 0 then return nil end

    local startT = tick()
    local conn = nil

    conn = RunService.RenderStepped:Connect(function(dt)
        if STATE.loopReworkBlocked or not STATE.loopRework then
            if conn then conn:Disconnect() end
            return
        end
        if not (targetRoot and targetRoot.Parent) then
            if conn then conn:Disconnect() end
            return
        end

        local hrpPos = hrp.Position
        local targetXZ = Vector3.new(targetRoot.Position.X, hrpPos.Y, targetRoot.Position.Z)
        if (targetXZ - hrpPos).Magnitude < 0.001 then
            -- already aligned
        else
            local desiredCFrame = CFrame.new(hrpPos, targetXZ)

            local resp = STATE.loopReworkResponsiveness
            resp = math.clamp(resp, 1, 10000)

            local alpha
            if resp >= 1000 then
                alpha = 1
            else
                local k = 0.02
                alpha = 1 - math.exp(-k * resp * dt)
                alpha = math.clamp(alpha, 0, 1)
            end

            if alpha >= 1 - 1e-6 then
                pcall(function() hrp.CFrame = desiredCFrame end)
            else
                local newCFrame = hrp.CFrame:Lerp(desiredCFrame, alpha)
                newCFrame = CFrame.new(hrpPos) * CFrame.fromMatrix(Vector3.new(), newCFrame.RightVector, newCFrame.UpVector)
                pcall(function() hrp.CFrame = newCFrame end)
            end
        end

        if tick() - startT >= duration then
            if conn then conn:Disconnect() end
            return
        end
    end)

    local function cleanup()
        if conn then pcall(function() conn:Disconnect() end) end
    end

    return cleanup
end

function loopReworkCancelActiveLockAndRestore()
    if loopReworkActiveLockCleanup then
        pcall(loopReworkActiveLockCleanup)
        loopReworkActiveLockCleanup = nil
    end
    local char = player.Character
    local humanoid = nil
    if char then
        humanoid = char:FindFirstChildOfClass("Humanoid")
    end
    pcall(function()
        if humanoid and humanoid.Parent then
            humanoid.AutoRotate = true
        end
    end)
end

function loopReworkForceJumpUpdateCharacter(char)
    if not char then
        loopReworkForceJumpCharacter = nil
        loopReworkForceJumpHumanoid = nil
        loopReworkForceJumpHRP = nil
        return
    end

    loopReworkForceJumpCharacter = char
    loopReworkForceJumpHumanoid = char:FindFirstChildOfClass("Humanoid")
    loopReworkForceJumpHRP = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

function loopReworkForceJumpDoJump(humanoid, hrp)
    if STATE.ForceJumpEnabled == false then
        return false
    end

    if not loopReworkForceJumpCanUse then
        return true
    end

    loopReworkForceJumpCanUse = false

    pcall(function()
        if humanoid and humanoid.Parent then
            humanoid.PlatformStand = false
            humanoid.Jump = true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    if hrp and hrp.Parent then
        pcall(function()
            local curr = hrp.AssemblyLinearVelocity
            local upwardVel = STATE.ForceJumpUpwardVelocity or 52
            hrp.AssemblyLinearVelocity = Vector3.new(curr.X, upwardVel, curr.Z)
        end)
        pcall(function()
            local v = hrp.Velocity
            local upwardVel = STATE.ForceJumpUpwardVelocity or 52
            hrp.Velocity = Vector3.new(v.X, upwardVel, v.Z)
        end)
    end

    local debounceTime = (STATE.ForceJumpDebounceTime or 18) / 100
    delay(debounceTime, function()
        loopReworkForceJumpCanUse = true
    end)

    return true
end

function loopReworkForceJumpSetup()
    if loopReworkForceJumpConnections.charAdded then return end
    loopReworkForceJumpConnections.charAdded = player.CharacterAdded:Connect(function(char)
        task.wait(1)
        loopReworkForceJumpUpdateCharacter(char)
    end)

    if player.Character then
        loopReworkForceJumpUpdateCharacter(player.Character)
    end
end

function loopReworkForceJumpUnload()
    if loopReworkForceJumpConnections.charAdded then
        pcall(function() loopReworkForceJumpConnections.charAdded:Disconnect() end)
        loopReworkForceJumpConnections.charAdded = nil
    end
    loopReworkForceJumpCharacter = nil
    loopReworkForceJumpHumanoid = nil
    loopReworkForceJumpHRP = nil
    loopReworkForceJumpCanUse = true
end

function loopReworkRunSequence()
    if STATE.loopReworkDebounce or not STATE.loopRework or STATE.loopReworkBlocked then return end
    STATE.loopReworkDebounce = true

    local waitDetectSeconds = STATE.loopReworkWaitDetect / 10
    local waitJumpSeconds = STATE.loopReworkWaitJump / 10
    local waitRemoteSeconds = STATE.loopReworkWaitRemote / 10
    local lockDurationSeconds = STATE.loopReworkLockDuration / 10
    local cooldownSeconds = STATE.loopReworkCooldown / 10

    local t0 = tick()
    while tick() - t0 < waitDetectSeconds do
        if not STATE.loopRework or STATE.loopReworkBlocked then
            STATE.loopReworkDebounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    if not STATE.loopRework or STATE.loopReworkBlocked then
        STATE.loopReworkDebounce = false
        return
    end

    local char, humanoid, hrp = loopReworkGetCharParts()
    if not humanoid or not hrp then
        STATE.loopReworkDebounce = false
        return
    end

    local prevAuto = nil
    pcall(function() prevAuto = humanoid.AutoRotate end)
    pcall(function() humanoid.AutoRotate = false end)

    local handled = false
    if STATE.ForceJumpEnabled == false then
        pcall(function()
            humanoid.Jump = true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
        handled = true
    else
        loopReworkForceJumpSetup()
        loopReworkForceJumpUpdateCharacter(char)
        handled = loopReworkForceJumpDoJump(humanoid, hrp)
        if not handled then
            pcall(function()
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end

    local t1 = tick()
    while tick() - t1 < waitJumpSeconds do
        if not STATE.loopRework or STATE.loopReworkBlocked then
            pcall(function() if humanoid and humanoid.Parent and prevAuto ~= nil then humanoid.AutoRotate = prevAuto end end)
            STATE.loopReworkDebounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    if not STATE.loopRework or STATE.loopReworkBlocked then
        pcall(function() if humanoid and humanoid.Parent and prevAuto ~= nil then humanoid.AutoRotate = prevAuto end end)
        STATE.loopReworkDebounce = false
        return
    end

    loopReworkFireDashQW()

    local t2 = tick()
    while tick() - t2 < waitRemoteSeconds do
        if not STATE.loopRework or STATE.loopReworkBlocked then
            pcall(function() if humanoid and humanoid.Parent and prevAuto ~= nil then humanoid.AutoRotate = prevAuto end end)
            STATE.loopReworkDebounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    if not STATE.loopRework or STATE.loopReworkBlocked then
        pcall(function() if humanoid and humanoid.Parent and prevAuto ~= nil then humanoid.AutoRotate = prevAuto end end)
        STATE.loopReworkDebounce = false
        return
    end

    local target = loopReworkFindBestTarget()
    local cleanupLock = nil
    if target and not STATE.loopReworkBlocked then
        cleanupLock = loopReworkStartHorizontalLockLerp(target, lockDurationSeconds)
        loopReworkActiveLockCleanup = cleanupLock
    end

    local keepOffUntil = tick() + math.max(lockDurationSeconds, 1.2)
    task.spawn(function()
        while tick() < keepOffUntil do
            if not STATE.loopRework or STATE.loopReworkBlocked then break end
            pcall(function() if humanoid and humanoid.Parent then humanoid.AutoRotate = false end end)
            RunService.Heartbeat:Wait()
        end
        pcall(function() if humanoid and humanoid.Parent and prevAuto ~= nil then humanoid.AutoRotate = prevAuto end end)
    end)

    task.delay(lockDurationSeconds, function()
        if cleanupLock then
            pcall(cleanupLock)
            loopReworkActiveLockCleanup = nil
        end
    end)

    task.delay(cooldownSeconds, function()
        STATE.loopReworkDebounce = false
    end)
end

function loopReworkOnAnimationPlayed(track)
    if not STATE.loopRework or STATE.loopReworkDebounce or STATE.loopReworkBlocked then return end
    if not track or not track.Animation then return end
    local id = tostring(track.Animation.AnimationId or "")
    if id == CONFIG.loopReworkAnimDetectId or id:find(CONFIG.loopReworkAnimDetectId, 1, true) then
        task.spawn(loopReworkRunSequence)
    end
end

function loopReworkHookCharacter()
    if loopReworkConnections.anim then
        pcall(function() loopReworkConnections.anim:Disconnect() end)
        loopReworkConnections.anim = nil
    end
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        loopReworkConnections.anim = humanoid.AnimationPlayed:Connect(loopReworkOnAnimationPlayed)
    end
end

function loopReworkStartBlockChecker()
    if loopReworkConnections.blockChecker then
        pcall(function() loopReworkConnections.blockChecker:Disconnect() end)
        loopReworkConnections.blockChecker = nil
    end

    local lastCheck = 0
    loopReworkConnections.blockChecker = RunService.Heartbeat:Connect(function(dt)
        if not STATE.loopRework then return end
        lastCheck = lastCheck + dt
        if lastCheck < 0.12 then return end
        lastCheck = 0

        local found, model = loopReworkScanForBlockingAnim()
        if found and not STATE.loopReworkBlocked then
            STATE.loopReworkBlocked = true
            loopReworkCancelActiveLockAndRestore()
            if loopReworkConnections.anim then
                pcall(function() loopReworkConnections.anim:Disconnect() end)
                loopReworkConnections.anim = nil
            end
        elseif not found and STATE.loopReworkBlocked then
            STATE.loopReworkBlocked = false
            if STATE.loopRework then
                loopReworkHookCharacter()
            end
        end
    end)
end

function loopReworkSetupLoopRework()
    if not STATE.loopRework then
        if loopReworkConnections.anim then
            pcall(function() loopReworkConnections.anim:Disconnect() end)
            loopReworkConnections.anim = nil
        end
        if loopReworkConnections.blockChecker then
            pcall(function() loopReworkConnections.blockChecker:Disconnect() end)
            loopReworkConnections.blockChecker = nil
        end
        if loopReworkConnections.charAdded then
            pcall(function() loopReworkConnections.charAdded:Disconnect() end)
            loopReworkConnections.charAdded = nil
        end
        loopReworkCancelActiveLockAndRestore()
        STATE.loopReworkDebounce = false
        STATE.loopReworkBlocked = false
        return
    end

    loopReworkHookCharacter()
    loopReworkStartBlockChecker()

    if loopReworkConnections.charAdded then
        pcall(function() loopReworkConnections.charAdded:Disconnect() end)
    end
    loopReworkConnections.charAdded = player.CharacterAdded:Connect(function()
        task.wait(1)
        if STATE.loopRework then
            loopReworkHookCharacter()
        end
    end)

    loopReworkForceJumpSetup()
end
