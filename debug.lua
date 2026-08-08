--// Auto-Collect Observer
--// Run this FIRST, then start the other auto-collect script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local collector =
    workspace.Map.Plots.Plot.Floor1.Holders.ItemHolder1.Collector

local function log(...)
    print("[COLLECT-SPY]", ...)
end

log("====================================")
log("COLLECTION SPY STARTED")
log("Collector:", collector:GetFullName())
log("====================================")

--==================================================
-- 1. ALL RemoteEvent / RemoteFunction calls
--==================================================

local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall

setreadonly(mt, false)

mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()

    if method == "FireServer"
        or method == "InvokeServer"
        or method == "Fire"
        or method == "Invoke" then

        local name = tostring(self:GetFullName()):lower()

        if name:find("collect")
            or name:find("cash")
            or name:find("money")
            or name:find("income")
            or name:find("claim")
            or name:find("pickup")
            or name:find("harvest")
            or name:find("orb") then

            log("NETWORK:", method, self:GetFullName(), ...)
        end
    end

    return oldNamecall(self, ...)
end)

setreadonly(mt, true)

--==================================================
-- 2. Monitor Collector attributes
--==================================================

for name, value in pairs(collector:GetAttributes()) do
    log("ATTRIBUTE:", name, "=", value)
end

collector.AttributeChanged:Connect(function(name)
    log(
        "ATTRIBUTE CHANGED:",
        name,
        "=",
        collector:GetAttribute(name)
    )
end)

--==================================================
-- 3. Monitor Collector descendants
--==================================================

collector.DescendantAdded:Connect(function(obj)
    log(
        "DESCENDANT ADDED:",
        obj:GetFullName(),
        obj.ClassName
    )
end)

collector.DescendantRemoving:Connect(function(obj)
    log(
        "DESCENDANT REMOVED:",
        obj:GetFullName(),
        obj.ClassName
    )
end)

--==================================================
-- 4. Monitor GUI amount
--==================================================

local amount =
    collector:FindFirstChild("FrameTag", true)
    and collector.FrameTag.Frame:FindFirstChild("Amount")

if amount then
    log("INITIAL AMOUNT:", amount.Text)

    amount:GetPropertyChangedSignal("Text"):Connect(function()
        log("AMOUNT CHANGED:", amount.Text)
    end)
end

--==================================================
-- 5. Monitor ValueBases inside collector
--==================================================

for _, obj in ipairs(collector:GetDescendants()) do

    if obj:IsA("ValueBase") then

        log(
            "VALUE:",
            obj:GetFullName(),
            "=",
            obj.Value
        )

        obj.Changed:Connect(function(value)
            log(
                "VALUE CHANGED:",
                obj:GetFullName(),
                "=",
                value
            )
        end)

    end

end

--==================================================
-- 6. CollectionService tags
--==================================================

for _, tag in ipairs(CollectionService:GetTags(collector)) do
    log("COLLECTOR TAG:", tag)
end

--==================================================
-- 7. Watch ALL instances for collect-related names
--==================================================

for _, obj in ipairs(game:GetDescendants()) do

    local n = obj.Name:lower()

    if n:find("collect")
        or n:find("cash")
        or n:find("money")
        or n:find("income")
        or n:find("claim")
        or n:find("pickup")
        or n:find("harvest") then

        log(
            "RELATED INSTANCE:",
            obj:GetFullName(),
            obj.ClassName
        )

    end

end

--==================================================
-- 8. Inspect currently loaded Lua functions
--==================================================

if getgc and debug and debug.getinfo then

    log("Scanning GC functions...")

    local count = 0

    for _, obj in ipairs(getgc(true)) do

        if type(obj) == "function" then

            local ok, info = pcall(debug.getinfo, obj)

            if ok and info then

                local source = tostring(info.source or "")
                local name = tostring(info.name or "")

                local text =
                    (source .. " " .. name):lower()

                if text:find("collect")
                    or text:find("cash")
                    or text:find("money")
                    or text:find("income")
                    or text:find("claim")
                    or text:find("pickup")
                    or text:find("harvest") then

                    count += 1

                    log(
                        "FUNCTION:",
                        "name=" .. name,
                        "source=" .. source
                    )
                end

            end
        end
    end

    log("Matching functions:", count)
end

log("====================================")
log("NOW START THE OTHER AUTO-COLLECT SCRIPT")
log("====================================")
