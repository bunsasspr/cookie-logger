-- ================= Fusion Standalone Script (v2) =================
-- Standalone script for testing the pet fusion feature.
--
-- Flow:
--   1. Detect 6 identical Normal pets (by Name) → fuse to Golden → claim
--   2. Detect 6 identical Golden pets (by Name) → fuse to Diamond → claim
--
-- Changes from v1:
--   - Claim remote is "AcknowledgeFusion" (not "ClaimFusion")
--   - Claim stays at FuseMachine (no spawn teleport)
--   - Diamond fusion requires 6 Golden pets (not 1)
--   - Better claim timer detection using Remaining / ReadyAt / Ready

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
local FUSION_MAX_WAIT = 300  -- 5 minutes max wait for fusion to complete
local CLAIM_TELEPORT_DELAY = 0.5

-- FuseMachine location (from FullGameDump data)
-- Machine Plinth CFrame: -104.240242, 1.77263951, 198.388123
local FUSE_MACHINE_CFRAME = CFrame.new(-104.240242, 1.77263951 + 5, 198.388123)

-- Spawn location (from FullGameDump data)
-- SpawnLocation CFrame: 6, 0.5, 122
local SPAWN_CFRAME = CFrame.new(6, 0.5 + 5, 122)

-- ===== Pinning system (same as rng.lua) =====
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
        if ok then
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

-- ===== Pet grouping logic =====
-- Groups pets by Name, optionally filtered by Variant.
-- Returns groups that have >= minCount pets, sorted by count descending.
-- Each group entry: { name = "Mike", ids = {id1, id2, ...}, count = N }
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
            -- If variantFilter is specified, only include pets with that variant
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

    -- Filter to groups with >= minCount
    local fusable = {}
    for _, group in pairs(groups) do
        if group.count >= minCount then
            table.insert(fusable, group)
        end
    end

    -- Sort by count descending (fuse the biggest groups first)
    table.sort(fusable, function(a, b)
        return a.count > b.count
    end)

    return fusable
end

-- ===== Teleport functions =====
local function teleportToFuseMachine()
    local part = workspace.Map.Island.FuseMachine.Machine:FindFirstChild("Machine Plinth")
    if part and part:IsA("BasePart") then
        pinTo(part.CFrame + Vector3.new(0, 5, 0))
    else
        -- Fallback to hardcoded CFrame from dump data
        pinTo(FUSE_MACHINE_CFRAME)
    end
    task.wait(TELEPORT_SETTLE_DELAY)
end

local function teleportToSpawn()
    local spawn = workspace.Map:FindFirstChild("SpawnLocation")
    if spawn and spawn:IsA("BasePart") then
        pinTo(spawn.CFrame + Vector3.new(0, 5, 0))
    else
        -- Fallback to hardcoded CFrame from dump data
        pinTo(SPAWN_CFRAME)
    end
    task.wait(TELEPORT_SETTLE_DELAY)
end

-- ===== Wait for fusion to be ready to claim =====
-- Uses multiple indicators: Ready, Remaining, ReadyAt
local function waitForFusionReady()
    local startTime = tick()
    while tick() - startTime < FUSION_MAX_WAIT do
        local fs = getFusionState()
        if fs and fs.Fusion then
            -- Check if fusion is ready using multiple indicators
            if fs.Fusion.Ready then
                print("[Fusion] Fusion is ready! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if fs.Fusion.Remaining and fs.Fusion.Remaining <= 0 then
                print("[Fusion] Fusion remaining is 0! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if fs.Fusion.ReadyAt and tick() >= fs.Fusion.ReadyAt then
                print("[Fusion] ReadyAt timestamp passed! JobId:", fs.Fusion.JobId)
                return fs.Fusion
            end
            if not fs.Fusion.Active then
                -- Fusion finished but not ready (maybe failed or already claimed)
                print("[Fusion] Fusion not active. Outcome:", fs.Fusion.Outcome or "unknown")
                return fs.Fusion
            end
        end
        task.wait(FUSION_WAIT_INTERVAL)
    end
    warn("[Fusion] Timed out waiting for fusion to complete")
    return nil
end

-- ===== Claim fusion (stay at FuseMachine, then acknowledge) =====
local function claimFusion(fusionInfo)
    if not fusionInfo.JobId then
        warn("[Fusion] No JobId in fusion info, cannot claim")
        return nil
    end

    -- Stay at the FuseMachine — the spawn teleport was wrong,
    -- claiming must happen at the machine itself.
    print("[Fusion] Acknowledging fusion with JobId:", fusionInfo.JobId)
    local result = acknowledgeFusion(fusionInfo.JobId)
    if result then
        print("[Fusion] AcknowledgeFusion result:", result)
    end
    return result
end

-- ===== Fuse 6 identical Normal pets to Golden =====
local function fuseToGolden()
    local state = getPlayerState()
    if not state then return false end

    -- Find groups of 6+ identical Normal pets by Name
    local fusableGroups = findFusableGroups(state, 6, "Normal")
    if #fusableGroups == 0 then
        print("[Fusion] No groups of 6+ identical Normal pets found")
        return false
    end

    local group = fusableGroups[1]
    print("[Fusion] Found", group.count, "identical Normal pets named:", group.name)

    -- Take exactly 6 pet IDs
    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    -- Teleport to the FuseMachine
    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    -- Fuse to Golden
    print("[Fusion] Fusing 6x", group.name, "to Golden...")
    local fuseResult = fusePets(petIds, "Golden")
    if fuseResult then
        print("[Fusion] Fuse result:", fuseResult)
    end

    -- Wait for fusion to complete
    local fusionInfo = waitForFusionReady()
    if not fusionInfo then
        unpin()
        return false
    end

    -- Claim the fusion
    claimFusion(fusionInfo)
    unpin()
    return true
end

-- ===== Fuse 6 identical Golden pets to Diamond =====
local function fuseToDiamond()
    local state = getPlayerState()
    if not state then return false end

    -- Find groups of 6+ identical Golden pets by Name
    local fusableGroups = findFusableGroups(state, 6, "Golden")
    if #fusableGroups == 0 then
        print("[Fusion] No groups of 6+ identical Golden pets found")
        return false
    end

    local group = fusableGroups[1]
    print("[Fusion] Found", group.count, "identical Golden pets named:", group.name)

    -- Take exactly 6 pet IDs
    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    -- Teleport to the FuseMachine
    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    -- Fuse to Diamond
    print("[Fusion] Fusing 6x Golden", group.name, "to Diamond...")
    local fuseResult = fusePets(petIds, "Diamond")
    if fuseResult then
        print("[Fusion] Fuse result:", fuseResult)
    end

    -- Wait for fusion to complete
    local fusionInfo = waitForFusionReady()
    if not fusionInfo then
        unpin()
        return false
    end

    -- Claim the fusion
    claimFusion(fusionInfo)
    unpin()
    return true
end

-- ===== Main loop =====
task.spawn(function()
    while true do
        local ok, err = pcall(function()
            -- Try Golden fusion first (6 Normal → 1 Golden)
            local goldenDone = fuseToGolden()
            if goldenDone then
                task.wait(1)
            end
            -- Then try Diamond fusion (6 Golden → 1 Diamond)
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

print("[Fusion] Standalone fusion script loaded (v2).")
