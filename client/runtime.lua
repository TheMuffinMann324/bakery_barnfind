-- Apply the published tablet settings to the barns around the player.
local ready = false

local points = {}   -- [barnId] = { key, point }
local characterRevision = 0

-- A barn exists in the world only while the player is inside its range, and is rebuilt when its spot, heading
-- or the range changes.
local function syncBarns(list, distance)
    local seen = {}
    for _, b in ipairs(list or {}) do
        seen[b.id] = true
        local key = ('%.2f|%.2f|%.2f|%.1f|%.0f'):format(b.x, b.y, b.z, b.w, distance)
        local have = points[b.id]
        if not have or have.key ~= key then
            if have then
                have.point:remove()
                Barn.despawn(b.id)
            end
            local id, coords = b.id, vec4(b.x, b.y, b.z, b.w)
            points[id] = {
                key = key,
                point = lib.points.new({
                    coords = coords.xyz,
                    distance = distance,
                    onEnter = function()
                        CreateThread(function()
                            Barn.spawn(id, coords)   -- may wait for the model to register (just after a restart)
                        end)
                    end,
                    onExit = function() Barn.despawn(id) end,
                }),
            }
        end
    end
    for id, have in pairs(points) do
        if not seen[id] then
            have.point:remove()
            Barn.despawn(id)
            points[id] = nil
        end
    end
end

local function apply(public)
    if type(public) ~= 'table' or type(public.settings) ~= 'table' then return end
    local s = public.settings
    local c = s.condition

    local distanceChanged = Tuning.Barn.InteractDistance ~= s.interactDistance
    RegisterBarnAdminCommand(public.menu)
    Tuning.Debug = public.debug
    Tuning.Barn.InteractDistance = s.interactDistance
    Tuning.Cutscene.Enabled = s.cutscene.enabled
    Tuning.Cutscene.Skippable = s.cutscene.skippable

    local dressingChanged = Tuning.Barn.DressingEnabled ~= s.dressing
    Tuning.Barn.DressingEnabled = s.dressing

    -- The wreck renderer keeps a reference to Tuning.Wreck.
    local w = Tuning.Wreck
    w.Dirt, w.Rust, w.BodyHealth, w.EngineHealth = c.dirt, c.rust, c.bodyHealth, c.engineHealth
    w.BurstTyres, w.SmashWindows = c.burstTyres, c.smashedWindows
    w.HoodAjar = c.hoodAjar > 0 and c.hoodAjar / 100.0 or false
    w.Plate = c.plate
    w.Paints = public.paints or {}

    syncBarns(public.barns, s.spawnDistance)
    if dressingChanged and ready then Barn.refreshDressing() end
    if distanceChanged then
        for _, id in ipairs(Barn.ids()) do Barn.refreshInteraction(id) end
    end
    ready = true
end

-- This player's own finds (the server only knows them by character id, so it's asked, not assumed).
local function refreshMine()
    characterRevision = characterRevision + 1
    local revision = characterRevision
    local ok, list = pcall(lib.callback.await, 'bakery_barnfind:mine', false)
    if revision == characterRevision and ok and type(list) == 'table' then Barn.setMine(list) end
end

-- Server pushes. Server-triggered events arrive with source 65535; anything else is another script
-- calling TriggerEvent locally and is ignored.
RegisterNetEvent('bakery_barnfind:client:config', function(public)
    if source ~= 65535 then return end
    apply(public)
end)

RegisterNetEvent('bakery_barnfind:client:mine', function(list)
    if source ~= 65535 then return end
    characterRevision = characterRevision + 1
    Barn.setMine(list)
end)

-- A different character: their finds are not the last one's.
for _, event in ipairs({ 'QBCore:Client:OnPlayerLoaded', 'qbx_core:client:playerLoaded', 'esx:playerLoaded' }) do
    RegisterNetEvent(event, function() CreateThread(refreshMine) end)
end
for _, event in ipairs({ 'QBCore:Client:OnPlayerUnload', 'qbx_core:client:playerLoggedOut', 'esx:onPlayerLogout' }) do
    RegisterNetEvent(event, function()
        characterRevision = characterRevision + 1
        Finds.stop()
        Barn.setMine({})
    end)
end

-- The server may still be loading its settings (first start seeds the database), so ask until it answers.
CreateThread(function()
    for _ = 1, 60 do
        local ok, public = pcall(lib.callback.await, 'bakery_barnfind:config', false)
        if ok and type(public) == 'table' and public.ready then
            apply(public)
            refreshMine()
            return
        end
        Wait(2000)
    end
    print('^3[bakery_barnfind] the server never answered with its settings; barns will not appear^7')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, have in pairs(points) do have.point:remove() end
end)
