# Revision 5 — record

Place: `Genrmination_Fight` (placeId 137098589879404), live baseline version 77.
Source of truth for geometry: `D:\game\4\Export.gltf`, exported 11 Sep 22:44, i.e.
before Revision 4.

---

## 1. Diagnosis

Revision 4 concluded that `Laboratory_Complex` had moved and that the Lounge
should follow it. It inferred the vector `(-25.142857, -23.25, +91.285714)` and
applied it to the Lounge and LoungeHatch (169 parts).

The vector was right. The object was wrong.

Authored positions, read from the glTF node translations:

| node | authored | live before repair |
|---|---|---|
| `Laboratory_Complex/Roof_1` | 82.2857, 129.375, 133.7143 | 57.1429, 106.125, 225.0000 |
| `LoungeHatch` | 110, −15.9, 130 | 84.857, −39.150, 221.286 |
| `HatchRim` | 110, −16, 130 | 110, −16, 130 |
| `Lounge/Floor` | 80, −49, 130 | 80, −72.25, 221.286 |
| `Lounge/Ceiling` | 80, −30, 130 | 80, −53.25, 221.286 |
| `LabSpawn` | 32.143, 1, 11.571 | 32.143, −0.1, 11.571 |

`HatchRim`, the three spawns and `LaboratoryFoundationGround` had **not** moved.
Only `Laboratory_Complex` had. The ground plane stayed at y = −8 while the first
floor sank to −23.25, so the ground sat **15.25 studs above the first floor** and
intersected Levels 1–2. That is the reported gap.

Revision 4's partial migration made it worse: the Lounge followed the building,
but the hatch's own rim did not, so the hatch and its rim ended up 95 studs apart.

`LabSpatial`'s `BASE_ROOF` constant, `CFrame.new(82.28571428571429, 129.375,
133.71428571428572)`, is exactly the authored roof position — further confirmation
that the authored frame, not the displaced one, is correct.

## 2. Repair

Two rigid moves, nothing else touched:

1. `Lounge` + `LoungeHatch` — 169 parts — by `(+25.142857, +23.25, −91.285714)`.
   Guarded: the move was only applied because the inverse landed `LoungeHatch` on
   `HatchRim` to within 0.1 studs. Result: `LoungeHatch = (110, −15.9, 130)`.
2. `Laboratory_Complex` — one `PivotTo` — by the delta that puts `Roof_1` on its
   exported position.

### Verification after repair

| check | result |
|---|---|
| `Roof_1` | 82.2857, 129.375, 133.7143 — exported value |
| Level_1 slab top | 0.000 |
| Basement slab top | −16.250 |
| Ground plane | −8.000 (correctly between the two) |
| Research stations resting on a real slab | 67 / 67, 0 in mid-air |
| Lab spawns | all three on `FloorSlab_1` |
| `HatchRim` over open basement floor | yes, `BasementSlab` @ −16.25 |
| Building parts overlapping the lounge volume | 1963 → **0** |
| Part counts | 61513 / 168 / 4 / 1×6 — unchanged |
| `LabSpatial.frame()` translation magnitude | **0.0000** |

The last row is the important one: with the map back on its authored datum, the
whole Revision 4 coordinate layer is a mathematical no-op, so it could be removed
rather than unpicked.

## 3. Source changes

Built by `revision5/build_fixes.py` from the pre-Revision-4 baseline
(`documentation/Genrmination_Fight/code/baseline`), re-applying only the
Revision 4 changes that stand on their own. Every replacement asserts its anchor
occurs exactly once.

Installed (7 scripts):

| script | bytes | change |
|---|---|---|
| `ReplicatedStorage.GWAPWorld` | 6184 | reverted to baseline (Revision 4 touched it only through LabSpatial) |
| `ServerScriptService.LabEquipment` | 181743 | reverted to baseline, same reason |
| `ReplicatedStorage.GWAPRouting` | 2644 | `FAILED` equipment excluded from mission targets |
| `ServerScriptService.GWAPServer` | 30395 | server-side repair validation (role, distance, state, line of sight); blast-removed equipment excluded from later blasts; NPC arming eligibility recomputed on a 5 s signature tick instead of per shot; weapon models kept rather than rebuilt; route nodes destroyed on mission finish |
| `ServerScriptService.LoungeSystems` | 5159 | `TextService:FilterStringAsync` + 3 s cooldown on shared signs |
| `StarterPlayer.StarterPlayerScripts.LabHUD` | 12175 | one watcher per model; route node list cached and invalidated on child add/remove; billboards only for on-screen, aimed-at NPCs; carrier HP folded into the mission panel |
| `ReplicatedStorage.GWAPNPC` | 5324 | server speech billboard removed; message retained as an attribute for the HUD |

Retired: `ReplicatedStorage.LabSpatial` → `ServerStorage.LabSpatial_RETIRED_revision4`.
No live script references it; the only remaining mentions are prose in the
documentation modules.

### Deliberately not carried over from Revision 4

* `LabSpatial` and all 30 `Spatial.*` call sites — the frame is identity.
* The per-step `workspace:Blockcast` in the carrier walk loop. ~180 bots × one
  blockcast per tick is a performance regression, and it bypasses the existing
  room-occupancy gate that keeps most bots idle.

`ServerStorage.GameDocumentation` had its Revision 4 conclusion prepended with a
correction notice; it previously recorded "The building itself was not moved
back" and "Do not move the lounge twice", both now false and both actively
misleading to a future reader. The `LabFrameAligned` marker on `Workspace.Lounge`
was cleared.

## 4. Play test

Clean start, no script errors:

```
[LoungeSystems] hidden lounge online
Role kiosks armed: 2.
[LabRound] units=872 meanDist=138 studs perTask=19.4s -> round=480s (8.0 min)
ServerBlasterManager ready: camera shots are server-validated and obstacle-checked.
Equipment armed: 872 items; recovery tool pads: 90.
[LabTechnicians] 180 technicians online
[GWAP] 10 scenarios, 5 research carriers, rooftop planting and solo opposition ready
```

Player spawns at (39.57, 3.76, 53.70), standing on Level 1. 180 bots tagged.
Same-floor pathfinding to research stations succeeds (13–32 waypoints).

## 5. Open, deliberately deferred

**Adopt `revision5/code/GWAPNavigation.lua`.** It is written and reviewed but not
yet wired in. It resolves floors from the actual `FloorSlab`/`BasementSlab` parts,
stairs from the actual named tread parts in each `StairTower_*`, and approach
points recomputed per route from live equipment bounds with ground, line-of-sight
and body-box checks — no stored coordinates, no frame. It exists to fix the cases
where a goal lands inside equipment (2 of 6 same-floor probes returned `NoPath`)
and cross-floor routes that `PathfindingService` cannot solve alone (basement
probe returned `NoPath`).

It is deferred on purpose: the map repair and the source revert are one verified
change, and stacking a routing rewrite on top would make a regression impossible
to attribute. Land this, confirm play, then wire navigation in as its own step.

**Why the building drifted in the first place is still unknown.** If it was a
generator rebuild writing at a different origin, a future rebuild will reproduce
the drift. Before the next full regeneration, check `Roof_1` against
`(82.2857, 129.375, 133.7143)`.

**Not saved.** Studio holds this repair in memory only.

---

# Stage 2 — role-bound missions and a hostile building (14 Sep)

## Mission selection removed

`GWAPScenarios` is now **two** entries, not ten:

| | route | stops |
|---|---|---|
| Germination integrity chain | Seed bank → Incubator → Clinostat → Orientation scanner → Vitality scanner → rooftop plot | 6 |
| Cold-chain contamination audit | Cryo-freezer → Wet lab → Symbiosis incubator → Chemical seedlings → Porometer → rooftop plot | 6 |

Every stop is a station *Capability* with three instances in the map (one
original, two backups), so a destroyed or unreachable stop reroutes rather than
stalling the run.

* Setting `LabRole` assigns one of the two straight away. Verified: role set →
  `GWAPScenario=1`, `GWAPTotalStages=6`, `GWAPTarget="Seed bank"`, with no
  further input.
* The HUD's "Jobs" button, the scenario menu, the list and the "Random
  assignment" button are gone.
* The server now **refuses** a `choose` action arriving from a client — it can
  only be a stale HUD or a crafted packet.
* Because nothing can be chosen any more, `finish()` reissues the next
  assignment 8 s after a mission ends.

## Hostile ambush

Replaces the old opposition loop, which fired once every 2.5 s, only when a
single player was in the server, and then applied ±2.5 studs of random spread —
so it usually missed and never left its room.

| behaviour | how |
|---|---|
| come out of rooms | rooms within 58 studs of a player release up to 3 workers; the door is **held open** for 9 s via a new `ForceOpen` attribute honoured by `bindAutoDoor` |
| stairs and greenhouse | pursuit is position-based, not room-based, so they follow onto the towers and the roof |
| never miss | the shot is a single raycast to the target with **no spread**; if it has the line, it connects |
| blow up hazards | 22% of shots go at a gas pipe within 26 studs (Explosion + fire/smoke) or a live machine within 16 studs (`explode`) |
| break greenhouse glass | a shot blocked by glass inside `RooftopGreenhouse` shatters it, and the next shot has the line |
| attack the carrier | hostiles switch to the carrier when it is clearly closer, so the Technician has something to defend |
| at most 10 | a hard roster cap, replenished from rooms further along as they are put down |

### Balance

Ten shooters that never miss is ~93 dps, which killed a standing player in 20 s
with no counterplay. Rather than make them miss — the opposite of what was
asked — the **combined** rate is capped by a leaky bucket per victim
(`INCOMING_CAP = 10/s`, carrier `9/s`). Every shot still connects and still
reads as a hit; it just cannot stack another full share in the same second.
Workers also take 1.2 s to bring a weapon up after waking, so an ambush
announces itself. Measured: a steady ~4 HP/s, survivable alongside the health
stations.

### Bugs found and fixed during this stage

1. **Hostiles would not move.** The existing patrol AI in `LabEquipment` was
   calling `PivotTo` on the same rigs; two systems driving one rig cancel out.
   The patrol now yields for as long as `GWAPHostile` is set.
2. **Still would not move.** The 3-direction wall slide could not get around a
   lab full of benches — the sweep was correctly refusing to walk through an
   `Incubator`. Widened to 8 headings, plus a real path solve when stuck for
   1.5 s, throttled to at most one worker per second across the whole roster.
3. **Seated desk staff were being recruited** and had no walk pose. Ambushers
   are now drawn only from workers already on their feet.
4. **`choose` was a nil global inside `finish()`** — the forward declaration sat
   below it. This is the same declare-after-use trap that has now bitten this
   project five times; moved up with the shared state.
5. **HUD errored every frame** (`LabHUD:83`) — the chooser's layout lines
   survived the removal of the button they positioned.

Measured after the fixes: 9 of 9 hostiles walked (28–291 studs each), several
closing to 9–10 studs; roster held at 10; up to 4 doors held open at once; no
script errors on either role.

## Still open

* 9 of 67 stations remain unroutable — all originals at `x = 67`, hard against
  the corridor's west wall. Missions reroute to backups automatically, so play
  is unaffected, but those 9 are decoration until they are nudged off the wall.
* `GWAPNavigation` is now used by both the carrier and the hostiles.

---

# Stage 3 — ambush tuning (14 Sep)

Three adjustments after play-testing stage 2.

| constant | was | now | effect |
|---|---|---|---|
| `HOSTILE_CAP` | 10 | **5** | half as many armed workers active at once |
| `PER_ROOM` | 3 | **2** | smaller release from each room |
| `HOSTILE_DAMAGE` | 4 | **2** | each hit costs half |
| `INCOMING_CAP` | 10 | **5** | combined damage to a player, per second |
| `CARRIER_INCOMING_CAP` | 9 | **3** | combined damage to the carrier, per second |
| `CARRIER_HUNTER_SHARE` | — | **0.5** | new: half of each ambush is assigned to the carrier on wake |

## Targeting the escorted carrier

Previously a hostile only switched to the carrier when it happened to be much
nearer (`carrierDist < bestDist * 0.45`), so the carrier was rarely the target.
Now each worker is given a target class **when it wakes** and keeps it: a
carrier hunter stays on the carrier while it is in range, and everyone else
still switches opportunistically on the old distance rule. Fixing the
assignment at wake-time stops hostiles flipping target every time the player
and the carrier cross distance.

The carrier cap was set to 3/s rather than left at 9/s because at 9/s the
carrier died in 15 s with nobody interfering, which makes the escort
unwinnable rather than hard. At 3/s it survives roughly 30 s of sustained fire
unaided, so intervening actually decides the outcome.

## Measured after tuning

* hostile roster: **5**, held for the whole sample
* carrier: ~**3.0 HP/s**, 84 → 13 over 25 s, still alive
* player: ~**0.2 HP/s** while standing clear of the fight
* target split: **4 nearer the carrier, 1 nearer the player**
* no script errors; health stations observed recharging normally

Player pressure is deliberately light in that figure because the player was
standing away from the carrier. Defending it means standing where the four
carrier hunters are shooting, which is where the player damage is actually felt.

---

# Stage 4 — damage balance and doorway line of sight (14 Sep)

Four symptoms reported, three distinct causes.

## 1. Hits registered as 0.5 damage

The rate limiter handed back a **fraction** of the requested damage. With five
shooters sharing a 5/s budget, each landed shot was scaled down to ~0.5, so a
hit did not read as a hit.

The bucket now decides **how often** a shot can hurt, never how much. A shot
either lands for its full value or is spent as a near miss:

```lua
-- All or nothing: a landed shot always costs its full value, so damage
-- numbers stay readable. The cap limits the RATE of hits, not their size.
if bucket.level+amount>cap then return 0 end
```

There is a constraint this creates, worth recording: **the cap must be at least
the hit size**, or no shot can ever afford to land. One hit per second is
therefore the fastest possible pace, so survival time is now set by the hit
size rather than by the cap.

| | was | now |
|---|---|---|
| `HOSTILE_DAMAGE` | 2 (scaled to ~0.5) | **6** per landed hit |
| `INCOMING_CAP` | 5 | **14** (~2 hits/s get through) |
| `CARRIER_DAMAGE` | 3 (scaled) | **4** per landed hit |
| `CARRIER_INCOMING_CAP` | 3 | **4** (1 hit/s, ~28 s unaided) |

## 2. No shot from an adjacent doorway

The shot ray was filtered with the **movement** filter, which excluded only the
shooter and other hostiles. A closed automatic door, or any idle co-worker
standing in the gap, swallowed the shot — so a hostile in the next room almost
never had a line.

Added `shotIgnore`, used for the shot ray only: the shooter's own side no
longer shields the target. Automatic doors open on approach and idle
co-workers are not cover, so neither stops a shot. **Movement still collides
with everything**, and walls and equipment still block the shot.

## 3. Player weapons one-shot the workers

`Lab Shotgun` was 6 pellets × 20 = **120 damage** against a 100 HP worker, so
any clean body hit was an instant kill — the "100 percent" in the report.
Pellet damage 20 → **12**, so a full-pellet hit is 72 and takes two, matching
the rifle (55) and sidearm (34). Head shots still kill instantly by design.

## Measured after the change

| | result |
|---|---|
| player hit size | **7.3 avg** (was 0.5), 9 hits in 26 s |
| carrier hit size | **4.0 exactly**, 21 hits |
| carrier survival, nobody helping | 84 HP → 0 in **24 s** (~3.2 HP/s) |
| shotgun vs worker | 72 of 100 — **two hits**, no longer one |
| hostile roster | 5, held |
| script errors | none |

Note the shotgun change is made in the installed `LabEquipment`. The generator
holds its own copy of the weapon table, so a full regeneration would restore
the old value — see the two-runtime-paths warning at the top of this record.

---

# Stage 5 — standoff, cadence and the one-shot kill (14 Sep)

## 1. Workers crowded the player

They closed to 6 studs and formed a scrum that could not be aimed through.
`stepHostile` now holds a firing line: a worker closes only to `STANDOFF`,
gives ground if it ends up inside `STANDOFF_MIN`, and applies a separation push
away from every other hostile within `SPACING` **on every tick** — not only
once it had already stopped, which was the first attempt and left the ones
still closing piling into the ones that had halted.

| | value |
|---|---|
| `STANDOFF` | 20 |
| `STANDOFF_MIN` | 15 |
| `SPACING` | 9 |

24/17 was tried first and held the line so far back that corridor equipment
broke line of sight and **nothing landed at all** in 28 s. 20/15 keeps clear
room to aim while leaving them in sight.

## 2. Fire rate and hit size

To the spec given: one shot per worker per ten seconds, half a health point per
hit, as an absolute value rather than a percentage.

| | was | now |
|---|---|---|
| `SHOT_INTERVAL` | 1.1 s | **10 s** |
| `HOSTILE_DAMAGE` | 6 | **0.5** (absolute points) |
| `INCOMING_CAP` | 14 | 5 — far above the hit size, so every shot lands |
| `HAZARD_CHANCE` | 0.22 | **0.08** |

The hazard chance had to come down with the cadence: at one shot per worker per
ten seconds, 0.22 still put an explosion in the room roughly every nine seconds,
and blast damage completely buried the 0.5 rifle hits. At 0.08 hazards are
punctuation rather than the main source of damage.

## 3. Every gun killed in one shot

Cause: `tool:SetAttribute("BlasterInstantHeadshot", style.pcOnly == true)` — and
all three PC weapons set `pcOnly = true`, so **instant-headshot was enabled on
every gun**. Whenever a ray cleared the collision hull and caught the head, any
weapon killed outright. Reducing the shotgun's pellet damage in stage 4 could
not fix this because the kill was not coming from the damage value at all.

A head shot now doubles damage instead of ending the fight, in both firing
paths (`BlasterInstantHeadshot` false, and the sidearm path's own head rule).
That closes every 1000-damage gun route; the remaining 1000s are the equipment
and gas-pipe explosions, which are meant to be lethal.

Verified through the real `BlasterHitBridge` against a full-health worker:

| weapon | damage | shots to kill |
|---|---|---|
| Lab Sidearm | 34 | **3** |
| Lab Shotgun | 6 x 12 | **2** |
| Lab Rifle | 55 | **2** |

## Measured after the change

* hit sizes recorded: `0.5` throughout (the occasional `1.0` is two shots
  landing inside one 0.25 s sample, not a bigger hit)
* 15 hits in 35 s from 4-5 workers, health 100 -> **94.5**
* closest any worker got: **13 studs**; typical distance **44**
* no script errors

## Diagnostic note

The bridge itself was never at fault — an isolated `BlasterHitBridge:Invoke`
with 34 damage took a worker from 100 to 66 exactly. That test is what ruled out
`damageWorkerBot` and the weapon table and pointed at the tool attribute.
