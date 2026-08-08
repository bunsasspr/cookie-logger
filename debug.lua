-- Auto Collect Money (only your own plot)
-- Kawaii Anime RNG

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local CollectDelay = 0.4          -- lower = faster (0.3 ~ 0.6 is usually good)
local UseTeleport = false          -- true = teleport to collector, false = firetouch only

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- Find your own plot
local function getMyPlot()
    local plotsFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
    if not plotsFolder then return nil end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        -- Method 1: Owner attribute / value
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner and (owner == LocalPlayer.Name or owner == LocalPlayer.UserId or tostring(owner) == tostring(LocalPlayer.UserId)) then
            return plot
        end

        -- Method 2: StringValue / ObjectValue named Owner
        local ownerVal = plot:FindFirstChild("Owner") or plot:FindFirstChild("owner") or plot:FindFirstChild("Player")
        if ownerVal then
            if ownerVal:IsA("StringValue") and ownerVal.Value == LocalPlayer.Name then
                return plot
            elseif ownerVal:IsA("ObjectValue") and ownerVal.Value == LocalPlayer then
                return plot
            elseif ownerVal:IsA("IntValue") and ownerVal.Value == LocalPlayer.UserId then
                return plot
            end
        end

        -- Method 3: Plot name contains your name
        if plot.Name:lower():find(LocalPlayer.Name:lower()) then
            return plot
        end
    end

    -- Fallback: closest plot to you (works most of the time)
    local hrp = getHRP()
    if not hrp then return nil end

    local closest, closestDist = nil, math.huge
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local primary = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart")
        if primary then
            local dist = (hrp.Position - primary.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = plot
            end
        end
    end
    return closest
end

local function collectFromPlot(plot)
    if not plot then return end

    local holders = plot:FindFirstChild("Floor1") and plot.Floor1:FindFirstChild("Holders")
    if not holders then return end

    local hrp = getHRP()
    if not hrp then return end

    for _, holder in ipairs(holders:GetChildren()) do
        if holder.Name:match("ItemHolder") then
            local collector = holder:FindFirstChild("Collector")
            if collector and collector:IsA("BasePart") then
                if UseTeleport then
                    -- Teleport right on top of the collector
                    hrp.CFrame = collector.CFrame + Vector3.new(0, 3, 0)
                else
                    -- Fire touch without moving (cleaner)
                    firetouchinterest(hrp, collector, 0)
                    task.wait(0.03)
                    firetouchinterest(hrp, collector, 1)
                end
                task.wait(0.05) -- tiny delay between holders
            end
        end
    end
end

-- Main loop
task.spawn(function()
    while true do
        local myPlot = getMyPlot()
        if myPlot then
            collectFromPlot(myPlot)
        else
            warn("[AutoCollect] Could not find your plot")
        end
        task.wait(CollectDelay)
    end
end)

print("✅ Auto Collect (own plot only) started")
