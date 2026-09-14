--[[
	Push every gameplay script in this place to tools/studio_sync_server.py.

	Run in Studio, EDIT mode, with the server already listening:
	    python tools/studio_sync_server.py

	Paste this into the Studio command bar (or a temporary Script) and run it.
	It only reads: nothing in the place is modified.

	HttpEnabled is turned on for the duration and restored afterwards, because
	Studio blocks HttpService by default and leaving it on is a footgun.
]]

local HttpService = game:GetService("HttpService")
local ENDPOINT = "http://127.0.0.1:8770"

-- Services worth capturing. Anything outside these is scenery or state, not source.
local SERVICES = {
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerScriptService"),
	game:GetService("ServerStorage"),
	game:GetService("StarterPlayer"),
	game:GetService("StarterGui"),
	game:GetService("StarterPack"),
	game:GetService("Workspace"),
}

-- Rollback snapshots and retired modules live in the DataModel alongside the
-- live code. They are history, not source: capturing them triples the file
-- count and puts superseded copies in the repository. Any path segment matching
-- one of these is skipped.
local IGNORE = {
	"^Before",          -- ServerStorage.BeforeAudit_20260913, BeforeBasementAndQuiz_...
	"_RETIRED",         -- ServerStorage.LabSpatial_RETIRED_revision4
	"_DISABLED",        -- Workspace.SeedLabGenerator_DISABLED_doNotEnable
	"_Before%w*_%d+",   -- BlasterController_BeforeMouseArmFix_20260912
}

local function isIgnored(path)
	for segment in string.gmatch(path, "[^.]+") do
		for _, pattern in ipairs(IGNORE) do
			if string.match(segment, pattern) then return true end
		end
	end
	return false
end

-- Dotted path from the service down, e.g. StarterPlayer.StarterPlayerScripts.LabHUD
local function dottedPath(inst)
	local parts = {}
	local node = inst
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

local previous = HttpService.HttpEnabled
HttpService.HttpEnabled = true

local sent, failed, skipped = 0, 0, 0
local ok, err = pcall(function()
	for _, service in ipairs(SERVICES) do
		for _, inst in ipairs(service:GetDescendants()) do
			if inst:IsA("LuaSourceContainer") then
				local path = dottedPath(inst)
				-- The receiver rejects anything that is not a plain dotted name,
				-- so filter here too and report it rather than fail silently.
				if isIgnored(path) then
					skipped += 1
				elseif not string.match(path, "^[A-Za-z0-9_.]+$") then
					skipped += 1
					warn("[capture] skipped, name has unusual characters: " .. path)
				else
					local body = HttpService:JSONEncode({path = path, source = inst.Source})
					local posted = pcall(function()
						HttpService:PostAsync(ENDPOINT .. "/script", body, Enum.HttpContentType.ApplicationJson)
					end)
					if posted then sent += 1 else failed += 1; warn("[capture] failed: " .. path) end
				end
			end
		end
	end
	pcall(function() HttpService:GetAsync(ENDPOINT .. "/done", true) end)
end)

HttpService.HttpEnabled = previous

if not ok then
	warn("[capture] aborted: " .. tostring(err))
else
	print(string.format("[capture] sent %d script(s), %d failed, %d skipped", sent, failed, skipped))
end
