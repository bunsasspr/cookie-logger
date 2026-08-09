-- ================= FUSION SYSTEM (forced claim on fail) =================
local lastClaimedJobId = nil
local pendingFusion = nil
local fusionActionBusy = false

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
        warn("[Fusion] Fuse call error:", result)
        return nil
    end
    return result
end

-- Force claim — tries both remotes until the fusion is gone
local function forceClaim(jobId, outcome)
    if not jobId then return false end
    if jobId == lastClaimedJobId then return true end

    print("[Fusion] Force claiming JobId:", jobId, "Outcome:", outcome or "?")

    -- Always try AcknowledgeFusion first when Outcome is Failed
    local remotesToTry = {}
    if outcome == "Failed" then
        table.insert(remotesToTry, "AcknowledgeFusion")
        table.insert(remotesToTry, "ClaimFusion")
    else
        table.insert(remotesToTry, "ClaimFusion")
        table.insert(remotesToTry, "AcknowledgeFusion")
    end

    for _, remoteName in ipairs(remotesToTry) do
        local ok, result = pcall(function()
            return EggInfo:InvokeServer(remoteName, {
                JobId = jobId,
            })
        end)

        if ok and type(result) == "table" then
            print("[Fusion]", remoteName, "→ Success:", result.Success, "Reason:", result.Reason)

            -- Check if the fusion is actually gone
            task.wait(0.4)
            local fs = getFusionState()
            if not fs or not fs.Fusion or not fs.Fusion.Active or fs.Fusion.JobId ~= jobId then
                print("[Fusion] Fusion cleared successfully with", remoteName)
                lastClaimedJobId = jobId
                return true
            end
        else
            print("[Fusion]", remoteName, "failed or returned nil")
        end
    end

    -- Last resort: mark it claimed anyway so we don't softlock forever
    warn("[Fusion] Could not clear fusion, marking as handled to prevent softlock")
    lastClaimedJobId = jobId
    return false
end

local function findFusableGroups(playerState, minCount, variantFilter)
    minCount = minCount or 6
    local groups = {}
    local pets = playerState and playerState.Pets
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

local function syncExistingFusion()
    local fs = getFusionState()
    if not fs or not fs.Fusion then return false end

    local fusion = fs.Fusion
    if not fusion.JobId or fusion.JobId == lastClaimedJobId then return false end

    if fusion.Active or fusion.Ready or (fusion.Remaining and fusion.Remaining <= 0) then
        if not pendingFusion or pendingFusion.JobId ~= fusion.JobId then
            pendingFusion = {
                JobId = fusion.JobId,
                Mode = fusion.Mode or "Golden",
                Outcome = fusion.Outcome,
            }
            print("[Fusion] Detected existing fusion → JobId:", pendingFusion.JobId,
                  "Ready:", fusion.Ready, "Outcome:", fusion.Outcome)
        end
        return true
    end
    return false
end

local function startFuse(variantFilter, mode)
    if fusionActionBusy then return false end

    -- If something is already running / ready, just sync it
    if syncExistingFusion() then
        return false
    end

    local playerState = getPlayerState()
    if not playerState then return false end

    local groups = findFusableGroups(playerState, 6, variantFilter)
    if #groups == 0 then return false end

    local group = groups[1]
    print("[Fusion] Found", group.count, variantFilter, group.name, "→", mode)

    fusionActionBusy = true

    local petIds = {}
    for i = 1, 6 do
        table.insert(petIds, group.ids[i])
    end

    teleportToFuseMachine()
    local fuseResult = fusePets(petIds, mode)

    if fuseResult then
        if fuseResult.Success == false and fuseResult.Reason == "FusionInProgress" then
            print("[Fusion] Server said FusionInProgress → syncing...")
            syncExistingFusion()
        elseif fuseResult.Success ~= false then
            task.wait(0.35)
            local fs = getFusionState()
            if fs and fs.Fusion and fs.Fusion.JobId then
                pendingFusion = {
                    JobId = fs.Fusion.JobId,
                    Mode = mode,
                    Outcome = fs.Fusion.Outcome,
                }
                print("[Fusion] Fuse started → JobId:", pendingFusion.JobId)
            end
        else
            print("[Fusion] Fuse failed →", fuseResult.Success, fuseResult.Reason)
        end
    end

    unpin()
    fusionActionBusy = false
    return true
end

-- Background claim watcher — highest priority when a fusion is ready/failed
task.spawn(function()
    while true do
        task.wait(1)

        if fusionActionBusy then
            continue
        end

        syncExistingFusion()

        if not pendingFusion then
            continue
        end

        local fs = getFusionState()
        if not fs or not fs.Fusion then
            pendingFusion = nil
            continue
        end

        local fusion = fs.Fusion
        local jobId = fusion.JobId

        if not jobId or jobId == lastClaimedJobId then
            pendingFusion = nil
            continue
        end

        local ready = fusion.Ready
            or (fusion.Remaining and fusion.Remaining <= 0)
            or fusion.Outcome == "Succeeded"
            or fusion.Outcome == "Failed"

        if ready then
            print("[Fusion] Ready/Failed → forcing claim (Outcome:", fusion.Outcome, ")")

            fusionActionBusy = true
            teleportToFuseMachine()

            -- This will try AcknowledgeFusion first when Outcome == "Failed"
            forceClaim(jobId, fusion.Outcome)

            task.wait(AFTER_CLAIM_COOLDOWN)
            unpin()

            pendingFusion = nil
            fusionActionBusy = false

            -- After clearing, try next fuse
            if state.autoCraftGolden then
                startFuse("Normal", "Golden")
            end
            if not pendingFusion and state.autoCraftDiamond then
                startFuse("Golden", "Diamond")
            end
        elseif not fusion.Active then
            pendingFusion = nil
        end
    end
end)
