-- Auto Collect (no remote version)
-- Adjust the filters below until it works for this game

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local CollectDelay = 0.35          -- how fast it loops
local MaxDistance = 80             -- only collect things within this range
local Teleport = true              -- true = teleport to the part, false = just fire touch

local function getHRP()
    Character = LocalPlayer.Character
    if not Character then return nil end
    return Character:FindFirstChild("HumanoidRootPart")
end

local function isCollectable(part)
    if not part:IsA("BasePart") then return false end
    if not part.Parent then return false end

    local name = part.Name:lower()
    -- Add / remove keywords that match the money parts in this game
    if name:find("cash") or name:find("money") or name:find("coin") 
    or name:find("collect") or name:find("bill") or name:find("dollar") then
        return true
    end

    -- Sometimes the collectible is a child of a model
    if part.Parent.Name:lower():find("cash") 
    or part.Parent.Name:lower():find("money") then
        return true
    end

    return false
end

local function tryCollect(part)
    local hrp = getHRP()
    if not hrp then return end

    local distance = (hrp.Position - part.Position).Magnitude
    if distance > MaxDistance then return end

    if Teleport then
        -- Instant teleport (most reliable when no remote)
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    else
        -- Simulate touch without moving (cleaner but sometimes blocked)
        firetouchinterest(hrp, part, 0)
        task.wait(0.05)
        firetouchinterest(hrp, part, 1)
    end
end

-- Main loop
task.spawn(function()
    while true do
        local hrp = getHRP()
        if hrp then
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isCollectable(obj) then
                    pcall(tryCollect, obj)
                end
            end
        end
        task.wait(CollectDelay)
    end
end)

print("Auto Collect started")
