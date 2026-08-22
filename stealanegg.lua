local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ====== CHANGE THESE ======
local IMAGE_ID = "rbxassetid://121204432291135"          -- your free decal
local SOUND_URL = "https://raw.githubusercontent.com/bunsasspr/cookie-logger/refs/heads/main/Jeff%20The%20Killer%20loud%20jumpscare%20-%20Mimek.mp3"  -- direct raw GitHub link (or any direct .mp3/.ogg link)
-- ==========================

-- Create GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Jumpscare"
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999999
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BorderSizePixel = 0
bg.Parent = screenGui

local image = Instance.new("ImageLabel")
image.Size = UDim2.fromScale(1, 1)
image.BackgroundTransparency = 1
image.Image = IMAGE_ID
image.ScaleType = Enum.ScaleType.Fit
image.Parent = screenGui

-- Download + play the sound
local function playExternalSound(url)
    local request = http_request or (syn and syn.request) or request
    if not request then
        warn("Your executor doesn't support http requests")
        return
    end

    local success, response = pcall(function()
        return request({
            Url = url,
            Method = "GET"
        })
    end)

    if success and response and response.Body then
        local fileName = "jumpscare_temp.mp3"
        writefile(fileName, response.Body)

        local sound = Instance.new("Sound")
        sound.SoundId = getcustomasset(fileName)
        sound.Volume = 3
        sound.Parent = SoundService
        sound:Play()

        -- optional: clean up the file later
        -- delfile(fileName)
    else
        warn("Failed to download sound")
    end
end

playExternalSound(SOUND_URL)

-- Block most input
UserInputService.ModalEnabled = true

-- Optional: auto remove after a few seconds
--[[
task.delay(5, function()
    screenGui:Destroy()
    UserInputService.ModalEnabled = false
end)
]]
