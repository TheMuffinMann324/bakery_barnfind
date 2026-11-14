-- The admin menu: opening it, the NUI <-> server proxy, and the few things it needs from the game world
-- (your position, teleport, vehicle names, the placement editor). The server checks access on every call.
local opening, registered = false, false

-- Server callbacks the NUI may call through the proxy.
local PROXY = {
    ['admin:save'] = true, ['admin:reset'] = true,
    ['admin:live'] = true, ['admin:resetBarn'] = true,
}

local function openMenu()
    if Nui.open or opening then return end
    opening = true
    local ok, res = pcall(lib.callback.await, 'bakery_barnfind:admin:open', false)
    opening = false
    if not ok or type(res) ~= 'table' or not res.ok then
        Bridge.notify((ok and type(res) == 'table' and res.error) or 'The menu failed to load.', 'error')
        return
    end
    Nui.open = true
    Nui.send('open', res)
    SetNuiFocus(true, true)
end

local function closeMenu()
    if not Nui.open then return end
    Nui.open = false
    SetNuiFocus(false, false)
    Nui.send('close')
end

function RegisterBarnAdminCommand(menu)
    if registered or not menu then return end
    registered = true
    RegisterCommand(menu.command, function()
        if Gizmo.active or Minigame.isActive() then return end
        if Nui.open then closeMenu() else openMenu() end
    end, false)
    if menu.keybind and menu.keybind ~= '' then
        RegisterKeyMapping(menu.command, 'Open the Barn Find admin menu', 'keyboard', menu.keybind)
    end
end

exports('openAdmin', openMenu)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb(true)
end)

RegisterNUICallback('call', function(data, cb)
    local name = type(data) == 'table' and data.name
    if not Nui.open or type(name) ~= 'string' or not PROXY[name] then return cb(false) end
    local ok, result = pcall(lib.callback.await, 'bakery_barnfind:' .. name, false, data.arg)
    cb(ok and result or { ok = false, error = 'No response from the server.' })
end)

-- The street (else the district) you stand in, to name a new barn after.
RegisterNUICallback('admin:area', function(_, cb)
    if not Nui.open then return cb(false) end
    local c = GetEntityCoords(cache.ped)
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(c.x, c.y, c.z)))
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    cb({ label = street ~= '' and street or (zone ~= 'NULL' and zone or '') })
end)

local function coordinate(value, min, max)
    return type(value) == 'number' and value >= min and value <= max
end

RegisterNUICallback('admin:teleport', function(data, cb)
    if not Nui.open or type(data) ~= 'table' then return cb({ ok = false }) end
    local x, y, z = data.x, data.y, data.z
    if not coordinate(x, -10000, 10000) or not coordinate(y, -10000, 10000) or not coordinate(z, -1000, 2000) then
        return cb({ ok = false })
    end
    local ped = cache.ped
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(ped, x, y, z + 1.0, false, false, false, false)
    if coordinate(data.w, 0, 360) then SetEntityHeading(ped, data.w + 0.0) end
    cb({ ok = true })
end)

local CLASSES = {
    [0] = 'Compacts', 'Sedans', 'SUVs', 'Coupes', 'Muscle', 'Sports Classics', 'Sports', 'Super', 'Motorcycles',
    'Off-road', 'Industrial', 'Utility', 'Vans', 'Cycles', 'Boats', 'Helicopters', 'Planes', 'Service', 'Emergency',
    'Military', 'Commercial', 'Trains', 'Open Wheel',
}

-- For each model: does it exist as a road vehicle in this game build, what is it called, and its class.
RegisterNUICallback('admin:labels', function(data, cb)
    local out = {}
    if not Nui.open or type(data) ~= 'table' or type(data.models) ~= 'table' then return cb(out) end
    for i = 1, math.min(#data.models, 400) do
        local model = data.models[i]
        if type(model) == 'string' and #model <= 32 and model:match('^[%w_]+$') then
            local hash = joaat(model)
            if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
                local make = GetLabelText(GetMakeNameFromVehicleModel(hash))
                local name = GetLabelText(GetDisplayNameFromVehicleModel(hash))
                if name == 'NULL' then name = GetDisplayNameFromVehicleModel(hash) end
                out[model] = {
                    ok = true,
                    label = ((make ~= 'NULL' and make ~= '' and make .. ' ' or '') .. name):gsub('^%s+', ''),
                    class = CLASSES[GetVehicleClassFromName(hash)] or '',
                }
            else
                out[model] = { ok = false }
            end
        end
    end
    cb(out)
end)

-- The placement editor (client/gizmo.lua). The menu hides itself while it runs; the result is { x, y, z, w } or
-- { cancelled = true }.
RegisterNUICallback('admin:place', function(data, cb)
    if not Nui.open or Gizmo.active then return cb({ cancelled = true }) end
    local opts = type(data) == 'table' and data or {}
    local start = opts.start
    if start ~= nil and (type(start) ~= 'table' or not coordinate(start.x, -10000, 10000)
        or not coordinate(start.y, -10000, 10000) or not coordinate(start.z, -1000, 2000)
        or not coordinate(start.w, 0, 360)) then
        return cb({ cancelled = true })
    end
    SetNuiFocus(false, false)
    local label = type(opts.label) == 'string' and opts.label:sub(1, 192) or nil
    local ok, result = pcall(Gizmo.place, { start = start, label = label })
    if Nui.open then SetNuiFocus(true, true) end
    if not ok then
        print(('^1[bakery_barnfind] the placement editor failed: %s^7'):format(result))
        Nui.send('place', { active = false })
        return cb({ cancelled = true })
    end
    cb(result or { cancelled = true })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Nui.open then SetNuiFocus(false, false) end
end)
