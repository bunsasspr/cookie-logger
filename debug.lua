-- ===== Auto Collect (test) =====
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getMyPlotModel()
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

local function getCollectorParts()
    local plot = getMyPlotModel()
    if not plot then
        warn("Could not find your plot")
        return {}
    end

    local collectors = {}
    for _, floor in ipairs(plot:GetChildren()) do
        if floor.Name:match("^Floor%d+$") then
            local holders = floor:FindFirstChild("Holders")
            if holders then
                for _, holder in ipairs(holders:GetChildren()) do
                    local collector = holder:FindFirstChild("Collector")
                    if collector and collector:IsA("BasePart") then
                        table.insert(collectors, collector)
                    end
                end
            end
        end
    end
    return collectors
end

local hrp = getHRP()
local collectors = getCollectorParts()
print(("Found %d collector(s)"):format(#collectors))

for _, collector in ipairs(collectors) do
    pcall(function()
        firetouchinterest(collector, hrp, 0)
    end)
end

task.wait(0.1)

for _, collector in ipairs(collectors) do
    pcall(function()
        firetouchinterest(collector, hrp, 1)
    end)
end

print("Fired touch interest on all collectors — check your cash")
