local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local MerchantRemote = RS:WaitForChild("Remotes"):WaitForChild("Merchant")

MerchantRemote.OnClientEvent:Connect(function(...)
    print("[Merchant OnClientEvent]", os.date("%X"), ...)
end)
print("Listening on Merchant.OnClientEvent...")

local mapShop = workspace.Map:FindFirstChild("MapShop")
local model = mapShop and mapShop:FindFirstChild("Merchant")

if not model then
    warn("Merchant not found — make sure it's currently spawned")
    return
end

local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
if not part then
    warn("No BasePart on Merchant model")
    return
end

local char = player.Character or player.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")
local target = part.CFrame

hrp.CFrame = target
hrp.AssemblyLinearVelocity = Vector3.zero
hrp.AssemblyAngularVelocity = Vector3.zero

local pinning = true
local pinConn = RunService.Heartbeat:Connect(function()
    if pinning then
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
end)

print("Pinned at Merchant (no prompt fired) — polling Holder for 6s...")

local deadline = tick() + 6
while tick() < deadline do
    local ok, holder = pcall(function()
        return player.PlayerGui.Main.Canvas.Merchant.Main.Holder
    end)
    if ok and holder then
        for _, entry in ipairs(holder:GetChildren()) do
            if entry.Name ~= "TextPlaceHolder" and not entry.Name:find("Template") then
                local diceName = entry:FindFirstChild("DiceName")
                local foodName = entry:FindFirstChild("FoodName")
                if diceName or foodName then
                    print(("[Holder, pinned, no prompt] Real entry: %s"):format(entry.Name))
                end
            end
        end
    end
    task.wait(0.5)
end

pinning = false
pinConn:Disconnect()
print("Done polling.")
