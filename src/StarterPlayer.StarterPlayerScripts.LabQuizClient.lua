--[========[
Revision 4 engineering reference | 13 September 2026
Authority: StarterPlayer.StarterPlayerScripts.LabQuizClient
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Quiz UI
Future change: Use an accessible modal with touch and keyboard choices and a clear timeout. Display server challenge data only.
Preserve dependencies: LabEquipment pendingQuizzes and MathQuizActive.
Acceptance cases: Wrong/late/replayed reply, cancel, death, target destruction, and overlap with GWAP HUD.
]========]

-- Addition popup: click/tap one of three answers. No phone keyboard or
-- changes to the player's camera, aiming, or movement controls are required.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("LabMathQuiz")
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("LabMathConsole")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LabMathConsole"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 60
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "AdditionQuiz"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.46)
panel.Size = UDim2.new(1, -28, 0, 238)
panel.BackgroundColor3 = Color3.fromRGB(14, 24, 30)
panel.BorderSizePixel = 0
panel.Active = true
panel.Visible = false
panel.Parent = gui
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(440, 238)
sizeLimit.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(95, 225, 170)
stroke.Thickness = 2
stroke.Parent = panel

local function label(name, y, height, size, colour)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Size = UDim2.new(1, -28, 0, height)
    item.Position = UDim2.fromOffset(14, y)
    item.BackgroundTransparency = 1
    item.TextColor3 = colour
    item.TextSize = size
    item.Font = Enum.Font.GothamBold
    item.TextWrapped = true
    item.Parent = panel
    return item
end
local title = label("Title", 10, 26, 18, Color3.fromRGB(110, 240, 185))
title.Size = UDim2.new(1, -70, 0, 26)
title.Text = "ADDITION CHECK"
local reason = label("Task", 40, 34, 13, Color3.fromRGB(195, 213, 223))
local question = label("Question", 76, 45, 34, Color3.fromRGB(250, 250, 250))
local status = label("Status", 190, 34, 13, Color3.fromRGB(255, 210, 100))
local cancel = Instance.new("TextButton")
cancel.Name = "Cancel"
cancel.Position = UDim2.new(1, -42, 0, 6)
cancel.Size = UDim2.fromOffset(36, 36)
cancel.BackgroundTransparency = 1
cancel.Text = "×"
cancel.TextColor3 = Color3.fromRGB(220, 228, 232)
cancel.TextSize = 28
cancel.Modal = true -- Let the pointer select an answer even in first-person view.
cancel.Parent = panel

local activeId
local submitted = false
local buttons = {}
local function answer(value)
    if not activeId or submitted then return end
    submitted = true
    status.Text = "Checking answer…"
    remote:FireServer(activeId, value)
end
for i = 1, 3 do
    local button = Instance.new("TextButton")
    button.Name = "Answer" .. i
    button.Position = UDim2.new((i - 1) / 3, 10, 0, 128)
    button.Size = UDim2.new(1 / 3, -14, 0, 56)
    button.BackgroundColor3 = Color3.fromRGB(50, 146, 112)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 26
    button.Parent = panel
    local rounding = Instance.new("UICorner")
    rounding.CornerRadius = UDim.new(0, 9)
    rounding.Parent = button
    button.Activated:Connect(function() answer(button:GetAttribute("Answer")) end)
    buttons[i] = button
end
cancel.Activated:Connect(function() answer(nil) end)

remote.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then return end
    if payload.Close then
        if payload.Id == activeId then panel.Visible = false; activeId = nil end
        return
    end
    activeId = payload.Id
    submitted = false
    reason.Text = tostring(payload.Reason or "Repair or collect a plant")
    question.Text = tostring(payload.Question or "?") .. " = ?"
    for i, button in ipairs(buttons) do
        local value = payload.Choices and payload.Choices[i]
        button.Text = tostring(value or "?")
        button:SetAttribute("Answer", value)
    end
    panel.Visible = true
    local thisId = activeId
    local expires = os.clock() + (tonumber(payload.Seconds) or 60)
    task.spawn(function()
        while activeId == thisId and panel.Visible do
            local left = math.max(0, math.ceil(expires - os.clock()))
            if not submitted then status.Text = "Tap the correct answer • " .. left .. "s • × cancels" end
            if left <= 0 then
                if not submitted then answer(nil) end
                panel.Visible = false
                break
            end
            task.wait(0.2)
        end
    end)
end)
