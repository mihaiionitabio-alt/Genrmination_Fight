-- Shared NPC presentation uses the same original Weapons Kit assets as player inventory.
local N={}
local specs={
	{name='Lab Sidearm',mesh='rbxassetid://2492922600',texture='rbxassetid://2492931263',scale=.1407,size=Vector3.new(.20,.92,1.36)},
	{name='Lab Shotgun',mesh='rbxassetid://2492972199',texture='rbxassetid://2492974190',scale=.6666,size=Vector3.new(.31,1,4.87)},
	{name='Lab Rifle',mesh='rbxassetid://2759059561',texture='rbxassetid://2759063893',scale=.6383,size=Vector3.new(.29,1.17,6.18)},
}
function N.gun(bot,index)
	local old=bot:FindFirstChild('SoloWeapon'); if old then old:Destroy() end
	local spec=specs[(index-1)%#specs+1]; local arm=bot:FindFirstChild('ArmR') or bot:FindFirstChild('Right Arm') or bot.PrimaryPart
	if not arm then return end
	local p=Instance.new('Part'); p.Name='SoloWeapon'; p.Size=spec.size; p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
	p.CFrame=arm.CFrame*CFrame.new(0,-.35,-.7)*CFrame.Angles(0,math.pi,0); p.Color=Color3.fromRGB(126,133,145)
	local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.FileMesh; mesh.MeshId=spec.mesh; mesh.TextureId=spec.texture; mesh.Scale=Vector3.one*spec.scale; mesh.Parent=p
	p:SetAttribute('InventoryName',spec.name); p.Parent=bot; bot:SetAttribute('NPCGun',spec.name)
	return p
end
function N.appearance(bot)
	if bot:GetAttribute('Gender')~='Girl' then return end
	local head=bot:FindFirstChild('Head'); if not head or bot:FindFirstChild('ResearchHair') then return end
	local hair=bot:FindFirstChild('HairCrown'); local color=hair and hair.Color or Color3.fromRGB(67,39,25)
	local folder=Instance.new('Model'); folder.Name='ResearchHair'; folder.Parent=bot
	local function piece(name,size,offset)
		local p=Instance.new('Part'); p.Name=name; p.Size=size; p.CFrame=head.CFrame*CFrame.new(offset); p.Color=color; p.Material=Enum.Material.SmoothPlastic; p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.Parent=folder; return p
	end
	piece('Back hair',Vector3.new(1.23,1.7,.34),Vector3.new(0,-.25,.55))
	for _,side in ipairs({-1,1}) do piece('Side locks',Vector3.new(.28,1.25,.58),Vector3.new(side*.58,-.15,.15)) end
	local pony=piece('Tied ponytail',Vector3.new(.55,1.3,.65),Vector3.new(0,-.25,.9)); pony.Shape=Enum.PartType.Ball
	local tie=piece('Hair tie',Vector3.new(.6,.16,.66),Vector3.new(0,.25,.9)); tie.Color=Color3.fromRGB(107,174,174)
end
function N.say(bot,message)
    bot:SetAttribute('MissionMessage',message)
    bot:SetAttribute('MissionMessageAt',workspace:GetServerTimeNow())
    local old=bot:FindFirstChild('MissionSpeech',true);if old then old:Destroy() end
end
function N.nearPlayer(player,bot)
	local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart'); if not root then return false end
	local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={player.Character,bot}; params.RespectCanCollide=true
	local overlap=OverlapParams.new(); overlap.FilterType=Enum.RaycastFilterType.Exclude; overlap.FilterDescendantsInstances={player.Character,bot}; overlap.RespectCanCollide=true
	for _,offset in ipairs({Vector3.new(5,0,-6),Vector3.new(-5,0,-6),Vector3.new(7,0,0),Vector3.new(-7,0,0),Vector3.new(0,0,8)}) do
		local pos=root.CFrame:PointToWorldSpace(offset)
		local floor=workspace:Raycast(pos+Vector3.new(0,3,0),Vector3.new(0,-10,0),params)
		local sight=workspace:Raycast(root.Position,pos-root.Position,params)
		if floor and floor.Normal.Y>.7 and not sight then
			pos=Vector3.new(pos.X,floor.Position.Y+3.25,pos.Z)
			if #workspace:GetPartBoundsInBox(CFrame.new(pos),Vector3.new(3,4.6,3),overlap)==0 then bot:PivotTo(CFrame.lookAt(pos,Vector3.new(root.Position.X,pos.Y,root.Position.Z))); return true end
		end
	end
	return false
end

local poses=setmetatable({}, {__mode='k'})
function N.animate(bot,dt)
	local root=bot.PrimaryPart; if not root then return end
	local data=poses[bot]
	if not data then
		data={parts={},previous=root.Position,phase=0,blend=0}
		for _,name in ipairs({'LegL','LegR','ArmL','ArmR','Trainer-1','Trainer1','Sole-1','Sole1'}) do
			local p=bot:FindFirstChild(name); if p then data.parts[name]={part=p,rest=root.CFrame:ToObjectSpace(p.CFrame)} end
		end
		poses[bot]=data
	end
	local distance=(root.Position-data.previous).Magnitude; data.previous=root.Position
	local speed=distance/math.max(dt,.001)
	if distance>8 then speed=0; distance=0 end -- regrouping is not a walking step
	data.phase+=distance*math.pi/3.2
	local moving=speed>.3 and 1 or 0
	data.blend+=(moving-data.blend)*(1-math.exp(-dt*16))
	local swing=math.sin(data.phase)*.42*data.blend
	for name,entry in pairs(data.parts) do if entry.part.Parent then
		local arm=name:sub(1,3)=='Arm'
		local left=name=='LegL' or name=='ArmL' or name:find('-1',1,true)
		local sign=left and -1 or 1
		local pivot=arm and Vector3.new(sign*1.18,.85,0) or Vector3.new(sign*.42,-1.05,0)
		local angle=arm and -swing*sign*.65 or swing*sign
		if arm and bot:GetAttribute('HasSeedling') then angle=-.4 end
		entry.part.CFrame=root.CFrame*CFrame.new(pivot)*CFrame.Angles(angle,0,0)*CFrame.new(-pivot)*entry.rest
	end end
	local gun=bot:FindFirstChild('SoloWeapon'); local arm=bot:FindFirstChild('ArmR')
	if gun and arm then gun.CFrame=arm.CFrame*CFrame.new(0,-.35,-.7)*CFrame.Angles(0,math.pi,0) end
end

return N