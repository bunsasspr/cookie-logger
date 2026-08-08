print("========== NEW FUNCTIONS ==========")

local count = 0

for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" and not _G.__before[fn] then
        count += 1

        local ok, info = pcall(debug.getinfo, fn)

        if ok and info then
            print("")
            print("----- NEW #" .. count .. " -----")
            print("Function:", tostring(fn))
            print("Name:", tostring(info.name))
            print("Source:", tostring(info.source))
            print("Line:", tostring(info.currentline))

            if debug.getconstants then
                local okc, constants = pcall(debug.getconstants, fn)

                if okc and type(constants) == "table" then
                    for i, v in pairs(constants) do
                        if type(v) == "string"
                            or type(v) == "number"
                            or type(v) == "boolean" then
                            print(
                                "CONST[" .. tostring(i) .. "]:",
                                tostring(v)
                            )
                        end
                    end
                end
            end
        end
    end
end

print("")
print("NEW FUNCTIONS:", count)
print("===================================")
