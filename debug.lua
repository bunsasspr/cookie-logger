-- ================= Fusion Standalone Script (v3) =================
-- Flow:
--   1. TP to FuseMachine (once)
--   2. Fuse
--   3. Wait until timer finishes
--   4. TP to claim position
--   5. Fire AcknowledgeFusion

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")
local EggInfo = remotes:WaitForChild("EggInfo")

-- ===== Config =====
local TELEPORT_SETTLE_DELAY = 0.5
local FUSION_CHECK_INTERVAL = 2
local FUSION_WAIT_INTERVAL = 1
local FUSION_MAX_WAIT = 300
local CLAIM_TELEPORT_DELAY = 0.5

-- FuseMachine location
local FUSE_MACHINE_CFRAME = CFrame.new(-104.240242, 1.77263951 + 5, 198.388123)

-- Claim position (exact CFrame you gave)
local CLAIM_CFRAME = CFrame.new(
    -116.513695, 5.76566458, 199.923004,
    0.133674741, -1.7736415e-08, 0.991025269,
    6.08319839e-09, 1, 1.7076502e-08,
    -0.991025269, 3.74590625e-09, 0.133674741
)

-- ===== Pinning system =====
local pinned = false
local pinTarget = nil

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

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
        if ok and hrp then
            hrp.CFrame = pinTarget
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

-- ===== Remote helpers =====
local function getPlayerState()
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("State")
    end)
    if not ok or not result then
        warn("[Fusion] Failed to get player state")
        return nil
    end
    return result
end

local function getFusionState()
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("GetFusionState")
    end)
    if not ok or not result then
        warn("[Fusion] Failed to get fusion state")
        return nil
    end
    return result
end

local function fusePets(petIds, mode)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("Fuse", {
            PetIds = petIds,
            Mode = mode,
        })
    end)
    if not ok then
        warn("[Fusion] Fuse call failed:", result)
        return nil
    end
    return result
end

local function acknowledgeFusion(jobId)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("AcknowledgeFusion", {
            JobId = jobId,
        })
    end)
    if not ok then
        warn("[Fusion] AcknowledgeFusion call failed:", result)
        return nil
    end
    return result
end

-- ===== Pet grouping =====
local function findFusableGroups(state, minCount, variantFilter)
    minCount = minCount or 6
    local groups = {}

    local pets = state and state.Pets
    if not pets then
        warn("[Fusion] No Pets table in state")
        return {}
    end

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

    table.sort(fusable, function(a, b)
        return a.count > b.count
    end)

    return fusable
end

-- ===== Teleports =====
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

local function teleportToClaimPosition()
    pinTo(CLAIM_CFRAME)
    task.wait(CLAIM_TELEPORT_DELAY)
end

-- ===== Wait for fusion ready =====
local function waitForFusionReady()
    local startTime = tick()
    while tick() - startTime < FUSION_MAX_WAIT do
        local fs = getFusionState()
        if fs and fs.Fusion then
            if fs.Fusion.Ready then
                print("[Fusion] Fusion ready! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if fs.Fusion.Remaining and fs.Fusion.Remaining <= 0 then
                print("[Fusion] Remaining <= 0! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if fs.Fusion.ReadyAt and tick() >= fs.Fusion.ReadyAt then
                print("[Fusion] ReadyAt passed! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if not fs.Fusion.Active then
                print("[Fusion] Fusion no longer active. Outcome:", fs.Fusion.Outcome or "unknown")
                return fs.Fusion
            end
        end
        task.wait(FUSION_WAIT_INTERVAL)
    end
    warn("[Fusion] Timed out waiting for fusion")
    return nil
end

-- ===== Claim (TP to claim pos → fire event) =====
local function claimFusion(fusionInfo)
    if not fusionInfo or not fusionInfo.JobId then
        warn("[Fusion] No JobId, cannot claim")
        return nil
    end

    print("[Fusion] Timer finished → teleporting to claim position...")
    teleportToClaimPosition()

    print("[Fusion] Firing AcknowledgeFusion with JobId:", fusionInfo.JobId)
    local result = acknowledgeFusion(fusionInfo.JobId)
    if result then
        print("[Fusion] AcknowledgeFusion result:", result)
    end
    return result
end

-- ===== Fuse 6 Normal → Golden =====
local function fuseToGolden()
    local state = getPlayerState()
    if not state then return false end

    local fusableGroups = findFusableGroups(state, 6, "Normal")
    if #fusableGroups == 0 then
        print("[Fusion] No 6+ identical Normal pets found")
        return false
    end

    local group = fusableGroups[1]
    print("[Fusion] Found", group.count, "Normal pets named:", group.name)

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    -- 1. TP to FuseMachine (once)
    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    -- 2. Fuse
    print("[Fusion] Fusing 6x", group.name, "→ Golden...")
    local fuseResult = fusePets(petIds, "Golden")
    if fuseResult then
        print("[Fusion] Fuse result:", fuseResult)
    end

    -- 3. Wait for timer
    local fusionInfo = waitForFusionReady()
    if not fusionInfo then
        unpin()
        return false
    end

    -- 4 + 5. TP to claim pos → fire claim
    claimFusion(fusionInfo)
    unpin()
    return true
end

-- ===== Fuse 6 Golden → Diamond =====
local function fuseToDiamond()
    local state = getPlayerState()
    if not state then return false end

    local fusableGroups = findFusableGroups(state, 6, "Golden")
    if #fusableGroups == 0 then
        print("[Fusion] No 6+ identical Golden pets found")
        return false
    end

    local group = fusableGroups[1]
    print("[Fusion] Found", group.count, "Golden pets named:", group.name)

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    -- 1. TP to FuseMachine (once)
    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    -- 2. Fuse
    print("[Fusion] Fusing 6x Golden", group.name, "→ Diamond...")
    local fuseResult = fusePets(petIds, "Diamond")
    if fuseResult then
        print("[Fusion] Fuse result:", fuseResult)
    end

    -- 3. Wait for timer
    local fusionInfo = waitForFusionReady()
    if not fusionInfo then
        unpin()
        return false
    end

    -- 4 + 5. TP to claim pos → fire claim
    claimFusion(fusionInfo)
    unpin()
    return true
end

-- ===== Main loop =====
task.spawn(function()
    while true do
        local ok, err = pcall(function()
            local goldenDone = fuseToGolden()
            if goldenDone then
                task.wait(1)
            end

            local diamondDone = fuseToDiamond()
            if diamondDone then
                task.wait(1)
            end
        end)
        if not ok then
            warn("[Fusion] Error:", err)
        end
        task.wait(FUSION_CHECK_INTERVAL)
    end
end)

print("[Fusion] Standalone fusion script loaded (v3).")
