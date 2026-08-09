-- ===== Standalone Fusion Test =====
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer

local EggInfo = RS:WaitForChild("Remotes"):WaitForChild("EggInfo")

local NUM_CYCLES = 5           -- how many full fuse cycles to run
local POLL_INTERVAL = 3        -- seconds between GetFusionState checks while waiting
local MAX_WAIT = 180           -- give up waiting on a single job after this long
local AFTER_CLAIM_COOLDOWN = 2
local FUSE_MACHINE_FALLBACK_CFRAME = CFrame.new(-104.240242, 6.77263951, 198.388123)

-- ===== Pin =====
local pinned = false
local pinTarget = nil
local function pinTo(cf) pinTarget = cf; pinned = true end
local function unpin() pinned = false; pinTarget = nil end
RunService.Heartbeat:Connect(function()
    if pinned and pinTarget then
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = pinTarget
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

local function teleportToFuseMachine()
    local part = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("Island")
        and workspace.Map.Island:FindFirstChild("FuseMachine")
        and workspace.Map.Island.FuseMachine:FindFirstChild("Machine")
        and workspace.Map.Island.FuseMachine.Machine:FindFirstChild("Machine Plinth")

    if part and part:IsA("BasePart") then
        pinTo(part.CFrame + Vector3.new(0, 5, 0))
    else
        pinTo(FUSE_MACHINE_FALLBACK_CFRAME)
    end
    task.wait(0.5)
end

-- ===== Remote helpers =====
local function getPlayerState()
    local ok, result = pcall(function() return EggInfo:InvokeServer("State") end)
    return ok and result or nil
end

local function getFusionState()
    local ok, result = pcall(function() return EggInfo:InvokeServer("GetFusionState") end)
    return ok and result or nil
end

local function fusePets(petIds, mode)
    local ok, result = pcall(function()
        return EggInfo:InvokeServer("Fuse", { PetIds = petIds, Mode = mode })
    end)
    if not ok then warn("[Test] Fuse error:", result); return nil end
    return result
end

-- outcome IS passed correctly here
local function claimFusion(jobId, outcome)
    print(("[Test] Claiming JobId %s (Outcome: %s)"):format(jobId, tostring(outcome)))
    local remoteName = (outcome == "Failed") and "AcknowledgeFusion" or "ClaimFusion"
    local ok, result = pcall(function()
        return EggInfo:InvokeServer(remoteName, { JobId = jobId })
    end)
    print(("[Test] %s → ok=%s Success=%s Reason=%s"):format(
        remoteName, tostring(ok), tostring(result and result.Success), tostring(result and result.Reason)))

    if not ok or not result or result.Success == false then
        print("[Test] Primary method didn't confirm success, trying the other one as fallback...")
        local fallbackName = (remoteName == "AcknowledgeFusion") and "ClaimFusion" or "AcknowledgeFusion"
        local ok2, result2 = pcall(function()
            return EggInfo:InvokeServer(fallbackName, { JobId = jobId })
        end)
        print(("[Test] %s (fallback) → ok=%s Success=%s Reason=%s"):format(
            fallbackName, tostring(ok2), tostring(result2 and result2.Success), tostring(result2 and result2.Reason)))
    end
end

local function findFusableGroup(playerState, minCount, variantFilter)
    local groups = {}
    local pets = playerState and playerState.Pets
    if not pets then return nil end
    for _, pet in pairs(pets) do
        if type(pet) == "table" and pet.Name and pet.Id and (not variantFilter or pet.Variant == variantFilter)
            and not pet.Equipped and not pet.Favorited then
            groups[pet.Name] = groups[pet.Name] or {}
            table.insert(groups[pet.Name], pet.Id)
        end
    end
    for name, ids in pairs(groups) do
        if #ids >= minCount then
            return name, ids
        end
    end
    return nil
end

-- ===== Main test loop =====
for cycle = 1, NUM_CYCLES do
    print(("\n========== CYCLE %d/%d =========="):format(cycle, NUM_CYCLES))

    -- Check for an already-active fusion first (in case one's left over)
    local fs = getFusionState()
    local activeJobId = fs and fs.Fusion and fs.Fusion.Active and fs.Fusion.JobId

    if not activeJobId then
        local playerState = getPlayerState()
        local name, ids = findFusableGroup(playerState, 6, "Normal")
        if not name then
            print("[Test] No group of 6+ unequipped/unfavorited Normal pets found — stopping test.")
            break
        end

        local petIds = {ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]}
        print(("[Test] Starting fuse: 6x %s → Golden"):format(name))

        teleportToFuseMachine()
        local fuseResult = fusePets(petIds, "Golden")
        unpin()

        if not fuseResult or fuseResult.Success == false then
            print("[Test] Fuse start failed:", fuseResult and fuseResult.Reason)
            break
        end

        task.wait(0.5)
        fs = getFusionState()
        activeJobId = fs and fs.Fusion and fs.Fusion.JobId
    else
        print("[Test] Found an already-active fusion, will wait on it instead of starting a new one.")
    end

    if not activeJobId then
        print("[Test] Could not confirm a job started — stopping test.")
        break
    end

    print("[Test] Waiting for JobId", activeJobId, "to be ready...")
    local waited = 0
    local ready = false
    local finalFusion = nil

    while waited < MAX_WAIT do
        task.wait(POLL_INTERVAL)
        waited = waited + POLL_INTERVAL
        fs = getFusionState()
        local fusion = fs and fs.Fusion
        if fusion and fusion.JobId == activeJobId then
            if fusion.Ready or (fusion.Remaining and fusion.Remaining <= 0) then
                ready = true
                finalFusion = fusion
                break
            end
        else
            print("[Test] Job no longer matches current fusion state — may have been cleared externally.")
            break
        end
    end

    if not ready then
        print("[Test] Gave up waiting after", waited, "seconds.")
        break
    end

    print(("[Test] Ready! Outcome=%s Mode=%s"):format(tostring(finalFusion.Outcome), tostring(finalFusion.Mode)))

    teleportToFuseMachine()
    claimFusion(activeJobId, finalFusion.Outcome)
    task.wait(AFTER_CLAIM_COOLDOWN)
    unpin()

    -- Verify it actually cleared
    task.wait(0.5)
    local verifyState = getFusionState()
    local stillActive = verifyState and verifyState.Fusion and verifyState.Fusion.Active
        and verifyState.Fusion.JobId == activeJobId

    if stillActive then
        print("[Test] ❌ VERIFY FAILED — job", activeJobId, "is STILL active after claiming. This confirms the claim did not actually clear it.")
        break
    else
        print("[Test] ✅ VERIFY OK — job cleared successfully.")
    end
end

print("\n[Test] Done.")
