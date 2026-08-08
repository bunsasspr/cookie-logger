-- ================= AutoFarm — Rayfield rework =================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")
local UsePotion = remotes:WaitForChild("UsePotion")
local RebirthRemote = remotes:WaitForChild("Rebirth")
local FoodCartRemote = remotes:WaitForChild("FoodCart")
local MerchantRemote = remotes:WaitForChild("Merchant")
local EggInfo = remotes:WaitForChild("EggInfo")
local Dialogue = remotes:WaitForChild("Dialogue")

-- ===== Config =====
local BUY_STAND_DURATION = 2       -- seconds to stand + spam-fire (dice/potion/eggs)
local BUY_FIRE_INTERVAL = 0.5      -- seconds between spam-fires
local TELEPORT_OFFSET = 4          -- studs back from target, avoids the collision push-out glitch
local TELEPORT_SETTLE_DELAY = 0.5  -- pause after teleporting before firing
local SCHEDULER_INTERVAL = 1       -- seconds between priority re-checks
local RESTOCK_BUFFER = 2           -- extra seconds after a restock timer hits 0
local FALLBACK_RESTOCK_WAIT = 120  -- used if a restock timer label can't be read
local COLLECT_INTERVAL = 3         -- seconds between money-collection sweeps
local USE_POTIONS_INTERVAL = 10    -- seconds between auto-use-potion sweeps
local REBIRTH_CHECK_INTERVAL = 2   -- seconds
local REBIRTH_COOLDOWN = 5         -- seconds after firing rebirth
local SELL_COOLDOWN = 3            -- seconds after selling before re-checking

-- Full item pools (found via Dark Dex) — fired blind, server rejects anything not
-- actually in stock, so no GUI reading is needed for Merchant at all.
local DICE_ORDER = {
    "Basic", "Bronze", "Iron", "Silver", "Gold", "Sapphire", "Emerald", "Ruby",
    "Obsidian", "Crystal", "Nebula", "Void", "Celestial", "Abyssal", "Infernal",
    "Ethereal", "Galactic", "Quantum", "Eldritch", "Sovereign", "Arcane",
    "Paradox", "Oblivion", "Singularity", "Transcendent", "Omnipotent",
    "Seraphic", "Valentine",
}
local POTION_ORDER = {
    "Luck I", "Cash I", "Luck II", "Cash II", "Mutation I", "Dice Consumption I",
    "Luck III", "Cash III", "Mutation II", "Godly Cash", "Godly Luck", "Egg Luck I",
    "Dice Consumption II", "Egg Luck II", "Godly Mutation", "Godly Dice Consumption",
    "Godly Egg Luck",
}
local FOOD_ORDER = {"Apple", "Potato", "Carrot", "Loaf", "Fish", "Steak"}
local EXCLUSIVE_ORDER = {"Holy Token", "Rainbow Godly"}

local MERCHANT_CATEGORIES = {
    {name = "Dices", items = DICE_ORDER},
    {name = "Potions", items = POTION_ORDER},
    {name = "Foods", items = FOOD_ORDER},
    {name = "Exclusive", items = EXCLUSIVE_ORDER},
}

-- workspace.Map.Island.EggHolders.<N> holds a model named after the egg type
local EGG_HOLDER_INDEX = {
    Basic = 1, Forest = 2, Jungle = 3, Beach = 4, Monster = 5,
    Desert = 6, Galaxy = 7, Candy = 8, Lava = 9, Frozen = 10,
}
local EGG_NAMES = {"Basic", "Forest", "Jungle", "Beach", "Monster", "Desert", "Galaxy", "Candy", "Lava", "Frozen"}

-- ===== Feature state (driven by the Rayfield elements below) =====
local state = {
    dice = false,
    potion = false,
    merchant = false,
    foodcart = false,
    collect = false,
    usePotions = false,
    egg = false,
    eggQuantity = 3,
    rebirth = false,
    selectedEgg = "Basic",
    sell = false,
    sellThreshold = 30,
}

-- ===== Helpers =====
local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- Teleports offset back from the target so the character doesn't land inside
-- collision geometry (which shoves it back out, sometimes well out of range),
-- and zeroes velocity so nothing carries into that push.
local function teleportTo(cframe, offset)
    offset = offset or TELEPORT_OFFSET
    local hrp = getHRP()
    hrp.CFrame = cframe * CFrame.new(0, 0, offset)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function getMapShopPart(modelName)
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    if not mapShop then return nil end
    local model = mapShop:FindFirstChild(modelName)
    if not model then return nil end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getEggPart(eggName)
    local idx = EGG_HOLDER_INDEX[eggName]
    if not idx then return nil end
    local holders = workspace.Map:FindFirstChild("Island") and workspace.Map.Island:FindFirstChild("EggHolders")
    if not holders then return nil end
    local holder = holders:FindFirstChild(tostring(idx))
    if not holder then return nil end
    return holder:FindFirstChild("Part")
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

-- shopName: "Main" (dice) or "Potion"
local function getRestockSeconds(shopName)
    local ok, label = pcall(function()
        return player.PlayerGui.Main.Canvas.MapShops[shopName].Holder.Timer.TextLabel
    end)
    if not ok or not label then return nil end
    local min, sec = label.Text:match("(%d+):(%d+)")
    if not min or not sec then return nil end
    return tonumber(min) * 60 + tonumber(sec)
end

local function getInventoryCount()
    local ok, counter = pcall(function()
        return player.PlayerGui.Main.Canvas.Inventory.MainFrame.Counter
    end)
    if not ok or not counter then return 0 end
    local current = counter.Text:match("(%d+)/")
    return tonumber(current) or 0
end

-- Reads the Potions inventory GUI for potions you actually own (count > 0).
-- NOTE: this path hasn't been confirmed live yet — if it prints nothing found
-- while you do own potions, the structure differs and we'll need to dump it
-- like we did for Merchant/FoodCart.
local function getOwnedPotions()
    local owned = {}
    local ok, holder = pcall(function()
        return player.PlayerGui.Main.Canvas.Potions.Holder.Holder
    end)
    if not ok or not holder then
        warn("[UsePotions] Could not find Potions inventory GUI at the expected path")
        return owned
    end

    for _, entry in ipairs(holder:GetChildren()) do
        local nameLabel = entry:FindFirstChild("NameLabel")
        local ownedLabel = entry:FindFirstChild("OwnedLabel")
        if nameLabel and ownedLabel then
            local count = tonumber(ownedLabel.Text:match("(%d+)"))
            if count and count > 0 then
                table.insert(owned, nameLabel.Text)
            end
        end
    end
    return owned
end

-- ================= Buy actions =================

local function buyDice()
    local part = getMapShopPart("Shop")
    if not part then
        warn("Dice shop model not found")
        return
    end
    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function()
            BuyDice:FireServer("BuyBestAvailable")
        end)
        task.wait(BUY_FIRE_INTERVAL)
        elapsed += BUY_FIRE_INTERVAL
    end
    print("[Dice] Bought")
end

local function buyPotion()
    local part = getMapShopPart("PotionShop")
    if not part then
        warn("Potion shop model not found")
        return
    end
    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function()
            BuyPotion:FireServer("BuyBestAvailable")
        end)
        task.wait(BUY_FIRE_INTERVAL)
        elapsed += BUY_FIRE_INTERVAL
    end
    print("[Potion] Bought")
end

local function getFoodCartModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    return mapShop and mapShop:FindFirstChild("FoodCart")
end

local function buyFoodCart()
    local cart = getFoodCartModel()
    if not cart then return end
    local part = cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    if not getFoodCartModel() then
        warn("[FoodCart] Despawned before buying")
        return
    end

    for _, item in ipairs(FOOD_ORDER) do
        pcall(function()
            FoodCartRemote:FireServer("BuyAll", item)
        end)
        task.wait(0.15)
    end
    print("[FoodCart] Done")
end

local function getMerchantModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    return mapShop and mapShop:FindFirstChild("Merchant")
end

local function buyMerchant()
    local model = getMerchantModel()
    if not model then return end
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    if not getMerchantModel() then
        warn("[Merchant] Despawned before buying")
        return
    end

    for _, cat in ipairs(MERCHANT_CATEGORIES) do
        for _, itemName in ipairs(cat.items) do
            pcall(function()
                MerchantRemote:FireServer("BuyAll", cat.name, itemName)
            end)
            task.wait(0.12)
        end
    end
    print("[Merchant] Done")
end

local function openEgg()
    local part = getEggPart(state.selectedEgg)
    if not part then
        warn("Egg holder not found for", state.selectedEgg)
        return
    end
    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function()
            EggInfo:InvokeServer("Buy", state.selectedEgg, state.eggQuantity)
        end)
        task.wait(BUY_FIRE_INTERVAL)
        elapsed += BUY_FIRE_INTERVAL
    end
end

local function sellInventory()
    local part = getMapShopPart("SellShop")
    if not part then
        warn("[Sell] SellShop model not found")
        return
    end
    teleportTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)

    pcall(function()
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview")
    end)
    task.wait(1.5)
    pcall(function()
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit")
    end)
    print("[Sell] Done")
end

-- ================= Priority scheduler =================
-- Merchant > Sell > FoodCart > Dice > Potion > Eggs. Sell's slot is a guess
-- since it wasn't specified — say the word if you want it reordered.
-- Only one of these moves the character at a time; each pass does at most one
-- action, then re-checks from the top so a higher-priority item can interrupt.
local lastMerchant, lastFoodCart = nil, nil
local nextDiceTime, nextPotionTime = 0, 0

task.spawn(function()
    while true do
        local didSomething = false

        local merchant = state.merchant and getMerchantModel()
        local foodcart = state.foodcart and getFoodCartModel()
        local sellReady = state.sell and getInventoryCount() >= state.sellThreshold

        if merchant and merchant ~= lastMerchant then
            lastMerchant = merchant
            buyMerchant()
            didSomething = true
        elseif sellReady then
            sellInventory()
            task.wait(SELL_COOLDOWN)
            didSomething = true
        elseif foodcart and foodcart ~= lastFoodCart then
            lastFoodCart = foodcart
            buyFoodCart()
            didSomething = true
        elseif state.dice and tick() >= nextDiceTime then
            buyDice()
            local restockWait = getRestockSeconds("Main")
            nextDiceTime = tick() + (restockWait and (restockWait + RESTOCK_BUFFER) or FALLBACK_RESTOCK_WAIT)
            didSomething = true
        elseif state.potion and tick() >= nextPotionTime then
            buyPotion()
            local restockWait = getRestockSeconds("Potion")
            nextPotionTime = tick() + (restockWait and (restockWait + RESTOCK_BUFFER) or FALLBACK_RESTOCK_WAIT)
            didSomething = true
        elseif state.egg then
            openEgg()
            didSomething = true
        end

        if not merchant then lastMerchant = nil end
        if not foodcart then lastFoodCart = nil end

        if not didSomething then
            task.wait(SCHEDULER_INTERVAL)
        end
    end
end)

-- ================= Independent background features =================
-- These don't move the character, so they run on their own without
-- competing with the priority scheduler above.

-- Auto Collect Money
local function getCollectorParts()
    local plot = getMyPlotModel()
    if not plot then return {} end
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

task.spawn(function()
    while true do
        if state.collect then
            local ok, hrp = pcall(getHRP)
            if ok then
                local collectors = getCollectorParts()
                for _, c in ipairs(collectors) do
                    pcall(function() firetouchinterest(c, hrp, 0) end)
                end
                task.wait(0.1)
                for _, c in ipairs(collectors) do
                    pcall(function() firetouchinterest(c, hrp, 1) end)
                end
            end
        end
        task.wait(COLLECT_INTERVAL)
    end
end)

-- Auto Use Potions — only fires for potions you actually own
task.spawn(function()
    while true do
        if state.usePotions then
            local owned = getOwnedPotions()
            for _, potionName in ipairs(owned) do
                pcall(function()
                    UsePotion:FireServer("Use", potionName, "Max")
                end)
                task.wait(0.12)
            end
        end
        task.wait(USE_POTIONS_INTERVAL)
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
        if state.rebirth then
            local ok, ready = pcall(isRebirthReady)
            if ok and ready then
                RebirthRemote:FireServer()
                print("[Rebirth] Fired")
                task.wait(REBIRTH_COOLDOWN)
            end
        end
        task.wait(REBIRTH_CHECK_INTERVAL)
    end
end)

-- Anti-AFK, always on
local VirtualUser = game:GetService("VirtualUser")
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ================= UI =================
local Window = Rayfield:CreateWindow({
    name = "AutoFarm",
    subtitle = "buns",
    configuration = {
        enabled = true,
    },
})

local MainTab = Window:CreateTab({ name = "Main", icon = 0 })

MainTab:CreateToggle({
    Name = "Auto Buy Merchant",
    CurrentValue = false,
    Flag = "AutoMerchant",
    Callback = function(v) state.merchant = v end,
})

MainTab:CreateToggle({
    Name = "Auto Buy FoodCart",
    CurrentValue = false,
    Flag = "AutoFoodCart",
    Callback = function(v) state.foodcart = v end,
})

MainTab:CreateToggle({
    Name = "Auto Buy Dice",
    CurrentValue = false,
    Flag = "AutoDice",
    Callback = function(v) state.dice = v end,
})

MainTab:CreateToggle({
    Name = "Auto Buy Potions",
    CurrentValue = false,
    Flag = "AutoPotion",
    Callback = function(v) state.potion = v end,
})

MainTab:CreateToggle({
    Name = "Auto Use Potions",
    CurrentValue = false,
    Flag = "AutoUsePotions",
    Callback = function(v) state.usePotions = v end,
})

MainTab:CreateToggle({
    Name = "Auto Collect Money",
    CurrentValue = false,
    Flag = "AutoCollect",
    Callback = function(v) state.collect = v end,
})

MainTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirth",
    Callback = function(v) state.rebirth = v end,
})

MainTab:CreateToggle({
    Name = "Auto Sell",
    CurrentValue = false,
    Flag = "AutoSell",
    Callback = function(v) state.sell = v end,
})

MainTab:CreateSlider({
    Name = "Sell Threshold",
    Range = {1, 100},
    Increment = 1,
    Suffix = "items",
    CurrentValue = 30,
    Flag = "SellThreshold",
    Callback = function(v) state.sellThreshold = v end,
})

local EggTab = Window:CreateTab({ name = "Eggs", icon = 0 })

EggTab:CreateDropdown({
    Name = "Egg Type",
    Options = EGG_NAMES,
    CurrentOption = {"Basic"},
    MultipleOptions = false,
    Flag = "EggType",
    Callback = function(option)
        state.selectedEgg = type(option) == "table" and option[1] or option
    end,
})

EggTab:CreateSlider({
    Name = "Egg Quantity",
    Range = {1, 10},
    Increment = 1,
    Suffix = "eggs",
    CurrentValue = 3,
    Flag = "EggQuantity",
    Callback = function(v) state.eggQuantity = v end,
})

EggTab:CreateToggle({
    Name = "Auto Egg",
    CurrentValue = false,
    Flag = "AutoEgg",
    Callback = function(v) state.egg = v end,
})

print("AutoFarm loaded.")
