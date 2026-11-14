-- The trolley jack (stream/bk_jack_*.ydr, built by props_src/build_jack.py): four props driven by script.
-- The base sits on the ground with its saddle end towards the car. The arm pitches up about its pivot, the saddle
-- rides level on the arm's tip, and the handle pumps up and down about its socket. As the arm rises its tip swings
-- back, so the base rolls forward under it to keep the saddle on the same spot, as a real trolley jack does.
do
    Jack = {}

    local C = Tuning.Restore.Wheels.Jack
    local REST = math.rad(C.RestAngle)

    local function model(name)
        local hash = joaat(name)
        lib.requestModel(hash, 10000)
        return hash
    end

    local function part(name, pos)
        local o = CreateObject(model(name), pos.x, pos.y, pos.z, false, false, false)
        SetModelAsNoLongerNeeded(joaat(name))
        SetEntityCollision(o, false, false)
        return o
    end

    -- Where the arm's tip is (base-local Y, Z) for an arm angle in radians.
    local function tip(theta)
        return C.ArmPivot.y + math.cos(theta) * C.ArmLength, C.ArmPivot.z + math.sin(theta) * C.ArmLength
    end

    -- Arm angle that puts the top of the saddle `h` metres above the ground.
    local function angleFor(h)
        local s = (h - C.SaddleTop - C.ArmPivot.z) / C.ArmLength
        return math.asin(math.max(math.sin(REST), math.min(math.sin(math.rad(C.MaxAngle)), s)))
    end

    -- spot: the point on the ground right under the car's jacking point. inward: flat unit vector from the jack's
    -- handle end towards its saddle end (into the car).
    function Jack.new(spot, inward)
        local j = {
            spot = spot, inward = inward,
            heading = math.deg(math.atan(-inward.x, inward.y)),   -- an entity's forward is (-sin h, cos h)
            theta = REST, handle = C.HandleRest, out = 0.0,
        }
        j.base = part(C.Models.base, spot)
        j.arm = part(C.Models.arm, spot)
        j.saddle = part(C.Models.saddle, spot)
        j.handleProp = part(C.Models.handle, spot)
        FreezeEntityPosition(j.base, true)
        Jack.pose(j)
        return j
    end

    -- Puts every part where j.theta (arm), j.handle (degrees) and j.out (metres rolled back out from under the car) say.
    function Jack.pose(j)
        local ty, tz = tip(j.theta)
        -- the base slides so the saddle stays over the spot
        local origin = j.spot - j.inward * (ty + j.out)
        SetEntityCoordsNoOffset(j.base, origin.x, origin.y, j.spot.z, false, false, false)
        SetEntityRotation(j.base, 0.0, 0.0, j.heading, 2, false)
        local p = C.ArmPivot
        AttachEntityToEntity(j.arm, j.base, 0, p.x, p.y, p.z, math.deg(j.theta), 0.0, 0.0, false, false, false, false, 2, true)
        AttachEntityToEntity(j.saddle, j.base, 0, 0.0, ty, tz, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        local h = C.HandlePivot
        AttachEntityToEntity(j.handleProp, j.base, 0, h.x, h.y, h.z, j.handle, 0.0, 0.0, false, false, false, false, 2, true)
    end

    -- Height of the top of the saddle above the ground.
    function Jack.saddleHeight(j)
        local _, tz = tip(j.theta)
        return tz + C.SaddleTop
    end

    function Jack.setSaddle(j, h)
        j.theta = angleFor(h)
    end

    function Jack.restHeight()
        local _, tz = tip(REST)
        return tz + C.SaddleTop
    end

    function Jack.maxHeight()
        local _, tz = tip(math.rad(C.MaxAngle))
        return tz + C.SaddleTop
    end

    -- Where the end of the handle is, for standing at it.
    function Jack.grip(j)
        return GetOffsetFromEntityInWorldCoords(j.handleProp, 0.0, -0.88, 0.0)
    end

    -- Rolls the jack in from `from` metres out (or back out to it), over ms.
    function Jack.roll(j, from, to, ms)
        local t0 = GetGameTimer()
        while true do
            local k = math.min(1.0, (GetGameTimer() - t0) / ms)
            local e = k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2
            j.out = from + (to - from) * e
            Jack.pose(j)
            if k >= 1.0 then break end
            Wait(0)
        end
    end

    function Jack.remove(j)
        if not j then return end
        for _, e in ipairs({ j.saddle, j.arm, j.handleProp, j.base }) do
            if e and DoesEntityExist(e) then DeleteEntity(e) end
        end
    end
end


-- Restoring, by hand: changing all four wheels. Each corner goes through
--   on -> jacked -> loose -> off -> fitted -> tight -> done
-- roll the trolley jack under the car and pump it up (client/jack.lua), undo the nuts (impact gun, any order), pull
-- the old wheel off, line the new one's holes up with the studs and push it on, do the nuts up in a star pattern to
-- the right torque, then let the car down. There is one jack, so one corner at a time.
--
-- The car's own wheel is hidden while it is off (SetVehicleWheelXOffset, set once: setting it every frame on a
-- frozen car keeps pushing the wheel further out); the new wheel you line up is a prop until it seats.
--
-- Wheels.begin runs it on a find in the barn (client/finds.lua runs the restore steps).
Wheels = {}

local cfg = Tuning.Restore.Wheels
local T = Tuning.Restore.Text

-- wheel index (SetVehicleWheelXOffset), tyre index (SetVehicleTyreFixed), bone, side (-1 left, 1 right)
local CORNERS = {
    { index = 0, tyre = 0, bone = 'wheel_lf', side = -1, front = true },
    { index = 1, tyre = 1, bone = 'wheel_rf', side = 1,  front = true },
    { index = 2, tyre = 4, bone = 'wheel_lr', side = -1, front = false },
    { index = 3, tyre = 5, bone = 'wheel_rr', side = 1,  front = false },
}

local job = nil
local settle

-- ---------------------------------------------------------------- helpers
local function model(name)
    local hash = joaat(name)
    lib.requestModel(hash, 10000)
    return hash
end

local function prop(name, pos)
    local o = CreateObject(model(name), pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(joaat(name))
    return o
end

local function delete(e) if e and DoesEntityExist(e) then DeleteEntity(e) end end

local function norm(v)
    local l = #v
    return l > 0.0001 and v / l or v
end

-- World point from a point relative to the car.
local function rel(v) return GetOffsetFromEntityInWorldCoords(job.veh, v.x + 0.0, v.y + 0.0, v.z + 0.0) end

-- The car's axes right now (they tilt while a corner is jacked).
local function axes()
    local f, r, u = GetEntityMatrix(job.veh)
    return f, r, u
end

local function groundZ(p)
    local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
    return ok and z or p.z
end

local function anim(a)
    lib.requestAnimDict(a.dict, 5000)
    TaskPlayAnim(cache.ped, a.dict, a.clip, 4.0, 4.0, -1, a.flag or 0, 0.0, false, false, false)
end

-- The wheel's centre. The bone is right while the wheel is on (a refitted wheel on a raised car hangs lower on its
-- suspension than where it came off, and the bone follows that). Once the wheel is hidden its bone is not right,
-- and it can still be wrong for a moment after the wheel goes back. So the spot is remembered (relative to the car)
-- as the wheel comes off, and used while it is off or whenever the bone is clearly somewhere else.
local function hub(w)
    if w.stage == 'off' then return rel(w.hub) end
    local b = GetWorldPositionOfEntityBone(job.veh, w.bone)
    if w.hub then
        local saved = rel(w.hub)
        if #(b - saved) > 0.6 then return saved end
    end
    return b
end

local function hubRel(w)
    local p = GetWorldPositionOfEntityBone(job.veh, w.bone)
    return GetOffsetFromEntityGivenWorldCoords(job.veh, p.x, p.y, p.z)
end

-- Centre of the wheel's outer face.
local function face(w)
    local _, r = axes()
    return hub(w) + r * (w.side * (w.width * 0.5 + 0.015))
end

-- Points around the hub face, in the wheel's plane, `radius` out, starting at the top.
local function ring(w, centre, radius, n, turn)
    local f, _, u = axes()
    local out = {}
    for k = 1, n do
        local a = (k - 1) / n * math.pi * 2.0 + (turn or 0.0)
        out[k] = centre + (u * math.cos(a) + f * (math.sin(a) * -w.side)) * radius
    end
    return out
end

local function nutRadius(w) return math.max(0.045, w.rim * cfg.NutCircle) end

-- ---------------------------------------------------------------- the player
-- Walk to a spot beside the wheel, face it and kneel.
local function kneelAt(w)
    local _, r = axes()
    local f = axes()
    local spot = hub(w) + r * (w.side * 0.78) + f * ((w.front and -1 or 1) * 0.18)
    spot = vec3(spot.x, spot.y, groundZ(spot))
    local h = GetHeadingFromVector_2d(hub(w).x - spot.x, hub(w).y - spot.y)
    local ped = cache.ped
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 3000, h, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 3000 and #(GetEntityCoords(ped).xy - spot.xy) > 0.25 do Wait(50) end
    ClearPedTasks(ped)
    SetEntityHeading(ped, h)
    anim(cfg.Anims.kneel)
end

local function gun(on)
    if on and not job.gun then
        job.gun = prop(cfg.GunProp, GetEntityCoords(cache.ped))
        AttachEntityToEntity(job.gun, cache.ped, GetPedBoneIndex(cache.ped, 57005), 0.10, 0.02, -0.03, -90.0, 0.0, -10.0, true, true, false, true, 1, true)
    elseif not on and job.gun then
        delete(job.gun)
        job.gun = nil
    end
end

local function stand()
    gun(false)
    ClearPedTasks(cache.ped)
end

-- ---------------------------------------------------------------- the camera
-- out: metres out from the wheel; along: towards the near end of the car; up: above the hub.
local function closeUp(w, out, along, up)
    local f, r, u = axes()
    local c = face(w)
    local pos = c + r * (w.side * (out or 0.92)) + f * ((w.front and 1 or -1) * (along or 0.32)) + u * (up or 0.14)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 42.0, false, 2)
    PointCamAtCoord(cam, c.x, c.y, c.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    job.cam = cam
    -- you are kneeling right where the camera looks: keep yourself out of the shot
    CreateThread(function()
        while job and job.cam == cam do
            SetEntityLocallyInvisible(cache.ped)
            if job.gun then SetEntityLocallyInvisible(job.gun) end
            Wait(0)
        end
    end)
    Wait(520)
end

local function closeUpEnd()
    if not job or not job.cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(job.cam, false)
    job.cam = nil
end

-- ---------------------------------------------------------------- the jack
-- t = 0 (resting) .. 1 (corner fully up) for the wheel the jack is under.
-- The corner comes up JackLift, leaning the car sideways and lengthways towards the jack while the diagonal
-- corner stays on the ground.
local function lift(w, t)
    local base = job.base
    local l = cfg.JackLift * t
    local pitch = (w.front and 1 or -1) * math.deg(math.atan(l * 0.25, math.max(0.5, math.abs(w.at.y))))
    local roll = -w.side * math.deg(math.atan(l * 0.25, math.max(0.4, math.abs(w.at.x))))
    local p = base.pos + vec3(0.0, 0.0, l * 0.8)
    SetEntityCoordsNoOffset(job.veh, p.x, p.y, p.z, false, false, false)
    SetEntityRotation(job.veh, base.rot.x + pitch, base.rot.y + roll, base.rot.z, 2, false)
end

-- The jack goes under the sill next to the wheel. Its saddle meets the car wherever the underside is right above
-- that spot (found with a ray), and the corner starts to come up once the saddle is there.
local function placeJack(w)
    local J = cfg.Jack
    local _, r = axes()
    local c = rel(vec3(w.at.x - w.side * J.In, w.at.y + (w.front and -J.Along or J.Along), w.at.z))
    local gz = groundZ(c)
    local spot = vec3(c.x, c.y, gz)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(spot.x, spot.y, gz + 0.03, spot.x, spot.y, gz + 1.6, 2, 0, 4)
    local _, hit, at = GetShapeTestResult(ray)
    local contact = (hit == 1) and (at.z - gz) or 0.28
    contact = math.max(Jack.restHeight() + 0.02, math.min(Jack.maxHeight() - cfg.JackLift, contact))
    local inward = -r * w.side
    inward = norm(vec3(inward.x, inward.y, 0.0))
    job.jack = Jack.new(spot, inward)
    job.jack.contact = contact
    job.jackOn = w
    return job.jack
end

-- How far the jack has got (0 down .. 1 corner fully up): saddle up to the car, then the car with it.
local function jackTo(w, p)
    local j = job.jack
    local h0, top = Jack.restHeight(), j.contact + cfg.JackLift
    local h = h0 + (top - h0) * p
    Jack.setSaddle(j, h)
    lift(w, math.max(0.0, h - j.contact) / cfg.JackLift)
end

local function removeJack()
    Jack.remove(job.jack)
    job.jack = nil
    job.jackOn = nil
end

-- A side-on view of the jack and the corner while you work the handle.
local function jackView(w)
    local f, r = axes()
    local out = r * w.side
    local target = (job.jack.spot + hub(w)) * 0.5 + vec3(0.0, 0.0, 0.15)
    local pos = target + out * 1.7 + f * ((w.front and -1 or 1) * 2.3) + vec3(0.0, 0.0, 0.45)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 46.0, false, 2)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, true)
    job.cam = cam
end

-- Kneel at the end of the handle, facing the car, hands on the grip.
local function standAtHandle()
    local j = job.jack
    local g = Jack.grip(j)
    local spot = vec3(g.x, g.y, 0.0) - j.inward * 0.40
    spot = vec3(spot.x, spot.y, groundZ(vec3(spot.x, spot.y, g.z)))
    local ped = cache.ped
    local h = j.heading
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 3000, h, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 3000 and #(GetEntityCoords(ped).xy - spot.xy) > 0.25 do Wait(50) end
    ClearPedTasks(ped)
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(ped, h)
    anim(cfg.Anims.kneel)
end

-- A new tyre is taller than the flat it replaced, so its corner sits higher once the car is down. The car stays
-- frozen (letting physics settle it changes how the other flat tyres are drawn), so that corner is raised by
-- hand until the new tyre just meets the ground, and that becomes the car's resting pose.
settle = function(w)
    local radius = GetVehicleWheelTireColliderSize(job.veh, w.index)
    local t = 0.0
    for _ = 1, 5 do
        local b = GetWorldPositionOfEntityBone(job.veh, w.bone)
        local short = radius - (b.z - groundZ(b))   -- how far the tyre is into the ground
        if math.abs(short) < 0.004 then break end
        t = math.max(0.0, t + short / cfg.JackLift)
        lift(w, t)
        Wait(0)
    end
    job.base = { pos = GetEntityCoords(job.veh), rot = GetEntityRotation(job.veh, 2) }
end

-- ---------------------------------------------------------------- the steps
local refresh

local function step(w, fn)
    if job.busy then return end
    job.busy = true
    refresh()
    local ok, err = pcall(fn)
    if not ok then print(('^1[bakery_barnfind] wheel step failed: %s^7'):format(err)) end
    if job then
        closeUpEnd()
        stand()
        job.busy = false
        refresh()
        if job.finished then
            local cb = job.onDone
            Wheels.stop()
            if cb then cb() end
        end
    end
end

local ACTIONS = {}

ACTIONS.jack = function(w)
    if job.jackOn and job.jackOn ~= w then return Bridge.notify(T.jackInUse, 'error') end
    step(w, function()
        local J = cfg.Jack
        local j = placeJack(w)
        j.out = J.RollIn
        Jack.pose(j)
        jackView(w)
        Jack.roll(j, J.RollIn, 0.0, 750)
        standAtHandle()
        local pumps = cfg.Pumps
        local res = Minigame.run({
            kind = 'pump',
            data = { pumps = pumps, title = 'Jack it up', hint = 'Click, or tap Space, to pump the handle' },
            onEvent = function(name, value)
                if name ~= 'progress' then return end
                local p = tonumber(value) or 0.0
                jackTo(w, p)
                -- each stroke pushes the handle down and lets it back up
                local phase = (p * pumps) % 1.0
                if p >= 1.0 then phase = 0.0 end
                j.handle = J.HandleRest + J.HandleStroke * math.sin(phase * math.pi)
                Jack.pose(j)
            end,
        })
        if res == 'done' then
            jackTo(w, 1.0)
            j.handle = J.HandleRest
            Jack.pose(j)
            w.stage = 'jacked'
        else
            jackTo(w, 0.0)
            Jack.pose(j)
            Jack.roll(j, 0.0, J.RollIn, 500)
            removeJack()
        end
    end)
end

local function nutGame(w, mode)
    closeUp(w)
    gun(true)
    local n = cfg.Nuts
    return Minigame.run({
        kind = mode,
        data = {
            nuts = n,
            title = mode == 'loosen' and 'Undo the wheel nuts' or 'Do the nuts up',
            hint = mode == 'loosen' and 'Hold the mouse on a nut to spin it off' or 'Star pattern: go across the wheel. Let go in the green.',
            ms = mode == 'loosen' and cfg.LoosenMs or cfg.TightenMs,
            band = cfg.TorqueBand,
        },
        points = function() return ring(w, face(w), nutRadius(w), n), 0.022 end,
    })
end

ACTIONS.loosen = function(w)
    step(w, function()
        kneelAt(w)
        if nutGame(w, 'loosen') == 'done' then w.stage = 'loose' end
    end)
end

ACTIONS.pull = function(w)
    step(w, function()
        kneelAt(w)
        Wait(700)
        w.hub = hubRel(w)
        SetVehicleWheelXOffset(job.veh, w.index, w.side * 60.0)   -- out of sight
        w.stage = 'off'
        -- the old wheel goes down flat on the ground, out of the way along the car
        local f, r = axes()
        local at = hub(w) + r * (w.side * 1.05) + f * ((w.front and 1 or -1) * 0.75)
        local old = prop(cfg.OldProp, at)
        SetEntityCoordsNoOffset(old, at.x, at.y, groundZ(at) + 0.12, false, false, false)
        SetEntityRotation(old, 90.0, 0.0, math.random(0, 359) + 0.0, 2, false)
        FreezeEntityPosition(old, true)
        SetEntityCollision(old, false, false)
        job.litter[#job.litter + 1] = old
        Wait(300)
    end)
end

ACTIONS.fit = function(w)
    step(w, function()
        kneelAt(w)
        -- the new wheel hangs just off the hub, turned so its holes miss the studs
        local wheel = prop(cfg.NewProp, hub(w))
        SetEntityCollision(wheel, false, false)
        local out = 0.22
        local angle = math.random(18, 54) + 0.0
        local spacing = 360.0 / cfg.Nuts
        local function place()
            local o = w.hub + vec3(w.side * out, 0.0, 0.0)
            AttachEntityToEntity(wheel, job.veh, 0, o.x, o.y, o.z, 0.0, angle, 90.0, false, false, false, false, 2, true)
        end
        place()
        closeUp(w, 1.55, 0.0, 0.0)   -- straight down the axle, so the holes and studs share a centre
        local n = cfg.Nuts
        local res = Minigame.run({
            kind = 'fit',
            data = {
                nuts = n, spacing = spacing, start = angle, tolerance = cfg.AlignTolerance,
                title = 'Fit the new wheel', hint = 'Drag sideways (or scroll) to turn it. Line the holes up with the studs, then click to push it on',
            },
            onEvent = function(name, value)
                if name == 'angle' then angle = tonumber(value) or angle; place() end
            end,
            points = function()
                local studs = ring(w, face(w), nutRadius(w), n)
                local holes = {}
                for k = 1, n do
                    local a = math.rad((k - 1) * spacing)
                    local r = nutRadius(w)
                    holes[k] = GetOffsetFromEntityInWorldCoords(wheel, math.sin(a) * r, 0.0, math.cos(a) * r)
                end
                for k = 1, n do studs[#studs + 1] = holes[k] end
                return studs, 0.022
            end,
        })
        if res == 'done' then
            -- slide it home, then swap the prop for the car's own wheel
            local t0 = GetGameTimer()
            while GetGameTimer() - t0 < 380 do
                out = 0.22 * (1.0 - (GetGameTimer() - t0) / 380)
                place()
                Wait(0)
            end
            delete(wheel)
            SetVehicleWheelXOffset(job.veh, w.index, w.xoff)
            SetVehicleTyreFixed(job.veh, w.tyre)
            Wait(150)   -- let the wheel's bone catch up before the nuts prompt is placed on it
            w.stage = 'fitted'
        else
            delete(wheel)
        end
    end)
end

ACTIONS.tighten = function(w)
    step(w, function()
        kneelAt(w)
        if nutGame(w, 'tighten') == 'done' then w.stage = 'tight' end
    end)
end

ACTIONS.lower = function(w)
    step(w, function()
        local j = job.jack
        jackView(w)
        standAtHandle()
        Wait(400)
        -- open the release valve: the arm sinks, the car comes down onto its wheel, the jack rolls back out
        local t0, ms = GetGameTimer(), 1800
        while GetGameTimer() - t0 < ms do
            local k = (GetGameTimer() - t0) / ms
            jackTo(w, 1.0 - (k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2))
            Jack.pose(j)
            Wait(0)
        end
        jackTo(w, 0.0)
        Jack.pose(j)
        Jack.roll(j, 0.0, cfg.Jack.RollIn, 600)
        removeJack()
        w.stage = 'done'
        w.hub = nil   -- the car settles onto the new tyre: back to the bone
        settle(w)
        local left = 0
        for _, x in ipairs(job.wheels) do if x.stage ~= 'done' then left = left + 1 end end
        if left == 0 then
            Bridge.notify(T.allDone:format(Bridge.duration((GetGameTimer() - job.started) / 1000)), 'success')
            job.finished = true
        else
            Bridge.notify(T.wheelsLeft:format(left), 'info')
        end
    end)
end

-- ---------------------------------------------------------------- prompts
local NEXT = { on = 'jack', jacked = 'loosen', loose = 'pull', off = 'fit', fitted = 'tighten', tight = 'lower' }

-- the target for this step: through kq_link, so it is whatever the server has set (ox_target, qb-target, 3D text...)
local function zone(name, coords, action, onSelect)
    return Bridge.addZone({
        name = name,
        coords = coords,
        heading = GetEntityHeading(job.veh),
        distance = 1.6,
        message = T[action],
        targetMessage = T[action .. 'Target'],
        icon = 'fas fa-wrench',
        canInteract = function() return job ~= nil and not job.busy end,
        onSelect = onSelect,
    })
end

function refresh()
    if not job then return end
    for _, z in ipairs(job.zones) do z.remove() end
    job.zones = {}
    if job.busy then return end
    local _, r = axes()
    for _, w in ipairs(job.wheels) do
        local action = NEXT[w.stage]
        if action == 'jack' and job.jackOn then action = nil end
        if action then
            local c = hub(w) + r * (w.side * 0.55)
            w.zoneAt = c
            job.zones[#job.zones + 1] = zone(('bk_wheel_%d'):format(w.index), vec3(c.x, c.y, c.z + 0.3), action, function() CreateThread(function() ACTIONS[action](w) end) end)
        end
    end
end

-- ---------------------------------------------------------------- start and stop
function Wheels.stop()
    if not job then return end
    Minigame.stop()
    closeUpEnd()
    for _, z in ipairs(job.zones) do z.remove() end
    for _, o in ipairs(job.litter) do delete(o) end
    Jack.remove(job.jack)
    delete(job.gun)
    ClearPedTasks(cache.ped)
    job = nil
end

-- Every restore job: stop whichever one is running. Shared by them all.
function StopRestoreJobs()
    for _, m in ipairs({ Wheels, Glass, Oil, Body, Ignition }) do
        if m and m.stop then m.stop() end
    end
end

-- Change all four wheels on `veh`. opts.onDone is called once every wheel is on (the job then packs up, leaving
-- the car).
function Wheels.begin(veh, opts)
    opts = opts or {}
    StopRestoreJobs()
    job = { veh = veh, onDone = opts.onDone, wheels = {}, zones = {}, litter = {}, started = GetGameTimer() }

    -- worn out: every tyre flat (deflated, not shredded down to the rim). Let it settle, then pin it.
    FreezeEntityPosition(veh, false)
    for _, c in ipairs(CORNERS) do SetVehicleTyreBurst(veh, c.tyre, false, 1000.0) end
    Wait(1200)
    if not job or job.veh ~= veh then return false end
    FreezeEntityPosition(veh, true)
    Wait(50)

    -- where each hub is, measured once the car has settled and before any wheel is touched
    -- (the bones go stale once an offset is set)
    for _, c in ipairs(CORNERS) do
        local bi = GetEntityBoneIndexByName(veh, c.bone)
        if bi ~= -1 and c.index < GetVehicleNumberOfWheels(veh) then
            local wp = GetWorldPositionOfEntityBone(veh, bi)
            job.wheels[#job.wheels + 1] = {
                index = c.index, tyre = c.tyre, side = c.side, front = c.front, bone = bi,
                at = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z),   -- for the jack's lean
                xoff = GetVehicleWheelXOffset(veh, c.index),
                rim = GetVehicleWheelRimColliderSize(veh, c.index),
                width = GetVehicleWheelTireColliderWidth(veh, c.index),
                stage = 'on',
            }
        end
    end
    if #job.wheels < 4 then
        Wheels.stop()
        Bridge.notify(T.notFourWheels, 'error')
        return false
    end

    job.base = { pos = GetEntityCoords(veh), rot = GetEntityRotation(veh, 2) }
    refresh()
    return true
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Wheels.stop() end
end)
