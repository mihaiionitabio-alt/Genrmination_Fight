--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ServerScriptService.GWAPWallDamage
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Wall fixture lifecycle
Future change: Replace name-pattern coupling with explicit wall/fixture association when geometry is refactored. Define restoration.
Preserve dependencies: Legacy gas detonation, research stations, prompts and tags.
Acceptance cases: Near/outside fixture, rotated wall, two blasts, round reset, old callback after quarantine.
]========]
-- Remove fixtures belonging to a wall section destroyed by an explosion.
local CS=game:GetService('CollectionService')
local c=workspace:WaitForChild('Laboratory_Complex')
local debris=Instance.new('Folder'); debris.Name='DestroyedWallFixtures'; debris.Parent=game:GetService('ServerStorage')
local fixtures={}; local recent={}
local function register(v)
	if not v:IsA('BasePart') then return end
	if v:GetAttribute('ToolKind') or v:GetAttribute('ShootablePoster') or v.Name:match('^HealthStation')
		or CS:HasTag(v,'LabEquipment') or CS:HasTag(v,'PlantGrowthChamber') or v:GetAttribute('GWAPEquipment')
		or (v.Parent and v.Parent.Name=='Stations') then fixtures[v]=true end
end
for _,v in ipairs(c:GetDescendants()) do register(v) end
c.DescendantAdded:Connect(register)
CS:GetInstanceAddedSignal('LabEquipment'):Connect(register)
workspace.DescendantAdded:Connect(function(v)
	if v:IsA('Explosion') then table.insert(recent,{position=v.Position,radius=v.BlastRadius,time=os.clock()}) end
	while #recent>0 and os.clock()-recent[1].time>3 do table.remove(recent,1) end
end)
c.DescendantRemoving:Connect(function(wall)
	if not wall:IsA('BasePart') or not (wall.Name:match('^Corridor_') or wall.Name:match('^Div_') or wall.Name:match('^Ext_') or wall.Name:match('^B_')) then return end
	local cf,size=wall.CFrame,wall.Size
	local exploded=false
	for _,blast in ipairs(recent) do if os.clock()-blast.time<3 then
		local localPoint=cf:PointToObjectSpace(blast.position)
		local closest=Vector3.new(math.clamp(localPoint.X,-size.X/2,size.X/2),math.clamp(localPoint.Y,-size.Y/2,size.Y/2),math.clamp(localPoint.Z,-size.Z/2,size.Z/2))
		if (localPoint-closest).Magnitude<=blast.radius then exploded=true; break end
	end end
	if not exploded then return end
	task.defer(function()
		if not c.Parent then return end
		local pad=Vector3.new(size.X<4 and 7 or 1,1,size.Z<4 and 7 or 1)
		local half=size/2+pad
		local count=0
		for item in pairs(fixtures) do if item:IsDescendantOf(c) then
			local pos=cf:PointToObjectSpace(item.Position)
			if math.abs(pos.X)<=half.X and math.abs(pos.Y)<=half.Y and math.abs(pos.Z)<=half.Z then
				item:SetAttribute('BlastRemoved',true); item:SetAttribute('FunctionalState','DESTROYED'); item:SetAttribute('Exploded',true)
				for _,v in ipairs(item:GetDescendants()) do if v:IsA('ProximityPrompt') then v.Enabled=false end end
				for _,tag in ipairs(CS:GetTags(item)) do CS:RemoveTag(item,tag) end
				item.Parent=debris; count+=1
			end
		end end
		workspace:SetAttribute('GWAPRemovedFixtures',(workspace:GetAttribute('GWAPRemovedFixtures') or 0)+count)
	end)
end)