-- Walk to the car's driver door and get in, as anyone would (no placing them in the seat). Returns true once seated.
local function getIn(veh, timeout)
    timeout = timeout or 10000
    ClearPedTasks(cache.ped)
    TaskEnterVehicle(cache.ped, veh, timeout, -1, 1.0, 1, 0)
    local t = GetGameTimer()
    while not IsPedInVehicle(cache.ped, veh, false) and GetGameTimer() - t < timeout do Wait(100) end
    return IsPedInVehicle(cache.ped, veh, false)
end

-- The find: a local, frozen, beaten-up display car parked in the barn. Restore steps that are done show on it
-- (Wreck.applyProgress); once restored, client/finds.lua swaps it for a real, owned car that drives out.
do
    Wreck = {}

    local cfg = Tuning.Wreck

    -- A small deterministic generator, so every client rolls the same damage for the same find (the server hands
    -- out one seed per find). Which tyres are flat and which windows are smashed come from it.
    local function roller(seed)
        local state = (tonumber(seed) or 1) % 2147483647
        if state <= 0 then state = state + 2147483646 end
        return function(n)
            state = (state * 48271) % 2147483647
            return (state % n) + 1
        end
    end

    local function choose(roll, pool, count)
        local list = { table.unpack(pool) }
        local out = {}
        for _ = 1, math.min(count, #list) do
            out[#out + 1] = table.remove(list, roll(#list))
        end
        return out
    end

    -- Damage is applied before freezing: GTA only deforms a vehicle that can move.
    local function ruin(veh, paint, seed)
        local roll = roller(seed)
        local c = cfg.Paints and (cfg.Paints[paint or 1] or cfg.Paints[1])
        if c then
            SetVehicleModKit(veh, 0)
            SetVehicleModColor_1(veh, 3, 0, 0)     -- matte
            SetVehicleModColor_2(veh, 3, 0)
            SetVehicleCustomPrimaryColour(veh, c[1], c[2], c[3])
            SetVehicleCustomSecondaryColour(veh, math.floor(c[1] * 0.7), math.floor(c[2] * 0.7), math.floor(c[3] * 0.7))
            SetVehicleExtraColours(veh, 0, 0)
        end
        SetVehicleNumberPlateText(veh, (cfg.Plate and cfg.Plate ~= '') and cfg.Plate or ' ')
        SetVehicleDirtLevel(veh, cfg.Dirt + 0.0)
        SetVehicleEnveffScale(veh, cfg.Rust + 0.0)
        for _, d in ipairs(cfg.Damage) do
            SetVehicleDamage(veh, d.offset.x + 0.0, d.offset.y + 0.0, d.offset.z + 0.0, d.damage + 0.0, d.radius + 0.0, true)
        end
        for _, w in ipairs(choose(roll, { 0, 1, 2, 3, 4, 5 }, cfg.SmashWindows or 0)) do SmashVehicleWindow(veh, w) end
        -- flat, not shredded: the tyre stays on the rim (true would strip it off, leaving no tyre at all)
        for _, t in ipairs(choose(roll, { 0, 1, 4, 5 }, cfg.BurstTyres or 0)) do SetVehicleTyreBurst(veh, t, false, 1000.0) end
        SetVehicleBodyHealth(veh, cfg.BodyHealth + 0.0)
        SetVehicleEngineHealth(veh, cfg.EngineHealth + 0.0)
        SetVehicleLights(veh, 1)
        SetVehicleDoorsLocked(veh, 2)
        if cfg.HoodAjar then SetVehicleDoorControl(veh, 4, 1, cfg.HoodAjar + 0.0) end
    end

    -- Spawns `model` at the barn's car spot in Tuning.Wreck.Paints[paint], damaged by `seed`. Returns the vehicle (nil if no such model).
    function Wreck.spawn(shell, model, paint, seed)
        local hash = joaat(model)
        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            print(('^3[bakery_barnfind] car model %s does not exist^7'):format(model))
            return
        end
        if not pcall(lib.requestModel, hash, 10000) then return end
        if not DoesEntityExist(shell) then
            SetModelAsNoLongerNeeded(hash)
            return
        end
        local spot = Tuning.Barn.CarSpot
        local pos = GetOffsetFromEntityInWorldCoords(shell, spot.x, spot.y, spot.z + 0.6)
        local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, GetEntityHeading(shell) + spot.w, false, false)
        SetModelAsNoLongerNeeded(hash)
        if veh == 0 then return end
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleOnGroundProperly(veh)
        SetVehicleHasBeenOwnedByPlayer(veh, false)
        SetVehicleNeedsToBeHotwired(veh, false)
        SetVehRadioStation(veh, 'OFF')
        ruin(veh, paint, seed)
        -- let the burst tyres and deformation settle onto the floor, then pin it
        CreateThread(function()
            Wait(1500)
            if DoesEntityExist(veh) then FreezeEntityPosition(veh, true) end
        end)
        return veh
    end

    -- Shows the restore steps that are done: new tyres, new glass, straight body, a healthy engine.
    function Wreck.applyProgress(veh, progress)
        if not veh or not DoesEntityExist(veh) then return end
        for _, id in ipairs(progress or {}) do
            if id == 'tyres' then
                for _, t in ipairs({ 0, 1, 4, 5 }) do SetVehicleTyreFixed(veh, t) end
            elseif id == 'glass' then
                for w = 0, 7 do FixVehicleWindow(veh, w) end
            elseif id == 'body' then
                SetVehicleDeformationFixed(veh)
                SetVehicleBodyHealth(veh, 1000.0)
            elseif id == 'start' then
                SetVehicleEngineHealth(veh, 1000.0)
            end
        end
    end

    function Wreck.remove(veh)
        if Finds and Finds.wreckGone then Finds.wreckGone(veh) end
        if veh and DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            DeleteVehicle(veh)
        end
    end
end


-- Restoring, by hand: the first start. Get in, turn the key, and catch it: a skill check (a needle sweeping round a
-- ring) that has to be hit three times in a row while it cranks. A miss and it coughs and dies, and the count
-- starts again. Esc gives up; the prompt comes back to try again.
--
-- Ignition.begin runs it on a find in the barn (client/finds.lua runs the restore steps).
do
    Ignition = {}

    local cfg = Tuning.Restore.Ignition
    local T = Tuning.Restore.Text

    local job = nil

    local function rel(v) return GetOffsetFromEntityInWorldCoords(job.veh, v.x + 0.0, v.y + 0.0, v.z + 0.0) end

    -- In the seat, key turning: three hits in a row and it catches.
    local function skillGame()
        local veh = job.veh
        return Minigame.run({
            kind = 'skill',
            data = {
                hits = cfg.Hits, speed = cfg.Speed, zone = cfg.Zone, speedUp = cfg.SpeedUp,
                title = 'Start it up', hint = 'Tap Space (or click) as the needle crosses the white mark. Three in a row',
            },
            onEvent = function(name)
                if name == 'cough' then
                    -- it turned over and died
                    SetVehicleEngineOn(veh, false, true, true)
                elseif name == 'catch' then
                    SetVehicleEngineHealth(veh, 1000.0)
                    SetVehicleUndriveable(veh, false)
                    SetVehicleEngineOn(veh, true, true, false)
                    SetVehicleLights(veh, 0)
                end
            end,
        })
    end

    local refresh

    local function start()
        if not job or job.busy then return end
        job.busy = true
        refresh()
        local veh = job.veh
        SetVehicleDoorsLocked(veh, 1)
        FreezeEntityPosition(veh, false)   -- so they can get in; frozen again once they are seated
        local seated = getIn(veh)
        FreezeEntityPosition(veh, true)
        if not seated then
            job.busy = false
            refresh()
            return
        end
        Wait(400)
        local ok, res = pcall(skillGame)
        if not ok then print(('^1[bakery_barnfind] start-up failed: %s^7'):format(res)) end
        if not job then return end
        job.busy = false
        if ok and res == 'done' then
            Bridge.notify(T.ignitionDone, 'success')
            local cb = job.onDone
            Ignition.stop()
            if cb then cb() end   -- you stay in the seat: the car is swapped for the real one under you
            return
        else
            TaskLeaveVehicle(cache.ped, veh, 16)
        end
        refresh()
    end

    function refresh()
        if not job then return end
        if job.zone then job.zone.remove() job.zone = nil end
        if job.busy then return end
        local mn = GetModelDimensions(GetEntityModel(job.veh))
        job.zone = Bridge.addZone({
            name = 'bk_ignition', coords = rel(vec3(mn.x - 0.2, 0.3, 0.3)), heading = GetEntityHeading(job.veh), distance = 2.2,
            message = T.ignition, targetMessage = T.ignitionTarget, icon = 'fas fa-key',
            canInteract = function() return job ~= nil and not job.busy end,
            onSelect = function() CreateThread(start) end,
        })
    end

    function Ignition.stop()
        if not job then return end
        Minigame.stop()
        if job.zone then job.zone.remove() end
        job = nil
    end

    -- Start `veh` for the first time. opts.onDone is called once it is running, with you in the seat (the job then packs
    -- up, leaving the car).
    function Ignition.begin(veh, opts)
        opts = opts or {}
        StopRestoreJobs()
        job = { veh = veh, onDone = opts.onDone }
        FreezeEntityPosition(veh, true)
        refresh()
        return true
    end

    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() then Ignition.stop() end
    end)
end


-- Restoring a find, on the car in the barn. The one who found it gets a prompt on the car for the next step (the
-- server says which, and what it needs: server/restore.lua). Picking it runs that step's job on the car itself:
--   tyres -> Wheels (client/wheels.lua)   glass -> Glass   oil -> Oil   body -> Body   start -> Ignition (below)
-- When the job is done the server uses the items up and saves the step; everyone nearby sees it on the car
-- (Wreck.applyProgress). The last step ends with the engine running; right then the car is made theirs (their
-- garage), the display car is swapped for a real one in the same spot with them in the seat, and kq_link hands over
-- the keys. If that can't happen yet a "Take it out of the barn" prompt does it later.
Finds = {}

local T = Tuning.Restore.Text
local JOBS = {
    tyres = function(veh, done) return Wheels.begin(veh, { onDone = done }) end,
    glass = function(veh, done) return Glass.begin(veh, { onDone = done }) ~= nil end,
    oil = function(veh, done) return Oil.begin(veh, { onDone = done }) end,
    body = function(veh, done)
        if Body.begin(veh, { onDone = done }) == 0 then done() end   -- no bodywork found to grind: nothing to do
        return true
    end,
    start = function(veh, done) return Ignition.begin(veh, { onDone = done }) end,
}

local zones = {}      -- [barnId] = zone handle
local status = {}     -- [barnId] = last status from the server, and when
local active = nil    -- { barnId, veh, stage } while a step's job runs
local claiming = false
local refreshing = {}

local function restoreCall(action, id, stage)
    local ok, result = pcall(lib.callback.await, 'bakery_barnfind:restore:' .. action, false, id, stage)
    return ok and type(result) == 'table' and result or {}
end

local function message(res)
    if res.error == 'missingItem' and res.item then return T.restoreMissing:format(res.item.count, res.item.label or res.item.name) end
    if res.error == 'notYours' then return T.restoreNotYours end
    return Tuning.Text[res.error or 'busy'] or Tuning.Text.busy
end

local function needs(items)
    local parts = {}
    for _, it in ipairs(items or {}) do parts[#parts + 1] = ('%dx %s'):format(it.count, it.label or it.name) end
    return #parts > 0 and T.restoreNeeds:format(table.concat(parts, ', ')) or nil
end

local function clearZone(id)
    if zones[id] then zones[id].remove() end
    zones[id] = nil
end

-- ---------------------------------------------------------------- driving it out
-- Make it theirs: the server saves it to their garage, then the display car (local, only this player sees it) is
-- swapped for a real, networked one in the same spot, running, with them in the seat. The keys come from the server
-- through kq_link, for that car. Returns true once they are in it.
function Finds.claim(id)
    local b = Barn.get(id)
    if claiming or active or not b or not b.wreck then return false end
    claiming = true
    local res = restoreCall('claim', id)
    if not res.ok then
        claiming = false
        Bridge.notify(message(res), 'error')
        return false
    end

    local t = GetGameTimer()
    while not NetworkDoesEntityExistWithNetworkId(res.netId) and GetGameTimer() - t < 5000 do Wait(50) end
    local car = NetworkDoesEntityExistWithNetworkId(res.netId) and NetToVeh(res.netId) or 0
    if car == 0 then
        claiming = false
        Bridge.notify(T.restoreHandoff, 'warning')
        return true
    end
    t = GetGameTimer()
    while not NetworkHasControlOfEntity(car) and GetGameTimer() - t < 2000 do
        NetworkRequestControlOfEntity(car)
        Wait(50)
    end
    lib.setVehicleProperties(car, res.props)
    SetVehicleNumberPlateText(car, res.plate)
    SetVehicleDirtLevel(car, 0.0)
    SetVehicleDoorsLocked(car, 1)
    SetVehicleOnGroundProperly(car)
    local keys
    for _ = 1, 8 do
        keys = restoreCall('keys', id).ok
        if keys then break end
        Wait(250)
    end
    if keys and getIn(car) then SetVehicleEngineOn(car, true, true, false) end
    claiming = false
    Bridge.notify(keys and T.restoreYours or T.restoreHandoff, keys and 'success' or 'warning')
    return true
end

-- ---------------------------------------------------------------- a step
-- Start the next restore step on the find in barn `id` (the prompt on the car does this).
function Finds.start(id, stage)
    local b = Barn.get(id)
    if not b or not b.wreck or active or claiming then return end
    local job = { barnId = id, veh = b.wreck }
    active = job
    local res = restoreCall('begin', id, stage.id)
    if active ~= job then return end
    if not res.ok then
        active = nil
        return Bridge.notify(message(res), 'error')
    end
    local began = GetGameTimer()

    clearZone(id)
    local finished = false
    local ok = JOBS[stage.id](job.veh, function()
        if finished or active ~= job then return end
        finished = true
        -- the server won't take a step done faster than it could really be done; a step with nothing to do (no
        -- broken glass, say) is over at once, so see out the rest of that time
        local left = (res.wait or 0) * 1000 - (GetGameTimer() - began)
        if left > 0 then
            lib.progressBar({ duration = left, label = T.restoreFinishing:format(stage.label), canCancel = false,
                disable = { move = true, car = true, combat = true } })
        end
        if active ~= job then return end
        local done = restoreCall('complete', id, stage.id)
        if active ~= job then return end
        active = nil
        if not done.ok then
            Bridge.notify(message(done), 'error')
        elseif done.finished then
            -- it runs: it's theirs, keys and all, from the seat they're already in
            if Finds.claim(id) then return end
            Bridge.notify(T.restoreAllDone, 'success')
        else
            Bridge.notify(T.restoreStepDone:format(stage.label, done.next), 'success')
            -- the next step starts on its own (no third-eye needed to begin it); if it can't, its target is still there
            CreateThread(function()
                local s = restoreCall('status', id)
                if s.next then Finds.start(id, s.next) end
            end)
        end
        status[id] = nil
        Finds.refresh(id)
    end)
    if not ok and active == job and not finished then active = nil Finds.refresh(id) end
end

-- ---------------------------------------------------------------- the prompt on the car
-- Ask the server what this player can do with the find, and put the prompt on the car to match.
function Finds.refresh(id)
    local b = Barn.get(id)
    if not b or not b.wreck or not DoesEntityExist(b.wreck) or (active and active.barnId == id) then
        status[id] = nil
        return clearZone(id)
    end
    local veh = b.wreck
    if #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) >= 15.0 or refreshing[id] then return end
    local s = status[id]
    if not s or s.veh ~= veh or GetGameTimer() - s.at > 4000 then
        refreshing[id] = true
        local res = restoreCall('status', id)
        refreshing[id] = nil
        if Barn.get(id) ~= b or b.wreck ~= veh or not DoesEntityExist(veh) or (active and active.barnId == id) then return end
        s = { at = GetGameTimer(), res = res, veh = veh }
        status[id] = s
    elseif zones[id] then
        return
    end
    clearZone(id)
    local res = s.res
    if not res.mine or res.claimed or not b.wreck then return end
    local c = GetEntityCoords(veh)
    if res.claimable then
        zones[id] = Bridge.addZone({
            name = ('bk_find_%s'):format(id), coords = vec3(c.x, c.y, c.z + 0.6), heading = GetEntityHeading(veh), distance = 3.0,
            message = T.restoreClaim, targetMessage = T.restoreClaimTarget, icon = 'fas fa-key',
            canInteract = function() return not active and not claiming end,
            onSelect = function() CreateThread(function() Finds.claim(id) end) end,
        })
    elseif res.next then
        local hint = needs(res.next.items)
        zones[id] = Bridge.addZone({
            name = ('bk_find_%s'):format(id), coords = vec3(c.x, c.y, c.z + 0.6), heading = GetEntityHeading(veh), distance = 3.0,
            message = T.restoreStep:format(res.next.label) .. (hint and ('~n~' .. hint) or ''),
            targetMessage = T.restoreStepTarget:format(res.next.label),
            icon = 'fas fa-screwdriver-wrench',
            canInteract = function() return not active and not claiming end,
            onSelect = function() CreateThread(function() Finds.start(id, res.next) end) end,
        })
    end
end

-- Stop the step being done, if there is one.
function Finds.stop()
    active = nil
    status = {}
    StopRestoreJobs()
end

-- The display car is going away (barn despawned or reset): stop a step that was being done on it.
function Finds.wreckGone(veh)
    if active and active.veh == veh then
        active = nil
        StopRestoreJobs()
    end
end

-- Near a barn with a find: keep its prompt current. Walk away mid-step and the step stops.
CreateThread(function()
    while true do
        local me = GetEntityCoords(cache.ped)
        for _, id in ipairs(Barn.ids()) do
            local b = Barn.get(id)
            local near = b and b.wreck and DoesEntityExist(b.wreck) and #(GetEntityCoords(b.wreck) - me) < 15.0
            local cached = status[id]
            if near and not zones[id] and (not cached or GetGameTimer() - cached.at > 4000) and not (active and active.barnId == id) then
                Finds.refresh(id)
            elseif not near and (zones[id] or cached) then
                clearZone(id)
                status[id] = nil
            end
        end
        if active then
            local b = Barn.get(active.barnId)
            if not b or not b.wreck or #(GetEntityCoords(b.wreck) - me) > 30.0 then
                active = nil
                StopRestoreJobs()
                Bridge.notify(T.restoreStopped, 'error')
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(zones) do clearZone(id) end
end)
