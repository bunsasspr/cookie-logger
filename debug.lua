print("========== COLLECTOR FUNCTION SCAN ==========")

local keywords = {
    "collect",
    "collector",
    "claim",
    "money",
    "cash",
    "income",
    "drop",
    "pickup",
    "itemholder",
    "itemholder1",
}

local function interesting(text)
    if type(text) ~= "string" then
        return false
    end

    text = text:lower()

    for _, keyword in ipairs(keywords) do
        if text:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

local found = {}
local count = 0

for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" then

        local okInfo, info = pcall(debug.getinfo, fn)

        if okInfo and info then

            local matched = false
            local reasons = {}

            -- Function name/source
            if interesting(info.name) then
                matched = true
                table.insert(reasons, "name=" .. tostring(info.name))
            end

            if interesting(info.source) then
                matched = true
                table.insert(reasons, "source=" .. tostring(info.source))
            end

            -- Constants
            if debug.getconstants then
                local okConstants, constants =
                    pcall(debug.getconstants, fn)

                if okConstants and type(constants) == "table" then
                    for index, constant in pairs(constants) do
                        if interesting(constant) then
                            matched = true

                            table.insert(
                                reasons,
                                "constant[" ..
                                tostring(index) ..
                                "]=" ..
                                tostring(constant)
                            )
                        end
                    end
                end
            end

            if matched and not found[fn] then
                found[fn] = true
                count += 1

                print("")
                print("----- MATCH #" .. count .. " -----")
                print("Function:", tostring(fn))
                print("Name:", tostring(info.name))
                print("Source:", tostring(info.source))
                print("Line:", tostring(info.currentline))

                for _, reason in ipairs(reasons) do
                    print("MATCH:", reason)
                end

                -- Upvalues
                if debug.getupvalues then
                    local okUpvalues, upvalues =
                        pcall(debug.getupvalues, fn)

                    if okUpvalues and type(upvalues) == "table" then
                        for k, v in pairs(upvalues) do
                            local valueText = tostring(v)

                            if interesting(valueText) then
                                print(
                                    "UPVALUE:",
                                    tostring(k),
                                    valueText
                                )
                            end
                        end
                    end
                end
            end
        end
    end
end

print("")
print("==============================================")
print("MATCHING FUNCTIONS:", count)
print("==============================================")
