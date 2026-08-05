-- Console Logger for Delta Executor (Batched)
local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

local WEBHOOK_URL = "https://discord.com/api/webhooks/1509743815777587220/W_sKhgd9-SAFexaJz5iJVcKt86Ddl23ouEkqakNRwUp324SwLfhPMfAaJV4r3ntLXQ4i" -- ← your webhook

local request = http_request or request or (syn and syn.request) or (http and http.request)
if not request then
    warn("[ConsoleLogger] No request function found")
    return
end

-- ======================== CONFIG ========================
local BATCH_INTERVAL   = 1.2      -- seconds between sends (adjust if you get rate limited)
local MAX_DESC_LENGTH  = 3900     -- safe limit under Discord's 4096
local MAX_LINES_PER_BATCH = 80    -- hard safety cap
-- ========================================================

local queue = {}          -- raw messages waiting to be batched
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

local function createEmbed(title, content, color)
    return {
        title = title,
        description = "```lua\n" .. content .. "\n```",
        color = color,
        timestamp = DateTime.now():ToIsoDate()
    }
end

-- Builds 1 or 2 embeds from a list of lines
local function buildEmbeds(lines)
    if #lines == 0 then return {} end

    local fullText = table.concat(lines, "\n")
    
    -- Case 1: Everything fits in one embed
    if #fullText <= MAX_DESC_LENGTH then
        local title, color = getInfo(Enum.MessageType.MessageOutput) -- default
        -- Try to detect dominant type (simple heuristic)
        for _, line in ipairs(lines) do
            if string.find(line, "ERROR") or string.find(line, "error") then
                title, color = "ERROR", 0xFF0000
                break
            elseif string.find(line, "WARN") or string.find(line, "warn") then
                title, color = "WARN", 0xFFAA00
            end
        end
        return { createEmbed(title .. " (" .. #lines .. " lines)", fullText, color) }
    end

    -- Case 2: Needs 2 embeds → split roughly in half by character count
    local mid = math.floor(#fullText / 2)
    -- Prefer splitting at a newline
    local splitPos = mid
    for i = mid, math.max(1, mid - 200), -1 do
        if string.sub(fullText, i, i) == "\n" then
            splitPos = i
            break
        end
    end

    local part1 = string.sub(fullText, 1, splitPos)
    local part2 = string.sub(fullText, splitPos + 1)

    -- Truncate if still too long (very rare)
    if #part1 > MAX_DESC_LENGTH then
        part1 = string.sub(part1, 1, MAX_DESC_LENGTH - 20) .. "\n... (truncated)"
    end
    if #part2 > MAX_DESC_LENGTH then
        part2 = string.sub(part2, 1, MAX_DESC_LENGTH - 20) .. "\n... (truncated)"
    end

    return {
        createEmbed("CONSOLE BATCH (1/2)", part1, 0x5865F2),
        createEmbed("CONSOLE BATCH (2/2)", part2, 0x5865F2)
    }
end

-- Sender loop
task.spawn(function()
    while true do
        if #queue > 0 and not busy then
            busy = true

            -- Take up to MAX_LINES_PER_BATCH messages
            local batch = {}
            local count = math.min(#queue, MAX_LINES_PER_BATCH)
            for i = 1, count do
                table.insert(batch, table.remove(queue, 1))
            end

            local embeds = buildEmbeds(batch)

            if #embeds > 0 then
                local payload = {
                    username = "Roblox Console",
                    embeds = embeds
                }

                local success, err = pcall(function()
                    request({
                        Url = WEBHOOK_URL,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = HttpService:JSONEncode(payload)
                    })
                end)

                if not success then
                    warn("[ConsoleLogger] Failed to send:", err)
                end
            end

            task.wait(BATCH_INTERVAL)
            busy = false
        end
        task.wait(0.1)
    end
end)

-- Listener
LogService.MessageOut:Connect(function(message, messageType)
    if typeof(message) ~= "string" or #message == 0 then return end
    if string.find(message, "ConsoleLogger") or string.find(message, "Running on Delta") then return end

    -- Optional: prefix with type for clarity inside the batch
    local prefix = ""
    if messageType == Enum.MessageType.MessageError then
        prefix = "[ERROR] "
    elseif messageType == Enum.MessageType.MessageWarning then
        prefix = "[WARN] "
    end

    local text = prefix .. message
    if #text > 1800 then
        text = string.sub(text, 1, 1800) .. " ... (truncated)"
    end

    table.insert(queue, text)
end)

print("[ConsoleLogger] Running on Delta – Batched mode ready")
