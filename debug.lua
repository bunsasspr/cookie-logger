-- Improved Auto Collect (no teleport)
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local DELAY_BETWEEN_HOLDERS = 0.08   -- small delay between each collector
local LOOP_DELAY = 1.2               -- full cycle delay

getgenv().AutoCollect = true

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getMyPlot()
    local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
            return plot
        end
    end
    return nil
end

local function getCollectors()
    local plot = getMyPlot()
    if not plot then return {} end

    local list = {}
    for _, floor in ipairs(plot:GetChildren()) do
        if floor.Name:match("^Floor%d+$") then
            local holders = floor:FindFirstChild("Holders")
            if holders then
                for _, holder in ipairs(holders:GetChildren()) do
                    local collector = holder:FindFirstChild("Collector")
                    if collector and collector:IsA("BasePart") then
                        table.insert(list, collector)
                    end
                end
            end
        end
    end
    return list
end

task.spawn(function()
    while getgenv().AutoCollect do
        local hrp = getHRP()
        local collectors = getCollectors()

        for _, collector in ipairs(collectors) do
            if not getgenv().AutoCollect then break end
            pcall(function()
                firetouchinterest(collector, hrp, 0)
                task.wait(0.03)
                firetouchinterest(collector, hrp, 1)
            end)
            task.wait(DELAY_BETWEEN_HOLDERS)
        end

        task.wait(LOOP_DELAY)
    end
end)

print("✅ Improved Auto Collect (no teleport) started")
