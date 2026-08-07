-- ===== Full Game Dumper (almost everything) =====
-- Saves hierarchy + scripts + values + basic properties

local ServicesToDump = {
    "ReplicatedStorage",
    "Workspace",
    "Players",
    "Lighting",
    "StarterGui",
    "StarterPlayer",
    "SoundService",
    "Chat",
    "Teams",
    "MaterialService",
}

local MAX_DEPTH = 15
local OUTPUT_ROOT = "FullGameDump"

-- ========== Helpers ==========
local function safeMakeFolder(path)
    pcall(function()
        if not isfolder(path) then
            makefolder(path)
        end
    end)
end

local function safeWriteFile(path, content)
    pcall(function()
        writefile(path, content)
    end)
end

local function sanitize(name)
    if type(name) ~= "string" then name = tostring(name) end
    name = name:gsub("[\r\n\t]", " ")
    name = name:gsub("[<>:\"/\\|?*]", "_")
    name = name:gsub("%s+", " ")
    name = name:match("^%s*(.-)%s*$") or "unnamed"
    if #name == 0 then name = "unnamed" end
    if #name > 60 then name = name:sub(1, 60) end
    return name
end

local function getDecompiled(script)
    local ok, source = pcall(function()
        return decompile(script)
    end)
    if ok and type(source) == "string" and #source > 10 then
        return source
    end
    return "-- [Could not decompile]\n"
end

local function getAttributes(inst)
    local attrs = {}
    local ok, list = pcall(function()
        return inst:GetAttributes()
    end)
    if ok and type(list) == "table" then
        for k, v in pairs(list) do
            attrs[tostring(k)] = tostring(v)
        end
    end
    return attrs
end

local function getBasicProperties(inst)
    local props = {}
    local interesting = {
        "ClassName", "Name", "Parent",
        "Value", "Text", "Image", "Texture", "MeshId", "SoundId",
        "BrickColor", "Color", "Material", "Transparency", "Reflectance",
        "Size", "Position", "CFrame", "Anchored", "CanCollide",
        "Health", "MaxHealth", "WalkSpeed", "JumpPower",
    }

    for _, prop in ipairs(interesting) do
        local ok, val = pcall(function()
            return inst[prop]
        end)
        if ok and val ~= nil then
            props[prop] = tostring(val)
        end
    end
    return props
end

local dumpedScripts = 0
local dumpedOthers = 0

local function dumpInstance(inst, currentPath, depth)
    if depth > MAX_DEPTH then return end
    if not inst or not inst.Parent and depth > 0 then return end

    local name = sanitize(inst.Name)
    local fullPath = currentPath .. "/" .. name

    -- Create folder for containers
    if inst:IsA("Folder") or inst:IsA("Model") or inst:IsA("Configuration") 
        or inst:IsA("Player") or inst:IsA("Backpack") or inst:IsA("PlayerGui") then
        safeMakeFolder(fullPath)
    end

    -- Scripts → save decompiled source
    if inst:IsA("ModuleScript") or inst:IsA("LocalScript") or inst:IsA("Script") then
        local source = getDecompiled(inst)
        local header = string.format(
            "-- Path: %s\n-- Class: %s\n\n",
            inst:GetFullName(), inst.ClassName
        )
        safeWriteFile(fullPath .. ".lua", header .. source)
        dumpedScripts += 1
        print("Script:", inst:GetFullName())

    -- Value objects
    elseif inst:IsA("StringValue") or inst:IsA("NumberValue") or inst:IsA("IntValue")
        or inst:IsA("BoolValue") or inst:IsA("ObjectValue") or inst:IsA("CFrameValue")
        or inst:IsA("Vector3Value") or inst:IsA("Color3Value") then
        local content = tostring(inst.Value)
        safeWriteFile(fullPath .. ".txt", content)
        dumpedOthers += 1

    -- Everything else → save a small info file
    else
        local info = {
            "ClassName: " .. inst.ClassName,
            "FullName: " .. inst:GetFullName(),
        }

        local props = getBasicProperties(inst)
        for k, v in pairs(props) do
            table.insert(info, k .. ": " .. v)
        end

        local attrs = getAttributes(inst)
        if next(attrs) then
            table.insert(info, "\n--- Attributes ---")
            for k, v in pairs(attrs) do
                table.insert(info, k .. " = " .. v)
            end
        end

        safeWriteFile(fullPath .. ".info.txt", table.concat(info, "\n"))
        dumpedOthers += 1
    end

    -- Recurse children
    local ok, children = pcall(function()
        return inst:GetChildren()
    end)
    if ok then
        for _, child in ipairs(children) do
            dumpInstance(child, fullPath, depth + 1)
        end
    end
end

-- ========== Start ==========
print("Starting FULL dump...")
print("Output:", OUTPUT_ROOT)
safeMakeFolder(OUTPUT_ROOT)

for _, serviceName in ipairs(ServicesToDump) do
    local service = game:FindService(serviceName) or game:GetService(serviceName)
    if service then
        local servicePath = OUTPUT_ROOT .. "/" .. serviceName
        safeMakeFolder(servicePath)
        print("\n=== Dumping", serviceName, "===")

        for _, child in ipairs(service:GetChildren()) do
            dumpInstance(child, servicePath, 1)
        end
    end
end

print("\n========================================")
print("FULL DUMP FINISHED")
print("Scripts dumped :", dumpedScripts)
print("Other instances:", dumpedOthers)
print("Saved to       :", OUTPUT_ROOT)
print("========================================")
