-- Small cutscene engine: a list of camera shots relative to an anchor entity, timed events, letterbox bars
-- and a skip key. The camera is driven by hand every frame (position, look-at and FOV eased per shot), which
-- keeps shots exact.
do
    Cinematic = {}

    local EASE = {
        linear = function(x) return x end,
        ['in'] = function(x) return x * x * x end,
        out = function(x) return 1.0 - (1.0 - x) ^ 3 end,
        inout = function(x) return x < 0.5 and 4.0 * x * x * x or 1.0 - (-2.0 * x + 2.0) ^ 3 / 2.0 end,
    }

    local function lerp(a, b, t) return a + (b - a) * t end

    -- World position of a point given relative to the anchor.
    local function rel(anchor, v)
        return GetOffsetFromEntityInWorldCoords(anchor, v.x + 0.0, v.y + 0.0, v.z + 0.0)
    end
    Cinematic.rel = rel

    -- Puts `cam` where `shot` is at fraction t (0..1).
    function Cinematic.frame(cam, anchor, shot, t)
        local e = (EASE[shot.ease or 'inout'] or EASE.inout)(math.min(math.max(t, 0.0), 1.0))
        local from, to = rel(anchor, shot.from), rel(anchor, shot.to or shot.from)
        local look, lookTo = rel(anchor, shot.look), rel(anchor, shot.lookTo or shot.look)
        local p, l = lerp(from, to, e), lerp(look, lookTo, e)
        SetCamCoord(cam, p.x, p.y, p.z)
        PointCamAtCoord(cam, l.x, l.y, l.z)
        SetCamFov(cam, lerp(shot.fov or 45.0, shot.fovTo or shot.fov or 45.0, e))
    end

    local function drawBars(height, alpha)
        if height <= 0 or alpha <= 0 then return end
        DrawRect(0.5, height / 2, 1.0, height, 0, 0, 0, alpha)
        DrawRect(0.5, 1.0 - height / 2, 1.0, height, 0, 0, 0, alpha)
    end

    -- The skip hint is drawn by the NUI page (web/src/components/SkipHint.tsx), in our own style.
    local function skipHint(show, label, keyLabel)
        SendNUIMessage({ action = 'skipHint', data = { show = show, label = label, key = keyLabel or 'Backspace' } })
    end

    --[[
        spec = {
            anchor = entity,                      -- shots are relative to this
            shots = { ...Tuning.Cutscene.Shots },
            events = { { at = ms, fn = function(ctx) end }, ... },   -- run once, in time order
            onFrame = function(ctx, now) end,     -- every frame (lights, particles)
            onSkip = function(ctx) end,           -- skipped: put the world in its end state
            onEnd = function(ctx, skipped) end,   -- always, after the camera is handed back
            letterbox = 0.11, skipKey = 194, skipKeyLabel = 'Backspace', skipLabel = 'Skip', blendOut = 1500,
        }
        Returns a promise resolved with `skipped` when the scene is over.
    ]]
    function Cinematic.play(spec)
        local p = promise.new()
        local ctx = { spec = spec, data = {} }
        local total, starts = 0, {}
        for i, shot in ipairs(spec.shots) do
            starts[i] = total
            total = total + shot.duration
        end
        table.sort(spec.events or {}, function(a, b) return a.at < b.at end)

        CreateThread(function()
            local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            ctx.cam = cam
            Cinematic.frame(cam, spec.anchor, spec.shots[1], 0.0)
            SetCamActive(cam, true)
            RenderScriptCams(true, false, 0, true, true)

            local start, nextEvent, shotIndex, skipped, hintShown = GetGameTimer(), 1, 0, false, false
            while true do
                local now = GetGameTimer() - start
                if now >= total then break end

                -- which shot are we in; a new shot is a hard cut (and gets its own camera shake)
                local i = shotIndex
                while i < #spec.shots and now >= starts[i + 1] do i = i + 1 end
                if i ~= shotIndex then
                    shotIndex = i
                    local shot = spec.shots[i]
                    StopCamShaking(cam, true)
                    if shot.shake and shot.shake > 0 then ShakeCam(cam, 'HAND_SHAKE', shot.shake) end
                    ctx.shot = shot.name
                end
                local shot = spec.shots[shotIndex]
                Cinematic.frame(cam, spec.anchor, shot, (now - starts[shotIndex]) / shot.duration)

                while spec.events and spec.events[nextEvent] and spec.events[nextEvent].at <= now do
                    local ev = spec.events[nextEvent]
                    nextEvent = nextEvent + 1
                    local ok, err = pcall(ev.fn, ctx)
                    if not ok then print(('^1[bakery_barnfind] cutscene event at %dms failed: %s^7'):format(ev.at, err)) end
                end
                if spec.onFrame then spec.onFrame(ctx, now) end

                -- bars slide in over the first 400 ms and stay
                drawBars((spec.letterbox or 0.11) * math.min(now / 400, 1.0), 255)
                HideHudAndRadarThisFrame()
                DisableAllControlActions(0)
                EnableControlAction(0, spec.skipKey or 194, true)
                if now > 800 and spec.skippable ~= false then
                    if not hintShown then
                        hintShown = true
                        skipHint(true, spec.skipLabel or 'Skip', spec.skipKeyLabel)
                    end
                    if IsDisabledControlJustPressed(0, spec.skipKey or 194) or IsControlJustPressed(0, spec.skipKey or 194) then
                        skipped = true
                        break
                    end
                end
                Wait(0)
            end

            if hintShown then skipHint(false) end
            if skipped then
                DoScreenFadeOut(250)
                while not IsScreenFadedOut() do Wait(0) end
                if spec.onSkip then pcall(spec.onSkip, ctx) end
            end

            -- hand the camera back, easing out (or cut while faded after a skip)
            StopCamShaking(cam, true)
            local blend = skipped and 0 or (spec.blendOut or 1500)
            RenderScriptCams(false, blend > 0, blend, true, true)
            local fadeStart = GetGameTimer()
            while GetGameTimer() - fadeStart < blend do
                local k = 1.0 - (GetGameTimer() - fadeStart) / blend
                drawBars((spec.letterbox or 0.11) * k, 255)
                Wait(0)
            end
            DestroyCam(cam, false)
            if skipped then DoScreenFadeIn(400) end
            if spec.onEnd then pcall(spec.onEnd, ctx, skipped) end
            p:resolve(skipped)
        end)
        return p
    end
end


-- The barn-find reveal: walk up, haul on the doors, they swing open from the dark, push in on the wreck.
-- Shots and marks live in Tuning.Cutscene; this file is the choreography.
BarnScene = {}

local cfg = Tuning.Cutscene
local playing = false

function BarnScene.isPlaying()
    return playing
end

local function shotStart(name)
    local t = 0
    for _, shot in ipairs(cfg.Shots) do
        if shot.name == name then return t end
        t = t + shot.duration
    end
    error('no cutscene shot named ' .. name)
end

-- Stands the ped on a mark (feet on the ground; SetEntityCoords takes the feet position for peds).
local function place(ped, shell, mark)
    local p = GetOffsetFromEntityInWorldCoords(shell, mark.x + 0.0, mark.y + 0.0, mark.z + 0.0)
    local found, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
    SetEntityCoords(ped, p.x, p.y, found and z or p.z, false, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(shell) + mark.w)
end

local function loadAssets()
    lib.requestAnimDict(cfg.PullAnim.dict)
    lib.requestAnimDict(cfg.AdmireAnim.dict)
    for _, fx in pairs(cfg.Particles) do lib.requestNamedPtfxAsset(fx.asset) end
end

local function dustBurst(shell, rel)
    local fx = cfg.Particles.dustBurst
    if not fx then return end
    local p = GetOffsetFromEntityInWorldCoords(shell, rel.x + 0.0, rel.y + 0.0, rel.z + 0.0)
    UseParticleFxAssetNextCall(fx.asset)
    StartParticleFxNonLoopedAtCoord(fx.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, fx.scale + 0.0, false, false, false)
end

local function drawLight(shell, strength)
    local l = cfg.Light
    if not l or strength <= 0 then return end
    local a = GetOffsetFromEntityInWorldCoords(shell, l.from.x, l.from.y, l.from.z)
    local b = GetOffsetFromEntityInWorldCoords(shell, l.to.x, l.to.y, l.to.z)
    local dir = norm(b - a)
    DrawSpotLightWithShadow(a.x, a.y, a.z, dir.x, dir.y, dir.z, l.color[1], l.color[2], l.color[3],
        l.distance + 0.0, l.brightness * strength, l.roundness + 0.0, l.radius + 0.0, l.falloff + 0.0, 0)
end

-- Plays the reveal for barn `id`, whose find is `{ car = model, paint = index }`.
-- Returns a promise resolved when control is back.
function BarnScene.play(id, find)
    local model = find.car
    local b = Barn.get(id)
    if not b or playing then return end
    playing = true
    local shell, ped = b.shell, cache.ped
    local tPull, tDark, tReveal = shotStart('pull'), shotStart('from_the_dark'), shotStart('reveal')
    local tRelease = tPull + math.floor(PullDoorCurve.release * 1000)
    local p = promise.new()

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end
    loadAssets()
    Barn.showFind(id, find)   -- parked behind the closed doors
    b.cutscene = true
    ClearPedTasksImmediately(ped)
    place(ped, shell, cfg.PlayerStart)
    SetPedCanRagdoll(ped, false)
    Wait(100)
    DoScreenFadeIn(600)

    local events = {
        { at = 0, fn = function()
            local m = GetOffsetFromEntityInWorldCoords(shell, PullDoorStart.x, PullDoorStart.y, 0.0)
            TaskGoStraightToCoord(ped, m.x, m.y, m.z, 1.0, 8000, GetEntityHeading(shell), 0.05)
        end },
        { at = tPull, fn = function()
            -- under the cut: stand exactly where the clip starts, then grab both handles and haul.
            -- The clip's mover walks the ped back; the doors follow its playback time (Doors.followClip).
            local s = GetOffsetFromEntityInWorldCoords(shell, PullDoorStart.x, PullDoorStart.y, PullDoorStart.z)
            local h = GetEntityHeading(shell) + PullDoorStart.w
            ClearPedTasksImmediately(ped)
            SetEntityCoordsNoOffset(ped, s.x, s.y, s.z, false, false, false)
            SetEntityHeading(ped, h)
            TaskPlayAnimAdvanced(ped, cfg.PullAnim.dict, cfg.PullAnim.clip, s.x, s.y, s.z, 0.0, 0.0, h,
                8.0, -4.0, -1, 0, 0.0, 0, 0)
            Barn.openWithClip(id, ped, cfg.PullAnim.dict, cfg.PullAnim.clip)
        end },
        { at = tRelease + 350, fn = function() dustBurst(shell, vec3(-1.2, -0.9, 0.15)) end },
        { at = tRelease + 650, fn = function() dustBurst(shell, vec3(1.2, -0.9, 0.15)) end },
        { at = tDark + 200, fn = function() dustBurst(shell, vec3(0.0, 0.6, 3.6)) end },
        { at = tReveal, fn = function()
            Barn.setAmbience(id, true)
            TaskPlayAnim(ped, cfg.AdmireAnim.dict, cfg.AdmireAnim.clip, 4.0, -4.0, -1, 1, 0.0, false, false, false)
        end },
    }

    local light = 0.0
    Cinematic.play({
        anchor = shell,
        shots = cfg.Shots,
        events = events,
        letterbox = cfg.Letterbox,
        skippable = cfg.Skippable,
        skipKey = cfg.SkipKey,
        skipKeyLabel = cfg.SkipKeyLabel,
        skipLabel = Tuning.Text.skip,
        blendOut = cfg.BlendOut,
        onFrame = function(_, now)
            -- daylight floods in as the doors open, and stays on the find
            if now >= tPull + 1200 then light = math.min(1.0, (now - tPull - 1200) / 2500) end
            drawLight(shell, light)
        end,
        onSkip = function()
            StopAnimTask(ped, cfg.PullAnim.dict, cfg.PullAnim.clip, 8.0)
            Wait(50)
            Barn.setDoors(id, 1.0)
            Barn.setAmbience(id, true)
            ClearPedTasksImmediately(ped)
            place(ped, shell, cfg.WatchMark)
        end,
        onEnd = function()
            SetPedCanRagdoll(ped, true)
            StopAnimTask(ped, cfg.AdmireAnim.dict, cfg.AdmireAnim.clip, 2.0)
            b.cutscene = nil
            playing = false
            Barn.refreshInteraction(id)
            local name = GetLabelText(GetDisplayNameFromVehicleModel(joaat(model)))
            Bridge.notify(('You found a %s. It has seen better days.'):format(name ~= 'NULL' and name or model), 'success')
            TriggerEvent('bakery_barnfind:client:found', id, model)
            p:resolve(true)
        end,
    })
    return p
end
