-- Restoring a find, server side. The steps are tyres, glass, oil, body and start,
-- in that order, as switched on in the admin menu. Each is played on the car in the barn (client/finds.lua
-- runs the job) and has to be started and finished through here:
--   begin     the finder, at the barn, on the next step, holding its items
--   complete  same step, not impossibly fast, items still there: they are used up and the step is saved
--   claim     every step done: the car is made theirs (their garage) and they get keys
-- Progress is saved with the find (barnfind_found.progress), so a restore can be picked up after a relog or restart.
-- Seconds each step has to take at the least, so a step can't be "finished" the moment it starts.
local MIN_SECONDS = { tyres = 20, glass = 8, oil = 20, body = 15, start = 3 }
local RANGE = 20.0
local SESSION_SECONDS = 1800
local HANDOFF_MS = 30000

local sessions, handoffs = {}, {}

local function done(entry, id)
    for _, d in ipairs(entry.progress or {}) do if d == id then return true end end
    return false
end

local function nextStage(entry)
    for _, s in ipairs(Store.settings().restore.stages) do
        if s.enabled and not done(entry, s.id) then return s end
    end
end

-- The find `src` can restore in this barn: theirs, there, not yet driven out. Returns barn, owner, entry, cid,
-- or nil and a client message key.
local function lookup(src, barnId)
    local barn = Store.barn(barnId)
    local ped, reason = Requests.nearBarn(src, barn, RANGE)
    if not ped then return nil, reason end
    local cid = Bridge.getIdentifier(src)
    if not cid then return nil, 'busy' end
    local owner = Found.owner(cid)
    local entry = Found.get(barn, owner)
    if not entry then return nil, 'busy' end
    if entry.by ~= cid then return nil, 'notYours' end
    return barn, owner, entry, cid
end

-- The items a step needs, with how many of each the player has.
local function itemsFor(src, stage)
    local out = {}
    for _, it in ipairs(stage.items or {}) do
        out[#out + 1] = { name = it.name, count = it.count, label = Bridge.itemLabel(it.name), have = Bridge.itemCount(src, it.name) }
    end
    return out
end

local function short(items)
    for _, it in ipairs(items) do
        if it.have < it.count then return it end
    end
end

-- What the player can do with this barn's find right now.
local function register(name, kind, handler, writes)
    lib.callback.register('bakery_barnfind:restore:' .. name, function(src, barnId, ...)
        if not Store.ready or not Requests.allow(src, kind) or not Requests.barnId(barnId) then
            return { ok = false, error = 'busy' }
        end
        if not writes then return handler(src, barnId, ...) end
        local entered, ok, result = Requests.mutate(':player:' .. src, Requests.mutate, barnId, handler, src, barnId, ...)
        return entered and ok and result or { ok = false, error = 'busy' }
    end)
end

register('status', 'read', function(src, barnId)
    local barn, owner, entry = lookup(src, barnId)
    if not barn then return { ok = true, mine = false, reason = owner } end
    if entry.claimed then return { ok = true, mine = true, claimed = true } end
    local s = nextStage(entry)
    local steps = {}
    for _, st in ipairs(Store.settings().restore.stages) do
        if st.enabled then steps[#steps + 1] = { id = st.id, label = st.label, done = done(entry, st.id) } end
    end
    return {
        ok = true, mine = true, steps = steps,
        next = s and { id = s.id, label = s.label, items = itemsFor(src, s) } or nil,
        claimable = s == nil,
    }
end)

register('begin', 'action', function(src, barnId, stageId)
    local barn, owner, entry = lookup(src, barnId)
    if not barn then return { ok = false, error = owner } end
    if entry.claimed then return { ok = false, error = 'busy' } end
    local s = nextStage(entry)
    if not s or s.id ~= stageId then return { ok = false, error = 'busy' } end
    local missing = short(itemsFor(src, s))
    if missing then return { ok = false, error = 'missingItem', item = missing } end
    sessions[src] = { entry = entry, stage = s, at = os.time() }
    return { ok = true, wait = (MIN_SECONDS[stageId] or 5) + 1 }   -- the client sees out at least this long
end, true)

local function refund(src, cid, items)
    for _, item in ipairs(items) do
        local metadata = item.metadata
        local ok = Bridge.getIdentifier(src) == cid
        if ok and type(metadata) == 'table' and #metadata > 0 then
            for _, meta in ipairs(metadata) do
                ok = Bridge.addItem(src, item.name, 1, meta) and ok
            end
        elseif ok then
            ok = Bridge.addItem(src, item.name, item.count)
        end
        if not ok then
            print(('^1[bakery_barnfind] could not fully refund %dx %s to character %s^7'):format(item.count, item.name, cid))
        end
    end
end

register('complete', 'action', function(src, barnId, stageId)
    local session = sessions[src]
    if not session or session.stage.id ~= stageId then return { ok = false, error = 'busy' } end
    local barn, owner, entry, cid = lookup(src, barnId)
    if not barn then return { ok = false, error = owner } end
    local s = nextStage(entry)
    local elapsed = os.time() - session.at
    if entry.claimed or entry ~= session.entry or s ~= session.stage
        or elapsed > SESSION_SECONDS or elapsed < (MIN_SECONDS[stageId] or 5) then
        return { ok = false, error = 'busy' }
    end
    local items = itemsFor(src, s)
    local missing = short(items)
    if missing then return { ok = false, error = 'missingItem', item = missing } end
    if Bridge.getIdentifier(src) ~= cid then return { ok = false, error = 'busy' } end
    local removed = {}
    for _, it in ipairs(items) do
        if Bridge.getIdentifier(src) ~= cid then
            refund(src, cid, removed)
            return { ok = false, error = 'busy' }
        end
        local ok, metadata = Bridge.removeItem(src, it.name, it.count)
        if ok == true or (type(metadata) == 'table' and #metadata > 0) then
            removed[#removed + 1] = { name = it.name, count = it.count, metadata = metadata }
        end
        if ok ~= true then
            refund(src, cid, removed)
            return { ok = false, error = 'missingItem', item = it }
        end
    end
    local progress = { table.unpack(entry.progress) }
    progress[#progress + 1] = stageId
    local ok, saved = pcall(Found.saveRestore, barn, owner, entry, src, progress, false, entry.plate)
    if not ok or not saved then
        refund(src, cid, removed)
        if not ok then error(saved, 0) end
        return { ok = false, error = 'busy' }
    end
    if sessions[src] == session then sessions[src] = nil end
    local after = nextStage(entry)
    return { ok = true, finished = after == nil, next = after and after.label or nil }
end, true)

-- The car as the player gets it: the find's colour, now glossy, clean and healthy, with its own plate.
local function props(entry, plate)
    local paints = Store.section('paints') or {}
    local p = paints[entry.paint] or paints[1]
    local out = { model = joaat(entry.car), plate = plate, dirtLevel = 0.0, bodyHealth = 1000.0, engineHealth = 1000.0, fuelLevel = 100.0 }
    if p and p.color then
        local r, g, b = tonumber(p.color:sub(2, 3), 16), tonumber(p.color:sub(4, 5), 16), tonumber(p.color:sub(6, 7), 16)
        out.color1 = { r, g, b }
        out.color2 = { math.floor(r * 0.7), math.floor(g * 0.7), math.floor(b * 0.7) }
    end
    return out
end

register('claim', 'action', function(src, barnId)
    local barn, owner, entry, cid = lookup(src, barnId)
    if not barn then return { ok = false, error = owner } end
    if entry.claimed or nextStage(entry) then return { ok = false, error = 'busy' } end
    local plate = Found.reservePlate(barn, owner, entry)
    if not plate then return { ok = false, error = 'busy' } end
    local p = props(entry, plate)
    local spot, heading = BarnLayout.CarSpot, math.rad(barn.w)
    local x = barn.x + math.cos(heading) * spot.x - math.sin(heading) * spot.y
    local y = barn.y + math.sin(heading) * spot.x + math.cos(heading) * spot.y
    local bucket = GetPlayerRoutingBucket(src)
    local vehicle = CreateVehicle(p.model, x, y, barn.z + spot.z + 0.6, (barn.w + spot.w) % 360, true, true)
    if vehicle == 0 then return { ok = false, error = 'busy' } end
    local ok, saved = pcall(function()
        local started = GetGameTimer()
        while not DoesEntityExist(vehicle) and GetGameTimer() - started < 5000 do Wait(50) end
        if not DoesEntityExist(vehicle) then return false end
        SetEntityRoutingBucket(vehicle, bucket)
        local owned = Bridge.ownedVehicle(cid, entry.car, plate)
        if owned == false or Bridge.getIdentifier(src) ~= cid or GetPlayerRoutingBucket(src) ~= bucket then return false end
        owned = owned or Bridge.giveVehicle(src, cid, entry.car, p)
        if not owned then return false end
        if type(owned) == 'number' and GetResourceState('qbx_vehicles') == 'started' then
            Entity(vehicle).state:set('vehicleid', owned, false)
        end
        return Found.saveRestore(barn, owner, entry, src, entry.progress, true, plate)
    end)
    if not ok or not saved then
        if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
        if not ok then error(saved, 0) end
        return { ok = false, error = 'busy' }
    end
    local handoff = { barnId = barnId, entry = entry, vehicle = vehicle, bucket = bucket }
    handoffs[src] = handoff
    SetTimeout(HANDOFF_MS, function()
        if handoffs[src] == handoff then handoffs[src] = nil end
    end)
    print(('^2[bakery_barnfind]^7 %s restored and claimed a %s (%s) from %s'):format(Bridge.getName(src), entry.car, plate, barn.id))
    return { ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), plate = plate, props = p }
end, true)

-- Only the server-created vehicle recorded during this claim is eligible for keys.
register('keys', 'action', function(src, barnId)
    local handoff = handoffs[src]
    if not handoff or handoff.barnId ~= barnId then return { ok = false } end
    local barn, _, entry = lookup(src, barnId)
    local veh = handoff.vehicle
    if not barn or entry ~= handoff.entry or GetPlayerRoutingBucket(src) ~= handoff.bucket
        or not DoesEntityExist(veh) or GetEntityRoutingBucket(veh) ~= handoff.bucket
        or GetEntityModel(veh) ~= joaat(entry.car)
        or (GetVehicleNumberPlateText(veh) or ''):gsub('%s', '') ~= entry.plate then return { ok = false } end
    if not Bridge.giveKeys(src, veh) then return { ok = false } end
    handoffs[src] = nil
    return { ok = true }
end, true)

AddEventHandler('playerDropped', function()
    sessions[source], handoffs[source] = nil, nil
end)
