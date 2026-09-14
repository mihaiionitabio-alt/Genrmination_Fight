--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.LabRound
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Round lifecycle
Future change: Make reset ordering explicit with one round transition contract and subsystem callbacks.
Preserve dependencies: Points, fractional debt, carrier termination, research repair, plot clearing.
Acceptance cases: Join during break, end during processing, disconnected winner, and reset after destruction.
]========]
-- LabRound: round timer, scoring cycle and end-of-round resolution.
-- Round length is COMPUTED from the built environment, not hard-coded.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local INTERMISSION = 20

local function computeRoundSeconds()
	local eq = CollectionService:GetTagged("LabEquipment")
	local pts = {}
	for _, e in ipairs(eq) do
		local ok, p = pcall(function() return e:GetPivot().Position end)
		if ok then table.insert(pts, p) end
	end
	if #pts < 2 then return 480, 0, 0 end
	local n, sum, samples = #pts, 0, 2000
	for _ = 1, samples do
		sum = sum + (pts[math.random(n)] - pts[math.random(n)]).Magnitude
	end
	local mean = sum / samples
	local WALK_SPEED   = 16   -- studs/sec, Roblox default
	local ROUTE_FACTOR = 1.5  -- corridors/doors vs straight line
	local VERTICAL     = 2.5  -- averaged elevator/stair cost
	local ACTION       = 4.0  -- HOLD R repair / E transfer
	local TARGET_TASKS = 25   -- tasks a competent player should fit in a round
	local perTask = (mean / WALK_SPEED) * ROUTE_FACTOR + VERTICAL + ACTION
	local secs = math.floor((perTask * TARGET_TASKS) / 30 + 0.5) * 30
	return math.clamp(secs, 300, 900), mean, perTask
end

local ROUND_SECONDS, meanDist, perTask = computeRoundSeconds()
print(string.format(
	"[LabRound] units=%d meanDist=%.0f studs perTask=%.1fs -> round=%ds (%.1f min)",
	#CollectionService:GetTagged("LabEquipment"), meanDist, perTask, ROUND_SECONDS, ROUND_SECONDS / 60))

workspace:SetAttribute("RoundLength", ROUND_SECONDS)

local function pointsOf(player)
	local stats = player:FindFirstChild("leaderstats")
	local p = stats and stats:FindFirstChild("Points")
	return p and p.Value or 0, p
end

local function resetScores()
	for _, player in ipairs(Players:GetPlayers()) do
		local _, p = pointsOf(player)
		if p then p.Value = 0 end
		player:SetAttribute("RoundStreakBest", 0)
	end
end

local function resolveRound()
	local best, bestScore = nil, -1
	for _, player in ipairs(Players:GetPlayers()) do
		local v = pointsOf(player)
		if v > bestScore then best, bestScore = player, v end
		local pb = player:GetAttribute("PersonalBest") or 0
		if v > pb then player:SetAttribute("PersonalBest", v) end
		player:SetAttribute("LastRoundScore", v)
	end
	workspace:SetAttribute("LastWinnerName", best and best.Name or "")
	workspace:SetAttribute("LastWinnerScore", bestScore > 0 and bestScore or 0)
end

task.spawn(function()
	local round = 0
	while true do
		round += 1
		resetScores()
		workspace:SetAttribute("RoundNumber", round)
		workspace:SetAttribute("RoundPhase", "PLAY")
		workspace:SetAttribute("RoundEndsAt", os.time() + ROUND_SECONDS)
		task.wait(ROUND_SECONDS)

		resolveRound()
		workspace:SetAttribute("RoundPhase", "BREAK")
		workspace:SetAttribute("RoundEndsAt", os.time() + INTERMISSION)
		task.wait(INTERMISSION)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("PersonalBest", 0)
end)
