-- LoungeSystems: the hidden social floor. Nothing here touches lab gameplay.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService=game:GetService("TextService")
local noteCooldown={}

local L = workspace:WaitForChild("Lounge")
local hatch = workspace:WaitForChild("LoungeHatch")
local juke = L.DJ.Jukebox
local sound = juke:WaitForChild("JukeSound")
local npText = juke.NowPlaying.Frame.Text
local noteBody = L.MessageWall.Notes.Frame.Body

local ARRIVE = L.ArrivalPad.Position + Vector3.new(0, 4, 0)
local RETURN_TO = hatch.Position + Vector3.new(0, 5, 0)

--------------------------------------------------------------- travel
local function move(player, where, inLounge)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = CFrame.new(where)
	player:SetAttribute("InLounge", inLounge)
end

hatch.HatchPrompt.Triggered:Connect(function(player)
	move(player, ARRIVE, true)
end)
L.ExitPad.ExitPrompt.Triggered:Connect(function(player)
	move(player, RETURN_TO, false)
end)

-- if someone respawns while flagged, clear the flag
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		if p:GetAttribute("InLounge") then p:SetAttribute("InLounge", false) end
	end)
end)

--------------------------------------------------------------- jukebox
local queue, current, skips = {}, nil, {}

local function refreshPanel()
	local lines = {"JUKEBOX"}
	table.insert(lines, current and ("now playing: " .. current.name) or "nothing playing")
	table.insert(lines, "queued: " .. #queue)
	table.insert(lines, "")
	table.insert(lines, "say  /play <audio id>")
	table.insert(lines, "hold E to vote skip")
	npText.Text = table.concat(lines, "\n")
end

local function playNext()
	skips = {}
	local nxt = table.remove(queue, 1)
	if not nxt then
		current = nil
		sound:Stop()
		refreshPanel()
		return
	end
	current = nxt
	sound.SoundId = "rbxassetid://" .. nxt.id
	sound.TimePosition = 0
	sound:Play()
	refreshPanel()
end

sound.Ended:Connect(playNext)
sound.Stopped:Connect(function()
	if current and not sound.IsPlaying then
		task.wait(0.5)
		if not sound.IsPlaying then playNext() end
	end
end)

juke.JukePrompt.Triggered:Connect(function(player)
	if not current then return end
	skips[player.UserId] = true
	local n = 0
	for _ in pairs(skips) do n = n + 1 end
	local need = math.max(1, math.floor(#Players:GetPlayers() / 2))
	if n >= need then
		playNext()
	else
		npText.Text = string.format("JUKEBOX\nskip votes %d / %d", n, need)
		task.delay(2, refreshPanel)
	end
end)

--------------------------------------------------------------- the wall
local notes = {}
local function refreshWall()
	if #notes == 0 then noteBody.Text = "(no messages yet)" return end
	local lines = {}
	for i = #notes, math.max(1, #notes - 7), -1 do
		table.insert(lines, notes[i])
	end
	noteBody.Text = table.concat(lines, "\n")
end

--------------------------------------------------------------- chat commands
local function onChat(player, msg)
	if not player:GetAttribute("InLounge") then return end
	local lower = string.lower(msg)
	local id = string.match(lower, "^/play%s+(%d+)")
	if id then
		if #queue >= 12 then return end
		table.insert(queue, {id = id, name = player.Name .. "'s pick (" .. id .. ")"})
		if not current then playNext() else refreshPanel() end
		return
	end
	if lower == "/stop" then
		queue = {}; current = nil; sound:Stop(); refreshPanel(); return
	end
	local note = string.match(msg, "^/note%s+(.+)")
	if note then
        if os.clock()-(noteCooldown[player] or -math.huge)<3 then return end
        noteCooldown[player]=os.clock()
        note=string.sub(note,1,90)
        local ok,filtered=pcall(function()
            return TextService:FilterStringAsync(note,player.UserId):GetNonChatStringForBroadcastAsync()
        end)
        if not ok or not player.Parent or not player:GetAttribute('InLounge') then return end
        table.insert(notes,player.Name..":  "..filtered)
		if #notes > 40 then table.remove(notes, 1) end
		refreshWall()
	end
end

local function hook(player) player.Chatted:Connect(function(m) onChat(player, m) end) end
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

--------------------------------------------------------------- dance floor
local PALETTE = {
	Color3.fromRGB(255, 80, 120), Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 200, 90), Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(90, 255, 170),
}
task.spawn(function()
	local tiles = L.DanceFloor:GetChildren()
	local step = 0
	while true do
		step = step + 1
		local beat = sound.IsPlaying and 0.35 or 0.9
		for _, t in ipairs(tiles) do
			local r = t:GetAttribute("Row") or 0
			local c = t:GetAttribute("Col") or 0
			local idx = ((r + c + step) % #PALETTE) + 1
			TweenService:Create(t, TweenInfo.new(beat * 0.8), {Color = PALETTE[idx]}):Play()
		end
		task.wait(beat)
	end
end)

refreshPanel()
refreshWall()
print("[LoungeSystems] hidden lounge online")

Players.PlayerRemoving:Connect(function(player) noteCooldown[player]=nil;skips[player.UserId]=nil end)
