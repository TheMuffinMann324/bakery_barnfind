-- Restoring, by hand: bodywork. The car comes in dented and grimy on each face (left, right, front, rear). Each
-- face has its own prompt: grind it back to bare metal with an angle grinder. The grinder follows your cursor on the
-- panel, disc flat against it, sparks where it bites. It is a percentage: the face is split into small areas and
-- each one fills as the grinder works over it, so you have to cover the lot. When a face is ground it is done and
-- its dents come out. The grime is left on.
--
-- Nothing here is shaped to a car: the spots are found by casting rays at the car from outside each face, so they
-- always sit on whatever bodywork the model has.
--
-- Body.begin runs it on a find in the barn (client/finds.lua runs the restore steps).
Body = {}

local cfg = Tuning.Restore.Body
local T = Tuning.Restore.Text

-- Each face: which way it looks (car space) and its name in the prompts.
local FACES = {
    { id = 'left',  n = vec3(-1.0, 0.0, 0.0), label = 'left side' },
    { id = 'right', n = vec3(1.0, 0.0, 0.0),  label = 'right side' },
    { id = 'front', n = vec3(0.0, 1.0, 0.0),  label = 'front' },
    { id = 'rear',  n = vec3(0.0, -1.0, 0.0), label = 'rear' },
}

local job = nil

-- ---------------------------------------------------------------- helpers
local function model(name)
    local hash = joaat(name)
    lib.requestModel(hash, 10000)
    return hash
end

local function delete(e) if e and DoesEntityExist(e) then DeleteEntity(e) end end

local function rel(v) return GetOffsetFromEntityInWorldCoords(job.veh, v.x + 0.0, v.y + 0.0, v.z + 0.0) end

-- A direction from car space to world space.
local function dir(v)
    local f, r, u = GetEntityMatrix(job.veh)
    return r * v.x + f * v.y + u * v.z
end

local function groundZ(p)
    local ok, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
    return ok and z or p.z
end

-- ---------------------------------------------------------------- finding the bodywork
-- Which work area of a face a car-space point falls in: a square of WorkCell metres, across the face.
local function cellOf(n, o)
    local u = n.x ~= 0.0 and o.y or o.x
    return ('%d:%d'):format(math.floor(u / cfg.WorkCell), math.floor(o.z / cfg.WorkCell))
end

-- Rays from outside a face, aimed straight in at the car. Hits on the car's body (not a wheel, light or plate) are kept, as car-space
-- points. Then a spread-out few of them are picked as the patches.
local function sample(veh, face, mn, mx, wheels, avoid)
    local h = mx.z - mn.z
    local zlo, zhi = mn.z + h * cfg.Band[1], mn.z + h * cfg.Band[2]
    local hits = {}
    for _ = 1, cfg.Rays do
        local a, b = math.random(), math.random()
        local z = zlo + (zhi - zlo) * b
        local from, to
        if face.n.x ~= 0.0 then
            local y = mn.y * 0.82 + (mx.y * 0.82 - mn.y * 0.82) * a
            from, to = vec3(face.n.x * (math.abs(face.n.x > 0 and mx.x or mn.x) + 1.0), y, z), vec3(0.0, y, z)
        else
            local x = mn.x * 0.72 + (mx.x * 0.72 - mn.x * 0.72) * a
            from, to = vec3(x, face.n.y * (math.abs(face.n.y > 0 and mx.y or mn.y) + 1.0), z), vec3(x, 0.0, z)
        end
        local wf = GetOffsetFromEntityInWorldCoords(veh, from.x, from.y, from.z)
        local wt = GetOffsetFromEntityInWorldCoords(veh, to.x, to.y, to.z)
        local ray = StartExpensiveSynchronousShapeTestLosProbe(wf.x, wf.y, wf.z, wt.x, wt.y, wt.z, 2, 0, 4)
        local _, hit, at, normal, ent = GetShapeTestResult(ray)
        if hit == 1 and ent == veh then
            local o = GetOffsetFromEntityGivenWorldCoords(veh, at.x, at.y, at.z)
            local f, r, u = GetEntityMatrix(veh)
            local nl = vec3(normal.x * r.x + normal.y * r.y + normal.z * r.z, normal.x * f.x + normal.y * f.y + normal.z * f.z,
                normal.x * u.x + normal.y * u.y + normal.z * u.z)
            -- a hit that faces away from where the ray came from is an edge or the inside of something
            if nl.x * face.n.x + nl.y * face.n.y + nl.z * face.n.z < 0.35 then o = nil end
            local clear = o ~= nil
            for _, w in ipairs(clear and wheels or {}) do
                if math.abs(o.y - w.y) < w.r + 0.12 and o.z < w.z + w.r + 0.10 then clear = false break end
            end
            for _, b in ipairs(clear and avoid or {}) do
                if #(o - b) < cfg.AvoidRadius then clear = false break end
            end
            if clear then hits[#hits + 1] = { p = o, n = nl } end
        end
    end
    -- every area of the face a ray found bodywork in is an area to work
    local cells, ncells = {}, 0
    for _, h in ipairs(hits) do
        local k = cellOf(face.n, h.p)
        if not cells[k] then cells[k] = true ncells = ncells + 1 end
    end
    -- farthest-point picking, so the patches spread over the face
    local out, normals = {}, {}
    if #hits == 0 then return out, normals, cells, ncells end
    local first = table.remove(hits, math.random(#hits))
    out[1], normals[1] = first.p, first.n
    while #out < cfg.Patches[face.n.x ~= 0.0 and 'side' or 'end'] and #hits > 0 do
        local best, bestD = 1, -1
        for i, h in ipairs(hits) do
            local d = math.huge
            for _, q in ipairs(out) do d = math.min(d, #(h.p - q)) end
            if d > bestD then best, bestD = i, d end
        end
        if bestD < cfg.MinGap then break end
        local h = table.remove(hits, best)
        out[#out + 1], normals[#normals + 1] = h.p, h.n
    end
    return out, normals, cells, ncells
end

-- Dents: a knock at a couple of the patches on each face that is still rough.
local function dent(veh, faces)
    for _, f in ipairs(faces) do
        if f.stage ~= 'done' then
            for k = 1, math.min(cfg.Dents, #f.patches) do
                local p = f.patches[k] - f.n * 0.05
                SetVehicleDamage(veh, p.x, p.y, p.z, cfg.DentDamage, cfg.DentRadius, true)
            end
        end
    end
end

-- ---------------------------------------------------------------- the camera
local function centre(f)
    local c = vec3(0.0, 0.0, 0.0)
    for _, p in ipairs(f.patches) do c = c + p end
    return c / #f.patches
end

local function standAt(f)
    local c = centre(f)
    local spot = rel(c + f.n * 0.75)
    spot = vec3(spot.x, spot.y, groundZ(spot))
    local wc = rel(c)
    local h = GetHeadingFromVector_2d(wc.x - spot.x, wc.y - spot.y)
    local ped = cache.ped
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 4000, h, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 4000 and #(GetEntityCoords(ped).xy - spot.xy) > 0.3 do Wait(50) end
    ClearPedTasks(ped)
    SetEntityHeading(ped, h)   -- just stand there: no animation while you work
end

-- Square on to the face, far enough back to see every patch.
local function closeUp(f)
    local c = centre(f)
    local spread = 0.25
    for _, p in ipairs(f.patches) do spread = math.max(spread, #(p - c)) end
    local fov = cfg.CamFov
    local dist = (spread + 0.12) / math.tan(math.rad(fov) * 0.5)
    local target = rel(c)
    local pos = rel(c + f.n * dist + vec3(0.0, 0.0, dist * 0.18))
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov, false, 2)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 600, true, true)
    job.cam = cam
    CreateThread(function()
        while job and job.cam == cam do
            SetEntityLocallyInvisible(cache.ped)
            Wait(0)
        end
    end)
    Wait(620)
end

local function closeUpEnd()
    if not job or not job.cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(job.cam, false)
    job.cam = nil
end

-- The world direction through a point on the screen (0..1 across and down), from the camera as rendered (a camera
-- aimed with PointCamAtCoord does not report that aim through GetCamRot).
local function screenRay(_, sx, sy)
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local fwd = vec3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
    local right = vec3(math.cos(z), math.sin(z), 0.0)
    local up = vec3(right.y * fwd.z - right.z * fwd.y, right.z * fwd.x - right.x * fwd.z, right.x * fwd.y - right.y * fwd.x)
    local t = math.tan(math.rad(GetFinalRenderedCamFov()) * 0.5)
    local d = fwd + right * ((sx - 0.5) * 2.0 * t * GetAspectRatio(false)) + up * ((0.5 - sy) * 2.0 * t)
    return GetFinalRenderedCamCoord(), d / #d
end

local function cross(a, b) return vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function unit(v) local l = #v return l > 0.0001 and v / l or v end

-- ---------------------------------------------------------------- the tool against the panel
-- The grinder is a free prop, not in your hand: every frame it goes where the cursor meets the car,
-- its disc flat on the panel and its body (the battery end) leaning back off it, down the panel.
local function toolPose(spec, contact, n, lift, shake)
    -- down the panel: world down, flattened onto it (or the car's forward on a flat-ish face)
    local up = vec3(0.0, 0.0, -1.0)
    local along = up - n * (up.x * n.x + up.y * n.y + up.z * n.z)
    if #along < 0.2 then along = dir(vec3(0.0, 1.0, 0.0)) end
    along = unit(along)
    local t = math.rad(spec.Tilt)
    local body = unit(along * math.cos(t) + n * math.sin(t))       -- where the tool's body points
    local norm = unit(n * math.cos(t) - along * math.sin(t))       -- the disc's face, out of the panel
    local side = cross(norm, body)
    -- the model's own axes: A (towards its body), Z (out of the disc), B = Z x A
    local A = spec.Body
    local Z = vec3(0.0, 0.0, 1.0)
    local B = cross(Z, A)
    local function world(v) return body * (v.x * A.x + v.y * A.y + v.z * A.z) + side * (v.x * B.x + v.y * B.y + v.z * B.z) + norm * v.z end
    local X, Y, Zw = world(vec3(1.0, 0.0, 0.0)), world(vec3(0.0, 1.0, 0.0)), world(vec3(0.0, 0.0, 1.0))
    local at = contact + n * (lift + 0.002) + (shake or vec3(0.0, 0.0, 0.0)) - world(spec.Disc)
    return X, Y, Zw, at
end

local function toolStart(f, kind)
    local spec = cfg.Tools[kind]
    local o = CreateObject(model(spec.Model), 0.0, 0.0, 0.0, false, false, false)
    SetModelAsNoLongerNeeded(joaat(spec.Model))
    SetEntityCollision(o, false, false)
    FreezeEntityPosition(o, true)
    job.disc = { e = o, spec = spec, kind = kind, face = f }
    local d = job.disc
    -- start on the middle of the face, off the panel
    d.contact, d.n, d.lift = rel(centre(f)), dir(f.n), 0.05
    CreateThread(function()
        while job and job.disc == d do
            local cur = job.cur
            if cur and job.cam then
                local from, ray = screenRay(job.cam, cur.x, cur.y)
                local to = from + ray * 8.0
                local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 2, cache.ped, 4)
                local _, hit, at, normal, ent = GetShapeTestResult(h)
                d.onCar = hit == 1 and ent == job.veh
                if d.onCar then
                    -- glide, rather than snap, to the new spot
                    local before = d.contact
                    d.contact = d.contact + (at - d.contact) * 0.55
                    d.moved = #(d.contact - before)
                    d.n = unit(d.n + (normal - d.n) * 0.4)
                else
                    d.moved = 0.0
                end
                d.working = cur.held
            end
            if d.tick then d.tick() end
            local lift = d.working and 0.0 or spec.Lift
            d.lift = d.lift + (lift - d.lift) * 0.3
            local shake = nil
            if d.working then
                local j = spec.Shake
                shake = vec3((math.random() - 0.5) * j, (math.random() - 0.5) * j, (math.random() - 0.5) * j)
            end
            local X, Y, Z, at = toolPose(spec, d.contact, d.n, d.lift, shake)
            SetEntityMatrix(d.e, Y.x, Y.y, Y.z, X.x, X.y, X.z, Z.x, Z.y, Z.z, at.x, at.y, at.z)
            Wait(0)
        end
    end)
end

local function toolStop()
    if not job or not job.disc then return end
    delete(job.disc.e)
    job.disc = nil
    job.cur = nil
end

-- Sparks (or polishing dust) where the disc meets the panel, for as long as the page says you are on a patch.
local function fxWork(kind)
    local fx = cfg.Fx[kind]
    local d = job.disc
    if not fx or not d then return end
    job.fxLast = GetGameTimer()
    if job.fx and job.fxAt and #(job.fxAt - d.contact) < 0.03 then return end
    if job.fx then StopParticleFxLooped(job.fx, false) job.fx = nil end
    lib.requestNamedPtfxAsset(fx.asset, 5000)
    UseParticleFxAsset(fx.asset)
    local p = d.contact + d.n * 0.01
    local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, d.n.z))))
    local yaw = GetHeadingFromVector_2d(d.n.x, d.n.y)
    job.fx = StartParticleFxLoopedAtCoord(fx.name, p.x, p.y, p.z, pitch, 0.0, yaw, fx.scale, false, false, false, false)
    job.fxAt = d.contact
    if not job.fxWatch then
        job.fxWatch = true
        CreateThread(function()
            while job and job.fxWatch do
                if job.fx and GetGameTimer() - (job.fxLast or 0) > 160 then
                    StopParticleFxLooped(job.fx, false)
                    job.fx, job.fxAt = nil, nil
                end
                Wait(50)
            end
        end)
    end
end

local function fxStop()
    if not job then return end
    job.fxWatch = false
    if job.fx then StopParticleFxLooped(job.fx, false) job.fx, job.fxAt = nil, nil end
end

-- ---------------------------------------------------------------- the steps
local refresh

local function step(fn)
    if job.busy then return end
    job.busy = true
    refresh()
    local ok, err = pcall(fn)
    if not ok then print(('^1[bakery_barnfind] body step failed: %s^7'):format(err)) end
    if job then
        fxStop()
        toolStop()
        closeUpEnd()
        ClearPedTasks(cache.ped)
        job.busy = false
        refresh()
        if job.finished then
            local cb = job.onDone
            Body.stop()
            if cb then cb() end
        end
    end
end

-- How much of the face this tool has done, 0..1: each area counts up to WorkCellMs of work.
local function covered(f, kind)
    local need, sum = cfg.WorkCellMs[kind], 0.0
    for _, v in pairs(f.work[kind]) do sum = sum + math.min(need, v) end
    return sum / (need * math.max(1, f.ncells))
end

-- Work the face with the grinder or the polisher: hold the mouse on the paint and keep the tool moving. There are
-- no spots: the game keeps the score (the page only shows it). The area under the disc fills while it moves, with
-- sparks there, and the face is done once WorkDone of it is.
local function sweepGame(f, kind)
    toolStart(f, kind)
    local d = job.disc
    local done = cfg.WorkDone
    local last, sent = GetGameTimer(), -1.0
    d.tick = function()
        local now = GetGameTimer()
        local dt = now - last
        last = now
        if d.working and d.onCar and (d.moved or 0.0) > cfg.WorkMinMove then
            local o = GetOffsetFromEntityGivenWorldCoords(job.veh, d.contact.x, d.contact.y, d.contact.z)
            local k = cellOf(f.n, o)
            if f.cells[k] then f.work[kind][k] = (f.work[kind][k] or 0.0) + dt end
            fxWork(kind)
        end
        local p = covered(f, kind)
        if math.abs(p - sent) >= 0.005 or p >= done then
            sent = p
            Minigame.update({ progress = math.min(1.0, p / done), busy = d.working and d.onCar })
        end
        if p >= done and Minigame.isActive() then
            d.tick = nil
            Minigame.complete()
        end
    end
    return Minigame.run({
        kind = 'sweep',
        data = {
            mode = kind,
            progress = math.min(1.0, covered(f, kind) / done),
            title = ('Grind back the %s'):format(f.label),
            hint = 'Hold the mouse and sweep the grinder over the whole side until it is back to bare metal',
        },
        onEvent = function(name, value)
            if name == 'cursor' and type(value) == 'table' then
                job.cur = { x = tonumber(value.x) or 0.5, y = tonumber(value.y) or 0.5, held = value.held == true }
            end
        end,
    })
end

local ACTIONS = {}

-- A face is done: its dents come out. Straighten the lot, then knock the faces still to do back in.
local function finishFace(f)
    f.stage = 'done'
    local left = 0
    for _, x in ipairs(job.faces) do if x.stage ~= 'done' then left = left + 1 end end
    SetVehicleDeformationFixed(job.veh)
    Wait(0)
    dent(job.veh, job.faces)
    SetVehicleBodyHealth(job.veh, 1000.0 - left * (1000.0 - cfg.BodyHealth) / #job.faces)
    if left == 0 then
        Bridge.notify(T.bodyDone:format(Bridge.duration((GetGameTimer() - job.started) / 1000)), 'success')
        job.finished = true
    else
        Bridge.notify(T.bodyLeft:format(f.label:sub(1, 1):upper() .. f.label:sub(2), #job.faces - left, #job.faces), 'success')
    end
end

ACTIONS.grind = function(f)
    step(function()
        standAt(f)
        closeUp(f)
        if sweepGame(f, 'grind') == 'done' then finishFace(f) end
    end)
end

-- ---------------------------------------------------------------- prompts
local NEXT = { rough = 'grind' }

function refresh()
    if not job then return end
    for _, z in ipairs(job.zones) do z.remove() end
    job.zones = {}
    if job.busy then return end
    for _, f in ipairs(job.faces) do
        local action = NEXT[f.stage]
        if action then
            local c = rel(centre(f) + f.n * 0.45)
            job.zones[#job.zones + 1] = Bridge.addZone({
                name = ('bk_body_%s'):format(f.id),
                coords = c,
                heading = GetEntityHeading(job.veh),
                distance = 1.8,
                message = T['body_' .. action]:format(f.label),
                targetMessage = T['body_' .. action .. 'Target']:format(f.label),
                icon = 'fas fa-hammer',
                canInteract = function() return job ~= nil and not job.busy end,
                onSelect = function() CreateThread(function() ACTIONS[action](f) end) end,
            })
        end
    end
end

-- ---------------------------------------------------------------- start and stop
function Body.stop()
    if not job then return end
    Minigame.stop()
    fxStop()
    toolStop()
    closeUpEnd()
    for _, z in ipairs(job.zones) do z.remove() end
    ClearPedTasks(cache.ped)
    job = nil
end

-- Grind back every face of `veh`. opts.onDone is called once every face is ground (the job then packs up, leaving
-- the car). Returns how many faces there are to do.
function Body.begin(veh, opts)
    opts = opts or {}
    StopRestoreJobs()
    job = { veh = veh, onDone = opts.onDone, faces = {}, zones = {}, started = GetGameTimer() }
    FreezeEntityPosition(veh, true)

    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    local wheels = {}
    for _, b in ipairs({ 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr' }) do
        local bi = GetEntityBoneIndexByName(veh, b)
        if bi ~= -1 then
            local wp = GetWorldPositionOfEntityBone(veh, bi)
            local o = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
            wheels[#wheels + 1] = { y = o.y, z = o.z, r = 0.38 }
        end
    end
    -- lights and plates are not bodywork
    local avoid = {}
    for _, b in ipairs(cfg.AvoidBones) do
        local bi = GetEntityBoneIndexByName(veh, b)
        if bi ~= -1 then
            local wp = GetWorldPositionOfEntityBone(veh, bi)
            avoid[#avoid + 1] = GetOffsetFromEntityGivenWorldCoords(veh, wp.x, wp.y, wp.z)
        end
    end
    for _, d in ipairs(FACES) do
        local f = { id = d.id, n = d.n, label = d.label, stage = 'rough' }
        f.patches, f.normals, f.cells, f.ncells = sample(veh, d, mn, mx, wheels, avoid)
        f.work = { grind = {} }
        if #f.patches >= 2 then job.faces[#job.faces + 1] = f end
    end
    if #job.faces == 0 then
        Body.stop()
        return 0
    end

    dent(veh, job.faces)
    SetVehicleBodyHealth(veh, cfg.BodyHealth + 0.0)
    refresh()
    return #job.faces
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Body.stop() end
end)
