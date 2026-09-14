-- Two grouped panels. Native inventory and movement/fire controls remain available.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local StarterGui=game:GetService('StarterGui')
local prompts=game:GetService('ProximityPromptService')
local p=Players.LocalPlayer; local pg=p:WaitForChild('PlayerGui')
local scenarios=require(RS:WaitForChild('GWAPScenarios')); local remote=RS:WaitForChild('GWAPAction')
local research=workspace:WaitForChild('Laboratory_Complex'):WaitForChild('GWAPResearch')
local gui=Instance.new('ScreenGui'); gui.Name='GWAPHUD'; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=false; gui.DisplayOrder=25; gui.Parent=pg
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health,false) end)
local white=Color3.fromRGB(239,247,243)
local function box(name,parent)
	local f=Instance.new('Frame'); f.Name=name; f.BackgroundColor3=Color3.fromRGB(23,31,37); f.BackgroundTransparency=.12; f.BorderSizePixel=0; f.Parent=parent or gui; Instance.new('UICorner',f).CornerRadius=UDim.new(0,8); return f
end
local function label(parent,name,size)
	local t=Instance.new('TextLabel'); t.Name=name; t.BackgroundTransparency=1; t.Font=Enum.Font.GothamMedium; t.TextColor3=white; t.TextSize=size or 13; t.TextWrapped=true; t.TextTruncate=Enum.TextTruncate.AtEnd; t.TextXAlignment=Enum.TextXAlignment.Left; t.TextYAlignment=Enum.TextYAlignment.Center; t.Parent=parent; return t
end
local function button(parent,name,callback)
	local t=Instance.new('TextButton'); t.Name=name; t.Text=name; t.Font=Enum.Font.GothamBold; t.TextColor3=white; t.TextSize=11; t.BackgroundColor3=Color3.fromRGB(63,73,91); t.BorderSizePixel=0; t.Parent=parent; Instance.new('UICorner',t).CornerRadius=UDim.new(0,5); t.Activated:Connect(callback); return t
end
local strip=box('Round and player'); strip.AnchorPoint=Vector2.new(.5,0)
local teams=label(strip,'Team scores',13); teams.TextXAlignment=Enum.TextXAlignment.Center
local timer=label(strip,'Timer',18); timer.TextXAlignment=Enum.TextXAlignment.Center
local personal=label(strip,'Player',12); personal.TextXAlignment=Enum.TextXAlignment.Right
local health=box('Health',strip); health.BackgroundColor3=Color3.fromRGB(54,66,61)
local fill=box('Fill',health); fill.BackgroundColor3=Color3.fromRGB(100,235,68); fill.BackgroundTransparency=0; fill.Size=UDim2.fromScale(1,1)
local panel=box('Mission and conversation')
local heading=label(panel,'Heading',13); heading.Font=Enum.Font.GothamBold
local target=label(panel,'Destination',12); target.TextColor3=Color3.fromRGB(151,238,204)
local dialogue=label(panel,'Carrier message',12); dialogue.TextYAlignment=Enum.TextYAlignment.Top
local note=label(panel,'Status',10); note.TextColor3=Color3.fromRGB(216,202,158); note.TextTruncate=Enum.TextTruncate.AtEnd; note.TextWrapped=false
-- Assignments follow the role; there is no selection screen.
local buttons={}
for i,name in ipairs({'Ready','Wait','Status','Regroup'}) do buttons[i]=button(panel,name,function() remote:FireServer('reply',i) end) end
local trail=Instance.new('Folder'); trail.Name='LocalMissionTrail'; trail.Parent=workspace
local dots={}
for i=1,90 do local dot=Instance.new('Part'); dot.Name='Direction'; dot.Size=Vector3.new(.16,.12,1.6); dot.Anchored=true; dot.CanCollide=false; dot.CanQuery=false; dot.CanTouch=false; dot.Material=Enum.Material.Neon; dot.Color=Color3.fromRGB(103,255,198); dot.Transparency=1; dot.Parent=trail; dots[i]=dot end
local routeCache=setmetatable({}, {__mode='k'})
local function showTrail(bot)
	for _,v in ipairs(dots) do v.Transparency=1 end
	local route=bot and research.Routes:FindFirstChild(bot.Name); local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
	if not bot or not route or not root or bot:GetAttribute('State')~='RUNNING' then return end
	local record=routeCache[route]
	if not record then record={};routeCache[route]=record;route.ChildAdded:Connect(function() record.nodes=nil end);route.ChildRemoved:Connect(function() record.nodes=nil end) end
	local nodes=record.nodes
	if not nodes then nodes=route:GetChildren();table.sort(nodes,function(a,b)return a.Name<b.Name end);record.nodes=nodes end
	local previous=bot:GetPivot().Position; local n=0
	for j=bot:GetAttribute('RouteIndex') or 1,#nodes do
		local to=nodes[j].Value; local delta=to-previous
		if delta.Magnitude>.1 then for d=0,delta.Magnitude,4 do
			local pos=previous+delta.Unit*d-Vector3.new(0,2.9,0)
			if (pos-root.Position).Magnitude<110 and math.abs(pos.Y-root.Position.Y)<10 then n+=1; if n>#dots then return end; dots[n].CFrame=CFrame.lookAt(pos,pos+delta); dots[n].Transparency=.12 end
		end end; previous=to
	end
end
prompts.PromptShown:Connect(function(prompt)
	local viewport=workspace.CurrentCamera.ViewportSize
	prompt.UIOffset=Vector2.new(viewport.X<1000 and 70 or 0,0)
end)
local billboards=setmetatable({}, {__mode='k'})
local function watchBot(bot)
	if billboards[bot] then return end
	local items={}; for _,v in ipairs(bot:GetDescendants()) do if v:IsA('BillboardGui') then table.insert(items,v) end end; billboards[bot]=items
	bot.DescendantAdded:Connect(function(v) if v:IsA('BillboardGui') then table.insert(items,v) end end)
end
local cs=game:GetService('CollectionService')
for _,bot in ipairs(cs:GetTagged('LabWorkerBot')) do watchBot(bot) end
for _,bot in ipairs(research.Carriers:GetChildren()) do watchBot(bot) end
research.Carriers.ChildAdded:Connect(watchBot)
local elapsed=0
Run.RenderStepped:Connect(function(dt)
	elapsed+=dt; if elapsed<.15 then return end; elapsed=0
	local v=workspace.CurrentCamera.ViewportSize; local mobile=v.X<1000 or v.Y<500
	local width=math.min(mobile and 180 or 290,v.X*.25); local height=mobile and 150 or 218
	local scale=math.min(1,(v.Y-95)/height); scale=math.max(.6,scale)
	local touch=pg:FindFirstChild('TouchGui'); local thumb=touch and touch:FindFirstChild('ThumbstickStart',true)
	if mobile and thumb and thumb.Visible then scale=math.min(scale,math.max(.6,(thumb.AbsolutePosition.Y-48-8)/height)) end
	local ui=panel:FindFirstChildOfClass('UIScale') or Instance.new('UIScale',panel); ui.Scale=scale
	panel.Position=UDim2.fromOffset(8,48); panel.Size=UDim2.fromOffset(width/scale,height)
	local w=width/scale
	heading.Position=UDim2.fromOffset(8,6); heading.Size=UDim2.fromOffset(w-16,mobile and 25 or 36); heading.TextSize=mobile and 11 or 15
	target.Position=UDim2.fromOffset(8,mobile and 33 or 46); target.Size=UDim2.fromOffset(w-16,mobile and 26 or 34); target.TextSize=mobile and 10 or 13
	dialogue.Position=UDim2.fromOffset(8,mobile and 61 or 84); dialogue.Size=UDim2.fromOffset(w-16,mobile and 45 or 69); dialogue.TextSize=mobile and 10 or 13
	for i,b in ipairs(buttons) do b.Position=UDim2.fromOffset(8+(i-1)*(w-16)/4,height-43); b.Size=UDim2.fromOffset((w-20)/4-2,23); b.TextSize=mobile and 9 or 11 end
	note.Position=UDim2.fromOffset(8,height-18); note.Size=UDim2.fromOffset(w-16,14); note.TextSize=mobile and 9 or 11
	local sw=math.min(460,v.X-26); strip.Position=UDim2.new(.5,0,0,3); strip.Size=UDim2.fromOffset(sw,38)
	teams.Position=UDim2.fromOffset(7,3); teams.Size=UDim2.fromOffset(sw*.35,30); teams.TextSize=mobile and 10 or 13
	timer.Position=UDim2.fromOffset(sw*.38,0); timer.Size=UDim2.fromOffset(sw*.19,35)
	personal.Position=UDim2.fromOffset(sw*.59,0); personal.Size=UDim2.fromOffset(sw*.39-8,23); personal.TextSize=mobile and 10 or 12
	health.Position=UDim2.fromOffset(sw*.61,26); health.Size=UDim2.fromOffset(sw*.35,6)
	local own=p.Character and p.Character:FindFirstChild('LabHealthBar',true); if own then own.Enabled=false end
	for _,name in ipairs({'RoleHUD','LabLog'}) do local old=pg:FindFirstChild(name); if old then old.Enabled=false end end
	local sums={Technician=0,['Laboratory Technician']=0}
	for _,player in ipairs(Players:GetPlayers()) do local role=player:GetAttribute('LabRole'); local stats=player:FindFirstChild('leaderstats'); local value=stats and stats:FindFirstChild('Points'); if sums[role] then sums[role]+=value and value.Value or 0 end end
	teams.Text='PROTECT '..sums.Technician..'   |   STOP '..sums['Laboratory Technician']
	local remaining=math.max(0,(workspace:GetAttribute('RoundEndsAt') or os.time())-os.time()); timer.Text=string.format('%d:%02d',remaining//60,remaining%60)
	local stats=p:FindFirstChild('leaderstats'); local value=stats and stats:FindFirstChild('Points'); local hum=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
	personal.Text=(value and value.Value or 0)..' pts  |  '..math.ceil(hum and hum.Health or 0)..' HP'; fill.Size=UDim2.fromScale(hum and math.clamp(hum.Health/math.max(1,hum.MaxHealth),0,1) or 0,1)
	local id=p:GetAttribute('GWAPScenario'); local s=id and scenarios[id]; local name=p:GetAttribute('GWAPCarrier'); local bot=name and research.Carriers:FindFirstChild(name)
	heading.Text=s and s.title or 'RESEARCH ASSIGNMENT'
	local floor=p:GetAttribute('GWAPTargetFloor'); local location=floor and (floor==8 and 'ROOF' or floor==-1 and 'B1' or 'L'..(floor+1)) or ''
	target.Text=s and ((p:GetAttribute('GWAPTarget') or '')..'  '..location) or 'Choose a role kiosk, then tap Jobs.'
	if bot and s then target.Text..=' | NPC '..math.ceil(bot:GetAttribute('Health') or 100)..' HP' end
	dialogue.Text=p:GetAttribute('GWAPDialogue') or 'Your carrier will meet you nearby and wait for your Ready reply.'
	local carried=p:GetAttribute('CarriedSample') or ''; local notice=p:GetAttribute('GWAPNotice') or ''
	note.Text=carried~='' and 'Carrying: '..carried or notice
	local cam=workspace.CurrentCamera; local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={p.Character}
	local aim=workspace:Raycast(cam.CFrame.Position,cam.CFrame.LookVector*80,params)
	for npc,items in pairs(billboards) do
		local projected,onScreen=cam:WorldToViewportPoint(npc:GetPivot().Position+Vector3.new(0,5,0))
		local show=npc.Parent and npc~=bot and onScreen and projected.Y>120 and (aim and aim.Instance:IsDescendantOf(npc)) and (npc:GetPivot().Position-cam.CFrame.Position).Magnitude<65
		for _,billboard in ipairs(items) do if billboard.Parent then billboard.Enabled=show==true and billboard.Name~='MissionSpeech'; billboard.MaxDistance=65 end end
	end
	for _,station in ipairs(research.Stations:GetChildren()) do
		local sign=station:FindFirstChild('StationLabel')
		if sign then sign.Enabled=aim~=nil and (aim.Instance==station or aim.Instance:IsDescendantOf(station)) and (station.Position-cam.CFrame.Position).Magnitude<40 end
	end
	showTrail(bot)
end)