-- ===== Auto Dice + Auto Potion + EquipBest + Auto Sell + Auto Rebirth + FoodCart + Merchant + Auto Eggs =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

-- ===== Anti AFK =====
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")
local EquipBest = remotes:WaitForChild("EquipBest")
local UsePotion = remotes:WaitForChild("UsePotion")
local Dialogue = remotes:WaitForChild("Dialogue")
local RebirthRemote = remotes:WaitForChild("Rebirth")
local FoodCartRemote = remotes:WaitForChild("FoodCart")
local MerchantRemote = remotes:WaitForChild("Merchant")
local EggInfo = remotes:WaitForChild("EggInfo")

-- Shop / sell / egg positions
local DICE_SHOP = CFrame.new(179.709259, 4.53835154, -144.103485, 0.909164608, -2.76407324e-08, -0.41643694, -1.1623088e-09, 1, -6.8911902e-08, 0.41643694, 6.31362909e-08, 0.909164608)
local POTION_SHOP = CFrame.new(153.449585, 4.03330231, -138.129669, 0.814049244, 6.003647e-08, 0.580795884, -6.18439913e-08, 1, -1.66881726e-08, -0.580795884, -2.23337384e-08, 0.814049244)
local SELL_CFRAME = CFrame.new(185.339233, 3.67208314, -117.684746, 0.0844980627, 5.13176062e-08, -0.996423662, -1.29543869e-08, 1, 5.04032442e-08, 0.996423662, 8.64908056e-09, 0.0844980627)
local EGG_CFRAME = CFrame.new(-198.375092, 3.67208314, 168.48439, -0.455900133, 5.02545072e-09, 0.890030921, 1.24778738e-08, 1, 7.45158324e-10, -0.890030921, 1.14454117e-08, -0.455900133)

local enabled = false
local WAIT_AFTER_BUY = 120 -- fallback if a timer label can't be read
local RESTOCK_BUFFER = 2 -- extra seconds after "0:00" to make sure server has actually restocked
local SELL_THRESHOLD = 30
local SELL_CHECK_INTERVAL = 5 -- seconds
local EQUIP_INTERVAL = 300 -- 5 minutes between equip sessions
local EQUIP_SESSION_DURATION = 20 -- stay at plot for this many seconds
local EQUIP_SPAM_DELAY = 5 -- equip best every N seconds while at plot
local EQUIP_BEFORE_SELL_COUNT = 3 -- how many times to equip before selling
local REBIRTH_CHECK_INTERVAL = 2 -- seconds
local REBIRTH_COOLDOWN = 5 -- seconds, let GUI/state settle after rebirthing
local NPC_CHECK_INTERVAL = 3 -- seconds, for FoodCart/Merchant existence polling
local EGG_SPAM_DELAY = 0.15 -- delay between egg opens

local FOODCART_ITEMS = {
    "Apple",
    "Potato",
    "Loaf",
    "Fish",
    "Steak",
}

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
-- Dice/potion/sell/rebirth/foodcart/merchant/equip all teleport the character.
-- Only one action may move the player at a time, or loops will fight over CFrame.
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

local function goToEggs(hrp)
    hrp.CFrame = EGG_CFRAME
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

-- ===== Auto Eggs (spam while idle at egg location) =====
task.spawn(function()
    while true do
        if enabled and not actionLock then
            pcall(function()
                EggInfo:InvokeServer("Buy", "Frozen", 3)
            end)
        end
        task.wait(EGG_SPAM_DELAY)
    end
end)

-- ===== Auto Dice =====
local function buyDice()
    withLock(function()
        local hrp = getHRP()
        hrp.CFrame = DICE_SHOP
        task.wait(1.35)
        BuyDice:FireServer("BuyBestAvailable")
        task.wait(1.3)
        goToEggs(hrp)
        print("Bought dice → eggs")
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
        task.wait(1.35)
        BuyPotion:FireServer("BuyBestAvailable")
        task.wait(1.3)
        goToEggs(hrp)
        task.wait(1.5)
        useAllPotions()
        print("Bought potion → eggs")
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

-- Spam EquipBest at plot for a duration (every EQUIP_SPAM_DELAY seconds)
local function equipAtPlot(duration)
    local hrp = getHRP()
    returnToPlot(hrp)
    task.wait(0.4)

    local elapsed = 0
    local count = 0
    while elapsed < duration and enabled do
        pcall(function()
            EquipBest:FireServer()
        end)
        count += 1
        print(("Equipped best (%d)"):format(count))
        task.wait(EQUIP_SPAM_DELAY)
        elapsed += EQUIP_SPAM_DELAY
    end
end

-- ===== Auto Equip (every 5 min — stay at plot 20s, equip every 5s, then back to eggs) =====
task.spawn(function()
    while true do
        if enabled then
            withLock(function()
                equipAtPlot(EQUIP_SESSION_DURATION)
                local hrp = getHRP()
                goToEggs(hrp)
                print("Equip session done → eggs")
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

        -- Equip a few times at plot first
        returnToPlot(hrp)
        task.wait(0.4)
        for i = 1, EQUIP_BEFORE_SELL_COUNT do
            pcall(function()
                EquipBest:FireServer()
            end)
            print(("Pre-sell equip %d/%d"):format(i, EQUIP_BEFORE_SELL_COUNT))
            task.wait(EQUIP_SPAM_DELAY)
        end

        -- Then go sell
        hrp.CFrame = SELL_CFRAME
        task.wait(0.4)
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview")
        task.wait(1.5)
        Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit")
        print("Sold inventory → eggs")
        task.wait(0.3)
        goToEggs(hrp)
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
                    -- after rebirth, go back to eggs
                    local hrp = getHRP()
                    goToEggs(hrp)
                end)
            end
        end
        task.wait(REBIRTH_CHECK_INTERVAL)
    end
end)

-- ===== Auto FoodCart =====
local function getFoodCartModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    if not mapShop then return nil end
    return mapShop:FindFirstChild("FoodCart")
end

local function buyFoodCart()
    withLock(function()
        local cart = getFoodCartModel()
        if not cart then
            warn("FoodCart not found (probably despawned)")
            return
        end
        local part = cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart", true)
        if not part then
            warn("No BasePart on FoodCart model")
            return
        end

        local hrp = getHRP()
        hrp.CFrame = part.CFrame
        task.wait(0.5)

        for _, item in ipairs(FOODCART_ITEMS) do
            pcall(function()
                FoodCartRemote:FireServer("BuyAll", item)
            end)
            task.wait(0.2)
        end

        print("Bought all FoodCart items → eggs")
        task.wait(0.3)
        goToEggs(hrp)
    end)
end

local lastFoodCart = nil
task.spawn(function()
    while true do
        if enabled then
            local cart = getFoodCartModel()
            if cart and cart ~= lastFoodCart then
                lastFoodCart = cart
                buyFoodCart()
            elseif not cart then
                lastFoodCart = nil
            end
        end
        task.wait(NPC_CHECK_INTERVAL)
    end
end)

-- ===== Auto Merchant =====
local function getMerchantModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    if not mapShop then return nil end
    return mapShop:FindFirstChild("Merchant")
end

local function findProximityPrompt(model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then
            return inst
        end
    end
    return nil
end

local function buyAllFromMerchant()
    withLock(function()
        local model = getMerchantModel()
        if not model then
            warn("Merchant not found (probably despawned)")
            return
        end

        local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if not part then
            warn("No BasePart on Merchant model")
            return
        end

        local hrp = getHRP()
        hrp.CFrame = part.CFrame
        task.wait(0.3)

        local prompt = findProximityPrompt(model)
        if prompt then
            pcall(function()
                fireproximityprompt(prompt)
            end)
        end
        task.wait(0.5) -- let the GUI populate

        local holder = player.PlayerGui.Main.Canvas.Merchant.Main.Holder
        local children = holder:GetChildren()
        table.sort(children, function(a, b)
            local aOrder = (pcall(function() return a.LayoutOrder end)) and a.LayoutOrder or 0
            local bOrder = (pcall(function() return b.LayoutOrder end)) and b.LayoutOrder or 0
            return aOrder < bOrder
        end)

        local currentCategory = nil
        local bought = 0

        for _, entry in ipairs(children) do
            local nameLabel = entry:FindFirstChild("NameLabel")
            if entry.Name == "TextPlaceHolder" and nameLabel then
                currentCategory = nameLabel.Text
            elseif entry.Name:find("Template") then
                -- skip clone-source templates, never real stock
            elseif entry:IsA("Frame") or entry:IsA("ImageButton") or entry:IsA("TextButton") or entry:IsA("CanvasGroup") then
                local itemNameLabel = entry:FindFirstChild("DiceName") or entry:FindFirstChild("FoodName")
                local stockLabel = entry:FindFirstChild("Stock")

                if itemNameLabel and currentCategory then
                    local stockText = stockLabel and stockLabel.Text or ""
                    if stockText ~= "Sold out" and stockText ~= "" then
                        local itemName = itemNameLabel.Text
                        pcall(function()
                            MerchantRemote:FireServer("BuyAll", currentCategory, itemName)
                        end)
                        print(("Bought %s (%s)"):format(itemName, currentCategory))
                        bought += 1
                        task.wait(0.2)
                    end
                end
            end
        end

        print(("Done — bought %d item(s) from Merchant → eggs"):format(bought))
        goToEggs(hrp)
    end)
end

local lastMerchant = nil
task.spawn(function()
    while true do
        if enabled then
            local merchant = getMerchantModel()
            if merchant and merchant ~= lastMerchant then
                lastMerchant = merchant
                buyAllFromMerchant()
            elseif not merchant then
                lastMerchant = nil
            end
        end
        task.wait(NPC_CHECK_INTERVAL)
    end
end)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        if enabled then
            -- on enable, go straight to eggs
            task.spawn(function()
                withLock(function()
                    local hrp = getHRP()
                    goToEggs(hrp)
                end)
            end)
        end
        print(enabled and "✅ Auto Farm: ON (eggs + shops)" or "❌ Auto Farm: OFF")
    end
end)

print("Full script loaded. Press B to toggle Auto Farm")
print("Eggs spam | Equip session every 5 min (20s at plot, equip every 5s) | Pre-sell equip x3 at plot")
