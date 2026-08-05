-- Console → Discord Webhook (Delta / Executor version)
-- Execute this with Delta

local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

-- ============== CONFIG ==============
local WEBHOOK_URL = "https://discord.com/api/webhooks/1509743815777587220/W_sKhgd9-SAFexaJz5iJVcKt86Ddl23ouEkqakNRwUp324SwLfhPMfAaJV4r3ntLXQ4i"  -- ← put your webhook here
local THROTTLE = 0.8          -- seconds between messages (prevent rate limit)
local MAX_LEN = 1800
-- ====================================

-- Get the executor's request function (Delta supports this)
local request = http_request or request or (syn and syn.request) or (http and http.request)

if not request then
    warn("[ConsoleLogger] No request function found. Your executor may not support HTTP.")
    return
end

local queue = {}
local sending = false

local function getColor(msgType)
    if msgType == Enum.MessageType.MessageError then
        return 0xFF0000, "ERROR"
    elseif msgType == Enum.MessageType.MessageWarning then
        return 0xFFAA00, "WARN"
    elseif msgType == Enum.MessageType.MessageInfo then
        return 0x00AAFF, "INFO"
    end
    return 0xAAAAAA, "PRINT"
end

local function send(content, title, color)
    local payload = {
        username = "Roblox Console",
        embeds = {{
            title = title,
            description = "```lua\n" .. content .. "\n```",
            color = color,
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    local body = HttpService:JSONEncode(payload)

    local success, result = pcall(function()
        return request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    end)

    if not success then
        warn("[ConsoleLogger] Request failed:", result)
    end
end

-- Separate sender loop (never yields inside MessageOut)
task.spawn(function()
    while true do
        if #queue > 0 and not sending then
            sending = true
            local item = table.remove(queue, 1)
            send(item.content, item.title, item.color)
            task.wait(THROTTLE)
            sending = false
        end
        task.wait(0.1)
    end
end)

-- Safe listener (does NOT yield)
LogService.MessageOut:Connect(function(message, messageType)
    if typeof(message) ~= "string" or message == "" then return end
    if string.find(message, "ConsoleLogger") then return end  -- prevent loop

    local color, title = getColor(messageType)
    local text = message
    if #text > MAX_LEN then
        text = string.sub(text, 1, MAX_LEN) .. "\n... (truncated)"
    end

    table.insert(queue, {
        content = text,
        title = title,
        color = color
    })
end)

-- Also send existing history
task.spawn(function()
    task.wait(1)
    local history = LogService:GetLogHistory()
    for _, entry in ipairs(history) do
        local color, title = getColor(entry.messageType)
        local text = entry.message or ""
        if #text > MAX_LEN then
            text = string.sub(text, 1, MAX_LEN) .. "\n... (truncated)"
        end
        table.insert(queue, {
            content = text,
            title = title,
            color = color
        })
    end
end)

print("[ConsoleLogger] Running on Delta – console messages will be sent to Discord")
