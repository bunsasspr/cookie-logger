-- ===== Auto Merchant =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local MerchantRemote = RS:WaitForChild("Remotes"):WaitForChild("Merchant")

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

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

local function openMerchantWindow()
    local model = getMerchantModel()
    if not model then
        warn("Merchant not found (probably despawned)")
        return false
    end

    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        warn("No BasePart on Merchant model")
        return false
    end

    local hrp = getHRP()
    hrp.CFrame = part.CFrame
    task.wait(0.3)

    local prompt = findProximityPrompt(model)
    if prompt then
        -- fireproximityprompt is an executor-provided function
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if not ok then
            warn("fireproximityprompt not available on this executor — open the window manually then re-run")
        end
    end

    task.wait(0.5) -- let the GUI populate
    return true
end

local function buyAllFromMerchant()
    if not openMerchantWindow() then return end

    local holder = player.PlayerGui.Main.Canvas.Merchant.Main.Holder
    local currentCategory = nil
    local bought = 0

    for _, entry in ipairs(holder:GetChildren()) do
        -- category headers
        local nameLabel = entry:FindFirstChild("NameLabel")
        if entry.Name == "TextPlaceHolder" and nameLabel then
            currentCategory = nameLabel.Text

        -- item entries (skip layout objects)
        elseif entry:IsA("Frame") or entry:IsA("ImageButton") or entry:IsA("TextButton") then
            local itemNameLabel = entry:FindFirstChild("DiceName") or entry:FindFirstChild("FoodName")
            local stockLabel = entry:FindFirstChild("Stock")

            if itemNameLabel and currentCategory then
                local stockText = stockLabel and stockLabel.Text or ""
                if stockText ~= "Sold out" then
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

    print(("Done — bought %d item(s) from Merchant"):format(bought))
end

buyAllFromMerchant()
