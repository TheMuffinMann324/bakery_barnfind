-- Tables are created on start. Settings are one JSON row per key (settings, cars, paints, barns) so they're in
-- your database backups; barnfind_found is who found what, and when, for the cooldowns, and how far its
-- restore has got.
DB = { isReady = false }

local waiting = {}

local TABLES = {
    [[
        CREATE TABLE IF NOT EXISTS `barnfind_settings` (
            `setting_key` VARCHAR(64) NOT NULL PRIMARY KEY,
            `value` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `barnfind_found` (
            `barn_id` VARCHAR(48) NOT NULL,
            `owner` VARCHAR(64) NOT NULL DEFAULT '',
            `car` VARCHAR(40) NOT NULL,
            `paint` INT NOT NULL DEFAULT 1,
            `seed` INT NOT NULL DEFAULT 0,
            `found_by` VARCHAR(64) NOT NULL DEFAULT '',
            `found_name` VARCHAR(80) NOT NULL DEFAULT '',
            `found_at` BIGINT NOT NULL,
            `progress` VARCHAR(255) NOT NULL DEFAULT '[]',
            `claimed` TINYINT(1) NOT NULL DEFAULT 0,
            `plate` VARCHAR(12) NOT NULL DEFAULT '',
            PRIMARY KEY (`barn_id`, `owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}

local COLUMNS = {
    { 'barnfind_found', 'progress', "VARCHAR(255) NOT NULL DEFAULT '[]'" },   -- restore steps done, in order
    { 'barnfind_found', 'claimed', 'TINYINT(1) NOT NULL DEFAULT 0' },         -- restored and driven out
    { 'barnfind_found', 'plate', "VARCHAR(12) NOT NULL DEFAULT ''" },        -- the plate it was given
}

function DB.onReady(cb)
    if DB.isReady then return cb() end
    waiting[#waiting + 1] = cb
end

function DB.decode(raw, fallback)
    if type(raw) ~= 'string' or raw == '' then return fallback end
    local ok, value = pcall(json.decode, raw)
    if ok and value ~= nil then return value end
    return fallback
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end
    MySQL.ready.await()
    for _, sql in ipairs(TABLES) do MySQL.query.await(sql) end
    -- columns added since the table was first made
    for _, col in ipairs(COLUMNS) do
        local has = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]], { col[1], col[2] })
        if (tonumber(has) or 0) == 0 then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(col[1], col[2], col[3])) end
    end
    DB.isReady = true
    for _, cb in ipairs(waiting) do
        local ok, err = pcall(cb)
        if not ok then
            DB.isReady = false
            print(('^1[bakery_barnfind] startup step failed: %s^7'):format(err))
            break
        end
    end
    waiting = {}
end)


-- Everything the admin menu edits, kept in the barnfind_settings table (one JSON row per section):
--   settings  global rules (scope, cooldown, condition of finds, the restore steps and their items...)
--   cars      what can be found and each car's weight (its chance)
--   paints    the faded paint colours a find can wear
--   barns     where barns stand and their vehicle pools
-- Whatever a client sends is cleaned here: types checked, numbers clamped, junk dropped.
Store = { ready = false }

local SECTIONS = { settings = true, cars = true, paints = true, barns = true }
local values = {}          -- section -> cleaned value
local barnIndex = {}       -- barn id -> barn
local public

-- ------------------------------------------------------------ helpers
local function num(value, lo, hi, default, int)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default end
    if int then n = math.floor(n + 0.5) end
    return math.max(lo, math.min(hi, n))
end

local function bool(value, default)
    if type(value) == 'boolean' then return value end
    return default
end

local function text(value, max, default)
    if type(value) ~= 'string' then return default end
    local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
    if not utf8.len(trimmed) then return default end
    local ending = utf8.offset(trimmed, max + 1)
    return ending and trimmed:sub(1, ending - 1) or trimmed
end

local function pick(value, allowed, default)
    for _, a in ipairs(allowed) do if value == a then return value end end
    return default
end

local function round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

-- Defaults used on first install and when restoring gameplay settings or paints.
local DEFAULT_SETTINGS = {
    scope = 'global',
    cooldownMinutes = 120,
    spawnDistance = 150.0,
    interactDistance = 2.2,
    cutscene = { enabled = true, skippable = true },
    dressing = true,
    condition = {
        dirt = 15.0, rust = 1.0, bodyHealth = 250, engineHealth = 150,
        burstTyres = 2, smashedWindows = 3, hoodAjar = 25, plate = '',
    },
    restore = {
        stages = {
            { id = 'tyres', label = 'Tyres and wheels', enabled = true },
            { id = 'glass', label = 'Windows', enabled = true },
            { id = 'oil', label = 'Oil and filter', enabled = true },
            { id = 'body', label = 'Bodywork', enabled = true },
            { id = 'start', label = 'Start it up', enabled = true },
        },
    },
}

local DEFAULT_PAINTS = {
    { name = 'Oxblood', color = '#5c2622' },
    { name = 'Sage', color = '#606e58' },
    { name = 'Cream', color = '#b0a486' },
    { name = 'Faded blue', color = '#405468' },
    { name = 'Burnt orange', color = '#764828' },
    { name = 'Graphite', color = '#3a3e3a' },
    { name = 'Mustard', color = '#827046' },
    { name = 'Racing green', color = '#283a2e' },
}

local function defaults(section)
    if section == 'settings' then return DEFAULT_SETTINGS end
    if section == 'paints' then return DEFAULT_PAINTS end
    return {}
end

-- ------------------------------------------------------------ cleaners
local function cleanSettings(raw)
    local d = DEFAULT_SETTINGS
    raw = type(raw) == 'table' and raw or {}
    local cutscene = type(raw.cutscene) == 'table' and raw.cutscene or {}
    local c = type(raw.condition) == 'table' and raw.condition or {}
    local r = type(raw.restore) == 'table' and raw.restore or {}

    -- Keep the built-in stage order and apply the saved enable flags and items.
    local stages = {}
    for _, base in ipairs(d.restore.stages) do
        local got
        for _, s in ipairs(type(r.stages) == 'table' and r.stages or {}) do
            if type(s) == 'table' and s.id == base.id then got = s break end
        end
        got = got or base
        local items, seen = {}, {}
        for _, it in ipairs(type(got.items) == 'table' and got.items or {}) do
            local name = type(it) == 'table' and type(it.name) == 'string' and it.name:gsub('%s', '') or ''
            if name ~= '' and #name <= 60 and name:match('^[%w_%-%.]+$') and not seen[name] and #items < 12 then
                seen[name] = true
                items[#items + 1] = { name = name, count = num(it.count, 1, 1000, 1, true) }
            end
        end
        stages[#stages + 1] = { id = base.id, label = base.label, enabled = bool(got.enabled, base.enabled), items = items }
    end

    return {
        scope = pick(raw.scope, { 'global', 'player' }, d.scope),
        cooldownMinutes = num(raw.cooldownMinutes, 0, 525600, d.cooldownMinutes, true),
        spawnDistance = num(raw.spawnDistance, 60, 500, d.spawnDistance),
        interactDistance = round(num(raw.interactDistance, 1.0, 6.0, d.interactDistance), 1),
        cutscene = { enabled = bool(cutscene.enabled, d.cutscene.enabled), skippable = bool(cutscene.skippable, d.cutscene.skippable) },
        dressing = bool(raw.dressing, d.dressing),
        condition = {
            dirt = round(num(c.dirt, 0, 15, d.condition.dirt), 1),
            rust = round(num(c.rust, 0, 1, d.condition.rust), 2),
            bodyHealth = num(c.bodyHealth, 0, 1000, d.condition.bodyHealth, true),
            engineHealth = num(c.engineHealth, 0, 1000, d.condition.engineHealth, true),
            burstTyres = num(c.burstTyres, 0, 4, d.condition.burstTyres, true),
            smashedWindows = num(c.smashedWindows, 0, 6, d.condition.smashedWindows, true),
            hoodAjar = num(c.hoodAjar, 0, 100, d.condition.hoodAjar, true),
            plate = text(c.plate, 8, d.condition.plate):upper(),
        },
        restore = { stages = stages },   -- restoring is always on, and a find is free to take out of the barn
    }
end

local function cleanModel(value)
    if type(value) ~= 'string' then return nil end
    local model = value:lower():gsub('%s', '')
    if model == '' or #model > 32 or not model:match('^[%w_]+$') then return nil end
    return model
end

local function cleanCars(raw)
    local out, seen = {}, {}
    for _, c in ipairs(type(raw) == 'table' and raw or {}) do
        local model = type(c) == 'table' and cleanModel(c.model)
        if model and not seen[model] and #out < 200 then
            seen[model] = true
            out[#out + 1] = { model = model, weight = num(c.weight, 0, 1000, 1, true), enabled = bool(c.enabled, true) }
        end
    end
    return out
end

local function cleanPaints(raw)
    local out = {}
    for _, p in ipairs(type(raw) == 'table' and raw or {}) do
        if type(p) == 'table' and type(p.color) == 'string' and p.color:match('^#%x%x%x%x%x%x$') and #out < 24 then
            out[#out + 1] = { name = text(p.name, 24, ''):gsub('^$', 'Paint ' .. (#out + 1)), color = p.color:lower() }
        end
    end
    return out
end

local function cleanBarns(raw)
    local out, seen = {}, {}
    for _, b in ipairs(type(raw) == 'table' and raw or {}) do
        local id = type(b) == 'table' and type(b.id) == 'string' and b.id:match('^[%w_%-]+$') and #b.id <= 40 and b.id
        if id and not seen[id] and #out < 200 then
            seen[id] = true
            local pool
            if type(b.pool) == 'table' then
                pool = {}
                for _, m in ipairs(b.pool) do
                    local model = cleanModel(m)
                    if model and #pool < 200 then pool[#pool + 1] = model end
                end
                if #pool == 0 then pool = nil end
            end
            out[#out + 1] = {
                id = id,
                name = text(b.name, 48, ''):gsub('^$', id),
                x = round(num(b.x, -10000, 10000, 0), 2), y = round(num(b.y, -10000, 10000, 0), 2),
                z = round(num(b.z, -1000, 2000, 0), 2), w = round(num(b.w, 0, 360, 0) % 360, 1),
                enabled = bool(b.enabled, true),
                pool = pool,
            }
        end
    end
    return out
end

local CLEANERS = { settings = cleanSettings, cars = cleanCars, paints = cleanPaints, barns = cleanBarns }

-- ------------------------------------------------------------ storage
local function reindex()
    barnIndex = {}
    for _, b in ipairs(values.barns or {}) do barnIndex[b.id] = b end
end

local function write(section, value)
    assert(MySQL.query.await('INSERT INTO barnfind_settings (setting_key, value) VALUES (?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)',
        { section, json.encode(value) }), 'Could not write ' .. section)
end

function Store.section(name) return values[name] end
function Store.defaults(name) return defaults(name) end
function Store.valid(name) return SECTIONS[name] == true end

-- Cleans and saves one section. Returns the cleaned value, which may differ from what was sent.
function Store.save(name, raw)
    local cleaned = CLEANERS[name](raw)
    write(name, cleaned)
    values[name] = cleaned
    if name == 'barns' then reindex() end
    public = nil
    return cleaned
end

function Store.settings() return values.settings end
function Store.barns() return values.barns end
function Store.barn(id) return barnIndex[id] end

-- ------------------------------------------------------------ cars
-- The cars a barn can hold: enabled, with a weight, and inside the barn's own pool if it has one.
local function pool(barn)
    local allowed
    if barn and type(barn.pool) == 'table' and #barn.pool > 0 then
        allowed = {}
        for _, m in ipairs(barn.pool) do allowed[m] = true end
    end
    local list, total = {}, 0
    for _, c in ipairs(values.cars or {}) do
        if c.enabled and c.weight > 0 and (not allowed or allowed[c.model]) then
            list[#list + 1] = c
            total = total + c.weight
        end
    end
    return list, total
end

function Store.pick(barn)
    local list, total = pool(barn)
    if total <= 0 then return nil end
    local roll = math.random() * total
    for _, c in ipairs(list) do
        roll = roll - c.weight
        if roll <= 0 then return c.model end
    end
    return list[#list].model
end

-- ------------------------------------------------------------ what clients get
local function publicConfig()
    if not Store.ready or not values.settings then return { ready = false } end   -- still loading: the client asks again
    if public then return public end
    local s = values.settings
    local paints, barns = {}, {}
    for i, p in ipairs(values.paints or {}) do
        paints[i] = { tonumber(p.color:sub(2, 3), 16), tonumber(p.color:sub(4, 5), 16), tonumber(p.color:sub(6, 7), 16) }
    end
    for _, b in ipairs(values.barns or {}) do
        if b.enabled and (b.x ~= 0 or b.y ~= 0) then barns[#barns + 1] = { id = b.id, x = b.x, y = b.y, z = b.z, w = b.w } end
    end
    public = {
        ready = Store.ready,
        menu = { command = Config.Admin.Command, keybind = Config.Admin.Keybind },
        debug = Config.Debug,
        settings = {
            spawnDistance = s.spawnDistance, interactDistance = s.interactDistance,
            cutscene = s.cutscene, dressing = s.dressing, condition = s.condition,
        },
        paints = paints,
        barns = barns,
    }
    return public
end

function Store.publish()
    TriggerClientEvent('bakery_barnfind:client:config', -1, publicConfig())
end

lib.callback.register('bakery_barnfind:config', function(src)
    if not Requests.allow(src, 'read') then return { ready = false } end
    return publicConfig()
end)

-- ------------------------------------------------------------ load
DB.onReady(function()
    local rows = MySQL.query.await('SELECT setting_key, value FROM barnfind_settings') or {}
    local stored = {}
    for _, row in ipairs(rows) do stored[row.setting_key] = DB.decode(row.value, nil) end

    for name in pairs(SECTIONS) do
        local seeded = stored[name] == nil
        values[name] = CLEANERS[name](seeded and defaults(name) or stored[name])
        if seeded then write(name, values[name]) end
    end
    reindex()
end)
