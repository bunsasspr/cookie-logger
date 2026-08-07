-- ============================================================
--  RNG PET FARM v3 — Full GUI Rework
--  Auto Dice | Auto Potion | Auto Equip | Auto Sell | Auto Rebirth
--  Auto Eggs | Auto FoodCart | Auto Merchant | Auto Collect Money
--  Dynamic NPC finding (no hardcoded coords!)
-- ============================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

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
    AutoDice = false,
    AutoPotion = false,
    AutoEquip = false,
    AutoSell = false,
    AutoRebirth = false,
    AutoEggs = false,
    AutoFoodCart = false,
    AutoMerchant = false,
    AutoCollect = false,

    SellThreshold = 30,
    SellCheckInterval = 5,
    EquipInterval = 300,
    EquipSessionDuration = 20,
    EquipSpamDelay = 5,
    EquipBeforeSell = 3,
    RebirthCheckInterval = 2,
    RebirthCooldown = 5,
    NPCCheckInterval = 3,
    EggSpamDelay = 0.15,
    EggName = "Frozen",
    EggAmount = 3,
    CollectInterval = 2,

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
    local mapShop = findNPC({"Map", "MapShop"})
    if not mapShop then return nil end
    local shop = mapShop:FindFirstChild(shopName)
    if not shop then return nil end
    local char = shop:FindFirstChild("Character")
    if not char then return nil end
    return char:FindFirstChildWhichIsA("Model", true) or char:FindFirstChildOfClass("Model")
end

local function getDiceShop() return getShopNPC("Shop") end
local function getPotionShop() return getShopNPC("PotionShop") end
local function getSellShop() return getShopNPC("SellShop") end

local function getModelPart(model)
    if not model then return nil end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getEggHolder(eggName)
    local eggHolders = findNPC({"Map", "Island", "EggHolders"})
    if not eggHolders then return nil end
    for _, holder in ipairs(eggHolders:GetChildren()) do
        local egg = holder:FindFirstChild(eggName)
        if egg then
            local center = egg:FindFirstChild("Center")
            return center or egg
        end
    end
    return nil
end

local function getFirstAvailableEgg()
    local eggHolders = findNPC({"Map", "Island", "EggHolders"})
    if not eggHolders then return nil end
    for _, holder in ipairs(eggHolders:GetChildren()) do
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("Model") then
                local part = getModelPart(child)
                if part then return part end
            end
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

-- ============================================================
--  TYCOON MONEY COLLECTOR (works from far away!)
-- ============================================================
local function getMyPlot()
    local plotsFolder = findNPC({"Map", "Plots"})
    if not plotsFolder then return nil end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = plot:GetAttribute("Owner") or plot:GetAttribute("owner")
        if owner == player.UserId or tostring(owner) == tostring(player.UserId) then
            return plot
        end
    end
    return nil
end

-- Finds the Collector part on our plot (where money is collected)
local function getCollectorPart()
    local plot = getMyPlot()
    if not plot then return nil end
    local collector = plot:FindFirstChild("Collector", true)
    if collector and collector:IsA("BasePart") then return collector end
    -- fallback: look in ItemHolder1.Place / first holder
    local floor1 = plot:FindFirstChild("Floor1")
    if floor1 then
        local holders = floor1:FindFirstChild("Holders")
        if holders then
            local itemHolder = holders:FindFirstChild("ItemHolder1")
            if itemHolder then
                collector = itemHolder:FindFirstChild("Collector")
                if collector and collector:IsA("BasePart") then return collector end
            end
        end
    end
    return nil
end

-- Fires the collector prompt/click from anywhere
local function collectMoney()
    local collector = getCollectorPart()
    if not collector then return false end

    local fired = false

    -- Try ProximityPrompt first (works from far with fireproximityprompt)
    for _, prompt in ipairs(collector:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            pcall(function()
                fireproximityprompt(prompt)
                fired = true
            end)
        end
    end
    if collector:IsA("ProximityPrompt") then
        pcall(function()
            fireproximityprompt(collector)
            fired = true
        end)
    end

    -- Try ClickDetector
    for _, det in ipairs(collector:GetDescendants()) do
        if det:IsA("ClickDetector") then
            pcall(function()
                fireclickdetector(det)
                fired = true
            end)
        end
    end

    -- Try firing any collect-related remote as a last resort (common in these games)
    if not fired then
        local candidates = { "Collect", "Collection", "CollectCash", "ClaimCash", "CashCollect", "PlotCollect", "Collector" }
        for _, name in ipairs(candidates) do
            local rmt = remotes:FindFirstChild(name)
            if rmt then
                pcall(function()
                    rmt:FireServer()
                    fired = true
                end)
            end
        end
    end

    return fired
end

-- Auto Collect Money loop
task.spawn(function()
    while true do
        if Config.AutoCollect then
            local ok = pcall(collectMoney)
            if not ok then
                -- if no collector found, stay quiet
            end
        end
        task.wait(Config.CollectInterval)
    end
end)

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
    local plot = getMyPlot()
    if not plot then return nil end
    local part = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame + Vector3.new(0, 3, 0) end
    return nil
end

local function goToEggs(hrp)
    local egg = getEggHolder(Config.EggName)
    if egg then
        local part = getModelPart(egg)
        if part then
            teleportTo(hrp, part.CFrame, 3)
            task.wait(Config.TeleportSettleDelay)
            return true
        end
    end
    -- fallback: any egg holder
    local fallback = getFirstAvailableEgg()
    if fallback then
        teleportTo(hrp, fallback.CFrame, 3)
        task.wait(Config.TeleportSettleDelay)
        return true
    end
    warn("Could not find egg location")
    return false
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
}

-- ============================================================
--  MERCHANT ITEM LISTS (verified from game dump)
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

-- Auto Eggs (fires remote from anywhere + teleports on enable)
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

        for _, cat in ipairs(MERCHANT_CATEGORIES) do
            for _, itemName in ipairs(cat.items) do
                pcall(function()
                    MerchantRemote:FireServer("BuyAll", cat.name, itemName)
                end)
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

-- ============================================================
--  UI LIBRARY (Kavo UI with built-in fallback)
-- ============================================================

local Library = nil
local usingKavo = false

-- Try to load Kavo UI from the public GitHub library
local okKavo, kavoResult = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
end)

if okKavo and type(kavoResult) == "table" and kavoResult.CreateLib then
    Library = kavoResult
    usingKavo = true
end

----------------------
-- KAVO UI PATH
----------------------
if usingKavo then
    local Window = Library.CreateLib("🎲 RNG Pet Farm v3", "DarkTheme")

    -- Farm Tab
    local FarmTab = Window:NewTab("Farm")
    local FarmSection = FarmTab:NewSection("Auto Farm")
    FarmSection:NewToggle("Auto Dice", "Buy best dice from shop", function(state) Config.AutoDice = state end)
    FarmSection:NewToggle("Auto Potion", "Buy & use all potions", function(state) Config.AutoPotion = state end)
    FarmSection:NewToggle("Auto Equip", "Equip best pets at plot", function(state) Config.AutoEquip = state end)
    FarmSection:NewToggle("Auto Sell", "Sell inventory when full", function(state) Config.AutoSell = state end)
    FarmSection:NewToggle("Auto Rebirth", "Rebirth when ready", function(state) Config.AutoRebirth = state end)
    FarmSection:NewToggle("Auto Eggs", "Open eggs + teleport to eggs", function(state)
        Config.AutoEggs = state
        if state then
            task.spawn(function()
                withLock(function()
                    local hrp = getHRP()
                    goToEggs(hrp)
                end)
            end)
        end
    end)
    FarmSection:NewToggle("Auto FoodCart", "Buy all food when cart spawns", function(state) Config.AutoFoodCart = state end)
    FarmSection:NewToggle("Auto Merchant", "Buy all from merchant", function(state) Config.AutoMerchant = state end)
    FarmSection:NewToggle("Auto Collect", "Collect tycoon money from anywhere", function(state) Config.AutoCollect = state end)

    local ManualSection = FarmTab:NewSection("Manual Actions")
    ManualSection:NewButton("🛒 Buy All Potions Now", "Buy and use all potions", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                local shop = getPotionShop()
                if shop then
                    local part = getModelPart(shop)
                    if part then
                        teleportTo(hp, part.CFrame)
                        task.wait(Config.TeleportSettleDelay)
                        local el = 0
                        while el < Config.BuyStandDuration do
                            pcall(function() BuyPotion:FireServer("BuyBestAvailable") end)
                            task.wait(Config.BuyFireInterval)
                            el = el + Config.BuyFireInterval
                        end
                    end
                end
                useAllPotions()
                goToEggs(hp)
            end)
        end)
    end)
    ManualSection:NewButton("🎲 Buy Best Dice Now", "Buy best dice", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                local shop = getDiceShop()
                if shop then
                    local part = getModelPart(shop)
                    if part then
                        teleportTo(hp, part.CFrame)
                        task.wait(Config.TeleportSettleDelay)
                        local el = 0
                        while el < Config.BuyStandDuration do
                            pcall(function() BuyDice:FireServer("BuyBestAvailable") end)
                            task.wait(Config.BuyFireInterval)
                            el = el + Config.BuyFireInterval
                        end
                    end
                end
                goToEggs(hp)
            end)
        end)
    end)
    ManualSection:NewButton("💰 Sell Inventory Now", "Sell all pets", function()
        task.spawn(function() sellInventory() end)
    end)
    ManualSection:NewButton("⚡ Equip Best Now", "Quick equip", function()
        task.spawn(function()
            withLock(function()
                equipAtPlot(5)
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    ManualSection:NewButton("🔄 Rebirth Now", "Rebirth once", function()
        task.spawn(function()
            withLock(function()
                RebirthRemote:FireServer()
                task.wait(Config.RebirthCooldown)
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    ManualSection:NewButton("🥚 Go To Eggs", "Teleport to selected egg", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    ManualSection:NewButton("🏠 Go To Plot", "Teleport to your plot", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                returnToPlot(hp)
            end)
        end)
    end)

    -- Settings Tab
    local SettingsTab = Window:NewTab("Settings")
    local GeneralSection = SettingsTab:NewSection("Sell / Inventory")
    GeneralSection:NewSlider("Sell Threshold", "Pets before selling", 1, 100, function(value) Config.SellThreshold = value end)
    GeneralSection:NewSlider("Sell Check Interval", "Seconds", 1, 30, function(value) Config.SellCheckInterval = value end)

    local EquipSection = SettingsTab:NewSection("Equip")
    EquipSection:NewSlider("Equip Interval", "Seconds between sessions", 30, 600, function(value) Config.EquipInterval = value end)
    EquipSection:NewSlider("Equip Session", "Seconds at plot", 5, 60, function(value) Config.EquipSessionDuration = value end)
    EquipSection:NewSlider("Equip Spam Delay", "Seconds between equips", 1, 10, function(value) Config.EquipSpamDelay = value end)

    local LoopSection = SettingsTab:NewSection("Loops")
    LoopSection:NewSlider("Rebirth Check", "Seconds", 1, 10, function(value) Config.RebirthCheckInterval = value end)
    LoopSection:NewSlider("NPC Check", "Seconds", 1, 10, function(value) Config.NPCCheckInterval = value end)
    LoopSection:NewSlider("Buy Stand Duration", "Seconds", 1, 10, function(value) Config.BuyStandDuration = value end)
    LoopSection:NewSlider("Buy Fire Interval", "Seconds", 0.1, 2, function(value) Config.BuyFireInterval = value end)
    LoopSection:NewSlider("Collect Interval", "Seconds", 1, 10, function(value) Config.CollectInterval = value end)

    -- Eggs Tab
    local EggsTab = Window:NewTab("Eggs")
    local EggSection = EggsTab:NewSection("Egg Settings")
    local eggChoices = { "Basic", "Forest", "Jungle", "Beach", "Monster", "Desert", "Galaxy", "Candy", "Lava", "Frozen", "Brainrot Egg" }
    EggSection:NewDropdown("Egg Type", "Choose egg to open", eggChoices, function(value) Config.EggName = value end)
    EggSection:NewSlider("Egg Amount", "How many at once", 1, 10, function(value) Config.EggAmount = value end)
    EggSection:NewSlider("Egg Spam Delay", "Seconds", 0.05, 1, function(value) Config.EggSpamDelay = value end)

    print("✅ RNG Pet Farm v3 loaded (Kavo UI)!")
else
----------------------
-- FALLBACK UI PATH
----------------------
    -- Only reachable if Kavo load failed. Minimal, clean, functional GUI.
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RNGFarmGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = player:WaitForChild("PlayerGui")

    local theme = {
        bg = Color3.fromRGB(20, 22, 30),
        panel = Color3.fromRGB(28, 31, 42),
        accent = Color3.fromRGB(88, 101, 242),
        text = Color3.fromRGB(230, 230, 240),
        subtext = Color3.fromRGB(150, 155, 170),
        green = Color3.fromRGB(60, 200, 120),
        red = Color3.fromRGB(220, 70, 70),
        border = Color3.fromRGB(45, 50, 65),
    }

    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.fromOffset(400, 600)
    Main.Position = UDim2.new(0, 20, 0.5, -300)
    Main.BackgroundColor3 = theme.bg
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            Main.Position = UDim2.fromOffset(input.Position.X - dragOffset.X, input.Position.Y - dragOffset.Y)
        end
    end)

    -- Title
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 36)
    Title.BackgroundColor3 = theme.panel
    Title.Text = "🎲 RNG Pet Farm v3 (Fallback UI)"
    Title.TextColor3 = theme.text
    Title.TextSize = 16
    Title.Font = Enum.Font.GothamBold
    Title.Parent = Main

    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 12)
    TitleCorner.Parent = Title

    -- Close
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.fromOffset(28, 28)
    CloseBtn.Position = UDim2.new(1, -34, 0, 4)
    CloseBtn.BackgroundColor3 = theme.red
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Color3.new(1, 1, 1)
    CloseBtn.TextSize = 12
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.Parent = Title

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = CloseBtn

    -- Scroller
    local Scroller = Instance.new("ScrollingFrame")
    Scroller.Size = UDim2.new(1, 0, 1, -36)
    Scroller.Position = UDim2.new(0, 0, 0, 36)
    Scroller.BackgroundTransparency = 1
    Scroller.BorderSizePixel = 0
    Scroller.ScrollBarThickness = 4
    Scroller.ScrollBarImageColor3 = theme.accent
    Scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
    Scroller.Parent = Main

    local Layout = Instance.new("UIListLayout")
    Layout.Padding = UDim.new(0, 4)
    Layout.Parent = Scroller

    local function addToggle(title, desc, getVal, setVal)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 44)
        row.BackgroundColor3 = theme.panel
        row.BorderSizePixel = 0
        row.Parent = Scroller

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 8)
        rowCorner.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -50, 1, 0)
        lbl.Position = UDim2.fromOffset(10, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = title .. "\n" .. desc
        lbl.TextColor3 = theme.text
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.Parent = row

        local toggle = Instance.new("TextButton")
        toggle.Size = UDim2.fromOffset(34, 20)
        toggle.Position = UDim2.new(1, -44, 0, 12)
        toggle.BackgroundColor3 = theme.red
        toggle.Text = ""
        toggle.BorderSizePixel = 0
        toggle.Parent = row

        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(1, 0)
        toggleCorner.Parent = toggle

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(14, 14)
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
            knob.Position = on and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3)
        end

        toggle.MouseButton1Click:Connect(function()
            setVal(not getVal())
            update()
        end)
        update()
    end

    local function addButton(text, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 36)
        btn.BackgroundColor3 = theme.accent
        btn.Text = text
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.TextSize = 14
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.Parent = Scroller

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(cb)
    end

    local function addLabel(text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -16, 0, 24)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = theme.accent
        lbl.TextSize = 14
        lbl.Font = Enum.Font.GothamBold
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = Scroller
    end

    addLabel("Auto Farm")
    addToggle("Auto Dice", "Buy best dice from shop", function() return Config.AutoDice end, function(v) Config.AutoDice = v end)
    addToggle("Auto Potion", "Buy & use all potions", function() return Config.AutoPotion end, function(v) Config.AutoPotion = v end)
    addToggle("Auto Equip", "Equip best pets at plot", function() return Config.AutoEquip end, function(v) Config.AutoEquip = v end)
    addToggle("Auto Sell", "Sell inventory when full", function() return Config.AutoSell end, function(v) Config.AutoSell = v end)
    addToggle("Auto Rebirth", "Rebirth when ready", function() return Config.AutoRebirth end, function(v) Config.AutoRebirth = v end)
    addToggle("Auto Eggs", "Open eggs + teleport to eggs", function() return Config.AutoEggs end, function(v)
        Config.AutoEggs = v
        if v then
            task.spawn(function()
                withLock(function()
                    local hp = getHRP()
                    goToEggs(hp)
                end)
            end)
        end
    end)
    addToggle("Auto FoodCart", "Buy all food when cart spawns", function() return Config.AutoFoodCart end, function(v) Config.AutoFoodCart = v end)
    addToggle("Auto Merchant", "Buy all from merchant", function() return Config.AutoMerchant end, function(v) Config.AutoMerchant = v end)
    addToggle("Auto Collect", "Collect tycoon money anywhere", function() return Config.AutoCollect end, function(v) Config.AutoCollect = v end)

    addLabel("Manual Actions")
    addButton("🛒 Buy All Potions Now", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                local shop = getPotionShop()
                if shop then
                    local part = getModelPart(shop)
                    if part then
                        teleportTo(hp, part.CFrame)
                        task.wait(Config.TeleportSettleDelay)
                        local el = 0
                        while el < Config.BuyStandDuration do
                            pcall(function() BuyPotion:FireServer("BuyBestAvailable") end)
                            task.wait(Config.BuyFireInterval)
                            el = el + Config.BuyFireInterval
                        end
                    end
                end
                useAllPotions()
                goToEggs(hp)
            end)
        end)
    end)
    addButton("🎲 Buy Best Dice Now", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                local shop = getDiceShop()
                if shop then
                    local part = getModelPart(shop)
                    if part then
                        teleportTo(hp, part.CFrame)
                        task.wait(Config.TeleportSettleDelay)
                        local el = 0
                        while el < Config.BuyStandDuration do
                            pcall(function() BuyDice:FireServer("BuyBestAvailable") end)
                            task.wait(Config.BuyFireInterval)
                            el = el + Config.BuyFireInterval
                        end
                    end
                end
                goToEggs(hp)
            end)
        end)
    end)
    addButton("💰 Sell Inventory Now", function() task.spawn(function() sellInventory() end) end)
    addButton("⚡ Equip Best Now", function()
        task.spawn(function()
            withLock(function()
                equipAtPlot(5)
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    addButton("🔄 Rebirth Now", function()
        task.spawn(function()
            withLock(function()
                RebirthRemote:FireServer()
                task.wait(Config.RebirthCooldown)
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    addButton("🥚 Go To Eggs", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                goToEggs(hp)
            end)
        end)
    end)
    addButton("🏠 Go To Plot", function()
        task.spawn(function()
            withLock(function()
                local hp = getHRP()
                returnToPlot(hp)
            end)
        end)
    end)

    addLabel("Egg Settings")
    -- simple egg name input
    local eggInput = Instance.new("TextBox")
    eggInput.Size = UDim2.new(1, -16, 0, 36)
    eggInput.BackgroundColor3 = theme.panel
    eggInput.PlaceholderText = "Egg name (e.g. Frozen)"
    eggInput.Text = Config.EggName
    eggInput.TextColor3 = theme.text
    eggInput.TextSize = 14
    eggInput.Font = Enum.Font.Gotham
    eggInput.Parent = Scroller

    local eggInputCorner = Instance.new("UICorner")
    eggInputCorner.CornerRadius = UDim.new(0, 8)
    eggInputCorner.Parent = eggInput

    eggInput.FocusLost:Connect(function()
        if eggInput.Text ~= "" then Config.EggName = eggInput.Text end
    end)

    -- Toggle button
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

    ToggleBtn.MouseButton1Click:Connect(function() Main.Visible = not Main.Visible end)
    CloseBtn.MouseButton1Click:Connect(function() Main.Visible = false end)

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.B then
            Main.Visible = not Main.Visible
        end
    end)

    print("✅ RNG Pet Farm v3 loaded (Fallback UI - Kavo could not be fetched)!")
end

print("🎲 RNG Pet Farm v3 loaded! Toggle GUI with B or 🎲 button")
