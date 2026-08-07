-- ===== Spam-pin TP to Merchant + buy everything =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local model = getMerchantModel()
if not model then
    warn("Merchant not found — make sure it's currently spawned")
    return
end

local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
if not part then
    warn("No BasePart on Merchant model")
    return
end

local hrp = getHRP()
local targetCFrame = part.CFrame

-- Pin the character to the target every frame, countering any physics push-out
local pinning = true
local pinConn = RunService.Heartbeat:Connect(function()
    if pinning then
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end)

task.wait(0.5) -- let the pin take hold before interacting

local prompt = findProximityPrompt(model)
if prompt then
    pcall(function()
        fireproximityprompt(prompt)
    end)
end

task.wait(0.8) -- let the GUI populate while still pinned

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
        -- skip clone-source templates
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
                task.wait(0.25) -- still pinned during this wait
            end
        end
    end
end

print(("Done — bought %d item(s) from Merchant"):format(bought))

-- stop pinning
pinning = false
pinConn:Disconnect()
