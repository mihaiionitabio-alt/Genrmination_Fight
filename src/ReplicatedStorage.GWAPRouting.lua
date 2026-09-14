local R={}
local function floorOf(item)
	local n=item:GetAttribute('Floor'); if n then return n end
	local label=item:GetAttribute('Level') or ''; return label=='Basement' and -1 or (tonumber(label:match('%d+')) or 1)-1
end
R.floorOf=floorOf
function R.healthy(item)
	return item and item:IsDescendantOf(workspace) and not item:GetAttribute('Exploded') and not item:GetAttribute('BlastRemoved') and item:GetAttribute('FunctionalState')~='DESTROYED' and item:GetAttribute('FunctionalState')~='FAILED'
end
function R.ensureBackups()
	local stations=workspace:WaitForChild('Laboratory_Complex'):WaitForChild('GWAPResearch'):WaitForChild('Stations')
	local originals=stations:GetChildren(); local perFloor={}
	table.sort(originals,function(a,b)return a.Name<b.Name end)
	for _,item in ipairs(originals) do if item:IsA('BasePart') and not item:GetAttribute('Backup') then
		local capability=item:GetAttribute('Planted')~=nil and 'Greenhouse planting' or item.Name
		item:SetAttribute('Capability',capability)
		if capability~='Greenhouse planting' then for variant=1,2 do
			local name=item.Name..' - Backup '..variant
			if not stations:FindFirstChild(name) then
				local copy=item:Clone(); copy.Name=name; copy:SetAttribute('Backup',true); copy:SetAttribute('Capability',capability)
				local floor=floorOf(item); if variant==2 then floor=(floor+2)%4-1 end
				local z=item.Position.Z; local x=89
				if variant==2 then perFloor[floor]=(perFloor[floor] or 0)+1; z=150+perFloor[floor]*14; x=67 end
				local pos=Vector3.new(x,floor*16.25+1.5,z); local shift=pos-copy.Position
				copy.Position=pos; for _,p in ipairs(copy:GetDescendants()) do if p:IsA('BasePart') then p.Position+=shift end end
				copy:SetAttribute('Floor',floor); copy:SetAttribute('Approach',Vector3.new(78,floor*16.25+3.25,z))
				copy:SetAttribute('Exploded',false); copy:SetAttribute('FunctionalState','RUNNING')
				local sign=copy:FindFirstChild('StationLabel'); local label=sign and sign:FindFirstChildOfClass('TextLabel'); if label then label.Text=capability..' | Backup | '..(floor==-1 and 'B1' or 'L'..(floor+1)) end
				copy.Parent=stations
			end
		end end
	end end
	return stations
end
-- reachable(item) is supplied by the caller (GWAPServer passes the navigation
-- probe). A station with no walkable approach is ranked below every reachable
-- one instead of being chosen and then stranding the carrier.
function R.choose(stations,capability,preferredFloor,position,reachable)
	local best,rank
	for _,item in ipairs(stations:GetChildren()) do if item:GetAttribute('Capability')==capability and R.healthy(item) and ((item:GetAttribute('Planted') or 0)<12) then
		local score=(floorOf(item)==preferredFloor and 0 or 100000)+math.abs(floorOf(item)-preferredFloor)*1000+(item.Position-position).Magnitude
		if reachable and not reachable(item) then score+=10000000 end
		if not rank or score<rank then best,rank=item,score end
	end end
	return best
end
return R