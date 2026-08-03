local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")

local WEBHOOK = "https://discord.com/api/webhooks/1533668016800403456/SCZjSG5Ic509v5WAh1dDIzTkdO6LV08hIoEkLCitpwW9iwbwarr7ibOy0Lez59JZDO0T"

local request = syn and syn.request
    or http_request
    or request
    or (http and http.request)

assert(request, "No HTTP request function found!")

local queue = {}

local function send(msg)
    table.insert(queue, msg)
end

task.spawn(function()
    while true do
        if #queue > 0 then
            local content = ""

            while #queue > 0 do
                local line = table.remove(queue, 1)

                if #content + #line + 1 > 1900 then
                    table.insert(queue, 1, line)
                    break
                end

                content ..= line .. "\n"
            end

            pcall(function()
                request({
                    Url = WEBHOOK,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = HttpService:JSONEncode({
                        username = "Delta Logger",
                        content = "```lua\n" .. content .. "```"
                    })
                })
            end)

            task.wait(1)
        else
            task.wait(.25)
        end
    end
end)

local oldPrint = print
hookfunction(print, function(...)
    local t = {}
    for i,v in ipairs({...}) do
        t[i] = tostring(v)
    end
    send("[PRINT] " .. table.concat(t," "))
    return oldPrint(...)
end)

local oldWarn = warn
hookfunction(warn, function(...)
    local t = {}
    for i,v in ipairs({...}) do
        t[i] = tostring(v)
    end
    send("[WARN] " .. table.concat(t," "))
    return oldWarn(...)
end)

local oldError = error
hookfunction(error, function(...)
    local t = {}
    for i,v in ipairs({...}) do
        t[i] = tostring(v)
    end
    send("[ERROR] " .. table.concat(t," "))
    return oldError(...)
end)

LogService.MessageOut:Connect(function(message, typ)
    send(("[%s] %s"):format(typ.Name, message))
end)

print("Logger loaded!")
