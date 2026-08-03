--[[
    Clear Other Canvases (standalone debug version)
    -------------------------------------------------
    Repeatedly finds every plot under Workspace.Map.PlotModels other than
    your own, and destroys every part inside its ActivePicture folder.
    Runs on a loop (not just once) and prints diagnostics, since a single
    pass can miss plots/pixels that stream in a moment after you join.

    Run this on its own to test/debug. If it still doesn't clear your
    neighbor's canvas, read the printed output -- it'll tell you exactly
    what it found (or didn't).

    CONTROLS:
        ClearCanvasesStop()   -- stops the loop
]]

local CONFIG = {
    plotOwnerName = nil,       -- set your exact username here if auto-detect fails
    scanInterval = 1.0,        -- how often (seconds) to re-scan and destroy new pixels
    maxScans = 60,             -- stop after this many scans (nil = run forever)
}

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if getgenv().ClearCanvasesRunning then
    getgenv().ClearCanvasesRunning = false
    task.wait(0.3)
end
getgenv().ClearCanvasesRunning = true
getgenv().ClearCanvasesStop = function()
    getgenv().ClearCanvasesRunning = false
    print("[ClearCanvases] Stop requested.")
end

local function findPlotModels()
    local map = workspace:FindFirstChild("Map")
    if not map then
        warn("[ClearCanvases] Workspace.Map not found -- is the folder named something else?")
        return nil
    end
    local plotModels = map:FindFirstChild("PlotModels")
    if not plotModels then
        warn("[ClearCanvases] Workspace.Map.PlotModels not found -- listing Map's children instead:")
        for _, child in ipairs(map:GetChildren()) do
            print("  -", child.Name, child.ClassName)
        end
        return nil
    end
    return plotModels
end

local function findOwnPlot(plotModels)
    local tryName = CONFIG.plotOwnerName or LocalPlayer.Name
    local plot = plotModels:FindFirstChild(tryName)
    if plot then
        print("[ClearCanvases] Own plot matched by name:", plot.Name)
        return plot
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        warn("[ClearCanvases] No character yet -- can't fall back to proximity match")
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
        print("[ClearCanvases] Own plot matched by proximity:", best.Name, "(", math.floor(bestDist), "studs)")
    else
        warn("[ClearCanvases] Could not determine own plot -- set CONFIG.plotOwnerName manually")
    end
    return best
end

-- Destroys everything currently inside an ActivePicture folder.
-- Returns how many parts it destroyed, for diagnostics.
local function clearActivePicture(ap)
    local count = 0
    for _, part in ipairs(ap:GetChildren()) do
        local ok, err = pcall(function() part:Destroy() end)
        if ok then
            count = count + 1
        else
            warn("[ClearCanvases] Failed to destroy a part:", err)
        end
    end
    return count
end

local function scanOnce(plotModels, ownPlot)
    local plotsSeen, plotsWithCanvas, totalDestroyed = 0, 0, 0

    for _, candidate in ipairs(plotModels:GetChildren()) do
        plotsSeen = plotsSeen + 1
        if candidate ~= ownPlot then
            local ap = candidate:FindFirstChild("ActivePicture")
            if ap then
                plotsWithCanvas = plotsWithCanvas + 1
                local before = #ap:GetChildren()
                local destroyed = clearActivePicture(ap)
                totalDestroyed = totalDestroyed + destroyed
                if before > 0 then
                    print(string.format("[ClearCanvases] %s: destroyed %d/%d pixels",
                        candidate.Name, destroyed, before))
                end
            else
                -- Only worth logging once in a while, not every scan
                -- print("[ClearCanvases]", candidate.Name, "has no ActivePicture (yet?)")
            end
        end
    end

    return plotsSeen, plotsWithCanvas, totalDestroyed
end

task.spawn(function()
    local plotModels = findPlotModels()
    if not plotModels then
        getgenv().ClearCanvasesRunning = false
        return
    end

    -- Character may not exist yet if this is run very early
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end

    local ownPlot = findOwnPlot(plotModels)
    if not ownPlot then
        warn("[ClearCanvases] Proceeding without a confirmed own plot -- ALL plots will be targeted. " ..
             "Set CONFIG.plotOwnerName if this clears your own canvas too!")
    end

    print("[ClearCanvases] Starting scan loop. Interval:", CONFIG.scanInterval, "Max scans:", CONFIG.maxScans or "infinite")

    local scans = 0
    while getgenv().ClearCanvasesRunning do
        scans = scans + 1
        local plotsSeen, plotsWithCanvas, totalDestroyed = scanOnce(plotModels, ownPlot)

        if scans == 1 then
            print(string.format("[ClearCanvases] Scan #1: saw %d plot(s), %d with an ActivePicture, destroyed %d pixel(s)",
                plotsSeen, plotsWithCanvas, totalDestroyed))
            if plotsSeen <= 1 then
                warn("[ClearCanvases] Only found your own plot (or none). If your neighbor's plot hasn't streamed in yet, " ..
                     "try increasing scanInterval/maxScans, or walk closer to them first.")
            end
        end

        if CONFIG.maxScans and scans >= CONFIG.maxScans then
            print("[ClearCanvases] Reached maxScans, stopping. Re-run the script if needed.")
            break
        end

        task.wait(CONFIG.scanInterval)
    end

    getgenv().ClearCanvasesRunning = false
    print("[ClearCanvases] Finished (or stopped).")
end)
