--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.LabRoles
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Roles and outfits
Future change: Keep exactly two roles unless commissioned otherwise; centralize role-to-outfit and permission mapping.
Preserve dependencies: GWAPServer LabRole observer and original equipment role checks.
Acceptance cases: Both kiosks, respawn, role change during mission, and accessory/rig variations.
]========]
-- LabRoles : role kiosks, teams, per-player leaderstats, a persistent
-- HUD, and a visible appearance change (tinted uniform + hard hat) so
-- everyone can see at a glance who is playing which role.

local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")

local ROLE_PAINT = {
	Technician = Color3.fromRGB(60, 120, 200),
	["Laboratory Technician"] = Color3.fromRGB(90, 170, 90),
}

local ROLE_HINT = {
	Unassigned = "Choose BLUE Technician or GREEN Laboratory Technician.",
	Technician = "Follow RED floor lights. HOLD R at the failed unit. Score grows with failure time and assigned distance.",
	["Laboratory Technician"] = "E takes a plant sample. Carry it to any GREEN RUNNING cabinet marked FREE SLOT and press E again to revive/drop it.",
}

local function roleEquipmentId(part)
	local code = part:GetAttribute("GrowthCode")
	if code and code ~= "" then return "CHAMBER:" .. code end
	return table.concat({part:GetAttribute("Level") or "Lab", part:GetAttribute("Room") or "Room", part.Name}, "|")
end

local function roleFloor(part)
	return part:GetAttribute("FloorLabel") or part:GetAttribute("Level") or "UNKNOWN FLOOR"
end

local function roleTransferSeconds(source, destination)
	local distance = destination and (destination.Position - source.Position).Magnitude or 60
	local playerCount = math.max(1, #Players:GetPlayers())
	local complex = workspace:FindFirstChild("Laboratory_Complex")
	local backlog = complex and (complex:GetAttribute("FailedSampleBacklog") or 0) or 0
	return math.clamp(math.floor(58 + distance * 0.65 + math.max(0, 3 - playerCount) * 10
		+ math.clamp(backlog / 20, 0, 25)), 60, 180)
end

local function roleEquipmentLabel(part)
	local code = part:GetAttribute("GrowthCode")
	if code and code ~= "" then return "CHAMBER " .. code end
	return (part:GetAttribute("Kind") or part.Name) .. " / " .. (part:GetAttribute("Room") or "Lab")
end

local function roleDestinations(source)
	local choices = {}
	for _, chamber in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
		local count = chamber:GetAttribute("SampleCount") or 0
		local reservations = chamber:GetAttribute("IncomingReservations") or 0
		if chamber ~= source and chamber:GetAttribute("FunctionalState") ~= "FAILED"
			and count + reservations < (chamber:GetAttribute("Capacity") or 10) then table.insert(choices, chamber) end
	end
	table.sort(choices, function(a, b)
		local sameA = a:GetAttribute("Level") == source:GetAttribute("Level") and 0 or 1
		local sameB = b:GetAttribute("Level") == source:GetAttribute("Level") and 0 or 1
		if sameA ~= sameB then return sameA < sameB end
		return (a:GetAttribute("SampleCount") or 0) < (b:GetAttribute("SampleCount") or 0)
	end)
	return choices
end

local function clearRoleAssignment(player)
	for _, name in ipairs({"AssignedRepairId", "AssignedRepairDistance", "AssignedRepairProjectedPoints", "AssignedTransferSource", "AssignedTransferDestination", "AssignedTransferDeadline"}) do
		player:SetAttribute(name, nil)
	end
end

local function assignRoleObjective(player, roleName)
	clearRoleAssignment(player)
	if roleName == "Technician" then
		local failed = {}
		for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
			if equipment:GetAttribute("FunctionalState") == "FAILED" then table.insert(failed, equipment) end
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		table.sort(failed, function(a, b)
			if root then return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude end
			return (a:GetAttribute("FailureSince") or 0) < (b:GetAttribute("FailureSince") or 0)
		end)
		local target = failed[1]
		if not target then return "All equipment is working. Repair score grows with failure time and assigned distance." end
		player:SetAttribute("AssignedRepairId", roleEquipmentId(target))
		local distance = root and (target.Position - root.Position).Magnitude or 0
		local waited = math.max(0, os.time() - (target:GetAttribute("FailureSince") or os.time()))
		local projected = math.clamp(20 + math.floor(waited / 8) + math.floor(distance / 10), 8, 120)
		player:SetAttribute("AssignedRepairDistance", distance)
		player:SetAttribute("AssignedRepairProjectedPoints", projected)
		return string.format("REPAIR JOB: %s • %s. Follow RED floor lights; HOLD R. About +%d points.",
			roleFloor(target), roleEquipmentLabel(target), projected)
	end

	local jobs = {}
	for _, source in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
		if source:GetAttribute("FunctionalState") == "FAILED" and (source:GetAttribute("SampleCount") or 0) > 0
			and not source:GetAttribute("ReservedByBot") then
			local destination = roleDestinations(source)[1]
			if destination then table.insert(jobs, {source = source, destination = destination}) end
		end
	end
	table.sort(jobs, function(a, b)
		local an = tonumber((a.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
		local bn = tonumber((b.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
		return an < bn
	end)
	local job = jobs[1]
	if not job then return "Waiting for a failed chamber with plants. Emergency move +12; assigned on-time move +30." end
	local sourceCode = job.source:GetAttribute("GrowthCode") or "R?"
	local destinationCode = job.destination:GetAttribute("GrowthCode") or "R?"
	player:SetAttribute("AssignedTransferSource", sourceCode)
	player:SetAttribute("AssignedTransferDestination", destinationCode)
	local allowedSeconds = roleTransferSeconds(job.source, job.destination)
	player:SetAttribute("AssignedTransferDeadline", os.time() + allowedSeconds)
	return "ASSIGNED +30: " .. roleFloor(job.source) .. " • " .. sourceCode .. " → " .. destinationCode
		.. " • " .. roleFloor(job.destination) .. ". PRESS E at source, deliver in " .. allowedSeconds .. " seconds."
end

--------------------------------------------------------------------
-- per-player HUD (role, contributions, current objective)
--------------------------------------------------------------------
	local function buildHud(player)
		local playerGui = player:WaitForChild("PlayerGui")
		local duplicate = playerGui:FindFirstChild("LiveLabHUD")
		if duplicate then duplicate:Destroy() end
		local gui = Instance.new("ScreenGui")
		gui.Name = "RoleHUD"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 20
		gui.Parent = playerGui
	
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(238, 90)
		frame.Position = UDim2.fromOffset(8, 50)
		frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		frame.BackgroundTransparency = 0.14
	frame.Parent = gui
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "RoleLabel"
		roleLabel.Size = UDim2.new(1, -14, 0, 16)
		roleLabel.Position = UDim2.new(0, 8, 0, 4)
	roleLabel.BackgroundTransparency = 1
	roleLabel.TextXAlignment = Enum.TextXAlignment.Left
	roleLabel.Font = Enum.Font.GothamBold
		roleLabel.TextSize = 13
	roleLabel.TextColor3 = Color3.fromRGB(240, 242, 246)
	roleLabel.Text = "Role: Unassigned"
	roleLabel.Parent = frame

	local contribLabel = Instance.new("TextLabel")
	contribLabel.Name = "ContribLabel"
		contribLabel.Size = UDim2.new(1, -14, 0, 13)
		contribLabel.Position = UDim2.new(0, 8, 0, 20)
	contribLabel.BackgroundTransparency = 1
	contribLabel.TextXAlignment = Enum.TextXAlignment.Left
	contribLabel.Font = Enum.Font.Gotham
		contribLabel.TextSize = 10
		contribLabel.TextTruncate = Enum.TextTruncate.AtEnd
	contribLabel.TextYAlignment = Enum.TextYAlignment.Top
	contribLabel.TextColor3 = Color3.fromRGB(200, 205, 212)
		contribLabel.Text = "POINTS 0"
	contribLabel.Parent = frame

	local carryLabel = Instance.new("TextLabel")
	carryLabel.Name = "CarryLabel"
		carryLabel.Size = UDim2.new(1, -14, 0, 13)
		carryLabel.Position = UDim2.new(0, 8, 0, 33)
	carryLabel.BackgroundTransparency = 1
	carryLabel.TextXAlignment = Enum.TextXAlignment.Left
	carryLabel.Font = Enum.Font.GothamBold
		carryLabel.TextSize = 10
	carryLabel.TextColor3 = Color3.fromRGB(115, 215, 245)
	carryLabel.Text = "Carrying: nothing"
	carryLabel.Parent = frame

		local targetsLabel = Instance.new("TextLabel")
		targetsLabel.Name = "TargetsLabel"
		targetsLabel.Size = UDim2.new(1, -14, 0, 13)
		targetsLabel.Position = UDim2.new(0, 8, 0, 46)
		targetsLabel.BackgroundTransparency = 1
		targetsLabel.TextXAlignment = Enum.TextXAlignment.Left
		targetsLabel.Font = Enum.Font.GothamBold
		targetsLabel.TextSize = 10
		targetsLabel.TextColor3 = Color3.fromRGB(255, 205, 120)
		targetsLabel.Text = "TARGETS 0 / 0"
		targetsLabel.Parent = frame

		local hintLabel = Instance.new("TextLabel")
		hintLabel.Name = "HintLabel"
		hintLabel.Size = UDim2.new(1, -14, 0, 25)
		hintLabel.Position = UDim2.new(0, 8, 0, 61)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top
	hintLabel.TextWrapped = true
	hintLabel.Font = Enum.Font.Gotham
		hintLabel.TextSize = 9
		hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
	hintLabel.Text = ROLE_HINT.Unassigned
	hintLabel.Parent = frame

	return gui
end

local function refreshHud(player, roleName)
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("RoleHUD")
	if not gui then return end
	local frame = gui:FindFirstChildOfClass("Frame")
	if not frame then return end
	frame.RoleLabel.Text = "Role: " .. roleName
	local carried = player:GetAttribute("CarriedSample")
	local objective = player:GetAttribute("LabObjective")
	frame.CarryLabel.Text = (carried and carried ~= "") and ("Carrying: " .. carried) or "Carrying: nothing"
	local hint = (objective and objective ~= "") and objective or (ROLE_HINT[roleName] or ROLE_HINT.Unassigned)
	local deadline = player:GetAttribute("AssignedTransferDeadline") or 0
	if roleName == "Laboratory Technician" and deadline > 0 then
		hint = hint .. "\nTIME LEFT FOR +30: " .. math.max(0, deadline - os.time()) .. " seconds"
	end
	frame.HintLabel.Text = hint
	local stats = player:FindFirstChild("leaderstats")
	local points = stats and stats:FindFirstChild("Points")
	local lastAmount = player:GetAttribute("LastPointAmount") or 0
	local lastReason = player:GetAttribute("LastPointAward") or ""
		frame.ContribLabel.Text = string.format("POINTS %d%s",
			points and points.Value or 0, lastAmount > 0 and ("  •  LAST +" .. lastAmount .. " " .. lastReason) or "")
	end

--------------------------------------------------------------------
-- Visible appearance change: a welded lab uniform sits above avatar
-- clothing, so layered clothes cannot hide the selected role.
--------------------------------------------------------------------
local function wearablePart(uniform, bodyPart, name, size, offset, colour, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = bodyPart.CFrame * offset
	p.Color = colour
	p.Material = material or Enum.Material.Fabric
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = uniform
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function applyAppearance(character, roleName)
	local paint = ROLE_PAINT[roleName]
	if not paint then return end
	local oldUniform = character:FindFirstChild("RoleUniform")
	if oldUniform then oldUniform:Destroy() end
	local oldHelmet = character:FindFirstChild("RoleHelmet")
	if oldHelmet then oldHelmet:Destroy() end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local head = character:FindFirstChild("Head")
	if not torso or not head then return end

	local uniform = Instance.new("Model")
	uniform.Name = "RoleUniform"
	uniform:SetAttribute("Role", roleName)
	uniform.Parent = character

	wearablePart(uniform, torso, "LabCoat", Vector3.new(torso.Size.X * 1.08, torso.Size.Y * 0.94, torso.Size.Z * 1.1),
		CFrame.new(), Color3.fromRGB(238, 241, 244), Enum.Material.Fabric)
	wearablePart(uniform, torso, "RolePanel", Vector3.new(torso.Size.X * 0.82, torso.Size.Y * 0.55, 0.14),
		CFrame.new(0, 0.08, -(torso.Size.Z / 2 + 0.12)), paint, Enum.Material.SmoothPlastic)
	wearablePart(uniform, torso, "RoleBelt", Vector3.new(torso.Size.X * 1.12, 0.18, torso.Size.Z * 1.14),
		CFrame.new(0, -torso.Size.Y * 0.34, 0), paint, Enum.Material.SmoothPlastic)
	wearablePart(uniform, torso, "RoleBadge", Vector3.new(0.36, 0.46, 0.16),
		CFrame.new(-torso.Size.X * 0.28, torso.Size.Y * 0.22, -(torso.Size.Z / 2 + 0.18)),
		Color3.fromRGB(255, 235, 120), Enum.Material.Neon)

	local helmet = wearablePart(uniform, head, "RoleHelmet", Vector3.new(1.82, 0.72, 1.82),
		CFrame.new(0, 0.72, 0), paint, Enum.Material.SmoothPlastic)
	helmet.Shape = Enum.PartType.Ball
	wearablePart(uniform, head, "HelmetBand", Vector3.new(1.9, 0.16, 1.9),
		CFrame.new(0, 0.52, 0), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic)

	for _, limbName in ipairs({"LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm"}) do
		local limb = character:FindFirstChild(limbName)
		if limb then
			wearablePart(uniform, limb, limbName:gsub(" ", "") .. "RoleBand",
				Vector3.new(limb.Size.X * 1.12, math.min(0.24, limb.Size.Y * 0.18), limb.Size.Z * 1.12),
				CFrame.new(0, -limb.Size.Y * 0.26, 0), paint, Enum.Material.SmoothPlastic)
		end
	end
end

local setupDone = {}
local function setupPlayer(player)
	if setupDone[player] then return end
	setupDone[player] = true
	if player:GetAttribute("CarriedSample") == nil then player:SetAttribute("CarriedSample", "") end
	if player:GetAttribute("LabObjective") == nil then player:SetAttribute("LabObjective", "") end
	local stats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local role = stats:FindFirstChild("Role") or Instance.new("StringValue")
	role.Name = "Role"
	if role.Value == "" then role.Value = "Unassigned" end
	role.Parent = stats

	local contrib = stats:FindFirstChild("Contributions") or Instance.new("IntValue")
	contrib.Name = "Contributions"
	contrib.Parent = stats
	local points = stats:FindFirstChild("Points") or Instance.new("IntValue")
	points.Name = "Points"
	points.Parent = stats

	local oldHud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("RoleHUD")
	if oldHud then oldHud:Destroy() end
	buildHud(player)
	role:GetPropertyChangedSignal("Value"):Connect(function() refreshHud(player, role.Value) end)
	contrib:GetPropertyChangedSignal("Value"):Connect(function() refreshHud(player, role.Value) end)
	points:GetPropertyChangedSignal("Value"):Connect(function() refreshHud(player, role.Value) end)
	player:GetAttributeChangedSignal("CarriedSample"):Connect(function() refreshHud(player, role.Value) end)
	player:GetAttributeChangedSignal("LabObjective"):Connect(function() refreshHud(player, role.Value) end)
	player:GetAttributeChangedSignal("LastPointAward"):Connect(function() refreshHud(player, role.Value) end)
	refreshHud(player, role.Value)

	-- Health must never regenerate passively: it only comes back through an
	-- Emergency Kit. Roblox's default character ships a "Health" script that
	-- does exactly the auto-regen we don't want, so remove it every spawn.
	local function stripAutoHealthRegen(character)
		local healthScript = character:FindFirstChild("Health")
		if healthScript then healthScript:Destroy() end
	end
	player.CharacterAdded:Connect(function(character)
		if role.Value ~= "Unassigned" then
			applyAppearance(character, role.Value)
		end
		stripAutoHealthRegen(character)
	end)
	if player.Character then
		if role.Value ~= "Unassigned" then applyAppearance(player.Character, role.Value) end
		stripAutoHealthRegen(player.Character)
	end
	task.spawn(function()
		while player.Parent do
			if (player:GetAttribute("AssignedTransferDeadline") or 0) > 0 then refreshHud(player, role.Value) end
			task.wait(1)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(setupPlayer, player) end

local function bindKiosk(part)
	local roleName = part:GetAttribute("Role")
	if not roleName then return end
	if part:GetAttribute("RoleKioskBound") then return end
	part:SetAttribute("RoleKioskBound", true)

	local button = Instance.new("Part")
	button.Name = "RoleSelectButton"
	button.Shape = Enum.PartType.Cylinder
	button.Size = Vector3.new(0.28, 1.05, 1.05)
	button.CFrame = part.CFrame * CFrame.new(0, -part.Size.Y * 0.32, -(part.Size.Z / 2 + 0.32))
		* CFrame.Angles(0, math.rad(90), 0)
	button.Color = ROLE_PAINT[roleName]
	button.Material = Enum.Material.Neon
	button.Anchored = true
	button.CanCollide = false
	button.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = roleName .. " Kiosk"
	prompt.ActionText = "Select " .. roleName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 30
	prompt.RequiresLineOfSight = false
	prompt.Parent = button

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 30
	click.Parent = button
	local debounce = {}
	local function selectRole(player)
		if debounce[player] and os.clock() < debounce[player] then return end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - part.Position).Magnitude > 36 then return end
		debounce[player] = os.clock() + 1
		setupPlayer(player)
		local team = Teams:FindFirstChild(roleName)
		if not team then return end
		player.Team = team
		player.Neutral = false
		player:SetAttribute("LabRole", roleName)
		local stats = player:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Role") then
			stats.Role.Value = roleName
		end
		player:SetAttribute("LabObjective", assignRoleObjective(player, roleName))
		if player.Character then applyAppearance(player.Character, roleName) end
		local oldColour = button.Color
		button.Color = Color3.fromRGB(255, 255, 255)
		task.delay(0.35, function() if button.Parent then button.Color = oldColour end end)
		refreshHud(player, roleName)
	end

	prompt.Triggered:Connect(selectRole)
	click.MouseClick:Connect(selectRole)
end

for _, p in ipairs(CollectionService:GetTagged("RoleKiosk")) do bindKiosk(p) end
CollectionService:GetInstanceAddedSignal("RoleKiosk"):Connect(bindKiosk)

print("Role kiosks armed: " .. #CollectionService:GetTagged("RoleKiosk") .. ".")
