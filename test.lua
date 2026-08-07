-- ============================================================
--  RNG PET FARM v2 — Full GUI Rework
--  Auto Dice | Auto Potion | Auto Equip | Auto Sell | Auto Rebirth
--  Auto Eggs | Auto FoodCart | Auto Merchant | Auto Feed Pets
--  Dynamic NPC finding (no hardcoded coords)
-- ============================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

-- ===== Anti AFK =====
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ===== Remotes =====
local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")
local EquipBest = remotes:WaitForChild("EquipBest")
local UsePotion = remotes:WaitForChild("UsePotion")
local Dialogue = remotes:WaitForChild("Dialogue")
local RebirthRemote = remotes:WaitForChild("Rebirth")
local FoodCartRemote = remotes:WaitForChild("FoodCart")
local MerchantRemote = remotes:WaitForChild("Merchant")
local EggInfo = remotes:WaitForChild("EggInfo")

-- ============================================================
--  CONFIG (editable via GUI)
-- ============================================================
local Config = {
    -- Toggles
    AutoDice = false,
    AutoPotion = false,
    AutoEquip = false,
    AutoSell = false,
    AutoRebirth = false,
    AutoEggs = false,
    AutoFoodCart = false,
    AutoMerchant = false,
    AutoFeedPets = false,

    -- Settings
    SellThreshold = 30,
    SellCheckInterval = 5,
    EquipInterval = 300,        -- seconds between equip sessions
    EquipSessionDuration = 20,  -- seconds at plot
    EquipSpamDelay = 5,         -- seconds between equips
    EquipBeforeSell = 3,        -- equips before selling
    RebirthCheckInterval = 2,
    RebirthCooldown = 5,
    NPCCheckInterval = 3,
    EggSpamDelay = 0.15,
    EggName = "Frozen",         -- which egg to open
    EggAmount = 3,              -- how many to open at once
    FeedFood = "Steak",         -- best food for pet leveling
    FeedAmount = 100,           -- how much food to feed
    FeedInterval = 10,          -- seconds between feed sessions
    ActionSettleDelay = 0.6,
    TeleportSettleDelay = 0.5,
    BuyStandDuration = 2,
    BuyFireInterval = 0.5,
    RestockBuffer = 2,
    FallbackWait = 120,
}

-- ============================================================
--  DYNAMIC NPC FINDING (no hardcoded coords!)
-- ============================================================
local function findNPC(path)
    local current = workspace
    for _, name in ipairs(path) do
        current = current:FindFirstChild(name)
        if not current then return nil end
    end
    return current
end

local function getShopNPC(shopName)
    -- workspace.Map.MapShop.<ShopName>.Character.<NpcName>
    local mapShop = findNPC({"Map", "MapShop"})
    if not mapShop then return nil end
    local shop = mapShop:FindFirstChild(shopName)
    if not shop then return nil end
    local char = shop:FindFirstChild("Character")
    if not char then return nil end
    return char:FindFirstChildWhichIsA("Model", true) or char:FindFirstChildOfClass("Model")
end

local function getDiceShop()
    return getShopNPC("Shop")
end

local function getPotionShop()
    return getShopNPC("PotionShop")
end

local function getSellShop()
    return getShopNPC("SellShop")
end

local function getEggHolder(eggName)
    local eggHolders = findNPC({"Map", "Island", "EggHolders"})
    if not eggHolders then return nil end
    for _, holder in ipairs(eggHolders:GetChildren()) do
        local egg = holder:FindFirstChild(eggName)
        if egg then
            return egg:FindFirstChild("Center") or egg
        end
    end
    return nil
end

local function getFoodCartModel()
    local mapShop = findNPC({"Map", "MapShop"})
    if not mapShop then return nil end
    return mapShop:FindFirstChild("FoodCart")
end

local function getMerchantModel()
    local mapShop = findNPC({"Map", "MapShop"})
    if not mapShop then return nil end
    return mapShop:FindFirstChild("Merchant")
end

local function getModelPart(model)
    if not model then return nil end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

-- ============================================================
--  MOVEMENT LOCK & TELEPORT
-- ============================================================
local actionLock = false
local function withLock(fn)
    while actionLock do task.wait(0.2) end
    actionLock = true
    task.wait(Config.ActionSettleDelay)
    local ok, err = pcall(fn)
    actionLock = false
    if not ok then warn("[Farm] Action error: " .. tostring(err)) end
end

local function startPin(hrp, cframe)
    local pinning = true
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if pinning and hrp and hrp.Parent then
            hrp.CFrame = cframe
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    return function()
        pinning = false
        conn:Disconnect()
    end
end

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function teleportTo(hrp, cframe, backOffset)
    backOffset = backOffset or 4
    hrp.CFrame = cframe * CFrame.new(0, 0, backOffset)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function getMyPlotCFrame()
    local plotsFolder = findNPC({"Map", "Plots"})
    if not plotsFolder then return nil end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
            local part = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.CFrame + Vector3.new(0, 3, 0) end
        end
    end
    return nil
end

local function goToEggs(hrp)
    local egg = getEggHolder(Config.EggName)
    if egg then
        local part = getModelPart(egg)
        if part then
            teleportTo(hrp, part.CFrame)
            task.wait(Config.TeleportSettleDelay)
            return
        end
    end
    -- fallback: find any egg holder
    local eggHolders = findNPC({"Map", "Island", "EggHolders"})
    if eggHolders then
        for _, holder in ipairs(eggHolders:GetChildren()) do
            local part = getModelPart(holder)
            if part then
                teleportTo(hrp, part.CFrame)
                task.wait(Config.TeleportSettleDelay)
                return
            end
        end
    end
    warn("Could not find egg location")
end

local function returnToPlot(hrp)
    local plotCF = getMyPlotCFrame()
    if plotCF then
        teleportTo(hrp, plotCF)
        task.wait(Config.TeleportSettleDelay)
    else
        warn("Could not find your plot!")
    end
end

-- ============================================================
--  RESTOCK TIMER READING
-- ============================================================
local function getRestockSeconds(shopName)
    local ok, label = pcall(function()
        return player.PlayerGui.Main.Canvas.MapShops[shopName].Holder.Timer.TextLabel
    end)
    if not ok or not label then return nil end
    local min, sec = label.Text:match("(%d+):(%d+)")
    if not min or not sec then return nil end
    return tonumber(min) * 60 + tonumber(sec)
end

-- ============================================================
--  POTION LIST
-- ============================================================
local potions = {
    {Name = "Cash I", Arg = "Max"},
    {Name = "Cash II", Arg = "Max"},
    {Name = "Cash III", Arg = "Max"},
    {Name = "Godly Cash", Arg = "Max"},
    {Name = "Luck I", Arg = "Max"},
    {Name = "Luck II", Arg = "Max"},
    {Name = "Luck III", Arg = "Max"},
    {Name = "Godly Luck", Arg = "Max"},
    {Name = "Egg Luck I", Arg = "Max"},
    {Name = "Egg Luck II", Arg = "Max"},
    {Name = "Godly Egg Luck", Arg = "Max"},
    {Name = "Mutation I", Arg = "Max"},
    {Name = "Mutation II", Arg = "Max"},
    {Name = "Mutation III", Arg = "Max"},
    {Name = "Godly Mutation", Arg = "Max"},
    {Name = "Dice Consumption I", Arg = "Max"},
    {Name = "Dice Consumption II", Arg = "Max"},
    {Name = "Godly Dice Consumption", Arg = "Max"},
    {Name = "Rainbow Godly", Arg = "Max"},
    {Name = "Rainbow Potion", Arg = "Max"},
}

-- ============================================================
--  MERCHANT ITEM LISTS (from game dump)
-- ============================================================
local MERCHANT_CATEGORIES = {
    {
        name = "Dices",
        items = {
            "Basic", "Bronze", "Iron", "Silver", "Gold", "Sapphire", "Emerald", "Ruby",
            "Obsidian", "Crystal", "Nebula", "Void", "Celestial", "Abyssal", "Infernal",
            "Ethereal", "Galactic", "Quantum", "Eldritch", "Sovereign", "Arcane",
            "Paradox", "Oblivion", "Singularity", "Transcendent", "Omnipotent",
            "Seraphic", "Valentine"
        }
    },
    {
        name = "Potions",
        items = {
            "Luck I", "Cash I", "Luck II", "Cash II", "Mutation I", "Dice Consumption I",
            "Luck III", "Cash III", "Mutation II", "Godly Cash", "Godly Luck", "Egg Luck I",
            "Dice Consumption II", "Egg Luck II", "Godly Mutation", "Godly Dice Consumption", "Godly Egg Luck"
        }
    },
    {
        name = "Foods",
        items = { "Apple", "Potato", "Carrot", "Loaf", "Fish", "Steak" }
    },
    {
        name = "Exclusives",
        items = { "Holy Token", "Rainbow Godly" }
    },
}

-- ============================================================
--  FEATURE IMPLEMENTATIONS
-- ============================================================

-- Auto Eggs
task.spawn(function()
    while true do
        if Config.AutoEggs and not actionLock then
            pcall(function()
                EggInfo:InvokeServer("Buy", Config.EggName, Config.EggAmount)
            end)
        end
        task.wait(Config.EggSpamDelay)
    end
end)

-- Auto Dice
local function buyDice()
    withLock(function()
        local shop = getDiceShop()
        if not shop then warn("Dice shop not found"); return end
        local part = getModelPart(shop)
        if not part then warn("Dice shop has no part"); return end

        local hrp = getHRP()
        teleportTo(hrp, part.CFrame)
        task.wait(Config.TeleportSettleDelay)

        local elapsed = 0
        while elapsed < Config.BuyStandDuration do
            pcall(function() BuyDice:FireServer("BuyBestAvailable") end)
            task.wait(Config.BuyFireInterval)
            elapsed = elapsed + Config.BuyFireInterval
        end

        goToEggs(hrp)
    end)
end

task.spawn(function()
    while true do
        if Config.AutoDice then
            buyDice()
            local restockWait = getRestockSeconds("Main")
            if restockWait then
                restockWait = restockWait + Config.RestockBuffer
            else
                restockWait = Config.FallbackWait
            end
            local waited = 0
            while waited < restockWait and Config.AutoDice do
                task.wait(1)
                waited = waited + 1
            end
        else
            task.wait(1)
        end
    end
end)

-- Auto Potion
local function useAllPotions()
    for _, potion in ipairs(potions) do
        pcall(function()
            UsePotion:FireServer("Use", potion.Name, potion.Arg)
        end)
        task.wait(0.12)
    end
end

local function buyPotion()
    withLock(function()
        local shop = getPotionShop()
        if not shop then warn("Potion shop not found"); return end
        local part = getModelPart(shop)
        if not part then warn("Potion shop has no part"); return end

        local hrp = getHRP()
        teleportTo(hrp, part.CFrame)
        task.wait(Config.TeleportSettleDelay)

        local elapsed = 0
        while elapsed < Config.BuyStandDuration do
            pcall(function() BuyPotion:FireServer("BuyBestAvailable") end)
            task.wait(Config.BuyFireInterval)
            elapsed = elapsed + Config.BuyFireInterval
        end

        goToEggs(hrp)
        task.wait(0.5)
        useAllPotions()
    end)
end

task.spawn(function()
    while true do
        if Config.AutoPotion then
            buyPotion()
            local restockWait = getRestockSeconds("Potion")
            if restockWait then
                restockWait = restockWait + Config.RestockBuffer
            else
                restockWait = Config.FallbackWait
            end
            local waited = 0
            while waited < restockWait and Config.AutoPotion do
                task.wait(1)
                waited = waited + 1
            end
        else
            task.wait(1)
        end
    end
end)

-- Auto Equip
local function equipAtPlot(duration)
    local hrp = getHRP()
    returnToPlot(hrp)
    local elapsed = 0
    local count = 0
    while elapsed < duration and Config.AutoEquip do
        pcall(function() EquipBest:FireServer() end)
        count = count + 1
        task.wait(Config.EquipSpamDelay)
        elapsed = elapsed + Config.EquipSpamDelay
    end
end

task.spawn(function()
    while true do
        if Config.AutoEquip then
            withLock(function()
                equipAtPlot(Config.EquipSessionDuration)
                local hrp = getHRP()
                goToEggs(hrp)
            end)
        end
        task.wait(Config.EquipInterval)
    end
end)

-- Auto Sell
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
        returnToPlot(hrp)
        for i = 1, Config.EquipBeforeSell do
            pcall(function() EquipBest:FireServer() end)
            task.wait(Config.EquipSpamDelay)
        end

        local shop = getSellShop()
        if not shop then warn("Sell shop not found"); return end
        local part = getModelPart(shop)
        if not part then warn("Sell shop has no part"); return end

        teleportTo(hrp, part.CFrame)
        task.wait(Config.TeleportSettleDelay)
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview")
        task.wait(1.5)
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit")
        goToEggs(hrp)
    end)
end

task.spawn(function()
    while true do
        if Config.AutoSell then
            local count = getInventoryCount()
            if count >= Config.SellThreshold then
                sellInventory()
                task.wait(3)
            end
        end
        task.wait(Config.SellCheckInterval)
    end
end)

-- Auto Rebirth
local function isRebirthReady()
    local ok, btn = pcall(function()
        return player.PlayerGui.Main.Canvas.Rebirth.MainFrame.Rebirth
    end)
    if not ok or not btn then return false end
    local color = btn.BackgroundColor3
    return color.G > color.R
end

task.spawn(function()
    while true do
        if Config.AutoRebirth then
            local ok, ready = pcall(isRebirthReady)
            if ok and ready then
                withLock(function()
                    RebirthRemote:FireServer()
                    task.wait(Config.RebirthCooldown)
                    local hrp = getHRP()
                    goToEggs(hrp)
                end)
            end
        end
        task.wait(Config.RebirthCheckInterval)
    end
end)

-- Auto FoodCart
local function findProximityPrompt(model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then return inst end
    end
    return nil
end

local function buyFoodCart()
    withLock(function()
        local cart = getFoodCartModel()
        if not cart then warn("FoodCart not found"); return end
        local part = getModelPart(cart)
        if not part then warn("FoodCart has no part"); return end

        local hrp = getHRP()
        teleportTo(hrp, part.CFrame, 0)
        task.wait(Config.TeleportSettleDelay)

        if not getFoodCartModel() then
            goToEggs(hrp)
            return
        end

        for _, item in ipairs({ "Apple", "Potato", "Loaf", "Fish", "Steak" }) do
            pcall(function() FoodCartRemote:FireServer("BuyAll", item) end)
            task.wait(0.15)
        end
        goToEggs(hrp)
    end)
end

local lastFoodCart = nil
task.spawn(function()
    while true do
        if Config.AutoFoodCart then
            local cart = getFoodCartModel()
            if cart and cart ~= lastFoodCart then
                lastFoodCart = cart
                buyFoodCart()
            elseif not cart then
                lastFoodCart = nil
            end
        end
        task.wait(Config.NPCCheckInterval)
    end
end)

-- Auto Merchant
local function buyAllFromMerchant()
    withLock(function()
        local model = getMerchantModel()
        if not model then warn("Merchant not found"); return end
        local part = getModelPart(model)
        if not part then warn("Merchant has no part"); return end

        local hrp = getHRP()
        local targetCFrame = part.CFrame
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.25)

        local stopPin = startPin(hrp, targetCFrame)

        local prompt = findProximityPrompt(model)
        if prompt then
            pcall(function() fireproximityprompt(prompt) end)
        end
        task.wait(0.8)

        local bought = 0
        for _, cat in ipairs(MERCHANT_CATEGORIES) do
            for _, itemName in ipairs(cat.items) do
                pcall(function()
                    MerchantRemote:FireServer("BuyAll", cat.name, itemName)
                end)
                bought = bought + 1
                task.wait(0.12)
            end
        end

        task.wait(0.8)
        stopPin()
        task.wait(5)

        local hrp2 = getHRP()
        goToEggs(hrp2)
    end)
end

local lastMerchant = nil
task.spawn(function()
    while true do
        if Config.AutoMerchant then
            local merchant = getMerchantModel()
            if merchant and merchant ~= lastMerchant then
                lastMerchant = merchant
                buyAllFromMerchant()
            elseif not merchant then
                lastMerchant = nil
            end
        end
        task.wait(Config.NPCCheckInterval)
    end
end)

-- Auto Feed Pets
local function feedPets()
    withLock(function()
        local hrp = getHRP()
        returnToPlot(hrp)
        -- Feed via FoodCart remote (BuyAll food then feed)
        pcall(function()
            FoodCartRemote:FireServer("BuyAll", Config.FeedFood)
        end)
        task.wait(0.5)
        -- Try to feed pets via the pet UI remote if available
        pcall(function()
            local FeedRemote = remotes:FindFirstChild("FeedPet") or remotes:FindFirstChild("Feed")
            if FeedRemote then
                FeedRemote:FireServer(Config.FeedFood, Config.FeedAmount)
            end
        end)
        goToEggs(hrp)
    end)
end

task.spawn(function()
    while true do
        if Config.AutoFeedPets then
            feedPets()
        end
        task.wait(Config.FeedInterval)
    end
end)

-- ============================================================
--  GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RNGFarmGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = player:WaitForChild("PlayerGui")

local theme = {
    bg = Color3.fromRGB(20, 22, 30),
    panel = Color3.fromRGB(28, 31, 42),
    accent = Color3.fromRGB(88, 101, 242),
    accentDark = Color3.fromRGB(66, 76, 190),
    text = Color3.fromRGB(230, 230, 240),
    subtext = Color3.fromRGB(150, 155, 170),
    green = Color3.fromRGB(60, 200, 120),
    red = Color3.fromRGB(220, 70, 70),
    border = Color3.fromRGB(45, 50, 65),
}

-- Main Frame
local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(420, 560)
Main.Position = UDim2.new(0, 20, 0.5, -280)
Main.BackgroundColor3 = theme.bg
Main.BackgroundTransparency = 0.05
Main.BorderSizePixel = 0
Main.Visible = false
Main.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = Main

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = theme.border
UIStroke.Thickness = 1
UIStroke.Parent = Main

-- Drag
local dragging, dragOffset
Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragOffset = input.Position - Main.AbsolutePosition
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        Main.Position = UDim2.fromOffset(input.Position.X - dragOffset.X, input.Position.Y - dragOffset.Y)
    end
end)

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = theme.panel
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.fromOffset(12, 0)
Title.BackgroundTransparency = 1
Title.Text = "🎲 RNG Pet Farm v2"
Title.TextColor3 = theme.text
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

-- Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(30, 30)
CloseBtn.Position = UDim2.new(1, -36, 0, 5)
CloseBtn.BackgroundColor3 = theme.red
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.TextSize = 14
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- Minimize Button
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.fromOffset(30, 30)
MinBtn.Position = UDim2.new(1, -70, 0, 5)
MinBtn.BackgroundColor3 = theme.panel
MinBtn.Text = "—"
MinBtn.TextColor3 = theme.text
MinBtn.TextSize = 14
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

-- Tabs
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, 0, 0, 40)
TabBar.Position = UDim2.new(0, 0, 0, 40)
TabBar.BackgroundColor3 = theme.bg
TabBar.BorderSizePixel = 0
TabBar.Parent = Main

local tabs = { "Farm", "Settings", "Eggs", "Pets" }
local tabButtons = {}
local tabFrames = {}

local function createTab(name)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.25, 0, 1, 0)
    btn.BackgroundColor3 = theme.bg
    btn.Text = name
    btn.TextColor3 = theme.subtext
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamMedium
    btn.BorderSizePixel = 0
    btn.Parent = TabBar
    return btn
end

local function createTabFrame()
    local frame = Instance.new("ScrollingFrame")
    frame.Size = UDim2.new(1, 0, 1, -80)
    frame.Position = UDim2.new(0, 0, 0, 80)
    frame.BackgroundColor3 = theme.bg
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 4
    frame.ScrollBarImageColor3 = theme.accent
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    frame.Visible = false
    frame.Parent = Main
    return frame
end

for i, name in ipairs(tabs) do
    local btn = createTab(name)
    btn.Position = UDim2.new((i - 1) * 0.25, 0, 0, 0)
    tabButtons[name] = btn
    local frame = createTabFrame()
    tabFrames[name] = frame

    btn.MouseButton1Click:Connect(function()
        for _, b in pairs(tabButtons) do
            b.BackgroundColor3 = theme.bg
            b.TextColor3 = theme.subtext
        end
        btn.BackgroundColor3 = theme.accent
        btn.TextColor3 = Color3.new(1, 1, 1)
        for _, f in pairs(tabFrames) do f.Visible = false end
        frame.Visible = true
    end)
end

-- Helper: create toggle row
local function createToggle(parent, title, desc, getVal, setVal)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 50)
    row.Position = UDim2.new(0, 10, 0, 0)
    row.BackgroundColor3 = theme.panel
    row.BorderSizePixel = 0
    row.Parent = parent

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -60, 0, 20)
    titleLbl.Position = UDim2.fromOffset(12, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.TextColor3 = theme.text
    titleLbl.TextSize = 14
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = row

    local descLbl = Instance.new("TextLabel")
    descLbl.Size = UDim2.new(1, -60, 0, 18)
    descLbl.Position = UDim2.fromOffset(12, 26)
    descLbl.BackgroundTransparency = 1
    descLbl.Text = desc
    descLbl.TextColor3 = theme.subtext
    descLbl.TextSize = 11
    descLbl.Font = Enum.Font.Gotham
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.fromOffset(40, 24)
    toggle.Position = UDim2.new(1, -52, 0, 13)
    toggle.BackgroundColor3 = theme.red
    toggle.Text = ""
    toggle.BorderSizePixel = 0
    toggle.Parent = row

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggle

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = toggle

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function update()
        local on = getVal()
        toggle.BackgroundColor3 = on and theme.green or theme.red
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3)
        }):Play()
    end

    toggle.MouseButton1Click:Connect(function()
        setVal(not getVal())
        update()
    end)

    update()
    return row
end

-- Helper: create slider row
local function createSlider(parent, title, min, max, getVal, setVal, format)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 60)
    row.Position = UDim2.new(0, 10, 0, 0)
    row.BackgroundColor3 = theme.panel
    row.BorderSizePixel = 0
    row.Parent = parent

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -20, 0, 20)
    titleLbl.Position = UDim2.fromOffset(12, 6)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.TextColor3 = theme.text
    titleLbl.TextSize = 13
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = row

    local valueLbl = Instance.new("TextLabel")
    valueLbl.Size = UDim2.fromOffset(60, 20)
    valueLbl.Position = UDim2.new(1, -72, 0, 6)
    valueLbl.BackgroundTransparency = 1
    valueLbl.Text = format and format(getVal()) or tostring(getVal())
    valueLbl.TextColor3 = theme.accent
    valueLbl.TextSize = 13
    valueLbl.Font = Enum.Font.GothamBold
    valueLbl.TextXAlignment = Enum.TextXAlignment.Right
    valueLbl.Parent = row

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(1, -24, 0, 6)
    sliderBg.Position = UDim2.new(0, 12, 0, 40)
    sliderBg.BackgroundColor3 = theme.border
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = row

    local sliderBgCorner = Instance.new("UICorner")
    sliderBgCorner.CornerRadius = UDim.new(1, 0)
    sliderBgCorner.Parent = sliderBg

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = theme.accent
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.new(0, -7, 0, -4)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = sliderBg

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function update()
        local val = getVal()
        local pct = (val - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, -7, 0, -4)
        valueLbl.Text = format and format(val) or tostring(val)
    end

    local dragging = false
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local relX = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + (max - min) * relX)
            setVal(val)
            update()
        end
    end)

    update()
    return row
end

-- Helper: create dropdown
local function createDropdown(parent, title, options, getVal, setVal)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 50)
    row.Position = UDim2.new(0, 10, 0, 0)
    row.BackgroundColor3 = theme.panel
    row.BorderSizePixel = 0
    row.Parent = parent

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0.5, -20, 0, 20)
    titleLbl.Position = UDim2.fromOffset(12, 15)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = title
    titleLbl.TextColor3 = theme.text
    titleLbl.TextSize = 13
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, -12, 0, 30)
    btn.Position = UDim2.new(0.5, 0, 0, 10)
    btn.BackgroundColor3 = theme.accent
    btn.Text = getVal()
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamMedium
    btn.BorderSizePixel = 0
    btn.Parent = row

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    local dropdown = Instance.new("Frame")
    dropdown.Size = UDim2.new(0.5, -12, 0, 0)
    dropdown.Position = UDim2.new(0.5, 0, 0, 42)
    dropdown.BackgroundColor3 = theme.panel
    dropdown.BorderSizePixel = 0
    dropdown.Visible = false
    dropdown.ZIndex = 10
    dropdown.Parent = row

    local dropdownCorner = Instance.new("UICorner")
    dropdownCorner.CornerRadius = UDim.new(0, 6)
    dropdownCorner.Parent = dropdown

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = dropdown

    btn.MouseButton1Click:Connect(function()
        dropdown.Visible = not dropdown.Visible
        if dropdown.Visible then
            dropdown.Size = UDim2.new(0.5, -12, 0, math.min(#options * 30, 180))
        end
    end)

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 28)
        optBtn.BackgroundColor3 = theme.panel
        optBtn.Text = opt
        optBtn.TextColor3 = theme.text
        optBtn.TextSize = 12
        optBtn.Font = Enum.Font.Gotham
        optBtn.BorderSizePixel = 0
        optBtn.Parent = dropdown

        optBtn.MouseButton1Click:Connect(function()
            setVal(opt)
            btn.Text = opt
            dropdown.Visible = false
        end)
    end

    return row
end

-- ===== FARM TAB =====
local farmFrame = tabFrames["Farm"]
local farmLayout = Instance.new("UIListLayout")
farmLayout.Padding = UDim.new(0, 6)
farmLayout.Parent = farmFrame

createToggle(farmFrame, "Auto Dice", "Buy best dice from shop", function() return Config.AutoDice end, function(v) Config.AutoDice = v end)
createToggle(farmFrame, "Auto Potion", "Buy & use all potions", function() return Config.AutoPotion end, function(v) Config.AutoPotion = v end)
createToggle(farmFrame, "Auto Equip", "Equip best pets at plot", function() return Config.AutoEquip end, function(v) Config.AutoEquip = v end)
createToggle(farmFrame, "Auto Sell", "Sell inventory when full", function() return Config.AutoSell end, function(v) Config.AutoSell = v end)
createToggle(farmFrame, "Auto Rebirth", "Rebirth when ready", function() return Config.AutoRebirth end, function(v) Config.AutoRebirth = v end)
createToggle(farmFrame, "Auto Eggs", "Open eggs continuously", function() return Config.AutoEggs end, function(v) Config.AutoEggs = v end)
createToggle(farmFrame, "Auto FoodCart", "Buy all food when cart spawns", function() return Config.AutoFoodCart end, function(v) Config.AutoFoodCart = v end)
createToggle(farmFrame, "Auto Merchant", "Buy all from merchant", function() return Config.AutoMerchant end, function(v) Config.AutoMerchant = v end)
createToggle(farmFrame, "Auto Feed Pets", "Feed pets to level them up", function() return Config.AutoFeedPets end, function(v) Config.AutoFeedPets = v end)

-- ===== SETTINGS TAB =====
local settingsFrame = tabFrames["Settings"]
local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Padding = UDim.new(0, 6)
settingsLayout.Parent = settingsFrame

createSlider(settingsFrame, "Sell Threshold", 1, 100, function() return Config.SellThreshold end, function(v) Config.SellThreshold = v end, function(v) return v .. " pets" end)
createSlider(settingsFrame, "Sell Check Interval", 1, 30, function() return Config.SellCheckInterval end, function(v) Config.SellCheckInterval = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Equip Interval", 30, 600, function() return Config.EquipInterval end, function(v) Config.EquipInterval = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Equip Session", 5, 60, function() return Config.EquipSessionDuration end, function(v) Config.EquipSessionDuration = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Equip Spam Delay", 1, 10, function() return Config.EquipSpamDelay end, function(v) Config.EquipSpamDelay = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Rebirth Check", 1, 10, function() return Config.RebirthCheckInterval end, function(v) Config.RebirthCheckInterval = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "NPC Check", 1, 10, function() return Config.NPCCheckInterval end, function(v) Config.NPCCheckInterval = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Buy Stand Duration", 1, 10, function() return Config.BuyStandDuration end, function(v) Config.BuyStandDuration = v end, function(v) return v .. "s" end)
createSlider(settingsFrame, "Buy Fire Interval", 0.1, 2, function() return Config.BuyFireInterval end, function(v) Config.BuyFireInterval = v end, function(v) return v .. "s" end)

-- ===== EGGS TAB =====
local eggsFrame = tabFrames["Eggs"]
local eggsLayout = Instance.new("UIListLayout")
eggsLayout.Padding = UDim.new(0, 6)
eggsLayout.Parent = eggsFrame

local eggOptions = { "Basic", "Forest", "Jungle", "Beach", "Monster", "Desert", "Galaxy", "Candy", "Lava", "Frozen", "Brainrot Egg" }
createDropdown(eggsFrame, "Egg Type", eggOptions, function() return Config.EggName end, function(v) Config.EggName = v end)
createSlider(eggsFrame, "Egg Amount", 1, 10, function() return Config.EggAmount end, function(v) Config.EggAmount = v end, function(v) return "x" .. v end)
createSlider(eggsFrame, "Egg Spam Delay", 0.05, 1, function() return Config.EggSpamDelay end, function(v) Config.EggSpamDelay = v end, function(v) return v .. "s" end)

-- ===== PETS TAB =====
local petsFrame = tabFrames["Pets"]
local petsLayout = Instance.new("UIListLayout")
petsLayout.Padding = UDim.new(0, 6)
petsLayout.Parent = petsFrame

local foodOptions = { "Apple", "Potato", "Carrot", "Loaf", "Fish", "Steak" }
createDropdown(petsFrame, "Feed Food", foodOptions, function() return Config.FeedFood end, function(v) Config.FeedFood = v end)
createSlider(petsFrame, "Feed Amount", 1, 1000, function() return Config.FeedAmount end, function(v) Config.FeedAmount = v end, function(v) return "x" .. v end)
createSlider(petsFrame, "Feed Interval", 5, 120, function() return Config.FeedInterval end, function(v) Config.FeedInterval = v end, function(v) return v .. "s" end)

-- ===== BUTTONS =====
local function createActionButton(parent, text, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, 0)
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = parent

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Add action buttons to Farm tab
createActionButton(farmFrame, "🛒 Buy All Potions Now", theme.accent, function()
    task.spawn(function()
        withLock(function()
            local hrp = getHRP()
            local shop = getPotionShop()
            if shop then
                local part = getModelPart(shop)
                if part then
                    teleportTo(hrp, part.CFrame)
                    task.wait(Config.TeleportSettleDelay)
                    local elapsed = 0
                    while elapsed < Config.BuyStandDuration do
                        pcall(function() BuyPotion:FireServer("BuyBestAvailable") end)
                        task.wait(Config.BuyFireInterval)
                        elapsed = elapsed + Config.BuyFireInterval
                    end
                end
            end
            useAllPotions()
            goToEggs(hrp)
        end)
    end)
end)

createActionButton(farmFrame, "🎲 Buy Best Dice Now", theme.accent, function()
    task.spawn(function()
        withLock(function()
            local hrp = getHRP()
            local shop = getDiceShop()
            if shop then
                local part = getModelPart(shop)
                if part then
                    teleportTo(hrp, part.CFrame)
                    task.wait(Config.TeleportSettleDelay)
                    local elapsed = 0
                    while elapsed < Config.BuyStandDuration do
                        pcall(function() BuyDice:FireServer("BuyBestAvailable") end)
                        task.wait(Config.BuyFireInterval)
                        elapsed = elapsed + Config.BuyFireInterval
                    end
                end
            end
            goToEggs(hrp)
        end)
    end)
end)

createActionButton(farmFrame, "💰 Sell Inventory Now", theme.green, function()
    task.spawn(function()
        sellInventory()
    end)
end)

createActionButton(farmFrame, "⚡ Equip Best Now", theme.green, function()
    task.spawn(function()
        withLock(function()
            equipAtPlot(5)
            local hrp = getHRP()
            goToEggs(hrp)
        end)
    end)
end)

createActionButton(farmFrame, "🔄 Rebirth Now", theme.red, function()
    task.spawn(function()
        withLock(function()
            RebirthRemote:FireServer()
            task.wait(Config.RebirthCooldown)
            local hrp = getHRP()
            goToEggs(hrp)
        end)
    end)
end)

-- ===== TOGGLE GUI =====
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.fromOffset(50, 50)
ToggleBtn.Position = UDim2.new(0, 20, 0.5, -25)
ToggleBtn.BackgroundColor3 = theme.accent
ToggleBtn.Text = "🎲"
ToggleBtn.TextColor3 = Color3.new(1, 1, 1)
ToggleBtn.TextSize = 24
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = ToggleBtn

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = theme.border
ToggleStroke.Thickness = 2
ToggleStroke.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Main.Visible = not Main.Visible
end)

CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
end)

MinBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
end)

-- Keyboard toggle (B key)
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        Main.Visible = not Main.Visible
    end
end)

-- ===== STATUS BAR =====
local StatusBar = Instance.new("Frame")
StatusBar.Size = UDim2.new(1, 0, 0, 30)
StatusBar.Position = UDim2.new(0, 0, 1, -30)
StatusBar.BackgroundColor3 = theme.panel
StatusBar.BorderSizePixel = 0
StatusBar.Parent = Main

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 12)
StatusCorner.Parent = StatusBar

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 1, 0)
StatusLabel.Position = UDim2.fromOffset(10, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Idle"
StatusLabel.TextColor3 = theme.subtext
StatusLabel.TextSize = 12
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = StatusBar

-- Update status
task.spawn(function()
    while true do
        local active = {}
        if Config.AutoDice then table.insert(active, "Dice") end
        if Config.AutoPotion then table.insert(active, "Potion") end
        if Config.AutoEquip then table.insert(active, "Equip") end
        if Config.AutoSell then table.insert(active, "Sell") end
        if Config.AutoRebirth then table.insert(active, "Rebirth") end
        if Config.AutoEggs then table.insert(active, "Eggs") end
        if Config.AutoFoodCart then table.insert(active, "FoodCart") end
        if Config.AutoMerchant then table.insert(active, "Merchant") end
        if Config.AutoFeedPets then table.insert(active, "Feed") end

        if #active > 0 then
            StatusLabel.Text = "Active: " .. table.concat(active, " | ")
            StatusLabel.TextColor3 = theme.green
        else
            StatusLabel.Text = "Idle — Press B or click 🎲 to open"
            StatusLabel.TextColor3 = theme.subtext
        end
        task.wait(1)
    end
end)

-- ===== INIT =====
-- Select first tab
tabButtons["Farm"].BackgroundColor3 = theme.accent
tabButtons["Farm"].TextColor3 = Color3.new(1, 1, 1)
tabFrames["Farm"].Visible = true

print("✅ RNG Pet Farm v2 loaded! Press B or click 🎲 to open the GUI")
