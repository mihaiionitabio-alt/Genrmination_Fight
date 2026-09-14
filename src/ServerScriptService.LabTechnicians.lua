--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.LabTechnicians
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Legacy worker service
Future change: Check which templates actually have Humanoids before extending its path loop. Avoid competing with LabEquipment worker motion.
Preserve dependencies: LabWorkerBot tags and template structure.
Acceptance cases: No double movement, no idle thread leak, valid target assignment, and bounded retry.
]========]
-- LabTechnicians: 15 human technicians who panic, tire, call for help and die.
-- They CANNOT repair anything: they can only locate faults and beg the player.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

--------------------------------------------------------------------
-- AUDIO: paste asset IDs you OWN or that are royalty-free.
-- Left empty deliberately: every free "scream"/"help me" asset on the
-- Creator Store is ripped from a commercial game, which risks having
-- your experience moderated. Bubbles work without any audio.
--------------------------------------------------------------------
local AUDIO = {
	scream_f = "",   -- e.g. "rbxassetid://123456789"
	scream_m = "",
	help     = "",
	follow   = "",
}

local PANIC_RADIUS   = 26
local HELP_COOLDOWN  = 9
local DAMAGE_PER_SEC = 2.5
local DAMAGE_RADIUS  = 11
local HEALTH_FLOOR   = 12
local RESPAWN_DELAY  = 25

local HELP_LINES = {
	"Help! %s is failing!", "Please help me, I can't repair this!",
	"Follow me - %s is critical!", "Come with me, hurry!",
	"I'm only a technician, I need you!", "Someone repair %s, please!",
}
local TIRED_LINES = {
	"I need a break...", "I can't keep running like this.",
	"My legs are gone. Give me a second.", "Too many alarms today...",
}

local function bubbleOf(rig)
	local head = rig:FindFirstChild("Head")
	if not head then return nil end
	local bb = head:FindFirstChild("SpeechBubble")
	if bb then return bb:FindFirstChildOfClass("TextLabel"), bb end
	bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"
	bb.Size = UDim2.new(0, 220, 0, 42)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Enabled = false
	bb.Parent = head
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 1, 0); f.BackgroundColor3 = Color3.fromRGB(18, 22, 24)
	f.BackgroundTransparency = 0.15; f.BorderSizePixel = 0; f.Parent = bb
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 120, 100); st.Thickness = 1.5; st.Parent = f
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -12, 1, -6); t.Position = UDim2.new(0, 6, 0, 3)
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamMedium; t.TextSize = 13
	t.TextColor3 = Color3.fromRGB(240, 245, 245); t.TextWrapped = true; t.Parent = f
	return t, bb
end

local function say(rig, text, colour)
	local label, bb = bubbleOf(rig)
	if not label then return end
	label.Text = text
	local stroke = bb:FindFirstChildOfClass("Frame"):FindFirstChildOfClass("UIStroke")
	if stroke and colour then stroke.Color = colour end
	bb.Enabled = true
	task.delay(4.5, function() if bb and bb.Parent then bb.Enabled = false end end)
end

local function playSound(rig, key)
	local id = AUDIO[key]
	if not id or id == "" then return end
	local head = rig:FindFirstChild("Head")
	if not head then return end
	local snd = Instance.new("Sound")
	snd.SoundId = id; snd.Volume = 1; snd.RollOffMaxDistance = 90
	snd.Parent = head; snd:Play()
	snd.Ended:Connect(function() snd:Destroy() end)
	task.delay(8, function() if snd and snd.Parent then snd:Destroy() end end)
end

local function labelOf(equip)
	return equip:GetAttribute("GrowthCode") or equip:GetAttribute("Kind") or equip.Name
end

local function nearestFault(pos)
	local best, bestD = nil, PANIC_RADIUS
	for _, e in ipairs(CollectionService:GetTagged("LabEquipment")) do
		if e:GetAttribute("FunctionalState") == "FAILED" then
			local ok, p = pcall(function() return e:GetPivot().Position end)
			if ok then
				local d = (p - pos).Magnitude
				if d < bestD then best, bestD = e, d end
			end
		end
	end
	return best, bestD
end

local function setStatus(rig, text, colour)
	local head = rig:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("NameTag")
	local st = tag and tag:FindFirstChild("Status")
	if st then st.Text = text; if colour then st.TextColor3 = colour end end
end

local function reviveLater(rig, spawnPivot)
	task.delay(RESPAWN_DELAY, function()
		if not rig or not rig.Parent then return end
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		rig:PivotTo(spawnPivot)
		hum.Health = hum.MaxHealth
		rig:SetAttribute("Fatigue", 0)
		rig:SetAttribute("Panic", false)
		rig:SetAttribute("NeedsHelp", false)
		rig:SetAttribute("KnockedOut", false)
		setStatus(rig, "Lab Technician", Color3.fromRGB(150, 200, 210))
		say(rig, "I'm back. Please keep the chambers alive.", Color3.fromRGB(120, 220, 180))
	end)
end

local function runTechnician(rig)
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local home = rig:GetPivot()
	local lastHelp, baseSpeed = 0, hum.WalkSpeed
	local female = rig:GetAttribute("Gender") == "F"

	hum.Died:Connect(function()
		rig:SetAttribute("KnockedOut", true)
		setStatus(rig, "COLLAPSED", Color3.fromRGB(255, 90, 80))
		say(rig, "I can't... breathe...", Color3.fromRGB(255, 90, 80))
		playSound(rig, female and "scream_f" or "scream_m")
		reviveLater(rig, home)
	end)

	task.spawn(function()
		while rig.Parent and hum.Health > 0 do
			local dt = 1.0
			local pos = rig:GetPivot().Position
			local fault, dist = nearestFault(pos)
			local fatigue = rig:GetAttribute("Fatigue") or 0

			if fault then
				-- PANIC: exaggerated reaction, damage over time, calls for help
				rig:SetAttribute("Panic", true)
				rig:SetAttribute("NeedsHelp", true)
				if dist <= DAMAGE_RADIUS then
					hum.Health = math.max(HEALTH_FLOOR, hum.Health - DAMAGE_PER_SEC * dt)
				end
				fatigue = math.min(100, fatigue + 2)
				setStatus(rig, "PANIC - needs a repair tech!", Color3.fromRGB(255, 120, 100))

				-- flailing: jump and jerk toward/away from the hazard
				if math.random() < 0.5 then hum.Jump = true end
				local away = (pos - fault:GetPivot().Position).Unit * 6
				hum:MoveTo(pos + Vector3.new(away.X, 0, away.Z))

				if os.clock() - lastHelp > HELP_COOLDOWN then
					lastHelp = os.clock()
					local line = HELP_LINES[math.random(#HELP_LINES)]
					say(rig, string.format(line, labelOf(fault)), Color3.fromRGB(255, 120, 100))
					playSound(rig, math.random() < 0.5 and "help" or "follow")
				end
			else
				rig:SetAttribute("Panic", false)
				rig:SetAttribute("NeedsHelp", false)
				fatigue = math.max(0, fatigue - 1.5)
				if hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.MaxHealth, hum.Health + 4)
				end
			end

			-- FATIGUE: slows them down, and they complain
			rig:SetAttribute("Fatigue", fatigue)
			hum.WalkSpeed = baseSpeed * (1 - 0.55 * (fatigue / 100))
			if fatigue > 70 then
				setStatus(rig, "EXHAUSTED", Color3.fromRGB(255, 200, 90))
				if math.random() < 0.12 then
					say(rig, TIRED_LINES[math.random(#TIRED_LINES)], Color3.fromRGB(255, 200, 90))
				end
			elseif not fault then
				setStatus(rig, "Lab Technician", Color3.fromRGB(150, 200, 210))
			end

			task.wait(dt)
		end
	end)
end

for _, rig in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
	task.spawn(runTechnician, rig)
end
CollectionService:GetInstanceAddedSignal("LabWorkerBot"):Connect(function(rig)
	task.wait(0.5); runTechnician(rig)
end)

print("[LabTechnicians] " .. #CollectionService:GetTagged("LabWorkerBot") .. " technicians online")
