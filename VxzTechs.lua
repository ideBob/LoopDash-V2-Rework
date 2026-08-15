--[[
    Vxz Techs
    Systems:
    - Loop Dash (Floater focused)
    - Instant Lethal Tech (researched)
    - Ping Set
]]

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local player           = Players.LocalPlayer

-- ////////// CONFIG //////////
local CONFIG = {
    LoopDashAnimId = "10503381238",
    BlockAnimId    = "10471478869",
}

-- ////////// GLOBAL PING //////////
local UserPing = 80

-- ////////// LOOP DASH (Floater optimized) //////////
local LoopDash = {
    Enabled          = false,
    Debounce         = false,
    Blocked          = false,
    WaitDetect       = 1.2,
    WaitJump         = 0,
    WaitRemote       = 0.35,
    LockDuration     = 14,
    TargetRadius     = 48,
    Cooldown         = 5.5,
    Responsiveness   = 980,
    Connections      = {},
    ActiveLockCleanup = nil,
}

-- ////////// INSTANT LETHAL TECH (Researched) //////////
-- Real Instant Lethal:
-- After Lethal Whirlwind ends → Instant Jump + Front Dash
-- Variants: Unshiftlock (easier) or Shiftlock + flick
-- Best with lower ping (<100)
local InstantLethal = {
    Enabled          = false,
    Debounce         = false,
    AutoJump         = true,
    AutoDash         = true,
    AutoUnshift      = true,          -- Unshift version (most consistent)
    ReshiftDelay     = 0.055,         -- How fast to turn shiftlock back on
    JumpDashDelay    = 0.01,          -- Tiny delay after detect
    Cooldown         = 0.45,
    Keybind          = Enum.KeyCode.E, -- Manual trigger key (or detect ability)
    Connections      = {},
}

-- ////////// WINDOW //////////
local Win = WindUI:CreateWindow({
    Title = "Vxz Techs",
    Icon = "rbxassetid://88536674439005",
    Author = "Vxz",
    Folder = "VxzTechs",
    Size = UDim2.fromOffset(640, 560),
    Theme = "Dark",
    HideSearchBar = false,
    NewElements = true,
    SideBarWidth = 185,
})

local TabLoop = Win:Tab({
    Title = "Loop Dash",
    Icon = "lucide:refresh-ccw",
    Opened = true
})

local TabLethal = Win:Tab({
    Title = "Instant Lethal",
    Icon = "lucide:swords",
})

local TabPing = Win:Tab({
    Title = "Ping Set",
    Icon = "lucide:wifi",
})

-- ======================================================
--                    HELPERS
-- ======================================================

local function GetCharParts()
    local char = player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if humanoid and hrp then
        return char, humanoid, hrp
    end
    return nil
end

local function FireDash()
    local char = player.Character
    if not char then return end
    local comm = char:FindFirstChild("Communicate")
    if comm and typeof(comm.FireServer) == "function" then
        pcall(function()
            comm:FireServer({
                Dash = Enum.KeyCode.W,
                Key  = Enum.KeyCode.Q,
                Goal = "KeyPress"
            })
        end)
    end
end

local function FindNearestTarget(radius)
    local live = Workspace:FindFirstChild("Live")
    if not live then return nil end
    local _, _, hrp = GetCharParts()
    if not hrp then return nil end

    local best, bestDist = nil, radius
    for _, model in ipairs(live:GetChildren()) do
        if model:IsA("Model") and model ~= player.Character then
            local root = model:FindFirstChild("HumanoidRootPart")
            local hum  = model:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local valid = (model.Name == "Weakest Dummy") or (Players:GetPlayerFromCharacter(model) ~= nil)
                if valid then
                    local dist = (root.Position - hrp.Position).Magnitude
                    if dist <= bestDist then
                        bestDist = dist
                        best = root
                    end
                end
            end
        end
    end
    return best
end

local function ApplyPingBasedTuning()
    local p = UserPing or 80

    if p <= 60 then
        LoopDash.WaitRemote = 0.28
        LoopDash.WaitDetect = 1.0
        LoopDash.Responsiveness = 990
        InstantLethal.ReshiftDelay = 0.045
        InstantLethal.JumpDashDelay = 0.008
    elseif p <= 100 then
        LoopDash.WaitRemote = 0.35
        LoopDash.WaitDetect = 1.2
        LoopDash.Responsiveness = 970
        InstantLethal.ReshiftDelay = 0.055
        InstantLethal.JumpDashDelay = 0.012
    else
        LoopDash.WaitRemote = 0.42
        LoopDash.WaitDetect = 1.5
        LoopDash.Responsiveness = 940
        InstantLethal.ReshiftDelay = 0.07
        InstantLethal.JumpDashDelay = 0.02
    end
end

-- ======================================================
--                    LOOP DASH LOGIC
-- ======================================================

local function HasBlockingAnim(model)
    if not model or not model.Parent then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local ok, tracks = pcall(function() return hum:GetPlayingAnimationTracks() end)
    if ok and tracks then
        for _, t in ipairs(tracks) do
            if t.Animation then
                local id = tostring(t.Animation.AnimationId or "")
                if id:find(CONFIG.BlockAnimId, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function ScanBlocking()
    local live = Workspace:FindFirstChild("Live")
    if not live then return false end
    for _, model in ipairs(live:GetChildren()) do
        if model:IsA("Model") and model ~= player.Character then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and HasBlockingAnim(model) then
                return true
            end
        end
    end
    return false
end

local function StartHorizontalLock(targetRoot, duration)
    if not targetRoot or not targetRoot.Parent then return nil end
    local _, humanoid, hrp = GetCharParts()
    if not hrp or not humanoid then return nil end
    if duration <= 0 then return nil end

    local startT = tick()
    local conn

    conn = RunService.RenderStepped:Connect(function(dt)
        if LoopDash.Blocked or not LoopDash.Enabled then
            if conn then conn:Disconnect() end
            return
        end
        if not (targetRoot and targetRoot.Parent) then
            if conn then conn:Disconnect() end
            return
        end

        local hrpPos = hrp.Position
        local targetXZ = Vector3.new(targetRoot.Position.X, hrpPos.Y, targetRoot.Position.Z)

        if (targetXZ - hrpPos).Magnitude >= 0.001 then
            local desired = CFrame.new(hrpPos, targetXZ)
            local resp = math.clamp(LoopDash.Responsiveness, 1, 10000)
            local alpha = (resp >= 1000) and 1 or math.clamp(1 - math.exp(-0.02 * resp * dt), 0, 1)

            if alpha >= 0.999 then
                pcall(function() hrp.CFrame = desired end)
            else
                local lerped = hrp.CFrame:Lerp(desired, alpha)
                local final = CFrame.new(hrpPos) * CFrame.fromMatrix(Vector3.zero, lerped.RightVector, lerped.UpVector)
                pcall(function() hrp.CFrame = final end)
            end
        end

        if tick() - startT >= duration then
            if conn then conn:Disconnect() end
        end
    end)

    return function()
        if conn then pcall(function() conn:Disconnect() end) end
    end
end

local function CancelLock()
    if LoopDash.ActiveLockCleanup then
        pcall(LoopDash.ActiveLockCleanup)
        LoopDash.ActiveLockCleanup = nil
    end
    local _, humanoid = GetCharParts()
    if humanoid then
        pcall(function() humanoid.AutoRotate = true end)
    end
end

local function RunLoopDashSequence()
    if LoopDash.Debounce or not LoopDash.Enabled or LoopDash.Blocked then return end
    LoopDash.Debounce = true

    local waitDetect  = LoopDash.WaitDetect / 10
    local waitJump    = LoopDash.WaitJump / 10
    local waitRemote  = LoopDash.WaitRemote / 10
    local lockTime    = LoopDash.LockDuration / 10
    local cooldown    = LoopDash.Cooldown / 10

    local t0 = tick()
    while tick() - t0 < waitDetect do
        if not LoopDash.Enabled or LoopDash.Blocked then
            LoopDash.Debounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    local char, humanoid, hrp = GetCharParts()
    if not humanoid or not hrp then
        LoopDash.Debounce = false
        return
    end

    local prevAuto = humanoid.AutoRotate
    humanoid.AutoRotate = false

    pcall(function()
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)

    local t1 = tick()
    while tick() - t1 < waitJump do
        if not LoopDash.Enabled or LoopDash.Blocked then
            humanoid.AutoRotate = prevAuto
            LoopDash.Debounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    FireDash()

    local t2 = tick()
    while tick() - t2 < waitRemote do
        if not LoopDash.Enabled or LoopDash.Blocked then
            humanoid.AutoRotate = prevAuto
            LoopDash.Debounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    local target = FindNearestTarget(LoopDash.TargetRadius)
    local cleanup
    if target and not LoopDash.Blocked then
        cleanup = StartHorizontalLock(target, lockTime)
        LoopDash.ActiveLockCleanup = cleanup
    end

    task.spawn(function()
        local untilT = tick() + math.max(lockTime, 1.1)
        while tick() < untilT do
            if not LoopDash.Enabled or LoopDash.Blocked then break end
            pcall(function() if humanoid.Parent then humanoid.AutoRotate = false end end)
            RunService.Heartbeat:Wait()
        end
        pcall(function() if humanoid.Parent then humanoid.AutoRotate = prevAuto end end)
    end)

    task.delay(lockTime, function()
        if cleanup then pcall(cleanup) end
        LoopDash.ActiveLockCleanup = nil
    end)

    task.delay(cooldown, function()
        LoopDash.Debounce = false
    end)
end

local function OnLoopAnimPlayed(track)
    if not LoopDash.Enabled or LoopDash.Debounce or LoopDash.Blocked then return end
    if not track or not track.Animation then return end
    local id = tostring(track.Animation.AnimationId or "")
    if id == CONFIG.LoopDashAnimId or id:find(CONFIG.LoopDashAnimId, 1, true) then
        task.spawn(RunLoopDashSequence)
    end
end

local function HookLoopDashCharacter()
    if LoopDash.Connections.Anim then
        pcall(function() LoopDash.Connections.Anim:Disconnect() end)
        LoopDash.Connections.Anim = nil
    end
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        LoopDash.Connections.Anim = humanoid.AnimationPlayed:Connect(OnLoopAnimPlayed)
    end
end

local function StartBlockChecker()
    if LoopDash.Connections.Block then
        pcall(function() LoopDash.Connections.Block:Disconnect() end)
    end

    local last = 0
    LoopDash.Connections.Block = RunService.Heartbeat:Connect(function(dt)
        if not LoopDash.Enabled then return end
        last += dt
        if last < 0.12 then return end
        last = 0

        local found = ScanBlocking()
        if found and not LoopDash.Blocked then
            LoopDash.Blocked = true
            CancelLock()
            if LoopDash.Connections.Anim then
                pcall(function() LoopDash.Connections.Anim:Disconnect() end)
                LoopDash.Connections.Anim = nil
            end
        elseif not found and LoopDash.Blocked then
            LoopDash.Blocked = false
            if LoopDash.Enabled then
                HookLoopDashCharacter()
            end
        end
    end)
end

local function SetupLoopDash(state)
    if not state then
        for _, conn in pairs(LoopDash.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        LoopDash.Connections = {}
        CancelLock()
        LoopDash.Debounce = false
        LoopDash.Blocked = false
        return
    end

    HookLoopDashCharacter()
    StartBlockChecker()

    if LoopDash.Connections.CharAdded then
        pcall(function() LoopDash.Connections.CharAdded:Disconnect() end)
    end
    LoopDash.Connections.CharAdded = player.CharacterAdded:Connect(function()
        task.wait(0.8)
        if LoopDash.Enabled then
            HookLoopDashCharacter()
        end
    end)
end

-- ======================================================
--               INSTANT LETHAL TECH LOGIC
-- ======================================================
-- Research:
-- After Lethal Whirlwind ends → Instant Jump + Front Dash
-- Unshiftlock version is most consistent for scripts
-- Lower ping = better consistency

local function PerformInstantLethal()
    if not InstantLethal.Enabled or InstantLethal.Debounce then return end

    local char, humanoid, hrp = GetCharParts()
    if not humanoid or not hrp then return end

    InstantLethal.Debounce = true

    -- 1. Optional Unshift (most popular consistent method)
    if InstantLethal.AutoUnshift then
        pcall(function()
            if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end)
    end

    -- 2. Tiny delay then Jump + Dash together (core of Instant Lethal)
    task.delay(InstantLethal.JumpDashDelay, function()
        if not InstantLethal.Enabled then
            InstantLethal.Debounce = false
            return
        end

        if InstantLethal.AutoJump then
            pcall(function()
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end

        if InstantLethal.AutoDash then
            FireDash()
        end

        -- 3. Quickly re-enable shiftlock (critical timing from tutorials ~0.05-0.06s)
        if InstantLethal.AutoUnshift then
            task.delay(InstantLethal.ReshiftDelay, function()
                pcall(function()
                    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
                end)
            end)
        end
    end)

    task.delay(InstantLethal.Cooldown, function()
        InstantLethal.Debounce = false
    end)
end

local function SetupInstantLethal(state)
    if not state then
        for _, conn in pairs(InstantLethal.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        InstantLethal.Connections = {}
        InstantLethal.Debounce = false
        return
    end

    -- Manual keybind trigger (press after Lethal ends)
    if InstantLethal.Connections.Input then
        pcall(function() InstantLethal.Connections.Input:Disconnect() end)
    end

    InstantLethal.Connections.Input = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not InstantLethal.Enabled then return end
        if input.KeyCode == InstantLethal.Keybind then
            PerformInstantLethal()
        end
    end)
end

-- ======================================================
--                    UI - LOOP DASH
-- ======================================================

TabLoop:Paragraph({
    Title = "Loop Dash (Floater Focus)",
    Desc = "Hit torso center for floaters • Low ping preferred",
    Image = "lucide:refresh-ccw",
    ImageSize = 18,
    Color = Color3.fromHex("#4ecdc4")
})

TabLoop:Toggle({
    Title = "Enable Loop Dash",
    Flag = "LD_Enable",
    Value = LoopDash.Enabled,
    Callback = function(v)
        LoopDash.Enabled = v
        SetupLoopDash(v)
        WindUI:Notify({ Title = "Loop Dash", Content = v and "ENABLED" or "DISABLED", Icon = v and "lucide:check" or "lucide:x", Duration = 2 })
    end
})

TabLoop:Slider({ Title = "Detect Delay", Flag = "LD_Detect", Value = { Min = 0, Max = 10, Default = LoopDash.WaitDetect }, Callback = function(v) LoopDash.WaitDetect = v end })
TabLoop:Slider({ Title = "First Flick Delay", Flag = "LD_Flick", Value = { Min = 0, Max = 10, Default = LoopDash.WaitRemote }, Callback = function(v) LoopDash.WaitRemote = v end })
TabLoop:Slider({ Title = "Smoothness / Lock (Floater)", Flag = "LD_Smooth", Value = { Min = 1, Max = 1000, Default = LoopDash.Responsiveness }, Callback = function(v) LoopDash.Responsiveness = v end })
TabLoop:Slider({ Title = "Lock Duration", Flag = "LD_Lock", Value = { Min = 1, Max = 30, Default = LoopDash.LockDuration }, Callback = function(v) LoopDash.LockDuration = v end })
TabLoop:Slider({ Title = "Target Radius", Flag = "LD_Radius", Value = { Min = 10, Max = 100, Default = LoopDash.TargetRadius }, Callback = function(v) LoopDash.TargetRadius = v end })
TabLoop:Slider({ Title = "Cooldown", Flag = "LD_CD", Value = { Min = 1, Max = 20, Default = LoopDash.Cooldown }, Callback = function(v) LoopDash.Cooldown = v end })

-- ======================================================
--                    UI - INSTANT LETHAL
-- ======================================================

TabLethal:Paragraph({
    Title = "Instant Lethal Tech",
    Desc = "After Lethal Whirlwind ends → Jump + Dash instantly\nPress keybind right when the move ends",
    Image = "lucide:swords",
    ImageSize = 18,
    Color = Color3.fromHex("#ff6b6b")
})

TabLethal:Toggle({
    Title = "Enable Instant Lethal",
    Flag = "IL_Enable",
    Value = InstantLethal.Enabled,
    Callback = function(v)
        InstantLethal.Enabled = v
        SetupInstantLethal(v)
        WindUI:Notify({ Title = "Instant Lethal", Content = v and "ENABLED" or "DISABLED", Icon = v and "lucide:check" or "lucide:x", Duration = 2 })
    end
})

TabLethal:Toggle({
    Title = "Auto Jump",
    Flag = "IL_Jump",
    Value = InstantLethal.AutoJump,
    Callback = function(v) InstantLethal.AutoJump = v end
})

TabLethal:Toggle({
    Title = "Auto Dash",
    Flag = "IL_Dash",
    Value = InstantLethal.AutoDash,
    Callback = function(v) InstantLethal.AutoDash = v end
})

TabLethal:Toggle({
    Title = "Unshiftlock Assist",
    Flag = "IL_Unshift",
    Desc = "Most consistent method from research",
    Value = InstantLethal.AutoUnshift,
    Callback = function(v) InstantLethal.AutoUnshift = v end
})

TabLethal:Slider({
    Title = "Reshift Delay (ms)",
    Flag = "IL_Reshift",
    Value = { Min = 2, Max = 15, Default = math.floor(InstantLethal.ReshiftDelay * 100) },
    Callback = function(v) InstantLethal.ReshiftDelay = v / 100 end
})

TabLethal:Slider({
    Title = "Jump+Dash Delay (ms)",
    Flag = "IL_Delay",
    Value = { Min = 0, Max = 10, Default = math.floor(InstantLethal.JumpDashDelay * 100) },
    Callback = function(v) InstantLethal.JumpDashDelay = v / 100 end
})

TabLethal:Slider({
    Title = "Cooldown",
    Flag = "IL_CD",
    Value = { Min = 10, Max = 100, Default = math.floor(InstantLethal.Cooldown * 100) },
    Callback = function(v) InstantLethal.Cooldown = v / 100 end
})

TabLethal:Paragraph({
    Title = "How to use",
    Desc = "1. Use Lethal Whirlwind\n2. The moment it ends press [E]\n3. Script does Jump + Dash + Unshift/Reshift",
    Image = "lucide:info",
    ImageSize = 16,
    Color = Color3.fromHex("#74b9ff")
})

-- ======================================================
--                    UI - PING SET
-- ======================================================

TabPing:Paragraph({
    Title = "Ping Set",
    Desc = "Enter your ping. Script auto-tunes both techs.",
    Image = "lucide:wifi",
    ImageSize = 18,
    Color = Color3.fromHex("#a29bfe")
})

local pingBox = TabPing:Input({
    Title = "Your Ping (ms)",
    Placeholder = "Example: 75",
    Flag = "PingInput",
    Value = tostring(UserPing),
    Callback = function() end
})

TabPing:Button({
    Title = "Save To Script",
    Callback = function()
        local raw = pingBox and pingBox.Value or tostring(UserPing)
        local num = tonumber(raw)

        if not num or num < 1 or num > 500 then
            WindUI:Notify({
                Title = "Ping Set",
                Content = "Invalid ping. Enter 1-500",
                Icon = "lucide:x",
                Duration = 3
            })
            return
        end

        UserPing = math.floor(num)
        ApplyPingBasedTuning()

        WindUI:Notify({
            Title = "Ping Set",
            Content = "Saved " .. UserPing .. "ms • Timings adjusted",
            Icon = "lucide:check",
            Duration = 3
        })
    end
})

TabPing:Paragraph({
    Title = "Research Notes",
    Desc = "Loop Dash floaters → your ping under 100\nInstant Lethal → lower ping is better (<100 ideal)\nOpponent higher ping helps both",
    Image = "lucide:info",
    ImageSize = 16,
    Color = Color3.fromHex("#74b9ff")
})

-- Init
ApplyPingBasedTuning()

WindUI:Notify({
    Title = "Vxz Techs",
    Content = "Loaded • Loop Dash + Instant Lethal + Ping Set",
    Icon = "lucide:check-circle",
    Duration = 3
})
