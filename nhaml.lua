-- ===== Auto Dice + Auto Potion (separate restock timers) + EquipBest + Auto Sell + Auto Rebirth =====
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
local RebirthRemote = remotes:WaitForChild("Rebirth")

-- Shop / sell positions
local DICE_SHOP = CFrame.new(179.709259, 4.53835154, -144.103485, 0.909164608, -2.76407324e-08, -0.41643694, -1.1623088e-09, 1, -6.8911902e-08, 0.41643694, 6.31362909e-08, 0.909164608)
local POTION_SHOP = CFrame.new(153.449585, 4.03330231, -138.129669, 0.814049244, 6.003647e-08, 0.580795884, -6.18439913e-08, 1, -1.66881726e-08, -0.580795884, -2.23337384e-08, 0.814049244)
local SELL_CFRAME = CFrame.new(185.339233, 3.67208314, -117.684746, 0.0844980627, 5.13176062e-08, -0.996423662, -1.29543869e-08, 1, 5.04032442e-08, 0.996423662, 8.64908056e-09, 0.0844980627)

local enabled = false
local WAIT_AFTER_BUY = 120 -- fallback if a timer label can't be read
local RESTOCK_BUFFER = 2 -- extra seconds after "0:00" to make sure server has actually restocked
local SELL_THRESHOLD = 30
local SELL_CHECK_INTERVAL = 5 -- seconds
local EQUIP_INTERVAL = 5 -- seconds
local REBIRTH_CHECK_INTERVAL = 2 -- seconds
local REBIRTH_COOLDOWN = 5 -- seconds, let GUI/state settle after rebirthing

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

-- ===== Movement lock =====
-- Dice/potion/sell/rebirth all teleport the character. Only one action may move
-- the player at a time, or loops will fight over CFrame and break each other.
local actionLock = false
local function withLock(fn)
    while actionLock do
        task.wait(0.2)
    end
    actionLock = true
    local ok, err = pcall(fn)
    actionLock = false
    if not ok then
        warn("[AutoFarm] Action error: " .. tostring(err))
    end
end

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

local function returnToPlot(hrp)
    local plotCF = getMyPlotCFrame()
    if plotCF then
        hrp.CFrame = plotCF
    else
        warn("Could not find your plot!")
    end
end

-- shopName: "Main" (dice shop) or "Potion"
local function getRestockSeconds(shopName)
    local ok, label = pcall(function()
        return player.PlayerGui.Main.Canvas.MapShops[shopName].Holder.Timer.TextLabel
    end)
    if not ok or not label then return nil end

    local min, sec = label.Text:match("(%d+):(%d+)")
    if not min or not sec then return nil end

    return tonumber(min) * 60 + tonumber(sec)
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

-- ===== Auto Dice =====
local function buyDice()
    withLock(function()
        local hrp = getHRP()
        hrp.CFrame = DICE_SHOP
        task.wait(1.0)
        BuyDice:FireServer("BuyBestAvailable")
        task.wait(0.3)
        returnToPlot(hrp)
        print("Bought dice")
    end)
end

task.spawn(function()
    while true do
        if enabled then
            buyDice()

            local restockWait = getRestockSeconds("Main")
            if restockWait then
                print(("Dice restocking in %ds"):format(restockWait))
                restockWait += RESTOCK_BUFFER
            else
                warn("Couldn't read dice restock timer, falling back to fixed wait")
                restockWait = WAIT_AFTER_BUY
            end

            local waited = 0
            while waited < restockWait and enabled do
                task.wait(1)
                waited += 1
            end
        else
            task.wait(1)
        end
    end
end)

-- ===== Auto Potion =====
local function buyPotion()
    withLock(function()
        local hrp = getHRP()
        hrp.CFrame = POTION_SHOP
        task.wait(1.0)
        BuyPotion:FireServer("BuyBestAvailable")
        task.wait(0.3)
        returnToPlot(hrp)
        task.wait(0.5)
        useAllPotions()
        print("Bought potion")
    end)
end

task.spawn(function()
    while true do
        if enabled then
            buyPotion()

            local restockWait = getRestockSeconds("Potion")
            if restockWait then
                print(("Potion restocking in %ds"):format(restockWait))
                restockWait += RESTOCK_BUFFER
            else
                warn("Couldn't read potion restock timer, falling back to fixed wait")
                restockWait = WAIT_AFTER_BUY
            end

            local waited = 0
            while waited < restockWait and enabled do
                task.wait(1)
                waited += 1
            end
        else
            task.wait(1)
        end
    end
end)

-- ===== Auto Equip (independent, no movement needed) =====
task.spawn(function()
    while true do
        if enabled then
            pcall(function()
                EquipBest:FireServer()
            end)
        end
        task.wait(EQUIP_INTERVAL)
    end
end)

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
    withLock(function()
        local hrp = getHRP()
        hrp.CFrame = SELL_CFRAME
        task.wait(0.4)
        -- Preview first
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview")
        task.wait(1.5) -- small delay between preview and commit
        -- Then commit
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit")
        print("Sold inventory")
        task.wait(0.3)
        returnToPlot(hrp)
    end)
end

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

-- ===== Auto Rebirth =====
local function getRebirthButton()
    local ok, btn = pcall(function()
        return player.PlayerGui.Main.Canvas.Rebirth.MainFrame.Rebirth
    end)
    if ok then return btn end
    return nil
end

local function isRebirthReady()
    local btn = getRebirthButton()
    if not btn then return false end
    local color = btn.BackgroundColor3
    return color.G > color.R
end

task.spawn(function()
    while true do
        if enabled then
            local ok, ready = pcall(isRebirthReady)
            if ok and ready then
                withLock(function()
                    print("[AutoRebirth] Requirements met — firing rebirth")
                    RebirthRemote:FireServer()
                    task.wait(REBIRTH_COOLDOWN)
                end)
            end
        end
        task.wait(REBIRTH_CHECK_INTERVAL)
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        print(enabled and "✅ Auto Farm: ON" or "❌ Auto Farm: OFF")
    end
end)

print("Full script loaded. Press B to toggle Auto Farm (dice + potions + equip + sell + rebirth)")
