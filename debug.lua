-- ============================================================
--  AUTO COLLECT MONEY — Standalone
--  Triggers the plot's money collector from anywhere
--  Uses firetouchinterest() to fire the Touched event
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
local COLLECT_INTERVAL = 1.5  -- seconds between collect attempts
local TOUCH_DURATION = 0.3    -- how long to "touch" the collector

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

-- ===== Find the collector part (the money button you step on) =====
local function getCollectorPart()
    local plot = getMyPlot()
    if not plot then return nil end

    -- Search for any part with a TouchInterest (the "step on" collector)
    for _, part in ipairs(plot:GetDescendants()) do
        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
            -- Prefer parts named Collector/Collect/Button/Money
            local name = part.Name:lower()
            if name:find("collect") or name:find("money") or name:find("button") or name:find("cash") then
                return part
            end
        end
    end

    -- Fallback: any part with TouchTransmitter on the plot
    for _, part in ipairs(plot:GetDescendants()) do
        if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
            return part
        end
    end

    -- Last resort: check ItemHolder1 specifically
    local floor1 = plot:FindFirstChild("Floor1")
    if floor1 then
        local holders = floor1:FindFirstChild("Holders")
        if holders then
            local itemHolder = holders:FindFirstChild("ItemHolder1")
            if itemHolder then
                for _, part in ipairs(itemHolder:GetDescendants()) do
                    if part:IsA("BasePart") and part:FindFirstChildOfClass("TouchTransmitter") then
                        return part
                    end
                end
            end
        end
    end

    return nil
end

-- ===== Fire the touch event from anywhere =====
local function collectMoney()
    local collector = getCollectorPart()
    if not collector then return false end

    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- firetouchinterest triggers the Touched event without being there
    local ok = pcall(function()
        firetouchinterest(collector, hrp, 0)  -- 0 = touch start
        task.wait(TOUCH_DURATION)
        firetouchinterest(collector, hrp, 1)  -- 1 = touch end
    end)

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

print("✅ Auto Collect loaded! Collecting money every " .. COLLECT_INTERVAL .. "s")
