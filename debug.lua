-- ===== Game Dumper (Client-side readable content) =====
-- Creates a folder structure and saves decompiled scripts + hierarchy

local ServicesToDump = {
    "ReplicatedStorage",
    "Workspace",
    "Players",
    "Lighting",
    "StarterGui",
    "StarterPlayer",
    "SoundService",
    "Chat",
}

local MAX_DEPTH = 12
local OUTPUT_ROOT = "GameDump_" .. os.date("%Y-%m-%d_%H-%M-%S")

-- Executor file functions (most modern executors support these)
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

local function getDecompiled(script)
    local ok, source = pcall(function()
        return decompile(script) -- most executors have this
    end)
    if ok and type(source) == "string" and #source > 0 then
        return source
    end
    return "-- [Could not decompile]\n"
end

local function sanitizeName(name)
    return name:gsub("[<>:\"/\\|?*]", "_")
end

local dumped = 0

local function dumpInstance(inst, currentPath, depth)
    if depth > MAX_DEPTH then return end

    local name = sanitizeName(inst.Name)
    local fullPath = currentPath .. "/" .. name

    if inst:IsA("Folder") or inst:IsA("Configuration") or inst:IsA("Model") then
        safeMakeFolder(fullPath)
    elseif inst:IsA("ModuleScript") or inst:IsA("LocalScript") or inst:IsA("Script") then
        -- Save the decompiled source
        local source = getDecompiled(inst)
        local fileName = fullPath .. ".lua"
        safeWriteFile(fileName, "-- Path: " .. inst:GetFullName() .. "\n-- Class: " .. inst.ClassName .. "\n\n" .. source)
        dumped += 1
        print("Dumped:", inst:GetFullName())
    elseif inst:IsA("StringValue") or inst:IsA("NumberValue") or inst:IsA("BoolValue") or inst:IsA("ObjectValue") then
        local content = tostring(inst.Value)
        safeWriteFile(fullPath .. ".txt", content)
    end

    -- Recurse children
    for _, child in ipairs(inst:GetChildren()) do
        dumpInstance(child, fullPath, depth + 1)
    end
end

-- Start
print("Starting dump...")
safeMakeFolder(OUTPUT_ROOT)

for _, serviceName in ipairs(ServicesToDump) do
    local service = game:FindService(serviceName) or game:GetService(serviceName)
    if service then
        local servicePath = OUTPUT_ROOT .. "/" .. serviceName
        safeMakeFolder(servicePath)
        print("Dumping service:", serviceName)

        for _, child in ipairs(service:GetChildren()) do
            dumpInstance(child, servicePath, 1)
        end
    end
end

print("========================================")
print("Dump finished!")
print("Scripts dumped:", dumped)
print("Folder created:", OUTPUT_ROOT)
print("Check your executor's workspace folder.")
print("========================================")
