--[[
    Paint-by-Number Auto Painter
    -----------------------------
    Finds your own plot's ActivePicture folder, groups unpainted pixels
    (Parts with attribute D == false) by their color number (attribute N),
    fires the SelectNumber remote to pick that color, then walks continuously
    across matching pixels until they're painted (D flips to true), before
    moving to the next number. Repeats until nothing unpainted is left.

    CONTINUOUS MODE (default):
      - Character never stops to wait for a single pixel.
      - Loop is paced by RunService.Heartbeat (no fixed sleep).
      - MoveTo is issued only when the target actually changes
        (re-issuing to the same point caused stutter).
      - Current target is checked every frame (cheap attribute read).
      - Full O(n) rescan for a closer pixel is throttled by retargetInterval.

    CONTROLS (console):
        PaintBotStop()    -- stop permanently
        PaintBotPause()   -- pause in place
        PaintBotResume()  -- resume

    On-screen UI Start/Stop button does the same pause/resume toggle.

    CONFIG — check these before running
]]

local CONFIG = {
    -- If auto-detection of your plot fails, set your exact in-game
    -- username here (case-sensitive) and re-run.
    plotOwnerName = nil,

    -- Keep character in motion; retarget nearest unpainted pixel of the
    -- current number. When true, paintWaitTimeout is ignored.
    continuousMode = true,

    -- How often (seconds) to fully rescan pixels for a closer/new target
    -- while continuousMode is active. Only throttles the O(n) scan.
    retargetInterval = 0.1,

    -- Horizontal distance (studs) that counts as "arrived".
    -- Used only in legacy mode.
    arriveDistance = 3,

    -- LEGACY ONLY: after arriving, how long to wait for D to flip true.
    paintWaitTimeout = 2,

    -- Delay after SelectNumber so the game registers the color switch.
    selectNumberSettleTime = 0.25,

    -- Optional walk speed boost. nil = leave WalkSpeed alone.
    walkSpeedOverride = nil,

    -- Stuck recovery
    stuckCheckInterval = 1.0,
    stuckMoveThreshold = 1.5,
    maxStuckRecoveries = 3,

    -- Progress UI
    showProgressUI = true,
    progressUpdateInterval = 0.5,

    -- "ascending" | "descending" | "random"  (changeable live via UI)
    drawMode = "ascending",

    -- Persist drawMode across rejoins (needs writefile/readfile/isfile)
    saveConfig = true,
    configFile = "paintbot_config.json",

    -- Prevent ~20 min AFK kick
    antiAfk = true,

    -- Console logging
    verbose = true,

    -- Applied on spawn/respawn once the bot starts. nil to disable.
    defaultPlayerSpeed = 50,

    -- Destroy other players' ActivePicture parts for FPS.
    hideOtherCanvases = true,
    canvasScanInterval = 1.0,
    -- Yield every N destroys so a burst of streamed pixels doesn't freeze
    -- the paint loop for multiple seconds.
    canvasClearYieldEvery = 40,
}

----------------------------------------------------------------
-- Services
----------------------------------------------------------------

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local VirtualUser       = game:GetService("VirtualUser")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local SelectNumberEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SelectNumber")

----------------------------------------------------------------
-- Logging / control flags
----------------------------------------------------------------

local function log(...)
    if CONFIG.verbose then
        print("[PaintBot]", ...)
    end
end

if getgenv().PaintBotRunning then
    getgenv().PaintBotRunning = false
    task.wait(0.3)
end
getgenv().PaintBotRunning = true
getgenv().PaintBotPaused  = false

getgenv().PaintBotStop = function()
    getgenv().PaintBotRunning = false
    print("[PaintBot] Stop requested.")
end
getgenv().PaintBotPause = function()
    getgenv().PaintBotPaused = true
    print("[PaintBot] Paused.")
end
getgenv().PaintBotResume = function()
    getgenv().PaintBotPaused = false
    print("[PaintBot] Resumed.")
end

-- Sleeps while paused; returns as soon as running is false so callers can exit.
local function waitWhilePaused()
    while getgenv().PaintBotRunning and getgenv().PaintBotPaused do
        task.wait(0.15)
    end
end

local function stillRunning()
    return getgenv().PaintBotRunning == true
end

local function modeChanged(expected)
    return expected ~= nil and getgenv().PaintBotDrawMode ~= expected
end

----------------------------------------------------------------
-- Plot detection
----------------------------------------------------------------

local function findOwnPlot()
    local plotModels = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("PlotModels")
    if not plotModels then
        warn("[PaintBot] Could not find Workspace.Map.PlotModels")
        return nil
    end

    -- 1) Exact name match
    local tryName = CONFIG.plotOwnerName or LocalPlayer.Name
    local plot = plotModels:FindFirstChild(tryName)
    if plot and plot:FindFirstChild("ActivePicture") then
        log("Found plot by name match:", plot.Name)
        return plot
    end

    -- 2) Closest plot with an ActivePicture
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        warn("[PaintBot] No character/HumanoidRootPart for proximity fallback")
        return nil
    end

    local best, bestDist = nil, math.huge
    for _, candidate in ipairs(plotModels:GetChildren()) do
        local ap = candidate:FindFirstChild("ActivePicture")
        if ap then
            local base = candidate:FindFirstChild("PersistentParts")
            local ref = (base and base:FindFirstChild("Base"))
                or ap:FindFirstChildWhichIsA("Part")
            if ref then
                local d = (ref.Position - hrp.Position).Magnitude
                if d < bestDist then
                    bestDist, best = d, candidate
                end
            end
        end
    end

    if best then
        log("Found plot by proximity:", best.Name, "(", math.floor(bestDist), "studs)")
    else
        warn("[PaintBot] No plot with ActivePicture found")
    end
    return best
end

----------------------------------------------------------------
-- Pixel helpers (pure, no side effects)
----------------------------------------------------------------

local function distanceXZ(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- True if the part still exists and is unpainted.
local function isOpen(part)
    return part ~= nil
        and part.Parent ~= nil
        and part:GetAttribute("D") ~= true
end

-- Group all unpainted pixels by their N attribute.
-- Returns: groups = { [n] = {part, part, ...}, ... }
local function gatherUnpaintedByNumber(activePicture)
    local groups = {}
    for _, part in ipairs(activePicture:GetChildren()) do
        if part:IsA("BasePart") then
            local n = part:GetAttribute("N")
            if n ~= nil and part:GetAttribute("D") == false then
                local list = groups[n]
                if not list then
                    list = {}
                    groups[n] = list
                end
                list[#list + 1] = part
            end
        end
    end
    return groups
end

-- Live list of still-unpainted parts for one number.
-- skipSet (optional table): parts to ignore this pass (stuck give-ups).
local function gatherForNumber(activePicture, n, skipSet)
    local out = {}
    for _, part in ipairs(activePicture:GetChildren()) do
        if part:IsA("BasePart")
            and part:GetAttribute("N") == n
            and part:GetAttribute("D") == false
            and not (skipSet and skipSet[part])
        then
            out[#out + 1] = part
        end
    end
    return out
end

local function findNearest(parts, fromPos)
    local best, bestDist = nil, math.huge
    for i = 1, #parts do
        local part = parts[i]
        if part and part.Parent then
            local d = distanceXZ(fromPos, part.Position)
            if d < bestDist then
                bestDist, best = d, part
            end
        end
    end
    return best, bestDist
end

local function selectNumber(n)
    local ok, err = pcall(function()
        SelectNumberEvent:FireServer(n)
    end)
    if not ok then
        warn("[PaintBot] SelectNumber failed:", err)
    end
    log("Selected number", n)
    task.wait(CONFIG.selectNumberSettleTime)
end

local function pickNextNumber(numbers)
    local mode = getgenv().PaintBotDrawMode or "ascending"
    if mode == "descending" then
        local best = numbers[1]
        for i = 2, #numbers do
            if numbers[i] > best then best = numbers[i] end
        end
        return best
    elseif mode == "random" then
        return numbers[math.random(#numbers)]
    else
        local best = numbers[1]
        for i = 2, #numbers do
            if numbers[i] < best then best = numbers[i] end
        end
        return best
    end
end

----------------------------------------------------------------
-- Config persistence
----------------------------------------------------------------

local function loadConfig()
    if not CONFIG.saveConfig then return end
    print("[PaintBot][Config] Checking for", CONFIG.configFile)

    local okCheck, exists = pcall(function()
        return isfile and isfile(CONFIG.configFile)
    end)
    if not okCheck then
        warn("[PaintBot][Config] isfile() errored:", exists)
        return
    end
    if not exists then
        print("[PaintBot][Config] No saved config. Using defaults.")
        return
    end

    local okRead, content = pcall(function()
        return readfile(CONFIG.configFile)
    end)
    if not okRead then
        warn("[PaintBot][Config] readfile failed:", content)
        return
    end

    local okDecode, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not okDecode or type(data) ~= "table" or not data.drawMode then
        warn("[PaintBot][Config] Invalid config data")
        return
    end

    getgenv().PaintBotDrawMode = data.drawMode
    print("[PaintBot][Config] Loaded drawMode =", data.drawMode)
end

local function saveConfigToFile()
    if not CONFIG.saveConfig then return end
    local data = { drawMode = getgenv().PaintBotDrawMode }
    local okEncode, json = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not okEncode then
        warn("[PaintBot][Config] JSONEncode failed:", json)
        return
    end
    local okWrite, err = pcall(function()
        writefile(CONFIG.configFile, json)
    end)
    if okWrite then
        print("[PaintBot][Config] Saved:", json)
    else
        warn("[PaintBot][Config] writefile failed:", err)
    end
end

----------------------------------------------------------------
-- Anti-AFK
----------------------------------------------------------------

local function setupAntiAfk()
    if not CONFIG.antiAfk then return end

    local function nudge()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end

    LocalPlayer.Idled:Connect(function()
        log("Anti-AFK: Idled fired")
        nudge()
    end)

    task.spawn(function()
        while stillRunning() do
            task.wait(600)
            if not stillRunning() then break end
            log("Anti-AFK: periodic nudge")
            nudge()
        end
    end)

    log("Anti-AFK armed")
end
setupAntiAfk()

getgenv().PaintBotDrawMode = CONFIG.drawMode
loadConfig()

----------------------------------------------------------------
-- Speed / canvas clearing
----------------------------------------------------------------

local function applySpeed(character)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.WalkSpeed = CONFIG.defaultPlayerSpeed
end

local function armSpeedHook()
    if not CONFIG.defaultPlayerSpeed then return end
    if LocalPlayer.Character then
        applySpeed(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(applySpeed)
    log("Speed hook armed (WalkSpeed =", CONFIG.defaultPlayerSpeed, ")")
end

local function armCanvasClearing(plotModels, ownPlot)
    if not CONFIG.hideOtherCanvases then return end

    local yieldEvery = math.max(1, CONFIG.canvasClearYieldEvery or 40)

    task.spawn(function()
        local firstPass = true
        while stillRunning() do
            local plotsSeen, plotsWithCanvas, destroyed = 0, 0, 0
            local sinceYield = 0

            for _, candidate in ipairs(plotModels:GetChildren()) do
                plotsSeen = plotsSeen + 1
                if candidate ~= ownPlot then
                    local ap = candidate:FindFirstChild("ActivePicture")
                    if ap then
                        plotsWithCanvas = plotsWithCanvas + 1
                        for _, part in ipairs(ap:GetChildren()) do
                            if pcall(part.Destroy, part) then
                                destroyed = destroyed + 1
                            end
                            sinceYield = sinceYield + 1
                            if sinceYield >= yieldEvery then
                                sinceYield = 0
                                task.wait()
                                if not stillRunning() then return end
                            end
                        end
                    end
                end
            end

            if firstPass then
                log(string.format(
                    "Canvas clear: %d plots, %d with canvas, destroyed %d pixels",
                    plotsSeen, plotsWithCanvas, destroyed))
                firstPass = false
            end

            task.wait(CONFIG.canvasScanInterval)
        end
    end)
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local THEME = {
    bg       = Color3.fromRGB(24, 24, 27),
    titlebar = Color3.fromRGB(32, 32, 36),
    accent   = Color3.fromRGB(0, 255, 140),
    danger   = Color3.fromRGB(255, 70, 70),
    chipOff  = Color3.fromRGB(50, 50, 55),
    barBg    = Color3.fromRGB(45, 45, 50),
    text     = Color3.fromRGB(235, 235, 240),
    subtext  = Color3.fromRGB(170, 170, 180),
}

local function corner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.new(0, 0, 0)
    s.Thickness = thickness or 1
    s.Transparency = 0.5
    s.Parent = inst
    return s
end

local function makeButton(parent, text, opts)
    opts = opts or {}
    local btn = Instance.new("TextButton")
    btn.Size = opts.size or UDim2.new(1, 0, 0, 26)
    btn.BackgroundColor3 = opts.bg or THEME.chipOff
    btn.BackgroundTransparency = opts.transparency or 0.15
    btn.AutoButtonColor = false
    btn.Text = text
    btn.Font = opts.bold == false and Enum.Font.Gotham or Enum.Font.GothamBold
    btn.TextSize = opts.textSize or 13
    btn.TextColor3 = opts.textColor or THEME.text
    btn.Parent = parent
    corner(btn, opts.radius or 6)
    return btn
end

local function makeDraggable(handle, frame)
    local dragging, dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local ProgressLabel, ProgressBarFill, ControlButton

local function refreshControlButton()
    if not ControlButton then return end
    if getgenv().PaintBotPaused then
        ControlButton.Text = "Start"
        ControlButton.BackgroundColor3 = THEME.accent
        ControlButton.TextColor3 = Color3.fromRGB(10, 10, 10)
    else
        ControlButton.Text = "Stop"
        ControlButton.BackgroundColor3 = THEME.danger
        ControlButton.TextColor3 = Color3.new(1, 1, 1)
    end
end

local function createProgressUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PaintBotProgressUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 240, 0, 178)
    frame.Position = UDim2.new(0.5, -120, 0, 20)
    frame.BackgroundColor3 = THEME.bg
    frame.Parent = screenGui
    corner(frame, 10)
    stroke(frame, Color3.new(0, 0, 0), 1)

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = THEME.titlebar
    titleBar.Parent = frame
    corner(titleBar, 10)

    local titleBarMask = Instance.new("Frame")
    titleBarMask.Size = UDim2.new(1, 0, 0, 10)
    titleBarMask.Position = UDim2.new(0, 0, 1, -10)
    titleBarMask.BackgroundColor3 = THEME.titlebar
    titleBarMask.BorderSizePixel = 0
    titleBarMask.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -40, 1, 0)
    titleLabel.Position = UDim2.new(0, 12, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "PaintBot"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextColor3 = THEME.text
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    makeDraggable(titleBar, frame)

    local reopenTab = makeButton(screenGui, "≡ Menu", {
        size = UDim2.new(0, 70, 0, 26),
        bg = THEME.bg,
        textSize = 12,
    })
    reopenTab.Position = UDim2.new(0.5, -35, 0, 20)
    reopenTab.Visible = false
    stroke(reopenTab, Color3.new(0, 0, 0), 1)

    local function setMenuOpen(open)
        frame.Visible = open
        reopenTab.Visible = not open
    end
    reopenTab.MouseButton1Click:Connect(function()
        setMenuOpen(true)
    end)

    local closeButton = makeButton(titleBar, "X", {
        size = UDim2.new(0, 22, 0, 22),
        bg = Color3.fromRGB(60, 60, 66),
        textSize = 13,
    })
    closeButton.Position = UDim2.new(1, -28, 0.5, -11)
    closeButton.MouseButton1Click:Connect(function()
        setMenuOpen(false)
    end)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -20, 1, -42)
    content.Position = UDim2.new(0, 10, 0, 38)
    content.BackgroundTransparency = 1
    content.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 8)
    layout.Parent = content

    ProgressLabel = Instance.new("TextLabel")
    ProgressLabel.Size = UDim2.new(1, 0, 0, 16)
    ProgressLabel.BackgroundTransparency = 1
    ProgressLabel.TextColor3 = THEME.subtext
    ProgressLabel.Font = Enum.Font.Gotham
    ProgressLabel.TextSize = 12
    ProgressLabel.TextXAlignment = Enum.TextXAlignment.Left
    ProgressLabel.Text = "0% (0/0)"
    ProgressLabel.LayoutOrder = 1
    ProgressLabel.Parent = content

    local barBG = Instance.new("Frame")
    barBG.Size = UDim2.new(1, 0, 0, 12)
    barBG.BackgroundColor3 = THEME.barBg
    barBG.LayoutOrder = 2
    barBG.Parent = content
    corner(barBG, 6)

    ProgressBarFill = Instance.new("Frame")
    ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
    ProgressBarFill.BackgroundColor3 = THEME.accent
    ProgressBarFill.Parent = barBG
    corner(ProgressBarFill, 6)

    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, 0, 0, 26)
    modeRow.BackgroundTransparency = 1
    modeRow.LayoutOrder = 3
    modeRow.Parent = content

    local modeLayout = Instance.new("UIListLayout")
    modeLayout.FillDirection = Enum.FillDirection.Horizontal
    modeLayout.Padding = UDim.new(0, 6)
    modeLayout.Parent = modeRow

    local modeButtons = {}
    local function setActiveMode(mode)
        getgenv().PaintBotDrawMode = mode
        saveConfigToFile()
        for m, btn in pairs(modeButtons) do
            local active = (m == mode)
            btn.BackgroundColor3 = active and THEME.accent or THEME.chipOff
            btn.TextColor3 = active and Color3.fromRGB(10, 10, 10) or THEME.text
        end
    end

    local modes  = { "ascending", "descending", "random" }
    local labels = { ascending = "Asc", descending = "Desc", random = "Random" }
    for _, mode in ipairs(modes) do
        local btn = makeButton(modeRow, labels[mode], {
            size = UDim2.new(1 / 3, -4, 1, 0),
            textSize = 12,
        })
        modeButtons[mode] = btn
        btn.MouseButton1Click:Connect(function()
            setActiveMode(mode)
        end)
    end
    setActiveMode(getgenv().PaintBotDrawMode or "ascending")

    ControlButton = makeButton(content, "Stop", {
        size = UDim2.new(1, 0, 0, 30),
        textSize = 13,
    })
    ControlButton.LayoutOrder = 4
    ControlButton.MouseButton1Click:Connect(function()
        if getgenv().PaintBotPaused then
            getgenv().PaintBotResume()
        else
            getgenv().PaintBotPause()
        end
        refreshControlButton()
    end)

    refreshControlButton()
end

local function updateProgressUI(activePicture)
    if not ProgressLabel or not ProgressBarFill then return end

    local total, done = 0, 0
    for _, part in ipairs(activePicture:GetChildren()) do
        if part:IsA("BasePart") and part:GetAttribute("N") ~= nil then
            total = total + 1
            if part:GetAttribute("D") == true then
                done = done + 1
            end
        end
    end

    local pct = total > 0 and math.floor((done / total) * 100) or 0
    local suffix = getgenv().PaintBotPaused and "  ·  Paused" or ""
    ProgressLabel.Text = string.format("%d%% (%d/%d)%s", pct, done, total, suffix)
    ProgressBarFill.Size = UDim2.new(pct / 100, 0, 1, 0)
    refreshControlButton()
end

----------------------------------------------------------------
-- Movement helpers
----------------------------------------------------------------

local function attemptUnstick(humanoid, hrp, targetPos)
    log("Stuck detected — recovering")
    humanoid.Jump = true
    task.wait(0.2)

    local nudge = hrp.Position + Vector3.new(
        (math.random() - 0.5) * 6,
        0,
        (math.random() - 0.5) * 6
    )
    humanoid:MoveTo(nudge)
    task.wait(0.5)
    humanoid:MoveTo(targetPos)
end

-- Refresh character refs after respawn. Returns humanoid, hrp (may be nil).
local function getCharacterRefs()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return humanoid, hrp
end

----------------------------------------------------------------
-- LEGACY: walk to one pixel, wait for paint, return success
----------------------------------------------------------------

local function walkToPixel(part, humanoid, hrp, expectedMode)
    humanoid:MoveTo(part.Position)

    local waited = 0
    local lastPos = hrp.Position
    local lastCheck = tick()
    local recoveries = 0

    while stillRunning() do
        if getgenv().PaintBotPaused then
            waitWhilePaused()
            if not stillRunning() then return false end
            humanoid:MoveTo(part.Position)
            lastPos = hrp.Position
            lastCheck = tick()
        end

        if modeChanged(expectedMode) then return false end
        if waited >= 10 then return false end
        if not isOpen(part) then return true end

        if distanceXZ(hrp.Position, part.Position) <= CONFIG.arriveDistance then
            local paintWait = 0
            while stillRunning() and paintWait < CONFIG.paintWaitTimeout do
                if getgenv().PaintBotPaused then waitWhilePaused() end
                if modeChanged(expectedMode) then return false end
                if not isOpen(part) then return true end
                task.wait(0.1)
                paintWait = paintWait + 0.1
            end
            return not isOpen(part)
        end

        if tick() - lastCheck >= CONFIG.stuckCheckInterval then
            if distanceXZ(hrp.Position, lastPos) < CONFIG.stuckMoveThreshold then
                recoveries = recoveries + 1
                if recoveries > CONFIG.maxStuckRecoveries then
                    log("Gave up on pixel after", recoveries, "recoveries")
                    return false
                end
                attemptUnstick(humanoid, hrp, part.Position)
            end
            lastPos = hrp.Position
            lastCheck = tick()
        end

        task.wait(0.1)
        waited = waited + 0.1
    end
    return false
end

local function paintNumberLegacy(n, activePicture, humanoid, hrp, expectedMode)
    while stillRunning() do
        waitWhilePaused()
        if not stillRunning() then break end
        if modeChanged(expectedMode) then
            log("Mode changed mid-color — switching")
            break
        end

        local remaining = gatherForNumber(activePicture, n, nil)
        if #remaining == 0 then break end

        local nearest, dist = findNearest(remaining, hrp.Position)
        if nearest then
            log(string.format("Walking to N=%s dist=%d", tostring(n), math.floor(dist)))
            if not walkToPixel(nearest, humanoid, hrp, expectedMode) then
                log("Timed out / gave up on a pixel")
            end
        end
    end
end

----------------------------------------------------------------
-- CONTINUOUS MODE
-- One loop paced by Heartbeat.
--   every frame  → cheap "is current target still open?"
--   every retargetInterval → full O(n) rescan for closer pixel
--   MoveTo only when target identity changes
----------------------------------------------------------------

local function paintNumberContinuous(n, activePicture, humanoid, hrp, expectedMode)
    local skipSet = {}          -- parts we gave up on (stuck)
    local target = nil
    local recoveries = 0
    local lastPos = hrp.Position
    local lastStuckCheck = tick()
    local lastRescan = 0
    local lastLog = 0
    local lastRemainCount = -1
    local rescanInterval = CONFIG.retargetInterval or 0.1

    log("Continuous pass start N=" .. tostring(n))

    while stillRunning() do
        ------------------------------------------------------------------
        -- Pause
        ------------------------------------------------------------------
        if getgenv().PaintBotPaused then
            waitWhilePaused()
            if not stillRunning() then return end
            lastPos = hrp.Position
            lastStuckCheck = tick()
            if isOpen(target) then
                humanoid:MoveTo(target.Position)
            end
        end

        if not stillRunning() then return end
        if modeChanged(expectedMode) then
            log("Mode changed mid-color — switching")
            return
        end

        ------------------------------------------------------------------
        -- Decide whether we need a new target
        ------------------------------------------------------------------
        local targetGone = target ~= nil and not isOpen(target)
        local needRescan = (tick() - lastRescan) >= rescanInterval

        if target == nil or targetGone or needRescan then
            lastRescan = tick()

            local remaining = gatherForNumber(activePicture, n, skipSet)

            -- If skipSet emptied the list, clear skips once and retry
            if #remaining == 0 and next(skipSet) then
                local anyLeft = gatherForNumber(activePicture, n, nil)
                if #anyLeft > 0 then
                    skipSet = {}
                    recoveries = 0
                    remaining = anyLeft
                end
            end

            if #remaining == 0 then
                break
            end

            local nearest, dist = findNearest(remaining, hrp.Position)
            if not nearest then
                break
            end

            -- Only re-issue MoveTo when the target object actually changes
            if nearest ~= target then
                target = nearest
                recoveries = 0
                lastPos = hrp.Position
                lastStuckCheck = tick()
                humanoid:MoveTo(target.Position)

                local now = tick()
                if now - lastLog >= 1.5 or #remaining ~= lastRemainCount then
                    log(string.format(
                        "N=%s  dist=%d  remaining=%d",
                        tostring(n), math.floor(dist), #remaining))
                    lastLog = now
                    lastRemainCount = #remaining
                end
            end
        end

        ------------------------------------------------------------------
        -- Stuck recovery
        ------------------------------------------------------------------
        if tick() - lastStuckCheck >= CONFIG.stuckCheckInterval then
            if distanceXZ(hrp.Position, lastPos) < CONFIG.stuckMoveThreshold then
                recoveries = recoveries + 1
                if recoveries > CONFIG.maxStuckRecoveries then
                    log("Skipping stuck pixel N=" .. tostring(n)
                        .. " after " .. recoveries .. " recoveries")
                    if target then
                        skipSet[target] = true
                    end
                    target = nil
                    recoveries = 0
                else
                    local pos = (target and target.Position) or hrp.Position
                    attemptUnstick(humanoid, hrp, pos)
                end
            end
            lastPos = hrp.Position
            lastStuckCheck = tick()
        end

        ------------------------------------------------------------------
        -- Yield to next frame
        ------------------------------------------------------------------
        RunService.Heartbeat:Wait()
    end

    log("Continuous pass done N=" .. tostring(n))
end

----------------------------------------------------------------
-- Main
----------------------------------------------------------------

task.spawn(function()
    local plot = findOwnPlot()
    if not plot then
        warn("[PaintBot] Aborting — no plot found. Set CONFIG.plotOwnerName and retry.")
        getgenv().PaintBotRunning = false
        return
    end

    local activePicture = plot:FindFirstChild("ActivePicture")
    if not activePicture then
        warn("[PaintBot] Plot has no ActivePicture folder")
        getgenv().PaintBotRunning = false
        return
    end

    armCanvasClearing(plot.Parent, plot)

    local humanoid, hrp = getCharacterRefs()
    if not humanoid or not hrp then
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        humanoid = char:WaitForChild("Humanoid")
        hrp = char:WaitForChild("HumanoidRootPart")
    end

    if CONFIG.walkSpeedOverride then
        humanoid.WalkSpeed = CONFIG.walkSpeedOverride
    end

    if CONFIG.showProgressUI then
        createProgressUI()
        task.spawn(function()
            while stillRunning() do
                updateProgressUI(activePicture)
                task.wait(CONFIG.progressUpdateInterval)
            end
            updateProgressUI(activePicture)
        end)
    end

    armSpeedHook()

    log("Starting.")
    if CONFIG.continuousMode then
        log("Continuous mode (rescan every", CONFIG.retargetInterval, "s)")
    else
        log("Legacy mode (arrive + paint-wait)")
    end

    while stillRunning() do
        waitWhilePaused()
        if not stillRunning() then break end

        -- Keep character refs fresh after respawn
        local h, r = getCharacterRefs()
        if h then humanoid = h end
        if r then hrp = r end
        if not humanoid or not hrp then
            task.wait(0.5)
            continue
        end

        local groups = gatherUnpaintedByNumber(activePicture)
        local numbers = {}
        for num in pairs(groups) do
            numbers[#numbers + 1] = num
        end

        if #numbers == 0 then
            log("No unpainted pixels left. Done!")
            break
        end

        local n = pickNextNumber(numbers)
        local workingMode = getgenv().PaintBotDrawMode
        selectNumber(n)

        if CONFIG.continuousMode then
            paintNumberContinuous(n, activePicture, humanoid, hrp, workingMode)
        else
            paintNumberLegacy(n, activePicture, humanoid, hrp, workingMode)
        end
    end

    log("Finished (or stopped).")
    getgenv().PaintBotRunning = false
end)
