-- Auto Buy + Return to Plot (dynamic)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")

local DICE_SHOP = CFrame.new(179.709259, 4.53835154, -144.103485, 0.909164608, -2.76407324e-08, -0.41643694, -1.1623088e-09, 1, -6.8911902e-08, 0.41643694, 6.31362909e-08, 0.909164608)
local POTION_SHOP = CFrame.new(153.449585, 4.03330231, -138.129669, 0.814049244, 6.003647e-08, 0.580795884, -6.18439913e-08, 1, -1.66881726e-08, -0.580795884, -2.23337384e-08, 0.814049244)

local enabled = false
local WAIT_AFTER_BUY = 120 -- 2 minutes

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- Dynamically find your current plot
local function getMyPlotCFrame()
    local plotsFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
    if not plotsFolder then return nil end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
            -- Try to get a good standing position
            if plot:IsA("Model") and plot.PrimaryPart then
                return plot.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
            end

            local part = plot:FindFirstChildWhichIsA("BasePart", true)
            if part then
                return part.CFrame + Vector3.new(0, 3, 0)
            end
        end
    end
    return nil
end

local function tryBuy()
    local hrp = getHRP()

    -- Dice Shop
    hrp.CFrame = DICE_SHOP
    task.wait(0.35)
    pcall(function()
        BuyDice:FireServer("BuyBestAvailable")
    end)

    task.wait(0.4)

    -- Potion Shop
    hrp.CFrame = POTION_SHOP
    task.wait(0.35)
    pcall(function()
        BuyPotion:FireServer("BuyBestAvailable")
    end)

    -- Go back to your plot
    local plotCF = getMyPlotCFrame()
    if plotCF then
        hrp.CFrame = plotCF
        print("Returned to plot. Waiting 2 minutes...")
    else
        warn("Could not find your plot!")
    end
end

task.spawn(function()
    while true do
        if enabled then
            tryBuy()
            task.wait(WAIT_AFTER_BUY)
        else
            task.wait(1)
        end
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        print(enabled and "✅ Auto Buy: ON" or "❌ Auto Buy: OFF")
    end
end)

print("Script loaded. Press B to toggle Auto Buy")
