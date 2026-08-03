--[[
    Attribute + Remote Scanner
    ---------------------------
    Instead of raycasting for a physical hit (which can miss tiles that
    have CanQuery/CanCollide disabled), this scans:
      1) Workspace for ANY instance carrying attributes — pixel/tile data
         is very often stored as an attribute (e.g. colorId, Painted,
         TargetColor) rather than being detectable by touch.
      2) ReplicatedStorage (and Workspace) for every RemoteEvent /
         RemoteFunction, since color selection is likely done by firing
         one of these rather than clicking a GUI button.

    Run this anywhere in the game — no need to stand on a specific spot.
]]

local CONFIG = {
    saveToFile = true,
    outputFile = "attribute_remote_scan.txt",

    -- Cap how many attribute-carrying instances we print in full detail
    -- (large canvases can have thousands of tiles; we sample instead of
    -- flooding the output)
    maxAttributeInstancesPrinted = 40,
}

----------------------------------------------------------------

local lines = {}
local function log(s)
    print(s)
    table.insert(lines, s)
end

log("STEP 0: scan started")

-- 1) Attribute scan across Workspace
log("=== INSTANCES WITH ATTRIBUTES (Workspace) ===")

local attrCount = 0
local ok1, err1 = pcall(function()
    for _, inst in ipairs(workspace:GetDescendants()) do
        local attrs = inst:GetAttributes()
        if next(attrs) ~= nil then
            attrCount = attrCount + 1
            if attrCount <= CONFIG.maxAttributeInstancesPrinted then
                local parts = {}
                for k, v in pairs(attrs) do
                    table.insert(parts, string.format("%s=%s", k, tostring(v)))
                end
                log(string.format("[%d] %s [%s] -- %s", attrCount, inst:GetFullName(), inst.ClassName, table.concat(parts, ", ")))
            end
        end
    end
end)
if not ok1 then
    log("[ERROR during attribute scan] " .. tostring(err1))
end
log("Total instances with attributes found: " .. attrCount)
if attrCount > CONFIG.maxAttributeInstancesPrinted then
    log("(only printed first " .. CONFIG.maxAttributeInstancesPrinted .. " -- raise maxAttributeInstancesPrinted to see more)")
end
log("")

-- 2) Remote scan
log("=== REMOTE EVENTS / FUNCTIONS ===")

local function scanForRemotes(root, label)
    local ok, err = pcall(function()
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                log(string.format("[%s] %s [%s]", label, inst:GetFullName(), inst.ClassName))
            end
        end
    end)
    if not ok then
        log("[ERROR scanning " .. label .. "] " .. tostring(err))
    end
end

scanForRemotes(game:GetService("ReplicatedStorage"), "ReplicatedStorage")
scanForRemotes(workspace, "Workspace")

log("")
log("STEP FINAL: scan finished")

local output = table.concat(lines, "\n")
if CONFIG.saveToFile then
    local ok, err = pcall(function()
        writefile(CONFIG.outputFile, output)
    end)
    if ok then
        print("[scan] Saved to " .. CONFIG.outputFile)
    else
        print("[scan] writefile not supported: " .. tostring(err))
    end
end
