-- Revision 5: read the current map; never move it to satisfy a route.
-- Public route points are carrier pivot positions (surface + ROOT_HEIGHT).
-- Floor numbers identify actual Level_N/Basement slabs, not old Floor attributes.
-- Pathfinding runs only when a mission requests a route. Stair fallback follows
-- named tread surfaces and checks complete legs once, never once per Heartbeat.
-- If a required surface is absent or blocked, return a reason and let the owner
-- pause/regroup. No regeneration, coordinate-frame migration, or geometry edits.
local Nav = {}
local Pathfinding = game:GetService('PathfindingService')
local Players = game:GetService('Players')
local ROOT_HEIGHT, BODY_SIZE = 3.25, Vector3.new(2.4, 4.4, 2.4)
-- Clearance used when VERIFYING a computed path. The pathfinder legitimately
-- hugs walls, so verifying with the full standing box rejects corridors the
-- agent can actually walk. Goal selection still uses the full BODY_SIZE.
local PATH_SIZE = Vector3.new(1.9, 4.2, 1.9)
local UP = Vector3.new(0, 1, 0)
local cached, cachedAt
local function invalidate() cached, cachedAt = nil, nil end

local function surface(part)
    return part.CFrame:PointToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0))
end
local function exists(part)
    return part and part:IsA('BasePart') and part:IsDescendantOf(workspace) and part.CanCollide
end
local function levelNumber(name)
    if name == 'Basement' then return -1 end
    local n = tonumber(name:match('^Level_(%d+)$'))
    return n and n - 1
end
local function snapshot()
    local complex = workspace:FindFirstChild('Laboratory_Complex')
    if not complex then return nil, 'Laboratory_Complex is missing.' end
    if cached and cached.complex == complex and os.clock() - cachedAt < 15 then return cached end
    local data = {complex=complex, floors={}, towers={}}
    for _, model in ipairs(complex:GetChildren()) do
        local level = levelNumber(model.Name)
        if level then
            for _, part in ipairs(model:GetChildren()) do
                if part:IsA('BasePart') and (part.Name:match('^FloorSlab') or part.Name == 'BasementSlab') then
                    table.insert(data.floors, {level=level, part=part})
                end
            end
        elseif model.Name:match('^StairTower_') then
            table.insert(data.towers, {model=model, landings={}, middles={}, flights={}})
        end
    end
    local highest = -math.huge
    for _, floor in ipairs(data.floors) do highest = math.max(highest, floor.level) end
    for _, part in ipairs(complex:GetChildren()) do
        if part:IsA('BasePart') and part.Name:match('^Roof_') then
            table.insert(data.floors, {level=highest + 1, part=part})
        end
    end
    local function record(tower, part)
        if not part:IsA('BasePart') then return end
        local level = tonumber(part.Name:match('^Landing_L(-?%d+)$'))
        if level then tower.landings[level] = part; return end
        level = tonumber(part.Name:match('^MidLanding_L(-?%d+)$'))
        if level then tower.middles[level] = part; return end
        local flight, floor, index = part.Name:match('^Flight([AB])_L(-?%d+)_t(%d+)$')
        if flight then
            floor, index = tonumber(floor), tonumber(index)
            tower.flights[floor] = tower.flights[floor] or {A={}, B={}}
            tower.flights[floor][flight][index] = part
        end
    end
    for _, tower in ipairs(data.towers) do
        for _, part in ipairs(tower.model:GetChildren()) do record(tower, part) end
    end
    -- The previously built final roof flight lives in GWAPResearch, outside its
    -- stair tower. Associate it by measured horizontal proximity, not a compass
    -- name or a coordinate copied from a generator version.
    local research = complex:FindFirstChild('GWAPResearch')
    if research then
        for _, part in ipairs(research:GetChildren()) do
            if part:IsA('BasePart') and (part.Name:match('^Flight[AB]_') or part.Name:match('^MidLanding_') or part.Name == 'Roof stair landing') then
                local nearest, distance
                for _, tower in ipairs(data.towers) do
                    for _, landing in pairs(tower.landings) do
                        local delta = landing.Position - part.Position
                        local d = Vector3.new(delta.X, 0, delta.Z).Magnitude
                        if not distance or d < distance then nearest, distance = tower, d end
                    end
                end
                if nearest then
                    if part.Name == 'Roof stair landing' then nearest.landings[highest+1] = part
                    else record(nearest, part) end
                end
            end
        end
    end
    if #data.floors == 0 then return nil, 'No current floor slabs were found.' end
    table.sort(data.towers, function(a,b) return a.model.Name < b.model.Name end)
    cached, cachedAt = data, os.clock()
    return data
end

local function floorAt(data, position)
    local best, rank
    for _, floor in ipairs(data.floors) do
        local part = floor.part
        if exists(part) then
            local localPoint = part.CFrame:PointToObjectSpace(position)
            local inside = math.abs(localPoint.X) <= part.Size.X/2 + 2 and math.abs(localPoint.Z) <= part.Size.Z/2 + 2
            local score = math.abs(position.Y - surface(part).Y) + (inside and 0 or 10000)
            if not rank or score < rank then best, rank = floor, score end
        end
    end
    return best
end
function Nav.floorOf(station)
    local data = snapshot()
    if not data or not station or not station:IsA('BasePart') then return nil end
    local floor = floorAt(data, station.Position - UP * station.Size.Y/2)
    return floor and floor.level
end

local function queryParams(excluded, station)
    local list = {}
    for _, item in ipairs(excluded or {}) do if typeof(item) == 'Instance' then table.insert(list,item) end end
    for _, player in ipairs(Players:GetPlayers()) do if player.Character then table.insert(list,player.Character) end end
    local data = snapshot()
    local complex = data and data.complex
    if complex then
        local workers = complex:FindFirstChild('WorkerTestNPCs')
        local research = complex:FindFirstChild('GWAPResearch')
        local carriers = research and research:FindFirstChild('Carriers')
        if workers then table.insert(list,workers) end
        if carriers then table.insert(list,carriers) end
    end
    if station then table.insert(list,station) end
    -- Automatic doors open on approach. Treating a currently-closed door as
    -- solid would make every room unreachable when routing from Edit or from
    -- across the building, so they are excluded from route blocking. The walk
    -- loop still collides with them in real time.
    if complex then
        for _, part in ipairs(complex:GetDescendants()) do
            if part:IsA('BasePart') and string.find(part.Name, 'autodoor', 1, true) then
                table.insert(list, part)
            end
        end
    end
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances = list
    ray.RespectCanCollide = true
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = list
    overlap.RespectCanCollide = true
    return ray, overlap
end
local function candidates(station, excluded)
    if not station or not station:IsA('BasePart') or not station:IsDescendantOf(workspace) then
        return nil, 'The requested equipment is no longer in the map.'
    end
    local data, reason = snapshot()
    if not data then return nil, reason end
    local floor = floorAt(data, station.Position - UP * station.Size.Y/2)
    if not floor then return nil, 'No floor supports this equipment.' end
    local ray, overlap = queryParams(excluded, station)
    local choices = {}
    -- Candidate offsets are body clearances from the actual equipment bounds.
    -- They are not map locations. Recompute on every route, so individually
    -- relocated equipment and regenerated room packing cannot leave stale goals.
    for _, extra in ipairs({4, 7}) do
        for _, offset in ipairs({
            Vector3.new(station.Size.X/2+extra,0,0), Vector3.new(-station.Size.X/2-extra,0,0),
            Vector3.new(0,0,station.Size.Z/2+extra), Vector3.new(0,0,-station.Size.Z/2-extra),
        }) do
            local point = station.CFrame:PointToWorldSpace(offset)
            local origin = Vector3.new(point.X, surface(floor.part).Y+5, point.Z)
            local ground = workspace:Raycast(origin, -UP*10, ray)
            if ground and ground.Normal.Y > .85 and math.abs(ground.Position.Y-surface(floor.part).Y) < 2 then
                point = ground.Position + UP*ROOT_HEIGHT
                local sight = workspace:Raycast(point, station.Position-point, ray)
                if not sight and #workspace:GetPartBoundsInBox(CFrame.new(point),BODY_SIZE,overlap) == 0 then
                    local delta = point-floor.part.Position
                    table.insert(choices,{point=point,score=Vector3.new(delta.X,0,delta.Z).Magnitude+extra})
                end
            end
        end
    end
    table.sort(choices,function(a,b) return a.score < b.score end)
    if #choices == 0 then return nil, 'There is no clear, supported approach to '..station.Name..'.' end
    return choices
end
function Nav.approach(station)
    local choices, reason = candidates(station)
    return choices and choices[1].point or nil, reason
end

local function append(points, position)
    if #points == 0 or (points[#points]-position).Magnitude > .1 then table.insert(points,position) end
end
-- A waypoint that only moves the agent vertically is unreachable for a walker:
-- it has no direction to walk in, and any ground-following correction cancels
-- the climb, so the agent spins on the spot. Stair treads are expressed as
-- rising points that always carry horizontal travel, so a purely vertical hop
-- is always an artefact of two landing points measured off different surfaces.
-- Fold those into the point that follows.
local function tidy(points)
    local out = {}
    for _, p in ipairs(points) do
        local last = out[#out]
        if last then
            local d = p - last
            local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
            if horizontal < .25 and math.abs(d.Y) < 3 then
                out[#out] = p          -- same column: keep the later height only
            else
                table.insert(out, p)
            end
        else
            table.insert(out, p)
        end
    end
    return out
end
local function length(points)
    local total = 0
    for i=2,#points do total += (points[i]-points[i-1]).Magnitude end
    return total
end
local function legClear(from, destination, ray, size)
    local delta = destination-from
    if delta.Magnitude < .1 then return true end
    return workspace:Blockcast(CFrame.new(from),size or BODY_SIZE,delta,ray) == nil
end
local function pathLeg(from, destination, ray)
    if (from-destination).Magnitude < .2 then return {destination} end
    if math.abs(from.Y-destination.Y) < .75 and legClear(from,destination,ray) then
        -- A clear air corridor is not sufficient: verify support along long legs
        -- so a missing slab cannot silently become an anchored-bot air bridge.
        local delta = destination-from
        local supported = true
        for i=0,math.ceil(delta.Magnitude/6) do
            local p = from:Lerp(destination,i/math.max(1,math.ceil(delta.Magnitude/6)))
            local ground = workspace:Raycast(p,-UP*(ROOT_HEIGHT+2),ray)
            if not ground or ground.Normal.Y < .7 then supported=false;break end
        end
        if supported then return {from,destination} end
    end
    local path = Pathfinding:CreatePath({AgentRadius=1.8,AgentHeight=5,AgentCanJump=false,WaypointSpacing=5})
    local ok = pcall(function() path:ComputeAsync(from-UP*ROOT_HEIGHT,destination-UP*ROOT_HEIGHT) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then path:Destroy();return nil end
    local points = {from}
    for _, waypoint in ipairs(path:GetWaypoints()) do
        append(points,waypoint.Position+UP*ROOT_HEIGHT)
    end
    path:Destroy()
    append(points,destination)
    for i=2,#points do if not legClear(points[i-1],points[i],ray,PATH_SIZE) then return nil end end
    return points
end

local function stairPoints(tower, first, last)
    local result = {}
    local function landingPoint(part, lanePart)
        if not exists(part) or not exists(lanePart) then return nil end
        return Vector3.new(lanePart.Position.X,surface(part).Y,part.Position.Z)+UP*ROOT_HEIGHT
    end
    local function flight(level)
        local stairs = tower.flights[level]
        local low, middle, high = tower.landings[level], tower.middles[level], tower.landings[level+1]
        if not stairs or not exists(low) or not exists(middle) or not exists(high) or #stairs.A == 0 or #stairs.B == 0 then return nil end
        local points = {}
        local begin = landingPoint(low,stairs.A[1])
        if not begin then return nil end
        append(points,begin)
        for _,part in ipairs(stairs.A) do if not exists(part) then return nil end;append(points,surface(part)+UP*ROOT_HEIGHT) end
        append(points,landingPoint(middle,stairs.A[#stairs.A]))
        append(points,landingPoint(middle,stairs.B[1]))
        for _,part in ipairs(stairs.B) do if not exists(part) then return nil end;append(points,surface(part)+UP*ROOT_HEIGHT) end
        append(points,landingPoint(high,stairs.B[#stairs.B]))
        return points
    end
    if last > first then
        for level=first,last-1 do
            local points=flight(level);if not points then return nil end
            for _,point in ipairs(points) do append(result,point) end
        end
    else
        for level=first-1,last,-1 do
            local points=flight(level);if not points then return nil end
            for i=#points,1,-1 do append(result,points[i]) end
        end
    end
    return result
end

function Nav.route(fromPosition, station, excludeInstances)
    local choices, reason = candidates(station,excludeInstances)
    if not choices then return nil, reason end
    local data = snapshot()
    local startFloor = floorAt(data,fromPosition-UP*ROOT_HEIGHT)
    local endFloor = floorAt(data,choices[1].point-UP*ROOT_HEIGHT)
    if not startFloor or not endFloor then return nil, 'The route has no identifiable floor.' end
    local ray = queryParams(excludeInstances)
    if startFloor.level == endFloor.level then
        for i=1,math.min(3,#choices) do
            local points = pathLeg(fromPosition,choices[i].point,ray)
            if points then return tidy(points) end
        end
        return nil, 'No walkable route reaches '..station.Name..' on this floor.'
    end
    -- At most two towers and two candidate goals are tried. No unbounded retry
    -- loop or per-worker path task is created; the caller owns retry timing.
    local best, bestLength
    for towerIndex=1,math.min(2,#data.towers) do
        local middle = stairPoints(data.towers[towerIndex],startFloor.level,endFloor.level)
        if middle and #middle > 0 then
            local clear = true
            for i=2,#middle do if not legClear(middle[i-1],middle[i],ray) then clear=false;break end end
            if clear then
                local entry = pathLeg(fromPosition,middle[1],ray)
                if entry then
                    for choiceIndex=1,math.min(2,#choices) do
                        local exit = pathLeg(middle[#middle],choices[choiceIndex].point,ray)
                        if exit then
                            local points = {}
                            for _,group in ipairs({entry,middle,exit}) do for _,point in ipairs(group) do append(points,point) end end
                            local distance = length(points)
                            if not bestLength or distance < bestLength then best,bestLength=points,distance end
                            break
                        end
                    end
                end
            end
        end
    end
    if best then return tidy(best) end
    return nil, 'The existing stairs or floor access are blocked; no geometry was changed.'
end
-- Point-to-point walkable path, used by the hostile AI to round obstacles.
-- Same verification as a mission leg, but it takes a bare destination rather
-- than a station, and returns nil rather than a reason.
function Nav.pathTo(fromPosition, destination, excluded)
    local list = {}
    for _, item in ipairs(excluded or {}) do if typeof(item) == 'Instance' then table.insert(list,item) end end
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances = list
    ray.RespectCanCollide = true
    local points = pathLeg(fromPosition, destination, ray)
    return points and tidy(points) or nil
end
function Nav.invalidate() invalidate() end
return Nav
