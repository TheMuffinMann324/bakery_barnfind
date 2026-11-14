-- Barn door animation.
--
-- The doors are separate props with their origin on the hinge, swung by script every frame along a keyframed
-- curve (Tuning.DoorOpenCurve). Doing it this way rather than with a .ycd clip keeps the doors' collision moving
-- with them and lets the cutscene time the animation precisely.
do
    Doors = {}

    local EASE = {
        linear = function(x) return x end,
        ['in'] = function(x) return x * x end,
        out = function(x) return 1.0 - (1.0 - x) * (1.0 - x) end,
        inout = function(x) return x < 0.5 and 2.0 * x * x or 1.0 - (-2.0 * x + 2.0) ^ 2 / 2.0 end,
    }

    -- Value of a curve at time t (ms).
    function Doors.sample(curve, t)
        if t <= curve[1].t then return curve[1].v end
        for i = 2, #curve do
            local a, b = curve[i - 1], curve[i]
            if t <= b.t then
                local x = (t - a.t) / (b.t - a.t)
                return a.v + (b.v - a.v) * (EASE[b.ease or 'inout'] or EASE.inout)(x)
            end
        end
        return curve[#curve].v
    end

    function Doors.length(curve)
        return curve[#curve].t
    end

    -- Puts a door at `amount` of its open angle (0 closed, 1 open) relative to the barn's heading.
    function Doors.pose(door, heading, amount)
        if DoesEntityExist(door.entity) then
            SetEntityRotation(door.entity, 0.0, 0.0, heading + door.cfg.openAngle * amount, 2, false)
        end
    end

    -- Angle (degrees) of each door at `t` seconds into PullDoorCurve (shared/pull_door_curve.lua).
    function Doors.pullAngles(t)
        local c = PullDoorCurve
        if t <= c[1].t then return c[1].l, c[1].r end
        for i = 2, #c do
            local a, b = c[i - 1], c[i]
            if t <= b.t then
                local x = (t - a.t) / (b.t - a.t)
                return a.l + (b.l - a.l) * x, a.r + (b.r - a.r) * x
            end
        end
        return c[#c].l, c[#c].r
    end

    -- Drives the doors from a ped's playing clip, so they move with the hands that hold them, frame-exact.
    -- Collision is off while they sweep past the ped. Resolves when the clip is done (or stops playing).
    function Doors.followClip(doors, heading, ped, dict, clip)
        local p = promise.new()
        CreateThread(function()
            for _, door in pairs(doors) do SetEntityCollision(door.entity, false, false) end
            local started, last = GetGameTimer(), 0.0
            while true do
                local playing = IsEntityPlayingAnim(ped, dict, clip, 3)
                local t = playing and GetEntityAnimCurrentTime(ped, dict, clip) * PullDoorCurve.duration or last
                if not playing and GetGameTimer() - started > 1000 then break end   -- finished, skipped or interrupted
                last = math.max(last, t)
                local l, r = Doors.pullAngles(last)
                for key, door in pairs(doors) do
                    local deg = key == 'left' and l or r
                    Doors.pose(door, heading, deg / math.abs(door.cfg.openAngle))
                end
                if last >= PullDoorCurve.duration - 0.02 then break end
                Wait(0)
            end
            for _, door in pairs(doors) do
                Doors.pose(door, heading, 1.0)
                SetEntityCollision(door.entity, true, true)
            end
            p:resolve(true)
        end)
        return p
    end

    -- Runs a curve over a set of doors. Each door starts after its cfg.delay (reversed when closing).
    -- Returns a promise resolved when every door has finished.
    function Doors.play(doors, heading, curve, closing)
        local p = promise.new()
        local maxDelay = 0
        for _, door in pairs(doors) do maxDelay = math.max(maxDelay, door.cfg.delay or 0) end
        local total = Doors.length(curve) + maxDelay
        CreateThread(function()
            local start = GetGameTimer()
            while true do
                local now = GetGameTimer() - start
                for _, door in pairs(doors) do
                    local delay = door.cfg.delay or 0
                    if closing then delay = maxDelay - delay end
                    local t = now - delay
                    Doors.pose(door, heading, Doors.sample(curve, math.max(t, 0)))
                end
                if now >= total then break end
                Wait(0)
            end
            p:resolve(true)
        end)
        return p
    end
end


-- Spawns barns (shell + two doors) as local, frozen props and drives their doors.
-- Each client builds its own copy, so the door animation is perfectly smooth. Whether a barn has been searched,
-- and what was in it, comes from the server: GlobalState.bakery_barnfind[id] for barns that are shared by everyone,
-- and `mine` (pushed only to the player) for barns where every player finds their own.
-- Either way a find is { car = model, paint = index, seed = number }.
Barn = {}

-- [id] = { shell, heading, doors = { left = {entity, cfg}, right = ... }, state, zone, find = model, wreck, fx }
local barns = {}
local spawning = {}

local mine = {}
-- The shared finds, as last announced. Kept here because inside a state bag change handler GlobalState still
-- holds the OLD value: the new one only arrives as the handler's argument.
local shared = GlobalState.bakery_barnfind or {}

local function foundIn(id)
    return shared[id] or mine[id]
end

local function spawnProp(model, coords, heading, current)
    local hash = joaat(model)
    if not pcall(lib.requestModel, hash, 10000) then return end
    if not current() then
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if obj == 0 then return end
    SetEntityRotation(obj, 0.0, 0.0, heading, 2, false)
    FreezeEntityPosition(obj, true)
    SetEntityLodDist(obj, 500)
    return obj
end

local FLOOR = 0.02   -- top of the dirt floor above the shell origin

-- Clutter from Tuning.Barn.Dressing: vanilla props placed relative to the shell, frozen, with collision.
local function spawnDressing(b)
    local dressing = {}
    b.dressing = dressing
    if Tuning.Barn.DressingEnabled == false then return end
    local h0 = GetEntityHeading(b.shell)
    for _, d in ipairs(Tuning.Barn.Dressing or {}) do
        local hash = joaat(d.model)
        if IsModelInCdimage(hash) and pcall(lib.requestModel, hash, 10000) then
            if b.dressing ~= dressing or not DoesEntityExist(b.shell) then
                SetModelAsNoLongerNeeded(hash)
                return
            end
            local z = FLOOR + d.p.z
            if not d.raw then
                local mn = GetModelDimensions(hash)
                z = z - mn.z                       -- sit the model's underside on the floor (or on p.z)
            end
            local pos = GetOffsetFromEntityInWorldCoords(b.shell, d.p.x + 0.0, d.p.y + 0.0, z + 0.0)
            local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            if obj ~= 0 then
                SetEntityRotation(obj, d.r.x + 0.0, d.r.y + 0.0, h0 + d.r.z, 2, false)
                FreezeEntityPosition(obj, true)
                SetEntityLodDist(obj, 120)
                dressing[#dressing + 1] = obj
            end
        elseif Tuning.Debug then
            print(('^3[bakery_barnfind] dressing model %s does not exist^7'):format(d.model))
        end
    end
end

-- Clears and respawns every barn's clutter (the admin switched it on or off).
function Barn.refreshDressing()
    for _, b in pairs(barns) do
        for _, obj in ipairs(b.dressing or {}) do
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
        spawnDressing(b)
    end
end

function Barn.get(id)
    return barns[id]
end

function Barn.ids()
    local out = {}
    for id in pairs(barns) do out[#out + 1] = id end
    return out
end

-- World position of a point given relative to the barn shell.
local function offset(id, rel)
    local b = barns[id]
    return b and GetOffsetFromEntityInWorldCoords(b.shell, rel.x, rel.y, rel.z)
end

-- coords: vec4, the barn origin (front centre of the floor) and heading.
function Barn.spawn(id, coords)
    if barns[id] or spawning[id] then return end
    local token, hash = {}, joaat(Tuning.Barn.Shell)
    spawning[id] = token
    local function current() return spawning[id] == token end
    -- just after the resource (re)starts the game is still registering our models from the .ytyp: wait for them,
    -- or a barn the player is already standing next to fails to spawn and never comes back
    local t = GetGameTimer()
    while current() and not IsModelInCdimage(hash) and GetGameTimer() - t < 15000 do Wait(100) end
    if not current() then return end
    if not IsModelInCdimage(hash) then
        spawning[id] = nil
        print(('^1[bakery_barnfind] the barn model %s is not loaded; barn %s not spawned^7'):format(Tuning.Barn.Shell, id))
        return
    end
    local heading = coords.w
    local shell = spawnProp(Tuning.Barn.Shell, coords.xyz, heading, current)
    if not shell then
        if current() then spawning[id] = nil end
        return
    end
    local b = { shell = shell, heading = heading, doors = {}, state = 'closed' }
    barns[id] = b
    for key, cfg in pairs(Tuning.Barn.Doors) do
        local pos = GetOffsetFromEntityInWorldCoords(shell, cfg.hinge.x, cfg.hinge.y, cfg.hinge.z)
        local door = spawnProp(cfg.model, pos, heading, current)
        if not door then
            if current() then Barn.despawn(id) end
            return
        end
        b.doors[key] = { entity = door, cfg = cfg }
    end
    spawnDressing(b)
    if not current() then return end
    spawning[id] = nil
    local found = foundIn(id)
    if found then
        -- already searched: doors stand open with the find inside
        Barn.showFind(id, found)
        if barns[id] ~= b then return end
        Barn.setDoors(id, 1.0)
        Barn.setAmbience(id, true)
    end
    Barn.refreshInteraction(id)
    return b
end

function Barn.despawn(id)
    spawning[id] = nil
    local b = barns[id]
    if not b then return end
    if b.zone then b.zone.remove() end
    Barn.setAmbience(id, false)
    Wreck.remove(b.wreck)
    for _, door in pairs(b.doors) do
        if DoesEntityExist(door.entity) then DeleteEntity(door.entity) end
    end
    for _, obj in ipairs(b.dressing or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    if DoesEntityExist(b.shell) then DeleteEntity(b.shell) end
    barns[id] = nil
end

-- Snap both doors to `amount` open (0..1) without animating.
function Barn.setDoors(id, amount)
    local b = barns[id]
    if not b then return end
    for _, door in pairs(b.doors) do Doors.pose(door, b.heading, amount) end
    b.state = amount > 0.5 and 'open' or 'closed'
    Barn.refreshInteraction(id)
end

-- Animate the doors open. Returns a promise (Citizen.Await it to wait for the swing to finish).
function Barn.open(id)
    local b = barns[id]
    if not b or b.state ~= 'closed' then return end
    b.state = 'opening'
    Barn.refreshInteraction(id)
    local p = Doors.play(b.doors, b.heading, Tuning.DoorOpenCurve, false)
    p:next(function() if barns[id] == b then b.state = 'open'; Barn.refreshInteraction(id) end end)
    return p
end

-- Opens the doors in step with a ped playing the two-handed pull clip (see Doors.followClip).
function Barn.openWithClip(id, ped, dict, clip)
    local b = barns[id]
    if not b or b.state ~= 'closed' then return end
    b.state = 'opening'
    Barn.refreshInteraction(id)
    local p = Doors.followClip(b.doors, b.heading, ped, dict, clip)
    p:next(function() if barns[id] == b then b.state = 'open'; Barn.refreshInteraction(id) end end)
    return p
end

function Barn.close(id)
    local b = barns[id]
    if not b or b.state ~= 'open' then return end
    b.state = 'closing'
    Barn.refreshInteraction(id)
    local p = Doors.play(b.doors, b.heading, Tuning.DoorCloseCurve, true)
    p:next(function() if barns[id] == b then b.state = 'closed'; Barn.refreshInteraction(id) end end)
    return p
end

-- Puts the find (`{ car = model, paint = index }`) in the barn; no-op if it's already there.
function Barn.showFind(id, find)
    local b = barns[id]
    if not b then return end
    if b.wreck and DoesEntityExist(b.wreck) and b.find and b.find.car == find.car and b.find.seed == find.seed then return end
    Wreck.remove(b.wreck)
    b.find = find
    b.progressKey = table.concat(find.progress or {}, ',')
    b.wreck = nil
    if find.claimed then return end   -- restored and driven out: the barn stands empty
    local veh = Wreck.spawn(b.shell, find.car, find.paint, find.seed)
    if barns[id] ~= b or b.find ~= find or find.claimed then
        Wreck.remove(veh)
        return
    end
    b.wreck = veh
    -- the damage has to land before the repairs: Wreck.spawn deforms it as it settles
    local progress = find.progress
    if veh and progress and #progress > 0 then
        CreateThread(function()
            Wait(1600)
            if b.wreck == veh then Wreck.applyProgress(veh, progress) end
        end)
    end
end

-- Removes the find and shuts the doors (admin reset).
function Barn.clearFind(id)
    local b = barns[id]
    if not b then return end
    Barn.setAmbience(id, false)
    Wreck.remove(b.wreck)
    b.wreck, b.find = nil, nil
    Barn.setDoors(id, 0.0)
end

-- Dust motes in the light and flies over the find, while the barn stands open.
function Barn.setAmbience(id, on)
    local b = barns[id]
    if not b then return end
    for _, h in ipairs(b.fx or {}) do StopParticleFxLooped(h, false) end
    b.fx = nil
    if not on then return end
    b.fx = {}
    local activeFx, spot = b.fx, Tuning.Barn.CarSpot
    local function loop(fx, rel)
        if not fx then return end
        if not pcall(lib.requestNamedPtfxAsset, fx.asset, 5000) or b.fx ~= activeFx or barns[id] ~= b then return end
        local p = GetOffsetFromEntityInWorldCoords(b.shell, rel.x + 0.0, rel.y + 0.0, rel.z + 0.0)
        UseParticleFxAssetNextCall(fx.asset)
        activeFx[#activeFx + 1] = StartParticleFxLoopedAtCoord(fx.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, fx.scale + 0.0, false, false, false, false)
    end
    local fx = Tuning.Cutscene.Particles
    loop(fx.motes, vec3(spot.x, spot.y - 2.5, 1.6))
    loop(fx.motes, vec3(spot.x, spot.y + 1.0, 2.2))
    loop(fx.flies, vec3(spot.x, spot.y, 1.4))
end

-- Prompt in front of the doors, rebuilt on every state change whoever caused it:
-- an unsearched barn offers "open the barn" (the cutscene); a searched one just opens / closes its doors.
function Barn.refreshInteraction(id)
    local b = barns[id]
    if not b then return end
    if b.zone then b.zone.remove() end
    b.zone = nil
    if spawning[id] or b.cutscene or (b.state ~= 'closed' and b.state ~= 'open') then return end
    local state = b.state
    local search = state == 'closed' and not foundIn(id)
    local opening = state == 'closed'
    b.zone = Bridge.addZone({
        name = ('bakery_barnfind_%s'):format(id),
        coords = offset(id, Tuning.Barn.InteractPoint),
        heading = b.heading,
        distance = Tuning.Barn.InteractDistance,
        message = search and Tuning.Text.search or opening and Tuning.Text.open or Tuning.Text.close,
        targetMessage = search and Tuning.Text.searchTarget or opening and Tuning.Text.openTarget or Tuning.Text.closeTarget,
        canInteract = function() return barns[id] == b and b.state == state and not b.cutscene end,
        onSelect = function()
            if search then
                Barn.search(id)
            elseif opening then
                Barn.open(id)
            else
                Barn.close(id)
            end
        end,
    })
end

-- Ask the server to claim the barn, then play the reveal.
function Barn.search(id)
    local b = barns[id]
    if not b or b.cutscene or BarnScene.isPlaying() then return end
    b.cutscene = true
    Barn.refreshInteraction(id)
    local called, ok, result, left = pcall(lib.callback.await, 'bakery_barnfind:search', false, id)
    if barns[id] ~= b then return end
    if not called then ok, result = false, 'busy' end
    if not ok then
        b.cutscene = nil
        Barn.syncState()
        local message = Tuning.Text[result] or Tuning.Text.busy
        if result == 'cooldown' and left then message = message:format(Bridge.duration(left)) end
        Bridge.notify(message, 'error')
        return
    end
    if Tuning.Cutscene.Enabled then
        BarnScene.play(id, result)
    else
        Barn.showFind(id, result)
        b.cutscene = nil
        Barn.open(id)
        Barn.setAmbience(id, true)
    end
end

-- Brings every spawned barn in line with what the server says: a find appeared (doors open, car shown), was
-- replaced, or is gone (doors shut, car removed). The barn being searched by this player is left to its cutscene.
function Barn.syncState()
    for id, b in pairs(barns) do
        if not spawning[id] and not b.cutscene then
            local found = foundIn(id)
            if found and b.find and (b.find.car ~= found.car or b.find.seed ~= found.seed) then
                Barn.clearFind(id)   -- a new find replaced the old one
            end
            if found and not b.find then
                Barn.showFind(id, found)
                if b.state == 'closed' then Barn.open(id) end
                Barn.setAmbience(id, true)
            elseif not found and b.find then
                Barn.clearFind(id)
            elseif found and b.find then
                -- the restore moved on: show the new steps, or take the car away once it has been driven out
                b.find.progress, b.find.claimed = found.progress, found.claimed
                if found.claimed and b.wreck then
                    Wreck.remove(b.wreck)
                    b.wreck = nil
                else
                    local key = table.concat(found.progress or {}, ',')
                    if key ~= b.progressKey then
                        b.progressKey = key
                        Wreck.applyProgress(b.wreck, found.progress)
                    end
                end
            end
            if Finds and Finds.refresh then Finds.refresh(id) end
        end
        Barn.refreshInteraction(id)
    end
end

-- This player's own finds (barns where every player finds their own).
function Barn.setMine(list)
    mine = type(list) == 'table' and list or {}
    Barn.syncState()
end

AddStateBagChangeHandler('bakery_barnfind', 'global', function(_, _, value)
    shared = type(value) == 'table' and value or {}
    Barn.syncState()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(barns) do Barn.despawn(id) end
end)
