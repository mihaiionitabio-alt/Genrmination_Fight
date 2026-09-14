-- Authoritative assignments, research carriers, solo opposition and score accounting.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local CS=game:GetService('CollectionService')
local SSS=game:GetService('ServerScriptService')
local Debris=game:GetService('Debris')
local Run=game:GetService('RunService')
local NPC=require(RS:WaitForChild('GWAPNPC'))
local Nav=require(RS:WaitForChild('GWAPNavigation'))
local refreshArmed=function() end
-- Carrier body used for every sweep. Matches the rig's collision hull.
local CARRIER_BODY=Vector3.new(2.4,4.4,2.4)
local CARRIER_ROOT=3.25
local Pathfinding=game:GetService('PathfindingService')
local pool=Instance.new('Folder'); pool.Name='GWAPCarrierPool'; pool.Parent=game:GetService('ServerStorage')
local companions={}
local World=require(RS:WaitForChild('GWAPWorld'))
local scenarios=require(RS:WaitForChild('GWAPScenarios'))
local research=World.build()
local Router=require(RS:WaitForChild('GWAPRouting'))
local stations=Router.ensureBackups()
local stationInfo={}
for _,item in ipairs(stations:GetChildren()) do stationInfo[item.Name]={capability=item:GetAttribute('Capability'),floor=Router.floorOf(item)} end
local remote=Instance.new('RemoteEvent'); remote.Name='GWAPAction'; remote.Parent=RS
local bridge=Instance.new('BindableFunction'); bridge.Name='GWAPHitBridge'; bridge.Parent=SSS
local botsFolder=Instance.new('Folder'); botsFolder.Name='Carriers'; botsFolder.Parent=research
local routesFolder=Instance.new('Folder'); routesFolder.Name='Routes'; routesFolder.Parent=research
local random=Random.new()
local carriers, assignments, cooldowns, armed={}, {}, {}, {}
-- Forward declaration: finish() reissues an assignment, and is defined long
-- before choose(). Without this the call inside finish() is a nil global.
local choose
local function alive(p)
	local c=p.Character; local h=c and c:FindFirstChildOfClass('Humanoid'); return h and h.Health>0 and c:FindFirstChild('HumanoidRootPart')
end
local function points(p)
	local s=p:FindFirstChild('leaderstats'); return s and s:FindFirstChild('Points')
end
local function award(p,n,reason)
	local v=points(p); if not v then return end
	v.Value=math.max(0,v.Value+n); p:SetAttribute('GWAPNotice',reason); p:SetAttribute('LastPointAmount',n); p:SetAttribute('LastPointAward',reason)
end
local function role(p) return p and (p:GetAttribute('LabRole') or (p.Team and p.Team.Name)) end
local function active(a) return a and a.bot and a.bot.Parent and a.bot:GetAttribute('State')=='RUNNING' end
local function nearby(p,bot,d) local r=alive(p); return r and (r.Position-bot:GetPivot().Position).Magnitude<=d end
local function publish(a)
	for p,bound in pairs(assignments) do if bound==a then
		p:SetAttribute('GWAPStage',a.stage); p:SetAttribute('GWAPTotalStages',#a.route)
		p:SetAttribute('GWAPTarget',a.target and a.target.Name or a.route[a.stage] or 'Complete'); p:SetAttribute('GWAPTargetFloor',a.target and Router.floorOf(a.target) or nil); p:SetAttribute('GWAPState',a.bot:GetAttribute('State'))
	end end
end
local function tell(a,message)
	NPC.say(a.bot,message)
	for p,bound in pairs(assignments) do if bound==a then p:SetAttribute('GWAPDialogue',message); p:SetAttribute('GWAPSpeaker',a.bot:GetAttribute('DisplayName') or 'Research carrier') end end
end
local function finish(a,state)
	if not active(a) then return end
	a.bot:SetAttribute('State',state); a.bot:SetAttribute('TaskState',state); a.bot:SetAttribute('HasSeedling',false)
	local carried=a.bot:FindFirstChild('Mission seedling'); if carried then carried:Destroy() end
	local route=routesFolder:FindFirstChild(a.bot.Name);if route then route:Destroy() end
	publish(a); a.finishedAt=os.clock(); tell(a,state=='COMPLETE' and 'The plant is in the greenhouse. Research assignment complete. Thank you!' or 'Mission stopped: '..state..'. A replacement assignment is on its way.')
	-- Assignments are no longer chosen, so the next one has to be issued.
	for player,bound in pairs(assignments) do
		if bound==a then
			assignments[player]=nil
			task.delay(8,function()
				local r=role(player)
				if player.Parent and (r=='Technician' or r=='Laboratory Technician') and not active(assignments[player]) then
					choose(player,random:NextInteger(1,#scenarios))
				end
			end)
		end
	end
end
local function updateHealth(bot)
	local t=bot:FindFirstChild('HealthText',true); local fill=bot:FindFirstChild('HealthBarFill',true)
	local h=bot:GetAttribute('Health') or 100
	local status=bot:FindFirstChild('Status',true)
	if status and status:IsA('TextLabel') then status.Text='RESEARCH CARRIER\n'..(bot:GetAttribute('Title') or 'Choose an assignment') end
	if t then t.Text='LIFE '..math.ceil(h)..' / 100' end
	if fill then fill.Size=UDim2.fromScale(h/100,1) end
end
local function damage(p,bot,amount)
	local a=carriers[bot]; if not active(a) then return end
	local h=math.max(0,bot:GetAttribute('Health')-amount); bot:SetAttribute('Health',h); updateHealth(bot)
	if role(p)=='Technician' and assignments[p]==a then a.disqualified[p]=true; p:SetAttribute('GWAPNotice','Protect your carrier: friendly hits cancel escort rewards.') end
	if h==0 then
		if assignments[p]==a and role(p)=='Laboratory Technician' then award(p,50,'+50 | Assigned research carrier stopped') end
		finish(a,'INTERCEPTED')
	end
end

local equipmentOriginal={}
for _,item in ipairs(stations:GetChildren()) do
	if item:IsA('BasePart') then
		local saved={}
		local function remember(v) if v:IsA('BasePart') then saved[v]={v.Color,v.Material,v.Transparency,v.CanQuery} end end
		remember(item); for _,v in ipairs(item:GetDescendants()) do remember(v) end
		equipmentOriginal[item]=saved
		item:SetAttribute('GWAPEquipment',true)
	end
end
local function repair(item)
	item:SetAttribute('Exploded',false); item:SetAttribute('FunctionalState','RUNNING')
	for part,props in pairs(equipmentOriginal[item] or {}) do if part.Parent then part.Color=props[1]; part.Material=props[2]; part.Transparency=props[3]; part.CanQuery=props[4] end end
	for _,v in ipairs(item:GetChildren()) do if v.Name=='GWAPFire' or v.Name=='GWAPSmoke' then v:Destroy() end end
	local prompt=item:FindFirstChild('ResearchRepair'); if prompt then prompt.Enabled=false end
end
local explode
explode=function(item,attacker)
	if not equipmentOriginal[item] or item:GetAttribute('Exploded') then return end
	item:SetAttribute('Exploded',true); item:SetAttribute('FunctionalState','DESTROYED')
	for part in pairs(equipmentOriginal[item]) do if part.Parent then part.Color=Color3.fromRGB(49,42,38); part.Material=Enum.Material.CorrodedMetal end end
	local fire=Instance.new('Fire'); fire.Name='GWAPFire'; fire.Size=5; fire.Heat=4; fire.Parent=item; Debris:AddItem(fire,8)
	local smoke=Instance.new('Smoke'); smoke.Name='GWAPSmoke'; smoke.Size=4; smoke.Opacity=.3; smoke.Parent=item; Debris:AddItem(smoke,12)
	local blast=Instance.new('Explosion'); blast.Position=item.Position; blast.BlastRadius=13; blast.BlastPressure=0; blast.DestroyJointRadiusPercent=0; blast.ExplosionType=Enum.ExplosionType.NoCraters
	if attacker then blast:SetAttribute('GWAPAttacker',attacker.UserId) end
	blast.Parent=workspace
	for _,a in pairs(carriers) do if active(a) then
		if (a.bot:GetPivot().Position-item.Position).Magnitude<13 then damage(attacker,a.bot,60) end
		if a.target==item then tell(a,item.Name..' was destroyed. I will find a working equivalent.'); end
	end end
	local prompt=item:FindFirstChild('ResearchRepair'); if prompt then prompt.Enabled=true end
end
for item in pairs(equipmentOriginal) do
	local prompt=Instance.new('ProximityPrompt'); prompt.Name='ResearchRepair'; prompt.ActionText='Repair research equipment'; prompt.ObjectText=item.Name; prompt.KeyboardKeyCode=Enum.KeyCode.R; prompt.HoldDuration=3; prompt.MaxActivationDistance=12; prompt.Enabled=false; prompt.Parent=item
	prompt.Triggered:Connect(function(p)
        local root=alive(p)
        if not root or role(p)~='Technician' or not item:IsDescendantOf(workspace)
            or item:GetAttribute('BlastRemoved') or not item:GetAttribute('Exploded')
            or (root.Position-item.Position).Magnitude>14 then return end
        local head=p.Character:FindFirstChild('Head') or root
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.Character}
        local hit=workspace:Raycast(head.Position,item.Position-head.Position,params)
        if hit and hit.Instance~=item and not hit.Instance:IsDescendantOf(item) then return end
        repair(item);p:SetAttribute('GWAPNotice',item.Name..' repaired. Ready for research.')
    end)
end
workspace.DescendantAdded:Connect(function(v)
	if not v:IsA('Explosion') then return end
	local center,radius=v.Position,v.BlastRadius
	local userId=v:GetAttribute('GWAPAttacker'); local attacker=userId and Players:GetPlayerByUserId(userId)
	-- Deferred bounded propagation: each station can explode only once until repaired.
	task.delay(.12,function()
		for item in pairs(equipmentOriginal) do if item:IsDescendantOf(workspace) and not item:GetAttribute('BlastRemoved') and not item:GetAttribute('Exploded') and (item.Position-center).Magnitude<=radius+item.Size.Magnitude*.25 then
			local delta=item.Position-center
			local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={v}
			local hit=delta.Magnitude>.1 and workspace:Raycast(center,delta,params)
			if not hit or hit.Instance==item or hit.Instance:IsDescendantOf(item) or hit.Instance:GetAttribute('Exploded') then explode(item,attacker) end
		end end
	end)
end)

bridge.OnInvoke=function(p,hit,damageAmount)
	local node=hit
	while node and node~=workspace do if equipmentOriginal[node] then explode(node,p); return true end; if carriers[node] then damage(p,node,damageAmount); return true end; node=node.Parent end
	return false
end
-- Routes are derived from the map as it exists right now: floor slabs give the
-- levels, the named tread parts in each StairTower give the flights, and the
-- approach point is recomputed from the target's live bounds. No coordinate is
-- stored anywhere, so relocated equipment and rebuilt rooms cannot strand a
-- carrier, and every leg is verified clear before the carrier is asked to walk it.
local function carrierIgnore(a)
	local list={a.bot}
	for _,p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list,p.Character) end end
	local complex=workspace:FindFirstChild('Laboratory_Complex')
	if complex then
		local r=complex:FindFirstChild('GWAPResearch')
		local c=r and r:FindFirstChild('Carriers'); if c then table.insert(list,c) end
		local w=complex:FindFirstChild('WorkerTestNPCs'); if w then table.insert(list,w) end
		-- Automatic doors open on approach; they are not route obstacles.
		for _,part in ipairs(complex:GetDescendants()) do
			if part:IsA('BasePart') and string.find(part.Name,'autodoor',1,true) then table.insert(list,part) end
		end
	end
	return list
end
local function routePoints(from,to)
	local points,reason=Nav.route(from,to,carrierIgnore({bot=to}))
	return points,reason
end
local function showRoute(a,route)
	local old=routesFolder:FindFirstChild(a.bot.Name); if old then old:Destroy() end
	local folder=Instance.new('Folder'); folder.Name=a.bot.Name; folder.Parent=routesFolder
	for i,v in ipairs(route) do local n=Instance.new('Vector3Value'); n.Name=string.format('%03d',i); n.Value=v; n.Parent=folder end
end
local function go(a,target)
	local revision=a.routeRevision or 0
	if not Router.healthy(target) then return false end
	local route,reason=Nav.route(a.bot:GetPivot().Position,target,carrierIgnore(a))
	if not route then
		-- Remember that this particular station cannot be reached from here, so
		-- the next selection falls through to a backup with the same capability
		-- instead of proposing the same unreachable target forever.
		a.unreachable=a.unreachable or {}
		a.unreachable[target]=os.clock()
		-- No walkable way exists right now. Say so and wait to be regrouped
		-- rather than sliding through the obstruction.
		if os.clock()-(a.lastRouteComplaint or 0)>8 then
			a.lastRouteComplaint=os.clock()
			tell(a,reason or 'I cannot find a walkable route from here. Ask me to regroup from an open corridor.')
		end
		a.needsRendezvous=true; a.deadline+=1; task.wait(1); return false
	end
	a.needsRendezvous=false
	showRoute(a,route)
	for i,goal in ipairs(route) do
		a.bot:SetAttribute('RouteIndex',i)
		if not Router.healthy(target) then a.needsRendezvous=true; return false end
		-- No single waypoint may hold the mission hostage. If one cannot be
		-- reached in time, abandon it and let the next one pull the carrier on;
		-- if several in a row fail, recompute the route from where we stand.
		local goalDeadline=os.clock()+12
		local stalled=false
		while active(a) and (goal-a.bot:GetPivot().Position).Magnitude>.35 do
			if os.clock()>goalDeadline then stalled=true; break end
			local dt=Run.Heartbeat:Wait(); if not active(a) then return false end
			if (a.routeRevision or 0)~=revision then return false end
			if not Router.healthy(target) then a.needsRendezvous=true; return false end
			if a.paused then a.deadline+=dt; continue end
			local ownerRoot=a.owner and alive(a.owner)
			if a.owner and role(a.owner)=='Technician' and (not ownerRoot or (ownerRoot.Position-a.bot:GetPivot().Position).Magnitude>45) then
				a.deadline+=dt
				if os.clock()-(a.lastWaitMessage or 0)>12 then a.lastWaitMessage=os.clock(); tell(a,'I am waiting for you. Follow the mint trail to my marker, then we can continue.') end
				continue
			end
			local start=a.bot:GetPivot().Position; local delta=goal-start
			local ownerHum=a.owner and a.owner.Character and a.owner.Character:FindFirstChildOfClass('Humanoid')
			local desiredSpeed=ownerHum and ownerHum.WalkSpeed or 16
			a.speed=(a.speed or desiredSpeed)+(desiredSpeed-(a.speed or desiredSpeed))*(1-math.exp(-dt*8))
			a.bot:SetAttribute('WalkSpeed',a.speed)
			local nextPos=start+delta.Unit*math.min(delta.Magnitude,math.clamp(a.speed,8,40)*math.min(dt,.1))
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
					-- Follow the surface, but never fight a deliberate climb: a step
					-- with no horizontal travel is the agent ascending in place, and
					-- snapping it back down would stall the route forever. Correct
					-- gradually so treads are walked rather than teleported.
					local horizontal=Vector3.new(step.X,0,step.Z).Magnitude
					if horizontal>1e-3 then
						local ground=workspace:Raycast(nextPos+Vector3.new(0,3,0),Vector3.new(0,-10,0),sweep)
						if ground and ground.Normal.Y>.5 then
							local want=ground.Position.Y+CARRIER_ROOT
							local blend=math.clamp(dt*12,0,1)
							nextPos=Vector3.new(nextPos.X,nextPos.Y+(want-nextPos.Y)*blend,nextPos.Z)
						end
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
			end
			if os.clock()>a.deadline then finish(a,'EXPIRED'); return false end
		end
		if not active(a) then return false end
		if stalled then
			a.stalledGoals=(a.stalledGoals or 0)+1
			if a.stalledGoals>=3 then
				a.stalledGoals=0
				a.routeRevision=(a.routeRevision or 0)+1
				a.needsRendezvous=true
				Nav.invalidate()
				return false
			end
		else
			a.stalledGoals=0
		end
	end
	return true
end
local function plantIn(bed,name)
	if bed:GetAttribute('Exploded') then return false end
	local count=bed:GetAttribute('Planted') or 0
	if count>=12 then return false end
	local pos=bed.Position+Vector3.new(-8+(count%4)*5,1,-3+math.floor(count/4)*3)
	World.plant(bed,pos,name); bed:SetAttribute('Planted',count+1)
	local sign=bed:FindFirstChild('StationLabel'); local label=sign and sign:FindFirstChildOfClass('TextLabel')
	if label then label.Text=bed.Name..' | '..(count+1)..' / 12 plants' end
	return true
end
local function checkpoint(a,final)
	for p,bound in pairs(assignments) do
		if bound==a and role(p)=='Technician' and not a.disqualified[p] and nearby(p,a.bot,45) then award(p,final and 60 or 15,final and '+60 | Protected rooftop planting' or '+15 | Protected research checkpoint') end
	end
end
local function runMission(a)
	for i,originalName in ipairs(a.route) do
		a.stage=i
		local original=stations:FindFirstChild(originalName)
		local info=stationInfo[originalName]
		local capability=info and info.capability or original and original:GetAttribute('Capability') or (originalName:match('^Plot ') and 'Greenhouse planting' or originalName)
		local preferredFloor=info and info.floor or original and Router.floorOf(original) or 0
		local completed=false
		while active(a) and not completed do
			-- A station is a candidate only if it is healthy, has a clear approach,
			-- and has not just failed to produce a route for this carrier.
			local function usable(item)
				if not item then return false end
				local failedAt=a.unreachable and a.unreachable[item]
				if failedAt and os.clock()-failedAt<45 then return false end
				return Nav.approach(item)~=nil
			end
			-- The sticky current target must be re-tested too, or a station that
			-- has just proved unreachable is proposed again on every retry.
			local target=Router.healthy(a.target) and a.target:GetAttribute('Capability')==capability and usable(a.target) and a.target
				or (Router.healthy(original) and usable(original) and original
				or Router.choose(stations,capability,preferredFloor,a.bot:GetPivot().Position,usable))
			if not target then
				a.target=nil; publish(a)
				if os.clock()-(a.lastNoEquipment or 0)>8 then a.lastNoEquipment=os.clock(); tell(a,'No working '..capability..' is available. Repair one with R; I will resume this assignment.') end
				a.deadline+=1; task.wait(1); continue
			end
			if target~=a.target then
				a.target=target; publish(a)
				if target~=original then a.bot:SetAttribute('Reroutes',(a.bot:GetAttribute('Reroutes') or 0)+1) end
				tell(a,target~=original and ('Rerouting to '..target.Name..' on '..(Router.floorOf(target)==-1 and 'B1' or Router.floorOf(target)==8 and 'the roof' or 'L'..(Router.floorOf(target)+1))..'. Same research function, new route.')
					or 'Next stop: '..target.Name..'. Stay with me.')
			end
			a.bot:SetAttribute('TaskState','Travel to '..target.Name)
			local reached=go(a,target)
			if not active(a) then return end
			if not reached then
				a.needsRendezvous=true
				if a.paused then repeat task.wait(.25) until not active(a) or not a.paused end
				task.wait(.1); continue
			end
			tell(a,'At '..target.Name..'. Processing the seedling now.')
			a.bot:SetAttribute('TaskState','Processing: '..target.Name)
			local seed=a.bot:FindFirstChild('Mission seedling')
			if seed then seed:PivotTo(CFrame.new(target.Position+Vector3.new(0,2,0))) end
			local work=0
			while active(a) and Router.healthy(target) and work<4 do task.wait(.1); if not a.paused then work+=.1 end end
			if not active(a) then return end
			if not Router.healthy(target) then a.needsRendezvous=true; continue end
			if i==#a.route then
				if plantIn(target,a.title..' | '..a.variant) then checkpoint(a,true); finish(a,'COMPLETE'); return end
				a.target=nil; original=nil; task.wait(.1); continue
			end
			if i==1 and not seed then a.bot:SetAttribute('HasSeedling',true); seed=World.plant(a.bot,a.bot:GetPivot().Position+Vector3.new(0,0,-2),'Mission seedling') end
			if seed then seed:PivotTo(CFrame.new(a.bot:GetPivot().Position+Vector3.new(0,0,-2))) end
			checkpoint(a,false); completed=true; a.target=nil; a.unreachable=nil
		end
		if not active(a) then return end
	end
end
local function startMission(bot,id,p)
	local s=scenarios[id]; local route=table.clone(s.route); table.insert(route,'Plot '..id)
	local a={bot=bot,id=id,title=s.title,route=route,stage=1,disqualified={},owner=p,needsRendezvous=true,paused=true,deadline=os.clock()+600}
	a.variant=s.variable..': '..random:NextInteger(s.low,s.high)..' '..s.units
	carriers[bot]=a; bot:SetAttribute('State','RUNNING'); bot:SetAttribute('Health',100); bot:SetAttribute('Scenario',id); bot:SetAttribute('Title',s.title); bot:SetAttribute('Variant',a.variant); updateHealth(bot)
	bot.Parent=botsFolder
	if not NPC.nearPlayer(p,bot) then bot.Parent=pool; carriers[bot]=nil; return nil end
	return a
end
local function makeBot(index)
	local template
	local choices={}
	for _,b in ipairs(CS:GetTagged('LabWorkerBot')) do if not b:GetAttribute('Seated') and b.PrimaryPart and ((index%2==1)==(b:GetAttribute('Gender')=='Girl')) then table.insert(choices,b) end end
	table.sort(choices,function(a,b) return a.Name<b.Name end); template=choices[(index-1)%math.max(1,#choices)+1]
	assert(template,'No worker template available')
	local b=template:Clone(); b.Name='ResearchCarrier_'..index
	for _,v in ipairs(b:GetDescendants()) do if v:IsA('LuaSourceContainer') or v:IsA('ProximityPrompt') or v:IsA('Humanoid') then v:Destroy() elseif v:IsA('BasePart') then v.Anchored=true; v.CanCollide=false end end
	for _,tag in ipairs(CS:GetTags(b)) do CS:RemoveTag(b,tag) end
	NPC.appearance(b)
	b:SetAttribute('Dead',false); b:SetAttribute('KnockedOut',false); b:SetAttribute('GWAPCarrier',true); b.Parent=botsFolder
	local h=Instance.new('Highlight'); h.Name='ResearchOutline'; h.FillTransparency=1; h.OutlineColor=Color3.fromRGB(92,244,199); h.DepthMode=Enum.HighlightDepthMode.Occluded; h.Parent=b
	return b
end
Run.Heartbeat:Connect(function(dt) for _,bot in ipairs(botsFolder:GetChildren()) do if bot:IsA('Model') then NPC.animate(bot,dt) end end end)
local available={}; for i=1,5 do available[i]=makeBot(i); available[i].Parent=pool; available[i]:SetAttribute('State','IDLE') end
local function companion(p)
	local bot=companions[p]
	if bot and bot.Parent then return bot end
	local reserved={}; for _,b in pairs(companions) do reserved[b]=true end
	for _,candidate in ipairs(available) do if not reserved[candidate] and not active(carriers[candidate]) then bot=candidate; break end end
	if not bot then bot=makeBot(#available+1); table.insert(available,bot) end
	companions[p]=bot; bot.Parent=botsFolder
	if not NPC.nearPlayer(p,bot) then bot.Parent=pool; p:SetAttribute('GWAPDialogue','Move to an open spot so I can meet you.'); return bot end
	p:SetAttribute('GWAPCarrier',bot.Name); p:SetAttribute('GWAPSpeaker',bot:GetAttribute('DisplayName')); p:SetAttribute('GWAPDialogue','Hello! I am your research carrier. Your assignment is being loaded.')
	NPC.say(bot,'Hello! I have our assignment. Tell me READY when you want to start.');task.defer(refreshArmed)
	return bot
end
function choose(p,id)
	if not alive(p) or workspace:GetAttribute('RoundPhase')=='BREAK' then return end
	if role(p)~='Technician' and role(p)~='Laboratory Technician' then p:SetAttribute('GWAPNotice','Choose a role at a blue or green kiosk first.'); return end
	if active(assignments[p]) then p:SetAttribute('GWAPNotice','Finish your current assignment before selecting another.'); return end
	local bot=companion(p)
	local a=startMission(bot,id,p)
	if not a then p:SetAttribute('GWAPNotice','Please move to an open spot so your carrier can appear beside you.'); return end
	assignments[p]=a; p:SetAttribute('GWAPCarrier',a.bot.Name); p:SetAttribute('GWAPScenario',id); p:SetAttribute('GWAPVariant',a.variant); p:SetAttribute('GWAPNotice',role(p)=='Technician' and 'Escort your carrier. Stay within 45 studs at checkpoints.' or 'Stop your assigned carrier before rooftop planting.'); publish(a)
	tell(a,'Our assignment is '..a.title..'. '..scenarios[id].purpose..' First stop: '..a.route[1]..'. Tell me READY when you want to start.')
	a.started=true; task.spawn(function() while active(a) and a.paused do task.wait(.25); a.deadline=os.clock()+600 end; if active(a) then runMission(a) end end)
end
remote.OnServerEvent:Connect(function(p,action,index)
	if typeof(action)~='string' or typeof(index)~='number' or index~=index or index%1~=0 then return end
	if os.clock()-(cooldowns[p] or 0)<.3 then return end; cooldowns[p]=os.clock()
	-- Assignments are bound to the role, never chosen. A 'choose' arriving from
	-- a client is therefore either a stale HUD or a crafted packet; ignore it.
	if action=='choose' then return
	elseif action=='reply' then
		local a=assignments[p]; if not active(a) then return end
		if index==1 then a.paused=false; tell(a,'Ready. Let us continue to '..(a.route[a.stage] or 'the greenhouse')..'.')
		elseif index==2 then a.paused=true; tell(a,'Understood. I will wait here. Press Ready when you want to continue.')
		elseif index==3 then tell(a,'We are heading to '..(a.target and a.target.Name or a.route[a.stage])..'. '..scenarios[a.id].purpose)
		elseif index==4 then
			if not a.paused then tell(a,'Ask me to wait before regrouping.'); return end
			if NPC.nearPlayer(p,a.bot) then a.needsRendezvous=true; a.routeRevision=(a.routeRevision or 0)+1; tell(a,'I am beside you again. Press Ready to continue.') end
		end
	end
end)
for _,bed in ipairs(stations:GetChildren()) do
	local prompt=bed:FindFirstChild('PlantSeedling')
	if prompt then prompt.Triggered:Connect(function(p)
		local r=alive(p); if not r or (r.Position-bed.Position).Magnitude>14 then return end
		local sample
		for _,holder in ipairs({p.Character,p:FindFirstChildOfClass('Backpack')}) do if holder then for _,t in ipairs(holder:GetChildren()) do if t:IsA('Tool') and (t:GetAttribute('PlantSample') or t:GetAttribute('TransferSample')) then sample=t; break end end end end
		if not sample then p:SetAttribute('GWAPNotice','Carry a germinated plant sample to this plot.'); return end
		if plantIn(bed,sample.Name) then sample:Destroy(); p:SetAttribute('CarriedSample',''); p:SetAttribute('GWAPNotice','Seedling planted in '..bed.Name) else p:SetAttribute('GWAPNotice','This plot is full. Use another plot.') end
	end) end
end
local function setArmed()
	local all={};local candidates=CS:GetTagged('LabWorkerBot')
    for _,bot in ipairs(available) do table.insert(candidates,bot) end
    for _,bot in ipairs(candidates) do
        if bot:IsDescendantOf(workspace) and not bot:GetAttribute('Dead') and not bot:GetAttribute('KnockedOut') and (bot:GetAttribute('Health') or 100)>0 then table.insert(all,bot)
        else bot:SetAttribute('GWAPArmed',false);local gun=bot:FindFirstChild('SoloWeapon');if gun then gun:Destroy() end end
    end
	table.sort(all,function(a,b) return a.Name<b.Name end)
	armed={}; local solo=#Players:GetPlayers()==1; local count=solo and math.floor(#all*.2) or 0
	local selected={}; local shuffle=table.clone(all); for i=#shuffle,2,-1 do local j=random:NextInteger(1,i); shuffle[i],shuffle[j]=shuffle[j],shuffle[i] end
	for i=1,count do selected[shuffle[i]]=true end
	for _,bot in ipairs(all) do
		local yes=selected[bot]==true; bot:SetAttribute('GWAPArmed',yes)
		local gun=bot:FindFirstChild('SoloWeapon')
		if yes then table.insert(armed,bot);if not gun then NPC.gun(bot,(bot:GetAttribute('BotNumber') or 1)) end
		elseif gun then gun:Destroy() end
	end
	workspace:SetAttribute('GWAPArmedCount',count); workspace:SetAttribute('GWAPBotCount',#all)
end
refreshArmed=setArmed
local retired={['Research SMG']=true,['Precision Rifle']=true,['Scatter Blaster']=true,['Blast Launcher']=true,['Pulse Bomb']=true}
local function watchPlayer(p)
	local function clean(v) if v:IsA('Tool') and (v:GetAttribute('GWAPWeapon') or retired[v.Name]) then v:Destroy() end end
	local function watch(container) for _,v in ipairs(container:GetChildren()) do clean(v) end; container.ChildAdded:Connect(clean) end
	task.spawn(function() watch(p:WaitForChild('Backpack')) end)
	local function onCharacter(c)
		watch(c)
		task.delay(1,function() if role(p)=='Technician' or role(p)=='Laboratory Technician' then
			local a=assignments[p]; if active(a) then a.paused=true; tell(a,'You are back. Ask me to regroup, then press Ready.') else companion(p) end
		end end)
	end
	if p.Character then onCharacter(p.Character) end; p.CharacterAdded:Connect(onCharacter)
	p:GetAttributeChangedSignal('LabRole'):Connect(function()
		local r=role(p)
		if r~='Technician' and r~='Laboratory Technician' then return end
		companion(p)
		-- Picking a role is picking a mission. One of the two assignments is
		-- drawn for the player straight away; there is no selection screen.
		task.defer(function()
			if active(assignments[p]) then return end
			choose(p,random:NextInteger(1,#scenarios))
		end)
	end)
	task.defer(setArmed)
end
Players.PlayerAdded:Connect(watchPlayer)
for _,p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
for _,bot in ipairs(CS:GetTagged('LabWorkerBot')) do NPC.appearance(bot) end
Players.PlayerRemoving:Connect(function(p) local a=assignments[p]; if active(a) then finish(a,'PLAYER LEFT') end; local bot=companions[p]; if bot then bot.Parent=pool end; companions[p]=nil; assignments[p]=nil; cooldowns[p]=nil; task.defer(setArmed) end)
setArmed()
local lastEligible=''
task.spawn(function() while task.wait(5) do
    local names={}
    for _,bot in ipairs(CS:GetTagged('LabWorkerBot')) do if bot:IsDescendantOf(workspace) and not bot:GetAttribute('Dead') and not bot:GetAttribute('KnockedOut') and (bot:GetAttribute('Health') or 100)>0 then table.insert(names,bot.Name) end end
    for _,bot in ipairs(available) do if bot:IsDescendantOf(workspace) and (bot:GetAttribute('Health') or 100)>0 then table.insert(names,bot.Name) end end
    table.sort(names);local key=tostring(#Players:GetPlayers())..':'..table.concat(names,'|')
    if key~=lastEligible then lastEligible=key;setArmed() end
end end)
--=====================================================================
-- HOSTILE AMBUSH
-- Workers ambush the player from the rooms they walk past, on the stair
-- towers and in the rooftop greenhouse. At most HOSTILE_CAP are awake at
-- once; as they are put down, rooms further along release replacements, so
-- the pressure stays constant while the cost stays bounded no matter how
-- many workers the building holds.
--=====================================================================
local HOSTILE_CAP=5
local RELEASE_RADIUS=58        -- how near the player a room must be to wake
local PER_ROOM=2               -- at most this many leave any one room
local ROOM_REARM_SECONDS=25
local HOSTILE_RANGE=95
local SHOT_INTERVAL=10         -- one shot per worker per ten seconds
local HOSTILE_DAMAGE=.5        -- absolute health points, not a percentage
local INCOMING_CAP=5           -- far above the hit size, so every shot lands
-- 24/17 held the line so far back that line of sight was usually broken by
-- corridor equipment and nothing landed. 20/15 still leaves clear room to aim
-- -- a worker never gets inside 15 studs -- while keeping them in sight of you.
local STANDOFF=20              -- hold this far off; do not crowd the target
local STANDOFF_MIN=15          -- back away if closer than this
local SPACING=9                -- and keep this far from each other
-- Note: with all-or-nothing damage the cap must be at least the hit size, or
-- no shot can ever afford to land. That makes one hit per second the fastest
-- possible pace, so the carrier's survival time is set by the hit SIZE.
local CARRIER_DAMAGE=4
local CARRIER_INCOMING_CAP=4   -- 1 hit a second; ~25 s of fire with nobody helping
local HOSTILE_SPEED=15
local HAZARD_CHANCE=.08        -- odds a shot goes at a pipe or machine instead
-- At one shot per worker per ten seconds, .22 put an explosion in the room
-- roughly every nine seconds, which buried the 0.5 rifle hits under blast
-- damage. .08 keeps hazards a punctuation mark rather than the main source.
local HOSTILE_BODY=Vector3.new(2.4,4.4,2.4)
local CARRIER_HUNTER_SHARE=.5  -- fraction of an ambush that goes for the carrier
local hostiles,roomArmedAt={},{}
local incoming=setmetatable({},{__mode='k'})
-- A leaky bucket per victim. Shots never miss; when the bucket is full the
-- shot still fires and still reads as a hit, it just cannot stack another
-- full share of damage on top in the same second.
local function spendDamage(victim,amount,cap)
	local now=os.clock()
	local bucket=incoming[victim]
	if not bucket then bucket={level=0,at=now}; incoming[victim]=bucket end
	bucket.level=math.max(0,bucket.level-(now-bucket.at)*cap)
	bucket.at=now
	-- All or nothing: a landed shot always costs its full value, so damage
	-- numbers stay readable. The cap limits the RATE of hits, not their size.
	if bucket.level+amount>cap then return 0 end
	bucket.level+=amount
	return amount
end

local function hostileCount()
	local n=0; for _ in pairs(hostiles) do n+=1 end; return n
end
local function botUsable(bot)
	-- Seated desk staff keep their pose; ambushers are drawn from workers who
	-- are already on their feet and can actually walk out of the room.
	if bot and bot:GetAttribute('Seated') then return false end
	return bot and bot.Parent and bot:IsDescendantOf(workspace)
		and not bot:GetAttribute('Dead') and not bot:GetAttribute('KnockedOut')
		and (bot:GetAttribute('Health') or 100)>0
end
local function dropHostile(bot)
	hostiles[bot]=nil
	if bot and bot.Parent then
		bot:SetAttribute('GWAPHostile',false)
		local gun=bot:FindFirstChild('SoloWeapon'); if gun then gun:Destroy() end
	end
end
local function wakeHostile(bot)
	if hostiles[bot] or not botUsable(bot) then return false end
	if hostileCount()>=HOSTILE_CAP then return false end
	hostiles[bot]={nextShot=os.clock()+1.2,since=os.clock(),stuck=0,
		huntsCarrier=random:NextNumber()<CARRIER_HUNTER_SHARE}
	bot:SetAttribute('GWAPHostile',true)
	bot:SetAttribute('GWAPArmed',true)
	if not bot:FindFirstChild('SoloWeapon') then NPC.gun(bot,(bot:GetAttribute('BotNumber') or 1)) end
	return true
end

-- Release workers from rooms the player is passing. The door is held open so
-- the player sees them come out rather than finding them already in the hall.
local function releaseNear(root)
	if hostileCount()>=HOSTILE_CAP then return end
	local complex=workspace:FindFirstChild('Laboratory_Complex'); if not complex then return end
	local now=os.clock()
	for _,door in ipairs(CS:GetTagged('AutoDoor')) do
		if hostileCount()>=HOSTILE_CAP then return end
		local doorY=door:GetAttribute('DoorY') or door.Position.Y
		if math.abs(root.Position.Y-doorY)<9 then
			local flat=(Vector3.new(root.Position.X,doorY,root.Position.Z)-Vector3.new(door.Position.X,doorY,door.Position.Z)).Magnitude
			if flat<RELEASE_RADIUS and now-(roomArmedAt[door] or -math.huge)>ROOM_REARM_SECONDS then
				local released=0
				for _,bot in ipairs(CS:GetTagged('LabWorkerBot')) do
					if released>=PER_ROOM or hostileCount()>=HOSTILE_CAP then break end
					if botUsable(bot) and not hostiles[bot] then
						local bp=bot:GetPivot().Position
						if math.abs(bp.Y-doorY)<9 and (bp-door.Position).Magnitude<34 then
							if wakeHostile(bot) then released+=1 end
						end
					end
				end
				if released>0 then
					roomArmedAt[door]=now
					door:SetAttribute('ForceOpen',true)
					task.delay(9,function() if door.Parent then door:SetAttribute('ForceOpen',false) end end)
				end
			end
		end
	end
end

local function hostileIgnore(bot)
	local list={bot}
	for other in pairs(hostiles) do if other~=bot then table.insert(list,other) end end
	return list
end
-- Filter for the SHOT ray only. Movement still collides with everything; this
-- just stops a hostile's own side from shielding the target. Automatic doors
-- open on approach and idle co-workers are not cover, so neither may swallow a
-- shot taken from an adjacent doorway. Walls and equipment still stop it.
local function shotIgnore(bot)
	local list=hostileIgnore(bot)
	for _,worker in ipairs(CS:GetTagged('LabWorkerBot')) do
		if worker~=bot then table.insert(list,worker) end
	end
	local complex=workspace:FindFirstChild('Laboratory_Complex')
	if complex then
		for _,part in ipairs(complex:GetDescendants()) do
			if part:IsA('BasePart') and string.find(part.Name,'autodoor',1,true) then table.insert(list,part) end
		end
	end
	return list
end

-- Straight-line pursuit with a wall slide. Hostiles engage inside the room or
-- corridor they were woken in, so a full path solve per bot per tick would be
-- cost with no benefit; the sweep still forbids walking through anything.
local lastSolveAt=0
local function stepHostile(bot,state,goal,dt)
	local from=bot:GetPivot().Position
	local delta=goal-from
	local flat=Vector3.new(delta.X,0,delta.Z)
	-- Hold a firing line. Walking all the way onto the target turned an ambush
	-- into a scrum the player could not aim through, so a worker closes only to
	-- STANDOFF, backs off below STANDOFF_MIN, and otherwise holds position.
	local range=flat.Magnitude
	-- Separation from the rest of the line, applied every tick so the workers
	-- still closing cannot pile into the ones that have already stopped.
	local push=Vector3.zero
	for other in pairs(hostiles) do
		if other~=bot and other.Parent then
			local away=from-other:GetPivot().Position
			local d=Vector3.new(away.X,0,away.Z)
			if d.Magnitude>1e-3 and d.Magnitude<SPACING then push+=d.Unit*(SPACING-d.Magnitude) end
		end
	end
	if range<STANDOFF_MIN then
		-- Too close to aim past. Give ground back to the firing line.
		goal=from-flat.Unit*(STANDOFF-range)+push
	elseif range<=STANDOFF then
		-- In position: hold, and only shuffle apart from whoever is crowding.
		if push.Magnitude<.4 then return end
		goal=from+push
	else
		goal=goal+push
	end
	delta=goal-from
	flat=Vector3.new(delta.X,0,delta.Z)
	if flat.Magnitude<.6 then return end
	local sweep=RaycastParams.new()
	sweep.FilterType=Enum.RaycastFilterType.Exclude
	sweep.FilterDescendantsInstances=hostileIgnore(bot)
	sweep.RespectCanCollide=true
	local speed=HOSTILE_SPEED*math.min(dt,.12)
	local dir=flat.Unit

	-- Follow a solved path while one is in hand: the lab floor is dense with
	-- machines and a pure steer cannot get around them.
	if state.path and state.pathIndex then
		local node=state.path[state.pathIndex]
		while node and (Vector3.new(node.X,0,node.Z)-Vector3.new(from.X,0,from.Z)).Magnitude<2.5 do
			state.pathIndex+=1; node=state.path[state.pathIndex]
		end
		if node then
			local toNode=node-from
			dir=Vector3.new(toNode.X,0,toNode.Z)
			dir=dir.Magnitude>1e-3 and dir.Unit or flat.Unit
		else
			state.path=nil; state.pathIndex=nil
		end
	end

	-- Eight headings, nearest to the goal first, so the worker rounds a bench
	-- instead of grinding against it.
	local right=Vector3.new(-dir.Z,0,dir.X)
	local options={dir}
	for _,angle in ipairs({25,-25,50,-50,80,-80,115,-115}) do
		local r=math.rad(angle)
		table.insert(options,(dir*math.cos(r)+right*math.sin(r)).Unit)
	end
	for _,option in ipairs(options) do
		local nextPos=from+option*speed
		if not workspace:Blockcast(CFrame.new(from),HOSTILE_BODY,nextPos-from,sweep) then
			local ground=workspace:Raycast(nextPos+Vector3.new(0,3,0),Vector3.new(0,-10,0),sweep)
			if ground and ground.Normal.Y>.5 then
				nextPos=Vector3.new(nextPos.X,nextPos.Y+((ground.Position.Y+3.25)-nextPos.Y)*math.clamp(dt*12,0,1),nextPos.Z)
				local previous=bot:GetPivot()
				local face=CFrame.lookAt(nextPos,nextPos+Vector3.new(delta.X,0,delta.Z))
				bot:PivotTo(CFrame.new(nextPos)*previous.Rotation:Lerp(face.Rotation,1-math.exp(-dt*10)))
				state.stuck=0
				return
			end
		end
	end

	-- Boxed in. Solve a real path, but at most one worker per second across the
	-- whole roster so ten hostiles cannot stall the server between them.
	state.stuck=(state.stuck or 0)+dt
	if state.stuck>1.5 and os.clock()-lastSolveAt>1 then
		lastSolveAt=os.clock()
		state.stuck=0
		local path=Nav.pathTo(from,goal,hostileIgnore(bot))
		if path and #path>1 then state.path=path; state.pathIndex=2 else state.path=nil end
	end
end

local function breakGlass(part)
	if not part or not part.Parent then return end
	if part:GetAttribute('GWAPShattered') then return end
	part:SetAttribute('GWAPShattered',true)
	local shard=Instance.new('Part')
	shard.Name='Broken glass'; shard.Anchored=true; shard.CanCollide=false; shard.CanQuery=false
	shard.Size=part.Size; shard.CFrame=part.CFrame; shard.Transparency=.55
	shard.Color=Color3.fromRGB(206,232,238); shard.Material=Enum.Material.Glass
	shard.Parent=part.Parent
	Debris:AddItem(shard,2.5)
	part:Destroy()
end

-- Pick a hazard beside the player: a gas pipe or a live machine. Detonating it
-- is how a hostile turns the room itself into the weapon.
local function hazardNear(position,origin)
	local best,rank
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude
	for _,pipe in ipairs(CS:GetTagged('GasPipe')) do
		if pipe.Parent then
			local d=(pipe.Position-position).Magnitude
			if d<26 and (not rank or d<rank) then best,rank=pipe,d end
		end
	end
	if best then return best,'pipe' end
	for item in pairs(equipmentOriginal) do
		if item.Parent and not item:GetAttribute('Exploded') and not item:GetAttribute('BlastRemoved') then
			local d=(item.Position-position).Magnitude
			if d<16 and (not rank or d<rank) then best,rank=item,d end
		end
	end
	return best,best and 'equipment' or nil
end

local function detonatePipe(pipe,at)
	if not pipe.Parent or pipe:GetAttribute('GWAPPipeBlown') then return end
	pipe:SetAttribute('GWAPPipeBlown',true)
	local blast=Instance.new('Explosion')
	blast.Position=at or pipe.Position
	blast.BlastRadius=26; blast.BlastPressure=260000
	blast.DestroyJointRadiusPercent=0
	blast.Parent=workspace
	for i=1,4 do
		local flare=Instance.new('Part')
		flare.Anchored=true; flare.CanCollide=false; flare.CanQuery=false; flare.Transparency=1
		flare.Size=Vector3.new(1,1,1)
		flare.CFrame=CFrame.new((at or pipe.Position)+Vector3.new(random:NextNumber(-7,7),random:NextNumber(-2,3),random:NextNumber(-7,7)))
		flare.Parent=workspace
		local fire=Instance.new('Fire'); fire.Size=9; fire.Heat=8; fire.Parent=flare
		local smoke=Instance.new('Smoke'); smoke.Size=8; smoke.Opacity=.5; smoke.Parent=flare
		Debris:AddItem(flare,9)
	end
	task.delay(12,function() if pipe.Parent then pipe:SetAttribute('GWAPPipeBlown',false) end end)
end

local function fireAt(bot,state,root,player)
	local gun=bot:FindFirstChild('SoloWeapon')
	local origin=gun and (gun.Position+gun.CFrame.LookVector*(-gun.Size.Z*.5)) or bot:GetPivot().Position+Vector3.new(0,1,0)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=shotIgnore(bot)

	-- Sometimes shoot the room instead of the person.
	if random:NextNumber()<HAZARD_CHANCE then
		local hazard,kind=hazardNear(root.Position,origin)
		if hazard then
			local d=hazard.Position-origin
			local look=workspace:Raycast(origin,d,params)
			if look and (look.Instance==hazard or look.Instance:IsDescendantOf(hazard)) then
				state.nextShot=os.clock()+SHOT_INTERVAL*2
				if kind=='pipe' then detonatePipe(hazard,look.Position) else explode(hazard,nil) end
				player:SetAttribute('GWAPNotice','A worker detonated the '..(kind=='pipe' and 'gas line' or hazard.Name)..' beside you.')
				return
			end
		end
	end

	local aim=root.Position
	local delta=aim-origin
	local sight=workspace:Raycast(origin,delta,params)
	if not sight then return end
	if not sight.Instance:IsDescendantOf(player.Character) then
		-- No clean line. If the obstruction is greenhouse glass, shoot it out;
		-- the next shot then has the line.
		local inGreenhouse=sight.Instance:FindFirstAncestor('RooftopGreenhouse')
		local looksGlass=sight.Instance.Transparency>.25 or string.find(string.lower(sight.Instance.Name),'glass',1,true)
		if inGreenhouse and looksGlass then
			state.nextShot=os.clock()+SHOT_INTERVAL
			breakGlass(sight.Instance)
		end
		return
	end

	-- Clean line: the shot connects. No spread is applied.
	state.nextShot=os.clock()+SHOT_INTERVAL
	local endpoint=sight.Position
	local beam=Instance.new('Part')
	beam.Name='NPC shot'; beam.Anchored=true; beam.CanCollide=false; beam.CanQuery=false
	beam.Material=Enum.Material.Neon; beam.Color=Color3.fromRGB(255,105,72)
	beam.Size=Vector3.new(.07,.07,(endpoint-origin).Magnitude)
	beam.CFrame=CFrame.lookAt((origin+endpoint)/2,endpoint)
	beam.Parent=workspace; Debris:AddItem(beam,.18)

	local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
	if hum and hum.Health>0 then
		local dealt=spendDamage(player,HOSTILE_DAMAGE,INCOMING_CAP)
		if dealt>0 then hum:TakeDamage(dealt) end
	end
	local v=points(player)
	if v then
		local debt=(player:GetAttribute('GWAPFractionalLoss') or 0)+math.max(0,v.Value)*.01
		local loss=math.floor(debt+1e-8); player:SetAttribute('GWAPFractionalLoss',debt-loss)
		v.Value=math.max(0,v.Value-loss)
	end
	player:SetAttribute('GWAPNotice','Hit by a worker: -1% score')
	player:SetAttribute('GWAPHitAt',workspace:GetServerTimeNow())
end

task.spawn(function()
	local last=os.clock()
	while true do
		local dt=os.clock()-last; last=os.clock()
		task.wait(.1)
		if workspace:GetAttribute('RoundPhase')=='BREAK' then
			for bot in pairs(hostiles) do dropHostile(bot) end
			continue
		end
		-- Retire anyone who is down, and top the roster back up from the rooms
		-- the players are near right now.
		for bot,state in pairs(hostiles) do
			if not botUsable(bot) then dropHostile(bot) end
		end
		for _,player in ipairs(Players:GetPlayers()) do
			local root=alive(player)
			if root then releaseNear(root) end
		end
		-- Drive the awake ones.
		for bot,state in pairs(hostiles) do
			if botUsable(bot) then
				local bp=bot:GetPivot().Position
				local best,bestRoot,bestPlayer,bestDist
				for _,player in ipairs(Players:GetPlayers()) do
					local root=alive(player)
					if root then
						local d=(root.Position-bp).Magnitude
						if d<HOSTILE_RANGE and (not bestDist or d<bestDist) then
							best,bestRoot,bestPlayer,bestDist=root.Position,root,player,d
						end
					end
				end
				-- The escorted carrier is a target too, so the Technician has
				-- something to actually protect.
				local carrierGoal,carrierDist
				for _,a in pairs(carriers) do
					if active(a) and a.bot~=bot then
						local d=(a.bot:GetPivot().Position-bp).Magnitude
						if d<HOSTILE_RANGE and (not carrierDist or d<carrierDist) then
							carrierGoal,carrierDist=a.bot,d
						end
					end
				end
				-- A carrier hunter stays on the carrier while it is in range; anyone
				-- else only switches to it when it is clearly the nearer target.
				local goCarrier=carrierGoal and (state.huntsCarrier or not bestDist or carrierDist<bestDist*.45)
				if goCarrier then
					stepHostile(bot,state,carrierGoal:GetPivot().Position,dt)
					if os.clock()>=state.nextShot and carrierDist<HOSTILE_RANGE then
						state.nextShot=os.clock()+SHOT_INTERVAL
						local dealt=spendDamage(carrierGoal,CARRIER_DAMAGE,CARRIER_INCOMING_CAP)
						if dealt>0 then damage(nil,carrierGoal,dealt) end
					end
				elseif bestRoot then
					stepHostile(bot,state,best,dt)
					if os.clock()>=state.nextShot then fireAt(bot,state,bestRoot,bestPlayer) end
				elseif os.clock()-state.since>40 then
					dropHostile(bot)
				end
			end
		end
		workspace:SetAttribute('GWAPHostileCount',hostileCount())
	end
end)
workspace:GetAttributeChangedSignal('RoundNumber'):Connect(function()
	for _,a in pairs(carriers) do if active(a) then finish(a,'SHIFT ENDED') end end
	for _,p in ipairs(Players:GetPlayers()) do p:SetAttribute('GWAPFractionalLoss',0) end
	for item in pairs(equipmentOriginal) do repair(item) end
	for _,bed in ipairs(stations:GetChildren()) do if bed:GetAttribute('Planted') then for _,v in ipairs(bed:GetChildren()) do if v:IsA('Model') then v:Destroy() end end; bed:SetAttribute('Planted',0); local sign=bed:FindFirstChild('StationLabel'); local label=sign and sign:FindFirstChildOfClass('TextLabel'); if label then label.Text=bed.Name..' | Ready for planting' end end end
	setArmed()
end)
print('[GWAP] 2 role assignments, research carriers, rooftop planting and hostile ambush ready')