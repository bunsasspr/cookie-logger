-- ================= Fusion Standalone Script =================
-- Standalone script for testing the pet fusion feature.
-- Detects 6 identical pets (by Name), teleports to the FuseMachine,
-- fuses them to Golden, claims the result, then upgrades Golden → Diamond.
--
-- Based on data from FullGameDump/pets.txt and the existing rng.lua patterns.

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

-- FuseMachine location (from FullGameDump data)
-- Machine Plinth CFrame: -104.240242, 1.77263951, 198.388123
-- We add a small Y offset so the player stands on top of the plinth
local FUSE_MACHINE_CFRAME = CFrame.new(-104.240242, 1.77263951 + 5, 198.388123)

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

local function claimFusion(jobId)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("ClaimFusion", {
            JobId = jobId,
        })
    end)
    if not ok then
        warn("[Fusion] ClaimFusion call failed:", result)
        return nil
    end
    return result
end

-- ===== Pet grouping logic =====
-- Groups pets by Name and returns groups that have >= 6 pets.
-- Each group entry: { name = "Mike", ids = {id1, id2, ...}, count = N }
local function findFusableGroups(state, minCount)
    minCount = minCount or 6
    local groups = {}  -- name -> {ids = {}, count = N}

    local pets = state and state.Pets
    if not pets then
        warn("[Fusion] No Pets table in state")
        return {}
    end

    for _, pet in pairs(pets) do
        if type(pet) == "table" and pet.Name and pet.Id then
            local name = pet.Name
            if not groups[name] then
                groups[name] = { name = name, ids = {}, count = 0 }
            end
            table.insert(groups[name].ids, pet.Id)
            groups[name].count = groups[name].count + 1
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

-- ===== Teleport to FuseMachine =====
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

-- ===== Wait for fusion to complete =====
local function waitForFusionComplete()
    local startTime = tick()
    while tick() - startTime < FUSION_MAX_WAIT do
        local fs = getFusionState()
        if fs and fs.Fusion then
            if fs.Fusion.Ready then
                print("[Fusion] Fusion is ready! JobId:", fs.Fusion.JobId)
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

-- ===== Main fusion routine =====
local function runFusion()
    -- Step 1: Get player state
    local state = getPlayerState()
    if not state then return end

    -- Step 2: Find groups of 6+ identical pets
    local fusableGroups = findFusableGroups(state, 6)
    if #fusableGroups == 0 then
        print("[Fusion] No groups of 6+ identical pets found")
        return
    end

    -- Step 3: Take the first (largest) group
    local group = fusableGroups[1]
    print("[Fusion] Found", group.count, "identical pets named:", group.name)

    -- Take exactly 6 pet IDs
    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    -- Step 4: Teleport to the FuseMachine
    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    -- Step 5: Fuse to Golden
    print("[Fusion] Fusing 6x", group.name, "to Golden...")
    local fuseResult = fusePets(petIds, "Golden")
    if fuseResult then
        print("[Fusion] Fuse result:", fuseResult)
    end

    -- Step 6: Wait for fusion to complete
    local fusionInfo = waitForFusionComplete()
    if not fusionInfo then
        unpin()
        return
    end

    -- Step 7: Claim the fusion
    if fusionInfo.JobId then
        print("[Fusion] Claiming fusion with JobId:", fusionInfo.JobId)
        local claimResult = claimFusion(fusionInfo.JobId)
        if claimResult then
            print("[Fusion] Claim result:", claimResult)
        end
    else
        warn("[Fusion] No JobId in fusion info, cannot claim")
    end

    unpin()

    -- Step 8: Gold → Diamond upgrade
    -- After claiming, the Golden pet should be in our inventory.
    -- We need to find it and fuse it to Diamond.
    task.wait(1)
    local newState = getPlayerState()
    if not newState then return end

    -- Find the Golden pet with the same name
    local goldenPetId = nil
    local pets = newState.Pets
    if pets then
        for _, pet in pairs(pets) do
            if type(pet) == "table" and pet.Name == group.name and pet.Variant == "Golden" then
                goldenPetId = pet.Id
                break
            end
        end
    end

    if goldenPetId then
        print("[Fusion] Found Golden", group.name, "with Id:", goldenPetId)
        print("[Fusion] Teleporting to FuseMachine for Diamond upgrade...")
        teleportToFuseMachine()

        print("[Fusion] Fusing Golden", group.name, "to Diamond...")
        local diamondResult = fusePets({goldenPetId}, "Diamond")
        if diamondResult then
            print("[Fusion] Diamond fuse result:", diamondResult)
        end

        -- Wait for diamond fusion to complete
        local diamondFusionInfo = waitForFusionComplete()
        if diamondFusionInfo and diamondFusionInfo.JobId then
            print("[Fusion] Claiming Diamond fusion with JobId:", diamondFusionInfo.JobId)
            local diamondClaimResult = claimFusion(diamondFusionInfo.JobId)
            if diamondClaimResult then
                print("[Fusion] Diamond claim result:", diamondClaimResult)
            end
        end

        unpin()
    else
        print("[Fusion] No Golden", group.name, "found in inventory for Diamond upgrade")
    end
end

-- ===== Main loop =====
task.spawn(function()
    while true do
        local ok, err = pcall(runFusion)
        if not ok then
            warn("[Fusion] Error in runFusion:", err)
        end
        task.wait(FUSION_CHECK_INTERVAL)
    end
end)

print("[Fusion] Standalone fusion script loaded.")
