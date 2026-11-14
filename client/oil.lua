-- Restoring, by hand: an oil and filter change.
--   1. Roll a trolley jack under the middle of one side and pump it: that side comes up, the car leans over.
--   2. Do the same on the other side: the car is up, level.
--   3. Get under it (on your back, the mechanic pose). The camera drops under the car, looking up at the filter:
--      spin the old filter off, then spin the new one on.
--   4. Let each side down.
--
-- Nothing here depends on a car's shape: the jacks go mid-sill from the model's size, and the filter is our own prop
-- (bk_oil_filter), hung under the car below its engine bone wherever that is.
--
-- Oil.begin runs it on a find in the barn (client/finds.lua runs the restore steps).
Oil = {}

local cfg = Tuning.Restore.Oil
local J = Tuning.Restore.Wheels.Jack
local T = Tuning.Restore.Text

local job = nil

-- ---------------------------------------------------------------- helpers
local function model(name)
    local hash = joaat(name)
    lib.requestModel(hash, 10000)
    return hash
end

local function prop(name, pos)
    local o = CreateObject(model(name), pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(joaat(name))
    SetEntityCollision(o, false, false)
    return o
end

local function delete(e) if e and DoesEntityExist(e) then DeleteEntity(e) end end

local function norm(v)
    local l = #v
    return l > 0.0001 and v / l or v
end

local function rel(x, y, z) return GetOffsetFromEntityInWorldCoords(job.veh, x + 0.0, y + 0.0, z + 0.0) end

local function groundZ(p)
    local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
    return ok and z or p.z
end

local function anim(a)
    lib.requestAnimDict(a.dict, 5000)
    TaskPlayAnim(cache.ped, a.dict, a.clip, 4.0, 4.0, -1, a.flag or 0, 0.0, false, false, false)
end

local function ease(k) return k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2 end

-- ---------------------------------------------------------------- the car going up
-- Each side comes up Lift * its t. The car rolls about its long axis so each side sits at its own height.
local function lift()
    local zl, zr = cfg.Lift * job.sides[-1].t, cfg.Lift * job.sides[1].t
    local roll = math.deg(math.atan(zl - zr, job.halfW * 2.0))
    local p = job.base.pos + vec3(0.0, 0.0, (zl + zr) * 0.5)
    SetEntityCoordsNoOffset(job.veh, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(job.veh, job.base.rot.x, job.base.rot.y + roll, job.base.rot.z, 2, false)
end

-- The jack goes under the sill, halfway along the car. Its saddle meets whatever is right above that spot.
local function placeJack(s)
    local side = job.sides[s]
    local c = rel(s * (job.halfW - cfg.JackIn), job.midY, 0.0)
    local gz = groundZ(c)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, gz + 0.03, c.x, c.y, gz + 1.6, 2, 0, 4)
    local _, hit, at = GetShapeTestResult(ray)
    local contact = (hit == 1) and (at.z - gz) or 0.28
    contact = math.max(Jack.restHeight() + 0.02, math.min(Jack.maxHeight() - cfg.Lift, contact))
    local _, r = GetEntityMatrix(job.veh)
    local inward = norm(vec3(-r.x * s, -r.y * s, 0.0))
    side.jack = Jack.new(vec3(c.x, c.y, gz), inward)
    side.jack.contact = contact
    return side.jack
end

-- 0 jack down .. 1 that side fully up: the saddle comes up to the car, then the car with it.
local function jackTo(s, p)
    local side = job.sides[s]
    local j = side.jack
    local h0, top = Jack.restHeight(), j.contact + cfg.Lift
    local h = h0 + (top - h0) * p
    Jack.setSaddle(j, h)
    side.t = math.max(0.0, h - j.contact) / cfg.Lift
    lift()
end

-- ---------------------------------------------------------------- cameras and the player
local function camAt(pos, target, fov, ms)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov, false, 2)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, ms or 600, true, true)
    job.cam = cam
    return cam
end

local function camEnd()
    if not job or not job.cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(job.cam, false)
    job.cam = nil
end

-- Side-on view of the jack and the car while you work the handle.
local function jackView(s)
    local f, r = GetEntityMatrix(job.veh)
    local j = job.sides[s].jack
    local target = j.spot + vec3(0.0, 0.0, 0.35)
    local pos = target + r * (s * 2.6) + f * 1.6 + vec3(0.0, 0.0, 0.6)
    camAt(pos, target, 50.0)
end

-- Kneel at the end of the handle, facing the car.
local function standAtHandle(j)
    local g = Jack.grip(j)
    local spot = vec3(g.x, g.y, 0.0) - j.inward * 0.40
    spot = vec3(spot.x, spot.y, groundZ(vec3(spot.x, spot.y, g.z)))
    local ped = cache.ped
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 4000, j.heading, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 4000 and #(GetEntityCoords(ped).xy - spot.xy) > 0.25 do Wait(50) end
    ClearPedTasks(ped)
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(ped, j.heading)
    anim(Tuning.Restore.Wheels.Anims.kneel)
end

-- ---------------------------------------------------------------- the filter
-- The filter's top (its origin) sits on the underside of the car below the engine bone; it hangs down from there.
local function filterSpot()
    local x, y = job.engine.x + cfg.FilterSide, job.engine.y
    local w = rel(x, y, 0.0)
    local gz = groundZ(w)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(w.x, w.y, gz + 0.03, w.x, w.y, gz + 2.0, 2, 0, 4)
    local _, hit, at = GetShapeTestResult(ray)
    local top = hit == 1 and at or vec3(w.x, w.y, gz + cfg.Lift + 0.25)
    local o = GetOffsetFromEntityGivenWorldCoords(job.veh, top.x, top.y, top.z)
    return vec3(x, y, o.z)
end

-- p: 0 screwed home .. 1 off the thread. spin in degrees.
local function hang(e, drop, spin)
    local o = job.filterAt
    AttachEntityToEntity(e, job.veh, 0, o.x, o.y, o.z - drop, 0.0, 0.0, spin, false, false, false, false, 2, true)
end

-- Where the filter's bottom face is, and a point on its rim (to size the ring on screen).
local function filterPoints(e)
    local L, R = cfg.FilterLength, cfg.FilterRadius
    return { GetOffsetFromEntityInWorldCoords(e, 0.0, 0.0, -L), GetOffsetFromEntityInWorldCoords(e, R, 0.0, -L) }, R
end

-- ---------------------------------------------------------------- getting under the car
local function lieUnder(s)
    local ped = cache.ped
    -- walk up beside the car next to the filter, then lie back with your head and shoulders under the sill
    local out = rel(s * (job.halfW + 0.55), job.lieY, 0.0)
    out = vec3(out.x, out.y, groundZ(out))
    local _, r = GetEntityMatrix(job.veh)
    local h = GetHeadingFromVector_2d(-r.x * s, -r.y * s)   -- facing in, under the car
    TaskGoStraightToCoord(ped, out.x, out.y, out.z, 1.0, 4000, h, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 4000 and #(GetEntityCoords(ped).xy - out.xy) > 0.3 do Wait(50) end
    ClearPedTasks(ped)
    -- keep the height you stood at beside the car: under it, a ground probe can find the car instead, and putting
    -- a ped's origin (its hips) on the ground drops it through the map
    local standZ = GetEntityCoords(ped).z
    local at = rel(s * (job.halfW + cfg.LieOut), job.lieY, 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, at.x, at.y, standZ, false, false, false)
    SetEntityHeading(ped, h + cfg.LieHeading)
    anim(cfg.Anims.under)
    Wait(600)
end

local function getUp(s)
    local ped = cache.ped
    local z = GetEntityCoords(ped).z
    ClearPedTasks(ped)
    local out = rel(s * (job.halfW + 0.7), job.lieY, 0.0)
    SetEntityCoordsNoOffset(ped, out.x, out.y, z, false, false, false)
    FreezeEntityPosition(ped, false)
end

-- Under the car, looking up at the filter from the side you came in on.
local function underView(s)
    local f, r = GetEntityMatrix(job.veh)
    local bottom = filterPoints(job.filter)[1]
    local pos = bottom + r * (s * cfg.UnderCam.out) - f * cfg.UnderCam.back
    pos = vec3(pos.x, pos.y, groundZ(pos) + cfg.UnderCam.up)
    local cam = camAt(pos, bottom, cfg.UnderCam.fov, 700)
    CreateThread(function()
        while job and job.cam == cam do
            SetEntityLocallyInvisible(cache.ped)
            Wait(0)
        end
    end)
    Wait(720)
end

local function spinGame(e, mode)
    local unscrew = mode == 'off'
    local turns = cfg.Turns
    return Minigame.run({
        kind = 'spin',
        data = {
            turns = turns, dir = unscrew and 'ccw' or 'cw',
            title = unscrew and 'Spin the old filter off' or 'Spin the new filter on',
            hint = unscrew and 'Hold the mouse and circle it anticlockwise' or 'Hold the mouse and circle it clockwise, until it is snug',
        },
        onEvent = function(name, value)
            if name ~= 'progress' then return end
            local p = tonumber(value) or 0.0
            -- off: it turns and comes down the thread; on: it goes up the thread
            local k = unscrew and p or (1.0 - p)
            hang(e, k * cfg.ThreadDrop, (unscrew and 1 or -1) * p * turns * 360.0)
        end,
        points = function() return filterPoints(e) end,
    })
end

-- ---------------------------------------------------------------- the steps
local refresh

local function step(fn)
    if job.busy then return end
    job.busy = true
    refresh()
    local ok, err = pcall(fn)
    if not ok then print(('^1[bakery_barnfind] oil step failed: %s^7'):format(err)) end
    if job then
        camEnd()
        FreezeEntityPosition(cache.ped, false)
        ClearPedTasks(cache.ped)
        job.busy = false
        refresh()
        if job.done then
            local cb = job.onDone
            Oil.stop()
            if cb then cb() end
        end
    end
end

local ACTIONS = {}

ACTIONS.jack = function(s)
    step(function()
        local side = job.sides[s]
        local j = placeJack(s)
        j.out = J.RollIn
        Jack.pose(j)
        jackView(s)
        Jack.roll(j, J.RollIn, 0.0, 750)
        standAtHandle(j)
        local pumps = cfg.Pumps
        local res = Minigame.run({
            kind = 'pump',
            data = { pumps = pumps, title = 'Jack it up', hint = 'Click, or tap Space, to pump the handle' },
            onEvent = function(name, value)
                if name ~= 'progress' then return end
                local p = tonumber(value) or 0.0
                jackTo(s, p)
                local phase = (p * pumps) % 1.0
                if p >= 1.0 then phase = 0.0 end
                j.handle = J.HandleRest + J.HandleStroke * math.sin(phase * math.pi)
                Jack.pose(j)
            end,
        })
        if res == 'done' then
            jackTo(s, 1.0)
            j.handle = J.HandleRest
            Jack.pose(j)
            side.stage = 'up'
        else
            jackTo(s, 0.0)
            Jack.pose(j)
            Jack.roll(j, 0.0, J.RollIn, 500)
            Jack.remove(j)
            side.jack = nil
        end
    end)
end

ACTIONS.under = function(s)
    step(function()
        lieUnder(s)
        underView(s)
        if job.filterStage == 'old' then
            if spinGame(job.filter, 'off') ~= 'done' then
                hang(job.filter, 0.0, 0.0)
                getUp(s)
                return
            end
            -- it drops off the thread into your hand and goes down on the ground beside you
            local old = job.filter
            DetachEntity(old, false, false)
            local f, r = GetEntityMatrix(job.veh)
            local at = GetEntityCoords(old) + r * (s * 0.35) + f * 0.2
            SetEntityCoordsNoOffset(old, at.x, at.y, groundZ(at) + cfg.FilterRadius, false, false, false)
            SetEntityRotation(old, 90.0, 0.0, math.random(0, 359) + 0.0, 2, false)
            FreezeEntityPosition(old, true)
            job.litter[#job.litter + 1] = old
            job.filter = nil
            job.filterStage = 'off'
            Wait(400)
        end
        if job.filterStage == 'off' then
            local new = prop(cfg.FilterProp, GetEntityCoords(job.veh))
            job.filter = new
            hang(new, cfg.ThreadDrop, 0.0)
            if spinGame(new, 'on') ~= 'done' then
                delete(new)
                job.filter = nil
                getUp(s)
                return
            end
            hang(new, 0.0, 0.0)
            job.filterStage = 'new'
            Bridge.notify(T.oilFilterDone, 'success')
        end
        Wait(300)
        camEnd()
        getUp(s)
    end)
end

ACTIONS.lower = function(s)
    step(function()
        local side = job.sides[s]
        local j = side.jack
        jackView(s)
        standAtHandle(j)
        Wait(400)
        local t0, ms = GetGameTimer(), 1800
        while GetGameTimer() - t0 < ms do
            jackTo(s, 1.0 - ease((GetGameTimer() - t0) / ms))
            Jack.pose(j)
            Wait(0)
        end
        jackTo(s, 0.0)
        Jack.pose(j)
        Jack.roll(j, 0.0, J.RollIn, 600)
        Jack.remove(j)
        side.jack = nil
        side.stage = 'down'
        if job.sides[-s].stage == 'down' then
            job.done = true
            Bridge.notify(T.oilDone:format(Bridge.duration((GetGameTimer() - job.started) / 1000)), 'success')
        end
    end)
end

-- ---------------------------------------------------------------- prompts
local function zone(name, s, action)
    local c = rel(s * (job.halfW + 0.35), job.midY, 0.0)
    return Bridge.addZone({
        name = name,
        coords = vec3(c.x, c.y, groundZ(c) + 0.8),
        heading = GetEntityHeading(job.veh),
        distance = 1.8,
        message = T['oil_' .. action],
        targetMessage = T['oil_' .. action .. 'Target'],
        icon = 'fas fa-oil-can',
        canInteract = function() return job ~= nil and not job.busy end,
        onSelect = function() CreateThread(function() ACTIONS[action](s) end) end,
    })
end

function refresh()
    if not job then return end
    for _, z in ipairs(job.zones) do z.remove() end
    job.zones = {}
    if job.busy or job.done then return end
    local bothUp = job.sides[-1].stage == 'up' and job.sides[1].stage == 'up'
    for _, s in ipairs({ -1, 1 }) do
        local side = job.sides[s]
        local action
        if job.filterStage ~= 'new' then
            if side.stage == 'down' then action = 'jack'
            elseif bothUp then action = 'under' end
        elseif side.stage == 'up' then
            action = 'lower'
        end
        if action then job.zones[#job.zones + 1] = zone(('bk_oil_%d'):format(s), s, action) end
    end
end

-- ---------------------------------------------------------------- start and stop
function Oil.stop()
    if not job then return end
    Minigame.stop()
    camEnd()
    for _, z in ipairs(job.zones) do z.remove() end
    for _, s in ipairs({ -1, 1 }) do Jack.remove(job.sides[s].jack) end
    for _, o in ipairs(job.litter) do delete(o) end
    delete(job.filter)
    FreezeEntityPosition(cache.ped, false)
    ClearPedTasks(cache.ped)
    job = nil
end

-- Change the oil filter on `veh`: jack both sides, get under, filter off and on, let it down. opts.onDone is called
-- once it is back down on its wheels (the job then packs up, leaving the car).
function Oil.begin(veh, opts)
    opts = opts or {}
    StopRestoreJobs()
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    job = {
        veh = veh, onDone = opts.onDone, zones = {}, litter = {}, started = GetGameTimer(),
        halfW = math.min(-mn.x, mx.x), midY = (mn.y + mx.y) * 0.5,
        sides = { [-1] = { side = -1, stage = 'down', t = 0.0 }, [1] = { side = 1, stage = 'down', t = 0.0 } },
        filterStage = 'old',
    }
    if not job or job.veh ~= veh then return false end
    FreezeEntityPosition(veh, true)
    job.base = { pos = GetEntityCoords(veh), rot = GetEntityRotation(veh, 2) }

    -- under the engine, or towards the front if the car has no engine bone
    local bi = GetEntityBoneIndexByName(veh, 'engine')
    if bi ~= -1 then
        local e = GetWorldPositionOfEntityBone(veh, bi)
        job.engine = GetOffsetFromEntityGivenWorldCoords(veh, e.x, e.y, e.z)
    else
        job.engine = vec3(0.0, mx.y * 0.55, 0.0)
    end
    -- measured with the car down: the ray finds the underside, and the filter keeps that spot as the car moves
    job.filterAt = filterSpot()
    job.filter = prop(cfg.FilterProp, GetEntityCoords(veh))
    hang(job.filter, 0.0, 0.0)
    -- where you lie: level with the filter, unless that puts you through a wheel; then just inside it
    job.lieY = job.filterAt.y
    for _, b in ipairs({ 'wheel_lf', 'wheel_lr' }) do
        local wi = GetEntityBoneIndexByName(veh, b)
        if wi ~= -1 then
            local wp = GetWorldPositionOfEntityBone(veh, wi)
            local wy = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z).y
            if math.abs(job.lieY - wy) < cfg.WheelClear then
                job.lieY = wy + (wy > job.midY and -cfg.WheelClear or cfg.WheelClear)
            end
        end
    end

    refresh()
    return true
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Oil.stop() end
end)
