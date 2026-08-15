--[[
    Vxz Techs
    Fully separated systems:
    - Loop Dash (independent)
    - Oreo Tech (independent)
    Advanced Luau | Clean architecture
]]

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local player            = Players.LocalPlayer

-- ////////// CONFIG //////////
local CONFIG = {
    LoopDashAnimId   = "10503381238",
    BlockAnimId      = "10471478869",
}

-- ////////// STATE (completely separated) //////////
local LoopDash = {
    Enabled          = false,
    Debounce         = false,
    Blocked          = false,
    WaitDetect       = 1.5,
    WaitJump         = 0,
    WaitRemote       = 0.4,
    LockDuration     = 12,
    TargetRadius     = 55,
    Cooldown         = 6,
    Responsiveness   = 950,
    Connections      = {},
    ActiveLockCleanup = nil,
}

local OreoTech = {
    Enabled          = false,
    CanJump          = true,
    JumpVelocity     = 72,
    DebounceTime     = 0.14,
    AutoJump         = false,          -- when true, auto jumps when grounded
    Keybind          = Enum.KeyCode.Space,
    Connections      = {},
    Character        = nil,
    Humanoid         = nil,
    HRP              = nil,
}

-- ////////// WINDOW //////////
local Win = WindUI:CreateWindow({
    Title = "Vxz Techs",
    Icon = "rbxassetid://88536674439005",
    Author = "Vxz",
    Folder = "VxzTechs",
    Size = UDim2.fromOffset(620, 520),
    Theme = "Dark",
    HideSearchBar = false,
    NewElements = true,
    SideBarWidth = 180,
})

-- ////////// TABS //////////
local TabLoop = Win:Tab({
    Title = "Loop Dash",
    Icon = "lucide:refresh-ccw",
    Opened = true
})

local TabOreo = Win:Tab({
    Title = "Oreo Tech",
    Icon = "lucide:zap",
})

-- ======================================================
--                    LOOP DASH LOGIC
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

local function FireDashQW()
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

local function FindBestTarget(radius)
    radius = radius or LoopDash.TargetRadius
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

    -- Detect wait
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

    -- Basic jump (NO Oreo Tech dependency)
    pcall(function()
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)

    -- Jump wait
    local t1 = tick()
    while tick() - t1 < waitJump do
        if not LoopDash.Enabled or LoopDash.Blocked then
            humanoid.AutoRotate = prevAuto
            LoopDash.Debounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    FireDashQW()

    -- Remote wait
    local t2 = tick()
    while tick() - t2 < waitRemote do
        if not LoopDash.Enabled or LoopDash.Blocked then
            humanoid.AutoRotate = prevAuto
            LoopDash.Debounce = false
            return
        end
        RunService.Heartbeat:Wait()
    end

    local target = FindBestTarget()
    local cleanup
    if target and not LoopDash.Blocked then
        cleanup = StartHorizontalLock(target, lockTime)
        LoopDash.ActiveLockCleanup = cleanup
    end

    -- Keep AutoRotate off during lock
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

local function OnAnimPlayed(track)
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
        LoopDash.Connections.Anim = humanoid.AnimationPlayed:Connect(OnAnimPlayed)
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
        -- Unload
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
--                    OREO TECH LOGIC
-- ======================================================

local function UpdateOreoCharacter(char)
    if not char then
        OreoTech.Character = nil
        OreoTech.Humanoid = nil
        OreoTech.HRP = nil
        return
    end
    OreoTech.Character = char
    OreoTech.Humanoid  = char:FindFirstChildOfClass("Humanoid")
    OreoTech.HRP       = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

local function PerformOreoJump()
    if not OreoTech.Enabled or not OreoTech.CanJump then return false end

    local humanoid = OreoTech.Humanoid
    local hrp = OreoTech.HRP
    if not humanoid or not hrp or not humanoid.Parent or not hrp.Parent then return false end

    OreoTech.CanJump = false

    pcall(function()
        humanoid.PlatformStand = false
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)

    local vel = OreoTech.JumpVelocity or 72
    pcall(function()
        local curr = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(curr.X, vel, curr.Z)
    end)
    pcall(function()
        local v = hrp.Velocity
        hrp.Velocity = Vector3.new(v.X, vel, v.Z)
    end)

    task.delay(OreoTech.DebounceTime, function()
        OreoTech.CanJump = true
    end)

    return true
end

local function SetupOreoTech(state)
    if not state then
        for _, conn in pairs(OreoTech.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        OreoTech.Connections = {}
        OreoTech.CanJump = true
        return
    end

    -- Character tracking
    if OreoTech.Connections.CharAdded then
        pcall(function() OreoTech.Connections.CharAdded:Disconnect() end)
    end
    OreoTech.Connections.CharAdded = player.CharacterAdded:Connect(function(char)
        task.wait(0.6)
        UpdateOreoCharacter(char)
    end)

    if player.Character then
        UpdateOreoCharacter(player.Character)
    end

    -- Keybind (Space by default)
    if OreoTech.Connections.Input then
        pcall(function() OreoTech.Connections.Input:Disconnect() end)
    end
    OreoTech.Connections.Input = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not OreoTech.Enabled then return end
        if input.KeyCode == OreoTech.Keybind then
            PerformOreoJump()
        end
    end)

    -- Optional AutoJump when grounded
    if OreoTech.Connections.Heartbeat then
        pcall(function() OreoTech.Connections.Heartbeat:Disconnect() end)
    end
    OreoTech.Connections.Heartbeat = RunService.Heartbeat:Connect(function()
        if not OreoTech.Enabled or not OreoTech.AutoJump then return end
        local humanoid = OreoTech.Humanoid
        if humanoid and humanoid.Parent and humanoid.FloorMaterial ~= Enum.Material.Air then
            if OreoTech.CanJump then
                PerformOreoJump()
            end
        end
    end)
end

-- ======================================================
--                    UI - LOOP DASH TAB
-- ======================================================

TabLoop:Paragraph({
    Title = "Loop Dash",
    Desc = "Independent system • Animation detect → Jump + Dash + Lock",
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
        WindUI:Notify({
            Title = "Loop Dash",
            Content = v and "ENABLED" or "DISABLED",
            Icon = v and "lucide:check" or "lucide:x",
            Duration = 2
        })
    end
})

TabLoop:Slider({
    Title = "Detect Delay",
    Flag = "LD_Detect",
    Value = { Min = 0, Max = 10, Default = LoopDash.WaitDetect },
    Callback = function(v) LoopDash.WaitDetect = v end
})

TabLoop:Slider({
    Title = "First Flick Delay",
    Flag = "LD_Flick",
    Value = { Min = 0, Max = 10, Default = LoopDash.WaitRemote },
    Callback = function(v) LoopDash.WaitRemote = v end
})

TabLoop:Slider({
    Title = "Smoothness / Lock Strength",
    Flag = "LD_Smooth",
    Value = { Min = 1, Max = 1000, Default = LoopDash.Responsiveness },
    Callback = function(v) LoopDash.Responsiveness = v end
})

TabLoop:Slider({
    Title = "Lock Duration",
    Flag = "LD_Lock",
    Value = { Min = 1, Max = 30, Default = LoopDash.LockDuration },
    Callback = function(v) LoopDash.LockDuration = v end
})

TabLoop:Slider({
    Title = "Target Radius",
    Flag = "LD_Radius",
    Value = { Min = 10, Max = 100, Default = LoopDash.TargetRadius },
    Callback = function(v) LoopDash.TargetRadius = v end
})

TabLoop:Slider({
    Title = "Cooldown",
    Flag = "LD_CD",
    Value = { Min = 1, Max = 20, Default = LoopDash.Cooldown },
    Callback = function(v) LoopDash.Cooldown = v end
})

-- ======================================================
--                    UI - OREO TECH TAB
-- ======================================================

TabOreo:Paragraph({
    Title = "Oreo Tech",
    Desc = "Independent high-jump system • Press Space (or enable Auto)",
    Image = "lucide:zap",
    ImageSize = 18,
    Color = Color3.fromHex("#ff9f43")
})

TabOreo:Toggle({
    Title = "Enable Oreo Tech",
    Flag = "OT_Enable",
    Value = OreoTech.Enabled,
    Callback = function(v)
        OreoTech.Enabled = v
        SetupOreoTech(v)
        WindUI:Notify({
            Title = "Oreo Tech",
            Content = v and "ENABLED" or "DISABLED",
            Icon = v and "lucide:check" or "lucide:x",
            Duration = 2
        })
    end
})

TabOreo:Toggle({
    Title = "Auto Jump (when grounded)",
    Flag = "OT_Auto",
    Desc = "Automatically performs Oreo jump when on ground",
    Value = OreoTech.AutoJump,
    Callback = function(v)
        OreoTech.AutoJump = v
    end
})

TabOreo:Slider({
    Title = "Jump Height",
    Flag = "OT_Height",
    Value = { Min = 30, Max = 120, Default = OreoTech.JumpVelocity },
    Callback = function(v) OreoTech.JumpVelocity = v end
})

TabOreo:Slider({
    Title = "Jump Debounce",
    Flag = "OT_Debounce",
    Value = { Min = 5, Max = 40, Default = math.floor(OreoTech.DebounceTime * 100) },
    Callback = function(v) OreoTech.DebounceTime = v / 100 end
})

-- Final notify
WindUI:Notify({
    Title = "Vxz Techs",
    Content = "Loaded • Loop Dash & Oreo Tech are fully separated",
    Icon = "lucide:check-circle",
    Duration = 3
})
