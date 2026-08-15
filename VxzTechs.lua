--[[
    Vxz Techs
    Research-based settings for:
    - Loop Dash (Floater focused)
    - Supa Tech
    + Ping Set system
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
    SupaUppercutKeywords = {"upper", "Upper", "1050", "1047", "punch", "M1"},
}

-- ////////// GLOBAL PING //////////
local UserPing = 80 -- default, user can save their real ping

-- ////////// LOOP DASH (Floater optimized defaults from research) //////////
-- Research notes:
-- Classic Loop Dash prefers LOWER your ping (<100)
-- Opponent higher ping helps floaters
-- Hit torso/chest center = floater instead of knockback
-- First flick timing is the most important
local LoopDash = {
    Enabled          = false,
    Debounce         = false,
    Blocked          = false,
    WaitDetect       = 1.2,     -- Faster detect for better floaters
    WaitJump         = 0,
    WaitRemote       = 0.35,    -- Tight first flick (critical for floater)
    LockDuration     = 14,      -- Longer lock helps stay under for float
    TargetRadius     = 48,
    Cooldown         = 5.5,
    Responsiveness   = 980,     -- Very high for tight lock under opponent
    Connections      = {},
    ActiveLockCleanup = nil,
}

-- ////////// SUPA TECH (Research based) //////////
-- Best ping range from research: ~120-160ms
-- Needs unshiftlock + instant dash after uppercut + slight backstep
local SupaTech = {
    Enabled          = false,
    Debounce         = false,
    AutoUnshift      = true,
    AutoDash         = true,
    BackstepStrength = 9,
    DashDelay        = 0.025,   -- Extremely tight
    Cooldown         = 0.32,
    DetectRadius     = 11,
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

local TabSupa = Win:Tab({
    Title = "Supa Tech",
    Icon = "lucide:zap",
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

-- Auto-adjust timings based on saved ping (research driven)
local function ApplyPingBasedTuning()
    local p = UserPing or 80

    -- Loop Dash prefers lower ping for classic floaters
    if p <= 60 then
        LoopDash.WaitRemote = 0.28
        LoopDash.WaitDetect = 1.0
        LoopDash.Responsiveness = 990
    elseif p <= 100 then
        LoopDash.WaitRemote = 0.35
        LoopDash.WaitDetect = 1.2
        LoopDash.Responsiveness = 970
    else
        -- Higher ping = slightly more delay tolerance
        LoopDash.WaitRemote = 0.42
        LoopDash.WaitDetect = 1.5
        LoopDash.Responsiveness = 940
    end

    -- Supa Tech sweet spot ~120-160
    if p >= 110 and p <= 170 then
        SupaTech.DashDelay = 0.022
        SupaTech.BackstepStrength = 9
    elseif p < 110 then
        SupaTech.DashDelay = 0.035  -- slightly more delay on low ping
        SupaTech.BackstepStrength = 7
    else
        SupaTech.DashDelay = 0.018
        SupaTech.BackstepStrength = 11
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
--                    SUPA TECH LOGIC
-- ======================================================

local function IsLikelyUppercut(track)
    if not track or not track.Animation then return false end
    local id = tostring(track.Animation.AnimationId or ""):lower()
    local name = (track.Name or ""):lower()
    for _, key in ipairs(CONFIG.SupaUppercutKeywords) do
        if id:find(key:lower(), 1, true) or name:find(key:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function PerformSupaTech()
    if not SupaTech.Enabled or SupaTech.Debounce then return end

    local char, humanoid, hrp = GetCharParts()
    if not humanoid or not hrp then return end

    local target = FindNearestTarget(SupaTech.DetectRadius)
    if not target then return end

    SupaTech.Debounce = true

    -- Backstep (research: slight back movement is key)
    pcall(function()
        local look = hrp.CFrame.LookVector
        local back = -look * SupaTech.BackstepStrength
        hrp.AssemblyLinearVelocity = Vector3.new(back.X, hrp.AssemblyLinearVelocity.Y, back.Z)
    end)

    -- Force unshiftlock
    if SupaTech.AutoUnshift then
        pcall(function()
            if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end)
    end

    task.delay(SupaTech.DashDelay, function()
        if not SupaTech.Enabled then
            SupaTech.Debounce = false
            return
        end

        if SupaTech.AutoDash then
            FireDash()
        end

        task.wait(0.015)
        pcall(function()
            if hrp and hrp.Parent then
                local look = hrp.CFrame.LookVector
                local curr = hrp.AssemblyLinearVelocity
                hrp.AssemblyLinearVelocity = Vector3.new(curr.X + look.X * 5, curr.Y, curr.Z + look.Z * 5)
            end
        end)
    end)

    task.delay(SupaTech.Cooldown, function()
        SupaTech.Debounce = false
    end)
end

local function OnSupaAnimPlayed(track)
    if not SupaTech.Enabled or SupaTech.Debounce then return end
    if IsLikelyUppercut(track) then
        task.spawn(PerformSupaTech)
    end
end

local function HookSupaCharacter()
    if SupaTech.Connections.Anim then
        pcall(function() SupaTech.Connections.Anim:Disconnect() end)
        SupaTech.Connections.Anim = nil
    end
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        SupaTech.Connections.Anim = humanoid.AnimationPlayed:Connect(OnSupaAnimPlayed)
    end
end

local function SetupSupaTech(state)
    if not state then
        for _, conn in pairs(SupaTech.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        SupaTech.Connections = {}
        SupaTech.Debounce = false
        return
    end

    HookSupaCharacter()

    if SupaTech.Connections.CharAdded then
        pcall(function() SupaTech.Connections.CharAdded:Disconnect() end)
    end
    SupaTech.Connections.CharAdded = player.CharacterAdded:Connect(function()
        task.wait(0.7)
        if SupaTech.Enabled then
            HookSupaCharacter()
        end
    end)
end

-- ======================================================
--                    UI - LOOP DASH
-- ======================================================

TabLoop:Paragraph({
    Title = "Loop Dash (Floater Focus)",
    Desc = "Research based • Hit torso center for floaters • Low ping preferred",
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
--                    UI - SUPA TECH
-- ======================================================

TabSupa:Paragraph({
    Title = "Supa Tech",
    Desc = "Research based • Best at 120-160 ping • Unshift + Instant Dash",
    Image = "lucide:zap",
    ImageSize = 18,
    Color = Color3.fromHex("#ff9f43")
})

TabSupa:Toggle({
    Title = "Enable Supa Tech",
    Flag = "ST_Enable",
    Value = SupaTech.Enabled,
    Callback = function(v)
        SupaTech.Enabled = v
        SetupSupaTech(v)
        WindUI:Notify({ Title = "Supa Tech", Content = v and "ENABLED" or "DISABLED", Icon = v and "lucide:check" or "lucide:x", Duration = 2 })
    end
})

TabSupa:Toggle({ Title = "Auto Unshiftlock", Flag = "ST_Unshift", Desc = "Core of real Supa Tech", Value = SupaTech.AutoUnshift, Callback = function(v) SupaTech.AutoUnshift = v end })
TabSupa:Toggle({ Title = "Auto Dash", Flag = "ST_Dash", Value = SupaTech.AutoDash, Callback = function(v) SupaTech.AutoDash = v end })
TabSupa:Slider({ Title = "Backstep Strength", Flag = "ST_Back", Value = { Min = 0, Max = 20, Default = SupaTech.BackstepStrength }, Callback = function(v) SupaTech.BackstepStrength = v end })
TabSupa:Slider({ Title = "Dash Delay (ms)", Flag = "ST_Delay", Value = { Min = 0, Max = 15, Default = math.floor(SupaTech.DashDelay * 100) }, Callback = function(v) SupaTech.DashDelay = v / 100 end })
TabSupa:Slider({ Title = "Detect Radius", Flag = "ST_Radius", Value = { Min = 5, Max = 25, Default = SupaTech.DetectRadius }, Callback = function(v) SupaTech.DetectRadius = v end })
TabSupa:Slider({ Title = "Cooldown", Flag = "ST_CD", Value = { Min = 10, Max = 80, Default = math.floor(SupaTech.Cooldown * 100) }, Callback = function(v) SupaTech.Cooldown = v / 100 end })

-- ======================================================
--                    UI - PING SET
-- ======================================================

TabPing:Paragraph({
    Title = "Ping Set",
    Desc = "Enter your current ping. Script auto-tunes Loop Dash & Supa Tech timings.",
    Image = "lucide:wifi",
    ImageSize = 18,
    Color = Color3.fromHex("#a29bfe")
})

local pingBox = TabPing:Input({
    Title = "Your Ping (ms)",
    Placeholder = "Example: 85",
    Flag = "PingInput",
    Value = tostring(UserPing),
    Callback = function(text)
        -- live update optional
    end
})

TabPing:Button({
    Title = "Save To Script",
    Callback = function()
        local raw = pingBox and pingBox.Value or tostring(UserPing)
        local num = tonumber(raw)

        if not num or num < 1 or num > 500 then
            WindUI:Notify({
                Title = "Ping Set",
                Content = "Invalid ping. Enter a number between 1-500",
                Icon = "lucide:x",
                Duration = 3
            })
            return
        end

        UserPing = math.floor(num)
        ApplyPingBasedTuning()

        WindUI:Notify({
            Title = "Ping Set",
            Content = "Saved " .. UserPing .. "ms • Timings auto-adjusted",
            Icon = "lucide:check",
            Duration = 3
        })
    end
})

TabPing:Paragraph({
    Title = "Research Notes",
    Desc = "Loop Dash floaters prefer your ping under 100.\nSupa Tech sweet spot is 120-160ms.\nHigher opponent ping helps both techs.",
    Image = "lucide:info",
    ImageSize = 16,
    Color = Color3.fromHex("#74b9ff")
})

-- Init
ApplyPingBasedTuning()

WindUI:Notify({
    Title = "Vxz Techs",
    Content = "Loaded with researched Floater + Supa settings",
    Icon = "lucide:check-circle",
    Duration = 3
})
