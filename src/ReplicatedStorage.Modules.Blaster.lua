--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ReplicatedStorage.Modules.Blaster
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Shared casting
Future change: Preserve desktop screen conversion and mobile camera-forward behavior as separate tested paths.
Preserve dependencies: Controller reticle and server manager raycasts.
Acceptance cases: Mouse edges, asymmetric safe areas, near wall, long range, and invalid vectors.
This revision changes documentation only in this source; executable input/aiming behavior is preserved.
]========]
-- Blaster
-- Shared, device-independent camera casting and client shot presentation.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Blaster = {}

Blaster.REMOTE_FOLDER_NAME = "BlasterRemotes"
Blaster.FIRE_REMOTE_NAME = "Fire"
Blaster.EFFECT_REMOTE_NAME = "ReplicateShot"

local replicationConnection

local function finiteNumber(value)
	return typeof(value) == "number"
		and value == value
		and value > -1e7
		and value < 1e7
end

function Blaster.IsFiniteVector(value)
	return typeof(value) == "Vector3"
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

local function numberAttribute(tool, name, fallback, minimum, maximum)
	local value = tool and tool:GetAttribute(name)
	if not finiteNumber(value) then value = fallback end
	return math.clamp(value, minimum, maximum)
end

function Blaster.GetWeaponConfig(tool)
	return {
		damage = numberAttribute(tool, "BlasterDamage", 25, 0, 1000),
		range = numberAttribute(tool, "BlasterRange", 250, 8, 1000),
		cooldown = numberAttribute(tool, "BlasterCooldown", 0.35, 0.06, 10),
		pellets = math.floor(numberAttribute(tool, "BlasterPellets", 1, 1, 16)),
		spread = numberAttribute(tool, "BlasterSpread", 0, 0, 0.35),
		selfCostPercent = numberAttribute(tool, "BlasterSelfCostPercent", 0, 0, 25),
		adsFov = numberAttribute(tool, "BlasterADSFOV", 55, 25, 100),
		automatic = tool and tool:GetAttribute("BlasterAutomatic") == true or false,
		instantHeadshot = tool and tool:GetAttribute("BlasterInstantHeadshot") == true or false,
		allowPlayerDamage = tool and tool:GetAttribute("BlasterAllowPlayerDamage") == true or false,
	}
end

function Blaster.GetCameraRay(camera, maxRange, screenPoint)
	camera = camera or workspace.CurrentCamera
	if not camera then return nil end
	maxRange = math.clamp(tonumber(maxRange) or 500, 1, 2000)
	if typeof(screenPoint) == "Vector2" then
		-- Desktop points are expressed in CoreUISafeInsets screen space (the
		-- mouse location minus GuiService:GetGuiInset()). ScreenPointToRay is
		-- the matching inverse transform. ViewportPointToRay uses device-safe
		-- coordinates instead and produces a vertical offset on PC and in the
		-- phone simulator.
		local ray = camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
		if ray.Direction.Magnitude < 0.99 then return nil end
		return ray.Origin, ray.Direction.Unit, ray.Direction.Unit * maxRange
	end

	local direction = camera.CFrame.LookVector
	if direction.Magnitude < 0.99 then return nil end

	return camera.CFrame.Position, direction.Unit, direction.Unit * maxRange
end

function Blaster.NewRaycastParams(ignoreList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.IgnoreWater = true
	return params
end

function Blaster.CastFromCamera(camera, maxRange, ignoreList, screenPoint)
	local origin, unitDirection, castDirection = Blaster.GetCameraRay(camera, maxRange, screenPoint)
	if not origin then return nil end

	local result = workspace:Raycast(origin, castDirection, Blaster.NewRaycastParams(ignoreList))
	return {
		origin = origin,
		direction = unitDirection,
		result = result,
		position = result and result.Position or (origin + castDirection),
	}
end

-- Returns the exact centre-line solution used for both the live reticle and a
-- shot. The camera chooses the intended point; the muzzle ray then catches a
-- nearby wall or prop that physically blocks the weapon.
function Blaster.GetAimSolution(tool, camera, ignoreList, screenPoint)
	if not tool or not tool:IsA("Tool") then return nil end
	local config = Blaster.GetWeaponConfig(tool)
	local cast = Blaster.CastFromCamera(camera, config.range, ignoreList, screenPoint)
	if not cast then return nil end

	local handle = tool:FindFirstChild("Handle")
	local muzzleOrigin = handle and handle.Position or cast.origin
	local muzzleDelta = cast.position - muzzleOrigin
	local muzzleResult
	if muzzleDelta.Magnitude > 0.05 then
		-- Extend just beyond the camera hit point. Ending exactly on a surface can
		-- miss it because of floating-point/raycast endpoint precision.
		muzzleResult = workspace:Raycast(
			muzzleOrigin,
			muzzleDelta.Unit * (muzzleDelta.Magnitude + 0.25),
			Blaster.NewRaycastParams(ignoreList)
		)
	end

	return {
		cameraOrigin = cast.origin,
		direction = cast.direction,
		muzzleOrigin = muzzleOrigin,
		position = muzzleResult and muzzleResult.Position or cast.position,
		result = muzzleResult,
		cameraResult = cast.result,
	}
end

local function tracerColor(tool)
	local value = tool and tool:GetAttribute("BlasterTracerColor")
	return typeof(value) == "Color3" and value or Color3.fromRGB(255, 226, 140)
end

function Blaster.DrawTracer(origin, hitPosition, color, lifetime)
	if not Blaster.IsFiniteVector(origin) or not Blaster.IsFiniteVector(hitPosition) then return end
	local distance = (hitPosition - origin).Magnitude
	if distance < 0.05 then return end

	local beam = Instance.new("Part")
	beam.Name = "BlasterTracer"
	beam.Size = Vector3.new(0.055, 0.055, distance)
	beam.CFrame = CFrame.lookAt((origin + hitPosition) * 0.5, hitPosition)
	beam.Color = typeof(color) == "Color3" and color or Color3.fromRGB(255, 226, 140)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.08
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Parent = workspace
	Debris:AddItem(beam, lifetime or 0.075)
end

function Blaster.DrawImpact(position, normal, color, lifetime)
	if not Blaster.IsFiniteVector(position) or not Blaster.IsFiniteVector(normal) then return end

	local impact = Instance.new("Part")
	impact.Name = "BlasterImpact"
	impact.Shape = Enum.PartType.Ball
	impact.Size = Vector3.new(0.16, 0.16, 0.16)
	impact.Position = position + normal * 0.04
	impact.Color = typeof(color) == "Color3" and color or Color3.fromRGB(255, 226, 140)
	impact.Material = Enum.Material.Neon
	impact.Anchored = true
	impact.CanCollide = false
	impact.CanTouch = false
	impact.CanQuery = false
	impact.CastShadow = false
	impact.Parent = workspace
	Debris:AddItem(impact, lifetime or 0.65)
end

local function getRemotes(timeout)
	local folder = ReplicatedStorage:WaitForChild(Blaster.REMOTE_FOLDER_NAME, timeout or 10)
	if not folder then return nil end
	local fireRemote = folder:WaitForChild(Blaster.FIRE_REMOTE_NAME, timeout or 10)
	local effectRemote = folder:WaitForChild(Blaster.EFFECT_REMOTE_NAME, timeout or 10)
	return fireRemote, effectRemote
end

function Blaster.StartReplication()
	if not RunService:IsClient() or replicationConnection then return replicationConnection end
	local _, effectRemote = getRemotes(15)
	if not effectRemote or not effectRemote:IsA("RemoteEvent") then return nil end

	replicationConnection = effectRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		if not Blaster.IsFiniteVector(payload.origin) or not Blaster.IsFiniteVector(payload.position) then return end
		Blaster.DrawTracer(payload.origin, payload.position, payload.color, 0.075)
		if Blaster.IsFiniteVector(payload.normal) then
			Blaster.DrawImpact(payload.position, payload.normal, payload.color)
		end
	end)
	return replicationConnection
end

function Blaster.Fire(tool, camera, sequence, screenPoint)
	assert(RunService:IsClient(), "Blaster.Fire can only be called by a client")
	if not tool or not tool:IsA("Tool") then return nil end

	local player = game:GetService("Players").LocalPlayer
	local character = player and player.Character
	if not character or tool.Parent ~= character then return nil end

	local ignoreList = {character, tool, workspace.CurrentCamera}
	local solution = Blaster.GetAimSolution(tool, camera, ignoreList, screenPoint)
	if not solution then return nil end

	Blaster.DrawTracer(solution.muzzleOrigin, solution.position, tracerColor(tool), 0.11)
	if solution.result then
		Blaster.DrawImpact(solution.position, solution.result.Normal, tracerColor(tool), 0.8)
	end

	local fireRemote = getRemotes(10)
	if fireRemote and fireRemote:IsA("RemoteEvent") then
		fireRemote:FireServer({
			version = 1,
			tool = tool,
			cameraOrigin = solution.cameraOrigin,
			direction = solution.direction,
			sequence = sequence,
			clientTime = workspace:GetServerTimeNow(),
		})
	end

	return solution
end

return Blaster

