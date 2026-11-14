-- Placement editor: the same free cam as bakery_racing's track editor, with a see-through copy of the real barn.
--
--   Aiming     (default) the mouse looks, W A S D fly, Space up, Ctrl down, Shift fast, Ctrl + wheel changes the speed.
--              The barn follows the crosshair across the ground.
--   Left Alt   gives the menu's page the mouse (NUI focus, like racing's editor) and holds the camera still, so you
--              can position the barn with the gizmo: drag an arrow to slide along one axis (red X, green Y, blue Z),
--              the square to slide on the ground, the ring to turn it. Alt again goes back to aiming.
--   Enter / Esc   save / cancel, in either mode.
--
-- While you slide on X / Y the barn follows the terrain (the highest ground under its footprint, like when it
-- spawns) until you drag the blue arrow. Everything is local: the menu saves the result.
Gizmo = { active = false }

local sin, cos, rad, deg, abs, sqrt, floor, max, min = math.sin, math.cos, math.rad, math.deg, math.abs, math.sqrt, math.floor, math.max, math.min

local AXES = {
    { name = 'x', dir = vector3(1.0, 0.0, 0.0), color = { 245, 85, 90 } },
    { name = 'y', dir = vector3(0.0, 1.0, 0.0), color = { 110, 230, 140 } },
    { name = 'z', dir = vector3(0.0, 0.0, 1.0), color = { 85, 160, 255 } },
}
local RING_COLOR = { 255, 214, 120 }
local PLANE_COLOR = { 255, 255, 255 }
local HOVER_RADIUS = 0.02           -- how close (screen height fractions) the crosshair must be to a handle
local FOOTPRINT = { -4.5, 4.5, 0.0, 12.0 }   -- the barn's outline, relative to its origin: x0, x1, y0, y1

local function round(n, places)
    local m = 10 ^ (places or 0)
    return floor(n * m + 0.5) / m
end

-- ------------------------------------------------------------ camera, rays and picking
-- GTA camera rotation (pitch, roll, yaw in degrees) to its forward / right / up vectors.
local function basis(rot)
    local p, y = rad(rot.x), rad(rot.z)
    local forward = vector3(-sin(y) * cos(p), cos(y) * cos(p), sin(p))
    local right = vector3(cos(y), sin(y), 0.0)
    return forward, right, cross(right, forward)
end

-- The world ray under a point of the screen (mx, my in 0..1).
local function mouseRay(cam, mx, my)
    local forward, right, up = basis(GetCamRot(cam, 2))
    local tanV = math.tan(rad(GetCamFov(cam)) / 2.0)
    local tanH = tanV * GetAspectRatio(false)
    local dir = forward + right * ((mx - 0.5) * 2.0 * tanH) + up * ((0.5 - my) * 2.0 * tanV)
    return GetCamCoord(cam), norm(dir)
end

-- Distance along the line (origin + t * dir) to its closest point to a ray. nil when they are parallel.
local function rayLineParam(ro, rd, origin, dir)
    local b = dot(rd, dir)
    local denom = 1.0 - b * b
    if abs(denom) < 1e-5 then return nil end
    local w = ro - origin
    return (dot(dir, w) - b * dot(rd, w)) / denom
end

-- Where the ray meets the horizontal plane at height z. nil when it points away or runs parallel.
local function rayPlane(ro, rd, z)
    if abs(rd.z) < 1e-4 then return nil end
    local t = (z - ro.z) / rd.z
    if t <= 0.0 then return nil end
    return ro + rd * t
end

local function toScreen(p)
    local on, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    if on then return { x = sx, y = sy } end
end

local function toWorld(origin, heading, lx, ly, lz)
    local r = rad(heading)
    return vector3(origin.x + lx * cos(r) - ly * sin(r), origin.y + lx * sin(r) + ly * cos(r), origin.z + lz)
end

-- Distance on screen (height-relative, so a circle stays a circle) from the cursor to a segment.
local function segmentDistance(mx, my, a, b, aspect)
    local ax, ay, bx, by = a.x * aspect, a.y, b.x * aspect, b.y
    local px, py = mx * aspect, my
    local dx, dy = bx - ax, by - ay
    local len = dx * dx + dy * dy
    local t = len > 1e-9 and max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / len)) or 0.0
    local cx, cy = ax + dx * t, ay + dy * t
    return sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

local function insideQuad(mx, my, quad)
    local inside = false
    local j = 4
    for i = 1, 4 do
        local a, b = quad[i], quad[j]
        if ((a.y > my) ~= (b.y > my)) and (mx < (b.x - a.x) * (my - a.y) / (b.y - a.y) + a.x) then inside = not inside end
        j = i
    end
    return inside
end

-- ------------------------------------------------------------ drawing
local function tri(a, b, c, col, alpha)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, col[1], col[2], col[3], alpha)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, b.x, b.y, b.z, col[1], col[2], col[3], alpha)   -- and the other side
end

-- A flat strip from a to b that always faces the camera, so lines have a real thickness.
local function ribbon(a, b, width, col, alpha, camPos)
    local side = cross(b - a, camPos - (a + b) * 0.5)
    if #side < 1e-6 then return end
    side = norm(side) * (width * 0.5)
    tri(a - side, a + side, b + side, col, alpha)
    tri(a - side, b + side, b - side, col, alpha)
end

local function arrow(origin, tip, width, col, alpha, camPos)
    ribbon(origin, tip, width, col, alpha, camPos)
    local dir = norm(tip - origin)
    local side = cross(dir, camPos - tip)
    if #side < 1e-6 then return end
    side = norm(side)
    local head = width * 5.0
    local base = tip - dir * head * 1.6
    tri(tip + dir * head * 0.6, base + side * head * 0.7, base - side * head * 0.7, col, alpha)
end

local function line3(a, b, col, alpha)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, col[1], col[2], col[3], alpha)
end

local function text3d(p, line, colour)
    local on, sx, sy = World3dToScreen2d(p.x, p.y, p.z)
    if not on then return end
    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(colour[1], colour[2], colour[3], 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(line)
    EndTextCommandDisplayText(sx, sy)
end

-- ------------------------------------------------------------ ground
-- Highest ground under the footprint (where the barn would sit) and how much the ground varies under it.
local function groundInfo(x, y, z, heading)
    local best, low
    local o = vector3(x, y, z)
    for _, p in ipairs({ { 0, -1.5 }, { -4.4, 0.1 }, { 4.4, 0.1 }, { -4.4, 11.9 }, { 4.4, 11.9 }, { 0, 6 }, { -2.5, 3 }, { 2.5, 9 } }) do
        local w = toWorld(o, heading, p[1] + 0.0, p[2] + 0.0, 0.0)
        local found, gz = GetGroundZFor_3dCoord(w.x, w.y, z + 10.0, false)
        if found then
            best = best and max(best, gz) or gz
            low = low and min(low, gz) or gz
        end
    end
    if not best then return nil, 0.0 end
    return best, best - low
end

-- ------------------------------------------------------------ the editor
-- opts: { start = { x, y, z, w } (omit for a new barn in front of you), label }
function Gizmo.place(opts)
    if Gizmo.active then return { cancelled = true } end
    Gizmo.active = true

    local ped = cache.ped
    local forwardOfPed = GetEntityForwardVector(ped)
    local pos, heading
    local start = opts.start
    if start and ((tonumber(start.x) or 0) ~= 0 or (tonumber(start.y) or 0) ~= 0) then
        pos = vector3(opts.start.x + 0.0, opts.start.y + 0.0, opts.start.z + 0.0)
        heading = (tonumber(opts.start.w) or 0.0) % 360.0
    else
        local ahead = GetEntityCoords(ped) + forwardOfPed * 7.0
        heading = GetEntityHeading(ped)
        local gz = groundInfo(ahead.x, ahead.y, ahead.z, heading)
        pos = vector3(ahead.x, ahead.y, gz or ahead.z - 1.0)
    end

    -- the barn, as a see-through copy: shell and both doors, shut
    local ghosts = {}
    local function ghost(model)
        local hash = joaat(model)
        if not pcall(lib.requestModel, hash, 10000) then return end
        local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if obj == 0 then return end
        ghosts[#ghosts + 1] = obj
        SetEntityAlpha(obj, 175, false)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
        return obj
    end
    local shell = ghost(Tuning.Barn.Shell)
    local doors = {}
    for key, d in pairs(Tuning.Barn.Doors) do doors[key] = { entity = ghost(d.model), hinge = d.hinge } end
    if not shell or not doors.left.entity or not doors.right.entity then
        for _, obj in ipairs(ghosts) do DeleteEntity(obj) end
        Gizmo.active = false
        return { cancelled = true }
    end

    local function placeGhosts()
        SetEntityCoordsNoOffset(shell, pos.x, pos.y, pos.z, false, false, false)
        SetEntityRotation(shell, 0.0, 0.0, heading, 2, false)
        for _, d in pairs(doors) do
            local h = toWorld(pos, heading, d.hinge.x + 0.0, d.hinge.y + 0.0, d.hinge.z + 0.0)
            SetEntityCoordsNoOffset(d.entity, h.x, h.y, h.z, false, false, false)
            SetEntityRotation(d.entity, 0.0, 0.0, heading, 2, false)
        end
    end

    -- camera: in front of the doors, high, looking at the barn. The rotation is set by hand and never with
    -- PointCamAtCoord: that keeps the camera locked onto its point, so the mouse could not turn it away.
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local doorSide = toWorld(pos, heading, 0.0, -16.0, 9.0)
    local middle = toWorld(pos, heading, 0.0, 6.0, 1.5)
    local look = norm(middle - doorSide)
    local camRot = vector3(deg(math.asin(look.z)), 0.0, deg(math.atan(-look.x, look.y)) % 360.0)
    SetCamCoord(cam, doorSide.x, doorSide.y, doorSide.z)
    SetCamRot(cam, camRot.x, 0.0, camRot.z, 2)
    SetCamFov(cam, 70.0)
    RenderScriptCams(true, true, 400, true, true)

    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)

    local autoGround = true
    local focus = false                   -- Left Alt: the page has the mouse and the gizmo is live
    local drag, hover, lastDown = nil, nil, false
    local speedMult, result = 1.0, nil
    local hudKey, hudAt = '', 0
    local slope = 0.0
    local startPos, startHeading = pos, heading
    local aim = { handle = nil, target = nil, probeEnd = nil }
    Gizmo.ptr = { mx = 0.5, my = 0.5, down = false }
    Gizmo.altRequested, Gizmo.pendingKey = false, nil

    local function setGround()
        local gz = groundInfo(pos.x, pos.y, pos.z, heading)
        if gz then pos = vector3(pos.x, pos.y, gz) end
    end

    local function setFocus(on)
        focus = on
        drag, hover, lastDown = nil, nil, false
        Gizmo.ptr = { mx = 0.5, my = 0.5, down = false }
        SetNuiFocus(on, on)
        SetNuiFocusKeepInput(false)
        hudKey = ''
    end

    -- The point under the crosshair. One async probe is in flight at a time and the last answer is reused, so no
    -- frame waits on a 500 m raycast (the same approach as racing's editor).
    local function aimTarget(camPos)
        if aim.handle then
            local status, hit, coords = GetShapeTestResult(aim.handle)
            if status ~= 1 then
                if status == 2 and hit == 1 then
                    aim.target = coords
                elseif status == 2 and aim.probeEnd then
                    local e = aim.probeEnd
                    local found, gz = GetGroundZFor_3dCoord(e.x, e.y, e.z + 50.0, false)
                    aim.target = vector3(e.x, e.y, found and gz or e.z)
                end
                aim.handle = nil
            end
        end
        if not aim.handle then
            local forward = basis(camRot)
            aim.probeEnd = camPos + forward * 500.0
            aim.handle = StartShapeTestLosProbe(camPos.x, camPos.y, camPos.z, aim.probeEnd.x, aim.probeEnd.y, aim.probeEnd.z, 1 | 16, ped, 7)
        end
        return aim.target
    end

    local ok, err = xpcall(function()
        placeGhosts()
        while not result do
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true)   -- push to talk
            DisableFrontendThisFrame()
            HideHudAndRadarThisFrame()
            DisablePlayerFiring(PlayerId(), true)

            -- ---- camera (bakery_racing's free cam: client/editor.lua updateCamera). It holds still while the
            -- page has the mouse.
            local camPos = GetCamCoord(cam)
            if not focus then
                local camSpeed = (IsDisabledControlPressed(0, 21) and 0.8 or 0.15) * speedMult
                local hd = rad(camRot.z)
                local fx, fy = -sin(hd), cos(hd)
                local dx, dy, dz = 0.0, 0.0, 0.0
                if IsDisabledControlPressed(0, 32) then dx, dy = dx + fx, dy + fy end
                if IsDisabledControlPressed(0, 33) then dx, dy = dx - fx, dy - fy end
                if IsDisabledControlPressed(0, 34) then dx, dy = dx - fy, dy + fx end
                if IsDisabledControlPressed(0, 35) then dx, dy = dx + fy, dy - fx end
                if IsDisabledControlPressed(0, 22) then dz = dz + 1.0 end
                if IsDisabledControlPressed(0, 36) or IsDisabledControlPressed(0, 20) then dz = dz - 1.0 end
                camPos = camPos + vector3(dx * camSpeed, dy * camSpeed, dz * camSpeed)
                camRot = vector3(
                    max(-89.0, min(89.0, camRot.x - GetDisabledControlNormal(0, 2) * 8.0)), 0.0,
                    (camRot.z - GetDisabledControlNormal(0, 1) * 8.0) % 360.0)
                local wheel = IsDisabledControlJustPressed(0, 15) and 1 or IsDisabledControlJustPressed(0, 14) and -1 or 0
                if wheel ~= 0 and IsDisabledControlPressed(0, 36) then speedMult = max(0.25, min(4.0, speedMult + wheel * 0.25)) end
            end
            SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
            SetCamRot(cam, camRot.x, 0.0, camRot.z, 2)
            SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)

            -- ---- Left Alt: aiming <-> gizmo. With the page focused the game no longer sees the key, so the page reports it.
            local altFromPage = Gizmo.altRequested
            Gizmo.altRequested = false
            if IsDisabledControlJustPressed(0, 19) or altFromPage then setFocus(not focus) end

            -- ---- aiming: the barn rides on the crosshair
            if not focus then
                local target = aimTarget(camPos)
                if target then
                    pos = vector3(target.x, target.y, target.z)
                    autoGround = true
                    setGround()
                end
            end

            -- The page reports cursor input while focused.
            local interactive = focus
            local input = (focus and Gizmo.ptr) or { mx = 0.5, my = 0.5, down = false }
            local pressed = input.down and not lastDown
            lastDown = input.down
            local aspect = GetAspectRatio(false)
            local ro, rd = mouseRay(cam, input.mx, input.my)

            -- ---- handles
            local s = max(1.6, min(40.0, #(camPos - pos) * 0.13))
            local width = s * 0.028
            local tips = {}
            for i, a in ipairs(AXES) do tips[i] = pos + a.dir * s end
            local quad = {
                pos + vector3(s * 0.30, s * 0.30, 0.0), pos + vector3(s * 0.55, s * 0.30, 0.0),
                pos + vector3(s * 0.55, s * 0.55, 0.0), pos + vector3(s * 0.30, s * 0.55, 0.0),
            }
            local ringR = s * 1.15
            local ring = {}
            for i = 0, 64 do
                local a = i * math.pi * 2.0 / 64.0
                ring[i + 1] = pos + vector3(cos(a) * ringR, sin(a) * ringR, 0.05)
            end

            if interactive and not drag then
                hover = nil
                local best = HOVER_RADIUS
                local origin2d = toScreen(pos)
                for i = 1, 3 do
                    local tip2d = toScreen(tips[i])
                    if origin2d and tip2d then
                        local d = segmentDistance(input.mx, input.my, origin2d, tip2d, aspect)
                        if d < best then best, hover = d, AXES[i].name end
                    end
                end
                local q2d, all = {}, true
                for i = 1, 4 do q2d[i] = toScreen(quad[i]) all = all and q2d[i] ~= nil end
                if all and insideQuad(input.mx, input.my, q2d) and best > 0.004 then hover, best = 'plane', 0.004 end
                local prev = toScreen(ring[1])
                for i = 2, 65 do
                    local cur = toScreen(ring[i])
                    if prev and cur then
                        local d = segmentDistance(input.mx, input.my, prev, cur, aspect)
                        if d < best then best, hover = d, 'ring' end
                    end
                    prev = cur
                end
            elseif not interactive then
                hover = nil
            end

            if pressed and hover then
                local start = { kind = hover, origin = pos, heading = heading }
                if hover == 'ring' then
                    local hit = rayPlane(ro, rd, pos.z)
                    if hit then start.angle = math.atan(hit.y - pos.y, hit.x - pos.x) else start = nil end
                elseif hover == 'plane' then
                    local hit = rayPlane(ro, rd, pos.z)
                    if hit then start.hit = hit else start = nil end
                else
                    for _, a in ipairs(AXES) do
                        if a.name == hover then
                            start.axis = a.dir
                            start.t = rayLineParam(ro, rd, pos, a.dir)
                        end
                    end
                    if not start.t then start = nil end
                end
                drag = start
            end

            if drag then
                if not input.down then
                    drag = nil
                else
                    if drag.kind == 'ring' then
                        local hit = rayPlane(ro, rd, drag.origin.z)
                        if hit then
                            local turned = deg(math.atan(hit.y - drag.origin.y, hit.x - drag.origin.x) - drag.angle)
                            heading = (drag.heading + turned) % 360.0
                        end
                    elseif drag.kind == 'plane' then
                        local hit = rayPlane(ro, rd, drag.origin.z)
                        if hit then
                            local p = drag.origin + (hit - drag.hit)
                            pos = vector3(p.x, p.y, drag.origin.z)
                        end
                    else
                        local t = rayLineParam(ro, rd, drag.origin, drag.axis)
                        if t then
                            pos = drag.origin + drag.axis * (t - drag.t)
                            if drag.kind == 'z' then autoGround = false end
                        end
                    end
                    if autoGround and drag.kind ~= 'ring' then setGround() end
                end
            end

            -- ---- Enter saves, Esc cancels (from the page's keys while it has focus)
            local key = Gizmo.pendingKey
            Gizmo.pendingKey = nil
            if IsDisabledControlJustPressed(0, 191) or key == 'enter' then
                result = { x = round(pos.x, 2), y = round(pos.y, 2), z = round(pos.z, 2), w = round(heading, 1) }
            elseif IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 322) or key == 'escape' then
                result = { cancelled = true }
            end

            -- ---- draw
            placeGhosts()
            local lit = drag and drag.kind or hover
            local function a(name) return lit == name and 255 or 175 end
            local outline = { toWorld(pos, heading, FOOTPRINT[1], FOOTPRINT[3], 0.06), toWorld(pos, heading, FOOTPRINT[2], FOOTPRINT[3], 0.06),
                toWorld(pos, heading, FOOTPRINT[2], FOOTPRINT[4], 0.06), toWorld(pos, heading, FOOTPRINT[1], FOOTPRINT[4], 0.06) }
            for i = 1, 4 do line3(outline[i], outline[i % 4 + 1], { 255, 255, 255 }, 150) end
            local door = toWorld(pos, heading, 0.0, -0.4, 0.06)
            arrow(door, toWorld(pos, heading, 0.0, -3.6, 0.06), 0.09, { 255, 255, 255 }, 190, camPos)
            text3d(toWorld(pos, heading, 0.0, -4.1, 0.6), 'DOORS', { 255, 255, 255 })

            tri(quad[1], quad[2], quad[3], PLANE_COLOR, lit == 'plane' and 120 or 55)
            tri(quad[1], quad[3], quad[4], PLANE_COLOR, lit == 'plane' and 120 or 55)
            for i = 1, 64 do ribbon(ring[i], ring[i + 1], width * (lit == 'ring' and 1.5 or 1.0), RING_COLOR, a('ring'), camPos) end
            for i, ax in ipairs(AXES) do
                arrow(pos, tips[i], width * (lit == ax.name and 1.5 or 1.0), ax.color, a(ax.name), camPos)
                text3d(pos + ax.dir * (s * 1.12), ax.name:upper(), ax.color)
            end
            DrawMarker(28, pos.x, pos.y, pos.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 0.18, 255, 255, 255, 220, false, false, 2, false, nil, nil, false)

            -- the crosshair, while aiming (the page's cursor takes over when focused)
            if not focus then
                DrawRect(0.5, 0.5, 0.004 / aspect, 0.004, 255, 255, 255, 235)
                DrawRect(0.5, 0.5, 0.016 / aspect, 0.0012, 255, 255, 255, 120)
                DrawRect(0.5, 0.5, 0.0012 / aspect, 0.016, 255, 255, 255, 120)
            end

            -- ---- the overlay in the menu's page (throttled; the ground check is the slow part)
            if GetGameTimer() - hudAt > 120 then
                hudAt = GetGameTimer()
                local _, s2 = groundInfo(pos.x, pos.y, pos.z, heading)
                slope = s2
                local keyStr = ('%.2f|%.2f|%.2f|%.1f|%s|%s|%s|%s|%.2f|%.2f'):format(pos.x, pos.y, pos.z, heading, tostring(lit), tostring(autoGround), tostring(drag ~= nil), tostring(focus), slope, speedMult)
                if keyStr ~= hudKey then
                    hudKey = keyStr
                    Nui.send('place', {
                        active = true, focus = focus, label = opts.label, x = round(pos.x, 2), y = round(pos.y, 2), z = round(pos.z, 2), w = round(heading, 1),
                        autoGround = autoGround, slope = round(slope, 2), hover = lit, dragging = drag ~= nil, speed = speedMult,
                        moved = #(pos - startPos) > 0.01 or abs(heading - startHeading) > 0.05,
                    })
                end
            end
        end
    end, debug.traceback)

    for _, obj in ipairs(ghosts) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    ClearFocus()
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityCollision(ped, true, true)
    SetNuiFocus(false, false)
    Nui.send('place', { active = false })
    Gizmo.active = false
    SetPauseMenuActive(false)
    if not ok then error(err) end
    return result
end

-- While the page has the mouse (Left Alt), it reports the cursor, and the keys the game can no longer see.
RegisterNUICallback('gizmo:pointer', function(data, cb)
    if Gizmo.active and type(data) == 'table' and type(data.x) == 'number' and type(data.y) == 'number'
        and data.x >= 0 and data.x <= 1 and data.y >= 0 and data.y <= 1 then
        Gizmo.ptr = { mx = data.x, my = data.y, down = data.down == true }
    end
    cb(1)
end)

RegisterNUICallback('gizmo:key', function(data, cb)
    if Gizmo.active and type(data) == 'table' then
        if data.key == 'alt' then Gizmo.altRequested = true
        elseif data.key == 'enter' or data.key == 'escape' then Gizmo.pendingKey = data.key end
    end
    cb(1)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Gizmo.active then return end
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityCollision(ped, true, true)
end)
