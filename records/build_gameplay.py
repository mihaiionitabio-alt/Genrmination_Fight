"""Revision 5 stage 1: give the research carrier real navigation and real movement.

Before: routePoints() returned a hardcoded polyline (x=78 corridor lane,
x=68.7857 stair lane, z=-6 tower mouth, tread offsets baked in) and the walk
loop drove the rig with PivotTo while checking only for players to avoid
shoving them. Nothing checked geometry, so the carrier walked through walls,
equipment and floors.

After: routes come from GWAPNavigation, which reads the current slabs, the
actual stair treads and live equipment bounds; and every step is swept against
the world and snapped onto the surface beneath before it is applied.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CODE = ROOT / 'code'
f = CODE / 'ServerScriptService.GWAPServer.lua'
s = f.read_text(encoding='utf-8')

def rep(old, new, n=1):
    global s
    got = s.count(old)
    assert got == n, (old[:100], got, n)
    s = s.replace(old, new)

# --- dependency -----------------------------------------------------------
rep("local NPC=require(RS:WaitForChild('GWAPNPC'))\nlocal refreshArmed=function() end",
    "local NPC=require(RS:WaitForChild('GWAPNPC'))\n"
    "local Nav=require(RS:WaitForChild('GWAPNavigation'))\n"
    "local refreshArmed=function() end\n"
    "-- Carrier body used for every sweep. Matches the rig's collision hull.\n"
    "local CARRIER_BODY=Vector3.new(2.4,4.4,2.4)\n"
    "local CARRIER_ROOT=3.25")

# --- route generation -----------------------------------------------------
old_route_points = s[s.index('local function routePoints(from,to)'):s.index('local function showRoute(a,route)')]
new_route_points = '''-- Routes are derived from the map as it exists right now: floor slabs give the
-- levels, the named tread parts in each StairTower give the flights, and the
-- approach point is recomputed from the target's live bounds. No coordinate is
-- stored anywhere, so relocated equipment and rebuilt rooms cannot strand a
-- carrier, and every leg is verified clear before the carrier is asked to walk it.
local function carrierIgnore(a)
\tlocal list={a.bot}
\tfor _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list,p.Character) end end
\tlocal complex=workspace:FindFirstChild('Laboratory_Complex')
\tif complex then
\t\tlocal r=complex:FindFirstChild('GWAPResearch')
\t\tlocal c=r and r:FindFirstChild('Carriers'); if c then table.insert(list,c) end
\t\tlocal w=complex:FindFirstChild('WorkerTestNPCs'); if w then table.insert(list,w) end
\t\t-- Automatic doors open on approach; they are not route obstacles.
\t\tfor _,part in ipairs(complex:GetDescendants()) do
\t\t\tif part:IsA('BasePart') and string.find(part.Name,'autodoor',1,true) then table.insert(list,part) end
\t\tend
\tend
\treturn list
end
local function routePoints(from,to)
\tlocal points,reason=Nav.route(from,to,carrierIgnore({bot=to}))
\treturn points,reason
end
'''
s = s.replace(old_route_points, new_route_points)

# --- go(): use Nav for both the rendezvous leg and the travel leg ----------
old_go_head = s[s.index('local function go(a,target)'):s.index('\tshowRoute(a,route)')]
new_go_head = '''local function go(a,target)
\tlocal revision=a.routeRevision or 0
\tif not Router.healthy(target) then return false end
\tlocal route,reason=Nav.route(a.bot:GetPivot().Position,target,carrierIgnore(a))
\tif not route then
\t\t-- No walkable way exists right now. Say so and wait to be regrouped
\t\t-- rather than sliding through the obstruction.
\t\tif os.clock()-(a.lastRouteComplaint or 0)>8 then
\t\t\ta.lastRouteComplaint=os.clock()
\t\t\ttell(a,reason or 'I cannot find a walkable route from here. Ask me to regroup from an open corridor.')
\t\tend
\t\ta.needsRendezvous=true; a.deadline+=1; task.wait(1); return false
\tend
\ta.needsRendezvous=false
'''
s = s.replace(old_go_head, new_go_head)

# --- the walk loop: physical movement -------------------------------------
rep("""			local nextPos=start+delta.Unit*math.min(delta.Magnitude,math.clamp(a.speed,8,40)*math.min(dt,.1))
			-- Research routes use measured open corridors and each actual stair tread.
			-- Stop for players; do not shove them or change their movement settings.
			local blocked=false
			for _,p in ipairs(Players:GetPlayers()) do local r=alive(p); if r and (r.Position-nextPos).Magnitude<2.8 then blocked=true end end
			if not blocked then
				local flat=Vector3.new(delta.X,0,delta.Z)
				local previous=a.bot:GetPivot()
				local desired=flat.Magnitude>.01 and CFrame.lookAt(nextPos,nextPos+flat) or CFrame.new(nextPos)*previous.Rotation
				a.bot:PivotTo(CFrame.new(nextPos)*previous.Rotation:Lerp(desired.Rotation,1-math.exp(-dt*10)))
			end""",
"""			local nextPos=start+delta.Unit*math.min(delta.Magnitude,math.clamp(a.speed,8,40)*math.min(dt,.1))
			-- Stop for players; do not shove them or change their movement settings.
			local blocked=false
			for _,p in ipairs(Players:GetPlayers()) do local r=alive(p); if r and (r.Position-nextPos).Magnitude<2.8 then blocked=true end end

			-- Physical movement. The rig is anchored and driven by PivotTo, which
			-- bypasses the physics solver, so the step is swept against the world
			-- by hand: a blocked step is never applied, and an applied step is
			-- snapped onto the surface underneath so the carrier can neither sink
			-- through a floor nor walk on air.
			local sweep=RaycastParams.new()
			sweep.FilterType=Enum.RaycastFilterType.Exclude
			sweep.FilterDescendantsInstances=carrierIgnore(a)
			sweep.RespectCanCollide=true
			if not blocked then
				local step=nextPos-start
				if step.Magnitude>1e-4 and workspace:Blockcast(CFrame.new(start),CARRIER_BODY,step,sweep) then
					blocked=true
					a.obstructedSince=a.obstructedSince or os.clock()
					if os.clock()-(a.lastObstacleMessage or 0)>10 then
						a.lastObstacleMessage=os.clock()
						tell(a,'Something is blocking the way. Clear it, or ask me to regroup from an open corridor.')
					end
					-- Persistent obstruction means the world changed under the
					-- route (blast debris, a sealed door). Recompute rather than
					-- stand still until the mission clock expires.
					if os.clock()-a.obstructedSince>6 then
						a.obstructedSince=nil
						a.routeRevision=(a.routeRevision or 0)+1
						a.needsRendezvous=true
						Nav.invalidate()
						return false
					end
				else
					a.obstructedSince=nil
					local ground=workspace:Raycast(nextPos+Vector3.new(0,2.5,0),Vector3.new(0,-9,0),sweep)
					if ground and ground.Normal.Y>.5 then
						nextPos=Vector3.new(nextPos.X,ground.Position.Y+CARRIER_ROOT,nextPos.Z)
					end
				end
			end
			if not blocked then
				a.bot:SetAttribute('Obstructed',false)
				local flat=Vector3.new(delta.X,0,delta.Z)
				local previous=a.bot:GetPivot()
				local desired=flat.Magnitude>.01 and CFrame.lookAt(nextPos,nextPos+flat) or CFrame.new(nextPos)*previous.Rotation
				a.bot:PivotTo(CFrame.new(nextPos)*previous.Rotation:Lerp(desired.Rotation,1-math.exp(-dt*10)))
			else
				a.bot:SetAttribute('Obstructed',true)
				a.deadline+=dt
			end""")

f.write_text(s, encoding='utf-8')

# --- reachability-aware station choice -------------------------------------
g = CODE / 'ReplicatedStorage.GWAPRouting.lua'
r = g.read_text(encoding='utf-8')
assert r.count('function R.choose(stations,capability,preferredFloor,position)') == 1
r = r.replace('function R.choose(stations,capability,preferredFloor,position)',
'''-- reachable(item) is supplied by the caller (GWAPServer passes the navigation
-- probe). A station with no walkable approach is ranked below every reachable
-- one instead of being chosen and then stranding the carrier.
function R.choose(stations,capability,preferredFloor,position,reachable)''')
r = r.replace(
"local score=(floorOf(item)==preferredFloor and 0 or 100000)+math.abs(floorOf(item)-preferredFloor)*1000+(item.Position-position).Magnitude",
"local score=(floorOf(item)==preferredFloor and 0 or 100000)+math.abs(floorOf(item)-preferredFloor)*1000+(item.Position-position).Magnitude\n\t\tif reachable and not reachable(item) then score+=10000000 end")
g.write_text(r, encoding='utf-8')

print('GWAPServer', len(s.encode()), 'bytes')
print('GWAPRouting', len(r.encode()), 'bytes')
