--[========[
GENRMINATION_FIGHT  --  COMPLETE WRITTEN REFERENCE
Revision 5, 14 September 2026.  Place 137098589879404.

This is the full engineering record, embedded verbatim for AI models reading
the place directly (Claude, ChatGPT, DeepSeek and others). It is a comment:
Lua discards it at compile time, so it has no runtime cost, and it lives in
ServerStorage, which never replicates to clients.

AUTHORITY: the 'Revision 5' chapter supersedes every chapter after it wherever
they disagree. Revision 4's C01/C02 conclusions are WRONG and are annotated in
place with '*** CORRECTED BY REVISION 5 ***'.

STANDING RULES FOR ANY MODEL MODIFYING THIS GAME:
  1. Never compose a global coordinate frame from a landmark part.
  2. Never store world coordinates in gameplay code. Resolve positions at
     runtime from RoomIndex, CollectionService tags, or instance lookup.
  3. Fixes belong in SeedLabGenerator.lua as well as the installed scripts;
     the installed scripts are its output and a rebuild reverts them.
  4. Declare locals above every function that names them. This project has
     lost threads to the nil-global trap five separate times.
  5. Verify with a numeric scene query, not a single play-through.
  6. Do not transform live instances. If unavoidable, make it idempotent and
     assert a known part lands where expected before touching the rest.

Reference part 2 of 2.
==============================================================================
BotsTotal | 1325, 1364 

BreakableWindow | 1347 

Capacity | 1511, 1635, 1750, 1816, 1847, 2115, 2145, 2206, 2224, 2570, 3215, 3328, 3343, 3362, 3412 

CarriedSample | 538, 545, 551, 2183 

CarryingPlant | 2824, 3195, 3242 

ChamberStatusLamp | 1834 

Charged | 3592, 3599 

Competitor | 61, 2825, 3022, 3120, 3174, 3223 

CompletedCycles | 2822, 3222 

Dead | 630, 648, 760, 862, 1297, 1301, 1358, 1360, 2990, 3021, 3022, 3023, 3043, 3113, 3117, 4019, 4024 

DestinationGrowthCode | 524, 537, 2180, 2229 

DestinationLabel | 537, 2455, 2512 

DestinationStorageId | 2510 

DispenserBound | 1194, 1197 

DisplayName | 2814 

DoorBound | 3497, 3498 

DoorClosedX | 3499 

DoorClosedZ | 3500 

DoorOpen | 3529, 4102, 4103 

DoorOpenX | 3501 

DoorOpenZ | 3502 

DoorY | 3503 

EmergencyMovesCompleted | 3431 

EmergencyTransfers | 2253 

EquipmentId | 2572 

EquipmentTaskRoutingBound | 3466, 3467 

EvacuationDestination | 1812, 3183, 3283, 3298, 3409 

Exploded | 729, 730, 833 

FailedSampleBacklog | 1419, 3430 

FailingChambers | 3429 

FailureReason | 1813, 2203, 2580, 2657, 2691, 2740, 3277, 3296, 3324, 3328, 3338 

FailureSince | 1612, 1889, 2029, 2135, 2581, 3278, 3297, 3325, 3339, 3395, 3460, 3952 

FloorLabel | 1400, 1699, 1809, 2573, 3271 

FloorMaxLevel | 1932 

FloorMinLevel | 1931 

FloorRiseStuds | 1926 

FunctionalState | 86, 731, 1609, 1765, 1783, 1807, 1849, 2020, 2050, 2106, 2113, 2141, 2143, 2218, 2575, 2579, 2636, 2639, 2641, 2651, 2661, 2667, 2690, 2739, 2830, 3128, 3215, 3265, 3273, 3294, 3316, 3322, 3337, 3364, 3367, 3404, 3410, 3445, 3447, 3867, 3946 

GasPipe | 847, 1302, 1369 

Genome | 2158, 2244, 2376, 2427, 2436 

GermAbnormalCount | 2411 

GermDeadCount | 2414 

GermNormalCount | 2329, 2409 

GermSownCount | 2327, 2407 

GerminationDate | 1817, 2160, 3420 

GerminationOutcome | 2406, 2437, 2438 

GrowthCode | 1404, 1410, 1699, 1776, 1808, 2058, 2059, 2068, 2069, 2093, 2098, 2132, 2212, 2287, 3157, 3158, 3183, 3185, 3197, 3212, 3269, 3270, 3283, 3409, 3418 

GrowthStage | 506, 1795, 2131, 2241, 2242, 2345, 2425, 3193, 3218 

Health | 606, 631, 632, 4022 

HitLogicBound | 975, 976 

Holes | 922, 924 

HomeCFrame | 702, 3107, 3108, 4020 

HomeGrowthCode | 2232 

HormoneFocus | 2383, 2444 

HormoneTreatment | 2382, 2443, 2444 

Humidity | 1819, 3280, 3300, 3406 

ImpactToolKind | 979, 1092, 1118, 1247 

IncomingReservations | 1647, 1848, 1856, 1857, 2114, 2144, 2182, 2193, 2250, 3182, 3244, 3267, 3318, 3371, 3387 

InteractionsBound | 2569, 2571 

Kind | 1412, 1488, 1495, 2341, 2473, 2568, 3127, 3201, 3204, 3444, 3893, 3948, 3957 

KitBound | 3575, 3576 

KnockedOut | 649, 3021, 3124, 4023 

LabImpactTool | 1119 

LabItemType | 309, 440 

LabObjective | 540, 542, 546, 1775, 2034, 2045, 2065, 2083, 2087, 2184, 2200, 2205, 2430 

LabRole | 168, 3468 

LabSample | 310, 464, 2794 

LabSidearm | 1134, 1246 

LastActionDetail | 1711 

LastActionStatus | 1710 

LastHitBy | 633 

LastPointAmount | 191 

LastPointAward | 192 

LastRepairedAt | 2673, 3368, 3386, 3448 

LastRepairedBy | 2674 

Level | 80, 96, 1400, 1406, 1480, 1489, 1699, 1809, 1851, 2917, 3098, 3125, 3271 

LevelSlot | 4001 

MathQuizActive | 236, 247 

MaxHealth | 606, 607, 4022 

MessageSerial | 158, 159, 163 

Moisture | 2158, 2245, 2426, 2436 

MutagenesisDoseGy | 2365, 2440, 2441 

MutagenesisSurvivalPercent | 2366, 2398, 2441 

NPCName | 4158 

NavigationBlocked | 3015, 3018, 3029 

Occupied | 1627, 1754 

OperationStarted | 1613, 1818, 2583, 3302, 3341 

PathFallbacks | 2823, 3053 

PlantExpiredAt | 1629 

PlantId | 525, 1628, 1755, 2230, 2348, 2368, 2415, 2430, 2435, 3304 

PlantLife | 313, 407, 415, 507, 1623, 1658, 1766, 1773, 1784, 1786, 2133, 2150, 2171, 2176, 2177, 2231, 2412, 2728, 3274, 3303, 3304 

PlantSample | 481 

Powered | 2597 

QuizPlayerId | 237, 245, 3266, 3317, 3953, 3970 

QuizProtected | 2174 

RecentTransferThroughput | 3432 

RecoveryEndsAt | 1772, 1787 

RecoveryToken | 1770, 1771, 1782 

RepairInstruction | 732, 3276, 3295, 3326, 3340, 3869 

RepairKey | 2574, 3275, 3323 

RepairRouteReady | 1970, 1973 

ReservedByBot | 2052, 2288, 2292, 3130, 3181, 3189, 3245, 3268, 3388 

Role | 4158 

Room | 79, 95, 1406, 1412, 1480, 1489, 3170 

RoomIndex | 2875 

RoomKey | 4061 

RoundNumber | 4036 

SampleCount | 88, 1624, 1626, 1636, 1661, 1753, 1794, 1846, 1856, 1857, 2051, 2114, 2144, 2296, 2832, 3129, 3303, 3328, 3343, 3361, 3394 

SampleId | 536, 551, 963, 2456, 2458, 2509 

SampleIds | 1625, 1745, 1752 

SampleSlot | 1631, 1797, 1798 

Score | 61, 2825, 3225 

Seated | 3111 

SecretBound | 3684, 3685 

SecretDestX | 3695 

SecretDestY | 3696 

SecretDestZ | 3697 

ShootablePoster | 1309, 1382 

SourceGrowthCode | 2232 

StairEastLaneX | 1928 

StairNorthZ | 1929 

StairSouthZ | 1930 

StairWestLaneX | 1927 

StorageId | 1478, 1481 

StoredTransparency | 1799 

TalkBound | 4153, 4154 

TaskState | 650, 2811, 4025 

Temperature | 1819, 3279, 3299, 3405 

Tips | 4155 

ToolKind | 1195 

TransferSample | 453, 534, 956 

TransferStartedAt | 2175 

Treatments | 488, 494, 500, 501, 2157, 2243 

Ventilation | 1820, 3281, 3301, 3407 

WallSide | 1507, 1903, 2614, 2847 

WindowBroken | 1348, 1349 

## S12 LabRoles

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

30 | roleEquipmentId 

36 | roleFloor 

40 | roleTransferSeconds 

49 | roleEquipmentLabel 

55 | roleDestinations 

72 | clearRoleAssignment 

78 | assignRoleObjective 

130 | buildHud 

216 | refreshHud 

243 | wearablePart 

265 | applyAppearance 

309 | setupPlayer 

344 | stripAutoHealthRegen 

369 | bindKiosk 

401 | selectRole 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

AssignedRepairDistance | 96 

AssignedRepairId | 92 

AssignedRepairProjectedPoints | 97 

AssignedTransferDeadline | 122, 226, 360 

AssignedTransferDestination | 120 

AssignedTransferSource | 119 

Capacity | 61 

CarriedSample | 222, 312, 336 

FailedSampleBacklog | 44 

FailureSince | 88, 94 

FloorLabel | 37 

FunctionalState | 60, 83, 104 

GrowthCode | 31, 50, 111, 112, 117, 118 

IncomingReservations | 59 

Kind | 52 

LabObjective | 223, 313, 337, 416 

LabRole | 411 

LastPointAmount | 233 

LastPointAward | 234, 338 

Level | 33, 37, 64, 65 

ReservedByBot | 105 

Role | 279, 370 

RoleKioskBound | 372, 373 

Room | 33, 52 

SampleCount | 58, 67, 104 

## S13 LabRound

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

18 | computeRoundSeconds 

48 | pointsOf 

54 | resetScores 

62 | resolveRound 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

LastRoundScore | 69 

LastWinnerName | 71 

LastWinnerScore | 72 

PersonalBest | 67, 68, 93 

RoundEndsAt | 82, 87 

RoundLength | 46 

RoundNumber | 80 

RoundPhase | 81, 86 

RoundStreakBest | 58 

## S14 LabTechnicians

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

46 | bubbleOf 

71 | say 

81 | playSound 

93 | labelOf 

97 | nearestFault 

111 | setStatus 

118 | reviveLater 

134 | runTechnician 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Fatigue | 125, 154, 187 

FunctionalState | 100 

Gender | 139 

GrowthCode | 94 

Kind | 94 

KnockedOut | 128, 142 

NeedsHelp | 127, 159, 179 

Panic | 126, 158, 178 

## S15 LoungeSystems

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

28 | move 

53 | refreshPanel 

63 | playNext 

103 | refreshWall 

113 | onChat 

142 | hook 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Col | 160 

InLounge | 33, 46, 114, 135 

Row | 159 

## S16 ServerBlasterManager

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

30 | getRemote 

60 | findHumanoidFromHit 

72 | randomSpread 

82 | broadcastShot 

95 | researchHit 

102 | bridgeHit 

114 | genericDamage 

127 | validSequence 

136 | handleFire 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BlasterTracerColor | 163 

BlasterWeapon | 147 

LabSidearm | 147 

## S25 LabHUD

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

23 | box 

26 | label 

29 | button 

44 | toggle 

58 | showTrail 

80 | watchBot 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

CarriedSample | 126 

GWAPCarrier | 120 

GWAPDialogue | 125 

GWAPNotice | 126 

GWAPScenario | 120 

GWAPTarget | 123 

GWAPTargetFloor | 122 

Health | 124 

LabRole | 115 

RoundEndsAt | 117 

RouteIndex | 67 

State | 61 

## S26 LabQuizClient

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

51 | label 

84 | answer 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Answer | 103, 121 

## S27 LabSidearmClient

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

29 | refresh 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BotsKilled | 30, 40 

BotsTotal | 31, 41 

## S28 LoungeClient

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

49 | apply 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

InLounge | 66, 67, 74, 85 

## S21 LabSpatial

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

7 | S.frame 

12 | S.world 

13 | S.localPoint 

14 | S.vector 

15 | S.floor 

18 | S.setApproach 

26 | S.approach 

32 | S.sync 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Approach | 23, 29, 34, 35 

ApproachLocal | 19, 29


<<< source chapter: chapters/visuals.tex >>>
==============================================================================
CHAPTER: Historical visual references
==============================================================================

figures/reference-1.png
Original layout reference supplied by the owner. This is another shooter used as a panel-layout reference, not a screenshot of the audited laboratory.

figures/reference-2.png
Historical laboratory screenshot showing the rejected added weapon selector and competing overlays. Not the current audited state.

figures/reference-3.png
Historical hallway lineup of repeated NPCs, supplied as defect evidence. Later pooling and template changes address this presentation.

figures/reference-4.png
Historical NPC appearance and weapon-visual detail, supplied as defect evidence.

figures/reference-5.png
Historical small-screen view with competing mission, carrier, and role-selection information. Used to explain the grouping requirement.


<<< source chapter: chapters/bibliography.tex >>>
==============================================================================
CHAPTER: Bibliography and source access
==============================================================================

## Shared development chat

Improve SeedLab interactions; browser read on 13 September 2026. Historical reports and requirement chronology.

https://chatgpt.com/s/cx_6aa68aee04bc8191a98fa52b54b28109

## Roblox client/server boundary

Primary guidance for server validation of client-triggered actions. Consulted 13 September 2026.

https://create.roblox.com/docs/scripting/security/client-server-boundary

## Roblox Camera reference

Primary API reference for screen/camera rays and coordinate conventions. Consulted 13 September 2026.

https://create.roblox.com/docs/reference/engine/classes/Camera

## Roblox pathfinding

Primary guidance for paths and navigation behavior. Consulted 13 September 2026.

https://create.roblox.com/docs/characters/pathfinding

## Roblox UI position and size

Primary guidance for interface sizing and positioning. Consulted 13 September 2026.

https://create.roblox.com/docs/ui/position-and-size

## Roblox text filtering

Primary guidance for filtering player-authored text displayed on shared signs. Relevant to open risk R07. Consulted 13 September 2026.

https://create.roblox.com/docs/ui/text-filtering

## Local primary evidence

evidence/live-source-capture.json contains the exact source capture; source-manifest.json identifies each listing; live-world-inventory.json records scene measurements; export-manifest.json records file hashes; export-5.rbxl preserves the supplied latest place. template-extracted.txt and template-links.json preserve the template structure and attribution links. shared-chat-reading-notes.md records the browser reading scope. GWAP_REVISION_NOTES.md preserves prior reported test results. The attached GWAP ideas are copied when available.


<<< source chapter: chapters/full-code.tex >>>
Complete active Studio source

==============================================================================
CHAPTER: S01 - GWAPNPC
==============================================================================

src:S01
ReplicatedStorage.GWAPNPC

Authority group: active. 6183 UTF-8 bytes; 96 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.GWAPNPC.lua

==============================================================================
CHAPTER: S02 - GWAPRouting
==============================================================================

src:S02
ReplicatedStorage.GWAPRouting

Authority group: active. 3434 UTF-8 bytes; 55 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.GWAPRouting.lua

==============================================================================
CHAPTER: S03 - GWAPScenarios
==============================================================================

src:S03
ReplicatedStorage.GWAPScenarios

Authority group: active. 2692 UTF-8 bytes; 23 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.GWAPScenarios.lua

==============================================================================
CHAPTER: S04 - GWAPWorld
==============================================================================

src:S04
ReplicatedStorage.GWAPWorld

Authority group: active. 7198 UTF-8 bytes; 95 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.GWAPWorld.lua

==============================================================================
CHAPTER: S05 - LabKinds
==============================================================================

src:S05
ReplicatedStorage.LabKinds

Authority group: active. 10408 UTF-8 bytes; 173 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.LabKinds.lua

==============================================================================
CHAPTER: S06 - Blaster
==============================================================================

src:S06
ReplicatedStorage.Modules.Blaster

Authority group: active. 9143 UTF-8 bytes; 239 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.Modules.Blaster.lua

==============================================================================
CHAPTER: S07 - BlasterController
==============================================================================

src:S07
ReplicatedStorage.Modules.BlasterController

Authority group: active. 35949 UTF-8 bytes; 915 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.Modules.BlasterController.lua

==============================================================================
CHAPTER: S08 - GWAPServer
==============================================================================

src:S08
ServerScriptService.GWAPServer

Authority group: active. 32199 UTF-8 bytes; 469 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.GWAPServer.lua

==============================================================================
CHAPTER: S09 - GWAPWallDamage
==============================================================================

src:S09
ServerScriptService.GWAPWallDamage

Authority group: active. 3254 UTF-8 bytes; 55 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.GWAPWallDamage.lua

==============================================================================
CHAPTER: S10 - LabElevators
==============================================================================

src:S10
ServerScriptService.LabElevators

Authority group: active. 4405 UTF-8 bytes; 132 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LabElevators.lua

==============================================================================
CHAPTER: S11 - LabEquipment
==============================================================================

src:S11
ServerScriptService.LabEquipment

Authority group: active. 182838 UTF-8 bytes; 4178 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LabEquipment.lua

==============================================================================
CHAPTER: S12 - LabRoles
==============================================================================

src:S12
ServerScriptService.LabRoles

Authority group: active. 19385 UTF-8 bytes; 431 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LabRoles.lua

==============================================================================
CHAPTER: S13 - LabRound
==============================================================================

src:S13
ServerScriptService.LabRound

Authority group: active. 3591 UTF-8 bytes; 94 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LabRound.lua

==============================================================================
CHAPTER: S14 - LabTechnicians
==============================================================================

src:S14
ServerScriptService.LabTechnicians

Authority group: active. 7915 UTF-8 bytes; 210 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LabTechnicians.lua

==============================================================================
CHAPTER: S15 - LoungeSystems
==============================================================================

src:S15
ServerScriptService.LoungeSystems

Authority group: active. 5872 UTF-8 bytes; 172 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.LoungeSystems.lua

==============================================================================
CHAPTER: S16 - ServerBlasterManager
==============================================================================

src:S16
ServerScriptService.ServerBlasterManager

Authority group: active. 8483 UTF-8 bytes; 195 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ServerScriptService.ServerBlasterManager.lua

==============================================================================
CHAPTER: S25 - LabHUD
==============================================================================

src:S25
StarterPlayer.StarterPlayerScripts.LabHUD

Authority group: active. 12852 UTF-8 bytes; 140 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/StarterPlayer.StarterPlayerScripts.LabHUD.lua

==============================================================================
CHAPTER: S26 - LabQuizClient
==============================================================================

src:S26
StarterPlayer.StarterPlayerScripts.LabQuizClient

Authority group: active. 5319 UTF-8 bytes; 138 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/StarterPlayer.StarterPlayerScripts.LabQuizClient.lua

==============================================================================
CHAPTER: S27 - LabSidearmClient
==============================================================================

src:S27
StarterPlayer.StarterPlayerScripts.LabSidearmClient

Authority group: active. 2409 UTF-8 bytes; 54 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/StarterPlayer.StarterPlayerScripts.LabSidearmClient.lua

==============================================================================
CHAPTER: S28 - LoungeClient
==============================================================================

src:S28
StarterPlayer.StarterPlayerScripts.LoungeClient

Authority group: active. 3247 UTF-8 bytes; 85 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/StarterPlayer.StarterPlayerScripts.LoungeClient.lua

==============================================================================
CHAPTER: S21 - LabSpatial
==============================================================================

src:S21
ReplicatedStorage.LabSpatial

Authority group: active. 1994 UTF-8 bytes; 39 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/active/ReplicatedStorage.LabSpatial.lua

Complete archived Studio source

==============================================================================
CHAPTER: S17 - LabElevators
==============================================================================

src:S17
ServerStorage.BeforeBasementAndQuiz_20260912.LabElevators

Authority group: archive. 3761 UTF-8 bytes; 123 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabElevators.lua

==============================================================================
CHAPTER: S18 - LabEquipment
==============================================================================

src:S18
ServerStorage.BeforeBasementAndQuiz_20260912.LabEquipment

Authority group: archive. 175504 UTF-8 bytes; 4068 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabEquipment.lua

==============================================================================
CHAPTER: S19 - LabRoles
==============================================================================

src:S19
ServerStorage.BeforeBasementAndQuiz_20260912.LabRoles

Authority group: archive. 18757 UTF-8 bytes; 422 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabRoles.lua

==============================================================================
CHAPTER: S20 - LabRound
==============================================================================

src:S20
ServerStorage.BeforeBasementAndQuiz_20260912.LabRound

Authority group: archive. 2954 UTF-8 bytes; 85 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabRound.lua

==============================================================================
CHAPTER: S21 - LabTechnicians
==============================================================================

src:S21
ServerStorage.BeforeBasementAndQuiz_20260912.LabTechnicians

Authority group: archive. 7271 UTF-8 bytes; 201 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabTechnicians.lua

==============================================================================
CHAPTER: S22 - LoungeSystems
==============================================================================

src:S22
ServerStorage.BeforeBasementAndQuiz_20260912.LoungeSystems

Authority group: archive. 4605 UTF-8 bytes; 152 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LoungeSystems.lua

==============================================================================
CHAPTER: S23 - ServerBlasterManager
==============================================================================

src:S23
ServerStorage.BeforeBasementAndQuiz_20260912.ServerBlasterManager

Authority group: archive. 7275 UTF-8 bytes; 175 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.ServerBlasterManager.lua

==============================================================================
CHAPTER: S24 - BlasterController_BeforeMouseArmFix_20260912
==============================================================================

src:S24
ServerStorage.BlasterController_BeforeMouseArmFix_20260912

Authority group: archive. 26610 UTF-8 bytes; 730 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

HISTORICAL BACKUP. This container is in ServerStorage and is not an active runtime script. Do not install it as an update without a deliberate comparison.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/archive/ServerStorage.BlasterController_BeforeMouseArmFix_20260912.lua

Complete disabled Studio generator

==============================================================================
CHAPTER: S29 - SeedLabGenerator_DISABLED_doNotEnable
==============================================================================

src:S29
Workspace.SeedLabGenerator_DISABLED_doNotEnable

Authority group: disabled. 524207 UTF-8 bytes; 11886 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

DISABLED GENERATOR. Retained as evidence. Enabling or executing it can rebuild/replace the world. It differs from the loose generator.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/disabled/Workspace.SeedLabGenerator_DISABLED_doNotEnable.lua

Complete historical workspace source

==============================================================================
CHAPTER: W01 - SeedLabGenerator.lua
==============================================================================

src:W01
SeedLabGenerator.lua

Authority group: workspace. 552155 UTF-8 bytes; 12398 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/SeedLabGenerator.lua

==============================================================================
CHAPTER: W02 - InstallGWAP.lua
==============================================================================

src:W02
InstallGWAP.lua

Authority group: workspace. 115778 UTF-8 bytes; 2109 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/InstallGWAP.lua

==============================================================================
CHAPTER: W03 - GWAPWorld.lua
==============================================================================

src:W03
GWAPWorld.lua

Authority group: workspace. 17807 UTF-8 bytes; 259 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPWorld.lua

==============================================================================
CHAPTER: W04 - GWAPScenarios.lua
==============================================================================

src:W04
GWAPScenarios.lua

Authority group: workspace. 2067 UTF-8 bytes; 13 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPScenarios.lua

==============================================================================
CHAPTER: W05 - GWAPNPC.lua
==============================================================================

src:W05
GWAPNPC.lua

Authority group: workspace. 6021 UTF-8 bytes; 90 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPNPC.lua

==============================================================================
CHAPTER: W06 - GWAPRouting.lua
==============================================================================

src:W06
GWAPRouting.lua

Authority group: workspace. 2594 UTF-8 bytes; 43 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPRouting.lua

==============================================================================
CHAPTER: W07 - GWAPServer.lua
==============================================================================

src:W07
GWAPServer.lua

Authority group: workspace. 28562 UTF-8 bytes; 418 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPServer.lua

==============================================================================
CHAPTER: W08 - GWAPWallDamage.lua
==============================================================================

src:W08
GWAPWallDamage.lua

Authority group: workspace. 2594 UTF-8 bytes; 45 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPWallDamage.lua

==============================================================================
CHAPTER: W09 - GWAPHUD.lua
==============================================================================

src:W09
GWAPHUD.lua

Authority group: workspace. 11596 UTF-8 bytes; 123 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/GWAPHUD.lua

==============================================================================
CHAPTER: W10 - Blaster.lua
==============================================================================

src:W10
Blaster.lua

Authority group: workspace. 8432 UTF-8 bytes; 227 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/Blaster.lua

==============================================================================
CHAPTER: W11 - BlasterController.lua
==============================================================================

src:W11
BlasterController.lua

Authority group: workspace. 35188 UTF-8 bytes; 905 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/BlasterController.lua

==============================================================================
CHAPTER: W12 - ServerBlasterManager.lua
==============================================================================

src:W12
ServerBlasterManager.lua

Authority group: workspace. 7714 UTF-8 bytes; 184 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

WORKSPACE ARTIFACT. Presence on disk does not establish installation. Compare against active sources. In particular, GWAPWorld.lua contains older server code and is not the correct world module.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/workspace/ServerBlasterManager.lua

Complete server-only documentation source

==============================================================================
CHAPTER: DOC01 - GameDocumentation
==============================================================================

src:DOC01
ServerStorage.GameDocumentation

Authority group: documentation. 120178 UTF-8 bytes; 827 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/documentation/ServerStorage.GameDocumentation.lua

==============================================================================
CHAPTER: DOC02 - GameDocumentationAnnex2
==============================================================================

src:DOC02
ServerStorage.GameDocumentationAnnex2

Authority group: documentation. 107451 UTF-8 bytes; 2159 source lines. SHA-256 is in the provenance chapter and machine-readable manifest.

fontsize=89.6,breaklines=true,breakanywhere=true,numbers=left,numbersep=6pt,tabsize=4,breaksymbolleft=,breaksymbolright=
code/documentation/ServerStorage.GameDocumentationAnnex2.lua


]========]
return {revision=5,part=2,parts=2,reference="Server-only written reference; never required by gameplay"}
