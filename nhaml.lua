-- Auto Buy Dice + Potion Shops
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")

-- Shop positions you gave me
local DICE_SHOP = CFrame.new(179.709259, 4.53835154, -144.103485, 0.909164608, -2.76407324e-08, -0.41643694, -1.1623088e-09, 1, -6.8911902e-08, 0.41643694, 6.31362909e-08, 0.909164608)
local POTION_SHOP = CFrame.new(153.449585, 4.03330231, -138.129669, 0.814049244, 6.003647e-08, 0.580795884, -6.18439913e-08, 1, -1.66881726e-08, -0.580795884, -2.23337384e-08, 0.814049244)

local enabled = false
local delayBetweenShops = 0.4   -- time between teleporting to each shop
local loopDelay = 3             -- how often the whole cycle repeats (seconds)

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function tryBuy()
    local hrp = getHRP()

    -- Dice shop
    hrp.CFrame = DICE_SHOP
    task.wait(0.25)
    pcall(function()
        BuyDice:FireServer() -- add arguments here if needed
    end)

    task.wait(delayBetweenShops)

    -- Potion shop
    hrp.CFrame = POTION_SHOP
    task.wait(0.25)
    pcall(function()
        BuyPotion:FireServer() -- add arguments here if needed
    end)
end

-- Main loop
task.spawn(function()
    while true do
        if enabled then
            tryBuy()
        end
        task.wait(loopDelay)
    end
end)

-- Toggle with key "B"
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        print(enabled and "Auto Buy: ON" or "Auto Buy: OFF")
    end
end)

print("Script loaded. Press B to toggle Auto Buy")
