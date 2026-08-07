-- ===== Simple Auto Merchant =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")
local MerchantRemote = remotes:WaitForChild("Merchant")

local enabled = false
local CHECK_INTERVAL = 2 -- how often to look for the merchant

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getMerchantModel()
    local mapShop = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MapShop")
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
    local model = getMerchantModel()
    if not model then
        warn("Merchant not found")
        return
    end

    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        warn("No BasePart on Merchant")
        return
    end

    local hrp = getHRP()

    -- Simple single teleport (no continuous pin)
    hrp.CFrame = part.CFrame + Vector3.new(0, 2, 0) -- slightly above so it doesn't clip
    task.wait(0.4)

    -- Open the merchant GUI
    local prompt = findProximityPrompt(model)
    if prompt then
        pcall(function()
            fireproximityprompt(prompt)
        end)
    end
    task.wait(0.6) -- wait for GUI to load

    -- Buy everything that is in stock
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
            -- skip templates
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
                    print("Bought:", itemName, "(" .. currentCategory .. ")")
                    bought += 1
                    task.wait(0.15)
                end
            end
        end
    end

    print("Done — bought", bought, "item(s)")
end

-- Detect merchant spawn
local lastMerchant = nil
task.spawn(function()
    while true do
        if enabled then
            local merchant = getMerchantModel()
            if merchant and merchant ~= lastMerchant then
                lastMerchant = merchant
                print("Merchant found → buying...")
                buyAllFromMerchant()
            elseif not merchant then
                lastMerchant = nil
            end
        end
        task.wait(CHECK_INTERVAL)
    end
end)

-- Toggle with B
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.B then
        enabled = not enabled
        print(enabled and "✅ Auto Merchant: ON" or "❌ Auto Merchant: OFF")
    end
end)

print("Simple Auto Merchant loaded. Press B to toggle.")
