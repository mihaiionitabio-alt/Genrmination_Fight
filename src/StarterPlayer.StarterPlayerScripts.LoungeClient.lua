--[========[
Revision 4 engineering reference | 13 September 2026
Authority: StarterPlayer.StarterPlayerScripts.LoungeClient
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Lounge presentation
Future change: Add local effects through lifecycle-managed connections and restore prior camera/UI state on exit.
Preserve dependencies: LoungeSystems and player character lifecycle.
Acceptance cases: Enter/exit, respawn inside, missing props, and device input.
]========]
-- LoungeClient: while you are downstairs, the lab stops shouting at you.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local KEEP = {LabHUD = true, LoungeUI = true}
local hidden = {}

local ui = Instance.new("ScreenGui")
ui.Name = "LoungeUI"; ui.ResetOnSpawn = false; ui.IgnoreGuiInset = true
ui.Enabled = false; ui.Parent = pg

local card = Instance.new("Frame")
card.Size = UDim2.new(0, 300, 0, 128)
card.Position = UDim2.new(0.5, 0, 1, -22)
card.AnchorPoint = Vector2.new(0.5, 1)
card.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
card.BackgroundTransparency = 0.12
card.BorderSizePixel = 0; card.Parent = ui
local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = card
local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(150, 110, 200)
st.Thickness = 1.5; st.Transparency = 0.3; st.Parent = card

local head = Instance.new("TextLabel")
head.Size = UDim2.new(1, 0, 0, 26); head.Position = UDim2.new(0, 0, 0, 8)
head.BackgroundTransparency = 1; head.Font = Enum.Font.GothamBold; head.TextSize = 15
head.TextColor3 = Color3.fromRGB(210, 170, 255); head.Text = "OFF SHIFT  -  no alarms down here"
head.Parent = card

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -22, 1, -40); body.Position = UDim2.new(0, 11, 0, 32)
body.BackgroundTransparency = 1; body.Font = Enum.Font.Gotham; body.TextSize = 13
body.TextColor3 = Color3.fromRGB(215, 218, 224)
body.TextXAlignment = Enum.TextXAlignment.Left; body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.Text = "/play <audio id>  queue a track\n/note <message>  post on the wall\n/stop  clear the queue\nHold E at the jukebox to vote skip\nSit down - click a sofa or stool"
body.Parent = card

local function apply(inLounge)
	ui.Enabled = inLounge
	if inLounge then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and not KEEP[g.Name] and g.Enabled then
				hidden[g] = true
				g.Enabled = false
			end
		end
	else
		for g in pairs(hidden) do
			if g and g.Parent then g.Enabled = true end
		end
		hidden = {}
	end
end

player:GetAttributeChangedSignal("InLounge"):Connect(function()
	apply(player:GetAttribute("InLounge") == true)
end)

-- catch anything the lab spawns while we are downstairs
task.spawn(function()
	while true do
		task.wait(1)
		if player:GetAttribute("InLounge") then
			for _, g in ipairs(pg:GetChildren()) do
				if g:IsA("ScreenGui") and not KEEP[g.Name] and g.Enabled then
					hidden[g] = true
					g.Enabled = false
				end
			end
		end
	end
end)

apply(player:GetAttribute("InLounge") == true)
