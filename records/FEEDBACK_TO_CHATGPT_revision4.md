# Feedback on Revision 4 — why the building broke, and how to redo the correction

Paste this whole file to ChatGPT as the brief for the next attempt.

---

## 1. The one sentence that matters

**The building did not move. It was re-generated.**

Revision 4 is built on a single hypothesis — that `Laboratory_Complex` was
translated as a rigid body, so gameplay coordinates can be repaired by composing
one global transform. That hypothesis is false, and it was already tested and
falsified before Revision 4 was written:

* The complex is produced end-to-end by `SeedLabGenerator.lua`. Nothing in it is
  hand-placed. Every position is derived at build time from plan constants
  (`W, L = 1280, 2080`, `CORR_X1/CORR_X2 = 500/720`, `F2F = 325`, `SLAB = 25`)
  through the unit helpers `X()`, `Y()`, `E()`, `EH()`.
* Between builds the room layout is re-packed. When two builds were compared
  part-by-part, the residual after best-fit translation was **X spread ≈ 53
  studs, Z spread ≈ 250 studs**. A rigid translation cannot produce that. A
  rotation fit was tested too and was worse.
* Therefore *no* `CFrame` — not `Roof_1 * BASE_ROOF:Inverse()`, not any other —
  maps old coordinates onto the current layout. Applying one does not correct the
  scene; it slides parts of the scene away from the rest. That is exactly the
  symptom reported: **the building moved and left gaps.**

Everything below follows from this.

---

## 2. Specific defects in `live_revision4`

### 2.1 `LabSpatial.frame()` is a rigid-body assumption with a silent failure mode

```lua
local BASE_ROOF = CFrame.new(82.28571428571429, 129.375, 133.71428571428572)
function S.frame()
    local complex = workspace:FindFirstChild('Laboratory_Complex')
    local roof = complex and complex:FindFirstChild('Roof_1')
    return roof and roof.CFrame * BASE_ROOF:Inverse() or CFrame.identity
end
```

Three problems:

1. **One landmark cannot describe a non-rigid change.** `Roof_1` moving tells you
   `Roof_1` moved. It says nothing about where Room 43 on Level 5 ended up.
2. **`BASE_ROOF` is a magic constant baked from one build.** The next generator
   run changes it, silently, with no assertion. It has no provenance in the code
   that produced it.
3. **The `or CFrame.identity` fallback is the worst possible failure.** If
   `Roof_1` is absent or renamed, every call quietly returns identity, and the
   session then runs with *half* the systems in lab-local space and half in world
   space. Nothing errors. Nothing logs. Missing landmark must be a hard error, not
   a silent identity.

### 2.2 The `GWAPWorld` patch physically moves geometry, and is not idempotent

```python
w = replace(w, '\treturn f\nend',
  "\tlocal frame=Spatial.frame()\n"
  "\tfor _,v in ipairs(f:GetDescendants()) do if v:IsA('BasePart') then v.CFrame=frame*v.CFrame end end\n"
  "\tSpatial.sync(stations)\n\treturn f\nend")
```

This is the line that breaks the place. It rewrites the transform of every
descendant part of `f` on every call. There is no guard, no marker attribute, no
"already transformed" check. Run the builder twice in one session — a rebuild, a
round reset, a re-require after a script edit — and the offset is applied twice.
Three times, three times. **This is the mechanism that produced the gaps.**

Any transform applied to live instances must be idempotent by construction:
tag the instance (`SetAttribute('SpatialFrameApplied', true)`) and skip it, or
better, never transform instances at all (see §3).

### 2.3 Mixed CFrame algebra

```lua
q.CFrame = Spatial.frame():Inverse() * q.CFrame + Vector3.new(0, 16.25, 0)
```

`CFrame * CFrame` then `+ Vector3` is order-sensitive and sign-confusing. The
inverse frame is being used where the forward frame is used two lines later. Even
if the frame concept were sound, this line is a coin flip. Any coordinate-space
change must be written with one explicit convention (`world = frame * local`,
`local = frame:Inverse() * world`) and unit-checked against a known part.

### 2.4 `Blockcast` per NPC per step is a performance regression

```lua
local obstruction = workspace:Blockcast(CFrame.new(start), Vector3.new(2.4,4.4,2.4), nextPos-start, sweep)
```

The stated goal was to make the game **lighter**. There are ~180 bots. A
`Blockcast` with `RespectCanCollide = true` on every short step for every walking
bot is the single most expensive thing that could have been added to the movement
loop. If obstruction detection is needed, do it on the *leg* (one cast per
waypoint pair), not per tick, and only for bots that are actually awake —
the project already has a room-occupancy gate (`botHasObserver`) that keeps
169–179 of 180 idle at rest. The sweep bypasses that gate entirely.

### 2.5 Documentation embedded in the DataModel

Splitting the reference across two ~200 KB `ModuleScript`s inside
`ServerScriptService` adds ~400 KB of string data to every server start and to
every place save, forever, to solve a problem that a file in
`D:\game\documentation\Genrmination_Fight\` already solves. This is directly
against the "lighter, not consuming memory that can be spared" requirement.
Per-subsystem comments in the code: yes. The full book in the place file: no.

### 2.6 The patch source is ambiguous

```python
BASE = ROOT.parent/'documentation/Genrmination_Fight/code/active'
if (ROOT.parent/'documentation/Genrmination_Fight/code/baseline').exists():
    BASE = ROOT.parent/'documentation/Genrmination_Fight/code/baseline'
```

Which tree the `assert count == 1` replacements run against depends on whether a
directory happens to exist. The same script therefore produces different output
on different machines or after a partial sync. Pin the baseline explicitly and
record its hash in `revision-record.md`.

### 2.7 The fixes were applied to the wrong artefact

The installed scripts in the place are **generated output**.
`SeedLabGenerator.lua` writes them (`EQUIP_SCRIPT_SOURCE`, plus the
`startLiveRuntimeFallback()` copy used when `Script.Source` writes fail). Editing
the installed copies means:

* the next generator run silently reverts every fix;
* the two runtime paths drift apart — **many helpers exist twice in that file and
  both copies must be changed**;
* nothing is reproducible from source.

Fixes belong in `SeedLabGenerator.lua`. The place is the *output*, and the test
target — never the edit target.

---

## 3. How to do the correction properly

### Rule 1 — Do not store world coordinates anywhere

Every coordinate in gameplay code should be *derived at runtime from the building
that currently exists*, not from a number captured from a previous build, and not
from a number captured from a previous build and then transformed.

The project already ships the mechanism for this. The generator publishes a
`RoomIndex` attribute: 81 room rectangles in stud space, packed as
`"Level_1:Room 1:x1:z1:x2:z2:y;..."`. Parse it once at startup and resolve
`roomAt(levelName, position)` / `roomRect(levelName, roomName)` from it. If a
room moves between builds, the index moves with it and the routing is correct for
free — with no frame, no landmark, no constant.

For anything the index does not cover, resolve by **tag or name lookup at
runtime** (`CollectionService:GetTagged`, `FindFirstChild`) and read the position
off the instance you found. A route that says "walk to the part tagged
`SeedBank` on Level 3" survives a regeneration. A route that says
"walk to `Vector3.new(78, 35.25, 120)`" does not, and no transform will save it.

### Rule 2 — Fix the generator, then rebuild, then verify

1. Edit `SeedLabGenerator.lua` only.
2. Push it into Studio via the localhost pipe:
   `python -m http.server 8765 --directory D:\game --bind 127.0.0.1`, then in
   Studio (Edit) `HttpService.HttpEnabled = true`,
   `loadstring(HttpService:GetAsync("http://127.0.0.1:8765/SeedLabGenerator.lua", true))()`,
   then set `HttpEnabled = false` again and stop the server.
   (`readfile` is nil in Studio; `Script.Source` caps at 200,000 chars, so use
   `ScriptEditorService:UpdateSourceAsync` for the disabled mirror copy.)
3. Verify numerically before claiming anything: count parts inside the building
   footprint (`x 0..164.6, z 0..267.4`, `Level_1 y = 0`, `F2F = 16.25`,
   basement `y = -16.25`), assert the expected chamber count, assert 0 exterior
   parts intrude into the footprint.
4. Screenshot. Play-test.

### Rule 3 — Change one thing, verify, then change the next

Revision 4 changed the coordinate space of seven modules in one pass and then
validated by playing one mission. A single mission passing does not demonstrate
that 81 rooms across 9 floors are consistent. Land one change, run the numeric
check, commit, then take the next.

### Rule 4 — Every transform must be idempotent and self-checking

If instance-level transforms are truly unavoidable:

* mark what you touched and skip marked instances;
* assert a known part lands where expected *before* touching the rest, and abort
  loudly if it does not;
* never fall back to identity on a missing landmark — raise.

### Rule 5 — Respect the two runtime paths and the preserve guard

* `EQUIP_SCRIPT_SOURCE` and `startLiveRuntimeFallback()` both need every fix.
* Watch the Lua ordering trap that has already bitten this project three times:
  a `local` declared *after* a function that references it resolves to a **nil
  global** inside that function and silently kills the thread at runtime
  (`botHasObserver`, `BODY_LIFETIME_SECONDS`). Declare before use.
* `SUPERSEDED_ON_REBUILD` / `PRESERVE_ON_REBUILD` at the top of the generator
  decide what survives a rebuild. Anything preserved across a regeneration will
  drift out of alignment, because the layout is re-packed — which is the original
  bug, and the reason `SiteWorks` and `OfficeFitout` were converted to procedural
  generation rather than preserved.

---

## 4. Recovery

`live_revision4/InstallGWAP.before-revision4.lua` (115,778 bytes, 13 Sep 02:15)
is the pre-Revision-4 installer. Restore from that, or simply re-run the
generator — the place is reproducible output, which is the whole point.

Then re-derive each Revision 4 fix on its own merits. Several of them are good
and are unrelated to the coordinate theory, and should be kept:

* server-side validation of the repair prompt (role check, distance check,
  line-of-sight raycast) instead of trusting client prompt visibility;
* `TextService:FilterStringAsync` + cooldown on lounge notes;
* NPC eligibility recomputed on knockout/recovery instead of per shot;
* route objects destroyed when a mission finishes;
* one HUD watcher per model instead of one per re-group;
* route node list cached and invalidated on `ChildAdded`/`ChildRemoved`.

Discard: `LabSpatial` and every `Spatial.world` / `Spatial.localPoint` /
`Spatial.frame` call site, the `GWAPWorld` descendant transform, the per-step
`Blockcast`, and the in-place documentation modules.

---

## 5. Checklist for the next attempt

- [ ] No hardcoded world coordinate is introduced anywhere.
- [ ] No global transform is composed from a landmark part.
- [ ] All positions resolve from `RoomIndex`, tags, or instance lookup at runtime.
- [ ] All edits land in `SeedLabGenerator.lua`, in **both** runtime paths.
- [ ] Nothing transforms live instances; if it must, it is idempotent and asserts.
- [ ] No new per-tick raycast/blockcast in the bot loop; the room-occupancy gate
      still keeps ~175/180 bots idle at rest.
- [ ] Documentation stays in `D:\game\documentation`; only per-subsystem comments
      go in the code.
- [ ] Each change is verified by a numeric scene query, not by one play-through.
- [ ] Baseline tree is pinned and hashed in `revision-record.md`.
