"""Revision 5 source build.

Starts from the PRE-Revision-4 baseline (documentation/.../code/baseline) and
re-applies only the Revision 4 changes that were correct on their own merits.

Deliberately NOT carried over from Revision 4:
  * ReplicatedStorage.LabSpatial and all 30 Spatial.* call sites. The laboratory
    was restored to its authored datum (Level_1 = 0, basement = -16.25,
    ground = -8), so the frame those calls composed is exactly identity and the
    baseline coordinates are correct as written.
  * The per-step workspace:Blockcast in the carrier walk loop. ~180 bots x one
    blockcast per tick is a performance regression, and it bypasses the existing
    room-occupancy gate that keeps most bots idle.
  * The two in-place documentation ModuleScripts (~228 KB of string data in the
    DataModel). The reference lives in D:\\game\\documentation.

Every replacement asserts its anchor occurs exactly once, so a drifted baseline
fails loudly instead of writing a half-patched file.
"""
from pathlib import Path
import json, hashlib

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / 'documentation/Genrmination_Fight/code/baseline'
OUT = ROOT / 'code'
OUT.mkdir(exist_ok=True)

if not BASE.is_dir():
    raise SystemExit(f'Baseline tree missing: {BASE}')

def read(name):
    return (BASE / (name + '.lua')).read_text(encoding='utf-8')

def replace(s, old, new, n=1):
    got = s.count(old)
    assert got == n, (old[:90], got, n)
    return s.replace(old, new)

written = {}
def save(path_in_game, class_name, source):
    fn = path_in_game + '.lua'
    data = source.encode('utf-8')
    (OUT / fn).write_bytes(data)
    written[path_in_game] = dict(path=path_in_game, cls=class_name, file=fn,
                                 bytes=len(data), sha256=hashlib.sha256(data).hexdigest())

# --------------------------------------------------------------------------
# GWAPWorld, GWAPRouting, LabEquipment: Revision 4 touched these ONLY through
# LabSpatial. Restored verbatim from baseline.
# --------------------------------------------------------------------------
save('ReplicatedStorage.GWAPWorld', 'ModuleScript', read('ReplicatedStorage.GWAPWorld'))
save('ServerScriptService.LabEquipment', 'Script', read('ServerScriptService.LabEquipment'))

# --------------------------------------------------------------------------
# GWAPRouting: keep only the FAILED-equipment exclusion.
# A station left in FAILED state was still offered as a mission target, so a
# reroute could pick the very equipment that had just failed.
# --------------------------------------------------------------------------
r = read('ReplicatedStorage.GWAPRouting')
r = replace(r,
    "and item:GetAttribute('FunctionalState')~='DESTROYED'",
    "and item:GetAttribute('FunctionalState')~='DESTROYED' and item:GetAttribute('FunctionalState')~='FAILED'")
save('ReplicatedStorage.GWAPRouting', 'ModuleScript', r)

# --------------------------------------------------------------------------
# GWAPServer: server-side authority, NPC eligibility, route cleanup.
# --------------------------------------------------------------------------
s = read('ServerScriptService.GWAPServer')
s = replace(s,
    "local NPC=require(RS:WaitForChild('GWAPNPC'))",
    "local NPC=require(RS:WaitForChild('GWAPNPC'))\nlocal refreshArmed=function() end")

# Client prompt visibility is not authority: re-validate role, distance, state
# and line of sight on the server before repairing equipment.
s = replace(s,
    "prompt.Triggered:Connect(function(p) local r=alive(p); if r and (r.Position-item.Position).Magnitude<14 and item:GetAttribute('Exploded') then repair(item); p:SetAttribute('GWAPNotice',item.Name..' repaired. Ready for research.') end end)",
    """prompt.Triggered:Connect(function(p)
        local root=alive(p)
        if not root or role(p)~='Technician' or not item:IsDescendantOf(workspace)
            or item:GetAttribute('BlastRemoved') or not item:GetAttribute('Exploded')
            or (root.Position-item.Position).Magnitude>14 then return end
        local head=p.Character:FindFirstChild('Head') or root
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.Character}
        local hit=workspace:Raycast(head.Position,item.Position-head.Position,params)
        if hit and hit.Instance~=item and not hit.Instance:IsDescendantOf(item) then return end
        repair(item);p:SetAttribute('GWAPNotice',item.Name..' repaired. Ready for research.')
    end)""")

# Equipment removed by a wall blast must not be caught by a later blast radius.
s = replace(s,
    "if item.Parent and not item:GetAttribute('Exploded') and (item.Position-center).Magnitude",
    "if item:IsDescendantOf(workspace) and not item:GetAttribute('BlastRemoved') and not item:GetAttribute('Exploded') and (item.Position-center).Magnitude")

# Only living, in-world bots are eligible to be armed; strip weapons from the rest.
s = replace(s,
    "local all=CS:GetTagged('LabWorkerBot'); for _,bot in ipairs(available) do table.insert(all,bot) end",
    """local all={};local candidates=CS:GetTagged('LabWorkerBot')
    for _,bot in ipairs(available) do table.insert(candidates,bot) end
    for _,bot in ipairs(candidates) do
        if bot:IsDescendantOf(workspace) and not bot:GetAttribute('Dead') and not bot:GetAttribute('KnockedOut') and (bot:GetAttribute('Health') or 100)>0 then table.insert(all,bot)
        else bot:SetAttribute('GWAPArmed',false);local gun=bot:FindFirstChild('SoloWeapon');if gun then gun:Destroy() end end
    end""")

# Rebuilding a bot's weapon model on every pass was pure churn; keep the model
# and only create or destroy it when eligibility actually changes.
s = replace(s,
    "\t\tlocal gun=bot:FindFirstChild('SoloWeapon'); if gun then gun:Destroy() end\n\t\tif yes then\n\t\t\ttable.insert(armed,bot); NPC.gun(bot,(bot:GetAttribute('BotNumber') or 1))\n\t\tend",
    "\t\tlocal gun=bot:FindFirstChild('SoloWeapon')\n\t\tif yes then table.insert(armed,bot);if not gun then NPC.gun(bot,(bot:GetAttribute('BotNumber') or 1)) end\n\t\telseif gun then gun:Destroy() end")

s = replace(s, 'local retired={', "refreshArmed=setArmed\nlocal retired={")
s = replace(s,
    "NPC.say(bot,'Hello! Choose an assignment and I will explain our research route.')",
    "NPC.say(bot,'Hello! Choose an assignment and I will explain our research route.');task.defer(refreshArmed)")

# Recompute eligibility on a 5 s tick, keyed on a cheap signature, so knockout and
# recovery are reflected without rebuilding guns on every shot.
s = replace(s, "setArmed()\ntask.spawn(function()",
    """setArmed()
local lastEligible=''
task.spawn(function() while task.wait(5) do
    local names={}
    for _,bot in ipairs(CS:GetTagged('LabWorkerBot')) do if bot:IsDescendantOf(workspace) and not bot:GetAttribute('Dead') and not bot:GetAttribute('KnockedOut') and (bot:GetAttribute('Health') or 100)>0 then table.insert(names,bot.Name) end end
    for _,bot in ipairs(available) do if bot:IsDescendantOf(workspace) and (bot:GetAttribute('Health') or 100)>0 then table.insert(names,bot.Name) end end
    table.sort(names);local key=tostring(#Players:GetPlayers())..':'..table.concat(names,'|')
    if key~=lastEligible then lastEligible=key;setArmed() end
end end)
task.spawn(function()""")

# Discard a mission's route nodes as soon as it finishes.
s = replace(s, "publish(a); a.finishedAt=os.clock(); tell(a,",
    "local route=routesFolder:FindFirstChild(a.bot.Name);if route then route:Destroy() end\n\tpublish(a); a.finishedAt=os.clock(); tell(a,")
save('ServerScriptService.GWAPServer', 'Script', s)

# --------------------------------------------------------------------------
# LoungeSystems: shared signs must show broadcast-filtered text, never raw chat.
# --------------------------------------------------------------------------
l = read('ServerScriptService.LoungeSystems')
l = replace(l, 'local TweenService = game:GetService("TweenService")',
    'local TweenService = game:GetService("TweenService")\nlocal TextService=game:GetService("TextService")\nlocal noteCooldown={}')
l = replace(l,
    '\t\tnote = string.sub(note, 1, 90)\n\t\ttable.insert(notes, player.Name .. ":  " .. note)',
    """        if os.clock()-(noteCooldown[player] or -math.huge)<3 then return end
        noteCooldown[player]=os.clock()
        note=string.sub(note,1,90)
        local ok,filtered=pcall(function()
            return TextService:FilterStringAsync(note,player.UserId):GetNonChatStringForBroadcastAsync()
        end)
        if not ok or not player.Parent or not player:GetAttribute('InLounge') then return end
        table.insert(notes,player.Name..":  "..filtered)""")
l += "\nPlayers.PlayerRemoving:Connect(function(player) noteCooldown[player]=nil;skips[player.UserId]=nil end)\n"
save('ServerScriptService.LoungeSystems', 'Script', l)

# --------------------------------------------------------------------------
# LabHUD: one watcher per model, cached route nodes, no off-screen billboards.
# --------------------------------------------------------------------------
h = read('StarterPlayer.StarterPlayerScripts.LabHUD')
h = replace(h, 'local function watchBot(bot)\n\tlocal items={};',
    "local function watchBot(bot)\n\tif billboards[bot] then return end\n\tlocal items={};")
h = replace(h, 'local function showTrail(bot)',
    "local routeCache=setmetatable({}, {__mode='k'})\nlocal function showTrail(bot)")
h = replace(h,
    'local nodes=route:GetChildren(); table.sort(nodes,function(a,b) return a.Name<b.Name end)',
    "local record=routeCache[route]\n\tif not record then record={};routeCache[route]=record;route.ChildAdded:Connect(function() record.nodes=nil end);route.ChildRemoved:Connect(function() record.nodes=nil end) end\n\tlocal nodes=record.nodes\n\tif not nodes then nodes=route:GetChildren();table.sort(nodes,function(a,b)return a.Name<b.Name end);record.nodes=nodes end")
h = replace(h,
    "local show=npc.Parent and (npc==bot or (aim and aim.Instance:IsDescendantOf(npc))) and (npc:GetPivot().Position-cam.CFrame.Position).Magnitude<65",
    "local projected,onScreen=cam:WorldToViewportPoint(npc:GetPivot().Position+Vector3.new(0,5,0))\n\t\tlocal show=npc.Parent and npc~=bot and onScreen and projected.Y>120 and (aim and aim.Instance:IsDescendantOf(npc)) and (npc:GetPivot().Position-cam.CFrame.Position).Magnitude<65")
h = replace(h, "or 'Choose a role kiosk, then tap Jobs.'",
    "or 'Choose a role kiosk, then tap Jobs.'\n\tif bot and s then target.Text..=' | NPC '..math.ceil(bot:GetAttribute('Health') or 100)..' HP' end")
save('StarterPlayer.StarterPlayerScripts.LabHUD', 'LocalScript', h)

# --------------------------------------------------------------------------
# GWAPNPC: the server-side speech billboard duplicated the grouped HUD and
# flashed over it. Retain the message as data; the HUD renders it.
# --------------------------------------------------------------------------
n = read('ReplicatedStorage.GWAPNPC')
start = n.index('function N.say(bot,message)')
finish = n.index('function N.nearPlayer', start)
n = n[:start] + """function N.say(bot,message)
    bot:SetAttribute('MissionMessage',message)
    bot:SetAttribute('MissionMessageAt',workspace:GetServerTimeNow())
    local old=bot:FindFirstChild('MissionSpeech',true);if old then old:Destroy() end
end
""" + n[finish:]
save('ReplicatedStorage.GWAPNPC', 'ModuleScript', n)

manifest = [written[k] for k in sorted(written)]
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'files': len(manifest),
                  'retired': ['ReplicatedStorage.LabSpatial'],
                  'entries': [{'path': m['path'], 'bytes': m['bytes']} for m in manifest]}, indent=2))
