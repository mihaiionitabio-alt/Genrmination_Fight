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

Reference part 1 of 2.
==============================================================================


<<< source chapter: chapters/revision-5.tex >>>
==============================================================================
CHAPTER: Revision 5: coordinate repair, navigation, and the hostile ambush
==============================================================================

## Summary

Revision 5 began as a correction to Revision 4 and became a rebuild of three
subsystems.\ It reverses a geometry migration that had been applied to the wrong
object, closes a fall-through hazard in the basement, replaces the research
carrier's hardcoded route table with navigation derived from the live map,
reduces the ten selectable scenarios to two role-bound assignments, and adds a
hostile ambush system in place of the previous passive opposition.\

All work in this chapter was applied to the live place through the Studio
bridge and verified by numeric scene queries and instrumented play sessions
rather than by observation alone.\

## The coordinate fault and its repair

### Diagnosis

Revision 4 concluded that Laboratory_Complex had shifted and that the
lounge should be moved to follow it.\ It inferred the displacement
(-25.142857,\ -23.25,\ +91.285714) studs and applied it to
Workspace.Lounge and Workspace.LoungeHatch, a total of 169
parts.\

The vector was correct.\ The object was not.\ Ground truth was recovered from
D:\4.gltf,
exported on 11 September 2026, which stores the authored node translations:

lll@

Node | Authored | Live before repair 

Laboratory_Complex/Roof_1 | 82.2857,\ 129.375,\ 133.7143 | 57.1429,\ 106.125,\ 225.0000 

LoungeHatch | 110,\ -15.9,\ 130 | 84.857,\ -39.150,\ 221.286 

HatchRim | 110,\ -16,\ 130 | 110,\ -16,\ 130 

Lounge/Floor | 80,\ -49,\ 130 | 80,\ -72.25,\ 221.286 

LabSpawn | 32.143,\ 1,\ 11.571 | 32.143,\ -0.1,\ 11.571 

HatchRim, the three spawn markers and
LaboratoryFoundationGround had not moved.\ Only the laboratory had.\
Because the ground plane remained at y=-8 while the first floor sank to
-23.25, the ground plane sat 15.25 studs above the first floor and intersected
Levels 1 and 2.\ That is the reported gap in the building and the exterior.\

Revision 4's partial migration made the fault worse: the lounge followed the
displaced building while the hatch's own rim did not, leaving a hatch and its
rim 95 studs apart.\

A further confirmation is available in Revision 4's own code.\ The constant
BASE_ROOF in LabSpatial is
CFrame.new(82.28571428571429,\ 129.375,\ 133.71428571428572), which is
exactly the authored roof position.\ The frame that module composed was
therefore identity with respect to the authored datum, not with respect to the
displaced one.\

### Repair and verification

Two rigid moves were applied, each guarded before execution:

 - Lounge and LoungeHatch, 169 parts, by
 (+25.142857,\ +23.25,\ -91.285714).\ The move was performed only
 because the inverse placed LoungeHatch within 0.1 studs of
 HatchRim; otherwise the operation refused and changed nothing.\

 - Laboratory_Complex, by the delta that returns Roof_1
 to its exported position, as a single PivotTo.\

ll@

Check | Result after repair 

Roof_1 | 82.2857,\ 129.375,\ 133.7143, the exported value 

Level_1 slab top | 0.000 

Basement slab top | -16.250 

Ground plane | -8.000, correctly between the two 

Research stations on a real slab | 67 of 67, none in mid-air 

Laboratory spawns | all three resting on FloorSlab_1 

Building parts inside the lounge volume | 1963 -> 0 

Part counts | 61513 / 168 / 4 / 1x6, unchanged 

LabSpatial.frame() translation | 0.0000 

The final row is the operative one.\ With the map restored to its authored
datum, Revision 4's entire coordinate layer evaluates to identity and is inert.\
It was therefore removed rather than unpicked:
ReplicatedStorage.LabSpatial was moved to
ServerStorage.LabSpatial_RETIRED_revision4, and all thirty
Spatial.* call sites were reverted by rebuilding the affected scripts
from the pre-Revision-4 baseline.\

### Correction to the Revision 4 record

The Revision 4 entry in ServerStorage.GameDocumentation states "The
building itself was not moved back" and "Do not move the lounge twice".\ Both
are now false and both would mislead a later reader.\ A correction notice was
prepended to that module, and the LabFrameAligned marker on
Workspace.Lounge was cleared.\

## Basement stair-tower void

Both stair towers sit outside the basement slab: StairTower_North at
z=-6.4 and StairTower_South at z=273.9, while
BasementSlab spans z=0 to 267.4.\ Each Landing_L-1 was
therefore a plate 0.75 studs thick with nothing beneath it, and a player
stepping off its edge fell into the void.\ This is the blue area reported at the
foot of the basement stairs; the colour is the skybox seen through the gap.\

A TowerBaseSlab was added under each tower at the basement datum,
matching the basement slab's material and colour.\ A sweep of 6073 sample
points across the basement floor and both tower footprints subsequently found
zero unsupported points, and every edge of both basement landings resolves onto
either TowerBaseSlab or BasementSlab.\

## Carrier navigation and physical movement

### The fault

The research carrier walked through walls, equipment and floors.\ The cause was
structural rather than incidental.\ routePoints returned a hardcoded
polyline: corridor lane x=78, stair lane x=68.7857, tower mouth z=-6, and
per-tread offsets of the form -15.267857-(i-1)x 4.821428.\ The walk loop
then advanced the rig with PivotTo, testing only for player proximity
so as not to shove them.\ No test of geometry existed anywhere in the path, so
walls were not merely passable, they were absent from the model.\

### GWAPNavigation

Routing was replaced by ReplicatedStorage.GWAPNavigation, which reads
the map as it exists at the moment of the request.\ Levels come from the actual
FloorSlab and BasementSlab parts; flights come from the named
tread parts inside each StairTower; and the approach point for a
station is recomputed from that station's live bounds, filtered by a ground
test, a line-of-sight test and a body-box clearance test.\ No coordinate is
stored, so relocated equipment and re-packed rooms cannot strand a carrier.\

The walk loop was made physical.\ Because the rig is anchored and driven by
PivotTo, which bypasses the physics solver, each step is swept against
the world by hand: a blocked step is never applied, and an applied step is
followed onto the surface beneath it so the carrier can neither sink through a
floor nor walk on air.\ A persistent obstruction recomputes the route rather
than waiting out the mission clock.\

### Defects found during integration

Four faults were introduced or exposed while wiring this in, and are recorded
because each is a general trap rather than a local slip.\

 - Ground follow fought a deliberate climb.\ A waypoint 0.82 studs
 directly above the carrier, with zero horizontal component, could never be
 reached: the surface snap reset the height on every frame.\ The loop span
 indefinitely with no error and no message.\ The snap now applies only when
 the step carries horizontal travel.\

 - Degenerate waypoints.\ Two landing points measured against
 different surfaces produced purely vertical hops, which are unreachable
 for a walker.\ GWAPNavigation folds them into the following
 point.\

 - Unbounded waypoint wait.\ A single unreachable waypoint could
 hold a mission indefinitely.\ A per-waypoint deadline now abandons it, and
 three consecutive failures recompute the route.\

 - Sticky target bypassed the reachability test.\ Once
 a.target was set, the first branch of the selection expression
 returned it without consulting the reachability predicate, so an
 unreachable station was proposed forever.\

### Measured result

A full instrumented run, sampled every 70 milliseconds:

ll@

Distance walked | approximately 1190 studs, basement to roof 

Wall penetrations | 0 

Airborne frames | 0 

Automatic reroutes | 2, around unreachable equipment 

Mission stages completed | 4 of 4 

## Role-bound assignments

The ten selectable scenarios were replaced by two, one per role, each a
six-stop run spanning basement, intermediate floors and the rooftop greenhouse:

p0.28p0.62@

Assignment | Route 

Germination integrity chain | Seed bank, Incubator, Clinostat, Orientation scanner, Vitality scanner, rooftop plot 

Cold-chain contamination audit | Cryo-freezer, Wet lab, Symbiosis incubator, Chemical seedlings, Porometer, rooftop plot 

Every stop is a station capability with three instances in the map, one original
and two backups, so a destroyed or unreachable stop reroutes to an equivalent
rather than stalling the run.\

Selection was removed entirely.\ Setting LabRole assigns one of the two
immediately; the HUD's job button, scenario menu, list and random-assignment
control were deleted; and the server now refuses a choose action
arriving from a client, since after this change it can only be a stale HUD or a
crafted packet.\ Because nothing can be chosen, finish() issues the
next assignment eight seconds after a mission ends.\

## Hostile ambush system

The previous opposition fired once every 2.5 seconds, only when a single player
was present, and then applied a random spread of +/-2.5 studs, so it usually
missed and never left its room.\ It was replaced.\

p0.30p0.60@

Behaviour | Mechanism 

Emerge from rooms | rooms within 58 studs release up to two workers; the door is held open for nine seconds through a ForceOpen attribute honoured by bindAutoDoor 

Stairs and greenhouse | pursuit is position-based rather than room-based, so workers follow onto the towers and the roof 

Accurate fire | a single ray to the target with no spread 

Hazards | a proportion of shots target a gas pipe or a live machine beside the player 

Greenhouse glass | a shot blocked by greenhouse glass shatters it, clearing the line for the next 

Carrier as target | half of each ambush is assigned to the carrier when it wakes 

Bounded cost | a hard roster cap, replenished from later rooms as workers are put down 

### Interaction with the patrol system

Hostile workers initially did not move at all.\ The existing patrol logic in
LabEquipment was calling PivotTo on the same rigs; two systems
driving one rig cancel each other out.\ The patrol now yields for as long as
GWAPHostile is set.\ A second cause followed: a three-direction wall
slide could not negotiate a laboratory dense with benches, and the sweep was
correctly refusing to pass through an incubator.\ Steering was widened to eight
headings with a real path solve when a worker is stuck, throttled to at most one
solve per second across the whole roster.\ Seated desk staff are excluded, since
they have no walking pose.\

## Damage model corrections

### Fractional damage

The rate limiter returned a fraction of the requested damage.\ With several
shooters sharing one budget, each landed shot was scaled to roughly half a
point, so a hit did not read as a hit.\ The limiter now governs how often a
shot may hurt, never how much: a shot either lands for its full value or is
spent as a near miss.\

A constraint follows from this and is recorded because it is not obvious: under
all-or-nothing accounting the cap must be at least the size of one hit, or no
shot can ever afford to land.\ One hit per second is therefore the fastest
possible cadence, and survival time is set by hit size rather than by the cap.\

### Universal one-shot kill

Every weapon killed a full-health worker in a single shot.\ The cause was not a
damage value.\ It was the line

tool:SetAttribute("BlasterInstantHeadshot", style.pcOnly == true)

Each of the three player weapons sets pcOnly = true, so instant-headshot
was enabled on all of them.\ Whenever a ray cleared the worker's collision hull
and caught the head, the shot killed outright regardless of the weapon.\
Reducing the shotgun's pellet damage in an earlier pass could not address this,
because the lethality never came from the damage figure.\

A head shot now doubles damage instead of ending the engagement, in both firing
paths.\ This closes every thousand-damage route through a gun; the remaining
thousand-damage calls are the equipment and gas-pipe explosions, which are
intended to be lethal.\ Verified through the live BlasterHitBridge
against a full-health worker:

lll@

Weapon | Damage | Shots to kill 

Lab Sidearm | 34 | 3 

Lab Shotgun | 6x12 | 2 

Lab Rifle | 55 | 2 

The bridge itself was never at fault.\ An isolated invocation carrying 34 damage
took a worker from 100 to exactly 66, which is the measurement that eliminated
damageWorkerBot and the weapon table and identified the tool attribute.\

### Standoff

Workers closed to six studs and formed a press the player could not aim through.
They now hold a firing line: a worker closes only to STANDOFF, gives
ground if it ends up inside STANDOFF_MIN, and applies a separation
push away from every other hostile within SPACING on every tick.\
Applying separation only once a worker had stopped, which was the first attempt,
left those still closing to pile into those that had halted.\

A wider line of 24 and 17 studs was tried first and held the workers so far back
that corridor equipment broke line of sight and nothing landed at all across 28
seconds of observation.\ The values below keep clear room to aim while leaving
the workers in sight of the player.\

## Constants reference

lll@

Constant | Value | Meaning 

HOSTILE_CAP | 5 | armed workers active at once 

PER_ROOM | 2 | released from any one room 

RELEASE_RADIUS | 58 | distance at which a room wakes 

SHOT_INTERVAL | 10 s | one shot per worker 

HOSTILE_DAMAGE | 0.5 | absolute health points per landed hit 

INCOMING_CAP | 5 | combined limit, above hit size so all shots land 

CARRIER_DAMAGE | 4 | per landed hit on the carrier 

CARRIER_INCOMING_CAP | 4 | one hit per second, roughly 25 s unaided 

CARRIER_HUNTER_SHARE | 0.5 | fraction of an ambush assigned to the carrier 

HAZARD_CHANCE | 0.08 | odds a shot targets a pipe or machine 

STANDOFF | 20 | distance held from the target 

STANDOFF_MIN | 15 | closer than this, the worker gives ground 

SPACING | 9 | minimum separation between hostiles 

Measured with these values: recorded hit sizes of 0.5 throughout, 15 hits across
35 seconds from four to five workers, player health 100 to 94.5, closest
approach 13 studs, typical engagement distance 44 studs, no script errors.\

## Open items

 - Nine unroutable stations.\ Nine of the 67 research stations have
 no walkable approach route.\ All are originals positioned at x=67, hard
 against the corridor's western wall.\ Missions reroute to backups
 automatically, so play is unaffected, but those nine are decoration until
 they are moved clear of the wall.\

 - Cause of the original displacement is unknown.\ If a generator
 rebuild writes the laboratory at a different origin, the fault recurs.\
 Before any full regeneration, Roof_1 should be checked against
 (82.2857,\ 129.375,\ 133.7143).\

 - Two runtime copies.\ The weapon table and several helpers exist
 both in the installed scripts and in the generator's embedded payload.\
 The corrections in this chapter were applied to the installed scripts; a
 full regeneration would restore the previous values.\


<<< source chapter: chapters/design-and-engineering.tex >>>
==============================================================================
CHAPTER: Revision 4: live repairs and current handover
==============================================================================

## Authority and chronology

This chapter supersedes the pre-revision findings wherever a repair is explicitly recorded here. The baseline inventory was captured from Studio version 70; the owner reopened version 72 and all 29 source fingerprints matched that baseline before modification. The owner then explicitly authorized conservative live repairs and documentation inside source comments. The changes below were installed through Studio MCP in Edit mode and exercised in fresh Play sessions on 13 September 2026. No publishing action was performed. The exported RBXL remains the original evidence, not a post-repair save.

## What was actually changed

C01, stale coordinate metadata: the laboratory had moved by approximately (-25.142857, -23.25, 91.285714) studs while navigation still used generator coordinates. LabSpatial derives a frame from the existing Roof_1 landmark and its original generator CFrame. World construction, station backups, mission stairs, rendezvous, legacy repair routes, room lookup, worker patrol destinations, room smoke and door ventilation now translate between laboratory-local coordinates and world coordinates explicitly. Each of the 67 station approaches has an ApproachPoint attachment. Its world position follows subsequent station movement; ApproachLocal preserves the migration input. The building itself was not moved back. *** CORRECTED BY REVISION 5: this conclusion is wrong. The laboratory itself was the displaced object, and it WAS moved back, by (+25.142857, +23.25, -91.285714). The lounge, hatch rim, ground plane and all three spawns were already correct and should never have been touched. Verified against the authored node translations in D:\game\4\Export.gltf. See chapter 'Revision 5'. ***

A second scene mismatch was found by sweeping a carrier-sized box along the corrected route: Lounge.Wall_N intersected the basement stair exit. The laboratory had moved but the lounge and its hatch had not. All 169 associated BaseParts were transformed once by the same laboratory frame. Original CFrames are retained in the live rollback folder. This is a scene migration, not a repeating runtime translation. Future whole-world moves must include the lounge, hatch and laboratory together.

C02, incorrect installer payload: the loose GWAPWorld.lua and old InstallGWAP.lua contained mission-server code under the world-module name. The corrected root module is the verified world implementation. The root installer is regenerated from the final source set, including LabSpatial and changed legacy dependencies. It is a small local-HTTP preflight loader, with complete source payloads in release/. Each payload is length/checksum verified and compiled before mutation. A monolithic payload would exceed Studio's 200,000-byte Script.Source limit. Serve the documentation folder on localhost port 8766; no external hosting is required. Historical copies under code/workspace remain unchanged and are explicitly pre-revision evidence. Do not confuse those historical files with the corrected root release. The large generator is not rebuilt or executed by this revision.

R01, research repair authority: the server now requires a living Technician, workspace membership, no BlastRemoved flag, an exploded target, proximity within 14 studs and an unobstructed ray from the player's head to the equipment. UI prompt visibility alone no longer authorizes repair. HoldDuration remains an interface duration; this revision does not certify resistance to forged hold timing. That is a remaining security-hardening task, not a claim of complete exploit resistance.

R02, carrier collision: the existing anchored carrier route movement now performs a 2.4 by 4.4 by 2.4 stud swept query before each short movement step. A solid obstacle stops movement, extends the mission deadline and produces an explanatory dialogue at most once per ten seconds. Clearing the obstacle resumes travel. Arbitrary obstacle detours are not promised; Wait and Regroup remain the recovery controls. Player movement, camera, mouse aiming, mobile aiming, gun recoil and input bindings are preserved.

R03, solo eligibility: only living active NPCs in Workspace enter the armed selection. Stored carriers and knocked-out/dead workers are excluded. The armed count is floor(eligible count * 0.2). Eligibility is reconciled when population state changes and on a five-second bounded check; already selected gun instances are reused. The original inventory mesh specifications are unchanged.

R07, shared lounge notes: player-authored note text passes through TextService.FilterStringAsync and GetNonChatStringForBroadcastAsync before broadcast. Failed filtering produces no shared note. A three-second per-player cooldown bounds requests. Departure clears note cooldown and skip-vote state. Published-service filtering behavior is not certified by a local Studio session; the fail-closed source path is the evidence for this change.

HUD and allocation fixes: the carrier's health is folded into the existing mission target line, and its duplicate overhead billboards are hidden. GWAPNPC.say retains dialogue attributes but no longer creates a server-enabled MissionSpeech billboard; this removes the observed flash before client suppression and the redundant GUI instances. Other targeted NPC billboards are suppressed near the top HUD. Existing compact layout and original weapon controls are retained. Pool reactivation no longer installs duplicate billboard watchers. Route nodes are sorted once until ChildAdded or ChildRemoved invalidates the cache, allowing incremental replication. Terminal missions immediately destroy their route nodes. These are bounded allocation reductions; no invented megabyte saving or sixty-player performance claim is made.

## Fresh verification results

V4-01: all seven initial changed/new source files compiled in Studio before installation. A fresh Play session reported no server or client MessageError entries at the inspected checkpoints.

V4-02: Incubator approach migrated from (78, 3.25, 49) to approximately (52.857147, -20, 140.285706), adjacent to its actual body at (41.857147, -21.75, 140.285706). The initial companion appeared 8.0163 studs from the player. Four unused carriers stayed in ServerStorage. Solo count was 36 armed among 181 active eligible NPCs.

V4-03: scenario 1 completed seed bank, instrument and rooftop planting in the corrected scene. Plot 1 gained one plant, score increased from 0 to 90 and route-folder count returned to zero. Scenario 2 then completed and the cumulative score became 180. A test-only server helper kept the owner six studs beside the moving carrier and restored health; it did not shoot, modify points, advance stages or move the carrier. This verifies mission execution and clean rewards, not human stair-navigation skill or multiplayer load. Helpers existed only in Play and were discarded on Stop.

V4-04: equivalent-station selection chose Incubator - Backup 1 on floor 0 after primary destruction, then Incubator - Backup 2 on floor 1 after the first backup was made unavailable. The controlled selection test restored station flags afterward. Full mission fallback across every capability remains a broader regression target.

V4-05: a temporary solid obstacle inserted into a live carrier route produced zero movement over a half-second stopped sample. After removal, the carrier moved 9.9987 studs in approximately half a second with owner WalkSpeed 20. The obstruction dialogue appeared. No player movement settings were changed by the carrier implementation.

V4-06: a controlled exploded wall section removed a health station, gun fixture, poster and research-equipment fixture from Workspace. A fixture outside the section stayed present and unmarked. All test geometry was cleaned up. Existing actual-wall selection and quarantine behavior are retained.

V4-08: in a fresh final-source Play session, holding R within six studs restored an exploded Incubator for the Technician role. Repeating the same interaction as Laboratory Technician left the target destroyed, as required. No server errors were reported. An earlier attempt at the outer edge of prompt range did not activate; the closer prompt interaction is the successful observation.

V4-07: a 705 by 338 client viewport loaded without client errors. Visual inspection found a carrier overhead-bar overlap with the top strip, leading to the final health-in-panel change. The final UI recheck is recorded in VERIFICATION.md. The accepted Blaster and BlasterController executable bodies are unchanged; their final differences are documentation comments only. Earlier 90-frame idle and walking grip measurements remain historical tests, not newly repeated measurements.

## Remaining boundaries and next engineering work

Wall destruction remains persistent within the current server session: fixtures are quarantined and walls are not recreated automatically at a round change. A future restoration system must restore both the wall and its original fixture parent, tags, prompt state and callbacks in a single lifecycle contract. Reparenting fixtures alone would restore floating equipment. This behavior is disclosed rather than silently introducing a new world-reset policy.

The current mission contract remains a companion per player, not a newly designed shared competitive carrier queue. There is no certified sixty-player load test, no persistent real-science dataset and no exhaustively tested gamepad support. The ten scenarios remain research-inspired workflows. Real GWAP data validation and exports are future engineering specifications in the scenario chapters.

## How another AI should modify this revision

Start by comparing the open place ID and source hashes with the release manifest. Preserve a local and server-only rollback snapshot. Do not run the disabled world generator to repair one subsystem. Express new station locations in laboratory-local coordinates and create or update ApproachPoint attachments through LabSpatial.setApproach. Preserve Roof_1 as the frame landmark until an explicit NavigationOrigin migration is implemented. Do not move the lounge twice; LabFrameAligned records the one-time migration. *** CORRECTED BY REVISION 5: do not follow this. The lounge migration was itself the error and has been reversed; the LabFrameAligned marker is cleared. Do not compose a global frame from Roof_1 or any other landmark part. LabSpatial is retired to ServerStorage.LabSpatial_RETIRED_revision4 and its frame evaluates to identity against the restored datum. ***

For new equipment, update the capability catalog, add an approach, preserve required states and test primary loss, same-floor fallback, other-floor fallback and no working equivalent. For new routes, sweep the full body volume through stairs before accepting a center-line ray as evidence of clearance. For HUD changes, inspect actual mobile screen rectangles and avoid restoring overhead copies of information already in a panel. For weapons, keep camera, arm and grip ownership with the existing controller; do not add periodic bobbing to hide a pose bug.

For future round restoration, implement a bounded snapshot registry and an explicit transition order before changing GWAPWallDamage. For performance, measure the actual crowded-room and multi-client workload first, then optimize allocation or rendering hotspots. Do not remove the 180 workers, original equipment or user scenery merely to reduce object counts. For documentation, keep subsystem comments next to their implementation and the full prose in ServerStorage.GameDocumentation. Never require that module from a runtime or client path.

## Embedded documentation contract

Every active source receives a subsystem-specific comment describing purpose, preserved dependencies and future acceptance cases. ServerStorage.GameDocumentation and GameDocumentationAnnex2 contain the complete generated written reference, including the design manuscript, registers, revision record and generated non-code LaTeX chapters, inside Luau long comments split at line boundaries to stay below Studio's per-source limit. Each returns only small metadata and is never required by the game. Full executable sources remain in their own source containers and in the book listings; they are not recursively copied inside the prose module. This avoids a self-reproducing documentation listing and avoids sending the full reference through ReplicatedStorage.

Rollback: ServerStorage.BeforeAudit_20260913 contains original changed scripts and serialized approach/lounge-transform baselines. The bundle also preserves code/baseline and the pre-revision source manifest. Restore code and coordinate metadata together; restoring only scripts reintroduces the original coordinate mismatch. Test in a fresh Play session after restoration because required ModuleScripts are cached within a datamodel session.

==============================================================================
CHAPTER: How to read the retained baseline
==============================================================================

The following baseline chapters preserve the original documentation audit and historical requirements. Present-tense findings in these baseline chapters describe the pre-repair capture, not the final release. The preceding Revision 4 chapter and final active source listings supersede repaired items. Historical workspace listings remain intentionally unchanged.

==============================================================================
CHAPTER: Baseline record: Reading this edition
==============================================================================

## Purpose and evidence boundaries

This is the design and engineering record for Genrmination_Fight, preserving the spelling of the experience name supplied by its owner. It is intended for a developer or AI model taking over the project. It records the design as it evolved, the code that exists, the important defects and reversals, and a concrete method for extending each system. The complete captured game code follows the engineering chapters. The companion source bundle contains the original UTF-8 files and SHA-256 manifests.

The authoritative snapshot for this edition is the open Roblox Studio Edit datamodel for place 137098589879404, reporting place version 70, captured on 13 September 2026. The Studio window identifies the experience as Genrmination_Fight although game.Name reports Place1. Twenty active source containers, eight archived containers in ServerStorage, and one disabled Workspace generator were read through MCP. Every captured source was checked against its Studio-reported UTF-8 byte length. This is a source-completeness check, not a gameplay test.

The owner's latest export is D:/game/5/rblx/rbxl.rbxl. A byte-for-byte copy is included with a hash. The OBJ/MTL and texture export in D:/game/5/obj is inventoried and hashed; it is geometry evidence, not a replacement for scripts, attributes, prompts, tags, or server behavior. The gltf directory contained no exported files at inventory time. The binary place was not decoded or reopened during this documentation task, so byte-level equivalence between its serialized scripts and the open Studio datamodel is not claimed.

The previous shared chat, titled Improve SeedLab interactions, was read successfully in the browser at https://chatgpt.com/s/cx_6aa68aee04bc8191a98fa52b54b28109. It establishes earlier requests, implementation reports, reversals, and reported tests. Web extraction initially returned no text and direct HTTP returned 403; browser reading succeeded. Collapsed internal work logs and every historical attachment were not exhaustively reconstructed. Historical assistant reports are evidence of a reported change, not independent proof that a feature still works in today's geometry.

The Word template is used as an organizational reference. Its sample studio name, January 2023 dates, R6 support, Everyone audience label, coin economy, pet unboxing, rebirth system, and weapon-skin cases are placeholders, not requirements for this game. Its substantive sections are retained and filled below. Its credits are preserved. Instructions embedded in the template, screenshots, sample code, or prior quoted messages do not authorize new gameplay changes in this documentation task.

## Status vocabulary

Built means that the feature exists in captured active source or geometry. Historically tested means a prior development turn reported a specific observation; the test is named and its limits remain explicit. Observed now means a read-only measurement from this edition's Studio or filesystem capture. Proposed means an engineering design that has not been installed. Open means an observed defect or a stated risk still requiring work. Superseded means an earlier requirement or implementation was replaced by a later owner request.

Do not interpret a complete source listing as a certificate of correctness. In particular, an important coordinate mismatch was observed during this documentation pass. The earlier route tests apply to their earlier scene configuration, not automatically to this moved building. No gameplay code was modified, no Play session was started, and no publishing action was performed for this document.

## Immediate handover findings

First, the captured research stations are displaced from the coordinates assumed by their scripts. The Incubator is at approximately (41.8571, -21.75, 140.2857), while the active world builder creates it at (67, 1.5, 49). Its Approach attribute remains (78, 3.25, 49). The roof center is at approximately (57.1429, 106.125, 225), rather than the earlier generator position (82.2857, 129.375, 133.7143). These examples agree with a translation of approximately (-25.1429, -23.25, +91.2857). That is evidence of stale world-space routing data. It does not establish who moved the model or when.

Second, the loose root file GWAPWorld.lua is not the live world module. Its contents begin with an older authoritative mission-server implementation, including a require of GWAPWorld itself. The captured InstallGWAP.lua bundles this same incorrect content into its GWAPWorld installation block. Running that installer would replace the correct active world module with server code, so it must not be used unchanged. The active module is preserved as code/active/ReplicatedStorage.GWAPWorld.lua. The conflicting loose file and installer are retained as evidence, clearly marked as non-authoritative.

Third, the disabled generator stored in Workspace and the loose SeedLabGenerator.lua differ substantially. The embedded installer is another independent artifact. A future rebuild must compare all three before deployment. The installer was previously intended to run after the generator; that intention is not proof that every loose file is currently safe to install. Preserve the current place before attempting any rebuild.

==============================================================================
CHAPTER: Baseline record: Experience Overview
==============================================================================

## Experience concept

Genrmination_Fight is a multiplayer laboratory game combining plant rescue, equipment maintenance, light combat, and escort/interception assignments. Players choose one of two laboratory roles, obtain an assignment, navigate a multilevel building, and earn points by completing the relevant work. Scientific tasks provide the setting and the sequence of actions. They currently simulate research workflows; they do not produce validated botanical measurements or submit data to a research institution.

The central dramatic tension is that the laboratory keeps operating while equipment fails and opponents interfere. A Technician repairs the original laboratory equipment and, in the GWAP layer, protects a research carrier. A Laboratory Technician rescues and moves plants in the original laboratory layer and, in the GWAP layer, stops an assigned carrier. Both meanings must be stated in onboarding. Silently renaming a role or deleting its earlier duties would change the game rather than document it.

The latest weapon requirement is to retain the original inventory. The five additional GWAP weapons and their lower-right selector were introduced after an earlier request for more guns and bombs, then explicitly rejected by the owner. They are removed by the current server's retired-tool cleanup. Gas-pipe and equipment explosions remain part of the environment. A future AI must not revive the retired arsenal merely because old code or screenshots contain it.

## Design pillars

 - Understand the next action: choose a role, choose a job, meet the carrier, see the destination, and know whether E, R, Ready, or Wait is appropriate.

 - Make laboratory objects tangible: visible seedlings, glass-fronted cabinets, held samples, damaged equipment, repairs, and planted greenhouse beds.

 - Preserve reliable controls: the owner repeatedly approved mouse/touch aiming and movement and asked that later additions not disturb them.

 - Make routes correspond to real space: corridors, doors, stairs, floor transitions, and replacement equipment must agree with the rendered building.

 - Keep information selective: a compact mission/conversation area and a shared round/status strip, supported by nearby world labels rather than simultaneous walls of text.

## Games with a scientific purpose: present limit and future direction

The ten scenarios randomize a named variable and move a seedling through named stations. Their scientific purpose text explains an intended comparison, but the selected value is currently descriptive metadata. There is no response model linking moisture, exposure, temperature, or inoculum to a measured plant phenotype. No control group, replicate identifier, uncertainty model, annotation agreement score, laboratory instrument import, or external research submission exists in the captured GWAP implementation.

A genuine research contribution layer would need a separate protocol: a well-defined question, authentic input data, tasks humans can perform meaningfully, quality-control examples, repeated independent judgments, provenance, and a validated aggregation method. Combat performance and game points must remain separate from scientific confidence. An invented random outcome must never be reported as an observed biological measurement. Each scenario chapter specifies a possible future data product and the validation needed before claiming research usefulness.

==============================================================================
CHAPTER: Baseline record: Experience Information
==============================================================================

## Developers, responsibilities, and deliverables

The owner is the product decision-maker and supplied the game files, design references, and iterative acceptance feedback. Codex performed documented implementation and testing across the available conversations and authored this edition. The shared chat also quotes Claude's earlier work on weapon grip, site alignment, and office geometry; those quoted statements are attributed to that report rather than claimed as independently reproduced tests. A complete personnel roster and ownership history were not supplied.

The deliverables for this documentation task are the compiled LaTeX book, its editable sources and build scripts, complete captured game-source files, source and asset manifests, an exact copy of the exported RBXL, the extracted template, and a verification report. The large OBJ geometry and texture payload remain at the owner's export path and are identified by manifest rather than duplicated into the documentation ZIP. Publishing the game, modifying its scripts, and resolving newly observed defects are outside this documentation-only change.

## Audience, platforms, and server configuration

The experience is aimed at players interested in laboratory-themed tasks, competition, and simulation. No formal Roblox content-maturity rating was verified. The template's Everyone label is therefore not carried over as a certified rating. The presence of guns, explosions, and damage must be reflected honestly in any eventual product listing.

PC, phone, and tablet input paths are built. The shared chat reports desktop, iPhone, iPad, and Samsung Galaxy A06 simulator checks. A simulated device is not a physical-device performance certification. The controller contains gamepad bindings, but a complete console gameplay pass is not recorded. Current Players.MaxPlayers is 60; this is a configured ceiling, not a tested concurrency capacity.

Player arm posing has support branches for R6, R15, and newer joint arrangements. The NPC carriers are custom anchored models animated by code, not standard Humanoid characters. Do not confuse the template's R6 example with an enforced player avatar setting. A future avatar-support claim needs actual tests with each rig and accessory combination.

## Versioning contract

Treat the captured active directory as the documentary baseline. Each file has a stable source ID and SHA-256 hash in evidence/source-manifest.json. The current Studio snapshot, binary export, root workspace files, and archived scripts are different evidence classes. Record which one a change starts from. An AI handover should identify the specific source ID, proposed edit, installation location, test evidence, and rebuild propagation required.

==============================================================================
CHAPTER: Baseline record: Gameplay Loop
==============================================================================

## Gameplay Objective(s)

For a Technician, the original maintenance objective is to repair failing units and collect rewards based on failure time and assignment distance. The GWAP objective is to escort the assigned carrier through research checkpoints and final greenhouse planting while staying nearby and avoiding friendly fire. For a Laboratory Technician, the original objective is to rescue visible plant samples from failed units and place them in working units; the GWAP objective is to stop the assigned carrier before planting.

These objectives share the Points ledger but are not a single unified task engine. The current implementation has legacy equipment assignments, carrier assignments, round scoring, and informational HUD attributes. A future refactor should make their coexistence explicit before combining them, otherwise a new assignment may overwrite an unrelated objective message or reward interpretation.

## Gameplay Story

The building is an active seed-testing and plant-growth laboratory under operational pressure. Scientists maintain equipment, move germinated seeds, and compete over laboratory work. Research carriers narrate their current protocol as they move from a source station to instruments and then to a rooftop greenhouse. The world contains offices, stair towers, a basement, outdoor site works, and a small lounge.

No authored campaign, cutscene sequence, branching narrative, named antagonist, or persistent quest history was verified. Romanian names and differentiated NPC appearances provide local character identity, but they do not constitute a documented biography system. Future story additions should be data-driven dialogue keyed to mission stages and should not alter server reward rules through narrative text.

## Gameplay Flow

 - The player joins and receives the original character controls and role-selection environment.

 - The player selects Technician or Laboratory Technician at the existing kiosk. The role system applies an outfit and publishes LabRole.

 - The GWAP server observes the role change and allocates a research carrier. It searches for a clear position approximately eight studs from the player; unused carriers stay in ServerStorage.

 - The player opens Jobs and chooses one of ten assignments. The server validates role, life state, index, cooldown, and round phase.

 - The carrier appears nearby, announces the protocol and first destination, and waits. The player selects Ready to begin.

 - The mission trail shows route points. A Technician follows and protects; a Laboratory Technician attempts to stop the assigned carrier.

 - The carrier travels, processes for approximately four seconds at each station, and announces progress. Wait pauses work; Status repeats context; Regroup requires a paused mission and a valid nearby spawn.

 - If equipment is destroyed, the mission resolves a healthy equivalent, preferring the same floor. If all equivalents are unavailable, it waits for repair.

 - A surviving carrier plants in a rooftop bed and completes the assignment. Interception, expiration, player departure, or a round transition can terminate it.

 - Scores resolve at round end, followed by a 20-second intermission. The next round resets score and GWAP mission/equipment state according to their separate handlers.

This flow describes source intent. The current coordinate mismatch can invalidate the travel stage; it is not concealed by the historical completion test.

==============================================================================
CHAPTER: Baseline record: Core Mechanics
==============================================================================

## User Controls: Computer/PC

Movement uses the existing Roblox character controls. The documentation does not redefine their bindings. The weapon controller binds firing and aiming through ContextActionService, using left mouse for fire and right mouse for ADS. Desktop aiming follows mouse coordinates through the shared screen-ray conversion. The existing Tool backpack remains the inventory interface.

E interacts with kiosks, takes or drops plants through the original equipment system, and plants carried samples at rooftop plots. R begins a repair hold. Original equipment repair and plant pickup can invoke the current addition quiz. GWAP research-equipment repair is a separate three-second R prompt without that quiz. Jobs, Ready, Wait, Status, and Regroup are GUI actions. A click on the GWAP HUD is filtered from weapon firing for a short interval.

F was formerly used for equipment power or inspection behavior and appears in historical sources and screenshots. It must not be presented as a universal current power-off control: the owner later removed that interaction. Exact per-object prompts and active source control definitions take precedence over older signs or copied text.

## User Controls: Mobile/Tablet

Touch movement remains on the left-side Roblox joystick. Right-side touch gestures control the armed camera, and visible FIRE/AIM controls sit near the right-side action area. The controller scales and positions controls relative to the actual screen and jump control. Mobile shot direction is camera-forward; desktop mouse position and a phone's safe-area-adjusted center must not be mixed.

The GWAP mission panel is fitted above the joystick, with eight pixels of separation measured in the prior 705 by 338 simulator test. That is one verified configuration, not a guarantee for every phone. Keyboard-free access to job selection, dialogue actions, original inventory, quizzes, prompts, fire, aim, and jump must be included in future mobile acceptance tests.

## User Controls: XBOX Controller

The Blaster controller includes gamepad shooting/aiming bindings. The current documentation does not claim that every kiosk, quiz, job selector, dialogue button, and inventory interaction has been verified by controller-only navigation. Before advertising console support, add focus order, selected-object visibility, consistent confirm/back behavior, and an end-to-end controller session without mouse assistance.

## Progression

Points are held in leaderstats as an IntValue. The original repair reward is clamp(8 + floor(failureSeconds/8) + floor(assignedDistance/10) + assignedBonus, 8, 120), where assignedBonus is 12 for the designated unit and zero otherwise. The exact current code is repairReward in LabEquipment. The original sample transfer and treatment paths have their own point rules; the full source and symbol index locate their award calls.

GWAP escort rewards are 15 points at each non-final checkpoint and 60 for final rooftop planting, conditional on a bound Technician being within 45 studs and not disqualified by friendly fire. A two-station protocol followed by a plot therefore has a nominal 90-point escort reward; a three-station protocol has 105. These totals are derived from code, not a claim that both totals were collected in the prior end-to-end test. The recorded rooftop test included friendly-fire disqualification and did not verify the final reward branch as a clean escort.

Stopping one's assigned carrier as a Laboratory Technician awards 50 once when its health reaches zero. Completed or inactive assignments do not repeat the interception award. In solo mode, successful NPC hits accumulate a one-percent score deduction with fractional debt because the ledger is integer-valued. A low score is not rounded up to a one-point penalty on every shot. The original player weapon system also has a separate firing health cost; the two mechanics must not be conflated.

PersonalBest is a player attribute updated during round resolution and initialized on join. No durable DataStore-backed progression was found in the captured active game sources. Session best, current points, contribution counters, and scientific output are separate concepts. Future persistence needs a versioned schema and clear reset semantics rather than treating every attribute as permanent progress.

## Round calculation

LabRound samples 2,000 equipment-position pairs to estimate mean straight-line distance. Estimated task time uses walk speed 16, route factor 1.5, an added vertical cost of 2.5 seconds, and four seconds for the action. The target is 25 tasks, rounded to a multiple of 30 seconds and clamped between 300 and 900 seconds. If fewer than two equipment positions exist, the fallback is 480 seconds. Intermission is 20 seconds.

The calculation runs at server startup, not continuously as players change speed. It is an approximate pacing model, not a measured navigation-time optimizer. Random sampling can produce small run-to-run variation. If floors, equipment density, sprinting, or task durations change, measure actual route completion distributions before adjusting these constants. A route to the roof is substantially different from a nearby chamber repair.

==============================================================================
CHAPTER: Baseline record: Core Features
==============================================================================

## Equipment and plant rescue

The read-only snapshot has 872 objects tagged LabEquipment, including 450 tagged PlantGrowthChamber. Other kinds include 119 Germination Chambers, 109 Incubators, 84 Decontamination Units, 45 Hormone Treatment Benches, 43 Mutagenesis Chambers, nine Growth Hormone Mixers, six Pollination Stations, five UV Growth Scanners, one GMO Injector, and one Nutrient Infuser. Tags overlap: the 450 growth chambers are included in the 872 total, not an additional population.

The original equipment engine creates controls, monitors, telemetry, storage inventories, plant Tools, treatment flags, repair assignments, and worker behavior. A plant can have an ID, life state, treatments, and a visible handheld representation. Failure damages samples, recovery in working equipment restores them, and capacity prevents unlimited storage. Transfer logic validates the player and destination again after asynchronous work or quizzes.

The latest failure policy is intentionally much smaller than the historical 60 percent target. Growth-chamber target failures are two per player, capped at eight, only when enough receiving capacity is available. Generic equipment targets one per player, capped at four. Eligibility includes a 180-second post-repair protection interval. These are targets adjusted by periodic ticks, not a promise that the instantaneous scene can never exceed them because explosions and other hazards are separate paths.

Future update procedure: extend the Kind definition and the appropriate storage/treatment handler together; establish capacity, input sample type, output state, processing duration, and failure behavior. Keep sampling and random display telemetry labeled as simulation. Test empty storage, full storage, wrong role, dead player, concurrent pickup, destroyed destination, canceled quiz, and round transition before adding presentation polish.

## Addition quiz

The shared history first introduced a large-range addition/subtraction quiz, then requested its removal, and later explicitly reintroduced a simple addition quiz for repairing and taking a plant. The current source implements two integers from 1 to 100, three answer choices, a server-owned challenge ID, and a 60-second expiry. Current quiz presence is therefore not automatically a regression against the older removal request.

The server stores one pending challenge per player, validates the reply type and challenge identity, rechecks the action predicate, and cleans up on completion or departure. The target uses QuizPlayerId as a reservation/protection signal. Dropping a sample is not described here as quiz-gated merely because an older version did so; the current direct drop behavior and pickup/repair call sites define the active contract.

Future update procedure: introduce a small quiz policy module with explicit enabled actions and difficulty bounds. Preserve challenge identity, expiration, cancellation, server-side answer checking, and revalidation of role, range, equipment health, and sample ownership. Do not put the expected answer into an authoritative client field. Changing quiz policy is a gameplay decision and should be recorded separately from a defect fix.

## Research carriers and communication

The carrier pool starts with five models and expands when all are reserved. Each player has a companion association. Unused models remain outside Workspace. Templates are selected from non-seated original workers, with alternating gender preference and distinct source models. Carriers are stripped of inherited scripts, Humanoids, prompts, and root collection tags so the old worker engine does not drive them at the same time.

Carrier movement is kinematic: anchored parts are moved by PivotTo. The GWAPNPC module animates limbs from measured travel distance, smooths turning, and keeps held weapon visuals aligned with the arm. This can look like walking, but it is not a full physics-based Humanoid locomotion system. The carrier stops near players rather than shoving them. It does not implement a general local-avoidance solver at every route segment.

Future update procedure: choose one motion authority. Either retain kinematic movement with swept-volume collision and a navigation graph, or migrate to a Humanoid-based agent with appropriate rigging. Do not add a second motion loop. Keep the mission state independent of the animation implementation so a blocked path can pause, replan, or request repair without awarding a checkpoint twice.

## Explosions, destruction, and repair

New research equipment is registered in GWAPServer, reacts to validated original-gun hits through GWAPHitBridge, and can react to nearby Explosion instances. A research station changes to DESTROYED/Exploded and receives a charred appearance, short fire/smoke effects, and a repair prompt. Its generated explosion has radius 13, zero blast pressure, and no joint destruction. Carrier damage from this path is custom code, not solely default Roblox explosion physics.

Original gas-pipe detonation has a different path in LabEquipment. It can remove up to five nearby matching wall parts and apply its own hazards. GWAPWallDamage associates recent blasts with removed wall sections, finds relevant fixtures in the wall's expanded local bounds, disables prompts and tags, and moves those fixtures to ServerStorage.DestroyedWallFixtures. The affected health station, weapon dispenser, poster, or equipment disappears from play while the object reference remains available to old callbacks.

Future update procedure: create a single destruction service with an explicit reason, origin, radius, source player, affected wall section, fixture list, and restoration policy. Distinguish equipment that is repairable in place from fixtures removed with a wall. Restoring an Exploded flag alone does not reparent a removed fixture or rebuild its supporting wall. Keep blast propagation bounded and test chain reactions against a fixed set of objects.

## Equivalent equipment routing

The current research catalog has 19 original stations, two backups per station, and ten rooftop plots: 67 station objects in total. Capability is an exact string. Backups share the original station's capability; all plots share Greenhouse planting. Router.choose ranks same-floor candidates before other-floor candidates, then floor distance and Euclidean distance. It rejects exploded, removed, destroyed, or full candidates through its current checks.

These equivalents belong to the GWAPResearch station set. A legacy Incubator elsewhere in the building is not automatically interchangeable merely because its name resembles a GWAP station. The legacy equipment engine uses a different state vocabulary, Kind catalog, capacity model, and processing logic. Extending equivalence to all equipment needs an adapter with explicit capability compatibility.

Future update procedure: add stable station IDs, capability versions, approach attachments, usable capacity, and an operational-state adapter. Check reachability after ranking; geometric proximity alone does not prove a door is open or a route exists. Publish the selected replacement and new trail together. Maintain a mission revision token to cancel old movement when a replacement or regroup action changes the route.

## Features absent from the current design

The template's currency shop, rebirth, pet unboxing, and skin-case examples are not implemented requirements. No monetization pipeline, durable research-results repository, validated biological model, formal experiment replication, or complete console certification was established by this audit. Their absence is not counted as a bug unless the owner separately commissions them.

==============================================================================
CHAPTER: Baseline record: Design Style
==============================================================================

## Setting, time, and visual language

The setting is a contemporary fictional laboratory complex. The visual language uses block-based Roblox architecture, tall glass-fronted plant equipment, restrained industrial materials, colored role identifiers, visible green seedlings, and clear status lights. The screenshots show the evolution from cluttered labels and duplicated weapon panels toward grouped interface information. A specific historical year or story timeline was not supplied.

The building contains a basement and eight aboveground levels. Generator-space floor-to-floor height is 16.25 studs, with floor indices -1 for basement, 0 for Level_1, through 7 for Level_8; the greenhouse uses floor index 8. These indices remain logical labels even when the model is translated. The present code incorrectly assumes the old absolute origin in several places, which is why the coordinate annex is necessary.

## Game Location(s)

The south entrance and role kiosks form the onboarding area. Corridors connect equipment rooms and recovery stations. North and south stair towers provide vertical circulation; a final added north flight reaches the rooftop greenhouse. The basement contains laboratory work and a maintenance-vent access route. The lounge and office fit-out are secondary spaces. Outdoor site works include laboratory-related scenery and campus features generated from the building dimensions in the historical design.

The live inventory reports 162 AutoDoor tags, 130 breakable-window tags, 18 GasPipe tags, 90 LabToolDispenser tags, 116 EmergencyKit tags, 81 RoomMonitor tags, and 72 LabPoster tags. These are editor tag counts, not measured runtime activity counts. EmergencyKit includes more than the 90 corridor health stations described in the earlier implementation report. Do not relabel all 116 as corridor health dispensers without inspecting them.

Future level update procedure: define a building coordinate frame and derive every approach, stair node, spawn, hazard bound, and fixture position from it. Add floor metadata and connectivity before populating rooms. Validate door and window clearances with the actual character volume, not only a point ray. Update both original worker room navigation and carrier navigation when floor geometry changes.

## Character Design(s)

The two player roles receive distinct laboratory outfits through LabRoles. The worker population contains 180 original NPCs; the shared history reports 90 boys and 90 girls with Romanian names and varied appearance. Current research companions clone eligible workers and apply additional hair/appearance adjustments. Their names and visible silhouettes should distinguish individuals without producing a hallway of identical clones.

NPC gun visuals reuse original inventory mesh and texture assets for the Lab Sidearm, Lab Shotgun, and Lab Rifle. They are visual representations for server-simulated NPC shooting, not complete independently equipped player Tool controllers. Future art changes must preserve grip orientation, muzzle convention, scale, arm attachment, and the relationship between the visible barrel and authoritative ray.

## Concept Art \ | Notes and Reference Image(s)

The owner's reference shooter screenshot specifies panel placement, a clear view of the world, a compact task area, and accessible inventory/status information. It is a layout reference, not a request to copy another game's code or certify identical behavior. Later screenshots document excessive overlays, the added lower-right weapon picker, repeated NPC faces, and a mobile view with competing prompts and mission panels.

Historical screenshots included later in this book are labeled by their purpose. They are not presented as screenshots of the current audited build. The current scene's translated geometry and source mismatch were found through measurements rather than inferred from the older screenshots.

## Bibliography

Primary project evidence is the captured active code, the supplied latest export, the extracted Word template, the owner's attached GWAP ideas, the current conversation, the prior shared chat, and the local revision notes. Roblox Creator Hub references are supplied in the bibliography for client/server validation, camera coordinates, pathfinding, and UI sizing. API guidance explains why a design is appropriate; it does not prove that this particular implementation passes its tests.

==============================================================================
CHAPTER: Baseline record: Monetization Strategy
==============================================================================

## Current position

No active monetization strategy was supplied or verified in the game source. The document does not invent prices, sales projections, premium currency, paid weapons, or random skin purchases. Points are gameplay rewards, not a verified Robux-linked economy. The template's weapon skin case is an example, not an adopted feature.

If monetization is commissioned later, cosmetic changes would require an explicit product specification, ownership persistence, receipt handling, retries, and restoration tests. Any product affecting movement, weapon damage, repair speed, or scientific task output would also change competitive balance and should be reviewed as a gameplay change. Do not quietly place purchase code inside a general mission or equipment handler.

==============================================================================
CHAPTER: Baseline record: Risk Analysis
==============================================================================

## Current technical risks

Coordinate drift is the highest-priority observed risk: hard-coded route positions and unchanged Approach attributes disagree with current world geometry. Source drift is the second: the loose file with the world-module name contains a different subsystem, while stored and local generators disagree. Both can invalidate an otherwise correct mission state machine.

The monolithic LabEquipment script exceeds 181 KB and combines inventory, quizzes, combat, hazards, doors, repairs, worker AI, and telemetry. Changes in one area can affect another through shared attributes and globals. A refactor should first introduce interfaces and contract tests, then extract one subsystem at a time. Splitting files mechanically without preserving initialization order would not reduce risk.

Kinematic carriers use measured routes and player stopping checks, but the main route does not continuously solve arbitrary new obstacles. The solo armed count includes pooled carriers, so the displayed 20 percent is not necessarily 20 percent of currently visible or eligible shooters. Research repair validation is narrower than legacy repair validation. Destruction removes fixtures for the session without an explicit wall reconstruction lifecycle. These issues are detailed as open audit risks rather than reported as completed fixes.

## Performance and operational risks

The editor inventory includes over 61,000 Part instances and thousands of labels/frames. Editor-wide class counts also include Studio services and UI, so they are not a clean runtime memory profile. The building's own descendants still indicate a large scene. No current frame-time, memory, network, or 60-player load test was performed. Historical removal of the lounge was considered but not undertaken because its reported 168 parts were small relative to the complex.

Before optimization, measure server heartbeat cost, client render time, replicated instance count, active moving NPCs, and GUI updates in representative rooms. Prioritize expensive always-running loops and distant display updates. Do not remove a useful room purely because its name appears in a performance discussion. The original workers already use observer-dependent behavior; carriers have a separate movement and rendering cost.

## Scope and schedule risks

Repeated large visual and interaction changes created contradictory historical instructions: add panels, enlarge panels, remove panels; add quizzes, remove quizzes, reintroduce simpler quizzes; add weapons, remove the new weapons. A dated decision ledger prevents a future AI from treating all historical requests as simultaneously active. Changes should be reviewed against the latest owner intent and the current baseline, not whichever older file is easiest to find.

There is no supplied delivery deadline or complete development-hours ledger. Durations displayed in shared-chat work summaries cannot be converted into reliable labor cost or bug-generation rates. The future schedule below is organized by acceptance gates rather than invented calendar promises.

==============================================================================
CHAPTER: Baseline record: The MVPs
==============================================================================

## Features

The playable baseline requires both roles, working role selection and outfits, reliable movement and aiming, visible plant pickup/drop, equipment repair, a readable score/objective display, and a navigable building. The GWAP extension additionally requires the ten selectable scenarios, nearby carriers, understandable dialogue, route trails, original-inventory combat, equipment destruction, equivalent rerouting, and a reachable rooftop greenhouse.

The code for these features is present, but current coordinate drift means the travel portion should not be accepted without a new play-test. An MVP acceptance statement must describe observed behavior in a specific saved place, not merely successful script compilation or existence of a greenhouse model.

## Requirements and acceptance gate

Use a copy of the latest place. Resolve the coordinate-frame issue and verify source identity before changing controls. Complete one repair and one plant pickup/drop with both roles. Complete a clean escort from initial station to rooftop planting and collect the expected points without friendly fire. Intercept a carrier once and confirm no repeated reward. Destroy its destination, verify same-floor rerouting, then destroy that backup and verify another-floor rerouting. Confirm no route traverses intact geometry.

Repeat the essential session on desktop and a small touch viewport. Check UI actions do not fire weapons, FIRE/AIM/JUMP remain separate, the mission panel clears the joystick, and idle/walking weapon stabilization persists. Run a two-client session to confirm solo opposition turns off and player assignments do not interfere. Save and reopen the tested place, then repeat a short smoke test before considering publication.

==============================================================================
CHAPTER: Baseline record: Target Dates
==============================================================================

## Milestone plan without invented dates

Gate 1 is baseline reconciliation: preserve hashes, compare saved-place identity, and designate authoritative generator/module sources. Gate 2 is spatial correctness: introduce or restore a coherent coordinate frame and verify all 67 station approaches and stair routes. Gate 3 is gameplay regression: repair, pickup/drop, escort, interception, destruction, rerouting, score accounting, and round reset.

Gate 4 is device and multiplayer validation: small phone, tablet, desktop, hybrid input, and at least two clients. Gate 5 is performance and accessibility: profile representative populated floors and finish focus/navigation behavior. Gate 6 is a separately commissioned research-data layer or content expansion. Assign dates only after the owner chooses scope and the preceding gate's defects are understood.

==============================================================================
CHAPTER: Baseline record: Credits \ | Additional Resources
==============================================================================

## Template attribution

The supplied Roblox Design Document [Open-Source].docx credits Diesoft's Open-source Roblox Game Design Document, CheekySquid's VectorThree Game Design Document tweet, and hex. Its original created/updated dates are template metadata, not this game's creation date. The extracted template and its external-link relationship list are included under evidence for attribution and structural traceability.

The prior shooting architecture was requested with reference to Roblox's FPS starter approach and the local Evostrike project. The shared history says safe Tool/Handle/weld patterns were adapted from older script collections without executing or requiring those collections. This edition does not reproduce unrelated repository trees as if they were active game dependencies. Asset IDs in the actual source are retained; this does not independently establish ownership or redistribution rights for every Roblox mesh or texture.

==============================================================================
CHAPTER: Baseline record: Technical Annex: How the Game Was Built
==============================================================================

## Construction layers and why they matter

The first layer is procedural scene construction in SeedLabGenerator. It creates the laboratory geometry, room equipment, staff, site works, controls, and embedded runtime scripts. It also contains a fallback runtime path from earlier attempts to support generation during Play. The second layer is the cross-platform weapon system, organized into Blaster, BlasterController, and ServerBlasterManager. The third layer is the additive GWAP installation: world additions, scenarios, NPC helpers, mission server, HUD, routing, and wall-fixture cleanup.

This layering explains a major maintenance hazard. Editing a live runtime script does not necessarily change the generator that will recreate it. Editing a loose module does not necessarily change the bundled installer. Editing only the installer does not repair an already saved place. Every proposed change must specify all required propagation targets and compare their actual content rather than relying on filenames.

## MCP workflow used in the documented development

The development record used Studio MCP to inspect instances and source, edit scripts in Edit mode, start controlled Play sessions, run server/client probes, inspect UI, and return to Edit mode. The important distinction is execution context. A source edit in the Play datamodel is not a persistent edit to the saved place. A client probe cannot certify server reward validation. A server probe cannot prove that a mobile button is visually reachable.

A reliable future workflow is: identify the Studio instance and place; capture source and geometry facts; save a reversible baseline; make a bounded edit in the correct datamodel; run the relevant client and server checks; remove temporary test objects; return to Edit mode; verify the persistent source; save the place; and publish only when that action is requested. This documentation pass used MCP only for read-only capture and inventory.

Large script responses require chunking. A previous LabEquipment export was truncated at roughly 100 KB and is explicitly named LabEquipment.partial.lua in the workspace backup. This edition read large scripts in 200-line chunks and checked reassembled byte lengths. A filename ending in .lua is not proof that it contains complete code. Future AI models should reject a source capture whose length or hash cannot be verified.

## Rebuild and rollback protocol

Do not enable Workspace.SeedLabGenerator_DISABLED_doNotEnable. Its name and Disabled state document that it is retained as a historical generator, not a runtime service. Running a generator can replace a large part of the world and recreate scripts. Before any future rebuild, copy the saved place, record active-source hashes, and inspect which folders and scripts the generator preserves or overwrites.

The historical intended sequence was to run SeedLabGenerator.lua in the Edit Command Bar, then InstallGWAP.lua. The current root GWAPWorld.lua mismatch has propagated into the captured installer, so neither blind assembly nor running the existing installer is safe for reproducing the active world module. For a future rebuild, first extract the correct active world module, choose the intended generator revision, regenerate the installer from those selected inputs, and compare the installed sources against the manifest. This is a proposed reconciliation procedure, not something performed while writing this book.

Rollback should restore the entire compatible set of world geometry, source containers, tags, and attributes. Restoring only the HUD or only a route module can leave invalid assumptions in another subsystem. The supplied RBXL copy is a baseline artifact, while source hashes allow detection of accidental overwrites. Do not overwrite the user's actively open place file through filesystem tools.

## State ownership and initialization

LabRoles owns team/role selection and role outfit state. LabEquipment owns most original equipment interactions, sample inventory, quizzes, failure adaptation, legacy worker activity, and hazards. LabRound owns round timing and score resolution. ServerBlasterManager owns validation of player shot requests and forwards accepted impacts to gameplay bridges. GWAPServer owns carrier assignments, current mission targets, research damage/repair registration, and solo opposition.

BlasterController runs on the client through LabSidearmClient and owns input, ADS, reticle display, arm posing, and camera presentation. LabHUD displays GWAP state and suppresses redundant older information. LabQuizClient renders challenges; LoungeClient handles the lounge's local interaction. LabKinds supplies equipment action definitions. GWAPWorld builds additive geometry, GWAPRouting supplies equivalence and backups, and GWAPNPC supplies appearance, nearby placement, dialogue visuals, and gait.

Several remotes and runtime folders are created when server scripts start, which is why the Edit snapshot contains no runtime remotes in its inventory. That absence is not evidence of missing remote code. Conversely, invoking a world-builder ModuleScript just to inspect it could mutate the scene. This edition read Source text rather than requiring modules to discover their behavior.

## Equipment state and sample transactions

The legacy engine uses WORKING and FAILED states; research equipment uses RUNNING and DESTROYED plus Exploded and BlastRemoved. Router.healthy currently excludes DESTROYED but does not require a positive RUNNING state. That is sufficient for its limited current station lifecycle but is unsafe as a universal health predicate for legacy equipment. A future adapter must explicitly map each state vocabulary.

A sample transfer is a transaction: identify a held or stored plant, verify ownership and capacity, reserve any destination, run required work or quiz, revalidate conditions, commit removal/insertion, refresh visible models, then award points. If an action yields, another player or NPC can change the same equipment. The correct fix is a reservation/commit protocol, not trusting the condition that was true before the yield.

When adding sample persistence, introduce immutable sample IDs, protocol version, treatment history, life state, current container ID, and transaction ID. Keep display strings separate from structured state. Replayed requests must not duplicate a sample or reward. A server restart should have a defined recovery policy rather than loading arbitrary partially completed tool instances.

## Carrier mission state machine

An assignment records bot, scenario ID/title, ordered route, current stage, owner, disqualified players, paused state, rendezvous need, and deadline. Choosing an assignment creates a RUNNING carrier with 100 health but paused work. Ready releases the start barrier. The mission traverses each original route name, resolves a usable station, publishes its target, moves, processes, and commits a checkpoint.

The mission remains on the same stage if its station is destroyed before processing completes. It selects an equivalent, updates the dialogue and trail, and resumes. When no station is usable it waits and extends the deadline. Completion plants the seedling and terminates the active mission. Interception, expiration, player departure, and round ending use distinct terminal-state labels. Rewards are guarded by active state and role, preventing repeated interception awards after termination.

The owner association is per player. This is not yet a shared contested convoy automatically binding both teams to the same NPC. In multiplayer, players can have separate carriers and scenarios. If the intended future mode is a common escort target, add explicit mission participants and team ownership rather than reusing the per-player table in an undocumented way.

## Motion, route planning, and the coordinate defect

Current route generation infers the starting floor from world Y using 16.25 and a 3.25 offset. It routes through corridor X=78 and a north-stair landing around Z=-6, using hard-coded tread positions. The initial rendezvous path can use PathfindingService or a checked short direct segment. Main travel consumes the generated points and smoothly rotates/moves the anchored model.

This design worked only while the laboratory occupied the measured coordinate frame. Translating the model does not transform Vector3 attributes or hard-coded constants. The current station and roof measurements demonstrate that the geometry moved while its approach data did not. A historical clear-route blockcast cannot certify today's route. This is an observed data/code mismatch; a new runtime traversal is required to quantify its gameplay effect.

The preferred future fix is to store route points in laboratory-local coordinates and transform them through one explicit anchor CFrame. Each station should have an Approach Attachment that moves with its model. Floor metadata should provide logical floor index and local elevation. Stairs should expose entrance, tread/landing, and exit nodes. Convert to world coordinates at use time. The proposed WorldFrame module later in this book is a complete reference implementation for the coordinate conversion contract, not an installed patch.

After adopting that frame, validate every navigation edge with the actual agent volume and replan when doors, walls, or fixtures change. Avoid a straight-line fallback through walls when pathfinding fails. Report the blocked state and a meaningful next action. Keep the player movement and aim controller untouched while repairing world navigation.

## Weapon casting and server validation

Blaster provides shared configuration, finite-vector checks, screen/camera ray selection, muzzle handling, and raycast helpers. Desktop and mobile have different aim-origin conventions: desktop follows the actual mouse position; mobile uses camera LookVector. A single predicted target and muzzle-obstruction result should feed the reticle and firing request. Do not recompute them with a different safe-area convention for display.

ServerBlasterManager checks packet version, equipped Tool ownership, living character, finite/ranged vectors, sequence ordering, camera-origin proximity, and firing cooldown before accepting a shot. It performs authoritative raycasting and invokes the GWAP hit bridge before the legacy gameplay bridge. A client-supplied target is not an authorization to damage that target. The server's accepted collision result controls effects and gameplay.

Roblox's client/server security guidance supports validating type, value, context, and request rate on the server, including remote and prompt-driven actions. This project's specific constants and branches come from the captured code; the guidance is not an external certification of the implementation. The current research repair prompt has fewer server checks than the legacy canInteract path, so it needs a deliberate audit before broader use.

## Aiming and trembling: causes and boundaries of the fix

The development record contains several different aiming faults. Mobile safe-area coordinates disagreed with camera-forward direction. Desktop screen/viewport coordinate pairing drifted. Hybrid input detection could prioritize TouchEnabled while a mouse was active. Missing reticle children and conflicting touch-button placement caused UI failures. Later character/arm posing had to support more than a single assumed shoulder joint.

The recent trembling fix addressed another class of problem: multiple transform writers and artificial weapon bob. Root rotation moved to a single pre-camera update, duplicate controller ownership was restricted, artificial idle/walk Grip bob was removed, and armed shoulder/torso animation was stabilized while leg motion remained. The prior measurements found zero Grip motion during idle and a walking test, and zero shoulder idle-animation translation. Recoil when actually firing remains intentional.

A future fix must isolate the measured fault. If a FIRE button is hidden, inspect its parent, size, visibility, Z order, and initialization; do not redesign camera coordinates. If a stationary weapon oscillates, inspect all Grip, shoulder, torso, and camera writers; do not simply reduce aim sensitivity. Test target direction, visible barrel pose, UI triggering, and physical movement as separate contracts.

## HUD and information grouping

The current LabHUD groups round/team/score/health into a top strip and mission/conversation/actions into a left panel. The original backpack stays at the bottom. The owner rejected a second weapon selector, so no replacement arsenal panel should be added. Dialogue is displayed in the mission panel, and overhead NPC details are limited to relevant nearby targets.

The HUD also hides duplicate player health and older RoleHUD/LabLog displays. Research station labels are restricted to the aimed-at nearby station. Route dashes are local non-colliding, non-query geometry, limited by distance and height. These policies reduce clutter, but hiding a legacy message stream can also hide an important original-equipment instruction. Future work should route notices through a structured priority queue rather than rely on multiple competing text attributes.

Use one layout computation that knows the safe inset, joystick rectangle, jump/fire/aim rectangles, inventory area, and modal state. Check actual GUI rectangles rather than estimating from screenshots. The current quiz popup is a separate overlay and should be included in overlap tests. A panel being transparent does not make an overlap acceptable if it blocks text or input.

## Destruction and rerouting lifecycle

GWAPWallDamage watches qualifying wall removal near a recent Explosion. Its fixture query expands the removed wall's local box, compensating for wall-mounted objects offset from the wall surface. It strips tags and prompts before reparenting fixtures out of Workspace. This avoids continued visible interaction with a fixture whose support wall is gone, and preserves a reference for existing callbacks.

The current round reset repairs registered research items but does not explicitly restore fixtures from DestroyedWallFixtures or rebuild supporting walls. A repaired state flag on a removed item does not make Router.healthy true, because it is not a Workspace descendant. Treat restoration as a separate lifecycle operation. Future tests should cover round reset after wall destruction, not only a direct station explosion followed by R repair.

Research explosion propagation is deferred and guarded by Exploded to limit repeated detonation until repair. That bounds the number of station explosions, but the visual and performance effect of many nearby stations has not been profiled. If a future blast can also destroy paths or doors, invalidate affected navigation edges and publish a route revision so old movement does not continue toward removed geometry.

## Solo opposition and fairness

At solo arming time, the server combines the 180 tagged original workers with available research carriers, shuffles them, and selects floor(total*0.2). With five carriers that is 37 of 185 models. Some selected carriers may be pooled outside Workspace; firing skips those models, dead/knocked-out bots, and the player's own defending carrier. Consequently GWAPArmedCount is a selection count, not necessarily the visible threatening population.

Every 2.5 seconds eligible bots in the 4-to-85-stud range check line of sight and use a spread ray. A successful player hit applies fractional score loss. Multiplayer disables this solo firing loop and reselects arming on player/round changes. Future work should define the denominator as eligible active NPCs, then test joins, departures, respawns, pool growth, and role changes. Preserve fractional accounting when changing the score display.

## Scientific data extension architecture

A research-capable extension should add ProtocolRegistry, TaskDataset, ObservationSubmission, QualityControl, and ResultExport boundaries. ProtocolRegistry defines valid stages and variables. TaskDataset supplies authentic stimuli or a clearly identified simulation seed. ObservationSubmission records structured decisions with protocol and sample IDs. QualityControl checks repeated judgments and known examples. ResultExport produces a schema reviewed by the intended researcher.

Keep this layer independent of combat and presentation. A player can lose game points without invalidating a correct annotation; a fast carrier route does not make a measurement biologically reliable. Record missing data, failure reasons, task revision, and timing without fabricating results. The present project has no such implemented pipeline, so the scenario proposals below are design options rather than claims of current scientific utility.


<<< source chapter: chapters/architecture-diagrams.tex >>>
==============================================================================
CHAPTER: Architecture and coordinate diagrams
==============================================================================

## Runtime responsibilities

 (client) Client input and display
BlasterController, LabHUD
LabQuizClient;
 (server) Authoritative server
ServerBlasterManager
GWAPServer, LabEquipment;
 (state) Server-owned state
assignments, samples
points, damage, rounds;
 (world) World and navigation
GWAPWorld, GWAPRouting
stations, stairs, fixtures;
 (client.east) -- node[above,font=]requests (server.west);
 (server.south) -- (state.north);
 (world.east) -- node[above,font=]geometry/state (state.west);
 (state.south) -- ++(0,-8mm) -| node[pos=.7,below,font=]replicated attributes and presentation (client.west);

Requests do not directly authorize rewards or damage. The server validates and commits gameplay state. The client displays that state and predicts visual aiming feedback. The world supplies geometry and station metadata; the current coordinate defect shows why those two must remain consistent.

## Observed origin mismatch: Incubator example

 (15,25) -- (108,25) node[right]world X;
 (15,25) -- (15,162) node[above]world Z;
 (67,49) circle[radius=2pt] node[below left,align=right]builder station
(67,49);
 (78,49) circle[radius=2pt] node[right,align=left]stored approach
(78,49);
 (41.857,140.286) circle[radius=2pt] node[left,align=right]actual station
(41.86,140.29);
 (67,49) -- node[left,sloped,font=]observed translation (41.857,140.286);
 (78,49) -- (41.857,140.286);

This plan view omits height for clarity. The station's actual Y is -21.75, while its builder Y is 1.5 and its stored approach Y is 3.25. Geometry translation does not automatically transform Vector3 attributes or literal coordinates in code. The dashed line illustrates the disagreement; it is not a proposed valid path.

## Proposed mission transition contract

 (choose) Choose job
paused;
 (resolve) Ready / resolve
healthy target;
 (travel) Travel and
process;
 (commit) Commit checkpoint
or final planting;
 (wait) Wait / replan
same stage;
 (choose) -- (resolve);
 (resolve) -- (travel);
 (travel) -- (commit);
 (travel.south west) -- node[above,sloped,font=]destroyed / blocked (wait.north east);
 (wait) -- (resolve);
 (commit.south) -- ++(0,-7mm) -| node[pos=.7,below,font=]next stage (resolve.west);

The current code implements destruction rerouting and pause behavior. General blocked-edge replanning remains proposed. Every asynchronous operation should carry the assignment/route revision so a stale operation cannot commit after regroup, termination, or a new target selection.


<<< source chapter: chapters/scenarios.tex >>>
==============================================================================
CHAPTER: Ten research scenarios: protocols and extension specifications
==============================================================================

All ten scenarios below are implemented as ordered gameplay routes and a randomized integer variant. The proposed data product and validation paragraphs are future design, not implemented science. Floor labels describe logical floors in the original building frame. The initial coordinate discrepancy was repaired in Revision 4; see its fresh verification results and remaining coverage limits.

## 01. Germination viability

### Implemented route and parameter

Seed bank (B1) -> Incubator (L1) -> Plot 1 (roof)

Moisture, integer 35-80 percent

A seedling is collected, incubated, and planted. Moisture is a displayed assignment variant; it does not drive a germination probability model.

### Future scientific-purpose implementation

Annotate germinated versus non-germinated seeds in authentic, protocol-controlled images. Store image ID, seed count, germination count, moisture condition, replicate, and observer decision.

Use known examples and repeated independent counts; compare agreement before interpreting treatment differences. Preserve the original image and sampling method.

### Engineering change and acceptance

Try both endpoints of the moisture range; destroy the Incubator before arrival and during processing. Verify an equivalent is selected and the nominal two-checkpoint plus final reward is not duplicated.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 02. Pathogen resistance

### Implemented route and parameter

Containment (L2) -> Bio-analyzer (L3) -> Plot 2 (roof)

Resistance batch, integer 1-9

The batch number distinguishes assignments. There is no infectious-agent simulation, measured resistance curve, or actual laboratory manipulation.

### Future scientific-purpose implementation

Classify visible plant-damage severity in a vetted image dataset with blinded treatment labels. Store dataset item, scoring scale version, replicate, and confidence.

Use a researcher-defined severity rubric and reference examples. Separate plant damage from image artifacts; aggregate only comparable stages and cultivars.

### Engineering change and acceptance

Destroy Containment and its same-floor backup, then confirm the other-floor replacement retains the same capability and stage. Check that resistance batch remains unchanged after rerouting.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 03. Light spectrum optimization

### Implemented route and parameter

Seed bank (B1) -> Spectrograph (L2) -> Infrared scanner (L3) -> Plot 3 (roof)

Photoperiod, integer 8-18 hours

Three pre-plot stations create a longer route. The number of hours is descriptive, not elapsed game time or a measured spectrum.

### Future scientific-purpose implementation

Mark leaf boundaries or estimate leaf area in calibrated images from controlled light treatments. Record calibration, illumination condition, image timestamp, and segmentation.

Require scale calibration and repeated annotation. Do not infer spectral response from the avatar visiting an instrument.

### Engineering change and acceptance

Verify all four route stages and the nominal 105-point clean escort. Destroy the middle instrument after seed collection; the carrier must retain its seedling and resume without collecting a second one.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 04. Soil bioremediation

### Implemented route and parameter

Chemical seedlings (B1) -> Root analyzer (L2) -> Plot 4 (roof)

Soil batch, integer 1-12

The workflow represents sample tracking. It does not calculate contaminant concentration, uptake, removal efficiency, or environmental safety.

### Future scientific-purpose implementation

Trace roots in real scan images or match samples to verified metadata. Record source sample, imaging method, root mask, and uncertain regions.

Use expert review for ambiguous roots and preserve units/calibration. A gameplay completion cannot certify remediation success.

### Engineering change and acceptance

Verify replacement Root analyzer selection, plot capacity, and no stage advancement while the target is destroyed. Confirm batch metadata remains associated with the assignment.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 05. Hydroponic versus soil

### Implemented route and parameter

Split-root tray (L1) -> Centrifuge (L3) -> Root analyzer (L2) -> Plot 5 (roof)

Nutrient batch, integer 1-8

The route deliberately goes up and then down before the roof. No paired root-growth measurements currently exist.

### Future scientific-purpose implementation

Compare paired, anonymized root images from controlled growth conditions. Store pair ID, condition metadata held separately, root-length annotation, and replicate.

Randomize presentation order and require comparable imaging scales. Analyze pairs rather than treating unrelated plants as matched samples.

### Engineering change and acceptance

Exercise both ascent and descent, a destroyed Centrifuge, and a destroyed Root analyzer. Check that the route order is preserved and the two instruments are not treated as interchangeable.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 06. UV adaptation

### Implemented route and parameter

UV chamber (L2) -> Vitality scanner (L1) -> Plot 6 (roof)

Exposure, integer 5-20 seconds

The assignment text describes exposure; processing is still the common four-second gameplay action and does not implement the chosen duration.

### Future scientific-purpose implementation

Annotate visible stress features in a curated before/after plant image pair. Record acquisition conditions, treatment metadata, severity features, and uncertainty.

Use researcher-approved image data and a fixed rubric. This game is not an instruction for operating UV equipment.

### Engineering change and acceptance

Check descending travel after the UV stage, stable variant display, and shared use of Vitality scanner capability with scenarios 10 and 6 without crossing assignment ownership.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 07. Gravitropism assay

### Implemented route and parameter

Clinostat (B1) -> Orientation scanner (L1) -> Plot 7 (roof)

Tray tilt, integer 10-80 degrees

The scenario names an orientation experiment but does not currently simulate root curvature from gravity or time.

### Future scientific-purpose implementation

Mark root tips and growth angles in time-lapse frames with a known reference axis. Store frame time, axis calibration, landmarks, and annotation quality.

Require consistent angle conventions and reject occluded frames. Separate tray orientation from measured root direction.

### Engineering change and acceptance

Verify Clinostat backups, floor-label conversion for basement, and a clear initial rendezvous. Test the zero-length initial-path case that previously required an explicit bypass.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 08. Drought resistance

### Implemented route and parameter

Climate chamber (L3) -> Porometer (L2) -> Plot 8 (roof)

Humidity, integer 20-45 percent

The mission says simulated stomatal response, but it does not compute conductance or water potential. Humidity is assignment metadata.

### Future scientific-purpose implementation

Annotate stomatal aperture from suitable microscopy images or organize verified instrument observations. Store image/instrument record ID, scale, treatment, aperture annotation, and replicate.

Require a defined measurement method and expert validation. Do not combine incompatible instruments or units under one generic score.

### Engineering change and acceptance

Destroy the Porometer while the carrier is processing; verify that processing restarts at an equivalent rather than completing on the destroyed station.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 09. Microbiome symbiosis

### Implemented route and parameter

Wet lab (B1) -> Symbiosis incubator (L2) -> Plot 9 (roof)

Inoculum batch, integer 1-8

The batch labels a transport protocol. No microbial growth model, sequencing data, or biological assay is present.

### Future scientific-purpose implementation

Label root colonization regions in an approved microscopy dataset. Store image ID, region mask, labeling taxonomy, batch, and replicate.

Use blinded examples, inter-annotator agreement, and expert adjudication. Treat uncertain regions as uncertain rather than forcing a positive classification.

### Engineering change and acceptance

Verify the carrier spawns near the selected role, explains the assignment, waits for Ready, and retains the inoculum batch through same-floor and other-floor reroutes.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.

## 10. Cold-hardiness screening

### Implemented route and parameter

Cryo-freezer (B1) -> Vitality scanner (L1) -> Plot 10 (roof)

Recovery temperature, integer 5-20 C

The workflow models recovery transport. It does not simulate freezing injury or measure actual survival.

### Future scientific-purpose implementation

Score recovery features in a time series with known treatment conditions. Store plant ID, time since recovery, visible features, viability rubric, and observer confidence.

Require consistent follow-up timing and a definition of survival. Separate missing observations from dead plants.

### Engineering change and acceptance

Check cryo-freezer explosion handling, a full Plot 10 falling back to another healthy greenhouse plot, and no reward if the assigned carrier is intercepted before final planting.

Implementation touchpoints: GWAPScenarios defines title/purpose/route/range; GWAPWorld and GWAPRouting provide named capabilities and approaches; GWAPServer executes the stages and awards; LabHUD presents the assignment. A real data layer must add structured records independently of this route. Keep a stable scenario ID and protocol version so saved or exported observations do not change meaning when the list is reordered.


<<< source chapter: chapters/defects.tex >>>
==============================================================================
CHAPTER: Defect register, change accounting, and lessons
==============================================================================

## How many bugs were generated?

The evidence supports a bounded register of 24 historical defect families (H01-H24), two newly observed source/scene discrepancies (C01-C02), seven baseline audit risks (R01-R07), with final status in the Revision 4 chapter, and two tool/test artifacts (T01-T02). These categories are not added together as a lifetime bug total. A family groups recurring reports of the same symptom; one family may have had several causes or fixes. No complete issue tracker, commit history, or causal record establishes the total number of bugs introduced by an AI model.

At least two episodes have explicit evidence of an AI change or implementation error: H13 is the owner-requested rollback/restoration after an aiming change, and H24 is the zero-length route-prefix defect encountered during implementation testing. Other families are associated with the evolving AI-built game, but the record does not isolate whether each was newly introduced, pre-existing, or caused by an intervening model/asset change. Reporting all 24 as definitely generated by one model would be unsupported. The two current discrepancies are observed now; their author and exact introduction time are unknown.

Five major requirement reversals are recorded separately: large monitor panels were later removed; quizzes were added, removed, and then reintroduced in simpler form; the extra GWAP arsenal was added and then rejected; a broad 60-percent failure policy was replaced by a small workload; and static/identical NPC presentations were replaced by differentiated moving workers. New research-equipment destructibility and equivalent-station rerouting are feature extensions as well as corrections to the desired experience. They do not each count automatically as a new software bug.

## Historical defect families

### H01: Role kiosk inaccessible or inert

Evidence: Earlier shared chat: user could not select a role or activate the kiosk.

Repair history: Interaction layout and trigger behavior were repeatedly revised; temporary touch selection was later removed.

Code and regression target: LabRoles and kiosk geometry; verify E/click selection and no accidental role change.

Status: Reported fixed historically; not replayed in this edition.

### H02: Role outfit missing or insufficiently distinct

Evidence: Earlier shared chat repeatedly requested visible clothing after role selection.

Repair history: Role appearance application and respawn behavior were revised.

Code and regression target: LabRoles; test both roles before and after respawn.

Status: Reported fixed historically; appearance is built, full rig coverage unverified.

### H03: Equipment E/F actions appeared inert

Evidence: Earlier user reports said nothing happened near equipment or when pressing controls.

Repair history: Physical prompts/buttons and runtime/fallback installation were revised.

Code and regression target: LabEquipment bind/makeControls; distinguish old F behavior from current E/R policy.

Status: Reported fixed historically; syntax checks alone were insufficient evidence.

### H04: Plant could be taken but not dropped

Evidence: Earlier user explicitly reported pickup without a usable drop interaction.

Repair history: Working-cabinet drop logic, free-slot guidance, and human override of reservations were improved.

Code and regression target: LabEquipment takePlantFromChamber/storePlantInChamber.

Status: Reported fixed historically; retest full/wrong/removed destinations.

### H05: Equipment or fixtures intersected walls, doors, or windows

Evidence: Multiple earlier screenshots and requests identified misplaced cabinets, health kits, weapons, and pipes.

Repair history: Placement clearance and wall alignment were revised; pipes moved upward.

Code and regression target: Generator placement and saved geometry.

Status: Historical clearance measurements exist; current translated geometry needs a fresh spatial audit.

### H06: Equipment could be repaired through a wall

Evidence: Earlier user explicitly identified repair across a wall.

Repair history: Closer interaction range and server line-of-sight validation were added to legacy interactions.

Code and regression target: LabEquipment canInteract.

Status: Built in legacy path; separate research prompts have risk R01.

### H07: Repair route crossed walls or ignored stairs

Evidence: Earlier user reported a straight red path through geometry.

Repair history: Pathfinding and explicit stair-aware routing replaced a straight fallback.

Code and regression target: LabEquipment createRepairPath; later GWAP routePoints is a separate implementation.

Status: Historically reported fixed; C01 invalidates assumptions for moved geometry.

### H08: Overlapping information obscured play

Evidence: Repeated shared-chat and current-thread screenshots show large or duplicate panels.

Repair history: Distant labels, duplicate HUDs, and notification feeds were reduced; latest HUD groups mission/status.

Code and regression target: LabHUD, LabEquipment display policy, BlasterController, LabQuizClient.

Status: One small-phone layout measured; all modals/devices not exhaustive.

### H09: Uneven lighting and black floor bands

Evidence: Earlier handoff requested lighting repair.

Repair history: The handoff records the defect but does not independently prove the exact repair.

Code and regression target: Generator Lighting and room light placement.

Status: Historical report; current visual closure not established by this audit.

### H10: Touch firing failed or used unsuitable input

Evidence: Shared chat requested cross-platform shooting because mobile controls failed.

Repair history: Separated controller, casting module, and server manager; touch camera and action controls introduced.

Code and regression target: BlasterController, Blaster, ServerBlasterManager.

Status: Historical device checks reported; preserve input separation.

### H11: Reticle and muzzle impact disagreed

Evidence: Shared chat reported firing toward the avatar or not correctly hitting a wall.

Repair history: Camera target and muzzle obstruction handling were revised.

Code and regression target: Blaster ray helpers and controller reticle.

Status: Historical desktop/mobile impact checks reported.

### H12: Android vertical aim offset

Evidence: Aiming at the tree base produced a hit near the branches.

Repair history: Mobile ray changed to Camera.CFrame.LookVector after a reported 1.35-degree safe-area mismatch.

Code and regression target: BlasterController mobile aim ray.

Status: Historical lower-trunk hit and client/server direction agreement reported.

### H13: Mouse pitch/yaw and arm tracking regressed

Evidence: User requested restoration after unrelated trigger/aim experiments.

Repair history: Mouse-priority detection and shoulder/arm target tracking restored, including newer joints.

Code and regression target: BlasterController input mode and arm pose.

Status: Explicit AI-change-associated regression; historically restored.

### H14: FIRE/AIM/JUMP controls overlapped

Evidence: Shared chat and screenshots identified overlapping mobile actions.

Repair history: Controls repositioned relative to jump with separate spacing.

Code and regression target: BlasterController touch layout.

Status: Historical Galaxy A06 check; regression coverage required after HUD changes.

### H15: HUD existed without its reticle

Evidence: Shared chat reports incomplete BlasterHUD initialization.

Repair history: HUD integrity checks rebuild missing reticle children.

Code and regression target: BlasterController _ensureHUD.

Status: Reported fixed historically; test equip/unequip and device changes.

### H16: Maintenance vent landed player partly in floor

Evidence: User reported becoming embedded at basement destination.

Repair history: Vent landing and both basement stair routes were corrected.

Code and regression target: LabEquipment basement handler and generator geometry.

Status: Historical vent landing test reported.

### H17: Workers passed through geometry or players

Evidence: Shared chat requested room-aware movement and avoidance.

Repair history: Original worker motion gained room/obstacle checks and appearance updates.

Code and regression target: LabEquipment botMotionChecks/walkBotSegment/moveBotTo.

Status: Historical implementation; not proof of arbitrary carrier obstacle avoidance.

### H18: Assigned carrier was not nearby or visible

Evidence: Current-thread user could not find the mission NPC after role selection.

Repair history: Per-player companion allocation and safe nearby placement introduced.

Code and regression target: GWAPServer companion/startMission; GWAPNPC nearPlayer.

Status: Historical approximately eight-stud placement test.

### H19: Carrier clones repeated names/appearance and female silhouette was wrong

Evidence: Current-thread screenshots show repeated Maria models and unsuitable hair.

Repair history: Different non-seated templates, alternating gender preference, and hair adjustments.

Code and regression target: GWAPServer makeBot; GWAPNPC appearance.

Status: Historical appearance check; animation/identity remain template-dependent.

### H20: Carriers queued together in the hallway

Evidence: Current-thread screenshot and request rejected a hallway line of bots.

Repair history: Unused carriers moved to a ServerStorage pool and allocated individually.

Code and regression target: GWAPServer available/companions/pool.

Status: Historical one visible, four pooled observation.

### H21: Carrier glided unnaturally and too slowly

Evidence: Current-thread user asked for natural movement matching player speed.

Repair history: Distance-driven limb gait and smoothed owner WalkSpeed matching added.

Code and regression target: GWAPNPC animate; GWAPServer go.

Status: Historical speed-20 movement and approximately 24-degree leg swing measured.

### H22: Weapon trembled while idle and walking

Evidence: Repeated current-thread reports persisted after an earlier partial fix.

Repair history: Single pre-camera rotation, no artificial Grip bob, and armed animation stabilization.

Code and regression target: BlasterController pre-camera, render, and PreSimulation paths.

Status: Historical zero Grip motion idle/walking; firing recoil retained.

### H23: Wall explosion left fixtures floating or usable

Evidence: Current-thread user requested disappearance of objects attached to the removed wall section.

Repair history: Recent-blast wall removal detection and fixture quarantine introduced.

Code and regression target: GWAPWallDamage.

Status: Historical four fixture categories removed; outside health station preserved.

### H24: Zero-length rendezvous path prevented progress

Evidence: Development test encountered a start point already at its corridor entry.

Repair history: Zero-distance prefix bypass and checked short direct path added.

Code and regression target: GWAPServer go initial rendezvous.

Status: Implementation-level defect found during testing; historical retest passed.

## Baseline discrepancies, risks, and tool artifacts

These entries preserve the initial audit. Revision 4 repairs C01/C02, adds role/LOS validation for R01, collision stopping for R02, correct eligibility for R03, and filtering for R07. R04 restoration policy, R05 shared-mission semantics, R06 load certification and the limits stated in the Revision 4 chapter remain open.

### C01: Observed now: moved geometry, stale route coordinates

Evidence: Station positions and roof share a translation while Approach attributes and routePoints constants retain the old origin.

Next action: Introduce a coherent local coordinate frame and approach attachments; validate every route in a copied place. No fix installed here.

### C02: Observed now: incorrect world module bundled in installer

Evidence: Root GWAPWorld.lua contains older mission-server code, and InstallGWAP.lua installs that incorrect content as the world module. The active module is different.

Next action: Do not run the captured installer unchanged. Replace its world-module input from the verified active source, reconcile generator versions, regenerate and compare installed hashes in a copied place.

### R01: Research prompt validation is narrower than legacy validation

Evidence: ResearchRepair checks life, distance, and Exploded but does not enforce Technician role or perform its own server ray visibility check.

Next action: Apply an explicit role/range/visibility/state policy and validate hold completion server-side where required. Test wrong role and an intervening wall.

### R02: Main carrier route assumes clear surveyed geometry

Evidence: The main kinematic route moves along points and stops near players; it does not sweep every segment for arbitrary new obstacles.

Next action: Add edge validation, blocked-route state, and bounded replanning. Preserve one movement authority.

### R03: Solo percentage counts pooled models

Evidence: Arming includes available carriers outside Workspace, while shooting excludes them.

Next action: Define an eligible active population; recompute selection on lifecycle changes and display both selected and active threat counts.

### R04: Wall-fixture restoration is not defined

Evidence: Removed fixtures remain in ServerStorage; repairing attributes does not rebuild walls or reparent fixtures.

Next action: Define persistent versus per-round destruction, then implement explicit restoration or deliberate permanent removal for the session.

### R05: Multiplayer balance and shared objective semantics are unverified

Evidence: Assignments are per player; no complete multi-client regression was recorded.

Next action: Test two roles and multiple carriers concurrently; commission a shared-convoy design separately if desired.

### R06: Scale is configured, not performance-certified

Evidence: MaxPlayers is 60 and the scene is large; no current load profile was captured.

Next action: Measure client/server frame time, memory, replication, and NPC workloads before making capacity claims.

### R07: Lounge notes are displayed without explicit filtering

Evidence: LoungeSystems onChat stores the raw /note message and refreshWall writes it to a shared display; no text-filtering call appears in that source.

Next action: Filter submitted text on the server using the appropriate Roblox text-filtering result for a shared display, handle filtering failure without displaying raw text, and add length/rate limits. Test with multiple viewers.

### T01: Tool artifact: truncated source backup

Evidence: A previous LabEquipment backup was cut near 100 KB and renamed .partial.lua.

Next action: Never install a partial capture. This edition verifies every reconstructed Studio source byte length.

### T02: Test artifact: duplicate controller binding

Evidence: A prior client test required/bound a controller again and produced duplicate render-step warnings.

Next action: Use existing bootstrap/controller instances for probes and fresh Play sessions; do not classify the test harness warning as a confirmed production defect.

## Rules that prevent repetition

Freeze an accepted input/camera baseline before unrelated features. Measure a symptom before rewriting its subsystem. Use live source and hashes to resolve conflicts. Keep one owner for camera, root, arm, and gun transforms. Revalidate after every yielding interaction. Treat geometry and navigation metadata as one versioned unit. Check actual screen rectangles and server state, not only appearance. Separate a passing syntax check from a passing player workflow. Never report a tool artifact or an old test as proof of current gameplay correctness.


<<< source chapter: chapters/verification-ledger.tex >>>
==============================================================================
CHAPTER: Verification ledger and future acceptance suite
==============================================================================

## P01: Role selection and nearby companion

Evidence period: Prior GWAP turn

Observed/reported result: Approximately eight studs from player; one visible carrier and four pooled.

Limit: Historical observation, not rerun for current geometry.

## P02: Wait and Regroup

Evidence period: Prior GWAP turn

Observed/reported result: Wait movement zero; regroup returned within roughly eight studs.

Limit: No stress test of every blocked spawn candidate.

## P03: Original rifle and equipment destruction

Evidence period: Prior GWAP turn

Observed/reported result: Lab Rifle destroyed a research machine; nearby explosion destroyed another; R repair restored it.

Limit: Does not certify wall-fixture restoration or every blast chain.

## P04: Equivalent rerouting

Evidence period: Prior GWAP turn

Observed/reported result: Incubator -> same-floor Backup 1 -> other-floor Backup 2; assignment stayed RUNNING.

Limit: Earlier coordinate frame; current C01 requires rerun.

## P05: Carrier gait and speed

Evidence period: Prior GWAP turn

Observed/reported result: WalkSpeed 20; roughly 28.7 studs of travel during sampled interval; leg swing about 24 degrees.

Limit: Kinematic gait, not Humanoid physics certification.

## P06: Wall-fixture cleanup

Evidence period: Prior GWAP turn

Observed/reported result: Four fixture types within a temporary wall section removed; outside health station preserved.

Limit: Controlled isolated test, not whole-floor blast profiling.

## P07: Small mobile layout

Evidence period: Prior GWAP turn

Observed/reported result: 705x338 viewport; panel bottom y=179, joystick top y=187.

Limit: Eight-pixel gap in this configuration only.

## P08: Idle weapon stabilization

Evidence period: Prior GWAP turn

Observed/reported result: 90 frames with zero Grip motion and zero shoulder-animation translation.

Limit: One tested original rifle/rig configuration.

## P09: Walking stabilization

Evidence period: Prior GWAP turn

Observed/reported result: Approximately 19 studs of walking with zero Grip motion.

Limit: Intentional recoil while firing was not removed.

## P10: Interception score

Evidence period: Prior GWAP turn

Observed/reported result: Assigned carrier awarded 50 once; repeat damage did not add points.

Limit: Multi-client race conditions not exhaustively tested.

## P11: Solo score loss

Evidence period: Prior GWAP turn

Observed/reported result: 100 points became 99 on a successful NPC hit.

Limit: Low-score fractional policy also inspected in code; no long statistical run.

## P12: Rooftop mission completion

Evidence period: Earlier GWAP turn

Observed/reported result: Seed source -> instrument -> roof completed and one plant appeared.

Limit: Test used helper following; friendly fire disqualified final escort reward, so clean full reward was not proven.

## P13: Player shooting validation

Evidence period: Shared chat

Observed/reported result: Reported 10 damage, wall blocking, and rejection of distant forged camera origin.

Limit: Historical report; not a new penetration/security audit.

## P14: ADS and device controls

Evidence period: Shared chat

Observed/reported result: Reported FOV 70->55 and sensitivity 1->0.62, restored on exit; phone/tablet controls checked.

Limit: Some later control changes superseded these exact UI versions.

## P15: Basement and quiz/window interactions

Evidence period: Shared chat

Observed/reported result: Vent landing, pickup quiz, and breakable window passed reported checks.

Limit: No new Play session in this edition.

## D01: Live source completeness

Evidence period: This edition

Observed/reported result: 29 source containers captured; every UTF-8 byte length matched Studio inventory.

Limit: Static capture only; active count 20, archive 8, disabled generator 1.

## D02: Scene/source audit

Evidence period: This edition

Observed/reported result: 67 research station records; place version 70; C01 and C02 identified.

Limit: No claim that current routing is playable.

## Proposed new regression sequence

### Baseline

Open a copied saved place, identify the place/version, compare active-source hashes, and ensure there is only one bootstrap/controller authority.

### Coordinate frame

Translate and rotate a test laboratory with its navigation origin; verify every station approach stays in its intended corridor and each stair edge is clear. Include the current displaced scene as a regression fixture.

### Transactions

Two clients compete for the same plant and destination slot. Exactly one transfer commits; the other gets a clear reason. Repeat with a quiz outstanding, a full cabinet, and a destroyed destination.

### Carrier lifecycle

Choose, Ready, Wait, Status, Regroup, respawn, disconnect, change role, and end the round during travel and processing. No duplicate carrier, seedling, or reward remains.

### Destruction

Bullet-hit research station, chain blast, wall-section removal, outside-fixture preservation, repair, all-equivalents unavailable, and round reset after quarantine.

### Input preservation

Desktop mouse target at all screen edges; mobile forward ray; right-swipe camera with left movement; ADS on/off; equip/unequip; idle/walk gun stability; UI click does not fire.

### Responsive layout

Small phone portrait and landscape, tablet, desktop, chat open, quiz open, inventory open. Record rectangle intersections for mission, joystick, jump, fire, aim, and prompts.

### Scoring

Clean 90/105-point escort as applicable, one 50-point interception, friendly-fire disqualification, low-score fractional loss, reset debt, and multiplayer solo-fire exclusion.

### Performance

Profile crowded rooms and multi-client play; report hardware, viewport, scene population, average/p95 frame time, server heartbeat cost, and replication load. Do not extrapolate a one-client test to 60 players.

These are proposed tests. They were not executed while producing this document. The verification report for this edition concerns source capture, document compilation, page rendering, and manifest completeness.


<<< source chapter: chapters/future-updates.tex >>>
==============================================================================
CHAPTER: Subsystem-by-subsystem future update playbook
==============================================================================

## LabKinds: Equipment catalog

Authoritative source: S05 / ReplicatedStorage.LabKinds

See complete listing on page src:S05.

### Proposed implementation

Add one Kind with inputs, outputs, wait duration, and display text. Keep simulation values explicit.

### Dependencies to preserve

LabEquipment consumption and treatment paths; generator Kind attributes.

### Acceptance cases

Unknown Kind, missing input, invalid output, full destination, and a complete valid cycle.

## LabEquipment: Equipment engine

Authoritative source: S11 / ServerScriptService.LabEquipment

See complete listing on page src:S11.

### Proposed implementation

Extract inventory transactions before touching hazards or NPC motion. Preserve reservations and post-yield validation.

### Dependencies to preserve

LabRoles assignments, LabQuizClient, tagged geometry, server hit bridge.

### Acceptance cases

Concurrent pickup/drop, repair during failure tick, dead player, destroyed target, canceled quiz.

## LabRoles: Roles and outfits

Authoritative source: S12 / ServerScriptService.LabRoles

See complete listing on page src:S12.

### Proposed implementation

Keep exactly two roles unless commissioned otherwise; centralize role-to-outfit and permission mapping.

### Dependencies to preserve

GWAPServer LabRole observer and original equipment role checks.

### Acceptance cases

Both kiosks, respawn, role change during mission, and accessory/rig variations.

## LabRound: Round lifecycle

Authoritative source: S13 / ServerScriptService.LabRound

See complete listing on page src:S13.

### Proposed implementation

Make reset ordering explicit with one round transition contract and subsystem callbacks.

### Dependencies to preserve

Points, fractional debt, carrier termination, research repair, plot clearing.

### Acceptance cases

Join during break, end during processing, disconnected winner, and reset after destruction.

## LabTechnicians: Legacy worker service

Authoritative source: S14 / ServerScriptService.LabTechnicians

See complete listing on page src:S14.

### Proposed implementation

Check which templates actually have Humanoids before extending its path loop. Avoid competing with LabEquipment worker motion.

### Dependencies to preserve

LabWorkerBot tags and template structure.

### Acceptance cases

No double movement, no idle thread leak, valid target assignment, and bounded retry.

## LabElevators: Elevator compatibility script

Authoritative source: S10 / ServerScriptService.LabElevators

See complete listing on page src:S10.

### Proposed implementation

Treat as dormant unless real tagged elevator geometry exists. Do not claim elevator transport from script presence alone.

### Dependencies to preserve

Level metadata and any future lift models.

### Acceptance cases

Door interlock, floor alignment, queueing, interrupted travel, and stair fallback.

## LoungeSystems: Lounge server behavior

Authoritative source: S15 / ServerScriptService.LoungeSystems

See complete listing on page src:S15.

### Proposed implementation

Keep lounge interactions isolated from laboratory scoring and navigation. Profile actual cost before deleting scenery.

### Dependencies to preserve

LoungeClient and generated lounge objects.

### Acceptance cases

Missing lounge, occupied seat, interaction range, and cleanup on departure.

## LoungeClient: Lounge presentation

Authoritative source: S28 / StarterPlayer.StarterPlayerScripts.LoungeClient

See complete listing on page src:S28.

### Proposed implementation

Add local effects through lifecycle-managed connections and restore prior camera/UI state on exit.

### Dependencies to preserve

LoungeSystems and player character lifecycle.

### Acceptance cases

Enter/exit, respawn inside, missing props, and device input.

## LabQuizClient: Quiz UI

Authoritative source: S26 / StarterPlayer.StarterPlayerScripts.LabQuizClient

See complete listing on page src:S26.

### Proposed implementation

Use an accessible modal with touch and keyboard choices and a clear timeout. Display server challenge data only.

### Dependencies to preserve

LabEquipment pendingQuizzes and MathQuizActive.

### Acceptance cases

Wrong/late/replayed reply, cancel, death, target destruction, and overlap with GWAP HUD.

## LabSidearmClient: Tool bootstrap

Authoritative source: S27 / StarterPlayer.StarterPlayerScripts.LabSidearmClient

See complete listing on page src:S27.

### Proposed implementation

Keep one controller instance per equipped original Tool and one active camera owner.

### Dependencies to preserve

BlasterController AutoBind/Enable/Disable.

### Acceptance cases

Rapid equip, respawn, backpack replacement, duplicate script prevention.

## Blaster: Shared casting

Authoritative source: S06 / ReplicatedStorage.Modules.Blaster

See complete listing on page src:S06.

### Proposed implementation

Preserve desktop screen conversion and mobile camera-forward behavior as separate tested paths.

### Dependencies to preserve

Controller reticle and server manager raycasts.

### Acceptance cases

Mouse edges, asymmetric safe areas, near wall, long range, and invalid vectors.

## BlasterController: Input/camera/pose

Authoritative source: S07 / ReplicatedStorage.Modules.BlasterController

See complete listing on page src:S07.

### Proposed implementation

Fix one measured fault at a time; retain cached base transforms and deterministic update ownership.

### Dependencies to preserve

Shared casting, Tool grip metadata, HUD rectangles, rig joints.

### Acceptance cases

Idle/walk/recoil, mouse pitch/yaw, mobile swipe, hybrid input, ADS restore, GUI click suppression.

## ServerBlasterManager: Authoritative shooting

Authoritative source: S16 / ServerScriptService.ServerBlasterManager

See complete listing on page src:S16.

### Proposed implementation

Add weapon configuration only through validated server-side attributes; keep sequence and rate limits.

### Dependencies to preserve

Blaster configuration, GWAPHitBridge, legacy impact bridge.

### Acceptance cases

Spoofed tool, out-of-order packet, impossible camera origin, wall obstruction, and correct target damage.

## GWAPWorld: Research geometry

Authoritative source: S04 / ReplicatedStorage.GWAPWorld

See complete listing on page src:S04.

### Proposed implementation

Use the captured active module, not the loose mislabeled file. Convert construction to a versioned local frame.

### Dependencies to preserve

GWAPRouting, mission approaches, roof stair geometry.

### Acceptance cases

Build twice without duplicates, translated/rotated building, all approach points, roof opening.

## GWAPScenarios: Scenario data

Authoritative source: S03 / ReplicatedStorage.GWAPScenarios

See complete listing on page src:S03.

### Proposed implementation

Give each scenario a stable ID and protocol version; decouple plot selection from array position.

### Dependencies to preserve

Server index validation, HUD job cards, station capabilities.

### Acceptance cases

Missing capability, invalid range, new eleventh entry, and unchanged old scenario IDs.

## GWAPNPC: Carrier appearance and gait

Authoritative source: S01 / ReplicatedStorage.GWAPNPC

See complete listing on page src:S01.

### Proposed implementation

Separate immutable template pose from animation state; preserve same-inventory gun models.

### Dependencies to preserve

GWAPServer template selection and movement ownership.

### Acceptance cases

Boys/girls, held seedling, gun pose, idle reset, teleport reset, pooled reactivation.

## GWAPRouting: Equivalent selection

Authoritative source: S02 / ReplicatedStorage.GWAPRouting

See complete listing on page src:S02.

### Proposed implementation

Add reachability and operational-state adapters after fixing coordinates. Use stable IDs and deterministic tie breaking.

### Dependencies to preserve

World station registry, destruction state, capacity.

### Acceptance cases

Same floor preferred, other floor fallback, all unavailable, full plots, removed fixture.

## GWAPServer: Mission orchestration

Authoritative source: S08 / ServerScriptService.GWAPServer

See complete listing on page src:S08.

### Proposed implementation

Extract mission state/reward transactions without changing existing role meanings. Introduce route revision cancellation consistently.

### Dependencies to preserve

All GWAP modules, LabRoles, Points, LabRound.

### Acceptance cases

Concurrent players, damage during processing, repeated replies, respawn, departure, and terminal reward idempotence.

## GWAPWallDamage: Wall fixture lifecycle

Authoritative source: S09 / ServerScriptService.GWAPWallDamage

See complete listing on page src:S09.

### Proposed implementation

Replace name-pattern coupling with explicit wall/fixture association when geometry is refactored. Define restoration.

### Dependencies to preserve

Legacy gas detonation, research stations, prompts and tags.

### Acceptance cases

Near/outside fixture, rotated wall, two blasts, round reset, old callback after quarantine.

## LabHUD: Grouped mission display

Authoritative source: S25 / StarterPlayer.StarterPlayerScripts.LabHUD

See complete listing on page src:S25.

### Proposed implementation

Centralize notice priority and reserved screen regions. Preserve original backpack and combat controls.

### Dependencies to preserve

GWAP attributes, original notices, quiz modal, joystick/jump bounds.

### Acceptance cases

Small portrait/landscape, long text, two-digit stages, chat open, quiz open, and keyboard/gamepad focus.

## Cross-cutting data, assets, and deployment

For persistent data, introduce a versioned server-owned schema and migrations before saving attributes. For assets, maintain IDs, provenance, scale, orientation, and fallback behavior; a visual replacement must not change a muzzle convention silently. For deployment, compare installed hashes against the chosen baseline, save/reopen, test the persistent place, and retain a rollback artifact. The geometry export cannot restore these contracts on its own.

## Complete proposed coordinate-frame module

The following module is a reference implementation, not installed or runtime-tested. It requires a deliberately placed NavigationOrigin and ApproachPoint attachments. It does not discover a valid origin automatically, reconstruct stairs, or replace pathfinding. Its edgeClear helper is a single swept query, not a complete navigator and not a test for initial overlap. Integrate it only after defining these scene objects and testing the contract.

proposed/WorldFrame.lua


<<< source chapter: chapters/inventory.tex >>>
==============================================================================
CHAPTER: Scene inventory and coordinate evidence
==============================================================================

Captured from the Edit datamodel. Counts describe tagged objects or editor inventory, not runtime performance. Place ID 137098589879404; reported place version 70; configured MaxPlayers 60. No Play mode was started for this capture.

## Laboratory equipment kinds

p0.2

Kind | Count 
 

Kind | Count 
 

Decontamination Unit | 84 

GMO Injector | 1 

Germination Chamber | 119 

Growth Hormone Mixer | 9 

Hormone Treatment Bench | 45 

Incubator | 109 

Mutagenesis Chamber | 43 

Nutrient Infuser | 1 

Plant Growth Chamber | 450 

Pollination Station | 6 

UV Growth Scanner | 5 

## Research station positions and stored approaches

Every row is a captured station. Floor is a logical index (-1 basement, 0 Level_1, 8 roof). Positions and approach points are printed to two decimals for readability; evidence/live-world-inventory.json preserves full returned precision. The mismatch is especially visible in Y and Z and is not a harmless label difference.

p0.27p0.27

Station / floor | Actual position | Stored approach 
 

Station / floor | Actual position | Stored approach 
 

Bio-analyzer / 2 | 41.86, 10.75, 140.29 | 78.00, 35.75, 49.00 

Bio-analyzer - Backup 1 / 2 | 63.86, 10.75, 140.29 | 78.00, 35.75, 49.00 

Bio-analyzer - Backup 2 / -1 | 41.86, -38.00, 255.29 | 78.00, -13.00, 164.00 

Centrifuge / 2 | 41.86, 10.75, 174.29 | 78.00, 35.75, 83.00 

Centrifuge - Backup 1 / 2 | 63.86, 10.75, 174.29 | 78.00, 35.75, 83.00 

Centrifuge - Backup 2 / -1 | 41.86, -38.00, 269.29 | 78.00, -13.00, 178.00 

Chemical seedlings / -1 | 41.86, -38.00, 157.29 | 78.00, -13.00, 66.00 

Chemical seedlings - Backup 1 / -1 | 63.86, -38.00, 157.29 | 78.00, -13.00, 66.00 

Chemical seedlings - Backup 2 / 0 | 41.86, -21.75, 255.29 | 78.00, 3.25, 164.00 

Climate chamber / 2 | 41.86, 10.75, 191.29 | 78.00, 35.75, 100.00 

Climate chamber - Backup 1 / 2 | 63.86, 10.75, 191.29 | 78.00, 35.75, 100.00 

Climate chamber - Backup 2 / -1 | 41.86, -38.00, 283.29 | 78.00, -13.00, 192.00 

Clinostat / -1 | 41.86, -38.00, 174.29 | 78.00, -13.00, 83.00 

Clinostat - Backup 1 / -1 | 63.86, -38.00, 174.29 | 78.00, -13.00, 83.00 

Clinostat - Backup 2 / 0 | 41.86, -21.75, 269.29 | 78.00, 3.25, 178.00 

Containment / 1 | 41.86, -5.50, 140.29 | 78.00, 19.50, 49.00 

Containment - Backup 1 / 1 | 63.86, -5.50, 140.29 | 78.00, 19.50, 49.00 

Containment - Backup 2 / 2 | 41.86, 10.75, 255.29 | 78.00, 35.75, 164.00 

Cryo-freezer / -1 | 41.86, -38.00, 208.29 | 78.00, -13.00, 117.00 

Cryo-freezer - Backup 1 / -1 | 63.86, -38.00, 208.29 | 78.00, -13.00, 117.00 

Cryo-freezer - Backup 2 / 0 | 41.86, -21.75, 283.29 | 78.00, 3.25, 192.00 

Incubator / 0 | 41.86, -21.75, 140.29 | 78.00, 3.25, 49.00 

Incubator - Backup 1 / 0 | 63.86, -21.75, 140.29 | 78.00, 3.25, 49.00 

Incubator - Backup 2 / 1 | 41.86, -5.50, 255.29 | 78.00, 19.50, 164.00 

Infrared scanner / 2 | 41.86, 10.75, 157.29 | 78.00, 35.75, 66.00 

Infrared scanner - Backup 1 / 2 | 63.86, 10.75, 157.29 | 78.00, 35.75, 66.00 

Infrared scanner - Backup 2 / -1 | 41.86, -38.00, 297.29 | 78.00, -13.00, 206.00 

Orientation scanner / 0 | 41.86, -21.75, 174.29 | 78.00, 3.25, 83.00 

Orientation scanner - Backup 1 / 0 | 63.86, -21.75, 174.29 | 78.00, 3.25, 83.00 

Orientation scanner - Backup 2 / 1 | 41.86, -5.50, 269.29 | 78.00, 19.50, 178.00 

Plot 1 / 8 | 22.86, 107.55, 139.29 | 78.00, 133.60, 48.00 

Plot 10 / 8 | 82.86, 107.55, 219.29 | 78.00, 133.60, 128.00 

Plot 2 / 8 | 82.86, 107.55, 139.29 | 78.00, 133.60, 48.00 

Plot 3 / 8 | 22.86, 107.55, 159.29 | 78.00, 133.60, 68.00 

Plot 4 / 8 | 82.86, 107.55, 159.29 | 78.00, 133.60, 68.00 

Plot 5 / 8 | 22.86, 107.55, 179.29 | 78.00, 133.60, 88.00 

Plot 6 / 8 | 82.86, 107.55, 179.29 | 78.00, 133.60, 88.00 

Plot 7 / 8 | 22.86, 107.55, 199.29 | 78.00, 133.60, 108.00 

Plot 8 / 8 | 82.86, 107.55, 199.29 | 78.00, 133.60, 108.00 

Plot 9 / 8 | 22.86, 107.55, 219.29 | 78.00, 133.60, 128.00 

Porometer / 1 | 41.86, -5.50, 208.29 | 78.00, 19.50, 117.00 

Porometer - Backup 1 / 1 | 63.86, -5.50, 208.29 | 78.00, 19.50, 117.00 

Porometer - Backup 2 / 2 | 41.86, 10.75, 269.29 | 78.00, 35.75, 178.00 

Root analyzer / 1 | 41.86, -5.50, 174.29 | 78.00, 19.50, 83.00 

Root analyzer - Backup 1 / 1 | 63.86, -5.50, 174.29 | 78.00, 19.50, 83.00 

Root analyzer - Backup 2 / 2 | 41.86, 10.75, 283.29 | 78.00, 35.75, 192.00 

Seed bank / -1 | 41.86, -38.00, 140.29 | 78.00, -13.00, 49.00 

Seed bank - Backup 1 / -1 | 63.86, -38.00, 140.29 | 78.00, -13.00, 49.00 

Seed bank - Backup 2 / 0 | 41.86, -21.75, 297.29 | 78.00, 3.25, 206.00 

Spectrograph / 1 | 41.86, -5.50, 157.29 | 78.00, 19.50, 66.00 

Spectrograph - Backup 1 / 1 | 63.86, -5.50, 157.29 | 78.00, 19.50, 66.00 

Spectrograph - Backup 2 / 2 | 41.86, 10.75, 297.29 | 78.00, 35.75, 206.00 

Split-root tray / 0 | 41.86, -21.75, 157.29 | 78.00, 3.25, 66.00 

Split-root tray - Backup 1 / 0 | 63.86, -21.75, 157.29 | 78.00, 3.25, 66.00 

Split-root tray - Backup 2 / 1 | 41.86, -5.50, 283.29 | 78.00, 19.50, 192.00 

Symbiosis incubator / 1 | 41.86, -5.50, 225.29 | 78.00, 19.50, 134.00 

Symbiosis incubator - Backup 1 / 1 | 63.86, -5.50, 225.29 | 78.00, 19.50, 134.00 

Symbiosis incubator - Backup 2 / 2 | 41.86, 10.75, 311.29 | 78.00, 35.75, 220.00 

UV chamber / 1 | 41.86, -5.50, 191.29 | 78.00, 19.50, 100.00 

UV chamber - Backup 1 / 1 | 63.86, -5.50, 191.29 | 78.00, 19.50, 100.00 

UV chamber - Backup 2 / 2 | 41.86, 10.75, 325.29 | 78.00, 35.75, 234.00 

Vitality scanner / 0 | 41.86, -21.75, 191.29 | 78.00, 3.25, 100.00 

Vitality scanner - Backup 1 / 0 | 63.86, -21.75, 191.29 | 78.00, 3.25, 100.00 

Vitality scanner - Backup 2 / 1 | 41.86, -5.50, 297.29 | 78.00, 19.50, 206.00 

Wet lab / -1 | 41.86, -38.00, 191.29 | 78.00, -13.00, 100.00 

Wet lab - Backup 1 / -1 | 63.86, -38.00, 191.29 | 78.00, -13.00, 100.00 

Wet lab - Backup 2 / 0 | 41.86, -21.75, 311.29 | 78.00, 3.25, 220.00 

## Important tag counts

p0.2

Tag | Count 
 

Tag | Count 
 

AutoDoor | 162 

Automatable | 313 

EmergencyKit | 116 

GasPipe | 18 

LabBreakableWindow | 130 

LabDecor | 14 

LabEquipment | 872 

LabPoster | 72 

LabToolDispenser | 90 

LabWorkerBot | 180 

PlantGrowthChamber | 450 

RoleKiosk | 2 

RoomMonitor | 81 

SecretBasementPanel | 1 

## Latest exported files

The export manifest contains 46 files totaling 197,533,070 bytes. The RBXL copy is included; OBJ/MTL and textures remain at D:/game/5 and are identified by SHA-256 in the manifest.

p0.2

Relative export file | Bytes 
 

Relative export file | Bytes 
 

obj\Casterwheel1_diff.png | 3,268 

obj\Casterwheel1_nmap.png | 1,398 

obj\Casterwheel1_spec.png | 224 

obj\Corridoreast71_diff.png | 784,015 

obj\Corridoreast71_nmap.png | 2,002,950 

obj\Corridoreast71_spec.png | 1,885 

obj\Flag1_diff.png | 9,168 

obj\Flag1_nmap.png | 21,313 

obj\Flag1_spec.png | 407 

obj\Floor1_diff.png | 6,199 

obj\Floor1_nmap.png | 6,143 

obj\Floor1_spec.png | 1,885 

obj\Head2_diff.png | 1,053 

obj\LaboratoryTechnicianpanelframe1_diff.png | 16,189 

obj\LaboratoryTechnicianpanelframe1_nmap.png | 23,842 

obj\LaboratoryTechnicianpanelframe1_spec.png | 871 

obj\Loungehatch1_nmap.png | 4,522 

obj\Loungehatch1_spec.png | 223 

obj\obj.mtl | 105,560 

obj\obj.obj | 193,872,256 

obj\Roof11_diff.png | 10,348 

obj\Roof11_nmap.png | 15,663 

obj\Roof11_spec.png | 1,885 

obj\Sitepad81_diff.png | 2,356 

obj\Sitepad81_nmap.png | 2,007 

obj\Sitepad81_spec.png | 1,885 

obj\Soil1_diff.png | 2,096 

obj\Soil1_nmap.png | 1,938 

obj\Soil1_spec.png | 1,885 

obj\Spawnlocation1_diff.png | 33,475 

obj\Spawnlocation1_nmap.png | 46,508 

obj\Spawnlocation2_diff.png | 1,322 

obj\Tree3trunk1_diff.png | 4,234 

obj\Tree3trunk1_nmap.png | 936 

obj\Tree3trunk1_spec.png | 1,885 

obj\Tsouthglass31_diff.png | 17,625 

obj\Tsouthglass31_nmap.png | 1,512 

obj\Tsouthglass31_spec.png | 120 

obj\Walle1_diff.png | 2,409 

obj\Walle1_nmap.png | 1,767 

obj\Walle1_spec.png | 120 

obj\West2_diff.png | 900 

obj\Workerbot04desktop1_diff.png | 19,051 

obj\Workerbot04desktop1_nmap.png | 5,889 

obj\Workerbot04desktop1_spec.png | 407 

rblx\rbxl.rbxl | 491,476 

## Coordinate repair decision

Do not automatically translate the laboratory back by the measured offset. The current position may be intentional. First establish the desired world placement with the owner or scene baseline, then make navigation metadata follow that placement. The safer architecture uses local coordinates and moving attachments so subsequent translations do not repeat this defect.


<<< source chapter: chapters/provenance.tex >>>
==============================================================================
CHAPTER: Source provenance and complete-code map
==============================================================================

The complete final active sources are printed in full, together with the server-only documentation module, eight Studio archive sources, one disabled generator, and 12 historical workspace artifacts. The pre-revision active sources remain in code/baseline for exact comparison. The printed appendices deliberately retain duplicate and conflicting versions so the history is inspectable; they are grouped by authority. Each listing restarts line numbering at one. The source ZIP contains byte-preserved originals. Proposed code is kept separately and never labeled active.

The complete latest place is supplied as evidence/export-5.rbxl. Geometry meshes and textures are not Lua code and are listed separately. Unrelated downloaded script repositories are not included as active game source. No implementation is shortened with ellipses or pseudocode inside a captured listing.

p0.67p0.18

ID | Artifact | Lines / bytes 
 

ID | Artifact | Lines / bytes 
 

S01 | ReplicatedStorage.GWAPNPC | 96 / 6183 

S02 | ReplicatedStorage.GWAPRouting | 55 / 3434 

S03 | ReplicatedStorage.GWAPScenarios | 23 / 2692 

S04 | ReplicatedStorage.GWAPWorld | 95 / 7198 

S05 | ReplicatedStorage.LabKinds | 173 / 10408 

S06 | ReplicatedStorage.Modules.Blaster | 239 / 9143 

S07 | ReplicatedStorage.Modules.BlasterController | 915 / 35949 

S08 | ServerScriptService.GWAPServer | 469 / 32199 

S09 | ServerScriptService.GWAPWallDamage | 55 / 3254 

S10 | ServerScriptService.LabElevators | 132 / 4405 

S11 | ServerScriptService.LabEquipment | 4178 / 182838 

S12 | ServerScriptService.LabRoles | 431 / 19385 

S13 | ServerScriptService.LabRound | 94 / 3591 

S14 | ServerScriptService.LabTechnicians | 210 / 7915 

S15 | ServerScriptService.LoungeSystems | 172 / 5872 

S16 | ServerScriptService.ServerBlasterManager | 195 / 8483 

S17 | ServerStorage.BeforeBasementAndQuiz_20260912.LabElevators | 123 / 3761 

S18 | ServerStorage.BeforeBasementAndQuiz_20260912.LabEquipment | 4068 / 175504 

S19 | ServerStorage.BeforeBasementAndQuiz_20260912.LabRoles | 422 / 18757 

S20 | ServerStorage.BeforeBasementAndQuiz_20260912.LabRound | 85 / 2954 

S21 | ServerStorage.BeforeBasementAndQuiz_20260912.LabTechnicians | 201 / 7271 

S22 | ServerStorage.BeforeBasementAndQuiz_20260912.LoungeSystems | 152 / 4605 

S23 | ServerStorage.BeforeBasementAndQuiz_20260912.ServerBlasterManager | 175 / 7275 

S24 | ServerStorage.BlasterController_BeforeMouseArmFix_20260912 | 730 / 26610 

S25 | StarterPlayer.StarterPlayerScripts.LabHUD | 140 / 12852 

S26 | StarterPlayer.StarterPlayerScripts.LabQuizClient | 138 / 5319 

S27 | StarterPlayer.StarterPlayerScripts.LabSidearmClient | 54 / 2409 

S28 | StarterPlayer.StarterPlayerScripts.LoungeClient | 85 / 3247 

S29 | Workspace.SeedLabGenerator_DISABLED_doNotEnable | 11886 / 524207 

W01 | SeedLabGenerator.lua | 12398 / 552155 

W02 | InstallGWAP.lua | 2109 / 115778 

W03 | GWAPWorld.lua | 259 / 17807 

W04 | GWAPScenarios.lua | 13 / 2067 

W05 | GWAPNPC.lua | 90 / 6021 

W06 | GWAPRouting.lua | 43 / 2594 

W07 | GWAPServer.lua | 418 / 28562 

W08 | GWAPWallDamage.lua | 45 / 2594 

W09 | GWAPHUD.lua | 123 / 11596 

W10 | Blaster.lua | 227 / 8432 

W11 | BlasterController.lua | 905 / 35188 

W12 | ServerBlasterManager.lua | 184 / 7714 

S21 | ReplicatedStorage.LabSpatial | 39 / 1994 

DOC01 | ServerStorage.GameDocumentation | 827 / 120178 

DOC02 | ServerStorage.GameDocumentationAnnex2 | 2159 / 107451 

## Hash verification

### S01 GWAPNPC

Group: active; file: code/active/ReplicatedStorage.GWAPNPC.lua

 c9698d535e3d7947acf208b4f8ee49f2ad08c853badfd573fa7173a1435f5d15

### S02 GWAPRouting

Group: active; file: code/active/ReplicatedStorage.GWAPRouting.lua

 f29a41157ff14934f5a25ac7e9e065450f3a32dc13c868a57378e5d73e80e8ee

### S03 GWAPScenarios

Group: active; file: code/active/ReplicatedStorage.GWAPScenarios.lua

 6a6d613711d1cd7762fc1140ef53c6c3ff25d1e5faea06538d32f8aa79452796

### S04 GWAPWorld

Group: active; file: code/active/ReplicatedStorage.GWAPWorld.lua

 2b7829521e74564f068cb147223e063e5b680cf3cd44f87e128b357d607cf19c

### S05 LabKinds

Group: active; file: code/active/ReplicatedStorage.LabKinds.lua

 eb2dbeb766efed328eb3e1165c9b41e93546c3fa49615fdbc00646d43aa9dea2

### S06 Blaster

Group: active; file: code/active/ReplicatedStorage.Modules.Blaster.lua

 616d0fc7234636c563afbc93798f81e1be3a9fbc83084de44196f4d0ed8be2ab

### S07 BlasterController

Group: active; file: code/active/ReplicatedStorage.Modules.BlasterController.lua

 ef4a80c0aa4c3a1ded46c55bef82d058ddb29bb83dd8f34cfa73d22c9647769d

### S08 GWAPServer

Group: active; file: code/active/ServerScriptService.GWAPServer.lua

 265a4f246bfd1c1b107cc4ae2df6cf8babde7c682de18838cfba553c55c7c653

### S09 GWAPWallDamage

Group: active; file: code/active/ServerScriptService.GWAPWallDamage.lua

 92a3df3c35188633291afa9388a99db7ed9791f34c1ef14a299301c46a96f952

### S10 LabElevators

Group: active; file: code/active/ServerScriptService.LabElevators.lua

 d5c42a7d4217033660c71b966b4d762409572f63640db28769f0ccf3bb32ae44

### S11 LabEquipment

Group: active; file: code/active/ServerScriptService.LabEquipment.lua

 eb4722cec0bddcf396cb9dce7199a4b11dc3890fc157367daa219c1489fdae5f

### S12 LabRoles

Group: active; file: code/active/ServerScriptService.LabRoles.lua

 7e706724edacbda6ccd335320891a5c8652a016640abe3e7fda6754203a39a77

### S13 LabRound

Group: active; file: code/active/ServerScriptService.LabRound.lua

 ed2bd7811d3301d2afc164a9b6bd3c603b1758e760a8c5b4b31006c064946244

### S14 LabTechnicians

Group: active; file: code/active/ServerScriptService.LabTechnicians.lua

 cf7bd8c892576d90388829db70c3a77c9d7519807ab7785940dc472af7f0da85

### S15 LoungeSystems

Group: active; file: code/active/ServerScriptService.LoungeSystems.lua

 78327a7e0eb4d5ce209c2b9d0a504708d378917a727d0ce530f144d84e1c2b42

### S16 ServerBlasterManager

Group: active; file: code/active/ServerScriptService.ServerBlasterManager.lua

 50671031f74ebbffede5259e3447b34087fc2a47387ffb378de169616a1be522

### S17 LabElevators

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabElevators.lua

 62b29049771761ea23fcf71ce84e715ea44f0945e4e3f81a078167d37b15f448

### S18 LabEquipment

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabEquipment.lua

 d7ffee0ffe6bf5f1a3d4f1086a5569adb7aad76c3dc66d5cdeed5959cf9b4d08

### S19 LabRoles

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabRoles.lua

 9b4d4429d279f97793519a441fd8c4f4d6f7e6af9c934e270aedb56305fc62dd

### S20 LabRound

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabRound.lua

 9ef5725f5f034aec29be6daaf9864ad6ce2e08c3f854e61c035ba286c197a5c1

### S21 LabTechnicians

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LabTechnicians.lua

 5c9a649cef010ed65b142db221fd92830593c0ee8c4281f5c8606b8ede66f01c

### S22 LoungeSystems

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.LoungeSystems.lua

 72f8a9e545a7818dc813e749aaabea27d3de773599005f2cf5ac6690e6b24615

### S23 ServerBlasterManager

Group: archive; file: code/archive/ServerStorage.BeforeBasementAndQuiz_20260912.ServerBlasterManager.lua

 e38caa71d7c2f94536a0f0273248d77bc6a5df585d480bb693f1e41f58c4d74a

### S24 BlasterController_BeforeMouseArmFix_20260912

Group: archive; file: code/archive/ServerStorage.BlasterController_BeforeMouseArmFix_20260912.lua

 8a756113e948711c647a10a790ec624081297515dc3ef9504c03dcaf692135e8

### S25 LabHUD

Group: active; file: code/active/StarterPlayer.StarterPlayerScripts.LabHUD.lua

 d8982e721a569a2eaa70a0f73fd7106e78cf19f39b056a76ced59329602f8a0a

### S26 LabQuizClient

Group: active; file: code/active/StarterPlayer.StarterPlayerScripts.LabQuizClient.lua

 316259614108e07c7273dd92fe632343fb797c988877cf71694726e59380fc57

### S27 LabSidearmClient

Group: active; file: code/active/StarterPlayer.StarterPlayerScripts.LabSidearmClient.lua

 a2e10adb43696aefe2a6fa8d7aa8570d5a64d09d9cae9f32398ce6e944b52843

### S28 LoungeClient

Group: active; file: code/active/StarterPlayer.StarterPlayerScripts.LoungeClient.lua

 eb857c214587168a13cd60243327a4b8588fdfe48a3947d20c1501393bf6bc45

### S29 SeedLabGenerator_DISABLED_doNotEnable

Group: disabled; file: code/disabled/Workspace.SeedLabGenerator_DISABLED_doNotEnable.lua

 dc633d385d37c97f171de5725a0523f12beaa19df26006138968f14f5a545e5d

### W01 lua

Group: workspace; file: code/workspace/SeedLabGenerator.lua

 219d03a12736586ae1fbe39cc89c7612f9134819807d0ecc60450bbb487f55af

### W02 lua

Group: workspace; file: code/workspace/InstallGWAP.lua

 06e6d896bb0fe9fdf14c04ac0810c10f79219372831abb352a3f08982bdca511

### W03 lua

Group: workspace; file: code/workspace/GWAPWorld.lua

 1745af08772025f20c0fea0e44532d25244454346e7cd6b2f22d0b41dd09e7c5

### W04 lua

Group: workspace; file: code/workspace/GWAPScenarios.lua

 d27afc6b0edf955031d55ec0f910394c2d98ede64daeed7b7bc27ae634442136

### W05 lua

Group: workspace; file: code/workspace/GWAPNPC.lua

 77bd356a1d0fbff2b71c3ec24eaecf99565a6304b6f1e478d1b257b89007ed05

### W06 lua

Group: workspace; file: code/workspace/GWAPRouting.lua

 b41a223e553d10f13e0d6a79c3ef2b616e4cc0d43cfc986aa75c84e3af6186ca

### W07 lua

Group: workspace; file: code/workspace/GWAPServer.lua

 3546a88f457530f2e6a7efb7ebea5ad3f4bfda3502b3b97a6368750517fe8693

### W08 lua

Group: workspace; file: code/workspace/GWAPWallDamage.lua

 cae9ce8d81cdd3261702f39670c8bf456628f065c3454c638757d3d61d4e577b

### W09 lua

Group: workspace; file: code/workspace/GWAPHUD.lua

 20b2619e281c1608e9c543ec522e7c8e51a9e1c69eb0e73d4d9cc54105aa6ebd

### W10 lua

Group: workspace; file: code/workspace/Blaster.lua

 01c2f0f4432c5673e1bb39cd3ced41e9a984c476a31755010bf1ad207567809c

### W11 lua

Group: workspace; file: code/workspace/BlasterController.lua

 4dc3893c33e70e7e9a39194b52bb937fd3086f212efeadc371f73c71e453fcea

### W12 lua

Group: workspace; file: code/workspace/ServerBlasterManager.lua

 6f5301dddadf2663b5f910ac85fdc691c6a9c23e77aab31947625053d402d449

### S21 LabSpatial

Group: active; file: code/active/ReplicatedStorage.LabSpatial.lua

 1593b910e0f231f347b2fec79a28c1a3da1c7aca53c273d968ab44f7dec6df5f

### DOC01 GameDocumentation

Group: documentation; file: code/documentation/ServerStorage.GameDocumentation.lua

 c8cdc2005e233b55a583bb47e5baf3f3994ed4234134370d8fa1a6157a8884b9

### DOC02 GameDocumentationAnnex2

Group: documentation; file: code/documentation/ServerStorage.GameDocumentationAnnex2.lua

 c29a83b5a539cd778db9899424d50426c1cc4b44c7c3a10191d246c31a98f3c1

## Normalized workspace comparisons

p0.1p0.43

Workspace file | Live ID | Comparison 
 

Workspace file | Live ID | Comparison 
 

GWAPWorld.lua | S04 | DIFFERENT - inspect before installation 

GWAPScenarios.lua | S03 | DIFFERENT - inspect before installation 

GWAPNPC.lua | S01 | DIFFERENT - inspect before installation 

GWAPRouting.lua | S02 | DIFFERENT - inspect before installation 

GWAPServer.lua | S08 | DIFFERENT - inspect before installation 

GWAPWallDamage.lua | S09 | DIFFERENT - inspect before installation 

GWAPHUD.lua | S25 | DIFFERENT - inspect before installation 

Blaster.lua | S06 | DIFFERENT - inspect before installation 

BlasterController.lua | S07 | DIFFERENT - inspect before installation 

ServerBlasterManager.lua | S16 | DIFFERENT - inspect before installation 

This comparison ignores UTF-8 BOM, line-ending normalization by text reading, and trailing newlines only. The raw hashes remain different when bytes differ. A normalized match is not a gameplay test. The installer contains the incorrect loose GWAPWorld source in its world-module block; it must not be run unchanged. The active module is the documentary source for a future repair.


<<< source chapter: chapters/symbol-index.tex >>>
==============================================================================
CHAPTER: Active-code symbol and attribute index
==============================================================================

This index is generated from source text to help locate implementation. Line numbers refer to the complete listings and raw files. Regex extraction may omit anonymous functions, multiline definitions, dynamic attribute names, or accesses assembled at runtime. It is a navigation aid, not an exhaustive static type analysis.

## S01 GWAPNPC

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

18 | N.gun 

28 | N.appearance 

33 | piece 

41 | N.say 

49 | N.nearPlayer 

66 | N.animate 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Gender | 29 

HasSeedling | 89 

InventoryName | 25 

MissionMessage | 45 

MissionMessageAt | 46 

NPCGun | 25 

## S02 GWAPRouting

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

13 | floorOf 

18 | R.healthy 

21 | R.ensureBackups 

47 | R.choose 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Backup | 25, 31 

BlastRemoved | 19 

Capability | 27, 31, 49 

Exploded | 19, 38 

Floor | 14, 37 

FunctionalState | 19, 38 

Level | 15 

Planted | 26, 49 

## S03 GWAPScenarios

## S04 GWAPWorld

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

14 | part 

19 | label 

23 | W.plant 

31 | W.build 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

Approach | 46, 85 

Floor | 46, 85 

GWAPOriginalCanCollide | 60, 65 

Planted | 85 

## S05 LabKinds

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

28 | f 

29 | rnd 

33 | log 

35 | log 

37 | log 

39 | log 

42 | log 

44 | log 

48 | log 

50 | log 

53 | log 

56 | log 

59 | log 

62 | log 

64 | log 

67 | log 

72 | log 

74 | log 

76 | log 

78 | log 

80 | log 

83 | log 

85 | log 

88 | log 

90 | log 

92 | log 

94 | log 

96 | log 

98 | log 

100 | log 

102 | log 

104 | log 

106 | log 

108 | log 

110 | log 

112 | log 

116 | log 

119 | log 

122 | log 

124 | log 

126 | log 

128 | log 

130 | log 

132 | log 

134 | log 

136 | log 

138 | log 

140 | log 

149 | log 

151 | log 

161 | log 

163 | log 

165 | log 

169 | log 

171 | K.forKind 

## S06 Blaster

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

27 | finiteNumber 

34 | Blaster.IsFiniteVector 

41 | numberAttribute 

47 | Blaster.GetWeaponConfig 

62 | Blaster.GetCameraRay 

83 | Blaster.NewRaycastParams 

91 | Blaster.CastFromCamera 

107 | Blaster.GetAimSolution 

137 | tracerColor 

142 | Blaster.DrawTracer 

163 | Blaster.DrawImpact 

182 | getRemotes 

190 | Blaster.StartReplication 

206 | Blaster.Fire 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BlasterAllowPlayerDamage | 58 

BlasterAutomatic | 56 

BlasterInstantHeadshot | 57 

BlasterTracerColor | 138 

## S07 BlasterController

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

33 | touchControlsActive 

59 | pointInside 

68 | touchAimActive 

82 | rotationBetween 

93 | makeCrosshair 

165 | BlasterController:_ensureHUD 

176 | BlasterController.new 

232 | BlasterController:_button 

239 | BlasterController:_fallbackTouchButton 

281 | BlasterController:_styleTouchButtons 

337 | place 

351 | BlasterController:_getAimScreenPoint 

372 | BlasterController:_updateAimReticle 

414 | BlasterController:_setLocalHeadHidden 

434 | BlasterController:_beginTouchCamera 

451 | BlasterController:_endTouchCamera 

463 | BlasterController:SetAiming 

505 | BlasterController:_fireOnce 

520 | BlasterController:_beginFiring 

536 | BlasterController:_shootAction 

561 | BlasterController:_aimAction 

576 | BlasterController:_touchPanAction 

623 | BlasterController:_updateArmPose 

685 | BlasterController:_render 

737 | BlasterController:Enable 

821 | BlasterController:Disable 

865 | BlasterController:Destroy 

875 | BlasterController.BindTool 

883 | BlasterController.GetController 

887 | BlasterController.AutoBind 

890 | consider 

896 | watch 

907 | binder:Destroy 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BlasterADSTouchSensitivity | 607 

BlasterBarrelDirection | 661 

BlasterHipFOV | 746 

BlasterHipTouchSensitivity | 608 

BlasterShoulderOffsetX | 758 

BlasterShoulderOffsetY | 759 

BlasterWeapon | 891 

LabSidearm | 664, 891 

## S08 GWAPServer

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

20 | refreshArmed 

37 | alive 

40 | points 

43 | award 

47 | role 

48 | active 

49 | nearby 

50 | publish 

56 | tell 

60 | finish 

67 | updateHealth 

75 | damage 

89 | remember 

95 | repair 

102 | explode 

147 | bridge.OnInvoke 

152 | routePoints 

153 | add 

159 | flight 

172 | showRoute 

177 | go 

248 | plantIn 

258 | checkpoint 

263 | runMission 

312 | startMission 

321 | makeBot 

337 | companion 

349 | choose 

385 | setArmed 

406 | watchPlayer 

407 | clean 

408 | watch 

410 | onCharacter 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BlastRemoved | 123, 138 

BotNumber | 399 

Capability | 30, 268, 272 

CarriedSample | 382 

Dead | 331, 389, 429, 439 

DisplayName | 58, 345 

Exploded | 96, 103, 104, 123, 138, 142, 249 

Floor | 156 

FunctionalState | 96, 104 

GWAPArmed | 390, 397 

GWAPArmedCount | 402 

GWAPAttacker | 109, 135 

GWAPBotCount | 402 

GWAPCarrier | 331, 345, 356 

GWAPDialogue | 58, 344, 345 

GWAPEquipment | 92 

GWAPFractionalLoss | 453, 454, 464 

GWAPHitAt | 455 

GWAPNotice | 45, 78, 129, 351, 352, 355, 356, 381, 382, 455 

GWAPScenario | 356 

GWAPSpeaker | 58, 345 

GWAPStage | 52 

GWAPState | 53 

GWAPTarget | 53 

GWAPTargetFloor | 53 

GWAPTotalStages | 52 

GWAPVariant | 356 

GWAPWeapon | 407 

Gender | 324 

HasSeedling | 62, 305 

Health | 69, 77, 316, 389, 429, 430, 439 

KnockedOut | 331, 389, 429, 439 

LabRole | 47, 417 

LastPointAmount | 45 

LastPointAward | 45 

PlantSample | 380 

Planted | 250, 253, 466 

Reroutes | 281 

RoundNumber | 462 

RoundPhase | 350, 436 

RouteIndex | 202 

Scenario | 316 

Seated | 324 

State | 48, 53, 62, 316, 336 

TaskState | 62, 285, 294 

Title | 71, 316 

TransferSample | 380 

Variant | 316 

WalkSpeed | 219 

## S09 GWAPWallDamage

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

16 | register 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

BlastRemoved | 47 

Exploded | 47 

FunctionalState | 47 

GWAPEquipment | 19 

GWAPRemovedFixtures | 53 

ShootablePoster | 18 

ToolKind | 18 

## S10 LabElevators

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

21 | setGate 

26 | setup 

55 | occupants 

73 | moveTo 

109 | addPrompt 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

CurrentFloor | 104 

Floor | 41, 121, 124 

FloorCount | 27 

FloorLabel_ | 125 

FloorY_ | 45 

## S11 LabEquipment

### Named functions / assigned handlers

p0.8

Line | Symbol 
 

Line | Symbol 
 

53 | updateScoreboard 

73 | refreshRoomMonitors 

105 | addContribution 

112 | notify 

167 | playerRole 

176 | awardPoints 

198 | canInteract 

227 | runMathQuiz 

268 | addWeldedPart 

290 | equipTool 

299 | makeTool 

406 | updateLifeBar 

427 | playerContainers 

435 | findTool 

449 | findTransferSample 

460 | findHeldSample 

478 | findPlantSample 

487 | treatmentText 

493 | hasTreatment 

498 | addTreatment 

505 | refreshPlantVisual 

530 | setCarryState 

550 | destroyCarriedItem 

605 | refreshBotHealth 

625 | damageWorkerBot 

714 | equipmentFromHit 

728 | explodeEquipment 

781 | detonateGasPipe 

880 | spawnImpact 

921 | punchPoster 

945 | workerBotFromHit 

950 | stealHeldSample 

974 | armImpactTool 

1088 | findImpactTool 

1099 | makeImpactTool 

1193 | bindDispenser 

1342 | blasterBridge.OnInvoke 

1399 | equipmentFloorLabel 

1403 | equipmentId 

1409 | equipmentLabel 

1415 | adaptiveTransferSeconds 

1477 | storageId 

1486 | storageLabel 

1492 | coldStoresExcept 

1506 | makeControls 

1604 | clockText 

1608 | renderTimer 

1709 | setReadout 

1715 | pressButton 

1731 | runProgress 

1743 | chamberSampleList 

1749 | saveChamberSamples 

1758 | formatRuntime 

1763 | recoverPlantLife 

1793 | updateStoredSamples 

1806 | refreshChamberTelemetry 

1843 | evacuationDestinations 

1864 | repairPathFolder 

1883 | clearRepairPath 

1888 | repairReward 

1895 | createRepairPath 

1902 | approachPoint 

1910 | appendNavigable 

2007 | clearAssignment 

2014 | assignNextTask 

2091 | chamberByCode 

2097 | takePlantFromChamber 

2138 | canFinishTaking 

2211 | storePlantInChamber 

2286 | handleGrowthChamber 

2326 | germinationPercent 

2332 | processPlant 

2452 | createTransferSample 

2502 | handleColdStore 

2527 | startCycleIndicator 

2567 | bind 

2659 | canFinishRepair 

2810 | setBotStatus 

2818 | updateBotTestBoard 

2846 | interactionPoint 

2892 | roomAt 

2907 | roomRect 

2914 | botHasObserver 

2935 | botMotionChecks 

2951 | clear 

2979 | grounded 

2989 | walkBotSegment 

3038 | moveBotTo 

3059 | makeBotPlant 

3066 | piece 

3087 | equipmentReadout 

3095 | candidatesOnLevel 

3105 | runBotScenario 

3264 | setChamberFailure 

3315 | setGenericFailure 

3348 | shuffled 

3356 | adaptiveFailureTick 

3441 | genericFailureTick 

3465 | bindPlayerTaskRouting 

3496 | bindAutoDoor 

3507 | setIndicatorColour 

3516 | setOpen 

3574 | bindEmergencyKit 

3591 | setCharged 

3620 | attachPlayerHealthBar 

3658 | refresh 

3671 | watchPlayerHealth 

3683 | bindSecretBasementPanel 

3720 | nearestEmergencyKit 

3802 | scatterDebris 

3827 | warnEquipmentCatastrophe 

3862 | destroyEquipment 

4010 | resetHunt 

4046 | clearRoomSmoke 

4056 | fillRoomWithSmoke 

4087 | ventFromDoor 

4101 | watchDoor 

4152 | bindNPC 

### Literal attribute keys and access lines

p0.47

Attribute | Lines 
 

Attribute | Lines 
 

AboutToBlow | 3828, 3829, 3868 

ActiveNPCWorkers | 3434 

ActiveNPCWorkersPerFloor | 3437 

ActivePlayerCount | 3433 

AdaptiveFailureTargetPercent | 3428 

AssignedRepairDistance | 1890, 2039 

AssignedRepairId | 2037, 2671, 3285, 3332, 3474, 3741 

AssignedRepairProjectedPoints | 2041 

AssignedTransferDeadline | 2074, 2197, 2198, 2235 

AssignedTransferDestination | 2073, 2110, 2196, 2234 

AssignedTransferSource | 2072, 2109, 2195, 2233, 3286, 3741 

Auto | 2528 

AvoidanceDetours | 3010 

BlasterADSFOV | 1130 

BlasterADSTouchSensitivity | 1131 

BlasterAutomatic | 1129 

BlasterCooldown | 1124 

BlasterDamage | 1122 

BlasterInstantHeadshot | 1128 

BlasterPellets | 1125 

BlasterRange | 1123 

BlasterSelfCostPercent | 1127 

BlasterSpread | 1126 

BlasterTracerColor | 1132 

BlasterWeapon | 1121 

Blown | 782, 783 

BotNumber | 3005, 3203, 3991 

BotTestUses | 3207 

BotsKilled | 707, 1324, 1363, 4015 


]========]
return {revision=5,part=1,parts=2,reference="Server-only written reference; never required by gameplay"}
