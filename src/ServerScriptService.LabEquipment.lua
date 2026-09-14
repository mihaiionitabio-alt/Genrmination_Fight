
-- LabEquipment : physical controls, equipment readouts, carried samples,
-- cold-store delivery missions, and non-lethal sample recovery tools.
-- All inventory and hit decisions happen on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")

local Kinds = require(ReplicatedStorage:WaitForChild("LabKinds"))
local QuizRemote = ReplicatedStorage:FindFirstChild("LabMathQuiz")
if QuizRemote and not QuizRemote:IsA("RemoteEvent") then QuizRemote:Destroy(); QuizRemote = nil end
if not QuizRemote then
	QuizRemote = Instance.new("RemoteEvent")
	QuizRemote.Name = "LabMathQuiz"
	QuizRemote.Parent = ReplicatedStorage
end

--------------------------------------------------------------------
-- SHARED GAME STATE
--------------------------------------------------------------------
local GameState = {
	repairsCompleted = 0,
	assignedRepairsCompleted = 0,
	transfersCompleted = 0,
	assignedTransfersCompleted = 0,
}

local ROLE_STATIONS = {}

local POINTS = {
	MOVE_ANY = 12,
	MOVE_ASSIGNED_LATE = 18,
	MOVE_ASSIGNED_ON_TIME = 30,
	PROCESS_PLANT = 4,
}

local function updateScoreboard()
	local board = CollectionService:GetTagged("BatchScoreboard")[1]
	if not board then return end
	local gui = board:FindFirstChildWhichIsA("BillboardGui")
	local label = gui and gui:FindFirstChild("Text")
	if label then
		local rivalScore = 0
		for _, bot in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
			if bot:GetAttribute("Competitor") then rivalScore = bot:GetAttribute("Score") or 0 break end
		end
		label.Text = string.format(
			"PLAYER TEAM SCORE\nRepairs: %d  •  assigned: %d\nPlant moves: %d  •  assigned: %d\nRival NPC score: %d",
			GameState.repairsCompleted, GameState.assignedRepairsCompleted,
			GameState.transfersCompleted, GameState.assignedTransfersCompleted, rivalScore)
	end
end

-- Per-room equipment status monitors. Each RoomMonitor panel carries a
-- Room attribute matching the LabEquipment parts placed in that same room,
-- so this just groups by that attribute and tallies running/failed/plants.
local function refreshRoomMonitors()
	-- Room names ("Room 4", etc.) repeat on every level, so the key here
	-- must include the level too -- otherwise a monitor sums up every
	-- same-numbered room across the whole building instead of just its own.
	local totals = {}
	for _, equip in ipairs(CollectionService:GetTagged("LabEquipment")) do
		local room = equip:GetAttribute("Room")
		local level = equip:GetAttribute("Level") or ""
		if room then
			local key = level .. "|" .. room
			local t = totals[key]
			if not t then t = {running = 0, failed = 0, plants = 0, count = 0}; totals[key] = t end
			t.count = t.count + 1
			if equip:GetAttribute("FunctionalState") == "FAILED" then t.failed = t.failed + 1
			else t.running = t.running + 1 end
			t.plants = t.plants + (equip:GetAttribute("SampleCount") or 0)
		end
	end
	for _, panel in ipairs(CollectionService:GetTagged("RoomMonitor")) do
		local surface = panel:FindFirstChildWhichIsA("SurfaceGui")
		local label = surface and surface:FindFirstChild("Status")
		if label then
			local room = panel:GetAttribute("Room") or "ROOM"
			local level = panel:GetAttribute("Level") or ""
			local t = totals[level .. "|" .. room] or {running = 0, failed = 0, plants = 0, count = 0}
			label.Text = string.format("%s\nEquipment: %d  •  RUNNING %d  •  FAILED %d\nPlants stored: %d",
				room, t.count, t.running, t.failed, t.plants)
			label.TextColor3 = (t.failed > 0) and Color3.fromRGB(255, 160, 90) or Color3.fromRGB(120, 235, 170)
		end
	end
end

local function addContribution(player, amount)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Contributions")
	if value then value.Value = value.Value + (amount or 1) end
end

	local facilityNoticeAt = setmetatable({}, {__mode = "k"})
	local function notify(player, text)
		local facilityAlert = text:match("^ALARM:") or text:match("^REPAIR ALARM:") or text:match("^CATASTROPHIC FAILURE:")
		if facilityAlert then
			local now = os.clock()
			if now - (facilityNoticeAt[player] or -math.huge) < 6 then return end
			facilityNoticeAt[player] = now
		end
		print("[" .. player.Name .. "] " .. text)
		local gui = player:FindFirstChild("PlayerGui")
	if not gui then return end
	local screen = gui:FindFirstChild("LabLog")
	if not screen then
			screen = Instance.new("ScreenGui")
			screen.Name = "LabLog"
			screen.ResetOnSpawn = false
			screen.DisplayOrder = 40
			screen.Parent = gui
	
			local frame = Instance.new("TextLabel")
			frame.Name = "Line"
			frame.Size = UDim2.new(0.48, 0, 0, 46)
			frame.AnchorPoint = Vector2.new(0.5, 1)
			frame.Position = UDim2.new(0.5, 0, 1, -68)
			frame.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
			frame.BackgroundTransparency = 0.12
			frame.TextColor3 = Color3.fromRGB(235, 238, 242)
			frame.TextWrapped = true
			frame.TextTruncate = Enum.TextTruncate.AtEnd
			frame.TextSize = 13
			frame.Font = Enum.Font.Gotham
			frame.Parent = screen
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = frame
			local sizeLimit = Instance.new("UISizeConstraint")
			sizeLimit.MinSize = Vector2.new(260, 46)
			sizeLimit.MaxSize = Vector2.new(420, 46)
			sizeLimit.Parent = frame
			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 10)
			padding.PaddingRight = UDim.new(0, 10)
			padding.Parent = frame
		end
	
		local line = screen:FindFirstChild("Line")
		if not line then return end
		local serial = (screen:GetAttribute("MessageSerial") or 0) + 1
		screen:SetAttribute("MessageSerial", serial)
		line.Visible = true
		line.Text = text
		task.delay(4, function()
			if line.Parent and screen:GetAttribute("MessageSerial") == serial then line.Visible = false end
		end)
	end

local function playerRole(player)
	local attributeRole = player:GetAttribute("LabRole")
	if attributeRole and attributeRole ~= "" then return attributeRole end
	if player.Team then return player.Team.Name end
	local stats = player:FindFirstChild("leaderstats")
	local role = stats and stats:FindFirstChild("Role")
	return role and role.Value or "Unassigned"
end

local function awardPoints(player, amount, reason)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local points = stats:FindFirstChild("Points")
	if not points then
		points = Instance.new("IntValue")
		points.Name = "Points"
		points.Parent = stats
	end
	points.Value = points.Value + amount
	addContribution(player, 1)
	player:SetAttribute("LastPointAmount", amount)
	player:SetAttribute("LastPointAward", reason)
	notify(player, string.format("+%d POINTS — %s • TOTAL %d", amount, reason, points.Value))
	updateScoreboard()
	return points.Value
end

local function canInteract(player, part, maxDistance)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil
		or (root.Position - part.Position).Magnitude > maxDistance + 2 then return false end
	local originPart = character:FindFirstChild("Head") or root
	local direction = part.Position - originPart.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = true
	local hit = workspace:Raycast(originPart.Position, direction, params)
	return hit == nil or hit.Instance == part or hit.Instance:IsDescendantOf(part)
end

-- Server-owned, one-use addition challenges. No InvokeClient yield can leave
-- equipment locked forever; the server expires or cancels each pending action.
local pendingQuizzes = {}
local quizSerial = 0
QuizRemote.OnServerEvent:Connect(function(player, id, answer)
	local pending = pendingQuizzes[player]
	if not pending or pending.id ~= id or pending.finished or os.clock() > pending.expires then return end
	if answer ~= nil and (typeof(answer) ~= "number" or answer ~= answer or answer % 1 ~= 0) then return end
	pending.answer = answer
	pending.finished = true
end)
Players.PlayerRemoving:Connect(function(player) pendingQuizzes[player] = nil end)

local function runMathQuiz(player, reason, target, validate)
	if pendingQuizzes[player] or not player.Parent or not validate() then return false end
	local a, b = math.random(1, 100), math.random(1, 100)
	local expected = a + b
	local choices = {expected, expected + math.random(1, 9), math.max(0, expected - math.random(1, 9))}
	for i = #choices, 2, -1 do local j = math.random(1, i); choices[i], choices[j] = choices[j], choices[i] end
	quizSerial = quizSerial + 1
	local pending = {id = quizSerial, expected = expected, expires = os.clock() + 60, finished = false}
	pendingQuizzes[player] = pending
	player:SetAttribute("MathQuizActive", true)
	target:SetAttribute("QuizPlayerId", player.UserId)
	QuizRemote:FireClient(player, {Id = pending.id, Question = string.format("%d + %d", a, b),
		Choices = choices, Seconds = 60, Reason = reason})
	while player.Parent and pendingQuizzes[player] == pending and not pending.finished
		and os.clock() < pending.expires and target.Parent and validate() do task.wait(0.1) end
	local correct = player.Parent ~= nil and target.Parent ~= nil and pendingQuizzes[player] == pending
		and pending.finished and pending.answer == pending.expected and os.clock() <= pending.expires and validate()
	if pendingQuizzes[player] == pending then pendingQuizzes[player] = nil end
	if target.Parent and target:GetAttribute("QuizPlayerId") == player.UserId then target:SetAttribute("QuizPlayerId", nil) end
	if player.Parent then
		player:SetAttribute("MathQuizActive", false)
		QuizRemote:FireClient(player, {Close = true, Id = pending.id})
		if not correct then notify(player, "Task not completed. Stay near the unit and try the addition check again.") end
	end
	return correct
end

--------------------------------------------------------------------
-- VISIBLE INVENTORY ITEMS
-- The old script collection used Tool + Handle + welded decorative
-- pieces. This keeps that useful pattern, but creates and validates the
-- tools entirely on the server instead of trusting a client script.
--------------------------------------------------------------------
local SAMPLE_ITEM = {
	[Kinds.Items.TRAY] = true,
	[Kinds.Items.GROUND] = true,
	[Kinds.Items.DRIED] = true,
	[Kinds.Items.SPUN] = true,
	[Kinds.Items.CULTURE] = true,
}

local function addWeldedPart(tool, handle, name, size, relativeCFrame, colour, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = handle.CFrame * relativeCFrame
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function equipTool(player, tool)
	task.defer(function()
		if not tool.Parent then return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid:EquipTool(tool) end
	end)
end

local function makeTool(player, name, options)
	options = options or {}
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then return nil end

	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = options.tooltip or "Visible laboratory item"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("LabItemType", options.itemType or name)
	tool:SetAttribute("LabSample", options.sample == true or SAMPLE_ITEM[name] == true)

	for key, value in pairs(options.attributes or {}) do tool:SetAttribute(key, value) end
	if options.plant and tool:GetAttribute("PlantLife") == nil then tool:SetAttribute("PlantLife", 100) end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = options.plant and Vector3.new(0.95, 0.72, 0.95) or Vector3.new(1.7, 0.22, 1.35)
	handle.Color = options.colour or Color3.fromRGB(205, 185, 138)
	handle.Material = options.plant and Enum.Material.WoodPlanks or Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	if options.plant then
		-- A real visible potted plant: soil, stem, leaves, and a glowing bud
		-- are welded to the Tool handle and replicate in the character hand.
		addWeldedPart(tool, handle, "Soil", Vector3.new(0.82, 0.14, 0.82),
			CFrame.new(0, 0.4, 0), Color3.fromRGB(78, 52, 33), Enum.Material.Ground)
		addWeldedPart(tool, handle, "PlantStem", Vector3.new(0.16, 1.0, 0.16),
			CFrame.new(0, 0.96, 0), Color3.fromRGB(65, 155, 75), Enum.Material.Grass)
		addWeldedPart(tool, handle, "LeafLeft", Vector3.new(0.78, 0.16, 0.42),
			CFrame.new(-0.34, 1.1, 0) * CFrame.Angles(0, 0, math.rad(-22)),
			Color3.fromRGB(70, 180, 82), Enum.Material.Grass)
		addWeldedPart(tool, handle, "LeafRight", Vector3.new(0.78, 0.16, 0.42),
			CFrame.new(0.34, 1.35, 0) * CFrame.Angles(0, 0, math.rad(22)),
			Color3.fromRGB(85, 195, 92), Enum.Material.Grass)
		addWeldedPart(tool, handle, "GrowthBud", Vector3.new(0.36, 0.36, 0.36),
			CFrame.new(0, 1.58, 0), Color3.fromRGB(245, 185, 80), Enum.Material.Neon, Enum.PartType.Ball)
	else
		-- Tray rim, sample pouch, and labelled vial make ordinary samples
		-- recognizable from a distance instead of a plain block.
		addWeldedPart(tool, handle, "TrayRim", Vector3.new(1.82, 0.12, 1.47),
			CFrame.new(0, 0.14, 0), Color3.fromRGB(55, 68, 78), Enum.Material.Metal)
		addWeldedPart(tool, handle, "SeedPouch", Vector3.new(0.92, 0.32, 0.76),
			CFrame.new(0, 0.35, 0), Color3.fromRGB(220, 193, 116), Enum.Material.Fabric)
		addWeldedPart(tool, handle, "SampleVial", Vector3.new(0.62, 0.22, 0.22),
			CFrame.new(0.47, 0.54, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(115, 215, 245), Enum.Material.Glass, Enum.PartType.Cylinder)
	end

	local marker = Instance.new("BillboardGui")
	marker.Name = "CarryLabel"
	marker.Size = UDim2.fromOffset(150, 34)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 1.15, 0)
	marker.MaxDistance = 8
	marker.AlwaysOnTop = false
	marker.Parent = handle
	local markerText = Instance.new("TextLabel")
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.BackgroundColor3 = Color3.fromRGB(20, 25, 30)
	markerText.BackgroundTransparency = 0.2
	markerText.TextColor3 = Color3.fromRGB(245, 225, 150)
	markerText.TextScaled = true
	markerText.Text = options.label or name
	markerText.Font = Enum.Font.GothamBold
	markerText.Parent = marker
	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(0, 6)
	markerCorner.Parent = markerText
	if options.plant then
		local lifeGui = Instance.new("BillboardGui")
		lifeGui.Name = "PlantLifeStatus"
		lifeGui.Size = UDim2.fromOffset(160, 46)
		lifeGui.StudsOffsetWorldSpace = Vector3.new(0, 1.72, 0)
		lifeGui.MaxDistance = 18
		lifeGui.AlwaysOnTop = false
		lifeGui.Parent = handle
		local lifeFrame = Instance.new("Frame")
		lifeFrame.Size = UDim2.fromScale(1, 1)
		lifeFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
		lifeFrame.BackgroundTransparency = 0.12
		lifeFrame.BorderSizePixel = 0
		lifeFrame.Parent = lifeGui
		local lifeText = Instance.new("TextLabel")
		lifeText.Name = "LifeText"
		lifeText.Size = UDim2.new(1, 0, 0.58, 0)
		lifeText.BackgroundTransparency = 1
		lifeText.TextScaled = true
		lifeText.Font = Enum.Font.GothamBold
		lifeText.Parent = lifeFrame
		local lifeBack = Instance.new("Frame")
		lifeBack.Name = "LifeBarBackground"
		lifeBack.Size = UDim2.new(0.9, 0, 0.2, 0)
		lifeBack.Position = UDim2.new(0.05, 0, 0.7, 0)
		lifeBack.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
		lifeBack.BorderSizePixel = 0
		lifeBack.Parent = lifeFrame
		local lifeFill = Instance.new("Frame")
		lifeFill.Name = "LifeBarFill"
		lifeFill.Size = UDim2.fromScale(1, 1)
		lifeFill.BorderSizePixel = 0
		lifeFill.Parent = lifeBack
		local function updateLifeBar()
			local life = math.clamp(tool:GetAttribute("PlantLife") or 100, 0, 100)
			lifeText.Text = "PLANT LIFE " .. math.floor(life + 0.5) .. "%"
			lifeFill.Size = UDim2.new(life / 100, 0, 1, 0)
			local colour = life > 60 and Color3.fromRGB(75, 235, 105)
				or (life > 30 and Color3.fromRGB(255, 190, 55) or Color3.fromRGB(255, 70, 60))
			lifeText.TextColor3 = colour
			lifeFill.BackgroundColor3 = colour
		end
		tool:GetAttributeChangedSignal("PlantLife"):Connect(updateLifeBar)
		updateLifeBar()
	end

	tool.Grip = options.plant
		and (CFrame.new(0, -0.25, -0.75) * CFrame.Angles(math.rad(-8), 0, 0))
		or (CFrame.new(0, -0.45, -0.65) * CFrame.Angles(math.rad(-12), 0, 0))
	tool.Parent = backpack
	if options.autoEquip ~= false then equipTool(player, tool) end
	return tool
end

local function playerContainers(player)
	local containers = {}
	if player.Character then table.insert(containers, player.Character) end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then table.insert(containers, backpack) end
	return containers
end

local function findTool(player, itemType)
	for _, container in ipairs(playerContainers(player)) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and
					(child.Name == itemType or child:GetAttribute("LabItemType") == itemType) then
					return child
				end
			end
		end
	end
	return nil
end

local function findTransferSample(player)
	for _, container in ipairs(playerContainers(player)) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("TransferSample") then return child end
			end
		end
	end
	return nil
end

local function findHeldSample(player)
	local character = player.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("LabSample") then return child end
	end
	return nil
end

local GROWTH_STAGE_NAME = {
	[0] = "Seedling",
	[1] = "Germinated",
	[2] = "Vegetative",
	[3] = "Budding",
	[4] = "Flowering",
	[5] = "Mature",
}

local function findPlantSample(player)
	for _, container in ipairs(playerContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("PlantSample") then return child end
		end
	end
	return nil
end

local function treatmentText(tool)
	local treatments = tool:GetAttribute("Treatments") or ""
	if treatments == "" then return "untreated" end
	return treatments:gsub("|", ", ")
end

local function hasTreatment(tool, key)
	local treatments = "|" .. (tool:GetAttribute("Treatments") or "") .. "|"
	return treatments:find("|" .. key .. "|", 1, true) ~= nil
end

local function addTreatment(tool, key)
	if hasTreatment(tool, key) then return false end
	local treatments = tool:GetAttribute("Treatments") or ""
	tool:SetAttribute("Treatments", treatments == "" and key or (treatments .. "|" .. key))
	return true
end

local function refreshPlantVisual(tool)
	local stage = math.clamp(tool:GetAttribute("GrowthStage") or 0, 0, 5)
	local life = math.clamp(tool:GetAttribute("PlantLife") or 100, 0, 100)
	local stem = tool:FindFirstChild("PlantStem")
	local left = tool:FindFirstChild("LeafLeft")
	local right = tool:FindFirstChild("LeafRight")
	local bud = tool:FindFirstChild("GrowthBud")
	if stem then stem.Size = Vector3.new(0.16 + stage * 0.025, 1 + stage * 0.13, 0.16 + stage * 0.025) end
	local lifeScale = 0.35 + life / 100 * 0.65
	if left then left.Color = Color3.fromRGB((70 + stage * 5) * lifeScale, (165 + stage * 10) * lifeScale, 55 * lifeScale) end
	if right then right.Color = Color3.fromRGB((75 + stage * 4) * lifeScale, (175 + stage * 10) * lifeScale, 60 * lifeScale) end
	if bud then
		bud.Transparency = stage < 3 and 0.65 or 0
		bud.Color = stage >= 5 and Color3.fromRGB(255, 105, 175) or Color3.fromRGB(245, 185, 80)
	end
	local handle = tool:FindFirstChild("Handle")
	local marker = handle and handle:FindFirstChild("CarryLabel")
	local label = marker and marker:FindFirstChildOfClass("TextLabel")
	if label then
		local destination = tool:GetAttribute("DestinationGrowthCode") or ""
		label.Text = (tool:GetAttribute("PlantId") or "PLANT") .. " • " .. (GROWTH_STAGE_NAME[stage] or "Growing")
			.. (destination ~= "" and (" • BONUS DROP " .. destination) or " • DROP IN GREEN R")
	end
end

local function setCarryState(player, sample)
	-- A cold-store transfer remains the main HUD objective even if the
	-- player briefly produces or pockets another laboratory item.
	local transfer = findTransferSample(player)
	if transfer and sample and not sample:GetAttribute("TransferSample") then sample = transfer end
	if sample then
		local id = sample:GetAttribute("SampleId") or sample.Name
		local destination = sample:GetAttribute("DestinationLabel") or sample:GetAttribute("DestinationGrowthCode")
		player:SetAttribute("CarriedSample", id)
		if destination and destination ~= "" then
			player:SetAttribute("LabObjective", "Carry " .. id .. " to bonus chamber " .. destination .. ", or press E at any GREEN RUNNING cabinet with a free slot.")
		else
			player:SetAttribute("LabObjective", "Carry " .. sample.Name .. " to the next required machine.")
		end
	else
		player:SetAttribute("CarriedSample", "")
		player:SetAttribute("LabObjective", "")
	end
end

local function destroyCarriedItem(player, tool)
	if player:GetAttribute("CarriedSample") == (tool:GetAttribute("SampleId") or tool.Name) then
		setCarryState(player, nil)
	end
	tool:Destroy()
end

--------------------------------------------------------------------
-- NON-LETHAL HIT TOOLS
--------------------------------------------------------------------
local IMPACT_STYLE = {
	["Foam Baton"] = {colour = Color3.fromRGB(245, 135, 55), accent = Color3.fromRGB(45, 48, 54), mode = "melee", damage = 18},
	["Sample Grabber"] = {colour = Color3.fromRGB(70, 165, 220), accent = Color3.fromRGB(205, 225, 235), mode = "melee", damage = 12},
	["Inspection Paddle"] = {colour = Color3.fromRGB(245, 205, 70), accent = Color3.fromRGB(95, 75, 30), mode = "melee", damage = 22},
	["Stun Blaster"] = {colour = Color3.fromRGB(90, 225, 245), accent = Color3.fromRGB(35, 55, 70), mode = "gun", damage = 28, range = 95},
	["Foam Dart Rifle"] = {colour = Color3.fromRGB(225, 80, 95), accent = Color3.fromRGB(45, 45, 52), mode = "gun", damage = 38, range = 125},
	["Basketball"] = {colour = Color3.fromRGB(225, 105, 35), accent = Color3.fromRGB(45, 28, 18), mode = "ball", damage = 24},
	-- PC-only weapons, built from the official Roblox Weapons Kit meshes.
	--
	-- meshScale is (the kit's intended size / the raw mesh size), measured off
	-- the kit's own MeshParts. This matters: the raw pistol mesh is 9.68 studs
	-- long, so the scale of 1.8 used at first drew a pistol about 17 studs
	-- long -- roughly three times the height of the character holding it.
	--
	-- A worker bot has 100 life, so damage is set for 2-3 body shots; a head
	-- shot kills outright regardless. selfCostPercent still charges the
	-- shooter 1% of their own max health per shot. pcOnly means the generic
	-- Tool.Activated path ignores them -- they fire only through the
	-- LabSidearmFire remote, which only the desktop client script sends.
	["Lab Sidearm"] = {
		colour = Color3.fromRGB(126, 133, 145), accent = Color3.fromRGB(38, 42, 50),
		mode = "gun", damage = 34, range = 240, selfCostPercent = 1, pcOnly = true,
		cooldown = 0.32, pellets = 1, spread = 0,
		meshId = "rbxassetid://2492922600", meshTexture = "rbxassetid://2492931263",
		meshScale = 0.1407, handleSize = Vector3.new(0.20, 0.92, 1.36),
		grip = CFrame.new(0, -0.20, -0.30) * CFrame.Angles(0, math.rad(180), 0),
	},
	["Lab Shotgun"] = {
		colour = Color3.fromRGB(122, 98, 72), accent = Color3.fromRGB(40, 34, 30),
		-- 6 pellets at 20 was 120 damage against a 100 HP worker, so any clean
		-- body hit was an instant kill. At 12 a full-pellet hit leaves the
		-- worker standing and takes two, matching the rifle and the sidearm.
		mode = "gun", damage = 12, range = 110, selfCostPercent = 1, pcOnly = true,
		cooldown = 0.85, pellets = 6, spread = 0.075,
		meshId = "rbxassetid://2492972199", meshTexture = "rbxassetid://2492974190",
		meshScale = 0.6666, handleSize = Vector3.new(0.31, 1.00, 4.87),
		grip = CFrame.new(0, -0.35, -0.95) * CFrame.Angles(0, math.rad(180), 0),
	},
	["Lab Rifle"] = {
		colour = Color3.fromRGB(96, 104, 96), accent = Color3.fromRGB(34, 38, 34),
		mode = "gun", damage = 55, range = 620, selfCostPercent = 1, pcOnly = true,
		cooldown = 0.95, pellets = 1, spread = 0,
		meshId = "rbxassetid://2759059561", meshTexture = "rbxassetid://2759063893",
		meshScale = 0.6383, handleSize = Vector3.new(0.29, 1.17, 6.18),
		grip = CFrame.new(0, -0.35, -1.20) * CFrame.Angles(0, math.rad(180), 0),
	},
}

local function refreshBotHealth(bot)
	local health = math.clamp(bot:GetAttribute("Health") or 100, 0, bot:GetAttribute("MaxHealth") or 100)
	local maximum = bot:GetAttribute("MaxHealth") or 100
	local text = bot:FindFirstChild("HealthText", true)
	local fill = bot:FindFirstChild("HealthBarFill", true)
	if text and text:IsA("TextLabel") then text.Text = string.format("LIFE %d / %d", health, maximum) end
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(health / math.max(1, maximum), 1)
		fill.BackgroundColor3 = health > maximum * 0.55 and Color3.fromRGB(75, 220, 95)
			or (health > maximum * 0.25 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(235, 65, 60))
	end
end

-- How long a body stays before it is cleaned up. Bodies are the biggest
-- avoidable part cost in a long round, so this is deliberately short.
-- Declared HERE, above damageWorkerBot, because that is what reads it: a
-- local declared further down the file resolves to a nil global inside a
-- function defined above it.
local BODY_LIFETIME_SECONDS = 60

local function damageWorkerBot(bot, amount, attacker)
	-- Only an already-dead worker is immune. This used to refuse damage to
	-- anything KnockedOut, which meant a worker downed by a hazard could not
	-- be finished off by gunfire or caught in a blast -- so a floor could
	-- never actually be cleared.
	if not bot or not CollectionService:HasTag(bot, "LabWorkerBot") or bot:GetAttribute("Dead") then return false end
	local health = math.max(0, (bot:GetAttribute("Health") or 100) - amount)
	bot:SetAttribute("Health", health)
	bot:SetAttribute("LastHitBy", attacker and attacker.Name or "environment")
	refreshBotHealth(bot)
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.fromRGB(255, 90, 70)
	flash.OutlineColor = Color3.fromRGB(255, 255, 255)
	flash.FillTransparency = 0.25
	-- Highlights render through geometry by default, which is why a hit
	-- worker (and any corpse that inherited the flash) glowed through walls.
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = bot
	Debris:AddItem(flash, 0.22)
	if health <= 0 then
		-- Death is permanent now: the hunt is the objective, so a worker that
		-- goes down stays down and its body is left where it fell. Bodies are
		-- cleared when the shift rolls over (see the RoundNumber watcher).
		bot:SetAttribute("Dead", true)
		bot:SetAttribute("KnockedOut", true)
		bot:SetAttribute("TaskState", "DEAD")

		-- The body left behind is a CLONE, not the worker itself. That keeps
		-- the original model pristine, so the shift roll-over can simply move
		-- it home and stand it back up rather than trying to undo a pile of
		-- destructive colour and rotation edits.
		local pivot = bot:GetPivot()
		local corpse = bot:Clone()
		corpse.Name = bot.Name .. "_Body"
		for _, d in ipairs(corpse:GetDescendants()) do
			-- A body reports no status, and must not inherit the damage-flash
			-- Highlight -- that is what made corpses visible through walls,
			-- because the clone's copy was never cleaned up.
			if d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("Sparkles")
				or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("PointLight")
				or d.Name:match("^Chair") or d.Name:match("^Desk") or d.Name == "Monitor" then
				d:Destroy()
			end
		end
		for _, d in ipairs(corpse:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Color = Color3.new(d.Color.R * 0.55 + 0.10, d.Color.G * 0.55 + 0.10, d.Color.B * 0.55 + 0.10)
				d.Material = Enum.Material.SmoothPlastic
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false     -- a body must not soak up later shots
				d.CastShadow = false   -- 180 shadow-casting corpses is not free
			end
		end
		local corpseFolder = workspace:FindFirstChild("LabBotBodies")
		if not corpseFolder then
			corpseFolder = Instance.new("Folder")
			corpseFolder.Name = "LabBotBodies"
			corpseFolder.Parent = workspace
		end
		-- The clone inherits every tag, including LabWorkerBot. Left alone it
		-- would be counted as a live worker by every GetTagged sweep and the
		-- kill total would never be able to reach the target.
		CollectionService:RemoveTag(corpse, "LabWorkerBot")
		corpse.Parent = corpseFolder
		-- Lay it down where it fell, with a random spin so a cleared room does
		-- not read as a row of identical dropped props.
		corpse:PivotTo(CFrame.new(pivot.Position - Vector3.new(0, 2.6, 0))
			* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
			* CFrame.Angles(math.rad(-90), 0, 0))
		CollectionService:AddTag(corpse, "LabBotCorpse")
		-- Bodies are the single biggest avoidable part cost in a long round:
		-- 180 of them is ~1,600 extra parts. They stay long enough to read a
		-- room as cleared, then go.
		Debris:AddItem(corpse, BODY_LIFETIME_SECONDS)

		-- Park the live worker out of the world until the next shift.
		if not bot:GetAttribute("HomeCFrame") then bot:SetAttribute("HomeCFrame", pivot) end
		bot:PivotTo(CFrame.new(0, -1000, 0))

		local complex = workspace:FindFirstChild("Laboratory_Complex")
		if complex then
			complex:SetAttribute("BotsKilled", (complex:GetAttribute("BotsKilled") or 0) + 1)
		end
	end
	return true
end

-- Walk up from whatever the ray actually hit to the tagged equipment part.
local function equipmentFromHit(hit)
	local node = hit
	while node and node ~= workspace do
		if node:IsA("BasePart")
			and (CollectionService:HasTag(node, "LabEquipment") or CollectionService:HasTag(node, "PlantGrowthChamber")) then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Shoot a machine and it goes up, taking out whatever is standing near it --
-- including the player who pulled the trigger, if they did it from close range.
local function explodeEquipment(item, attacker)
	if item:GetAttribute("Exploded") then return false end
	item:SetAttribute("Exploded", true)
	item:SetAttribute("FunctionalState", "DESTROYED")
	item:SetAttribute("RepairInstruction", "Destroyed beyond repair")

	local position = item.Position
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = 17
	blast.BlastPressure = 0        -- the lab is anchored; pressure would do nothing
	blast.DestroyJointRadiusPercent = 0
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace

	local fire = Instance.new("Fire")
	fire.Heat = 14
	fire.Size = 9
	fire.Parent = item
	Debris:AddItem(fire, 14)
	local smoke = Instance.new("Smoke")
	smoke.Size = 5
	smoke.Opacity = 0.4
	smoke.RiseVelocity = 9
	smoke.Color = Color3.fromRGB(60, 58, 56)
	smoke.Parent = item
	Debris:AddItem(smoke, 18)

	item.Color = Color3.fromRGB(48, 40, 36)
	item.Material = Enum.Material.CorrodedMetal

	for _, bot in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
		if not bot:GetAttribute("Dead") and bot.PrimaryPart then
			if (bot.PrimaryPart.Position - position).Magnitude < 17 then
				damageWorkerBot(bot, 1000, attacker)
			end
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local c = other.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if h and hrp and h.Health > 0 then
			local d = (hrp.Position - position).Magnitude
			if d < 17 then h:TakeDamage(math.max(18, 75 * (1 - d / 17))) end
		end
	end
	return true
end

-- A gas line going up is a different order of event from a machine failing:
-- it takes out a chunk of the room -- a couple of neighbouring machines and
-- part of the wall structure itself.
local function detonateGasPipe(pipe, attacker, atPosition)
	if pipe:GetAttribute("Blown") then return false end
	pipe:SetAttribute("Blown", true)
	-- Blow at the point that was actually hit. A corridor run is one long part
	-- whose Position is its midpoint, so using that detonated the pipe up to a
	-- hundred studs away from where the player shot it.
	local position = atPosition or pipe.Position

	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = 30
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace

	-- a running wall of fire and smoke along the rupture
	for i = -2, 2 do
		local flare = Instance.new("Part")
		flare.Name = "GasFire"
		flare.Size = Vector3.new(1, 1, 1)
		flare.CFrame = CFrame.new(position + Vector3.new(0, 0, i * 7))
		flare.Anchored = true
		flare.CanCollide = false
		flare.CanQuery = false
		flare.CanTouch = false
		flare.Transparency = 1
		flare.Parent = workspace
		local fire = Instance.new("Fire")
		fire.Heat = 25
		fire.Size = 24
		fire.Parent = flare
		local smoke = Instance.new("Smoke")
		smoke.Size = 15
		smoke.Opacity = 0.5
		smoke.RiseVelocity = 14
		smoke.Color = Color3.fromRGB(40, 38, 36)
		smoke.Parent = flare
		task.delay(16, function()
			if flare.Parent then fire.Enabled = false; smoke.Enabled = false end
		end)
		Debris:AddItem(flare, 22)
	end

	pipe.Color = Color3.fromRGB(62, 52, 30)
	pipe.Material = Enum.Material.CorrodedMetal

	-- take two or three neighbouring machines with it, staggered so it reads
	-- as a chain rather than one simultaneous bang
	local nearby = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(position, 24)) do
		if (CollectionService:HasTag(part, "LabEquipment") or CollectionService:HasTag(part, "PlantGrowthChamber"))
			and not part:GetAttribute("Exploded") then
			table.insert(nearby, part)
		end
	end
	for i = 1, math.min(3, #nearby) do
		local item = nearby[i]
		task.delay(0.18 * i, function()
			if item.Parent then explodeEquipment(item, attacker) end
		end)
	end

	-- and blow an actual hole in the structure
	local blown = 0
	for _, part in ipairs(workspace:GetPartBoundsInRadius(position, 15)) do
		if part:IsA("BasePart") and part.CanCollide and not part:GetAttribute("GasPipe") then
			local n = part.Name
			if n:match("^Corridor_") or n:match("^Div_") or n:match("^Ext_") or n:match("^B_") then
				if blown < 5 then
					blown = blown + 1
					part:Destroy()
				else
					part.Color = Color3.fromRGB(60, 54, 50)
					part.Material = Enum.Material.CorrodedMetal
				end
			end
		end
	end

	for _, bot in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
		if not bot:GetAttribute("Dead") and bot.PrimaryPart
			and (bot.PrimaryPart.Position - position).Magnitude < 30 then
			damageWorkerBot(bot, 1000, attacker)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local c = other.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if h and hrp and h.Health > 0 then
			local d = (hrp.Position - position).Magnitude
			if d < 30 then h:TakeDamage(math.max(30, 140 * (1 - d / 30))) end
		end
	end
	return true
end

-- Scorch mark, smoke puff and sparks wherever a round lands.
local function spawnImpact(position, normal)
	local hole = Instance.new("Part")
	hole.Name = "BulletHole"
	hole.Size = Vector3.new(0.3, 0.3, 0.06)
	hole.CFrame = CFrame.lookAt(position + normal * 0.03, position + normal * 2)
	hole.Color = Color3.fromRGB(24, 22, 21)
	hole.Material = Enum.Material.Slate
	hole.Anchored = true
	hole.CanCollide = false
	hole.CanQuery = false
	hole.CanTouch = false
	hole.CastShadow = false
	hole.Parent = workspace
	Debris:AddItem(hole, 45)

	local puff = Instance.new("Part")
	puff.Name = "ImpactPuff"
	puff.Size = Vector3.new(0.1, 0.1, 0.1)
	puff.CFrame = CFrame.new(position + normal * 0.25)
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.CanTouch = false
	puff.Transparency = 1
	puff.Parent = workspace
	local smoke = Instance.new("Smoke")
	smoke.Size = 0.7
	smoke.RiseVelocity = 5
	smoke.Opacity = 0.3
	smoke.Color = Color3.fromRGB(125, 125, 125)
	smoke.Parent = puff
	local sparks = Instance.new("Sparkles")
	sparks.SparkleColor = Color3.fromRGB(255, 208, 128)
	sparks.Parent = puff
	task.delay(0.3, function()
		if puff.Parent then smoke.Enabled = false; sparks.Enabled = false end
	end)
	Debris:AddItem(puff, 3)
end

-- Posters keep their holes for good rather than fading like scorch marks.
local function punchPoster(poster, position, normal)
	local holes = poster:GetAttribute("Holes") or 0
	if holes >= 30 then return end
	poster:SetAttribute("Holes", holes + 1)
	local tear = Instance.new("Part")
	tear.Name = "PosterTear"
	tear.Size = Vector3.new(0.36, 0.36, 0.03)
	tear.CFrame = CFrame.lookAt(position + normal * 0.012, position + normal * 2)
	tear.Color = Color3.fromRGB(198, 190, 174)
	tear.Material = Enum.Material.SmoothPlastic
	tear.Anchored = true
	tear.CanCollide = false
	tear.CanQuery = false
	tear.CanTouch = false
	tear.CastShadow = false
	tear.Parent = poster
	local hole = tear:Clone()
	hole.Name = "PosterHole"
	hole.Size = Vector3.new(0.22, 0.22, 0.05)
	hole.Color = Color3.fromRGB(16, 15, 14)
	hole.CFrame = CFrame.lookAt(position + normal * 0.025, position + normal * 2)
	hole.Parent = poster
end

local function workerBotFromHit(hit)
	local model = hit and hit:FindFirstAncestorOfClass("Model")
	return model and CollectionService:HasTag(model, "LabWorkerBot") and model or nil
end

local function stealHeldSample(attacker, victim)
	local sample = findHeldSample(victim)
	if not sample then
		notify(attacker, victim.DisplayName .. " is not holding a sample.")
		return false
	end
	if sample:GetAttribute("TransferSample") and findTransferSample(attacker) then
		notify(attacker, "Your hands are already assigned to another cold-store sample.")
		return false
	end

	local backpack = attacker:FindFirstChildOfClass("Backpack")
	if not backpack then return false end
	local id = sample:GetAttribute("SampleId") or sample.Name
	sample.Parent = backpack
	setCarryState(victim, nil)
	setCarryState(attacker, sample)
	addContribution(attacker)
	notify(attacker, "Recovered " .. id .. " from " .. victim.DisplayName .. ". It is now in your hand.")
	notify(victim, attacker.DisplayName .. " took " .. id .. " from your hand. Collect or recover another sample.")
	equipTool(attacker, sample)
	return true
end

local function armImpactTool(tool)
	if tool:GetAttribute("HitLogicBound") then return end
	tool:SetAttribute("HitLogicBound", true)
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	local style = IMPACT_STYLE[tool:GetAttribute("ImpactToolKind") or tool.Name]
	if not style then return end

	local activeUntil = 0
	local nextSwing = 0
	local hitThisSwing = {}

	tool.Activated:Connect(function()
		-- Every gun is driven by BlasterController on the owning client.
		-- Keep Tool.Activated for melee and throwable tools only, avoiding
		-- duplicate shots from Roblox's default Tool activation path.
		if style.mode == "gun" then return end
		local owner = Players:GetPlayerFromCharacter(tool.Parent)
		if not owner or os.clock() < nextSwing then return end
		nextSwing = os.clock() + (style.mode == "gun" and 0.55 or 0.8)
		hitThisSwing = {}
		local original = handle.Color
		handle.Color = Color3.fromRGB(255, 245, 190)
		task.delay(0.18, function()
			if handle.Parent then handle.Color = original end
		end)

		local rootPart = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end
		if style.mode == "gun" then
			local origin = rootPart.Position + Vector3.new(0, 1.25, 0) + rootPart.CFrame.LookVector * 2
			local direction = rootPart.CFrame.LookVector * (style.range or 100)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {owner.Character}
			local result = workspace:Raycast(origin, direction, params)
			local hitPosition = result and result.Position or (origin + direction)
			local beam = Instance.new("Part")
			beam.Name = "FoamTracer"
			beam.Size = Vector3.new(0.08, 0.08, (hitPosition - origin).Magnitude)
			beam.CFrame = CFrame.lookAt((origin + hitPosition) / 2, hitPosition)
			beam.Color = style.colour
			beam.Material = Enum.Material.Neon
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanTouch = false
			beam.Parent = workspace
			Debris:AddItem(beam, 0.12)
			local bot = result and workerBotFromHit(result.Instance)
			if bot then damageWorkerBot(bot, style.damage or 25, owner) end
			return
		elseif style.mode == "ball" then
			local ball = Instance.new("Part")
			ball.Name = "ThrownBasketball"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(1.35, 1.35, 1.35)
			ball.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.3, 0) + rootPart.CFrame.LookVector * 3)
			ball.Color = style.colour
			ball.Material = Enum.Material.Rubber
			ball.CanCollide = true
			ball.Parent = workspace
			ball.AssemblyLinearVelocity = rootPart.CFrame.LookVector * 58 + Vector3.new(0, 13, 0)
			local ballHit = false
			ball.Touched:Connect(function(hit)
				if ballHit then return end
				local bot = workerBotFromHit(hit)
				if bot then ballHit = true; damageWorkerBot(bot, style.damage or 20, owner) end
			end)
			Debris:AddItem(ball, 7)
			return
		end
		activeUntil = os.clock() + 0.45
	end)

	handle.Touched:Connect(function(hit)
		if os.clock() > activeUntil then return end
		local attacker = Players:GetPlayerFromCharacter(tool.Parent)
		if not attacker then return end
		local targetCharacter = hit:FindFirstAncestorOfClass("Model")
		local workerBot = workerBotFromHit(hit)
		if workerBot then
			if hitThisSwing[workerBot] then return end
			hitThisSwing[workerBot] = true
			damageWorkerBot(workerBot, style.damage or 15, attacker)
			return
		end
		local victim = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
		if not victim or victim == attacker or hitThisSwing[victim] then return end

		local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
		local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		local victimHumanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
		if not attackerRoot or not victimRoot or not victimHumanoid or victimHumanoid.Health <= 0 then return end
		if (attackerRoot.Position - victimRoot.Position).Magnitude > 9 then return end
		hitThisSwing[victim] = true

		local delta = victimRoot.Position - attackerRoot.Position
		if delta.Magnitude > 0.1 then
			local direction = delta.Unit
			victimRoot.AssemblyLinearVelocity = victimRoot.AssemblyLinearVelocity
				+ Vector3.new(direction.X * 9, 3, direction.Z * 9)
		end

		local flash = Instance.new("Highlight")
		flash.Name = "SampleRecoveryHit"
		flash.FillColor = Color3.fromRGB(255, 210, 80)
		flash.OutlineColor = Color3.fromRGB(255, 255, 255)
		flash.FillTransparency = 0.35
		flash.Parent = victim.Character
		Debris:AddItem(flash, 0.25)
		stealHeldSample(attacker, victim)
	end)
end

local function findImpactTool(player, kind)
	for _, container in ipairs(playerContainers(player)) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("ImpactToolKind") == kind then return child end
			end
		end
	end
	return nil
end

local function makeImpactTool(player, kind)
	local existing = findImpactTool(player, kind)
	if existing then
		equipTool(player, existing)
		notify(player, kind .. " equipped. Click or tap to use it against worker NPCs or recover a held sample from another player.")
		return existing
	end

	local style = IMPACT_STYLE[kind]
	if not style then return nil end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then return nil end

	local tool = Instance.new("Tool")
	tool.Name = kind
	tool.ToolTip = style.mode == "gun" and "Fire at the screen crosshair; hold right-click or tap AIM for ADS"
		or (style.mode == "ball" and "Throw a basketball at worker NPCs" or "Hit players to recover samples; hit NPCs to lower life")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("ImpactToolKind", kind)
	tool:SetAttribute("LabImpactTool", true)
	if style.mode == "gun" then
		tool:SetAttribute("BlasterWeapon", true)
		tool:SetAttribute("BlasterDamage", style.damage or 25)
		tool:SetAttribute("BlasterRange", style.range or 200)
		tool:SetAttribute("BlasterCooldown", style.cooldown or 0.55)
		tool:SetAttribute("BlasterPellets", style.pellets or 1)
		tool:SetAttribute("BlasterSpread", style.spread or 0)
		tool:SetAttribute("BlasterSelfCostPercent", style.selfCostPercent or 0)
		-- A head shot doubles damage; it no longer kills outright. With this on,
		-- ANY weapon one-shot a worker whenever the ray cleared the collision
		-- hull and caught the head, which is what made every gun lethal in one.
		tool:SetAttribute("BlasterInstantHeadshot", false)
		tool:SetAttribute("BlasterAutomatic", style.automatic == true)
		tool:SetAttribute("BlasterADSFOV", (style.range or 0) >= 500 and 44 or ((style.pellets or 1) > 1 and 58 or 54))
		tool:SetAttribute("BlasterADSTouchSensitivity", 0.42)
		tool:SetAttribute("BlasterTracerColor", style.colour)
		-- Legacy marker retained for old saved tools; the legacy remote is inert.
		if style.pcOnly then tool:SetAttribute("LabSidearm", true) end
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = style.mode == "gun" and Vector3.new(0.72, 0.88, 2.2)
		or (style.mode == "ball" and Vector3.new(1.35, 1.35, 1.35) or Vector3.new(0.42, 3.4, 0.42))
	handle.Color = style.colour
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	if style.mode == "ball" then handle.Shape = Enum.PartType.Ball; handle.Material = Enum.Material.Rubber end

	if style.meshId then
		-- Imported gun shape. A SpecialMesh is used rather than a MeshPart
		-- because MeshPart.MeshId cannot be assigned at runtime -- SpecialMesh
		-- can, so the tool builds correctly on a live server as well as in
		-- Studio, with no dependency on anything sitting in ServerStorage.
		handle.Size = style.handleSize or Vector3.new(0.20, 0.92, 1.36)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = style.meshId
		if style.meshTexture then mesh.TextureId = style.meshTexture end
		local scale = style.meshScale or 1.6
		mesh.Scale = Vector3.new(scale, scale, scale)
		mesh.Parent = handle
	elseif style.mode == "gun" then
		addWeldedPart(tool, handle, "Barrel", Vector3.new(0.34, 0.34, 1.7),
			CFrame.new(0, 0.1, -1.65), style.colour, Enum.Material.Neon)
		addWeldedPart(tool, handle, "GunGrip", Vector3.new(0.48, 1.05, 0.55),
			CFrame.new(0, -0.75, 0.42) * CFrame.Angles(math.rad(-18), 0, 0), style.accent, Enum.Material.Rubber)
	elseif kind == "Inspection Paddle" then
		addWeldedPart(tool, handle, "Paddle", Vector3.new(1.45, 1.65, 0.28),
			CFrame.new(0, 2.15, 0), style.colour, Enum.Material.SmoothPlastic)
	elseif kind == "Sample Grabber" then
		addWeldedPart(tool, handle, "LeftClaw", Vector3.new(0.25, 1.1, 0.3),
			CFrame.new(-0.38, 1.95, 0) * CFrame.Angles(0, 0, math.rad(-28)), style.accent, Enum.Material.Metal)
		addWeldedPart(tool, handle, "RightClaw", Vector3.new(0.25, 1.1, 0.3),
			CFrame.new(0.38, 1.95, 0) * CFrame.Angles(0, 0, math.rad(28)), style.accent, Enum.Material.Metal)
	elseif style.mode == "melee" then
		addWeldedPart(tool, handle, "FoamTip", Vector3.new(0.75, 1.5, 0.75),
			CFrame.new(0, 2, 0), style.colour, Enum.Material.Fabric)
	end
	if style.mode == "melee" then
		addWeldedPart(tool, handle, "Grip", Vector3.new(0.58, 1.15, 0.58),
			CFrame.new(0, -1.1, 0), style.accent, Enum.Material.Rubber)
	end

	tool.Grip = style.grip or (style.mode == "gun" and CFrame.new(0, -0.2, 0.6))
		or (style.mode == "ball" and CFrame.new(0, -0.25, -0.4) or CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(-8), 0, 0))
	tool.Parent = backpack
	armImpactTool(tool)
	equipTool(player, tool)
	notify(player, kind .. " equipped. Click or tap to use it against worker NPCs; their LIFE bar shows damage and recovery.")
	return tool
end

local function bindDispenser(part)
	if part:GetAttribute("DispenserBound") then return end
	local kind = part:GetAttribute("ToolKind")
	if not kind or not IMPACT_STYLE[kind] then return end
	part:SetAttribute("DispenserBound", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = kind
	prompt.ActionText = "Equip combat tool"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local lastUse = {}
	prompt.Triggered:Connect(function(player)
		if not canInteract(player, part, prompt.MaxActivationDistance) then return end
		if os.clock() < (lastUse[player] or 0) then return end
		lastUse[player] = os.clock() + 0.75
		makeImpactTool(player, kind)
	end)
end

--------------------------------------------------------------------
-- PC SIDEARM -- mouse-aimed, costs the shooter 1% of their life per shot
--
-- Fired only through this remote, which only the desktop client script
-- sends, so the weapon is inert on touch and console clients.
--------------------------------------------------------------------
local sidearmRemote = ReplicatedStorage:FindFirstChild("LabSidearmFire")
if not sidearmRemote then
	sidearmRemote = Instance.new("RemoteEvent")
	sidearmRemote.Name = "LabSidearmFire"
	sidearmRemote.Parent = ReplicatedStorage
end

local sidearmCooldown = {}
Players.PlayerRemoving:Connect(function(player) sidearmCooldown[player] = nil end)

sidearmRemote.OnServerEvent:Connect(function(player, aimPoint)
	-- Superseded by ServerBlasterManager. Keep the legacy remote inert so
	-- old clients and exploit traffic cannot enter the retired mouse path.
	if true then return end
	if typeof(aimPoint) ~= "Vector3" then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return end

	-- The client only ever asks; the server decides whether the player is
	-- really holding a weapon, and what that weapon is allowed to do.
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("LabSidearm") then return end
	local style = IMPACT_STYLE[tool:GetAttribute("ImpactToolKind") or ""]
	if not style then return end

	local now = os.clock()
	if now < (sidearmCooldown[player] or 0) then return end
	sidearmCooldown[player] = now + (style.cooldown or 0.35)

	local handle = tool:FindFirstChild("Handle")
	local origin = (handle and handle.Position or root.Position) + Vector3.new(0, 0.5, 0)
	local baseDelta = aimPoint - origin
	if baseDelta.Magnitude < 0.1 then return end
	local baseDir = baseDelta.Unit
	local range = style.range or 200

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}

	local killsThisShot = 0
	for _ = 1, (style.pellets or 1) do
		-- Shotgun pellets scatter around the aim line; everything else is exact.
		local dir = baseDir
		local spread = style.spread or 0
		if spread > 0 then
			dir = (baseDir + Vector3.new(
				(math.random() - 0.5) * spread * 2,
				(math.random() - 0.5) * spread * 2,
				(math.random() - 0.5) * spread * 2)).Unit
		end

		local result = workspace:Raycast(origin, dir * range, params)
		local hitPosition = result and result.Position or (origin + dir * range)

		local beam = Instance.new("Part")
		beam.Name = "SidearmTracer"
		beam.Size = Vector3.new(0.07, 0.07, (hitPosition - origin).Magnitude)
		beam.CFrame = CFrame.lookAt((origin + hitPosition) / 2, hitPosition)
		beam.Color = Color3.fromRGB(255, 226, 140)
		beam.Material = Enum.Material.Neon
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanTouch = false
		beam.CanQuery = false
		beam.CastShadow = false
		beam.Parent = workspace
		Debris:AddItem(beam, 0.1)

		if result then
			local instance, normal = result.Instance, result.Normal
			local bot = workerBotFromHit(instance)
			if bot and not bot:GetAttribute("Dead") then
				-- A head shot doubles damage rather than killing outright, so no
				-- weapon removes a full-health worker in a single shot.
				local headShot = instance.Name == "Head"
				damageWorkerBot(bot, (style.damage or 25) * (headShot and 2 or 1), player)
				if bot:GetAttribute("Dead") then killsThisShot = killsThisShot + 1 end
			elseif instance:GetAttribute("GasPipe") then
				detonateGasPipe(instance, player, hitPosition)
				spawnImpact(hitPosition, normal)
			else
				local equipment = equipmentFromHit(instance)
				if equipment then
					explodeEquipment(equipment, player)
				elseif instance:GetAttribute("ShootablePoster") then
					punchPoster(instance, hitPosition, normal)
				end
				spawnImpact(hitPosition, normal)
			end
		end
	end

	-- Firing always costs the shooter 1% of their own maximum health,
	-- whether or not the shot connects with anything.
	humanoid:TakeDamage(humanoid.MaxHealth * (style.selfCostPercent or 1) / 100)

	if killsThisShot > 0 then
		local complex = workspace:FindFirstChild("Laboratory_Complex")
		notify(player, string.format("Target down.  %d / %d cleared.",
			complex and complex:GetAttribute("BotsKilled") or 0,
			complex and complex:GetAttribute("BotsTotal") or 0))
	end
end)

--------------------------------------------------------------------
-- BLASTER GAMEPLAY BRIDGE
-- ServerBlasterManager owns validation and raycasts. This callback only
-- translates a validated impact into this game's custom worker/environment
-- systems, keeping those systems private to the server.
--------------------------------------------------------------------
local blasterBridge = game:GetService("ServerScriptService"):FindFirstChild("BlasterHitBridge")
if not blasterBridge then
	blasterBridge = Instance.new("BindableFunction")
	blasterBridge.Name = "BlasterHitBridge"
	blasterBridge.Parent = game:GetService("ServerScriptService")
end

blasterBridge.OnInvoke = function(player, instance, hitPosition, hitNormal, damage, instantHeadshot)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	if typeof(instance) ~= "Instance" or not instance:IsDescendantOf(workspace) then return false end

	-- This receives an already-validated bullet impact; aiming/firing is unchanged.
	if instance:GetAttribute("BreakableWindow") then
		if instance:GetAttribute("WindowBroken") then return false end
		instance:SetAttribute("WindowBroken", true)
		instance.Transparency = 1
		instance.CanCollide, instance.CanTouch, instance.CanQuery = false, false, false
		spawnImpact(hitPosition, hitNormal)
		return true
	end

	local bot = workerBotFromHit(instance)
	if bot then
		local wasDead = bot:GetAttribute("Dead") == true
		local handled = damageWorkerBot(bot, instantHeadshot and 1000 or damage, player)
		if handled and not wasDead and bot:GetAttribute("Dead") then
			local complex = workspace:FindFirstChild("Laboratory_Complex")
			notify(player, string.format("Target down.  %d / %d cleared.",
				complex and complex:GetAttribute("BotsKilled") or 0,
				complex and complex:GetAttribute("BotsTotal") or 0))
		end
		return handled
	end

	if instance:GetAttribute("GasPipe") then
		detonateGasPipe(instance, player, hitPosition)
		spawnImpact(hitPosition, hitNormal)
		return true
	end

	local equipment = equipmentFromHit(instance)
	if equipment then
		explodeEquipment(equipment, player)
		spawnImpact(hitPosition, hitNormal)
		return true
	end

	if instance:GetAttribute("ShootablePoster") then
		punchPoster(instance, hitPosition, hitNormal)
		spawnImpact(hitPosition, hitNormal)
		return true
	end

	return false
end

--------------------------------------------------------------------
-- COLD-STORE SAMPLE TRANSFERS
--------------------------------------------------------------------
local COLD_STORE = {Refrigerator = true, ["Chest Freezer"] = true}
local nextSampleNumber = 1000

local PLANT_CHAMBER_KIND = "Plant Growth Chamber"

local function equipmentFloorLabel(part)
	return part:GetAttribute("FloorLabel") or part:GetAttribute("Level") or "UNKNOWN FLOOR"
end

local function equipmentId(part)
	local code = part:GetAttribute("GrowthCode")
	if code and code ~= "" then return "CHAMBER:" .. code end
	return table.concat({part:GetAttribute("Level") or "Lab", part:GetAttribute("Room") or "Room", part.Name}, "|")
end

local function equipmentLabel(part)
	local code = part:GetAttribute("GrowthCode")
	if code and code ~= "" then return "CHAMBER " .. code end
	return (part:GetAttribute("Kind") or part.Name) .. " / " .. (part:GetAttribute("Room") or "Lab")
end

local function adaptiveTransferSeconds(source, destination)
	local distance = destination and (destination.Position - source.Position).Magnitude or 60
	local playerCount = math.max(1, #Players:GetPlayers())
	local complex = workspace:FindFirstChild("Laboratory_Complex")
	local backlog = complex and (complex:GetAttribute("FailedSampleBacklog") or 0) or 0
	return math.clamp(math.floor(180 + distance * 1.2 + math.max(0, 3 - playerCount) * 15
		+ math.clamp(backlog / 20, 0, 30)), 180, 420)
end
local PLANT_PROCESS = {
	["Germination Chamber"] = {
		key = "Germination", gain = 1,
		caption = "Warming seed and logging germination response",
	},
	["Incubator"] = {
		key = "Incubation", gain = 1,
		caption = "Holding controlled temperature and humidity",
	},
	["Growth Hormone Mixer"] = {
		key = "Growth Hormone", gain = 2,
		caption = "Dosing auxin/cytokinin growth treatment",
	},
	["GMO Injector"] = {
		key = "GMO Injection", gain = 1, genome = true,
		caption = "Injecting and verifying a new plant trait",
	},
	["Nutrient Infuser"] = {
		key = "Nutrient Infusion", gain = 1, moistureGain = 18,
		caption = "Balancing nitrogen, phosphorus, and potassium",
	},
	["UV Growth Scanner"] = {
		repeatable = true, gain = 0,
		caption = "Scanning chlorophyll and canopy development",
	},
	["Pollination Station"] = {
		key = "Pollination", gain = 1, minStage = 3,
		caption = "Applying controlled pollen and checking viability",
	},
	-- Micropropagation chain, step 1: surface-sterilize the seed coat before
	-- it ever reaches a growth chamber. Nothing downstream requires this, but
	-- a Sterilized sample gets a real (and referenced) germination boost --
	-- contamination is the #1 real-world cause of failed plant tissue culture.
	["Decontamination Unit"] = {
		key = "Sterilized", gain = 0,
		caption = "Surface-sterilizing seed coat (dilute bleach + ethanol rinse) and sealing on sterile media",
	},
	-- Dose-response mutagenesis modeled on the reference Viola cornuta gamma
	-- study: germination viability falls off steeply above ~400 Gy, and by
	-- 1000 Gy almost nothing survives. Dose is chosen per treatment so two
	-- visits to the same chamber can give a different, honestly-labeled result.
	["Mutagenesis Chamber"] = {
		key = "Mutagenesis", gain = 0, mutagenesis = true,
		caption = "Irradiating seed with a measured gamma dose",
	},
	-- Hormone Treatment Bench: auxin pushes rooting, cytokinin pushes
	-- shoot/bud growth, and a balanced ratio pushes both -- the same
	-- direction of effect reported for lemon seed germination trials.
	["Hormone Treatment Bench"] = {
		key = "Hormone Treatment", gain = 1, hormone = true,
		caption = "Dosing a measured auxin/cytokinin treatment",
	},
}

local function storageId(part)
	local id = part:GetAttribute("StorageId")
	if not id then
		id = table.concat({part:GetAttribute("Level") or "Lab", part:GetAttribute("Room") or "Room", part.Name}, "|")
		part:SetAttribute("StorageId", id)
	end
	return id
end

local function storageLabel(part)
	local unit = part.Name:match("_(%d+)$") or "1"
	return string.format("%s, %s, %s (unit %s)", part:GetAttribute("Kind") or "Cold store",
		part:GetAttribute("Level") or "Lab", part:GetAttribute("Room") or "room", unit)
end

local function coldStoresExcept(source)
	local stores = {}
	for _, candidate in ipairs(CollectionService:GetTagged("LabEquipment")) do
		if candidate ~= source and COLD_STORE[candidate:GetAttribute("Kind")] then
			table.insert(stores, candidate)
		end
	end
	table.sort(stores, function(a, b) return storageId(a) < storageId(b) end)
	return stores
end

--------------------------------------------------------------------
-- PHYSICAL CONTROL BUTTON AND DATA DISPLAY
--------------------------------------------------------------------
local function makeControls(part, kind, spec)
	local wallSide = part:GetAttribute("WallSide")
	local frontAxisX = wallSide == "W" or wallSide == "E"
	local frontDirection = ((wallSide == "E") or (wallSide == "S")) and -1 or 1
	local isGrowthChamber = kind == PLANT_CHAMBER_KIND
	local isPlantContainer = (part:GetAttribute("Capacity") or 0) > 0
	local timerGui = Instance.new("BillboardGui")
	timerGui.Name = "EquipmentStatusTimer"
	timerGui.Size = UDim2.fromOffset(160, 32)
	timerGui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3.8, 0)
	timerGui.MaxDistance = 10
	timerGui.AlwaysOnTop = false
	timerGui.Parent = part
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.Size = UDim2.fromScale(1, 1)
	timerLabel.BackgroundColor3 = Color3.fromRGB(12, 16, 18)
	timerLabel.BackgroundTransparency = 0.16
	timerLabel.BorderSizePixel = 0
	timerLabel.TextScaled = true
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = timerGui
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 8)
	timerCorner.Parent = timerLabel

	-- Equipment name plate, mounted directly above the RUNNING/FAILED timer
	-- badge so each unit's kind is obvious at a glance from close range.
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "EquipmentNamePlate"
	nameGui.Size = UDim2.fromOffset(160, 24)
	nameGui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 5.4, 0)
	nameGui.MaxDistance = 10
	nameGui.AlwaysOnTop = false
	nameGui.Parent = part
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Kind"
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundColor3 = Color3.fromRGB(235, 200, 60)
	nameLabel.BackgroundTransparency = 0.05
	nameLabel.BorderSizePixel = 0
	nameLabel.Text = kind
	nameLabel.TextColor3 = Color3.fromRGB(20, 20, 20)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.Parent = nameGui
	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 8)
	nameCorner.Parent = nameLabel

	local slotGui = Instance.new("BillboardGui")
	slotGui.Name = "EquipmentFreeSlots"
	slotGui.Size = UDim2.fromOffset(150, 28)
	slotGui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 2.7, 0)
	slotGui.MaxDistance = 10
	slotGui.AlwaysOnTop = false
	slotGui.Parent = part
	local slotLabel = Instance.new("TextLabel")
	slotLabel.Name = "FreeSlots"
	slotLabel.Size = UDim2.fromScale(1, 1)
	slotLabel.BackgroundColor3 = Color3.fromRGB(12, 19, 22)
	slotLabel.BackgroundTransparency = 0.12
	slotLabel.BorderSizePixel = 0
	slotLabel.TextScaled = true
	slotLabel.Font = Enum.Font.GothamBold
	slotLabel.Parent = slotGui
	local slotCorner = Instance.new("UICorner")
	slotCorner.CornerRadius = UDim.new(0, 8)
	slotCorner.Parent = slotLabel
	local storedLifeGui, storedLifeText, storedLifeFill
	if isPlantContainer then
		local plantAnchor = part:FindFirstChild("ChamberSample_01_Stem") or part
		storedLifeGui = Instance.new("BillboardGui")
		storedLifeGui.Name = "StoredPlantLifeStatus"
		storedLifeGui.Size = UDim2.fromOffset(140, 40)
		storedLifeGui.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
		storedLifeGui.MaxDistance = 10
		storedLifeGui.AlwaysOnTop = false
		storedLifeGui.Parent = plantAnchor
		storedLifeText = Instance.new("TextLabel")
		storedLifeText.Size = UDim2.new(1, 0, 0.62, 0)
		storedLifeText.BackgroundColor3 = Color3.fromRGB(16, 20, 18)
		storedLifeText.BackgroundTransparency = 0.16
		storedLifeText.BorderSizePixel = 0
		storedLifeText.TextScaled = true
		storedLifeText.Font = Enum.Font.GothamBold
		storedLifeText.Parent = storedLifeGui
		local storedLifeBack = Instance.new("Frame")
		storedLifeBack.Size = UDim2.new(0.9, 0, 0.2, 0)
		storedLifeBack.Position = UDim2.new(0.05, 0, 0.72, 0)
		storedLifeBack.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
		storedLifeBack.BorderSizePixel = 0
		storedLifeBack.Parent = storedLifeGui
		storedLifeFill = Instance.new("Frame")
		storedLifeFill.Size = UDim2.fromScale(1, 1)
		storedLifeFill.BorderSizePixel = 0
		storedLifeFill.Parent = storedLifeBack
	end
	local function clockText(seconds)
		seconds = math.max(0, math.floor(seconds or 0))
		return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	end
	local function renderTimer()
		local state = part:GetAttribute("FunctionalState")
		local destroyed = state == "DESTROYED"
		local failed = destroyed or state == "FAILED"
		local since = failed and (part:GetAttribute("FailureSince") or os.time())
			or (part:GetAttribute("OperationStarted") or os.time())
		if destroyed then
			timerLabel.Text = "DESTROYED -- UNFIXABLE"
			timerLabel.TextColor3 = Color3.fromRGB(90, 90, 95)
		else
			timerLabel.Text = (failed and "FAILED  " or "RUNNING  ") .. clockText(os.time() - since)
			timerLabel.TextColor3 = failed and Color3.fromRGB(255, 75, 65) or Color3.fromRGB(75, 255, 125)
		end
		if isPlantContainer and failed then
			local life = math.clamp(100 - math.floor(math.max(0, os.time() - since - 120) / 6), 0, 100)
			part:SetAttribute("PlantLife", life)
			if life <= 0 and (part:GetAttribute("SampleCount") or 0) > 0 then
				part:SetAttribute("SampleIds", "")
				part:SetAttribute("SampleCount", 0)
				part:SetAttribute("Occupied", false)
				part:SetAttribute("PlantId", "")
				part:SetAttribute("PlantExpiredAt", os.time())
				for _, child in ipairs(part:GetDescendants()) do
					if child:IsA("BasePart") and child:GetAttribute("SampleSlot") then child.Transparency = 1 end
				end
			end
		end
		local capacity = part:GetAttribute("Capacity") or 0
		local count = math.clamp(part:GetAttribute("SampleCount") or 0, 0, capacity)
		local free = math.max(0, capacity - count)
		slotLabel.Text = free == 0 and ("FULL  •  " .. count .. "/" .. capacity)
			or string.format("%d FREE SLOT%s  •  %d/%d", free, free == 1 and "" or "S", count, capacity)
		slotLabel.TextColor3 = free == 0 and Color3.fromRGB(255, 80, 70) or Color3.fromRGB(90, 235, 180)
		-- Beacon: someone is actively carrying a plant toward THIS chamber
		-- (IncomingReservations is set the moment a plant is taken with this
		-- chamber as its destination). Make that one chamber's slot readout
		-- visible from across the room -- through walls too -- so "where do I
		-- put this plant" is answered by looking up, not by wandering every
		-- aisle reading labels that are otherwise only readable up close.
		local incoming = (part:GetAttribute("IncomingReservations") or 0) > 0
		if incoming and not failed then
			slotGui.MaxDistance = 30
			slotGui.AlwaysOnTop = false
			slotLabel.Text = "★ DROP HERE ★  " .. slotLabel.Text
			slotLabel.TextColor3 = Color3.fromRGB(120, 255, 170)
		else
			slotGui.MaxDistance = 10
			slotGui.AlwaysOnTop = false
		end
		if storedLifeGui then
			local life = math.clamp(part:GetAttribute("PlantLife") or 100, 0, 100)
			local colour = life > 60 and Color3.fromRGB(75, 235, 105)
				or (life > 30 and Color3.fromRGB(255, 190, 55) or Color3.fromRGB(255, 70, 60))
			storedLifeGui.Enabled = (part:GetAttribute("SampleCount") or 0) > 0
			storedLifeText.Text = "PLANT LIFE " .. math.floor(life + 0.5) .. "%"
			storedLifeText.TextColor3 = colour
			storedLifeFill.Size = UDim2.new(life / 100, 0, 1, 0)
			storedLifeFill.BackgroundColor3 = colour
		end
	end
	renderTimer()
	task.spawn(function()
		while part.Parent do
			renderTimer()
			task.wait(1)
		end
	end)

	local button = Instance.new("Part")
	button.Name = "PushButton"
	button.Shape = Enum.PartType.Cylinder
	button.Size = isGrowthChamber and Vector3.new(0.24, 0.64, 0.64) or Vector3.new(0.2, 0.48, 0.48)
	local buttonSide = math.clamp((frontAxisX and part.Size.Z or part.Size.X) * 0.34, 0.25, 1.2)
	local buttonY = math.clamp(part.Size.Y * 0.03, -0.15, 0.45)
	if frontAxisX then
		button.CFrame = part.CFrame * CFrame.new(frontDirection * (part.Size.X / 2 + 0.16), buttonY, buttonSide)
	else
		button.CFrame = part.CFrame * CFrame.new(-buttonSide, buttonY, frontDirection * (part.Size.Z / 2 + 0.16))
			* CFrame.Angles(0, math.rad(90), 0)
	end
	button.Color = Color3.fromRGB(218, 68, 58)
	button.Material = Enum.Material.Neon
	button.Anchored = true
	button.CanCollide = false
	button.CanTouch = false
	button.CastShadow = false
	button.Parent = part
	local restCFrame = button.CFrame

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = isGrowthChamber
		and ((part:GetAttribute("FloorLabel") or part:GetAttribute("Level") or "FLOOR") .. " • CHAMBER " .. (part:GetAttribute("GrowthCode") or "R?"))
		or kind
	prompt.ActionText = isPlantContainer and "E: TAKE / DROP PLANT" or "E: USE / INSPECT"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = isPlantContainer and 0 or 0.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = true
	prompt.Parent = button

	local function setReadout(status, data, colour)
		part:SetAttribute("LastActionStatus", tostring(status or ""))
		part:SetAttribute("LastActionDetail", tostring(data or ""))
		renderTimer()
	end

	local function pressButton()
		button.Color = Color3.fromRGB(255, 205, 70)
		local down = TweenService:Create(button, TweenInfo.new(0.07, Enum.EasingStyle.Quad),
			{CFrame = restCFrame * CFrame.new(-0.11, 0, 0)})
		down:Play()
		down.Completed:Wait()
		local up = TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {CFrame = restCFrame})
		up:Play()
		task.delay(0.12, function()
			if button.Parent then button.Color = Color3.fromRGB(218, 68, 58) end
		end)
	end

	return prompt, setReadout, pressButton
end

local function runProgress(seconds, caption, setReadout)
	local steps = 4
	for step = 1, steps do
		task.wait(seconds / steps)
		setReadout("RUNNING  " .. (step * 25) .. "%", caption, Color3.fromRGB(255, 205, 80))
	end
end

local emergencyMovesCompleted = 0
local setChamberFailure
local setGenericFailure

local function chamberSampleList(chamber)
	local samples = {}
	for id in string.gmatch(chamber:GetAttribute("SampleIds") or "", "[^|]+") do table.insert(samples, id) end
	return samples
end

local function saveChamberSamples(chamber, samples)
	local capacity = chamber:GetAttribute("Capacity") or 10
	while #samples > capacity do table.remove(samples) end
	chamber:SetAttribute("SampleIds", table.concat(samples, "|"))
	chamber:SetAttribute("SampleCount", #samples)
	chamber:SetAttribute("Occupied", #samples > 0)
	chamber:SetAttribute("PlantId", samples[1] or "")
end

local function formatRuntime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function recoverPlantLife(chamber, startingLife, player, plantId)
	startingLife = math.clamp(startingLife or 100, 0, 100)
	if startingLife >= 100 or chamber:GetAttribute("FunctionalState") == "FAILED" then
		chamber:SetAttribute("PlantLife", startingLife)
		return 0
	end
	local seconds = math.clamp(math.ceil((100 - startingLife) / 16), 3, 7)
	local token = (chamber:GetAttribute("RecoveryToken") or 0) + 1
	chamber:SetAttribute("RecoveryToken", token)
	chamber:SetAttribute("RecoveryEndsAt", os.time() + seconds)
	chamber:SetAttribute("PlantLife", startingLife)
	if player then
		player:SetAttribute("LabObjective", string.format("%s dropped in %s. LIFE %d%% → 100%% in %d seconds.",
			plantId or "Plant", chamber:GetAttribute("GrowthCode") or equipmentLabel(chamber), startingLife, seconds))
		notify(player, string.format("Plant LIFE %d%%. Recovery started; full life in %d seconds.", startingLife, seconds))
	end
	task.spawn(function()
		for step = 1, seconds do
			task.wait(1)
			if not chamber.Parent or chamber:GetAttribute("RecoveryToken") ~= token
				or chamber:GetAttribute("FunctionalState") == "FAILED" then return end
			chamber:SetAttribute("PlantLife", math.floor(startingLife + (100 - startingLife) * step / seconds + 0.5))
		end
		chamber:SetAttribute("PlantLife", 100)
		chamber:SetAttribute("RecoveryEndsAt", 0)
		if player and player.Parent then notify(player, (plantId or "Plant") .. " recovered to 100% LIFE.") end
	end)
	return seconds
end

local function updateStoredSamples(chamber)
	local count = chamber:GetAttribute("SampleCount") or 0
	local stage = math.clamp(chamber:GetAttribute("GrowthStage") or 0, 0, 5)
	for _, child in ipairs(chamber:GetDescendants()) do
		if child:IsA("BasePart") and child:GetAttribute("SampleSlot") then
			local visible = child:GetAttribute("SampleSlot") <= count
			child.Transparency = visible and (child:GetAttribute("StoredTransparency") or 0) or 1
			if child.Name:match("Stem") then child.Color = Color3.fromRGB(55 + stage * 4, 145 + stage * 10, 65)
			elseif child.Name:match("Leaf") then child.Color = Color3.fromRGB(65 + stage * 3, 160 + stage * 12, 75) end
		end
	end
end

local function refreshChamberTelemetry(chamber)
	local state = chamber:GetAttribute("FunctionalState") or "WORKING"
	local code = chamber:GetAttribute("GrowthCode") or equipmentLabel(chamber)
	local floorLabel = chamber:GetAttribute("FloorLabel") or chamber:GetAttribute("Level") or "UNKNOWN FLOOR"
	local samples = chamberSampleList(chamber)
	local sampleText = #samples > 0 and table.concat(samples, ", ") or "NO SAMPLES"
	local destination = chamber:GetAttribute("EvacuationDestination") or ""
	local detail = state == "FAILED" and ((chamber:GetAttribute("FailureReason") or "Unknown fault")
		.. (destination ~= "" and ("  -> MOVE TO " .. destination) or "  -> WAITING FOR SPACE")) or "SYSTEM NORMAL"
	local text = string.format("%s • CHAMBER %s • %s\nSAMPLES %d/%d • GERMINATED %s\nRUN %s • TEMP %d C • HUM %d%% • VENT %d%%\n%s\n%s",
		floorLabel, code, state, #samples, chamber:GetAttribute("Capacity") or 10,
		chamber:GetAttribute("GerminationDate") or "unknown",
		formatRuntime(os.time() - (chamber:GetAttribute("OperationStarted") or os.time())),
		chamber:GetAttribute("Temperature") or 0, chamber:GetAttribute("Humidity") or 0,
		chamber:GetAttribute("Ventilation") or 0, detail,
		state == "FAILED" and "REPAIR: HOLD R" or "CONTROL: E TAKE / DROP")
	for _, child in ipairs(chamber:GetDescendants()) do
		if child:IsA("TextLabel") and child.Name == "ChamberTelemetry" then
			child.Text = text
			-- DESTROYED must never read as fine (green): only a genuinely
			-- WORKING chamber gets green, FAILED gets the usual red, and a
			-- permanently DESTROYED one gets an even harsher red so it never
			-- gets mistaken for "just needs a repair."
			child.TextColor3 = state == "DESTROYED" and Color3.fromRGB(255, 50, 40)
				or state == "FAILED" and Color3.fromRGB(255, 105, 90)
				or Color3.fromRGB(105, 245, 160)
		elseif child:IsA("TextLabel") and child.Name == "ChamberSampleList" then
			child.Text = "PLANTS (" .. #samples .. "): " .. sampleText
		elseif child:IsA("BasePart") and child:GetAttribute("ChamberStatusLamp") then
			child.Color = state == "DESTROYED" and Color3.fromRGB(200, 20, 15)
				or state == "FAILED" and Color3.fromRGB(230, 55, 45)
				or Color3.fromRGB(40, 165, 95)
			child.Material = state == "DESTROYED" and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

local function evacuationDestinations(source)
	local sameLevel, anywhere = {}, {}
	for _, candidate in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
		local count = candidate:GetAttribute("SampleCount") or 0
		local capacity = candidate:GetAttribute("Capacity") or 10
		local incoming = candidate:GetAttribute("IncomingReservations") or 0
		if candidate ~= source and candidate:GetAttribute("FunctionalState") ~= "FAILED" and count + incoming < capacity then
			table.insert(anywhere, candidate)
			if candidate:GetAttribute("Level") == source:GetAttribute("Level") then table.insert(sameLevel, candidate) end
		end
	end
	local list = #sameLevel > 0 and sameLevel or anywhere
	table.sort(list, function(a, b)
		local ac = (a:GetAttribute("SampleCount") or 0) + (a:GetAttribute("IncomingReservations") or 0)
		local bc = (b:GetAttribute("SampleCount") or 0) + (b:GetAttribute("IncomingReservations") or 0)
		if ac == bc then return (a.Position - source.Position).Magnitude < (b.Position - source.Position).Magnitude end
		return ac < bc
	end)
	return list
end

local function repairPathFolder(player, create)
	local complex = workspace:FindFirstChild("Laboratory_Complex")
	if not complex then return nil end
	local rootFolder = complex:FindFirstChild("TechnicianRepairPaths")
	if create and not rootFolder then
		rootFolder = Instance.new("Folder")
		rootFolder.Name = "TechnicianRepairPaths"
		rootFolder.Parent = complex
	end
	local name = "Player_" .. player.UserId
	local folder = rootFolder and rootFolder:FindFirstChild(name)
	if create and not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = rootFolder
	end
	return folder
end

local function clearRepairPath(player)
	local folder = repairPathFolder(player, false)
	if folder then folder:Destroy() end
end

local function repairReward(player, equipment, assigned)
	local waited = math.max(0, os.time() - (equipment:GetAttribute("FailureSince") or os.time()))
	local distance = assigned and (player:GetAttribute("AssignedRepairDistance") or 0) or 0
	local points = 8 + math.floor(waited / 8) + math.floor(distance / 10) + (assigned and 12 or 0)
	return math.clamp(points, 8, 120), waited, distance
end

local function createRepairPath(player, target)
	clearRepairPath(player)
	local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not characterRoot or not target then return 0, false end
	local folder = repairPathFolder(player, true)
	if not folder then return 0, false end

	local function approachPoint(part)
		local side = part:GetAttribute("WallSide")
		local floorY = part.Position.Y - part.Size.Y / 2
		if side == "W" then return Vector3.new(part.Position.X + part.Size.X / 2 + 2.5, floorY, part.Position.Z) end
		if side == "E" then return Vector3.new(part.Position.X - part.Size.X / 2 - 2.5, floorY, part.Position.Z) end
		if side == "N" then return Vector3.new(part.Position.X, floorY, part.Position.Z + part.Size.Z / 2 + 2.5) end
		return Vector3.new(part.Position.X, floorY, part.Position.Z - part.Size.Z / 2 - 2.5)
	end
	local function appendNavigable(points, fromPosition, toPosition)
		local path = PathfindingService:CreatePath({
			AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
			AgentCanClimb = true, WaypointSpacing = 4,
		})
		local computed = pcall(function() path:ComputeAsync(fromPosition, toPosition) end)
		if not computed or path.Status ~= Enum.PathStatus.Success then return false end
		local waypoints = path:GetWaypoints()
		if #waypoints < 2 then return false end
		for index, waypoint in ipairs(waypoints) do
			if index > 1 or #points == 0 then table.insert(points, waypoint.Position) end
		end
		return true
	end

	local complex = workspace:FindFirstChild("Laboratory_Complex")
	local rise = complex and complex:GetAttribute("FloorRiseStuds")
	local westX = complex and complex:GetAttribute("StairWestLaneX")
	local eastX = complex and complex:GetAttribute("StairEastLaneX")
	local northZ = complex and complex:GetAttribute("StairNorthZ")
	local southZ = complex and complex:GetAttribute("StairSouthZ")
	local floorMin = (complex and complex:GetAttribute("FloorMinLevel")) or -1
	local floorMax = (complex and complex:GetAttribute("FloorMaxLevel")) or 2
	local destination = approachPoint(target)
	local points = {}
	local routeReady = false
	if rise and westX and eastX and northZ and southZ then
		local startFloor = math.clamp(math.floor((characterRoot.Position.Y - 2.5) / rise + 0.5), floorMin, floorMax)
		local targetFloor = math.clamp(math.floor(destination.Y / rise + 0.5), floorMin, floorMax)
		if startFloor == targetFloor then
			routeReady = appendNavigable(points, characterRoot.Position, destination)
		else
			local direction = targetFloor > startFloor and 1 or -1
			local firstLaneX = direction > 0 and westX or eastX
			local stairEntry = Vector3.new(firstLaneX, startFloor * rise, northZ)
			routeReady = appendNavigable(points, characterRoot.Position, stairEntry)
			local floor = startFloor
			while routeReady and floor ~= targetFloor do
				local baseY = floor * rise
				if direction > 0 then
					table.insert(points, Vector3.new(westX, baseY + rise / 2, southZ))
					table.insert(points, Vector3.new(eastX, baseY + rise / 2, southZ))
					table.insert(points, Vector3.new(eastX, baseY + rise, northZ))
				else
					table.insert(points, Vector3.new(eastX, baseY - rise / 2, southZ))
					table.insert(points, Vector3.new(westX, baseY - rise / 2, southZ))
					table.insert(points, Vector3.new(westX, baseY - rise, northZ))
				end
				floor = floor + direction
				if floor ~= targetFloor then
					table.insert(points, Vector3.new(direction > 0 and westX or eastX, floor * rise, northZ))
				end
			end
			if routeReady then
				routeReady = appendNavigable(points, points[#points], destination)
			end
		end
	end
	if not routeReady then
		folder:Destroy()
		player:SetAttribute("RepairRouteReady", false)
		return (destination - characterRoot.Position).Magnitude, false
	end
	player:SetAttribute("RepairRouteReady", true)
	local distance = 0
	local markerCount = 0
	for pointIndex = 1, #points - 1 do
		local a, b = points[pointIndex], points[pointIndex + 1]
		local delta = b - a
		local segmentDistance = delta.Magnitude
		distance = distance + segmentDistance
		if segmentDistance > 0.1 then
			local direction = delta.Unit
			local count = math.max(1, math.ceil(segmentDistance / 4))
			for index = 1, count do
				markerCount = markerCount + 1
				if markerCount > 120 then break end
				local marker = Instance.new("Part")
				marker.Name = "RedRepairPath"
				marker.Size = Vector3.new(0.55, 0.08, math.min(2.8, segmentDistance / count * 0.7))
				local position = a:Lerp(b, (index - 0.5) / count) + Vector3.new(0, 0.1, 0)
				marker.CFrame = CFrame.lookAt(position, position + direction)
				marker.Color = Color3.fromRGB(255, 32, 28)
				marker.Material = Enum.Material.Neon
				marker.Transparency = 0.12
				marker.Anchored = true
				marker.CanCollide = false
				marker.CanTouch = false
				marker.CanQuery = false
				marker.Parent = folder
			end
		end
		if markerCount > 120 then break end
	end
	return distance, true
end

local function clearAssignment(player)
	clearRepairPath(player)
	for _, name in ipairs({"AssignedRepairId", "AssignedRepairDistance", "AssignedRepairProjectedPoints", "AssignedTransferSource", "AssignedTransferDestination", "AssignedTransferDeadline"}) do
		player:SetAttribute(name, nil)
	end
end

local function assignNextTask(player)
	clearAssignment(player)
	local role = playerRole(player)
	if role == "Technician" then
		local failed = {}
		for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
			if equipment.Parent and equipment:GetAttribute("FunctionalState") == "FAILED" then table.insert(failed, equipment) end
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		table.sort(failed, function(a, b)
			if root then
				local aDistance = (a.Position - root.Position).Magnitude + (math.abs(a.Position.Y - root.Position.Y) > 12 and 500 or 0)
				local bDistance = (b.Position - root.Position).Magnitude + (math.abs(b.Position.Y - root.Position.Y) > 12 and 500 or 0)
				if aDistance ~= bDistance then return aDistance < bDistance end
			end
			return (a:GetAttribute("FailureSince") or 0) < (b:GetAttribute("FailureSince") or 0)
		end)
		local target = failed[1]
		if not target then
			local text = "All equipment is working. Repair score increases with failure time; assigned jobs also pay for travel distance."
			player:SetAttribute("LabObjective", text)
			return text
		end
		player:SetAttribute("AssignedRepairId", equipmentId(target))
		local distance, routeReady = createRepairPath(player, target)
		player:SetAttribute("AssignedRepairDistance", distance)
		local projected = select(1, repairReward(player, target, true))
		player:SetAttribute("AssignedRepairProjectedPoints", projected)
		local routeInstruction = routeReady and "Follow RED floor lights" or "Use the NORTH STAIR; route is recalculating"
		local text = string.format("REPAIR JOB: %s • %s. %s. HOLD R. About +%d points (%d studs; score grows while failed).",
			equipmentFloorLabel(target), equipmentLabel(target), routeInstruction, projected, math.floor(distance + 0.5))
		player:SetAttribute("LabObjective", text)
		return text
	elseif role == "Laboratory Technician" then
		local sources = {}
		for _, chamber in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
			if chamber.Parent and chamber:GetAttribute("FunctionalState") == "FAILED"
				and (chamber:GetAttribute("SampleCount") or 0) > 0
				and not chamber:GetAttribute("ReservedByBot") then
				local destination = evacuationDestinations(chamber)[1]
				if destination then table.insert(sources, {source = chamber, destination = destination}) end
			end
		end
		table.sort(sources, function(a, b)
			local an = tonumber((a.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
			local bn = tonumber((b.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
			return an < bn
		end)
		local job = sources[1]
		if not job then
			local text = "Laboratory Technician: waiting for a failed chamber with plants. Emergency moves pay +12; assigned on-time moves pay +30."
			player:SetAttribute("LabObjective", text)
			return text
		end
		local sourceCode = job.source:GetAttribute("GrowthCode") or "R?"
		local destinationCode = job.destination:GetAttribute("GrowthCode") or "R?"
		local allowedSeconds = adaptiveTransferSeconds(job.source, job.destination)
		local deadline = os.time() + allowedSeconds
		player:SetAttribute("AssignedTransferSource", sourceCode)
		player:SetAttribute("AssignedTransferDestination", destinationCode)
		player:SetAttribute("AssignedTransferDeadline", deadline)
		-- Same red floor-marker route the Technician role gets to a failed
		-- unit, but pointed at the destination chamber the plant must be
		-- carried to -- so "where does this go" is never a guess.
		local routeReady = select(2, createRepairPath(player, job.destination))
		local routeInstruction = routeReady and "Follow RED floor lights to the destination chamber" or "Route recalculating"
		local text = string.format("ASSIGNED +%d: %s • %s → %s • %s. Press E to take a plant. %s. Deliver in %d sec.",
			POINTS.MOVE_ASSIGNED_ON_TIME, equipmentFloorLabel(job.source), sourceCode, destinationCode,
			equipmentFloorLabel(job.destination), routeInstruction, allowedSeconds)
		player:SetAttribute("LabObjective", text)
		return text
	end
	local text = "Choose BLUE Technician or GREEN Laboratory Technician at a role kiosk."
	player:SetAttribute("LabObjective", text)
	return text
end

local function chamberByCode(code)
	for _, chamber in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
		if chamber:GetAttribute("GrowthCode") == code then return chamber end
	end
end

local function takePlantFromChamber(player, chamber, setReadout)
	local code = chamber:GetAttribute("GrowthCode") or equipmentLabel(chamber)
	if playerRole(player) ~= "Laboratory Technician" then
		setReadout("LAB ROLE REQUIRED", "GREEN kiosk • Laboratory Technician moves plants", Color3.fromRGB(255, 175, 80))
		notify(player, "Only a Laboratory Technician can take plants. Choose the GREEN role; Technicians repair with R.")
		return
	end
	local samples = chamberSampleList(chamber)
	if #samples == 0 then setReadout(code .. "  EMPTY", "No germinated samples available", Color3.fromRGB(255, 200, 90)); return end
	local failed = chamber:GetAttribute("FunctionalState") == "FAILED"
	local destination
	if failed then
		local assignedSource = player:GetAttribute("AssignedTransferSource")
		local assignedDestination = player:GetAttribute("AssignedTransferDestination")
		if assignedSource == code and assignedDestination then
			local requested = chamberByCode(assignedDestination)
			if requested and requested:GetAttribute("FunctionalState") ~= "FAILED"
				and (requested:GetAttribute("SampleCount") or 0) + (requested:GetAttribute("IncomingReservations") or 0)
					< (requested:GetAttribute("Capacity") or 10) then
				destination = requested
			end
		end
		destination = destination or evacuationDestinations(chamber)[1]
		if not destination then
			setReadout(code .. "  FAILED", "No working chamber has free capacity", Color3.fromRGB(255, 105, 90))
			notify(player, "No safe destination currently has room. The adaptive controller will reduce failures and free capacity.")
			return
		end
		-- Refresh the floor-marker route to whichever chamber this specific
		-- plant actually ends up assigned to (may differ from the original
		-- job destination if that one filled up in the meantime).
		createRepairPath(player, destination)
	end
	local plantId = samples[1]
	local stage = chamber:GetAttribute("GrowthStage") or 0
	local destinationCode = destination and destination:GetAttribute("GrowthCode") or ""
	local plantLife = chamber:GetAttribute("PlantLife") or 100
	if failed then
		plantLife = math.clamp(100 - math.floor(math.max(0, os.time() - (chamber:GetAttribute("FailureSince") or os.time()) - 120) / 6), 0, 100)
	end
	setReadout("TAKING SAMPLE", "Removing " .. plantId .. " from " .. code, Color3.fromRGB(120, 235, 170))
	local function canFinishTaking()
		return chamber.Parent ~= nil and playerRole(player) == "Laboratory Technician"
			and canInteract(player, chamber, 10) and not findPlantSample(player)
			and chamber:GetAttribute("FunctionalState") ~= "DESTROYED"
			and chamberSampleList(chamber)[1] == plantId
			and (not destination or (destination.Parent ~= nil and destination:GetAttribute("FunctionalState") == "WORKING"
				and (destination:GetAttribute("SampleCount") or 0) + (destination:GetAttribute("IncomingReservations") or 0)
					< (destination:GetAttribute("Capacity") or 10)))
	end
	if not runMathQuiz(player, "TAKE PLANT " .. plantId, chamber, canFinishTaking) then return end
	-- Re-read inventory after the popup; do not overwrite another transfer.
	samples = chamberSampleList(chamber)
	plantLife = math.clamp(chamber:GetAttribute("PlantLife") or 100, 0, 100)
	table.remove(samples, 1)
	local sample = makeTool(player, "Plant Sample " .. plantId, {
		itemType = failed and "Emergency Plant Transfer" or "Plant Sample",
		sample = true, plant = true, label = plantId, colour = Color3.fromRGB(133, 92, 55),
		attributes = {
			PlantSample = true, SampleId = plantId, PlantId = plantId, HomeGrowthCode = code, SourceGrowthCode = code,
			GrowthStage = stage, Treatments = chamber:GetAttribute("Treatments") or "",
			Genome = chamber:GetAttribute("Genome") or "Wild Type", Moisture = chamber:GetAttribute("Moisture") or 50,
			PlantLife = plantLife,
			GerminationDate = chamber:GetAttribute("GerminationDate") or "unknown",
			EvacuationSample = failed, DestinationGrowthCode = destinationCode, TransferStartedAt = os.time(),
		},
	})
	if not sample then table.insert(samples, 1, plantId); return end
	saveChamberSamples(chamber, samples)
	updateStoredSamples(chamber)
	refreshChamberTelemetry(chamber)
	refreshPlantVisual(sample)
	setCarryState(player, sample)
	task.spawn(function()
		while sample.Parent and (sample:GetAttribute("PlantLife") or 0) > 0 do
			task.wait(1)
			if not sample.Parent then return end
			if not sample:GetAttribute("QuizProtected") then
				local carriedFor = os.time() - (sample:GetAttribute("TransferStartedAt") or os.time())
				local life = math.max(0, (sample:GetAttribute("PlantLife") or 0) - (carriedFor > 180 and 0.2 or 0))
				sample:SetAttribute("PlantLife", life)
				refreshPlantVisual(sample)
				if life <= 0 then
					local reservedCode = sample:GetAttribute("DestinationGrowthCode") or ""
					local reserved = reservedCode ~= "" and chamberByCode(reservedCode) or nil
					if reserved then reserved:SetAttribute("IncomingReservations", math.max(0, (reserved:GetAttribute("IncomingReservations") or 1) - 1)) end
					player:SetAttribute("CarriedSample", "")
					player:SetAttribute("LabObjective", plantId .. " reached 0% LIFE and disappeared. Take another plant.")
					task.wait(0.5)
					if sample.Parent then sample:Destroy() end
					return
				end
			end
		end
	end)
	if destination then
		destination:SetAttribute("IncomingReservations", (destination:GetAttribute("IncomingReservations") or 0) + 1)
		-- Begin the bonus clock after pickup, excluding the time spent on the quiz.
		player:SetAttribute("AssignedTransferSource", code)
		player:SetAttribute("AssignedTransferDestination", destinationCode)
		player:SetAttribute("AssignedTransferDeadline", os.time() + adaptiveTransferSeconds(chamber, destination))
		local deadline = player:GetAttribute("AssignedTransferDeadline") or 0
		local seconds = math.max(0, deadline - os.time())
		player:SetAttribute("LabObjective", string.format("CARRYING %s: press E at ANY GREEN RUNNING cabinet with a FREE SLOT. BONUS target %s has %d sec left for +%d points.",
			plantId, destinationCode, seconds, POINTS.MOVE_ASSIGNED_ON_TIME))
		setReadout(code .. "  FAILED", plantId .. " removed • SEND TO " .. destinationCode, Color3.fromRGB(255, 145, 75))
		notify(player, "ALARM: " .. code .. " failed (" .. (chamber:GetAttribute("FailureReason") or "fault") .. "). Move " .. plantId .. " to " .. destinationCode .. ".")
	else
		player:SetAttribute("LabObjective", "Treat " .. plantId .. ", then press E at any GREEN RUNNING cabinet with a FREE SLOT.")
		setReadout(code .. "  WORKING", plantId .. " taken • " .. #samples .. "/" .. (chamber:GetAttribute("Capacity") or 0) .. " remain", Color3.fromRGB(115, 220, 160))
		notify(player, plantId .. " equipped in your hand. Process it or move it to a working chamber.")
	end
end

local function storePlantInChamber(player, chamber, plant, setReadout)
	local code = chamber:GetAttribute("GrowthCode") or equipmentLabel(chamber)
	if playerRole(player) ~= "Laboratory Technician" then
		setReadout("LAB ROLE REQUIRED", "GREEN kiosk • Laboratory Technician stores plants", Color3.fromRGB(255, 175, 80))
		notify(player, "Only a Laboratory Technician can complete plant transfers.")
		return
	end
	if chamber:GetAttribute("FunctionalState") == "FAILED" then
		setReadout(code .. "  FAILED", "Cannot drop here • find any GREEN RUNNING cabinet", Color3.fromRGB(255, 105, 90))
		notify(player, code .. " is failed. Carry the plant to any GREEN RUNNING cabinet with a FREE SLOT and press E.")
		return
	end
	local samples = chamberSampleList(chamber)
	local capacity = chamber:GetAttribute("Capacity") or 10
	if #samples >= capacity then
		setReadout(code .. "  FULL", capacity .. "/" .. capacity .. " samples • choose another working chamber", Color3.fromRGB(255, 175, 75))
		return
	end
	local wanted = plant:GetAttribute("DestinationGrowthCode") or ""
	local plantId = plant:GetAttribute("PlantId") or plant.Name
	local plantLife = math.clamp(plant:GetAttribute("PlantLife") or 100, 0, 100)
	local sourceCode = plant:GetAttribute("SourceGrowthCode") or plant:GetAttribute("HomeGrowthCode") or ""
	local assignedMove = wanted ~= "" and player:GetAttribute("AssignedTransferSource") == sourceCode
		and player:GetAttribute("AssignedTransferDestination") == code
	local assignedOnTime = assignedMove and os.time() <= (player:GetAttribute("AssignedTransferDeadline") or 0)
	setReadout("STORING SAMPLE", "Placing " .. plantId .. " into " .. code, Color3.fromRGB(120, 235, 170))
	-- Only repair and pickup use a quiz; delivery remains immediate.
	if not plant.Parent or not canInteract(player, chamber, 10) then return end
	table.insert(samples, plantId)
	saveChamberSamples(chamber, samples)
	local stage = math.clamp(plant:GetAttribute("GrowthStage") or 0, 0, 5)
	chamber:SetAttribute("GrowthStage", math.max(chamber:GetAttribute("GrowthStage") or 0, stage))
	chamber:SetAttribute("Treatments", plant:GetAttribute("Treatments") or "")
	chamber:SetAttribute("Genome", plant:GetAttribute("Genome") or "Wild Type")
	chamber:SetAttribute("Moisture", plant:GetAttribute("Moisture") or chamber:GetAttribute("Moisture") or 50)
	local recoverySeconds = recoverPlantLife(chamber, plantLife, player, plantId)
	if wanted ~= "" then
		local reservedDestination = chamberByCode(wanted)
		if reservedDestination then
			reservedDestination:SetAttribute("IncomingReservations", math.max(0, (reservedDestination:GetAttribute("IncomingReservations") or 1) - 1))
		end
		emergencyMovesCompleted = emergencyMovesCompleted + 1
		player:SetAttribute("EmergencyTransfers", (player:GetAttribute("EmergencyTransfers") or 0) + 1)
	end
	updateStoredSamples(chamber)
	refreshChamberTelemetry(chamber)
	destroyCarriedItem(player, plant)
	local points = 0
	local reason = "plant stored"
	if wanted ~= "" then
		GameState.transfersCompleted = GameState.transfersCompleted + 1
		if assignedMove then
			GameState.assignedTransfersCompleted = GameState.assignedTransfersCompleted + 1
			points = assignedOnTime and POINTS.MOVE_ASSIGNED_ON_TIME or POINTS.MOVE_ASSIGNED_LATE
			reason = assignedOnTime and ("assigned on-time move " .. sourceCode .. " → " .. code)
				or ("assigned late move " .. sourceCode .. " → " .. code)
		else
			points = POINTS.MOVE_ANY
			reason = "emergency plant move " .. sourceCode .. " → " .. code
		end
	end
	setReadout(code .. "  STORED" .. (points > 0 and ("  +" .. points) or ""),
		plantId .. " • " .. #samples .. "/" .. capacity .. " samples", Color3.fromRGB(115, 245, 150))
	if points > 0 then
		awardPoints(player, points, reason)
		if recoverySeconds > 0 then
			task.delay(recoverySeconds, function() if player.Parent then assignNextTask(player) end end)
		else
			assignNextTask(player)
		end
	else
		notify(player, plantId .. " safely stored in " .. code .. ". Capacity: " .. #samples .. "/" .. capacity .. ".")
	end
end

local function handleGrowthChamber(player, chamber, setReadout)
	local code = chamber:GetAttribute("GrowthCode") or equipmentLabel(chamber)
	local reservedBy = chamber:GetAttribute("ReservedByBot")
	if reservedBy then
		-- Human players always have priority over test bots. Clearing the
		-- reservation makes one press of E immediately take or drop a plant.
		chamber:SetAttribute("ReservedByBot", nil)
	end
	local plant = findPlantSample(player)
	if plant then storePlantInChamber(player, chamber, plant, setReadout)
	elseif (chamber:GetAttribute("SampleCount") or 0) > 0 then takePlantFromChamber(player, chamber, setReadout)
	else
		setReadout(code .. "  EMPTY", "Working chamber can receive a carried sample", Color3.fromRGB(255, 200, 90))
	end
end

local GMO_TRAITS = {"Drought Resistant", "High Yield", "Salt Tolerant", "Fast Flowering", "Disease Resistant"}

-- Dose-response germination-viability curve, bucketed off the reference
-- Viola cornuta gamma-irradiation study (Trends Sci. 2025;22(1):8705): mild
-- doses barely dent germination, but survival collapses above ~600 Gy and is
-- nearly gone by 1000 Gy. Each visit rolls a dose and a survival check.
local MUTAGENESIS_DOSES = {
	{gy = 100,  survivalMin = 85, survivalMax = 95},
	{gy = 200,  survivalMin = 65, survivalMax = 85},
	{gy = 400,  survivalMin = 45, survivalMax = 70},
	{gy = 600,  survivalMin = 15, survivalMax = 40},
	{gy = 800,  survivalMin = 5,  survivalMax = 20},
	{gy = 1000, survivalMin = 0,  survivalMax = 8},
}

-- Auxin pushes rooting, cytokinin pushes shoot/bud growth, and a balanced
-- ratio pushes both -- the direction of effect reported for lemon seed
-- germination hormone trials, kept as a labeled tag rather than a hidden stat.
local HORMONE_TREATMENTS = {
	{name = "Auxin-dominant (IBA-heavy)",      focus = "Root",  gain = 1},
	{name = "Cytokinin-dominant (BAP-heavy)",  focus = "Shoot", gain = 1},
	{name = "Balanced 1:1 auxin:cytokinin",    focus = "Root+Shoot", gain = 2},
}

local function germinationPercent(player)
	local sown = player:GetAttribute("GermSownCount") or 0
	if sown == 0 then return 0 end
	return math.floor(((player:GetAttribute("GermNormalCount") or 0) / sown) * 100 + 0.5)
end

local function processPlant(player, part, spec, process, setReadout)
	if playerRole(player) ~= "Laboratory Technician" then
		setReadout("LAB ROLE REQUIRED", "GREEN kiosk • Laboratory Technician develops plants", Color3.fromRGB(255, 175, 80))
		notify(player, "Only a Laboratory Technician can use plant-development equipment.")
		return false
	end
	local plant = findPlantSample(player)
	if not plant then
		setReadout("PLANT REQUIRED", "Take one from an R-numbered chamber", Color3.fromRGB(255, 150, 85))
		notify(player, part:GetAttribute("Kind") .. ": take a visible plant sample from an R chamber first.")
		return false
	end

	local stage = math.clamp(plant:GetAttribute("GrowthStage") or 0, 0, 5)
	if process.minStage and stage < process.minStage then
		setReadout("STAGE TOO EARLY", "Needs Budding stage or later", Color3.fromRGB(255, 150, 85))
		notify(player, "Grow " .. (plant:GetAttribute("PlantId") or "the plant") .. " to Budding before pollination.")
		return false
	end
	if process.key and not process.repeatable and hasTreatment(plant, process.key) then
		setReadout("ALREADY APPLIED", process.key .. " is already recorded", Color3.fromRGB(255, 180, 85))
		notify(player, process.key .. " has already been applied to this plant. Use another machine.")
		return false
	end

	runProgress(spec.wait or 1.5, process.caption, setReadout)

	-- Mutagenesis Chamber: roll a dose, then roll survival against that
	-- dose's real-world-modeled band. A killed sample ends here.
	if process.mutagenesis then
		local bucket = MUTAGENESIS_DOSES[math.random(1, #MUTAGENESIS_DOSES)]
		local survivalPercent = math.random(bucket.survivalMin, bucket.survivalMax)
		local survived = math.random(1, 100) <= math.max(survivalPercent, 1)
		plant:SetAttribute("MutagenesisDoseGy", bucket.gy)
		plant:SetAttribute("MutagenesisSurvivalPercent", survivalPercent)
		if not survived then
			local plantId = plant:GetAttribute("PlantId") or "sample"
			setReadout("SAMPLE LOST", string.format("%d Gy dose • %d%% survival odds • did not survive", bucket.gy, survivalPercent),
				Color3.fromRGB(255, 90, 80))
			notify(player, plantId .. " did not survive the " .. bucket.gy .. " Gy dose (" .. survivalPercent .. "% survival odds). Take another plant.")
			destroyCarriedItem(player, plant)
			return true
		end
		addTreatment(plant, "Mutagenesis " .. bucket.gy .. "Gy")
		plant:SetAttribute("Genome", "Mutagenized (" .. bucket.gy .. " Gy)")
	end

	-- Hormone Treatment Bench: roll a hormone mix, tag the resulting focus.
	if process.hormone then
		local mix = HORMONE_TREATMENTS[math.random(1, #HORMONE_TREATMENTS)]
		plant:SetAttribute("HormoneTreatment", mix.name)
		plant:SetAttribute("HormoneFocus", mix.focus)
		process = {key = process.key, gain = mix.gain, moistureGain = process.moistureGain, caption = process.caption}
		addTreatment(plant, "Hormone: " .. mix.name)
	elseif process.key then
		addTreatment(plant, process.key)
	end

	-- Germination Chamber: classify the outcome (AOSA normal / abnormal /
	-- dead), the same three buckets a real seed-testing lab reports, and
	-- track a running germination percentage on the Laboratory Technician.
	-- A prior Decontamination Unit visit (Sterilized treatment) meaningfully
	-- improves the odds, matching real seed-testing guidance that
	-- contamination is the leading cause of an abnormal or dead result.
	if process.key == "Germination" then
		local sterilized = hasTreatment(plant, "Sterilized")
		local irradiated = plant:GetAttribute("MutagenesisSurvivalPercent")
		local normalChance = sterilized and 82 or 60
		if irradiated then normalChance = math.floor(normalChance * (irradiated / 100)) end
		local roll = math.random(1, 100)
		local outcome
		if roll <= normalChance then outcome = "Normal"
		elseif roll <= normalChance + 25 then outcome = "Abnormal"
		else outcome = "Dead" end
		plant:SetAttribute("GerminationOutcome", outcome)
		player:SetAttribute("GermSownCount", (player:GetAttribute("GermSownCount") or 0) + 1)
		if outcome == "Normal" then
			player:SetAttribute("GermNormalCount", (player:GetAttribute("GermNormalCount") or 0) + 1)
		elseif outcome == "Abnormal" then
			player:SetAttribute("GermAbnormalCount", (player:GetAttribute("GermAbnormalCount") or 0) + 1)
			plant:SetAttribute("PlantLife", math.clamp((plant:GetAttribute("PlantLife") or 100) - 25, 10, 100))
		else
			player:SetAttribute("GermDeadCount", (player:GetAttribute("GermDeadCount") or 0) + 1)
			local plantId = plant:GetAttribute("PlantId") or "sample"
			setReadout("DEAD  •  AOSA", string.format("Lab germination rate now %d%%", germinationPercent(player)), Color3.fromRGB(255, 90, 80))
			notify(player, plantId .. " classified DEAD under AOSA rules (" .. (sterilized and "sterilized" or "unsterilized")
				.. " seed). Your running germination rate: " .. germinationPercent(player) .. "%. Take another plant.")
			destroyCarriedItem(player, plant)
			return true
		end
	end

	local newStage = math.clamp(stage + (process.gain or 0), 0, 5)
	plant:SetAttribute("GrowthStage", newStage)
	plant:SetAttribute("Moisture", math.clamp((plant:GetAttribute("Moisture") or 50) + (process.moistureGain or -2), 15, 100))
	if process.genome then plant:SetAttribute("Genome", GMO_TRAITS[math.random(1, #GMO_TRAITS)]) end
	refreshPlantVisual(plant)
	setCarryState(player, plant)
	player:SetAttribute("LabObjective", "Plant " .. (plant:GetAttribute("PlantId") or "sample") .. " is "
		.. (GROWTH_STAGE_NAME[newStage] or "Growing") .. ". Use another treatment or return it to an empty R chamber.")
	if process.key then awardPoints(player, POINTS.PROCESS_PLANT, process.key .. " plant treatment") end

	local data = string.format("%s • %s • %d%% moisture\nGenome: %s",
		plant:GetAttribute("PlantId") or "PLANT", GROWTH_STAGE_NAME[newStage] or "Growing",
		plant:GetAttribute("Moisture") or 50, plant:GetAttribute("Genome") or "Wild Type")
	if plant:GetAttribute("GerminationOutcome") then
		data = data .. string.format("\nAOSA: %s • Lab germination rate %d%%", plant:GetAttribute("GerminationOutcome"), germinationPercent(player))
	end
	if plant:GetAttribute("MutagenesisDoseGy") then
		data = data .. string.format("\nDose %d Gy • %d%% survival odds", plant:GetAttribute("MutagenesisDoseGy"), plant:GetAttribute("MutagenesisSurvivalPercent") or 0)
	end
	if plant:GetAttribute("HormoneTreatment") then
		data = data .. "\n" .. plant:GetAttribute("HormoneTreatment") .. " • " .. (plant:GetAttribute("HormoneFocus") or "")
	end
	setReadout("PLANT DATA", data, Color3.fromRGB(120, 240, 160))
	notify(player, data:gsub("\n", " | ") .. " | Treatments: " .. treatmentText(plant))
	equipTool(player, plant)
	return true
end

local function createTransferSample(player, source, setReadout)
	local existing = findTransferSample(player)
	if existing then
		local target = existing:GetAttribute("DestinationLabel") or "the named cold store"
		setReadout("SAMPLE IN TRANSIT", (existing:GetAttribute("SampleId") or existing.Name) .. " -> " .. target,
			Color3.fromRGB(255, 205, 80))
		notify(player, "You already carry " .. (existing:GetAttribute("SampleId") or existing.Name) .. ". Deliver it to " .. target .. ".")
		equipTool(player, existing)
		return
	end

	local destinations = coldStoresExcept(source)
	if #destinations == 0 then
		setReadout("TRANSFER UNAVAILABLE", "A second refrigerator or freezer is required.", Color3.fromRGB(255, 110, 100))
		notify(player, "This transfer needs at least two refrigerators/freezers in the generated lab.")
		return
	end
	-- Prefer a true refrigerator destination so the guaranteed lobby
	-- pair always supports the requested fridge-to-fridge play loop.
	local refrigeratorDestinations = {}
	for _, candidate in ipairs(destinations) do
		if candidate:GetAttribute("Kind") == "Refrigerator" then
			table.insert(refrigeratorDestinations, candidate)
		end
	end
	if #refrigeratorDestinations > 0 then destinations = refrigeratorDestinations end

	local destination = destinations[math.random(1, #destinations)]
	nextSampleNumber = nextSampleNumber + 1
	local sampleId = string.format("SL-%04d", nextSampleNumber)
	local targetLabel = storageLabel(destination)
	local sample = makeTool(player, "Seed Sample " .. sampleId, {
		itemType = "Transfer Seed Sample",
		sample = true,
		label = sampleId,
		colour = Color3.fromRGB(120, 190, 225),
		attributes = {
			TransferSample = true,
			SampleId = sampleId,
			SourceStorageId = storageId(source),
			DestinationStorageId = storageId(destination),
			DestinationLabel = targetLabel,
		},
	})
	if not sample then return end
	setCarryState(player, sample)
	setReadout("DISPATCHED " .. sampleId, "DEST: " .. targetLabel, Color3.fromRGB(100, 220, 255))
	notify(player, "Picked up " .. sampleId .. ". Carry it visibly to " .. targetLabel .. ".")
end

local function handleColdStore(player, part, setReadout)
	local sample = findTransferSample(player)
	if not sample then
		createTransferSample(player, part, setReadout)
		return
	end

	local sampleId = sample:GetAttribute("SampleId") or sample.Name
	local wanted = sample:GetAttribute("DestinationStorageId")
	if wanted ~= storageId(part) then
		local destination = sample:GetAttribute("DestinationLabel") or "the assigned cold store"
		setReadout("WRONG STORAGE", sampleId .. " -> " .. destination, Color3.fromRGB(255, 120, 95))
		notify(player, sampleId .. " belongs in " .. destination .. ". It remains in your hand.")
		equipTool(player, sample)
		return
	end

	destroyCarriedItem(player, sample)
	GameState.transfersCompleted = GameState.transfersCompleted + 1
	addContribution(player)
	updateScoreboard()
	setReadout("RECEIVED " .. sampleId, "TRANSFER VERIFIED  |  +1 contribution", Color3.fromRGB(115, 245, 150))
	notify(player, sampleId .. " delivered and verified. Transfer complete.")
end

local function startCycleIndicator(part)
	local auto = part:GetAttribute("Auto")
	if not auto then return nil, function() end end
	local indicator = Instance.new("Part")
	indicator.Name = "CycleIndicator"
	indicator.Size = (auto == "spin") and Vector3.new(0.9, 0.15, 0.9) or Vector3.new(0.5, 0.5, 0.5)
	indicator.Shape = (auto == "spin") and Enum.PartType.Block or Enum.PartType.Ball
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CanTouch = false
	indicator.CastShadow = false
	indicator.Material = Enum.Material.Neon
	indicator.Color = Color3.fromRGB(255, 196, 60)
	indicator.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 0.8, 0))
	indicator.Parent = part.Parent
	local light = Instance.new("PointLight")
	light.Color = indicator.Color
	light.Brightness = 1.5
	light.Range = 12
	light.Parent = indicator

	local running = true
	task.spawn(function()
		local t = 0
		while running and indicator.Parent do
			t = t + task.wait(0.1)
			if auto == "spin" then
				indicator.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 0.8, 0))
					* CFrame.Angles(0, t * 5, 0)
			else
				indicator.Transparency = 0.15 + (math.sin(t * 7) + 1) / 2 * 0.55
			end
		end
	end)
	return indicator, function()
		running = false
		if indicator.Parent then indicator:Destroy() end
	end
end

local function bind(part)
	local kind = part:GetAttribute("Kind")
	if not kind or part:GetAttribute("InteractionsBound") then return end
	local isPlantContainer = (part:GetAttribute("Capacity") or 0) > 0
	part:SetAttribute("InteractionsBound", true)
	part:SetAttribute("EquipmentId", equipmentId(part))
	part:SetAttribute("FloorLabel", equipmentFloorLabel(part))
	part:SetAttribute("RepairKey", "R")
	if part:GetAttribute("FunctionalState") == nil then
		local hash = 0
		for i = 1, #equipmentId(part) do hash = hash + string.byte(equipmentId(part), i) end
		local failed = false
		part:SetAttribute("FunctionalState", failed and "FAILED" or "WORKING")
		part:SetAttribute("FailureReason", failed and "Control-system diagnostic fault" or "")
		part:SetAttribute("FailureSince", failed and os.time() or 0)
	end
	if part:GetAttribute("OperationStarted") == nil then part:SetAttribute("OperationStarted", os.time()) end
	if COLD_STORE[kind] then storageId(part) end
	if isPlantContainer then
		updateStoredSamples(part)
		refreshChamberTelemetry(part)
	end
	local spec = Kinds.forKind(kind)
	local prompt, setReadout, pressButton = makeControls(part, kind, spec)
	-- Cabinet trim can occlude Roblox's prompt ray to its own push button.
	-- The server still enforces distance and wall line-of-sight via canInteract.
	prompt.RequiresLineOfSight = false
	local baseColour = part.Color
	local busy = false
	local powerOn = true
	part:SetAttribute("Powered", true)
	local powerLight = Instance.new("PointLight")
	powerLight.Color = Color3.fromRGB(120, 220, 140)
	powerLight.Brightness = powerOn and 2 or 0
	powerLight.Range = 7
	powerLight.Parent = part

	local led = Instance.new("Part")
	led.Name = "StatusLED"
	led.Shape = Enum.PartType.Ball
	led.Size = Vector3.new(0.22, 0.22, 0.22)
	led.Anchored = true
	led.CanCollide = false
	led.CanTouch = false
	led.CastShadow = false
	led.Material = Enum.Material.Neon
	led.Color = powerOn and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(64, 68, 74)
	local controlSide = part:GetAttribute("WallSide")
	if controlSide == "W" or controlSide == "E" then
		local direction = controlSide == "W" and 1 or -1
		led.CFrame = part.CFrame * CFrame.new(direction * (part.Size.X / 2 + 0.08), part.Size.Y / 2 - 0.3, part.Size.Z * 0.32)
	else
		local direction = controlSide == "S" and -1 or 1
		led.CFrame = part.CFrame * CFrame.new(part.Size.X * 0.32, part.Size.Y / 2 - 0.3, direction * (part.Size.Z / 2 + 0.08))
	end
	led.Parent = part

	local repairAnchor = part:FindFirstChild("ControllerScreen") or led
	local floorLabel = equipmentFloorLabel(part)
	local unitLabel = equipmentLabel(part)
	local repairPrompt = Instance.new("ProximityPrompt")
	repairPrompt.Name = "RepairPrompt"
	repairPrompt.ObjectText = floorLabel .. " • " .. unitLabel
	repairPrompt.ActionText = "Hold R to repair"
	repairPrompt.KeyboardKeyCode = Enum.KeyCode.R
	repairPrompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	repairPrompt.HoldDuration = 3
	repairPrompt.MaxActivationDistance = 8
	repairPrompt.RequiresLineOfSight = false
	repairPrompt.Enabled = part:GetAttribute("FunctionalState") == "FAILED"
	repairPrompt.Parent = repairAnchor

	part:GetAttributeChangedSignal("FunctionalState"):Connect(function()
		if repairPrompt.Parent then
			repairPrompt.Enabled = not busy and part:GetAttribute("FunctionalState") == "FAILED"
		end
	end)

	repairPrompt.Triggered:Connect(function(player)
		if playerRole(player) ~= "Technician" then
			setReadout("TECHNICIAN REQUIRED", "Choose the BLUE role to repair equipment", Color3.fromRGB(255, 175, 80))
			notify(player, "Only a Technician can repair equipment. Choose the BLUE role kiosk.")
			return
		end
		if busy or part:GetAttribute("FunctionalState") ~= "FAILED"
			or not canInteract(player, part, repairPrompt.MaxActivationDistance) then return end
		busy = true
		prompt.Enabled = false
		repairPrompt.Enabled = false
		setReadout("REPAIRING", floorLabel .. " • " .. unitLabel .. " • diagnosing "
			.. (part:GetAttribute("FailureReason") or "equipment fault"), Color3.fromRGB(255, 205, 75))
		setReadout("REPAIRING", "Working on " .. floorLabel .. " • " .. unitLabel, Color3.fromRGB(120, 235, 170))
		local function canFinishRepair()
			return part.Parent ~= nil and playerRole(player) == "Technician"
				and part:GetAttribute("FunctionalState") == "FAILED"
				and canInteract(player, part, repairPrompt.MaxActivationDistance)
		end
		if not runMathQuiz(player, "REPAIR " .. unitLabel, part, canFinishRepair) then
			setReadout("REPAIR NOT COMPLETED", "Hold R for 3 seconds to try another quiz", Color3.fromRGB(255, 105, 90))
			prompt.Enabled = true
			repairPrompt.Enabled = part:GetAttribute("FunctionalState") == "FAILED"
			busy = false
			return
		end
		local assigned = player:GetAttribute("AssignedRepairId") == equipmentId(part)
		local points, failedSeconds, routeDistance = repairReward(player, part, assigned)
		part:SetAttribute("LastRepairedAt", os.time())
		part:SetAttribute("LastRepairedBy", player.Name)
		if kind == PLANT_CHAMBER_KIND then setChamberFailure(part, false) else setGenericFailure(part, false) end
		GameState.repairsCompleted = GameState.repairsCompleted + 1
		if assigned then GameState.assignedRepairsCompleted = GameState.assignedRepairsCompleted + 1 end
		local total = awardPoints(player, points, string.format("%s%s • failed %ds • route %d studs",
			assigned and "assigned repair: " or "equipment repair: ", unitLabel, failedSeconds, math.floor(routeDistance + 0.5)))
		setReadout("REPAIR COMPLETE  +" .. points, floorLabel .. " • " .. unitLabel .. " WORKING • TOTAL " .. total,
			Color3.fromRGB(105, 245, 155))
		assignNextTask(player)
		prompt.Enabled = true
		busy = false
	end)

	prompt.Triggered:Connect(function(player)
		if busy or not canInteract(player, part, prompt.MaxActivationDistance) then return end
		task.spawn(pressButton)
		if not isPlantContainer and part:GetAttribute("FunctionalState") == "FAILED" then
			setReadout("FAILED • HOLD R", equipmentFloorLabel(part) .. " • " .. (part:GetAttribute("FailureReason") or "equipment fault"),
				Color3.fromRGB(255, 105, 90))
			notify(player, kind .. " is FAILED. A Technician must HOLD R to repair it.")
			return
		end

		local station = ROLE_STATIONS[kind]
		if station then
			if not player.Team or player.Team.Name ~= station.role then
				setReadout("ACCESS DENIED", station.role .. " role required", Color3.fromRGB(255, 105, 90))
				notify(player, kind .. ": only a " .. station.role .. " can use this. Join that role at the entrance kiosk.")
				return
			end
			busy = true
			prompt.Enabled = false
			runProgress(spec.wait or 1, "Reading shared batch queue", setReadout)
			local msg, err = station.run(GameState)
			if err then
				setReadout("NO BATCH DATA", err, Color3.fromRGB(255, 160, 90))
				notify(player, kind .. ": " .. err)
			else
				addContribution(player)
				setReadout("INSPECTION DATA", msg, Color3.fromRGB(115, 245, 150))
				notify(player, kind .. " -- " .. msg)
				updateScoreboard()
			end
			prompt.Enabled = true
			busy = false
			return
		end

		local plantProcess = PLANT_PROCESS[kind]
		local carriedPlant = findPlantSample(player)
		local shouldUsePlantStorage = isPlantContainer and (
			kind == PLANT_CHAMBER_KIND
			or not plantProcess
			or not carriedPlant
			or (carriedPlant:GetAttribute("PlantLife") or 100) < 100
		)
		if shouldUsePlantStorage then
			busy = true
			prompt.Enabled = false
			handleGrowthChamber(player, part, setReadout)
			prompt.Enabled = true
			busy = false
			return
		end

		if part:GetAttribute("FunctionalState") == "FAILED" then
			setReadout("FAILED • HOLD R", equipmentFloorLabel(part) .. " • " .. (part:GetAttribute("FailureReason") or "equipment fault"),
				Color3.fromRGB(255, 105, 90))
			notify(player, kind .. " is FAILED. A Technician must HOLD R to repair it.")
			return
		end

		if plantProcess then
			busy = true
			prompt.Enabled = false
			processPlant(player, part, spec, plantProcess, setReadout)
			prompt.Enabled = true
			busy = false
			return
		end

		if COLD_STORE[kind] then
			busy = true
			prompt.Enabled = false
			runProgress(0.6, "Scanning cold-store inventory", setReadout)
			handleColdStore(player, part, setReadout)
			prompt.Enabled = true
			busy = false
			return
		end

		local consumed
		if spec.consumes then
			consumed = findTool(player, spec.consumes)
			if not consumed then
				setReadout("MATERIAL NEEDED", spec.consumes, Color3.fromRGB(255, 160, 90))
				notify(player, kind .. ": needs " .. spec.consumes .. " first.")
				return
			end
		end

		busy = true
		prompt.Enabled = false
		if spec.activeColour then part.Color = spec.activeColour end
		local uv
		if spec.uvLight then
			uv = Instance.new("PointLight")
			uv.Color = Color3.fromRGB(150, 210, 255)
			uv.Brightness = 2
			uv.Range = 26
			uv.Parent = part
		end

		local _, stopIndicator = startCycleIndicator(part)
		runProgress(spec.wait or 1, spec.action, setReadout)
		stopIndicator()

		if consumed then destroyCarriedItem(player, consumed) end
		for _, item in ipairs(spec.produces or {}) do
			local made = makeTool(player, item)
			if made and made:GetAttribute("LabSample") then setCarryState(player, made) end
		end
		local result = spec.log and spec.log() or "Inspection complete; equipment left ready."
		setReadout("INSPECTION DATA", result, Color3.fromRGB(115, 245, 150))
		notify(player, kind .. " -- " .. result)

		if uv then uv:Destroy() end
		part.Color = baseColour
		prompt.Enabled = true
		busy = false
	end)
end

--------------------------------------------------------------------
-- FIFTY AUTONOMOUS GAMEPLAY TEST WORKERS
--------------------------------------------------------------------
local function setBotStatus(bot, message)
	bot:SetAttribute("TaskState", message)
	local status = bot:FindFirstChild("Status", true)
	if status and status:IsA("TextLabel") then
		status.Text = (bot:GetAttribute("DisplayName") or bot.Name) .. "\n" .. message
	end
end

local function updateBotTestBoard()
	local workers = CollectionService:GetTagged("LabWorkerBot")
	local cycles, carrying, fallbacks, rivalScore = 0, 0, 0, 0
	for _, bot in ipairs(workers) do
		cycles = cycles + (bot:GetAttribute("CompletedCycles") or 0)
		fallbacks = fallbacks + (bot:GetAttribute("PathFallbacks") or 0)
		if (bot:GetAttribute("CarryingPlant") or "") ~= "" then carrying = carrying + 1 end
		if bot:GetAttribute("Competitor") then rivalScore = bot:GetAttribute("Score") or 0 end
	end
	local chambers = CollectionService:GetTagged("PlantGrowthChamber")
	local failing, failedSamples = 0, 0
	for _, chamber in ipairs(chambers) do
		if chamber:GetAttribute("FunctionalState") == "FAILED" then
			failing = failing + 1
			failedSamples = failedSamples + (chamber:GetAttribute("SampleCount") or 0)
		end
	end
	for _, board in ipairs(CollectionService:GetTagged("BotTestBoard")) do
		for _, label in ipairs(board:GetDescendants()) do
			if label:IsA("TextLabel") and label.Name == "BotTestStatus" then
				label.Text = string.format(
					"ADAPTIVE GROWTH-ROOM TEST\nWorkers: %d/50  Transfers: %d  Carrying: %d\nFAILED: %d/%d (%.0f%%)  Samples waiting: %d\nRIVAL SCORE: %d  •  Path fallbacks: %d",
					#workers, cycles, carrying, failing, #chambers, failing / math.max(1, #chambers) * 100, failedSamples, rivalScore, fallbacks)
			end
		end
	end
end

local function interactionPoint(part)
	local side = part:GetAttribute("WallSide")
	local bottomY = part.Position.Y - part.Size.Y / 2
	local point = Vector3.new(part.Position.X, bottomY + 3.25, part.Position.Z)
	if side == "W" then point = point + Vector3.new(part.Size.X / 2 + 2.5, 0, 0)
	elseif side == "E" then point = point - Vector3.new(part.Size.X / 2 + 2.5, 0, 0)
	elseif side == "N" then point = point + Vector3.new(0, 0, part.Size.Z / 2 + 2.5)
	elseif side == "S" then point = point - Vector3.new(0, 0, part.Size.Z / 2 + 2.5)
	else point = point + Vector3.new(0, 0, part.Size.Z / 2 + 2.5) end
	return point
end

--------------------------------------------------------------------
-- OBSERVER GATE
-- A worker only runs its scenario while a player is in the room with it.
-- Everything else stands still. This is what keeps 180 NPCs off the
-- pathfinding budget: an unobserved bot costs one cheap check a second
-- instead of a continuous walk loop and a PathfindingService computation
-- every few seconds.
--------------------------------------------------------------------
local FLOOR_BAND  = 10   -- studs, about half a floor-to-floor height
local WAKE_RADIUS = 35   -- studs, fallback for corridors and doorways, where
                         -- neither the bot nor the player is inside any room

-- Room rectangles published by the generator as one packed attribute:
-- "Level_1:Room 1:x1:z1:x2:z2:y;..." already in stud space.
local roomsByLevel = {}
do
	local complex = workspace:FindFirstChild("Laboratory_Complex")
	local packed = complex and complex:GetAttribute("RoomIndex")
	if typeof(packed) == "string" then
		for entry in packed:gmatch("[^;]+") do
			local level, name, x1, z1, x2, z2, y =
				entry:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")
			if level then
				roomsByLevel[level] = roomsByLevel[level] or {}
				table.insert(roomsByLevel[level], {
					name = name, x1 = tonumber(x1), z1 = tonumber(z1),
					x2 = tonumber(x2), z2 = tonumber(z2), y = tonumber(y),
				})
			end
		end
	end
end

-- Only the ~10 rooms on the bot's own floor are ever tested, not all 81.
local function roomAt(levelName, position)
	local list = levelName and roomsByLevel[levelName]
	if not list then return nil end
	for _, r in ipairs(list) do
		if math.abs(position.Y - r.y) < FLOOR_BAND
			and position.X >= r.x1 and position.X <= r.x2
			and position.Z >= r.z1 and position.Z <= r.z2 then
			return r.name
		end
	end
	return nil
end

-- The rectangle itself, for picking a patrol point inside a room.
local function roomRect(levelName, roomName)
	for _, r in ipairs((levelName and roomsByLevel[levelName]) or {}) do
		if r.name == roomName then return r end
	end
	return nil
end

local function botHasObserver(bot)
	local ok, pivot = pcall(function() return bot:GetPivot().Position end)
	if not ok then return false end
	local levelName = bot:GetAttribute("Level")
	local botRoom = roomAt(levelName, pivot)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local here = hrp.Position
			-- Cheapest test first: wrong floor is an instant no.
			if math.abs(here.Y - pivot.Y) < FLOOR_BAND then
				if botRoom and roomAt(levelName, here) == botRoom then return true end
				local dx, dz = here.X - pivot.X, here.Z - pivot.Z
				if dx * dx + dz * dz < WAKE_RADIUS * WAKE_RADIUS then return true end
			end
		end
	end
	return false
end

local function botMotionChecks(bot)
	local excluded = {bot}
	local corpses = workspace:FindFirstChild("LabBotBodies")
	if corpses then table.insert(excluded, corpses) end
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Exclude
	cast.FilterDescendantsInstances = excluded
	cast.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = excluded
	overlap.RespectCanCollide = true
	overlap.MaxParts = 1
	-- Square horizontal footprint encloses the arms at any yaw. The small
	-- floor clearance avoids treating a floor seam as a wall.
	local size = Vector3.new(3.4, 5.4, 3.4)
	local function clear(from, to)
		local delta = to - from
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if hrp and humanoid and humanoid.Health > 0 and math.abs(hrp.Position.Y - from.Y) < 5 then
				local flatDelta = Vector3.new(delta.X, 0, delta.Z)
				local relative = Vector3.new(hrp.Position.X - from.X, 0, hrp.Position.Z - from.Z)
				local alpha = flatDelta.Magnitude > 0.01 and math.clamp(relative:Dot(flatDelta) / flatDelta:Dot(flatDelta), 0, 1) or 0
				local movingAway = relative.Magnitude < 3.4 and alpha < 0.001
					and (relative - flatDelta).Magnitude > relative.Magnitude + 0.01
				if (relative - flatDelta * alpha).Magnitude < 3.4 and not movingAway then
					return false, hrp.Position
				end
			end
		end
		local offset = Vector3.new(0, -0.2, 0)
		if delta.Magnitude > 0.01 then
			local hit = workspace:Blockcast(CFrame.new(from + offset), size, delta, cast)
			if hit then return false, hit.Instance.Position end
		end
		-- Blockcast does not cover pre-existing overlaps; test the destination
		-- too, so a door closing or another worker arriving cannot be skipped.
		local occupied = workspace:GetPartBoundsInBox(CFrame.new(to + offset), size, overlap)
		if occupied[1] then return false, occupied[1].Position end
		return true
	end
	local function grounded(point, currentY)
		local floor = workspace:Raycast(Vector3.new(point.X, currentY + 1, point.Z), Vector3.new(0, -7, 0), cast)
		if not floor or floor.Normal.Y < 0.65 then return nil end
		local y = floor.Position.Y + 3.25
		if math.abs(y - currentY) > 1.25 then return nil end
		return Vector3.new(point.X, y, point.Z)
	end
	return clear, grounded
end

local function walkBotSegment(bot, destination, allowDetour)
	if not bot.Parent or not bot.PrimaryPart or bot:GetAttribute("Dead") then return false end
	local clear, grounded = botMotionChecks(bot)
	local start = bot:GetPivot().Position
	local goal = Vector3.new(destination.X, start.Y, destination.Z)
	local direction = goal - start
	if direction.Magnitude < 0.15 then return true end
	local free, obstruction = clear(start, goal)
	if not free then
		-- Dynamic obstacles are not reliably included in Roblox's navmesh.
		-- Try both sides, with two corner points around the person/obstacle.
		-- Each leg still gets the same full-body collision tests below.
		if allowDetour ~= false and obstruction then
			local forward = direction.Unit
			local side = Vector3.new(-forward.Z, 0, forward.X)
			local centre = Vector3.new(obstruction.X, start.Y, obstruction.Z)
			local preferred = (bot:GetAttribute("BotNumber") or 1) % 2 == 0 and 1 or -1
			for _, sign in ipairs({preferred, -preferred}) do
				local entry = grounded(centre - forward * 4.5 + side * sign * 4.5, start.Y)
				local exitPoint = grounded(centre + forward * 4.5 + side * sign * 4.5, start.Y)
				if entry and exitPoint and clear(start, entry) and clear(entry, exitPoint) and clear(exitPoint, goal) then
					bot:SetAttribute("AvoidanceDetours", (bot:GetAttribute("AvoidanceDetours") or 0) + 1)
					return walkBotSegment(bot, entry, false) and walkBotSegment(bot, exitPoint, false) and walkBotSegment(bot, destination, false)
				end
			end
		end
		bot:SetAttribute("NavigationBlocked", true)
		return false
	end
	bot:SetAttribute("NavigationBlocked", false)
	local steps = math.max(1, math.ceil(direction.Magnitude / 0.45))
	for step = 1, steps do
		while bot.Parent and bot:GetAttribute("KnockedOut") and not bot:GetAttribute("Dead") do task.wait(0.25) end
		while bot.Parent and not bot:GetAttribute("Dead") and not bot:GetAttribute("Competitor") and not botHasObserver(bot) do task.wait(0.5) end
		-- A worker that has joined an ambush is driven by the hostile AI in
		-- GWAPServer. Two systems calling PivotTo on the same rig cancel each
		-- other out, so the patrol walk yields for as long as it stays hostile.
		if bot:GetAttribute("GWAPHostile") then return false end
		if not bot.Parent or bot:GetAttribute("Dead") then return false end
		local current = bot:GetPivot().Position
		local nextPoint = grounded(start:Lerp(goal, step / steps), current.Y)
		-- A player may have stepped into the path since it was planned. Stop
		-- before touching them; the caller replans from this actual position.
		if not nextPoint or not clear(current, nextPoint) then
			bot:SetAttribute("NavigationBlocked", true)
			return false
		end
		bot:PivotTo(CFrame.lookAt(nextPoint, nextPoint + direction.Unit))
		task.wait(0.06)
	end
	return true
end

local function moveBotTo(bot, target)
	local destination = interactionPoint(target)
	-- A blocked leg is replanned, never replaced with a teleport/straight
	-- line through a wall. Radius matches the swept body, not just its torso.
	for attempt = 1, 3 do
		if not bot.Parent or bot:GetAttribute("Dead") then return false end
		local path = PathfindingService:CreatePath({AgentRadius = 1.7, AgentHeight = 5.8, AgentCanJump = false, WaypointSpacing = 5})
		local ok = pcall(function() path:ComputeAsync(bot:GetPivot().Position, destination) end)
		local arrived = ok and path.Status == Enum.PathStatus.Success
		if arrived then
			for _, waypoint in ipairs(path:GetWaypoints()) do
				if not walkBotSegment(bot, waypoint.Position + Vector3.new(0, 3.25, 0)) then arrived = false break end
			end
		end
		if arrived then return true end
		bot:SetAttribute("PathFallbacks", (bot:GetAttribute("PathFallbacks") or 0) + 1)
		task.wait(0.25 * attempt)
	end
	return false
end

local function makeBotPlant(bot, stage)
	local old = bot:FindFirstChild("BotHeldPlant")
	if old then old:Destroy() end
	local held = Instance.new("Model")
	held.Name = "BotHeldPlant"
	held.Parent = bot
	local base = bot:GetPivot() * CFrame.new(0.85, 0.1, -0.72)
	local function piece(name, size, offset, colour, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = base * CFrame.new(offset)
		p.Color = colour
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = held
		return p
	end
	piece("Pot", Vector3.new(0.85, 0.62, 0.85), Vector3.new(0, 0, 0), Color3.fromRGB(118, 77, 46))
	piece("Stem", Vector3.new(0.13, 0.75 + stage * 0.13, 0.13), Vector3.new(0, 0.65, 0), Color3.fromRGB(65, 165, 72))
	piece("LeafL", Vector3.new(0.48, 0.12, 0.3), Vector3.new(-0.24, 0.78, 0), Color3.fromRGB(75, 185, 82))
	piece("LeafR", Vector3.new(0.48, 0.12, 0.3), Vector3.new(0.24, 1.0, 0), Color3.fromRGB(75, 185, 82))
	return held
end

local function equipmentReadout(part, top, bottom, colour)
	local label = part:FindFirstChild("Readout", true)
	if label and label:IsA("TextLabel") then
		label.Text = top .. "\n" .. bottom
		label.TextColor3 = colour or Color3.fromRGB(115, 245, 150)
	end
end

local function candidatesOnLevel(levelName, predicate)
	local result = {}
	for _, item in ipairs(CollectionService:GetTagged("LabEquipment")) do
		if item.Parent and item:GetAttribute("Level") == levelName and predicate(item) then
			table.insert(result, item)
		end
	end
	return result
end

local function runBotScenario(bot)
	-- Remember where this worker started, so a shift reset can stand it back up.
	if not bot:GetAttribute("HomeCFrame") then
		pcall(function() bot:SetAttribute("HomeCFrame", bot:GetPivot()) end)
	end
	-- Desk staff stay at their desk. They are still perfectly good targets.
	if bot:GetAttribute("Seated") then
		setBotStatus(bot, "At the desk")
		while bot.Parent and not bot:GetAttribute("Dead") do task.wait(5) end
		return
	end

	while bot.Parent and not bot:GetAttribute("Dead") do
		-- The rival keeps running wherever it is: it is a single NPC and the
		-- competitive scoring loop depends on it making progress.
		if bot:GetAttribute("GWAPHostile") then
			-- Hunting the player takes precedence over the shift routine.
			setBotStatus(bot, "Hunting")
			task.wait(0.5)
			continue
		end
		local awake = bot:GetAttribute("Competitor") or botHasObserver(bot)
		if not awake then
			setBotStatus(bot, "Idle -- no one in the room")
			task.wait(1)
		elseif bot:GetAttribute("KnockedOut") then task.wait(1) else
			local levelName = bot:GetAttribute("Level")
			local failed = candidatesOnLevel(levelName, function(item)
				return item:GetAttribute("Kind") == PLANT_CHAMBER_KIND
					and item:GetAttribute("FunctionalState") == "FAILED"
					and (item:GetAttribute("SampleCount") or 0) > 0
					and not item:GetAttribute("ReservedByBot")
			end)
			if #failed == 0 then
				-- Nothing has failed on this floor right now. The adaptive
				-- difficulty tick deliberately holds the failure rate down when
				-- few players are online, so this is the common case rather than
				-- the rare one -- and standing frozen in front of a player who
				-- just walked in is exactly what "the NPCs don't move" looked
				-- like. Patrol the room instead so the floor reads as staffed.
				-- Only ever runs for a bot somebody is actually watching.
				setBotStatus(bot, "Checking chambers")
				local patrolRoom = roomAt(levelName, bot:GetPivot().Position)
				local rect = patrolRoom and roomRect(levelName, patrolRoom)
				if rect then
					local here = bot:GetPivot().Position
					local spanX = math.max(1, (rect.x2 - rect.x1) - 12)
					local spanZ = math.max(1, (rect.z2 - rect.z1) - 12)
					walkBotSegment(bot, Vector3.new(
						rect.x1 + 6 + math.random() * spanX,
						here.Y,
						rect.z1 + 6 + math.random() * spanZ))
					task.wait(0.5 + math.random() * 1.5)
				else
					task.wait(3)
				end
			else
				table.sort(failed, function(a, b)
					local an = tonumber((a:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
					local bn = tonumber((b:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge
					return an < bn
				end)
				-- Prefer a job in the room the worker is already standing in --
				-- which, because it only wakes when a player is there, is the
				-- room the player is watching. Without this a woken worker
				-- usually picks a chamber elsewhere on the floor, walks out of
				-- the room and stops the moment it loses its observer.
				local botRoom = roomAt(levelName, bot:GetPivot().Position)
				local sameRoom = {}
				if botRoom then
					for _, item in ipairs(failed) do
						if item:GetAttribute("Room") == botRoom then table.insert(sameRoom, item) end
					end
				end
				local pool = (#sameRoom > 0) and sameRoom or failed
				local source = bot:GetAttribute("Competitor") and pool[1] or pool[math.random(1, #pool)]
				local destination = evacuationDestinations(source)[1]
				if not destination then
					setBotStatus(bot, "Waiting for safe capacity")
					task.wait(3)
				else
					local botId = bot.Name
					source:SetAttribute("ReservedByBot", botId)
					destination:SetAttribute("IncomingReservations", (destination:GetAttribute("IncomingReservations") or 0) + 1)
					source:SetAttribute("EvacuationDestination", destination:GetAttribute("GrowthCode") or "")
					refreshChamberTelemetry(source)
					setBotStatus(bot, "Responding to " .. (source:GetAttribute("GrowthCode") or "alarm"))
					local reachedSource = moveBotTo(bot, source)
					local samples = chamberSampleList(source)
					local plantId = reachedSource and table.remove(samples, 1)
					if plantId and source:GetAttribute("ReservedByBot") == botId then
						saveChamberSamples(source, samples)
						updateStoredSamples(source)
						refreshChamberTelemetry(source)
						local stage = math.clamp(source:GetAttribute("GrowthStage") or 0, 0, 5)
						makeBotPlant(bot, stage)
						bot:SetAttribute("CarryingPlant", plantId)
						setBotStatus(bot, "Evacuating " .. plantId)
						equipmentReadout(source, (source:GetAttribute("GrowthCode") or "R?") .. " FAILED", "SEND " .. plantId .. " TO " .. (destination:GetAttribute("GrowthCode") or "R?"), Color3.fromRGB(255, 105, 90))

						-- Emergency transfers still receive one quick development step,
						-- so the same growth mechanics are continuously regression-tested.
						local stations = candidatesOnLevel(levelName, function(item) return PLANT_PROCESS[item:GetAttribute("Kind")] ~= nil end)
						if #stations > 0 then
							local station = stations[((bot:GetAttribute("BotNumber") or 1) - 1) % #stations + 1]
							local process = PLANT_PROCESS[station:GetAttribute("Kind")]
							if moveBotTo(bot, station) then
								stage = math.clamp(stage + (process.gain or 0), 0, 5)
								station:SetAttribute("BotTestUses", (station:GetAttribute("BotTestUses") or 0) + 1)
								equipmentReadout(station, "BOT GROWTH TEST", plantId .. " • stage " .. stage, Color3.fromRGB(120, 235, 165))
							end
						end

						setBotStatus(bot, "Delivering to " .. (destination:GetAttribute("GrowthCode") or "R?"))
						local reachedDestination = moveBotTo(bot, destination)
						local destinationSamples = chamberSampleList(destination)
						if reachedDestination and destination:GetAttribute("FunctionalState") ~= "FAILED" and destination:GetAttribute("FunctionalState") ~= "DESTROYED" and #destinationSamples < (destination:GetAttribute("Capacity") or 10) then
							table.insert(destinationSamples, plantId)
							saveChamberSamples(destination, destinationSamples)
							destination:SetAttribute("GrowthStage", math.max(destination:GetAttribute("GrowthStage") or 0, stage))
							updateStoredSamples(destination)
							refreshChamberTelemetry(destination)
							emergencyMovesCompleted = emergencyMovesCompleted + 1
							bot:SetAttribute("CompletedCycles", (bot:GetAttribute("CompletedCycles") or 0) + 1)
							if bot:GetAttribute("Competitor") then
								local gained = POINTS.MOVE_ASSIGNED_ON_TIME
								bot:SetAttribute("Score", (bot:GetAttribute("Score") or 0) + gained)
								setBotStatus(bot, "+" .. gained .. " resource win")
								updateScoreboard()
							else
								setBotStatus(bot, "Transfer passed")
							end
						else
							-- Capacity changed while walking; return the sample to the source
							-- rather than deleting it and let the next cycle choose again.
							table.insert(samples, plantId)
							saveChamberSamples(source, samples)
							updateStoredSamples(source)
							refreshChamberTelemetry(source)
							setBotStatus(bot, "Destination changed; retrying")
						end
						local held = bot:FindFirstChild("BotHeldPlant")
						if held then held:Destroy() end
						bot:SetAttribute("CarryingPlant", "")
					end
					destination:SetAttribute("IncomingReservations", math.max(0, (destination:GetAttribute("IncomingReservations") or 1) - 1))
					if source:GetAttribute("ReservedByBot") == botId then source:SetAttribute("ReservedByBot", nil) end
					updateBotTestBoard()
					task.wait(1.5 + math.random())
				end
			end
		end
	end
end

--------------------------------------------------------------------
-- ADAPTIVE, INDEFINITE CHAMBER FAILURE SIMULATION
--------------------------------------------------------------------
local FAILURE_REASONS = {
	"Temperature control fault", "Humidity sensor drift", "Ventilation fan blocked",
	"Door seal leak", "Lighting circuit fault", "Nutrient pump pressure low",
}
local generatedSampleSerial = 20000
local previousCompletedMoves = 0

setChamberFailure = function(chamber, failed)
	if not chamber.Parent or chamber:GetAttribute("FunctionalState") == "DESTROYED" then return end
	if chamber:GetAttribute("QuizPlayerId") then return end
	if failed and ((chamber:GetAttribute("IncomingReservations") or 0) > 0
		or chamber:GetAttribute("ReservedByBot")) then return end
	local codeNumber = tonumber((chamber:GetAttribute("GrowthCode") or ""):match("%d+")) or 1
	local code = chamber:GetAttribute("GrowthCode") or ("R" .. codeNumber)
	local floorLabel = chamber:GetAttribute("FloorLabel") or chamber:GetAttribute("Level") or "UNKNOWN FLOOR"
	if failed then
		chamber:SetAttribute("FunctionalState", "FAILED")
		if chamber:GetAttribute("PlantLife") == nil then chamber:SetAttribute("PlantLife", 100) end
		chamber:SetAttribute("RepairKey", "R")
		chamber:SetAttribute("RepairInstruction", "Go to " .. floorLabel .. " • CHAMBER " .. code .. " • HOLD R TO REPAIR")
		chamber:SetAttribute("FailureReason", FAILURE_REASONS[math.random(1, #FAILURE_REASONS)])
		chamber:SetAttribute("FailureSince", os.time())
		chamber:SetAttribute("Temperature", 31 + codeNumber % 8)
		chamber:SetAttribute("Humidity", 35 + codeNumber % 24)
		chamber:SetAttribute("Ventilation", 10 + codeNumber % 28)
		local destination = evacuationDestinations(chamber)[1]
		chamber:SetAttribute("EvacuationDestination", destination and destination:GetAttribute("GrowthCode") or "")
		for _, player in ipairs(Players:GetPlayers()) do
			if playerRole(player) == "Technician" and not player:GetAttribute("AssignedRepairId") then assignNextTask(player) end
			if playerRole(player) == "Laboratory Technician" and not player:GetAttribute("AssignedTransferSource") then assignNextTask(player) end
			if playerRole(player) == "Laboratory Technician" then
				notify(player, "PLANT ALARM: " .. floorLabel .. " • CHAMBER " .. code .. " failed. Press E to remove plants and follow the assigned destination.")
			else
				notify(player, "REPAIR ALARM: " .. floorLabel .. " • CHAMBER " .. code .. " failed. Technician: HOLD R to repair.")
			end
		end
	else
		chamber:SetAttribute("FunctionalState", "WORKING")
		chamber:SetAttribute("RepairInstruction", "Unit working • E TAKE / DROP")
		chamber:SetAttribute("FailureReason", "")
		chamber:SetAttribute("FailureSince", 0)
		chamber:SetAttribute("EvacuationDestination", "")
		chamber:SetAttribute("Temperature", 22 + codeNumber % 4)
		chamber:SetAttribute("Humidity", 67 + codeNumber % 14)
		chamber:SetAttribute("Ventilation", 62 + codeNumber % 29)
		chamber:SetAttribute("OperationStarted", os.time())
		if (chamber:GetAttribute("SampleCount") or 0) > 0 and (chamber:GetAttribute("PlantLife") or 100) < 100 then
			recoverPlantLife(chamber, chamber:GetAttribute("PlantLife"), nil, chamber:GetAttribute("PlantId"))
		end
	end
	refreshChamberTelemetry(chamber)
end

local GENERIC_FAILURE_REASONS = {
	"Power relay fault", "Controller communication loss", "Pump interlock fault",
	"Calibration expired", "Safety sensor trip", "Motor overload",
}

setGenericFailure = function(part, failed)
	if not part.Parent or part:GetAttribute("FunctionalState") == "DESTROYED" then return end
	if part:GetAttribute("QuizPlayerId") then return end
	if failed and (part:GetAttribute("IncomingReservations") or 0) > 0 then return end
	local floorLabel = equipmentFloorLabel(part)
	local unitLabel = equipmentLabel(part)
	if failed then
		part:SetAttribute("FunctionalState", "FAILED")
		part:SetAttribute("RepairKey", "R")
		part:SetAttribute("FailureReason", GENERIC_FAILURE_REASONS[math.random(1, #GENERIC_FAILURE_REASONS)])
		part:SetAttribute("FailureSince", os.time())
		part:SetAttribute("RepairInstruction", floorLabel .. " • " .. unitLabel .. " • HOLD R")
		equipmentReadout(part, "FAILED • HOLD R", floorLabel .. " • " .. unitLabel .. " • PLANTS "
			.. (part:GetAttribute("SampleCount") or 0) .. "/" .. (part:GetAttribute("Capacity") or 0) .. " • " .. part:GetAttribute("FailureReason"),
			Color3.fromRGB(255, 105, 90))
		for _, player in ipairs(Players:GetPlayers()) do
			if playerRole(player) == "Technician" then
				if not player:GetAttribute("AssignedRepairId") then assignNextTask(player) end
				notify(player, "REPAIR ALARM: " .. floorLabel .. " • " .. unitLabel .. " FAILED. HOLD R to repair.")
			end
		end
	else
		part:SetAttribute("FunctionalState", "WORKING")
		part:SetAttribute("FailureReason", "")
		part:SetAttribute("FailureSince", 0)
		part:SetAttribute("RepairInstruction", "WORKING • E USE / INSPECT")
		part:SetAttribute("OperationStarted", os.time())
		equipmentReadout(part, "WORKING", floorLabel .. " • " .. unitLabel .. " • PLANTS "
			.. (part:GetAttribute("SampleCount") or 0) .. "/" .. (part:GetAttribute("Capacity") or 0) .. " • E USE / INSPECT",
			Color3.fromRGB(110, 235, 170))
	end
end

local function shuffled(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function adaptiveFailureTick()
	local chambers = CollectionService:GetTagged("PlantGrowthChamber")
	local failed, working = {}, {}
	local failedSamples, totalSamples, workingFree = 0, 0, 0
	for _, chamber in ipairs(chambers) do
		local count = chamber:GetAttribute("SampleCount") or 0
		local capacity = chamber:GetAttribute("Capacity") or 10
		totalSamples = totalSamples + count
		if chamber:GetAttribute("FunctionalState") == "FAILED" then
			table.insert(failed, chamber)
			failedSamples = failedSamples + count
		elseif chamber:GetAttribute("FunctionalState") == "WORKING" then
			if os.time() - (chamber:GetAttribute("LastRepairedAt") or 0) >= 180 then
				table.insert(working, chamber)
			end
			workingFree = workingFree + math.max(0, capacity - count - (chamber:GetAttribute("IncomingReservations") or 0))
		end
	end

	local throughput = emergencyMovesCompleted - previousCompletedMoves
	previousCompletedMoves = emergencyMovesCompleted
	-- A human-sized workload, independent of the hundreds of installed units.
	-- Two failed chambers per player (at most eight), one new alarm per tick.
	local playerCount = math.max(1, #Players:GetPlayers())
	local targetFailed = workingFree >= 12 and math.min(8, playerCount * 2) or 0
	local targetRate = targetFailed / math.max(1, #chambers)
	local change = math.min(1, targetFailed - #failed)
	if change > 0 then
		local eligible = {}
		for _, chamber in ipairs(working) do
			if os.time() - (chamber:GetAttribute("LastRepairedAt") or 0) >= 180
				and (chamber:GetAttribute("IncomingReservations") or 0) == 0
				and not chamber:GetAttribute("ReservedByBot") then table.insert(eligible, chamber) end
		end
		shuffled(eligible)
		for i = 1, math.min(change, #eligible) do setChamberFailure(eligible[i], true) end
	elseif change < 0 then
		table.sort(failed, function(a, b)
			local ac, bc = a:GetAttribute("SampleCount") or 0, b:GetAttribute("SampleCount") or 0
			if ac == bc then return (a:GetAttribute("FailureSince") or 0) < (b:GetAttribute("FailureSince") or 0) end
			return ac < bc
		end)
		for i = 1, math.min(-change, #failed) do setChamberFailure(failed[i], false) end
	end

	-- Failed telemetry continues to drift; working chambers continuously
	-- germinate replacement samples so the transfer game never runs out.
	for _, chamber in ipairs(chambers) do
		if chamber:GetAttribute("FunctionalState") == "FAILED" then
			chamber:SetAttribute("Temperature", math.clamp((chamber:GetAttribute("Temperature") or 33) + math.random(-2, 2), 28, 42))
			chamber:SetAttribute("Humidity", math.clamp((chamber:GetAttribute("Humidity") or 45) + math.random(-4, 4), 25, 65))
			chamber:SetAttribute("Ventilation", math.clamp((chamber:GetAttribute("Ventilation") or 20) + math.random(-5, 3), 0, 48))
			local destination = evacuationDestinations(chamber)[1]
			chamber:SetAttribute("EvacuationDestination", destination and destination:GetAttribute("GrowthCode") or "")
		elseif chamber:GetAttribute("FunctionalState") == "WORKING" then
			local samples = chamberSampleList(chamber)
			local capacity = chamber:GetAttribute("Capacity") or 10
			local refillChance = math.clamp(0.08 + (capacity - #samples) * 0.025 + throughput * 0.002
				+ playerCount * 0.008, 0.08, 0.46)
			-- Keep receiving space available for real evacuation tasks.
			if #samples < capacity - math.max(2, math.ceil(capacity * 0.3)) and math.random() < refillChance then
				generatedSampleSerial = generatedSampleSerial + 1
				table.insert(samples, string.format("%s-G%05d", chamber:GetAttribute("GrowthCode") or "R", generatedSampleSerial))
				saveChamberSamples(chamber, samples)
				chamber:SetAttribute("GerminationDate", os.date("%Y-%m-%d %H:%M"))
				updateStoredSamples(chamber)
			end
		end
		refreshChamberTelemetry(chamber)
	end
	local complex = workspace:FindFirstChild("Laboratory_Complex")
	if complex then
		complex:SetAttribute("AdaptiveFailureTargetPercent", math.floor(targetRate * 100 + 0.5))
		complex:SetAttribute("FailingChambers", #failed)
		complex:SetAttribute("FailedSampleBacklog", failedSamples)
		complex:SetAttribute("EmergencyMovesCompleted", emergencyMovesCompleted)
		complex:SetAttribute("RecentTransferThroughput", throughput)
		complex:SetAttribute("ActivePlayerCount", playerCount)
		complex:SetAttribute("ActiveNPCWorkers", math.clamp(8 + playerCount * 6 + math.floor(failedSamples / 20), 8, 50))
		-- Per-FLOOR budget. Multiplied across the basement plus every level
		-- this is what actually decides how many workers are visibly busy.
		complex:SetAttribute("ActiveNPCWorkersPerFloor", math.clamp(6 + playerCount * 2 + math.floor(failedSamples / 60), 6, 20))
	end
end

local function genericFailureTick()
	local failed, working = {}, {}
	for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
		if equipment:GetAttribute("Kind") ~= PLANT_CHAMBER_KIND then
			if equipment:GetAttribute("FunctionalState") == "FAILED" then
				table.insert(failed, equipment)
			elseif equipment:GetAttribute("FunctionalState") == "WORKING"
				and os.time() - (equipment:GetAttribute("LastRepairedAt") or 0) >= 180 then
				table.insert(working, equipment)
			end
		end
	end
	local playerCount = math.max(1, #Players:GetPlayers())
	local targetFailed = math.min(4, playerCount)
	local change = math.min(1, targetFailed - #failed)
	if change > 0 then
		shuffled(working)
		for i = 1, math.min(change, #working) do setGenericFailure(working[i], true) end
	elseif change < 0 then
		table.sort(failed, function(a, b) return (a:GetAttribute("FailureSince") or 0) < (b:GetAttribute("FailureSince") or 0) end)
		for i = 1, math.min(-change, #failed) do setGenericFailure(failed[i], false) end
	end
end

local function bindPlayerTaskRouting(player)
	if player:GetAttribute("EquipmentTaskRoutingBound") then return end
	player:SetAttribute("EquipmentTaskRoutingBound", true)
	player:GetAttributeChangedSignal("LabRole"):Connect(function()
		task.delay(0.2, function()
			if player.Parent then assignNextTask(player) end
		end)
	end)
	player.CharacterAdded:Connect(function()
		if playerRole(player) == "Technician" and player:GetAttribute("AssignedRepairId") then
			task.delay(1, function() if player.Parent then assignNextTask(player) end end)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do bindPlayerTaskRouting(player) end
Players.PlayerAdded:Connect(bindPlayerTaskRouting)
Players.PlayerRemoving:Connect(clearRepairPath)

for _, p in ipairs(CollectionService:GetTagged("LabEquipment")) do bind(p) end
CollectionService:GetInstanceAddedSignal("LabEquipment"):Connect(bind)

--------------------------------------------------------------------
-- AUTOMATIC DOORS
-- Every AutoDoor panel slides up into the header void when a player's
-- HumanoidRootPart comes within range, and back down once nobody is close,
-- so rooms have real doors instead of a permanently open gap.
--------------------------------------------------------------------
local DOOR_OPEN_RANGE = 11
local DOOR_CLOSE_RANGE = 15
local DOOR_MIN_OPEN_SECONDS = 3
local function bindAutoDoor(door)
	if door:GetAttribute("DoorBound") then return end
	door:SetAttribute("DoorBound", true)
	local closedX = door:GetAttribute("DoorClosedX") or door.Position.X
	local closedZ = door:GetAttribute("DoorClosedZ") or door.Position.Z
	local openX = door:GetAttribute("DoorOpenX") or closedX
	local openZ = door:GetAttribute("DoorOpenZ") or closedZ
	local doorY = door:GetAttribute("DoorY") or door.Position.Y
	local isOpen = false
	local openedAt = 0
	local tween
	local function setIndicatorColour(open)
		local colour = open and Color3.fromRGB(60, 210, 90) or Color3.fromRGB(210, 40, 40)
		for _, gui in ipairs(door:GetChildren()) do
			if gui:IsA("SurfaceGui") and gui.Name == "AutoDoorLabel" then
				local indicator = gui:FindFirstChild("DoorIndicator")
				if indicator then indicator.BackgroundColor3 = colour end
			end
		end
	end
	local function setOpen(open)
		if open == isOpen then return end
		isOpen = open
		if open then openedAt = os.clock() end
		if tween then tween:Cancel() end
		local targetX = open and openX or closedX
		local targetZ = open and openZ or closedZ
		-- 0.9s ease so the slide is smooth and readable (never an instant
		-- snap, which is what made the old vertical slide read as flicker).
		tween = TweenService:Create(door, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{CFrame = CFrame.new(targetX, doorY, targetZ)})
		tween:Play()
		door.CanCollide = not open
		door:SetAttribute("DoorOpen", open)   -- watched by the room smoke system
		setIndicatorColour(open)
	end
	task.spawn(function()
		while door.Parent do
			local nearest = math.huge
			-- The ambush system holds a door open so workers can come out of the
			-- room while the player is still in the corridor, beyond the range a
			-- player alone would trigger.
			if door:GetAttribute("ForceOpen") then nearest = 0 end
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp then
					-- Floors stack directly above each other at the same X/Z, so a
					-- flat (X/Z-only) distance check would treat a player on a
					-- completely different floor as "standing at the door." Only
					-- count players actually close in height to this door first.
					local verticalGap = math.abs(hrp.Position.Y - doorY)
					if verticalGap < 8 then
						local flat = (Vector3.new(hrp.Position.X, doorY, hrp.Position.Z) - Vector3.new(closedX, doorY, closedZ)).Magnitude
						if flat < nearest then nearest = flat end
					end
				end
			end
			-- Once opened, a door holds for at least DOOR_MIN_OPEN_SECONDS
			-- before it's allowed to close again -- this is what actually
			-- fixes the "opens and closes too fast" flicker, independent of
			-- the slide direction/speed above.
			if isOpen and nearest > DOOR_CLOSE_RANGE and (os.clock() - openedAt) >= DOOR_MIN_OPEN_SECONDS then
				setOpen(false)
			elseif not isOpen and nearest < DOOR_OPEN_RANGE then
				setOpen(true)
			end
			task.wait(0.25)
		end
	end)
end

for _, p in ipairs(CollectionService:GetTagged("AutoDoor")) do bindAutoDoor(p) end
CollectionService:GetInstanceAddedSignal("AutoDoor"):Connect(bindAutoDoor)

--------------------------------------------------------------------
-- EMERGENCY KITS
-- One per room. Press E to fully restore health. When a player's health
-- drops below half (and they're not mid-job), a red floor-marker route --
-- the same system used for repair/transfer jobs -- guides them to the
-- closest kit.
--------------------------------------------------------------------
local function bindEmergencyKit(kit)
	if kit:GetAttribute("KitBound") then return end
	kit:SetAttribute("KitBound", true)
	local prompt = kit:FindFirstChild("EmergencyKitPrompt")
	if not prompt then return end
	-- Health stations RECHARGE rather than being consumed. A single-use kit
	-- that destroyed itself meant a floor could be permanently stripped of
	-- health with no way to get it back.
	local RECHARGE_SECONDS = 25
	local caption
	local faceGui = kit:FindFirstChild("EmergencyKitFace")
	if faceGui then
		for _, d in ipairs(faceGui:GetDescendants()) do
			if d:IsA("TextLabel") then caption = d break end
		end
	end

	local function setCharged(charged)
		kit:SetAttribute("Charged", charged)
		prompt.Enabled = charged
		kit.Color = charged and Color3.fromRGB(225, 40, 35) or Color3.fromRGB(92, 60, 58)
		if caption then caption.Text = charged and "HEALTH" or "CHARGING" end
	end

	prompt.Triggered:Connect(function(player)
		if kit:GetAttribute("Charged") == false then return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		setCharged(false)
		humanoid.Health = humanoid.MaxHealth
		notify(player, "Health restored. This station recharges in " .. RECHARGE_SECONDS .. "s -- there are more along every corridor.")
		task.delay(RECHARGE_SECONDS, function()
			if kit.Parent then setCharged(true) end
		end)
	end)
	setCharged(true)
end
for _, p in ipairs(CollectionService:GetTagged("EmergencyKit")) do bindEmergencyKit(p) end
CollectionService:GetInstanceAddedSignal("EmergencyKit"):Connect(bindEmergencyKit)

--------------------------------------------------------------------
-- PLAYER HEALTH BARS
-- Matches the bar the worker bots carry, so a player can read their own
-- and everyone else's condition without opening any menu.
--------------------------------------------------------------------
local function attachPlayerHealthBar(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 8)
	if not humanoid or not head or head:FindFirstChild("LabHealthBar") then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "LabHealthBar"
	gui.Size = UDim2.fromOffset(168, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.AlwaysOnTop = false
	gui.Parent = head

	local back = Instance.new("Frame")
	back.Name = "HealthBarBack"
	back.Size = UDim2.new(0.9, 0, 0.34, 0)
	back.Position = UDim2.new(0.05, 0, 0.06, 0)
	back.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "HealthBarFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(75, 220, 95)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local label = Instance.new("TextLabel")
	label.Name = "HealthText"
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.Position = UDim2.new(0, 0, 0.48, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(224, 238, 248)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	local function refresh()
		local maximum = math.max(1, humanoid.MaxHealth)
		local ratio = math.clamp(humanoid.Health / maximum, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = ratio > 0.55 and Color3.fromRGB(75, 220, 95)
			or (ratio > 0.25 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(235, 65, 60))
		label.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	refresh()
end

local function watchPlayerHealth(player)
	player.CharacterAdded:Connect(attachPlayerHealthBar)
	if player.Character then task.spawn(attachPlayerHealthBar, player.Character) end
end
Players.PlayerAdded:Connect(watchPlayerHealth)
for _, player in ipairs(Players:GetPlayers()) do watchPlayerHealth(player) end

--------------------------------------------------------------------
-- SECRET BASEMENT VENT
-- Disguised as part of the lobby's own exterior wall. Holding E on it
-- drops the player straight into the basement corridor.
--------------------------------------------------------------------
local function bindSecretBasementPanel(panel)
	if panel:GetAttribute("SecretBound") then return end
	panel:SetAttribute("SecretBound", true)
	local prompt = panel:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or (hrp.Position - panel.Position).Magnitude > 12 then return end
		local floorPoint = Vector3.new(
			panel:GetAttribute("SecretDestX") or hrp.Position.X,
			panel:GetAttribute("SecretDestY") or hrp.Position.Y,
			panel:GetAttribute("SecretDestZ") or hrp.Position.Z)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {character}
		params.RespectCanCollide = true
		local floorHit = workspace:Raycast(floorPoint + Vector3.new(0, 7, 0), Vector3.new(0, -12, 0), params)
		if not floorHit or floorHit.Normal.Y < 0.7 then return end
		local feetOffset = humanoid.HipHeight + hrp.Size.Y / 2
		for _, name in ipairs({"LeftFoot", "RightFoot", "Left Leg", "Right Leg"}) do
			local foot = character:FindFirstChild(name)
			if foot and foot:IsA("BasePart") then
				feetOffset = math.max(feetOffset, hrp.Position.Y - (foot.Position.Y - foot.Size.Y / 2))
			end
		end
		hrp.CFrame = CFrame.new(floorHit.Position + Vector3.new(0, feetOffset + 0.35, 0))
		hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		notify(player, "The vent panel swings open -- you drop into the basement.")
	end)
end
for _, p in ipairs(CollectionService:GetTagged("SecretBasementPanel")) do bindSecretBasementPanel(p) end
CollectionService:GetInstanceAddedSignal("SecretBasementPanel"):Connect(bindSecretBasementPanel)

local function nearestEmergencyKit(position)
	local best, bestDist
	for _, kit in ipairs(CollectionService:GetTagged("EmergencyKit")) do
		if kit.Parent then
			local d = (kit.Position - position).Magnitude
			if not bestDist or d < bestDist then best, bestDist = kit, d end
		end
	end
	return best
end

local healthPathActive = {}
task.spawn(function()
	while true do
		task.wait(3)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and hrp and humanoid.Health > 0 then
				local low = humanoid.Health < humanoid.MaxHealth * 0.5
				local busy = player:GetAttribute("AssignedRepairId") or player:GetAttribute("AssignedTransferSource")
				if low and not busy and not healthPathActive[player] then
					local kit = nearestEmergencyKit(hrp.Position)
					if kit then
						createRepairPath(player, kit)
						healthPathActive[player] = true
						notify(player, "Health low: follow the RED floor lights to the nearest emergency kit.")
					end
				elseif (not low or busy) and healthPathActive[player] then
					healthPathActive[player] = false
					if not busy then clearRepairPath(player) end
				end
			end
		end
	end
end)

--------------------------------------------------------------------
-- EQUIPMENT HAZARDS
-- A malfunctioning (FAILED) unit is genuinely dangerous to linger next to:
-- electrical faults, steam/humidity blowouts, chemical spills and coolant
-- (freon) leaks all drain health while a player stays in range.
--------------------------------------------------------------------
local HAZARD_BY_KIND = {
	["Germination Chamber"] = {"STEAM LEAK", 3},
	["Incubator"] = {"STEAM LEAK", 3},
	["Decontamination Unit"] = {"CHEMICAL VAPOR", 4},
	["Mutagenesis Chamber"] = {"RADIATION LEAK", 6},
	["Hormone Treatment Bench"] = {"CHEMICAL SPILL", 4},
	["Plant Growth Chamber"] = {"COOLANT (FREON) LEAK", 3},
	["Growth Hormone Mixer"] = {"CHEMICAL SPILL", 4},
	["GMO Injector"] = {"ELECTRICAL FAULT", 5},
	["Nutrient Infuser"] = {"PRESSURE LEAK", 4},
	["UV Growth Scanner"] = {"UV OVEREXPOSURE", 4},
	["Pollination Station"] = {"ELECTRICAL FAULT", 5},
}
local HAZARD_RANGE = 9
local hazardWarnedAt = {}

-- A unit that's been left FAILED too long can catastrophically blow up,
-- catch fire, or arc -- and unlike an ordinary failure, this one can never
-- be repaired. It keeps draining nearby health (worse than before) and its
-- StatusLED/timer read DESTROYED permanently.
--
-- Two-stage sequence: warnEquipmentCatastrophe() runs a 2-second siren +
-- strobe so anyone nearby has time to clear out, THEN destroyEquipment()
-- fires the actual explosion/fire/arc/leak effects.
local DESTRUCTION_KIND = {
	["Germination Chamber"] = "steam",
	["Incubator"] = "steam",
	["Decontamination Unit"] = "gas",
	["Mutagenesis Chamber"] = "electrical",
	["Hormone Treatment Bench"] = "liquid",
	["Plant Growth Chamber"] = "gas",
	["Growth Hormone Mixer"] = "liquid",
	["GMO Injector"] = "electrical",
	["Nutrient Infuser"] = "gas",
	["UV Growth Scanner"] = "electrical",
	["Pollination Station"] = "electrical",
}

local function scatterDebris(part)
	for i = 1, math.random(4, 7) do
		local chunk = Instance.new("Part")
		chunk.Name = "Debris"
		chunk.Size = Vector3.new(math.random(2, 6) / 10, math.random(2, 6) / 10, math.random(2, 6) / 10)
		chunk.Color = part.Color
		chunk.Material = Enum.Material.Metal
		chunk.CFrame = part.CFrame * CFrame.new(math.random(-3, 3) / 2, math.random(0, 3) / 2, math.random(-3, 3) / 2)
		chunk.Anchored = false
		chunk.CanCollide = true
		chunk.Parent = part.Parent
		local av = Instance.new("AngularVelocity")
		av.AngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		av.Parent = chunk
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(4000, 4000, 4000)
		bv.Velocity = Vector3.new(math.random(-16, 16), math.random(6, 16), math.random(-16, 16))
		bv.Parent = chunk
		Debris:AddItem(bv, 0.25)
		Debris:AddItem(chunk, 8)
	end
end

local destroyEquipment

local function warnEquipmentCatastrophe(part, floorLabel, unitLabel)
	if part:GetAttribute("AboutToBlow") then return end
	part:SetAttribute("AboutToBlow", true)
	local beacon = Instance.new("PointLight")
	beacon.Color = Color3.fromRGB(255, 40, 30)
	beacon.Brightness = 4
	beacon.Range = 16
	beacon.Parent = part
	local siren = Instance.new("Sound")
	siren.Name = "SirenWarning"
	siren.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	siren.Looped = true
	siren.Volume = 3
	siren.PlaybackSpeed = 1.6
	siren.Parent = part
	siren:Play()
	for _, player in ipairs(Players:GetPlayers()) do
		notify(player, "ALARM: " .. floorLabel .. " • " .. unitLabel .. " is about to fail catastrophically -- MOVE AWAY NOW!")
	end
	task.spawn(function()
		local elapsed = 0
		while elapsed < 2 and part.Parent do
			beacon.Enabled = not beacon.Enabled
			task.wait(0.2)
			elapsed = elapsed + 0.2
		end
	end)
	task.delay(2, function()
		siren:Stop()
		siren:Destroy()
		beacon:Destroy()
		if part.Parent then destroyEquipment(part) end
	end)
end

destroyEquipment = function(part)
	local floorLabel = equipmentFloorLabel(part)
	local unitLabel = equipmentLabel(part)
	local causes = {"exploded", "caught fire", "arced and shorted out"}
	local cause = causes[math.random(1, #causes)]
	part:SetAttribute("FunctionalState", "DESTROYED")
	part:SetAttribute("AboutToBlow", nil)
	part:SetAttribute("RepairInstruction", floorLabel .. " • " .. unitLabel .. " • DESTROYED, UNFIXABLE")
	equipmentReadout(part, "DESTROYED", floorLabel .. " • " .. unitLabel .. " " .. cause .. " -- permanently offline",
		Color3.fromRGB(150, 40, 35))
	for _, ledPart in ipairs(part:GetDescendants()) do
		if ledPart.Name == "StatusLED" then ledPart.Color = Color3.fromRGB(40, 40, 40); ledPart.Material = Enum.Material.SmoothPlastic end
	end
	part.Color = part.Color:Lerp(Color3.fromRGB(35, 32, 30), 0.6)

	local bang = Instance.new("Sound")
	bang.SoundId = "rbxasset://sounds/impact_generic.mp3"
	bang.Volume = 4
	bang.PlaybackSpeed = 0.8
	bang.Parent = part
	bang:Play()
	Debris:AddItem(bang, 4)

	local explosion = Instance.new("Explosion")
	explosion.Position = part.Position
	explosion.BlastRadius = 8
	explosion.BlastPressure = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	local kindOfDestruction = DESTRUCTION_KIND[part:GetAttribute("Kind")] or "electrical"

	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(90, 90, 90)
	fire.Parent = part
	Debris:AddItem(fire, 16)

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 230, 120)
	sparkles.Parent = part
	Debris:AddItem(sparkles, 3)

	local smoke = Instance.new("Smoke")
	smoke.Size = 8
	smoke.Opacity = kindOfDestruction == "steam" and 0.5 or 0.8
	smoke.RiseVelocity = kindOfDestruction == "gas" and 1.5 or 3
	smoke.Color = (kindOfDestruction == "steam") and Color3.fromRGB(225, 230, 235)
		or (kindOfDestruction == "gas") and Color3.fromRGB(140, 200, 120)
		or Color3.fromRGB(50, 50, 55)
	smoke.Parent = part
	Debris:AddItem(smoke, 20)

	if kindOfDestruction == "liquid" then
		local puddle = Instance.new("Part")
		puddle.Name = "LeakPuddle"
		puddle.Shape = Enum.PartType.Cylinder
		puddle.Size = Vector3.new(0.05, 3.5, 3.5)
		puddle.CFrame = CFrame.new(part.Position.X, part.Position.Y - part.Size.Y / 2 + 0.05, part.Position.Z)
			* CFrame.Angles(0, 0, math.rad(90))
		puddle.Color = Color3.fromRGB(120, 90, 40)
		puddle.Material = Enum.Material.Neon
		puddle.Transparency = 0.35
		puddle.Anchored = true
		puddle.CanCollide = false
		puddle.Parent = part.Parent
		Debris:AddItem(puddle, 25)
	end

	scatterDebris(part)

	for _, player in ipairs(Players:GetPlayers()) do
		notify(player, "CATASTROPHIC FAILURE: " .. floorLabel .. " • " .. unitLabel .. " " .. cause .. ". It cannot be repaired.")
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		local hazards = {}
		for _, equip in ipairs(CollectionService:GetTagged("LabEquipment")) do
			local state = equip.Parent and equip:GetAttribute("FunctionalState")
			if state == "FAILED" then
				local info = HAZARD_BY_KIND[equip:GetAttribute("Kind")]
				if info then table.insert(hazards, {part = equip, label = info[1], dps = info[2]}) end
				-- Five minutes to reach the job before a rare catastrophic risk;
				-- a unit under a player's addition check cannot self-destruct.
				local failedFor = os.time() - (equip:GetAttribute("FailureSince") or os.time())
				if failedFor > 300 and not equip:GetAttribute("QuizPlayerId") and math.random(1, 600) == 1 then
					warnEquipmentCatastrophe(equip, equipmentFloorLabel(equip), equipmentLabel(equip))
				end
			elseif state == "DESTROYED" then
				local info = HAZARD_BY_KIND[equip:GetAttribute("Kind")]
				if info then table.insert(hazards, {part = equip, label = info[1] .. " (DESTROYED)", dps = info[2] + 2}) end
			end
		end
		if #hazards > 0 then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if humanoid and hrp and humanoid.Health > 0 then
					local worst
					for _, hazard in ipairs(hazards) do
						local d = (hazard.part.Position - hrp.Position).Magnitude
						if d < HAZARD_RANGE and hazard.part:GetAttribute("QuizPlayerId") ~= player.UserId
							and (not worst or hazard.dps > worst.dps) then worst = hazard end
					end
					if worst then
						humanoid:TakeDamage(worst.dps)
						local last = hazardWarnedAt[player] or 0
						if os.clock() - last > 2 then
							hazardWarnedAt[player] = os.clock()
							notify(player, string.format("WARNING: %s nearby -- move away! (%d HP)", worst.label, math.floor(humanoid.Health)))
						end
					end
				end
			end
		end
	end
end)

for _, p in ipairs(CollectionService:GetTagged("LabToolDispenser")) do bindDispenser(p) end
CollectionService:GetInstanceAddedSignal("LabToolDispenser"):Connect(bindDispenser)

local testBots = CollectionService:GetTagged("LabWorkerBot")
table.sort(testBots, function(a, b) return (a:GetAttribute("BotNumber") or 0) < (b:GetAttribute("BotNumber") or 0) end)
for index, bot in ipairs(testBots) do
	-- Stagger WITHIN each floor, not across the whole building. Staggering on
	-- the global index at 0.32s a bot meant the top floor did not begin its
	-- loop until nearly a minute after the server started, so the upper
	-- levels looked completely frozen to anyone who walked up there early.
	-- Keyed off the per-floor slot, every floor is fully awake in ~7s.
	-- Only bots someone is standing next to will actually compute a path now,
	-- so there is no thundering herd to spread out and the stagger can be
	-- short. Every floor is ready ~1.6s in instead of ~58s.
	local slot = bot:GetAttribute("LevelSlot") or index
	task.delay(slot * 0.08, function()
		if bot.Parent then runBotScenario(bot) end
	end)
end

-- Bodies stay put for the whole shift. LabRound stamps RoundNumber on
-- Workspace when the shift rolls over; that is the cue to clear them away and
-- put every worker back on its feet for a fresh hunt.
local function resetHunt()
	local bodies = workspace:FindFirstChild("LabBotBodies")
	if bodies then bodies:ClearAllChildren() end

	local complex = workspace:FindFirstChild("Laboratory_Complex")
	if complex then complex:SetAttribute("BotsKilled", 0) end

	local restaged = 0
	for _, bot in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
		if bot:GetAttribute("Dead") then
			local home = bot:GetAttribute("HomeCFrame")
			if typeof(home) == "CFrame" then bot:PivotTo(home) end
			bot:SetAttribute("Health", bot:GetAttribute("MaxHealth") or 100)
			bot:SetAttribute("KnockedOut", false)
			bot:SetAttribute("Dead", false)
			bot:SetAttribute("TaskState", "Waiting for plant task")
			refreshBotHealth(bot)
			-- its old scenario loop exited on death, so start a fresh one
			task.spawn(runBotScenario, bot)
			restaged = restaged + 1
		end
	end
	if restaged > 0 then
		print("Shift reset: cleared bodies and restaged " .. restaged .. " workers.")
	end
end
workspace:GetAttributeChangedSignal("RoundNumber"):Connect(resetHunt)

--------------------------------------------------------------------
-- ROOM SMOKE
-- Small rooms slowly fill with smoke. Opening a door vents it. Capped so
-- there are never more than a handful of smoke volumes alive at once.
--------------------------------------------------------------------
local MAX_SMOKY_ROOMS = 4
local smokeByRoom = {}

local function clearRoomSmoke(key)
	local folder = smokeByRoom[key]
	if not folder then return end
	smokeByRoom[key] = nil
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Smoke") then d.Enabled = false end
	end
	Debris:AddItem(folder, 5)   -- let what is already in the air disperse
end

local function fillRoomWithSmoke(levelName, rect)
	local key = levelName .. "/" .. rect.name
	if smokeByRoom[key] then return end
	local folder = Instance.new("Folder")
	folder.Name = "RoomSmoke"
	folder:SetAttribute("RoomKey", key)
	folder.Parent = workspace
	for i = 1, 5 do
		local emitter = Instance.new("Part")
		emitter.Name = "SmokeSource"
		emitter.Size = Vector3.new(1, 1, 1)
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.Transparency = 1
		emitter.CFrame = CFrame.new(
			rect.x1 + (rect.x2 - rect.x1) * (i - 0.5) / 5,
			rect.y + 3,
			rect.z1 + (rect.z2 - rect.z1) * ((i * 2) % 5 + 0.5) / 5)
		emitter.Parent = folder
		local smoke = Instance.new("Smoke")
		smoke.Size = 11
		smoke.Opacity = 0.32
		smoke.RiseVelocity = 2
		smoke.Color = Color3.fromRGB(150, 150, 152)
		smoke.Parent = emitter
	end
	smokeByRoom[key] = folder
end

local function ventFromDoor(door)
	local pos = door.Position
	for key in pairs(smokeByRoom) do
		local levelName, roomName = key:match("^(.-)/(.+)$")
		local rect = roomRect(levelName, roomName)
		-- a door on the room's own boundary counts, hence the small margin
		if rect and math.abs(pos.Y - rect.y) < FLOOR_BAND
			and pos.X >= rect.x1 - 8 and pos.X <= rect.x2 + 8
			and pos.Z >= rect.z1 - 8 and pos.Z <= rect.z2 + 8 then
			clearRoomSmoke(key)
		end
	end
end

local function watchDoor(door)
	door:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		if door:GetAttribute("DoorOpen") then ventFromDoor(door) end
	end)
end
for _, door in ipairs(CollectionService:GetTagged("AutoDoor")) do watchDoor(door) end
CollectionService:GetInstanceAddedSignal("AutoDoor"):Connect(watchDoor)

task.spawn(function()
	while true do
		task.wait(45)
		local live = 0
		for _ in pairs(smokeByRoom) do live = live + 1 end
		if live < MAX_SMOKY_ROOMS then
			local levels = {}
			for levelName in pairs(roomsByLevel) do table.insert(levels, levelName) end
			if #levels > 0 then
				local levelName = levels[math.random(1, #levels)]
				-- only the small east bays; the long west room is not a "small room"
				local small = {}
				for _, r in ipairs(roomsByLevel[levelName]) do
					if (r.x2 - r.x1) < 90 and (r.z2 - r.z1) < 90 then table.insert(small, r) end
				end
				if #small > 0 then
					fillRoomWithSmoke(levelName, small[math.random(1, #small)])
				end
			end
		end
	end
end)
task.spawn(function()
	while task.wait(2) do updateBotTestBoard() end
end)
task.spawn(function()
	while task.wait(2) do refreshRoomMonitors() end
end)
task.spawn(function()
	task.wait(3)
	while true do
		adaptiveFailureTick()
		genericFailureTick()
		task.wait(45)
	end
end)

print("Equipment armed: " .. #CollectionService:GetTagged("LabEquipment")
	.. " items; recovery tool pads: " .. #CollectionService:GetTagged("LabToolDispenser") .. ".")

--------------------------------------------------------------------
-- LAB STAFF NPCs
--------------------------------------------------------------------
local function bindNPC(part)
	if part:GetAttribute("TalkBound") then return end
	part:SetAttribute("TalkBound", true)
	local tipsStr = part:GetAttribute("Tips") or ""
	local tips = {}
	for t in tipsStr:gmatch("[^|]+") do table.insert(tips, t) end
	local label = part:GetAttribute("NPCName") or part:GetAttribute("Role") or "Lab Staff"

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = label
	prompt.ActionText = "Talk"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if not canInteract(player, part, prompt.MaxActivationDistance) then return end
		if #tips == 0 then return end
		notify(player, label .. ": " .. tips[math.random(1, #tips)])
	end)
end

for _, p in ipairs(CollectionService:GetTagged("LabNPC")) do bindNPC(p) end
CollectionService:GetInstanceAddedSignal("LabNPC"):Connect(bindNPC)

print("Lab staff NPCs armed: " .. #CollectionService:GetTagged("LabNPC") .. ".")
