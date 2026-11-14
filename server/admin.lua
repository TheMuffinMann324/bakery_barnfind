-- The admin menu's server side. Every call checks access again: the NUI is never trusted.
local function isAdmin(src)
    for _, ace in ipairs(Config.Admin.Aces) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    local license = GetPlayerIdentifierByType(src, 'license')
    for _, allowed in ipairs(Config.Admin.Licenses) do
        if allowed == license then return true end
    end
    return false
end

local function snapshot()
    return {
        ok = true,
        settings = Store.settings(),
        cars = Store.section('cars'),
        paints = Store.section('paints'),
        barns = Store.section('barns'),
        live = Found.live(),
        items = Bridge.itemList(),
        now = os.time(),
    }
end

local function register(name, fn, writes)
    lib.callback.register('bakery_barnfind:admin:' .. name, function(src, ...)
        if not Store.ready then return { ok = false, error = 'Barn Find is still starting up.' } end
        if not Requests.allow(src, 'admin') then return { ok = false, error = 'Too many requests. Try again in a moment.' } end
        if not isAdmin(src) then return { ok = false, error = 'No access.' } end
        local ok, result
        if writes then
            ok, result = Requests.mutate(nil, fn, src, ...)
            if not ok and result == nil then return { ok = false, error = 'Barn Find is busy. Try again in a moment.' } end
        else
            ok, result = pcall(fn, src, ...)
        end
        if not ok then
            print(('^1[bakery_barnfind] admin:%s failed: %s^7'):format(name, tostring(result)))
            return { ok = false, error = 'Could not complete that. Check the server console.' }
        end
        return result
    end)
end

local function sane(value)
    local ok, encoded = pcall(json.encode, value)
    return ok and type(encoded) == 'string' and #encoded <= 300000
end

register('open', function(src)
    local data = snapshot()
    data.me = { name = GetPlayerName(src) or 'Admin' }
    return data
end)

register('save', function(src, payload)
    if type(payload) ~= 'table' or not Store.valid(payload.section) or type(payload.value) ~= 'table' or not sane(payload.value) then
        return { ok = false, error = 'Invalid request.' }
    end
    local section = payload.section
    local oldScope = Store.settings().scope
    local cleaned = Store.save(section, payload.value)
    if section == 'barns' then Found.forgetBarns() end
    if oldScope ~= Store.settings().scope then Found.publishScope() end
    Store.publish()
    print(('^3[bakery_barnfind]^7 %s saved %s'):format(GetPlayerName(src) or src, section))
    return { ok = true, value = cleaned, live = Found.live() }
end, true)

register('reset', function(src, payload)
    local section = type(payload) == 'table' and payload.section
    if section ~= 'settings' and section ~= 'paints' then
        return { ok = false, error = 'That section has no defaults.' }
    end
    local oldScope = Store.settings().scope
    local cleaned = Store.save(section, Store.defaults(section))
    if oldScope ~= Store.settings().scope then Found.publishScope() end
    Store.publish()
    print(('^3[bakery_barnfind]^7 %s restored %s to its defaults'):format(GetPlayerName(src) or src, section))
    return { ok = true, value = cleaned }
end, true)

register('live', function()
    return { ok = true, live = Found.live(), now = os.time() }
end)

-- id: one barn, or nil for every barn.
register('resetBarn', function(src, payload)
    if type(payload) ~= 'table' then return { ok = false, error = 'Invalid request.' } end
    local id = payload.id
    local count
    if id == nil then
        count = Found.reset()
    elseif Requests.barnId(id) and Store.barn(id) then
        count = Found.reset(id)
    else
        return { ok = false, error = 'Unknown barn.' }
    end
    print(('^3[bakery_barnfind]^7 %s reset %s (%d finds cleared)'):format(GetPlayerName(src) or src, id or 'every barn', count))
    return { ok = true, cleared = count, live = Found.live() }
end, true)
