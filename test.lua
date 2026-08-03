--[[
    Paint-by-Number Auto Painter
    -----------------------------
    Finds your own plot's ActivePicture folder, groups unpainted pixels
    (Parts with attribute D == false) by their color number (attribute N),
    fires the SelectNumber remote to pick that color, then walks to each
    matching pixel until it's painted (D flips to true), before moving to
    the next number. Repeats until nothing unpainted is left.

    CONTROLS (run in console):
        PaintBotStop()    -- stops the bot cleanly (cannot be resumed)
        PaintBotPause()   -- pauses in place (can be resumed)
        PaintBotResume()  -- resumes after a pause

    There's also a Start/Stop button on the on-screen progress UI that
    does the same pause/resume toggle as the console functions above.

    CONFIG — check these before running
]]

local CONFIG = {
    -- If auto-detection of your plot fails, set your exact in-game
    -- username here (case-sensitive) and re-run.
    plotOwnerName = nil,

    -- How close (studs, horizontal XZ distance) counts as "arrived" at a pixel
    arriveDistance = 3,

    -- After arriving, how long to wait for the game to auto-paint (D flips
    -- to true) before giving up on this pixel and moving to the next
    paintWaitTimeout = 2,

    -- Delay after firing SelectNumber before starting to walk, to give the
    -- game time to register the color switch
    selectNumberSettleTime = 0.25,

    -- Optional walk speed boost. Set to nil to leave WalkSpeed untouched.
    walkSpeedOverride = nil,

    -- STUCK RECOVERY: how often (seconds) to check whether the character
    -- has actually moved while walking to a pixel
    stuckCheckInterval = 1.0,

    -- If the character has moved less than this many studs since the last
    -- check, it's considered stuck
    stuckMoveThreshold = 1.5,

    -- How many recovery attempts to make on a single pixel before giving
    -- up on it entirely and moving to a different one (it'll be picked up
    -- again on a later pass if still unpainted)
    maxStuckRecoveries = 3,

    -- On-screen progress bar
    showProgressUI = true,
    progressUpdateInterval = 0.5,

    -- Order colors are worked through: "ascending" (1->30), "descending"
    -- (30->1), or "random" (shuffled each pass). Can also be changed live
    -- via the buttons on the progress UI.
    drawMode = "ascending",

    -- Persist settings (currently just drawMode) to a file so they survive
    -- rejoining the game. Requires writefile/readfile/isfile support.
    saveConfig = true,
    configFile = "paintbot_config.json",

    -- Anti-AFK: nudges the game whenever Roblox's own idle detector fires,
    -- so the ~20 minute AFK kick doesn't happen during long runs.
    antiAfk = true,

    -- Print progress as it works
    verbose = true,

    -- Default WalkSpeed to apply to the local player once the bot has
    -- started (applies on spawn/respawn too). Set to nil to disable and
    -- rely solely on walkSpeedOverride above.
    defaultPlayerSpeed = 50,

    -- FPS BOOST: destroy the pixel parts belonging to every other plot's
    -- ActivePicture folder (your own plot is left untouched), and keep
    -- clearing any new ones that stream in as other players draw or join.
    -- Set to false to leave other canvases alone.
    hideOtherCanvases = true,
}

----------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local SelectNumberEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SelectNumber")

local function log(...)
    if CONFIG.verbose then
        print("[PaintBot]", ...)
    end
end

-- Stop switch
if getgenv().PaintBotRunning then
    getgenv().PaintBotRunning = false
    task.wait(0.3)
end
getgenv().PaintBotRunning = true
getgenv().PaintBotPaused = false

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

-- Sleeps in short increments while paused, returns early if the bot is
-- stopped entirely so callers can bail out of their own loops.
local function waitWhilePaused()
    while getgenv().PaintBotRunning and getgenv().PaintBotPaused do
        task.wait(0.15)
    end
end

local function findOwnPlot()
    local plotModels = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("PlotModels")
    if not plotModels then
        warn("[PaintBot] Could not find Workspace.Map.PlotModels")
        return nil
    end

    -- 1) Try exact name match (config override or player's own name)
    local tryName = CONFIG.plotOwnerName or LocalPlayer.Name
    local plot = plotModels:FindFirstChild(tryName)
    if plot and plot:FindFirstChild("ActivePicture") then
        log("Found plot by name match:", plot.Name)
        return plot
    end

    -- 2) Fallback: closest plot to the player's character
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        warn("[PaintBot] No character/HumanoidRootPart to use for fallback plot detection")
        return nil
    end

    local best, bestDist = nil, math.huge
    for _, candidate in ipairs(plotModels:GetChildren()) do
        local ap = candidate:FindFirstChild("ActivePicture")
        if ap then
            local base = candidate:FindFirstChild("PersistentParts")
            local refPart = (base and base:FindFirstChild("Base")) or ap:FindFirstChildWhichIsA("Part")
            if refPart then
                local d = (refPart.Position - hrp.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = candidate
                end
            end
        end
    end

    if best then
        log("Found plot by proximity fallback:", best.Name, "(distance:", math.floor(bestDist), "studs)")
    else
        warn("[PaintBot] Could not find any plot with an ActivePicture folder")
    end
    return best
end

local function gatherUnpaintedByNumber(activePicture)
    local groups = {}
    for _, part in ipairs(activePicture:GetChildren()) do
        if part:IsA("BasePart") then
            local done = part:GetAttribute("D")
            local n = part:GetAttribute("N")
            if done == false and n ~= nil then
                groups[n] = groups[n] or {}
                table.insert(groups[n], part)
            end
        end
    end
    return groups
end

local function selectNumber(n)
    local okFire, errFire = pcall(function()
        SelectNumberEvent:FireServer(n)
    end)
    if not okFire then
        warn("[PaintBot] Failed to fire SelectNumber:", errFire)
    end
    log("Selected number", n)
    task.wait(CONFIG.selectNumberSettleTime)
end

local function distanceXZ(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- Config save/load (persists drawMode across game rejoins)
local function loadConfig()
    if not CONFIG.saveConfig then return end

    print("[PaintBot][Config] Checking for", CONFIG.configFile)

    local okCheck, exists = pcall(function() return isfile and isfile(CONFIG.configFile) end)
    if not okCheck then
        warn("[PaintBot][Config] isfile() check errored:", exists)
        return
    end
    if not exists then
        print("[PaintBot][Config] No saved config file found (isfile returned false/nil). Using defaults.")
        return
    end

    local okRead, content = pcall(function() return readfile(CONFIG.configFile) end)
    if not okRead then
        warn("[PaintBot][Config] readfile() failed:", content)
        return
    end
    print("[PaintBot][Config] Raw file content:", tostring(content))

    local okDecode, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not okDecode then
        warn("[PaintBot][Config] JSONDecode failed:", data)
        return
    end
    if type(data) ~= "table" or not data.drawMode then
        warn("[PaintBot][Config] Decoded data missing drawMode:", tostring(data))
        return
    end

    getgenv().PaintBotDrawMode = data.drawMode
    print("[PaintBot][Config] Loaded saved drawMode =", data.drawMode)
end

local function saveConfigToFile()
    if not CONFIG.saveConfig then return end
    local data = { drawMode = getgenv().PaintBotDrawMode }
    local okEncode, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not okEncode then
        warn("[PaintBot][Config] JSONEncode failed:", json)
        return
    end
    local okWrite, errWrite = pcall(function() writefile(CONFIG.configFile, json) end)
    if okWrite then
        print("[PaintBot][Config] Saved:", json)
    else
        warn("[PaintBot][Config] writefile() failed:", errWrite)
    end
end

-- Anti-AFK: fires whenever Roblox detects no input for a while, simulating
-- a harmless click to reset its internal idle timer
local function setupAntiAfk()
    if not CONFIG.antiAfk then return end
    LocalPlayer.Idled:Connect(function()
        log("Anti-AFK: nudging to prevent idle kick")
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end
setupAntiAfk()

-- Live-adjustable draw mode (buttons on the UI can change this mid-run)
getgenv().PaintBotDrawMode = CONFIG.drawMode
loadConfig()

-- Default speed hookup. This only starts watching for character spawns
-- once armSpeedHook() is called (done from task.spawn below, right after
-- the main bot confirms it has a plot and is starting), so it doesn't do
-- anything before the bot itself is actually running.
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
    log("Default speed hook armed (WalkSpeed =", CONFIG.defaultPlayerSpeed, ")")
end

-- FPS boost: destroys the pixel parts under an ActivePicture folder and
-- keeps destroying any new ones added afterward (covers pixels that
-- stream in as the other player draws, or a repainted/refreshed picture).
local function watchAndClearCanvas(activePicture)
    for _, part in ipairs(activePicture:GetChildren()) do
        part:Destroy()
    end
    activePicture.ChildAdded:Connect(function(part)
        part:Destroy()
    end)
end

-- Clears every other plot's canvas (never touches ownPlot), and keeps
-- watching for plots that load in later (e.g. a player joining after us).
local function clearOtherCanvases(plotModels, ownPlot)
    if not CONFIG.hideOtherCanvases then return end

    local watched = 0
    for _, candidate in ipairs(plotModels:GetChildren()) do
        if candidate ~= ownPlot then
            local ap = candidate:FindFirstChild("ActivePicture")
            if ap then
                watchAndClearCanvas(ap)
                watched = watched + 1
            end
        end
    end

    plotModels.ChildAdded:Connect(function(candidate)
        if candidate == ownPlot then return end
        task.spawn(function()
            local ap = candidate:WaitForChild("ActivePicture", 10)
            if ap then
                watchAndClearCanvas(ap)
            end
        end)
    end)

    log("Clearing other players' canvases (", watched, "plots on start) to reduce lag")
end

local function pickNextNumber(numbers)
    local mode = getgenv().PaintBotDrawMode or "ascending"
    if mode == "descending" then
        local best = numbers[1]
        for _, n in ipairs(numbers) do
            if n > best then best = n end
        end
        return best
    elseif mode == "random" then
        return numbers[math.random(#numbers)]
    else
        local best = numbers[1]
        for _, n in ipairs(numbers) do
            if n < best then best = n end
        end
        return best
    end
end

local ProgressLabel, ProgressBarFill, ControlButton

local function refreshControlButton()
    if not ControlButton then return end
    if getgenv().PaintBotPaused then
        ControlButton.Text = "▶ Start"
        ControlButton.BackgroundColor3 = Color3.fromRGB(0, 255, 140)
        ControlButton.BackgroundTransparency = 0.3
    else
        ControlButton.Text = "⏹ Stop"
        ControlButton.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
        ControlButton.BackgroundTransparency = 0.3
    end
end

local function createProgressUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PaintBotProgressUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 220, 0, 102)
    frame.Position = UDim2.new(0.5, -110, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.25
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    ProgressLabel = Instance.new("TextLabel")
    ProgressLabel.Size = UDim2.new(1, 0, 0, 18)
    ProgressLabel.Position = UDim2.new(0, 0, 0, 2)
    ProgressLabel.BackgroundTransparency = 1
    ProgressLabel.TextColor3 = Color3.new(1, 1, 1)
    ProgressLabel.Font = Enum.Font.GothamBold
    ProgressLabel.TextSize = 13
    ProgressLabel.Text = "PaintBot: 0% (0/0)"
    ProgressLabel.Parent = frame

    local barBG = Instance.new("Frame")
    barBG.Size = UDim2.new(0.9, 0, 0, 12)
    barBG.Position = UDim2.new(0.05, 0, 0, 26)
    barBG.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    barBG.Parent = frame
    Instance.new("UICorner", barBG).CornerRadius = UDim.new(0, 6)

    ProgressBarFill = Instance.new("Frame")
    ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
    ProgressBarFill.BackgroundColor3 = Color3.fromRGB(0, 255, 140)
    ProgressBarFill.Parent = barBG
    Instance.new("UICorner", ProgressBarFill).CornerRadius = UDim.new(0, 6)

    -- Draw mode buttons
    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(0.9, 0, 0, 22)
    modeRow.Position = UDim2.new(0.05, 0, 0, 44)
    modeRow.BackgroundTransparency = 1
    modeRow.Parent = frame

    local modeButtons = {}
    local function setActiveMode(mode)
        getgenv().PaintBotDrawMode = mode
        saveConfigToFile()
        for m, btn in pairs(modeButtons) do
            btn.BackgroundColor3 = (m == mode) and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(60, 60, 60)
            btn.BackgroundTransparency = (m == mode) and 0.3 or 0.6
        end
    end

    local modes = {"ascending", "descending", "random"}
    local labels = {ascending = "Asc", descending = "Desc", random = "Random"}
    for i, mode in ipairs(modes) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1/3, -4, 1, 0)
        btn.Position = UDim2.new((i - 1) / 3, 2, 0, 0)
        btn.Text = labels[mode]
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        btn.BackgroundTransparency = 0.6
        btn.Parent = modeRow
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        modeButtons[mode] = btn
        btn.MouseButton1Click:Connect(function()
            setActiveMode(mode)
        end)
    end

    setActiveMode(getgenv().PaintBotDrawMode or "ascending")

    -- Start/Stop (pause/resume) button
    ControlButton = Instance.new("TextButton")
    ControlButton.Size = UDim2.new(0.9, 0, 0, 22)
    ControlButton.Position = UDim2.new(0.05, 0, 0, 72)
    ControlButton.Font = Enum.Font.GothamBold
    ControlButton.TextSize = 12
    ControlButton.TextColor3 = Color3.new(1, 1, 1)
    ControlButton.Parent = frame
    Instance.new("UICorner", ControlButton).CornerRadius = UDim.new(0, 4)

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
    local statusSuffix = getgenv().PaintBotPaused and " [Paused]" or ""
    ProgressLabel.Text = string.format("PaintBot: %d%% (%d/%d)%s", pct, done, total, statusSuffix)
    ProgressBarFill.Size = UDim2.new(pct / 100, 0, 1, 0)
    refreshControlButton()
end

local function attemptUnstick(humanoid, hrp, targetPos)
    log("Stuck detected, attempting recovery...")
    -- Jump in place first, sometimes enough to pop free of geometry
    humanoid.Jump = true
    task.wait(0.2)

    -- Nudge toward a small random offset near current position to break
    -- out of a bad pathing lock, then re-issue the real move
    local nudge = hrp.Position + Vector3.new(
        (math.random() - 0.5) * 6,
        0,
        (math.random() - 0.5) * 6
    )
    humanoid:MoveTo(nudge)
    task.wait(0.5)

    humanoid:MoveTo(targetPos)
end

local function walkToPixel(part, humanoid, hrp, expectedMode)
    humanoid:MoveTo(part.Position)
    local waited = 0

    local lastCheckPos = hrp.Position
    local lastCheckTime = tick()
    local stuckRecoveries = 0

    while getgenv().PaintBotRunning do
        if getgenv().PaintBotPaused then
            -- Hold position while paused; don't count this time against
            -- the walk timeout or the stuck-recovery clock.
            waitWhilePaused()
            if not getgenv().PaintBotRunning then
                return false
            end
            humanoid:MoveTo(part.Position)
            lastCheckPos = hrp.Position
            lastCheckTime = tick()
            continue
        end
        if expectedMode and getgenv().PaintBotDrawMode ~= expectedMode then
            return false -- mode changed mid-walk, abandon this pixel immediately
        end
        if waited >= 10 then
            return false
        end
        if not part or not part.Parent then
            return true -- disappeared/painted and cleaned up
        end
        if part:GetAttribute("D") == true then
            return true
        end
        if distanceXZ(hrp.Position, part.Position) <= CONFIG.arriveDistance then
            -- arrived, give the game a moment to auto-paint
            local paintWaited = 0
            while getgenv().PaintBotRunning and paintWaited < CONFIG.paintWaitTimeout do
                if getgenv().PaintBotPaused then
                    waitWhilePaused()
                end
                if expectedMode and getgenv().PaintBotDrawMode ~= expectedMode then
                    return false
                end
                if not part.Parent or part:GetAttribute("D") == true then
                    return true
                end
                task.wait(0.1)
                paintWaited = paintWaited + 0.1
            end
            return part.Parent == nil or part:GetAttribute("D") == true
        end

        -- Stuck check: has the character actually moved recently?
        if tick() - lastCheckTime >= CONFIG.stuckCheckInterval then
            local moved = distanceXZ(hrp.Position, lastCheckPos)
            if moved < CONFIG.stuckMoveThreshold then
                stuckRecoveries = stuckRecoveries + 1
                if stuckRecoveries > CONFIG.maxStuckRecoveries then
                    log("Gave up on this pixel after", stuckRecoveries, "stuck recoveries")
                    return false
                end
                attemptUnstick(humanoid, hrp, part.Position)
            end
            lastCheckPos = hrp.Position
            lastCheckTime = tick()
        end

        task.wait(0.1)
        waited = waited + 0.1
    end
    return false
end

task.spawn(function()
    local plot = findOwnPlot()
    if not plot then
        warn("[PaintBot] Aborting - no plot found. Set CONFIG.plotOwnerName manually and retry.")
        getgenv().PaintBotRunning = false
        return
    end

    local activePicture = plot:FindFirstChild("ActivePicture")
    if not activePicture then
        warn("[PaintBot] Plot has no ActivePicture folder")
        getgenv().PaintBotRunning = false
        return
    end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:WaitForChild("HumanoidRootPart")

    if CONFIG.walkSpeedOverride then
        humanoid.WalkSpeed = CONFIG.walkSpeedOverride
    end

    if CONFIG.showProgressUI then
        createProgressUI()
        task.spawn(function()
            while getgenv().PaintBotRunning do
                updateProgressUI(activePicture)
                task.wait(CONFIG.progressUpdateInterval)
            end
            -- final update so it shows 100% / final state before stopping
            updateProgressUI(activePicture)
        end)
    end

    armSpeedHook()

    log("Starting. Scanning for unpainted pixels...")

    while getgenv().PaintBotRunning do
        waitWhilePaused()
        if not getgenv().PaintBotRunning then
            break
        end

        local groups = gatherUnpaintedByNumber(activePicture)

        local numbers = {}
        for n, _ in pairs(groups) do
            table.insert(numbers, n)
        end

        if #numbers == 0 then
            log("No unpainted pixels found. Picture appears complete!")
            break
        end

        local n = pickNextNumber(numbers)
        local workingMode = getgenv().PaintBotDrawMode
        selectNumber(n)

        -- Keep working this number until no unpainted pixels with it remain,
        -- OR until the draw mode changes (then abandon and re-pick immediately)
        while getgenv().PaintBotRunning do
            waitWhilePaused()
            if not getgenv().PaintBotRunning then
                break
            end

            if getgenv().PaintBotDrawMode ~= workingMode then
                log("Mode changed mid-color -- switching immediately")
                break
            end

            -- re-scan live so we pick up pixels painted by chance and skip stale ones
            local remaining = {}
            for _, part in ipairs(activePicture:GetChildren()) do
                if part:IsA("BasePart") and part:GetAttribute("N") == n and part:GetAttribute("D") == false then
                    table.insert(remaining, part)
                end
            end

            if #remaining == 0 then
                break
            end

            -- pick nearest remaining pixel for this number
            local nearest, nearestDist = nil, math.huge
            for _, part in ipairs(remaining) do
                local d = distanceXZ(hrp.Position, part.Position)
                if d < nearestDist then
                    nearestDist = d
                    nearest = part
                end
            end

            if nearest then
                log("Walking to pixel N=" .. tostring(n) .. " at distance " .. math.floor(nearestDist))
                local success = walkToPixel(nearest, humanoid, hrp, workingMode)
                if not success then
                    log("Timed out / gave up on a pixel, moving on")
                end
            end
        end
    end

    log("Finished (or stopped).")
    getgenv().PaintBotRunning = false
end)
