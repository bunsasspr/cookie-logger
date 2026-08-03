-- Console Logger → Discord Webhook (Delta / UNC)
-- Replace the webhook if needed

local WEBHOOK = "https://discord.com/api/webhooks/1533668016800403456/SCZjSG5Ic509v5WAh1dDIzTkdO6LV08hIoEkLCitpwW9iwbwarr7ibOy0Lez59JZDO0T"

local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

-- Rate limiting
local queue = {}
local lastSend = 0
local SEND_DELAY = 1.2 -- seconds between messages (safe for Discord)

local function sendToDiscord(content)
    table.insert(queue, content)
end

task.spawn(function()
    while true do
        if #queue > 0 and tick() - lastSend >= SEND_DELAY then
            local msg = table.remove(queue, 1)
            lastSend = tick()

            local success, err = pcall(function()
                request({
                    Url = WEBHOOK,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = HttpService:JSONEncode({
                        content = msg
                    })
                })
            end)

            if not success then
                warn("[Console Logger] Failed to send:", err)
            end
        end
        task.wait(0.1)
    end
end)

local function formatMessage(message, messageType)
    local prefix = "[Print]"
    if messageType == Enum.MessageType.MessageWarning then
        prefix = "[Warning]"
    elseif messageType == Enum.MessageType.MessageError then
        prefix = "[Error]"
    elseif messageType == Enum.MessageType.MessageInfo then
        prefix = "[Info]"
    end

    -- Discord has a 2000 character limit
    local text = string.format("```%s %s```", prefix, tostring(message))
    if #text > 1900 then
        text = text:sub(1, 1900) .. "...```"
    end
    return text
end

-- Send existing console history
local history = LogService:GetLogHistory()
for _, entry in ipairs(history) do
    sendToDiscord(formatMessage(entry.message, entry.messageType))
end

-- Log new messages
LogService.MessageOut:Connect(function(message, messageType)
    sendToDiscord(formatMessage(message, messageType))
end)

print("[Console Logger] Started – logging to Discord webhook")
