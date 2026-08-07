-- ===== Standalone: simulate AutoFarm's exact Merchant flow, including return to eggs =====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")
local MerchantRemote = remotes:WaitForChild("Merchant")

local EGG_CFRAME = CFrame.new(-198.375092, 3.67208314, 168.48439, -0.455900133, 5.02545072e-09, 0.890030921, 1.24778738e-08, 1, 7.45158324e-10, -0.890030921, 1.14454117e-08, -0.455900133)

local ACTION_SETTLE_DELAY = 0.6
local TELEPORT_SETTLE_DELAY = 0.5
local PIN_DURATION = 5

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

local function startPin(hrp, cframe)
    local pinning = true
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if pinning then
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

local function getMerchantHolder()
    local ok, holder = pcall(function()
        return player.PlayerGui.Main.Canvas.Merchant.Main.Holder
    end)
    if ok then return holder end
    return nil
end

-- ===== Simulated withLock settle delay =====
print("[Step] Acquired 'lock' — settling")
task.wait(ACTION_SETTLE_DELAY)

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
print("[Step] Teleporting (zero offset)")
teleportTo(hrp, part.CFrame, 0)
task.wait(TELEPORT_SETTLE_DELAY)

model = getMerchantModel()
if not model then
    warn("Merchant despawned right before buying")
    return
end

local prompt = findProximityPrompt(model)
if prompt then
    print("[Step] MaxActivationDistance:", prompt.MaxActivationDistance)
    pcall(function()
        fireproximityprompt(prompt)
    end)
else
    warn("[Step] No ProximityPrompt found")
end
task.wait(0.5)

local holder = getMerchantHolder()
if not holder then
    warn("[Step] Merchant Holder GUI not found — window probably didn't open")
    return
end

local children = holder:GetChildren()
table.sort(children, function(a, b)
    local aOrder = (pcall(function() return a.LayoutOrder end)) and a.LayoutOrder or 0
    local bOrder = (pcall(function() return b.LayoutOrder end)) and b.LayoutOrder or 0
    return aOrder < bOrder
end)

local toBuy = {}
local currentCategory = nil
for _, entry in ipairs(children) do
    local nameLabel = entry:FindFirstChild("NameLabel")
    if entry.Name == "TextPlaceHolder" and nameLabel then
        currentCategory = nameLabel.Text
    elseif entry.Name:find("Template") then
        -- skip
    elseif entry:IsA("Frame") or entry:IsA("ImageButton") or entry:IsA("TextButton") or entry:IsA("CanvasGroup") then
        local itemNameLabel = entry:FindFirstChild("DiceName") or entry:FindFirstChild("FoodName")
        local stockLabel = entry:FindFirstChild("Stock")
        if itemNameLabel and currentCategory then
            local stockText = stockLabel and stockLabel.Text or ""
            if stockText ~= "Sold out" and stockText ~= "" then
                table.insert(toBuy, {category = currentCategory, itemName = itemNameLabel.Text})
            end
        end
    end
end

print(("[Step] Found %d purchasable item(s)"):format(#toBuy))
if #toBuy == 0 then
    warn("[Step] Nothing to buy — GUI may not have populated, or genuinely no stock")
end

print("[Step] Pinning + firing")
local stopPin = startPin(hrp, part.CFrame)
local pinStart = tick()

for _, item in ipairs(toBuy) do
    pcall(function()
        MerchantRemote:FireServer("BuyAll", item.category, item.itemName)
    end)
    print(("[Step] Fired: %s (%s)"):format(item.itemName, item.category))
    task.wait(0.15)
end

local remaining = PIN_DURATION - (tick() - pinStart)
if remaining > 0 then
    print(("[Step] Holding pin for %.1f more seconds"):format(remaining))
    task.wait(remaining)
end

stopPin()
print("[Step] Stopped pin")

print("[Step] Teleporting to eggs")
teleportTo(hrp, EGG_CFRAME, 4)
task.wait(TELEPORT_SETTLE_DELAY)

print("[Step] Done — check your inventory/stock now")
