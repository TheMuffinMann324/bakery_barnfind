-- Framework lookups go through kq_link, like the other Bakery resources.
Bridge = {}

local kq = exports.kq_link

local function safe(fn)
    local ok, result, extra = pcall(fn)
    if not ok then
        if Config.Debug then print(('^3[bakery_barnfind] kq_link call failed: %s^7'):format(result)) end
        return nil
    end
    return result, extra
end

-- Character id (citizenid / identifier / charid, whichever the framework uses). Looked up fresh each time:
-- switching character doesn't have to disconnect.
function Bridge.getIdentifier(src)
    local id = safe(function() return kq:GetPlayerCharacterId(src) end)
    if type(id) ~= 'string' and type(id) ~= 'number' then return nil end
    id = tostring(id)
    if id == '' or #id > 64 then return nil end
    return id
end

function Bridge.getName(src)
    local name = safe(function() return kq:GetPlayerCharacterName(src) end)
    if type(name) ~= 'string' or not utf8.len(name) then name = GetPlayerName(src) end
    if type(name) ~= 'string' or not utf8.len(name) then return 'Unknown' end
    local ending = utf8.offset(name, 81)
    return ending and name:sub(1, ending - 1) or name
end

-- Every item the inventory knows, as { name, label }, for the admin menu to suggest. Empty if it can't tell.
function Bridge.itemList()
    local out = {}
    local items = GetResourceState('ox_inventory') == 'started' and safe(function() return exports.ox_inventory:Items() end)
    if type(items) == 'table' then
        for name, it in pairs(items) do
            if type(name) == 'string' then
                local label = type(it) == 'table' and it.label
                out[#out + 1] = { name = name, label = type(label) == 'string' and label or name }
            end
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- ------------------------------------------------------------ restoring: items and the car
-- How many of an item the player has.
function Bridge.itemCount(src, name)
    return tonumber(safe(function() return kq:GetPlayerItemCount(src, name) end)) or 0
end

function Bridge.removeItem(src, name, count)
    return safe(function() return kq:RemovePlayerItem(src, name, count) end)
end

function Bridge.addItem(src, name, count, metadata)
    return safe(function() return kq:AddPlayerItem(src, name, count, metadata) end) == true
end

-- An item's display name, or its name if the inventory doesn't say.
local labels
function Bridge.itemLabel(name)
    if not labels then
        labels = {}
        for _, it in ipairs(Bridge.itemList()) do labels[it.name] = it.label end
    end
    return labels[name] or name
end

local function garageTable()
    if GetResourceState('qbx_vehicles') == 'started' or GetResourceState('qb-core') == 'started' then
        return 'player_vehicles'
    end
    if GetResourceState('es_extended') == 'started' then return 'owned_vehicles' end
end

-- A plate no other owned car has: BF and six characters.
function Bridge.newPlate()
    local garage = garageTable()
    if not garage then return nil end
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    for _ = 1, 50 do
        local p = 'BF'
        for _ = 1, 6 do
            local i = math.random(#chars)
            p = p .. chars:sub(i, i)
        end
        local taken = MySQL.scalar.await(('SELECT EXISTS(SELECT 1 FROM %s WHERE plate = ?) '
            .. 'OR EXISTS(SELECT 1 FROM barnfind_found WHERE plate = ?)'):format(garage), { p, p })
        if tonumber(taken) == 0 then return p end
    end
end

-- A saved plate lets a retry reconcile a garage write that already succeeded.
function Bridge.ownedVehicle(cid, model, plate)
    local garage = garageTable()
    if garage == 'player_vehicles' then
        local row = MySQL.single.await('SELECT id, citizenid, vehicle FROM player_vehicles WHERE plate = ?', { plate })
        if not row then return nil end
        return row.citizenid == cid and row.vehicle == model and row.id or false
    end
    if garage == 'owned_vehicles' then
        local row = MySQL.single.await('SELECT owner, vehicle FROM owned_vehicles WHERE plate = ?', { plate })
        if not row then return nil end
        local props = DB.decode(row.vehicle, {})
        return row.owner == cid and type(props) == 'table' and tonumber(props.model) == joaat(model)
    end
    return false
end

-- Make `model` an owned car of the character `cid`, in their garage, with `props` (plate, colours...).
-- Qbox (qbx_vehicles), then QBCore and ESX. Returns true when it is saved.
function Bridge.giveVehicle(src, cid, model, props)
    if GetResourceState('qbx_vehicles') == 'started' then
        local id = safe(function() return exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = cid, props = props }) end)
        return type(id) == 'number' and id > 0 and id or false
    end
    if GetResourceState('qb-core') == 'started' then
        local license = GetPlayerIdentifierByType(src, 'license')
        if not license then return false end
        local id = MySQL.insert.await([[INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state)
            VALUES (?, ?, ?, ?, ?, ?, 0)]], { license, cid, model, joaat(model), json.encode(props), props.plate })
        return type(id) == 'number' and id > 0 and id or false
    end
    if GetResourceState('es_extended') == 'started' then
        local affected = MySQL.update.await('INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, 0)',
            { cid, props.plate, json.encode(props), 'car' })
        return affected == 1
    end
    print('^1[bakery_barnfind] no garage system found to give the car to (edit Bridge.giveVehicle in server/bridge.lua)^7')
    return false
end

function Bridge.giveKeys(src, vehicle)
    local ok, result = pcall(function() return kq:GiveVehicleKeys(src, vehicle) end)
    return ok and result ~= false
end
