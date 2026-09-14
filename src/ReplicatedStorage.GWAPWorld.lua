-- Idempotent additive build: research stations, final roof flight and greenhouse.
local W = {}
local function part(parent, name, size, pos, color, material)
	local p = Instance.new('Part'); p.Name=name; p.Size=size; p.Position=pos
	p.Anchored=true; p.Color=color or Color3.fromRGB(49,66,70); p.Material=material or Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth; p.Parent=parent; return p
end
local function label(p, text)
	local g=Instance.new('BillboardGui'); g.Name='StationLabel'; g.Size=UDim2.fromOffset(210,44); g.StudsOffset=Vector3.new(0,3,0); g.MaxDistance=65; g.Parent=p
	local t=Instance.new('TextLabel'); t.Size=UDim2.fromScale(1,1); t.BackgroundColor3=Color3.fromRGB(24,32,38); t.BackgroundTransparency=.18; t.TextColor3=Color3.fromRGB(220,255,235); t.TextSize=13; t.Font=Enum.Font.GothamBold; t.TextWrapped=true; t.Text=text; t.Parent=g
end
function W.plant(parent, pos, name)
	local m=Instance.new('Model'); m.Name=name or 'Germinated seed'; m.Parent=parent
	part(m,'Root plug',Vector3.new(.7,.5,.7),pos,Color3.fromRGB(94,65,43))
	part(m,'Stem',Vector3.new(.12,1.4,.12),pos+Vector3.new(0,.8,0),Color3.fromRGB(77,148,53))
	for i=-1,1,2 do local p=part(m,'Leaf',Vector3.new(.85,.12,.5),pos+Vector3.new(i*.35,1.1,0),Color3.fromRGB(102,202,77)); p.CFrame*=CFrame.Angles(0,0,i*.4) end
	for _,p in ipairs(m:GetChildren()) do p.CanCollide=false; p.CanQuery=false end
	return m
end
function W.build()
	local c=workspace:WaitForChild('Laboratory_Complex'); local old=c:FindFirstChild('GWAPResearch')
	if old then return old end
	local f=Instance.new('Folder'); f.Name='GWAPResearch'; f.Parent=c
	local stations=Instance.new('Folder'); stations.Name='Stations'; stations.Parent=f
	local specs={
		{'Seed bank',-1},{'Incubator',0},{'Containment',1},{'Bio-analyzer',2},
		{'Spectrograph',1},{'Infrared scanner',2},{'Chemical seedlings',-1},{'Root analyzer',1},
		{'Split-root tray',0},{'Centrifuge',2},{'UV chamber',1},{'Clinostat',-1},
		{'Orientation scanner',0},{'Climate chamber',2},{'Porometer',1},{'Wet lab',-1},
		{'Symbiosis incubator',1},{'Cryo-freezer',-1},{'Vitality scanner',0}}
	local perFloor={}
	for _,s in ipairs(specs) do
		local n=(perFloor[s[2]] or 0)+1; perFloor[s[2]]=n
		local p=part(stations,s[1],Vector3.new(3,3,5),Vector3.new(67,s[2]*16.25+1.5,32+n*17))
		p:SetAttribute('Floor',s[2]); p:SetAttribute('Approach',Vector3.new(78,s[2]*16.25+3.25,p.Position.Z))
		local glass=part(p,'Observation window',Vector3.new(3.05,1.4,3),p.Position+Vector3.new(0,.6,0),Color3.fromRGB(113,232,204),Enum.Material.Glass); glass.Transparency=.45
		part(p,'Status light',Vector3.new(.15,.25,3),p.Position+Vector3.new(1.6,1.3,0),Color3.fromRGB(95,255,141),Enum.Material.Neon)
		label(p,s[1]..' | '..(s[2]==-1 and 'B1' or 'L'..(s[2]+1)))
		W.plant(p,p.Position+Vector3.new(0,1.7,0),'Reference seedling')
	end
	-- Extend the existing north stair geometry by one flight, preserving player controls.
	local tower=c:FindFirstChild('StairTower_North')
	if tower then
		for _,p in ipairs(tower:GetChildren()) do
			if p:IsA('BasePart') and (p.Name:match('^Flight[AB]_L6_') or p.Name=='MidLanding_L6' or p.Name=='Handrail_L6') then
				local q=p:Clone(); q.Name=p.Name:gsub('L6','L7'); q.Position+=Vector3.new(0,16.25,0); q.Parent=f
			end
		end
		local cap=tower:FindFirstChild('T_Roof'); if cap then cap:SetAttribute('GWAPOriginalCanCollide',cap.CanCollide); cap.CanCollide=false; cap.Transparency=1; cap.CanQuery=false end
		part(f,'Roof stair landing',Vector3.new(41.14,.75,12.86),Vector3.new(78.43,129.625,-6.43))
	end
	local parapet=c:FindFirstChild('Parapet_N_1')
	if parapet then
		parapet:SetAttribute('GWAPOriginalCanCollide',parapet.CanCollide); parapet.CanCollide=false; parapet.Transparency=1; parapet.CanQuery=false
		local left=parapet.Position.X-parapet.Size.X/2; local right=parapet.Position.X+parapet.Size.X/2
		for _,range in ipairs({{left,71},{86,right}}) do part(f,'Roof entry parapet',Vector3.new(range[2]-range[1],parapet.Size.Y,parapet.Size.Z),Vector3.new((range[1]+range[2])/2,parapet.Position.Y,parapet.Position.Z),parapet.Color) end
	end
	local g=Instance.new('Model'); g.Name='RooftopGreenhouse'; g.Parent=f
	local y=130
	part(g,'Foundation',Vector3.new(100,.35,112),Vector3.new(78,y+.175,90),Color3.fromRGB(190,200,190))
	for _,x in ipairs({28,128}) do for z=34,146,28 do part(g,'Steel upright',Vector3.new(.4,15,.4),Vector3.new(x,y+7.5,z)) end end
	for _,x in ipairs({28,128}) do local p=part(g,'Glazed wall',Vector3.new(.25,14,112),Vector3.new(x,y+7.4,90),Color3.fromRGB(184,223,222),Enum.Material.Glass); p.Transparency=.72 end
	for _,z in ipairs({34,146}) do
		for _,range in ipairs({{28,70},{86,128}}) do local p=part(g,'Entry glass',Vector3.new(range[2]-range[1],14,.25),Vector3.new((range[1]+range[2])/2,y+7.4,z),Color3.fromRGB(184,223,222),Enum.Material.Glass); p.Transparency=.72 end
		part(g,'Door lintel',Vector3.new(100,.5,.5),Vector3.new(78,y+14.5,z))
	end
	for z=34,146,14 do part(g,'Roof rib',Vector3.new(100,.3,.3),Vector3.new(78,y+15,z)) end
	local roof=part(g,'Glass roof',Vector3.new(100,.25,112),Vector3.new(78,y+15,90),Color3.fromRGB(190,235,230),Enum.Material.Glass); roof.Transparency=.8
	local sign=part(g,'Greenhouse sign',Vector3.new(14,1,1),Vector3.new(78,y+11,34),Color3.fromRGB(60,175,113)); label(sign,'ROOFTOP GREENHOUSE | Research plots')
	for i=1,10 do
		local x=i%2==1 and 48 or 108; local z=48+math.floor((i-1)/2)*20
		local bed=part(stations,'Plot '..i,Vector3.new(22,1,12),Vector3.new(x,y+.8,z),Color3.fromRGB(91,65,44),Enum.Material.Ground)
		bed:SetAttribute('Floor',8); bed:SetAttribute('Approach',Vector3.new(78,y+3.6,z)); bed:SetAttribute('Planted',0)
		label(bed,'PLOT '..i..' | Ready for planting')
		for _,dz in ipairs({-6,6}) do part(g,'Bed border',Vector3.new(23,1.4,.4),Vector3.new(x,y+.7,z+dz),Color3.fromRGB(132,112,80),Enum.Material.Wood) end
		local prompt=Instance.new('ProximityPrompt'); prompt.Name='PlantSeedling'; prompt.ActionText='Plant carried seedling'; prompt.ObjectText='Research plot '..i; prompt.KeyboardKeyCode=Enum.KeyCode.E; prompt.HoldDuration=1; prompt.MaxActivationDistance=12; prompt.Parent=bed
	end
	return f
end
return W