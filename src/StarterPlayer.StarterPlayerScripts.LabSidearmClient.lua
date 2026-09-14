--[========[
Revision 4 engineering reference | 13 September 2026
Authority: StarterPlayer.StarterPlayerScripts.LabSidearmClient
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Tool bootstrap
Future change: Keep one controller instance per equipped original Tool and one active camera owner.
Preserve dependencies: BlasterController AutoBind/Enable/Disable.
Acceptance cases: Rapid equip, respawn, backpack replacement, duplicate script prevention.
This revision changes documentation only in this source; executable input/aiming behavior is preserved.
]========]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

	-- The hunt counter belongs inside RoleHUD; a second top-centre panel covered
	-- the crosshair and duplicated information on phones.
	task.spawn(function()
		local complex = workspace:WaitForChild("Laboratory_Complex", 60)
		if not complex then return end
		local playerGui = player:WaitForChild("PlayerGui", 30)
		if not playerGui then return end
		local roleGui = playerGui:WaitForChild("RoleHUD", 30)
		local frame = roleGui and roleGui:FindFirstChildOfClass("Frame")
		local label = frame and frame:FindFirstChild("TargetsLabel")
		if not label then return end

	local function refresh()
		local killed = complex:GetAttribute("BotsKilled") or 0
		local total = complex:GetAttribute("BotsTotal") or 0
		if total > 0 and killed >= total then
				label.Text = "LAB CLEARED  •  " .. killed .. " / " .. total
			label.TextColor3 = Color3.fromRGB(125, 255, 155)
		else
				label.Text = string.format("TARGETS  %d / %d", killed, total)
			label.TextColor3 = Color3.fromRGB(255, 205, 120)
		end
	end
	complex:GetAttributeChangedSignal("BotsKilled"):Connect(refresh)
	complex:GetAttributeChangedSignal("BotsTotal"):Connect(refresh)
	refresh()
end)

-- One lightweight bootstrap watches standard Tools as they move between the
-- Backpack and Character. All device input/camera behavior lives in the module.
local modules = ReplicatedStorage:WaitForChild("Modules", 30)
if not modules then
	warn("Blaster modules were not installed")
	return
end

local BlasterController = require(modules:WaitForChild("BlasterController"))
BlasterController.AutoBind()
