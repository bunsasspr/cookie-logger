local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local MerchantRemote = RS:WaitForChild("Remotes"):WaitForChild("Merchant")

-- 1) Hook OnClientEvent in case the server pushes stock data through this
--    same remote (bidirectional RemoteEvent usage is common)
MerchantRemote.OnClientEvent:Connect(function(...)
    print("[Merchant OnClientEvent]", os.date("%X"), ...)
end)
print("Listening on Merchant.OnClientEvent...")

-- 2) Teleport near it WITHOUT firing the prompt, then poll the Holder to see
--    if real (non-template) entries appear on their own just from proximity
local mapShop = workspace.Map:FindFirstChild("MapShop")
local model = mapShop and mapShop:FindFirstChild("Merchant")

if not model then
    warn("Merchant not found — make sure it's currently spawned")
else
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if part then
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart")
        hrp.CFrame = part.CFrame
        print("Teleported near Merchant (no prompt fired) — polling Holder for 6s...")

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
                            print(("[Holder, no prompt fired] Real entry: %s"):format(entry.Name))
                        end
                    end
                end
            end
            task.wait(0.5)
        end
        print("Done polling.")
    else
        warn("No BasePart on Merchant model")
    end
end
