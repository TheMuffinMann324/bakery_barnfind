-- Everything framework / notification / interaction related goes through kq_link,
-- so the resource follows whatever kq_link is configured for (ox_target, qb-target, 3D text, ...).
Bridge = {}

local kq = exports.kq_link

local function call(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok and Tuning.Debug then print(('^3[bakery_barnfind] kq_link call failed: %s^7'):format(res)) end
    return ok and res or nil
end

function Bridge.notify(message, kind)
    call(function() kq:Notify(message, kind or 'info') end)
end

-- Returns a handle with :remove(). opts: coords, heading, message, targetMessage, onSelect, canInteract, distance, name
function Bridge.addZone(opts)
    local handle = call(function()
        return kq:AddInteractionZone(opts.coords, vector3(0.0, 0.0, opts.heading or 0.0), vector3(2.0, 2.0, 2.5),
            opts.message, opts.targetMessage, 38, opts.onSelect, opts.canInteract,
            { name = opts.name }, opts.distance or 2.0, opts.icon or 'fas fa-warehouse')
    end)
    return {
        remove = function()
            if handle then call(function() handle.Delete() end) end
            handle = nil
        end,
    }
end

-- "2h 5m", "45m", "30s": how long until something is ready.
function Bridge.duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
    if d > 0 then return h > 0 and ('%dd %dh'):format(d, h) or ('%dd'):format(d) end
    if h > 0 then return m > 0 and ('%dh %dm'):format(h, m) or ('%dh'):format(h) end
    if m > 0 then return ('%dm'):format(m) end
    return ('%ds'):format(seconds)
end
