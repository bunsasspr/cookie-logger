-- Console Logger for Delta Executor
local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

local WEBHOOK_URL = "https://discord.com/api/webhooks/1509743815777587220/W_sKhgd9-SAFexaJz5iJVcKt86Ddl23ouEkqakNRwUp324SwLfhPMfAaJV4r3ntLXQ4i" -- ← put your webhook here

local request = http_request or request or (syn and syn.request) or (http and http.request)

if not request then
    warn("No request function found")
    return
end

local queue = {}
local busy = false

local function getInfo(msgType)
    if msgType == Enum.MessageType.MessageError then
        return "ERROR", 0xFF0000
    elseif msgType == Enum.MessageType.MessageWarning then
        return "WARN", 0xFFAA00
    else
        return "PRINT", 0xAAAAAA
    end
end

-- Sender loop (safe, never runs inside MessageOut)
task.spawn(function()
    while true do
        if #queue > 0 and not busy then
            busy = true
            local data = table.remove(queue, 1)

            local payload = {
                username = "Roblox Console",
                embeds = {{
                    title = data.title,
                    description = "```lua\n" .. data.content .. "\n```",
                    color = data.color,
                    timestamp = DateTime.now():ToIsoDate()
                }}
            }

            pcall(function()
                request({
                    Url = WEBHOOK_URL,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode(payload)
                })
            end)

            task.wait(0.8) -- prevent rate limit
            busy = false
        end
        task.wait(0.15)
    end
end)

-- Listener (does NOT call any yielding function)
LogService.MessageOut:Connect(function(message, messageType)
    if typeof(message) ~= "string" or #message == 0 then return end
    if string.find(message, "ConsoleLogger") or string.find(message, "Running on Delta") then return end

    local title, color = getInfo(messageType)
    local text = message
    if #text > 1800 then
        text = string.sub(text, 1, 1800) .. "\n... (truncated)"
    end

    table.insert(queue, {
        content = text,
        title = title,
        color = color
    })
end)

print("[ConsoleLogger] Running on Delta – ready")
