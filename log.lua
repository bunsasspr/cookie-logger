-- Console Logger → Discord Webhook
-- Place in ServerScriptService as a Script

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

-- ================== CONFIG ==================
local WEBHOOK_URL = "https://discord.com/api/webhooks/1533668016800403456/SCZjSG5Ic509v5WAh1dDIzTkdO6LV08hIoEkLCitpwW9iwbwarr7ibOy0Lez59JZDO0T"  -- Replace this!

-- Optional proxy (recommended for live games). Leave empty "" to try direct.
-- Popular free options change often. Examples:
-- "https://discord-webhook.com/api/webhook/send"  (needs special payload)
-- Or self-host / use a public proxy like hooks.hyra.io style
local PROXY_URL = ""  -- e.g. "https://your-proxy.example/api/webhooks/..."

local SEND_EXISTING_HISTORY = true   -- Send previous logs when the script starts
local MAX_MESSAGE_LENGTH = 1900      -- Discord limit is 2000
local THROTTLE_SECONDS = 0.6         -- Minimum delay between webhook posts
local ONLY_IN_STUDIO = false         -- Set true if you only want Studio debugging
-- ============================================

local lastSent = 0
local queue = {}

local function getTypeName(messageType)
	if messageType == Enum.MessageType.MessageError then
		return "ERROR", 0xFF0000
	elseif messageType == Enum.MessageType.MessageWarning then
		return "WARN", 0xFFAA00
	elseif messageType == Enum.MessageType.MessageInfo then
		return "INFO", 0x00AAFF
	else
		return "PRINT", 0xAAAAAA
	end
end

local function sendToDiscord(content, title, color)
	if ONLY_IN_STUDIO and not RunService:IsStudio() then
		return
	end

	local payload = {
		username = "Roblox Console",
		embeds = {{
			title = title or "Console Message",
			description = content,
			color = color or 0x5865F2,
			timestamp = DateTime.now():ToIsoDate(),
			footer = {
				text = "PlaceId: " .. tostring(game.PlaceId)
			}
		}}
	}

	local body = HttpService:JSONEncode(payload)
	local url = WEBHOOK_URL

	-- Simple proxy support (adjust payload if your proxy needs a different format)
	if PROXY_URL ~= "" then
		url = PROXY_URL
		-- Many proxies expect the real webhook URL inside the body
		-- Uncomment & adjust if needed:
		-- body = HttpService:JSONEncode({
		--     webhookUrl = WEBHOOK_URL,
		--     payload = payload
		-- })
	end

	local success, err = pcall(function()
		HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
	end)

	if not success then
		warn("[ConsoleLogger] Failed to send webhook:", err)
	end
end

local function processMessage(message, messageType)
	if typeof(message) ~= "string" or message == "" then
		return
	end

	-- Avoid infinite loop if the webhook itself errors
	if string.find(message, "ConsoleLogger") or string.find(message, "HttpService") then
		return
	end

	local typeName, color = getTypeName(messageType)
	local truncated = message
	if #truncated > MAX_MESSAGE_LENGTH then
		truncated = string.sub(message, 1, MAX_MESSAGE_LENGTH - 20) .. "\n... (truncated)"
	end

	local now = os.clock()
	if now - lastSent < THROTTLE_SECONDS then
		table.insert(queue, {truncated, typeName, color})
		return
	end

	lastSent = now
	sendToDiscord("```lua\n" .. truncated .. "\n```", typeName, color)
end

-- Flush queue periodically
task.spawn(function()
	while true do
		task.wait(THROTTLE_SECONDS)
		if #queue > 0 then
			local item = table.remove(queue, 1)
			lastSent = os.clock()
			sendToDiscord("```lua\n" .. item[1] .. "\n```", item[2], item[3])
		end
	end
end)

-- Listen for new messages
LogService.MessageOut:Connect(function(message, messageType)
	processMessage(message, messageType)
end)

-- Optionally send existing history on start
if SEND_EXISTING_HISTORY then
	local history = LogService:GetLogHistory()
	for _, entry in ipairs(history) do
		processMessage(entry.message, entry.messageType)
	end
end

print("[ConsoleLogger] Started – sending console output to Discord webhook")
