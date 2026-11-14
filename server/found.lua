-- Which barns have been searched, by whom, what was in them and when (and how far its restore has got).
-- Persisted in barnfind_found. Searching a barn (the doors prompt) comes through here too.
--
-- Scope decides who a find belongs to (the global setting, the same for every barn):
--   global  one find per barn for the whole server (owner ''). Everyone nearby sees the doors open and the car.
--   player  every character finds their own (owner = character id). Only they see it; other players see a shut barn.
-- Cooldown decides when a used barn resets (the global setting, the same for every barn). 0 = never.
Found = {}

local found = {}   -- [barnId][owner] = { car, paint, seed, by, name, at, progress = { stage ids done }, claimed, plate }

local function now() return os.time() end

local function scope()
    return Store.settings().scope
end

-- Minutes until a used barn resets, nil when it never does.
local function cooldownMinutes()
    local minutes = Store.settings().cooldownMinutes or 0
    if minutes <= 0 then return nil end
    return minutes
end

function Found.owner(cid)
    return scope() == 'player' and cid or ''
end

local function view(entry)
    return { car = entry.car, paint = entry.paint, seed = entry.seed, progress = entry.progress or {}, claimed = entry.claimed or nil }
end

-- ------------------------------------------------------------ publishing
local function globalSnapshot()
    local out = {}
    if scope() ~= 'global' then return out end
    for id, owners in pairs(found) do
        if owners[''] then out[id] = view(owners['']) end
    end
    return out
end

local function mine(cid)
    local out = {}
    if scope() ~= 'player' then return out end
    for id, owners in pairs(found) do
        if owners[cid] then out[id] = view(owners[cid]) end
    end
    return out
end

local function publishGlobal()
    GlobalState.bakery_barnfind = globalSnapshot()
end

local function pushMine(cid, src)
    TriggerClientEvent('bakery_barnfind:client:mine', src, mine(cid))
end

local function publish(owner, src)
    if owner == '' then
        publishGlobal()
    elseif src and Bridge.getIdentifier(src) == owner then
        pushMine(owner, src)
    end
end

function Found.publishScope()
    publishGlobal()
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        local cid = Bridge.getIdentifier(src)
        if cid then pushMine(cid, src) end
    end
end

-- ------------------------------------------------------------ storage
local function drop(barnId, owner)
    local owners = found[barnId]
    if not owners or not owners[owner] then return false end
    owners[owner] = nil
    if next(owners) == nil then found[barnId] = nil end
    return true
end

local function timeLeft(entry, minutes, at)
    return minutes and entry.at + minutes * 60 - at
end

-- The active find for this owner, and the seconds until it resets (nil = never).
function Found.get(barn, owner)
    local entry = found[barn.id] and found[barn.id][owner]
    if not entry then return nil end
    local left = timeLeft(entry, cooldownMinutes(), now())
    if left and left <= 0 then return nil end
    return entry, left
end

local function create(barn, owner, cid, src, car)
    local paints = Store.section('paints') or {}
    local entry = {
        car = car, paint = #paints > 0 and math.random(#paints) or 1, seed = math.random(1, 2147483000),
        by = cid, name = Bridge.getName(src), at = now(), progress = {},
    }
    local saved = MySQL.query.await([[
            INSERT INTO barnfind_found (barn_id, owner, car, paint, seed, found_by, found_name, found_at, progress, claimed, plate)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, '[]', 0, '')
            ON DUPLICATE KEY UPDATE car = VALUES(car), paint = VALUES(paint), seed = VALUES(seed),
                found_by = VALUES(found_by), found_name = VALUES(found_name), found_at = VALUES(found_at),
                progress = '[]', claimed = 0, plate = ''
    ]], { barn.id, owner, car, entry.paint, entry.seed, cid, entry.name, entry.at })
    if not saved then return nil end
    found[barn.id] = found[barn.id] or {}
    found[barn.id][owner] = entry
    publish(owner, src)
    return entry
end

-- A find's restore moved on (a step done, or claimed): save it and tell whoever can see it.
function Found.saveRestore(barn, owner, entry, src, progress, claimed, plate)
    local changed = MySQL.update.await('UPDATE barnfind_found SET progress = ?, claimed = ?, plate = ? WHERE barn_id = ? AND owner = ?',
        { json.encode(progress), claimed and 1 or 0, plate or '', barn.id, owner })
    if changed ~= 1 then return false end
    entry.progress, entry.claimed, entry.plate = progress, claimed, plate
    publish(owner, src)
    return true
end

function Found.reservePlate(barn, owner, entry)
    if entry.plate and entry.plate ~= '' then return entry.plate end
    local ok, plate = Requests.mutate(':plate', function()
        local candidate = Bridge.newPlate()
        if not candidate then return nil end
        local changed = MySQL.update.await('UPDATE barnfind_found SET plate = ? WHERE barn_id = ? AND owner = ?',
            { candidate, barn.id, owner })
        if changed ~= 1 then return nil end
        entry.plate = candidate
        return candidate
    end)
    return ok and plate or nil
end

function Found.reset(barnId)
    local count
    if barnId then
        count = MySQL.update.await('DELETE FROM barnfind_found WHERE barn_id = ?', { barnId })
        found[barnId] = nil
    else
        count = MySQL.update.await('DELETE FROM barnfind_found')
        found = {}
    end
    Found.publishScope()
    return count
end

-- A barn that was deleted in the menu takes its finds with it.
function Found.forgetBarns()
    local removed = false
    for id in pairs(found) do
        if not Store.barn(id) then
            MySQL.update.await('DELETE FROM barnfind_found WHERE barn_id = ?', { id })
            found[id] = nil
            removed = true
        end
    end
    if removed then Found.publishScope() end
end

-- ------------------------------------------------------------ admin view
function Found.live()
    local out = {}
    local minutes, at, currentScope = cooldownMinutes(), now(), scope()
    for _, barn in ipairs(Store.barns() or {}) do
        local entries = {}
        for owner, e in pairs(found[barn.id] or {}) do
            entries[#entries + 1] = {
                owner = owner, name = e.name, car = e.car, at = e.at,
                left = minutes and math.max(0, timeLeft(e, minutes, at)) or nil,
            }
        end
        table.sort(entries, function(a, b) return a.at > b.at end)
        local shown = {}
        for i = 1, math.min(#entries, 6) do shown[i] = entries[i] end
        out[#out + 1] = {
            id = barn.id, count = #entries, entries = shown,
            scope = currentScope, cooldown = minutes,
        }
    end
    return out
end

-- ------------------------------------------------------------ searching
local SEARCH_RANGE = 8.0

-- A player at the doors wants to search the barn.
-- Returns true + { car, paint, seed } for the reveal, or false + a client message key and optional cooldown.
local function search(src, id)
    local barn = Store.barn(id)
    local ped, reason = Requests.nearBarn(src, barn, SEARCH_RANGE)
    if not ped then return false, reason end

    local cid = Bridge.getIdentifier(src)
    if not cid then return false, 'busy' end

    local owner = Found.owner(cid)
    local entry, left = Found.get(barn, owner)
    if entry then
        if left then return false, 'cooldown', left end
        return false, 'alreadyFound'
    end

    local car = Store.pick(barn)
    if not car then return false, 'empty' end
    entry = create(barn, owner, cid, src, car)
    if not entry then return false, 'busy' end
    return true, { car = entry.car, paint = entry.paint, seed = entry.seed }
end

lib.callback.register('bakery_barnfind:search', function(src, id)
    if not Store.ready or not Requests.allow(src, 'action') or not Requests.barnId(id) then return false, 'busy' end
    local ok, result, payload, left = Requests.mutate(id, search, src, id)
    if not ok then return false, 'busy' end
    return result, payload, left
end)

-- This player's own finds, for barns where every player finds their own.
lib.callback.register('bakery_barnfind:mine', function(src)
    if not Store.ready or not Requests.allow(src, 'read') then return false end
    local cid = Bridge.getIdentifier(src)
    return cid and mine(cid) or {}
end)

-- ------------------------------------------------------------ expiry
local function sweep()
    local minutes, at = cooldownMinutes(), now()
    if not minutes then return end
    local expireBefore = at - minutes * 60
    local expired = false
    for _, owners in pairs(found) do
        for _, entry in pairs(owners) do
            if entry.at <= expireBefore then expired = true break end
        end
        if expired then break end
    end
    if not expired then return end
    MySQL.update.await('DELETE FROM barnfind_found WHERE found_at <= ?', { expireBefore })
    local sharedChanged, owners = false, {}
    for id, byOwner in pairs(found) do
        for owner, e in pairs(byOwner) do
            if e.at <= expireBefore then
                drop(id, owner)
                if owner == '' then sharedChanged = true else owners[owner] = true end
            end
        end
    end
    if sharedChanged then publishGlobal() end
    if scope() == 'player' and next(owners) then
        for _, player in ipairs(GetPlayers()) do
            local src = tonumber(player)
            local cid = Bridge.getIdentifier(src)
            if owners[cid] then pushMine(cid, src) end
        end
    end
end

DB.onReady(function()
    for _, row in ipairs(MySQL.query.await('SELECT * FROM barnfind_found') or {}) do
        found[row.barn_id] = found[row.barn_id] or {}
        local progress = DB.decode(row.progress, {})
        found[row.barn_id][row.owner] = {
            car = row.car, paint = row.paint, seed = row.seed, by = row.found_by, name = row.found_name, at = tonumber(row.found_at) or 0,
            progress = type(progress) == 'table' and progress or {},
            claimed = row.claimed == 1 or row.claimed == true, plate = row.plate,
        }
    end
    Found.forgetBarns()
    sweep()
    Store.ready = true
    publishGlobal()
    Store.publish()
    print(('^2[bakery_barnfind]^7 %d barns, %d cars, %d paints loaded'):format(
        #Store.barns(), #Store.section('cars'), #Store.section('paints')))
    CreateThread(function()
        while true do
            Wait(15000)
            Requests.mutate(nil, sweep)
        end
    end)
end)
