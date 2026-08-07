local mapShop = workspace.Map:FindFirstChild("MapShop")
local model = mapShop and mapShop:FindFirstChild("Merchant")

if not model then
    warn("Merchant not found — make sure it's currently spawned")
    return
end

local prompt
for _, inst in ipairs(model:GetDescendants()) do
    if inst:IsA("ProximityPrompt") then
        prompt = inst
        break
    end
end

if not prompt then
    warn("No ProximityPrompt found on Merchant")
    return
end

print("Prompt path:", prompt:GetFullName())
print("ActionText:", prompt.ActionText)
print("ObjectText:", prompt.ObjectText)
print("HoldDuration:", prompt.HoldDuration)
print("MaxActivationDistance:", prompt.MaxActivationDistance)
print("RequiresLineOfSight:", prompt.RequiresLineOfSight)
print("Enabled:", prompt.Enabled)
print("Style:", prompt.Style)
print("KeyboardKeyCode:", prompt.KeyboardKeyCode)
print("UIOffset:", prompt.UIOffset)

-- also watch if the Merchant GUI's visibility ever changes, in case it opens
-- but somewhere off-screen or the Visible property just isn't flipping
local ok, mainFrame = pcall(function()
    return game.Players.LocalPlayer.PlayerGui.Main.Canvas.Merchant.Main
end)
if ok and mainFrame then
    print("Merchant.Main currently Visible:", mainFrame.Visible)
    mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
        print("[Merchant.Main.Visible changed to]", mainFrame.Visible, os.date("%X"))
    end)
    print("Watching for Visible changes... now try fireproximityprompt or interact manually")
end
