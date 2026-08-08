local TARGET = "=QiUmItaUgqarWtuEiLaRxBKPQ"

print("========== LUAST TARGET ==========")

local count = 0
local seen = {}

for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" and not seen[fn] then
        seen[fn] = true

        local ok, info = pcall(debug.getinfo, fn)

        if ok and info and info.source == TARGET then
            count += 1

            print("")
            print("===== FUNCTION #" .. count .. " =====")
            print("Function:", tostring(fn))
            print("Name:", tostring(info.name))
            print("Line:", tostring(info.currentline))

            local okc, constants = pcall(debug.getconstants, fn)

            if okc and type(constants) == "table" then
                for i, value in pairs(constants) do
                    print(
                        "CONST[" .. tostring(i) .. "]:",
                        typeof(value),
                        tostring(value)
                    )
                end
            end

            if debug.getupvalues then
                local oku, upvalues = pcall(debug.getupvalues, fn)

                if oku and type(upvalues) == "table" then
                    print("-- UPVALUES --")

                    for i, value in pairs(upvalues) do
                        print(
                            "UPVALUE[" .. tostring(i) .. "]:",
                            typeof(value),
                            tostring(value)
                        )
                    end
                end
            end
        end
    end
end

print("")
print("TOTAL:", count)
print("==================================")
