--=====================================================================
-- LABORATORY COMPLEX -- PROCEDURAL BUILDING GENERATOR
-- Basement + 3 upper floors + roof.
-- Rooms are numbered. Equipment is generated from a catalogue of
-- basic laboratory items and packed against the walls automatically.
-- Vertical circulation: one stair tower + three working elevators.
--
-- HOW TO USE
--   Roblox Studio -> View -> Command Bar -> paste -> Enter.
--   Edit-mode Command Bar use installs the permanent runtime scripts.
--   Running from a server Script during Play also works for that session
--   through the built-in live fallback near the end of this file.
--=====================================================================

local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local Lighting            = game:GetService("Lighting")
local RunService          = game:GetService("RunService")
local StarterPlayer       = game:GetService("StarterPlayer")

--------------------------------------------------------------------
-- SCALE
--------------------------------------------------------------------
local STUD         = 28    -- cm per stud at 1:1
-- The building's footprint (SCALE) is independent of equipment size
-- (FIT_SCALE below): equipment is always drawn at its literal real-world
-- size, and only the ROOM PLAN gets stretched by SCALE before converting
-- to studs. So a bigger SCALE spreads the same fixed-size equipment
-- further apart -- exactly how you make a floor feel roomier instead of
-- crowded, without equipment growing at all.
local SCALE        = 3.6   -- horizontal size of the plan vs. true 1:1 (3x the previous pass)
local HEIGHT_SCALE = 1.4   -- vertical size vs. true 1:1 -- kept modest on purpose: this is what
                            -- was making the building read as an 8-story warehouse before, and
                            -- fixing "crowded" doesn't need taller ceilings, just more floor room
-- Equipment stays at TRUE (1:1) human scale regardless of how big the
-- rooms are blown up, so a balance or a fridge reads as roughly the
-- size it should be next to a normal-sized player -- not a giant box.
local FIT_SCALE    = 1
local FIT_HEIGHT   = 1

--------------------------------------------------------------------
-- PLAN DIMENSIONS (centimetres)
--------------------------------------------------------------------
local WALL_H   = 300
local SLAB     = 25
local F2F      = WALL_H + SLAB
local EXT_T    = 30
local INT_T    = 16
local DOOR_W   = 90
local DOOR_H   = 210
local WIDE_W   = 150     -- double doors
local WIN_SILL = 90
local WIN_HEAD = 220

local COUNTER_H = 90     -- equipment cm
-- Overall footprint and corridor position follow the reference floor
-- plans (one long room down the west side, individually-doored rooms
-- off a corridor to the east): roughly 12.8 m x 20.8 m per floor.
local W, L      = 1280, 2080
local CORR_X1, CORR_X2 = 500, 720

local RNG_SEED = 20260907

--------------------------------------------------------------------
-- LIGHTING
--------------------------------------------------------------------
local BUILD_LIGHTS     = true
local LIGHT_SPACING    = 40    -- in studs, against the now-true-scale building
local LIGHT_RANGE      = 16    -- was tuned for a 24x-oversized building; way too
                                -- big now, which is most of why everything blew out white
local LIGHT_BRIGHTNESS = 0.6
local CONFIGURE_LIGHTING = true

--------------------------------------------------------------------
local C = {
	slab     = Color3.fromRGB(224, 227, 226),
	basement = Color3.fromRGB(120, 122, 125),
	ext      = Color3.fromRGB(232, 232, 228),
	int      = Color3.fromRGB(244, 244, 246),
	corridor = Color3.fromRGB(226, 231, 236),
	basewall = Color3.fromRGB(105, 110, 116),
	pillar   = Color3.fromRGB(88, 92, 96),
	stair    = Color3.fromRGB(168, 170, 172),
	roof     = Color3.fromRGB(148, 150, 152),
	glass    = Color3.fromRGB(180, 214, 230),
	door     = Color3.fromRGB(120, 132, 146),
	shaft    = Color3.fromRGB(150, 154, 160),
	car      = Color3.fromRGB(206, 210, 214),
}

-- Stop a previous play-test runtime before creating replacement tagged
-- objects. Otherwise its CollectionService listeners can bind the new
-- equipment, then disappear when replaced, leaving dead interaction prompts.
for _, runtimeName in ipairs({"LabEquipment", "LabElevators", "LabRoles", "LabWorkflow", "SeedLabWorkflow", "ServerBlasterManager"}) do
	local previous = ServerScriptService:FindFirstChild(runtimeName)
	if previous then previous:Destroy() end
end
for _, runtimeName in ipairs({"LabKinds", "LabFlow", "ISTA_Flow", "LabMathQuiz"}) do
	local previous = ReplicatedStorage:FindFirstChild(runtimeName)
	if previous then previous:Destroy() end
end
local previousModules = ReplicatedStorage:FindFirstChild("Modules")
if previousModules and previousModules:IsA("Folder") then
	for _, moduleName in ipairs({"Blaster", "BlasterController"}) do
		local previous = previousModules:FindFirstChild(moduleName)
		if previous then previous:Destroy() end
	end
end
for _, clientName in ipairs({"LabQuizClient", "LabSidearmClient", "LabHUD"}) do
	local previousClient = StarterPlayer.StarterPlayerScripts:FindFirstChild(clientName)
	if previousClient then previousClient:Destroy() end
end

-- Work that this generator does NOT own but which lives inside
-- Laboratory_Complex is carried across a rebuild instead of being wiped
-- with it. Rebuilding used to destroy the whole model outright, which
-- silently took hand-built content -- the site exterior and the office
-- fit-out -- with it every single time the generator was re-run.
-- Anything listed here, or any child carrying a PreserveOnRebuild
-- attribute, is detached first and re-attached to the fresh model.
-- SiteWorks and OfficeFitout used to be carried across a rebuild. They were
-- built for an earlier, differently-sized building, and measured against the
-- current one they no longer fit: NONE of the 5,541 office parts landed inside
-- the building footprint, and the exterior ran straight through the corridors.
-- Neither a translation nor a rotation lines them up (the room layout changed
-- between the two builds), so they are regenerated from the current W and L
-- instead. Carrying the old geometry would only reintroduce the overlap.
local SUPERSEDED_ON_REBUILD = {
	SiteWorks = true,
	OfficeFitout = true,
}

local PRESERVE_ON_REBUILD = {
	-- add hand-built folder names here to carry them across a rebuild
}

local old = Workspace:FindFirstChild("Laboratory_Complex")
local preserved = {}
if old then
	for _, child in ipairs(old:GetChildren()) do
		if SUPERSEDED_ON_REBUILD[child.Name] then
			child:Destroy()   -- old geometry for a building that no longer exists
		elseif PRESERVE_ON_REBUILD[child.Name] or child:GetAttribute("PreserveOnRebuild") then
			child.Parent = Workspace          -- park it outside the model being destroyed
			table.insert(preserved, child)
		end
	end
	old:Destroy()
end

local root = Instance.new("Model")
root.Name = "Laboratory_Complex"
root.Parent = Workspace

for _, child in ipairs(preserved) do
	child:SetAttribute("PreserveOnRebuild", true)   -- so it survives every later rebuild too
	child.Parent = root
end
if #preserved > 0 then
	print("Carried " .. #preserved .. " hand-built folder(s) across the rebuild.")
end

--------------------------------------------------------------------
-- UNITS
--------------------------------------------------------------------
local function X(v)  return v * SCALE / STUD end        -- plan cm -> studs, horizontal
local function Y(v)  return v * HEIGHT_SCALE / STUD end -- plan cm -> studs, vertical
local function E(v)  return v * FIT_SCALE / STUD end    -- fit cm  -> studs, horizontal
local function EH(v) return v * FIT_HEIGHT / STUD end   -- fit cm  -> studs, vertical
local function P(v)  return v * FIT_SCALE / SCALE end   -- fit cm  -> plan cm

--------------------------------------------------------------------
-- DETERMINISTIC RANDOM (so a rebuild gives the same layout)
--------------------------------------------------------------------
local function newRng(seed)
	local s = seed % 2147483647
	if s <= 0 then s = s + 2147483646 end
	local r = {}
	function r.next() s = (s * 16807) % 2147483647; return s / 2147483647 end
	function r.int(a, b) return a + math.floor(r.next() * (b - a + 1)) end
	function r.pick(t) return t[r.int(1, #t)] end
	function r.chance(p) return r.next() < p end
	return r
end

--------------------------------------------------------------------
-- PRIMITIVES
--------------------------------------------------------------------
local function newPart(name, size, cframe, colour, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = colour or C.int
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or root
	return p
end

local function slab(parent, name, x1, z1, x2, z2, topY, thickness, colour, material)
	thickness = thickness or SLAB
	return newPart(name,
		Vector3.new(X(math.abs(x2 - x1)), Y(thickness), X(math.abs(z2 - z1))),
		CFrame.new(X((x1 + x2) / 2), Y(topY - thickness / 2), X((z1 + z2) / 2)),
		colour or C.slab, material or Enum.Material.Concrete, parent)
end

--------------------------------------------------------------------
-- WALLS WITH OPENINGS
--------------------------------------------------------------------
local function wall(parent, name, x1, z1, x2, z2, thickness, baseY, height, openings, colour, material)
	height = height or WALL_H
	local alongX = (z1 == z2)
	local len = alongX and math.abs(x2 - x1) or math.abs(z2 - z1)
	local sgn = alongX and (x2 >= x1 and 1 or -1) or (z2 >= z1 and 1 or -1)
	local n = 0

	local function seg(s, e, y0, y1)
		if e - s < 0.5 or y1 - y0 < 0.5 then return end
		n = n + 1
		local mid = (s + e) / 2
		local px = alongX and (x1 + sgn * mid) or x1
		local pz = alongX and z1 or (z1 + sgn * mid)
		local size = alongX
			and Vector3.new(X(e - s), Y(y1 - y0), X(thickness))
			or  Vector3.new(X(thickness), Y(y1 - y0), X(e - s))
		newPart(name .. "_" .. n, size,
			CFrame.new(X(px), Y(baseY + (y0 + y1) / 2), X(pz)),
			colour or C.int, material or Enum.Material.Plaster, parent)
	end

	local ops = {}
	for _, o in ipairs(openings or {}) do
		table.insert(ops, {at = o.at, width = o.width, sill = o.sill or 0,
			head = o.head or DOOR_H, glass = o.glass, leaf = o.leaf, mainEntrance = o.mainEntrance})
	end
	table.sort(ops, function(a, b) return a.at < b.at end)

	local cursor = 0
	for _, o in ipairs(ops) do
		local a, b = math.max(cursor, 0, o.at), math.min(len, o.at + o.width)
		if b <= a then continue end -- Never create backwards/zero-width reveals.
		if a > cursor then seg(cursor, a, 0, height) end
		if o.sill > 0 then seg(a, b, 0, o.sill) end
		if o.head < height then seg(a, b, o.head, height) end

		local mid = (a + b) / 2
		local px = alongX and (x1 + sgn * mid) or x1
		local pz = alongX and z1 or (z1 + sgn * mid)

		if o.glass then
			local size = alongX
				and Vector3.new(X(b - a), Y(o.head - o.sill), X(4))
				or  Vector3.new(X(4), Y(o.head - o.sill), X(b - a))
			local g = newPart(name .. "_glass" .. n, size,
				CFrame.new(X(px), Y(baseY + (o.sill + o.head) / 2), X(pz)),
				C.glass, Enum.Material.Glass, parent)
			g.Transparency = 0.55
			g:SetAttribute("BreakableWindow", true)
			CollectionService:AddTag(g, "LabBreakableWindow")
		elseif o.leaf then
			-- The surrounding structural wall already frames the door; no freestanding leaves.

			-- The actual functional door: a solid panel filling the opening
			-- itself. It starts closed (CanCollide true) and is tagged
			-- AutoDoor so the runtime slides it up into the header void when
			-- a player approaches, and back down once they've passed through.
			local doorHeight = math.max(o.head - o.sill - 6, 20)
			local doorThickness = math.max(thickness * 0.6, 5)
			local doorSize
			if alongX then
				doorSize = Vector3.new(X(b - a - 6), Y(doorHeight), X(doorThickness))
			else
				doorSize = Vector3.new(X(doorThickness), Y(doorHeight), X(b - a - 6))
			end
			local closedY = Y(baseY + o.sill + doorHeight / 2 + 3)
			-- Automatic doors get their own industrial blue/metal look (never
			-- the same colour/material as the wall or the decorative casing)
			-- plus black-and-yellow hazard striping along the leading edge and
			-- an "AUTOMATIC DOOR" surface label, so they read as a functional
			-- door rather than a wall panel even before they start moving.
			local autoDoor = newPart(name .. "_autodoor" .. n, doorSize,
				CFrame.new(X(px), closedY, X(pz)), Color3.fromRGB(58, 104, 158), Enum.Material.Metal, parent)
			autoDoor.CanCollide = true
			autoDoor:SetAttribute("MainEntrance", o.mainEntrance == true)
			-- Doors slide sideways into the wall pocket beside the opening
			-- (left-to-right along the wall's own run), not up/down -- a
			-- vertical slide read as flicker when it snapped through the
			-- header void. The slide distance is the door's own width so it
			-- tucks fully out of the opening.
			-- IMPORTANT: these are stored in STUDS (via X()), matching the
			-- part's actual CFrame units -- storing raw plan-cm values here
			-- (as an earlier pass did) made the door's "closed"/"open"
			-- targets read as almost-zero stud offsets, so the proximity
			-- check never found a player "close enough" and the door never
			-- moved at all.
			autoDoor:SetAttribute("DoorAxis", alongX and "X" or "Z")
			local closedXStud, closedZStud = X(px), X(pz)
			autoDoor:SetAttribute("DoorClosedX", closedXStud)
			autoDoor:SetAttribute("DoorClosedZ", closedZStud)
			local slideDistStud = X(b - a) * 0.96
			if alongX then
				autoDoor:SetAttribute("DoorOpenX", closedXStud + slideDistStud)
				autoDoor:SetAttribute("DoorOpenZ", closedZStud)
			else
				autoDoor:SetAttribute("DoorOpenX", closedXStud)
				autoDoor:SetAttribute("DoorOpenZ", closedZStud + slideDistStud)
			end
			autoDoor:SetAttribute("DoorY", closedY)
			autoDoor:SetAttribute("DoorOpen", false)
			CollectionService:AddTag(autoDoor, "AutoDoor")

			-- Hazard stripes, the "AUTOMATIC DOOR" label, and the open/closed
			-- indicator light are all drawn as SurfaceGui elements parented to
			-- the door part itself (rather than separate 3D parts), so they
			-- track the door perfectly when the runtime tweens it open/closed.
			local labelFaces = alongX and {Enum.NormalId.Front, Enum.NormalId.Back}
				or {Enum.NormalId.Left, Enum.NormalId.Right}
			for _, normal in ipairs(labelFaces) do
				local labelGui = Instance.new("SurfaceGui")
				labelGui.Name = "AutoDoorLabel"
				labelGui.Face = normal
				labelGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				labelGui.PixelsPerStud = 60
				labelGui.AlwaysOnTop = false
				labelGui.Parent = autoDoor

				local topStripe = Instance.new("Frame")
				topStripe.Name = "HazardStripeTop"
				topStripe.Size = UDim2.new(1, 0, 0.07, 0)
				topStripe.Position = UDim2.new(0, 0, 0, 0)
				topStripe.BackgroundColor3 = Color3.fromRGB(235, 195, 35)
				topStripe.BorderSizePixel = 0
				topStripe.Parent = labelGui
				local bottomStripe = topStripe:Clone()
				bottomStripe.Name = "HazardStripeBottom"
				bottomStripe.Position = UDim2.new(0, 0, 0.93, 0)
				bottomStripe.Parent = labelGui

				local labelText = Instance.new("TextLabel")
				labelText.Name = "Caption"
				labelText.Size = UDim2.new(0.86, 0, 0.24, 0)
				labelText.Position = UDim2.new(0.07, 0, 0.13, 0)
				labelText.BackgroundColor3 = Color3.fromRGB(235, 195, 35)
				labelText.BackgroundTransparency = 0.05
				labelText.BorderSizePixel = 0
				labelText.Text = o.mainEntrance and "ENTRANCE" or "AUTOMATIC DOOR"
				labelText.TextColor3 = Color3.fromRGB(20, 20, 20)
				labelText.TextScaled = true
				labelText.Font = Enum.Font.SourceSansBold
				labelText.Parent = labelGui

				local indicator = Instance.new("Frame")
				indicator.Name = "DoorIndicator"
				indicator.Size = UDim2.new(0.16, 0, 0.06, 0)
				indicator.Position = UDim2.new(0.42, 0, 0.42, 0)
				indicator.BackgroundColor3 = Color3.fromRGB(210, 40, 40)
				indicator.BorderSizePixel = 0
				indicator.Parent = labelGui
			end
		end
		cursor = math.max(cursor, b)
	end
	if cursor < len then seg(cursor, len, 0, height) end
end

--------------------------------------------------------------------
-- ROOM SCHEDULE -- numbered rooms
--
-- Matches the shape of the reference floor plans: one long room runs
-- the full length of the west side, and a cluster of individually
-- doored rooms line the east side of a central corridor. Room COUNT
-- varies by level, following the reference drawings: 10 on the ground
-- floor, 9 on the (identical) upper floors, 8 in the basement.
--------------------------------------------------------------------

-- Build the room list with every opening it owns.
--   namePrefix  - nil for "Room 1".."Room N", or e.g. "B" for basement
--                 "Room B1".."Room BN"
--   rightCount  - how many individually-doored rooms line the east side
--   hasExterior - false suppresses exterior windows/exit doors (basement)
local function buildRoomSchedule(namePrefix, rightCount, hasExterior)
	if hasExterior == nil then hasExterior = true end
	local rooms, n = {}, 0

	local function add(sideOfPlan, x1, x2, band)
		n = n + 1
		local label = namePrefix and (namePrefix .. n) or tostring(n)
		local r = {
			number = n, name = "Room " .. label, plan = sideOfPlan,
			x1 = x1, x2 = x2, z1 = band[1], z2 = band[2],
			open = {N = {}, S = {}, E = {}, W = {}},
		}
		rooms[n] = r
		return r
	end

	add("L", 0, CORR_X1, {0, L})
	local firstRight = n + 1
	for i = 1, rightCount do
		add("R", CORR_X2, W, {L * (i - 1) / rightCount, L * i / rightCount})
	end

	-- doors
	for _, r in ipairs(rooms) do
		local depth = r.z2 - r.z1
		local corridorSide = (r.plan == "L") and "E" or "W"

		-- corridor doors: one, or two for a deep room
		if depth <= 300 then
			table.insert(r.open[corridorSide], {at = depth / 2 - DOOR_W / 2, width = DOOR_W, leaf = true})
		else
			table.insert(r.open[corridorSide], {at = depth * 0.28 - DOOR_W / 2, width = DOOR_W, leaf = true})
			table.insert(r.open[corridorSide], {at = depth * 0.72 - WIDE_W / 2, width = WIDE_W, leaf = true})
		end

		-- exterior wall: windows, plus an exit door on the deeper rooms
		-- (skipped below grade, in the basement)
		if hasExterior then
			local extSide = (r.plan == "L") and "W" or "E"
			if depth >= 300 then
				table.insert(r.open[extSide], {at = depth * 0.12 - DOOR_W / 2, width = DOOR_W, sill = 20, head = 230, glass = true})
				table.insert(r.open[extSide], {at = depth * 0.45 - 90, width = 180, sill = WIN_SILL, head = WIN_HEAD, glass = true})
				table.insert(r.open[extSide], {at = depth * 0.78 - 90, width = 180, sill = WIN_SILL, head = WIN_HEAD, glass = true})
			else
				table.insert(r.open[extSide], {at = depth * 0.5 - 55, width = 110, sill = WIN_SILL, head = WIN_HEAD, glass = true})
			end
		end
		r.extDoorDepth = depth
	end

	-- interconnecting doors between consecutive east-side rooms
	-- (the west side is a single room, so it needs none)
	local function link(a, b)
		local at = (a.x2 - a.x1) * 0.32 - DOOR_W / 2
		local op = {at = at, width = DOOR_W, leaf = true}
		table.insert(a.open.S, op)
		table.insert(b.open.N, {at = at, width = DOOR_W, leaf = true})
	end
	for i = firstRight, n - 1 do link(rooms[i], rooms[i + 1]) end

	-- The building shell defines its north/south doors and windows separately
	-- from the room schedule. Copy those openings into the rooms that touch
	-- each end wall so wall packing can never put a cabinet across one.
	if hasExterior then
		local northOpenings = {
			{at = CORR_X1 + 20, width = 160},
			{at = W * 0.12, width = 140, glass = true},
			{at = W * 0.77, width = 140, glass = true},
		}
		local southOpenings = {
			{at = CORR_X1 + 25, width = WIDE_W},
			{at = W * 0.12, width = 90},
			{at = W * 0.20, width = 150, glass = true},
			{at = W * 0.50, width = 150, glass = true},
			{at = W * 0.80, width = 90},
		}
		local function copyEndOpenings(room, side, openings)
			for _, opening in ipairs(openings) do
				local left = math.max(room.x1, opening.at)
				local right = math.min(room.x2, opening.at + opening.width)
				if right > left then
					table.insert(room.open[side], {
						at = left - room.x1,
						width = right - left,
						glass = opening.glass,
					})
				end
			end
		end
		for _, room in ipairs(rooms) do
			if room.z1 == 0 then copyEndOpenings(room, "N", northOpenings) end
			if room.z2 == L then copyEndOpenings(room, "S", southOpenings) end
		end
	end

	return rooms, firstRight
end

local GROUND_ROOMS   = buildRoomSchedule(nil, 9, true)   -- "Plan parter": 10 rooms
local TYPICAL_ROOMS  = buildRoomSchedule(nil, 8, true)   -- "Plan etaj": 9 rooms, reused on floors 2 and 3
local BASEMENT_ROOMS = buildRoomSchedule("B", 7, false)  -- "Plan demisol": 8 rooms, no exterior windows

--------------------------------------------------------------------
-- SIGNAGE AND LIGHT
--------------------------------------------------------------------
local function sign(parent, text, xcm, zcm, baseY, px, maxDist)
	local a = newPart("Sign", Vector3.new(1, 1, 1),
		CFrame.new(X(xcm), Y(baseY + WALL_H * 0.72), X(zcm)), C.int, Enum.Material.SmoothPlastic, parent)
	a.Transparency = 1
	a.CanCollide = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, px or 300, 0, (px or 300) * 0.32)
	-- World labels only appear when the player is close. Long-range,
	-- always-on-top labels stack over one another in a furnished room.
	bb.MaxDistance = math.min(maxDist or 18, 22)
	bb.AlwaysOnTop = false
	bb.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = Color3.fromRGB(35, 40, 48)
	t.TextStrokeTransparency = 0.55
	t.TextStrokeColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = bb
	return a
end

-- A stationary lab-staff mannequin, built from primitive parts at true
-- human scale (independent of the building's SCALE/HEIGHT_SCALE, same
-- as equipment) so it always reads as a person standing in the room.
-- Tagged "LabNPC" for the runtime script to arm with a "Talk" prompt.
local function buildNPC(parent, npcName, role, xcm, zcm, y0, badgeColour, tips)
	-- Medical/lab-coat outfit: white coat and trousers for every NPC,
	-- with a small coloured badge and a red cross on the chest so it
	-- reads as clinical/lab staff rather than a random passer-by.
	local skin = Color3.fromRGB(224, 189, 154)
	local coat = Color3.fromRGB(246, 247, 249)
	local trouser = Color3.fromRGB(210, 213, 217)
	local baseY = Y(y0)

	local legL = newPart(npcName .. "_LegL", Vector3.new(0.8, 2.3, 0.8),
		CFrame.new(X(xcm) - 0.42, baseY + 1.15, X(zcm)), trouser, Enum.Material.Fabric, parent)
	local legR = newPart(npcName .. "_LegR", Vector3.new(0.8, 2.3, 0.8),
		CFrame.new(X(xcm) + 0.42, baseY + 1.15, X(zcm)), trouser, Enum.Material.Fabric, parent)
	local torso = newPart(npcName .. "_Torso", Vector3.new(2, 2.1, 1.1),
		CFrame.new(X(xcm), baseY + 3.35, X(zcm)), coat, Enum.Material.Fabric, parent)
	local armL = newPart(npcName .. "_ArmL", Vector3.new(0.65, 2, 0.65),
		CFrame.new(X(xcm) - 1.35, baseY + 3.3, X(zcm)), coat, Enum.Material.Fabric, parent)
	local armR = newPart(npcName .. "_ArmR", Vector3.new(0.65, 2, 0.65),
		CFrame.new(X(xcm) + 1.35, baseY + 3.3, X(zcm)), coat, Enum.Material.Fabric, parent)
	local head = newPart(npcName .. "_Head", Vector3.new(1.25, 1.25, 1.25),
		CFrame.new(X(xcm), baseY + 4.95, X(zcm)), skin, Enum.Material.SmoothPlastic, parent)
	head.Shape = Enum.PartType.Ball

	-- badge (role colour) and a small red cross, both worn on the chest
	local badge = newPart(npcName .. "_Badge", Vector3.new(0.32, 0.42, 0.06),
		CFrame.new(X(xcm) - 0.55, baseY + 3.55, X(zcm) - 0.58), badgeColour, Enum.Material.SmoothPlastic, parent)
	local crossV = newPart(npcName .. "_CrossV", Vector3.new(0.1, 0.32, 0.06),
		CFrame.new(X(xcm) + 0.4, baseY + 3.45, X(zcm) - 0.58), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic, parent)
	local crossH = newPart(npcName .. "_CrossH", Vector3.new(0.32, 0.1, 0.06),
		CFrame.new(X(xcm) + 0.4, baseY + 3.45, X(zcm) - 0.58), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic, parent)

	for _, p in ipairs({legL, legR, torso, armL, armR, head, badge, crossV, crossH}) do
		p.CanCollide = false
		p.CastShadow = true
	end

	CollectionService:AddTag(torso, "LabNPC")
	torso:SetAttribute("NPCName", npcName)
	torso:SetAttribute("Role", role)
	torso:SetAttribute("Tips", table.concat(tips, "|"))

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 170, 0, 40)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = 14
	bb.AlwaysOnTop = false
	bb.Parent = torso
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.4
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = npcName .. "\n" .. role
	lbl.Parent = bb

	return torso
end

-- Lightweight, server-driven worker models. They stay anchored and are
-- moved along navigation waypoints by the runtime, which lets fifty test
-- workers operate without the physics cost of fifty full player rigs.
-- Desk, chair and monitor for a seated worker. Built as separate furniture
-- rather than as part of the bot, so that killing the worker leaves the
-- workstation standing instead of tipping a desk over with the body.
local function buildWorkstation(parent, seatCF, name)
	local metal = Color3.fromRGB(58, 62, 70)
	local function piece(pieceName, size, offset, colour, material)
		local part = newPart(name .. "_" .. pieceName, size, seatCF * offset, colour, material, parent)
		part.CanCollide = false     -- never block a walking route
		part.CanTouch = false
		return part
	end
	-- the bot faces -Z, so the desk sits at negative Z and the chair behind it
	piece("ChairSeat", Vector3.new(1.7, 0.2, 1.7), CFrame.new(0, -1.10, 0.40), metal, Enum.Material.Metal)
	piece("ChairBack", Vector3.new(1.7, 1.5, 0.2), CFrame.new(0, -0.35, 0.95), metal, Enum.Material.Metal)
	piece("ChairStem", Vector3.new(0.25, 1.3, 0.25), CFrame.new(0, -1.78, 0.40), Color3.fromRGB(48, 52, 58), Enum.Material.Metal)
	piece("DeskTop", Vector3.new(3.4, 0.18, 1.9), CFrame.new(0, -0.45, -1.90), Color3.fromRGB(198, 188, 170), Enum.Material.WoodPlanks)
	piece("DeskLegL", Vector3.new(0.2, 2.0, 0.2), CFrame.new(-1.50, -1.45, -1.90), metal, Enum.Material.Metal)
	piece("DeskLegR", Vector3.new(0.2, 2.0, 0.2), CFrame.new(1.50, -1.45, -1.90), metal, Enum.Material.Metal)
	piece("Monitor", Vector3.new(1.5, 0.95, 0.12), CFrame.new(0, 0.22, -2.35), Color3.fromRGB(28, 32, 38), Enum.Material.SmoothPlastic)
	piece("MonitorStand", Vector3.new(0.35, 0.5, 0.3), CFrame.new(0, -0.28, -2.35), metal, Enum.Material.Metal)
end

local function buildWorkerBot(parent, botNumber, xcm, zcm, y0, seated)
	local model = Instance.new("Model")
	local isCompetitor = botNumber == 14
	model.Name = isCompetitor and "RivalScientist" or string.format("WorkerBot_%02d", botNumber)
	model.Parent = parent
	local roleNames = {"Technician", "Laboratory Technician"}
	local roleColours = {
		Color3.fromRGB(68, 135, 220),
		Color3.fromRGB(75, 175, 105),
	}
	local roleIndex = ((botNumber - 1) % #roleNames) + 1
	local baseY = Y(y0)
	-- Stable identities: 15 given names x 6 surnames for each gender. The
	-- 180 workers therefore have 180 different names, exactly 90 of each.
	local isGirl = botNumber % 2 == 0
	local identity = math.floor((botNumber - 1) / 2)
	local givenNames = isGirl
		and {"Ana", "Ioana", "Maria", "Elena", "Andreea", "Alexandra", "Daria", "Irina", "Sofia", "Teodora", "Raluca", "Cristina", "Gabriela", "Bianca", "Mihaela"}
		or {"Andrei", "Mihai", "Alexandru", "Radu", "Stefan", "Vlad", "Matei", "Gabriel", "David", "Tudor", "Razvan", "Ionut", "Cristian", "Darius", "Florin"}
	local surnames = {"Popescu", "Ionescu", "Dumitrescu", "Stan", "Marin", "Georgescu"}
	local displayName = givenNames[identity % #givenNames + 1] .. " " .. surnames[math.floor(identity / #givenNames) % #surnames + 1]
	local coats = {Color3.fromRGB(28, 31, 39), Color3.fromRGB(44, 60, 87), Color3.fromRGB(87, 40, 49), Color3.fromRGB(49, 75, 65), Color3.fromRGB(78, 59, 92), Color3.fromRGB(178, 157, 121)}
	local skins = {Color3.fromRGB(241, 207, 174), Color3.fromRGB(225, 183, 143), Color3.fromRGB(201, 155, 115), Color3.fromRGB(170, 123, 88), Color3.fromRGB(233, 195, 159)}
	local hairs = {Color3.fromRGB(74, 40, 20), Color3.fromRGB(121, 70, 30), Color3.fromRGB(31, 25, 23), Color3.fromRGB(193, 153, 75), Color3.fromRGB(137, 57, 29)}
	local coat = coats[identity % #coats + 1]
	local skin = skins[math.floor(identity / 3) % #skins + 1]
	local hair = hairs[math.floor(identity / 2) % #hairs + 1]
	local shirt = Color3.fromHSV((botNumber * 0.618034) % 1, 0.48, 0.82)
	local centre = Vector3.new(X(xcm), baseY, X(zcm))
	local function botPart(name, size, offset, colour, material)
		local part = newPart(name, size, CFrame.new(centre + offset), colour, material, model)
		part.CanCollide = false
		part.CanTouch = false
		-- Queryable on purpose. These were CanQuery = false back when nothing
		-- ever needed to hit-test a worker, which meant every shot fired at one
		-- passed straight through it into the wall behind. A worker has to be
		-- raycast-visible to be a target.
		part.CanQuery = true
		return part
	end

	local torso, head
	local trouser = Color3.fromRGB(62, 72, 86)
	if seated then
		-- Desk pose: thighs forward, shins down, body dropped to chair height.
		-- The whole model faces -Z, which is also its LookVector, so the caller
		-- can simply PivotTo(CFrame.lookAt(seat, desk)) to sit it at a desk.
		torso = botPart("Torso", Vector3.new(1.8, 2.0, 1.0), Vector3.new(0, 2.45, 0), coat, Enum.Material.Fabric)
		botPart("LegL", Vector3.new(0.7, 0.7, 1.7), Vector3.new(-0.42, 1.55, -0.75), trouser, Enum.Material.Fabric)
		botPart("LegR", Vector3.new(0.7, 0.7, 1.7), Vector3.new(0.42, 1.55, -0.75), trouser, Enum.Material.Fabric)
		botPart("ShinL", Vector3.new(0.7, 1.45, 0.7), Vector3.new(-0.42, 0.72, -1.5), trouser, Enum.Material.Fabric)
		botPart("ShinR", Vector3.new(0.7, 1.45, 0.7), Vector3.new(0.42, 0.72, -1.5), trouser, Enum.Material.Fabric)
		botPart("ArmL", Vector3.new(0.58, 0.58, 1.6), Vector3.new(-1.05, 2.6, -0.7), coat, Enum.Material.Fabric)
		botPart("ArmR", Vector3.new(0.58, 0.58, 1.6), Vector3.new(1.05, 2.6, -0.7), coat, Enum.Material.Fabric)
		head = botPart("Head", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 3.95, 0), skin, Enum.Material.SmoothPlastic)
		botPart("RoleBadge", Vector3.new(0.38, 0.42, 0.08), Vector3.new(-0.5, 2.68, -0.54), roleColours[roleIndex], Enum.Material.Neon)
	else
		torso = botPart("Torso", Vector3.new(1.8, 2.0, 1.0), Vector3.new(0, 3.25, 0), coat, Enum.Material.Fabric)
		botPart("LegL", Vector3.new(0.7, 2.2, 0.7), Vector3.new(-0.42, 1.1, 0), trouser, Enum.Material.Fabric)
		botPart("LegR", Vector3.new(0.7, 2.2, 0.7), Vector3.new(0.42, 1.1, 0), trouser, Enum.Material.Fabric)
		botPart("ArmL", Vector3.new(0.58, 1.9, 0.58), Vector3.new(-1.18, 3.2, 0), coat, Enum.Material.Fabric)
		botPart("ArmR", Vector3.new(0.58, 1.9, 0.58), Vector3.new(1.18, 3.2, 0), coat, Enum.Material.Fabric)
		head = botPart("Head", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 4.75, 0), skin, Enum.Material.SmoothPlastic)
		botPart("RoleBadge", Vector3.new(0.38, 0.42, 0.08), Vector3.new(-0.5, 3.48, -0.54), roleColours[roleIndex], Enum.Material.Neon)
	end
	-- Block-avatar styling, like the player: hair, smiling face, an open
	-- jacket over an individual shirt, jeans and white-soled trainers.
	local headY = seated and 3.95 or 4.75
	local chestY = seated and 2.45 or 3.25
	botPart("Shirt", Vector3.new(0.80, 1.68, 0.06), Vector3.new(0, chestY, -0.535), shirt, Enum.Material.Fabric)
	botPart("JacketZip", Vector3.new(0.055, 1.65, 0.07), Vector3.new(0, chestY, -0.575), Color3.fromRGB(175, 181, 184), Enum.Material.Metal)
	for _, side in ipairs({-1, 1}) do
		local shoeZ = seated and -1.60 or -0.10
		botPart("Trainer" .. side, Vector3.new(0.75, 0.30, 0.95), Vector3.new(side * 0.42, 0.16, shoeZ), coat, Enum.Material.Fabric)
		botPart("Sole" .. side, Vector3.new(0.77, 0.10, 0.97), Vector3.new(side * 0.42, 0.055, shoeZ), Color3.fromRGB(235, 236, 228), Enum.Material.SmoothPlastic)
	end
	botPart("HairCrown", Vector3.new(1.20, 0.32, 1.16), Vector3.new(0, headY + 0.51, 0.04), hair, Enum.Material.SmoothPlastic)
	botPart("HairFringe", Vector3.new(0.76, 0.36, 0.19), Vector3.new((identity % 2 == 0) and -0.20 or 0.20, headY + 0.34, -0.53), hair, Enum.Material.SmoothPlastic)
	if isGirl then
		local style = identity % 3
		botPart("HairBack", Vector3.new(1.14, style == 0 and 1.55 or 0.94, 0.24), Vector3.new(0, headY - (style == 0 and 0.25 or 0.02), 0.55), hair, Enum.Material.SmoothPlastic)
		if style == 1 then
			local pony = botPart("Ponytail", Vector3.new(0.46, 1.25, 0.56), Vector3.new(0, headY - 0.08, 0.88), hair, Enum.Material.SmoothPlastic)
			pony.Shape = Enum.PartType.Ball
		elseif style == 2 then
			local bun = botPart("HairBun", Vector3.new(0.65, 0.65, 0.60), Vector3.new(0, headY + 0.48, 0.64), hair, Enum.Material.SmoothPlastic)
			bun.Shape = Enum.PartType.Ball
		end
	else
		botPart("HairBack", Vector3.new(1.16, 0.58, 0.22), Vector3.new(0, headY + 0.16, 0.54), hair, Enum.Material.SmoothPlastic)
		if identity % 3 == 0 then
			botPart("HairQuiff", Vector3.new(0.42, 0.22, 0.68), Vector3.new(0.17, headY + 0.75, -0.10), hair, Enum.Material.SmoothPlastic)
		end
	end
	local face = Instance.new("Decal")
	face.Name = "FriendlyFace"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	-- A single compact hull prevents players walking through the worker. Its
	-- navmesh modifier lets the worker plan from inside its own hull; movement
	-- still explicitly checks all other workers and players before every step.
	local hull = botPart("WorkerCollisionHull", Vector3.new(2.95, seated and 3.6 or 4.9, seated and 2.5 or 1.70),
		Vector3.new(0, seated and 2.1 or 2.7, seated and -0.50 or 0), coat, Enum.Material.SmoothPlastic)
	hull.Transparency = 1
	hull.CanCollide = true
	hull.CastShadow = false
	local navigation = Instance.new("PathfindingModifier")
	navigation.Name = "DynamicWorkerObstacle"
	navigation.PassThrough = true
	navigation.Parent = hull

	model.PrimaryPart = torso
	model:SetAttribute("BotNumber", botNumber)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("Gender", isGirl and "Girl" or "Boy")
	model:SetAttribute("AppearanceId", botNumber)
	model:SetAttribute("Role", roleNames[roleIndex])
	model:SetAttribute("Level", y0 == -F2F and "Basement" or ("Level_" .. (math.floor(y0 / F2F) + 1)))
	model:SetAttribute("TaskState", "Waiting for plant task")
	model:SetAttribute("CompletedCycles", 0)
	model:SetAttribute("Competitor", isCompetitor)
	model:SetAttribute("Score", 0)
	model:SetAttribute("Health", 100)
	model:SetAttribute("MaxHealth", 100)
	model:SetAttribute("KnockedOut", false)
	CollectionService:AddTag(model, "LabWorkerBot")

	local gui = Instance.new("BillboardGui")
	gui.Name = "BotStatus"
	gui.Size = UDim2.fromOffset(172, 64)
	gui.StudsOffset = Vector3.new(0, 3.0, 0)
	-- Was 12 studs, which meant you had to stand almost on top of a bot to
	-- see anything. The health bar is only useful if it reads across a room.
	gui.MaxDistance = 70
	gui.AlwaysOnTop = false
	gui.Parent = head
	local text = Instance.new("TextLabel")
	text.Name = "Status"
	text.Size = UDim2.fromScale(1, 0.5)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(235, 245, 255)
	text.TextStrokeTransparency = 0.35
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Text = displayName .. "\n" .. (isCompetitor and "Rival scientist" or roleNames[roleIndex])
	text.Parent = gui

	-- Health bar under the caption. refreshBotHealth() has always looked for
	-- children named HealthBarFill and HealthText and updated them -- but
	-- nothing ever created them, so it searched, found nothing and silently
	-- did nothing. A damaged bot never showed any damage.
	local barBack = Instance.new("Frame")
	barBack.Name = "HealthBarBack"
	barBack.Size = UDim2.new(0.88, 0, 0.18, 0)
	barBack.Position = UDim2.new(0.06, 0, 0.54, 0)
	barBack.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
	barBack.BackgroundTransparency = 0.2
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local barFill = Instance.new("Frame")
	barFill.Name = "HealthBarFill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(75, 220, 95)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Size = UDim2.new(1, 0, 0.26, 0)
	healthText.Position = UDim2.new(0, 0, 0.74, 0)
	healthText.BackgroundTransparency = 1
	healthText.TextColor3 = Color3.fromRGB(214, 232, 244)
	healthText.TextStrokeTransparency = 0.4
	healthText.TextScaled = true
	healthText.Font = Enum.Font.Gotham
	healthText.Text = "LIFE 100 / 100"
	healthText.Parent = gui

	return model
end

local function lamp(parent, xcm, zcm, baseY, brightness)
	if not BUILD_LIGHTS then return end
	local p = newPart("Luminaire", Vector3.new(X(120), Y(8), X(30)),
		CFrame.new(X(xcm), Y(baseY + WALL_H - 14), X(zcm)),
		Color3.fromRGB(250, 250, 244), Enum.Material.SmoothPlastic, parent)
	p.CanCollide = false
	p.CastShadow = false
	local l = Instance.new("PointLight")
	l.Range = LIGHT_RANGE
	l.Brightness = (brightness or 1) * LIGHT_BRIGHTNESS
	l.Color = Color3.fromRGB(255, 250, 236)
	l.Shadows = false
	l.Parent = p
end

local function lightGrid(parent, x1, z1, x2, z2, baseY, brightness)
	local nx = math.max(1, math.floor(X(math.abs(x2 - x1)) / LIGHT_SPACING + 0.5))
	local nz = math.max(1, math.floor(X(math.abs(z2 - z1)) / LIGHT_SPACING + 0.5))
	for i = 1, nx do
		for j = 1, nz do
			lamp(parent, x1 + (x2 - x1) * ((i - 0.5) / nx), z1 + (z2 - z1) * ((j - 0.5) / nz), baseY, brightness)
		end
	end
end

--=====================================================================
-- ELEVATOR CORES (three, set into the corridor so a walking route
-- always stays clear alongside each shaft)
--=====================================================================
-- Elevators removed by request: the building is stairs-only now (a tower
-- at each end of the corridor -- see buildStairTower below -- both running
-- basement to roof). Left as an empty list rather than deleting all the
-- downstream machinery: with zero entries here, no shafts get built, no
-- holes get cut in any floor slab, and the elevator control script simply
-- finds nothing tagged "Elevator" and does nothing.
local ELEVATORS = {}

-- The clear opening each shaft needs through a slab: the inner car
-- area only, so the slab still carries the shaft walls.
local ELEV_HOLES = {}
for _, e in ipairs(ELEVATORS) do
	table.insert(ELEV_HOLES, {
		x1 = (e.face == "X+") and (e.x1 + INT_T / 2) or e.x1,
		x2 = (e.face == "X+") and e.x2 or (e.x2 - INT_T / 2),
		z1 = e.z1 + INT_T / 2,
		z2 = e.z2 - INT_T / 2,
	})
end

-- Slab with rectangular holes punched through it (holes must not
-- overlap in z, which the elevator bays do not).
local function slabWithHoles(parent, name, x1, z1, x2, z2, topY, thickness, holes, colour, material)
	local list = {}
	for _, h in ipairs(holes or {}) do table.insert(list, h) end
	table.sort(list, function(a, b) return a.z1 < b.z1 end)
	local k = 0
	local function rect(ax, az, bx, bz)
		if bx - ax < 1 or bz - az < 1 then return end
		k = k + 1
		slab(parent, name .. "_" .. k, ax, az, bx, bz, topY, thickness, colour, material)
	end
	local cursor = z1
	for _, h in ipairs(list) do
		if h.z1 > cursor then rect(x1, cursor, x2, h.z1) end
		if h.x1 > x1 then rect(x1, h.z1, h.x1, h.z2) end
		if h.x2 < x2 then rect(h.x2, h.z1, x2, h.z2) end
		cursor = math.max(cursor, h.z2)
	end
	if cursor < z2 then rect(x1, cursor, x2, z2) end
end

--=====================================================================
-- LEVEL SHELL
--=====================================================================
local LEVELS = {
	{index = 0, label = "1", name = "Level_1", rooms = GROUND_ROOMS},
	{index = 1, label = "2", name = "Level_2", rooms = TYPICAL_ROOMS},
	{index = 2, label = "3", name = "Level_3", rooms = TYPICAL_ROOMS},
}
-- Five more floors on top of the original three (eight total). Each one
-- reuses the same typical room layout but gets its own RNG seed for
-- fitOutRoom (seeded off the level index further down), so the equipment
-- arrangement differs floor to floor even though the room shapes repeat.
for i = 3, 7 do
	table.insert(LEVELS, {index = i, label = tostring(i + 1), name = "Level_" .. (i + 1), rooms = TYPICAL_ROOMS})
end

local function offsetOps(list, base, extra)
	local out = {}
	for _, o in ipairs(list) do
		table.insert(out, {at = base + o.at, width = o.width, sill = o.sill,
			head = o.head, glass = o.glass, leaf = o.leaf, mainEntrance = o.mainEntrance})
	end
	for _, o in ipairs(extra or {}) do table.insert(out, o) end
	return out
end

local function buildLevelShell(levelIndex, levelName, levelLabel, rooms)
	local y = levelIndex * F2F
	local m = Instance.new("Model")
	m.Name = levelName
	m.Parent = root

	slabWithHoles(m, "FloorSlab", 0, 0, W, L, y, SLAB, ELEV_HOLES, C.slab, Enum.Material.SmoothPlastic)

	-- corridor walls, assembled from every room's own door list
	local wOps, eOps = {}, {}
	for _, r in ipairs(rooms) do
		if r.plan == "L" then
			for _, o in ipairs(offsetOps(r.open.E, r.z1)) do table.insert(wOps, o) end
		else
			for _, o in ipairs(offsetOps(r.open.W, r.z1)) do table.insert(eOps, o) end
		end
	end
	wall(m, "Corridor_West", CORR_X1, 0, CORR_X1, L, INT_T, y, WALL_H, wOps, C.int)
	wall(m, "Corridor_East", CORR_X2, 0, CORR_X2, L, INT_T, y, WALL_H, eOps, C.int)

	-- exterior long walls
	local extW, extE = {}, {}
	for _, r in ipairs(rooms) do
		if r.plan == "L" then
			for _, o in ipairs(offsetOps(r.open.W, r.z1)) do table.insert(extW, o) end
		else
			for _, o in ipairs(offsetOps(r.open.E, r.z1)) do table.insert(extE, o) end
		end
	end
	-- Only the ground-floor west lobby has a normal exterior entrance.
	if levelIndex == 0 and extW[1] then
		extW[1].glass, extW[1].leaf, extW[1].sill, extW[1].mainEntrance = false, true, 0, true
	end
	wall(m, "Ext_West", EXT_T / 2, 0, EXT_T / 2, L, EXT_T, y, WALL_H, extW, C.ext, Enum.Material.Concrete)
	wall(m, "Ext_East", W - EXT_T / 2, 0, W - EXT_T / 2, L, EXT_T, y, WALL_H, extE, C.ext, Enum.Material.Concrete)

	-- exterior end walls
	wall(m, "Ext_North", 0, EXT_T / 2, W, EXT_T / 2, EXT_T, y, WALL_H, {
		{at = CORR_X1 + 20, width = 160, head = 240},
		{at = W * 0.12, width = 140, sill = WIN_SILL, head = WIN_HEAD, glass = true},
		{at = W * 0.77, width = 140, sill = WIN_SILL, head = WIN_HEAD, glass = true},
	}, C.ext, Enum.Material.Concrete)

	wall(m, "Ext_South", 0, L - EXT_T / 2, W, L - EXT_T / 2, EXT_T, y, WALL_H, {
		{at = CORR_X1 + 25, width = WIDE_W, head = 240, leaf = true},
		{at = W * 0.12, width = 90, sill = 20, head = 230, glass = true},
		{at = W * 0.20, width = 150, sill = WIN_SILL, head = WIN_HEAD, glass = true},
		{at = W * 0.80, width = 90, sill = 20, head = 230, glass = true},
	}, C.ext, Enum.Material.Concrete)

	-- dividers, carrying the interconnecting doors
	for i, r in ipairs(rooms) do
		local nxt = rooms[i + 1]
		if nxt and nxt.plan == r.plan and nxt.z1 == r.z2 then
			wall(m, "Div_" .. i, r.x1, r.z2, r.x2, r.z2, INT_T, y, WALL_H,
				r.open.S, C.int)
		end
	end

	-- signage and lighting
	for _, r in ipairs(rooms) do
		local sx = (r.plan == "L") and (CORR_X1 - 45) or (CORR_X2 + 45)
		sign(m, r.name, sx, (r.z1 + r.z2) / 2, y, 220, 55)
		lightGrid(m, r.x1, r.z1, r.x2, r.z2, y, 1)
	end
	lightGrid(m, CORR_X1, 0, CORR_X2, L, y, 0.8)
	sign(m, "Floor " .. levelLabel, (CORR_X1 + CORR_X2) / 2, 120, y, 300, 90)

	return m
end

--=====================================================================
-- BASEMENT -- driven by BASEMENT_ROOMS, same shape as "Plan demisol":
-- one long room down the west side, 7 rooms off the corridor to the
-- east, solid (below-grade) exterior walls with no windows.
--=====================================================================
local function buildBasement()
	local y = -F2F
	local m = Instance.new("Model")
	m.Name = "Basement"
	m.Parent = root

	slab(m, "BasementSlab", 0, 0, W, L, y, 40, C.basement, Enum.Material.Concrete)

	wall(m, "B_West",  EXT_T, 0, EXT_T, L, 40, y, WALL_H, {}, C.basewall, Enum.Material.Concrete)
	wall(m, "B_East",  W - EXT_T, 0, W - EXT_T, L, 40, y, WALL_H, {}, C.basewall, Enum.Material.Concrete)
	wall(m, "B_North", 0, EXT_T, W, EXT_T, 40, y, WALL_H,
		{{at = CORR_X1 + 20, width = 160, head = 240}}, C.basewall, Enum.Material.Concrete)
	wall(m, "B_South", 0, L - EXT_T, W, L - EXT_T, 40, y, WALL_H,
		{{at = CORR_X1 + 20, width = 160, head = 240}}, C.basewall, Enum.Material.Concrete)

	-- corridor walls, doors gathered from every basement room's own list
	local wOps, eOps = {}, {}
	for _, r in ipairs(BASEMENT_ROOMS) do
		if r.plan == "L" then
			for _, o in ipairs(offsetOps(r.open.E, r.z1)) do table.insert(wOps, o) end
		else
			for _, o in ipairs(offsetOps(r.open.W, r.z1)) do table.insert(eOps, o) end
		end
	end
	wall(m, "B_Corr_West", CORR_X1, 0, CORR_X1, L, INT_T, y, WALL_H, wOps, C.basewall)
	wall(m, "B_Corr_East", CORR_X2, 0, CORR_X2, L, INT_T, y, WALL_H, eOps, C.basewall)

	-- dividers between consecutive east-side bays
	for i, r in ipairs(BASEMENT_ROOMS) do
		local nxt = BASEMENT_ROOMS[i + 1]
		if nxt and nxt.plan == r.plan and nxt.z1 == r.z2 then
			wall(m, "B_Div_" .. i, r.x1, r.z2, r.x2, r.z2, INT_T, y, WALL_H,
				r.open.S, C.basewall)
		end
	end

	for _, x in ipairs({150, 250, W - 250, W - 150}) do
		for z = 250, L - 200, 350 do
			newPart("Pillar", Vector3.new(X(45), Y(WALL_H), X(45)),
				CFrame.new(X(x), Y(y + WALL_H / 2), X(z)), C.pillar, Enum.Material.Concrete, m)
		end
	end

	for _, r in ipairs(BASEMENT_ROOMS) do
		local sx = (r.plan == "L") and (CORR_X1 - 45) or (CORR_X2 + 45)
		sign(m, r.name, sx, (r.z1 + r.z2) / 2, y, 200, 55)
		lightGrid(m, r.x1, r.z1, r.x2, r.z2, y, 0.6)
	end
	lightGrid(m, CORR_X1, 0, CORR_X2, L, y, 0.5)
	sign(m, "Basement", (CORR_X1 + CORR_X2) / 2, 120, y, 300, 90)
	return m, BASEMENT_ROOMS
end

--=====================================================================
-- STAIR TOWER
--=====================================================================
-- centred on the corridor, which sits at CORR_X1..CORR_X2. Two towers now,
-- one attached beyond each end of the building (north, before z=0, and
-- south, beyond z=L) -- stairs "on each opposite part of the hallway" per
-- request, instead of a single stairwell everyone has to walk the whole
-- corridor to reach. Both run the full basement-to-roof height.
local TX1, TX2 = CORR_X1 - 50, CORR_X2 + 50
local TXM = (TX1 + TX2) / 2

local function buildStairTower(bottomLevel, topLevel, southEnd)
	local m = Instance.new("Model")
	m.Name = southEnd and "StairTower_South" or "StairTower_North"
	m.Parent = root
	local bottomY = bottomLevel * F2F
	local shellH = (topLevel - bottomLevel) * F2F + WALL_H

	-- All the tower's Z coordinates are measured outward from the building
	-- edge it attaches to (0 = flush with the building). "dir" flips the
	-- sign so the exact same layout mirrors onto the south end: outerZ is
	-- the far exterior wall (carries the entrance door), edgeZ is flush
	-- with the building's own end wall (and its existing WIDE_W doorway,
	-- on the south end -- see Ext_South), flightNearZ/flightFarZ are the
	-- switchback landing points in between. wall()/slab() both take their
	-- span via math.abs() of the two endpoints, so the sign of "dir" alone
	-- is enough to mirror every call below without reordering anything.
	local edgeZ = southEnd and L or 0
	local dir = southEnd and 1 or -1
	local outerZ = edgeZ + dir * 460
	local flightNearZ = edgeZ + dir * 100
	local flightFarZ = edgeZ + dir * 400

	wall(m, "T_West", TX1, edgeZ, TX1, outerZ, EXT_T, bottomY, shellH, {}, C.ext, Enum.Material.Concrete)
	wall(m, "T_East", TX2, edgeZ, TX2, outerZ, EXT_T, bottomY, shellH, {}, C.ext, Enum.Material.Concrete)
	wall(m, southEnd and "T_South" or "T_North", TX1, outerZ, TX2, outerZ, EXT_T, bottomY, shellH,
		{{at = 105, width = 110, sill = -bottomY + 20, head = -bottomY + 235, glass = true}}, C.ext, Enum.Material.Concrete)
	slab(m, "T_Roof", TX1 - EXT_T, edgeZ, TX2 + EXT_T, outerZ + dir * EXT_T, bottomY + shellH + SLAB, SLAB, C.roof)
	slab(m, "T_Apron", TX1 - 60, outerZ, TX2 + 60, outerZ + dir * 260, 0, 20, C.slab)

	local halfRise = Y(F2F) / 2
	local STEPS = math.max(8, math.ceil(halfRise / 1.4))

	local function flight(name, x1, x2, zStart, zEnd, yStart, yEnd)
		local dz, dy = (zEnd - zStart) / STEPS, (yEnd - yStart) / STEPS
		for i = 1, STEPS do
			local z0, z1 = zStart + dz * (i - 1), zStart + dz * i
			local top = yStart + dy * i
			local a, b = math.min(z0, z1), math.max(z0, z1)
			newPart(name .. "_t" .. i, Vector3.new(X(x2 - x1), Y(18), X(math.abs(dz))),
				CFrame.new(X((x1 + x2) / 2), Y(top - 9), X((a + b) / 2)), C.stair, Enum.Material.Concrete, m)
			newPart(name .. "_r" .. i, Vector3.new(X(x2 - x1), Y(math.abs(dy) + 4), X(math.abs(dz))),
				CFrame.new(X((x1 + x2) / 2), Y(top - 18 - (math.abs(dy) + 4) / 2), X((a + b) / 2)),
				C.stair, Enum.Material.Concrete, m)
		end
	end

	for lvl = bottomLevel, topLevel do
		local y = lvl * F2F
		slab(m, "Landing_L" .. lvl, TX1, flightNearZ, TX2, edgeZ, y, 15, C.stair)
		if lvl < topLevel then
			local half = y + F2F / 2
			flight("FlightA_L" .. lvl, TX1 + 10, TXM, flightNearZ, flightFarZ, y, half)
			slab(m, "MidLanding_L" .. lvl, TX1, outerZ, TX2, flightFarZ, half, 15, C.stair)
			flight("FlightB_L" .. lvl, TXM, TX2 - 10, flightFarZ, flightNearZ, half, y + F2F)
			newPart("Handrail_L" .. lvl, Vector3.new(X(8), Y(100), X(math.abs(flightNearZ - flightFarZ))),
				CFrame.new(X(TXM), Y(y + F2F / 2 + 50), X((flightFarZ + flightNearZ) / 2)),
				Color3.fromRGB(120, 128, 136), Enum.Material.Metal, m).CanCollide = false
		end
		-- Put a compact light over the level landing, never across a flight.
		local light = newPart("StairLandingLight_L" .. lvl, Vector3.new(2.5, 0.18, 0.65),
			CFrame.new(X(TX1 + 22), Y(y + WALL_H - 15), X(edgeZ + dir * 45)),
			Color3.fromRGB(245, 242, 225), Enum.Material.Neon, m)
		light.CanCollide, light.CanTouch, light.CanQuery = false, false, false
		local glow = Instance.new("PointLight")
		glow.Range, glow.Brightness, glow.Parent = 24, 0.8, light
	end
	return m
end

--=====================================================================
-- ELEVATOR BUILDER
--=====================================================================
local function buildElevator(spec, bottomLevel, topLevel)
	local m = Instance.new("Model")
	m.Name = "Elevator_" .. spec.id
	m.Parent = root

	local bottomY = bottomLevel * F2F
	local shellH  = (topLevel - bottomLevel) * F2F + WALL_H
	local openAtX2 = (spec.face == "X+")           -- open face is x2 (or x1)
	local backX    = openAtX2 and spec.x1 or spec.x2
	local frontX   = openAtX2 and spec.x2 or spec.x1

	-- shaft: back wall plus both sides, open on the corridor face
	wall(m, "Shaft_Back", backX, spec.z1, backX, spec.z2, INT_T, bottomY, shellH, {}, C.shaft, Enum.Material.Metal)
	wall(m, "Shaft_S1", spec.x1, spec.z1, spec.x2, spec.z1, INT_T, bottomY, shellH, {}, C.shaft, Enum.Material.Metal)
	wall(m, "Shaft_S2", spec.x1, spec.z2, spec.x2, spec.z2, INT_T, bottomY, shellH, {}, C.shaft, Enum.Material.Metal)
	slab(m, "Shaft_Roof", spec.x1, spec.z1, spec.x2, spec.z2, bottomY + shellH + SLAB, SLAB, C.shaft)

	local innerZ1, innerZ2 = spec.z1 + INT_T / 2, spec.z2 - INT_T / 2
	local innerX1 = openAtX2 and (spec.x1 + INT_T / 2) or spec.x1
	local innerX2 = openAtX2 and spec.x2 or (spec.x2 - INT_T / 2)

	local floors = {}
	for lvl = bottomLevel, topLevel do table.insert(floors, lvl) end

	m:SetAttribute("FloorCount", #floors)
	m:SetAttribute("Face", spec.face)
	for i, lvl in ipairs(floors) do
		m:SetAttribute("FloorY_" .. i, Y(lvl * F2F))
		m:SetAttribute("FloorLabel_" .. i, lvl < 0 and "B" or tostring(lvl + 1))
	end

	-- landing gate + call button at every floor
	local gates = Instance.new("Folder"); gates.Name = "Gates"; gates.Parent = m
	local calls = Instance.new("Folder"); calls.Name = "CallPanels"; calls.Parent = m
	for i, lvl in ipairs(floors) do
		local y = lvl * F2F
		local g = newPart("Gate_" .. i,
			Vector3.new(X(8), Y(DOOR_H + 20), X(innerZ2 - innerZ1)),
			CFrame.new(X(frontX), Y(y + (DOOR_H + 20) / 2), X((innerZ1 + innerZ2) / 2)),
			Color3.fromRGB(110, 120, 132), Enum.Material.Metal, gates)
		g:SetAttribute("Floor", i)

		local panel = newPart("Call_" .. i, Vector3.new(X(6), Y(40), X(30)),
			CFrame.new(X(frontX + (openAtX2 and 12 or -12)), Y(y + 120), X(innerZ1 - 25)),
			Color3.fromRGB(60, 66, 74), Enum.Material.Metal, calls)
		panel:SetAttribute("Floor", i)
		panel:SetAttribute("ElevatorId", spec.id)
	end

	-- the car
	local car = Instance.new("Model"); car.Name = "Car"; car.Parent = m
	local startY = bottomLevel * F2F
	local cw = innerX2 - innerX1
	local cd = innerZ2 - innerZ1

	slab(car, "Platform", innerX1, innerZ1, innerX2, innerZ2, startY + 10, 10, C.car, Enum.Material.Metal)
	local function carWall(name, x1, z1, x2, z2)
		wall(car, name, x1, z1, x2, z2, 10, startY + 10, 250, {}, C.car, Enum.Material.Metal)
	end
	carWall("Car_Back", backX + (openAtX2 and 12 or -12), innerZ1, backX + (openAtX2 and 12 or -12), innerZ2)
	carWall("Car_S1", innerX1, innerZ1 + 6, innerX2, innerZ1 + 6)
	carWall("Car_S2", innerX1, innerZ2 - 6, innerX2, innerZ2 - 6)
	slab(car, "Car_Roof", innerX1, innerZ1, innerX2, innerZ2, startY + 270, 10, C.car, Enum.Material.Metal)
	local carLight = newPart("Car_Light", Vector3.new(X(40), Y(6), X(40)),
		CFrame.new(X((innerX1 + innerX2) / 2), Y(startY + 250), X((innerZ1 + innerZ2) / 2)),
		Color3.fromRGB(255, 255, 245), Enum.Material.Neon, car)
	carLight.CanCollide = false
	local cl = Instance.new("PointLight"); cl.Range = 30; cl.Brightness = 1.2; cl.Parent = carLight

	-- in-car buttons, one per floor, on the back wall
	local buttons = Instance.new("Folder"); buttons.Name = "Buttons"; buttons.Parent = car
	for i, lvl in ipairs(floors) do
		local t = (i - 0.5) / #floors
		local b = newPart("Btn_" .. i, Vector3.new(X(8), Y(26), X(16)),
			CFrame.new(X(backX + (openAtX2 and 22 or -22)), Y(startY + 130),
				X(innerZ1 + (innerZ2 - innerZ1) * t)),
			Color3.fromRGB(230, 200, 90), Enum.Material.Neon, buttons)
		b.CanCollide = false
		b:SetAttribute("Floor", i)
	end

	m:SetAttribute("CurrentFloor", 1)
	CollectionService:AddTag(m, "Elevator")
	return m
end

--=====================================================================
-- BASIC LABORATORY EQUIPMENT CATALOGUE
-- Nothing here is tied to a particular room or process. The fit-out
-- for every room is generated from this list.
--=====================================================================
local COL = {
	bench   = Color3.fromRGB(178, 182, 186),
	steel   = Color3.fromRGB(196, 200, 205),
	white   = Color3.fromRGB(236, 238, 241),
	dark    = Color3.fromRGB(72, 78, 86),
	timber  = Color3.fromRGB(166, 142, 112),
	cold    = Color3.fromRGB(198, 216, 226),
	warm    = Color3.fromRGB(206, 178, 140),
	safety  = Color3.fromRGB(190, 62, 52),
	green   = Color3.fromRGB(78, 138, 96),
	glassy  = Color3.fromRGB(198, 220, 230),
}

-- class: "run"  = long fitted furniture, takes the best wall
--        "floor"= free-standing unit against a wall
--        "top"  = sits on a bench run
--        "duty" = safety kit, one of each per room
-- shape: how the item is actually built out of primitive parts, so it
-- reads as real equipment rather than a plain box (see buildKind below)
local CATALOGUE = {
	-- Room contents are now limited to equipment that actually acts on a
	-- germinated plant sample (matches an entry in PLANT_PROCESS, or is the
	-- separately-placed Plant Growth Chamber). Generic lab furniture,
	-- benchtop instruments and safety kit that never touch a plant sample
	-- were removed by request so every object in a room is something that
	-- moves a plant's status forward.
	{kind = "Germination Chamber", class = "floor", w = 95, d = 80,  h = 195, col = COL.cold,   mat = Enum.Material.Metal,      weight = 4, shape = "appliance", auto = "pulse"},
	{kind = "Incubator",         class = "floor", w = 90,  d = 75,  h = 180, col = COL.green,  mat = Enum.Material.Metal,      weight = 4, shape = "appliance"},
	{kind = "Decontamination Unit", class = "floor", w = 75, d = 60, h = 150, col = COL.white,  mat = Enum.Material.Metal,      weight = 3, shape = "appliance", auto = "pulse"},
	{kind = "Mutagenesis Chamber", class = "floor", w = 90, d = 80, h = 200, col = COL.safety, mat = Enum.Material.Metal,      weight = 2, shape = "appliance", auto = "pulse"},
	{kind = "Hormone Treatment Bench", class = "floor", w = 80, d = 65, h = 175, col = COL.green,  mat = Enum.Material.Metal,      weight = 2, shape = "appliance", auto = "spin"},

	-- Smaller "run" variants of the same five kinds so bench-run islands
	-- (the middle of a room's floor, not just its walls) also fill up with
	-- functional equipment -- this is most of what gets the building well
	-- past a thousand units total.
	{kind = "Germination Chamber", class = "run", w = 68, d = 55, h = 195, col = COL.cold,   mat = Enum.Material.Metal, weight = 4, shape = "appliance", auto = "pulse"},
	{kind = "Incubator",         class = "run", w = 64, d = 52, h = 180, col = COL.green,  mat = Enum.Material.Metal, weight = 4, shape = "appliance"},
	{kind = "Decontamination Unit", class = "run", w = 58, d = 46, h = 150, col = COL.white,  mat = Enum.Material.Metal, weight = 3, shape = "appliance", auto = "pulse"},
	{kind = "Mutagenesis Chamber", class = "run", w = 64, d = 55, h = 200, col = COL.safety, mat = Enum.Material.Metal, weight = 2, shape = "appliance", auto = "pulse"},
	{kind = "Hormone Treatment Bench", class = "run", w = 58, d = 48, h = 175, col = COL.green,  mat = Enum.Material.Metal, weight = 2, shape = "appliance", auto = "spin"},

	-- Pure decoration: potted plants, flower planters, and lab storage
	-- furniture (drawer units / filing cabinets). None of these are tagged
	-- as functional equipment (no status LED, no failure/hazard behaviour)
	-- -- they exist purely to fill every remaining sliver of wall and floor
	-- space so the building reads as a real, lived-in facility rather than
	-- rows of machines with bare walls and floor between them.
	{kind = "Potted Plant", class = "decor", w = 42, d = 42, h = 62, col = Color3.fromRGB(150, 108, 70), mat = Enum.Material.SmoothPlastic, weight = 5, shape = "planter"},
	{kind = "Flowering Planter", class = "decor", w = 55, d = 32, h = 40, col = Color3.fromRGB(168, 120, 78), mat = Enum.Material.SmoothPlastic, weight = 4, shape = "planter", flowering = true},
	{kind = "Storage Drawers", class = "decor", w = 62, d = 45, h = 95, col = Color3.fromRGB(96, 102, 110), mat = Enum.Material.Metal, weight = 4, shape = "drawers"},
	{kind = "Filing Cabinet", class = "decor", w = 48, d = 52, h = 130, col = Color3.fromRGB(72, 78, 86), mat = Enum.Material.Metal, weight = 3, shape = "drawers"},
	{kind = "Supply Shelf", class = "decor", w = 90, d = 38, h = 175, col = Color3.fromRGB(120, 126, 130), mat = Enum.Material.Metal, weight = 3, shape = "rack"},
}

-- Scientific machines share one readable, refrigerator-like design language.
-- Desks and benches remain furniture; benchtop instruments and safety kit
-- keep their own real-world proportions (a Microscope should never look like
-- a walk-in freezer). Only true free-standing floor equipment -- growth
-- chambers, ovens, storage cabinets and the like -- get the industrial
-- cabinet treatment, and it's sized for an industrial facility: wide, tall
-- units with real walking clearance around them. Width/height variants
-- still communicate capacity.
local CABINET_SIZES = {
	{w = 100, d = 90,  h = 220, capacity = 6},
	{w = 115, d = 95,  h = 235, capacity = 8},
	{w = 130, d = 100, h = 250, capacity = 10},
	{w = 145, d = 105, h = 265, capacity = 14},
}
for _, entry in ipairs(CATALOGUE) do
	if entry.class == "floor" then
		local hash = 0
		for i = 1, #entry.kind do hash = hash + string.byte(entry.kind, i) end
		local cabinet = CABINET_SIZES[hash % #CABINET_SIZES + 1]
		entry.w, entry.d, entry.h = cabinet.w, cabinet.d, cabinet.h
		entry.capacity = cabinet.capacity
		entry.shape = "appliance"
		entry.plantCabinet = true
	end
end

local BY_CLASS = {run = {}, floor = {}, top = {}, duty = {}, decor = {}}
for _, e in ipairs(CATALOGUE) do
	table.insert(BY_CLASS[e.class], e)
end

local function weightedPick(list, rng)
	local total = 0
	for _, e in ipairs(list) do total = total + (e.weight or 1) end
	local roll = rng.next() * total
	for _, e in ipairs(list) do
		roll = roll - (e.weight or 1)
		if roll <= 0 then return e end
	end
	return list[#list]
end

--=====================================================================
-- AUTOMATIC WALL PACKING
--=====================================================================
local WALL_GAP   = 16   -- plan cm of clear floor between a wall face and a cabinet
local ALONG_GAP  = 26   -- plan cm between neighbours -- enough of an aisle gap that each
                         -- cabinet's status text doesn't overlap its neighbour's
local CORNER     = 100  -- plan cm kept clear at each corner (must exceed
                        -- the deepest unit so adjacent walls cannot clash)
local DOOR_CLEAR = 55   -- plan cm kept clear either side of a door

-- Free intervals along one wall of a room, in that wall's local
-- coordinates, with door swings excluded.
local function freeSpans(length, openings)
	local blocked = {}
	for _, o in ipairs(openings or {}) do
		-- Windows need clear floor space just as doors do. The smaller window
		-- margin preserves capacity while keeping every cabinet out of glazing.
		local clear = o.glass and 30 or DOOR_CLEAR
		table.insert(blocked, {o.at - clear, o.at + o.width + clear})
	end
	table.sort(blocked, function(a, b) return a[1] < b[1] end)

	local spans, cursor = {}, CORNER
	for _, b in ipairs(blocked) do
		if b[1] > cursor then table.insert(spans, {cursor, math.min(b[1], length - CORNER)}) end
		cursor = math.max(cursor, b[2])
	end
	if cursor < length - CORNER then table.insert(spans, {cursor, length - CORNER}) end

	local out = {}
	for _, s in ipairs(spans) do
		if s[2] - s[1] > 20 then table.insert(out, s) end
	end
	return out
end

local function takeSpan(spans, need)
	for _, s in ipairs(spans) do
		if s[2] - s[1] >= need then
			local at = s[1] + need / 2
			s[1] = s[1] + need + ALONG_GAP
			return at
		end
	end
	return nil
end

-- Same as takeSpan but with a caller-chosen gap. Decoration (plants,
-- drawers, ...) doesn't carry a status readout that neighbours could
-- overlap, so it can pack into slivers real equipment leaves behind with
-- only a token gap between pieces.
local function takeSpanGap(spans, need, gap)
	for _, s in ipairs(spans) do
		if s[2] - s[1] >= need then
			local at = s[1] + need / 2
			s[1] = s[1] + need + gap
			return at
		end
	end
	return nil
end

local function spansTotal(spans)
	local t = 0
	for _, s in ipairs(spans) do t = t + (s[2] - s[1]) end
	return t
end

--=====================================================================
-- EQUIPMENT SHAPES
-- Every catalogue entry is built from 1-4 primitive parts instead of a
-- single box, so it reads as the kind of thing it is: a bench with
-- legs and a top, an appliance with a door and a handle, a rack with
-- shelves, an instrument with a small control panel. Everything here
-- is axis-aligned (the generator never yaws a part), so offsets are
-- plain world-space vectors added to a centre position.
--=====================================================================
local function buildKind(parent, entry, pos, size, wallSide)
	local shape = entry.shape or "box"
	local dark  = Color3.fromRGB(36, 38, 44)
	-- The accent/panel colour always contrasts AGAINST the body colour,
	-- not just darkens it: a body that's already dark (COL.dark items
	-- like the hot plate stirrer, the pH meter, ...) used to get an
	-- accent that was darker still, so the door/panel disappeared into
	-- the body and the whole thing read as a plain black box.
	local lum = entry.col.R * 0.299 + entry.col.G * 0.587 + entry.col.B * 0.114
	local accent
	if lum > 0.45 then
		accent = Color3.fromRGB(
			math.max(0, entry.col.R * 255 - 45),
			math.max(0, entry.col.G * 255 - 45),
			math.max(0, entry.col.B * 255 - 45))
	else
		accent = Color3.fromRGB(
			math.min(255, entry.col.R * 255 + 80),
			math.min(255, entry.col.G * 255 + 80),
			math.min(255, entry.col.B * 255 + 80))
	end
	local panelColour = lum > 0.45 and dark or Color3.fromRGB(168, 172, 178)

	-- Every sub-part of an assembly is parented to the piece's own main
	-- part (not the room model) so the runtime script can reliably find
	-- "this instance's own door/panel/light" with FindFirstChild instead
	-- of guessing among same-named siblings from every other item.
	if shape == "appliance" then
		-- Every appliance-class unit is built as a real germination-cabinet
		-- style enclosure -- insulated shell, glass front with frame trim,
		-- interior shelving/lighting, a rear vent, a controller screen and
		-- caster wheels -- the same construction language as the R1-R200
		-- growth chambers, never a plain box with a door bolted on. Colour
		-- (drawn from the catalogue entry, which already varies per kind)
		-- is what gives each equipment TYPE its own tailored look: a cold
		-- germination unit reads pale and clinical, a mutagenesis chamber
		-- reads hazard-yellow, and so on -- hospital-white insulated shells,
		-- industrial metal frame/trim, and lab glass fronts throughout.
		local frontOnX, direction
		if wallSide == "W" or wallSide == "E" then
			frontOnX = true
			direction = (wallSide == "W") and 1 or -1
		else
			frontOnX = false
			direction = (wallSide == "S") and -1 or 1
		end

		local shellColour = lum > 0.55 and Color3.fromRGB(226, 231, 229)
			or lum > 0.3 and Color3.fromRGB(196, 202, 201)
			or Color3.fromRGB(54, 58, 62)
		local frameColour = Color3.fromRGB(56, 62, 66)
		local glassColour = Color3.fromRGB(
			math.min(255, entry.col.R * 255 * 0.5 + 150),
			math.min(255, entry.col.G * 255 * 0.5 + 155),
			math.min(255, entry.col.B * 255 * 0.5 + 155))

		-- Backing volume only (matches the growth-chamber reference): a
		-- transparent placeholder that all the real, opaque panels below
		-- attach to, sized/positioned exactly as the caller expects so the
		-- runtime's LED/prompt/status binding keeps working unmodified.
		local body = newPart("Body", size, CFrame.new(pos), Color3.fromRGB(205, 216, 212), Enum.Material.Glass, parent)
		body.Transparency = 0.9

		local innerWidth = frontOnX and size.Z or size.X
		local innerDepth = frontOnX and size.X or size.Z
		local shellT = math.max(math.min(size.X, size.Z) * 0.05, 0.12)
		local function interiorOffset(across, up, fromFront)
			if frontOnX then return CFrame.new(direction * (innerDepth / 2 - fromFront), up, across) end
			return CFrame.new(across, up, direction * (innerDepth / 2 - fromFront))
		end

		-- Opaque insulated back/side/top/floor panels -- only the front
		-- stays glazed, matching a real controlled-environment cabinet.
		if frontOnX then
			newPart("InsulatedBack", Vector3.new(shellT, size.Y * 0.96, innerWidth),
				body.CFrame * CFrame.new(-direction * (innerDepth / 2 - shellT / 2), 0, 0), shellColour, Enum.Material.Metal, body)
			for _, sideSign in ipairs({-1, 1}) do
				newPart("InsulatedSide", Vector3.new(innerDepth, size.Y * 0.96, shellT),
					body.CFrame * CFrame.new(0, 0, sideSign * (innerWidth / 2 - shellT / 2)), shellColour, Enum.Material.Metal, body)
			end
		else
			newPart("InsulatedBack", Vector3.new(innerWidth, size.Y * 0.96, shellT),
				body.CFrame * CFrame.new(0, 0, -direction * (innerDepth / 2 - shellT / 2)), shellColour, Enum.Material.Metal, body)
			for _, sideSign in ipairs({-1, 1}) do
				newPart("InsulatedSide", Vector3.new(shellT, size.Y * 0.96, innerDepth),
					body.CFrame * CFrame.new(sideSign * (innerWidth / 2 - shellT / 2), 0, 0), shellColour, Enum.Material.Metal, body)
			end
		end
		local capSize = frontOnX and Vector3.new(innerDepth, shellT, innerWidth) or Vector3.new(innerWidth, shellT, innerDepth)
		newPart("InsulatedTop", capSize, body.CFrame * CFrame.new(0, size.Y / 2 - shellT / 2, 0), shellColour, Enum.Material.Metal, body)
		newPart("InsulatedFloor", capSize, body.CFrame * CFrame.new(0, -size.Y / 2 + shellT / 2, 0), shellColour, Enum.Material.Metal, body)

		-- Glass front door, framed in metal on all four edges.
		local frontDist = innerDepth / 2 + 0.07
		local doorSize = frontOnX and Vector3.new(shellT * 1.2, size.Y * 0.82, innerWidth * 0.86)
			or Vector3.new(innerWidth * 0.86, size.Y * 0.82, shellT * 1.2)
		local doorCFrame = frontOnX and (body.CFrame * CFrame.new(direction * frontDist, 0, 0))
			or (body.CFrame * CFrame.new(0, 0, direction * frontDist))
		local door = newPart("Door", doorSize, doorCFrame, glassColour, Enum.Material.Glass, body)
		door.Transparency = entry.plantCabinet and 0.34 or 0.5
		door.CanCollide = false
		if frontOnX then
			local fx = direction * frontDist
			newPart("GlassFrameLeft", Vector3.new(0.18, size.Y * 0.94, 0.2), body.CFrame * CFrame.new(fx, 0, -innerWidth * 0.46), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameRight", Vector3.new(0.18, size.Y * 0.94, 0.2), body.CFrame * CFrame.new(fx, 0, innerWidth * 0.46), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameTop", Vector3.new(0.18, 0.22, innerWidth * 0.94), body.CFrame * CFrame.new(fx, size.Y * 0.46, 0), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameBottom", Vector3.new(0.18, 0.22, innerWidth * 0.94), body.CFrame * CFrame.new(fx, -size.Y * 0.46, 0), frameColour, Enum.Material.Metal, body).CanCollide = false
		else
			local fz = direction * frontDist
			newPart("GlassFrameLeft", Vector3.new(0.2, size.Y * 0.94, 0.18), body.CFrame * CFrame.new(-innerWidth * 0.46, 0, fz), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameRight", Vector3.new(0.2, size.Y * 0.94, 0.18), body.CFrame * CFrame.new(innerWidth * 0.46, 0, fz), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameTop", Vector3.new(innerWidth * 0.94, 0.22, 0.18), body.CFrame * CFrame.new(0, size.Y * 0.46, fz), frameColour, Enum.Material.Metal, body).CanCollide = false
			newPart("GlassFrameBottom", Vector3.new(innerWidth * 0.94, 0.22, 0.18), body.CFrame * CFrame.new(0, -size.Y * 0.46, fz), frameColour, Enum.Material.Metal, body).CanCollide = false
		end
		local handleSize = frontOnX and Vector3.new(0.05, size.Y * 0.22, 0.05) or Vector3.new(size.Y * 0.22, 0.05, 0.05)
		local handle = newPart("Handle", handleSize,
			doorCFrame * (frontOnX and CFrame.new(direction * 0.05, 0, innerWidth * 0.3) or CFrame.new(innerWidth * 0.3, 0, direction * 0.05)),
			dark, Enum.Material.Metal, body)
		handle.CanCollide = false

		-- Interior tier shelving + a light strip per tier, exactly like the
		-- growth-chamber reference, on every appliance -- not just the ones
		-- that hold plant samples -- so nothing reads as an empty shell.
		local tiers = entry.plantCabinet and 3 or 2
		for tier = 0, tiers - 1 do
			local shelfY = -size.Y * 0.32 + tier * (size.Y * 0.6 / math.max(1, tiers - 1))
			local shelfSize = frontOnX
				and Vector3.new(innerDepth * 0.72, 0.08, innerWidth * 0.84)
				or Vector3.new(innerWidth * 0.84, 0.08, innerDepth * 0.72)
			newPart("Shelf_" .. (tier + 1), shelfSize, body.CFrame * CFrame.new(0, shelfY - 0.24, 0),
				Color3.fromRGB(150, 156, 156), Enum.Material.Metal, body).CanCollide = false
			local lightSize = frontOnX and Vector3.new(0.1, 0.08, innerWidth * 0.72) or Vector3.new(innerWidth * 0.72, 0.08, 0.1)
			newPart("Light_" .. (tier + 1), lightSize,
				body.CFrame * interiorOffset(0, shelfY + size.Y * 0.1, innerDepth * 0.44),
				Color3.fromRGB(255, 248, 222), Enum.Material.Neon, body).CanCollide = false
		end

		-- Rear ventilation grille + a raised controller housing with a
		-- status screen -- the runtime anchors the repair prompt/LED here
		-- when present, exactly as it does on the growth chambers.
		local ventSize = frontOnX and Vector3.new(0.1, size.Y * 0.22, innerWidth * 0.42) or Vector3.new(innerWidth * 0.42, size.Y * 0.22, 0.1)
		newPart("VentilationGrille", ventSize, body.CFrame * interiorOffset(0, size.Y * 0.18, innerDepth * 0.94),
			Color3.fromRGB(68, 74, 78), Enum.Material.DiamondPlate, body).CanCollide = false
		local controllerSize = frontOnX and Vector3.new(innerDepth * 0.86, 0.6, innerWidth * 0.92) or Vector3.new(innerWidth * 0.92, 0.6, innerDepth * 0.86)
		local controller = newPart("ClimateController", controllerSize, body.CFrame * CFrame.new(0, size.Y * 0.5 + 0.3, 0),
			Color3.fromRGB(222, 226, 224), Enum.Material.Metal, body)
		controller.CanCollide = false
		newPart("ControllerScreen",
			frontOnX and Vector3.new(0.1, 0.4, innerWidth * 0.56) or Vector3.new(innerWidth * 0.56, 0.4, 0.1),
			body.CFrame * interiorOffset(0, size.Y * 0.5 + 0.3, -0.16), accent, Enum.Material.Neon, body).CanCollide = false

		-- Small caster wheels, like a real mobile lab cabinet.
		for _, across in ipairs({-innerWidth * 0.38, innerWidth * 0.38}) do
			for _, depthSign in ipairs({-1, 1}) do
				local wheelOffset
				if frontOnX then wheelOffset = CFrame.new(depthSign * innerDepth * 0.32, -size.Y / 2 - 0.2, across)
				else wheelOffset = CFrame.new(across, -size.Y / 2 - 0.2, depthSign * innerDepth * 0.32) end
				local wheel = newPart("CasterWheel", Vector3.new(0.34, 0.34, 0.2), body.CFrame * wheelOffset,
					Color3.fromRGB(28, 30, 32), Enum.Material.Rubber, body)
				wheel.Shape = Enum.PartType.Cylinder
				wheel.CanCollide = false
			end
		end

		-- Power hookup: a wall junction box and conduit on the BACK face
		-- (opposite the door), running down to a floor-level cable stub
		-- toward the wall it's packed against, so every appliance reads as
		-- actually wired in rather than just placed in the room.
		local backDirX = frontOnX and -direction or 0
		local backDirZ = frontOnX and 0 or -direction
		local backX = pos.X + backDirX * size.X / 2
		local backZ = pos.Z + backDirZ * size.Z / 2
		local boxSize = Vector3.new(0.42, 0.42, 0.42)
		local junction = newPart("PowerJunctionBox", boxSize,
			CFrame.new(backX + backDirX * boxSize.X * 0.45, pos.Y + size.Y * 0.3, backZ + backDirZ * boxSize.Z * 0.45),
			Color3.fromRGB(56, 58, 62), Enum.Material.Metal, body)
		junction.CanCollide = false
		junction.CastShadow = false
		local conduitH = math.max(size.Y * 0.38, 0.5)
		local conduit = newPart("PowerConduit", Vector3.new(0.14, conduitH, 0.14),
			CFrame.new(backX + backDirX * 0.14, pos.Y + size.Y * 0.3 - conduitH / 2, backZ + backDirZ * 0.14),
			Color3.fromRGB(26, 28, 31), Enum.Material.Metal, body)
		conduit.CanCollide = false
		conduit.CastShadow = false
		local cableLen = 0.85
		local cableSize = frontOnX and Vector3.new(cableLen, 0.08, 0.08) or Vector3.new(0.08, 0.08, cableLen)
		local cable = newPart("PowerCable", cableSize,
			CFrame.new(backX + backDirX * (0.14 + cableLen / 2), pos.Y - size.Y / 2 + 0.12, backZ + backDirZ * (0.14 + cableLen / 2)),
			Color3.fromRGB(18, 18, 19), Enum.Material.SmoothPlastic, body)
		cable.CanCollide = false
		cable.CastShadow = false
		return body

	elseif shape == "bench" then
		local topH = math.max(size.Y * 0.14, 0.15)
		local top = newPart("Top", Vector3.new(size.X, topH, size.Z),
			CFrame.new(pos.X, pos.Y + size.Y / 2 - topH / 2, pos.Z), entry.col, entry.mat, parent)
		local legT = math.min(size.X, size.Z) * 0.07
		local legH = math.max(size.Y - topH, 0.2)
		for _, s in ipairs({{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}) do
			local leg = newPart("Leg", Vector3.new(legT, legH, legT),
				CFrame.new(pos.X + s[1] * (size.X / 2 - legT), pos.Y - size.Y / 2 + legH / 2,
					pos.Z + s[2] * (size.Z / 2 - legT)),
				dark, Enum.Material.Metal, top)
			leg.CanCollide = false
		end
		return top

	elseif shape == "instrument" then
		local bodyH = size.Y * 0.55
		local body = newPart("Body", Vector3.new(size.X, bodyH, size.Z),
			CFrame.new(pos.X, pos.Y - size.Y / 2 + bodyH / 2, pos.Z), entry.col, entry.mat, parent)
		local panelH = math.max(size.Y - bodyH, 0.1)
		local panel = newPart("Panel", Vector3.new(size.X * 0.72, panelH, size.Z * 0.55),
			CFrame.new(pos.X, pos.Y - size.Y / 2 + bodyH + panelH / 2, pos.Z - size.Z * 0.12),
			panelColour, Enum.Material.SmoothPlastic, body)
		panel.CanCollide = false
		-- a small glowing indicator strip so even a tiny instrument reads
		-- as "a device" at a glance, not a plain block
		local led = newPart("IndicatorStrip", Vector3.new(size.X * 0.5, math.max(panelH * 0.18, 0.05), size.Z * 0.05),
			CFrame.new(pos.X, pos.Y - size.Y / 2 + bodyH + panelH * 0.78, pos.Z - size.Z * 0.12 + size.Z * 0.28),
			accent, Enum.Material.Neon, body)
		led.CanCollide = false
		led.CastShadow = false
		return body

	elseif shape == "rack" then
		local backT = math.max(size.Z * 0.14, 0.1)
		local back = newPart("Back", Vector3.new(size.X, size.Y, backT),
			CFrame.new(pos.X, pos.Y, pos.Z - size.Z / 2 + backT / 2), entry.col, entry.mat, parent)
		local shelfH = math.max(size.Y * 0.06, 0.08)
		for i = 1, 3 do
			local sy = pos.Y - size.Y / 2 + size.Y * (i / 4)
			local shelf = newPart("Shelf" .. i, Vector3.new(size.X, shelfH, size.Z),
				CFrame.new(pos.X, sy, pos.Z), entry.col, entry.mat, back)
			shelf.CanCollide = false
		end
		return back

	elseif shape == "planter" then
		-- A potted plant / flower box: a pot or trough with a soil cap and
		-- several stem+leaf clusters -- pure decoration, no door/handle.
		local potH = size.Y * 0.42
		local pot = newPart("Pot", Vector3.new(size.X, potH, size.Z),
			CFrame.new(pos.X, pos.Y - size.Y / 2 + potH / 2, pos.Z), entry.col, entry.mat, parent)
		local soil = newPart("Soil", Vector3.new(size.X * 0.86, potH * 0.22, size.Z * 0.86),
			CFrame.new(pos.X, pos.Y - size.Y / 2 + potH * 0.94, pos.Z), Color3.fromRGB(58, 42, 30), Enum.Material.Ground, pot)
		soil.CanCollide = false
		local clusters = entry.flowering and 4 or 3
		for i = 1, clusters do
			local ang = (i / clusters) * math.pi * 2 + (pos.X % 1)
			local rx = math.cos(ang) * size.X * 0.22
			local rz = math.sin(ang) * size.Z * 0.22
			local stemH = size.Y * (0.4 + (i % 3) * 0.06)
			local stem = newPart("Stem_" .. i, Vector3.new(size.X * 0.05, stemH, size.Z * 0.05),
				CFrame.new(pos.X + rx, pos.Y - size.Y / 2 + potH + stemH / 2, pos.Z + rz),
				Color3.fromRGB(58, 130, 66), Enum.Material.Grass, pot)
			stem.CanCollide = false
			local leafColour = entry.flowering
				and ({Color3.fromRGB(230, 90, 130), Color3.fromRGB(240, 200, 70), Color3.fromRGB(210, 100, 210)})[((i - 1) % 3) + 1]
				or Color3.fromRGB(72, 168, 84)
			local leaf = newPart("Leaf_" .. i, Vector3.new(size.X * 0.3, size.Y * 0.16, size.Z * 0.3),
				CFrame.new(pos.X + rx, pos.Y - size.Y / 2 + potH + stemH, pos.Z + rz),
				leafColour, entry.flowering and Enum.Material.Neon or Enum.Material.Grass, pot)
			leaf.CanCollide = false
			leaf.Shape = Enum.PartType.Ball
		end
		return pot

	elseif shape == "drawers" then
		-- Lab storage drawers / filing cabinet: a metal carcass with 3-4
		-- stacked drawer fronts and handles, so it reads as furniture rather
		-- than another appliance.
		local body = newPart("Body", size, CFrame.new(pos), entry.col, entry.mat, parent)
		local tiers = 3 + (math.floor(size.Y * 10) % 2)
		local frontOnX = wallSide == "W" or wallSide == "E"
		local frontDir = (wallSide == "W" or wallSide == "N") and 1 or -1
		for tier = 1, tiers do
			local fy = -size.Y / 2 + (tier - 0.5) * (size.Y / tiers)
			local frontSize = frontOnX
				and Vector3.new(size.X * 0.06, size.Y / tiers * 0.82, size.Z * 0.86)
				or Vector3.new(size.X * 0.86, size.Y / tiers * 0.82, size.Z * 0.06)
			local frontCFrame = frontOnX
				and CFrame.new(pos.X + frontDir * size.X / 2 * 0.97, pos.Y + fy, pos.Z)
				or CFrame.new(pos.X, pos.Y + fy, pos.Z + frontDir * size.Z / 2 * 0.97)
			local front = newPart("Drawer_" .. tier, frontSize, frontCFrame, accent, Enum.Material.Metal, body)
			front.CanCollide = false
			local handleSize = frontOnX and Vector3.new(0.06, 0.06, size.Z * 0.4) or Vector3.new(size.X * 0.4, 0.06, 0.06)
			local handle = newPart("DrawerHandle_" .. tier, handleSize,
				frontCFrame * CFrame.new(frontOnX and 0.05 or 0, 0, 0) * (frontOnX and CFrame.new(0, 0, 0) or CFrame.new(0, 0, 0.05)),
				dark, Enum.Material.Metal, body)
			handle.CanCollide = false
		end
		return body

	else -- "box": last-resort fallback, not used by anything in the
		-- catalogue any more, but kept so a future entry without a
		-- matching shape still gets a plate instead of a bare cube.
		local body = newPart("Body", size, CFrame.new(pos), entry.col, entry.mat, parent)
		local capH = math.min(size.Y * 0.08, 0.15)
		if capH > 0.03 then
			local cap = newPart("Cap", Vector3.new(size.X * 0.94, capH, size.Z * 0.94),
				CFrame.new(pos.X, pos.Y + size.Y / 2 + capH / 2, pos.Z), accent, entry.mat, body)
			cap.CanCollide = false
		end
		return body
	end
end

local function populateEquipmentCabinet(body, entry, size, wallSide, sampleCount, capacity)
	if not entry.plantCabinet or entry.kind == "Plant Growth Chamber" then return end
	local frontOnX = wallSide == "W" or wallSide == "E"
	local width = frontOnX and size.Z or size.X
	local depth = frontOnX and size.X or size.Z
	local shelfCount = capacity >= 9 and 4 or (capacity >= 6 and 3 or 2)
	for tier = 1, shelfCount do
		local y = -size.Y * 0.34 + (tier - 1) * (size.Y * 0.68 / math.max(1, shelfCount - 1))
		local shelfSize = frontOnX and Vector3.new(depth * 0.72, 0.1, width * 0.84)
			or Vector3.new(width * 0.84, 0.1, depth * 0.72)
		local shelf = newPart("EquipmentShelf_" .. tier, shelfSize, body.CFrame * CFrame.new(0, y, 0),
			Color3.fromRGB(138, 145, 147), Enum.Material.Metal, body)
		shelf.CanCollide = false
	end
	for slot = 1, capacity do
		local tier = math.floor((slot - 1) / 3)
		local column = (slot - 1) % 3
		local across = (column - 1) * width * 0.25
		local up = -size.Y * 0.34 + tier * (size.Y * 0.68 / math.max(1, shelfCount - 1))
		local offset = frontOnX and Vector3.new(0, up + 0.25, across) or Vector3.new(across, up + 0.25, 0)
		local base = body.CFrame * CFrame.new(offset)
		local pot = newPart("EquipmentPlant_" .. slot .. "_Tray", Vector3.new(0.58, 0.28, 0.52), base,
			Color3.fromRGB(126, 77, 45), Enum.Material.SmoothPlastic, body)
		local stem = newPart("EquipmentPlant_" .. slot .. "_Stem", Vector3.new(0.09, 0.48, 0.09),
			base * CFrame.new(0, 0.35, 0), Color3.fromRGB(58, 158, 70), Enum.Material.SmoothPlastic, body)
		local leaf = newPart("EquipmentPlant_" .. slot .. "_Leaf", Vector3.new(0.42, 0.1, 0.25),
			base * CFrame.new(0.17, 0.52, 0), Color3.fromRGB(72, 184, 82), Enum.Material.SmoothPlastic, body)
		for _, plantPart in ipairs({pot, stem, leaf}) do
			plantPart.CanCollide = false
			plantPart.CanTouch = false
			plantPart:SetAttribute("SampleSlot", slot)
			plantPart:SetAttribute("StoredTransparency", 0)
			if slot > sampleCount then plantPart.Transparency = 1 end
		end
	end
end

--=====================================================================
-- ROOM FIT-OUT
--=====================================================================
local EQUIP_TAG = "LabEquipment"
local placedCount = 0
local addGrowthCodeLabel

local function fitOutRoom(parent, room, levelY, levelName, rng, growthCodes, plantStationKind)
	local sides = {"W", "E", "N", "S"}
	local lenOf = {
		W = room.z2 - room.z1, E = room.z2 - room.z1,
		N = room.x2 - room.x1, S = room.x2 - room.x1,
	}
	local spans = {}
	for _, s in ipairs(sides) do
		spans[s] = freeSpans(lenOf[s], room.open[s])
	end

	local benchRuns = {}
	local index = 0
	local function wallFaceInset(side)
		local exterior = (side == "W" and room.x1 == 0)
			or (side == "E" and room.x2 == W)
			or (side == "N" and room.z1 == 0)
			or (side == "S" and room.z2 == L)
		return (exterior and EXT_T or INT_T / 2) + WALL_GAP
	end

	local function spawn(entry, side, at, lift, liftInset)
		index = index + 1
		placedCount = placedCount + 1
		local inset = liftInset or (wallFaceInset(side) + P(entry.d) / 2)
		local px, pz, size
		if side == "W" then
			px, pz = room.x1 + inset, room.z1 + at
			size = Vector3.new(E(entry.d), EH(entry.h), E(entry.w))
		elseif side == "E" then
			px, pz = room.x2 - inset, room.z1 + at
			size = Vector3.new(E(entry.d), EH(entry.h), E(entry.w))
		elseif side == "N" then
			px, pz = room.x1 + at, room.z1 + inset
			size = Vector3.new(E(entry.w), EH(entry.h), E(entry.d))
		else
			px, pz = room.x1 + at, room.z2 - inset
			size = Vector3.new(E(entry.w), EH(entry.h), E(entry.d))
		end
		local baseY = Y(levelY) + (lift and EH(COUNTER_H) or 0)
		local pos = Vector3.new(X(px), baseY + size.Y / 2, X(pz))
		local p = buildKind(parent, entry, pos, size, side)
		p.Name = entry.kind:gsub("%s", "") .. "_" .. room.number .. "_" .. index
		p:SetAttribute("Kind", entry.kind)
		p:SetAttribute("Room", room.name)
		p:SetAttribute("Level", levelName)
		p:SetAttribute("WallSide", side)
		-- Every placed unit -- including the densely-packed "run" duplicates
		-- added to fill out walls -- is tagged as real, functional equipment
		-- so it gets the same status LED, timer/nameplate, hazard behaviour,
		-- and catastrophic-failure system as everything else. (Previously
		-- "run"-class units were left untagged, which is why they looked
		-- like bare, undetailed boxes -- none of the runtime binding that
		-- adds those visuals ever ran on them.) Pure decoration (potted
		-- plants, drawers, ...) is the one exception -- it's not equipment,
		-- so it gets its own lightweight tag instead of the full status/
		-- hazard/failure system.
		if entry.class == "decor" then
			CollectionService:AddTag(p, "LabDecor")
		else
			CollectionService:AddTag(p, EQUIP_TAG)
		end
		if entry.plantCabinet then
			local capacity = entry.capacity or 6
			local sampleCount = math.clamp(1 + ((room.number * 3 + index * 5) % capacity), 1, capacity)
			local sampleIds = {}
			for sampleIndex = 1, sampleCount do
				table.insert(sampleIds, string.format("%s-P%02d", entry.kind:gsub("%s", ""):sub(1, 6):upper(), sampleIndex))
			end
			p:SetAttribute("Capacity", capacity)
			p:SetAttribute("SampleCount", sampleCount)
			p:SetAttribute("SampleIds", table.concat(sampleIds, "|"))
			p:SetAttribute("Occupied", sampleCount > 0)
			populateEquipmentCabinet(p, entry, size, side, sampleCount, capacity)
		end
		if entry.auto then
			p:SetAttribute("Auto", entry.auto)
			CollectionService:AddTag(p, "Automatable")
		end

		-- Equipment names and instructions are presented on the two large
		-- floor-level panels created by the runtime; no overhead label is used.
		return p
	end

	-- 1. fitted runs on the longest available walls
	local order = {}
	for _, s in ipairs(sides) do table.insert(order, s) end
	table.sort(order, function(a, b) return spansTotal(spans[a]) > spansTotal(spans[b]) end)

	-- Room status monitor: reserved FIRST, on the roomiest wall, so it never
	-- gets squeezed into a leftover corner sliver by equipment placed later.
	-- Large panel, mounted at eye level so it reads from across the room.
	do
		local monitorWidth = 220
		local mSide, mAt
		for _, side in ipairs(order) do
			local total = spansTotal(spans[side])
			local at = (total >= P(monitorWidth)) and takeSpan(spans[side], P(monitorWidth)) or nil
			if at then mSide, mAt = side, at; break end
		end
		if not mSide then
			-- Even the roomiest wall is tight: shrink to fit rather than
			-- falling back to a corner placement.
			for _, side in ipairs(order) do
				local total = spansTotal(spans[side])
				if total > 40 then
					local fitWidth = math.min(monitorWidth, (total - 4) * SCALE)
					local at = takeSpan(spans[side], P(fitWidth))
					if at then monitorWidth, mSide, mAt = fitWidth, side, at; break end
				end
			end
		end
		if mSide then
			local inset = wallFaceInset(mSide)
			local px, pz
			if mSide == "W" then px, pz = room.x1 + inset, room.z1 + mAt
			elseif mSide == "E" then px, pz = room.x2 - inset, room.z1 + mAt
			elseif mSide == "N" then px, pz = room.x1 + mAt, room.z1 + inset
			else px, pz = room.x1 + mAt, room.z2 - inset end
			local mOnX = (mSide == "W" or mSide == "E")
			local panelSize = mOnX and Vector3.new(0.2, EH(135), E(monitorWidth))
				or Vector3.new(E(monitorWidth), EH(135), 0.2)
			local baseY = Y(levelY) + EH(175)
			local mPos = Vector3.new(X(px), baseY + panelSize.Y / 2, X(pz))
			local panel = newPart("RoomMonitor_" .. room.number, panelSize, CFrame.new(mPos),
				Color3.fromRGB(22, 26, 30), Enum.Material.Metal, parent)
			panel.CanCollide = false
			panel:SetAttribute("Room", room.name)
			panel:SetAttribute("Level", levelName)
			CollectionService:AddTag(panel, "RoomMonitor")
			-- Slim backlit frame so the panel reads as a mounted screen, not a wall patch.
			local frameDepth = mOnX and Vector3.new(0.05, panelSize.Y + 0.5, panelSize.Z + 0.5)
				or Vector3.new(panelSize.X + 0.5, panelSize.Y + 0.5, 0.05)
			local frameOffset = (mSide == "W") and CFrame.new(-0.14, 0, 0)
				or (mSide == "E") and CFrame.new(0.14, 0, 0)
				or (mSide == "N") and CFrame.new(0, 0, -0.14)
				or CFrame.new(0, 0, 0.14)
			local frame = newPart("RoomMonitor_" .. room.number .. "_Frame", frameDepth,
				panel.CFrame * frameOffset, Color3.fromRGB(235, 200, 60), Enum.Material.Metal, parent)
			frame.CanCollide = false
			local face = (mSide == "W") and Enum.NormalId.Right
				or (mSide == "E") and Enum.NormalId.Left
				or (mSide == "N") and Enum.NormalId.Back
				or Enum.NormalId.Front
			local surface = Instance.new("SurfaceGui")
			surface.Name = "RoomMonitorSurface"
			surface.Face = face
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 60
			surface.AlwaysOnTop = false
			surface.Parent = panel
			local header = Instance.new("TextLabel")
			header.Name = "Header"
			header.Size = UDim2.new(1, 0, 0.22, 0)
			header.Position = UDim2.new(0, 0, 0, 0)
			header.BackgroundColor3 = Color3.fromRGB(235, 200, 60)
			header.BorderSizePixel = 0
			header.TextColor3 = Color3.fromRGB(20, 20, 20)
			header.TextScaled = true
			header.Font = Enum.Font.SourceSansBold
			header.Text = "ROOM MONITOR"
			header.Parent = surface
			local label = Instance.new("TextLabel")
			label.Name = "Status"
			label.Size = UDim2.new(1, 0, 0.78, 0)
			label.Position = UDim2.new(0, 0, 0.22, 0)
			label.BackgroundColor3 = Color3.fromRGB(14, 18, 20)
			label.BackgroundTransparency = 0.05
			label.BorderSizePixel = 0
			label.TextColor3 = Color3.fromRGB(120, 235, 170)
			label.TextScaled = true
			label.TextWrapped = true
			label.Font = Enum.Font.Code
			label.Text = room.name .. "\nSTATUS LOADING..."
			label.Parent = surface
		end
	end

	-- Emergency Kit: a LIMITED, single-use supply (about 1 room in 3, not
	-- every room), avatar-sized, reserved right after the monitor so it
	-- always gets real wall space too. Using one destroys it permanently --
	-- health only comes back by finding another kit. The interaction and
	-- healing behaviour is wired at runtime (bindEmergencyKit); this just
	-- builds the physical cabinet.
	if room.number % 3 == 0 then
		local kitWidth, kitDepth, kitHeight = 62, 30, 154 -- cm, ~ a standing avatar's footprint/height
		local kSide, kAt
		for _, side in ipairs(order) do
			local at = takeSpan(spans[side], P(kitWidth))
			if at then kSide, kAt = side, at; break end
		end
		if kSide then
			local inset = wallFaceInset(kSide) + P(kitDepth) / 2
			local px, pz
			if kSide == "W" then px, pz = room.x1 + inset, room.z1 + kAt
			elseif kSide == "E" then px, pz = room.x2 - inset, room.z1 + kAt
			elseif kSide == "N" then px, pz = room.x1 + kAt, room.z1 + inset
			else px, pz = room.x1 + kAt, room.z2 - inset end
			local kOnX = (kSide == "W" or kSide == "E")
			local cabinetSize = kOnX and Vector3.new(E(kitDepth), EH(kitHeight), E(kitWidth))
				or Vector3.new(E(kitWidth), EH(kitHeight), E(kitDepth))
			local baseY = Y(levelY)
			local cabinet = newPart("EmergencyKit_" .. room.number, cabinetSize,
				CFrame.new(X(px), baseY + cabinetSize.Y / 2, X(pz)), Color3.fromRGB(225, 40, 35), Enum.Material.SmoothPlastic, parent)
			cabinet.CanCollide = true
			cabinet:SetAttribute("Room", room.name)
			cabinet:SetAttribute("Level", levelName)
			cabinet:SetAttribute("WallSide", kSide)
			CollectionService:AddTag(cabinet, "EmergencyKit")

			-- White cross + label on the door face so it reads as a first-aid
			-- cabinet, not a generic red box.
			local face = (kSide == "W") and Enum.NormalId.Right
				or (kSide == "E") and Enum.NormalId.Left
				or (kSide == "N") and Enum.NormalId.Back
				or Enum.NormalId.Front
			local surface = Instance.new("SurfaceGui")
			surface.Name = "EmergencyKitFace"
			surface.Face = face
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 60
			surface.AlwaysOnTop = false
			surface.Parent = cabinet
			local crossV = Instance.new("Frame")
			crossV.Size = UDim2.new(0.22, 0, 0.55, 0)
			crossV.Position = UDim2.new(0.39, 0, 0.12, 0)
			crossV.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			crossV.BorderSizePixel = 0
			crossV.Parent = surface
			local crossH = Instance.new("Frame")
			crossH.Size = UDim2.new(0.55, 0, 0.22, 0)
			crossH.Position = UDim2.new(0.12, 0, 0.28, 0)
			crossH.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			crossH.BorderSizePixel = 0
			crossH.Parent = surface
			local kitLabel = Instance.new("TextLabel")
			kitLabel.Size = UDim2.new(1, 0, 0.22, 0)
			kitLabel.Position = UDim2.new(0, 0, 0.72, 0)
			kitLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			kitLabel.BackgroundTransparency = 0.05
			kitLabel.BorderSizePixel = 0
			kitLabel.Text = "EMERGENCY KIT"
			kitLabel.TextColor3 = Color3.fromRGB(200, 30, 25)
			kitLabel.TextScaled = true
			kitLabel.Font = Enum.Font.SourceSansBold
			kitLabel.Parent = surface

			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "EmergencyKitPrompt"
			prompt.ActionText = "Use Emergency Kit"
			prompt.ObjectText = "Restore health"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = cabinet
		end
	end

	-- Reserve wall space for this room's share of R1-R200 before normal
	-- furniture is packed. A shuffled wall order keeps the chambers spread
	-- around the building, but every one remains fridge-like and wall-backed.
	for codeIndex, code in ipairs(growthCodes or {}) do
		local sizeVariants = {
			{w = 100, d = 90,  h = 220, capacity = 6},
			{w = 115, d = 95,  h = 235, capacity = 9},
			{w = 130, d = 100, h = 250, capacity = 12},
			{w = 145, d = 105, h = 265, capacity = 16},
		}
		local variant = sizeVariants[((tonumber(code:match("%d+")) or codeIndex) - 1) % #sizeVariants + 1]
		local entry = {
			kind = "Plant Growth Chamber",
			label = code,
			w = variant.w, d = variant.d, h = variant.h,
			col = Color3.fromRGB(215, 220, 218),
			mat = Enum.Material.Metal,
			shape = "appliance",
		}
		local chamber
		local firstSide = rng.int(1, #order)
		-- Placement ladder. The preferred size is tried first on every wall;
		-- if the room's walls are already busy (the monitor, the emergency
		-- kit and the guaranteed plant station are all reserved ahead of the
		-- chambers) it steps down through the smaller cabinets, and only as a
		-- last resort tightens the neighbour gap. Without this ladder a code
		-- that found no span was silently dropped, which is exactly why the
		-- narrow east-side rooms kept landing 1-2 chambers under their share
		-- and the building missed its 50-per-floor target.
		local fallbackOrder = {variant}
		local smaller = {}
		for _, alt in ipairs(sizeVariants) do
			if alt ~= variant then table.insert(smaller, alt) end
		end
		table.sort(smaller, function(a, b) return a.w < b.w end)
		for _, alt in ipairs(smaller) do table.insert(fallbackOrder, alt) end
		-- Bottom of the ladder: a compact under-counter cabinet that exists
		-- only to rescue the very last code in a room whose walls are down to
		-- slivers. It is never picked as a room's preferred size, so it does
		-- not change how the building normally looks.
		table.insert(fallbackOrder, {w = 85, d = 78, h = 196, capacity = 5})

		for _, gap in ipairs({ALONG_GAP, 10}) do
			for _, candidate in ipairs(fallbackOrder) do
				for try = 0, #order - 1 do
					local side = order[((firstSide + try - 1) % #order) + 1]
					local at = takeSpanGap(spans[side], P(candidate.w), gap)
					if at then
						variant = candidate
						entry.w, entry.d, entry.h = candidate.w, candidate.d, candidate.h
						chamber = spawn(entry, side, at, false)
						break
					end
				end
				if chamber then break end
			end
			if chamber then break end
		end
		if chamber then
			local codeNumber = tonumber(code:match("%d+")) or codeIndex
			local capacity = variant.capacity
			local sampleCount = math.clamp(1 + ((codeNumber * 7) % capacity), 1, capacity)
			local sampleIds = {}
			for sampleIndex = 1, sampleCount do
				table.insert(sampleIds, string.format("%s-S%02d", code, sampleIndex))
			end
			-- Start safe; the runtime introduces a small, player-scaled workload.
			local initiallyFailed = false
			local floorLabel = levelName == "Basement" and "BASEMENT"
				or ("FLOOR " .. (levelName:match("%d+") or levelName))
			local failureReasons = {
				"Temperature control fault", "Humidity sensor drift", "Ventilation fan blocked",
				"Door seal leak", "Lighting circuit fault", "Nutrient pump pressure low",
			}
			local temperature = initiallyFailed and (31 + codeNumber % 8) or (22 + codeNumber % 4)
			local humidity = initiallyFailed and (38 + codeNumber % 19) or (67 + codeNumber % 14)
			local ventilation = initiallyFailed and (12 + codeNumber % 24) or (62 + codeNumber % 29)
			chamber.Name = "GrowthChamber_" .. code
			chamber:SetAttribute("GrowthCode", code)
			chamber:SetAttribute("FloorLabel", floorLabel)
			chamber:SetAttribute("Capacity", capacity)
			chamber:SetAttribute("SampleCount", sampleCount)
			chamber:SetAttribute("SampleIds", table.concat(sampleIds, "|"))
			chamber:SetAttribute("Occupied", sampleCount > 0)
			chamber:SetAttribute("PlantId", sampleIds[1] or code)
			chamber:SetAttribute("GrowthStage", 0)
			chamber:SetAttribute("Treatments", "")
			chamber:SetAttribute("Genome", "Wild Type")
			chamber:SetAttribute("PlantLife", 100)
			chamber:SetAttribute("RecoveryUntil", 0)
			chamber:SetAttribute("Moisture", humidity)
			chamber:SetAttribute("Temperature", temperature)
			chamber:SetAttribute("Humidity", humidity)
			chamber:SetAttribute("Ventilation", ventilation)
			chamber:SetAttribute("OperationStarted", os.time() - (codeNumber * 173) % 10800)
			chamber:SetAttribute("GerminationDate", os.date("%Y-%m-%d %H:%M", os.time() - (codeNumber % 6 + 1) * 86400))
			chamber:SetAttribute("FunctionalState", initiallyFailed and "FAILED" or "WORKING")
			chamber:SetAttribute("RepairKey", "R")
			chamber:SetAttribute("RepairInstruction", initiallyFailed
				and ("Go to " .. floorLabel .. " • CHAMBER " .. code .. " • HOLD R TO REPAIR")
				or "Unit working • E TAKE / DROP • R REPAIR")
			chamber:SetAttribute("FailureReason", initiallyFailed and failureReasons[((codeNumber - 1) % #failureReasons) + 1] or "")
			chamber:SetAttribute("FailureSince", initiallyFailed and os.time() or 0)
			chamber:SetAttribute("EvacuationDestination", "")
			CollectionService:AddTag(chamber, "PlantGrowthChamber")
			-- Reference-inspired controlled-environment cabinet: insulated
			-- body, glass door, bright tier lighting, tray shelves, rear vents,
			-- header controller and caster wheels. The translucent body is only
			-- a backing volume; the metal frame gives it a refrigerator profile.
			chamber.Material = Enum.Material.Glass
			chamber.Color = Color3.fromRGB(205, 216, 212)
			chamber.Transparency = 0.88
			local wallSide = chamber:GetAttribute("WallSide")
			local frontOnX = wallSide == "W" or wallSide == "E"
			local direction = ((wallSide == "E") or (wallSide == "S")) and -1 or 1
			local frameColour = Color3.fromRGB(62, 69, 72)
			local innerWidth = frontOnX and chamber.Size.Z or chamber.Size.X
			local innerDepth = frontOnX and chamber.Size.X or chamber.Size.Z
			local shellColour = codeNumber % 5 == 0 and Color3.fromRGB(43, 48, 50)
				or (codeNumber % 3 == 0 and Color3.fromRGB(198, 203, 202) or Color3.fromRGB(232, 234, 231))
			local function interiorOffset(across, up, fromFront)
				if frontOnX then return CFrame.new(direction * (innerDepth / 2 - fromFront), up, across) end
				return CFrame.new(across, up, direction * (innerDepth / 2 - fromFront))
			end
			local frameParts = {}
			local shellThickness = 0.18
			-- Opaque insulated rear, side, top and floor panels leave only
			-- the front door transparent, matching real growth cabinets.
			if frontOnX then
				table.insert(frameParts, newPart("InsulatedBack",
					Vector3.new(shellThickness, chamber.Size.Y * 0.96, innerWidth),
					chamber.CFrame * CFrame.new(-direction * (innerDepth / 2 - shellThickness / 2), 0, 0),
					shellColour, Enum.Material.Metal, chamber))
				for _, sideSign in ipairs({-1, 1}) do
					table.insert(frameParts, newPart("InsulatedSide",
						Vector3.new(innerDepth, chamber.Size.Y * 0.96, shellThickness),
						chamber.CFrame * CFrame.new(0, 0, sideSign * (innerWidth / 2 - shellThickness / 2)),
						shellColour, Enum.Material.Metal, chamber))
				end
				table.insert(frameParts, newPart("InsulatedTop", Vector3.new(innerDepth, shellThickness, innerWidth),
					chamber.CFrame * CFrame.new(0, chamber.Size.Y / 2 - shellThickness / 2, 0),
					shellColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("InsulatedFloor", Vector3.new(innerDepth, shellThickness, innerWidth),
					chamber.CFrame * CFrame.new(0, -chamber.Size.Y / 2 + shellThickness / 2, 0),
					shellColour, Enum.Material.Metal, chamber))
			else
				table.insert(frameParts, newPart("InsulatedBack",
					Vector3.new(innerWidth, chamber.Size.Y * 0.96, shellThickness),
					chamber.CFrame * CFrame.new(0, 0, -direction * (innerDepth / 2 - shellThickness / 2)),
					shellColour, Enum.Material.Metal, chamber))
				for _, sideSign in ipairs({-1, 1}) do
					table.insert(frameParts, newPart("InsulatedSide",
						Vector3.new(shellThickness, chamber.Size.Y * 0.96, innerDepth),
						chamber.CFrame * CFrame.new(sideSign * (innerWidth / 2 - shellThickness / 2), 0, 0),
						shellColour, Enum.Material.Metal, chamber))
				end
				table.insert(frameParts, newPart("InsulatedTop", Vector3.new(innerWidth, shellThickness, innerDepth),
					chamber.CFrame * CFrame.new(0, chamber.Size.Y / 2 - shellThickness / 2, 0),
					shellColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("InsulatedFloor", Vector3.new(innerWidth, shellThickness, innerDepth),
					chamber.CFrame * CFrame.new(0, -chamber.Size.Y / 2 + shellThickness / 2, 0),
					shellColour, Enum.Material.Metal, chamber))
			end
			local frontDistance = innerDepth / 2 + 0.08
			if frontOnX then
				local frontX = direction * frontDistance
				table.insert(frameParts, newPart("GlassFrameLeft", Vector3.new(0.2, chamber.Size.Y * 0.94, 0.22), chamber.CFrame * CFrame.new(frontX, 0, -chamber.Size.Z * 0.46), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameRight", Vector3.new(0.2, chamber.Size.Y * 0.94, 0.22), chamber.CFrame * CFrame.new(frontX, 0, chamber.Size.Z * 0.46), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameTop", Vector3.new(0.2, 0.24, chamber.Size.Z * 0.94), chamber.CFrame * CFrame.new(frontX, chamber.Size.Y * 0.47, 0), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameBottom", Vector3.new(0.2, 0.24, chamber.Size.Z * 0.94), chamber.CFrame * CFrame.new(frontX, -chamber.Size.Y * 0.47, 0), frameColour, Enum.Material.Metal, chamber))
			else
				local frontZ = direction * frontDistance
				table.insert(frameParts, newPart("GlassFrameLeft", Vector3.new(0.22, chamber.Size.Y * 0.94, 0.2), chamber.CFrame * CFrame.new(-chamber.Size.X * 0.46, 0, frontZ), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameRight", Vector3.new(0.22, chamber.Size.Y * 0.94, 0.2), chamber.CFrame * CFrame.new(chamber.Size.X * 0.46, 0, frontZ), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameTop", Vector3.new(chamber.Size.X * 0.94, 0.24, 0.2), chamber.CFrame * CFrame.new(0, chamber.Size.Y * 0.47, frontZ), frameColour, Enum.Material.Metal, chamber))
				table.insert(frameParts, newPart("GlassFrameBottom", Vector3.new(chamber.Size.X * 0.94, 0.24, 0.2), chamber.CFrame * CFrame.new(0, -chamber.Size.Y * 0.47, frontZ), frameColour, Enum.Material.Metal, chamber))
			end

			-- Four ventilated shelves and four white grow-light strips.
			for tier = 0, 3 do
				local shelfY = -chamber.Size.Y * 0.35 + tier * chamber.Size.Y * 0.22
				local shelfSize = frontOnX
					and Vector3.new(innerDepth * 0.72, 0.1, innerWidth * 0.86)
					or Vector3.new(innerWidth * 0.86, 0.1, innerDepth * 0.72)
				local shelf = newPart("PlantShelf_" .. (tier + 1), shelfSize,
					chamber.CFrame * CFrame.new(0, shelfY - 0.28, 0), Color3.fromRGB(128, 135, 136), Enum.Material.Metal, chamber)
				local lightSize = frontOnX and Vector3.new(0.14, 0.1, innerWidth * 0.75) or Vector3.new(innerWidth * 0.75, 0.1, 0.14)
				local light = newPart("GrowLight_" .. (tier + 1), lightSize,
					chamber.CFrame * interiorOffset(0, shelfY + chamber.Size.Y * 0.13, innerDepth * 0.45),
					Color3.fromRGB(255, 248, 222), Enum.Material.Neon, chamber)
				table.insert(frameParts, shelf); table.insert(frameParts, light)
			end

			-- Rear ventilation grille and a raised controller housing.
			local ventSize = frontOnX and Vector3.new(0.12, chamber.Size.Y * 0.24, innerWidth * 0.45) or Vector3.new(innerWidth * 0.45, chamber.Size.Y * 0.24, 0.12)
			local vent = newPart("VentilationGrille", ventSize,
				chamber.CFrame * interiorOffset(0, chamber.Size.Y * 0.2, innerDepth * 0.92), Color3.fromRGB(70, 78, 82), Enum.Material.DiamondPlate, chamber)
			table.insert(frameParts, vent)
			local controllerSize = frontOnX and Vector3.new(innerDepth * 0.9, 0.72, innerWidth * 0.94) or Vector3.new(innerWidth * 0.94, 0.72, innerDepth * 0.9)
			local controller = newPart("ClimateController", controllerSize,
				chamber.CFrame * CFrame.new(0, chamber.Size.Y * 0.5 + 0.34, 0), Color3.fromRGB(226, 229, 228), Enum.Material.Metal, chamber)
			controller.CanCollide = false
			local controllerFace = newPart("ControllerScreen",
				frontOnX and Vector3.new(0.12, 0.46, innerWidth * 0.58) or Vector3.new(innerWidth * 0.58, 0.46, 0.12),
				chamber.CFrame * interiorOffset(0, chamber.Size.Y * 0.5 + 0.34, -0.18),
				initiallyFailed and Color3.fromRGB(220, 55, 45) or Color3.fromRGB(40, 150, 95), Enum.Material.Neon, chamber)
			controllerFace.CanCollide = false
			controllerFace:SetAttribute("ChamberStatusLamp", true)

			-- Small caster wheels like the mobile cabinets in the references.
			for _, across in ipairs({-innerWidth * 0.38, innerWidth * 0.38}) do
				for _, depthSign in ipairs({-1, 1}) do
					local wheelOffset
					if frontOnX then wheelOffset = CFrame.new(depthSign * innerDepth * 0.32, -chamber.Size.Y / 2 - 0.23, across)
					else wheelOffset = CFrame.new(across, -chamber.Size.Y / 2 - 0.23, depthSign * innerDepth * 0.32) end
					local wheel = newPart("CasterWheel", Vector3.new(0.38, 0.38, 0.22), chamber.CFrame * wheelOffset,
						Color3.fromRGB(28, 30, 32), Enum.Material.Rubber, chamber)
					wheel.Shape = Enum.PartType.Cylinder
					wheel.CanCollide = false
				end
			end

			local door = chamber:FindFirstChild("Door")
			if door then
				door.Material = Enum.Material.Glass
				door.Color = Color3.fromRGB(205, 232, 225)
				door.Transparency = 0.38
				addGrowthCodeLabel(door, code)
			end
			for _, framePart in ipairs(frameParts) do
				framePart.CanCollide = false
				framePart.CanTouch = false
			end

			-- Individually addressable germinated-seed trays. Capacity follows
			-- physical cabinet size: 4, 6, 8, or 12 plants.
			for slot = 1, capacity do
				local tier = math.floor((slot - 1) / 3)
				local column = (slot - 1) % 3
				local across = (column - 1) * innerWidth * 0.27
				if slot == 10 then across = 0 end
				local up = -chamber.Size.Y * 0.35 + tier * chamber.Size.Y * 0.22
				local plantBase = chamber.CFrame * interiorOffset(across, up, 0.48)
				local slotName = string.format("ChamberSample_%02d_", slot)
				local pot = newPart(slotName .. "Tray", Vector3.new(0.64, 0.32, 0.56), plantBase,
					Color3.fromRGB(128, 75, 43), Enum.Material.SmoothPlastic, chamber)
				local stem = newPart(slotName .. "Stem", Vector3.new(0.1, 0.55, 0.1),
					plantBase * CFrame.new(0, 0.4, 0), Color3.fromRGB(55, 155, 68), Enum.Material.SmoothPlastic, chamber)
				local leafL = newPart(slotName .. "LeafL", Vector3.new(0.36, 0.09, 0.22),
					plantBase * CFrame.new(-0.18, 0.53, 0), Color3.fromRGB(72, 184, 82), Enum.Material.SmoothPlastic, chamber)
				local leafR = newPart(slotName .. "LeafR", Vector3.new(0.36, 0.09, 0.22),
					plantBase * CFrame.new(0.18, 0.68, 0), Color3.fromRGB(72, 184, 82), Enum.Material.SmoothPlastic, chamber)
				for _, plantPart in ipairs({pot, stem, leafL, leafR}) do
					plantPart.CanCollide = false
					plantPart.CanTouch = false
					plantPart:SetAttribute("SampleSlot", slot)
					plantPart:SetAttribute("StoredTransparency", 0)
					if slot > sampleCount then plantPart.Transparency = 1 end
				end
			end

		end
	end

	-- Every level receives the complete five-machine plant-development
	-- route, distributed across separate rooms and packed against walls.
	-- This guarantees that players and all 50 bots can finish a full cycle.
	if plantStationKind then
		local stationColours = {
			["Growth Hormone Mixer"] = Color3.fromRGB(100, 190, 110),
			["GMO Injector"] = Color3.fromRGB(170, 100, 215),
			["Nutrient Infuser"] = Color3.fromRGB(210, 165, 65),
			["UV Growth Scanner"] = Color3.fromRGB(70, 145, 225),
			["Pollination Station"] = Color3.fromRGB(225, 125, 170),
		}
		local entry = {
			kind = plantStationKind,
			w = 115, d = 95, h = 235, capacity = 8,
			col = stationColours[plantStationKind] or COL.green,
			mat = Enum.Material.Metal,
			shape = "appliance",
			plantCabinet = true,
			auto = "pulse",
		}
		local firstSide = rng.int(1, #order)
		for try = 0, #order - 1 do
			local side = order[((firstSide + try - 1) % #order) + 1]
			local at = takeSpan(spans[side], P(entry.w))
			if at then spawn(entry, side, at, false); break end
		end
	end

	local area = (room.x2 - room.x1) * (room.z2 - room.z1)
	-- Every wall gets its own island run, and each run keeps packing units
	-- for as long as its wall physically has room -- not a fixed rep count,
	-- so no wall is left with a leftover gap a unit could still have filled.
	-- A short streak of consecutive misses (picked entry just didn't fit
	-- the last sliver) is what actually ends a wall's run, not a target.
	if #BY_CLASS.run > 0 then
		for _, side in ipairs(order) do
			local guard, misses = 0, 0
			while guard < 200 and misses < 6 do
				guard = guard + 1
				local entry = weightedPick(BY_CLASS.run, rng)
				local need = P(entry.w)
				local at = takeSpan(spans[side], need)
				if at then
					misses = 0
					spawn(entry, side, at, false)
					table.insert(benchRuns, {
						side = side,
						inset = wallFaceInset(side) + P(entry.d) / 2,
						spans = {{at - need / 2 + 12, at + need / 2 - 12}},
						height = entry.h,
					})
				else
					misses = misses + 1
				end
			end
		end
	end

	-- 2. free-standing units -- fills whatever wall space the island runs
	-- above didn't claim, again running until every wall genuinely can't
	-- take another unit rather than stopping at an area-based headcount.
	if #BY_CLASS.floor > 0 then
		local guard, misses = 0, 0
		while guard < 3000 and misses < 24 do
			guard = guard + 1
			local entry = weightedPick(BY_CLASS.floor, rng)
			local side = order[rng.int(1, #order)]
			local at = takeSpan(spans[side], P(entry.w))
			if at then
				misses = 0
				spawn(entry, side, at, false)
			else
				misses = misses + 1
			end
		end
	end

	-- 2b. decoration pass -- potted plants, flower planters, and lab
	-- storage furniture pack into whatever slivers are still left on every
	-- wall once real equipment can no longer fit, using a much smaller gap
	-- since decor carries no status readout for a neighbour to overlap.
	-- This is what actually gets a room to "no free wall space" rather
	-- than just "no free space equipment can use."
	if #BY_CLASS.decor > 0 then
		for _, side in ipairs(order) do
			local guard, misses = 0, 0
			while guard < 300 and misses < 8 do
				guard = guard + 1
				local entry = weightedPick(BY_CLASS.decor, rng)
				local at = takeSpanGap(spans[side], P(entry.w), 6)
				if at then
					misses = 0
					spawn(entry, side, at, false)
				else
					misses = misses + 1
				end
			end
		end
	end

	-- 3. instruments on the bench runs
	if #BY_CLASS.top > 0 then
		for _, run in ipairs(benchRuns) do
			local slots = rng.int(1, 3)
			for _ = 1, slots do
				local entry = weightedPick(BY_CLASS.top, rng)
				local at = takeSpan(run.spans, P(entry.w))
				if at then spawn(entry, run.side, at, true, run.inset) end
			end
		end
	end

	-- 4. safety kit, one of each, wherever it still fits
	for _, entry in ipairs(BY_CLASS.duty) do
		for _, side in ipairs(order) do
			local at = takeSpan(spans[side], P(entry.w))
			if at then spawn(entry, side, at, false); break end
		end
	end

	-- (Room status monitor is reserved earlier, right after `order` is
	-- computed, so it always claims prime wall space instead of a leftover
	-- corner sliver — see the block above, right after the wall-side sort.)
end

--------------------------------------------------------------------
-- R1-R200 PLANT GROWTH CHAMBERS
-- Fifty variable-size growing chambers are placed on every level. Codes are
-- printed on the door itself, so labels never float across the room.
--------------------------------------------------------------------
addGrowthCodeLabel = function(door, code)
	local labelFaces = (door.Size.X < door.Size.Z)
		and {Enum.NormalId.Left, Enum.NormalId.Right}
		or {Enum.NormalId.Front, Enum.NormalId.Back}
	for _, normal in ipairs(labelFaces) do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "GrowthCodeLabel"
		surface.Face = normal
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 70
		surface.AlwaysOnTop = false
		surface.Parent = door

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.72, 0, 0.3, 0)
		label.Position = UDim2.new(0.14, 0, 0.08, 0)
		label.BackgroundColor3 = Color3.fromRGB(20, 44, 34)
		label.BackgroundTransparency = 0.08
		label.BorderSizePixel = 0
		label.Text = code
		label.TextColor3 = Color3.fromRGB(170, 255, 185)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = surface

		local instruction = Instance.new("TextLabel")
		instruction.Size = UDim2.new(0.82, 0, 0.18, 0)
		instruction.Position = UDim2.new(0.09, 0, 0.72, 0)
		instruction.BackgroundTransparency = 1
		instruction.Text = "E TAKE / DROP  •  R REPAIR"
		instruction.TextColor3 = Color3.fromRGB(225, 235, 225)
		instruction.TextScaled = true
		instruction.Font = Enum.Font.Gotham
		instruction.Parent = surface
	end
end

-- Usable wall a room can actually back a chamber against: each of the four
-- walls minus the corner keep-outs at both of its ends.
local function growthWallWeight(room)
	local acrossX = math.max(0, (room.x2 - room.x1) - 2 * CORNER)
	local acrossZ = math.max(0, (room.z2 - room.z1) - 2 * CORNER)
	return math.max(acrossX * 2 + acrossZ * 2, 1)
end

-- The 50 R-codes a floor owns are shared out in proportion to that usable
-- wall, not evenly. The plan is deliberately lopsided -- one long room runs
-- the entire west side while the east rooms are short bays -- so an even
-- split kept asking the narrow bays for more chambers than their walls could
-- physically hold (the overflow was silently dropped) while the long west
-- room sat half empty. Largest-remainder rounding keeps each floor's total
-- at exactly 50 and the codes contiguous.
local function growthCodesForRoom(firstCode, roomIndex, rooms)
	local weights, total = {}, 0
	for i, r in ipairs(rooms) do
		weights[i] = growthWallWeight(r)
		total = total + weights[i]
	end

	local counts, assigned, remainders = {}, 0, {}
	for i = 1, #rooms do
		local exact = 50 * weights[i] / total
		counts[i] = math.floor(exact)
		assigned = assigned + counts[i]
		table.insert(remainders, {index = i, frac = exact - counts[i]})
	end
	table.sort(remainders, function(a, b)
		if a.frac == b.frac then return a.index < b.index end
		return a.frac > b.frac
	end)
	for i = 1, 50 - assigned do
		local pick = remainders[i]
		if not pick then break end
		counts[pick.index] = counts[pick.index] + 1
	end

	local before = 0
	for i = 1, roomIndex - 1 do before = before + counts[i] end
	local codes = {}
	for i = 1, counts[roomIndex] do
		table.insert(codes, "R" .. (firstCode + before + i - 1))
	end
	return codes
end

--=====================================================================
-- BUILD
--=====================================================================
local BOTTOM_LEVEL = -1
local TOP_LEVEL    = LEVELS[#LEVELS].index

local basementModel, basementRooms = buildBasement()
local levelModels = {}

local GUARANTEED_PLANT_STATIONS = {
	"Growth Hormone Mixer",
	"GMO Injector",
	"Nutrient Infuser",
	"UV Growth Scanner",
	"Pollination Station",
}
for _, lv in ipairs(LEVELS) do
	local m = buildLevelShell(lv.index, lv.name, lv.label, lv.rooms)
	levelModels[lv.index] = m
	local folder = Instance.new("Folder")
	folder.Name = "Equipment"
	folder.Parent = m
	for roomIndex, r in ipairs(lv.rooms) do
		-- The ground floor's first room is the entrance lobby: it gets a
		-- full equipment fit-out just like every other room, but the mid-
		-- room strip where the role-selection kiosks/spawn/chevrons live
		-- (roughly z 150-460 in the room's own coordinates) is reserved as
		-- a keep-clear zone first, the same way a door or window reserves
		-- clearance, so wall equipment never grows over the kiosks.
		local isEntranceLobby = (lv.index == 0 and roomIndex == 1)
		if isEntranceLobby then
			table.insert(r.open.W, {at = 150, width = 310})
			table.insert(r.open.E, {at = 150, width = 310})
		end
		fitOutRoom(folder, r, lv.index * F2F, lv.name,
			newRng(RNG_SEED + lv.index * 1000 + r.number),
			growthCodesForRoom(1 + lv.index * 50, roomIndex, lv.rooms),
			GUARANTEED_PLANT_STATIONS[roomIndex])
	end
end

do
	local folder = Instance.new("Folder")
	folder.Name = "Equipment"
	folder.Parent = basementModel
	for roomIndex, r in ipairs(basementRooms) do
		-- Basement's code block starts right after every above-ground
		-- level's own 50-code block, whatever the level count is (used to
		-- be a hard-coded 151, back when there were only 3 levels above
		-- it -- with more levels that collided with a level's own codes).
		fitOutRoom(folder, r, BOTTOM_LEVEL * F2F, "Basement",
			newRng(RNG_SEED + 7777 + r.number),
			growthCodesForRoom(1 + #LEVELS * 50, roomIndex, basementRooms),
			GUARANTEED_PLANT_STATIONS[roomIndex])
	end
end

-- Visible test scientists are distributed over EVERY level -- basement
-- included -- at a fixed count per floor, rather than a fixed total split
-- across just the original four. That keeps bot density per floor roughly
-- constant as floors are added or removed instead of spreading the same
-- headcount thinner across a bigger building. BOTS_PER_LEVEL is kept
-- moderate (not the 50/floor first asked for) because with basement + all
-- LEVELS that would put ~950 concurrent pathfinding NPCs on one server --
-- a real lag/timeout risk. This keeps the total in the low hundreds while
-- still reading as far denser per floor than before. The runtime assigns
-- each one the same loop a player performs: answer a failed-chamber alarm,
-- visibly carry one germinated plant through a growth process, and rescue
-- it into a working R chamber with capacity.
--=====================================================================
-- CORRIDOR FIXTURES -- health stations and sidearm cabinets
--
-- These hang on the corridor walls rather than inside rooms on purpose:
-- room wall space is already fully budgeted (monitor, kit, plant station,
-- the floor's share of R-code chambers, then furniture), so putting these
-- in rooms would push chambers back under the 50-per-floor target. The
-- corridor is circulation space nobody was using. They are CanCollide off
-- so they can never block a doorway or an NPC's path.
--=====================================================================
	-- Ten of each support pickup per floor gives players a nearby recovery or
	-- weapon option without putting a cabinet in a doorway.
	local HEALTH_STATIONS_PER_FLOOR = 10
	local WEAPON_STATIONS_PER_FLOOR = 10

-- Weapon kinds the corridor cabinets hand out, one per cabinet per floor.
-- Declared here because the cabinets are built long before IMPACT_STYLE (which
-- defines the weapons themselves) appears further down the file.
local PC_WEAPONS = {"Lab Sidearm", "Lab Shotgun", "Lab Rifle"}

-- Poster copy. Drawn procedurally from Frames and TextLabels -- no imported
-- decals, so nothing here depends on an uploaded image asset.
local POSTER_TITLES = {
	{title = "GERMINATION RATE BY CULTIVAR", seed = 3, colour = Color3.fromRGB(46, 122, 84),
	 body = "n = 400 seeds per lot, 4 replicates of 100. Counts at day 4 and day 8. Rolled paper substrate, 20/30 C alternating."},
	{title = "SEED VIABILITY - TETRAZOLIUM", seed = 5, colour = Color3.fromRGB(150, 52, 52),
	 body = "1% TZ solution, 30 C for 4 h in darkness. Embryo staining scored 1-5. Confirms viability where germination is dormant."},
	{title = "MOISTURE CONTENT & STORAGE LIFE", seed = 2, colour = Color3.fromRGB(52, 96, 150),
	 body = "Oven method, 103 C for 17 h. Each 1% drop in moisture roughly doubles safe storage life within the working range."},
	{title = "ISTA SAMPLING PROTOCOL", seed = 7, colour = Color3.fromRGB(96, 74, 148),
	 body = "Primary samples drawn from the lot, combined, then reduced by successive halving to the submitted sample."},
	{title = "THERMAL TIME MODEL", seed = 4, colour = Color3.fromRGB(150, 108, 40),
	 body = "Base temperature Tb = 4.2 C. Accumulated degree-days predict time to 50% emergence across the tested range."},
	{title = "GMO EVENT DETECTION - qPCR", seed = 6, colour = Color3.fromRGB(38, 108, 130),
	 body = "Event-specific primers against the junction region. Reference gene normalisation, LOD 0.05% w/w."},
	{title = "HORMONE PRIMING RESPONSE", seed = 8, colour = Color3.fromRGB(120, 60, 110),
	 body = "Gibberellin soak breaks dormancy in stratification-requiring lots. Dose response measured over 5 concentrations."},
	{title = "PATHOGEN SCREENING WORKFLOW", seed = 9, colour = Color3.fromRGB(140, 84, 36),
	 body = "Blotter incubation 7 days, 22 C, 12 h NUV. Fungal structures identified under stereo and compound microscopy."},
}

	local function buildCorridorFixtures(parent, levelY, levelName, rooms)
		if not parent then return end

		-- Build one shared wall-space allocator for every corridor fixture. Door
		-- openings are excluded with the same generous clearance used by room
		-- equipment, and the end margins keep pickups away from entrance glazing.
		local function corridorOpenings(onWest)
			local openings = {}
			for _, room in ipairs(rooms or {}) do
				local belongs = (onWest and room.plan == "L") or ((not onWest) and room.plan == "R")
				if belongs then
					local side = onWest and "E" or "W"
					for _, opening in ipairs(room.open[side] or {}) do
						table.insert(openings, {at = room.z1 + opening.at, width = opening.width})
					end
				end
			end
			return openings
		end

		local available = {
			west = freeSpans(L, corridorOpenings(true)),
			east = freeSpans(L, corridorOpenings(false)),
		}

		-- Taking the centre of the longest remaining span distributes fixtures
		-- along the full corridor instead of clustering them near one stairwell.
		local function takeCentred(spans, needed)
			local bestIndex, bestLength
			for index, span in ipairs(spans) do
				local length = span[2] - span[1]
				if length >= needed and (not bestLength or length > bestLength) then
					bestIndex, bestLength = index, length
				end
			end
			if not bestIndex then return nil end

			local span = table.remove(spans, bestIndex)
			local centre = (span[1] + span[2]) / 2
			local half = needed / 2
			local separation = 18
			if centre - half - separation > span[1] then
				table.insert(spans, {span[1], centre - half - separation})
			end
			if centre + half + separation < span[2] then
				table.insert(spans, {centre + half + separation, span[2]})
			end
			return centre
		end

		local function reserveCorridorSpot(preferWest, width)
			local first = preferWest and "west" or "east"
			local second = preferWest and "east" or "west"
			local at = takeCentred(available[first], P(width))
			if at then return first == "west", at end
			at = takeCentred(available[second], P(width))
			if at then return second == "west", at end
			error("No door-safe corridor wall space remains for " .. levelName)
		end

		for i = 1, HEALTH_STATIONS_PER_FLOOR do
			-- Alternate walls so you can always see one from anywhere in the run.
			local depth, width, height = 18, 55, 70
			local onWest, pz = reserveCorridorSpot(i % 2 == 1, width)
			local px = onWest and (CORR_X1 + INT_T / 2 + depth / 2) or (CORR_X2 - INT_T / 2 - depth / 2)

		local station = newPart("HealthStation_" .. levelName .. "_" .. i,
			Vector3.new(E(depth), EH(height), E(width)),
			CFrame.new(X(px), Y(levelY) + EH(height) / 2 + EH(110), X(pz)),
			Color3.fromRGB(225, 40, 35), Enum.Material.SmoothPlastic, parent)
		station.CanCollide = false
		station:SetAttribute("Level", levelName)
		CollectionService:AddTag(station, "EmergencyKit")

		local face = Instance.new("SurfaceGui")
		face.Name = "EmergencyKitFace"
		face.Face = onWest and Enum.NormalId.Right or Enum.NormalId.Left
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 60
		face.AlwaysOnTop = false
		face.Parent = station
		local crossV = Instance.new("Frame")
		crossV.Size = UDim2.new(0.2, 0, 0.5, 0)
		crossV.Position = UDim2.new(0.4, 0, 0.1, 0)
		crossV.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		crossV.BorderSizePixel = 0
		crossV.Parent = face
		local crossH = Instance.new("Frame")
		crossH.Size = UDim2.new(0.5, 0, 0.2, 0)
		crossH.Position = UDim2.new(0.25, 0, 0.25, 0)
		crossH.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		crossH.BorderSizePixel = 0
		crossH.Parent = face
		local caption = Instance.new("TextLabel")
		caption.Name = "KitCaption"
		caption.Size = UDim2.new(1, 0, 0.26, 0)
		caption.Position = UDim2.new(0, 0, 0.7, 0)
		caption.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		caption.BackgroundTransparency = 0.05
		caption.BorderSizePixel = 0
		caption.Text = "HEALTH"
		caption.TextColor3 = Color3.fromRGB(200, 30, 25)
		caption.TextScaled = true
		caption.Font = Enum.Font.SourceSansBold
		caption.Parent = face

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EmergencyKitPrompt"
		prompt.ActionText = "Use Health Station"
		prompt.ObjectText = "Restore health"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = station
	end

		-- Ten weapon cabinets per floor, distributed across both corridor walls.
		for i = 1, WEAPON_STATIONS_PER_FLOOR do
			local depth, width, height = 22, 70, 120
			local onWest, pz = reserveCorridorSpot(i % 2 == 0, width)
			local px = onWest and (CORR_X1 + INT_T / 2 + depth / 2) or (CORR_X2 - INT_T / 2 - depth / 2)
			local cabinet = newPart("SidearmCabinet_" .. levelName .. "_" .. i,
			Vector3.new(E(depth), EH(height), E(width)),
			CFrame.new(X(px), Y(levelY) + EH(height) / 2 + EH(80), X(pz)),
			Color3.fromRGB(52, 58, 68), Enum.Material.Metal, parent)
		cabinet.CanCollide = false
		cabinet:SetAttribute("Level", levelName)
		-- One weapon type per cabinet, so every floor offers all three.
		local weaponKind = PC_WEAPONS[((i - 1) % #PC_WEAPONS) + 1]
		cabinet:SetAttribute("ToolKind", weaponKind)
		CollectionService:AddTag(cabinet, "LabToolDispenser")

		local face = Instance.new("SurfaceGui")
		face.Name = "SidearmCabinetFace"
			face.Face = onWest and Enum.NormalId.Right or Enum.NormalId.Left
		face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		face.PixelsPerStud = 60
		face.AlwaysOnTop = false
		face.Parent = cabinet
		local caption = Instance.new("TextLabel")
		caption.Size = UDim2.new(0.9, 0, 0.3, 0)
		caption.Position = UDim2.new(0.05, 0, 0.12, 0)
		caption.BackgroundColor3 = Color3.fromRGB(235, 195, 35)
		caption.BackgroundTransparency = 0.05
		caption.BorderSizePixel = 0
		caption.Text = (weaponKind:gsub("^Lab ", "")):upper()
		caption.TextColor3 = Color3.fromRGB(25, 25, 25)
		caption.TextScaled = true
		caption.Font = Enum.Font.SourceSansBold
		caption.Parent = face
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(0.9, 0, 0.4, 0)
		sub.Position = UDim2.new(0.05, 0, 0.48, 0)
		sub.BackgroundTransparency = 1
		sub.Text = "PC • MOBILE • TABLET\nHold E / tap to equip\nAim at the target marker"
		sub.TextColor3 = Color3.fromRGB(235, 240, 245)
		sub.TextScaled = true
		sub.Font = Enum.Font.Gotham
		sub.Parent = face
	end

	-- Gas service pipes. Deliberately obvious, and very dangerous: a round
	-- into one takes out a chunk of the room. CanCollide is off so they never
	-- block a walking route, but CanQuery stays on so they can be shot.
	for i, px in ipairs({CORR_X1 + 20, CORR_X2 - 20}) do
		local pipe = newPart("GasPipe_" .. levelName .. "_" .. i,
			Vector3.new(E(16), EH(16), X(L - 240)),
				CFrame.new(X(px), Y(levelY) + Y(WALL_H) - EH(18), X(L / 2)),
			Color3.fromRGB(216, 176, 42), Enum.Material.Metal, parent)
		pipe.CanCollide = false
		pipe:SetAttribute("GasPipe", true)
		pipe:SetAttribute("Level", levelName)
		CollectionService:AddTag(pipe, "GasPipe")

		-- hazard collars every few metres so it reads as a gas line
		for band = 1, 6 do
			local collar = newPart("GasPipeBand_" .. levelName .. "_" .. i .. "_" .. band,
				Vector3.new(E(19), EH(19), X(26)),
					CFrame.new(X(px), Y(levelY) + Y(WALL_H) - EH(18), X(L * band / 7)),
				Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic, parent)
			collar.CanCollide = false
			collar.CastShadow = false
		end
	end

	-- Scientific posters. Every one is a real part with CanQuery left on, so
	-- the weapon raycast can hit it and punch a hole that stays put.
		for i = 1, #POSTER_TITLES do
			local depth, width, height = 6, 118, 84
			local onWest, pz = reserveCorridorSpot(i % 2 == 0, width)
			local px = onWest and (CORR_X1 + INT_T / 2 + depth / 2) or (CORR_X2 - INT_T / 2 - depth / 2)

		local poster = newPart("Poster_" .. levelName .. "_" .. i,
			Vector3.new(E(depth), EH(height), E(width)),
			CFrame.new(X(px), Y(levelY) + EH(height) / 2 + EH(120), X(pz)),
			Color3.fromRGB(242, 240, 233), Enum.Material.SmoothPlastic, parent)
		poster.CanCollide = false
		poster:SetAttribute("ShootablePoster", true)
		poster:SetAttribute("Holes", 0)
		poster:SetAttribute("Level", levelName)
		CollectionService:AddTag(poster, "LabPoster")

		local art = Instance.new("SurfaceGui")
		art.Name = "PosterFace"
		art.Face = onWest and Enum.NormalId.Right or Enum.NormalId.Left
		art.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		art.PixelsPerStud = 55
		art.AlwaysOnTop = false
		art.Parent = poster

		local entry = POSTER_TITLES[i]
		local band = Instance.new("Frame")
		band.Size = UDim2.new(1, 0, 0.2, 0)
		band.BackgroundColor3 = entry.colour
		band.BorderSizePixel = 0
		band.Parent = art
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(0.92, 0, 0.8, 0)
		title.Position = UDim2.new(0.04, 0, 0.1, 0)
		title.BackgroundTransparency = 1
		title.Text = entry.title
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		title.TextScaled = true
		title.Font = Enum.Font.GothamBold
		title.Parent = band

		-- A little chart so it reads as a research poster rather than a sign.
		local plot = Instance.new("Frame")
		plot.Size = UDim2.new(0.44, 0, 0.5, 0)
		plot.Position = UDim2.new(0.04, 0, 0.28, 0)
		plot.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
		plot.BorderSizePixel = 0
		plot.Parent = art
		for barIndex = 1, 5 do
			local h = 0.2 + ((entry.seed * barIndex) % 7) / 9
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0.14, 0, h, 0)
			bar.Position = UDim2.new(0.05 + (barIndex - 1) * 0.19, 0, 1 - h, 0)
			bar.BackgroundColor3 = entry.colour
			bar.BorderSizePixel = 0
			bar.Parent = plot
		end

		local body = Instance.new("TextLabel")
		body.Size = UDim2.new(0.44, 0, 0.5, 0)
		body.Position = UDim2.new(0.52, 0, 0.28, 0)
		body.BackgroundTransparency = 1
		body.Text = entry.body
		body.TextColor3 = Color3.fromRGB(48, 52, 58)
		body.TextScaled = true
		body.TextWrapped = true
		body.Font = Enum.Font.Gotham
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.Parent = art

		local footer = Instance.new("TextLabel")
		footer.Size = UDim2.new(0.92, 0, 0.12, 0)
		footer.Position = UDim2.new(0.04, 0, 0.84, 0)
		footer.BackgroundTransparency = 1
		footer.Text = "SEED TESTING LABORATORY  -  " .. levelName:upper()
		footer.TextColor3 = Color3.fromRGB(120, 126, 134)
		footer.TextScaled = true
		footer.Font = Enum.Font.Gotham
		footer.TextXAlignment = Enum.TextXAlignment.Left
		footer.Parent = art
	end
end

	buildCorridorFixtures(basementModel, BOTTOM_LEVEL * F2F, "Basement", BASEMENT_ROOMS)
	for _, lv in ipairs(LEVELS) do
		buildCorridorFixtures(levelModels[lv.index], lv.index * F2F, lv.name, lv.rooms)
	end

-- Publish every room's rectangle, already converted to stud space, so the
-- runtime can answer "is this player in the same room as this bot?" exactly.
-- A plain radius test cannot do that here: the west room runs the full 267
-- studs of the plan, so any radius wide enough to cover it also reaches
-- straight through the corridor wall into the rooms opposite.
do
	local entries = {}
	local function addRooms(levelName, rooms, levelY)
		for _, r in ipairs(rooms) do
			table.insert(entries, string.format("%s:%s:%.1f:%.1f:%.1f:%.1f:%.1f",
				levelName, r.name, X(r.x1), X(r.z1), X(r.x2), X(r.z2), Y(levelY)))
		end
	end
	addRooms("Basement", basementRooms, BOTTOM_LEVEL * F2F)
	for _, lv in ipairs(LEVELS) do
		addRooms(lv.name, lv.rooms, lv.index * F2F)
	end
	root:SetAttribute("RoomIndex", table.concat(entries, ";"))
end

local BOTS_PER_LEVEL = 20
local workerFolder = Instance.new("Folder")
workerFolder.Name = "WorkerTestNPCs"
workerFolder.Parent = root
local botNumber = 0
local botLevelSpecs = {{y = BOTTOM_LEVEL * F2F, count = BOTS_PER_LEVEL,
	name = "Basement", rooms = basementRooms}}
for _, lv in ipairs(LEVELS) do
	table.insert(botLevelSpecs, {y = lv.index * F2F, count = BOTS_PER_LEVEL,
		name = lv.name, rooms = lv.rooms})
end

-- Some staff sit at a workstation instead of patrolling. Seats are placed
-- from the ROOM SCHEDULE, not from the preserved OfficeFitout: that fit-out
-- was built for an earlier version of the building and its geometry now sits
-- outside the current footprint entirely, so seating from it would put staff
-- in mid-air outside the walls.
local SEATED_PER_LEVEL = 5
for _, levelSpec in ipairs(botLevelSpecs) do
	local seatedThisLevel = 0
	for slot = 1, levelSpec.count do
		botNumber = botNumber + 1
		local xcm = (slot % 2 == 0) and 260 or 1040
		local zcm = 190 + ((slot - 1) * 137) % 1690
		-- skip index 1: that is the long west room, which is circulation space
		local seatRoom
		if seatedThisLevel < SEATED_PER_LEVEL and levelSpec.rooms then
			seatRoom = levelSpec.rooms[seatedThisLevel + 2]
		end
		local botModel = buildWorkerBot(workerFolder, botNumber, xcm, zcm, levelSpec.y, seatRoom ~= nil)
		-- The bot's index WITHIN ITS OWN FLOOR (1..BOTS_PER_LEVEL). The runtime
		-- throttles how many workers are busy per floor using this. It used to
		-- throttle on the global BotNumber instead, which counts straight
		-- through every floor (basement 1-20, Level_1 21-40, ... Level_8
		-- 161-180) and was compared against a cap of at most 50 -- so every
		-- bot above 50 sat in permanent "Adaptive standby" and floors 3 and up
		-- never moved at all.
		if botModel then
			botModel:SetAttribute("LevelSlot", slot)
			if seatRoom then
				seatedThisLevel = seatedThisLevel + 1
				botModel:SetAttribute("Seated", true)
				botModel:SetAttribute("Room", seatRoom.name)
				-- Sit a third of the way in from the room's west wall, facing
				-- the middle of the room. The seated pose is built facing -Z,
				-- which is the model's LookVector, so lookAt orients it.
				local seatHeight = Y(levelSpec.y) + 2.45
				local centreX = (seatRoom.x1 + seatRoom.x2) / 2
				local centreZ = (seatRoom.z1 + seatRoom.z2) / 2
				local seatX = seatRoom.x1 + (seatRoom.x2 - seatRoom.x1) * 0.3
				local seatCF = CFrame.lookAt(
					Vector3.new(X(seatX), seatHeight, X(centreZ)),
					Vector3.new(X(centreX), seatHeight, X(centreZ)))
				botModel:PivotTo(seatCF)
				buildWorkstation(workerFolder, seatCF, botModel.Name)
			end
		end
	end
end

-- Hunt bookkeeping: how many targets exist, and how many are down. The HUD
-- and the kill feed both read these off the model.
root:SetAttribute("BotsTotal", botNumber)
root:SetAttribute("BotsKilled", 0)

-- Wall-mounted QA board: the autonomous workers update this during play,
-- making the scenario test visible instead of hiding it in server output.
-- Mounted on the CORRIDOR wall (never inside a room), well above any door's
-- head height, so equipment placed against a room's own walls can never end
-- up in front of it.
-- Oversized floating NPC-test board removed; status remains in the compact HUD.

-- roof, punched for the shafts
local topY = TOP_LEVEL * F2F + WALL_H + SLAB
slabWithHoles(root, "Roof", -EXT_T, -EXT_T, W + EXT_T, L + EXT_T, topY, SLAB, ELEV_HOLES, C.roof)
wall(root, "Parapet_W", 0, -EXT_T, 0, L + EXT_T, EXT_T, topY, 110, {}, C.ext, Enum.Material.Concrete)
wall(root, "Parapet_E", W, -EXT_T, W, L + EXT_T, EXT_T, topY, 110, {}, C.ext, Enum.Material.Concrete)
wall(root, "Parapet_N", -EXT_T, 0, W + EXT_T, 0, EXT_T, topY, 110, {}, C.ext, Enum.Material.Concrete)
wall(root, "Parapet_S", -EXT_T, L, W + EXT_T, L, EXT_T, topY, 110, {}, C.ext, Enum.Material.Concrete)

buildStairTower(BOTTOM_LEVEL, TOP_LEVEL, false)
buildStairTower(BOTTOM_LEVEL, TOP_LEVEL, true)
-- Runtime route guidance uses these exact stair-lane coordinates. Keeping
-- them on the generated model avoids hard-coded world positions inside the
-- server scripts and guarantees an upper-floor route follows both flights.
root:SetAttribute("FloorRiseStuds", Y(F2F))
root:SetAttribute("StairWestLaneX", X((TX1 + 10 + TXM) / 2))
root:SetAttribute("StairEastLaneX", X((TXM + TX2 - 10) / 2))
-- These describe the north tower's switchback specifically (the runtime's
-- manual floor-by-floor fallback route always walks through that one
-- tower) -- same numeric values buildStairTower(..., false) itself used.
root:SetAttribute("StairNorthZ", X(-100))
root:SetAttribute("StairSouthZ", X(-400))
-- So the fallback router (below) can clamp to however many floors this
-- building actually has instead of a hard-coded 3-floors-plus-basement
-- assumption from when there were only 3 floors.
root:SetAttribute("FloorMinLevel", BOTTOM_LEVEL)
root:SetAttribute("FloorMaxLevel", TOP_LEVEL)
for _, spec in ipairs(ELEVATORS) do buildElevator(spec, BOTTOM_LEVEL, TOP_LEVEL) end

slab(root, "Apron_East",  W, 100, W + 400, L * 0.94, 0, 20, C.slab)
slab(root, "Apron_West", -400, 100, 0, L * 0.94, 0, 20, C.slab)
slabWithHoles(root, "Apron_South", 60, L, W * 0.9, L + 350, 0, 20,
	{{x1 = TX1, x2 = TX2, z1 = L, z2 = L + 350}}, C.slab)

local pad = 700
-- Soil must surround the foundations, not fill the basement and stair flights.
slabWithHoles(root, "SitePad", -pad, -pad - 500, W + pad, L + pad, -2, 30, {
	{x1 = TX1 - EXT_T, x2 = TX2 + EXT_T, z1 = -460 - EXT_T, z2 = 0},
	{x1 = 0, x2 = W, z1 = 0, z2 = L},
	{x1 = TX1 - EXT_T, x2 = TX2 + EXT_T, z1 = L, z2 = L + 460 + EXT_T},
},
	Color3.fromRGB(122, 136, 112), Enum.Material.Grass)

-- The template Baseplate is 16 studs thick: it used to fill the entire
-- basement. Keep its exterior surface and store the original for recovery.
do
	local storage = game:GetService("ServerStorage")
	local base = Workspace:FindFirstChild("Baseplate") or storage:FindFirstChild("LaboratoryOriginalBaseplate")
	if base and base:IsA("BasePart") and base.CFrame.Rotation == CFrame.identity then
		local oldGround = Workspace:FindFirstChild("LaboratoryFoundationGround")
		if oldGround then oldGround:Destroy() end
		local ground = Instance.new("Folder")
		ground.Name, ground.Parent = "LaboratoryFoundationGround", Workspace
		local minX, maxX = base.Position.X - base.Size.X / 2, base.Position.X + base.Size.X / 2
		local minZ, maxZ = base.Position.Z - base.Size.Z / 2, base.Position.Z + base.Size.Z / 2
		local hx1, hx2, hz1, hz2 = X(-EXT_T), X(W + EXT_T), X(-460 - EXT_T), X(L + 460 + EXT_T)
		local function outside(name, x1, z1, x2, z2)
			if x2 <= x1 or z2 <= z1 then return end
			local piece = base:Clone()
			piece.Name = name
			piece.Size = Vector3.new(x2 - x1, base.Size.Y, z2 - z1)
			piece.CFrame = CFrame.new((x1 + x2) / 2, base.Position.Y, (z1 + z2) / 2)
			piece.Parent = ground
		end
		outside("West", minX, minZ, hx1, maxZ)
		outside("East", hx2, minZ, maxX, maxZ)
		outside("North", hx1, minZ, hx2, hz1)
		outside("South", hx1, hz2, hx2, maxZ)
		base.Name, base.Parent = "LaboratoryOriginalBaseplate", storage
	end
end

--=====================================================================
-- SITE WORKS
--
-- Regenerated from W and L every build, so it always fits the building
-- that was just generated. Everything here stays strictly OUTSIDE the
-- footprint x[0..W] z[0..L] -- the only things south of the building are
-- the forecourt and entrance canopy, which belong there.
--=====================================================================
do
	local site = Instance.new("Folder")
	site.Name = "SiteWorks"
	site.Parent = root

	local rng = newRng(RNG_SEED + 4242)
	local FENCE_X1, FENCE_X2 = -pad + 90, W + pad - 90
	local FENCE_Z1, FENCE_Z2 = -pad - 400, L + pad - 90
	local fenceGreen = Color3.fromRGB(46, 104, 58)
	local GATE_X1, GATE_X2 = 460, 740        -- lines up with the south entrance

	-- perimeter fence, with a gap on the south run for the gate
	wall(site, "Fence_S", FENCE_X1, FENCE_Z2, FENCE_X2, FENCE_Z2, 14, 0, 190,
		{{at = GATE_X1 - FENCE_X1, width = GATE_X2 - GATE_X1, head = 190}}, fenceGreen, Enum.Material.Metal)
	wall(site, "Fence_N", FENCE_X1, FENCE_Z1, FENCE_X2, FENCE_Z1, 14, 0, 190, {}, fenceGreen, Enum.Material.Metal)
	wall(site, "Fence_W", FENCE_X1, FENCE_Z1, FENCE_X1, FENCE_Z2, 14, 0, 190, {}, fenceGreen, Enum.Material.Metal)
	wall(site, "Fence_E", FENCE_X2, FENCE_Z1, FENCE_X2, FENCE_Z2, 14, 0, 190, {}, fenceGreen, Enum.Material.Metal)

	-- barred gate across the opening
	for i = 0, 11 do
		local gx = GATE_X1 + (GATE_X2 - GATE_X1) * i / 11
		newPart("GateBar_" .. i, Vector3.new(X(9), Y(180), X(9)),
			CFrame.new(X(gx), Y(90), X(FENCE_Z2)), Color3.fromRGB(28, 34, 30), Enum.Material.Metal, site)
	end
	newPart("GateRail", Vector3.new(X(GATE_X2 - GATE_X1), Y(12), X(12)),
		CFrame.new(X((GATE_X1 + GATE_X2) / 2), Y(174), X(FENCE_Z2)), Color3.fromRGB(28, 34, 30), Enum.Material.Metal, site)

	-- Small canopy at the single west-lobby entrance, clear of both stair towers.
	slab(site, "Canopy", -160, 170, 0, 330, 270, 16, Color3.fromRGB(206, 210, 214), Enum.Material.Metal)
	for _, cz in ipairs({180, 320}) do
		newPart("CanopyPost", Vector3.new(X(16), Y(254), X(16)),
			CFrame.new(X(-145), Y(127), X(cz)), Color3.fromRGB(150, 155, 160), Enum.Material.Metal, site)
	end

	-- planters either side of the door
	for i, px in ipairs({390, 810}) do
		newPart("Planter_" .. i, Vector3.new(X(120), Y(70), X(120)),
			CFrame.new(X(px), Y(35), X(L + 90)), Color3.fromRGB(176, 168, 150), Enum.Material.Concrete, site)
		newPart("PlanterSoil_" .. i, Vector3.new(X(104), Y(16), X(104)),
			CFrame.new(X(px), Y(72), X(L + 90)), Color3.fromRGB(84, 66, 48), Enum.Material.Ground, site)
		for f = 1, 4 do
			newPart("PlanterShrub_" .. i .. "_" .. f, Vector3.new(X(34), Y(46), X(34)),
				CFrame.new(X(px + rng.int(-30, 30)), Y(100), X(L + 90 + rng.int(-30, 30))),
				Color3.fromRGB(64, 122, 62), Enum.Material.Grass, site)
		end
	end

	-- flagpole
	newPart("FlagPole", Vector3.new(X(10), Y(560), X(10)),
		CFrame.new(X(900), Y(280), X(L + 210)), Color3.fromRGB(214, 216, 220), Enum.Material.Metal, site)
	newPart("Flag", Vector3.new(X(4), Y(90), X(150)),
		CFrame.new(X(900), Y(500), X(L + 285)), Color3.fromRGB(200, 208, 216), Enum.Material.Fabric, site)

	-- parking bays and cars on the south forecourt
	local function buildCar(name, cx, cz, colour)
		newPart(name .. "_Body", Vector3.new(X(170), Y(80), X(360)),
			CFrame.new(X(cx), Y(60), X(cz)), colour, Enum.Material.Metal, site)
		newPart(name .. "_Cabin", Vector3.new(X(150), Y(60), X(170)),
			CFrame.new(X(cx), Y(126), X(cz + 10)), Color3.fromRGB(80, 96, 112), Enum.Material.Glass, site)
		for _, wx in ipairs({-80, 80}) do
			for _, wz in ipairs({-115, 115}) do
				local wheel = newPart(name .. "_Wheel", Vector3.new(X(26), Y(58), X(58)),
					CFrame.new(X(cx + wx), Y(28), X(cz + wz)), Color3.fromRGB(30, 30, 32), Enum.Material.Rubber, site)
				wheel.Shape = Enum.PartType.Cylinder
			end
		end
	end
	local carColours = {
		Color3.fromRGB(180, 60, 55), Color3.fromRGB(60, 80, 150),
		Color3.fromRGB(220, 220, 224), Color3.fromRGB(70, 74, 80),
	}
	for bay = 0, 4 do
		local bx = 900 + bay * 220 -- outside the south stair tower; full car-width bays
		newPart("BayLine_" .. bay, Vector3.new(X(6), Y(4), X(200)),
			CFrame.new(X(bx), Y(2), X(L + 220)), Color3.fromRGB(238, 238, 232), Enum.Material.SmoothPlastic, site)
		if bay < 4 then
			buildCar("Car_" .. bay, bx + 110, L + 215, carColours[bay + 1])
		end
	end

	-- greenhouses on the west apron
	for g = 1, 3 do
		local gz = 260 + (g - 1) * 620
		slab(site, "GreenhouseBase_" .. g, -370, gz, -70, gz + 460, 4, 12, Color3.fromRGB(150, 146, 138), Enum.Material.Concrete)
		for _, corner in ipairs({{-370, gz}, {-70, gz}, {-370, gz + 460}, {-70, gz + 460}}) do
			newPart("GreenhouseFrame_" .. g, Vector3.new(X(14), Y(230), X(14)),
				CFrame.new(X(corner[1]), Y(115), X(corner[2])), Color3.fromRGB(196, 200, 204), Enum.Material.Metal, site)
		end
		local glassSides = {
			{-370, gz, -70, gz}, {-370, gz + 460, -70, gz + 460},
			{-370, gz, -370, gz + 460}, {-70, gz, -70, gz + 460},
		}
		for si, side in ipairs(glassSides) do
			local gl = wall(site, "GreenhouseGlass_" .. g .. "_" .. si,
				side[1], side[2], side[3], side[4], 8, 0, 210, {}, Color3.fromRGB(186, 216, 224), Enum.Material.Glass)
		end
		local roof = slab(site, "GreenhouseRoof_" .. g, -370, gz, -70, gz + 460, 240, 10,
			Color3.fromRGB(196, 222, 230), Enum.Material.Glass)
		roof.Transparency = 0.5
		-- crop benches inside
		for b = 0, 2 do
			newPart("GreenhouseBench_" .. g .. "_" .. b, Vector3.new(X(70), Y(20), X(400)),
				CFrame.new(X(-330 + b * 100), Y(80), X(gz + 230)), Color3.fromRGB(96, 138, 84), Enum.Material.Grass, site)
		end
	end

	-- trial crop plots on the east apron
	for plot = 0, 1 do
		local px = W + 90 + plot * 170
		slab(site, "TrialPlot_" .. plot, px, 220, px + 140, L * 0.9, 6, 14,
			Color3.fromRGB(96, 74, 54), Enum.Material.Ground)
		for row = 0, 9 do
			newPart("CropRow_" .. plot .. "_" .. row, Vector3.new(X(120), Y(26), X(70)),
				CFrame.new(X(px + 70), Y(20), X(300 + row * 160)),
				Color3.fromRGB(84, 142, 70), Enum.Material.Grass, site)
		end
	end

	-- street trees, kept out of the building, the aprons and the forecourt
	local function buildTree(name, tx, tz)
		newPart(name .. "_Trunk", Vector3.new(X(30), Y(240), X(30)),
			CFrame.new(X(tx), Y(120), X(tz)), Color3.fromRGB(94, 68, 46), Enum.Material.Wood, site)
		for c = 1, 3 do
			local crown = newPart(name .. "_Crown", Vector3.new(X(150 - c * 22), Y(150 - c * 22), X(150 - c * 22)),
				CFrame.new(X(tx + rng.int(-20, 20)), Y(250 + c * 42), X(tz + rng.int(-20, 20))),
				Color3.fromRGB(52, 104 + c * 8, 50), Enum.Material.Grass, site)
			crown.Shape = Enum.PartType.Ball
		end
	end
	local n = 0
	for i = 0, 7 do   -- west strip
		n = n + 1; buildTree("Tree_" .. n, -560 + rng.int(-60, 60), -200 + i * 330)
	end
	for i = 0, 7 do   -- east strip
		n = n + 1; buildTree("Tree_" .. n, W + 560 + rng.int(-60, 60), -200 + i * 330)
	end
	for i = 0, 5 do   -- north band, in front of the building
		n = n + 1; buildTree("Tree_" .. n, -300 + i * 380, -560 + rng.int(-80, 80))
	end
	for i = 0, 5 do   -- south band, beyond the forecourt
		n = n + 1; buildTree("Tree_" .. n, -300 + i * 380, L + 520 + rng.int(-60, 60))
	end
end

--=====================================================================
-- OFFICE FIT-OUT
-- A desk and a shelf in each room, placed from the room rectangle so they
-- sit in the clear middle of the floor rather than fighting the equipment
-- packed against the walls.
--=====================================================================
do
	local office = Instance.new("Folder")
	office.Name = "OfficeFitout"
	office.Parent = root

	local function fitOutOffice(rooms, levelY, levelName)
		for index, r in ipairs(rooms) do
			local width, depth = r.x2 - r.x1, r.z2 - r.z1
			if width > 200 and depth > 200 then
				local seatHeight = Y(levelY) + 2.45
				-- desk, facing across the room
				local deskX = r.x1 + width * 0.62
				local deskZ = r.z1 + depth * 0.34
				local cf = CFrame.lookAt(
					Vector3.new(X(deskX), seatHeight, X(deskZ)),
					Vector3.new(X(r.x1 + width * 0.5), seatHeight, X(deskZ)))
				buildWorkstation(office, cf, levelName .. "_" .. index)

				-- a shelf unit against the clear part of the floor
				local shelfX = r.x1 + width * 0.62
				local shelfZ = r.z1 + depth * 0.72
				newPart("Shelf_" .. levelName .. "_" .. index, Vector3.new(E(90), EH(180), E(38)),
					CFrame.new(X(shelfX), Y(levelY) + EH(90), X(shelfZ)),
					Color3.fromRGB(150, 142, 128), Enum.Material.WoodPlanks, office).CanCollide = false
				for shelfLevel = 1, 3 do
					newPart("ShelfBooks_" .. levelName .. "_" .. index .. "_" .. shelfLevel,
						Vector3.new(E(78), EH(26), E(28)),
						CFrame.new(X(shelfX), Y(levelY) + EH(38 + shelfLevel * 42), X(shelfZ)),
						Color3.fromRGB(120 + shelfLevel * 22, 90, 70), Enum.Material.SmoothPlastic, office).CanCollide = false
				end
			end
		end
	end

	fitOutOffice(basementRooms, BOTTOM_LEVEL * F2F, "Basement")
	for _, lv in ipairs(LEVELS) do
		fitOutOffice(lv.rooms, lv.index * F2F, lv.name)
	end
end

local oldSpawn = Workspace:FindFirstChild("LabSpawn")
if oldSpawn then oldSpawn:Destroy() end
-- neutral start: right inside the entrance, facing the three role
-- kiosks, so choosing a role is the very first thing a new player does
local sp = Instance.new("SpawnLocation")
sp.Name = "LabSpawn"
sp.Size = Vector3.new(6, 0.1, 6)
-- SpawnLocation's default facing is -Z; the kiosks sit at a HIGHER z
-- than the spawn, so without a 180-degree turn a new player spawns
-- with their back to them and never sees the panels. Face +Z instead.
sp.CFrame = CFrame.new(X(GROUND_ROOMS[1].x1 + 250), -0.1, X(90)) * CFrame.Angles(0, math.rad(180), 0)
sp.Anchored = true
sp.Transparency, sp.CanCollide, sp.CanTouch, sp.CanQuery = 1, false, false, false
sp.Duration = 0
sp.Color = Color3.fromRGB(120, 170, 120)
sp.Material = Enum.Material.Concrete
sp.Parent = Workspace

--=====================================================================
-- TEAMS AND ROLE STATIONS
-- Two competitive gameplay roles: Technicians repair equipment, while
-- Laboratory Technicians move and process germinated plant samples.
--=====================================================================
local Teams = game:GetService("Teams")

local ROLES = {
	{name = "Technician", team = BrickColor.new("Bright blue"),   paint = Color3.fromRGB(60, 120, 200)},
	{name = "Laboratory Technician", team = BrickColor.new("Lime green"), paint = Color3.fromRGB(90, 170, 90)},
}

for _, obsoleteName in ipairs({"Inspector", "Supervisor"}) do
	local obsolete = Teams:FindFirstChild(obsoleteName)
	if obsolete then obsolete:Destroy() end
end

for _, role in ipairs(ROLES) do
	local old = Teams:FindFirstChild(role.name)
	if old then old:Destroy() end
	local t = Instance.new("Team")
	t.Name = role.name
	t.TeamColor = role.team
	t.AutoAssignable = false
	t.Parent = Teams
end

do
	-- everything below lives in the long west room of the ground floor
	local lobby = GROUND_ROOMS[1]
	local y0 = 0
	local colX = {lobby.x1 + 130, lobby.x1 + 250, lobby.x1 + 370}

	local function prop(name, xcm, zcm, w, d, h, colour, shape)
		local isEquipmentCabinet = (shape or "box") ~= "rack"
		if isEquipmentCabinet then w, d, h = 96, 74, 205 end
		local size = Vector3.new(E(w), EH(h), E(d))
		local pos = Vector3.new(X(xcm), Y(y0) + size.Y / 2, X(zcm))
		local entry = {kind = name, col = colour, mat = Enum.Material.Metal,
			shape = isEquipmentCabinet and "appliance" or (shape or "box"), plantCabinet = isEquipmentCabinet, capacity = 8}
		local p = buildKind(root, entry, pos, size)
		p.Name = name:gsub("%s", "")
		if isEquipmentCabinet then
			local sampleCount = 4
			local sampleIds = {}
			for i = 1, sampleCount do table.insert(sampleIds, string.format("%s-P%02d", p.Name:sub(1, 6):upper(), i)) end
			p:SetAttribute("Capacity", entry.capacity)
			p:SetAttribute("SampleCount", sampleCount)
			p:SetAttribute("SampleIds", table.concat(sampleIds, "|"))
			populateEquipmentCabinet(p, entry, size, nil, sampleCount, entry.capacity)
		end
		return p
	end

	-- a glowing floor chevron pointing from a kiosk toward its station
	local function chevron(xcm, zcm, colour)
		local w, len, thick = 60, 40, 7
		for _, side in ipairs({-1, 1}) do
			local arm = newPart("ArrowMark", Vector3.new(X(thick), Y(4), X(len)),
				CFrame.new(X(xcm + side * w / 4), Y(y0) + Y(2), X(zcm)) * CFrame.Angles(0, math.rad(side * 35), 0),
				colour, Enum.Material.Neon, root)
			arm.CanCollide = false
			arm.CastShadow = false
		end
	end

	-- role panels: two big, unmistakable glowing panels right in
	-- front of the spawn point -- touch one to become that role, which
	-- immediately changes your character's appearance.
	for i, role in ipairs(ROLES) do
		local panelSize = Vector3.new(E(100), EH(190), E(14))
		local panelPos = Vector3.new(X(colX[i]), Y(y0) + panelSize.Y / 2, X(220))
		local frame = newPart(role.name .. "_PanelFrame", panelSize,
			CFrame.new(panelPos), Color3.fromRGB(30, 32, 36), Enum.Material.Metal, root)
		frame.CanCollide = true
		local face = newPart(role.name .. "_PanelFace", Vector3.new(panelSize.X * 0.86, panelSize.Y * 0.82, panelSize.Z * 0.3),
			CFrame.new(panelPos.X, panelPos.Y + panelSize.Y * 0.04, panelPos.Z + panelSize.Z / 2 * 0.9),
			role.paint, Enum.Material.Neon, root)
		face.CanCollide = false
		face.CastShadow = false
		local p = frame
		p:SetAttribute("Role", role.name)
		CollectionService:AddTag(p, "RoleKiosk")

		-- Printed directly on the panel instead of floating in the room.
		-- Front + back faces keep it readable regardless of panel direction.
		for _, normal in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
			local surface = Instance.new("SurfaceGui")
			surface.Name = "RoleLabel"
			surface.Face = normal
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 55
			surface.AlwaysOnTop = false
			surface.Parent = face
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.BackgroundTransparency = 1
			lbl.Text = role.name:upper() .. "\nPRESS E"
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextStrokeTransparency = 0.55
			lbl.TextScaled = true
			lbl.Font = Enum.Font.GothamBold
			lbl.Parent = surface
		end

		local oldSp = Workspace:FindFirstChild(role.name .. "Spawn")
		if oldSp then oldSp:Destroy() end
		local rsp = Instance.new("SpawnLocation")
		rsp.Name = role.name .. "Spawn"
		rsp.Neutral = false
		rsp.TeamColor = role.team
		rsp.Size = Vector3.new(6, 0.1, 6)
		rsp.CFrame = CFrame.new(X(colX[i]), -0.1, X(340))
		rsp.Anchored = true
		rsp.CanCollide = false
		rsp.CanTouch = false
		rsp.CanQuery = false
		rsp.Transparency = 1
		rsp.Duration = 0
		rsp.Color = role.paint
		rsp.Material = Enum.Material.SmoothPlastic
		rsp.Parent = Workspace

		-- Role selection is shown on the kiosk, not on raised pads/floor arrows.
	end

	-- Floating scoreboard/how-to slabs removed to keep the lobby and doors clear.

	-- SECRET BASEMENT ENTRANCE: a disguised maintenance vent flush with the
	-- lobby's own exterior wall, finished in the same concrete as the wall
	-- around it so it reads as part of the wall, not a door. It sits inside
	-- the kiosk area's reserved buffer zone (z 150-460 on this room's W/E
	-- walls, blocked off from the normal equipment fit-out earlier), so it
	-- can never end up buried behind an equipment cabinet. A nearby sign
	-- carries the actual instructions -- this is meant to be found, just
	-- not obvious at a glance.
	local secretPanel = newPart("MaintenanceVentPanel", Vector3.new(X(6), Y(140), X(90)),
		CFrame.new(X(EXT_T + 3), Y(y0) + Y(95), X(400)), C.ext, Enum.Material.Concrete, root)
	secretPanel.CanCollide = false
	CollectionService:AddTag(secretPanel, "SecretBasementPanel")
	local grille = newPart("VentGrille", Vector3.new(X(2), Y(60), X(60)),
		CFrame.new(X(EXT_T + 6), Y(y0) + Y(95), X(400)), Color3.fromRGB(70, 74, 78), Enum.Material.DiamondPlate, root)
	grille.CanCollide = false
	grille.CastShadow = false
	local secretPrompt = Instance.new("ProximityPrompt")
	secretPrompt.ObjectText = "Maintenance Vent"
	secretPrompt.ActionText = "Pry open"
	secretPrompt.KeyboardKeyCode = Enum.KeyCode.E
	secretPrompt.HoldDuration = 1.5
	secretPrompt.MaxActivationDistance = 8
	secretPrompt.RequiresLineOfSight = false
	secretPrompt.Parent = secretPanel
	-- Drop point: open basement corridor floor, well clear of any equipment.
	secretPanel:SetAttribute("SecretDestX", X((CORR_X1 + CORR_X2) / 2))
	secretPanel:SetAttribute("SecretDestY", Y(BOTTOM_LEVEL * F2F)) -- floor surface; runtime fits the avatar
	secretPanel:SetAttribute("SecretDestZ", X(200))

	sign(root, "MAINTENANCE ACCESS\nA basement vent panel is set into the west wall\nnear the role kiosks. Hold E on it to pry it open.",
		EXT_T + 55, 400, y0, 260, 20)
end

--=====================================================================
-- RUNTIME SCRIPTS
--=====================================================================
-- Check spawn clearance only after furniture, walls and kiosks all exist.
-- Movement collision checks cannot rescue a worker initially embedded in a wall.
do
	local relocated, blocked = 0, 0
	for _, bot in ipairs(workerFolder:GetChildren()) do
		if bot:IsA("Model") and bot.PrimaryPart and not bot:GetAttribute("Seated") then
			local original = bot:GetPivot()
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Exclude
			overlap.FilterDescendantsInstances = {bot}
			overlap.RespectCanCollide, overlap.MaxParts = true, 1
			local ray = RaycastParams.new()
			ray.FilterType = Enum.RaycastFilterType.Exclude
			ray.FilterDescendantsInstances = {bot}
			ray.RespectCanCollide = true
			local function clear(point)
				return #Workspace:GetPartBoundsInBox(CFrame.new(point - Vector3.new(0, 0.2, 0)), Vector3.new(3.6, 5.4, 3.6), overlap) == 0
			end
			if not clear(original.Position) then
				local found
				for radius = 4, 28, 4 do
					for step = 0, 15 do
						local angle = step * math.pi / 8
						local point = original.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
						local floor = Workspace:Raycast(point + Vector3.new(0, 1, 0), Vector3.new(0, -6, 0), ray)
						if floor and floor.Normal.Y > 0.8 and math.abs(floor.Position.Y + 3.25 - original.Position.Y) < 0.3 then
							point = Vector3.new(point.X, floor.Position.Y + 3.25, point.Z)
							if clear(point) then found = point; break end
						end
					end
					if found then break end
				end
				if found then bot:PivotTo(CFrame.new(found) * original.Rotation); relocated += 1
				else blocked += 1 end
			end
		end
	end
	root:SetAttribute("WorkerSpawnsRelocated", relocated)
	root:SetAttribute("WorkerSpawnsBlocked", blocked)
end

local FLOW_SOURCE = [==[
-- LabKinds : what each kind of basic laboratory equipment does.
-- Keyed by the Kind attribute the generator writes on every item, so
-- any number of copies anywhere in the building behave the same.

local K = {}

K.Items = {
	TRAY    = "Sample Tray",
	GROUND  = "Ground Sample",
	DRIED   = "Dried Sample",
	SPUN    = "Separated Sample",
	CULTURE = "Culture Plate",
	WASTE   = "Used Material",
	CLEAN   = "Clean Glassware",
}
local I = K.Items

local function f(n, dp) return string.format("%." .. dp .. "f", n) end
local function rnd(a, b) return a + math.random() * (b - a) end

K.Actions = {
	["Workbench"] = {action = "Set out a sample", wait = 1.2, produces = {I.TRAY},
		log = function() return "Sample laid out on the bench." end},
	["Island Bench"] = {action = "Set out a sample", wait = 1.2, produces = {I.TRAY},
		log = function() return "Sample laid out on the island bench." end},
	["Base Cabinet Run"] = {action = "Open the cabinet", wait = 0.8,
		log = function() return "Consumables drawn from the cabinet." end},
	["Desk"] = {action = "Write up the record", wait = 1.2,
		log = function() return "Notes entered in the log book." end},

	["Sink Unit"] = {action = "Wash glassware", wait = 2.0, produces = {I.CLEAN},
		log = function() return "Glassware rinsed and set to drain." end},
	["Fume Hood"] = {action = "Work under extraction", wait = 2.5, uvLight = true,
		log = function() return "Extraction running at " .. f(rnd(0.4, 0.6), 2) .. " m/s face velocity." end},

	["Laboratory Mill"] = {action = "Grind the sample", wait = 2.0,
		consumes = I.TRAY, produces = {I.GROUND}, activeColour = Color3.fromRGB(200, 160, 60),
		log = function() return "Ground for two minutes; chamber cleaned afterwards." end},
	["Sieve Shaker"] = {action = "Sieve the sample", wait = 2.0,
		log = function() return f(rnd(45, 80), 0) .. "% passed the working mesh." end},
	["Drying Oven"] = {action = "Dry the sample", wait = 3.5,
		consumes = I.TRAY, produces = {I.DRIED}, activeColour = Color3.fromRGB(200, 60, 50),
		log = function() return "Oven holding " .. f(rnd(101, 105), 1) .. " C." end},
	["Centrifuge"] = {action = "Spin the sample", wait = 2.5,
		consumes = I.TRAY, produces = {I.SPUN},
		log = function() return f(rnd(3000, 12000), 0) .. " rpm for " .. math.random(5, 20) .. " minutes." end},
	["Incubator"] = {action = "Incubate the sample", wait = 3.0,
		consumes = I.TRAY, produces = {I.CULTURE}, activeColour = Color3.fromRGB(255, 170, 0),
		log = function() return "Holding " .. f(rnd(19, 31), 1) .. " C; door log updated." end},
	["Autoclave"] = {action = "Sterilize a load", wait = 3.0,
		consumes = I.WASTE, activeColour = Color3.fromRGB(0, 120, 255),
		log = function() return "Cycle complete at 121 C; indicator strip filed." end},
	["Waste Bin"] = {action = "Discard used material", wait = 0.8, consumes = I.WASTE,
		log = function() return "Waste segregated for removal." end},

	["Analytical Balance"] = {action = "Weigh the sample", wait = 1.5,
		log = function()
			local w = rnd(0.4, 25)
			return "Reading " .. f(w, w < 1 and 4 or 3) .. " g; balance levelled and zeroed."
		end},
	["Microscope"] = {action = "Examine the sample", wait = 1.5,
		log = function() return "Examined at " .. math.random(1, 4) * 10 .. "x." end},
	["pH Meter"] = {action = "Measure pH", wait = 1.2,
		log = function() return "pH " .. f(rnd(4.5, 9.0), 2) .. " at " .. f(rnd(19, 23), 1) .. " C." end},
	["Water Bath"] = {action = "Warm the sample", wait = 1.5,
		log = function() return "Bath steady at " .. f(rnd(30, 60), 1) .. " C." end},
	["Hot Plate Stirrer"] = {action = "Stir and heat", wait = 1.5,
		log = function() return "Stirring at " .. math.random(200, 900) .. " rpm." end},
	["Orbital Shaker"] = {action = "Shake the sample", wait = 1.5,
		log = function() return "Shaking at " .. math.random(80, 260) .. " rpm." end},
	["Desiccator"] = {action = "Cool the sample", wait = 1.8,
		consumes = I.DRIED, produces = {I.WASTE},
		log = function() return "Cooled over dry desiccant before the second weighing." end},
	["Computer Terminal"] = {action = "Enter the result", wait = 1.2,
		log = function() return "Result recorded against the sample number." end},

	["Refrigerator"] = {action = "Load / unload sample", wait = 1.2,
		log = function() return "Held at " .. f(rnd(2, 8), 1) .. " C." end},
	["Chest Freezer"] = {action = "Load / unload sample", wait = 1.2,
		log = function() return "Held at " .. f(rnd(-25, -16), 0) .. " C." end},
	["Sample Cabinet"] = {action = "File the sample", wait = 1.0,
		log = function() return "Filed by sample number." end},
	["Shelving Unit"] = {action = "Draw stock", wait = 0.8,
		log = function() return "Stock drawn; reorder level checked." end},
	["Storage Rack"] = {action = "Draw stock", wait = 0.8,
		log = function() return "Stock drawn from the rack." end},
	["Glassware Rack"] = {action = "Take clean glassware", wait = 0.8, produces = {I.CLEAN},
		log = function() return "Clean glassware taken from the rack." end},
	["Trolley"] = {action = "Load the trolley", wait = 0.8,
		log = function() return "Trolley loaded for transfer." end},
	["Filing Cabinet"] = {action = "Pull a file", wait = 0.8,
		log = function() return "File retrieved." end},
	["Locker Bank"] = {action = "Change clothing", wait = 1.2,
		log = function() return "Changed before entering the working area." end},
	["Gas Cylinder Rack"] = {action = "Check the cylinders", wait = 1.0,
		log = function() return "Cylinders chained; regulator pressure " .. math.random(20, 200) .. " bar." end},
	["Reagent Rack"] = {action = "Take a reagent", wait = 0.8,
		log = function() return "Reagent taken; bottle logged back in." end},
	["Test Tube Rack"] = {action = "Rack the tubes", wait = 0.8,
		log = function() return "Tubes racked and labelled." end},
	["Pipette Stand"] = {action = "Take a pipette", wait = 0.8,
		log = function() return "Pipette taken; last service date in date." end},

	["Germination Chamber"] = {action = "Load a germination test", wait = 2.5,
		consumes = I.TRAY, produces = {I.CULTURE}, activeColour = Color3.fromRGB(120, 200, 140),
		log = function() return "Test set at " .. f(rnd(18, 25), 1) .. " C, day count started." end},
	["Sample Divider"] = {action = "Divide the sample", wait = 1.8,
		consumes = I.GROUND, produces = {I.TRAY},
		log = function() return "Split into equal working portions." end},
	["Decontamination Unit"] = {action = "Run decontamination", wait = 2.2, consumes = I.WASTE,
		activeColour = Color3.fromRGB(150, 210, 255),
		log = function() return "Cycle complete; surfaces clear." end},
	["Water Distiller"] = {action = "Draw distilled water", wait = 1.2,
		log = function() return "Conductivity " .. f(rnd(0.5, 2.5), 1) .. " uS/cm." end},
	["Reference Sample Archive"] = {action = "File a reference sample", wait = 1.0,
		log = function() return "Filed against the reference register." end},
	["Optical Analyzer"] = {action = "Run an optical reading", wait = 1.8,
		log = function() return "Reading logged at " .. math.random(400, 800) .. " nm." end},
	["Electrophoresis Unit"] = {action = "Run a separation", wait = 2.0, activeColour = Color3.fromRGB(0, 120, 255),
		log = function() return "Run complete at " .. math.random(60, 150) .. " V." end},
	["Thermal Cycler"] = {action = "Run an amplification cycle", wait = 2.5, activeColour = Color3.fromRGB(255, 170, 0),
		log = function() return math.random(25, 40) .. " cycles complete." end},
	["Homogenizer"] = {action = "Homogenize the sample", wait = 1.5,
		log = function() return "Sample homogenized at " .. math.random(8000, 24000) .. " rpm." end},
	["Seed Counter"] = {action = "Count the sample", wait = 1.5,
		log = function() return math.random(200, 1200) .. " units counted." end},
	["Calibration Weight Set"] = {action = "Check calibration", wait = 1.0,
		log = function() return "Balance checked against certified weights." end},
	["Temperature Logger"] = {action = "Read the logger", wait = 0.6,
		log = function() return "Log downloaded; " .. f(rnd(2, 8), 1) .. " C average." end},

	["Plant Growth Chamber"] = {action = "Take / return plant", wait = 0.8},
	["Growth Hormone Mixer"] = {action = "Apply growth hormone", wait = 2.0},
	["GMO Injector"] = {action = "Inject GMO trait", wait = 2.4},
	["Nutrient Infuser"] = {action = "Infuse nutrients", wait = 1.8},
	["UV Growth Scanner"] = {action = "Scan plant development", wait = 1.5},
	["Pollination Station"] = {action = "Pollinate the plant", wait = 2.1},
	["Mutagenesis Chamber"] = {action = "Irradiate the sample", wait = 2.4,
		log = function() return math.random(100, 1000) .. " Gy dose logged; dosimeter reset." end},
	["Hormone Treatment Bench"] = {action = "Apply hormone treatment", wait = 2.0,
		log = function() return "Auxin/cytokinin mix dosed and logged." end},

	-- Cooperative role stations: LabEquipment special-cases these three
	-- kinds before ever reaching this table, so only the prompt flavour
	-- text below (action/wait) is actually used for them.
	["Sample Intake"]      = {action = "Log a sample", wait = 1.0},
	["Inspection Station"] = {action = "Inspect the batch", wait = 1.2},
	["Supervisor Console"] = {action = "Sign off the batch", wait = 1.5},

	["Fire Extinguisher"] = {action = "Check the extinguisher", wait = 1.0,
		log = function() return "Gauge in the green; inspection tag current." end},
	["First Aid Cabinet"] = {action = "Check the first aid kit", wait = 1.0,
		log = function() return "Contents complete." end},
	["Eyewash Station"] = {action = "Flush the eyewash", wait = 1.5,
		log = function() return "Weekly flush run; water clear." end},
}

K.Default = {action = "Inspect", wait = 1.0,
	log = function() return "Checked and left in order." end}

function K.forKind(kind) return K.Actions[kind] or K.Default end

return K
]==]

local EQUIP_SCRIPT_SOURCE = [==[
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
		mode = "gun", damage = 20, range = 110, selfCostPercent = 1, pcOnly = true,
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
		tool:SetAttribute("BlasterInstantHeadshot", style.pcOnly == true)
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
				-- A head shot kills outright, whatever the weapon.
				local headShot = instance.Name == "Head"
				damageWorkerBot(bot, headShot and 1000 or (style.damage or 25), player)
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
]==]

local BLASTER_SOURCE = [====[
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

]====]

local BLASTER_CONTROLLER_SOURCE = [====[
-- BlasterController
-- Local Tool controller: ContextActionService input, mobile controls, ADS,
-- touch aim damping, camera recoil, crosshair, and weapon bob.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Blaster = require(script.Parent:WaitForChild("Blaster"))
local localPlayer = Players.LocalPlayer

local BlasterController = {}
BlasterController.__index = BlasterController

local controllers = setmetatable({}, {__mode = "k"})
local nextControllerId = 0

local function touchControlsActive()
	if UserInputService.TouchEnabled then return true end
	local okTouchScreen, touchScreen = pcall(function()
		return UserInputService.TouchScreenEnabled
	end)
	if okTouchScreen and touchScreen then return true end
	local okPreferred, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if okPreferred and tostring(preferred):find("Touch") then return true end
	local okControls, controls = pcall(function()
		return GuiService.TouchControlsEnabled
	end)
	if okControls and controls then return true end

	-- Studio can retain desktop input flags when a phone preset is selected
	-- after the client starts. Recognize the simulator's compact landscape
	-- viewport so the weapon does not silently lose its mobile camera/buttons.
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	return RunService:IsStudio()
		and viewport ~= nil
		and viewport.Y <= 450
		and viewport.X / math.max(1, viewport.Y) >= 1.45
end

local function pointInside(button, point)
	if not button or not button.Visible then return false end
	local p = button.AbsolutePosition
	local s = button.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X
		and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

-- Hardware support does not identify the active input on an emulator/hybrid.
local function touchAimActive()
	local input = UserInputService:GetLastInputType()
	if input == Enum.UserInputType.Touch then return true end
	if input == Enum.UserInputType.MouseMovement
		or input == Enum.UserInputType.MouseButton1
		or input == Enum.UserInputType.MouseButton2
		or input == Enum.UserInputType.MouseButton3
		or input == Enum.UserInputType.MouseWheel
		or input == Enum.UserInputType.Keyboard then
		return false
	end
	return touchControlsActive()
end

local function rotationBetween(from, to)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local axis = from:Cross(to)
	if axis.Magnitude < 0.00001 then
		if dot > 0 then return CFrame.identity end
		axis = from:Cross(Vector3.yAxis)
		if axis.Magnitude < 0.00001 then axis = from:Cross(Vector3.xAxis) end
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function makeCrosshair(hudName)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild(hudName)
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = hudName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Crosshair"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(30, 30)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.fromRGB(120, 235, 255)
	dot.BorderSizePixel = 0
	dot.Parent = root
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(6, 15, 22)
	dotStroke.Transparency = 0.15
	dotStroke.Thickness = 1.5
	dotStroke.Parent = dot

	for index, data in ipairs({
		{UDim2.new(0.5, -1, 0, 1), UDim2.fromOffset(2, 8)},
		{UDim2.new(0.5, -1, 1, -9), UDim2.fromOffset(2, 8)},
		{UDim2.new(0, 1, 0.5, -1), UDim2.fromOffset(8, 2)},
		{UDim2.new(1, -9, 0.5, -1), UDim2.fromOffset(8, 2)},
	}) do
		local line = Instance.new("Frame")
		line.Name = "Line" .. index
		line.Position = data[1]
		line.Size = data[2]
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BackgroundTransparency = 0.08
		line.BorderSizePixel = 0
		line.Parent = root
	end

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0.5, 25)
	status.Size = UDim2.fromOffset(210, 24)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(220, 232, 242)
	status.TextSize = 13
	status.TextStrokeTransparency = 0.5
	status.Parent = gui

	return gui, root, status, dot
end

function BlasterController:_ensureHUD()
	if self.hud and self.hud.Parent and self.crosshair and self.crosshair.Parent == self.hud
		and self.reticleDot and self.reticleDot.Parent == self.crosshair then return false end
	if self.hud then self.hud:Destroy() end
	self.fallbackShootButton = nil
	self.fallbackAimButton = nil
	self.hud, self.crosshair, self.statusLabel, self.reticleDot = makeCrosshair("BlasterHUD_" .. self.id)
	self.hud.Enabled = self.enabled
	return true
end

function BlasterController.new(tool, overrides)
	assert(RunService:IsClient(), "BlasterController must be required on the client")
	assert(tool and tool:IsA("Tool"), "BlasterController.new expects a Tool")

	nextControllerId = nextControllerId + 1
	local self = setmetatable({}, BlasterController)
	self.tool = tool
	self.overrides = overrides or {}
	self.id = nextControllerId
	self.actionPrefix = "Blaster_" .. nextControllerId .. "_"
	self.connections = {}
	self.enabled = false
	self.aiming = false
	self.triggerHeld = false
	self.fireLoopRunning = false
	self.sequence = 0
	self.nextLocalShot = 0
	self.baseGrip = tool.Grip
	self.recoilPitch = 0
	self.recoilYaw = 0
	self.touchInput = nil
	self.touchLastPosition = nil
	self.hiddenParts = {}
	self.shoulderOffset = Vector3.zero

	self.connections.equipped = tool.Equipped:Connect(function()
		self:Enable()
	end)
	self.connections.unequipped = tool.Unequipped:Connect(function()
		self:Disable()
	end)
	self.connections.destroying = tool.Destroying:Connect(function()
		self:Destroy()
	end)
	self.connections.ancestry = tool.AncestryChanged:Connect(function()
		if self.enabled and tool.Parent ~= localPlayer.Character then
			self:Disable()
		end
	end)
	-- Tool.Activated is Roblox's device-independent activation path. ContextActionService
	-- remains the primary input layer, while this fallback covers touch/controller layouts
	-- that route their built-in Tool button directly to Activated.
	self.connections.activated = tool.Activated:Connect(function()
		if self.enabled then self:_beginFiring() end
	end)
	self.connections.deactivated = tool.Deactivated:Connect(function()
		self.triggerHeld = false
	end)

	if localPlayer.Character and tool.Parent == localPlayer.Character then
		task.defer(function() self:Enable() end)
	end

	return self
end

function BlasterController:_button(actionName)
	local ok, button = pcall(function()
		return ContextActionService:GetButton(actionName)
	end)
	return ok and button or nil
end

function BlasterController:_fallbackTouchButton(kind, title)
	local field = kind == "Shoot" and "fallbackShootButton" or "fallbackAimButton"
	local existing = self[field]
	if existing and existing.Parent then return existing end
	if not self.hud then return nil end

	local button = Instance.new("TextButton")
	button.Name = "Fallback" .. kind
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(35, 48, 60)
	button.BorderSizePixel = 0
	button.Text = title
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(245, 250, 255)
	button.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
	button.TextStrokeTransparency = 0.25
	button.TextScaled = false
	button.ZIndex = 20
	button.Parent = self.hud
	self[field] = button

	if kind == "Shoot" then
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_shootAction(nil, Enum.UserInputState.Begin)
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:_shootAction(nil, Enum.UserInputState.End)
			end
		end)
	else
		button.Activated:Connect(function()
			if self.enabled then self:SetAiming(not self.aiming) end
		end)
	end
	return button
end

function BlasterController:_styleTouchButtons()
	if not touchControlsActive() then return end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	local diameter = math.clamp(math.floor(math.min(viewport.X, viewport.Y) * 0.13), 52, 80)
	if jump and jump.AbsoluteSize.X > 0 then
		diameter = math.clamp(math.floor(math.min(jump.AbsoluteSize.X, jump.AbsoluteSize.Y) * 0.85), 48, 80)
	end

	-- Own the visuals/hit targets; CAS still binds desktop/controller actions.
	local shootButton = self:_fallbackTouchButton("Shoot", "FIRE")
	local aimButton = self:_fallbackTouchButton("Aim", "AIM")
	for _, action in ipairs({"Shoot", "Aim"}) do
		local casButton = self:_button(self.actionPrefix .. action)
		if casButton then casButton.Visible = false end
	end
	for _, button in ipairs({shootButton, aimButton}) do
		if button then
			button.Visible = true
			button.Size = UDim2.fromOffset(diameter, diameter)
			button.TextSize = math.floor(diameter * 0.25)
			button.BackgroundTransparency = 0.18
			if button:IsA("ImageButton") then
				button.ImageTransparency = 0.08
				button.ImageColor3 = Color3.fromRGB(35, 48, 60)
			end
			local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = button
			local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(220, 235, 245)
			stroke.Transparency = 0.25
			stroke.Thickness = 2
			stroke.Parent = button
			local title = button:FindFirstChild("ActionTitle")
			if title and title:IsA("TextLabel") then
				title.Font = Enum.Font.GothamBold
				title.TextColor3 = Color3.fromRGB(245, 250, 255)
				title.TextStrokeColor3 = Color3.fromRGB(5, 8, 12)
				title.TextStrokeTransparency = 0.25
				title.TextScaled = true
			end
		end
	end

	-- GUI absolute coordinates include the simulator's safe-area translation.
	-- Anchor to Roblox's real JUMP rectangle, never an estimated viewport point.
	local gap = math.max(12, math.floor(diameter * 0.22))
	local jumpSize = jump and jump.AbsoluteSize or Vector2.new(diameter, diameter)
	local jumpPoint = jump and jump.AbsolutePosition
		or (self.hud.AbsolutePosition + self.hud.AbsoluteSize - jumpSize - Vector2.new(28, 28))
	local shootPoint = Vector2.new(jumpPoint.X + (jumpSize.X - diameter) * 0.5, jumpPoint.Y - diameter - gap)
	local aimPoint = Vector2.new(jumpPoint.X - diameter - gap, jumpPoint.Y + (jumpSize.Y - diameter) * 0.5)
	local function place(button, point)
		if not button or not button.Parent then return end
		button.AnchorPoint = Vector2.zero
		local origin = button.Parent.AbsolutePosition
		button.Position = UDim2.fromOffset(
			math.floor(point.X - origin.X + 0.5),
			math.floor(point.Y - origin.Y + 0.5)
		)
	end
	place(shootButton, shootPoint)
	place(aimButton, aimPoint)
	self.lastJumpPosition = jump and jump.AbsolutePosition
end

function BlasterController:_getAimScreenPoint(camera)
	if not camera then return nil end
	if touchAimActive() then
		-- Mobile aims along the Scriptable camera's true forward vector. In the
		-- Studio phone simulator, ViewportPointToRay(viewportCenter) is offset by
		-- the asymmetric safe-area canvas and can land several degrees above the
		-- visible centre marker.
		return nil
	end
	local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	-- Clicking an on-screen action must not pull the target onto that button.
	if pointInside(self.fallbackShootButton, point) or pointInside(self.fallbackAimButton, point) then
		return self.lastPointerAim or camera.ViewportSize * 0.5
	end
	self.lastPointerAim = point
	return Vector2.new(
		math.clamp(point.X, 0, camera.ViewportSize.X),
		math.clamp(point.Y, 0, camera.ViewportSize.Y)
	)
end

function BlasterController:_updateAimReticle(camera)
	if not self.hud or not self.crosshair or not camera then return end
	local rayScreenPoint = self:_getAimScreenPoint(camera)
	local screenPoint = rayScreenPoint
	local character = localPlayer.Character
	local solution = character and Blaster.GetAimSolution(self.tool, camera, {
		character,
		self.tool,
		camera,
	}, rayScreenPoint)

	if rayScreenPoint == nil then
		-- The shot uses Camera.CFrame.LookVector. Project that same forward
		-- vector with WorldToScreenPoint so the marker lands in the exact CoreUI
		-- coordinate space used by this ScreenGui, including notches/top bars.
		local projected = camera:WorldToScreenPoint(
			camera.CFrame.Position + camera.CFrame.LookVector * 100
		)
		screenPoint = Vector2.new(projected.X, projected.Y)
	elseif not screenPoint then
		screenPoint = camera.ViewportSize * 0.5
	end

	if solution then
		if self.reticleDot then
			self.reticleDot.BackgroundColor3 = solution.result
				and Color3.fromRGB(255, 224, 105)
				or Color3.fromRGB(120, 235, 255)
		end
	end

	-- ScreenGui's simulated-device canvas can be larger than Camera.ViewportSize
	-- and begin at a negative absolute position. Counter that offset so this
	-- marker identifies the muzzle-checked world hit on every device.
	local origin = self.hud.AbsolutePosition
	local center = screenPoint - origin
	self.crosshair.Position = UDim2.fromOffset(
		math.floor(center.X + 0.5),
		math.floor(center.Y + 0.5)
	)
end

function BlasterController:_setLocalHeadHidden(hidden)
	local character = localPlayer.Character
	if not character then return end
	if hidden then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and (descendant.Name == "Head" or descendant.Parent:IsA("Accessory")) then
				if self.hiddenParts[descendant] == nil then
					self.hiddenParts[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			end
		end
	else
		for part, transparency in pairs(self.hiddenParts) do
			if part.Parent then part.LocalTransparencyModifier = transparency end
		end
		table.clear(self.hiddenParts)
	end
end

function BlasterController:_beginTouchCamera()
	if not touchAimActive() or self.mobileCameraActive then return end
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid then return end

	local look = camera.CFrame.LookVector
	self.touchPitch = math.asin(math.clamp(look.Y, -1, 1))
	self.touchYaw = math.atan2(-look.X, -look.Z)
	self.savedCameraType = camera.CameraType
	self.mobileCameraActive = true
	humanoid.AutoRotate = false
	camera.CameraType = Enum.CameraType.Scriptable
	self:_setLocalHeadHidden(true)
end

function BlasterController:_endTouchCamera()
	if not self.mobileCameraActive then return end
	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and self.savedCameraType then camera.CameraType = self.savedCameraType end
	self.mobileCameraActive = false
	self.touchInput = nil
	self.touchLastPosition = nil
	self:_setLocalHeadHidden(false)
end

function BlasterController:SetAiming(aiming)
	if not self.enabled then aiming = false end
	if self.aiming == aiming then return end
	self.aiming = aiming

	local camera = workspace.CurrentCamera
	if not camera then return end
	local config = Blaster.GetWeaponConfig(self.tool)
	local targetFov = aiming and config.adsFov or (self.hipFov or 70)
	if self.fovTween then self.fovTween:Cancel() end
	self.fovTween = TweenService:Create(camera, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	})
	self.fovTween:Play()

	if touchAimActive() then
		-- Mobile weapons keep the camera active in hip-fire too, so the right
		-- half of the screen always steers the reticle like a dedicated FPS.
		self:_beginTouchCamera()
	elseif aiming then
			self.savedMouseSensitivity = UserInputService.MouseDeltaSensitivity
			UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity * 0.62
	else
		if self.savedMouseSensitivity then
			UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity
			self.savedMouseSensitivity = nil
		end
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not self.mobileCameraActive then
		humanoid.CameraOffset = aiming
			and Vector3.new(1.25, 0.55, 0)
			or self.shoulderOffset
	end

	if self.statusLabel then
		self.statusLabel.Text = aiming and "ADS" or ""
	end
end

function BlasterController:_fireOnce()
	if not self.enabled or self.tool.Parent ~= localPlayer.Character then return end
	local config = Blaster.GetWeaponConfig(self.tool)
	local now = os.clock()
	if now < self.nextLocalShot then return end
	self.nextLocalShot = now + config.cooldown
	self.sequence = self.sequence + 1

	local camera = workspace.CurrentCamera
	Blaster.Fire(self.tool, camera, self.sequence, self:_getAimScreenPoint(camera))
	local recoilScale = self.aiming and 0.55 or 1
	self.recoilPitch = self.recoilPitch + math.rad(0.75 * recoilScale)
	self.recoilYaw = self.recoilYaw + math.rad((math.random() - 0.5) * 0.55 * recoilScale)
end

function BlasterController:_beginFiring()
	self.triggerHeld = true
	if self.fireLoopRunning then return end
	self.fireLoopRunning = true
	task.spawn(function()
		repeat
			self:_fireOnce()
			local config = Blaster.GetWeaponConfig(self.tool)
			if not config.automatic then break end
			task.wait(config.cooldown)
		until not self.triggerHeld or not self.enabled
		self.fireLoopRunning = false
	end)
end

function BlasterController:_shootAction(_, inputState, inputObject)
	if not self.enabled then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin and inputObject
		and inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
		local point = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		if pointInside(self.fallbackAimButton, point) then return Enum.ContextActionResult.Pass end
	end
	if inputState == Enum.UserInputState.Begin then
		self:_beginFiring()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.triggerHeld = false
	end
	return Enum.ContextActionResult.Sink
end

function BlasterController:_aimAction(_, inputState, inputObject)
	if not self.enabled then return Enum.ContextActionResult.Pass end
	local isTouch = inputObject and inputObject.UserInputType == Enum.UserInputType.Touch
	if isTouch then
		if inputState == Enum.UserInputState.Begin then
			self:SetAiming(not self.aiming)
		end
	elseif inputState == Enum.UserInputState.Begin then
		self:SetAiming(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self:SetAiming(false)
	end
	return Enum.ContextActionResult.Sink
end

function BlasterController:_touchPanAction(_, inputState, inputObject)
	if not self.enabled or not touchControlsActive() then
		return Enum.ContextActionResult.Pass
	end

	local point = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	point = point - inset

	if inputState == Enum.UserInputState.Begin then
		local shootButton = self.fallbackShootButton or self:_button(self.actionPrefix .. "Shoot")
		local aimButton = self.fallbackAimButton or self:_button(self.actionPrefix .. "Aim")
		local touchGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
		local jumpButton = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if point.X < viewport.X * 0.42 or pointInside(shootButton, point)
			or pointInside(aimButton, point) or pointInside(jumpButton, point) then
			return Enum.ContextActionResult.Pass
		end
		self.touchInput = inputObject
		self:_beginTouchCamera()
		self.touchLastPosition = point
		return Enum.ContextActionResult.Sink
	end

	if inputObject ~= self.touchInput then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Change and self.touchLastPosition then
		local delta = point - self.touchLastPosition
		self.touchLastPosition = point
		local sensitivity = self.aiming
			and (self.tool:GetAttribute("BlasterADSTouchSensitivity") or 0.42)
			or (self.tool:GetAttribute("BlasterHipTouchSensitivity") or 0.72)
		sensitivity = math.clamp(sensitivity, 0.15, 1.2)
		self.touchYaw = self.touchYaw - delta.X * 0.0031 * sensitivity
		self.touchPitch = math.clamp(self.touchPitch - delta.Y * 0.0027 * sensitivity, math.rad(-78), math.rad(78))
		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.touchInput = nil
		self.touchLastPosition = nil
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function BlasterController:_updateArmPose(targetPosition)
	local character = localPlayer.Character
	local handle = self.tool:FindFirstChild("Handle")
	if not character or not handle or not targetPosition then return end
	if not self.aimJoint or not self.aimJoint.Parent then
		local joints = {}
		for _, joint in ipairs(character:GetDescendants()) do
			if (joint:IsA("JointInstance") or joint:IsA("AnimationConstraint")) and joint.Part0 and joint.Part1 then
				joints[joint.Part1] = joint
			end
		end
		local chain = {}
		local part = handle
		for _ = 1, 8 do
			local joint = joints[part]
			if not joint then return end
			table.insert(chain, 1, joint)
			if joint.Name == "Right Shoulder" or joint.Name == "RightShoulder" then
				self.aimJoint = joint
				self.aimBaseC0 = joint.C0
				self.aimChain = chain
				break
			end
			part = joint.Part0
		end
	end
	local shoulder = self.aimJoint
	if not shoulder or not shoulder.Part0 then return end
	-- Rebuild from the untouched joint/grip and the current animation each frame.
	-- This preserves R6/R15 rest rotations and avoids accumulating aim offsets.
	local jointWorld = shoulder.Part0.CFrame * self.aimBaseC0
	local predicted = shoulder.Part0.CFrame
	for _, joint in ipairs(self.aimChain) do
		if not joint.Parent then return end
		local c0 = joint == shoulder and self.aimBaseC0 or joint.C0
		local animation = (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) and joint.Transform or CFrame.identity
		predicted = predicted * c0 * animation * joint.C1:Inverse()
	end
	local forward = self.tool:GetAttribute("BlasterBarrelDirection")
	if typeof(forward) ~= "Vector3" or forward.Magnitude < 0.1 then
		-- Imported Weapons Kit meshes face +Z; procedural barrels face -Z.
		forward = self.tool:GetAttribute("LabSidearm") and Vector3.zAxis or -Vector3.zAxis
	end
	local turn = CFrame.identity
	local pivot = jointWorld.Position
	for _ = 1, 4 do
		local delta = targetPosition - predicted.Position
		if delta.Magnitude < 0.1 then break end
		local correction = rotationBetween(predicted:VectorToWorldSpace(forward.Unit), delta.Unit)
		predicted = CFrame.new(pivot) * correction * CFrame.new(-pivot) * predicted
		turn = correction * turn
	end
	local pose = shoulder.Part0.CFrame:ToObjectSpace(CFrame.new(pivot) * turn * jointWorld.Rotation)
	if shoulder:IsA("AnimationConstraint") then
		shoulder.Attachment0.CFrame = pose
	else
		shoulder.C0 = pose
	end
end

function BlasterController:_render(dt)
	if not self.enabled then return end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then return end
	local hudRebuilt = self:_ensureHUD()
	local touchMode = touchControlsActive()
	local touchAim = touchAimActive()
	if touchAim and not self.mobileCameraActive then
		self:_beginTouchCamera()
	elseif not touchAim and self.mobileCameraActive then
		self:_endTouchCamera()
	end
	local touchGui = localPlayer.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if touchMode and (hudRebuilt or self.lastTouchViewport ~= camera.ViewportSize
		or (jump and jump.AbsolutePosition ~= self.lastJumpPosition)) then
		self.lastTouchViewport = camera.ViewportSize
		task.defer(function()
			if self.enabled then self:_styleTouchButtons() end
		end)
	end
	local moving = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
	local speed = self.aiming and 7 or 9.5
	local amount = self.aiming and 0.012 or 0.035
	local clock = os.clock() * speed
	local bob = CFrame.new(math.sin(clock) * amount * moving, math.abs(math.cos(clock)) * amount * moving, 0)
		* CFrame.Angles(0, 0, math.sin(clock) * math.rad(0.35) * moving)
	self.tool.Grip = self.baseGrip * bob

	self.recoilPitch = self.recoilPitch * math.exp(-dt * 14)
	self.recoilYaw = self.recoilYaw * math.exp(-dt * 16)
	if self.mobileCameraActive and head and root then
		self.touchPitch = math.clamp(self.touchPitch - self.recoilPitch * dt * 7, math.rad(-78), math.rad(78))
		self.touchYaw = self.touchYaw + self.recoilYaw * dt * 7
		local rotation = CFrame.fromOrientation(self.touchPitch, self.touchYaw, 0)
		local focus = head.Position + Vector3.new(0, 0.12, 0)
		local desired = focus - rotation.LookVector * 0.18 + rotation.RightVector * 0.08
		local cameraResult = workspace:Raycast(focus, desired - focus, Blaster.NewRaycastParams({character, self.tool}))
		local position = cameraResult and (cameraResult.Position + cameraResult.Normal * 0.1) or desired
		camera.CFrame = CFrame.new(position) * rotation
		camera.Focus = CFrame.new(focus + rotation.LookVector * 12)
		local flatLook = Vector3.new(rotation.LookVector.X, 0, rotation.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
		end
	elseif math.abs(self.recoilPitch) > 0.00001 or math.abs(self.recoilYaw) > 0.00001 then
		camera.CFrame = camera.CFrame * CFrame.Angles(-self.recoilPitch * dt * 7, self.recoilYaw * dt * 7, 0)
	end
	local config = Blaster.GetWeaponConfig(self.tool)
	local cast = Blaster.CastFromCamera(camera, config.range, {character, self.tool, camera}, self:_getAimScreenPoint(camera))
	if cast then
		if root and not humanoid.Sit then
			local flat = Vector3.new(cast.position.X - root.Position.X, 0, cast.position.Z - root.Position.Z)
			if flat.Magnitude > 0.1 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) end
		end
		self:_updateArmPose(cast.position)
	end
	self:_updateAimReticle(camera)
end

function BlasterController:Enable()
	if self.enabled then return end
	self.enabled = true
	self.baseGrip = self.tool.Grip
	self.hipFov = self.tool:GetAttribute("BlasterHipFOV") or (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70

	self:_ensureHUD()
	self.hud.Enabled = true

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self.savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		self.savedCameraOffset = humanoid.CameraOffset
		self.shoulderOffset = Vector3.new(
			self.tool:GetAttribute("BlasterShoulderOffsetX") or 2.2,
			self.tool:GetAttribute("BlasterShoulderOffsetY") or 0.65,
			0
		)
		humanoid.CameraOffset = self.shoulderOffset
	end
	if touchAimActive() then self:_beginTouchCamera() end

	local shootName = self.actionPrefix .. "Shoot"
	local aimName = self.actionPrefix .. "Aim"
	local panName = self.actionPrefix .. "TouchPan"
	local priority = Enum.ContextActionPriority.High.Value

	ContextActionService:BindActionAtPriority(shootName, function(...)
		return self:_shootAction(...)
	end, true, priority + 2, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(aimName, function(...)
		return self:_aimAction(...)
	end, true, priority + 2, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority(panName, function(...)
		return self:_touchPanAction(...)
	end, false, priority + 1, Enum.UserInputType.Touch)

	ContextActionService:SetTitle(shootName, "FIRE")
	ContextActionService:SetTitle(aimName, "AIM")
	task.delay(0.1, function()
		if self.enabled then self:_styleTouchButtons() end
	end)

	self.renderName = self.actionPrefix .. "Render"
	RunService:BindToRenderStep(self.renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_render(dt)
	end)
end

function BlasterController:Disable()
	if not self.enabled then return end
	self.triggerHeld = false
	self:SetAiming(false)
	self.enabled = false

	ContextActionService:UnbindAction(self.actionPrefix .. "Shoot")
	ContextActionService:UnbindAction(self.actionPrefix .. "Aim")
	ContextActionService:UnbindAction(self.actionPrefix .. "TouchPan")
	if self.renderName then RunService:UnbindFromRenderStep(self.renderName) end
	if self.hud then self.hud.Enabled = false end
	if self.tool.Parent then self.tool.Grip = self.baseGrip end
	if self.aimJoint and self.aimJoint.Parent then
		if self.aimJoint:IsA("AnimationConstraint") then
			self.aimJoint.Attachment0.CFrame = self.aimBaseC0
		else
			self.aimJoint.C0 = self.aimBaseC0
		end
	end
	self.aimJoint, self.aimBaseC0, self.aimChain = nil, nil, nil

	local camera = workspace.CurrentCamera
	if camera and self.hipFov then camera.FieldOfView = self.hipFov end
	self:_endTouchCamera()
	if self.savedMouseSensitivity then
		UserInputService.MouseDeltaSensitivity = self.savedMouseSensitivity
		self.savedMouseSensitivity = nil
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and self.savedAutoRotate ~= nil then humanoid.AutoRotate = self.savedAutoRotate end
	self.savedAutoRotate = nil
	if humanoid and self.savedCameraOffset then
		humanoid.CameraOffset = self.savedCameraOffset
	end
	self.savedCameraOffset = nil
	self.lastTouchViewport = nil
end

function BlasterController:Destroy()
	self:Disable()
	for _, connection in pairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.hud then self.hud:Destroy() end
	controllers[self.tool] = nil
end

function BlasterController.BindTool(tool, overrides)
	if controllers[tool] then return controllers[tool] end
	local controller = BlasterController.new(tool, overrides)
	controllers[tool] = controller
	Blaster.StartReplication()
	return controller
end

function BlasterController.GetController(tool)
	return controllers[tool]
end

function BlasterController.AutoBind()
	local binder = {connections = {}}

	local function consider(instance)
		if instance:IsA("Tool") and (instance:GetAttribute("BlasterWeapon") or instance:GetAttribute("LabSidearm")) then
			BlasterController.BindTool(instance)
		end
	end

	local function watch(container)
		if not container then return end
		for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
		table.insert(binder.connections, container.DescendantAdded:Connect(consider))
	end

	watch(localPlayer:WaitForChild("Backpack"))
	watch(localPlayer.Character)
	table.insert(binder.connections, localPlayer.CharacterAdded:Connect(watch))
	Blaster.StartReplication()

	function binder:Destroy()
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
	end

	return binder
end

return BlasterController
]====]

local SERVER_BLASTER_MANAGER_SOURCE = [====[
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

local function bridgeHit(player, result, damage, instantHeadshot)
	if not result then return false end
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
	
	]====]

	-- Compact responsive score/timer overlay. Touch devices get only the live
	-- essentials; the top-three board remains available on larger displays.
	local LAB_HUD_SOURCE = [==[
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")

	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local compact = UIS.TouchEnabled or (camera and camera.ViewportSize.X < 900)
	local S = compact and 0.78 or 0.9

	local INK = Color3.fromRGB(232, 238, 236)
	local PANEL = Color3.fromRGB(18, 22, 24)
	local GOOD = Color3.fromRGB(96, 226, 150)
	local WARN = Color3.fromRGB(255, 186, 74)
	local HOT = Color3.fromRGB(255, 96, 84)

	local old = player:WaitForChild("PlayerGui"):FindFirstChild("LabHUD")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "LabHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player.PlayerGui

	local function panel(parent, size, pos, anchor)
		local f = Instance.new("Frame")
		f.Size, f.Position, f.AnchorPoint = size, pos, anchor or Vector2.zero
		f.BackgroundColor3 = PANEL
		f.BackgroundTransparency = 0.14
		f.BorderSizePixel = 0
		f.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(90, 100, 104)
		stroke.Transparency = 0.58
		stroke.Parent = f
		return f
	end

	local function label(parent, text, size, pos, textSize, colour, align)
		local t = Instance.new("TextLabel")
		t.Size, t.Position = size, pos
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.Text = text
		t.TextSize = textSize * S
		t.TextColor3 = colour or INK
		t.TextXAlignment = align or Enum.TextXAlignment.Center
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Parent = parent
		return t
	end

	local roundBox = panel(gui, UDim2.fromOffset(230 * S, 52 * S), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0))
	local roundName = label(roundBox, "SHIFT 1", UDim2.new(1, 0, 0, 16 * S), UDim2.fromOffset(0, 3), 11, Color3.fromRGB(150, 160, 165))
	local clock = label(roundBox, "--:--", UDim2.new(1, 0, 0, 24 * S), UDim2.fromOffset(0, 17 * S), 21)
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -18, 0, 4)
	barBg.Position = UDim2.new(0, 9, 1, -8)
	barBg.BackgroundColor3 = Color3.fromRGB(52, 58, 62)
	barBg.BorderSizePixel = 0
	barBg.Parent = roundBox
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barBg
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = GOOD
	bar.BorderSizePixel = 0
	bar.Parent = barBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = bar

	local scoreBox = panel(gui, UDim2.fromOffset(140 * S, 52 * S), UDim2.new(1, -8, 0, 6), Vector2.new(1, 0))
	label(scoreBox, "SCORE", UDim2.new(1, -10, 0, 14 * S), UDim2.fromOffset(0, 3), 10, Color3.fromRGB(150, 160, 165), Enum.TextXAlignment.Right)
	local scoreText = label(scoreBox, "0", UDim2.new(1, -10, 0, 23 * S), UDim2.fromOffset(0, 16 * S), 22, INK, Enum.TextXAlignment.Right)
	local pbText = label(scoreBox, "BEST 0", UDim2.new(1, -10, 0, 11 * S), UDim2.new(0, 0, 1, -13 * S), 9, Color3.fromRGB(140, 150, 155), Enum.TextXAlignment.Right)
	local streakText = label(scoreBox, "", UDim2.new(0.55, 0, 0, 16 * S), UDim2.fromOffset(7, 18 * S), 11, WARN, Enum.TextXAlignment.Left)

	local popups = Instance.new("Frame")
	popups.Size = UDim2.fromOffset(190 * S, 150 * S)
	popups.Position = UDim2.new(1, -8, 0, 54 * S)
	popups.AnchorPoint = Vector2.new(1, 0)
	popups.BackgroundTransparency = 1
	popups.Parent = gui
	local popupLayout = Instance.new("UIListLayout")
	popupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	popupLayout.Padding = UDim.new(0, 3)
	popupLayout.Parent = popups

	local board = panel(gui, UDim2.fromOffset(170 * S, 82 * S), UDim2.new(1, -8, 0, 64 * S), Vector2.new(1, 0))
	board.Visible = not compact
	label(board, "TOP TECHNICIANS", UDim2.new(1, 0, 0, 14 * S), UDim2.fromOffset(0, 4), 10, Color3.fromRGB(150, 160, 165))
	local rows = {}
	for i = 1, 3 do
		rows[i] = label(board, "", UDim2.new(1, -14, 0, 17 * S), UDim2.fromOffset(7, (16 + i * 17) * S), 11, INK, Enum.TextXAlignment.Left)
		rows[i].Font = Enum.Font.Gotham
	end

	local shown, target = 0, 0
	local function pointsValue()
		local stats = player:FindFirstChild("leaderstats")
		local points = stats and stats:FindFirstChild("Points")
		return points and points.Value or 0
	end

	local streak, lastAward = 0, 0
	local function popup(amount, reason)
		local row = panel(popups, UDim2.fromOffset(184 * S, 25 * S), UDim2.fromOffset(0, 0), Vector2.zero)
		local amountLabel = label(row, "+" .. amount, UDim2.new(0, 45 * S, 1, 0), UDim2.fromOffset(6, 0), 13, GOOD, Enum.TextXAlignment.Left)
		local reasonLabel = label(row, tostring(reason), UDim2.new(1, -53 * S, 1, 0), UDim2.fromOffset(49 * S, 0), 9, Color3.fromRGB(190, 200, 205), Enum.TextXAlignment.Left)
		reasonLabel.Font = Enum.Font.Gotham
		task.delay(2.2, function()
			if not row.Parent then return end
			TweenService:Create(row, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
			TweenService:Create(amountLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			TweenService:Create(reasonLabel, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			task.wait(0.32)
			row:Destroy()
		end)
	end

	player:GetAttributeChangedSignal("LastPointAward"):Connect(function()
		local amount = player:GetAttribute("LastPointAmount") or 0
		if amount <= 0 then return end
		local now = os.clock()
		streak = (now - lastAward <= 14) and streak + 1 or 1
		lastAward = now
		popup(amount, player:GetAttribute("LastPointAward") or "Task complete")
		scoreText.TextColor3 = GOOD
		TweenService:Create(scoreText, TweenInfo.new(0.5), {TextColor3 = INK}):Play()
		if streak >= 2 then streakText.Text = "x" .. streak end
	end)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		target = pointsValue()
		if shown ~= target then
			shown += (target - shown) * math.min(dt * 8, 1)
			if math.abs(target - shown) < 0.6 then shown = target end
			scoreText.Text = tostring(math.floor(shown + 0.5))
		end
		if streak >= 2 and os.clock() - lastAward > 14 then streak = 0; streakText.Text = "" end

		local endsAt = workspace:GetAttribute("RoundEndsAt")
		local length = workspace:GetAttribute("RoundLength") or 480
		local phase = workspace:GetAttribute("RoundPhase") or "PLAY"
		if endsAt then
			local left = math.max(0, endsAt - os.time())
			clock.Text = string.format("%d:%02d", left // 60, left % 60)
			if phase == "BREAK" then
				roundName.Text = "SHIFT OVER"
				bar.BackgroundColor3 = Color3.fromRGB(120, 130, 140)
				bar.Size = UDim2.fromScale(1, 1)
			else
				roundName.Text = "SHIFT " .. tostring(workspace:GetAttribute("RoundNumber") or 1)
				bar.Size = UDim2.new(math.clamp(left / length, 0, 1), 0, 1, 0)
				bar.BackgroundColor3 = left <= 30 and HOT or left <= 90 and WARN or GOOD
				clock.TextColor3 = (left <= 10 and left > 0 and left % 2 == 0) and HOT or INK
			end
		end

		acc += dt
		if acc >= 1.5 then
			acc = 0
			local list = {}
			for _, pl in ipairs(Players:GetPlayers()) do
				local stats = pl:FindFirstChild("leaderstats")
				local points = stats and stats:FindFirstChild("Points")
				table.insert(list, {name = pl.Name, value = points and points.Value or 0})
			end
			table.sort(list, function(a, b) return a.value > b.value end)
			for i = 1, 3 do
				local entry = list[i]
				rows[i].Text = entry and string.format("%d. %s  %d", i, entry.name, entry.value) or ""
				rows[i].TextColor3 = entry and entry.name == player.Name and GOOD or INK
			end
			pbText.Text = "BEST " .. tostring(player:GetAttribute("PersonalBest") or 0)
		end
	end)
	]==]

	-- Lightweight client bootstrap. Input, crosshair, camera, bob and ADS all
	-- live in BlasterController; this script updates the shared compact HUD and binds
-- every standard Tool carrying the BlasterWeapon attribute.
local SIDEARM_CLIENT_SOURCE = [==[
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
]==]

local ELEVATOR_SCRIPT_SOURCE = [==[
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
]==]

local ROLES_SCRIPT_SOURCE = [==[
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
]==]

local QUIZ_CLIENT_SOURCE = [==[
-- Addition popup: click/tap one of three answers. No phone keyboard or
-- changes to the player's camera, aiming, or movement controls are required.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("LabMathQuiz")
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("LabMathConsole")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LabMathConsole"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 60
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "AdditionQuiz"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.46)
panel.Size = UDim2.new(1, -28, 0, 238)
panel.BackgroundColor3 = Color3.fromRGB(14, 24, 30)
panel.BorderSizePixel = 0
panel.Active = true
panel.Visible = false
panel.Parent = gui
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(440, 238)
sizeLimit.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(95, 225, 170)
stroke.Thickness = 2
stroke.Parent = panel

local function label(name, y, height, size, colour)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Size = UDim2.new(1, -28, 0, height)
    item.Position = UDim2.fromOffset(14, y)
    item.BackgroundTransparency = 1
    item.TextColor3 = colour
    item.TextSize = size
    item.Font = Enum.Font.GothamBold
    item.TextWrapped = true
    item.Parent = panel
    return item
end
local title = label("Title", 10, 26, 18, Color3.fromRGB(110, 240, 185))
title.Size = UDim2.new(1, -70, 0, 26)
title.Text = "ADDITION CHECK"
local reason = label("Task", 40, 34, 13, Color3.fromRGB(195, 213, 223))
local question = label("Question", 76, 45, 34, Color3.fromRGB(250, 250, 250))
local status = label("Status", 190, 34, 13, Color3.fromRGB(255, 210, 100))
local cancel = Instance.new("TextButton")
cancel.Name = "Cancel"
cancel.Position = UDim2.new(1, -42, 0, 6)
cancel.Size = UDim2.fromOffset(36, 36)
cancel.BackgroundTransparency = 1
cancel.Text = "×"
cancel.TextColor3 = Color3.fromRGB(220, 228, 232)
cancel.TextSize = 28
cancel.Modal = true -- Let the pointer select an answer even in first-person view.
cancel.Parent = panel

local activeId
local submitted = false
local buttons = {}
local function answer(value)
    if not activeId or submitted then return end
    submitted = true
    status.Text = "Checking answer…"
    remote:FireServer(activeId, value)
end
for i = 1, 3 do
    local button = Instance.new("TextButton")
    button.Name = "Answer" .. i
    button.Position = UDim2.new((i - 1) / 3, 10, 0, 128)
    button.Size = UDim2.new(1 / 3, -14, 0, 56)
    button.BackgroundColor3 = Color3.fromRGB(50, 146, 112)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 26
    button.Parent = panel
    local rounding = Instance.new("UICorner")
    rounding.CornerRadius = UDim.new(0, 9)
    rounding.Parent = button
    button.Activated:Connect(function() answer(button:GetAttribute("Answer")) end)
    buttons[i] = button
end
cancel.Activated:Connect(function() answer(nil) end)

remote.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then return end
    if payload.Close then
        if payload.Id == activeId then panel.Visible = false; activeId = nil end
        return
    end
    activeId = payload.Id
    submitted = false
    reason.Text = tostring(payload.Reason or "Repair or collect a plant")
    question.Text = tostring(payload.Question or "?") .. " = ?"
    for i, button in ipairs(buttons) do
        local value = payload.Choices and payload.Choices[i]
        button.Text = tostring(value or "?")
        button:SetAttribute("Answer", value)
    end
    panel.Visible = true
    local thisId = activeId
    local expires = os.clock() + (tonumber(payload.Seconds) or 60)
    task.spawn(function()
        while activeId == thisId and panel.Visible do
            local left = math.max(0, math.ceil(expires - os.clock()))
            if not submitted then status.Text = "Tap the correct answer • " .. left .. "s • × cancels" end
            if left <= 0 then
                if not submitted then answer(nil) end
                panel.Visible = false
                break
            end
            task.wait(0.2)
        end
    end)
end)
]==]

-- Studio only permits Script.Source writes from trusted authoring contexts.
-- If the generator itself is executed by a normal server Script during a
-- play test, those writes fail. This compact live fallback binds the core
-- gameplay directly so role prompts, held plants, recovery tools and worker
-- tests still function in that exact situation.
local function startLiveRuntimeFallback()
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local PathfindingService = game:GetService("PathfindingService")
	local liveBound = {}
	local liveEmergencyMoves = 0
	local liveSampleSerial = 40000
	local liveRepairs, liveAssignedRepairs, liveTransfers, liveAssignedTransfers = 0, 0, 0, 0
	local LIVE_POINTS = {MOVE_ANY = 12, MOVE_LATE = 18, MOVE_ON_TIME = 30, PROCESS = 4}
	local liveAssignTask

	local function livePlayerRole(player)
		local role = player:GetAttribute("LabRole")
		if role and role ~= "" then return role end
		return player.Team and player.Team.Name or "Unassigned"
	end

	local function liveEquipmentId(part)
		local code = part:GetAttribute("GrowthCode")
		if code and code ~= "" then return "CHAMBER:" .. code end
		return table.concat({part:GetAttribute("Level") or "Lab", part:GetAttribute("Room") or "Room", part.Name}, "|")
	end

	local function liveFloor(part)
		return part:GetAttribute("FloorLabel") or part:GetAttribute("Level") or "UNKNOWN FLOOR"
	end

	local function liveTransferSeconds(source, destination)
		local distance = destination and (destination.Position - source.Position).Magnitude or 60
		local playerCount = math.max(1, #Players:GetPlayers())
		local complex = workspace:FindFirstChild("Laboratory_Complex")
		local backlog = complex and (complex:GetAttribute("FailedSampleBacklog") or 0) or 0
		return math.clamp(math.floor(58 + distance * 0.65 + math.max(0, 3 - playerCount) * 10
			+ math.clamp(backlog / 20, 0, 25)), 60, 180)
	end

	local function liveEquipmentLabel(part)
		local code = part:GetAttribute("GrowthCode")
		if code and code ~= "" then return "CHAMBER " .. code end
		return (part:GetAttribute("Kind") or part.Name) .. " / " .. (part:GetAttribute("Room") or "Lab")
	end

	local function refreshLiveScoreboard()
		local rivalScore = 0
		for _, bot in ipairs(CollectionService:GetTagged("LabWorkerBot")) do
			if bot:GetAttribute("Competitor") then rivalScore = bot:GetAttribute("Score") or 0 break end
		end
		for _, board in ipairs(CollectionService:GetTagged("BatchScoreboard")) do
			local label = board:FindFirstChild("Text", true)
			if label and label:IsA("TextLabel") then
				label.Text = string.format("PLAYER TEAM SCORE\nRepairs: %d  •  assigned: %d\nPlant moves: %d  •  assigned: %d\nRival NPC score: %d",
					liveRepairs, liveAssignedRepairs, liveTransfers, liveAssignedTransfers, rivalScore)
			end
		end
	end

	local function refreshLiveRoomMonitors()
		-- Room names repeat on every level, so key by level+room, not room alone.
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

	local function liveAward(player, amount, reason)
		local stats = player:FindFirstChild("leaderstats")
		if not stats then stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player end
		local points = stats:FindFirstChild("Points")
		if not points then points = Instance.new("IntValue"); points.Name = "Points"; points.Parent = stats end
		points.Value = points.Value + amount
		player:SetAttribute("LastPointAmount", amount)
		player:SetAttribute("LastPointAward", reason)
		refreshLiveScoreboard()
		return points.Value
	end

	-- Math-quiz gate removed by request: pass straight through.
	local function runLiveMathQuiz(player, reason)
		return true
	end
	local plantProcesses = {
		["Germination Chamber"] = {name = "Germination", gain = 1},
		Incubator = {name = "Incubation", gain = 1},
		["Growth Hormone Mixer"] = {name = "Growth Hormone", gain = 2},
		["GMO Injector"] = {name = "GMO Injection", gain = 1},
		["Nutrient Infuser"] = {name = "Nutrient Infusion", gain = 1},
		["UV Growth Scanner"] = {name = "UV Scan", gain = 0},
		["Pollination Station"] = {name = "Pollination", gain = 1},
	}
	local function findPlant(player)
		for _, container in ipairs({player.Character, player:FindFirstChildOfClass("Backpack")}) do
			if container then
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("Tool") and child:GetAttribute("PlantSample") then return child end
				end
			end
		end
	end

	local function liveChamberSamples(chamber)
		local samples = {}
		for id in string.gmatch(chamber:GetAttribute("SampleIds") or "", "[^|]+") do
			table.insert(samples, id)
		end
		return samples
	end

	local function saveLiveChamber(chamber, samples)
		local capacity = chamber:GetAttribute("Capacity") or 10
		while #samples > capacity do table.remove(samples) end
		chamber:SetAttribute("SampleIds", table.concat(samples, "|"))
		chamber:SetAttribute("SampleCount", #samples)
		chamber:SetAttribute("Occupied", #samples > 0)
		chamber:SetAttribute("PlantId", samples[1] or "")
	end

	local function equip(player, tool)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and tool then humanoid:EquipTool(tool) end
	end

	local function weldPiece(tool, handle, name, size, offset, colour)
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.CFrame = handle.CFrame * CFrame.new(offset)
		piece.Color = colour
		piece.Material = Enum.Material.SmoothPlastic
		piece.CanCollide = false
		piece.Massless = true
		piece.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
		return piece
	end

	local function makePlantTool(player, chamber, requestedPlantId, destinationCode)
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 3)
		if not backpack then return nil end
		local code = chamber:GetAttribute("GrowthCode") or liveEquipmentLabel(chamber)
		local plantId = requestedPlantId or chamber:GetAttribute("PlantId") or code
		local tool = Instance.new("Tool")
		tool.Name = "Plant Sample " .. plantId
		tool.ToolTip = "Visible germinated plant from " .. code
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		tool:SetAttribute("LabSample", true)
		tool:SetAttribute("PlantSample", true)
		tool:SetAttribute("PlantId", plantId)
		tool:SetAttribute("SampleId", plantId)
		tool:SetAttribute("OriginGrowthCode", code)
		tool:SetAttribute("SourceGrowthCode", code)
		tool:SetAttribute("DestinationGrowthCode", destinationCode or "")
		tool:SetAttribute("TransferStartedAt", os.time())
		tool:SetAttribute("GrowthStage", chamber:GetAttribute("GrowthStage") or 0)
		tool:SetAttribute("Treatments", chamber:GetAttribute("Treatments") or "")
		tool:SetAttribute("Genome", chamber:GetAttribute("Genome") or "Wild Type")
		tool:SetAttribute("Moisture", chamber:GetAttribute("Moisture") or 50)
		local plantLife = chamber:GetAttribute("PlantLife") or 100
		if chamber:GetAttribute("FunctionalState") == "FAILED" then
			plantLife = math.clamp(100 - math.floor((os.time() - (chamber:GetAttribute("FailureSince") or os.time())) * 1.5), 0, 100)
		end
		tool:SetAttribute("PlantLife", plantLife)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1.05, 0.8, 1.05)
		handle.Color = Color3.fromRGB(116, 75, 45)
		handle.Material = Enum.Material.SmoothPlastic
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		weldPiece(tool, handle, "PlantStem", Vector3.new(0.15, 1.25, 0.15), Vector3.new(0, 0.9, 0), Color3.fromRGB(58, 160, 70))
		weldPiece(tool, handle, "LeafL", Vector3.new(0.7, 0.15, 0.4), Vector3.new(-0.32, 1.15, 0), Color3.fromRGB(73, 185, 84))
		weldPiece(tool, handle, "LeafR", Vector3.new(0.7, 0.15, 0.4), Vector3.new(0.32, 1.42, 0), Color3.fromRGB(73, 185, 84))
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
		lifeText.Size = UDim2.new(1, 0, 0.58, 0)
		lifeText.BackgroundTransparency = 1
		lifeText.TextScaled = true
		lifeText.Font = Enum.Font.GothamBold
		lifeText.Parent = lifeFrame
		local lifeBack = Instance.new("Frame")
		lifeBack.Size = UDim2.new(0.9, 0, 0.2, 0)
		lifeBack.Position = UDim2.new(0.05, 0, 0.7, 0)
		lifeBack.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
		lifeBack.BorderSizePixel = 0
		lifeBack.Parent = lifeFrame
		local lifeFill = Instance.new("Frame")
		lifeFill.Name = "LifeBarFill"
		lifeFill.BorderSizePixel = 0
		lifeFill.Parent = lifeBack
		local function updateLife()
			local life = math.clamp(tool:GetAttribute("PlantLife") or 100, 0, 100)
			local colour = life > 60 and Color3.fromRGB(75, 235, 105)
				or (life > 30 and Color3.fromRGB(255, 190, 55) or Color3.fromRGB(255, 70, 60))
			lifeText.Text = "PLANT LIFE " .. math.floor(life + 0.5) .. "%"
			lifeText.TextColor3 = colour
			lifeFill.Size = UDim2.new(life / 100, 0, 1, 0)
			lifeFill.BackgroundColor3 = colour
		end
		tool:GetAttributeChangedSignal("PlantLife"):Connect(updateLife)
		updateLife()
		tool.Grip = CFrame.new(0, -0.65, -0.25) * CFrame.Angles(math.rad(-10), 0, 0)
		tool.Parent = backpack
		equip(player, tool)
		task.spawn(function()
			while tool.Parent and (tool:GetAttribute("PlantLife") or 0) > 0 do
				task.wait(1)
				if not tool.Parent then return end
				if not tool:GetAttribute("QuizProtected") then
					local life = math.max(0, (tool:GetAttribute("PlantLife") or 0) - 2)
					tool:SetAttribute("PlantLife", life)
					if life <= 0 then
						local reservedCode = tool:GetAttribute("DestinationGrowthCode") or ""
						for _, candidate in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
							if candidate:GetAttribute("GrowthCode") == reservedCode then
								candidate:SetAttribute("IncomingReservations", math.max(0, (candidate:GetAttribute("IncomingReservations") or 1) - 1))
								break
							end
						end
						player:SetAttribute("CarriedSample", "")
						player:SetAttribute("LabObjective", plantId .. " reached 0% LIFE and disappeared. Take another plant.")
						task.wait(0.5)
						if tool.Parent then tool:Destroy() end
						return
					end
				end
			end
		end)
		return tool
	end

	local function showChamberPlant(chamber, visible)
		local count = visible and (chamber:GetAttribute("SampleCount") or 0) or 0
		for _, child in ipairs(chamber:GetDescendants()) do
			if child:IsA("BasePart") and (child:GetAttribute("SampleSlot") or child.Name:match("^ChamberPlant")) then
				local slot = child:GetAttribute("SampleSlot") or 1
				child.Transparency = slot <= count and (child:GetAttribute("StoredTransparency") or 0) or 1
			end
		end
	end

	local function liveRuntimeText(seconds)
		seconds = math.max(0, math.floor(seconds or 0))
		return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	end

	local function recoverLivePlantLife(chamber, startingLife, player, plantId)
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
				plantId or "Plant", chamber:GetAttribute("GrowthCode") or liveEquipmentLabel(chamber), startingLife, seconds))
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
			if player and player.Parent then player:SetAttribute("LabObjective", (plantId or "Plant") .. " recovered to 100% LIFE.") end
		end)
		return seconds
	end

	local function refreshLiveTelemetry(chamber)
		local samples = liveChamberSamples(chamber)
		local state = chamber:GetAttribute("FunctionalState") or "WORKING"
		local code = chamber:GetAttribute("GrowthCode") or liveEquipmentLabel(chamber)
		local floorLabel = chamber:GetAttribute("FloorLabel") or chamber:GetAttribute("Level") or "UNKNOWN FLOOR"
		local destination = chamber:GetAttribute("EvacuationDestination") or ""
		local detail = state == "FAILED" and ((chamber:GetAttribute("FailureReason") or "FAULT")
			.. (destination ~= "" and ("  •  EVACUATE TO " .. destination) or "")) or "SYSTEM NORMAL"
		local text = string.format(
			"%s • CHAMBER %s • %s\nSAMPLES %d/%d • GERMINATED %s\nRUN %s • TEMP %d C • HUM %d%% • VENT %d%%\n%s\n%s",
			floorLabel, code, state, #samples,
			chamber:GetAttribute("Capacity") or 0,
			chamber:GetAttribute("GerminationDate") or "pending",
			liveRuntimeText(os.time() - (chamber:GetAttribute("OperationStarted") or os.time())),
			chamber:GetAttribute("Temperature") or 23, chamber:GetAttribute("Humidity") or 72,
			chamber:GetAttribute("Ventilation") or 75, detail,
			state == "FAILED" and "REPAIR: HOLD R" or "CONTROL: E TAKE / DROP")
		for _, child in ipairs(chamber:GetDescendants()) do
			if child:IsA("TextLabel") and child.Name == "ChamberTelemetry" then
				child.Text = text
				child.TextColor3 = state == "DESTROYED" and Color3.fromRGB(255, 50, 40)
					or state == "FAILED" and Color3.fromRGB(255, 120, 105)
					or Color3.fromRGB(130, 245, 165)
			elseif child:IsA("TextLabel") and child.Name == "ChamberSampleList" then
				child.Text = "PLANTS (" .. #samples .. "): "
					.. (#samples > 0 and table.concat(samples, ", ") or "NO SAMPLES")
			elseif child:IsA("BasePart") and child:GetAttribute("ChamberStatusLamp") then
				child.Color = state == "DESTROYED" and Color3.fromRGB(200, 20, 15)
					or state == "FAILED" and Color3.fromRGB(230, 55, 45)
					or Color3.fromRGB(40, 165, 95)
				child.Material = state == "DESTROYED" and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end

	local function liveDestinations(source)
		local choices = {}
		for _, candidate in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
			local count = candidate:GetAttribute("SampleCount") or 0
			local capacity = candidate:GetAttribute("Capacity") or 10
			local reservations = candidate:GetAttribute("IncomingReservations") or 0
			if candidate ~= source and candidate:GetAttribute("FunctionalState") ~= "FAILED"
				and count + reservations < capacity then
				table.insert(choices, candidate)
			end
		end
		table.sort(choices, function(a, b)
			local sameA = a:GetAttribute("Level") == source:GetAttribute("Level") and 0 or 1
			local sameB = b:GetAttribute("Level") == source:GetAttribute("Level") and 0 or 1
			if sameA ~= sameB then return sameA < sameB end
			local ac = a:GetAttribute("SampleCount") or 0
			local bc = b:GetAttribute("SampleCount") or 0
			if ac ~= bc then return ac < bc end
			return (a:GetAttribute("GrowthCode") or "") < (b:GetAttribute("GrowthCode") or "")
		end)
		return choices
	end

	local function liveRepairPathFolder(player, create)
		local complex = workspace:FindFirstChild("Laboratory_Complex")
		if not complex then return nil end
		local rootFolder = complex:FindFirstChild("TechnicianRepairPaths")
		if create and not rootFolder then
			rootFolder = Instance.new("Folder")
			rootFolder.Name = "TechnicianRepairPaths"
			rootFolder.Parent = complex
		end
		local folder = rootFolder and rootFolder:FindFirstChild("Player_" .. player.UserId)
		if create and not folder then
			folder = Instance.new("Folder")
			folder.Name = "Player_" .. player.UserId
			folder.Parent = rootFolder
		end
		return folder
	end

	local function clearLiveRepairPath(player)
		local folder = liveRepairPathFolder(player, false)
		if folder then folder:Destroy() end
	end

	local function liveRepairReward(player, equipment, assigned)
		local waited = math.max(0, os.time() - (equipment:GetAttribute("FailureSince") or os.time()))
		local distance = assigned and (player:GetAttribute("AssignedRepairDistance") or 0) or 0
		return math.clamp(8 + math.floor(waited / 8) + math.floor(distance / 10) + (assigned and 12 or 0), 8, 120), waited, distance
	end

	local function createLiveRepairPath(player, target)
		clearLiveRepairPath(player)
		local characterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not characterRoot or not target then return 0, false end
		local folder = liveRepairPathFolder(player, true)
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
				if routeReady then routeReady = appendNavigable(points, points[#points], destination) end
			end
		end
		if not routeReady then
			folder:Destroy()
			player:SetAttribute("RepairRouteReady", false)
			return (destination - characterRoot.Position).Magnitude, false
		end
		player:SetAttribute("RepairRouteReady", true)
		local distance, markerCount = 0, 0
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

	liveAssignTask = function(player)
		clearLiveRepairPath(player)
		for _, name in ipairs({"AssignedRepairId", "AssignedRepairDistance", "AssignedRepairProjectedPoints", "AssignedTransferSource", "AssignedTransferDestination", "AssignedTransferDeadline"}) do
			player:SetAttribute(name, nil)
		end
		if livePlayerRole(player) == "Technician" then
			local failed = {}
			for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
				if equipment:GetAttribute("FunctionalState") == "FAILED" then table.insert(failed, equipment) end
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			table.sort(failed, function(a, b)
				if root then
					local ad = (a.Position - root.Position).Magnitude + (math.abs(a.Position.Y - root.Position.Y) > 12 and 500 or 0)
					local bd = (b.Position - root.Position).Magnitude + (math.abs(b.Position.Y - root.Position.Y) > 12 and 500 or 0)
					if ad ~= bd then return ad < bd end
				end
				return (a:GetAttribute("FailureSince") or 0) < (b:GetAttribute("FailureSince") or 0)
			end)
			local target = failed[1]
			local text = "All equipment is working. Repair score grows with failure time; assigned jobs also pay for travel distance."
			if target then
				player:SetAttribute("AssignedRepairId", liveEquipmentId(target))
				local distance, routeReady = createLiveRepairPath(player, target)
				player:SetAttribute("AssignedRepairDistance", distance)
				local projected = select(1, liveRepairReward(player, target, true))
				player:SetAttribute("AssignedRepairProjectedPoints", projected)
				local routeInstruction = routeReady and "Follow RED floor lights" or "Use the NORTH STAIR; route is recalculating"
				text = string.format("REPAIR JOB: %s • %s. %s. HOLD R. About +%d points (%d studs; score grows while failed).",
					liveFloor(target), liveEquipmentLabel(target), routeInstruction, projected, math.floor(distance + 0.5))
			end
			player:SetAttribute("LabObjective", text)
			return text
		end
		local jobs = {}
		for _, source in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
			if source:GetAttribute("FunctionalState") == "FAILED" and (source:GetAttribute("SampleCount") or 0) > 0
				and not source:GetAttribute("ReservedByBot") then
				local destination = liveDestinations(source)[1]
				if destination then table.insert(jobs, {source = source, destination = destination}) end
			end
		end
		table.sort(jobs, function(a, b)
			return (tonumber((a.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge)
				< (tonumber((b.source:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge)
		end)
		local job = jobs[1]
		if not job then
			local text = "Waiting for a failed chamber with plants. Emergency move +12; assigned on-time move +30."
			player:SetAttribute("LabObjective", text)
			return text
		end
		local sourceCode = job.source:GetAttribute("GrowthCode") or "R?"
		local destinationCode = job.destination:GetAttribute("GrowthCode") or "R?"
		player:SetAttribute("AssignedTransferSource", sourceCode)
		player:SetAttribute("AssignedTransferDestination", destinationCode)
		local allowedSeconds = liveTransferSeconds(job.source, job.destination)
		player:SetAttribute("AssignedTransferDeadline", os.time() + allowedSeconds)
		-- Same red floor-marker route the Technician role gets, pointed at
		-- the destination chamber so it's obvious where the plant goes.
		local routeReady = select(2, createLiveRepairPath(player, job.destination))
		local routeInstruction = routeReady and "Follow RED floor lights to the destination chamber" or "Route recalculating"
		local text = "ASSIGNED +30: " .. liveFloor(job.source) .. " • " .. sourceCode .. " → " .. destinationCode
			.. " • " .. liveFloor(job.destination) .. ". PRESS E; " .. routeInstruction .. ". Deliver in " .. allowedSeconds .. " seconds."
		player:SetAttribute("LabObjective", text)
		return text
	end

	local setLiveFailure
	local setLiveGenericFailure

	local function controlCFrame(part, yOffset, standOff)
		local side = part:GetAttribute("WallSide")
		if side == "W" then return part.CFrame * CFrame.new(part.Size.X / 2 + standOff, yOffset, 0), true end
		if side == "E" then return part.CFrame * CFrame.new(-part.Size.X / 2 - standOff, yOffset, 0), true end
		if side == "S" then return part.CFrame * CFrame.new(0, yOffset, -part.Size.Z / 2 - standOff), false end
		return part.CFrame * CFrame.new(0, yOffset, part.Size.Z / 2 + standOff), false
	end

	local function bindLiveEquipment(part)
		if liveBound[part] or not part:IsA("BasePart") then return end
		liveBound[part] = true
		local kind = part:GetAttribute("Kind") or part.Name
		local isGrowthChamber = kind == "Plant Growth Chamber"
		local isPlantContainer = (part:GetAttribute("Capacity") or 0) > 0
		part:SetAttribute("EquipmentId", liveEquipmentId(part))
		part:SetAttribute("FloorLabel", liveFloor(part))
		part:SetAttribute("RepairKey", "R")
		if part:GetAttribute("FunctionalState") == nil then
			local hash = 0
			for i = 1, #liveEquipmentId(part) do hash = hash + string.byte(liveEquipmentId(part), i) end
			local failed = not isGrowthChamber and hash % 7 == 0
			part:SetAttribute("FunctionalState", failed and "FAILED" or "WORKING")
			part:SetAttribute("FailureReason", failed and "Control-system diagnostic fault" or "")
			part:SetAttribute("FailureSince", failed and os.time() or 0)
		end
		if part:GetAttribute("OperationStarted") == nil then part:SetAttribute("OperationStarted", os.time()) end
		local display = part
		local readout = {Text = "", TextColor3 = Color3.fromRGB(115, 235, 165)}
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
		local function liveClockText(seconds)
			seconds = math.max(0, math.floor(seconds or 0))
			return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
		end
		local function renderLiveTimer()
			local state = part:GetAttribute("FunctionalState")
			local destroyed = state == "DESTROYED"
			local failed = destroyed or state == "FAILED"
			local since = failed and (part:GetAttribute("FailureSince") or os.time())
				or (part:GetAttribute("OperationStarted") or os.time())
			if destroyed then
				timerLabel.Text = "DESTROYED -- UNFIXABLE"
				timerLabel.TextColor3 = Color3.fromRGB(90, 90, 95)
			else
				timerLabel.Text = (failed and "FAILED  " or "RUNNING  ") .. liveClockText(os.time() - since)
				timerLabel.TextColor3 = failed and Color3.fromRGB(255, 75, 65) or Color3.fromRGB(75, 255, 125)
			end
			if isPlantContainer and failed then
				local life = math.clamp(100 - math.floor((os.time() - since) * 1.5), 0, 100)
				part:SetAttribute("PlantLife", life)
				if life <= 0 and (part:GetAttribute("SampleCount") or 0) > 0 then
					part:SetAttribute("SampleIds", "")
					part:SetAttribute("SampleCount", 0)
					part:SetAttribute("Occupied", false)
					part:SetAttribute("PlantId", "")
					part:SetAttribute("PlantExpiredAt", os.time())
					showChamberPlant(part, false)
				end
			end
			local capacity = part:GetAttribute("Capacity") or 0
			local count = math.clamp(part:GetAttribute("SampleCount") or 0, 0, capacity)
			local free = math.max(0, capacity - count)
			slotLabel.Text = free == 0 and ("FULL  •  " .. count .. "/" .. capacity)
				or string.format("%d FREE SLOT%s  •  %d/%d", free, free == 1 and "" or "S", count, capacity)
			slotLabel.TextColor3 = free == 0 and Color3.fromRGB(255, 80, 70) or Color3.fromRGB(90, 235, 180)
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
		renderLiveTimer()
		task.spawn(function()
			while part.Parent do renderLiveTimer(); task.wait(1) end
		end)

		local button = Instance.new("Part")
		button.Name = "PushButton"
		button.Shape = Enum.PartType.Ball
		button.Size = isGrowthChamber and Vector3.new(0.62, 0.62, 0.62) or Vector3.new(0.42, 0.42, 0.42)
		button.CFrame = select(1, controlCFrame(part, 0, 0.22))
		button.Color = Color3.fromRGB(220, 65, 55)
		button.Material = Enum.Material.Neon
		button.Anchored = true
		button.CanCollide = false
		button.Parent = part
		local usePrompt = Instance.new("ProximityPrompt")
		usePrompt.ActionText = isPlantContainer and "E: TAKE / DROP PLANT" or "E: USE / INSPECT"
		usePrompt.ObjectText = isPlantContainer
			and ((part:GetAttribute("FloorLabel") or part:GetAttribute("Level") or "FLOOR") .. " • " .. liveEquipmentLabel(part))
			or kind
		usePrompt.KeyboardKeyCode = Enum.KeyCode.E
		usePrompt.MaxActivationDistance = 8
		usePrompt.RequiresLineOfSight = true
		usePrompt.Parent = button

		local led = Instance.new("Part")
		led.Name = "StatusLED"
		led.Shape = Enum.PartType.Ball
		led.Size = Vector3.new(0.28, 0.28, 0.28)
		led.CFrame = select(1, controlCFrame(part, -0.55, 0.24))
		led.Color = Color3.fromRGB(95, 240, 125)
		led.Material = Enum.Material.Neon
		led.Anchored = true
		led.CanCollide = false
		led.Parent = part
		local powered = true
		part:SetAttribute("Powered", true)
		local repairBusy = false

		local floorLabel = liveFloor(part)
		local unitLabel = liveEquipmentLabel(part)
		local repairPrompt = Instance.new("ProximityPrompt")
		repairPrompt.Name = "RepairPrompt"
		repairPrompt.ActionText = "Hold R to repair"
		repairPrompt.ObjectText = floorLabel .. " • " .. unitLabel
		repairPrompt.KeyboardKeyCode = Enum.KeyCode.R
		repairPrompt.GamepadKeyCode = Enum.KeyCode.ButtonB
		repairPrompt.HoldDuration = 3
		repairPrompt.MaxActivationDistance = 8
		repairPrompt.RequiresLineOfSight = true
		repairPrompt.Enabled = part:GetAttribute("FunctionalState") == "FAILED"
		repairPrompt.Parent = part:FindFirstChild("ControllerScreen") or display

		part:GetAttributeChangedSignal("FunctionalState"):Connect(function()
			if repairPrompt.Parent then repairPrompt.Enabled = not repairBusy and part:GetAttribute("FunctionalState") == "FAILED" end
		end)
		repairPrompt.Triggered:Connect(function(player)
			if livePlayerRole(player) ~= "Technician" then
				readout.Text = "TECHNICIAN REQUIRED\nChoose the BLUE role kiosk"
				return
			end
			if repairBusy or part:GetAttribute("FunctionalState") ~= "FAILED" then return end
			repairBusy = true
			repairPrompt.Enabled = false
			readout.Text = "REPAIRING\n" .. floorLabel .. " • " .. unitLabel
			if not runLiveMathQuiz(player, "REPAIR " .. floorLabel .. " • " .. unitLabel) then
				readout.Text = "REPAIR NOT COMPLETED\nHold R for 3 seconds to try again"
				repairBusy = false
				repairPrompt.Enabled = part:GetAttribute("FunctionalState") == "FAILED"
				return
			end
			local assigned = player:GetAttribute("AssignedRepairId") == liveEquipmentId(part)
			local points, failedSeconds, routeDistance = liveRepairReward(player, part, assigned)
			part:SetAttribute("LastRepairedAt", os.time())
			part:SetAttribute("LastRepairedBy", player.Name)
			if isGrowthChamber then setLiveFailure(part, false) else setLiveGenericFailure(part, false) end
			liveRepairs = liveRepairs + 1
			if assigned then liveAssignedRepairs = liveAssignedRepairs + 1 end
			local total = liveAward(player, points, string.format("%s%s • failed %ds • route %d studs",
				assigned and "assigned repair: " or "equipment repair: ", unitLabel, failedSeconds, math.floor(routeDistance + 0.5)))
			readout.Text = "REPAIR COMPLETE +" .. points .. "\n" .. floorLabel .. " • " .. unitLabel .. "\nPLANTS "
				.. (part:GetAttribute("SampleCount") or 0) .. "/" .. (part:GetAttribute("Capacity") or 0) .. " • TOTAL " .. total
			liveAssignTask(player)
			repairBusy = false
		end)

		usePrompt.Triggered:Connect(function(player)
			button.Color = Color3.fromRGB(255, 205, 65)
			task.delay(0.2, function() if button.Parent then button.Color = Color3.fromRGB(220, 65, 55) end end)
			if not isPlantContainer and part:GetAttribute("FunctionalState") == "FAILED" then
				readout.Text = "FAILED • HOLD R\n" .. liveFloor(part) .. " • " .. (part:GetAttribute("FailureReason") or "fault")
				return
			end
			local carriedPlant = findPlant(player)
			local plantProcess = plantProcesses[kind]
			local shouldUsePlantStorage = isPlantContainer and (
				isGrowthChamber
				or not plantProcess
				or not carriedPlant
				or (carriedPlant:GetAttribute("PlantLife") or 100) < 100
			)
			if shouldUsePlantStorage then
				if livePlayerRole(player) ~= "Laboratory Technician" then
					readout.Text = "LAB ROLE REQUIRED\nGREEN kiosk moves plants"
					return
				end
				-- Players override test-bot reservations so E always performs the
				-- obvious take/drop action when they are standing at the cabinet.
				if part:GetAttribute("ReservedByBot") then part:SetAttribute("ReservedByBot", nil) end
				local plant = carriedPlant
				local code = part:GetAttribute("GrowthCode") or liveEquipmentLabel(part)
				local samples = liveChamberSamples(part)
				local capacity = part:GetAttribute("Capacity") or 10
				local failed = part:GetAttribute("FunctionalState") == "FAILED"
				if plant then
					local wanted = plant:GetAttribute("DestinationGrowthCode") or ""
					if failed then
						readout.Text = code .. "  FAILED\nCannot store plants here"
						player:SetAttribute("LabObjective", code .. " is FAILED. Find any GREEN RUNNING cabinet marked FREE SLOT and press E to drop the plant.")
					elseif #samples + (part:GetAttribute("IncomingReservations") or 0) >= capacity then
						readout.Text = code .. "  FULL\nChoose another working chamber"
					else
						local plantId = plant:GetAttribute("PlantId") or plant.Name
						local plantLife = math.clamp(plant:GetAttribute("PlantLife") or 100, 0, 100)
						local sourceCode = plant:GetAttribute("SourceGrowthCode") or plant:GetAttribute("OriginGrowthCode") or ""
						local assigned = wanted ~= "" and player:GetAttribute("AssignedTransferSource") == sourceCode
							and player:GetAttribute("AssignedTransferDestination") == code
						local onTime = assigned and os.time() <= (player:GetAttribute("AssignedTransferDeadline") or 0)
						plant:SetAttribute("QuizProtected", true)
						readout.Text = "STORING SAMPLE\nPlacing " .. plantId .. " into " .. code
						local passedQuiz = runLiveMathQuiz(player, "REVIVE " .. plantId .. " IN " .. code)
						plant:SetAttribute("QuizProtected", nil)
						if not passedQuiz or not plant.Parent then return end
						table.insert(samples, plantId)
						saveLiveChamber(part, samples)
						part:SetAttribute("GrowthStage", math.max(part:GetAttribute("GrowthStage") or 0, plant:GetAttribute("GrowthStage") or 0))
						part:SetAttribute("Treatments", plant:GetAttribute("Treatments") or "")
						part:SetAttribute("Genome", plant:GetAttribute("Genome") or "Wild Type")
						local recoverySeconds = recoverLivePlantLife(part, plantLife, player, plantId)
						if wanted ~= "" then
							for _, reservedDestination in ipairs(CollectionService:GetTagged("PlantGrowthChamber")) do
								if reservedDestination:GetAttribute("GrowthCode") == wanted then
									reservedDestination:SetAttribute("IncomingReservations", math.max(0, (reservedDestination:GetAttribute("IncomingReservations") or 1) - 1))
									break
								end
							end
							liveEmergencyMoves = liveEmergencyMoves + 1
						end
						showChamberPlant(part, true)
						refreshLiveTelemetry(part)
						player:SetAttribute("CarriedSample", "")
						plant:Destroy()
						if wanted ~= "" then
							liveTransfers = liveTransfers + 1
							if assigned then liveAssignedTransfers = liveAssignedTransfers + 1 end
							local points = assigned and (onTime and LIVE_POINTS.MOVE_ON_TIME or LIVE_POINTS.MOVE_LATE) or LIVE_POINTS.MOVE_ANY
							local total = liveAward(player, points, assigned and (onTime and "assigned on-time plant move" or "assigned late plant move") or "emergency plant move")
							readout.Text = string.format("%s STORED +%d\n%s • %d/%d • TOTAL %d", code, points, plantId, #samples, capacity, total)
							if recoverySeconds > 0 then
								task.delay(recoverySeconds, function() if player.Parent then liveAssignTask(player) end end)
							else
								liveAssignTask(player)
							end
						else
							readout.Text = string.format("%s STORED\n%s • %d/%d samples", code, plantId, #samples, capacity)
							player:SetAttribute("LabObjective", "Take the plant to growth equipment or another chamber.")
						end
					end
				elseif #samples > 0 then
					local destination
					if failed and player:GetAttribute("AssignedTransferSource") == code then
						local assignedDestination = player:GetAttribute("AssignedTransferDestination")
						for _, candidate in ipairs(liveDestinations(part)) do
							if candidate:GetAttribute("GrowthCode") == assignedDestination then destination = candidate break end
						end
					end
					if failed then destination = destination or liveDestinations(part)[1] end
					if failed and not destination then
						readout.Text = code .. "  FAILED\nNo working chamber has space"
						player:SetAttribute("LabObjective", "Working chambers are full. Wait for NPC transfers or an automatic recovery.")
						return
					end
					if failed and destination then createLiveRepairPath(player, destination) end
					local plantId = samples[1]
					local destinationCode = destination and destination:GetAttribute("GrowthCode") or ""
					readout.Text = "TAKING SAMPLE\n" .. plantId .. " from " .. code
					if not runLiveMathQuiz(player, "TAKE PLANT " .. plantId .. " FROM " .. code) then return end
					table.remove(samples, 1)
					local made = makePlantTool(player, part, plantId, destinationCode)
					if made then
						saveLiveChamber(part, samples)
						showChamberPlant(part, true)
						if destination then
							destination:SetAttribute("IncomingReservations", (destination:GetAttribute("IncomingReservations") or 0) + 1)
							part:SetAttribute("EvacuationDestination", destinationCode)
							player:SetAttribute("LabObjective", "CARRYING " .. plantId .. ": press E at ANY GREEN RUNNING cabinet marked FREE SLOT. BONUS target: " .. destinationCode .. ".")
							readout.Text = code .. "  FAILED\nSEND " .. plantId .. " TO " .. destinationCode
						else
							player:SetAttribute("LabObjective", "Use growth equipment on " .. plantId .. ", then return it to a working chamber.")
							readout.Text = string.format("%s  SAMPLE OUT\n%s • %d/%d remain", code, plantId, #samples, capacity)
						end
						player:SetAttribute("CarriedSample", plantId)
						refreshLiveTelemetry(part)
					else
						table.insert(samples, 1, plantId)
					end
				else
					readout.Text = code .. (failed and "  FAILED + EMPTY\nAlarm awaiting refill" or "  EMPTY\nBring a plant")
				end
			elseif part:GetAttribute("FunctionalState") == "FAILED" then
				readout.Text = "FAILED • HOLD R\n" .. liveFloor(part) .. " • " .. (part:GetAttribute("FailureReason") or "fault")
				return
			elseif plantProcess then
				if livePlayerRole(player) ~= "Laboratory Technician" then
					readout.Text = "LAB ROLE REQUIRED\nGREEN kiosk develops plants"
					return
				end
				local plant = findPlant(player)
				if not plant then readout.Text = "PLANT REQUIRED\nTake one from an R-numbered chamber"; return end
				local process = plantProcess
				local stage = math.clamp((plant:GetAttribute("GrowthStage") or 0) + process.gain, 0, 5)
				plant:SetAttribute("GrowthStage", stage)
				local treatments = plant:GetAttribute("Treatments") or ""
				if not string.find(treatments, process.name, 1, true) then
					plant:SetAttribute("Treatments", treatments == "" and process.name or (treatments .. ", " .. process.name))
				end
				local total = liveAward(player, LIVE_POINTS.PROCESS, process.name .. " plant treatment")
				readout.Text = kind .. "\nSTATUS WORKING • PLANTS " .. (part:GetAttribute("SampleCount") or 0) .. "/"
					.. (part:GetAttribute("Capacity") or 0) .. "\nPLANT DATA +" .. LIVE_POINTS.PROCESS .. " • "
					.. (plant:GetAttribute("PlantId") or "Plant") .. " • stage " .. stage .. " • TOTAL " .. total
				equip(player, plant)
			else
				part:SetAttribute("Inspections", (part:GetAttribute("Inspections") or 0) + 1)
				readout.Text = string.format("%s • %s\nSTATUS WORKING • POWER ON\nPLANTS %d/%d\nInspection normal",
					liveFloor(part), kind, part:GetAttribute("SampleCount") or 0, part:GetAttribute("Capacity") or 0)
			end
		end)
	end

	local roleColours = {
		Technician = Color3.fromRGB(60, 120, 200),
		["Laboratory Technician"] = Color3.fromRGB(90, 170, 90),
	}
	local function dressCharacter(character, role)
		for _, old in ipairs(character:GetChildren()) do
			if old.Name:match("^LiveLabUniform") then old:Destroy() end
		end
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not torso then return end
		local panel = Instance.new("Part")
		panel.Name = "LiveLabUniform_Coat"
		panel.Size = torso.Size + Vector3.new(0.18, 0.25, 0.18)
		panel.CFrame = torso.CFrame
		panel.Color = Color3.fromRGB(240, 244, 247)
		panel.Material = Enum.Material.Fabric
		panel.CanCollide = false
		panel.Massless = true
		panel.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso; weld.Part1 = panel; weld.Parent = panel
		local roleColour = roleColours[role] or Color3.fromRGB(150, 160, 170)
		local badge = weldPiece(character, panel, "LiveLabUniform_Badge", Vector3.new(0.4, 0.5, 0.08), Vector3.new(-0.52, 0.25, -panel.Size.Z / 2), roleColour)
		badge.Name = "LiveLabUniform_Badge"
		local head = character:FindFirstChild("Head")
		if head then
			local helmet = weldPiece(character, head, "LiveLabUniform_Helmet", Vector3.new(1.82, 0.7, 1.82), Vector3.new(0, 0.72, 0), roleColour)
			helmet.Shape = Enum.PartType.Ball
		end
	end

	local function refreshLiveHud(player)
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return end
		local gui = playerGui:FindFirstChild("LiveLabHUD")
		local label = gui and gui:FindFirstChild("Objective")
		if label and label:IsA("TextLabel") then
			local role = player:GetAttribute("LabRole") or "Choose a role"
			local carried = player:GetAttribute("CarriedSample") or ""
			local objective = player:GetAttribute("LabObjective") or ""
			local stats = player:FindFirstChild("leaderstats")
			local points = stats and stats:FindFirstChild("Points")
			local lastAmount = player:GetAttribute("LastPointAmount") or 0
			local lastReason = player:GetAttribute("LastPointAward") or ""
			local timer = ""
			if (player:GetAttribute("AssignedTransferDeadline") or 0) > 0 then
				timer = " • " .. math.max(0, player:GetAttribute("AssignedTransferDeadline") - os.time()) .. " sec"
			end
				label.Text = string.format("%s%s • POINTS %d%s\n%s%s", role,
				carried ~= "" and ("  •  HAND: " .. carried) or "",
				points and points.Value or 0,
				lastAmount > 0 and (" • LAST +" .. lastAmount .. " " .. lastReason) or "",
				objective ~= "" and objective or "Press E at BLUE or GREEN role kiosk.", timer)
		end
	end

	local function buildLiveHud(player)
		local playerGui = player:WaitForChild("PlayerGui", 5)
		if not playerGui then return end
		if playerGui:FindFirstChild("RoleHUD") then
			local duplicate = playerGui:FindFirstChild("LiveLabHUD")
			if duplicate then duplicate:Destroy() end
			return
		end
		if playerGui:FindFirstChild("LiveLabHUD") then refreshLiveHud(player); return end
		local gui = Instance.new("ScreenGui")
		gui.Name = "LiveLabHUD"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
		local label = Instance.new("TextLabel")
		label.Name = "Objective"
		label.Size = UDim2.new(0.48, 0, 0, 62)
		label.Position = UDim2.new(0.02, 0, 0, 54)
		label.BackgroundColor3 = Color3.fromRGB(10, 18, 22)
		label.BackgroundTransparency = 0.18
		label.BorderSizePixel = 0
		label.TextColor3 = Color3.fromRGB(225, 245, 232)
		label.TextWrapped = true
		label.TextScaled = false
		label.TextSize = 12
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Font = Enum.Font.GothamBold
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		local constraint = Instance.new("UISizeConstraint")
		constraint.MinSize = Vector2.new(260, 62)
		constraint.MaxSize = Vector2.new(360, 62)
		constraint.Parent = label
		refreshLiveHud(player)
	end

	for _, kiosk in ipairs(CollectionService:GetTagged("RoleKiosk")) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Select role"
		prompt.ObjectText = kiosk:GetAttribute("Role") or "Lab role"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = kiosk
		prompt.Triggered:Connect(function(player)
			local role = kiosk:GetAttribute("Role")
			local team = role and Teams:FindFirstChild(role)
			if team then player.Team = team; player.Neutral = false end
			player:SetAttribute("LabRole", role)
			liveAssignTask(player)
			if player.Character then dressCharacter(player.Character, role) end
			refreshLiveHud(player)
		end)
	end
	local function preserveLiveUniform(player)
		if player:GetAttribute("LiveUniformConnected") then return end
		player:SetAttribute("LiveUniformConnected", true)
		local stats = player:FindFirstChild("leaderstats")
		if not stats then stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player end
		local points = stats:FindFirstChild("Points")
		if not points then points = Instance.new("IntValue"); points.Name = "Points"; points.Parent = stats end
		task.spawn(buildLiveHud, player)
		player:GetAttributeChangedSignal("LabObjective"):Connect(function() refreshLiveHud(player) end)
		player:GetAttributeChangedSignal("CarriedSample"):Connect(function() refreshLiveHud(player) end)
		player:GetAttributeChangedSignal("LabRole"):Connect(function() refreshLiveHud(player) end)
		player:GetAttributeChangedSignal("LastPointAward"):Connect(function() refreshLiveHud(player) end)
		points:GetPropertyChangedSignal("Value"):Connect(function() refreshLiveHud(player) end)
		player.CharacterAdded:Connect(function(character)
			local role = player:GetAttribute("LabRole")
			if role then task.wait(0.35); dressCharacter(character, role) end
			local healthScript = character:FindFirstChild("Health")
			if healthScript then healthScript:Destroy() end
		end)
		if player.Character then
			local healthScript = player.Character:FindFirstChild("Health")
			if healthScript then healthScript:Destroy() end
		end
		task.spawn(function()
			while player.Parent do
				if (player:GetAttribute("AssignedTransferDeadline") or 0) > 0 then refreshLiveHud(player) end
				task.wait(1)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do preserveLiveUniform(player) end
	Players.PlayerAdded:Connect(preserveLiveUniform)

	local LIVE_IMPACT = {
		["Foam Baton"] = {mode = "melee", damage = 18, colour = Color3.fromRGB(245, 135, 55)},
		["Sample Grabber"] = {mode = "melee", damage = 12, colour = Color3.fromRGB(70, 165, 220)},
		["Inspection Paddle"] = {mode = "melee", damage = 22, colour = Color3.fromRGB(245, 205, 70)},
		["Stun Blaster"] = {mode = "gun", damage = 28, range = 95, colour = Color3.fromRGB(90, 225, 245)},
		["Foam Dart Rifle"] = {mode = "gun", damage = 38, range = 125, colour = Color3.fromRGB(225, 80, 95)},
		["Basketball"] = {mode = "ball", damage = 24, colour = Color3.fromRGB(225, 105, 35)},
	}

	local function liveBotFromHit(hit)
		local model = hit and hit:FindFirstAncestorOfClass("Model")
		return model and CollectionService:HasTag(model, "LabWorkerBot") and model or nil
	end

	local function refreshLiveBotHealth(bot)
		local maximum = bot:GetAttribute("MaxHealth") or 100
		local health = math.clamp(bot:GetAttribute("Health") or maximum, 0, maximum)
		local label = bot:FindFirstChild("HealthText", true)
		local fill = bot:FindFirstChild("HealthBarFill", true)
		if label and label:IsA("TextLabel") then label.Text = string.format("LIFE %d / %d", health, maximum) end
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.fromScale(health / math.max(1, maximum), 1)
			fill.BackgroundColor3 = health > maximum * 0.55 and Color3.fromRGB(75, 220, 95)
				or (health > maximum * 0.25 and Color3.fromRGB(245, 190, 55) or Color3.fromRGB(235, 65, 60))
		end
	end

	local function damageLiveBot(bot, amount, attacker)
		if not bot or bot:GetAttribute("KnockedOut") then return end
		local health = math.max(0, (bot:GetAttribute("Health") or 100) - amount)
		bot:SetAttribute("Health", health)
		bot:SetAttribute("LastHitBy", attacker and attacker.Name or "environment")
		refreshLiveBotHealth(bot)
		local flash = Instance.new("Highlight")
		flash.FillColor = Color3.fromRGB(255, 90, 70)
		flash.FillTransparency = 0.25
		flash.Parent = bot
		Debris:AddItem(flash, 0.22)
		if health <= 0 then
			bot:SetAttribute("KnockedOut", true)
			bot:SetAttribute("TaskState", "KNOCKED OUT")
			local status = bot:FindFirstChild("Status", true)
			if status and status:IsA("TextLabel") then status.Text = bot.Name .. "\nKNOCKED OUT" end
			task.delay(8, function()
				if bot.Parent then
					bot:SetAttribute("Health", bot:GetAttribute("MaxHealth") or 100)
					bot:SetAttribute("KnockedOut", false)
					refreshLiveBotHealth(bot)
				end
			end)
		end
	end

	local function stealLiveSample(attacker, victim)
		local stolen = findPlant(victim)
		local backpack = attacker:FindFirstChildOfClass("Backpack")
		if not stolen or stolen.Parent ~= victim.Character or not backpack then return end
		stolen.Parent = backpack
		victim:SetAttribute("CarriedSample", "")
		attacker:SetAttribute("CarriedSample", stolen:GetAttribute("PlantId") or stolen.Name)
		local destination = stolen:GetAttribute("DestinationGrowthCode") or ""
		attacker:SetAttribute("LabObjective", destination ~= "" and ("Stolen sample must be rescued to " .. destination .. ".")
			or "Use growth equipment, then return the sample to a working chamber.")
		equip(attacker, stolen)
	end

	local function grantImpactTool(player, kind)
		local style = LIVE_IMPACT[kind]
		if not style then return end
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 3)
		if not backpack then return end
		local existing = backpack:FindFirstChild(kind) or (player.Character and player.Character:FindFirstChild(kind))
		if existing then equip(player, existing); return end
		local tool = Instance.new("Tool")
		tool.Name = kind
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		tool.ToolTip = style.mode == "gun" and "Fire at worker NPCs"
			or (style.mode == "ball" and "Throw at worker NPCs" or "Hit NPCs or recover another player's held sample")
		tool:SetAttribute("LabImpactTool", true)
		tool:SetAttribute("ImpactToolKind", kind)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = style.mode == "gun" and Vector3.new(0.72, 0.88, 2.2)
			or (style.mode == "ball" and Vector3.new(1.35, 1.35, 1.35)
				or (kind == "Inspection Paddle" and Vector3.new(1.2, 3.2, 0.35) or Vector3.new(0.5, 3.4, 0.5)))
		handle.Color = style.colour
		handle.Material = style.mode == "ball" and Enum.Material.Rubber or Enum.Material.SmoothPlastic
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		if style.mode == "ball" then
			handle.Shape = Enum.PartType.Ball
		elseif style.mode == "gun" then
			weldPiece(tool, handle, "Barrel", Vector3.new(0.34, 0.34, 1.7), Vector3.new(0, 0.1, -1.65), style.colour)
			weldPiece(tool, handle, "GunGrip", Vector3.new(0.48, 1.05, 0.55), Vector3.new(0, -0.75, 0.42), Color3.fromRGB(42, 45, 52))
		end

		local activeUntil, nextUse = 0, 0
		local hitThisUse = {}
		tool.Activated:Connect(function()
			local attacker = Players:GetPlayerFromCharacter(tool.Parent)
			if not attacker or os.clock() < nextUse then return end
			nextUse = os.clock() + (style.mode == "gun" and 0.55 or 0.8)
			hitThisUse = {}
			local rootPart = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
			if not rootPart then return end
			if style.mode == "gun" then
				local origin = rootPart.Position + Vector3.new(0, 1.25, 0) + rootPart.CFrame.LookVector * 2
				local direction = rootPart.CFrame.LookVector * (style.range or 100)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = {attacker.Character}
				local result = workspace:Raycast(origin, direction, params)
				local hitPosition = result and result.Position or origin + direction
				local tracer = Instance.new("Part")
				tracer.Name = "FoamTracer"
				tracer.Size = Vector3.new(0.08, 0.08, (hitPosition - origin).Magnitude)
				tracer.CFrame = CFrame.lookAt((origin + hitPosition) / 2, hitPosition)
				tracer.Color = style.colour
				tracer.Material = Enum.Material.Neon
				tracer.Anchored = true
				tracer.CanCollide = false
				tracer.Parent = workspace
				Debris:AddItem(tracer, 0.12)
				local bot = result and liveBotFromHit(result.Instance)
				if bot then damageLiveBot(bot, style.damage, attacker) end
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
				local used = false
				ball.Touched:Connect(function(hit)
					if used then return end
					local bot = liveBotFromHit(hit)
					if bot then used = true; damageLiveBot(bot, style.damage, attacker) end
				end)
				Debris:AddItem(ball, 7)
			else
				activeUntil = os.clock() + 0.45
			end
		end)
		handle.Touched:Connect(function(hit)
			if style.mode ~= "melee" or os.clock() > activeUntil then return end
			local attacker = Players:GetPlayerFromCharacter(tool.Parent)
			if not attacker then return end
			local bot = liveBotFromHit(hit)
			if bot then
				if hitThisUse[bot] then return end
				hitThisUse[bot] = true
				damageLiveBot(bot, style.damage, attacker)
				return
			end
			local victim = Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model"))
			if not victim or attacker == victim or hitThisUse[victim] then return end
			hitThisUse[victim] = true
			stealLiveSample(attacker, victim)
		end)
		tool.Parent = backpack
		equip(player, tool)
	end

	for _, padPart in ipairs(CollectionService:GetTagged("LabToolDispenser")) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up and equip"
		prompt.ObjectText = padPart:GetAttribute("ToolKind") or "Recovery tool"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = padPart
		prompt.Triggered:Connect(function(player) grantImpactTool(player, padPart:GetAttribute("ToolKind")) end)
	end

	for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do bindLiveEquipment(equipment) end

	-- Automatic doors, live-fallback copy: same open-near / close-away
	-- behaviour as the installed runtime.
	local LIVE_DOOR_OPEN_RANGE = 11
	local LIVE_DOOR_CLOSE_RANGE = 15
	local LIVE_DOOR_MIN_OPEN_SECONDS = 3
	local function bindLiveAutoDoor(door)
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
			tween = TweenService:Create(door, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{CFrame = CFrame.new(targetX, doorY, targetZ)})
			tween:Play()
			door.CanCollide = not open
			setIndicatorColour(open)
		end
		task.spawn(function()
			while door.Parent do
				local nearest = math.huge
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					if hrp then
						-- Same fix as the installed runtime: floors stack at the
						-- same X/Z, so require the player be close in height to
						-- this door before the flat distance counts at all.
						local verticalGap = math.abs(hrp.Position.Y - doorY)
						if verticalGap < 8 then
							local flat = (Vector3.new(hrp.Position.X, doorY, hrp.Position.Z) - Vector3.new(closedX, doorY, closedZ)).Magnitude
							if flat < nearest then nearest = flat end
						end
					end
				end
				-- Minimum 3-second open hold before the door is allowed to
				-- close again -- fixes the open/close-too-fast flicker.
				if isOpen and nearest > LIVE_DOOR_CLOSE_RANGE and (os.clock() - openedAt) >= LIVE_DOOR_MIN_OPEN_SECONDS then
					setOpen(false)
				elseif not isOpen and nearest < LIVE_DOOR_OPEN_RANGE then
					setOpen(true)
				end
				task.wait(0.25)
			end
		end)
	end
	for _, p in ipairs(CollectionService:GetTagged("AutoDoor")) do bindLiveAutoDoor(p) end
	CollectionService:GetInstanceAddedSignal("AutoDoor"):Connect(bindLiveAutoDoor)

		local liveFacilityNoticeAt = setmetatable({}, {__mode = "k"})
		local function liveNotify(player, text)
			local facilityAlert = text:match("^ALARM:") or text:match("^REPAIR ALARM:") or text:match("^CATASTROPHIC FAILURE:")
			if facilityAlert then
				local now = os.clock()
				if now - (liveFacilityNoticeAt[player] or -math.huge) < 6 then return end
				liveFacilityNoticeAt[player] = now
			end
			print("[" .. player.Name .. "] " .. text)
		local gui = player:FindFirstChild("PlayerGui")
		if not gui then return end
		local screen = gui:FindFirstChild("LabLog")
		if not screen then
			screen = Instance.new("ScreenGui")
			screen.Name = "LabLog"
			screen.ResetOnSpawn = false
			screen.Parent = gui
			local label = Instance.new("TextLabel")
			label.Name = "Line"
				label.Size = UDim2.new(0.48, 0, 0, 46)
				label.Position = UDim2.new(0.5, 0, 1, -68)
				label.AnchorPoint = Vector2.new(0.5, 1)
			label.BackgroundTransparency = 0.3
			label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
			label.TextColor3 = Color3.fromRGB(255, 210, 90)
				label.TextScaled = false
				label.TextWrapped = true
				label.TextTruncate = Enum.TextTruncate.AtEnd
				label.TextSize = 13
			label.Font = Enum.Font.GothamBold
				label.Parent = screen
				local constraint = Instance.new("UISizeConstraint")
				constraint.MinSize = Vector2.new(260, 46)
				constraint.MaxSize = Vector2.new(420, 46)
				constraint.Parent = label
		end
		local label = screen:FindFirstChild("Line")
			if label then
				local serial = (screen:GetAttribute("MessageSerial") or 0) + 1
				screen:SetAttribute("MessageSerial", serial)
				label.Text = text
				label.Visible = true
				task.delay(4, function()
					if label.Parent and screen:GetAttribute("MessageSerial") == serial then label.Visible = false end
				end)
		end
	end

	-- EMERGENCY KITS: one per room, press E to fully restore health. Live-
	-- fallback copy of the same behaviour as the installed runtime.
	local function bindLiveEmergencyKit(kit)
		if kit:GetAttribute("KitBound") then return end
		kit:SetAttribute("KitBound", true)
		local prompt = kit:FindFirstChild("EmergencyKitPrompt")
		if not prompt then return end
		-- Recharges rather than being consumed, same as the installed copy.
		local RECHARGE_SECONDS = 25
		local function setCharged(charged)
			kit:SetAttribute("Charged", charged)
			prompt.Enabled = charged
			kit.Color = charged and Color3.fromRGB(225, 40, 35) or Color3.fromRGB(92, 60, 58)
		end
		prompt.Triggered:Connect(function(player)
			if kit:GetAttribute("Charged") == false then return end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end
			setCharged(false)
			humanoid.Health = humanoid.MaxHealth
			liveNotify(player, "Health restored. This station recharges in " .. RECHARGE_SECONDS .. "s.")
			task.delay(RECHARGE_SECONDS, function()
				if kit.Parent then setCharged(true) end
			end)
		end)
		setCharged(true)
	end
	for _, p in ipairs(CollectionService:GetTagged("EmergencyKit")) do bindLiveEmergencyKit(p) end
	CollectionService:GetInstanceAddedSignal("EmergencyKit"):Connect(bindLiveEmergencyKit)

	-- SECRET BASEMENT VENT: live-fallback copy of the same disguised panel
	-- behaviour -- hold E on it to drop straight into the basement corridor.
	local function bindLiveSecretBasementPanel(panel)
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
			liveNotify(player, "The vent panel swings open -- you drop into the basement.")
		end)
	end
	for _, p in ipairs(CollectionService:GetTagged("SecretBasementPanel")) do bindLiveSecretBasementPanel(p) end
	CollectionService:GetInstanceAddedSignal("SecretBasementPanel"):Connect(bindLiveSecretBasementPanel)

	local function liveNearestEmergencyKit(position)
		local best, bestDist
		for _, kit in ipairs(CollectionService:GetTagged("EmergencyKit")) do
			if kit.Parent then
				local d = (kit.Position - position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = kit, d end
			end
		end
		return best
	end

	local liveHealthPathActive = {}
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
					if low and not busy and not liveHealthPathActive[player] then
						local kit = liveNearestEmergencyKit(hrp.Position)
						if kit then
							createLiveRepairPath(player, kit)
							liveHealthPathActive[player] = true
							liveNotify(player, "Health low: follow the RED floor lights to the nearest emergency kit.")
						end
					elseif (not low or busy) and liveHealthPathActive[player] then
						liveHealthPathActive[player] = false
						if not busy then clearLiveRepairPath(player) end
					end
				end
			end
		end
	end)

	-- EQUIPMENT HAZARDS: a FAILED unit drains health in nearby players --
	-- electrical faults, steam/humidity blowouts, chemical spills, coolant
	-- (freon) leaks. Live-fallback copy of the installed runtime's version.
	local LIVE_HAZARD_BY_KIND = {
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
	local LIVE_HAZARD_RANGE = 9
	local liveHazardWarnedAt = {}

	local LIVE_DESTRUCTION_KIND = {
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

	local function liveScatterDebris(part)
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

	-- Same catastrophic-failure escalation as the installed runtime: a unit
	-- left FAILED too long can permanently blow up / catch fire / arc, with
	-- kind-dependent smoke/liquid/gas effects and flying debris.
	local destroyLiveEquipment

	local function warnLiveEquipmentCatastrophe(part, floorLabel, unitLabel)
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
			liveNotify(player, "ALARM: " .. floorLabel .. " • " .. unitLabel .. " is about to fail catastrophically -- MOVE AWAY NOW!")
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
			if part.Parent then destroyLiveEquipment(part) end
		end)
	end

	destroyLiveEquipment = function(part)
		local floorLabel = liveFloor(part)
		local unitLabel = liveEquipmentLabel(part)
		local causes = {"exploded", "caught fire", "arced and shorted out"}
		local cause = causes[math.random(1, #causes)]
		part:SetAttribute("FunctionalState", "DESTROYED")
		part:SetAttribute("AboutToBlow", nil)
		part:SetAttribute("RepairInstruction", floorLabel .. " • " .. unitLabel .. " • DESTROYED, UNFIXABLE")
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

		local kindOfDestruction = LIVE_DESTRUCTION_KIND[part:GetAttribute("Kind")] or "electrical"

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

		liveScatterDebris(part)

		for _, player in ipairs(Players:GetPlayers()) do
			liveNotify(player, "CATASTROPHIC FAILURE: " .. floorLabel .. " • " .. unitLabel .. " " .. cause .. ". It cannot be repaired.")
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local hazards = {}
			for _, equip in ipairs(CollectionService:GetTagged("LabEquipment")) do
				local state = equip.Parent and equip:GetAttribute("FunctionalState")
				if state == "FAILED" then
					local info = LIVE_HAZARD_BY_KIND[equip:GetAttribute("Kind")]
					if info then table.insert(hazards, {part = equip, label = info[1], dps = info[2]}) end
					local failedFor = os.time() - (equip:GetAttribute("FailureSince") or os.time())
					if failedFor > 45 and math.random(1, 6) == 1 then
						warnLiveEquipmentCatastrophe(equip, liveFloor(equip), liveEquipmentLabel(equip))
					end
				elseif state == "DESTROYED" then
					local info = LIVE_HAZARD_BY_KIND[equip:GetAttribute("Kind")]
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
							if d < LIVE_HAZARD_RANGE and (not worst or hazard.dps > worst.dps) then worst = hazard end
						end
						if worst then
							humanoid:TakeDamage(worst.dps)
							local last = liveHazardWarnedAt[player] or 0
							if os.clock() - last > 2 then
								liveHazardWarnedAt[player] = os.clock()
								liveNotify(player, string.format("WARNING: %s nearby -- move away! (%d HP)", worst.label, math.floor(humanoid.Health)))
							end
						end
					end
				end
			end
		end
	end)

	-- Fallback runtime uses the same full-body navigation as installed gameplay.
	local function liveBotInteractionPoint(part)
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
	
	local function botMove(bot, target)
		local destination = liveBotInteractionPoint(target)
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
	
	local function liveBotPlant(bot, visible)
		local oldHeld = bot:FindFirstChild("BotHeldPlant")
		if oldHeld then oldHeld:Destroy() end
		if not visible then return end
		local held = Instance.new("Model")
		held.Name = "BotHeldPlant"
		held.Parent = bot
		local base = bot:GetPivot() * CFrame.new(1.45, 0.1, -0.7)
		for _, data in ipairs({
			{"Pot", Vector3.new(0.82, 0.62, 0.82), Vector3.new(0, 0, 0), Color3.fromRGB(116, 75, 45)},
			{"Stem", Vector3.new(0.13, 1.0, 0.13), Vector3.new(0, 0.72, 0), Color3.fromRGB(58, 160, 70)},
			{"LeafL", Vector3.new(0.55, 0.13, 0.34), Vector3.new(-0.25, 0.9, 0), Color3.fromRGB(73, 185, 84)},
			{"LeafR", Vector3.new(0.55, 0.13, 0.34), Vector3.new(0.25, 1.12, 0), Color3.fromRGB(73, 185, 84)},
		}) do
			local piece = Instance.new("Part")
			piece.Name = data[1]
			piece.Size = data[2]
			piece.CFrame = base * CFrame.new(data[3])
			piece.Color = data[4]
			piece.Material = Enum.Material.SmoothPlastic
			piece.Anchored = true
			piece.CanCollide = false
			piece.CanTouch = false
			piece.Parent = held
		end
	end
	local function refreshLiveBotBoard()
		local workers = CollectionService:GetTagged("LabWorkerBot")
		local cycles, carrying, knockedOut, rivalScore = 0, 0, 0, 0
		for _, worker in ipairs(workers) do
			cycles = cycles + (worker:GetAttribute("CompletedCycles") or 0)
			if (worker:GetAttribute("CarryingPlant") or "") ~= "" then carrying = carrying + 1 end
			if worker:GetAttribute("KnockedOut") then knockedOut = knockedOut + 1 end
			if worker:GetAttribute("Competitor") then rivalScore = worker:GetAttribute("Score") or 0 end
		end
		local chambers = CollectionService:GetTagged("PlantGrowthChamber")
		local failed, failedSamples, totalSamples = 0, 0, 0
		for _, chamber in ipairs(chambers) do
			local count = chamber:GetAttribute("SampleCount") or 0
			totalSamples = totalSamples + count
			if chamber:GetAttribute("FunctionalState") == "FAILED" then
				failed = failed + 1
				failedSamples = failedSamples + count
			end
		end
		for _, board in ipairs(CollectionService:GetTagged("BotTestBoard")) do
			for _, label in ipairs(board:GetDescendants()) do
				if label:IsA("TextLabel") and label.Name == "BotTestStatus" then
					label.Text = string.format(
						"NPC GAMEPLAY TESTS\nWorkers: %d / 50  •  knocked out: %d\nRescue cycles: %d  •  plants in transit: %d\nFailed chambers: %d / %d  •  failed samples: %d\nStored samples: %d  •  RIVAL SCORE: %d",
						#workers, knockedOut, cycles, carrying, failed, #chambers, failedSamples, totalSamples, rivalScore)
				end
			end
		end
	end

	local function setLiveBotStatus(bot, message)
		bot:SetAttribute("TaskState", message)
		local status = bot:FindFirstChild("Status", true)
		if status and status:IsA("TextLabel") then status.Text = (bot:GetAttribute("DisplayName") or bot.Name) .. "\n" .. message end
	end

	-- Same room-occupancy gate as the installed script: a worker only runs
	-- while a player is in the room with it.
	local liveFloorBand, liveWakeRadius = 10, 35
	local liveRoomsByLevel = {}
	do
		local complex = workspace:FindFirstChild("Laboratory_Complex")
		local packed = complex and complex:GetAttribute("RoomIndex")
		if typeof(packed) == "string" then
			for entry in packed:gmatch("[^;]+") do
				local level, name, x1, z1, x2, z2, y =
					entry:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")
				if level then
					liveRoomsByLevel[level] = liveRoomsByLevel[level] or {}
					table.insert(liveRoomsByLevel[level], {
						name = name, x1 = tonumber(x1), z1 = tonumber(z1),
						x2 = tonumber(x2), z2 = tonumber(z2), y = tonumber(y),
					})
				end
			end
		end
	end

	local function liveRoomAt(levelName, position)
		local list = levelName and liveRoomsByLevel[levelName]
		if not list then return nil end
		for _, r in ipairs(list) do
			if math.abs(position.Y - r.y) < liveFloorBand
				and position.X >= r.x1 and position.X <= r.x2
				and position.Z >= r.z1 and position.Z <= r.z2 then
				return r.name
			end
		end
		return nil
	end

	local function liveBotHasObserver(bot)
		local ok, pivot = pcall(function() return bot:GetPivot().Position end)
		if not ok then return false end
		local levelName = bot:GetAttribute("Level")
		local botRoom = liveRoomAt(levelName, pivot)
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local here = hrp.Position
				if math.abs(here.Y - pivot.Y) < liveFloorBand then
					if botRoom and liveRoomAt(levelName, here) == botRoom then return true end
					local dx, dz = here.X - pivot.X, here.Z - pivot.Z
					if dx * dx + dz * dz < liveWakeRadius * liveWakeRadius then return true end
				end
			end
		end
		return false
	end

	local bots = CollectionService:GetTagged("LabWorkerBot")
	for index, bot in ipairs(bots) do
		refreshLiveBotHealth(bot)
		-- Sleeping bots are cheap, so there is no herd to spread out.
		local startSlot = bot:GetAttribute("LevelSlot") or index
		task.delay(startSlot * 0.08, function()
			while bot.Parent do
				local awake = bot:GetAttribute("Competitor") or liveBotHasObserver(bot)
				if not awake then
					setLiveBotStatus(bot, "Idle -- no one in the room")
					task.wait(1)
				elseif bot:GetAttribute("KnockedOut") then
					task.wait(1)
				else
					local levelName = bot:GetAttribute("Level")
					local failed, stations = {}, {}
					for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
						if equipment:GetAttribute("Level") == levelName then
							if equipment:GetAttribute("Kind") == "Plant Growth Chamber"
								and equipment:GetAttribute("FunctionalState") == "FAILED"
								and (equipment:GetAttribute("SampleCount") or 0) > 0
								and not equipment:GetAttribute("ReservedByBot") then
								table.insert(failed, equipment)
							end
							if plantProcesses[equipment:GetAttribute("Kind")] then table.insert(stations, equipment) end
						end
					end
					if #failed == 0 then
						setLiveBotStatus(bot, "Monitoring chamber alarms")
					else
						table.sort(failed, function(a, b)
							return (tonumber((a:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge)
								< (tonumber((b:GetAttribute("GrowthCode") or ""):match("%d+")) or math.huge)
						end)
						local source = bot:GetAttribute("Competitor") and failed[1] or failed[math.random(1, #failed)]
						local destination = liveDestinations(source)[1]
						if not destination then
							setLiveBotStatus(bot, "Waiting for safe capacity")
						else
							source:SetAttribute("ReservedByBot", bot.Name)
							destination:SetAttribute("IncomingReservations", (destination:GetAttribute("IncomingReservations") or 0) + 1)
							source:SetAttribute("EvacuationDestination", destination:GetAttribute("GrowthCode") or "")
							refreshLiveTelemetry(source)
							setLiveBotStatus(bot, "Responding to " .. (source:GetAttribute("GrowthCode") or "alarm"))
							botMove(bot, source)
							local sourceSamples = liveChamberSamples(source)
							local plantId = table.remove(sourceSamples, 1)
							if plantId and source:GetAttribute("ReservedByBot") == bot.Name then
								saveLiveChamber(source, sourceSamples)
								showChamberPlant(source, true)
								refreshLiveTelemetry(source)
								bot:SetAttribute("CarryingPlant", plantId)
								liveBotPlant(bot, true)
								setLiveBotStatus(bot, "Evacuating " .. plantId)

								local stage = source:GetAttribute("GrowthStage") or 0
								if #stations > 0 then
									local station = stations[((bot:GetAttribute("BotNumber") or index) - 1) % #stations + 1]
									botMove(bot, station)
									local process = plantProcesses[station:GetAttribute("Kind")]
									stage = math.clamp(stage + (process.gain or 0), 0, 5)
									station:SetAttribute("BotTestUses", (station:GetAttribute("BotTestUses") or 0) + 1)
								end

								setLiveBotStatus(bot, "Delivering to " .. (destination:GetAttribute("GrowthCode") or "working chamber"))
								botMove(bot, destination)
								local destinationSamples = liveChamberSamples(destination)
								if destination:GetAttribute("FunctionalState") ~= "FAILED"
									and #destinationSamples < (destination:GetAttribute("Capacity") or 10) then
									table.insert(destinationSamples, plantId)
									saveLiveChamber(destination, destinationSamples)
									destination:SetAttribute("GrowthStage", math.max(destination:GetAttribute("GrowthStage") or 0, stage))
									showChamberPlant(destination, true)
									refreshLiveTelemetry(destination)
									liveEmergencyMoves = liveEmergencyMoves + 1
									bot:SetAttribute("CompletedCycles", (bot:GetAttribute("CompletedCycles") or 0) + 1)
									if bot:GetAttribute("Competitor") then
										bot:SetAttribute("Score", (bot:GetAttribute("Score") or 0) + LIVE_POINTS.MOVE_ON_TIME)
										setLiveBotStatus(bot, "+" .. LIVE_POINTS.MOVE_ON_TIME .. " resource win")
										refreshLiveScoreboard()
									else
										setLiveBotStatus(bot, "Rescue cycle passed")
									end
								else
									table.insert(sourceSamples, plantId)
									saveLiveChamber(source, sourceSamples)
									showChamberPlant(source, true)
									refreshLiveTelemetry(source)
									setLiveBotStatus(bot, "Destination changed; retrying")
								end
								bot:SetAttribute("CarryingPlant", "")
								liveBotPlant(bot, false)
							end
							destination:SetAttribute("IncomingReservations", math.max(0, (destination:GetAttribute("IncomingReservations") or 1) - 1))
							if source:GetAttribute("ReservedByBot") == bot.Name then source:SetAttribute("ReservedByBot", nil) end
						end
					end
				end
				refreshLiveBotBoard()
				task.wait(1.5 + math.random())
			end
		end)
	end

	local LIVE_FAILURE_REASONS = {
		"Temperature control fault", "Humidity sensor drift", "Ventilation fan blocked",
		"Door seal leak", "Lighting circuit fault", "Nutrient pump pressure low",
	}
	local previousLiveMoves = 0
	setLiveFailure = function(chamber, failed)
		local codeNumber = tonumber((chamber:GetAttribute("GrowthCode") or ""):match("%d+")) or 1
		local code = chamber:GetAttribute("GrowthCode") or ("R" .. codeNumber)
		local floorLabel = chamber:GetAttribute("FloorLabel") or chamber:GetAttribute("Level") or "UNKNOWN FLOOR"
		if failed then
			chamber:SetAttribute("FunctionalState", "FAILED")
			if chamber:GetAttribute("PlantLife") == nil then chamber:SetAttribute("PlantLife", 100) end
			chamber:SetAttribute("RepairKey", "R")
			chamber:SetAttribute("RepairInstruction", "Go to " .. floorLabel .. " • CHAMBER " .. code .. " • HOLD R TO REPAIR")
			chamber:SetAttribute("FailureReason", LIVE_FAILURE_REASONS[math.random(1, #LIVE_FAILURE_REASONS)])
			chamber:SetAttribute("FailureSince", os.time())
			chamber:SetAttribute("Temperature", 31 + codeNumber % 8)
			chamber:SetAttribute("Humidity", 35 + codeNumber % 24)
			chamber:SetAttribute("Ventilation", 10 + codeNumber % 28)
			local destination = liveDestinations(chamber)[1]
			chamber:SetAttribute("EvacuationDestination", destination and destination:GetAttribute("GrowthCode") or "")
			for _, player in ipairs(Players:GetPlayers()) do
				if livePlayerRole(player) == "Technician" and not player:GetAttribute("AssignedRepairId") then liveAssignTask(player) end
				if livePlayerRole(player) == "Laboratory Technician" and not player:GetAttribute("AssignedTransferSource") then liveAssignTask(player) end
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
				recoverLivePlantLife(chamber, chamber:GetAttribute("PlantLife"), nil, chamber:GetAttribute("PlantId"))
			end
		end
		refreshLiveTelemetry(chamber)
	end

	local LIVE_GENERIC_REASONS = {"Power relay fault", "Controller link lost", "Pump interlock fault", "Calibration expired", "Motor overload"}
	setLiveGenericFailure = function(part, failed)
		if failed then
			part:SetAttribute("FunctionalState", "FAILED")
			part:SetAttribute("FailureReason", LIVE_GENERIC_REASONS[math.random(1, #LIVE_GENERIC_REASONS)])
			part:SetAttribute("FailureSince", os.time())
			part:SetAttribute("RepairInstruction", liveFloor(part) .. " • " .. liveEquipmentLabel(part) .. " • HOLD R")
		else
			part:SetAttribute("FunctionalState", "WORKING")
			part:SetAttribute("FailureReason", "")
			part:SetAttribute("FailureSince", 0)
			part:SetAttribute("RepairInstruction", "WORKING • E USE / INSPECT")
			part:SetAttribute("OperationStarted", os.time())
		end
		local readout = part:FindFirstChild("Readout", true)
		if readout and readout:IsA("TextLabel") then
			readout.Text = (failed and "FAILED • HOLD R\n" or "WORKING\n") .. liveFloor(part) .. " • " .. liveEquipmentLabel(part)
				.. "\nPLANTS " .. (part:GetAttribute("SampleCount") or 0) .. "/" .. (part:GetAttribute("Capacity") or 0)
			readout.TextColor3 = failed and Color3.fromRGB(255, 105, 90) or Color3.fromRGB(115, 235, 165)
		end
		if failed then
			for _, player in ipairs(Players:GetPlayers()) do
				if livePlayerRole(player) == "Technician" and not player:GetAttribute("AssignedRepairId") then liveAssignTask(player) end
			end
		end
	end

	local function liveAdaptiveFailureTick()
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
			else
				if os.time() - (chamber:GetAttribute("LastRepairedAt") or 0) >= 45 then
					table.insert(working, chamber)
				end
				workingFree = workingFree + math.max(0, capacity - count - (chamber:GetAttribute("IncomingReservations") or 0))
			end
		end
		local throughput = liveEmergencyMoves - previousLiveMoves
		previousLiveMoves = liveEmergencyMoves
		local backlogRatio = failedSamples / math.max(1, totalSamples)
		local playerCount = math.max(1, #Players:GetPlayers())
		local targetRate = 0.60 + math.clamp((throughput - 5) * 0.003, -0.03, 0.08)
			+ math.clamp((playerCount - 1) * 0.012, 0, 0.10)
			- math.clamp((backlogRatio - 0.60) * 0.08, -0.04, 0.04)
		if workingFree < 20 then targetRate = targetRate - 0.12 end
		targetRate = math.clamp(targetRate, 0.42, 0.76)
		local targetFailed = math.floor(#chambers * targetRate + 0.5)
		local maxChange = math.clamp(2 + playerCount * 2, 4, 12)
		local change = math.clamp(targetFailed - #failed, -maxChange, maxChange)
		if change > 0 then
			for _ = 1, change do
				if #working == 0 then break end
				local chosen = table.remove(working, math.random(1, #working))
				setLiveFailure(chosen, true)
			end
		elseif change < 0 then
			table.sort(failed, function(a, b) return (a:GetAttribute("SampleCount") or 0) < (b:GetAttribute("SampleCount") or 0) end)
			for _ = 1, -change do
				if #failed == 0 then break end
				setLiveFailure(table.remove(failed, 1), false)
			end
		end

		local currentFailed = 0
		for _, chamber in ipairs(chambers) do
			if chamber:GetAttribute("FunctionalState") == "FAILED" then
				currentFailed = currentFailed + 1
				chamber:SetAttribute("Temperature", math.clamp((chamber:GetAttribute("Temperature") or 33) + math.random(-2, 2), 28, 42))
				chamber:SetAttribute("Humidity", math.clamp((chamber:GetAttribute("Humidity") or 45) + math.random(-4, 4), 25, 65))
				chamber:SetAttribute("Ventilation", math.clamp((chamber:GetAttribute("Ventilation") or 20) + math.random(-5, 3), 0, 48))
				local destination = liveDestinations(chamber)[1]
				chamber:SetAttribute("EvacuationDestination", destination and destination:GetAttribute("GrowthCode") or "")
			else
				local samples = liveChamberSamples(chamber)
				local capacity = chamber:GetAttribute("Capacity") or 10
				local refillChance = math.clamp(0.10 + (capacity - #samples) * 0.022 + throughput * 0.002
					+ playerCount * 0.008, 0.10, 0.46)
				if #samples < capacity and math.random() < refillChance then
					liveSampleSerial = liveSampleSerial + 1
					table.insert(samples, string.format("%s-G%05d", chamber:GetAttribute("GrowthCode") or "R", liveSampleSerial))
					saveLiveChamber(chamber, samples)
					chamber:SetAttribute("GerminationDate", os.date("%Y-%m-%d %H:%M"))
					showChamberPlant(chamber, true)
				end
			end
			refreshLiveTelemetry(chamber)
		end
		local complex = workspace:FindFirstChild("Laboratory_Complex")
		if complex then
			complex:SetAttribute("AdaptiveFailureTargetPercent", math.floor(targetRate * 100 + 0.5))
			complex:SetAttribute("FailingChambers", currentFailed)
			complex:SetAttribute("FailedSampleBacklog", failedSamples)
			complex:SetAttribute("EmergencyMovesCompleted", liveEmergencyMoves)
			complex:SetAttribute("RecentTransferThroughput", throughput)
			complex:SetAttribute("ActivePlayerCount", playerCount)
			complex:SetAttribute("ActiveNPCWorkers", math.clamp(8 + playerCount * 6 + math.floor(failedSamples / 20), 8, 50))
		-- Per-FLOOR budget. Multiplied across the basement plus every level
		-- this is what actually decides how many workers are visibly busy.
		complex:SetAttribute("ActiveNPCWorkersPerFloor", math.clamp(6 + playerCount * 2 + math.floor(failedSamples / 60), 6, 20))
		end
	end

	local function liveGenericFailureTick()
		local failed, working = {}, {}
		for _, equipment in ipairs(CollectionService:GetTagged("LabEquipment")) do
			if equipment:GetAttribute("Kind") ~= "Plant Growth Chamber" then
				if equipment:GetAttribute("FunctionalState") == "FAILED" then table.insert(failed, equipment)
				elseif os.time() - (equipment:GetAttribute("LastRepairedAt") or 0) >= 45 then table.insert(working, equipment) end
			end
		end
		local playerCount = math.max(1, #Players:GetPlayers())
		local targetRate = math.clamp(0.12 + playerCount * 0.018, 0.14, 0.28)
		local target = math.max(2, math.floor((#failed + #working) * targetRate + 0.5))
		local maxChange = math.clamp(1 + math.ceil(playerCount / 2), 2, 6)
		local change = math.clamp(target - #failed, -maxChange, maxChange)
		for _ = 1, math.max(0, change) do
			if #working == 0 then break end
			setLiveGenericFailure(table.remove(working, math.random(1, #working)), true)
		end
		for _ = 1, math.max(0, -change) do
			if #failed == 0 then break end
			setLiveGenericFailure(table.remove(failed, 1), false)
		end
	end

	task.spawn(function()
		while task.wait(2) do refreshLiveBotBoard() end
	end)
	task.spawn(function()
		while task.wait(2) do refreshLiveRoomMonitors() end
	end)
	task.spawn(function()
		task.wait(3)
		while true do
			liveAdaptiveFailureTick()
			liveGenericFailureTick()
			task.wait(math.clamp(15 - #Players:GetPlayers() * 1.25, 6, 14))
		end
	end)
	Players.PlayerRemoving:Connect(clearLiveRepairPath)
	warn("Seed Lab live fallback armed: normal Script.Source installation was unavailable, but E/F gameplay is active for this play session.")
end

do
	for _, n in ipairs({"LabKinds"}) do
		local e = ReplicatedStorage:FindFirstChild(n); if e then e:Destroy() end
	end
	for _, n in ipairs({"LabEquipment", "LabElevators", "LabRoles", "LabWorkflow", "SeedLabWorkflow", "ServerBlasterManager"}) do
		local e = ServerScriptService:FindFirstChild(n); if e then e:Destroy() end
	end
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	if modules and not modules:IsA("Folder") then modules:Destroy(); modules = nil end
	if not modules then
		modules = Instance.new("Folder")
		modules.Name = "Modules"
		modules.Parent = ReplicatedStorage
	end
	for _, moduleName in ipairs({"Blaster", "BlasterController"}) do
		local oldModule = modules:FindFirstChild(moduleName)
		if oldModule then oldModule:Destroy() end
	end
	-- Replace the old quiz with the compact addition-check popup.
	for _, clientName in ipairs({"LabQuizClient", "LabSidearmClient", "LabHUD"}) do
		local oldClient = StarterPlayer.StarterPlayerScripts:FindFirstChild(clientName)
		if oldClient then oldClient:Destroy() end
	end
	local oldFlow = ReplicatedStorage:FindFirstChild("LabFlow"); if oldFlow then oldFlow:Destroy() end
	local oldFlow2 = ReplicatedStorage:FindFirstChild("ISTA_Flow"); if oldFlow2 then oldFlow2:Destroy() end

	local mod = Instance.new("ModuleScript"); mod.Name = "LabKinds"
	local s1  = Instance.new("Script");       s1.Name  = "LabEquipment"
	local s2  = Instance.new("Script");       s2.Name  = "LabElevators"
	local s3  = Instance.new("Script");       s3.Name  = "LabRoles"
	local s4  = Instance.new("LocalScript");  s4.Name  = "LabSidearmClient"
	local s5  = Instance.new("LocalScript");  s5.Name  = "LabHUD"
	local quizClient = Instance.new("LocalScript"); quizClient.Name = "LabQuizClient"
	local blasterModule = Instance.new("ModuleScript"); blasterModule.Name = "Blaster"
	local controllerModule = Instance.new("ModuleScript"); controllerModule.Name = "BlasterController"
	local serverBlaster = Instance.new("Script"); serverBlaster.Name = "ServerBlasterManager"

	local ok = pcall(function()
		mod.Source = FLOW_SOURCE
		s1.Source  = EQUIP_SCRIPT_SOURCE
		s2.Source  = ELEVATOR_SCRIPT_SOURCE
		s3.Source  = ROLES_SCRIPT_SOURCE
		s4.Source  = SIDEARM_CLIENT_SOURCE
		s5.Source  = LAB_HUD_SOURCE
		quizClient.Source = QUIZ_CLIENT_SOURCE
		blasterModule.Source = BLASTER_SOURCE
		controllerModule.Source = BLASTER_CONTROLLER_SOURCE
		serverBlaster.Source = SERVER_BLASTER_MANAGER_SOURCE
	end)

	if ok then
		mod.Parent = ReplicatedStorage
		blasterModule.Parent = modules
		controllerModule.Parent = modules
		serverBlaster.Parent = ServerScriptService
		s1.Parent = ServerScriptService
		s2.Parent = ServerScriptService
		s3.Parent = ServerScriptService
		s4.Parent = StarterPlayer.StarterPlayerScripts
		s5.Parent = StarterPlayer.StarterPlayerScripts
		quizClient.Parent = StarterPlayer.StarterPlayerScripts
		print("Installed lab runtime plus cross-platform Blaster, BlasterController and ServerBlasterManager.")
	else
		mod:Destroy(); s1:Destroy(); s2:Destroy(); s3:Destroy(); s4:Destroy(); s5:Destroy()
		quizClient:Destroy()
		blasterModule:Destroy(); controllerModule:Destroy(); serverBlaster:Destroy()
		if RunService:IsRunning() then
			startLiveRuntimeFallback()
		else
			warn("Could not write script source from this context. Run the file from the Studio Command Bar.")
		end
	end
end

--=====================================================================
-- LOAD TIME
--=====================================================================
-- The place is ~77,000 parts. Without streaming, a joining client has to
-- download and build every one of them before it can move -- that is the
-- bulk of the join wait. With streaming on, the server sends only what is
-- near the player and fills the rest in as they walk, which is the single
-- biggest thing available here for load time. These are place properties,
-- so they are saved with the place and only settable from Edit.
do
	local ok = pcall(function() Workspace.StreamingEnabled = true end)
	if ok then
		pcall(function() Workspace.StreamingMinRadius = 160 end)
		pcall(function() Workspace.StreamingTargetRadius = 512 end)
		pcall(function()
			Workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.MinimumRadiusPause
		end)
		print("Streaming enabled for faster joins.")
	else
		warn("Could not enable streaming from this context; set Workspace.StreamingEnabled by hand.")
	end
end

--=====================================================================
-- LIGHTING SERVICE
--=====================================================================
if CONFIGURE_LIGHTING then
	local ok = pcall(function() Lighting.Technology = Enum.Technology.ShadowMap end)
	if not ok then warn("Set Lighting.Technology to ShadowMap or Future by hand.") end
	Lighting.GlobalShadows            = true
	Lighting.Brightness               = 1.3
	Lighting.ExposureCompensation     = -0.35
	Lighting.Ambient                  = Color3.fromRGB(58, 60, 66)
	Lighting.OutdoorAmbient           = Color3.fromRGB(92, 96, 104)
	Lighting.EnvironmentDiffuseScale  = 0.35
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.ClockTime                = 13.5
	Lighting.GeographicLatitude       = 45
	for _, fx in ipairs(Lighting:GetChildren()) do
		if fx:IsA("BloomEffect") then
			fx.Intensity = math.min(fx.Intensity, 0.4)
			fx.Threshold = math.max(fx.Threshold, 1.2)
		end
	end
end

local lamps, doors = 0, 0
for _, d in ipairs(root:GetDescendants()) do
	if d:IsA("PointLight") then lamps = lamps + 1 end
	if d.Name:find("_leaf") then doors = doors + 1 end
end
local growthChamberCount = #CollectionService:GetTagged("PlantGrowthChamber")
local workerBotCount = #CollectionService:GetTagged("LabWorkerBot")
local expectedChambers = (#LEVELS + 1) * 50
local expectedBots = (#LEVELS + 1) * BOTS_PER_LEVEL
if growthChamberCount ~= expectedChambers then
	warn("BUILD CHECK FAILED: expected " .. expectedChambers .. " plant growth chambers, created " .. growthChamberCount .. ".")
end
if workerBotCount ~= expectedBots then
	warn("BUILD CHECK FAILED: expected " .. expectedBots .. " worker test NPCs, created " .. workerBotCount .. ".")
end
print(string.format(
	"Built: %.0f x %.0f studs -- %d floors (ground floor %d rooms, floors 2-%d %d rooms each), basement %d rooms -- %d equipment items including %d plant growth chambers, %d worker test NPCs, %d door leaves, stairs-only (no elevators), %d lights, %d parts.",
	X(W), X(L), #LEVELS, #GROUND_ROOMS, #LEVELS, #TYPICAL_ROOMS, #BASEMENT_ROOMS, placedCount, growthChamberCount,
	workerBotCount, doors, lamps, #root:GetDescendants()))
