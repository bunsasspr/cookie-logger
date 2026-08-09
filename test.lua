-- ================= AutoFarm — Fluent Modded rework + Fusion =================
local Fluent = loadstring(game:HttpGet(
    "https://github.com/StyearX/Fluent-Modded/releases/download/Fluent/FluentPro"
))()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")

local BuyDice = remotes:WaitForChild("BuyDice")
local BuyPotion = remotes:WaitForChild("BuyPotion")
local UsePotion = remotes:WaitForChild("UsePotion")
local EquipBest = remotes:FindFirstChild("EquipBest") or remotes:WaitForChild("EquipBest")
local RebirthRemote = remotes:WaitForChild("Rebirth")
local FoodCartRemote = remotes:WaitForChild("FoodCart")
local MerchantRemote = remotes:WaitForChild("Merchant")
local EggInfo = remotes:WaitForChild("EggInfo")
local Dialogue = remotes:WaitForChild("Dialogue")
local PotionUpdater = remotes:FindFirstChild("PotionUpdater")

-- ===== Config =====
local BUY_STAND_DURATION = 2
local BUY_FIRE_INTERVAL = 0.5
local TELEPORT_SETTLE_DELAY = 0.5
local SCHEDULER_INTERVAL = 1
local RESTOCK_BUFFER = 2
local FALLBACK_RESTOCK_WAIT = 120
local EQUIP_BEST_SETTLE = 0.5
local USE_POTIONS_INTERVAL = 10
local REBIRTH_CHECK_INTERVAL = 2
local REBIRTH_COOLDOWN = 5
local SELL_COOLDOWN = 3

-- Fusion config
local FUSION_CHECK_INTERVAL = 4
local FUSION_WAIT_INTERVAL = 1
local FUSION_MAX_WAIT = 300
local AFTER_CLAIM_COOLDOWN = 2.5
local FUSE_MACHINE_CFRAME = CFrame.new(-104.240242, 1.77263951 + 5, 198.388123)

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

local EGG_HOLDER_INDEX = {
    Basic = 1, Forest = 2, Jungle = 3, Beach = 4, Monster = 5,
    Desert = 6, Galaxy = 7, Candy = 8, Lava = 9, Frozen = 10,
}
local EGG_NAMES = {"Basic", "Forest", "Jungle", "Beach", "Monster", "Desert", "Galaxy", "Candy", "Lava", "Frozen"}

-- ===== Feature state =====
local state = {
    dice = false, potion = false, merchant = false, foodcart = false,
    usePotions = false, egg = false, eggQuantity = 3,
    rebirth = false, equipBest = false, sell = false, sellThreshold = 30,
    selectedEgg = "Basic",
    autoCraftGolden = false,
    autoCraftDiamond = false,
}

-- ===== Helpers =====
local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- ================= Pinning system =================
local pinned = false
local pinTarget = nil

local function pinTo(cframe)
    pinTarget = cframe
    pinned = true
end

local function unpin()
    pinned = false
    pinTarget = nil
end

RunService.Heartbeat:Connect(function()
    if pinned and pinTarget then
        local ok, hrp = pcall(getHRP)
        if ok then
            hrp.CFrame = pinTarget
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

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

local function getPlotCFrame()
    local plot = getMyPlotModel()
    if not plot then return nil end
    local part = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame + Vector3.new(0, 3, 0) end
    local spawn = plot:FindFirstChild("Spawn")
    if spawn and spawn:IsA("BasePart") then return spawn.CFrame end
    return nil
end

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

-- PotionUpdater
local ownedPotionCounts = {}
if PotionUpdater then
    PotionUpdater.OnClientEvent:Connect(function(event, data)
        if event == "Update" and type(data) == "table" then
            for name, info in pairs(data) do
                if type(info) == "table" and info.Owned ~= nil then
                    ownedPotionCounts[name] = tonumber(info.Owned) or 0
                elseif type(info) == "number" then
                    ownedPotionCounts[name] = info
                end
            end
        end
    end)
    pcall(function() PotionUpdater:FireServer("Request") end)
end

local function getOwnedPotions()
    local owned = {}
    for name, count in pairs(ownedPotionCounts) do
        if count > 0 then table.insert(owned, name) end
    end
    if #owned > 0 then return owned end
    local ok, holder = pcall(function()
        return player.PlayerGui.Main.Canvas.Potions.Holder.Holder
    end)
    if ok and holder then
        for _, entry in ipairs(holder:GetChildren()) do
            local nameLabel = entry:FindFirstChild("NameLabel")
            local ownedLabel = entry:FindFirstChild("OwnedLabel")
            if nameLabel and ownedLabel then
                local count = tonumber(ownedLabel.Text:match("(%d+)"))
                if count and count > 0 then table.insert(owned, nameLabel.Text) end
            end
        end
    end
    return owned
end

-- ================= Buy actions =================
local function buyDice()
    local part = getMapShopPart("Shop")
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function() BuyDice:FireServer("BuyBestAvailable") end)
        task.wait(BUY_FIRE_INTERVAL); elapsed = elapsed + BUY_FIRE_INTERVAL
    end
    unpin()
end

local function buyPotion()
    local part = getMapShopPart("PotionShop")
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function() BuyPotion:FireServer("BuyBestAvailable") end)
        task.wait(BUY_FIRE_INTERVAL); elapsed = elapsed + BUY_FIRE_INTERVAL
    end
    unpin()
end

local function getFoodCartModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    return mapShop and mapShop:FindFirstChild("FoodCart")
end

local function buyFoodCart()
    local cart = getFoodCartModel(); if not cart then return end
    local part = cart.PrimaryPart or cart:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    if not getFoodCartModel() then unpin(); return end
    for _, item in ipairs(FOOD_ORDER) do
        pcall(function() FoodCartRemote:FireServer("BuyAll", item) end)
        task.wait(0.15)
    end
    unpin()
end

local function getMerchantModel()
    local mapShop = workspace.Map:FindFirstChild("MapShop")
    return mapShop and mapShop:FindFirstChild("Merchant")
end

local function buyMerchant()
    local model = getMerchantModel(); if not model then return end
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    if not getMerchantModel() then unpin(); return end
    for _, cat in ipairs(MERCHANT_CATEGORIES) do
        for _, itemName in ipairs(cat.items) do
            pcall(function() MerchantRemote:FireServer("BuyAll", cat.name, itemName) end)
            task.wait(0.12)
        end
    end
    unpin()
end

local function openEgg()
    local part = getEggPart(state.selectedEgg)
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    local elapsed = 0
    while elapsed < BUY_STAND_DURATION do
        pcall(function() EggInfo:InvokeServer("Buy", state.selectedEgg, state.eggQuantity) end)
        task.wait(BUY_FIRE_INTERVAL); elapsed = elapsed + BUY_FIRE_INTERVAL
    end
    unpin()
end

local function equipBest()
    local cf = getPlotCFrame()
    if not cf then warn("[EquipBest] Could not find your plot"); return end
    pinTo(cf)
    task.wait(TELEPORT_SETTLE_DELAY)
    pcall(function() EquipBest:FireServer() end)
    task.wait(EQUIP_BEST_SETTLE)
    unpin()
end

task.spawn(function()
    while true do
        if state.usePotions then
            local owned = getOwnedPotions()
            for _, name in ipairs(owned) do
                pcall(function() UsePotion:FireServer("Use", name, "Max") end)
                task.wait(0.12)
            end
        end
        task.wait(USE_POTIONS_INTERVAL)
    end
end)

local function sellInventory()
    if state.equipBest then
        equipBest()
    end
    local part = getMapShopPart("SellShop")
    if not part then return end
    pinTo(part.CFrame)
    task.wait(TELEPORT_SETTLE_DELAY)
    pcall(function() Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "preview") end)
    task.wait(1.5)
    pcall(function() Dialogue:InvokeServer("SellNpc", 1, "I want to sell my inventory", "commit") end)
    unpin()
end

-- ================= FUSION SYSTEM (fixed) =================
local lastClaimedJobId = nil
local pendingFusion = nil          -- {JobId = ..., Mode = ...}
local fusionActionBusy = false

local function getPlayerState()
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("State")
    end)
    return ok and result or nil
end

local function getFusionState()
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("GetFusionState")
    end)
    return ok and result or nil
end

local function fusePets(petIds, mode)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("Fuse", {
            PetIds = petIds,
            Mode = mode,
        })
    end)
    if not ok then
        warn("[Fusion] Fuse call error:", result)
        return nil
    end
    return result
end

local function claimFusion(jobId, outcome)
    if not jobId or jobId == lastClaimedJobId then return nil end

    print("[Fusion] Claiming JobId:", jobId, "Outcome:", outcome or "?")

    local result

    -- Try the correct remote based on outcome
    if outcome == "Failed" then
        -- Failed fusions use AcknowledgeFusion
        local ok, res = pcall(function()
            return EggInfo:InvokeServer("AcknowledgeFusion", {
                JobId = jobId,
            })
        end)
        if ok then result = res end
        print("[Fusion] AcknowledgeFusion →", result and result.Success, result and result.Reason)
    else
        -- Successful fusions use ClaimFusion
        local ok, res = pcall(function()
            return EggInfo:InvokeServer("ClaimFusion", {
                JobId = jobId,
            })
        end)
        if ok then result = res end
        print("[Fusion] ClaimFusion →", result and result.Success, result and result.Reason)
    end

    -- Fallback: if the first one failed, try the other
    if not result or result.Success == false then
        print("[Fusion] First claim method failed, trying fallback...")
        local ok2, res2 = pcall(function()
            if outcome == "Failed" then
                return EggInfo:InvokeServer("ClaimFusion", { JobId = jobId })
            else
                return EggInfo:InvokeServer("AcknowledgeFusion", { JobId = jobId })
            end
        end)
        if ok2 and res2 then
            result = res2
            print("[Fusion] Fallback result →", result.Success, result.Reason)
        end
    end

    -- Always mark as handled so we don't loop forever
    lastClaimedJobId = jobId
    return result
end

local function findFusableGroups(playerState, minCount, variantFilter)
    minCount = minCount or 6
    local groups = {}
    local pets = playerState and playerState.Pets
    if not pets then return {} end

    for _, pet in pairs(pets) do
        if type(pet) == "table" and pet.Name and pet.Id then
            if not variantFilter or pet.Variant == variantFilter then
                local name = pet.Name
                if not groups[name] then
                    groups[name] = { name = name, ids = {}, count = 0 }
                end
                table.insert(groups[name].ids, pet.Id)
                groups[name].count = groups[name].count + 1
            end
        end
    end

    local fusable = {}
    for _, group in pairs(groups) do
        if group.count >= minCount then
            table.insert(fusable, group)
        end
    end
    table.sort(fusable, function(a, b) return a.count > b.count end)
    return fusable
end

local function teleportToFuseMachine()
    local part = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("Island")
        and workspace.Map.Island:FindFirstChild("FuseMachine")
        and workspace.Map.Island.FuseMachine:FindFirstChild("Machine")
        and workspace.Map.Island.FuseMachine.Machine:FindFirstChild("Machine Plinth")

    if part and part:IsA("BasePart") then
        pinTo(part.CFrame + Vector3.new(0, 5, 0))
    else
        pinTo(FUSE_MACHINE_CFRAME)
    end
    task.wait(TELEPORT_SETTLE_DELAY)
end

-- Returns true if there is already an active fusion we should wait for / claim
local function syncExistingFusion()
    local fs = getFusionState()
    if not fs or not fs.Fusion then return false end

    local fusion = fs.Fusion
    if not fusion.Active or not fusion.JobId then return false end
    if fusion.JobId == lastClaimedJobId then return false end

    -- There is already a fusion running or ready → treat it as pending
    if not pendingFusion or pendingFusion.JobId ~= fusion.JobId then
        pendingFusion = {
            JobId = fusion.JobId,
            Mode = fusion.Mode or "Golden",
        }
        print("[Fusion] Detected existing fusion → JobId:", pendingFusion.JobId,
              "Ready:", fusion.Ready, "Remaining:", fusion.Remaining)
    end
    return true
end

-- Starts a new fuse (only if nothing is already running)
local function startFuse(variantFilter, mode)
    if fusionActionBusy then return false end

    -- If a fusion is already in progress, just sync it and return
    if syncExistingFusion() then
        return false
    end

    local playerState = getPlayerState()
    if not playerState then return false end

    local groups = findFusableGroups(playerState, 6, variantFilter)
    if #groups == 0 then return false end

    local group = groups[1]
    print("[Fusion] Found", group.count, variantFilter, group.name, "→", mode)

    fusionActionBusy = true

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    teleportToFuseMachine()
    local fuseResult = fusePets(petIds, mode)

    if fuseResult then
        if fuseResult.Success == false and fuseResult.Reason == "FusionInProgress" then
            -- Server already has a fusion → sync it
            print("[Fusion] Server said FusionInProgress → syncing...")
            syncExistingFusion()
        elseif fuseResult.Success ~= false then
            -- New fusion started successfully
            task.wait(0.3)
            local fs = getFusionState()
            if fs and fs.Fusion and fs.Fusion.JobId then
                pendingFusion = {
                    JobId = fs.Fusion.JobId,
                    Mode = mode,
                }
                print("[Fusion] Fuse started → JobId:", pendingFusion.JobId, "— resuming farm")
            end
        else
            print("[Fusion] Fuse failed → Success:", fuseResult.Success, "Reason:", fuseResult.Reason)
        end
    end

    unpin()
    fusionActionBusy = false
    return true
end

-- Background watcher: claims when ready (success OR fail), then tries next fuse
task.spawn(function()
    while true do
        task.wait(1.2)

        if fusionActionBusy then
            continue
        end

        -- Always keep pendingFusion in sync with server
        syncExistingFusion()

        if not pendingFusion then
            continue
        end

        local fs = getFusionState()
        if not fs or not fs.Fusion then
            pendingFusion = nil
            continue
        end

        local fusion = fs.Fusion
        local jobId = fusion.JobId

        if not jobId or jobId == lastClaimedJobId then
            pendingFusion = nil
            continue
        end

        local ready = fusion.Ready
            or (fusion.Remaining and fusion.Remaining <= 0)
            or (fusion.Outcome == "Succeeded" or fusion.Outcome == "Failed")

        if ready then
            print("[Fusion] Timer finished (Outcome:", fusion.Outcome or "?", ") → claiming...")

            fusionActionBusy = true
            teleportToFuseMachine()
            claimFusion(jobId)
            task.wait(AFTER_CLAIM_COOLDOWN)
            unpin()

            pendingFusion = nil
            fusionActionBusy = false

            -- After claim, immediately try to start another fuse if possible
            if state.autoCraftGolden then
                startFuse("Normal", "Golden")
            end
            if not pendingFusion and state.autoCraftDiamond then
                startFuse("Golden", "Diamond")
            end
        elseif not fusion.Active then
            pendingFusion = nil
        end
    end
end)

-- Auto Rebirth
local function isRebirthReady()
    local ok, btn = pcall(function() return player.PlayerGui.Main.Canvas.Rebirth.MainFrame.Rebirth end)
    if not ok or not btn then return false end
    local color = btn.BackgroundColor3
    return color.G > color.R
end

task.spawn(function()
    while true do
        if state.rebirth then
            local ok, ready = pcall(isRebirthReady)
            if ok and ready then
                RebirthRemote:FireServer(); print("[Rebirth] Fired")
                task.wait(REBIRTH_COOLDOWN)
            end
        end
        task.wait(REBIRTH_CHECK_INTERVAL)
    end
end)

local VirtualUser = game:GetService("VirtualUser")
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ================= UI — Fluent Modded =================
local Window = Fluent:CreateWindow({
    Title       = "Buns hub",
    SubTitle    = "Kawaii Anime Rng",
    TabWidth    = 150,
    Size        = UDim2.fromOffset(520, 480),
    Acrylic     = true,
    Theme       = "Cyanic",
    MinimizeKey = Enum.KeyCode.LeftControl,
    Search      = true,
})

-- ============ Main Tab ============
local MainTab = Window:AddTab({ Title = "Main", Icon = "solar/home-bold" })

MainTab:AddToggle("AutoUsePotions", {
    Title = "Auto Use Potions", Default = false,
    Callback = function(v) state.usePotions = v end,
})
MainTab:AddToggle("AutoRebirth", {
    Title = "Auto Rebirth", Default = false,
    Callback = function(v) state.rebirth = v end,
})
MainTab:AddToggle("AutoEquipBest", {
    Title = "Auto Equip Best", Default = false,
    Callback = function(v) state.equipBest = v end,
})
MainTab:AddToggle("AutoSell", {
    Title = "Auto Sell", Default = false,
    Callback = function(v) state.sell = v end,
})
MainTab:AddSlider("SellThreshold", {
    Title = "Sell Threshold", Default = 30, Min = 1, Max = 100, Rounding = 1,
    Callback = function(v) state.sellThreshold = tonumber(v) or 30 end,
})

-- ============ Shop Tab ============
local ShopTab = Window:AddTab({ Title = "Shop", Icon = "solar/cart-large-2-bold" })

ShopTab:AddToggle("AutoDice", {
    Title = "Auto Buy Dice", Default = false,
    Callback = function(v) state.dice = v end,
})
ShopTab:AddToggle("AutoPotion", {
    Title = "Auto Buy Potions", Default = false,
    Callback = function(v) state.potion = v end,
})
ShopTab:AddToggle("AutoMerchant", {
    Title = "Auto Merchant", Default = false,
    Callback = function(v) state.merchant = v end,
})
ShopTab:AddToggle("AutoFoodCart", {
    Title = "Auto FoodCart", Default = false,
    Callback = function(v) state.foodcart = v end,
})

-- ============ Eggs Tab ============
local EggTab = Window:AddTab({ Title = "Eggs", Icon = "solar/database-bold" })

EggTab:AddDropdown("EggType", {
    Title = "Egg Type", Values = EGG_NAMES, Default = "Basic", Multi = false,
    Callback = function(v) state.selectedEgg = v end,
})
EggTab:AddDropdown("EggQuantity", {
    Title = "Egg Quantity", Values = {"1", "2", "3", "4", "5"}, Default = "3", Multi = false,
    Callback = function(v) state.eggQuantity = tonumber(v) or 3 end,
})
EggTab:AddToggle("AutoEgg", {
    Title = "Auto Egg", Default = false,
    Callback = function(v) state.egg = v end,
})

-- NEW FUSION TOGGLES
EggTab:AddToggle("AutoCraftGolden", {
    Title = "Auto Craft Golden", Default = false,
    Callback = function(v) state.autoCraftGolden = v end,
})
EggTab:AddToggle("AutoCraftDiamond", {
    Title = "Auto Craft Diamond", Default = false,
    Callback = function(v) state.autoCraftDiamond = v end,
})

-- ============ Settings Tab ============
local SettingsTab = Window:AddTab({ Title = "Settings", Icon = "solar/settings-bold" })

local SaveManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/StyearX/Fluent-modded/main/Addons/SaveManager.lua"
))()
local InterfaceManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/StyearX/Fluent-modded/main/Addons/InterfaceManager.lua"
))()

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

InterfaceManager:SetFolder("BunsHub")
SaveManager:SetFolder("BunsHub/Config")

InterfaceManager.Settings = {
    Theme       = "Cyanic",
    Acrylic     = true,
    Transparency = true,
    DisableBG   = false,
    Favorites   = {},
    Animated    = true,
    MenuKeybind = "LeftControl",
    Font        = "SourceSans",
}

pcall(function()
    InterfaceManager:SaveSettings()
    Fluent:SetTheme("Cyanic")
    InterfaceManager:ApplyFont("SourceSans")
end)

InterfaceManager:BuildInterfaceSection(SettingsTab)
SaveManager:IgnoreThemeSettings()
SaveManager:LoadAutoloadConfig()

local autoSaveThread
for idx, opt in pairs(SaveManager.Options) do
    if SaveManager.Parser[opt.Type] and not SaveManager.Ignore[idx] then
        local cb = opt.Callback
        opt.Callback = function(v)
            if cb then cb(v) end
            if autoSaveThread then task.cancel(autoSaveThread) end
            autoSaveThread = task.delay(0.5, function()
                pcall(function() SaveManager:Save("AutoSave") end)
            end)
        end
        if opt.OnChanged then
            local old = opt.OnChanged
            opt.OnChanged = function()
                if old then old() end
                pcall(function() SaveManager:Save("AutoSave") end)
            end
        end
    end
end

pcall(function()
    local autoPath = "BunsHub/Config/settings/autoload.txt"
    if not isfile(autoPath) then
        task.delay(1, function()
            pcall(function()
                SaveManager:Save("AutoSave")
                writefile(autoPath, "AutoSave")
            end)
        end)
    end
end)

print("AutoFarm loaded (Fluent Modded + Fusion).")
