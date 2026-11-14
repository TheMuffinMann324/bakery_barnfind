Requests = {}

local buckets = {}
local mutations, inFlight, exclusive = {}, 0, false
local policies = {
    read = { burst = 20, perSecond = 4 },
    action = { burst = 8, perSecond = 2 },
    admin = { burst = 20, perSecond = 5 },
}

function Requests.allow(src, kind)
    local policy = policies[kind]
    local now = GetGameTimer()
    local player = buckets[src]
    if not player then
        player = {}
        buckets[src] = player
    end
    local bucket = player[kind] or { tokens = policy.burst, at = now }
    bucket.tokens = math.min(policy.burst, bucket.tokens + math.max(0, now - bucket.at) * policy.perSecond / 1000)
    bucket.at = now
    player[kind] = bucket
    if bucket.tokens < 1 then return false end
    bucket.tokens = bucket.tokens - 1
    return true
end

function Requests.barnId(id)
    return type(id) == 'string' and #id <= 40 and id:match('^[%w_%-]+$') ~= nil
end

function Requests.nearBarn(src, barn, range)
    if not barn or not barn.enabled or (barn.x == 0 and barn.y == 0) then return nil, 'busy' end
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) then return nil, 'busy' end
    if #(GetEntityCoords(ped) - vec3(barn.x, barn.y, barn.z)) > range then return nil, 'tooFar' end
    return ped
end

-- Serialize writes to each barn. Settings and resets take an exclusive lock
-- because they can change the meaning of a find while a database call yields.
function Requests.mutate(key, fn, ...)
    if exclusive or (key and mutations[key]) or (not key and inFlight > 0) then return false end
    if key then mutations[key] = true else exclusive = true end
    inFlight = inFlight + 1
    local result = table.pack(pcall(fn, ...))
    inFlight = inFlight - 1
    if key then mutations[key] = nil else exclusive = false end
    if not result[1] then
        print(('^1[bakery_barnfind] write failed: %s^7'):format(tostring(result[2])))
    end
    return table.unpack(result, 1, result.n)
end

AddEventHandler('playerDropped', function() buckets[source] = nil end)
