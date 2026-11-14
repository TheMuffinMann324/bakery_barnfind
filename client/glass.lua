-- Restoring, by hand: replacing the glass. Every smashed window gets its own prompt (third eye / interaction,
-- whatever kq_link is set to). Picking one walks you up to it and plays the work through: clear out the broken
-- glass, then fit the new pane. One window at a time, any order.
--
-- No per-car shapes: the prompt sits on the window's bone, so it follows whatever car it is.
--
-- Glass.begin runs it on a find in the barn (client/finds.lua runs the restore steps).
Glass = {}

local cfg = Tuning.Restore.Glass
local T = Tuning.Restore.Text

-- window index (SmashVehicleWindow / FixVehicleWindow), bone, name in the prompts
local WINDOWS = {
    { index = 6, bone = 'windscreen',   label = 'windscreen' },
    { index = 7, bone = 'windscreen_r', label = 'rear screen' },
    { index = 0, bone = 'window_lf',    label = 'front left window' },
    { index = 1, bone = 'window_rf',    label = 'front right window' },
    { index = 2, bone = 'window_lr',    label = 'rear left window' },
    { index = 3, bone = 'window_rr',    label = 'rear right window' },
}

local job = nil

local function boneAt(w) return GetWorldPositionOfEntityBone(job.veh, GetEntityBoneIndexByName(job.veh, w.bone)) end

-- Walk up to the window from outside the car and face it.
local function goTo(w)
    local b = boneAt(w)
    local o = GetOffsetFromEntityGivenWorldCoords(job.veh, b.x, b.y, b.z)
    local mn, mx = GetModelDimensions(GetEntityModel(job.veh))
    local x
    if math.abs(o.x) > 0.3 then
        x = o.x < 0 and mn.x - 0.45 or mx.x + 0.45   -- a side window: stand beside it
    else
        -- a screen: stand at its corner, on the side you are already on
        local pc = GetEntityCoords(cache.ped)
        local me = GetOffsetFromEntityGivenWorldCoords(job.veh, pc.x, pc.y, pc.z)
        x = me.x < 0 and mn.x - 0.45 or mx.x + 0.45
    end
    local spot = GetOffsetFromEntityInWorldCoords(job.veh, x, o.y, 0.0)
    local ok, gz = GetGroundZFor_3dCoord(spot.x, spot.y, b.z + 1.0, false)
    spot = vec3(spot.x, spot.y, ok and gz or spot.z)
    local h = GetHeadingFromVector_2d(b.x - spot.x, b.y - spot.y)
    local ped = cache.ped
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 4000, h, 0.05)
    local t = GetGameTimer()
    while GetGameTimer() - t < 4000 and #(GetEntityCoords(ped).xy - spot.xy) > 0.3 do Wait(50) end
    ClearPedTasks(ped)
    SetEntityHeading(ped, h)
end

local function work(label, ms)
    return lib.progressBar({
        duration = ms,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = cfg.Anim.dict, clip = cfg.Anim.clip, flag = 1 },
    })
end

local refresh

local function replace(w)
    if not job or job.busy or w.done then return end
    job.busy = true
    refresh()
    local ok, err = pcall(function()
        goTo(w)
        -- (the broken glass stays on the car until the new pane goes in: once RemoveVehicleWindow has taken a
        -- window out, FixVehicleWindow cannot put it back)
        if not work(T.glassClearing:format(w.label), cfg.ClearMs) then return end
        if not work(T.glassFitting:format(w.label), cfg.FitMs) then return end
        FixVehicleWindow(job.veh, w.index)
        w.done = true
        local left = 0
        for _, x in ipairs(job.windows) do if not x.done then left = left + 1 end end
        if left == 0 then
            Bridge.notify(T.glassDone:format(Bridge.duration((GetGameTimer() - job.started) / 1000)), 'success')
            job.finished = true
        else
            Bridge.notify(T.glassLeft:format(left), 'info')
        end
    end)
    if not ok then print(('^1[bakery_barnfind] glass step failed: %s^7'):format(err)) end
    if job then
        ClearPedTasks(cache.ped)
        job.busy = false
        refresh()
        if job.finished then
            local cb = job.onDone
            Glass.stop()
            if cb then cb() end
        end
    end
end

function refresh()
    if not job then return end
    for _, z in ipairs(job.zones) do z.remove() end
    job.zones = {}
    if job.busy then return end
    for _, w in ipairs(job.windows) do
        if not w.done then
            job.zones[#job.zones + 1] = Bridge.addZone({
                name = ('bk_glass_%d'):format(w.index),
                coords = boneAt(w),
                heading = GetEntityHeading(job.veh),
                distance = 2.0,
                message = T.glassReplace:format(w.label),
                targetMessage = T.glassReplaceTarget:format(w.label),
                icon = 'fas fa-car-side',
                canInteract = function() return job ~= nil and not job.busy end,
                onSelect = function() CreateThread(function() replace(w) end) end,
            })
        end
    end
end

-- ---------------------------------------------------------------- start and stop
function Glass.stop()
    if not job then return end
    if lib.progressActive() then lib.cancelProgress() end
    for _, z in ipairs(job.zones) do z.remove() end
    ClearPedTasks(cache.ped)
    job = nil
end

-- Replace the broken glass on `veh`. opts.onDone is called once all the glass is in (the job then packs up, leaving
-- the car). A car with no broken glass is done at once. Returns how many windows there are to do.
function Glass.begin(veh, opts)
    opts = opts or {}
    StopRestoreJobs()
    job = { veh = veh, onDone = opts.onDone, windows = {}, zones = {}, started = GetGameTimer() }
    for _, d in ipairs(WINDOWS) do
        if GetEntityBoneIndexByName(veh, d.bone) ~= -1 then
            if not IsVehicleWindowIntact(veh, d.index) then
                job.windows[#job.windows + 1] = { index = d.index, bone = d.bone, label = d.label }
            end
        end
    end
    local n = #job.windows
    if n == 0 then
        local cb = job.onDone
        Glass.stop()
        if cb then cb() end
        return 0
    end
    refresh()
    return n
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Glass.stop() end
end)
