-- ===== Locate restock countdown label + any backing timestamp source =====
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function findLabelsContaining(root, substring)
    local found = {}
    local function scan(instance)
        local ok, text = pcall(function() return instance.Text end)
        if ok and text and text:find(substring) then
            table.insert(found, instance)
        end
        for _, child in ipairs(instance:GetChildren()) do
            scan(child)
        end
    end
    scan(root)
    return found
end

local matches = findLabelsContaining(player.PlayerGui, "New items")
if #matches == 0 then
    warn("No label found containing 'New items' — text might be split across multiple labels, or built with string.format at runtime. Try searching for 'items in' or just ':' instead.")
else
    for _, label in ipairs(matches) do
        print("FOUND LABEL:", label:GetFullName())
        print("  Text:", label.Text)

        -- dump attributes on the label itself and its ancestors up to PlayerGui,
        -- looking for a timestamp-like NumberValue/IntValue or attribute
        local inst = label
        while inst and inst ~= player.PlayerGui.Parent do
            local attrs = inst:GetAttributes()
            if next(attrs) then
                print("  Attributes on", inst:GetFullName(), ":")
                for k, v in pairs(attrs) do
                    print("    ", k, "=", v)
                end
            end
            for _, child in ipairs(inst:GetChildren()) do
                if child:IsA("NumberValue") or child:IsA("IntValue") then
                    print("  Value object:", child:GetFullName(), "=", child.Value)
                end
            end
            inst = inst.Parent
        end
    end
end

-- also check if a LocalScript is driving it (won't give us source, but confirms client-side calc)
print("=== Also checking ReplicatedStorage for a shop data folder ===")
local RS = game:GetService("ReplicatedStorage")
local function scanNames(instance, depth, maxDepth)
    if depth > maxDepth then return end
    for _, child in ipairs(instance:GetChildren()) do
        if child.Name:lower():find("shop") or child.Name:lower():find("restock") or child.Name:lower():find("dice") or child.Name:lower():find("potion") then
            print(string.rep("  ", depth) .. child:GetFullName() .. " [" .. child.ClassName .. "]")
        end
        scanNames(child, depth + 1, maxDepth)
    end
end
scanNames(RS, 0, 4)
