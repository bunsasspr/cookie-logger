-- ============================================================
--  AUTO COLLECT MONEY — Standalone v2
--  Teleports to the Collector, fires the touch, teleports back
--  Works because the server checks character position
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer

-- ===== Anti AFK =====
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ===== Config =====
local COLLECT_INTERVAL = 2.0   -- seconds between collect attempts
local TOUCH_DURATION = 0.3     -- how long to "touch" the collector

-- ===== Find your plot =====
local function getMyPlot()
    local plotsFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
            return plot
        end
    end
    return nil
end

-- ===== Find the Collector part (exact path from game dump) =====
local function getCollectorPart()
    local plot = getMyPlot()
    if not plot then return nil end

    -- Exact path: plot.Floor1.Holders.ItemHolder1.Collector
    local floor1 = plot:FindFirstChild("Floor1")
    if floor1 then
        local holders = floor1:FindFirstChild("Holders")
        if holders then
            local itemHolder = holders:FindFirstChild("ItemHolder1")
            if itemHolder then
                local collector = itemHolder:FindFirstChild("Collector")
                if collector and collector:IsA("BasePart") then
                    return collector
                end
            end
        end
    end

    -- Fallback: search whole plot for a part named Collector
    for _, part in ipairs(plot:GetDescendants()) do
        if part:IsA("BasePart") and part.Name == "Collector" then
            return part
        end
    end

    -- Last resort: any part with TouchTransmitter
    for _, part in ipairs(plot:GetDescendants()) do
        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
            return part
        end
    end

    return nil
end

-- ===== Teleport to collector, fire touch, teleport back =====
local function collectMoney()
    local collector = getCollectorPart()
    if not collector then return false end

    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- Save current position
    local originalCF = hrp.CFrame

    -- Teleport to the collector
    hrp.CFrame = collector.CFrame * CFrame.new(0, 2, 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    task.wait(0.1)

    -- Fire the touch event
    local ok = pcall(function()
        firetouchinterest(collector, hrp, 0)  -- touch start
        task.wait(TOUCH_DURATION)
        firetouchinterest(collector, hrp, 1)  -- touch end
    end)

    -- Teleport back
    task.wait(0.1)
    hrp.CFrame = originalCF
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    return ok
end

-- ===== Main loop =====
task.spawn(function()
    while true do
        local ok = pcall(collectMoney)
        if not ok then
            -- collector not found yet, keep trying
        end
        task.wait(COLLECT_INTERVAL)
    end
end)

print("✅ Auto Collect v2 loaded! Teleporting to collector every " .. COLLECT_INTERVAL .. "s")
