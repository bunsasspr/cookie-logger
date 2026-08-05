-- ===== Auto Buy + Use Potions + EquipBest + Return to Plot + Auto Sell =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")
local EquipBest = remotes:WaitForChild("EquipBest")
local UsePotion = remotes:WaitForChild("UsePotion")
local Dialogue = remotes:WaitForChild("Dialogue")

-- Shop / sell positions
local DICE_SHOP = CFrame.new(179.709259, 4.53835154, -144.103485, 0.909164608, -2.76407324e-08, -0.41643694, -1.1623088e-09, 1, -6.8911902e-08, 0.41643694, 6.31362909e-08, 0.909164608)
local POTION_SHOP = CFrame.new(153.449585, 4.03330231, -138.129669, 0.814049244, 6.003647e-08, 0.580795884, -6.18439913e-08, 1, -1.66881726e-08, -0.580795884, -2.23337384e-08, 0.814049244)
local SELL_CFRAME = CFrame.new(185.339233, 3.67208314, -117.684746, 0.0844980627, 5.13176062e-08, -0.996423662, -1.29543869e-08, 1, 5.04032442e-08, 0.996423662, 8.64908056e-09, 0.0844980627)

local enabled = false
local WAIT_AFTER_BUY = 120 -- 2 minutes
local SELL_THRESHOLD = 30
local SELL_CHECK_INTERVAL = 5 -- seconds

-- Potion list (cleaner format)
local potions = {
    -- Cash
    {Name = "Cash I", Arg = "Max"},
    {Name = "Cash II", Arg = "Max"},
    {Name = "Cash III", Arg = "Max"},
    {Name = "Godly Cash", Arg = "Max"},

    -- Luck
    {Name = "Luck I", Arg = "Max"},
    {Name = "Luck II", Arg = "Max"},
    {Name = "Luck III", Arg = "Max"},
    {Name = "Godly Luck", Arg = "Max"},

    -- Egg Luck
    {Name = "Egg Luck I", Arg = "Max"},
    {Name = "Egg Luck II", Arg = "Max"},
    {Name = "Godly Egg Luck", Arg = "Max"},

    -- Mutation
    {Name = "Mutation I", Arg = "Max"},
    {Name = "Mutation II", Arg = "Max"},
    {Name = "Mutation III", Arg = "Max"},
    {Name = "Godly Mutation", Arg = "Max"},

    -- Dice Consumption
    {Name = "Dice Consumption I", Arg = "Max"},
    {Name = "Dice Consumption II", Arg = "Max"},
    {Name = "Godly Dice Consumption", Arg = "Max"},

    -- Others
    {Name = "Rainbow Godly", Arg = "Max"},
    {Name = "Rainbow Potion", Arg = "Max"},
}

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getMyPlotCFrame()
    local plotsFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
    if not plotsFolder then return nil end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
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

local function useAllPotions()
    for _, potion in ipairs(potions) do
        pcall(function()
            UsePotion:FireServer("Use", potion.Name, potion.Arg)
        end)
        task.wait(0.12)
    end
    print("Used all potions")
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

    -- Return to plot
    local plotCF = getMyPlotCFrame()
    if plotCF then
        hrp.CFrame = plotCF
        print("Returned to plot")
    else
        warn("Could not find your plot!")
    end

    -- Use all potions after returning
    task.wait(0.5)
    useAllPotions()
end

-- ===== Auto Sell =====
local function getInventoryCount()
    local counter = player.PlayerGui.Main.Canvas.Inventory.MainFrame:FindFirstChild("Counter")
    if counter and counter:IsA("TextLabel") then
        local current = counter.Text:match("(%d+)/")
        return tonumber(current) or 0
    end
    return 0
end

local function sellInventory()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = SELL_CFRAME
    task.wait(0.4)
    -- Preview first
    pcall(function()
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview")
    end)
    task.wait(1.5) -- small delay between preview and commit
    -- Then commit
    pcall(function()
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit")
    end)
    print("Sold inventory")
end

-- ===== Main buy/potion/equip loop =====
task.spawn(function()
    while true do
        if enabled then
            tryBuy()

            -- Wait 2 minutes while firing EquipBest every 5 seconds
            local waited = 0
            while waited < WAIT_AFTER_BUY and enabled do
                pcall(function()
                    EquipBest:FireServer()
                end)
                task.wait(5)
                waited += 5
            end
        else
            task.wait(1)
        end
    end
end)

-- ===== Auto sell loop (runs independently, checks inventory count) =====
task.spawn(function()
    while true do
        if enabled then
            local count = getInventoryCount()
            if count >= SELL_THRESHOLD then
                print("Inventory is", count, "→ Selling...")
                sellInventory()
                task.wait(3)
            end
        end
        task.wait(SELL_CHECK_INTERVAL)
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        print(enabled and "✅ Auto Farm: ON" or "❌ Auto Farm: OFF")
    end
end)

print("Full script loaded. Press B to toggle Auto Farm (buy + potions + equip + sell)")
