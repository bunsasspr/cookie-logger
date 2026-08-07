local Players = game:GetService("Players")
local player = Players.LocalPlayer
local holder = player.PlayerGui.Main.Canvas.Merchant.Main.Holder

for _, child in ipairs(holder:GetChildren()) do
    local layoutOrder = "n/a"
    pcall(function() layoutOrder = tostring(child.LayoutOrder) end)

    local extra = ""
    local nameLabel = child:FindFirstChild("NameLabel")
    local diceName = child:FindFirstChild("DiceName")
    local foodName = child:FindFirstChild("FoodName")
    if nameLabel then extra = "NameLabel=" .. nameLabel.Text end
    if diceName then extra = "DiceName=" .. diceName.Text end
    if foodName then extra = "FoodName=" .. foodName.Text end

    print(child.Name, "[" .. child.ClassName .. "]", "LayoutOrder=" .. layoutOrder, extra)
end
