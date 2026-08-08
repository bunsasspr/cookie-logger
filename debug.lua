-- Better Auto Collect (no teleport)
local Players = game:GetService("Players")
local player = Players.LocalPlayer

getgenv().AutoCollect = true

local BETWEEN_HOLDER = 0.12   -- delay between each collector
local FULL_LOOP = 1.8         -- delay after finishing all holders

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

        for i, collector in ipairs(collectors) do
            if not getgenv().AutoCollect then break end

            -- Fire touch multiple times for better reliability
            for _ = 1, 3 do
                pcall(function()
                    firetouchinterest(collector, hrp, 0)
                    task.wait(0.02)
                    firetouchinterest(collector, hrp, 1)
                end)
                task.wait(0.03)
            end

            task.wait(BETWEEN_HOLDER)
        end

        task.wait(FULL_LOOP)
    end
end)

print("✅ Improved Auto Collect started (no teleport)")
