-- ================= Smart Auto Egg Tester =================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local EggInfo = RS:WaitForChild("Remotes"):WaitForChild("EggInfo")

-- ===== Settings (change these) =====
local SELECTED_EGG = "Basic"      -- change egg type here
local QUANTITY = 1                -- 1 ~ MaxOpenAmount
local ENABLED = true              -- set to false to stop

-- ===== Pinning (same as your main script) =====
local pinned = false
local pinTarget = nil

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function pinTo(cf)
    pinTarget = cf
    pinned = true
end

local function unpin()
    pinned = false
    pinTarget = nil
end

RunService.Heartbeat:Connect(function()
    if pinned and pinTarget then
        local ok, hrp = pcall(getHRP)
        if ok and hrp then
            hrp.CFrame = pinTarget
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

-- ===== Egg position helpers =====
local EGG_HOLDER_INDEX = {
    Basic = 1, Forest = 2, Jungle = 3, Beach = 4, Monster = 5,
    Desert = 6, Galaxy = 7, Candy = 8, Lava = 9, Frozen = 10,
}

local function getEggPart(eggName)
    local idx = EGG_HOLDER_INDEX[eggName]
    if not idx then return nil end
    local holders = workspace:FindFirstChild("Map") 
        and workspace.Map:FindFirstChild("Island") 
        and workspace.Map.Island:FindFirstChild("EggHolders")
    if not holders then return nil end
    local holder = holders:FindFirstChild(tostring(idx))
    if not holder then return nil end
    return holder:FindFirstChild("Part")
end

-- ===== Smart Open Function =====
local function smartOpenEgg(eggName, quantity)
    local part = getEggPart(eggName)
    if not part then
        warn("[SmartEgg] Could not find egg part for:", eggName)
        return false
    end

    pinTo(part.CFrame)
    task.wait(0.4)

    local maxAttempts = 15
    for attempt = 1, maxAttempts do
        local success, result = pcall(function()
            return EggInfo:InvokeServer("Buy", eggName, quantity)
        end)

        if not success then
            warn("[SmartEgg] Remote error:", result)
            task.wait(0.8)
            continue
        end

        if typeof(result) == "table" then
            if result.Success == true then
                print(string.format("[SmartEgg] Successfully opened %s x%d", eggName, quantity))
                unpin()
                return true
            end

            if result.Reason == "Cooldown" and typeof(result.RetryAfter) == "number" then
                local waitTime = result.RetryAfter + 0.12
                print(string.format("[SmartEgg] On cooldown, waiting %.2fs (attempt %d)", waitTime, attempt))
                task.wait(waitTime)
            else
                warn("[SmartEgg] Failed:", result.Reason or "Unknown")
                task.wait(0.7)
            end
        else
            task.wait(0.7)
        end
    end

    warn("[SmartEgg] Gave up after max attempts")
    unpin()
    return false
end

-- ===== Main Loop =====
print("=== Smart Auto Egg Tester started ===")
print("Egg:", SELECTED_EGG, "| Quantity:", QUANTITY)

task.spawn(function()
    while ENABLED do
        smartOpenEgg(SELECTED_EGG, QUANTITY)
        task.wait(0.15) -- tiny delay between successful opens
    end
end)

print("Running... Set ENABLED = false to stop")
