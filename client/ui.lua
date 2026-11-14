-- The NUI page: messages to it (Nui.send), and the restore minigames played on it (Minigame).
Nui = { open = false }

function Nui.send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Runs an interactive minigame on the NUI overlay (web/src/components/Minigame.tsx) while the game keeps
-- rendering behind it. The page gets the mouse; the game sends it where things are on screen (world points
-- projected every frame, so a moving camera or a car being jacked keeps the markers on the parts) and the page
-- reports back as the player works (pumps, nuts, the wheel's angle) and when it is finished.
Minigame = {}

local active = nil   -- { kind, p = promise, onEvent, points }

-- spec = {
--   kind = 'pump' | 'loosen' | 'tighten' | 'fit' | 'spin' | 'sweep' | 'skill',
--   data = { ... },                          -- sent to the page as is (labels, counts, tuning)
--   points = function() return { {x,y,z}, ... }, radiusWorld end,   -- optional: world points to project
--   onEvent = function(name, value) end,     -- optional: progress from the page
-- }
-- Blocks until the player finishes ('done') or backs out ('cancel').
function Minigame.run(spec)
    if active then return 'cancel' end
    local p = promise.new()
    active = { kind = spec.kind, p = p, onEvent = spec.onEvent, points = spec.points }

    Nui.send('minigame', { kind = spec.kind, data = spec.data or {} })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    if spec.points then
        CreateThread(function()
            local last = ''
            while active and active.p == p do
                local list, radius = spec.points()
                local out, rpx = {}, 0
                local sw, sh = GetActiveScreenResolution()
                for i, w in ipairs(list) do
                    local on, sx, sy = GetScreenCoordFromWorldCoord(w.x, w.y, w.z)
                    out[i] = { x = on and sx or -1, y = on and sy or -1 }
                end
                -- how big `radius` metres looks at the first point, in pixels, to size the markers
                if radius and list[1] then
                    local cam = GetFinalRenderedCamCoord()
                    local dist = #(list[1] - cam)
                    local fov = GetFinalRenderedCamFov()
                    rpx = (radius / (dist * math.tan(math.rad(fov) / 2.0))) * (sh / 2.0)
                end
                local key = ''
                for _, s in ipairs(out) do key = key .. ('%.4f,%.4f;'):format(s.x, s.y) end
                key = key .. ('%.1f'):format(rpx)
                if key ~= last then
                    last = key
                    Nui.send('minigame:points', { points = out, radius = rpx, w = sw, h = sh })
                end
                Wait(0)
            end
        end)
    end

    local result = Citizen.Await(p)
    return result
end

function Minigame.isActive() return active ~= nil end

local function finish(result)
    if not active then return end
    local p = active.p
    active = nil
    SetNuiFocus(false, false)
    Nui.send('minigame', nil)
    p:resolve(result)
end

-- Cancel from the game side when the active job ends.
function Minigame.stop() finish('cancel') end

-- Finish it from the game side, when the game is the one keeping score.
function Minigame.complete() finish('done') end

-- Send the page something new while it runs (progress the game keeps, say).
function Minigame.update(data)
    if active then Nui.send('minigame:update', data) end
end

RegisterNUICallback('mg:event', function(data, cb)
    cb(true)
    if active and active.onEvent and type(data) == 'table' then
        local ok, err = pcall(active.onEvent, data.name, data.value)
        if not ok then print(('^1[bakery_barnfind] minigame event failed: %s^7'):format(err)) end
    end
end)

RegisterNUICallback('mg:done', function(data, cb)
    cb(true)
    finish(type(data) == 'table' and data.result == 'done' and 'done' or 'cancel')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then SetNuiFocus(false, false) end
end)
