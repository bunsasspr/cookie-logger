-- =================================================================
-- FPS BOOST (LIGHT VERSION) - No Black Screen, No Webhook, No FPS Cap
-- =================================================================

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Lighting = game:GetService("Lighting")
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")

-- =================================================================
-- 1. GRAPHICS SETTINGS
-- =================================================================
pcall(function()
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    settings().Network.IncomingReplicationLag = 0
end)

-- =================================================================
-- 2. ANTI-AFK (Prevents disconnect after 20 min idle)
-- =================================================================
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
    print("[Anti-AFK] Simulated input to prevent disconnect.")
end)

-- =================================================================
-- 3. AUTO REJOIN ON KICK/DISCONNECT
-- =================================================================
pcall(function()
    CoreGui.RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" then
            print("[Auto Rejoin] Disconnect/Kick detected! Rejoining in 3 seconds...")
            task.wait(3)

            if game.JobId and #Players:GetPlayers() > 1 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            else
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end
        end
    end)
end)

-- =================================================================
-- 4. LIGHTING & TERRAIN OPTIMIZATION
-- =================================================================
Lighting.GlobalShadows = false
Lighting.FogEnd = 9e9
Lighting.Brightness = 0
Lighting.ClockTime = 12

if Terrain then
    Terrain.WaterWaveSize = 0
    Terrain.WaterWaveSpeed = 0
    Terrain.WaterReflectance = 0
    Terrain.WaterTransparency = 1
    pcall(function() Terrain.Decoration = false end)
end

for _, obj in pairs(Lighting:GetChildren()) do
    if obj:IsA("PostEffect") or obj:IsA("Sky") or obj:IsA("Atmosphere") or obj:IsA("Clouds") then
        obj:Destroy()
    end
end

-- =================================================================
-- 5. MUTE ALL SOUNDS
-- =================================================================
for _, sound in pairs(game:GetDescendants()) do
    if sound:IsA("Sound") then
        sound:Stop()
        sound.Volume = 0
    end
end

-- =================================================================
-- 6. WORKSPACE OPTIMIZATION (materials, shadows, effects, decals)
-- =================================================================
local function ultraOptimize(v)
    if v:IsA("BasePart") then
        v.Material = Enum.Material.SmoothPlastic
        v.Reflectance = 0
        v.CastShadow = false
        if v:IsA("MeshPart") then
            v.RenderFidelity = Enum.RenderFidelity.Performance
        end
    elseif v:IsA("Decal") or v:IsA("Texture") or v:IsA("ShirtGraphic") then
        v:Destroy()
    elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") or v:IsA("Beam") or v:IsA("Highlight") then
        v.Enabled = false
    elseif v:IsA("SpecialMesh") then
        v.TextureId = ""
    end
end

for _, v in pairs(workspace:GetDescendants()) do
    ultraOptimize(v)
end

workspace.DescendantAdded:Connect(function(v)
    ultraOptimize(v)
end)

print("[FPS Boost] Light optimization script loaded successfully!")
