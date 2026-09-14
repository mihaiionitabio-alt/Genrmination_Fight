--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.LabElevators
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Elevator compatibility script
Future change: Treat as dormant unless real tagged elevator geometry exists. Do not claim elevator transport from script presence alone.
Preserve dependencies: Level metadata and any future lift models.
Acceptance cases: Door interlock, floor alignment, queueing, interrupted travel, and stair fallback.
]========]
-- LabElevators : moving cars that carry whoever is standing inside.
-- An anchored part does not drag a character with it, so the car
-- offsets every occupant by the same delta on each step.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local SPEED = 45   -- studs per second

local function setGate(gate, open)
	gate.CanCollide = not open
	gate.Transparency = open and 0.85 or 0
end

local function setup(model)
	local floorCount = model:GetAttribute("FloorCount")
	if not floorCount then return end

	local car = model:WaitForChild("Car")
	local platform = car:FindFirstChild("Platform") or car:FindFirstChild("Platform_1")
	if not platform then
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:match("^Platform") then platform = d break end
		end
	end
	if not platform then return end

	local gates = {}
	for _, g in ipairs(model:WaitForChild("Gates"):GetChildren()) do
		gates[g:GetAttribute("Floor")] = g
	end

	local ys = {}
	for i = 1, floorCount do ys[i] = model:GetAttribute("FloorY_" .. i) end

	local current, moving = 1, false
	for i, g in pairs(gates) do setGate(g, i == current) end

	local carParts = {}
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(carParts, d) end
	end

	local function occupants()
		local list = {}
		local half = platform.Size * 0.5
		local top = platform.Position.Y + half.Y
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = hrp.Position - platform.Position
				if math.abs(d.X) <= half.X + 2 and math.abs(d.Z) <= half.Z + 2
					and hrp.Position.Y > top - 2 and hrp.Position.Y < top + 24 then
					table.insert(list, hrp)
				end
			end
		end
		return list
	end

	local function moveTo(target)
		if moving or target == current or not ys[target] then return end
		moving = true
		setGate(gates[current], false)

		local startY = platform.Position.Y
		local goalY  = startY + (ys[target] - ys[current])
		local dist = math.abs(goalY - startY)
		local dur = math.max(0.4, dist / SPEED)
		local t0 = os.clock()
		local lastY = startY

		while true do
			local a = math.min(1, (os.clock() - t0) / dur)
			local newY = startY + (goalY - startY) * a
			local dy = newY - lastY
			if dy ~= 0 then
				local riders = occupants()
				for _, p in ipairs(carParts) do
					p.CFrame = p.CFrame + Vector3.new(0, dy, 0)
				end
				for _, hrp in ipairs(riders) do
					hrp.CFrame = hrp.CFrame + Vector3.new(0, dy, 0)
				end
				lastY = newY
			end
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end

		current = target
		model:SetAttribute("CurrentFloor", current)
		setGate(gates[current], true)
		moving = false
	end

	local function addPrompt(part, floor, label, text)
		local p = Instance.new("ProximityPrompt")
		p.ObjectText = label
		p.ActionText = text
		p.HoldDuration = 0.15
		p.MaxActivationDistance = 22
		p.RequiresLineOfSight = false
		p.Parent = part
		p.Triggered:Connect(function() moveTo(floor) end)
	end

	for _, panel in ipairs(model:WaitForChild("CallPanels"):GetChildren()) do
		addPrompt(panel, panel:GetAttribute("Floor"), "Elevator", "Call")
	end
	for _, btn in ipairs(car:WaitForChild("Buttons"):GetChildren()) do
		local i = btn:GetAttribute("Floor")
		addPrompt(btn, i, "Elevator", "Go to floor " .. (model:GetAttribute("FloorLabel_" .. i) or i))
	end
end

for _, m in ipairs(CollectionService:GetTagged("Elevator")) do setup(m) end
CollectionService:GetInstanceAddedSignal("Elevator"):Connect(setup)

print("Elevators armed: " .. #CollectionService:GetTagged("Elevator") .. ".")
