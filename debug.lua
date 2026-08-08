-- ================= Fusion Standalone Script (v7) =================
-- Fully remote: Fuse → wait → ClaimFusion

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("Remotes")
local EggInfo = remotes:WaitForChild("EggInfo")

local TELEPORT_SETTLE_DELAY = 0.6
local FUSION_CHECK_INTERVAL = 3
local FUSION_WAIT_INTERVAL = 1
local FUSION_MAX_WAIT = 300
local AFTER_CLAIM_COOLDOWN = 3

local FUSE_MACHINE_CFRAME = CFrame.new(-104.240242, 1.77263951 + 5, 198.388123)

local pinned = false
local pinTarget = nil
local lastClaimedJobId = nil

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
        warn("[Fusion] Fuse failed:", result)
        return nil
    end
    return result
end

local function claimFusion(jobId)
    if not jobId then return nil end
    if jobId == lastClaimedJobId then
        print("[Fusion] Already claimed this JobId, skipping")
        return nil
    end

    print("[Fusion] Claiming with ClaimFusion | JobId:", jobId)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("ClaimFusion", {
            JobId = jobId,
        })
    end)

    if not ok then
        warn("[Fusion] ClaimFusion call failed:", result)
        return nil
    end

    if type(result) == "table" then
        print("[Fusion] ClaimFusion → Success:", result.Success, "Reason:", result.Reason)
        if result.Success then
            lastClaimedJobId = jobId
        end
    else
        print("[Fusion] ClaimFusion result:", result)
    end

    return result
end

local function findFusableGroups(state, minCount, variantFilter)
    minCount = minCount or 6
    local groups = {}
    local pets = state and state.Pets
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

local function waitForFusionReady()
    local startTime = tick()
    while tick() - startTime < FUSION_MAX_WAIT do
        local fs = getFusionState()
        if fs and fs.Fusion then
            local jobId = fs.Fusion.JobId

            if jobId and jobId == lastClaimedJobId then
                task.wait(FUSION_WAIT_INTERVAL)
                continue
            end

            if fs.Fusion.Ready or (fs.Fusion.Remaining and fs.Fusion.Remaining <= 0) then
                print("[Fusion] Fusion ready! JobId:", jobId)
                return fs.Fusion
            end

            if not fs.Fusion.Active then
                return nil
            end
        end
        task.wait(FUSION_WAIT_INTERVAL)
    end
    warn("[Fusion] Timed out waiting for fusion")
    return nil
end

local function fuseToGolden()
    local state = getPlayerState()
    if not state then return false end

    local groups = findFusableGroups(state, 6, "Normal")
    if #groups == 0 then
        print("[Fusion] No 6+ Normal pets")
        return false
    end

    local group = groups[1]
    print("[Fusion] Found", group.count, "Normal", group.name)

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    print("[Fusion] Fusing 6x", group.name, "→ Golden...")
    local fuseResult = fusePets(petIds, "Golden")
    if fuseResult then
        print("[Fusion] Fuse Success:", fuseResult.Success, "Reason:", fuseResult.Reason)
    end

    local fusionInfo = waitForFusionReady()
    if not fusionInfo or not fusionInfo.JobId then
        unpin()
        return false
    end

    -- Fully remote claim
    claimFusion(fusionInfo.JobId)
    unpin()
    task.wait(AFTER_CLAIM_COOLDOWN)
    return true
end

local function fuseToDiamond()
    local state = getPlayerState()
    if not state then return false end

    local groups = findFusableGroups(state, 6, "Golden")
    if #groups == 0 then
        print("[Fusion] No 6+ Golden pets")
        return false
    end

    local group = groups[1]
    print("[Fusion] Found", group.count, "Golden", group.name)

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    print("[Fusion] Teleporting to FuseMachine...")
    teleportToFuseMachine()

    print("[Fusion] Fusing 6x Golden", group.name, "→ Diamond...")
    local fuseResult = fusePets(petIds, "Diamond")
    if fuseResult then
        print("[Fusion] Fuse Success:", fuseResult.Success, "Reason:", fuseResult.Reason)
    end

    local fusionInfo = waitForFusionReady()
    if not fusionInfo or not fusionInfo.JobId then
        unpin()
        return false
    end

    claimFusion(fusionInfo.JobId)
    unpin()
    task.wait(AFTER_CLAIM_COOLDOWN)
    return true
end

task.spawn(function()
    while true do
        local ok, err = pcall(function()
            if fuseToGolden() then task.wait(1) end
            if fuseToDiamond() then task.wait(1) end
        end)
        if not ok then
            warn("[Fusion] Error:", err)
        end
        task.wait(FUSION_CHECK_INTERVAL)
    end
end)

print("[Fusion] Standalone fusion script loaded (v7 - fully remote ClaimFusion).")
