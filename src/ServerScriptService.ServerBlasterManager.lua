--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.ServerBlasterManager
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Authoritative shooting
Future change: Add weapon configuration only through validated server-side attributes; keep sequence and rate limits.
Preserve dependencies: Blaster configuration, GWAPHitBridge, legacy impact bridge.
Acceptance cases: Spoofed tool, out-of-order packet, impossible camera origin, wall obstruction, and correct target damage.
This revision changes documentation only in this source; executable input/aiming behavior is preserved.
]========]
-- ServerBlasterManager
-- Authoritative validation, obstacle recasting, damage, and shot replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local Blaster = require(modules:WaitForChild("Blaster"))

local remoteFolder = ReplicatedStorage:FindFirstChild(Blaster.REMOTE_FOLDER_NAME)
if remoteFolder and not remoteFolder:IsA("Folder") then remoteFolder:Destroy(); remoteFolder = nil end
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = Blaster.REMOTE_FOLDER_NAME
	remoteFolder.Parent = ReplicatedStorage
end

local function getRemote(name)
	local remote = remoteFolder:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then remote:Destroy(); remote = nil end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remoteFolder
	end
	return remote
end

local fireRemote = getRemote(Blaster.FIRE_REMOTE_NAME)
local effectRemote = getRemote(Blaster.EFFECT_REMOTE_NAME)

local hitBridge = ServerScriptService:FindFirstChild("BlasterHitBridge")
if hitBridge and not hitBridge:IsA("BindableFunction") then hitBridge:Destroy(); hitBridge = nil end
if not hitBridge then
	hitBridge = Instance.new("BindableFunction")
	hitBridge.Name = "BlasterHitBridge"
	hitBridge.Parent = ServerScriptService
end

-- Roblox's default third-person zoom can legitimately place the camera well
-- behind the character. Keep the anti-spoof bound, but allow normal PC/mobile
-- zoom distances and the over-shoulder hip-fire camera.
local MAX_CAMERA_OFFSET = 40
local RATE_TOLERANCE = 0.88
local nextShotByPlayer = {}
local lastSequenceByTool = setmetatable({}, {__mode = "k"})

local function findHumanoidFromHit(instance)
	local node = instance
	while node and node ~= workspace do
		if node:IsA("Model") then
			local humanoid = node:FindFirstChildOfClass("Humanoid")
			if humanoid then return humanoid, node end
		end
		node = node.Parent
	end
	return nil
end

local function randomSpread(direction, spread)
	if spread <= 0 then return direction end
	local reference = math.abs(direction.Y) > 0.96 and Vector3.xAxis or Vector3.yAxis
	local right = direction:Cross(reference).Unit
	local up = right:Cross(direction).Unit
	local radius = math.sqrt(math.random()) * spread
	local angle = math.random() * math.pi * 2
	return (direction + right * math.cos(angle) * radius + up * math.sin(angle) * radius).Unit
end

local function broadcastShot(shooter, origin, position, normal, color)
	local payload = {
		origin = origin,
		position = position,
		normal = normal,
		color = color,
	}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= shooter then effectRemote:FireClient(other, payload) end
	end
end


local function researchHit(player, result, damage)
	local researchBridge = ServerScriptService:FindFirstChild("GWAPHitBridge")
	if not researchBridge then return false end
	local ok, handled = pcall(function() return researchBridge:Invoke(player, result.Instance, damage) end)
	return ok and handled == true
end

local function bridgeHit(player, result, damage, instantHeadshot)
	if not result then return false end
	if researchHit(player, result, instantHeadshot and result.Instance.Name == "Head" and 1000 or damage) then return true end
	-- BindableFunction callbacks are write-only. LabEquipment binds this during
	-- server startup; pcall keeps a missing/failed optional bridge fail-closed.
	local ok, response = pcall(function()
		return hitBridge:Invoke(player, result.Instance, result.Position, result.Normal, damage,
			instantHeadshot and result.Instance.Name == "Head")
	end)
	return ok and response == true
end

local function genericDamage(player, result, config)
	local humanoid, model = findHumanoidFromHit(result.Instance)
	if not humanoid or humanoid.Health <= 0 or model == player.Character then return end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer and not config.allowPlayerDamage then return end

	local damage = config.damage
	if result.Instance.Name == "Head" then
		damage = config.instantHeadshot and math.max(1000, humanoid.MaxHealth) or damage * 2
	end
	humanoid:TakeDamage(damage)
end

local function validSequence(tool, sequence)
	if typeof(sequence) ~= "number" or sequence ~= sequence or sequence % 1 ~= 0 then return false end
	if sequence < 1 or sequence > 2147483647 then return false end
	local previous = lastSequenceByTool[tool]
	if previous and sequence <= previous then return false end
	lastSequenceByTool[tool] = sequence
	return true
end

local function handleFire(player, packet)
	if typeof(packet) ~= "table" or packet.version ~= 1 then return end
	if not Blaster.IsFiniteVector(packet.cameraOrigin) or not Blaster.IsFiniteVector(packet.direction) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local tool = packet.tool
	if not humanoid or not head or not root or humanoid.Health <= 0 then return end
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= character then return end
	if tool:GetAttribute("BlasterWeapon") ~= true and tool:GetAttribute("LabSidearm") ~= true then return end

	if (packet.cameraOrigin - head.Position).Magnitude > MAX_CAMERA_OFFSET then return end
	local directionMagnitude = packet.direction.Magnitude
	if directionMagnitude < 0.5 or directionMagnitude > 1.5 then return end
	local aimDirection = packet.direction.Unit
	if not validSequence(tool, packet.sequence) then return end

	local config = Blaster.GetWeaponConfig(tool)
	local now = os.clock()
	if now < (nextShotByPlayer[player] or 0) then return end
	nextShotByPlayer[player] = now + config.cooldown * RATE_TOLERANCE

	local params = Blaster.NewRaycastParams({character, tool})
	local handle = tool:FindFirstChild("Handle")
	local muzzleOrigin = handle and handle.Position or (head.Position + aimDirection * 0.5)
	local tracerColor = tool:GetAttribute("BlasterTracerColor")
	if typeof(tracerColor) ~= "Color3" then tracerColor = Color3.fromRGB(255, 226, 140) end

	for _ = 1, config.pellets do
		local pelletDirection = randomSpread(aimDirection, config.spread)
		local cameraResult = workspace:Raycast(packet.cameraOrigin, pelletDirection * config.range, params)
		local aimPoint = cameraResult and cameraResult.Position or (packet.cameraOrigin + pelletDirection * config.range)
		local muzzleDelta = aimPoint - muzzleOrigin
		local castDirection = muzzleDelta.Magnitude > 0.05 and muzzleDelta.Unit or pelletDirection
		local castLength = math.min(config.range, math.max(0.1, muzzleDelta.Magnitude + 0.25))
		local result = workspace:Raycast(muzzleOrigin, castDirection * castLength, params)
		local hitPosition = result and result.Position or (muzzleOrigin + castDirection * castLength)

		broadcastShot(player, muzzleOrigin, hitPosition, result and result.Normal or nil, tracerColor)
		if result then
			local handled = bridgeHit(player, result, config.damage, config.instantHeadshot)
			if not handled then genericDamage(player, result, config) end
		end
	end

	if config.selfCostPercent > 0 and humanoid.Health > 0 then
		humanoid:TakeDamage(humanoid.MaxHealth * config.selfCostPercent / 100)
	end
end

fireRemote.OnServerEvent:Connect(handleFire)
Players.PlayerRemoving:Connect(function(player)
	nextShotByPlayer[player] = nil
end)

print("ServerBlasterManager ready: camera shots are server-validated and obstacle-checked.")
	
	